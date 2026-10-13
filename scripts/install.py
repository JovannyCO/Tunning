#!/usr/bin/env python3
"""Instala configuraciones con respaldo; --target-dir permite probar sin tocar HOME."""
import argparse
import datetime
import json
import os
from pathlib import Path
import platform
import shlex
import shutil
import subprocess
import tempfile

REPO = Path(__file__).resolve().parent.parent
START = '# === TUNNING TERMINAL SETUP - MATERIAL MD3 ==='
END = '## FIN TUNNING TERMINAL SETUP ##'


def run(*args, **kwargs):
    return subprocess.run(args, check=True, text=True, **kwargs)


def detect_profile():
    if os.environ.get('CLOUD_SHELL') or Path('/google/devshell/bashrc.google').exists():
        return 'cloudshell'
    release = platform.freedesktop_os_release()
    if release.get('ID') != 'ubuntu' or release.get('VERSION_ID') != '26.04':
        raise ValueError('Este instalador requiere Ubuntu 26.04 o Google Cloud Shell.')
    return 'wsl' if 'microsoft' in platform.release().lower() else 'ubuntu'


def saved_preferences(path):
    """Lee únicamente los valores generados; nunca ejecuta settings.sh."""
    if not path.exists():
        return {}
    allowed = {'TUNNING_PROFILE': {'wsl', 'ubuntu', 'cloudshell'},
               'TUNNING_PROMPT': {'bash', 'starship'},
               'TUNNING_EXTRAS': {'true', 'false'}}
    saved = {}
    for number, line in enumerate(path.read_text().splitlines(), 1):
        fields = shlex.split(line, comments=True)
        if not fields:
            continue
        if fields[0] == 'export':
            fields = fields[1:]
        if len(fields) != 1 or '=' not in fields[0]:
            raise ValueError(f'{path}:{number}: se esperaba una preferencia literal.')
        key, value = fields[0].split('=', 1)
        if key not in allowed or value not in allowed[key] or key in saved:
            raise ValueError(f'{path}:{number}: preferencia desconocida, inválida o repetida.')
        saved[key] = value
    return saved


def bashrc_contents(original, config_dir, profile):
    # Preflight: no eliminar nada si hay marcadores incompletos o anidados.
    outside = []
    inside = False
    old_boot = 'command -v devup &>/dev/null && [[ $- == *i* ]] && devup --boot'
    google = {'source /google/devshell/bashrc.google', '. /google/devshell/bashrc.google'}
    for line in original.splitlines(keepends=True):
        stripped = line.strip()
        if stripped == START:
            if inside:
                raise ValueError('.bashrc contiene bloques Tunning anidados; corrige los marcadores.')
            inside = True
        elif stripped == END:
            if not inside:
                raise ValueError('.bashrc contiene un cierre Tunning sin apertura.')
            inside = False
        elif not inside and stripped != old_boot and not (profile == 'cloudshell' and stripped in google):
            outside.append(line)
    if inside:
        raise ValueError('.bashrc contiene un bloque Tunning sin cierre; no se ha modificado.')
    block = [START]
    if profile == 'cloudshell':
        block.append('[ ! -r /google/devshell/bashrc.google ] || . /google/devshell/bashrc.google')
    block.extend([f'. {shlex.quote(str(config_dir / "bashrc_append.sh"))}', END])
    return ''.join(outside).rstrip('\n') + '\n\n' + '\n'.join(block) + '\n'


def gitconfig_contents(original, binary, profile):
    with tempfile.TemporaryDirectory(prefix='tunning-gitconfig-') as tmp:
        config = Path(tmp) / 'config'
        config.write_bytes(original)
        command = '!' + shlex.quote(str(binary))
        for alias in ('sync', 'syncPR', 'syncPRmerge'):
            run('git', 'config', '--file', str(config), f'alias.{alias}',
                command + f' --tunning-mode={alias}')
        current = subprocess.run(['git', 'config', '--file', str(config), '--get', 'tunning.syncSign'],
                                 capture_output=True, text=True)
        if current.returncode == 1:
            run('git', 'config', '--file', str(config), 'tunning.syncSign',
                'false' if profile == 'cloudshell' else 'true')
        elif current.returncode:
            raise ValueError('No se pudo leer la configuración Git existente.')
        return config.read_bytes()


def atomic_write(destination, contents, mode):
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=destination.parent, prefix='.tunning-', delete=False) as tmp:
        temporary = Path(tmp.name)
        tmp.write(contents)
    try:
        temporary.chmod(mode)
        temporary.replace(destination)
    finally:
        temporary.unlink(missing_ok=True)


