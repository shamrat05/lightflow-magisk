import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
KEYS = ('wifi_scan_always_enabled', 'ble_scan_always_enabled')


class RadioScanPolicyTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.base = Path(self.tmp.name)
        self.bin = self.base / 'bin'
        self.bin.mkdir()
        self.values = self.base / 'values'
        self.values.mkdir()
        self.state = self.base / 'state'
        self.calls = self.base / 'calls'
        for key in KEYS:
            (self.values / key).write_text('1\n')
        command = self.bin / 'settings'
        command.write_text('''#!/system/bin/sh
key=$3
case "$1" in
  get)
    [ "$FAIL_READ" != "$key" ] || exit 1
    if [ -f "$MOCK_VALUES/$key" ]; then cat "$MOCK_VALUES/$key"; else echo null; fi
    ;;
  put|delete)
    printf '%s\\n' "$*" >> "$MOCK_CALLS"
    [ "$FAIL_WRITE" != "$key" ] || exit 1
    [ "$NO_EFFECT" != "$key" ] || exit 0
    if [ "$1" = put ]; then printf '%s\\n' "$4" > "$MOCK_VALUES/$key"
    else rm -f "$MOCK_VALUES/$key"; fi
    ;;
  *) exit 2 ;;
esac
''')
        command.chmod(0o755)
        self.env = dict(os.environ, PATH=str(self.bin) + ':' + os.environ['PATH'],
                        LIGHTFLOW_RADIO_STATE=str(self.state),
                        MOCK_VALUES=str(self.values), MOCK_CALLS=str(self.calls),
                        FAIL_READ='', FAIL_WRITE='', NO_EFFECT='')

    def tearDown(self):
        self.tmp.cleanup()

    def run_policy(self, mode='apply'):
        return subprocess.run(['/system/bin/sh', str(ROOT / 'module/radio-scan-policy.sh'), mode],
                              env=self.env, capture_output=True, text=True)

    def test_apply_verifies_both_and_keeps_originals_on_repeat(self):
        self.assertEqual(self.run_policy().returncode, 0)
        for key in KEYS:
            self.assertEqual((self.values / key).read_text(), '0\n')
            self.assertEqual((self.state / key).read_text(), '1\n')
            self.assertEqual((self.state / key).stat().st_mode & 0o777, 0o600)
        calls = self.calls.read_text()
        self.assertEqual(self.run_policy().returncode, 0)
        self.assertEqual(self.calls.read_text(), calls)
        self.assertEqual(self.run_policy('restore').returncode, 0)
        for key in KEYS:
            self.assertEqual((self.values / key).read_text(), '1\n')
            self.assertFalse((self.state / key).exists())

    def test_legacy_wifi_backup_is_reused_without_overwrite(self):
        self.state.mkdir()
        (self.state / KEYS[0]).write_text('null\n')
        self.assertEqual(self.run_policy().returncode, 0)
        self.assertEqual((self.state / KEYS[0]).read_text(), 'null\n')
        self.assertEqual(self.run_policy('restore').returncode, 0)
        self.assertFalse((self.values / KEYS[0]).exists())

    def test_failed_or_malformed_read_does_not_write_or_invent_backup(self):
        self.env['FAIL_READ'] = KEYS[0]
        (self.values / KEYS[1]).write_text('Error: unavailable\n')
        self.assertNotEqual(self.run_policy().returncode, 0)
        self.assertFalse(self.calls.exists())
        self.assertEqual(list(self.state.iterdir()), [])

    def test_invalid_backup_is_preserved_and_other_key_can_apply(self):
        self.state.mkdir()
        bad = self.state / KEYS[0]
        bad.write_text('invalid\n')
        self.assertNotEqual(self.run_policy().returncode, 0)
        self.assertEqual(bad.read_text(), 'invalid\n')
        self.assertEqual((self.values / KEYS[0]).read_text(), '1\n')
        self.assertEqual((self.values / KEYS[1]).read_text(), '0\n')

    def test_write_without_effect_fails_readback_and_retains_backup(self):
        self.env['NO_EFFECT'] = KEYS[0]
        self.assertNotEqual(self.run_policy().returncode, 0)
        self.assertEqual((self.state / KEYS[0]).read_text(), '1\n')
        self.assertEqual((self.values / KEYS[0]).read_text(), '1\n')

    def test_backup_directory_is_not_treated_as_successful_backup(self):
        self.state.mkdir()
        (self.state / KEYS[0]).mkdir()
        self.assertNotEqual(self.run_policy().returncode, 0)
        self.assertEqual((self.values / KEYS[0]).read_text(), '1\n')
        self.assertEqual(list((self.state / KEYS[0]).iterdir()), [])
        self.assertEqual((self.values / KEYS[1]).read_text(), '0\n')

    def test_inaccessible_state_directory_prevents_every_write(self):
        self.state.write_text('not a directory\n')
        self.assertNotEqual(self.run_policy().returncode, 0)
        self.assertFalse(self.calls.exists())

    def test_failed_restore_preserves_backup_for_retry(self):
        self.assertEqual(self.run_policy().returncode, 0)
        self.env['FAIL_WRITE'] = KEYS[0]
        self.assertNotEqual(self.run_policy('restore').returncode, 0)
        self.assertEqual((self.state / KEYS[0]).read_text(), '1\n')
        self.assertEqual((self.values / KEYS[0]).read_text(), '0\n')
        self.env['FAIL_WRITE'] = ''
        self.assertEqual(self.run_policy('restore').returncode, 0)
        self.assertEqual((self.values / KEYS[0]).read_text(), '1\n')

    def test_restore_preserves_later_user_choice(self):
        self.assertEqual(self.run_policy().returncode, 0)
        (self.values / KEYS[0]).write_text('1\n')
        (self.values / KEYS[1]).unlink()
        calls = self.calls.read_text()
        self.assertEqual(self.run_policy('restore').returncode, 0)
        self.assertEqual(self.calls.read_text(), calls)
        self.assertEqual((self.values / KEYS[0]).read_text(), '1\n')
        self.assertFalse((self.values / KEYS[1]).exists())
        self.assertEqual(list(self.state.iterdir()), [])

    def test_status_and_unknown_mode_do_not_modify_settings(self):
        result = self.run_policy('status')
        self.assertEqual(result.returncode, 0)
        self.assertIn('wifi_scan_always_enabled=1', result.stdout)
        self.assertFalse(self.calls.exists())
        self.assertFalse(self.state.exists())
        self.assertEqual(self.run_policy('always-on').returncode, 2)
        self.assertFalse(self.state.exists())


if __name__ == '__main__':
    unittest.main()
