#!/usr/bin/env bash
# Archivo autónomo: el instalador copia esta única implementación del comando.
set -euo pipefail
exec python3 - "$@" <<'PY'
import datetime
import os
from pathlib import Path
import posixpath
import pwd
import socket
import subprocess
import sys
from urllib.parse import urlsplit, urlunsplit


HELP = '''Uso: git sync ["mensaje"]
Valida e inicializa los submódulos recursivos en sus commits registrados.
De hijos a padres: agrega cambios, crea commits, integra mediante merge la rama
remota y production (si existe), y publica únicamente cada rama de trabajo.
Un HEAD separado necesita submodule.<nombre>.branch en el padre; branch=.
usa la rama del padre. No se elige una rama por defecto para HEAD separado.
Configuración por repositorio: tunning.syncSign (true), tunning.syncProduction
(true). Con syncSign=false se respeta commit.gpgsign. Se respetan los remotos
branch.<rama>.remote/pushRemote y remote.pushDefault; por defecto, origin.
Un fallo detiene sus padres. Antes del push se comprueba la disponibilidad
remota de las referencias hijas, también con --recurse-submodules=check.
'''
if sys.argv[1:2] in (['--help'], ['-h']):
    print(HELP, end='')
    sys.exit(0)

MESSAGE = ' '.join(sys.argv[1:]) or 'Cambios en la matrix'
ROOT = None
REPOS = {}
PUBLISHED = {}


class SyncError(Exception):
    pass


def label(path):
    return str(path.relative_to(ROOT)) if ROOT and path.is_relative_to(ROOT) else str(path)


def fail(path, reason):
    raise SyncError(f'[{label(path)}] {reason}')


def git(path, *args, stream=False, codes=(0,)):
    # Las rutas son argumentos literales, nunca código shell ni pathspecs mágicos.
    env = {**os.environ, 'GIT_LITERAL_PATHSPECS': '1'}
    result = subprocess.run(
        ['git', '-c', 'submodule.recurse=false', '-c', 'fetch.recurseSubmodules=false', *args],
        cwd=path, env=env, capture_output=not stream, text=True, errors='surrogateescape')
    if result.returncode not in codes:
        detail = (result.stderr or '').strip() if not stream else ''
        command = args[0]
        if command == '-c':
            command = args[next(i for i in range(0, len(args), 2) if args[i] != '-c')]
        fail(path, f'{command} falló (código {result.returncode}).' + (f'\n{detail}' if detail else ''))
    return result


def value(path, key, file=None):
    args = ['config'] + (['--file', str(file)] if file else [])
    result = git(path, *args, '--null', '--get-all', key, codes=(0, 1))
    values = result.stdout.rstrip('\0').split('\0') if result.returncode == 0 else []
    if file and len(set(values)) > 1:
        fail(path, f'Configuración ambigua: {key} en {file}.')
    # Git da prioridad al último valor, incluyendo las preferencias locales.
    return values[-1] if values else None


def boolean(path, key):
    result = git(path, 'config', '--type=bool', '--get', key, codes=(0, 1))
    return result.returncode == 1 or result.stdout.strip() == 'true'


def head(path):
    return git(path, 'rev-parse', '--verify', 'HEAD').stdout.strip()


def ancestor(path, older, newer):
    return git(path, 'merge-base', '--is-ancestor', older, newer, codes=(0, 1)).returncode == 0


def heads(path, remote, *patterns, tags=False):
    args = ['ls-remote', '--heads'] + (['--tags'] if tags else [])
    result = git(path, *args, '--', remote, *patterns)
    return {ref: oid for oid, ref in (row.split('\t', 1) for row in result.stdout.splitlines())}


def links(path, committed=False):
    result = git(path, *(['ls-tree', '-rz', 'HEAD'] if committed else ['ls-files', '--stage', '-z']))
    found = {}
    for entry in result.stdout.split('\0'):
        if not entry:
            continue
        metadata, name = entry.split('\t', 1)
        mode, kind, oid = metadata.split(' ', 2)
        if committed:
            if mode == '160000':
                found[name] = oid
        elif oid != '0':
            fail(path, f'Hay conflictos sin resolver en {name!r}.')
        elif mode == '160000':
            found[name] = kind
    return found


def module_contents(path):
    modules = path / '.gitmodules'
    if modules.is_symlink():
        fail(path, '.gitmodules no puede ser un enlace simbólico.')
    return modules.read_bytes() if modules.exists() else b''


