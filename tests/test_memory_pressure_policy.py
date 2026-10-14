import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


class MemoryPressurePolicyTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.base = Path(self.tmp.name)
        self.bin = self.base / 'bin'
        self.bin.mkdir()
        self.meminfo = self.base / 'meminfo'
        self.psi = self.base / 'pressure-memory'
        self.log = self.base / 'lightflow.log'
        self.calls = self.base / 'calls'
        self._write_mock('getprop', '''
if [ "$1" = ro.product.model ]; then echo "${MOCK_MODEL:-RMX3741}"; fi
if [ "$1" = ro.build.version.sdk ]; then echo "${MOCK_SDK:-35}"; fi
''')
        am = self.bin / 'am'
        am.write_text('#!/system/bin/sh\nprintf "%s\\n" "$*" >> "$MOCK_CALLS"\n')
        am.chmod(0o755)
        source = (ROOT / 'module/memory-pressure-policy.sh').read_text()
        source = source.replace('/proc/meminfo', str(self.meminfo))
        source = source.replace('/proc/pressure/memory', str(self.psi))
        source = source.replace('/data/adb/lightflow.log', str(self.log))
        source = source.replace('/system/bin/am', str(am))
        self.script = self.base / 'memory-pressure-policy.sh'
        self.script.write_text(source)
        self.script.chmod(0o755)
        self.env = dict(os.environ, PATH=str(self.bin) + ':' + os.environ['PATH'],
                        MOCK_CALLS=str(self.calls))

    def _write_mock(self, name, body):
        path = self.bin / name
        path.write_text('#!/system/bin/sh\n' + body)
        path.chmod(0o755)

    def run_policy(self, mode='apply', **env):
        merged = dict(self.env, **env)
        return subprocess.run(['/system/bin/sh', str(self.script), mode], env=merged,
                              capture_output=True, text=True)

    def test_healthy_device_does_not_kill_cached_processes(self):
        self.meminfo.write_text('MemAvailable: 2200000 kB\nSwapTotal: 5767164 kB\nSwapFree: 4000000 kB\n')
        self.psi.write_text('some avg10=0.00 avg60=0.00 avg300=0.00 total=0\nfull avg10=0.00 avg60=0.00 avg300=0.00 total=0\n')
        result = self.run_policy()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.calls.exists())
        self.assertIn('no cached-process relief needed', self.log.read_text())

    def test_high_swap_requests_android_cached_process_relief(self):
        self.meminfo.write_text('MemAvailable: 1400000 kB\nSwapTotal: 5767164 kB\nSwapFree: 1000000 kB\n')
        self.psi.write_text('some avg10=0.00 avg60=0.00 avg300=0.00 total=0\nfull avg10=0.00 avg60=0.00 avg300=0.00 total=0\n')
        result = self.run_policy()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls.read_text(), 'kill-all\n')
        self.assertIn('cached-process kill requested', self.log.read_text())

    def test_wrong_device_is_noop(self):
        self.meminfo.write_text('MemAvailable: 1 kB\nSwapTotal: 100 kB\nSwapFree: 0 kB\n')
        self.psi.write_text('full avg10=99.00 avg60=99.00 avg300=99.00 total=0\n')
        result = self.run_policy(MOCK_MODEL='other-device')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.calls.exists())


if __name__ == '__main__':
    unittest.main()
