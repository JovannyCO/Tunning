#!/usr/bin/env bash
# Archivo autónomo: el instalador copia esta única implementación del comando.
set -euo pipefail
exec python3 - "$@" <<'PY'
import datetime
import argparse
import hashlib
import json
import os
from pathlib import Path
import posixpath
import pwd
import re
import socket
import subprocess
import sys
import tempfile
from urllib.parse import quote, urlencode, urlsplit, urlunsplit


HELP = '''Uso: git sync ["mensaje"]
     git syncPR ["mensaje"] [--issue N]
     git syncPRmerge ["mensaje"] [--issue N]
Los tres alias usan esta implementación. sync publica; syncPR prepara PR;
syncPRmerge exige evidencia vigente y auditoría independiente para fusionar.
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
Los modos PR necesitan gh autenticado en github.com y una rama distinta de
la base (tunning.prBase o rama predeterminada real). No crean ramas arbitrarias.
Política/auditorías: tunning.prPolicy y tunning.auditReport, fuera del checkout.
Ver docs/GIT-PR.md para evidencia, firmas, pruebas y reanudación.
'''
MODE = 'sync'
if sys.argv[1:2] and sys.argv[1].startswith('--tunning-mode='):
    MODE = sys.argv.pop(1).split('=', 1)[1]
if sys.argv[1:2] in (['--help'], ['-h']):
    print(HELP, end='')
    sys.exit(0)

OPTIONS = None
if MODE != 'sync':
    parser = argparse.ArgumentParser(description=HELP)
    parser.add_argument('message', nargs='*')
    parser.add_argument('--issue', type=int)
    parser.add_argument('--repository')
    parser.add_argument('--pr', type=int)
    parser.add_argument('--record', type=Path)
    parser.add_argument('--run', type=int)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--provider')
    parser.add_argument('--session')
    parser.add_argument('--environment')
    parser.add_argument('--signing-key')
    parser.add_argument('--findings', type=Path)
    parser.add_argument('--approve', action='store_true')
    OPTIONS = parser.parse_args()
MESSAGE = ' '.join(OPTIONS.message if OPTIONS else sys.argv[1:]) or 'Cambios en la matrix'
ROOT = None
REPOS = {}
PUBLISHED = {}
PRS = {}
MERGED = {}


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


def canonical(data):
    return json.dumps(data, sort_keys=True, ensure_ascii=True, separators=(',', ':')).encode()


def digest(data):
    return hashlib.sha256(data).hexdigest()


class GitHub:
    """CLI autenticada; todos los datos se pasan como argumentos o JSON stdin."""
    def __init__(self, path, repository):
        if not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', repository):
            fail(path, 'Nombre de repositorio GitHub inválido.')
        self.path, self.repository = path, repository
        self.prefix = f'repos/{repository}'

    def api(self, endpoint='', method='GET', data=None):
        args = ['gh', 'api', '--hostname', 'github.com', '--method', method,
                self.prefix + ('/' + endpoint if endpoint else '')]
        if data is not None:
            args += ['--input', '-']
        result = subprocess.run(args, cwd=self.path, input=json.dumps(data) if data is not None else None,
                                capture_output=True, text=True,
                                env={**os.environ, 'GH_PROMPT_DISABLED': '1'})
        if result.returncode:
            # No imprimir respuestas/headers que puedan contener credenciales.
            fail(self.path, f'GitHub {method} {endpoint or self.repository} falló; revisa gh auth status y permisos (código {result.returncode}).')
        try:
            return json.loads(result.stdout) if result.stdout.strip() else None
        except ValueError:
            fail(self.path, 'Respuesta JSON inválida de GitHub.')

    def pages(self, endpoint, key=None):
        found = []
        for page in range(1, 1001):
            data = self.api(endpoint + ('&' if '?' in endpoint else '?') + f'per_page=100&page={page}')
            batch = data[key] if key else data
            if not isinstance(batch, list):
                fail(self.path, f'Lista inválida de GitHub: {endpoint}.')
            found.extend(batch)
            if len(batch) < 100:
                return found
        fail(self.path, 'La consulta GitHub excede el límite de paginación; no se asume una lista completa.')

    def branch_sha(self, branch):
        return self.api('git/ref/heads/' + quote(branch, safe=''))['object']['sha']


def github_name(path, remote):
    # La configuración cruda identifica GitHub incluso si Git aplica insteadOf.
    url = value(path, f'remote.{remote}.pushurl') or value(path, f'remote.{remote}.url') or ''
    matched = re.fullmatch(r'(?:git@github\.com:|https://github\.com/|ssh://git@github\.com/)([^/]+/[^/]+?)(?:\.git)?/?', url)
    if not matched:
        fail(path, f'El remoto {remote!r} no identifica inequívocamente un repositorio en github.com.')
    return matched[1]


