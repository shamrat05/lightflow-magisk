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
