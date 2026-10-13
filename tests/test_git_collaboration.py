"""Colaboración entre clones independientes; transportes solo locales."""
import shlex

from test_terminal import GitFixture


class CollaborationTests(GitFixture):
    def two_clones(self):
        first, peer = self.root / 'first clone', self.root / 'second clone'
        for path in (first, peer):
            self.git('clone', '-q', '-b', 'main', str(self.remote), str(path))
            for key, value in [('user.name', 'Audit'), ('user.email', 'audit@example.invalid'),
                               ('commit.gpgsign', 'false'), ('tunning.syncSign', 'false'),
                               ('alias.sync', self.git('config', 'alias.sync').stdout.strip())]:
                self.git('config', key, value, cwd=path)
        self.work = first
        return peer

    def peer_commit(self, peer, filename, content):
        (peer / filename).write_text(content)
        self.git('add', '-A', cwd=peer)
        self.git('commit', '-qm', 'peer changes', cwd=peer)
        self.git('push', '-q', 'origin', 'main', cwd=peer)
        return self.remote_head()

    def test_two_clones_merge_divergence_without_losing_commits(self):
        peer = self.two_clones()
        (self.work / 'first.txt').write_text('first work\n')
        self.git('add', '-A')
        self.git('commit', '-qm', 'first pending commit')
        local = self.git('rev-parse', 'HEAD').stdout.strip()
        remote = self.peer_commit(peer, 'second.txt', 'second work\n')
        self.git('sync', 'audit divergent clones')
        for commit in (local, remote):
            self.git('merge-base', '--is-ancestor', commit, 'HEAD')
        self.assertEqual(self.remote_head(), self.git('rev-parse', 'HEAD').stdout.strip())
        self.assertEqual((self.work / 'first.txt').read_text(), 'first work\n')
        self.assertEqual((self.work / 'second.txt').read_text(), 'second work\n')

    def test_two_clones_conflict_preserves_local_and_remote_work(self):
        peer = self.two_clones()
        self.modify()
        remote = self.peer_commit(peer, 'file.txt', 'conflicting peer work\n')
        result = self.git('sync', check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('Publicando', result.stdout)
        self.assertEqual(self.remote_head(), remote)
        self.assertTrue((self.work / '.git/MERGE_HEAD').exists())
        self.assertNotEqual(self.git('rev-parse', 'HEAD').stdout.strip(), self.initial)

    def test_remote_race_rejects_obsolete_push_without_force(self):
        peer = self.two_clones()
        (self.work / 'local.txt').write_text('pending local work\n')
        quoted = shlex.quote(str(peer))
        hook = ('#!/bin/sh\nset -e\n'
                f'printf "%s\\n" "peer races the push" > {shlex.quote(str(peer / "race.txt"))}\n'
                f'git -C {quoted} add -- race.txt\n'
                f'git -C {quoted} commit -qm "concurrent peer"\n'
                f'git -C {quoted} push -q origin main\n')
        self.script(self.work / '.git/hooks/pre-push', hook)
        result = self.git('sync', check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('rejected', result.stderr)
        self.assertNotIn('Sincronizados ', result.stdout)
        self.assertEqual(self.remote_head(), self.git('rev-parse', 'HEAD', cwd=peer).stdout.strip())
        self.assertNotEqual(self.remote_head(), self.git('rev-parse', 'HEAD').stdout.strip())
        self.assertEqual((self.work / 'local.txt').read_text(), 'pending local work\n')