def criteria(body, path):
    match = re.search(r'^## Criterios de aceptación\s*\n(.*?)(?=^## |\Z)', body or '', re.M | re.S)
    rows = re.findall(r'^- \[([ xX])\] (.+)$', match[1], re.M) if match else []
    if not rows:
        fail(path, 'El issue no tiene una sección de Criterios de aceptación con casillas.')
    # La explicación de verificación puede cambiar; el criterio sigue siendo el mismo.
    return [(f'A{i}', checked.lower() == 'x', text.split(' — ', 1)[0].strip())
            for i, (checked, text) in enumerate(rows, 1)]


def proof_from(body, path):
    blocks = re.findall(r'^```tunning-evidence\s*\n(.*?)^```\s*$', body or '', re.M | re.S)
    if len(blocks) != 1:
        fail(path, 'Falta un único bloque tunning-evidence en el issue; un push no demuestra sus criterios.')
    try:
        return json.loads(blocks[0])
    except ValueError:
        fail(path, 'El bloque tunning-evidence no contiene JSON válido.')


def successful_run(gh, run_id, sha, workflow):
    run = gh.api(f'actions/runs/{int(run_id)}')
    if (run.get('head_sha') != sha or run.get('status') != 'completed' or
            run.get('conclusion') != 'success' or run.get('path', '').split('@', 1)[0] != workflow):
        fail(gh.path, f'CI {run_id} no acredita {workflow} con éxito para el SHA {sha}.')
    return run


def check_criteria(gh, pr, issue_number, workflow='.github/workflows/tests.yml'):
    issue = gh.api(f'issues/{int(issue_number)}')
    rows = criteria(issue.get('body'), gh.path)
    pending = [number for number, done, _ in rows if not done]
    if pending:
        fail(gh.path, f'Issue #{issue_number}: criterios pendientes: {", ".join(pending)}.')
    proof = proof_from(issue.get('body'), gh.path)
    expected = {'schema': 1, 'repository': gh.repository, 'sha': pr['head']['sha'],
                'base_sha': pr['base']['sha'], 'criteria_sha256': digest(canonical([(n, t) for n, _, t in rows]))}
    if any(proof.get(key) != val for key, val in expected.items()):
        fail(gh.path, f'Issue #{issue_number}: evidencia obsoleta o de otro PR/base/criterio.')
    entries = proof.get('criteria', [])
    if (not isinstance(entries, list) or len(entries) != len(rows) or
            {e.get('id') for e in entries if isinstance(e, dict)} != {n for n, _, _ in rows}):
        fail(gh.path, 'La evidencia no cubre exactamente todos los criterios.')
    runs = set()
    for entry in entries:
        if not isinstance(entry.get('detail'), str) or not entry['detail'].strip() or not isinstance(entry.get('run'), int):
            fail(gh.path, f'Evidencia incompleta para {entry.get("id")}.')
        runs.add(entry['run'])
    for run_id in runs:
        successful_run(gh, run_id, pr['head']['sha'], workflow)
    return proof


def issue_for_pr(gh, pr):
    body = pr.get('body') or ''
    # Solo directivas completas, fuera de bloques de código y comentarios HTML.
    prose = re.sub(r'(?ms)^```.*?^```\s*$|<!--.*?-->', '', body)
    issues = set(re.findall(r'^Closes #(\d+)\s*$', prose, re.M | re.I))
    if len(issues) != 1:
        fail(gh.path, 'El PR necesita una única línea Closes #N con su issue de criterios.')
    return int(issues.pop())


def criteria_command():
    if not OPTIONS.repository or not OPTIONS.pr:
        fail(Path.cwd(), 'Usa --repository owner/repo --pr N.')
    gh = GitHub(Path.cwd(), OPTIONS.repository)
    pr = gh.api(f'pulls/{OPTIONS.pr}')
    issue_number = issue_for_pr(gh, pr)
    if OPTIONS.record:
        if not OPTIONS.run:
            fail(gh.path, '--record necesita --run con CI ya aprobado para el SHA vigente.')
        successful_run(gh, OPTIONS.run, pr['head']['sha'], '.github/workflows/tests.yml')
        issue = gh.api(f'issues/{issue_number}')
        rows = criteria(issue.get('body'), gh.path)
        entries = json.loads(OPTIONS.record.read_text())
        if (not isinstance(entries, list) or len(entries) != len(rows) or
                {e.get('id') for e in entries if isinstance(e, dict)} != {n for n, _, _ in rows} or
                any(not isinstance(e.get('detail'), str) or not e['detail'].strip() for e in entries)):
            fail(gh.path, '--record exige una explicación verificable para cada criterio; no se deduce del push.')
        proof = {'schema': 1, 'repository': gh.repository, 'sha': pr['head']['sha'],
                 'base_sha': pr['base']['sha'], 'criteria_sha256': digest(canonical([(n, t) for n, _, t in rows])),
                 'criteria': [dict(e, run=OPTIONS.run) for e in entries]}
        body = re.sub(r'(?ms)^```tunning-evidence\s*\n.*?^```\s*$', '', issue['body']).rstrip()
        section = re.search(r'^## Criterios de aceptación\s*\n(.*?)(?=^## |\Z)', body, re.M | re.S)
        checked = re.sub(r'^- \[[ xX]\]', '- [x]', section[1], flags=re.M)
        body = body[:section.start(1)] + checked + body[section.end(1):]
        body += '\n\n```tunning-evidence\n' + json.dumps(proof, ensure_ascii=False, indent=2) + '\n```\n'
        gh.api(f'issues/{issue_number}', 'PATCH', {'body': body})
    check_criteria(gh, pr, issue_number)
    print(f'Criterios y evidencia OK: {gh.repository} PR #{OPTIONS.pr}, issue #{issue_number}, {pr["head"]["sha"]}.')


