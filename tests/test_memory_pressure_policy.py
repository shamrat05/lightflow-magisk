from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class MemoryPressurePolicyTests(unittest.TestCase):
    def test_apply_reports_pressure_without_killing_or_writing_state(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            meminfo = base / 'meminfo'
            meminfo.write_text('MemAvailable: 400000 kB\nSwapTotal: 100 kB\nSwapFree: 0 kB\n')
            psi = base / 'psi'
            psi.write_text('full avg10=99.0\n')
            source = (ROOT / 'module/memory-pressure-policy.sh').read_text()
            source = source.replace('/proc/meminfo', str(meminfo)).replace('/proc/pressure/memory', str(psi))
            script = base / 'policy.sh'
            script.write_text(source)
            result = subprocess.run(['/system/bin/sh', str(script), 'apply'],
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('no shell cleanup or kill timer', result.stdout)
            self.assertIn('400000', result.stdout)
            self.assertNotIn('am kill', source)

    def test_retired_watchdog_status_leaves_pid_file_and_skips_process_scan(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            pid_file = base / 'watchdog.pid'
            pid_file.write_text('123\n')
            scan = base / 'scan'
            fake_ps = base / 'ps'
            fake_ps.write_text(f'#!/system/bin/sh\ntouch "{scan}"\n')
            fake_ps.chmod(0o755)
            source = (ROOT / 'module/memory-watchdog.sh').read_text()
            script = base / 'watchdog.sh'
            script.write_text(source.replace('/system/bin/ps', str(fake_ps))
                              .replace('/data/adb/lightflow/memory/watchdog.pid', str(pid_file)))
            for args in ([], ['status'], ['start']):
                result = subprocess.run(['/system/bin/sh', str(script), *args],
                                        capture_output=True, text=True, timeout=5)
                self.assertEqual(result.returncode, 2 if args == ['start'] else 0)
                self.assertEqual(pid_file.read_text(), '123\n')
                self.assertFalse(scan.exists())
            result = subprocess.run(['/system/bin/sh', str(script), 'stop'],
                                    capture_output=True, text=True, timeout=5)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertFalse(pid_file.exists())
            self.assertTrue(scan.exists())
