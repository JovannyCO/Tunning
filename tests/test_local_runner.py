"""Regresiones del runner con módulos mínimos, sin invocar la suite recursivamente."""
from contextlib import redirect_stdout
import importlib.util
import io
import json
from pathlib import Path
import shutil
import sys
import tempfile
import unittest
from unittest.mock import patch

REPO = Path(__file__).resolve().parent.parent
SPEC = importlib.util.spec_from_file_location('tunning_local_runner', REPO / 'scripts/test-local.py')
RUNNER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RUNNER)


class LocalRunnerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='tunning-runner-fixture-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.tests = self.root / 'tests'
        self.tests.mkdir()
        self.verify = self.root / 'verify.py'
        self.verify.write_text('print("fixture verification OK")\n')
        self.module = 'test_' + self.root.name.replace('-', '_')
        self.addCleanup(lambda: sys.modules.pop(self.module, None))

    def write_tests(self, methods):
        (self.tests / (self.module + '.py')).write_text(
            'import unittest\nfrom pathlib import Path\n'
            'class Cases(unittest.TestCase):\n' + methods)

    def run_fixture(self, *args):
        output = io.StringIO()
        with redirect_stdout(output):
            returncode = RUNNER.main(args, tests_dir=self.tests, verify_script=self.verify)
        directory = Path(output.getvalue().splitlines()[0].removeprefix('Registros: '))
        self.addCleanup(lambda: shutil.rmtree(directory))
        summary = json.loads((directory / 'summary.json').read_text())
        return returncode, summary, output.getvalue(), directory

    def test_every_discovered_case_runs_once_across_workers(self):
        markers = self.root / 'markers'
        markers.mkdir()
        methods = ''.join(
            f'    def test_case_{index}(self):\n'
            f'        with open({str(markers / str(index))!r}, "a") as marker:\n'
            '            marker.write("run\\n")\n'
            for index in range(9))
        self.write_tests(methods)
        returncode, summary, output, directory = self.run_fixture('--jobs', '8')
        self.assertEqual(returncode, 0, output)
        self.assertEqual(summary['jobs'], 8)
        self.assertEqual(summary['tests_discovered'], 9)
        workers = summary['results'][1:]
        assigned = [test for worker in workers for test in worker['tests_assigned']]
        self.assertEqual(len(assigned), len(set(assigned)))
        self.assertEqual(sum(worker['tests_run'] for worker in workers), 9)
        self.assertEqual(len(list(markers.iterdir())), 9)
        self.assertTrue(all(marker.read_text() == 'run\n' for marker in markers.iterdir()))
        self.assertTrue(all(Path(worker['log']).parent == directory for worker in workers))
        self.assertFalse(directory.is_relative_to(REPO))

    def test_worker_failure_returns_failure_with_visible_traceback(self):
        self.write_tests('    def test_failure(self):\n        self.fail("fixture failure")\n'
                         '    def test_success(self):\n        self.assertTrue(True)\n')
        returncode, summary, output, _ = self.run_fixture('--jobs', '2')
        self.assertEqual(returncode, 1)
        self.assertEqual(sum(worker['tests_run'] for worker in summary['results'][1:]), 2)
        self.assertTrue(any(worker['returncode'] for worker in summary['results'][1:]))
        self.assertIn('AssertionError: fixture failure', output)
        self.assertIn('Resultado: FALLO', output)

    def test_success_exit_without_completing_unittest_cannot_report_success(self):
        self.write_tests('    def test_a_exit(self):\n        __import__("os")._exit(0)\n'
                         '    def test_b_never(self):\n        self.fail("must not run")\n')
        returncode, summary, output, _ = self.run_fixture('--jobs', '1')
        self.assertEqual(returncode, 1)
        worker = summary['results'][1]
        self.assertEqual(worker['returncode'], 0)
        self.assertIsNone(worker['tests_run'])
        self.assertEqual(len(worker['tests_assigned']), 2)
        self.assertIn('count_error', worker)
        self.assertIn('no terminó todas las pruebas asignadas', output)
        self.assertIn('Resultado: FALLO', output)

    def test_failed_verification_stops_before_running_tests(self):
        self.verify.write_text('raise SystemExit(3)\n')
        self.write_tests('    def test_never(self):\n        self.fail("must not run")\n')
        returncode, summary, output, _ = self.run_fixture()
        self.assertEqual(returncode, 1)
        self.assertEqual(len(summary['results']), 1)
        self.assertEqual(summary['results'][0]['returncode'], 3)
        self.assertNotIn('must not run', output)

    def test_empty_discovery_cannot_report_success(self):
        returncode, summary, output, _ = self.run_fixture()
        self.assertEqual(returncode, 1)
        self.assertEqual(summary['tests_discovered'], 0)
        self.assertIn('No se encontraron pruebas', output)

    def test_invalid_jobs_are_rejected_before_any_command(self):
        for value in ('0', '-2', 'text'):
            with self.subTest(value=value), patch.object(RUNNER, 'run_command') as command:
                with self.assertRaises(SystemExit) as error, patch('sys.stderr', io.StringIO()):
                    RUNNER.main(['--jobs', value])
                self.assertEqual(error.exception.code, 2)
                command.assert_not_called()


if __name__ == '__main__':
    unittest.main(verbosity=2)