def state_path(repo):
    common = git(repo.path, 'rev-parse', '--git-common-dir').stdout.removesuffix('\n')
    return (repo.path / common).resolve() / 'tunning-sync' / 'state.json'


def read_state(repo):
    path = state_path(repo)
    return json.loads(path.read_text()) if path.exists() else {}


def save_state(repo, data):
    path = state_path(repo)
    path.parent.mkdir(mode=0o700, exist_ok=True)
    with tempfile.NamedTemporaryFile(mode='w', dir=path.parent, delete=False) as tmp:
        json.dump(data, tmp, ensure_ascii=True, indent=2)
        temporary = Path(tmp.name)
    os.replace(temporary, path)


def pr_prepare(repo):
    repo.github = GitHub(repo.path, github_name(repo.path, repo.push_remote))
    metadata = repo.github.api()
    if metadata.get('archived') or not metadata.get('permissions', {}).get('push'):
        fail(repo.path, 'GitHub no permite publicar en este repositorio (sin permiso push o archivado).')
    repo.base = value(repo.path, 'tunning.prBase') or metadata['default_branch']
    repo.default_base = metadata['default_branch']
    git(repo.path, 'check-ref-format', f'refs/heads/{repo.base}')
    if repo.branch == repo.base or repo.branch == repo.default_base:
        fail(repo.path, f'La rama {repo.branch!r} es principal/base; prepara explícitamente una rama con git switch -c antes de syncPR.')
    repo.base_sha = repo.github.branch_sha(repo.base)
    repo.metadata = metadata
    repo.responsible = value(repo.path, 'tunning.responsible') or repo.github.repository.split('/')[0]
    if not re.fullmatch(r'[A-Za-z0-9-]+', repo.responsible):
        fail(repo.path, 'tunning.responsible debe ser un login de GitHub válido.')
    repo.github.api('assignees/' + repo.responsible)
    issue = OPTIONS.issue if repo.path == ROOT and OPTIONS.issue else value(repo.path, 'tunning.issue')
    repo.issue = int(issue) if issue else None
    if repo.issue:
        existing = repo.github.api(f'issues/{repo.issue}')
        receipt = read_state(repo).get('merged')
        resumed = (receipt and read_state(repo).get('issue') == repo.issue and
                   repo.github.api(f'pulls/{receipt["pr"]}').get('merged'))
        if existing.get('pull_request') or (existing.get('state') != 'open' and not resumed):
            fail(repo.path, f'Issue #{repo.issue} no es un issue abierto.')
        criteria(existing.get('body'), repo.path)


