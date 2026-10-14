"""Fusiones recursivas, referencias nuevas y reanudación con API local."""
import json
from pathlib import Path

import test_git_pr as pr_fixtures
from test_terminal import REPO, execute


class MergeTreeFixture(pr_fixtures.PRTreeFixture, pr_fixtures.AuditFixture):
    def approve(self, path, repository, method='merge'):
        self.make_policy()
        policy = json.loads(self.policy.read_text())
        policy['merge_method'] = method
        policy_file = self.root / (repository.replace('/', '-') + '-policy.json')
        policy_file.write_text(json.dumps(policy))
        self.git('config', 'tunning.prPolicy', str(policy_file), cwd=path)
        sha = self.git('rev-parse', 'HEAD', cwd=path).stdout.strip()
        data = self.api()
        remote = data['repositories'][repository]
        remote['runs'] = {'42': {'head_sha': sha, 'status': 'completed', 'conclusion': 'success',
                                'path': '.github/workflows/tests.yml'}}
        remote['prs'][0]['draft'] = False
        self.api_file.write_text(json.dumps(data))
        criteria = self.root / 'criteria-for-tree.json'
        criteria.write_text(json.dumps([{'id': 'A1', 'detail': 'Fixture tests passed'}, {'id': 'A2', 'detail': 'Fixture reviewed'}]))
        execute(['python3', REPO / 'scripts/check-issue-criteria.py', '--repository', repository,
                 '--pr', '1', '--record', criteria, '--run', '42'], cwd=path, env=self.env)
        report = self.root / f'{repository.replace("/", "-")}-{sha[:12]}-audit.json'
        self.git('config', 'tunning.auditReport', str(report), cwd=path)
        execute(['bash', REPO / 'scripts/git-sync.sh', '--tunning-mode=audit', '--provider', 'anthropic',
                 '--session', 'separate-auditor', '--environment', 'fixture-terminal', '--signing-key',
                 self.fingerprint, '--output', report, '--approve'], cwd=path, env=self.env)


class MergeTreeTests(MergeTreeFixture):
    def test_child_merge_updates_parent_requires_new_audit_then_resumes(self):
        child = self.module(path='child with spaces')
        self.change(child)
        self.git('syncPR')
        old_parent = self.git('rev-parse', 'HEAD').stdout.strip()
        self.approve(child['path'], child['repository'])
        self.approve(self.work, 'fixture/parent')
        result = self.git('syncPRmerge', check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('necesita nuevas pruebas y auditoría', result.stderr)
        self.assertNotEqual(old_parent, self.git('rev-parse', 'HEAD').stdout.strip())
        self.assertEqual(self.initial, self.remote_head())
        self.assertEqual(self.git('rev-parse', 'HEAD:' + child['relative']).stdout.strip(),
                         self.git('rev-parse', 'HEAD', cwd=child['path']).stdout.strip())
        self.approve(self.work, 'fixture/parent')
        self.git('syncPRmerge')
        calls = [c['repository'] for c in self.api()['calls'] if c['method'] == 'PUT' and c['path'].endswith('/merge')]
        self.assertEqual(calls, [child['repository'], 'fixture/parent'])
        self.assertFalse(self.git('status', '--porcelain', '--ignore-submodules=none').stdout)

    def test_squash_child_preserves_commits_and_requires_parent_audit(self):
        child = self.module()
        self.change(child)
        self.git('syncPR')
        original = self.git('rev-parse', 'HEAD', cwd=child['path']).stdout.strip()
        self.approve(child['path'], child['repository'], method='squash')
        result = self.git('syncPRmerge', check=False)
        self.assertIn('necesita nuevas pruebas y auditoría', result.stderr)
        self.git('merge-base', '--is-ancestor', original, 'HEAD', cwd=child['path'])
        self.assertEqual(self.git('symbolic-ref', '--short', 'HEAD', cwd=child['path']).stdout.strip(), 'topic')
        self.assertEqual(self.git('rev-parse', 'HEAD:child').stdout.strip(),
                         self.remote_oid(child['remote'], 'topic'))
        self.approve(self.work, 'fixture/parent')
        self.git('syncPRmerge')

    def test_many_children_failure_and_resume_do_not_duplicate_merges(self):
        nodes = [self.module(path=f'child {i}') for i in range(5)]
        for node in nodes:
            self.change(node)
        self.git('syncPR')
        self.approve(nodes[0]['path'], nodes[0]['repository'])
        result = self.git('syncPRmerge', check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.initial, self.remote_head())
        for node in nodes[1:]:
            self.approve(node['path'], node['repository'])
        result = self.git('syncPRmerge', check=False)
        self.assertIn('necesita nuevas pruebas y auditoría', result.stderr)
        self.approve(self.work, 'fixture/parent')
        self.git('syncPRmerge')
        calls = [c['repository'] for c in self.api()['calls'] if c['method'] == 'PUT' and c['path'].endswith('/merge')]
        self.assertEqual(calls, [n['repository'] for n in nodes] + ['fixture/parent'])

    def test_nested_merges_require_each_changed_ancestor_to_be_audited_again(self):
        child = self.module()
        leaf = self.module(parent=child['path'], path='nested')
        self.change(leaf)
        self.git('syncPR')
        self.approve(leaf['path'], leaf['repository'])
        result = self.git('syncPRmerge', check=False)
        self.assertIn('necesita nuevas pruebas y auditoría', result.stderr)
        self.approve(child['path'], child['repository'])
        result = self.git('syncPRmerge', check=False)
        self.assertIn('necesita nuevas pruebas y auditoría', result.stderr)
        self.approve(self.work, 'fixture/parent')
        self.git('syncPRmerge')
        calls = [c['repository'] for c in self.api()['calls'] if c['method'] == 'PUT' and c['path'].endswith('/merge')]
        self.assertEqual(calls, [leaf['repository'], child['repository'], 'fixture/parent'])