def fingerprint(path):
    return links(path), module_contents(path)


def configured_branch(parent, name, child_path):
    key = f'submodule.{name}.branch'
    local = git(parent.path, 'config', '--local', '--null', '--get-all', key, codes=(0, 1))
    if local.returncode == 0 and len(set(local.stdout.rstrip('\0').split('\0'))) > 1:
        fail(child_path, f'Hay varias ramas locales configuradas en {key}.')
    try:
        branch = value(parent.path, key)
        if branch is None:
            branch = value(parent.path, key, '.gitmodules')
    except SyncError as error:
        fail(child_path, str(error))
    return parent.branch if branch == '.' else branch


def absolute_url(parent, url):
    if not url.startswith(('./', '../')):
        return url
    # Las URL relativas se resuelven respecto al repositorio remoto del padre.
    remote = 'origin' if parent.detached else parent.remote
    base = git(parent.path, 'remote', 'get-url', '--', remote).stdout.strip()
    parsed = urlsplit(base)
    if '://' in base:
        return urlunsplit(parsed._replace(path=posixpath.normpath(parsed.path + '/' + url)))
    if ':' in base and not base.startswith('/'):
        host, remote_path = base.split(':', 1)
        return host + ':' + posixpath.normpath(remote_path + '/' + url)
    return str((parent.path / base / url).resolve())


class Repo:
    def __init__(self, path):
        self.path = path
        self.created = []
        self.children = []

    def check_branch_available(self):
        worktree = git(self.path, 'for-each-ref', '--format=%(worktreepath)',
                       f'refs/heads/{self.branch}').stdout.strip()
        if worktree:
            fail(self.path, f'La rama configurada {self.branch!r} está activa en otro worktree: {worktree}.')

    def validate(self, parent=None, name=None):
        actual = Path(git(self.path, 'rev-parse', '--show-toplevel').stdout.removesuffix('\n')).resolve()
        if actual != self.path:
            fail(self.path, 'No es un checkout independiente del submódulo.')
        for state in ('MERGE_HEAD', 'CHERRY_PICK_HEAD', 'REVERT_HEAD', 'rebase-merge',
                      'rebase-apply', 'sequencer', 'BISECT_START', 'index.lock'):
            pending = git(self.path, 'rev-parse', '--git-path', state).stdout.removesuffix('\n')
            if (self.path / pending).exists():
                fail(self.path, f'Hay una operación Git pendiente ({state}); resuélvela primero.')
        current = git(self.path, 'symbolic-ref', '--quiet', '--short', 'HEAD', codes=(0, 1))
        self.detached = current.returncode == 1
        self.branch = configured_branch(parent, name, self.path) if self.detached and parent else current.stdout.strip()
        if not self.branch:
            fail(self.path, 'HEAD está separado y no hay una rama configurada inequívoca en el padre.')
        git(self.path, 'check-ref-format', f'refs/heads/{self.branch}')
        if self.branch == 'HEAD':
            fail(self.path, 'HEAD no es un nombre de rama válido.')
        self.sign = ['-S'] if boolean(self.path, 'tunning.syncSign') else []
        self.production = boolean(self.path, 'tunning.syncProduction')
        self.remote = value(self.path, f'branch.{self.branch}.remote') or 'origin'
        self.push_remote = (value(self.path, f'branch.{self.branch}.pushRemote') or
                            value(self.path, 'remote.pushDefault') or self.remote)
        merge_key = f'branch.{self.branch}.merge'
        merges = git(self.path, 'config', '--null', '--get-all', merge_key, codes=(0, 1))
        if merges.returncode == 0 and len(set(merges.stdout.rstrip('\0').split('\0'))) > 1:
            fail(self.path, f'Hay varios upstreams en {merge_key}; selecciona uno antes de sincronizar.')
        self.tracked = value(self.path, merge_key) or f'refs/heads/{self.branch}'
        if not self.tracked.startswith('refs/heads/'):
            fail(self.path, f'Upstream no publicable: {self.tracked!r}.')
        git(self.path, 'check-ref-format', self.tracked)
        for remote in {self.remote, self.push_remote}:
            if remote == '.':
                fail(self.path, 'El remoto local "." no permite verificar una publicación.')
            git(self.path, 'remote', 'get-url', '--', remote)
        urls = git(self.path, 'remote', 'get-url', '--push', '--all', '--', self.push_remote).stdout.splitlines()
        if len(urls) != 1:
            fail(self.path, f'El remoto {self.push_remote!r} necesita una única URL de publicación.')
        self.push_url = urls[0]
        self.remote_heads = heads(self.path, self.remote)
        heads(self.path, self.push_url)
        self.branch_tip = None
        if self.detached:
            self.check_branch_available()
            tip = git(self.path, 'rev-parse', '--verify', f'refs/heads/{self.branch}', codes=(0, 128))
            if tip.returncode == 0:
                self.branch_tip = tip.stdout.strip()
                self.common_history(self.branch_tip)
        links(self.path)  # Valida conflictos del índice antes de crear commits.

    def common_history(self, oid):
        if git(self.path, 'merge-base', 'HEAD', oid, codes=(0, 1)).returncode == 1:
            fail(self.path, f'El commit {oid} y HEAD no tienen historia común; se conserva el checkout.')

    def ensure_commit(self, oid, url):
        if git(self.path, 'cat-file', '-e', f'{oid}^{{commit}}', codes=(0, 1, 128)).returncode:
            git(self.path, 'fetch', '--no-recurse-submodules', '--no-tags', '--', url, oid, stream=True)
        self.common_history(oid)