def pr_publish(repo):
    gh = repo.github
    sha = head(repo.path)
    repo.base_sha = gh.branch_sha(repo.base)
    comparison = gh.api('compare/' + quote(repo.base_sha, safe='') + '...' + quote(sha, safe=''))
    if not comparison.get('ahead_by') or not comparison.get('files'):
        print(f'=> [{label(repo.path)}] Sin diferencias con {repo.base}; no se crea PR.', flush=True)
        return
    query = urlencode({'state': 'open', 'head': gh.repository.split('/')[0] + ':' + repo.branch, 'base': repo.base})
    existing = gh.pages('pulls?' + query)
    if len(existing) > 1:
        fail(repo.path, 'Hay varios PR abiertos para la misma rama/base; resuelve la ambigüedad.')
    if existing:
        existing = existing[0]
        if repo.issue is None:
            repo.issue = issue_for_pr(gh, existing)
        elif issue_for_pr(gh, existing) != repo.issue:
            fail(repo.path, 'El PR existente está asociado a otro issue; no se reemplaza esa asociación.')
    if repo.issue is None:
        marker = '<!-- tunning-branch:' + digest(canonical([repo.branch, repo.base])) + ' -->'
        matches = [i for i in gh.pages('issues?state=open') if not i.get('pull_request') and marker in (i.get('body') or '')]
        if len(matches) > 1:
            fail(repo.path, 'Hay varios issues para la rama/base; configura tunning.issue.')
        issue = matches[0] if matches else gh.api('issues', 'POST', {
            'title': f'Sincronizar {repo.branch} hacia {repo.base}',
            'assignees': [repo.responsible],
            'body': marker + '\n\n## Criterios de aceptación\n\n- [ ] Pruebas acordadas aprobadas para el SHA vigente.\n- [ ] Cambios y referencias hijas revisados sin hallazgos pendientes.\n'})
        repo.issue = issue['number']
    gh.api(f'issues/{repo.issue}/assignees', 'POST', {'assignees': [repo.responsible]})
    children = [{'path': path, 'repository': child.github.repository, 'sha': head(child.path),
                 'pr': PRS.get(child.path, {}).get('number')} for path, _, _, _, child in repo.children]
    block = '<!-- tunning-sync:start -->\n' + f'Rama `{repo.branch}` → `{repo.base}`; SHA `{sha}`.\n\n'
    block += f'Closes #{repo.issue}\n\n'
    block += 'Dependencias hijas: ' + (json.dumps(children, ensure_ascii=True) if children else 'ninguna')
    block += '\n\nLos criterios, CI y la auditoría deben corresponder a este SHA y base.\n<!-- tunning-sync:end -->'
    if existing:
        body = existing.get('body') or ''
        # Conservar la descripción humana y su única referencia de cierre.
        block = block.replace(f'Closes #{repo.issue}\n\n', '')
        body = re.sub(r'<!-- tunning-sync:start -->.*?<!-- tunning-sync:end -->', '', body, flags=re.S).rstrip()
        if not re.search(rf'^Closes #{repo.issue}\s*$', body, re.M | re.I):
            body += f'\n\nCloses #{repo.issue}'
        pr = gh.api(f'pulls/{existing["number"]}', 'PATCH', {'body': body + '\n\n' + block})
    else:
        pr = gh.api('pulls', 'POST', {'head': repo.branch, 'base': repo.base,
                                    'title': f'Sincronizar {repo.branch}', 'body': block, 'draft': True})
    gh.api(f'issues/{pr["number"]}/assignees', 'POST', {'assignees': [repo.responsible]})
    PRS[repo.path] = pr
    state = read_state(repo)
    state.update({'schema': 1, 'path': str(repo.path), 'repository': gh.repository, 'branch': repo.branch,
                  'base': repo.base, 'sha': sha, 'base_sha': repo.base_sha, 'issue': repo.issue,
                  'pr': pr['number'], 'children': children,
                  'responsible': repo.responsible,
                  'implementer': {'provider': value(repo.path, 'tunning.implementerProvider'),
                                  'session': value(repo.path, 'tunning.implementerSession'),
                                  'identity': git(repo.path, 'log', '-1', '--format=%an <%ae>').stdout.strip()}})
    # No reciclar la aprobación de otro SHA/base, aunque quede un informe en disco.
    state.pop('audit', None)
    save_state(repo, state)


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
        if MODE in ('syncPR', 'syncPRmerge'):
            pr_prepare(self)

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


def external_path(repo, filename, purpose):
    path = Path(filename).expanduser().resolve()
    common = state_path(repo).parent.parent
    if path.is_relative_to(repo.path) or path.is_relative_to(common):
        fail(repo.path, f'{purpose} debe estar fuera del checkout y de su directorio Git.')
    return path


def audit_policy(repo):
    name = value(repo.path, 'tunning.prPolicy')
    if not name:
        fail(repo.path, 'Falta tunning.prPolicy: política externa de pruebas, checks e identidades auditoras.')
    path = external_path(repo, name, 'La política de auditoría')
    if path.stat().st_uid != os.getuid() or path.stat().st_mode & 0o022:
        fail(repo.path, 'La política debe pertenecer al usuario y no admitir escritura de grupo/otros.')
    raw = path.read_bytes()
    policy = json.loads(raw)
    commands = policy.get('commands')
    if (not isinstance(commands, list) or not commands or
            any(not isinstance(c, list) or not c or any(not isinstance(a, str) or not a for a in c) for c in commands)):
        fail(repo.path, 'La política debe acordar comandos de prueba como arrays de argumentos.')
    if not policy.get('checks') or not policy.get('auditors'):
        fail(repo.path, 'La política necesita checks e identidades/fingerprints de auditores autorizados.')
    policy['_sha256'] = digest(raw)
    return policy


