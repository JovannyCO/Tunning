#!/usr/bin/env python3
"""API GitHub simulada sobre remotos bare locales. Nunca usa la red."""
import json
import os
from pathlib import Path
import re
import subprocess
import sys
from urllib.parse import parse_qs, unquote, urlsplit

state_file = Path(os.environ['TUNNING_TEST_GITHUB'])
state = json.loads(state_file.read_text())
args = sys.argv[1:]
method = args[args.index('--method') + 1]
endpoint = args[args.index('--method') + 2]
data = json.load(sys.stdin) if '--input' in args else None
route = urlsplit(endpoint)
owner, name, *parts = route.path.split('/')[1:]
repository = owner + '/' + name
repo = state['repositories'][repository]
query = parse_qs(route.query)
state.setdefault('calls', []).append({'repository': repository, 'method': method, 'path': '/'.join(parts), 'data': data})


def git(*args, input=None):
    return subprocess.check_output(['git', '--git-dir', repo['remote'], '-c', 'user.name=Mock',
                                    '-c', 'user.email=mock@example.invalid', *args], input=input, text=True).strip()


def sha(branch):
    return git('rev-parse', 'refs/heads/' + branch)


def pr_current(pr):
    pr['head']['sha'] = sha(pr['head']['ref'])
    pr['base']['sha'] = sha(pr['base']['ref'])
    return pr


def fail():
    state_file.write_text(json.dumps(state))
    sys.exit(1)


path = '/'.join(parts)
if repo.get('failure') == [method, path]:
    fail()
if not parts:
    result = {'default_branch': repo.get('default_branch', 'main'), 'archived': False,
              'permissions': {'push': repo.get('push', True)}, 'allow_merge_commit': True,
              'allow_squash_merge': True, 'allow_rebase_merge': True}
elif parts[0] == 'assignees':
    result = None
    if repo.get('assignable') is False:
        fail()
elif parts[:3] == ['git', 'ref', 'heads']:
    result = {'object': {'sha': sha(unquote('/'.join(parts[3:])))}}
elif parts[0] == 'compare':
    base, tip = unquote(parts[1]).split('...')
    result = {'ahead_by': int(git('rev-list', '--count', base + '..' + tip)),
              'files': [{'filename': f} for f in git('diff', '--name-only', base, tip).splitlines()]}
elif path == 'issues' and method == 'GET':
    result = [i for i in repo.get('issues', []) if i['state'] == query.get('state', ['open'])[0]]
elif path == 'issues' and method == 'POST':
    result = dict(data, number=len(repo.setdefault('issues', [])) + 1, state='open')
    repo['issues'].append(result)
elif parts[0] == 'issues':
    result = next(i for i in repo['issues'] if i['number'] == int(parts[1]))
    if method == 'PATCH':
        result.update(data)
    if len(parts) == 3 and parts[2] == 'assignees':
        result['assignees'] = list(set(result.get('assignees', []) + data['assignees']))
        for pr in repo.get('prs', []):
            if pr['number'] == int(parts[1]):
                pr['assignees'] = result['assignees']
elif path == 'pulls' and method == 'GET':
    result = [pr_current(p) for p in repo.get('prs', []) if p['state'] == query.get('state', ['open'])[0]
              and p['head']['ref'] == query.get('head', [':'])[0].split(':', 1)[1]
              and p['base']['ref'] == query.get('base', ['main'])[0]]
elif path == 'pulls' and method == 'POST':
    result = dict(data, number=len(repo.setdefault('prs', [])) + 1, state='open', merged=False,
                  mergeable=True, mergeable_state='clean', user={'login': 'implementer'},
                  html_url=f'https://github.com/{repository}/pull/{len(repo["prs"]) + 1}')
    result['head'], result['base'] = {'ref': data['head']}, {'ref': data['base']}
    pr_current(result)
    repo['prs'].append(result)
elif parts[0] == 'pulls':
    pr = next(p for p in repo['prs'] if p['number'] == int(parts[1]))
    if len(parts) == 2:
        if method == 'GET':
            repo['pull_reads'] = repo.get('pull_reads', 0) + 1
            if repo.get('head_race') and repo['pull_reads'] == 2:
                branch = pr['head']['ref']
                tip = sha(branch)
                changed = git('commit-tree', tip + '^{tree}', '-p', tip, input='concurrent push\n')
                git('update-ref', 'refs/heads/' + branch, changed)
        result = pr_current(pr)
        if method == 'PATCH':
            result.update(data)
    elif parts[2] == 'reviews':
        result = repo.get('reviews', [])
    elif parts[2] == 'merge':
        if repo.get('push_race'):
            branch = pr['head']['ref']
            tip = sha(branch)
            changed = git('commit-tree', tip + '^{tree}', '-p', tip, input='push just before merge\n')
            git('update-ref', 'refs/heads/' + branch, changed)
        if repo.get('merge_failure') or pr.get('draft') or data['sha'] != sha(pr['head']['ref']):
            fail()
        base, tip = sha(pr['base']['ref']), sha(pr['head']['ref'])
        if repo.get('base_race'):
            base = git('commit-tree', base + '^{tree}', '-p', base, input='concurrent base\n')
        if data['merge_method'] == 'merge':
            merged = git('commit-tree', tip + '^{tree}', '-p', base, '-p', tip, input='mock merge\n')
        elif data['merge_method'] == 'squash':
            merged = git('commit-tree', tip + '^{tree}', '-p', base, input='mock squash\n')
        else:
            merged = base
            for commit in git('rev-list', '--reverse', pr['base']['sha'] + '..' + tip).splitlines():
                merged = git('commit-tree', commit + '^{tree}', '-p', merged, input='mock rebase\n')
        git('update-ref', 'refs/heads/' + pr['base']['ref'], merged)
        pr.update(merged=True, state='closed', merge_commit_sha=merged)
        for issue in repo.get('issues', []):
            if f'Closes #{issue["number"]}' in pr['body'] and pr['base']['ref'] == repo.get('default_branch', 'main'):
                issue['state'] = 'closed'
        result = {'merged': True, 'sha': merged}
    else:
        fail()
elif parts[0] == 'commits' and parts[2] == 'check-runs':
    result = {'check_runs': repo.get('checks', [{'name': 'terminal', 'status': 'completed', 'conclusion': 'success'}])}
elif parts[0] == 'commits' and parts[2] == 'statuses':
    result = [status for status in repo.get('statuses', []) if status.get('sha', parts[1]) == parts[1]]
elif parts[0] == 'statuses' and method == 'POST':
    if (len(parts) != 2 or not re.fullmatch(r'[a-f0-9]{40}', parts[1]) or
            data.get('state') not in ('pending', 'error', 'failure', 'success') or
            not isinstance(data.get('context'), str) or not data['context'].strip()):
        fail()
    git('cat-file', '-e', parts[1] + '^{commit}')
    result = dict(data, sha=parts[1])
    repo.setdefault('statuses', []).insert(0, result)
elif parts[:2] == ['actions', 'runs']:
    result = repo['runs'][parts[2]]
else:
    fail()
state_file.write_text(json.dumps(state))
print(json.dumps(result))
