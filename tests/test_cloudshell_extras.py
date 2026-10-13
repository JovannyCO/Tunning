"""Archivos locales con curl simulado: nunca instala en el HOME real ni usa red."""
import hashlib
import io
import re
import tarfile

from test_terminal import Fixture, REPO, execute


class CloudExtrasTests(Fixture):
    def setUp(self):
        super().setUp()
        self.target = self.root / "usuario con ' espacios"
        self.target.mkdir()
        self.mockbin = self.root / 'bin'
        self.log = self.root / 'downloads'
        source = (REPO / 'scripts/install-cloudshell-extras.sh').read_text()
        members = ['starship', './eza', 'fastfetch-linux-amd64/usr/bin/fastfetch']
        checksums = re.findall(r'\b[0-9a-f]{64}\b', source)
        self.assertEqual(len(checksums), 3)
        for tool, member, checksum in zip(('starship', 'eza', 'fastfetch'), members, checksums):
            archive = self.root / f'{tool}.tar.gz'
            data = f'#!/bin/sh\nprintf "%s\\n" "fixture {tool}"\n'.encode()
            with tarfile.open(archive, 'w:gz') as tar:
                entry = tarfile.TarInfo(member)
                entry.size = len(data)
                entry.mode = 0o755
                tar.addfile(entry, io.BytesIO(data))
            source = source.replace(checksum, hashlib.sha256(archive.read_bytes()).hexdigest())
            # La presencia en PATH no debe confundirse con una copia persistente.
            self.script(self.mockbin / tool, '#!/bin/sh\necho system-version\n')
        self.installer = self.script(self.root / 'extras.sh', source)
        self.script(self.mockbin / 'uname', '#!/bin/sh\necho "${TUNNING_TEST_ARCH:-x86_64}"\n')
        self.script(self.mockbin / 'sudo', '#!/bin/sh\necho unexpected-sudo >&2\nexit 99\n')
        self.script(self.mockbin / 'curl', '''#!/usr/bin/python3
import os
from pathlib import Path
import shutil
import sys
url = next(a for a in sys.argv if a.startswith('https://'))
tool = 'starship' if '/starship/starship/' in url else 'eza' if '/eza-community/' in url else 'fastfetch'
with open(os.environ['TUNNING_TEST_LOG'], 'a') as log:
    log.write(tool + '\\n')
if tool == os.environ.get('TUNNING_TEST_FAIL'):
    raise SystemExit(22)
destination = sys.argv[sys.argv.index('--output') + 1]
shutil.copyfile(Path(os.environ['TUNNING_TEST_ARCHIVES']) / (tool + '.tar.gz'), destination)
''')
        self.env.update(HOME=str(self.target), PATH=f'{self.mockbin}:/usr/bin:/bin',
                        TUNNING_TEST_LOG=str(self.log), TUNNING_TEST_ARCHIVES=str(self.root))

    def install(self, check=True):
        return execute(['bash', self.installer], cwd=self.root, env=self.env, check=check)

    def test_installs_persistent_copies_and_reinstall_needs_no_downloads(self):
        self.install()
        self.assertEqual(self.log.read_text().splitlines(), ['starship', 'eza', 'fastfetch'])
        for tool in ('starship', 'eza', 'fastfetch'):
            binary = self.target / '.local/bin' / tool
            self.assertEqual(execute([binary, '--version'], env=self.env).stdout.strip(), f'fixture {tool}')
        self.install()
        self.assertEqual(len(self.log.read_text().splitlines()), 3)

    def test_checksum_failure_installs_none_of_the_staged_binaries(self):
        (self.root / 'fastfetch.tar.gz').write_bytes(b'corrupted download')
        result = self.install(check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('fastfetch', result.stderr)
        self.assertFalse((self.target / '.local').exists())

    def test_download_failure_installs_none_of_the_staged_binaries(self):
        self.env['TUNNING_TEST_FAIL'] = 'eza'
        result = self.install(check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('eza', result.stderr)
        self.assertFalse((self.target / '.local').exists())

    def test_symlink_replacement_backs_up_link_and_preserves_external_target(self):
        external = self.script(self.root / 'other-eza', '#!/bin/sh\necho original\n')
        original = external.read_bytes()
        binary = self.target / '.local/bin/eza'
        binary.parent.mkdir(parents=True)
        binary.symlink_to(external)
        self.install()
        self.assertFalse(binary.is_symlink())
        self.assertEqual(external.read_bytes(), original)
        backups = list((self.target / '.local/state/tunning/backups').glob('*/extras/eza'))
        self.assertEqual(len(backups), 1)
        self.assertTrue(backups[0].is_symlink())

    def test_existing_user_executable_is_preserved(self):
        binary = self.script(self.target / '.local/bin/starship', '#!/bin/sh\necho user-version\n')
        original = binary.read_bytes()
        self.install()
        self.assertEqual(binary.read_bytes(), original)
        self.assertEqual(self.log.read_text().splitlines(), ['eza', 'fastfetch'])

    def test_unsupported_architecture_stops_before_downloads_and_writes(self):
        self.env['TUNNING_TEST_ARCH'] = 'aarch64'
        result = self.install(check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('x86_64', result.stderr)
        self.assertFalse(self.log.exists())
        self.assertFalse((self.target / '.local').exists())