def audit_snapshot(path):
    """Archivos propios y módulos inicializados; no staging, checkout ni refresh."""
    index = path / git(path, 'rev-parse', '--git-path', 'index').stdout.removesuffix('\n')
    result = {'head': head(path), 'index': digest(index.read_bytes()) if index.exists() else None, 'files': {}}
    children = links(path, committed=True)
    files = git(path, 'ls-files', '--cached', '--others', '--exclude-standard', '-z').stdout.split('\0')
    for filename in sorted(set(files) - {''}):
        entry = path / filename
        if filename in children:
            if not (entry / '.git').exists():
                fail(entry, 'La auditoría exige un módulo inicializado; no modifica checkouts para prepararlo.')
            result['files'][filename] = audit_snapshot(entry)
        elif entry.is_symlink():
            result['files'][filename] = ['symlink', os.readlink(entry)]
        elif entry.is_file():
            result['files'][filename] = [entry.stat().st_mode & 0o777, digest(entry.read_bytes())]
        else:
            result['files'][filename] = None
    return result


def audit_command(repo):
    # Auditoría aparte del flujo de implementación: no prepare/discover/sync.
    os.environ['GIT_OPTIONAL_LOCKS'] = '0'
    state = read_state(repo)
    if not state.get('pr') or not state.get('implementer', {}).get('provider'):
        fail(repo.path, 'Primero el implementador debe publicar syncPR y registrar proveedor/sesión.')
    if not all((OPTIONS.output, OPTIONS.provider, OPTIONS.session, OPTIONS.environment, OPTIONS.signing_key)):
        fail(repo.path, 'Auditoría: usa --output, --provider, --session, --environment y --signing-key.')
    if not OPTIONS.approve and not OPTIONS.findings:
        fail(repo.path, 'Declara --approve tras revisar, o --findings con hallazgos; los tests no deciden la revisión.')
    output = external_path(repo, OPTIONS.output, 'El informe')
    if output.exists() or Path(str(output) + '.asc').exists():
        fail(repo.path, 'El informe o su firma ya existen; usa otra ruta para conservar la evidencia.')
    policy = audit_policy(repo)
    signer = policy['auditors'].get(OPTIONS.signing_key.upper())
    if (not signer or signer.get('provider') != OPTIONS.provider or not signer.get('identity') or
            OPTIONS.provider == state['implementer']['provider'] or OPTIONS.session == state['implementer']['session']):
        fail(repo.path, 'La política no autoriza a este auditor independiente/proveedor/sesión.')
    gh = GitHub(repo.path, state['repository'])
    pr = gh.api(f'pulls/{state["pr"]}')
    if (pr.get('merged') or pr.get('state') != 'open' or head(repo.path) != state['sha'] or
            pr['head']['sha'] != state['sha'] or pr['base']['sha'] != state['base_sha']):
        fail(repo.path, 'El manifiesto/PR cambió antes de la auditoría; el implementador debe preparar la versión vigente.')
    clean(repo)
    issue = gh.api(f'issues/{state["issue"]}')
    rows = criteria(issue.get('body'), repo.path)
    findings = json.loads(external_path(repo, OPTIONS.findings, 'Los hallazgos').read_text()) if OPTIONS.findings else []
    if not isinstance(findings, list) or (OPTIONS.approve and findings):
        fail(repo.path, 'Hallazgos deben ser un array; --approve requiere cero hallazgos.')
    before, results = audit_snapshot(repo.path), []
    for command in policy['commands']:
        try:
            run = subprocess.run(command, cwd=repo.path, env={**os.environ, 'PYTHONDONTWRITEBYTECODE': '1'},
                                 capture_output=True, timeout=policy.get('timeout_seconds', 600))
            results.append({'argv': command, 'returncode': run.returncode,
                            'log_sha256': digest(run.stdout + b'\n' + run.stderr)})
        except subprocess.TimeoutExpired:
            results.append({'argv': command, 'returncode': 124, 'log_sha256': digest(b'timeout')})
        except OSError as error:
            results.append({'argv': command, 'returncode': 127, 'log_sha256': digest(str(error).encode())})
    try:
        unchanged = audit_snapshot(repo.path) == before
    except (SyncError, OSError):
        unchanged = False
    report = {'schema': 1, 'repository': state['repository'], 'sha': state['sha'], 'base_sha': state['base_sha'],
              'children': links(repo.path, committed=True), 'pr': state['pr'], 'issue': state['issue'],
              'criteria_sha256': digest(canonical([(n, t) for n, _, t in rows])), 'policy_sha256': policy['_sha256'],
              'implementer': state['implementer'],
              'auditor': {'provider': OPTIONS.provider, 'session': OPTIONS.session, 'environment': OPTIONS.environment,
                          'identity': signer['identity']},
              'tests': results, 'findings': findings, 'unchanged': unchanged,
              'review_approved': OPTIONS.approve, 'timestamp': datetime.datetime.now(datetime.timezone.utc).isoformat()}
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open('x', encoding='utf-8') as destination:
        json.dump(report, destination, ensure_ascii=True, indent=2)
    output.chmod(0o600)
    signed = subprocess.run(['gpg', '--batch', '--local-user', OPTIONS.signing_key, '--armor', '--detach-sign',
                             '--output', str(output) + '.asc', str(output)], capture_output=True)
    if signed.returncode:
        fail(repo.path, f'No se pudo firmar el informe {output}; se conserva sin aprobar.')
    print(f'Informe de auditoría: {output}; firma: {output}.asc; sin cambios: {unchanged}.')
    if not unchanged or findings or not OPTIONS.approve or any(t['returncode'] for t in results):
        fail(repo.path, 'Auditoría fallida; informe conservado. El auditor no corrige ni revierte el código.')