def prepare(path, parent=None, name=None):
    repo = REPOS.setdefault(path, Repo(path))
    repo.validate(parent, name)
    repo.children = discover(repo)
    return repo


def discover(repo):
    repo.modules = module_contents(repo.path)
    registered = links(repo.path)
    if not registered:
        return []
    if not (repo.path / '.gitmodules').is_file() or (repo.path / '.gitmodules').is_symlink():
        fail(repo.path, 'Hay gitlinks sin un archivo .gitmodules válido.')
    entries = git(repo.path, 'config', '--file', '.gitmodules', '--null', '--get-regexp',
                  r'^submodule\..*\.path$', codes=(0, 1))
    names = {}
    for entry in entries.stdout.rstrip('\0').split('\0') if entries.stdout else []:
        key, path = entry.split('\n', 1)
        if path in names:
            fail(repo.path, f'Ruta de submódulo duplicada: {path!r}.')
        names[path] = key[len('submodule.'):-len('.path')]
    children = []
    for path, oid in sorted(registered.items()):
        child_path = (repo.path / path).resolve()
        if not child_path.is_relative_to(repo.path) or child_path == repo.path:
            fail(repo.path, f'Ruta de submódulo fuera del repositorio: {path!r}.')
        if path not in names:
            fail(child_path, 'Falta el registro del submódulo en .gitmodules.')
        name = names[path]
        declared = value(repo.path, f'submodule.{name}.url', '.gitmodules')
        if not declared:
            fail(child_path, 'Falta la URL del submódulo en .gitmodules.')
        if not (child_path / '.git').exists():
            branch = configured_branch(repo, name, child_path)
            if not branch:
                fail(child_path, 'Submódulo sin inicializar y sin rama configurada para resolver HEAD separado.')
            valid = git(repo.path, 'check-ref-format', f'refs/heads/{branch}', codes=(0, 1))
            if valid.returncode or branch == 'HEAD':
                fail(child_path, f'Rama configurada inválida: {branch!r}.')
            print(f'=> [{label(child_path)}] Inicializando en el commit registrado {oid[:12]}...', flush=True)
            try:
                git(repo.path, 'submodule', 'update', '--init', '--checkout', '--', path, stream=True)
            except SyncError as error:
                fail(child_path, f'No se pudo inicializar el submódulo. {error}')
        if value(repo.path, f'submodule.{name}.url') is None:
            git(repo.path, 'submodule', 'init', '--', path, stream=True)
        effective = value(repo.path, f'submodule.{name}.url')
        urls = list(dict.fromkeys([absolute_url(repo, declared), effective]))
        child = prepare(child_path, repo, name)
        child.ensure_commit(oid, effective)
        for url in urls:
            heads(child.path, url)
        children.append((path, name, oid, urls, child))
    return children


