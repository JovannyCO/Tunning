#!/usr/bin/env python3
"""Verifica el checkout y reparte las pruebas locales entre procesos aislados."""
import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys
import tempfile
import threading
import time
import unittest

ROOT = Path(__file__).resolve().parent.parent
TESTS = ROOT / 'tests'
VERIFY = ROOT / 'scripts/verify.py'


def available_cpus():
    try:
        return len(os.sched_getaffinity(0)) or 1
    except (AttributeError, OSError):
        return os.cpu_count() or 1


def positive_jobs(value):
    try:
        jobs = int(value)
    except ValueError as error:
        raise argparse.ArgumentTypeError('--jobs debe ser un entero positivo') from error
    if jobs < 1:
        raise argparse.ArgumentTypeError('--jobs debe ser un entero positivo')
    return jobs


def test_ids(tests_dir, pattern):
    """Mantiene el descubrimiento de unittest y evita ejecutar un caso dos veces."""
    old_path = sys.path[:]
    old_bytecode = sys.dont_write_bytecode
    sys.dont_write_bytecode = True
    try:
        loader = unittest.TestLoader()
        suite = loader.discover(str(tests_dir), pattern=pattern,
                                top_level_dir=str(tests_dir))
        if loader.errors:
            raise ValueError('\n'.join(loader.errors))

        def flatten(group):
            for case in group:
                if isinstance(case, unittest.TestSuite):
                    yield from flatten(case)
                else:
                    yield case.id()

        return list(dict.fromkeys(flatten(suite)))
    finally:
        sys.path[:] = old_path
        sys.dont_write_bytecode = old_bytecode


def run_command(command, cwd, log_path, label, emit):
    started = time.monotonic()
    reported_count = None
    env = {**os.environ, 'PYTHONDONTWRITEBYTECODE': '1'}
    with log_path.open('w') as log:
        log.write(shlex.join(command) + '\n')
        log.flush()
        try:
            with subprocess.Popen(command, cwd=cwd, env=env, stdout=subprocess.PIPE,
                                  stderr=subprocess.STDOUT, text=True, bufsize=1) as process:
                for line in process.stdout:
                    log.write(line)
                    log.flush()
                    emit(f'[{label}] {line.rstrip()}')
                    match = re.fullmatch(r'Ran (\d+) tests? in .+\n?', line)
                    if match:
                        reported_count = int(match[1])
                returncode = process.wait()
        except OSError as error:
            message = f'No se pudo ejecutar {command[0]}: {error}'
            log.write(message + '\n')
            emit(f'[{label}] {message}')
            returncode = 1
    return {'label': label, 'command': command, 'returncode': returncode,
            'seconds': round(time.monotonic() - started, 3),
            'tests_run': reported_count, 'log': str(log_path)}


def main(argv=None, *, tests_dir=TESTS, verify_script=VERIFY):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--jobs', '-j', type=positive_jobs,
                        default=min(8, available_cpus()),
                        help='procesos de pruebas (por defecto: CPU disponibles, máximo 8)')
    parser.add_argument('--pattern', default='test_*.py',
                        help='patrón de módulos para repetir pruebas (por defecto: test_*.py)')
    args = parser.parse_args(argv)
    started = time.monotonic()
    tests_dir = Path(tests_dir).resolve()
    log_dir = Path(tempfile.mkdtemp(prefix='tunning-tests-', dir='/tmp'))
    print_lock = threading.Lock()

    def emit(message):
        with print_lock:
            print(message, flush=True)

    summary = {'tests_dir': str(tests_dir), 'pattern': args.pattern,
               'requested_jobs': args.jobs, 'results': []}

    def finish(returncode):
        summary['returncode'] = returncode
        summary['seconds'] = round(time.monotonic() - started, 3)
        (log_dir / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
        emit(f"Resultado: {'OK' if returncode == 0 else 'FALLO'}; "
             f"{summary['seconds']:.3f} s; registros: {log_dir}")
        return returncode

    emit(f'Registros: {log_dir}')
    verification = run_command([sys.executable, str(verify_script)], ROOT,
                               log_dir / 'verify.log', 'verificación', emit)
    summary['results'].append(verification)
    if verification['returncode']:
        return finish(1)
    try:
        ids = test_ids(tests_dir, args.pattern)
    except Exception as error:
        summary['discovery_error'] = str(error)
        emit(f'Error al descubrir pruebas: {error}')
        return finish(1)
    summary['tests_discovered'] = len(ids)
    if not ids:
        emit(f'No se encontraron pruebas para {args.pattern}.')
        return finish(1)
    jobs = min(args.jobs, len(ids))
    summary['jobs'] = jobs
    emit(f'{len(ids)} pruebas; {jobs} procesos; {available_cpus()} CPU disponibles.')
    failed = False
    with ThreadPoolExecutor(max_workers=jobs) as pool:
        pending = {}
        for index in range(jobs):
            assigned = ids[index::jobs]
            command = [sys.executable, '-m', 'unittest', '-v', *assigned]
            label = f'proceso {index + 1}'
            future = pool.submit(run_command, command, tests_dir,
                                 log_dir / f'worker-{index + 1}.log', label, emit)
            pending[future] = assigned
        for future in as_completed(pending):
            result = future.result()
            result['tests_assigned'] = pending[future]
            if result['tests_run'] != len(pending[future]):
                result['count_error'] = 'El proceso no terminó todas las pruebas asignadas.'
                emit(f"[{result['label']}] {result['count_error']}")
                failed = True
            failed = failed or bool(result['returncode'])
            summary['results'].append(result)
            emit(f"[{result['label']}] código {result['returncode']}; {result['seconds']:.3f} s")
    return finish(1 if failed else 0)


if __name__ == '__main__':
    raise SystemExit(main())
