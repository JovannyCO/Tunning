"""Modos PR y criterios: remotos temporales y gh simulado, sin credenciales reales."""
import json
import hashlib
import shlex
from pathlib import Path

from test_terminal import GitFixture, REPO, execute
import test_git_sync_submodules as submodule_fixtures


class GitPRFixture(GitFixture):
    def setUp(self):
        super().setUp()
        previous = self.work
        self.work = self.root / 'work with spaces'
        previous.rename(self.work)
        self.api_file = self.root / 'github.json'
        self.api_file.write_text(json.dumps({'repositories': {'fixture/parent': {'remote': str(self.remote)}}}))
        self.env['TUNNING_TEST_GITHUB'] = str(self.api_file)
        binary = self.script(self.root / 'bin/gh', '#!/bin/sh\nexec /usr/bin/python3 ' +
                             shlex.quote(str(REPO / 'tests/fixtures/github_api.py')) + ' "$@"\n')
        self.env['PATH'] = str(binary.parent) + ':' + self.env['PATH']
        self.git('config', 'url.' + str(self.remote) + '.insteadOf', 'https://github.com/fixture/parent.git')
        self.git('remote', 'set-url', 'origin', 'https://github.com/fixture/parent.git')
        for mode in ('syncPR', 'syncPRmerge'):
            self.git('config', 'alias.' + mode, '!bash ' + shlex.quote(str(REPO / 'scripts/git-sync.sh')) + ' --tunning-mode=' + mode)
        self.git('switch', '-qc', '8-work')
        self.git('config', 'tunning.implementerProvider', 'openai')
        self.git('config', 'tunning.implementerSession', 'implementer-terminal')

    def api(self):
        return json.loads(self.api_file.read_text())

    def update_api(self, update):
        data = self.api()
        update(data['repositories']['fixture/parent'])
        self.api_file.write_text(json.dumps(data))

    def criterion_command(self, *args):
        return execute(['python3', REPO / 'scripts/check-issue-criteria.py', '--repository',
                        'fixture/parent', '--pr', '1', *args], cwd=self.work, env=self.env, check=False)

    def evidence(self):
        self.update_api(lambda r: r.update(runs={'42': {'head_sha': self.git('rev-parse', 'HEAD').stdout.strip(),
            'status': 'completed', 'conclusion': 'success', 'path': '.github/workflows/tests.yml'}}))
        file = self.root / 'criteria.json'
        file.write_text(json.dumps([{'id': 'A1', 'detail': 'Local fixtures passed'}, {'id': 'A2', 'detail': 'Reviewed child references'}]))
        return self.criterion_command('--record', file, '--run', '42')

