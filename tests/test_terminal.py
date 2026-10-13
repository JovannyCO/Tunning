"""Pruebas sin instalaciones de paquetes ni acceso a remotos externos."""
import os
from pathlib import Path
import pty
import shlex
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parent.parent


def execute(argv, cwd=None, env=None, check=True):
    result = subprocess.run([str(a) for a in argv], cwd=cwd, env=env, capture_output=True,
                            text=True, timeout=30)
    if check and result.returncode:
        raise AssertionError(f'{argv}\n{result.stdout}\n{result.stderr}')
    return result


class Fixture(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='tunning-test-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.env = {'PATH': '/usr/bin:/bin', 'LC_ALL': 'C.UTF-8',
                    'GIT_CONFIG_NOSYSTEM': '1', 'GIT_CONFIG_GLOBAL': str(self.root / 'global.gitconfig'),
                    'GIT_TERMINAL_PROMPT': '0'}

    def script(self, path, contents):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(contents)
        path.chmod(0o755)
        return path


class GitFixture(Fixture):
    def setUp(self):
        super().setUp()
        self.remote = self.root / 'origin.git'
        self.work = self.root / 'work'
        execute(['git', 'init', '--bare', '-q', self.remote], env=self.env)
        execute(['git', 'init', '-q', '-b', 'main', self.work], env=self.env)
        for key, value in [('user.name', 'Audit'), ('user.email', 'audit@example.invalid'),
                           ('commit.gpgsign', 'false'), ('tunning.syncSign', 'false'),
                           ('alias.sync', '!bash ' + shlex.quote(str(REPO / 'scripts/git-sync.sh')) + ' --tunning-mode=sync')]:
            self.git('config', key, value)
        (self.work / 'file.txt').write_text('base\n')
        self.git('add', '.')
        self.git('commit', '-qm', 'base')
        self.git('remote', 'add', 'origin', str(self.remote))
        self.git('push', '-qu', 'origin', 'main')
        self.initial = self.remote_head()

    def git(self, *args, check=True, cwd=None):
        return execute(['git', *args], cwd=cwd or self.work, env=self.env, check=check)

    def remote_head(self, branch='main'):
        return self.git('--git-dir', str(self.remote), 'rev-parse', f'refs/heads/{branch}').stdout.strip()

    def modify(self):
        (self.work / 'file.txt').write_text('local change\n')

    def peer(self, branch='main', filename='file.txt'):
        peer = self.root / 'peer'
        execute(['git', 'clone', '-q', '-b', 'main', self.remote, peer], env=self.env)
        for key, value in [('user.name', 'Peer'), ('user.email', 'peer@example.invalid'), ('commit.gpgsign', 'false')]:
            self.git('config', key, value, cwd=peer)
        if branch != 'main':
            self.git('checkout', '-qb', branch, cwd=peer)
        (peer / filename).write_text('peer change\n')
        self.git('add', '.', cwd=peer)
        self.git('commit', '-qm', 'peer', cwd=peer)
        self.git('push', '-q', 'origin', branch, cwd=peer)
        return peer


