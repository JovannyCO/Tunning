"""Integración recursiva con remotos locales y configuración completamente aislada."""
from pathlib import Path
import shlex

from test_terminal import GitFixture, REPO, execute


class SubmoduleSyncTests(GitFixture):
    def setUp(self):
        super().setUp()
        self.sequence = 0
        self.publications = self.root / 'publications'
        for key, value in [('user.name', 'Audit'), ('user.email', 'audit@example.invalid'),
                           ('commit.gpgsign', 'false'), ('tunning.syncSign', 'false'),
                           ('protocol.file.allow', 'always'),
                           ('alias.sync', '!bash ' + shlex.quote(str(REPO / 'scripts/git-sync.sh')))]:
            execute(['git', 'config', '--file', self.env['GIT_CONFIG_GLOBAL'], key, value], env=self.env)
        self.record_push(self.remote, 'parent')

    def record_push(self, remote, name):
        self.script(remote / 'hooks/post-receive', '#!/bin/sh\n'
                    f'while read old new ref; do printf "%s %s\\n" {shlex.quote(name)} "$ref" '
                    f'>> {shlex.quote(str(self.publications))}; done\n')

    def remote_oid(self, remote, branch):
        return self.git('--git-dir', str(remote), 'rev-parse', f'refs/heads/{branch}').stdout.strip()

    def add_child(self, parent=None, path='child', branch='topic', configured='topic'):
        parent = parent or self.work
        self.sequence += 1
        name = f'module{self.sequence}'
        remote = self.root / f'{name}.git'
        seed = self.root / f'{name}-seed'
        self.git('init', '--bare', '-q', str(remote))
        self.git('init', '-q', '-b', branch, str(seed))
        (seed / 'file.txt').write_text('base\n')
        self.git('add', '.', cwd=seed)
        self.git('commit', '-qm', 'child base', cwd=seed)
        self.git('remote', 'add', 'origin', str(remote), cwd=seed)
        self.git('push', '-qu', 'origin', branch, cwd=seed)
        self.git('--git-dir', str(remote), 'symbolic-ref', 'HEAD', f'refs/heads/{branch}')
        self.record_push(remote, name)
        self.git('submodule', 'add', '-q', '-b', branch, '--name', name, '--', str(remote), path, cwd=parent)
        if configured is None:
            self.git('config', '--file', '.gitmodules', '--unset', f'submodule.{name}.branch', cwd=parent)
        else:
            self.git('config', '--file', '.gitmodules', f'submodule.{name}.branch', configured, cwd=parent)
        self.git('add', '-A', cwd=parent)
        self.git('commit', '-qm', f'add {name}', cwd=parent)
        active = self.git('symbolic-ref', '--short', 'HEAD', cwd=parent).stdout.strip()
        self.git('push', '-q', 'origin', active, cwd=parent)
        self.publications.write_text('')
        self.initial = self.remote_head()
        return {'path': parent / path, 'relative': path, 'name': name, 'remote': remote,
                'branch': branch, 'seed': seed, 'base': self.remote_oid(remote, branch)}

    def change(self, node, filename='file.txt', contents='child change\n'):
        (node['path'] / filename).write_text(contents)

    def assert_published(self, node, branch=None, parent=None):
        branch = branch or node['branch']
        parent = parent or self.work
        oid = self.git('rev-parse', 'HEAD', cwd=node['path']).stdout.strip()
        self.assertEqual(oid, self.remote_oid(node['remote'], branch))
        self.assertEqual(oid, self.git('rev-parse', f"HEAD:{node['relative']}", cwd=parent).stdout.strip())
        self.assertFalse(self.git('status', '--porcelain', '--ignore-submodules=none', cwd=node['path']).stdout)
        return oid

    def git_path(self, node, relative):
        path = self.git('rev-parse', '--git-path', relative, cwd=node['path']).stdout.rstrip('\n')
        return node['path'] / path

    def assert_parent_stopped(self, node, result, parent_head):
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(f"[{node['relative']}]", result.stderr)
        self.assertNotIn('[.] Publicando', result.stdout)
        self.assertNotIn('Sincronizados ', result.stdout)
        self.assertEqual(parent_head, self.remote_head())

    def test_modified_child_and_literal_message_publish_before_parent(self):
        child = self.add_child()
        self.change(child)
        self.modify()
        message = 'literal $(touch NEVER) `touch NEVER` con espacios'
        result = self.git('sync', message)
        self.assert_published(child)
        for path in (self.work, child['path']):
            self.assertIn(message, self.git('log', '-1', '--format=%s', cwd=path).stdout)
            self.assertFalse((path / 'NEVER').exists())
        self.assertEqual(['module1 refs/heads/topic', 'parent refs/heads/main'], self.publications.read_text().splitlines())
        self.assertIn('Sincronizados 2 repositorios', result.stdout)
        self.assertFalse(self.git('status', '--porcelain').stdout)

    def test_clean_child_with_pending_commit_is_published(self):
        child = self.add_child()
        self.change(child)
        self.git('commit', '-qam', 'already committed', cwd=child['path'])
        pending = self.git('rev-parse', 'HEAD', cwd=child['path']).stdout.strip()
        self.assertFalse(self.git('status', '--porcelain', cwd=child['path']).stdout)
        self.git('sync')
        self.assertEqual(pending, self.assert_published(child))

    def test_multiple_children_keep_their_active_branches(self):
        first = self.add_child(path='one', branch='topic', configured='production')
        second = self.add_child(path='two', branch='review', configured='main')
        self.change(first)
        self.change(second)
        self.git('commit', '-qam', 'pending review', cwd=second['path'])
        self.git('sync')
        for node in (first, second):
            self.assert_published(node)
            self.assertEqual(node['branch'], self.git('symbolic-ref', '--short', 'HEAD', cwd=node['path']).stdout.strip())
        self.assertEqual(['module1 refs/heads/topic', 'module2 refs/heads/review', 'parent refs/heads/main'],
                         self.publications.read_text().splitlines())

    def test_nested_publication_order_and_references(self):
        child = self.add_child()
        grandchild = self.add_child(parent=child['path'], path='nested', branch='leaf', configured='leaf')
        self.git('add', '-A')
        self.git('commit', '-qm', 'record nested child')
        self.git('push', '-q', 'origin', 'main')
        self.publications.write_text('')
        self.change(grandchild)
        self.change(child, filename='own.txt')
        self.modify()
        self.git('sync')
        self.assert_published(grandchild, parent=child['path'])
        self.assert_published(child)
        self.assertEqual(['module2 refs/heads/leaf', 'module1 refs/heads/topic', 'parent refs/heads/main'],
                         self.publications.read_text().splitlines())

    def test_paths_with_spaces_quotes_and_shell_characters_are_literal(self):
        path = "deps/literal ' $(touch NEVER) `touch NEVER`"
        child = self.add_child(path=path)
        self.change(child)
        self.git('sync', 'rutas literales')
        self.assert_published(child)
        self.assertFalse((self.work / 'NEVER').exists())
        self.assertFalse((child['path'] / 'NEVER').exists())

    def test_path_with_tab_and_newline(self):
        child = self.add_child(path='deps/tab\tnewline\nend')
        self.change(child)
        self.git('sync')
        self.assert_published(child)

    def test_detached_configured_branch_keeps_pending_commits_and_changes(self):
        child = self.add_child()
        self.git('checkout', '--detach', '-q', cwd=child['path'])
        self.change(child, 'detached.txt')
        self.git('add', '-A', cwd=child['path'])
        self.git('commit', '-qm', 'detached pending', cwd=child['path'])
        pending = self.git('rev-parse', 'HEAD', cwd=child['path']).stdout.strip()
        self.change(child)
        self.git('sync')
        self.assert_published(child)
        self.assertEqual('topic', self.git('symbolic-ref', '--short', 'HEAD', cwd=child['path']).stdout.strip())
        self.git('merge-base', '--is-ancestor', pending, 'HEAD', cwd=child['path'])

    def test_detached_and_configured_local_branch_divergence_preserves_both(self):
        child = self.add_child()
        self.change(child, 'branch.txt')
        self.git('add', '-A', cwd=child['path'])
        self.git('commit', '-qm', 'local branch work', cwd=child['path'])
        branch_tip = self.git('rev-parse', 'HEAD', cwd=child['path']).stdout.strip()
        self.git('checkout', '--detach', '-q', child['base'], cwd=child['path'])
        self.change(child, 'detached.txt')
        self.git('add', '-A', cwd=child['path'])
        self.git('commit', '-qm', 'detached work', cwd=child['path'])
        detached_tip = self.git('rev-parse', 'HEAD', cwd=child['path']).stdout.strip()
        self.change(child, 'uncommitted.txt')
        self.git('sync')
        self.assert_published(child)
        for oid in (branch_tip, detached_tip):
            self.git('merge-base', '--is-ancestor', oid, 'HEAD', cwd=child['path'])
        for filename in ('branch.txt', 'detached.txt', 'uncommitted.txt'):
            self.assertTrue((child['path'] / filename).exists())

    def test_ambiguous_detached_child_stops_all_before_staging(self):
        first = self.add_child(path='a-valid')
        unsafe = self.add_child(path='z-unsafe', configured=None)
        self.change(first)
        self.change(unsafe)
        self.modify()
        self.git('checkout', '--detach', '-q', cwd=unsafe['path'])
        result = self.git('sync', check=False)
        self.assert_parent_stopped(unsafe, result, self.initial)
        self.assertIn('HEAD está separado', result.stderr)
        self.assertNotIn('Agregando', result.stdout)
        self.assertEqual(first['base'], self.remote_oid(first['remote'], first['branch']))
        self.assertEqual(unsafe['base'], self.git('rev-parse', 'HEAD', cwd=unsafe['path']).stdout.strip())
        self.assertFalse(self.git('diff', '--cached', '--name-only').stdout)

    def test_local_branch_configuration_overrides_gitmodules(self):
        child = self.add_child()
        self.git('config', f"submodule.{child['name']}.branch", 'local-review')
        self.git('checkout', '--detach', '-q', cwd=child['path'])
        self.change(child)
        self.git('sync')
        self.assert_published(child, branch='local-review')
        self.assertEqual(child['base'], self.remote_oid(child['remote'], 'topic'))

    def test_branch_dot_inherits_parent_recursively(self):
        child = self.add_child(configured='.')
        grandchild = self.add_child(parent=child['path'], path='nested', configured='.')
        for node in (child, grandchild):
            self.git('checkout', '--detach', '-q', cwd=node['path'])
            self.change(node)
        self.git('sync')
        self.assert_published(child, branch='main')
        self.assert_published(grandchild, branch='main', parent=child['path'])

    def test_uninitialized_checkout_starts_at_recorded_commit_then_integrates(self):
        child = self.add_child()
        (child['seed'] / 'remote.txt').write_text('newer remote\n')
        self.git('add', '-A', cwd=child['seed'])
        self.git('commit', '-qm', 'remote after pin', cwd=child['seed'])
        self.git('push', '-q', 'origin', 'topic', cwd=child['seed'])
        clone = self.root / 'fresh clone'
        self.git('clone', '-q', '-b', 'main', '--no-recurse-submodules', str(self.remote), str(clone))
        self.work = clone
        child['path'] = clone / child['relative']
        self.assertFalse((child['path'] / '.git').exists())
        result = self.git('sync')
        self.assertIn(f"checked out '{child['base']}'", result.stdout)
        self.assertTrue((child['path'] / 'remote.txt').exists())
        self.assert_published(child)

    def test_child_commit_rejection_prevents_parent_commit_and_push(self):
        child = self.add_child()
        self.change(child)
        self.modify()
        self.script(self.git_path(child, 'hooks/pre-commit'), '#!/bin/sh\nexit 1\n')
        result = self.git('sync', check=False)
        self.assert_parent_stopped(child, result, self.initial)
        self.assertEqual(self.initial, self.git('rev-parse', 'HEAD').stdout.strip())

    def test_child_staging_failure_prevents_parent_push(self):
        child = self.add_child()
        self.change(child)
        self.git_path(child, 'index.lock').touch()
        result = self.git('sync', check=False)
        self.assert_parent_stopped(child, result, self.initial)
        self.assertNotIn('Creando commit', result.stdout)

    def test_child_false_sync_sign_still_respects_commit_gpgsign(self):
        child = self.add_child()
        self.change(child)
        signer = self.script(self.root / 'reject-signer', '#!/bin/sh\necho child-signature-rejected >&2\nexit 1\n')
        self.git('config', 'commit.gpgsign', 'true', cwd=child['path'])
        self.git('config', 'gpg.program', str(signer), cwd=child['path'])
        result = self.git('sync', check=False)
        self.assert_parent_stopped(child, result, self.initial)
        self.assertIn('child-signature-rejected', result.stderr)

    def test_child_unavailable_remote_prevents_all_commits(self):
        child = self.add_child()
        self.change(child)
        self.modify()
        self.git('remote', 'set-url', 'origin', str(self.root / 'missing.git'), cwd=child['path'])
        result = self.git('sync', check=False)
        self.assert_parent_stopped(child, result, self.initial)
        self.assertNotIn('Agregando', result.stdout)

    def test_child_merge_conflict_prevents_parent_push(self):
        child = self.add_child()
        (child['seed'] / 'file.txt').write_text('remote conflict\n')
        self.git('commit', '-qam', 'remote conflict', cwd=child['seed'])
        self.git('push', '-q', 'origin', 'topic', cwd=child['seed'])
        self.change(child, contents='local conflict\n')
        result = self.git('sync', check=False)
        self.assert_parent_stopped(child, result, self.initial)
        self.assertTrue(self.git_path(child, 'MERGE_HEAD').exists())

    def test_child_rejected_push_keeps_commit_and_prevents_parent_push(self):
        child = self.add_child()
        self.change(child)
        self.script(child['remote'] / 'hooks/pre-receive', '#!/bin/sh\necho publication-rejected >&2\nexit 1\n')
        result = self.git('sync', check=False)
        self.assert_parent_stopped(child, result, self.initial)
        self.assertIn('publication-rejected', result.stderr)
        self.assertNotEqual(child['base'], self.git('rev-parse', 'HEAD', cwd=child['path']).stdout.strip())
        self.assertEqual(child['base'], self.remote_oid(child['remote'], 'topic'))

    def test_nested_failure_does_not_publish_any_ancestor(self):
        child = self.add_child()
        grandchild = self.add_child(parent=child['path'], path='nested')
        child_head = self.remote_oid(child['remote'], 'topic')
        self.change(grandchild)
        self.script(grandchild['remote'] / 'hooks/pre-receive', '#!/bin/sh\nexit 1\n')
        result = self.git('sync', check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('[child/nested]', result.stderr)
        self.assertNotIn('[child] Publicando', result.stdout)
        self.assertNotIn('[.] Publicando', result.stdout)
        self.assertEqual(child_head, self.remote_oid(child['remote'], 'topic'))
        self.assertEqual(self.initial, self.remote_head())

    def test_production_policy_is_independent_and_production_is_not_pushed(self):
        child = self.add_child()
        self.git('checkout', '-qb', 'production', cwd=child['seed'])
        (child['seed'] / 'production.txt').write_text('child production\n')
        self.git('add', '-A', cwd=child['seed'])
        self.git('commit', '-qm', 'production work', cwd=child['seed'])
        self.git('push', '-q', 'origin', 'production', cwd=child['seed'])
        production = self.remote_oid(child['remote'], 'production')
        self.git('config', 'tunning.syncProduction', 'false')
        self.change(child)
        self.publications.write_text('')
        self.git('sync')
        self.assertTrue((child['path'] / 'production.txt').exists())
        self.assertEqual(production, self.remote_oid(child['remote'], 'production'))
        self.assert_published(child)
        self.assertNotIn('refs/heads/production', self.publications.read_text())

    def test_child_can_disable_production_without_changing_parent_preference(self):
        child = self.add_child()
        self.git('checkout', '-qb', 'production', cwd=child['seed'])
        (child['seed'] / 'file.txt').write_text('production conflict\n')
        self.git('commit', '-qam', 'production conflict', cwd=child['seed'])
        self.git('push', '-q', 'origin', 'production', cwd=child['seed'])
        self.git('config', 'tunning.syncProduction', 'false', cwd=child['path'])
        self.change(child)
        self.git('sync')
        self.assert_published(child)
        self.assertEqual('child change\n', (child['path'] / 'file.txt').read_text())

    def test_reference_must_be_available_in_registered_clone_remote(self):
        child = self.add_child()
        other = self.root / 'other.git'
        self.git('clone', '--bare', '-q', str(child['remote']), str(other))
        self.git('config', '--file', '.gitmodules', f"submodule.{child['name']}.url", str(other))
        self.change(child)
        result = self.git('sync', check=False)
        self.assert_parent_stopped(child, result, self.initial)
        self.assertIn('no es alcanzable', result.stderr)
        self.assertIn('sincronización incompleta', result.stdout)

    def test_remote_merge_discovers_and_initializes_new_child(self):
        self.add_child(path='existing')
        peer = self.root / 'parent-peer'
        self.git('clone', '-q', '-b', 'main', str(self.remote), str(peer))
        new = self.add_child(parent=peer, path='from remote')
        new['path'] = self.work / new['relative']
        result = self.git('sync')
        self.assertIn('[from remote] Inicializando', result.stdout)
        self.assert_published(new)
        self.assertIn('Sincronizados 3 repositorios', result.stdout)
        self.assertFalse(self.git('status', '--porcelain').stdout)

    def test_remote_merge_with_unsafe_new_child_stops_parent(self):
        self.add_child(path='existing')
        peer = self.root / 'parent-peer'
        self.git('clone', '-q', '-b', 'main', str(self.remote), str(peer))
        unsafe = self.add_child(parent=peer, path='unsafe new', configured=None)
        result = self.git('sync', check=False)
        self.assert_parent_stopped(unsafe, result, self.initial)
        self.assertIn('sin rama configurada', result.stderr)

    def test_live_remote_check_catches_deleted_branch_despite_tracking_ref(self):
        child = self.add_child()
        self.change(child)
        self.script(self.work / '.git/hooks/pre-commit', '#!/bin/sh\n'
                    f'git --git-dir {shlex.quote(str(child["remote"]))} update-ref -d refs/heads/topic\n')
        result = self.git('sync', check=False)
        self.assert_parent_stopped(child, result, self.initial)
        self.assertIn('no es alcanzable', result.stderr)
        self.assertTrue(self.git('rev-parse', '--verify', 'refs/remotes/origin/topic', cwd=child['path']).stdout)

    def test_invalid_later_child_config_is_detected_before_first_commit(self):
        first = self.add_child(path='a-first')
        second = self.add_child(path='z-second')
        self.change(first)
        self.git('config', 'tunning.syncSign', 'invalid-bool', cwd=second['path'])
        result = self.git('sync', check=False)
        self.assert_parent_stopped(second, result, self.initial)
        self.assertNotIn('Creando commit', result.stdout)
        self.assertEqual(first['base'], self.remote_oid(first['remote'], 'topic'))

    def test_ignore_all_submodule_preference_does_not_skip_gitlink_update(self):
        child = self.add_child()
        self.git('config', f"submodule.{child['name']}.ignore", 'all')
        self.change(child)
        self.git('sync')
        self.assert_published(child)

    def test_hook_changed_clone_url_is_revalidated_before_parent_push(self):
        child = self.add_child()
        other = self.root / 'other.git'
        self.git('clone', '--bare', '-q', str(child['remote']), str(other))
        self.change(child)
        self.script(self.work / '.git/hooks/pre-commit', '#!/bin/sh\n'
                    f'git config --file .gitmodules submodule.{child["name"]}.url {shlex.quote(str(other))}\n'
                    'git add .gitmodules\n')
        result = self.git('sync', check=False)
        self.assert_parent_stopped(child, result, self.initial)
        self.assertIn('no es alcanzable', result.stderr)

    def test_multiple_local_detached_branch_choices_are_rejected(self):
        child = self.add_child()
        key = f"submodule.{child['name']}.branch"
        self.git('config', '--add', key, 'topic')
        self.git('config', '--add', key, 'other')
        self.git('checkout', '--detach', '-q', cwd=child['path'])
        self.change(child)
        result = self.git('sync', check=False)
        self.assert_parent_stopped(child, result, self.initial)
        self.assertNotIn('Agregando', result.stdout)
        self.assertIn('varias ramas', result.stderr)

    def test_uninitialized_clone_failure_names_the_child(self):
        child = self.add_child()
        self.git('config', '--file', '.gitmodules', f"submodule.{child['name']}.url", str(self.root / 'missing.git'))
        self.git('commit', '-qam', 'unavailable clone URL')
        self.git('push', '-q', 'origin', 'main')
        self.initial = self.remote_head()
        clone = self.root / 'fresh clone'
        self.git('clone', '-q', '-b', 'main', str(self.remote), str(clone))
        self.work = clone
        result = self.git('sync', check=False)
        self.assert_parent_stopped(child, result, self.initial)
        self.assertIn('inicializar', result.stderr)
        self.assertNotIn('Agregando', result.stdout)

    def test_uninitialized_invalid_branch_stops_before_creating_checkout(self):
        child = self.add_child(configured='invalid branch')
        clone = self.root / 'fresh clone'
        self.git('clone', '-q', '-b', 'main', str(self.remote), str(clone))
        self.work = clone
        result = self.git('sync', check=False)
        self.assert_parent_stopped(child, result, self.initial)
        self.assertIn('Rama configurada inválida', result.stderr)
        self.assertFalse((clone / 'child/.git').exists())

    def test_fetch_remote_and_publication_remote_can_be_configured(self):
        child = self.add_child()
        self.git('remote', 'rename', 'origin', 'upstream', cwd=child['path'])
        self.git('remote', 'add', 'publish', str(child['remote']), cwd=child['path'])
        self.git('config', 'branch.topic.pushRemote', 'publish', cwd=child['path'])
        self.change(child)
        self.git('sync')
        self.assert_published(child)
        self.assertEqual('upstream', self.git('config', 'branch.topic.remote', cwd=child['path']).stdout.strip())

    def test_merge_imports_changed_gitlink_from_another_child_branch(self):
        child = self.add_child()
        self.git('checkout', '-qb', 'alternate', cwd=child['seed'])
        (child['seed'] / 'alternate.txt').write_text('new recorded commit\n')
        self.git('add', '-A', cwd=child['seed'])
        self.git('commit', '-qm', 'alternate work', cwd=child['seed'])
        self.git('push', '-q', 'origin', 'alternate', cwd=child['seed'])
        alternate = self.remote_oid(child['remote'], 'alternate')
        peer = self.root / 'parent-peer'
        self.git('clone', '-q', '-b', 'main', str(self.remote), str(peer))
        self.git('update-index', '--cacheinfo', f'160000,{alternate},child', cwd=peer)
        self.git('commit', '-qm', 'new recorded child commit', cwd=peer)
        self.git('push', '-q', 'origin', 'main', cwd=peer)
        result = self.git('sync')
        self.assertIn('commit registrado', result.stdout)
        self.assertEqual(alternate, self.assert_published(child))
        self.assertTrue((child['path'] / 'alternate.txt').exists())
        self.assertEqual('topic', self.git('symbolic-ref', '--short', 'HEAD', cwd=child['path']).stdout.strip())

    def test_signed_child_merge_failure_stops_parent_with_clean_child_tree(self):
        child = self.add_child()
        self.change(child, 'local.txt')
        self.git('add', '-A', cwd=child['path'])
        self.git('commit', '-qm', 'local pending', cwd=child['path'])
        (child['seed'] / 'remote.txt').write_text('remote divergence\n')
        self.git('add', '-A', cwd=child['seed'])
        self.git('commit', '-qm', 'remote pending', cwd=child['seed'])
        self.git('push', '-q', 'origin', 'topic', cwd=child['seed'])
        signer = self.script(self.root / 'reject-signer', '#!/bin/sh\necho merge-signature-rejected >&2\nexit 1\n')
        self.git('config', 'tunning.syncSign', 'true', cwd=child['path'])
        self.git('config', 'gpg.program', str(signer), cwd=child['path'])
        self.assertFalse(self.git('status', '--porcelain', cwd=child['path']).stdout)
        result = self.git('sync', check=False)
        self.assert_parent_stopped(child, result, self.initial)
        self.assertIn('merge-signature-rejected', result.stderr)

    def test_relative_gitmodules_url_is_resolved_against_parent_remote(self):
        child = self.add_child()
        self.git('config', '--file', '.gitmodules', f"submodule.{child['name']}.url", f"../{child['name']}.git")
        self.change(child)
        self.git('sync')
        self.assert_published(child)

    def test_multiple_upstreams_stop_before_child_commit(self):
        child = self.add_child()
        self.git('config', '--add', 'branch.topic.merge', 'refs/heads/another', cwd=child['path'])
        self.change(child)
        result = self.git('sync', check=False)
        self.assert_parent_stopped(child, result, self.initial)
        self.assertNotIn('Agregando', result.stdout)
        self.assertIn('varios upstreams', result.stderr)
