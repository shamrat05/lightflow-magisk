import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


class ThermalMemoryPolicyTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.base = Path(self.tmp.name)
        self.state = self.base / 'state'
        self.sys = self.base / 'sys'
        zone = self.sys / 'class/thermal/thermal_zone0'
        zone.mkdir(parents=True)
        (zone / 'type').write_text('mtktscpu\n')
        (zone / 'temp').write_text('70000\n')
        self.meminfo = self.base / 'meminfo'
        self.meminfo.write_text('MemAvailable: 900000 kB\nSwapTotal: 5767164 kB\nSwapFree: 1000000 kB\n')
        self.swap = self.base / 'swappiness'
        self.swap.write_text('160\n')
        self.log = self.base / 'calls'
        self.bin = self.base / 'bin'
        self.bin.mkdir()
        self._mock('dumpsys', '''#!/system/bin/sh
if [ "$1" = battery ]; then echo '  temperature: 380'; else echo 'Thermal Status: 2'; fi
''')
        self._mock('settings', 'printf "settings %s\\n" "$*" >> "$MOCK_LOG"\n')
        self._mock('am', 'printf "am %s\\n" "$*" >> "$MOCK_LOG"\n')
        source = (ROOT / 'module/thermal-memory-policy.sh').read_text()
        source = source.replace('/sys/class/thermal', str(self.sys / 'class/thermal'))
        source = source.replace('/proc/meminfo', str(self.meminfo))
        source = source.replace('/proc/sys/vm/swappiness', str(self.swap))
        source = source.replace('/data/adb/lightflow', str(self.state))
        self.script = self.base / 'thermal-memory-policy.sh'
        self.script.write_text(source)
        self.script.chmod(0o755)
        self.env = dict(os.environ, PATH=str(self.bin) + os.pathsep + os.environ['PATH'], MOCK_LOG=str(self.log))

    def _mock(self, name, body):
        path = self.bin / name
        path.write_text('#!/system/bin/sh\n' + body)
        path.chmod(0o755)

    def run_policy(self, mode):
        return subprocess.run(['/system/bin/sh', str(self.script), mode], env=self.env,
                              capture_output=True, text=True)

    def test_cool_relief_saves_and_lowers_swap(self):
        result = self.run_policy('cool')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.swap.read_text(), '60\n')
        self.assertEqual((self.state / 'memory/swappiness').read_text(), '160\n')
        calls = self.log.read_text()
        self.assertNotIn('am kill-all', calls)
        self.assertIn('settings put system user_refresh_rate 60', calls)

    def test_restore_preserves_user_change(self):
        self.assertEqual(self.run_policy('cool').returncode, 0)
        self.swap.write_text('80\n')
        self.assertEqual(self.run_policy('restore').returncode, 0)
        self.assertEqual(self.swap.read_text(), '80\n')
        self.assertTrue((self.state / 'memory/swappiness').exists())

    def test_cool_does_not_stop_processes_when_healthy(self):
        (self.sys / 'class/thermal/thermal_zone0/temp').write_text('40000\n')
        self.meminfo.write_text('MemAvailable: 2200000 kB\nSwapTotal: 5767164 kB\nSwapFree: 4000000 kB\n')
        self.swap.write_text('60\n')
        self._mock('dumpsys', '''#!/system/bin/sh
if [ "$1" = battery ]; then echo '  temperature: 350'; else echo 'Thermal Status: 0'; fi
''')
        result = self.run_policy('cool')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('No heat or memory-pressure threshold reached', result.stdout)
        calls = self.log.read_text()
        self.assertIn('settings put system user_refresh_rate 90', calls)
        self.assertNotIn('am kill-all', calls)


if __name__ == '__main__':
    unittest.main()