def commit_changes(repo):
    print(f'=> [{label(repo.path)}] Agregando cambios...', flush=True)
    overrides = [arg for _, name, _, _, _ in repo.children for arg in ('-c', f'submodule.{name}.ignore=none')]
    git(repo.path, *overrides, 'add', '-A', '--', stream=True)
    changed = git(repo.path, 'diff', '--cached', '--quiet', '--ignore-submodules=none', codes=(0, 1))
    if changed.returncode == 0:
        print(f'=> [{label(repo.path)}] No hay cambios para crear un commit.', flush=True)
        return
    months = ('enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto',
              'septiembre', 'octubre', 'noviembre', 'diciembre')
    now = datetime.datetime.now()
    host = socket.gethostname()
    if os.environ.get('TUNNING_PROFILE') == 'cloudshell' or os.environ.get('CLOUD_SHELL') or Path('/google/devshell/bashrc.google').exists():
        host = 'CSE'
    message = f'{pwd.getpwuid(os.geteuid()).pw_name}@{host} {now.day}{months[now.month-1]}{now:%H:%M} - {MESSAGE}'
    print(f'=> [{label(repo.path)}] Creando commit: {message}', flush=True)
    git(repo.path, 'commit', *repo.sign, '-m', message, stream=True)
    repo.created.append(head(repo.path))


def integrate(repo, args, description):
    before = fingerprint(repo.path)
    previous = head(repo.path)
    print(f'=> [{label(repo.path)}] Integrando {description}...', flush=True)
    git(repo.path, *args, stream=True)
    current = head(repo.path)
    if current != previous:
        target = git(repo.path, 'rev-parse', 'FETCH_HEAD').stdout.strip() if args[0] == 'pull' else args[-1]
        parents = git(repo.path, 'log', '-1', '--format=%P').stdout.split()
        if current != target and len(parents) > 1 and parents[0] == previous:
            repo.created.append(current)
    if fingerprint(repo.path) != before:
        for removed in set(before[0]) - set(links(repo.path)):
            if (repo.path / removed).exists():
                fail(repo.path, f'El merge retiró {removed!r}; su directorio se conserva. Resuelve esa eliminación antes del push.')
        # Un merge puede añadir módulos o cambiar gitlinks/URL/ramas. Se valida
        # nuevamente el árbol e integra el commit registrado antes de restage.
        repo.children = discover(repo)
        for _, _, oid, _, child in repo.children:
            sync(child, oid)
        commit_changes(repo)


def attach(repo):
    if not repo.detached:
        actual = git(repo.path, 'symbolic-ref', '--quiet', '--short', 'HEAD').stdout.strip()
        if actual != repo.branch:
            fail(repo.path, 'La rama activa cambió durante la sincronización.')
        return
    repo.check_branch_available()
    if repo.branch_tip:
        if not ancestor(repo.path, repo.branch_tip, head(repo.path)):
            fail(repo.path, 'La rama configurada no está integrada; no se mueve su referencia.')
        # Sólo avance rápido con comparación del valor anterior. HEAD, índice
        # y archivos se conservan intactos, sin sustituir ninguna historia.
        git(repo.path, 'update-ref', f'refs/heads/{repo.branch}', head(repo.path), repo.branch_tip)
        git(repo.path, 'switch', '--no-recurse-submodules', repo.branch, stream=True)
    else:
        git(repo.path, 'switch', '--no-recurse-submodules', '-c', repo.branch, stream=True)
    repo.detached = False


def verify_reference(child, oid, urls):
    for url in urls:
        advertised = heads(child.path, url, tags=True)
        if oid in advertised.values():
            continue
        reachable = False
        for tip in set(advertised.values()):
            if git(child.path, 'cat-file', '-e', tip, codes=(0, 1, 128)).returncode:
                git(child.path, 'fetch', '--no-recurse-submodules', '--no-tags', '--', url, tip, stream=True)
            commit = git(child.path, 'rev-parse', '--verify', f'{tip}^{{commit}}', codes=(0, 128))
            if commit.returncode == 0 and ancestor(child.path, oid, commit.stdout.strip()):
                reachable = True
                break
        if not reachable:
            fail(child.path, f'La referencia {oid} no es alcanzable en el remoto registrado {url!r}; no se publica su padre.')


def clean(repo):
    status = git(repo.path, 'status', '--porcelain=v1', '--untracked-files=all', '--ignore-submodules=none').stdout
    if status:
        fail(repo.path, f'Quedan cambios después de sincronizar.\n{status}')


