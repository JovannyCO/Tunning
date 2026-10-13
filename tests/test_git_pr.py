"""Modos PR y criterios: remotos temporales y gh simulado, sin credenciales reales."""
import json
import shlex

from test_terminal import GitFixture, REPO, execute


class GitPRTests(GitFixture):
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