def verified_audit(repo, pr, policy):
    filename = value(repo.path, 'tunning.auditReport')
    if not filename:
        fail(repo.path, 'Falta tunning.auditReport: se requiere auditoría independiente firmada para este SHA.')
    report_path = external_path(repo, filename, 'El informe')
    signature = Path(str(report_path) + '.asc')
    result = subprocess.run(['gpg', '--batch', '--no-auto-key-retrieve', '--status-fd=1',
                             '--verify', str(signature), str(report_path)], capture_output=True, text=True)
    valid = [line.split()[2:] for line in result.stdout.splitlines() if line.startswith('[GNUPG:] VALIDSIG ')]
    bad = any('[GNUPG:] ' + token in result.stdout for token in ('EXPKEYSIG', 'EXPSIG', 'REVKEYSIG', 'BADSIG', 'ERRSIG'))
    if result.returncode or bad or len(valid) != 1:
        fail(repo.path, 'Firma de auditoría inválida, expirada o revocada; no se importan claves del informe.')
    fingerprint = valid[0][-1] if len(valid[0]) >= 10 else valid[0][0]
    identity = policy['auditors'].get(fingerprint)
    if not identity:
        fail(repo.path, 'El firmante no está autorizado por la política local de auditoría.')
    report = json.loads(report_path.read_text())
    expected = {'schema': 1, 'repository': repo.github.repository, 'sha': head(repo.path),
                'base_sha': pr['base']['sha'], 'children': links(repo.path, committed=True),
                'pr': pr['number'], 'issue': repo.issue, 'policy_sha256': policy['_sha256']}
    if any(report.get(key) != val for key, val in expected.items()):
        fail(repo.path, 'Auditoría obsoleta: cambió SHA, base, hijos, PR, issue o política.')
    auditor = report.get('auditor', {})
    implementer = read_state(repo).get('implementer', {})
    if (not implementer.get('provider') or not implementer.get('session') or
            auditor.get('provider') != identity.get('provider') or auditor.get('identity') != identity.get('identity') or
            not auditor.get('session') or not auditor.get('environment') or
            auditor.get('provider') == implementer['provider'] or auditor.get('session') == implementer['session']):
        fail(repo.path, 'Se necesita un auditor autorizado de otro proveedor y sesión independiente.')
    if report.get('implementer') != implementer:
        fail(repo.path, 'La identidad del implementador no coincide con el manifiesto vigente.')
    results = report.get('tests', [])
    if ([t.get('argv') for t in results] != policy['commands'] or
            any(t.get('returncode') != 0 or not re.fullmatch(r'[a-f0-9]{64}', t.get('log_sha256', '')) for t in results) or
            report.get('findings') != [] or report.get('unchanged') is not True or report.get('review_approved') is not True):
        fail(repo.path, 'Auditoría con hallazgos, cambios de código o suites incompletas/fallidas.')
    return {'fingerprint': fingerprint, 'report_sha256': digest(report_path.read_bytes()), 'report': report}


def merge_checks(repo, pr, policy):
    gh = repo.github
    if pr.get('draft') or pr.get('mergeable') is not True or pr.get('mergeable_state') not in ('clean', 'unstable', 'has_hooks'):
        fail(repo.path, 'PR borrador, con conflicto o estado de integración sin resolver.')
    checks = gh.pages(f'commits/{pr["head"]["sha"]}/check-runs?filter=latest', 'check_runs')
    statuses = gh.pages(f'commits/{pr["head"]["sha"]}/statuses')
    latest = {}
    for status in statuses:
        latest.setdefault(status['context'], status['state'])
    observed = {c['name']: c.get('conclusion') if c.get('status') == 'completed' else 'pending' for c in checks}
    observed.update(latest)
    if not observed or any(s != 'success' for s in observed.values()):
        fail(repo.path, 'Checks pendientes, fallidos, omitidos o ausentes; no se fusiona.')
    missing = set(policy['checks']) - set(observed)
    if missing:
        fail(repo.path, 'Faltan checks acordados: ' + ', '.join(sorted(missing)))
    reviews = gh.pages(f'pulls/{pr["number"]}/reviews')
    by_user = {}
    for review in reviews:
        if review.get('state') in ('APPROVED', 'CHANGES_REQUESTED', 'DISMISSED'):
            by_user[review['user']['login']] = review
    if any(r['state'] == 'CHANGES_REQUESTED' for r in by_user.values()):
        fail(repo.path, 'Hay una revisión de GitHub que solicita cambios.')
    approved = {u for u, r in by_user.items() if r['state'] == 'APPROVED' and
                r.get('commit_id') == pr['head']['sha'] and u != pr.get('user', {}).get('login')}
    if not set(policy.get('reviewers', [])) <= approved:
        fail(repo.path, 'Faltan revisiones acordadas sobre el SHA actual.')
    # GitHub aplica también protecciones/rulesets, equipos y CODEOWNERS en el
    # endpoint de merge normal; nunca se solicita admin override.