class GitPRTests(GitPRFixture):
    def test_create_and_reuse_single_issue_pr_literal_message(self):
        self.modify()
        message = 'literal $(touch NEVER) `touch NEVER` con espacios'
        first = self.git('syncPR', message)
        sha = self.git('rev-parse', 'HEAD').stdout.strip()
        self.git('syncPR', message)
        api = self.api()['repositories']['fixture/parent']
        self.assertEqual(len(api['prs']), 1)
        self.assertEqual(len(api['issues']), 1)
        self.assertIn('Closes #1', api['prs'][0]['body'])
        self.assertEqual(sha, self.git('rev-parse', 'HEAD').stdout.strip())
        self.assertIn('base: main; issue #1; PR', first.stdout)
        self.assertFalse((self.work / 'NEVER').exists())
        self.assertEqual(self.initial, self.remote_head())
        self.assertFalse(api['prs'][0]['merged'])
        self.assertEqual(api['issues'][0]['assignees'], ['fixture'])
        self.assertEqual(api['prs'][0]['assignees'], ['fixture'])

    def test_custom_responsible_preserves_other_assignees(self):
        self.git('config', 'tunning.responsible', 'JovannyCO')
        self.modify()
        self.git('syncPR')
        self.update_api(lambda r: r['issues'][0]['assignees'].append('teammate'))
        self.git('syncPR')
        self.assertEqual(set(self.api()['repositories']['fixture/parent']['issues'][0]['assignees']), {'teammate', 'JovannyCO'})

    def test_unassignable_responsible_blocks_before_commit(self):
        self.modify()
        self.update_api(lambda r: r.update(assignable=False))
        result = self.git('syncPR', check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.initial, self.git('rev-parse', 'HEAD').stdout.strip())

    def test_main_blocks_before_staging(self):
        self.git('switch', 'main')
        self.modify()
        result = self.git('syncPR', check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('prepara explícitamente', result.stderr)
        self.assertEqual(self.initial, self.git('rev-parse', 'HEAD').stdout.strip())
        self.assertFalse(self.git('diff', '--cached', '--stat').stdout)

    def test_permissions_block_before_commit(self):
        self.update_api(lambda r: r.update(push=False))
        self.modify()
        result = self.git('syncPR', check=False)
        self.assertIn('sin permiso push', result.stderr)
        self.assertEqual(self.initial, self.git('rev-parse', 'HEAD').stdout.strip())

    def test_no_diff_skips_pr_and_issue(self):
        self.git('syncPR')
        self.assertNotIn('prs', self.api()['repositories']['fixture/parent'])
        self.assertNotIn('issues', self.api()['repositories']['fixture/parent'])

    def test_api_failure_keeps_published_work_partial_summary(self):
        self.update_api(lambda r: r.update(failure=['POST', 'pulls']))
        self.modify()
        result = self.git('syncPR', check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('sincronización incompleta', result.stdout)
        self.assertEqual(self.git('rev-parse', 'HEAD').stdout.strip(), self.remote_head('8-work'))

    def test_base_uses_actual_default_branch(self):
        self.git('push', 'origin', 'main:production')
        self.update_api(lambda r: r.update(default_branch='production'))
        self.modify()
        self.git('syncPR')
        self.assertEqual('production', self.api()['repositories']['fixture/parent']['prs'][0]['base']['ref'])

    def test_criteria_pending_and_missing_proof_rejected(self):
        self.modify()
        self.git('syncPR')
        self.assertIn('criterios pendientes', self.criterion_command().stderr)
        self.update_api(lambda r: r['issues'][0].update(body=r['issues'][0]['body'].replace('[ ]', '[x]')))
        self.assertIn('tunning-evidence', self.criterion_command().stderr)

    def test_record_current_ci_checks_criteria_but_never_merges(self):
        self.modify()
        self.git('syncPR')
        result = self.evidence()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.criterion_command().returncode, 0)
        self.assertFalse(self.api()['repositories']['fixture/parent']['prs'][0]['merged'])

    def test_evidence_stale_after_push(self):
        self.modify()
        self.git('syncPR')
        self.assertEqual(self.evidence().returncode, 0)
        (self.work / 'next').write_text('another change')
        self.git('syncPR')
        self.assertIn('obsoleta', self.criterion_command().stderr)

    def test_evidence_stale_after_base_advances(self):
        self.modify()
        self.git('syncPR')
        self.assertEqual(self.evidence().returncode, 0)
        self.peer(filename='base-only.txt')
        self.assertIn('obsoleta', self.criterion_command().stderr)

    def test_changed_criteria_and_duplicate_evidence_are_rejected(self):
        self.modify()
        self.git('syncPR')
        self.assertEqual(self.evidence().returncode, 0)
        self.update_api(lambda r: r['issues'][0].update(body=r['issues'][0]['body'].replace('Pruebas acordadas', 'Pruebas nuevas')))
        self.assertIn('obsoleta', self.criterion_command().stderr)
        self.assertEqual(self.evidence().returncode, 0)
        self.update_api(lambda r: r['issues'][0].update(body=r['issues'][0]['body'].replace('"A2"', '"A1"')))
        self.assertIn('no cubre exactamente', self.criterion_command().stderr)

    def test_missing_failed_skipped_or_other_sha_ci_blocks_record(self):
        self.modify()
        self.git('syncPR')
        self.assertEqual(self.evidence().returncode, 0)
        for key, value in [('status', 'queued'), ('conclusion', 'failure'), ('conclusion', 'skipped'), ('head_sha', self.initial)]:
            with self.subTest(key=key, value=value):
                self.update_api(lambda r: r['runs']['42'].update({key: value}))
                self.assertNotEqual(self.criterion_command().returncode, 0)

    def test_merge_requires_independent_evidence_no_merge_call(self):
        self.modify()
        result = self.git('syncPRmerge', check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('tunning.prPolicy', result.stderr)
        self.assertFalse(any(c['path'].endswith('/merge') for c in self.api()['calls']))
        self.assertEqual(self.initial, self.remote_head())


class AuditFixture(GitPRFixture):
    def make_policy(self, commands=None, provider='anthropic'):
        if not hasattr(self, 'fingerprint'):
            keyring = self.root / 'keyring'
            keyring.mkdir(mode=0o700)
            self.env['GNUPGHOME'] = str(keyring)
            self.addCleanup(lambda: execute(['gpgconf', '--kill', 'gpg-agent'], env=self.env, check=False))
            execute(['gpg', '--batch', '--pinentry-mode', 'loopback', '--passphrase', '', '--quick-generate-key',
                     'Fixture Auditor <fixture@example.invalid>', 'ed25519', 'sign', '0'], env=self.env)
            listing = execute(['gpg', '--with-colons', '--fingerprint', '--list-keys'], env=self.env).stdout
            self.fingerprint = next(line.split(':')[9] for line in listing.splitlines() if line.startswith('fpr:'))
        self.policy = self.root / 'trusted-policy.json'
        self.policy.write_text(json.dumps({'commands': commands or [['python3', '-c', 'print("fixture tests OK")']],
            'checks': ['terminal'], 'auditors': {self.fingerprint: {'provider': provider, 'identity': 'Fixture Auditor'}}}))
        self.git('config', 'tunning.prPolicy', str(self.policy))
        self.report = self.root / 'signed-report.json'
        self.git('config', 'tunning.auditReport', str(self.report))

    def run_audit(self, *extra):
        return execute(['bash', REPO / 'scripts/git-sync.sh', '--tunning-mode=audit', '--provider', 'anthropic',
                        '--session', 'auditor-terminal', '--environment', 'fixture-independent-terminal',
                        '--signing-key', self.fingerprint, '--output', self.report, *extra],
                       cwd=self.work, env=self.env, check=False)

    def prepare_audit(self, commands=None):
        self.make_policy(commands)
        self.modify()
        self.git('syncPR')


class AuditTests(AuditFixture):
    def test_signed_audit_keeps_source_index_head_and_main_unchanged(self):
        self.prepare_audit()
        before = (self.git('rev-parse', 'HEAD').stdout, (self.work / '.git/index').read_bytes(),
                  (self.work / 'file.txt').read_bytes())
        result = self.run_audit('--approve')
        self.assertEqual(result.returncode, 0, result.stderr)
        after = (self.git('rev-parse', 'HEAD').stdout, (self.work / '.git/index').read_bytes(),
                 (self.work / 'file.txt').read_bytes())
        self.assertEqual(before, after)
        report = json.loads(self.report.read_text())
        self.assertTrue(report['unchanged'])
        self.assertEqual(report['tests'][0]['returncode'], 0)
        self.assertTrue(Path(str(self.report) + '.asc').exists())
        self.assertEqual(self.initial, self.remote_head())
        self.assertNotEqual(self.run_audit('--approve').returncode, 0)

    def test_audit_detects_file_mutation_without_correcting_it(self):
        self.prepare_audit([['python3', '-c', 'from pathlib import Path; Path("file.txt").write_text("unexpected edit")']])
        result = self.run_audit('--approve')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(json.loads(self.report.read_text())['unchanged'])
        self.assertEqual((self.work / 'file.txt').read_text(), 'unexpected edit')

    def test_audit_detects_head_mutation(self):
        self.prepare_audit([['git', 'commit', '--allow-empty', '-m', 'unexpected commit']])
        previous = self.git('rev-parse', 'HEAD').stdout
        self.assertNotEqual(self.run_audit('--approve').returncode, 0)
        self.assertFalse(json.loads(self.report.read_text())['unchanged'])
        self.assertNotEqual(previous, self.git('rev-parse', 'HEAD').stdout)

    def test_audit_detects_index_mutation(self):
        self.prepare_audit([['git', 'update-index', '--chmod=+x', 'file.txt']])
        self.assertNotEqual(self.run_audit('--approve').returncode, 0)
        self.assertFalse(json.loads(self.report.read_text())['unchanged'])

    def test_failing_suite_records_failure_and_blocks_approval(self):
        self.prepare_audit([['python3', '-c', 'raise SystemExit(1)']])
        self.assertNotEqual(self.run_audit('--approve').returncode, 0)
        self.assertEqual(json.loads(self.report.read_text())['tests'][0]['returncode'], 1)

    def test_same_provider_blocks_audit_before_tests(self):
        self.prepare_audit()
        policy = json.loads(self.policy.read_text())
        policy['auditors'][self.fingerprint]['provider'] = 'openai'
        self.policy.write_text(json.dumps(policy))
        self.assertNotEqual(self.run_audit('--approve').returncode, 0)
        self.assertFalse(self.report.exists())

    def test_report_inside_checkout_is_rejected(self):
        self.prepare_audit()
        self.report = self.work / 'report.json'
        self.assertIn('fuera del checkout', self.run_audit('--approve').stderr)

    def test_findings_recorded_without_self_approval(self):
        self.prepare_audit()
        findings = self.root / 'findings.json'
        findings.write_text('[{"detail":"A defect remains"}]')
        self.assertNotEqual(self.run_audit('--findings', findings).returncode, 0)
        self.assertFalse(json.loads(self.report.read_text())['review_approved'])


class PRTreeFixture(GitPRFixture):
    record_push = submodule_fixtures.SubmoduleSyncTests.record_push
    add_child = submodule_fixtures.SubmoduleSyncTests.add_child
    remote_oid = submodule_fixtures.SubmoduleSyncTests.remote_oid
    change = submodule_fixtures.SubmoduleSyncTests.change

    def setUp(self):
        super().setUp()
        self.sequence = 0
        self.publications = self.root / 'publications'
        for key, value in [('user.name', 'Fixture'), ('user.email', 'fixture@example.invalid'),
                           ('commit.gpgsign', 'false'), ('tunning.syncSign', 'false'),
                           ('protocol.file.allow', 'always'), ('tunning.implementerProvider', 'openai'),
                           ('tunning.implementerSession', 'implementer-terminal')]:
            self.git('config', '--file', self.env['GIT_CONFIG_GLOBAL'], key, value)
        self.record_push(self.remote, 'parent')

    def module(self, parent=None, path='child', branch='topic'):
        child = self.add_child(parent=parent, path=path, branch=branch, configured=branch)
        self.git('push', '-q', 'origin', branch + ':main', cwd=child['path'])
        name = 'fixture/' + child['name']
        url = f'https://github.com/{name}.git'
        self.git('config', '--file', self.env['GIT_CONFIG_GLOBAL'], 'url.' + str(child['remote']) + '.insteadOf', url)
        self.git('remote', 'set-url', 'origin', url, cwd=child['path'])
        data = self.api()
        data['repositories'][name] = {'remote': str(child['remote'])}
        self.api_file.write_text(json.dumps(data))
        child['repository'] = name
        return child


class PRTreeTests(PRTreeFixture):
    def test_two_children_pending_clean_commit_literal_path_before_parent(self):
        first = self.module(path="child with ' spaces $(literal)")
        second = self.module(path='second', branch='review')
        self.change(first)
        self.change(second)
        self.git('commit', '-qam', 'already committed', cwd=second['path'])
        result = self.git('syncPR', 'literal $(touch NEVER) `touch NEVER`')
        created = [c['repository'] for c in self.api()['calls'] if c['method'] == 'POST' and c['path'] == 'pulls']
        self.assertEqual(created, [first['repository'], second['repository'], 'fixture/parent'])
        self.assertIn('Sincronizados 3 repositorios', result.stdout)
        for child in (first, second):
            self.assertEqual(self.git('rev-parse', 'HEAD', cwd=child['path']).stdout.strip(),
                             self.git('rev-parse', 'HEAD:' + child['relative']).stdout.strip())
        self.git('syncPR')
        self.assertTrue(all(len(r['prs']) == 1 and len(r['issues']) == 1 for r in self.api()['repositories'].values()))

    def test_nested_pr_order(self):
        child = self.module()
        leaf = self.module(parent=child['path'], path='nested')
        self.change(leaf)
        self.git('syncPR')
        created = [c['repository'] for c in self.api()['calls'] if c['method'] == 'POST' and c['path'] == 'pulls']
        self.assertEqual(created, [leaf['repository'], child['repository'], 'fixture/parent'])

    def test_child_api_failure_prevents_parent_staging(self):
        child = self.module()
        self.change(child)
        before = self.git('rev-parse', 'HEAD').stdout
        data = self.api()
        data['repositories'][child['repository']]['failure'] = ['POST', 'pulls']
        self.api_file.write_text(json.dumps(data))
        (self.work / 'parent change').write_text('parent work')
        result = self.git('syncPR', check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('[child]', result.stderr)
        self.assertEqual(before, self.git('rev-parse', 'HEAD').stdout)
        self.assertFalse(self.git('diff', '--cached', '--stat').stdout)
        self.assertNotIn('prs', self.api()['repositories']['fixture/parent'])

    def test_later_child_permissions_fail_before_first_commit(self):
        first, second = self.module(path='one'), self.module(path='two')
        self.change(first)
        self.change(second)
        data = self.api()
        data['repositories'][second['repository']]['push'] = False
        self.api_file.write_text(json.dumps(data))
        before = self.git('rev-parse', 'HEAD', cwd=first['path']).stdout
        result = self.git('syncPR', check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(before, self.git('rev-parse', 'HEAD', cwd=first['path']).stdout)
        self.assertNotIn('Agregando', result.stdout)


class MergeTests(AuditFixture):
    def ready(self):
        self.prepare_audit()
        self.assertEqual(self.evidence().returncode, 0)
        self.assertEqual(self.run_audit('--approve').returncode, 0)
        self.update_api(lambda r: r['prs'][0].update(draft=False))

    def resign(self, change):
        report = json.loads(self.report.read_text())
        change(report)
        self.report.write_text(json.dumps(report))
        execute(['gpg', '--batch', '--yes', '--local-user', self.fingerprint, '--armor', '--detach-sign',
                 '--output', str(self.report) + '.asc', self.report], env=self.env)

    def assert_no_merge(self, result):
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertFalse(any(c['path'].endswith('/merge') and c['method'] == 'PUT' for c in self.api()['calls']))
        self.assertEqual(self.initial, self.remote_head())

    def test_current_signed_independent_audit_merges_expected_sha_and_resumes(self):
        self.ready()
        original = self.git('rev-parse', 'HEAD').stdout.strip()
        result = self.git('syncPRmerge', '--issue', '1')
        merged = self.remote_head()
        self.assertEqual(merged, self.git('rev-parse', 'HEAD').stdout.strip())
        self.git('merge-base', '--is-ancestor', original, 'HEAD')
        call = next(c for c in self.api()['calls'] if c['path'].endswith('/merge'))
        self.assertEqual(call['data'], {'sha': original, 'merge_method': 'merge'})
        self.assertIn('progreso guardado', result.stdout)
        self.git('syncPRmerge', '--issue', '1')
        self.assertEqual(sum(c['path'].endswith('/merge') for c in self.api()['calls']), 1)

    def test_same_provider_signed_report_blocks(self):
        self.ready()
        policy = json.loads(self.policy.read_text())
        policy['auditors'][self.fingerprint]['provider'] = 'openai'
        self.policy.write_text(json.dumps(policy))
        self.resign(lambda r: r.update(policy_sha256=hashlib.sha256(self.policy.read_bytes()).hexdigest(),
                                       auditor=dict(r['auditor'], provider='openai')))
        result = self.git('syncPRmerge', check=False)
        self.assert_no_merge(result)
        self.assertIn('otro proveedor', result.stderr)

    def test_same_session_signed_report_blocks(self):
        self.ready()
        self.resign(lambda r: r['auditor'].update(session='implementer-terminal'))
        self.assert_no_merge(self.git('syncPRmerge', check=False))

    def test_tampered_report_blocks_signature_verification(self):
        self.ready()
        self.report.write_text(self.report.read_text().replace('Fixture Auditor', 'Tampered Auditor'))
        result = self.git('syncPRmerge', check=False)
        self.assert_no_merge(result)
        self.assertIn('Firma de auditoría inválida', result.stderr)

    def test_signed_findings_block(self):
        self.ready()
        self.resign(lambda r: r.update(findings=[{'detail': 'Unresolved defect'}]))
        self.assert_no_merge(self.git('syncPRmerge', check=False))

    def test_stale_audit_blocks_even_after_new_ci_evidence(self):
        self.ready()
        (self.work / 'new').write_text('updated work')
        self.git('syncPR')
        self.assertEqual(self.evidence().returncode, 0)
        result = self.git('syncPRmerge', check=False)
        self.assert_no_merge(result)
        self.assertIn('Auditoría obsoleta', result.stderr)

    def test_pending_failed_skipped_missing_checks_block(self):
        self.ready()
        for checks in ([{'name': 'terminal', 'status': 'in_progress', 'conclusion': None}],
                       [{'name': 'terminal', 'status': 'completed', 'conclusion': 'failure'}],
                       [{'name': 'terminal', 'status': 'completed', 'conclusion': 'skipped'}], []):
            with self.subTest(checks=checks):
                self.update_api(lambda r: r.update(checks=checks))
                self.assert_no_merge(self.git('syncPRmerge', check=False))

    def test_changes_requested_and_required_other_reviewer_block(self):
        self.ready()
        self.update_api(lambda r: r.update(reviews=[{'state': 'CHANGES_REQUESTED', 'user': {'login': 'reviewer'},
                                                   'commit_id': self.git('rev-parse', 'HEAD').stdout.strip()}]))
        self.assert_no_merge(self.git('syncPRmerge', check=False))

    def test_draft_conflict_or_unknown_mergeability_blocks(self):
        self.ready()
        for change in ({'draft': True}, {'draft': False, 'mergeable': False}, {'mergeable': None}):
            with self.subTest(change=change):
                self.update_api(lambda r: r['prs'][0].update(change))
                self.assert_no_merge(self.git('syncPRmerge', check=False))

    def test_api_merge_rejection_preserves_published_branch(self):
        self.ready()
        self.update_api(lambda r: r.update(merge_failure=True))
        result = self.git('syncPRmerge', check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.initial, self.remote_head())
        self.assertFalse(self.git('status', '--porcelain').stdout)

    def test_base_race_records_remote_merge_and_stops(self):
        self.ready()
        self.update_api(lambda r: r.update(base_race=True))
        result = self.git('syncPRmerge', check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('La base o el contenido cambió', result.stderr)
        state = json.loads((self.work / '.git/tunning-sync/state.json').read_text())
        self.assertEqual(state['merged']['sha'], self.remote_head())
        self.assertIn('progreso guardado', result.stdout)

    def test_squash_keeps_original_commit_and_active_branch(self):
        self.ready()
        policy = json.loads(self.policy.read_text())
        policy['merge_method'] = 'squash'
        self.policy.write_text(json.dumps(policy))
        self.resign(lambda r: r.update(policy_sha256=hashlib.sha256(self.policy.read_bytes()).hexdigest()))
        original = self.git('rev-parse', 'HEAD').stdout.strip()
        self.git('syncPRmerge')
        self.git('merge-base', '--is-ancestor', original, 'HEAD')
        self.git('merge-base', '--is-ancestor', self.remote_head(), 'HEAD')
        self.assertEqual(self.git('symbolic-ref', '--short', 'HEAD').stdout.strip(), '8-work')
        self.assertEqual(self.git('rev-parse', 'HEAD').stdout.strip(), self.remote_head('8-work'))
        self.assertFalse(self.git('status', '--porcelain').stdout)

    def test_rebase_keeps_original_commit_and_active_branch(self):
        self.ready()
        policy = json.loads(self.policy.read_text())
        policy['merge_method'] = 'rebase'
        self.policy.write_text(json.dumps(policy))
        self.resign(lambda r: r.update(policy_sha256=hashlib.sha256(self.policy.read_bytes()).hexdigest()))
        original = self.git('rev-parse', 'HEAD').stdout.strip()
        self.git('syncPRmerge')
        self.git('merge-base', '--is-ancestor', original, 'HEAD')
        self.git('merge-base', '--is-ancestor', self.remote_head(), 'HEAD')
        self.assertEqual(self.git('rev-parse', 'HEAD').stdout.strip(), self.remote_head('8-work'))

    def test_head_race_before_merge_blocks_without_api_mutation(self):
        self.ready()
        self.update_api(lambda r: r.update(head_race=True, pull_reads=0))
        result = self.git('syncPRmerge', check=False)
        self.assert_no_merge(result)
        self.assertIn('justo antes de fusionar', result.stderr)

    def test_push_during_api_merge_is_rejected_by_expected_sha(self):
        self.ready()
        self.update_api(lambda r: r.update(push_race=True))
        result = self.git('syncPRmerge', check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.initial, self.remote_head())
