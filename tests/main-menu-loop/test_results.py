"""Exercise final result reporting from both real worker implementations.

Run without arguments for the PR installer, or pass a standalone run.sh path.
All system operations are replaced by shell functions in a temporary sandbox.
"""
from pathlib import Path
import os
import subprocess
import sys
import tempfile
import unittest

SHELL = 'C:/Program Files/Git/bin/bash.exe' if os.name == 'nt' else '/bin/sh'
SOURCE = Path(sys.argv.pop(1)) if len(sys.argv) > 1 else Path(__file__).resolve().parents[2] / 'main-menu-loop.sh'
SOURCE = SOURCE.read_text()
STANDALONE = 'mzd_finish()' in SOURCE


class Results(unittest.TestCase):
    def run_case(self, body, cleanup=False, record_failure=False):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            if STANDALONE:
                functions = SOURCE[SOURCE.index('mzd_report_message()'):SOURCE.index('# --- Local system helpers')]
                setup = """
MZD_REPORT=$PWD/report
MZD_CLEANUP=test_cleanup
MZD_SUCCESS='install completed. Other changes were preserved.'
test_cleanup() { return CLEANUP_RESULT; }
trap mzd_finish 0
""".replace('CLEANUP_RESULT', '1' if cleanup else '0')
                body = body.replace('FAIL', 'mzd_fail').replace('FATAL', 'mzd_fatal')
            else:
                functions = SOURCE[SOURCE.index('fail() {'):SOURCE.index('trap finish 0')].replace('/jci/tools/jci-dialog', 'test_dialog')
                setup = """
REPORT=$PWD/report
ROOT_CHANGED=CLEANUP_RESULT
WATCHDOG_CHANGED=0
LOCKED=0
UI=0
TITLE=test
SUCCESS='install completed. Other changes were preserved.'
FAILURE=''
CRITICAL=0
mount() { return 1; }
test_dialog() { printf 'GUI:%s\\n' \"$1\" >&4; }
killall() { :; }
reboot() { printf 'REBOOT\\n' >&4; }
trap finish 0
""".replace('CLEANUP_RESULT', '1' if cleanup else '0')
                body = body.replace('FAIL', 'fail').replace('FATAL', 'fatal')
            script = root / 'case.sh'
            script.write_text('#!/bin/sh\nset -u\nmkdir report\nexec 3>&1 4>&2\nexec > report/run.log 2>&1\nsync() { :; }\n' + functions + setup + ('mkdir report/status.txt\n' if record_failure else '') + body + '\n', encoding='utf-8', newline='\n')
            result = subprocess.run([SHELL, script.as_posix()], cwd=root, capture_output=True, text=True, timeout=20)
            status = root / 'report/status.txt'
            recorded = status.read_text() if status.is_file() else None
            return result, recorded

    def test_success(self):
        result, recorded = self.run_case('exit 0')
        self.assertEqual(result.returncode, 0)
        self.assertIn('install completed', result.stdout)
        self.assertEqual(result.stderr, '')
        self.assertEqual(recorded, 'exit_code=0\n')

    def test_interrupted_mutation_is_critical(self):
        result, recorded = self.run_case('ACTION=install; exit 143')
        self.assertEqual(result.returncode, 2)
        self.assertEqual(result.stdout, '')
        self.assertIn('Do NOT reboot', result.stderr)
        self.assertEqual(recorded, 'exit_code=2\n')

    def test_safe_failure(self):
        result, recorded = self.run_case("FAIL 'Write failed; the previous file was restored.'")
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout, '')
        self.assertIn('previous file was restored', result.stderr)
        self.assertEqual(recorded, 'exit_code=1\n')

    def test_critical_failure(self):
        # Standalone helpers can fail inside a subshell; preserve severity even
        # when the outer caller converts its exit status to 1.
        result, recorded = self.run_case("( FATAL 'Write AND rollback failed. Do NOT reboot.' ) || exit 1" if STANDALONE else "FATAL 'Write AND rollback failed. Do NOT reboot.'")
        self.assertEqual(result.returncode, 2)
        self.assertEqual(result.stdout, '')
        self.assertIn('Do NOT reboot', result.stderr)
        self.assertEqual(recorded, 'exit_code=2\n')

    def test_cleanup_failure_suppresses_success(self):
        result, recorded = self.run_case('exit 0', cleanup=True)
        self.assertEqual(result.returncode, 2)
        self.assertEqual(result.stdout, '')
        self.assertIn('Do NOT reboot', result.stderr)
        self.assertEqual(recorded, 'exit_code=2\n')

    def test_unexplained_failure_is_reported(self):
        result, recorded = self.run_case('exit 1')
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout, '')
        self.assertIn('Operation failed', result.stderr)

    def test_result_record_failure_suppresses_success(self):
        result, recorded = self.run_case('exit 0', record_failure=True)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout, '')
        self.assertIn('Cannot save the final result', result.stderr)

    def test_status_only_after_successful_cleanup(self):
        body = "MZD_SUCCESS=''; MZD_STATUS=installed; exit 0" if STANDALONE else "SUCCESS=''; STATUS_RESULT=installed; exit 0"
        result, recorded = self.run_case(body)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout, 'installed\n')
        result, recorded = self.run_case(body, cleanup=True)
        self.assertEqual(result.returncode, 2)
        self.assertEqual(result.stdout, '')
        self.assertIn('Do NOT reboot', result.stderr)

    @unittest.skipIf(STANDALONE, 'Standalone workers never open GUI dialogs')
    def test_gui_cleanup_failure_never_offers_reboot(self):
        result, _ = self.run_case('UI=1; OFFER_REBOOT=1; exit 0', cleanup=True)
        self.assertEqual(result.returncode, 2)
        self.assertEqual(result.stdout, '')
        self.assertIn('GUI:--info', result.stderr)
        self.assertNotIn('GUI:--question', result.stderr)
        self.assertNotIn('REBOOT', result.stderr)

    @unittest.skipIf(STANDALONE, 'Standalone workers never open GUI dialogs')
    def test_gui_success_can_offer_reboot(self):
        result, _ = self.run_case('UI=1; OFFER_REBOOT=1; exit 0')
        self.assertEqual(result.returncode, 0)
        self.assertIn('GUI:--question', result.stderr)
        self.assertIn('REBOOT', result.stderr)


if __name__ == '__main__':
    unittest.main(verbosity=2)