def merge_tree(repo):
    for _, _, _, _, child in repo.children:
        merge_tree(child)
    current_links = links(repo.path, committed=True)
    if any(current_links.get(path) != head(child.path) for path, _, _, _, child in repo.children):
        sync(repo)
        fail(repo.path, 'Las fusiones hijas cambiaron referencias: nuevo commit padre publicado; necesita nuevas pruebas y auditoría antes de fusionar.')
    state = read_state(repo)
    receipt = state.get('merged')
    if repo.path not in PRS:
        if receipt:
            merged = repo.github.api(f'pulls/{receipt["pr"]}')
            if not merged.get('merged') or merged.get('merge_commit_sha') != receipt['sha']:
                fail(repo.path, 'El progreso guardado no coincide con una fusión real en GitHub.')
            repo.ensure_commit(receipt['sha'], repo.push_url)
            if not ancestor(repo.path, receipt['sha'], head(repo.path)):
                fail(repo.path, 'El resultado de la fusión guardada no está integrado en la rama activa.')
            MERGED[repo.path] = receipt
        return
    gh = repo.github
    pr = gh.api(f'pulls/{PRS[repo.path]["number"]}')
    if pr.get('merged'):
        fail(repo.path, 'El PR ya fue fusionado fuera de esta ejecución; vuelve a sincronizar y validar su resultado.')
    if pr['head']['sha'] != head(repo.path) or pr['base']['ref'] != repo.base:
        fail(repo.path, 'El PR cambió de SHA/base después de publicarlo.')
    policy = audit_policy(repo)
    proof = check_criteria(gh, pr, repo.issue, policy.get('workflow', '.github/workflows/tests.yml'))
    audit = verified_audit(repo, pr, policy)
    if audit['report'].get('criteria_sha256') != proof['criteria_sha256']:
        fail(repo.path, 'La auditoría no cubre los criterios vigentes del issue.')
    merge_checks(repo, pr, policy)
    method = policy.get('merge_method', 'merge')
    allowed_key = 'allow_merge_commit' if method == 'merge' else f'allow_{method}_merge'
    if method not in ('merge', 'squash', 'rebase') or not repo.metadata.get(allowed_key):
        fail(repo.path, f'Método de merge {method!r} no permitido por la política o GitHub.')
    if method == 'rebase' and git(repo.path, 'rev-list', '--min-parents=2', pr['base']['sha'] + '..' + pr['head']['sha']).stdout.strip():
        fail(repo.path, 'Rebase necesita historia lineal del PR; elige merge/squash o resuélvelo explícitamente.')
    rebase_count = int(git(repo.path, 'rev-list', '--count', pr['base']['sha'] + '..' + pr['head']['sha']).stdout)
    audited_tree = git(repo.path, 'rev-parse', 'HEAD^{tree}').stdout.strip()
    clean(repo)
    fresh = gh.api(f'pulls/{pr["number"]}')
    remote = heads(repo.path, repo.push_url, f'refs/heads/{repo.branch}', f'refs/heads/{repo.base}')
    if (fresh['head']['sha'] != pr['head']['sha'] or fresh['base']['sha'] != pr['base']['sha'] or
            remote.get(f'refs/heads/{repo.branch}') != pr['head']['sha'] or
            remote.get(f'refs/heads/{repo.base}') != pr['base']['sha'] or head(repo.path) != pr['head']['sha'] or
            links(repo.path, committed=True) != audit['report']['children']):
        fail(repo.path, 'HEAD/base/referencias cambiaron justo antes de fusionar; evidencia invalidada.')
    result = gh.api(f'pulls/{pr["number"]}/merge', 'PUT', {'sha': pr['head']['sha'], 'merge_method': method})
    if not result.get('merged') or not result.get('sha'):
        fail(repo.path, 'GitHub rechazó la fusión; los ancestros se detienen.')
    receipt = {'pr': pr['number'], 'sha': result['sha'], 'head_sha': pr['head']['sha'], 'base_sha': pr['base']['sha']}
    state['merged'], state['audit'] = receipt, audit
    save_state(repo, state)  # La fusión remota no se deshace si falla un paso posterior.
    MERGED[repo.path] = receipt
    repo.ensure_commit(result['sha'], repo.push_url)
    parents = git(repo.path, 'log', '-1', '--format=%P', result['sha']).stdout.split()
    expected_base = (parents == [pr['base']['sha'], pr['head']['sha']] if method == 'merge' else
                     parents == [pr['base']['sha']] if method == 'squash' else
                     git(repo.path, 'rev-parse', result['sha'] + '~' + str(rebase_count)).stdout.strip() == pr['base']['sha'])
    if not expected_base or git(repo.path, 'rev-parse', result['sha'] + '^{tree}').stdout.strip() != audited_tree:
        fail(repo.path, 'La base o el contenido cambió durante la fusión remota; se guardó el resultado, pero se detienen sus padres.')
    if ancestor(repo.path, head(repo.path), result['sha']):
        git(repo.path, 'merge', '--ff-only', result['sha'], stream=True)
    else:
        # Squash/rebase conserva los commits originales y la rama activa:
        # integra el resultado remoto mediante un merge firmado, sin reset.
        integrate(repo, ['merge', '--no-edit', '--no-autostash', *repo.sign, result['sha']], f'resultado {method} de PR #{pr["number"]}')
    if git(repo.path, 'rev-parse', 'HEAD^{tree}').stdout.strip() != audited_tree:
        fail(repo.path, 'Integrar la fusión cambió el contenido auditado; se conserva el trabajo y se detienen sus padres.')
    clean(repo)
    for path, _, _, urls, child in repo.children:
        verify_reference(child, links(repo.path, committed=True)[path], urls)
    git(repo.path, 'push', '--recurse-submodules=check', '--', repo.push_remote,
        f'HEAD:refs/heads/{repo.branch}', stream=True)
    if heads(repo.path, repo.push_url, f'refs/heads/{repo.branch}').get(f'refs/heads/{repo.branch}') != head(repo.path):
        fail(repo.path, 'La rama de trabajo no coincide con su publicación tras integrar la fusión.')
    PUBLISHED[repo.path] = (head(repo.path), repo.push_remote, repo.branch)


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
    if MODE in ('syncPR', 'syncPRmerge'):
        base_sha = repo.github.branch_sha(repo.base)
        repo.ensure_commit(base_sha, repo.push_url)
        if not ancestor(repo.path, base_sha, head(repo.path)):
            integrate(repo, ['merge', '--no-edit', '--no-autostash', *repo.sign, base_sha], f'base PR {repo.base}')
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
    if MODE in ('syncPR', 'syncPRmerge'):
        pr_publish(repo)