def apply_changes(target, changes):
    stamp = datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f')
    backup = target / '.local/state/tunning/backups' / stamp
    backup.mkdir(parents=True, mode=0o700)
    manifest = []
    for path, _, _ in changes:
        relative = path.relative_to(target)
        exists = os.path.lexists(path)
        manifest.append({'path': str(relative), 'existed': exists})
        if exists:
            saved = backup / relative
            saved.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, saved, follow_symlinks=False)
    (backup / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    applied = []
    try:
        for destination, contents, mode in changes:
            atomic_write(destination, contents, mode)
            applied.append(destination)
    except BaseException:
        for destination in reversed(applied):
            saved = backup / destination.relative_to(target)
            if saved.is_symlink():
                destination.unlink()
                destination.symlink_to(os.readlink(saved))
            elif saved.exists():
                atomic_write(destination, saved.read_bytes(), saved.stat().st_mode & 0o777)
            else:
                destination.unlink(missing_ok=True)
        raise
    print(f'Respaldo: {backup}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--profile', choices=['auto', 'wsl', 'ubuntu', 'cloudshell'], default='auto')
    parser.add_argument('--prompt', choices=['bash', 'starship'])
    extra_flags = parser.add_mutually_exclusive_group()
    extra_flags.add_argument('--extras', dest='extras', action='store_true',
                             help='Instalar/activar eza y fastfetch además de Starship.')
    extra_flags.add_argument('--no-extras', dest='extras', action='store_false',
                             help='Desactivar extras; requiere el prompt Bash.')
    parser.set_defaults(extras=None)
    parser.add_argument('--no-packages', action='store_true', help='Solo instalar configuración y comandos.')
    parser.add_argument('--target-dir', type=Path, help='Destino alternativo para pruebas o preparación.')
    parser.add_argument('--dry-run', action='store_true', help='Mostrar cambios sin instalar ni escribir destinos.')
    args = parser.parse_args()
    detected = detect_profile()
    profile = detected if args.profile == 'auto' else args.profile
    if profile != detected and not (args.target_dir and args.no_packages):
        raise ValueError(f'Perfil solicitado: {profile}; entorno detectado: {detected}.')
    target = (args.target_dir or Path.home()).expanduser().absolute()
    config_dir = target / '.config/tunning'
    saved = saved_preferences(config_dir / 'settings.sh')
    prompt = args.prompt or saved.get('TUNNING_PROMPT') or ('starship' if profile == 'cloudshell' else 'bash')
    if prompt == 'starship' and args.extras is False:
        raise ValueError('Starship requiere extras. Para desactivarlos usa --prompt bash --no-extras.')
    extras = (args.extras if args.extras is not None else saved.get('TUNNING_EXTRAS') == 'true') or prompt == 'starship'
    if profile == 'cloudshell' and extras and args.target_dir and not args.no_packages:
        raise ValueError('Para preparar otro destino Cloud Shell usa --no-packages.')
    bashrc = target / '.bashrc'
    gitconfig = target / '.gitconfig'
    # Validar marcadores y Git antes de instalar paquetes o escribir configuración.
    rc_text = bashrc_contents(bashrc.read_text() if bashrc.exists() else '', config_dir, profile)
    git_text = gitconfig_contents(gitconfig.read_bytes() if gitconfig.exists() else b'',
                                  target / '.local/bin/git-sync', profile)
    settings = (f'export TUNNING_PROFILE={shlex.quote(profile)}\n'
                f'export TUNNING_PROMPT={shlex.quote(prompt)}\n'
                f'export TUNNING_EXTRAS={str(extras).lower()}\n')
    plans = {config_dir / 'settings.sh': (settings.encode(), 0o644)}
    for filename in ['bashrc_append.sh', 'prompt-bash.sh']:
        plans[config_dir / filename] = ((REPO / 'configs' / filename).read_bytes(), 0o644)
    for source, destination in [('devup.sh', 'devup'), ('git-sync.sh', 'git-sync')]:
        plans[target / '.local/bin' / destination] = ((REPO / 'scripts' / source).read_bytes(), 0o755)
    if extras:
        variant = '-cloudshell' if profile == 'cloudshell' else ''
        for source, destination in [(f'starship{variant}.toml', '.config/starship.toml'),
                                    (f'fastfetch{variant}.jsonc', '.config/fastfetch/config.jsonc')]:
            plans[target / destination] = ((REPO / 'configs' / source).read_bytes(), 0o644)
    # Publicar los puntos de entrada cuando sus archivos de destino ya existen.
    plans[gitconfig] = (git_text, 0o600)
    plans[bashrc] = (rc_text.encode(), 0o644)
    changes = [(path, data, mode) for path, (data, mode) in plans.items()
               if path.is_symlink() or not path.exists() or path.read_bytes() != data
               or path.stat().st_mode & 0o777 != mode]
    print(f'Entorno: {profile}; prompt: {prompt}; extras: {extras}; destino: {target}')
    for path, _, _ in changes:
        print(f'  Actualizar: {path}')
    if not args.no_packages:
        print('Paquetes: git, curl, ca-certificates, bash-completion, util-linux, gnupg'
              + (' y herramientas opcionales' if extras else ''))
    if args.dry_run:
        return
    if not args.no_packages:
        run('sudo', 'apt-get', 'update')
        run('sudo', 'apt-get', 'install', '-y', 'git', 'curl', 'ca-certificates', 'bash-completion', 'util-linux', 'gnupg')
        if extras:
            if profile == 'cloudshell':
                run('bash', str(REPO / 'scripts/install-cloudshell-extras.sh'))
            else:
                run('sudo', 'apt-get', 'install', '-y', 'starship', 'eza', 'fastfetch')
    if changes:
        apply_changes(target, changes)
    else:
        print('La configuración ya está actualizada.')
    print('Configuración completa. Abre una terminal nueva o ejecuta: source ~/.bashrc')
    if profile == 'wsl':
        print('Windows Terminal: importa el esquema y el perfil de configs/; consulta README.md.')


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        raise SystemExit(f'Error: {error}')