def sync(repo, recorded=None):
    for _, _, oid, _, child in repo.children:
        sync(child, oid)
    commit_changes(repo)
    head(repo.path)
    if recorded and not ancestor(repo.path, recorded, head(repo.path)):
        integrate(repo, ['merge', '--no-edit', '--no-autostash', *repo.sign, recorded], f'commit registrado {recorded[:12]}')
    if repo.branch_tip and not ancestor(repo.path, repo.branch_tip, head(repo.path)):
        integrate(repo, ['merge', '--no-edit', '--no-autostash', *repo.sign, repo.branch_tip], f'rama configurada {repo.branch}')
    if repo.tracked in repo.remote_heads:
        integrate(repo, ['pull', '--no-rebase', '--no-edit', '--no-autostash', '--no-recurse-submodules',
                         *repo.sign, '--', repo.remote, repo.tracked], f'{repo.remote}/{repo.tracked[len("refs/heads/"):]}')
    if repo.production and 'refs/heads/production' in repo.remote_heads and repo.branch != 'production':
        integrate(repo, ['pull', '--no-rebase', '--no-edit', '--no-autostash', '--no-recurse-submodules',
                         *repo.sign, '--', repo.remote, 'production'], f'{repo.remote}/production')
    # Los hooks también pueden cambiar .gitmodules durante un commit. La URL
    # que se va a publicar debe ser la misma que se haya validado, sin cachés.
    if module_contents(repo.path) != repo.modules:
        repo.children = discover(repo)
        for _, _, oid, _, child in repo.children:
            sync(child, oid)
        commit_changes(repo)
        if module_contents(repo.path) != repo.modules:
            fail(repo.path, '.gitmodules volvió a cambiar durante la confirmación; revisa los hooks.')
    attach(repo)
    clean(repo)
    committed = links(repo.path, committed=True)
    if set(committed) != {path for path, _, _, _, _ in repo.children}:
        fail(repo.path, 'Los submódulos cambiaron después de validar el árbol; se detiene el push.')
    for path, _, _, urls, child in repo.children:
        oid = committed.get(path)
        if oid != head(child.path) or PUBLISHED.get(child.path, (None,))[0] != oid:
            fail(child.path, 'La referencia cambió después de publicar el hijo; se detiene su padre.')
        clean(child)
        verify_reference(child, oid, urls)
    print(f'=> [{label(repo.path)}] Publicando {repo.push_remote}/{repo.branch}...', flush=True)
    upstream = [] if value(repo.path, f'branch.{repo.branch}.remote') and value(repo.path, f'branch.{repo.branch}.merge') else ['--set-upstream']
    expected = head(repo.path)
    git(repo.path, 'push', '--recurse-submodules=check', *upstream, '--', repo.push_remote,
        f'HEAD:refs/heads/{repo.branch}', stream=True)
    actual = heads(repo.path, repo.push_url, f'refs/heads/{repo.branch}').get(f'refs/heads/{repo.branch}')
    if actual != expected or head(repo.path) != expected:
        fail(repo.path, 'El HEAD local y la rama publicada no coinciden después del push.')
    clean(repo)
    PUBLISHED[repo.path] = (expected, repo.push_remote, repo.branch)


def summary(title):
    print(title, flush=True)
    for path, (oid, remote, branch) in PUBLISHED.items():
        created = ', '.join(commit[:12] for commit in REPOS[path].created) or 'ninguno'
        print(f'  [{label(path)}] {remote}/{branch} -> {oid[:12]}; commits creados: {created}', flush=True)


try:
    ROOT = Path(git(Path.cwd(), 'rev-parse', '--show-toplevel').stdout.removesuffix('\n')).resolve()
    print('=> Validando repositorios y submódulos antes de confirmar cambios...', flush=True)
    root = prepare(ROOT)
    sync(root)
    for path, (oid, _, _) in PUBLISHED.items():
        if head(path) != oid:
            fail(path, 'HEAD cambió después de la publicación.')
        clean(REPOS[path])
    summary(f'Sincronizados {len(PUBLISHED)} repositorios:')
except (SyncError, OSError) as error:
    print(f'git sync: {error}', file=sys.stderr, flush=True)
    if PUBLISHED:
        summary('Publicaciones completadas antes del error (sincronización incompleta):')
    sys.exit(1)
except KeyboardInterrupt:
    print('git sync: Interrumpido; los padres pendientes no se publicaron.', file=sys.stderr)
    sys.exit(130)
PY
