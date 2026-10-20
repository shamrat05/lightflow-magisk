import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import textwrap
import unittest

ROOT = Path(__file__).resolve().parents[1]
PKG = 'dev.lightflow.guard'
BOOT_A = '00000000-0000-4000-8000-000000000001'
BOOT_B = '00000000-0000-4000-8000-000000000002'

# These executables model Android/Vector responses only. Production paths are
# replaced in the copied script; the production helper has no test overrides.
MOCK = r'''
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

state_path = Path(os.environ['GUARD_DEPLOYMENT_TEST_STATE'])
state = json.loads(state_path.read_text())
name = Path(sys.argv[0]).name
args = sys.argv[1:]
entry = {'name': name, 'args': args,
         'deadline': os.environ.get('GUARD_DEPLOYMENT_TEST_DEADLINE')}
state['calls'].append(entry)

def save():
    temp = state_path.with_suffix('.next')
    temp.write_text(json.dumps(state))
    temp.replace(state_path)

def finish(value='', code=0):
    save()
    if value:
        print(value)
    raise SystemExit(code)

if name == 'getprop':
    finish(str(state['properties'].get(args[0], '')))
elif name == 'setprop':
    if not (state.get('ignore_enable_property') and args == ['sys.lightflow.guard', '1']):
        state['properties'][args[0]] = args[1]
    finish()
elif name == 'sleep':
    finish()
elif name in ('watchdog', 'chown', 'set_perm'):
    finish()
elif name == 'timeout':
    if not args:
        finish('missing timeout arguments', 91)
    kill_after = None
    if args[0] == '-k':
        kill_after, args = args[1], args[2:]
    elif args[0].startswith('-k'):
        kill_after, args = args[0][2:], args[1:]
    if not args or kill_after != '2':
        finish('expected bounded timeout with -k2', 91)
    duration, command = args[0], args[1:]
    if not command:
        finish('missing bounded command', 91)
    state['calls'][-1].update(duration=duration, kill_after=kill_after,
                              command=[Path(command[0]).name, *command[1:]])
    target = ' '.join([Path(command[0]).name, *command[1:2]])
    if (Path(command[0]).name == 'cli' and command[1:3] == ['modules', 'ls']
            and state.get('inventory_timeouts_remaining', 0) > 0):
        state['inventory_timeouts_remaining'] -= 1
        state['calls'][-1]['simulated_inventory_timeout'] = True
        save()
        raise SystemExit(124)
    # Simulate a slow service without delaying the suite. A cold Vector read
    # observed above five seconds must not be rejected by a five-second budget.
    minimum = state.get('cli_minimum_seconds', 0) if Path(command[0]).name == 'cli' else 0
    state['calls'][-1]['simulated_service_seconds'] = minimum
    save()
    if target in state.get('timeout_commands', []) or float(duration) < minimum:
        raise SystemExit(124)
    env = dict(os.environ, GUARD_DEPLOYMENT_TEST_DEADLINE=duration)
    raise SystemExit(subprocess.run(command, env=env, timeout=5).returncode)
elif name == 'pm':
    if state.get('pm_unavailable'):
        finish('Package manager unavailable', 1)
    if args[:2] == ['path', 'android']:
        finish('package:' + state['framework_apk'])
    if args[:2] == ['path', 'dev.lightflow.guard']:
        installed = Path(state['installed_apk'])
        finish('package:' + str(installed) if installed.exists() else '',
               0 if installed.exists() else 1)
    if args and args[0] == 'install':
        source = Path(args[-1]).resolve()
        if not source.is_relative_to(Path(state['base']).resolve()):
            finish('refused non-fixture install path', 92)
        if state.get('install_failures', 0):
            state['install_failures'] -= 1
            finish('Failure [Failed transaction (2147483646)]', 1)
        installed = Path(state['installed_apk'])
        installed.parent.mkdir(parents=True, exist_ok=True)
        if state.get('false_install_success'):
            installed.write_bytes(b'wrong APK bytes despite Success output')
        else:
            shutil.copyfile(source, installed)
        finish('Success')
    if args[:2] == ['list', 'packages']:
        finish('package:android\npackage:dev.lightflow.guard uid:10313')
    finish('unsupported mock pm request', 93)
elif name == 'cli':
    if state.get('cli_unavailable'):
        finish('{"success": false}', 1)
    if args[:2] == ['modules', 'enable']:
        if not state.get('enable_noop'):
            state['module_status'] = 'enabled'
        finish('{"success": true}')
    if args[:2] == ['modules', 'ls']:
        rows = state.get('module_rows')
        if rows is None:
            rows = [{'PACKAGE': 'dev.lightflow.guard', 'UID': 10313,
                     'STATUS': state['module_status']}]
        finish(json.dumps({'data': rows, 'success': True}, indent=2))
    if args[:2] == ['scope', 'set']:
        if not state.get('scope_noop'):
            # Vector stores precisely the requested rows; it does not invent a
            # system/0 alias for android/0. This catches the RC3 regression.
            state['scope_rows'] = [
                {'APP_PACKAGE': target.rsplit('/', 1)[0],
                 'USER_ID': int(target.rsplit('/', 1)[1])}
                for target in args[3:] if not target.startswith('--')]
        finish('{"success": true}')
    if args[:2] == ['scope', 'ls']:
        finish(json.dumps({'data': state['scope_rows'], 'success': True}, indent=2))
    finish('unsupported mock Vector request', 93)
elif name == 'dumpsys':
    if state.get('diagnostic_missing'):
        finish('Unknown dump command')
    finish('LightFlow System Guard (read-only diagnostic)\n'
           'installedTargets=' + str(state.get('installed_targets', 3)) +
           ' expected=3 (Athena=1 Atomic=2) diagnostics=' +
           ('false' if state.get('diagnostic_disabled') else 'true') + '\n'
           'policySelfCheck=' + state.get('self_check', 'PASS') +
           ' (isolated policy copy)')
finish('unsupported mock command', 93)
'''


class GuardDeploymentTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.bin = self.base / 'bin'
        self.bin.mkdir()
        self.module = self.base / 'module'
        self.module.mkdir()
        self.state_dir = self.base / 'lightflow'
        self.receipt = self.state_dir / 'guard-deployment/prepared'
        self.staging = self.base / 'staging'
        self.staging.mkdir()
        self.boot = self.base / 'boot-id'
        self.boot.write_text(BOOT_A + '\n')
        self.apk = self.module / 'guard.apk'
        self.apk.write_bytes(b'LightFlow signed guard fixture version 1\n')
        self.digest = hashlib.sha256(self.apk.read_bytes()).hexdigest()
        self.installed = self.base / 'installed/base.apk'
        framework = self.base / 'framework-res.apk'
        framework.write_bytes(b'Android framework fixture')
        self.state_file = self.base / 'mock-state.json'
        self.state_file.write_text(json.dumps({
            'base': str(self.base), 'installed_apk': str(self.installed),
            'framework_apk': str(framework), 'calls': [],
            'properties': {'ro.product.model': 'RMX3741',
                           'ro.build.version.sdk': '35',
                           'sys.boot_completed': '1',
                           'sys.lightflow.guard': '1'},
            'module_status': 'enabled',
            'scope_rows': [{'APP_PACKAGE': 'android', 'USER_ID': 0},
                           {'APP_PACKAGE': 'system', 'USER_ID': 0}],
        }))
        for name in ('getprop', 'setprop', 'pm', 'cli', 'dumpsys', 'timeout',
                     'sleep', 'watchdog', 'chown', 'set_perm'):
            executable = self.bin / name
            executable.write_text('#!' + sys.executable + '\n' + textwrap.dedent(MOCK))
            executable.chmod(0o755)
        self.shell = shutil.which('sh')
        self.assertIsNotNone(self.shell)
        self.env = dict(os.environ, PATH=str(self.bin) + os.pathsep + os.environ['PATH'],
                        GUARD_DEPLOYMENT_TEST_STATE=str(self.state_file))
        # Never execute another module helper in the device's real context.
        for script in (ROOT / 'module').glob('*.sh'):
            target = self.module / script.name
            target.write_text('#!' + self.shell + '\nexit 0\n')
            target.chmod(0o755)
        self.script = self.module / 'guard-policy.sh'
        self.script.write_text(self.fixture_source(ROOT / 'module/guard-policy.sh'))
        self.script.chmod(0o755)
        (self.module / 'memory-watchdog.sh').write_text(
            '#!' + self.shell + '\nexec "' + str(self.bin / 'watchdog') + '" "$@"\n')
        (self.module / 'module.prop').write_text('id=lightflow\n')

    def fixture_source(self, path):
        source = path.read_text()
        replacements = {
            '/data/adb/lightflow': str(self.state_dir),
            '/data/adb/lspd/cli': str(self.bin / 'cli'),
            '/data/local/tmp': str(self.staging),
            '/proc/sys/kernel/random/boot_id': str(self.boot),
            '/system/bin/timeout': str(self.bin / 'timeout'),
            '/system/bin/sh': self.shell,
        }
        for name in ('getprop', 'setprop', 'pm', 'dumpsys', 'chown'):
            replacements['/system/bin/' + name] = str(self.bin / name)
        for original, replacement in replacements.items():
            source = source.replace(original, replacement)
        return source

    def state(self):
        return json.loads(self.state_file.read_text())

    def configure(self, **values):
        state = self.state()
        state.update(values)
        self.state_file.write_text(json.dumps(state))

    def calls(self, name=None, prefix=None):
        calls = self.state()['calls']
        return [call for call in calls
                if (name is None or call['name'] == name)
                and (prefix is None or call['args'][:len(prefix)] == list(prefix))]

    def run_policy(self, mode):
        return subprocess.run([self.shell, str(self.script), mode], env=self.env,
                              capture_output=True, text=True, timeout=20)

    def ready_for_next_boot(self):
        self.installed.parent.mkdir(exist_ok=True)
        shutil.copyfile(self.apk, self.installed)
        self.receipt.parent.mkdir(parents=True, exist_ok=True)
        self.receipt.write_text(BOOT_A + '\n' + self.digest + '\n')
        self.boot.write_text(BOOT_B + '\n')

    def assert_stock(self, result):
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.state()['properties']['sys.lightflow.guard'], '0')
        self.assertFalse(self.calls('pm', ('install',)))
        self.assertFalse(self.calls('cli', ('modules', 'enable')))
        self.assertFalse(self.calls('cli', ('scope', 'set')))

    def test_fresh_prepare_verifies_bytes_scope_receipt_and_keeps_property(self):
        prior = self.staging / 'lightflow-guard.apk'
        prior.write_bytes(b'unrelated pre-existing file')
        result = self.run_policy('prepare')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.installed.read_bytes(), self.apk.read_bytes())
        self.assertEqual(self.receipt.read_text().splitlines(), [BOOT_A, self.digest])
        self.assertEqual(self.state()['properties']['sys.lightflow.guard'], '1')
        self.assertFalse(self.calls('setprop'))
        installs = self.calls('pm', ('install',))
        self.assertEqual(len(installs), 1)
        staged = Path(installs[0]['args'][-1])
        self.assertTrue(staged.is_relative_to(self.staging))
        stage_root = self.staging / staged.relative_to(self.staging).parts[0]
        self.assertTrue(stage_root.name.startswith('lightflow-guard.'))
        self.assertNotEqual(stage_root, prior)
        self.assertFalse(stage_root.exists(), 'temporary staging must be cleaned')
        self.assertEqual(prior.read_bytes(), b'unrelated pre-existing file')
        self.assertEqual(self.receipt.stat().st_mode & 0o777, 0o600)
        self.assertEqual(self.receipt.parent.stat().st_mode & 0o777, 0o700)
        self.assertTrue(self.calls('cli', ('modules', 'enable')))
        scope_set = self.calls('cli', ('scope', 'set'))
        self.assertTrue(scope_set)
        self.assertIn('system/0', scope_set[-1]['args'])
        self.assertIn({'APP_PACKAGE': 'system', 'USER_ID': 0}, self.state()['scope_rows'])

    def test_matching_apk_skips_install_and_records_current_boot(self):
        self.ready_for_next_boot()
        result = self.run_policy('prepare')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(self.calls('pm', ('install',)))
        self.assertEqual(self.receipt.read_text().splitlines(), [BOOT_B, self.digest])
        self.assertFalse(self.calls('setprop'))

    def test_transient_install_failure_retries_then_verifies(self):
        self.configure(install_failures=2)
        result = self.run_policy('prepare')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(len(self.calls('pm', ('install',))), 3)
        self.assertEqual([call['args'] for call in self.calls('sleep')], [['2'], ['2']])
        self.assertEqual(self.installed.read_bytes(), self.apk.read_bytes())
        self.assertTrue(self.receipt.exists())

    def test_permanent_install_failure_stops_after_three_attempts(self):
        self.configure(install_failures=99)
        result = self.run_policy('prepare')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(len(self.calls('pm', ('install',))), 3)
        self.assertEqual([call['args'] for call in self.calls('sleep')], [['2'], ['2']])
        self.assertFalse(self.receipt.exists())
        self.assertFalse(self.calls('setprop'))
        self.assertEqual(list(self.staging.iterdir()), [])

    def test_false_install_success_cannot_create_preparation_receipt(self):
        self.configure(false_install_success=True)
        result = self.run_policy('prepare')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.receipt.exists())
        self.assertNotEqual(self.installed.read_bytes(), self.apk.read_bytes())
        self.assertFalse(self.calls('setprop'))

    def test_successful_enable_output_requires_enabled_readback(self):
        self.configure(module_status='disabled', enable_noop=True)
        result = self.run_policy('prepare')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.receipt.exists())

    def test_scope_set_success_requires_actual_system_user_zero_readback(self):
        self.configure(scope_noop=True, scope_rows=[{'APP_PACKAGE': 'system', 'USER_ID': 10},
                                                  {'APP_PACKAGE': 'android', 'USER_ID': 0}])
        result = self.run_policy('prepare')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.receipt.exists())

    def test_prepare_preflights_unavailable_services_before_install_or_mutation(self):
        for service in ('pm_unavailable', 'cli_unavailable'):
            with self.subTest(service=service):
                self.configure(**dict({'pm_unavailable': False, 'cli_unavailable': False, 'calls': []}, **{service: True}))
                result = self.run_policy('prepare')
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(self.calls('pm', ('install',)))
                self.assertFalse(self.calls('cli', ('modules', 'enable')))
                self.assertFalse(self.calls('cli', ('scope', 'set')))
                self.assertFalse(self.calls('setprop'))
                self.assertFalse(self.receipt.exists())

    def test_prepare_external_commands_have_finite_deadlines(self):
        result = self.run_policy('prepare')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        for call in self.calls():
            if call['name'] not in ('pm', 'cli'):
                continue
            expected = '20' if call['name'] == 'cli' else '15'
            self.assertEqual(call['deadline'], expected, call)
        self.assertTrue(self.calls('timeout'))

    def test_install_timeout_is_bounded_and_leaves_no_receipt_or_staging_file(self):
        self.configure(timeout_commands=['pm install'])
        result = self.run_policy('prepare')
        self.assertNotEqual(result.returncode, 0)
        timeouts = [call for call in self.calls('timeout')
                    if call.get('command', [])[:2] == ['pm', 'install']]
        self.assertEqual(len(timeouts), 3)
        self.assertEqual([call['duration'] for call in timeouts], ['15'] * 3)
        self.assertFalse(self.receipt.exists())
        self.assertEqual(list(self.staging.iterdir()), [])

    def test_start_never_installs_or_reconfigures_and_requires_later_boot(self):
        self.ready_for_next_boot()
        self.boot.write_text(BOOT_A + '\n')
        self.assert_stock(self.run_policy('start'))

    def test_next_boot_activation_requires_real_diagnostic_and_property_readback(self):
        self.ready_for_next_boot()
        result = self.run_policy('start')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.state()['properties']['sys.lightflow.guard'], '1')
        self.assertFalse(self.calls('pm', ('install',)))
        self.assertFalse(self.calls('cli', ('modules', 'enable')))
        self.assertFalse(self.calls('cli', ('scope', 'set')))
        self.assertTrue(self.calls('dumpsys'))
        calls = self.state()['calls']
        enabled_at = max(index for index, call in enumerate(calls)
                         if call['name'] == 'setprop' and call['args'] == ['sys.lightflow.guard', '1'])
        self.assertTrue(any(call['name'] == 'getprop' and call['args'] == ['sys.lightflow.guard']
                            for call in calls[enabled_at + 1:]))

    def test_start_refuses_empty_current_boot_identity(self):
        self.ready_for_next_boot()
        self.boot.write_text('\n')
        self.assert_stock(self.run_policy('start'))

    def test_start_refuses_missing_receipt(self):
        self.ready_for_next_boot()
        self.receipt.unlink()
        self.assert_stock(self.run_policy('start'))

    def test_start_refuses_packaged_apk_changed_since_preparation(self):
        self.ready_for_next_boot()
        self.apk.write_bytes(b'unprepared module update')
        self.assert_stock(self.run_policy('start'))

    def test_start_refuses_installed_apk_changed_since_preparation(self):
        self.ready_for_next_boot()
        self.installed.write_bytes(b'older installed APK')
        self.assert_stock(self.run_policy('start'))

    def test_start_refuses_user_ten_module_even_when_enabled(self):
        self.ready_for_next_boot()
        self.configure(module_rows=[{'PACKAGE': PKG, 'UID': 1010313, 'STATUS': 'enabled'}])
        self.assert_stock(self.run_policy('start'))

    def test_start_cannot_mix_user_ten_enabled_with_user_zero_disabled(self):
        self.ready_for_next_boot()
        self.configure(module_rows=[{'PACKAGE': PKG, 'UID': 1010313, 'STATUS': 'enabled'},
                                    {'PACKAGE': PKG, 'UID': 10313, 'STATUS': 'disabled'}])
        self.assert_stock(self.run_policy('start'))

    def test_other_user_disabled_does_not_reject_enabled_user_zero_module(self):
        self.ready_for_next_boot()
        self.configure(module_rows=[{'PACKAGE': PKG, 'UID': 1010313, 'STATUS': 'disabled'},
                                    {'PACKAGE': PKG, 'UID': 10313, 'STATUS': 'enabled'}])
        result = self.run_policy('start')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_start_refuses_wrong_scope_without_combining_unrelated_rows(self):
        self.ready_for_next_boot()
        self.configure(scope_rows=[{'APP_PACKAGE': 'system', 'USER_ID': 10},
                                   {'APP_PACKAGE': 'android', 'USER_ID': 0}])
        self.assert_stock(self.run_policy('start'))

    def test_start_accepts_android_and_system_scope(self):
        self.ready_for_next_boot()
        self.configure(scope_rows=[{'APP_PACKAGE': 'android', 'USER_ID': 0},
                                   {'APP_PACKAGE': 'system', 'USER_ID': 0}])
        result = self.run_policy('start')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_start_refuses_android_only_scope_even_with_all_runtime_diagnostics(self):
        self.ready_for_next_boot()
        self.configure(scope_rows=[{'APP_PACKAGE': 'android', 'USER_ID': 0}])
        self.assert_stock(self.run_policy('start'))

    def test_start_accepts_system_only_scope_for_system_server(self):
        self.ready_for_next_boot()
        self.configure(scope_rows=[{'APP_PACKAGE': 'system', 'USER_ID': 0}])
        result = self.run_policy('start')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.state()['properties']['sys.lightflow.guard'], '1')

    def test_start_recovers_from_one_transient_vector_inventory_timeout(self):
        self.ready_for_next_boot()
        receipt_before = self.receipt.read_bytes()
        self.configure(inventory_timeouts_remaining=1)
        result = self.run_policy('start')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.state()['properties']['sys.lightflow.guard'], '1')
        probes = [call for call in self.calls('timeout')
                  if call.get('command', [])[:3] == ['cli', 'modules', 'ls']]
        self.assertEqual(len(probes), 2)
        self.assertEqual([call['duration'] for call in probes], ['20', '20'])
        self.assertTrue(probes[0].get('simulated_inventory_timeout'))
        self.assertEqual([call['args'] for call in self.calls('sleep')], [['2']])
        self.assertEqual(self.receipt.read_bytes(), receipt_before)
        self.assertFalse(self.calls('pm', ('install',)))
        self.assertFalse(self.calls('cli', ('modules', 'enable')))
        self.assertFalse(self.calls('cli', ('scope', 'set')))

    def test_start_retains_stock_after_three_vector_inventory_timeouts(self):
        self.ready_for_next_boot()
        self.configure(inventory_timeouts_remaining=3)
        self.assert_stock(self.run_policy('start'))
        probes = [call for call in self.calls('timeout')
                  if call.get('command', [])[:3] == ['cli', 'modules', 'ls']]
        self.assertEqual(len(probes), 3)
        self.assertEqual([call['duration'] for call in probes], ['20'] * 3)
        self.assertTrue(all(call.get('simulated_inventory_timeout') for call in probes))
        self.assertEqual([call['args'] for call in self.calls('sleep')], [['2'], ['2']])

    def test_cold_vector_response_above_five_seconds_fits_twenty_second_budget(self):
        self.ready_for_next_boot()
        self.configure(cli_minimum_seconds=8)
        result = self.run_policy('prepare')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        probes = [call for call in self.calls('timeout')
                  if call.get('command', [])[:1] == ['cli']]
        self.assertTrue(probes)
        self.assertTrue(all(call['duration'] == '20' for call in probes))
        self.assertTrue(all(call['simulated_service_seconds'] == 8 for call in probes))
        self.assertEqual(self.receipt.read_text().splitlines(), [BOOT_B, self.digest])

    def test_activation_bounds_pm_vector_and_diagnostic_reads(self):
        self.ready_for_next_boot()
        result = self.run_policy('start')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        for name, expected in (('pm', '15'), ('cli', '20'), ('dumpsys', '12')):
            probes = self.calls(name)
            self.assertTrue(probes)
            self.assertTrue(all(call['deadline'] == expected for call in probes), probes)
        self.assertEqual(self.calls('dumpsys')[-1]['args'][:2], ['-t', '10'])

    def test_start_refuses_missing_incomplete_or_failed_hook_diagnostics(self):
        self.ready_for_next_boot()
        cases = ({'diagnostic_missing': True}, {'installed_targets': 1},
                 {'installed_targets': 2}, {'installed_targets': 30},
                 {'diagnostic_disabled': True}, {'self_check': 'FAIL'})
        for changed in cases:
            with self.subTest(changed=changed):
                self.configure(diagnostic_missing=False, installed_targets=3,
                               diagnostic_disabled=False, self_check='PASS', calls=[])
                self.configure(**changed)
                self.assert_stock(self.run_policy('start'))

    def test_diagnostic_timeout_cannot_enable_guard(self):
        self.ready_for_next_boot()
        self.configure(timeout_commands=['dumpsys -t'])
        self.assert_stock(self.run_policy('start'))

    def test_failed_enable_property_readback_returns_to_stock(self):
        self.ready_for_next_boot()
        self.configure(ignore_enable_property=True)
        self.assert_stock(self.run_policy('start'))

    def test_status_and_stop_do_not_install_or_reconfigure_vector(self):
        self.ready_for_next_boot()
        previous_receipt = self.receipt.read_bytes()
        result = self.run_policy('status')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(self.calls('setprop'))
        self.assertEqual(self.receipt.read_bytes(), previous_receipt)
        result = self.run_policy('stop')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.state()['properties']['sys.lightflow.guard'], '0')
        self.assertFalse(self.calls('pm', ('install',)))
        self.assertFalse(self.calls('cli', ('modules', 'enable')))
        self.assertFalse(self.calls('cli', ('scope', 'set')))

    def run_customize(self, bootmode):
        customize = self.module / 'customize.sh'
        customize.write_text(self.fixture_source(ROOT / 'module/customize.sh'))
        wrapper = ('abort() { printf "%s\\n" "$*" >&2; exit 73; }; '
                   'ui_print() { printf "%s\\n" "$*"; }; set_perm() { :; }; . "$1"')
        env = dict(self.env, MODPATH=str(self.module), BOOTMODE=bootmode)
        return subprocess.run([self.shell, '-c', wrapper, 'customize-fixture', str(customize)],
                              env=env, capture_output=True, text=True, timeout=20)

    def test_recovery_installer_aborts_before_external_changes(self):
        result = self.run_customize('false')
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(self.calls('pm', ('install',)))
        self.assertFalse(self.calls('cli', ('modules', 'enable')))
        self.assertFalse(self.calls('cli', ('scope', 'set')))
        self.assertFalse(self.calls('setprop'))
        self.assertFalse(self.receipt.exists())

    def test_normal_installer_runs_verified_preparation_before_success(self):
        result = self.run_customize('true')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.receipt.read_text().splitlines(), [BOOT_A, self.digest])
        self.assertFalse(self.calls('setprop'))

    def test_optional_codex_preparation_failure_preserves_guard_receipt(self):
        (self.module / 'codex-launcher.sh').write_text(
            '#!' + self.shell + '\nexit 23\n')
        result = self.run_customize('true')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.receipt.read_text().splitlines(), [BOOT_A, self.digest])
        self.assertIn('Codex launch helper preparation failed', result.stdout)
        self.assertIn('System guard preparation succeeded.', result.stdout)
        self.assertFalse(self.calls('setprop'))

    def test_installer_aborts_when_android_services_unavailable(self):
        self.configure(pm_unavailable=True)
        result = self.run_customize('true')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.calls('pm', ('install',)))
        self.assertFalse(self.calls('cli', ('modules', 'enable')))
        self.assertFalse(self.receipt.exists())


if __name__ == '__main__':
    unittest.main()