class GitSyncTests(GitFixture):
    def test_success_and_literal_message(self):
        self.modify()
        message = 'literal $(touch NEVER) `touch NEVER` con espacios'
        self.git('sync', message)
        self.assertIn(message, self.git('log', '-1', '--format=%s').stdout)
        self.assertNotEqual(self.initial, self.remote_head())
        self.assertFalse((self.work / 'NEVER').exists())
        self.assertFalse(self.git('status', '--porcelain').stdout)

    def test_internal_mode_text_remains_literal_message_in_sync(self):
        self.modify()
        self.git('sync', '--tunning-mode=syncPRmerge')
        self.assertIn('--tunning-mode=syncPRmerge', self.git('log', '-1', '--format=%s').stdout)
        self.assertEqual(self.git('rev-parse', 'HEAD').stdout.strip(), self.remote_head())

    def test_rejected_commit_stops_before_push(self):
        self.modify()
        self.script(self.work / '.git/hooks/pre-commit', '#!/bin/sh\nexit 1\n')
        result = self.git('sync', check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('Publicando', result.stdout)
        self.assertEqual(self.initial, self.remote_head())

    def test_signing_failure_stops_before_push(self):
        self.modify()
        signer = self.script(self.root / 'reject-signature', '#!/bin/sh\necho signer-rejected >&2\nexit 1\n')
        self.git('config', 'gpg.program', str(signer))
        self.git('config', 'tunning.syncSign', 'true')
        result = self.git('sync', check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('signer-rejected', result.stderr)
        self.assertNotIn('Publicando', result.stdout)
        self.assertEqual(self.initial, self.remote_head())

    def test_add_failure_stops(self):
        self.modify()
        (self.work / '.git/index.lock').touch()
        result = self.git('sync', check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('Creando commit', result.stdout)
        self.assertNotIn('Publicando', result.stdout)

    def test_current_branch_conflict_stops_before_push(self):
        self.peer()
        upstream = self.remote_head()
        self.modify()
        result = self.git('sync', check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('Publicando', result.stdout)
        self.assertEqual(upstream, self.remote_head())

    def test_production_conflict_stops_before_push(self):
        self.peer('production')
        self.modify()
        result = self.git('sync', check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('origin/production', result.stdout)
        self.assertNotIn('Publicando', result.stdout)
        self.assertEqual(self.initial, self.remote_head())

    def test_merges_production_without_rewriting_commits(self):
        self.peer('production', 'production.txt')
        self.modify()
        self.git('sync')
        self.assertTrue((self.work / 'production.txt').exists())
        self.assertEqual(self.remote_head(), self.git('rev-parse', 'HEAD').stdout.strip())
        self.assertEqual(2, len(self.git('log', '-1', '--format=%P').stdout.split()))

    def test_clean_tree_still_pushes_existing_commits(self):
        self.modify()
        self.git('commit', '-qam', 'pending')
        self.git('sync')
        self.assertEqual(self.remote_head(), self.git('rev-parse', 'HEAD').stdout.strip())

    def test_new_branch_is_published(self):
        self.git('checkout', '-qb', 'new-branch')
        self.modify()
        self.git('sync')
        self.assertEqual(self.remote_head('new-branch'), self.git('rev-parse', 'HEAD').stdout.strip())

    def test_detached_head_is_rejected_before_staging(self):
        self.git('checkout', '--detach', '-q')
        self.modify()
        result = self.git('sync', check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('Agregando', result.stdout)

    def test_remote_failure_stops_before_push(self):
        self.git('remote', 'set-url', 'origin', str(self.root / 'missing.git'))
        result = self.git('sync', check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('Publicando', result.stdout)


class InstallTests(Fixture):
    def install(self, target, *args, check=True):
        return execute(['bash', REPO / 'setup.sh', '--no-packages', '--target-dir', target, *args],
                       cwd=self.root, env=self.env, check=check)

    def test_reinstall_preserves_settings_and_is_idempotent(self):
        target = self.root / "usuario con ' espacios"
        target.mkdir()
        (target / '.bashrc').write_text('export USER_BEFORE=1\nexport USER_AFTER=1\n')
        (target / '.gitconfig').write_text('[user]\n\tname = Person\n\temail = example@example.invalid\n[commit]\n\tgpgsign = true\n')
        self.install(target)
        first = {str(p.relative_to(target)): p.read_bytes() for p in target.rglob('*') if p.is_file()}
        self.install(target)
        second = {str(p.relative_to(target)): p.read_bytes() for p in target.rglob('*') if p.is_file()}
        self.assertEqual(first, second)
        text = (target / '.bashrc').read_text()
        self.assertEqual(text.count('# === TUNNING TERMINAL SETUP'), 1)
        self.assertIn('export USER_BEFORE=1', text)
        self.assertIn('export USER_AFTER=1', text)
        config = target / '.gitconfig'
        self.assertEqual(execute(['git', 'config', '--file', config, 'user.name']).stdout.strip(), 'Person')
        self.assertEqual(execute(['git', 'config', '--file', config, 'commit.gpgsign']).stdout.strip(), 'true')
        env = {**self.env, 'GIT_CONFIG_GLOBAL': str(config)}
        self.assertIn('Uso: git sync', execute(['git', 'sync', '-h'], cwd=self.root, env=env).stdout)
        for mode in ('syncPR', 'syncPRmerge'):
            self.assertIn(mode, execute(['git', mode, '--help'], cwd=self.root, env=env).stdout)
            alias = execute(['git', 'config', '--file', config, 'alias.' + mode]).stdout.strip()
            self.assertTrue(alias.endswith('--tunning-mode=' + mode))

    def test_incomplete_marker_preserves_entire_target(self):
        target = self.root / 'target'
        target.mkdir()
        text = 'keep\n# === TUNNING TERMINAL SETUP - MATERIAL MD3 ===\nkeep too\n'
        (target / '.bashrc').write_text(text)
        result = self.install(target, check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((target / '.bashrc').read_text(), text)
        self.assertEqual([p.name for p in target.iterdir()], ['.bashrc'])

    def test_replaces_devup_symlink_without_writing_its_target(self):
        target = self.root / 'target'
        old = self.script(self.root / 'other-checkout/devup.sh', '#!/bin/sh\necho original\n')
        original = old.read_bytes()
        binary = target / '.local/bin/devup'
        binary.parent.mkdir(parents=True)
        binary.symlink_to(old)
        self.install(target)
        self.assertFalse(binary.is_symlink())
        self.assertEqual(original, old.read_bytes())
        backups = list((target / '.local/state/tunning/backups').glob('*/.local/bin/devup'))
        self.assertEqual(len(backups), 1)
        self.assertTrue(backups[0].is_symlink())

    def test_dry_run_writes_no_destination(self):
        target = self.root / 'target'
        self.install(target, '--dry-run')
        self.assertFalse(target.exists())

    def test_update_replaces_independent_sync_copy_and_preserves_preferences(self):
        target = self.root / 'target'
        self.install(target)
        binary = target / '.local/bin/git-sync'
        old = b'#!/bin/sh\necho old-sync\n'
        binary.write_bytes(old)
        config = target / '.gitconfig'
        for key in ('tunning.syncSign', 'tunning.syncProduction'):
            execute(['git', 'config', '--file', config, key, 'false'], env=self.env)
        self.install(target)
        self.assertEqual(binary.read_bytes(), (REPO / 'scripts/git-sync.sh').read_bytes())
        self.assertFalse(binary.is_symlink())
        backups = list((target / '.local/state/tunning/backups').glob('*/.local/bin/git-sync'))
        self.assertEqual([p.read_bytes() for p in backups], [old])
        for key in ('tunning.syncSign', 'tunning.syncProduction'):
            self.assertEqual(execute(['git', 'config', '--file', config, key], env=self.env).stdout.strip(), 'false')

    def test_cloudshell_retains_variants_and_google_before_tunning(self):
        target = self.root / 'cloud'
        target.mkdir()
        (target / '.bashrc').write_text('source /google/devshell/bashrc.google\n')
        self.install(target, '--profile', 'cloudshell', '--prompt', 'starship', '--extras')
        text = (target / '.bashrc').read_text()
        self.assertLess(text.index('/google/devshell/bashrc.google'), text.index('/bashrc_append.sh'))
        self.assertEqual((target / '.config/starship.toml').read_bytes(),
                         (REPO / 'configs/starship-cloudshell.toml').read_bytes())
        self.assertEqual((target / '.config/fastfetch/config.jsonc').read_bytes(),
                         (REPO / 'configs/fastfetch-cloudshell.jsonc').read_bytes())

    def test_reinstall_retains_selected_prompt_and_extras(self):
        for prompt in ('bash', 'starship'):
            with self.subTest(prompt=prompt):
                target = self.root / prompt
                self.install(target, '--prompt', prompt, '--extras')
                first = {str(p.relative_to(target)): p.read_bytes() for p in target.rglob('*') if p.is_file()}
                self.install(target)
                second = {str(p.relative_to(target)): p.read_bytes() for p in target.rglob('*') if p.is_file()}
                self.assertEqual(first, second)
                settings = (target / '.config/tunning/settings.sh').read_text()
                self.assertIn(f'TUNNING_PROMPT={prompt}', settings)
                self.assertIn('TUNNING_EXTRAS=true', settings)

    def test_explicitly_disable_extras_and_retain_choice(self):
        target = self.root / 'target'
        self.install(target, '--prompt', 'starship')
        self.install(target, '--prompt', 'bash', '--no-extras')
        self.install(target)
        settings = (target / '.config/tunning/settings.sh').read_text()
        self.assertIn('TUNNING_PROMPT=bash', settings)
        self.assertIn('TUNNING_EXTRAS=false', settings)

    def test_cloudshell_wrapper_retains_bash_choice(self):
        target = self.root / 'cloud'
        args = ['bash', REPO / 'setup-cloudshell.sh', '--no-packages', '--target-dir', target]
        execute([*args, '--prompt', 'bash', '--no-extras'], env=self.env)
        execute(args, env=self.env)
        settings = (target / '.config/tunning/settings.sh').read_text()
        self.assertIn('TUNNING_PROFILE=cloudshell', settings)
        self.assertIn('TUNNING_PROMPT=bash', settings)
        self.assertIn('TUNNING_EXTRAS=false', settings)

    def test_invalid_preferences_stop_without_execution_or_writes(self):
        target = self.root / 'target'
        self.install(target)
        preferences = target / '.config/tunning/settings.sh'
        preferences.write_text('export TUNNING_PROMPT=$(touch SENTINEL)\n')
        before = {str(p.relative_to(target)): p.read_bytes() for p in target.rglob('*') if p.is_file()}
        result = self.install(target, check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('settings.sh:1:', result.stderr)
        self.assertFalse((self.root / 'SENTINEL').exists())
        after = {str(p.relative_to(target)): p.read_bytes() for p in target.rglob('*') if p.is_file()}
        self.assertEqual(before, after)

    def test_starship_without_extras_stops_before_install(self):
        target = self.root / 'target'
        result = self.install(target, '--prompt', 'starship', '--no-extras', check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('--prompt bash --no-extras', result.stderr)
        self.assertFalse(target.exists())


class DevupTests(Fixture):
    def setUp(self):
        super().setUp()
        self.log = self.root / 'calls'
        mockbin = self.root / 'bin'
        for name in ['npm', 'codex', 'claude', 'sudo']:
            self.script(mockbin / name, '#!/bin/sh\nprintf "%s %s\\n" "${0##*/}" "$*" >> "$TUNNING_TEST_LOG"\n'
                        'if [ "${0##*/}" = "${TUNNING_TEST_FAIL:-}" ]; then exit 1; fi\n')
        self.script(mockbin / 'timeout', '#!/bin/sh\nexit 0\n')
        self.cache = self.root / 'cache'
        self.env.update(PATH=f'{mockbin}:/usr/bin:/bin', XDG_CACHE_HOME=str(self.cache),
                        TUNNING_TEST_LOG=str(self.log))

    def devup(self, *args, check=True):
        return execute(['bash', REPO / 'scripts/devup.sh', *args], env=self.env, check=check)

    def test_light_updates_all_clis_without_apt(self):
        self.devup('-l')
        log = self.log.read_text()
        self.assertIn('npm install -g firebase-tools@latest', log)
        self.assertIn('codex update', log)
        self.assertIn('claude update', log)
        self.assertNotIn('sudo', log)
        self.assertFalse((self.cache / 'devup/last-update').exists())

    def test_failure_is_reported_after_remaining_steps(self):
        self.env['TUNNING_TEST_FAIL'] = 'npm'
        result = self.devup('-l', check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('claude update', self.log.read_text())
        self.assertIn('Fallaron', result.stdout)

    def test_full_update_records_success(self):
        self.devup('-y')
        self.assertIn('sudo apt autoremove -y', self.log.read_text())
        self.assertTrue((self.cache / 'devup/last-update').exists())

    def test_help_and_noninteractive_boot_have_no_side_effects(self):
        self.devup('--help')
        self.devup('--boot')
        self.assertFalse(self.cache.exists())
        self.assertFalse(self.log.exists())

    def test_boot_prompts_once(self):
        for _ in range(2):
            master, slave = pty.openpty()
            try:
                process = subprocess.Popen(['bash', str(REPO / 'scripts/devup.sh'), '--boot'],
                                           stdin=slave, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                           env=self.env, text=True)
                os.write(master, b'n\n')
                stdout, stderr = process.communicate(timeout=5)
                self.assertEqual(process.returncode, 0, stderr)
                if _ == 0:
                    self.assertIn('Actualizar entorno', stdout)
                else:
                    self.assertNotIn('Actualizar entorno', stdout)
            finally:
                os.close(master)
                os.close(slave)
        self.assertEqual(len(list((self.cache / 'devup').glob('boot-*'))), 1)
        self.assertFalse(self.log.exists())


class PromptTests(Fixture):
    def test_cloudshell_bash_fallback_uses_no_private_font_glyphs(self):
        env = {**self.env, 'TERM': 'xterm-256color', 'USER': 'tester', 'COLUMNS': '120',
               'TUNNING_PROFILE': 'cloudshell'}
        source = shlex.quote(str(REPO / 'configs/prompt-bash.sh'))
        command = f'source {source}; false; __build_ps1; printf "%s" "${{PS1@P}}"'
        result = execute(['bash', '--noprofile', '--norc', '-c', command], env=env, cwd=self.root)
        self.assertIn('tester@CSE', result.stdout)
        self.assertIn('2;188;249', result.stdout)
        self.assertIn('207;102;121m\x02❯', result.stdout)
        self.assertFalse(any(0xE000 <= ord(c) <= 0xF8FF or 0xF0000 <= ord(c) <= 0x10FFFD
                             for c in result.stdout))

    def test_prompt_contains_current_palette_and_success_error_colors(self):
        env = {**self.env, 'TERM': 'xterm-256color', 'USER': 'tester', 'COLUMNS': '120'}
        source = shlex.quote(str(REPO / 'configs/prompt-bash.sh'))
        for status, color in [('true', '105;240;174'), ('false', '207;102;121')]:
            command = f'source {source}; {status}; __build_ps1; printf "%s" "${{PS1@P}}"'
            text = execute(['bash', '--noprofile', '--norc', '-c', command], env=env, cwd=self.root).stdout
            self.assertIn('255;109;0', text)
            self.assertIn('tester@', text)
            self.assertIn(str(self.root), text)
            self.assertIn(color + 'm\x02❯', text)
            self.assertIn('\n', text)

    def test_directory_names_are_not_evaluated_as_shell_code(self):
        directory = self.root / 'literal $(touch SENTINEL)'
        directory.mkdir()
        source = shlex.quote(str(REPO / 'configs/prompt-bash.sh'))
        env = {**self.env, 'TERM': 'xterm-256color', 'USER': 'tester', 'COLUMNS': '120'}
        command = f'source {source}; __build_ps1; printf "%s" "${{PS1@P}}"'
        result = execute(['bash', '--noprofile', '--norc', '-c', command], env=env, cwd=directory)
        self.assertIn('$(touch SENTINEL)', result.stdout)
        self.assertFalse((directory / 'SENTINEL').exists())

    def test_startup_preserves_timezone_and_terminal_and_path_is_idempotent(self):
        source = shlex.quote(str(REPO / 'configs/bashrc_append.sh'))
        env = {**os.environ, 'TZ': 'America/New_York', 'TERM': 'screen-256color',
               'TUNNING_DEVUP_BOOT': '0', 'TUNNING_PROMPT': 'bash', 'TUNNING_PROFILE': 'wsl',
               'NVM_DIR': str(self.root / 'no-nvm')}
        command = (f'source {source}; first=$PATH; source {source}; '
                   '[[ $first == "$PATH" ]] || exit 1; '
                   'printf "AUDIT:%s:%s:%s\\n" "$TZ" "$TERM" "$PROMPT_COMMAND"; '
                   'bind -q history-search-backward; bind -q menu-complete')
        result = execute(['bash', '--noprofile', '--norc', '-ic', command], env=env, cwd=self.root)
        self.assertIn('AUDIT:America/New_York:screen-256color:__build_ps1', result.stdout)


if __name__ == '__main__':
    unittest.main(verbosity=2)
