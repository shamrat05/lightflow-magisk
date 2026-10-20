import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
SERVICES = ('ostatsd', 'ostats_tpd', 'ostats_pullerd')


class OemDiagnosticsPolicyTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)
        self.state = self.base / 'owned'
        self.props = self.base / 'properties.json'
        self.calls = self.base / 'writes.jsonl'
        self.bin = self.base / 'bin'
        self.bin.mkdir()
        self.env = dict(os.environ, PATH=str(self.bin)+':'+os.environ['PATH'],
                        LF_PROPS=str(self.props), LF_WRITES=str(self.calls))
        properties = {'ro.product.model': 'RMX3741', 'ro.build.version.sdk': '35',
                      'ro.build.version.incremental': 'T.R4T2.231124a_d5daf',
                      'init.svc.thermal': 'running', 'persist.sys.thermal.enable': '1'}
        for service in SERVICES:
            properties['persist.sys.'+service+'.enable'] = '1'
            properties['init.svc.'+service] = 'running'
        self.save(properties)
        self.script = self.base / 'policy.sh'
        self.script.write_text((ROOT / 'module/oem-diagnostics-policy.sh').read_text().replace(
            'STATE=/data/adb/lightflow/oem-diagnostics', 'STATE='+str(self.state)))
        tools = {
            'getprop': '''import json,os,sys
print(json.load(open(os.environ['LF_PROPS'])).get(sys.argv[1],''))
''',
            'setprop': '''import json,os,sys
from pathlib import Path
p=Path(os.environ['LF_PROPS']);d=json.loads(p.read_text());key,value=sys.argv[1:]
with open(os.environ['LF_WRITES'],'a') as f:f.write(json.dumps([key,value])+'\\n')
d[key]=value
if key.startswith('persist.sys.ostats') and key.endswith('.enable'):
 service=key[len('persist.sys.'):-len('.enable')]
 if not (value=='0' and os.environ.get('LF_FAIL_STOP')==service):
  d['init.svc.'+service]='stopped' if value=='0' else 'running'
p.write_text(json.dumps(d))
''',
            'sleep': 'pass\n',
        }
        for name,body in tools.items():
            tool=self.bin/name
            tool.write_text('#!'+sys.executable+'\n'+body)
            tool.chmod(0o755)

    def save(self, props):
        self.props.write_text(json.dumps(props))

    def load(self):
        return json.loads(self.props.read_text())

    def writes(self):
        return [json.loads(line) for line in self.calls.read_text().splitlines()] if self.calls.exists() else []

    def run_policy(self, mode='apply'):
        return subprocess.run(['/system/bin/sh', str(self.script), mode],
                              env=self.env, capture_output=True, text=True, timeout=20)

    def test_apply_stops_only_audited_collectors_and_restore_restarts_them(self):
        original=self.load()
        p=self.run_policy()
        self.assertEqual(p.returncode,0,p.stdout+p.stderr)
        for service in SERVICES:
            self.assertEqual(self.load()['init.svc.'+service], 'stopped')
            self.assertEqual((self.state/service).read_text(), '1\n')
        self.assertEqual(set(k for k,v in self.writes()),
                         {'persist.sys.'+s+'.enable' for s in SERVICES})
        self.assertEqual(self.load()['init.svc.thermal'], 'running')
        p=self.run_policy('restore')
        self.assertEqual(p.returncode,0,p.stdout+p.stderr)
        self.assertEqual(self.load(), original)
        self.assertFalse(self.state.exists())

    def test_reapply_is_read_only(self):
        self.assertEqual(self.run_policy().returncode,0)
        before=self.writes()
        self.assertEqual(self.run_policy().returncode,0)
        self.assertEqual(self.writes(),before)

    def test_user_disabled_collector_is_not_owned_or_enabled_on_restore(self):
        props=self.load()
        props.update({'persist.sys.ostatsd.enable':'0','init.svc.ostatsd':'stopped'})
        self.save(props)
        self.assertEqual(self.run_policy().returncode,0)
        self.assertFalse((self.state/'ostatsd').exists())
        self.assertEqual(self.run_policy('restore').returncode,0)
        self.assertEqual(self.load()['persist.sys.ostatsd.enable'],'0')

    def test_unknown_firmware_makes_no_changes(self):
        for key,value in [('ro.product.model','another-device'),
                          ('ro.build.version.sdk','36'),
                          ('ro.build.version.incremental','another-build')]:
            with self.subTest(key=key):
                original=self.load();changed=dict(original);changed[key]=value;self.save(changed)
                self.assertEqual(self.run_policy().returncode,0)
                self.assertEqual(self.load(),changed)
                self.assertFalse(self.state.exists())
                self.assertEqual(self.writes(),[])
                self.save(original)

    def test_stop_failure_rolls_back_and_reports_failure(self):
        self.env['LF_FAIL_STOP']='ostatsd'
        p=self.run_policy()
        self.assertNotEqual(p.returncode,0)
        self.assertEqual(self.load()['persist.sys.ostatsd.enable'],'1')
        self.assertEqual(self.load()['init.svc.ostatsd'],'running')
        self.assertFalse((self.state/'ostatsd').exists())
        self.assertIn('disable not verified',p.stdout)

    def test_later_reenable_is_preserved_on_restore(self):
        self.assertEqual(self.run_policy().returncode,0)
        props=self.load()
        props.update({'persist.sys.ostatsd.enable':'1','init.svc.ostatsd':'running'})
        self.save(props);before=self.writes()
        self.assertEqual(self.run_policy('restore').returncode,0)
        writes=self.writes()[len(before):]
        self.assertNotIn(['persist.sys.ostatsd.enable','1'],writes)
        self.assertFalse((self.state/'ostatsd').exists())

    def test_status_and_unknown_mode_never_write(self):
        self.assertEqual(self.run_policy('status').returncode,0)
        self.assertEqual(self.run_policy('unknown').returncode,2)
        self.assertEqual(self.writes(),[])
        self.assertFalse(self.state.exists())


if __name__ == '__main__':
    unittest.main()
