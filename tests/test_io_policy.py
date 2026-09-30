import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


class IoPolicyTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.node = self.root / 'sys/class/block/dm-42/queue/read_ahead_kb'
        self.node.parent.mkdir(parents=True)
        self.node.write_text('512\n')
        name = self.node.parent.parent / 'dm/name'
        name.parent.mkdir()
        name.write_text('userdata\n')
        mounts = self.root / 'mounts'
        mounts.write_text('/dev/block/dm-42 /data f2fs rw 0 0\n')
        source = (Path(__file__).parents[1] / 'module/io-policy.sh').read_text()
        source = source.replace('/data/adb/lightflow/io', str(self.root / 'state'))
        source = source.replace('/proc/mounts', str(mounts))
        source = source.replace('/sys/class/block', str(self.root / 'sys/class/block'))
        self.script = self.root / 'io-policy.sh'
        self.script.write_text(source)
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        self.env = dict(os.environ, PATH=str(self.bin) + os.pathsep + os.environ['PATH'])
        self.mock('sleep', 'printf "sleep\\n" >> "' + str(self.root / 'sleeps') + '"\n')
        self.properties()

    def mock(self, command, body):
        target = self.bin / command
        target.write_text('#!' + shutil.which('sh') + '\n' + body)
        target.chmod(0o755)

    def properties(self, ready_after=4, model='RMX3741'):
        counter = str(self.root / 'calls')
        self.mock('getprop', f'''if [ "$1" = ro.product.model ]; then
  printf '{model}\\n'; exit 0
fi
n=$(cat '{counter}' 2>/dev/null || printf 0)
n=$((n + 1))
printf '%s\\n' "$n" > '{counter}'
if [ "$n" -gt {ready_after} ]; then printf 'stopped\\n'; else printf 'running\\n'; fi
''')

    def run_policy(self, mode):
        return subprocess.run([shutil.which('sh'), str(self.script), mode],
                              env=self.env, capture_output=True, text=True)

    def test_waits_for_vendor_then_applies_and_preserves_backup(self):
        result = self.run_policy('boot')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.root / 'calls').read_text().strip(), '9')
        self.assertEqual(len((self.root / 'sleeps').read_text().splitlines()), 9)
        self.assertEqual(self.node.read_text().strip(), '128')
        self.assertEqual((self.root / 'state/read_ahead_kb').read_text().strip(), '512')
        self.assertEqual(self.run_policy('apply').returncode, 0)
        self.assertEqual(self.run_policy('restore').returncode, 0)
        self.assertEqual(self.node.read_text().strip(), '512')

    def test_timeout_skips_write(self):
        self.properties(ready_after=100)
        result = self.run_policy('boot')
        self.assertEqual(result.returncode, 1)
        self.assertIn('did not settle', result.stdout)
        self.assertEqual((self.root / 'calls').read_text().strip(), '30')
        self.assertEqual(self.node.read_text().strip(), '512')
        self.assertFalse((self.root / 'state').exists())

    def test_unsupported_model_skips_wait_and_write(self):
        self.properties(model='OTHER')
        self.assertEqual(self.run_policy('boot').returncode, 0)
        self.assertFalse((self.root / 'sleeps').exists())
        self.assertEqual(self.node.read_text().strip(), '512')

    def test_smaller_user_value_is_preserved(self):
        self.node.write_text('64\n')
        self.assertEqual(self.run_policy('apply').returncode, 0)
        self.assertEqual(self.node.read_text().strip(), '64')
        self.assertFalse((self.root / 'state').exists())

    def test_restore_preserves_later_changes(self):
        self.assertEqual(self.run_policy('apply').returncode, 0)
        self.node.write_text('256\n')
        self.assertEqual(self.run_policy('restore').returncode, 0)
        self.assertEqual(self.node.read_text().strip(), '256')
        self.assertFalse((self.root / 'state/read_ahead_kb').exists())


if __name__ == '__main__':
    unittest.main()
