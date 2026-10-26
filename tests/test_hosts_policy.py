import collections
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
POLICY = ROOT / 'module/hosts-policy.sh'


def mappings(text):
    result = collections.defaultdict(list)
    for line in text.splitlines():
        tokens = line.split('#', 1)[0].split()
        for name in tokens[1:]:
            result[name].append(tokens[0])
    return dict(result)


class HostsPolicyTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.base = Path(self.tmp.name)
        self.bin = self.base / 'bin'
        self.bin.mkdir()
        self.source = self.base / 'source'
        self.target = self.base / 'target'
        self.state = self.base / 'state'
        self.calls = self.base / 'calls'
        self.source.write_text(''.join(f'0.0.0.0 ads{i:06}.example.invalid\n' for i in range(34000))
                               + '127.0.0.1 localhost\n::1 localhost\n')
        subprocess.run(['ln', str(self.source), str(self.target)], check=True,
                       capture_output=True)
        for name in ['chown', 'chcon']:
            self.command(name, '#!/system/bin/sh\nexit 0\n')
        self.command('getprop', '#!/system/bin/sh\ncase "$1" in *model) echo RMX3741;; *sdk) echo 35;; esac\n')
        self.command('hosts-bind', '''#!/system/bin/sh
printf '%s\n' "$*" >> "$MOCK_CALLS"
rm -f "$2"; ln "$1" "$2"
if [ "$REPLACE_ON_RO_FAILURE" = 1 ]; then
  rm -f "$2"; printf '127.0.0.1 replacement\n' > "$2"
fi
[ "$FAIL_RO" != 1 ]
''')
        self.command('umount', '''#!/system/bin/sh
printf 'umount %s\n' "$1" >> "$MOCK_CALLS"
rm -f "$1"
ln "$MOCK_UNDERLYING" "$1"
''')
        self.env = dict(os.environ, PATH=str(self.bin) + ':' + os.environ['PATH'],
                        LIGHTFLOW_HOSTS_STATE=str(self.state),
                        LIGHTFLOW_HOSTS_SOURCE=str(self.source),
                        LIGHTFLOW_HOSTS_TARGET=str(self.target),
                        LIGHTFLOW_HOSTS_BINDER=str(self.bin / 'hosts-bind'),
                        MOCK_CALLS=str(self.calls), MOCK_UNDERLYING=str(self.source), FAIL_RO='')

    def command(self, name, text):
        p = self.bin / name
        p.write_text(text)
        p.chmod(0o755)

    def tearDown(self):
        self.tmp.cleanup()

    def run_policy(self, *args):
        return subprocess.run(['/system/bin/sh', str(POLICY), *args],
                              env=self.env, capture_output=True, text=True)

    def test_compaction_preserves_all_addresses_duplicates_and_localhost(self):
        original = self.source.read_text()
        result = self.run_policy('apply')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.source.read_text(), original)
        self.assertEqual(mappings(self.target.read_text()), mappings(original))
        self.assertLess(self.target.stat().st_size, self.source.stat().st_size)
        self.assertIn('Hosts formatting: compact overlay active', self.run_policy('status').stdout)
        calls = self.calls.read_text()
        self.assertEqual(self.run_policy('apply').returncode, 0)
        self.assertEqual(self.calls.read_text(), calls)
        self.assertEqual(self.run_policy('restore').returncode, 0)
        self.assertEqual(self.target.read_text(), original)

    def test_format_limits_aliases_and_long_lines_and_keeps_conflicting_order(self):
        text = ('# header\n0.0.0.0 MiXeD.invalid duplicate.invalid\n'
                '0.0.0.0 duplicate.invalid\n127.0.0.1 duplicate.invalid localhost\n'
                '0.0.0.0 comment.invalid # inline comment\n'
                + ''.join('0.0.0.0 ' + str(i) + 'x' * 230 + '.invalid\n' for i in range(40)))
        self.source.write_text(text)
        output = self.base / 'formatted'
        result = self.run_policy('format', str(self.source), str(output))
        self.assertEqual(result.returncode, 0, result.stderr)
        formatted = output.read_text()
        self.assertEqual(mappings(text), mappings(formatted))
        self.assertIn('0.0.0.0 comment.invalid # inline comment\n', formatted)
        for line in formatted.splitlines():
            self.assertLessEqual(len(line.encode()), 900)
            if line.startswith('0.0.0.0'):
                self.assertLessEqual(len(line.split('#', 1)[0].split()) - 1, 16)

    def test_failed_readonly_remount_rolls_back(self):
        original = self.target.read_bytes()
        self.env['FAIL_RO'] = '1'
        self.assertNotEqual(self.run_policy('apply').returncode, 0)
        self.assertEqual(self.target.read_bytes(), original)
        self.assertIn('umount ', self.calls.read_text())

    def test_restore_preserves_another_owners_replacement(self):
        self.assertEqual(self.run_policy('apply').returncode, 0)
        self.target.unlink()
        self.target.write_text('127.0.0.1 localhost\n')
        calls = self.calls.read_text()
        self.assertEqual(self.run_policy('restore').returncode, 0)
        self.assertEqual(self.calls.read_text(), calls)
        self.assertEqual(self.target.read_text(), '127.0.0.1 localhost\n')

    def test_failed_remount_preserves_a_racing_replacement(self):
        self.env.update(FAIL_RO='1', REPLACE_ON_RO_FAILURE='1')
        self.assertNotEqual(self.run_policy('apply').returncode, 0)
        self.assertEqual(self.target.read_text(), '127.0.0.1 replacement\n')
        self.assertNotIn('umount ', self.calls.read_text())

    def test_different_active_list_is_not_masked(self):
        self.target.unlink()
        self.target.write_text('127.0.0.1 localhost\n')
        self.assertNotEqual(self.run_policy('apply').returncode, 0)
        self.assertFalse(self.calls.exists())

    def test_hash_failure_never_mounts(self):
        self.command('sha256sum', '#!/system/bin/sh\nexit 1\n')
        self.assertNotEqual(self.run_policy('apply').returncode, 0)
        self.assertFalse(self.calls.exists())

    def test_unsupported_device_does_not_create_state(self):
        self.command('getprop', '#!/system/bin/sh\necho unsupported\n')
        self.assertEqual(self.run_policy('apply').returncode, 0)
        self.assertFalse(self.state.exists())

    def test_small_list_is_left_unchanged(self):
        self.source.write_text('127.0.0.1 localhost\n0.0.0.0 ads.invalid\n')
        self.assertEqual(self.run_policy('apply').returncode, 0)
        self.assertFalse(self.calls.exists())
        self.assertFalse(self.state.exists())


if __name__ == '__main__':
    unittest.main()