def summary(title):
    print(title, flush=True)
    for path, (oid, remote, branch) in PUBLISHED.items():
        created = ', '.join(commit[:12] for commit in REPOS[path].created) or 'ninguno'
        print(f'  [{label(path)}] {remote}/{branch} -> {oid[:12]}; commits creados: {created}', flush=True)
        if path in PRS:
            repo = REPOS[path]
            print(f'    base: {repo.base}; issue #{repo.issue}; PR {PRS[path]["html_url"]}', flush=True)
    for path, receipt in MERGED.items():
        print(f'  [{label(path)}] PR #{receipt["pr"]} fusionado: {receipt["sha"]}; progreso guardado.', flush=True)


try:
    if MODE == 'criteria':
        criteria_command()
        sys.exit(0)
    if MODE not in ('sync', 'syncPR', 'syncPRmerge', 'audit'):
        fail(Path.cwd(), f'Modo desconocido: {MODE}.')
    ROOT = Path(git(Path.cwd(), 'rev-parse', '--show-toplevel').stdout.removesuffix('\n')).resolve()
    if MODE == 'audit':
        audit_command(Repo(ROOT))
        sys.exit(0)
    print('=> Validando repositorios y submódulos antes de confirmar cambios...', flush=True)
    root = prepare(ROOT)
    sync(root)
    if MODE == 'syncPRmerge':
        merge_tree(root)
    for path, (oid, _, _) in PUBLISHED.items():
        if head(path) != oid:
            fail(path, 'HEAD cambió después de la publicación.')
        clean(REPOS[path])
    summary(f'Sincronizados {len(PUBLISHED)} repositorios:')
except (SyncError, OSError, ValueError, KeyError, TypeError) as error:
    print(f'git {MODE}: {error}', file=sys.stderr, flush=True)
    if PUBLISHED:
        summary('Publicaciones completadas antes del error (sincronización incompleta):')
    sys.exit(1)
except KeyboardInterrupt:
    print('git sync: Interrumpido; los padres pendientes no se publicaron.', file=sys.stderr)
    sys.exit(130)
PY
