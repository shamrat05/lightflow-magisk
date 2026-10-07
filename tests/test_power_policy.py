import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class PowerPolicyTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.base = Path(self.tmp.name)
        self.bin = self.base/'bin'
        self.bin.mkdir()
        self.state = self.base/'state'
        self.log = self.base/'calls'
        self.data = self.base/'data.json'
        self.values = {'cached_apps_freezer': 'null', 'app_standby_enabled': '0',
                       'dynamic_power_savings_enabled': '0', 'activity': 'use_freezer=true',
                       'power': 'adaptive=false', 'failed': []}
        script = '''#!/data/data/com.termux/files/usr/bin/python
import json,os,sys
from pathlib import Path
data=json.loads(Path(os.environ['MOCK_DATA']).read_text())
name=Path(sys.argv[0]).name
args=sys.argv[1:]
if name=='settings' and args[0]=='get':
 key=args[2]
 if key in data['failed']:sys.exit(1)
 print(data.get(key,''))
elif name=='dumpsys':
 key=args[0]
 if key in data['failed']:sys.exit(1)
 print(data.get(key,''))
else:
 if 'writes' in data['failed']:sys.exit(1)
 with open(os.environ['MOCK_LOG'],'a') as f:f.write(name+' '+' '.join(args)+'\\n')
'''
        for name in ('settings','dumpsys','cmd'):
            path = self.bin/name
            path.write_text(script)
            path.chmod(0o755)
        self.env = dict(os.environ, PATH=str(self.bin)+':'+os.environ['PATH'],
                        LIGHTFLOW_POWER_STATE=str(self.state), MOCK_DATA=str(self.data),
                        MOCK_LOG=str(self.log))

    def tearDown(self):
        self.tmp.cleanup()

    def run_policy(self, *args):
        self.data.write_text(json.dumps(self.values))
        result = subprocess.run(['sh', str(ROOT/'module/power-policy.sh'), *args],
                                env=self.env, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        return self.log.read_text() if self.log.exists() else ''

    def test_backups_and_policy_preserve_trigger_selection(self):
        calls = self.run_policy()
        self.assertIn('settings put global cached_apps_freezer enabled', calls)
        self.assertIn('cmd power set-adaptive-power-saver-enabled true', calls)
        self.assertNotIn('automatic_power_save_mode', calls)
        self.assertEqual((self.state/'cached_apps_freezer').read_text(), 'null\n')
        self.assertEqual((self.state/'adaptive_power_saver').read_text(), 'false\n')
        self.values['app_standby_enabled'] = '1'
        self.run_policy()
        self.assertEqual((self.state/'app_standby_enabled').read_text(), '0\n')

    def test_failed_reads_do_not_invent_backups_or_write(self):
        self.values['failed'] = ['cached_apps_freezer','app_standby_enabled',
                                 'dynamic_power_savings_enabled','power']
        self.assertEqual(self.run_policy(), '')
        self.assertEqual(list(self.state.iterdir()), [])

    def test_empty_and_unknown_reads_are_not_false_or_null(self):
        self.values.update(cached_apps_freezer='', app_standby_enabled='Error: unavailable',
                           dynamic_power_savings_enabled='9', power='unrelated output')
        self.assertEqual(self.run_policy(), '')
        self.assertEqual(list(self.state.iterdir()), [])

    def test_unsupported_freezer_is_not_requested(self):
        self.values['activity'] = 'use_freezer=false'
        calls = self.run_policy()
        self.assertNotIn('cached_apps_freezer', calls)
        self.assertFalse((self.state/'cached_apps_freezer').exists())

    def test_invalid_existing_backup_is_preserved_and_not_applied(self):
        self.state.mkdir()
        (self.state/'app_standby_enabled').write_text('invalid\n')
        (self.state/'adaptive_power_saver').write_text('unknown\n')
        calls = self.run_policy()
        self.assertNotIn('app_standby_enabled', calls)
        self.assertNotIn('set-adaptive-power-saver-enabled', calls)
        self.assertEqual((self.state/'app_standby_enabled').read_text(), 'invalid\n')

    def test_restore_validates_backups_and_keeps_invalid_values(self):
        self.state.mkdir()
        (self.state/'cached_apps_freezer').write_text('null\n')
        (self.state/'app_standby_enabled').write_text('bad\n')
        (self.state/'adaptive_power_saver').write_text('false\n')
        self.data.write_text(json.dumps(self.values))
        result = subprocess.run(['sh', str(ROOT/'module/power-policy.sh'), 'restore'],
                                env=self.env, capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        calls = self.log.read_text()
        self.assertIn('settings delete global cached_apps_freezer', calls)
        self.assertIn('cmd power set-adaptive-power-saver-enabled false', calls)
        self.assertNotIn('app_standby_enabled', calls)
        self.assertFalse((self.state/'cached_apps_freezer').exists())
        self.assertEqual((self.state/'app_standby_enabled').read_text(), 'bad\n')

    def test_restore_failure_preserves_backup_for_retry(self):
        self.state.mkdir()
        saved = self.state/'dynamic_power_savings_enabled'
        saved.write_text('0\n')
        self.values['failed'] = ['writes']
        self.data.write_text(json.dumps(self.values))
        result = subprocess.run(['sh', str(ROOT/'module/power-policy.sh'), 'restore'],
                                env=self.env, capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(saved.read_text(), '0\n')

    def test_legacy_trigger_preserves_later_selection(self):
        self.state.mkdir()
        (self.state/'automatic_power_save_mode').write_text('1\n')
        self.values['automatic_power_save_mode'] = '0'
        self.assertEqual(self.run_policy('restore-legacy-trigger'), '')
        self.assertFalse((self.state/'automatic_power_save_mode').exists())

    def test_legacy_trigger_restores_only_still_managed_value(self):
        self.state.mkdir()
        (self.state/'automatic_power_save_mode').write_text('0\n')
        self.values['automatic_power_save_mode'] = '1'
        calls = self.run_policy('restore-legacy-trigger')
        self.assertEqual(calls, 'settings put global automatic_power_save_mode 0\n')


if __name__ == '__main__':
    unittest.main()
