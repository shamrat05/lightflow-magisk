import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
LAUNCHER = b'''#!/data/data/com.termux/files/usr/bin/sh
export TMPDIR="/data/data/com.termux/files/usr/tmp"
export HOME="/data/data/com.termux/files/home"
export PREFIX="/data/data/com.termux/files/usr"
export PATH="$PREFIX/bin:$PATH"
exec "$PREFIX/bin/node" "$PREFIX/lib/node_modules/@openai/codex/bin/codex.js" "$@"
'''
CORE_LAUNCHER = b'''#!/data/data/com.termux/files/usr/bin/sh
set -eu

: "${PREFIX:=/data/data/com.termux/files/usr}"
export TMPDIR="${TMPDIR:-$PREFIX/tmp}"
export HOME="${HOME:-/data/data/com.termux/files/home}"
export PATH="$PREFIX/bin:$PATH"
exec "$PREFIX/bin/node" "$PREFIX/lib/node_modules/@openai/codex/bin/codex.js" "$@"
'''


class CodexPolicyTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.base = Path(self.tmp.name)
        self.state = self.base / 'root-state'
        self.user = self.base / 'user-state'
        self.target = self.base / 'codex'
        self.boot = self.base / 'boot-id'
        self.boot.write_text('test-boot\n')
        self.target.write_bytes(LAUNCHER)
        self.target.chmod(0o755)
        self.env = dict(os.environ, LIGHTFLOW_CODEX_TARGET=str(self.target),
                        LIGHTFLOW_ROOT_STATE=str(self.state),
                        LIGHTFLOW_CODEX_STATE=str(self.user),
                        LIGHTFLOW_BOOT_ID_FILE=str(self.boot))

    def tearDown(self):
        self.tmp.cleanup()

    def install(self, *args):
        return subprocess.run(['sh', str(ROOT/'module/codex-launcher.sh'), *args],
                              env=self.env, text=True, capture_output=True)

    def use_default_core(self):
        self.env.pop('LIGHTFLOW_CODEX_TARGET')
        self.env['LIGHTFLOW_CODEX_BIN_DIR'] = str(self.base)
        self.target.unlink()
        npm_source = self.base/'npm-launcher.js'
        npm_source.write_text('#!/usr/bin/env node\n// separate npm CLI\n')
        self.target.symlink_to(npm_source)
        core = self.base/'codex-core'
        core.write_bytes(CORE_LAUNCHER)
        core.chmod(0o755)
        return core, npm_source

    def assert_install_ok(self, *args):
        result = self.install(*args)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_fixture_and_install_are_exact_and_idempotent(self):
        self.assertEqual(hashlib.sha256(LAUNCHER).hexdigest(),
                         '5d196fa3898c12cbcccf10337c08f0219ad41197f4af49d13127893c0cfa1216')
        self.assertEqual(self.install().returncode, 0)
        managed = self.target.read_bytes()
        self.assertNotEqual(managed, LAUNCHER)
        self.assertEqual((self.state/'codex-launcher.original').read_bytes(), LAUNCHER)
        self.assertEqual(self.target.stat().st_mode & 0o777, 0o755)
        self.assertEqual((self.user/'codex-boot-id').read_text(), 'test-boot\n')
        self.assertLess(managed.index(b'codex-policy.sh'), managed.index(b'exec '))
        self.assertIn(LAUNCHER.splitlines()[-1], managed)
        self.assertEqual(self.install().returncode, 0)
        self.assertEqual(self.target.read_bytes(), managed)

    def test_interrupted_first_install_recovers_known_helper(self):
        self.assertEqual(self.install().returncode, 0)
        (self.state/'codex-policy.managed').unlink()
        self.assertEqual(self.install().returncode, 0)
        self.assertEqual((self.state/'codex-policy.managed').read_bytes(),
                         (ROOT/'module/codex-policy.sh').read_bytes())

    def test_staging_failure_leaves_launcher_intact(self):
        commands = self.base/'bin'
        commands.mkdir()
        failing = commands/'cat'
        failing.write_text('#!/system/bin/sh\nexit 1\n')
        failing.chmod(0o755)
        self.env['PATH'] = str(commands) + ':' + os.environ['PATH']
        self.assertNotEqual(self.install().returncode, 0)
        self.assertEqual(self.target.read_bytes(), LAUNCHER)
        self.assertEqual(list(self.base.glob('codex.lightflow.*')), [])

    def test_unknown_launcher_is_not_modified(self):
        self.target.write_text('#!/bin/sh\necho user launcher\n')
        original = self.target.read_bytes()
        self.assertEqual(self.install().returncode, 0)
        self.assertEqual(self.target.read_bytes(), original)
        self.assertFalse(self.user.exists())

    def test_uninstall_restores_original_and_removes_gate(self):
        self.assertEqual(self.install().returncode, 0)
        self.assertEqual(self.install('uninstall').returncode, 0)
        self.assertEqual(self.target.read_bytes(), LAUNCHER)
        self.assertFalse((self.user/'codex-boot-id').exists())
        self.assertFalse((self.user/'codex-policy.sh').exists())

    def test_later_user_edits_survive_update_and_uninstall(self):
        self.assertEqual(self.install().returncode, 0)
        edited = self.target.read_bytes() + b'# later user edit\n'
        self.target.write_bytes(edited)
        self.assertEqual(self.install().returncode, 0)
        self.assertEqual(self.target.read_bytes(), edited)
        self.assertEqual(self.install('uninstall').returncode, 0)
        self.assertEqual(self.target.read_bytes(), edited)

    def test_user_helper_edit_is_preserved(self):
        self.assertEqual(self.install().returncode, 0)
        helper = self.user/'codex-policy.sh'
        helper.write_text('# custom helper\n')
        self.assertEqual(self.install().returncode, 0)
        self.assertEqual(helper.read_text(), '# custom helper\n')
        self.assertEqual(self.install('uninstall').returncode, 0)
        self.assertEqual(helper.read_text(), '# custom helper\n')
        self.assertFalse((self.user/'codex-boot-id').exists())

    def test_symlink_launcher_is_rejected(self):
        self.target.unlink()
        source = self.base/'another-launcher'
        source.write_bytes(LAUNCHER)
        self.target.symlink_to(source)
        self.assertNotEqual(self.install().returncode, 0)
        self.assertEqual(source.read_bytes(), LAUNCHER)

    def test_default_npm_symlink_uses_exact_core_without_modifying_npm(self):
        self.assertEqual(len(CORE_LAUNCHER), 307)
        self.assertEqual(hashlib.sha256(CORE_LAUNCHER).hexdigest(),
                         'ecacc9dee620711203c461b926f2cb3bfda63114bf08076752ca9fcb39707217')
        core, npm_source = self.use_default_core()
        npm_bytes = npm_source.read_bytes()
        npm_link = os.readlink(self.target)
        self.assert_install_ok()
        managed = core.read_bytes()
        self.assertNotEqual(managed, CORE_LAUNCHER)
        self.assertLess(managed.index(b'codex-policy.sh'), managed.index(b'exec '))
        self.assertEqual((self.state/'codex-core-launcher.original').read_bytes(), CORE_LAUNCHER)
        self.assertFalse((self.state/'codex-launcher.original').exists())
        self.assertEqual(os.readlink(self.target), npm_link)
        self.assertEqual(npm_source.read_bytes(), npm_bytes)

    def test_core_migration_preserves_legacy_backup_namespace(self):
        self.assert_install_ok()
        old_original = (self.state/'codex-launcher.original').read_bytes()
        old_managed = (self.state/'codex-launcher.managed').read_bytes()
        core, _ = self.use_default_core()
        self.assert_install_ok()
        self.assertEqual((self.state/'codex-launcher.original').read_bytes(), old_original)
        self.assertEqual((self.state/'codex-launcher.managed').read_bytes(), old_managed)
        self.assertEqual((self.state/'codex-core-launcher.original').read_bytes(), CORE_LAUNCHER)
        self.assertIn(b'set -eu', core.read_bytes())

    def test_default_core_reinstall_is_idempotent_and_refreshes_boot_gate(self):
        core, _ = self.use_default_core()
        self.assert_install_ok()
        managed = core.read_bytes()
        self.boot.write_text('next-boot\n')
        self.assert_install_ok()
        self.assertEqual(core.read_bytes(), managed)
        self.assertEqual((self.user/'codex-boot-id').read_text(), 'next-boot\n')
        self.assertEqual((self.state/'codex-core-launcher.original').read_bytes(), CORE_LAUNCHER)

    def test_core_uninstall_restores_core_and_removes_gate_preserving_npm(self):
        core, npm_source = self.use_default_core()
        npm_bytes = npm_source.read_bytes()
        self.assert_install_ok()
        self.assert_install_ok('uninstall')
        self.assertEqual(core.read_bytes(), CORE_LAUNCHER)
        self.assertTrue(self.target.is_symlink())
        self.assertEqual(npm_source.read_bytes(), npm_bytes)
        self.assertFalse((self.user/'codex-boot-id').exists())
        self.assertFalse((self.user/'codex-policy.sh').exists())

    def test_core_user_edits_survive_update_and_uninstall_clears_gate(self):
        core, _ = self.use_default_core()
        self.assert_install_ok()
        edited = core.read_bytes() + b'# later user edit\n'
        core.write_bytes(edited)
        self.assert_install_ok()
        self.assertEqual(core.read_bytes(), edited)
        self.assert_install_ok('uninstall')
        self.assertEqual(core.read_bytes(), edited)
        self.assertFalse((self.user/'codex-boot-id').exists())

    def test_default_unknown_core_and_npm_launcher_are_not_modified(self):
        core, npm_source = self.use_default_core()
        core.write_text('#!/bin/sh\necho user core\n')
        unknown = core.read_bytes()
        npm_bytes = npm_source.read_bytes()
        self.assertNotEqual(self.install().returncode, 0)
        self.assertEqual(core.read_bytes(), unknown)
        self.assertEqual(npm_source.read_bytes(), npm_bytes)
        self.assertTrue(self.target.is_symlink())
        self.assertFalse(self.user.exists())

    def test_default_core_state_symlink_is_rejected(self):
        core, _ = self.use_default_core()
        self.state.mkdir()
        source = self.base/'foreign-backup'
        source.write_bytes(CORE_LAUNCHER)
        (self.state/'codex-core-launcher.original').symlink_to(source)
        self.assertNotEqual(self.install().returncode, 0)
        self.assertEqual(core.read_bytes(), CORE_LAUNCHER)
        self.assertEqual(source.read_bytes(), CORE_LAUNCHER)

    def test_core_rejects_original_backup_from_other_target(self):
        core, _ = self.use_default_core()
        self.state.mkdir()
        (self.state/'codex-core-launcher.original').write_bytes(LAUNCHER)
        self.assertNotEqual(self.install().returncode, 0)
        self.assertEqual(core.read_bytes(), CORE_LAUNCHER)
        self.assertFalse(self.user.exists())

    def test_core_rejects_corrupted_managed_snapshot(self):
        core, _ = self.use_default_core()
        self.state.mkdir()
        (self.state/'codex-core-launcher.original').write_bytes(CORE_LAUNCHER)
        (self.state/'codex-core-launcher.managed').write_text('# wrong target\n')
        self.assertNotEqual(self.install().returncode, 0)
        self.assertEqual(core.read_bytes(), CORE_LAUNCHER)
        self.assertFalse(self.user.exists())

    def test_explicit_target_does_not_switch_to_default_core(self):
        self.env['LIGHTFLOW_CODEX_BIN_DIR'] = str(self.base)
        core = self.base/'codex-core'
        core.write_bytes(CORE_LAUNCHER)
        self.assert_install_ok()
        self.assertNotEqual(self.target.read_bytes(), LAUNCHER)
        self.assertEqual(core.read_bytes(), CORE_LAUNCHER)
        self.assertFalse((self.state/'codex-core-launcher.original').exists())

    def test_legacy_default_without_core_keeps_existing_integration(self):
        self.env.pop('LIGHTFLOW_CODEX_TARGET')
        self.env['LIGHTFLOW_CODEX_BIN_DIR'] = str(self.base)
        self.assert_install_ok()
        self.assertNotEqual(self.target.read_bytes(), LAUNCHER)
        self.assertEqual((self.state/'codex-launcher.original').read_bytes(), LAUNCHER)

    def test_managed_core_still_executes_node_after_policy_failure(self):
        core, _ = self.use_default_core()
        self.assert_install_ok()
        shell = shutil.which('sh')
        failing_helper = self.base/'failing-policy.sh'
        failing_helper.write_text(f'#!{shell}\nprintf attempted > "$LIGHTFLOW_TEST_POLICY_SENTINEL"\nexit 23\n')
        executable = self.base/'managed-core-test'
        managed = core.read_text()
        production_helper = '/data/data/com.termux/files/home/.lightflow/codex-policy.sh'
        self.assertEqual(managed.count(production_helper), 2)
        executable.write_text(managed.replace(production_helper, str(failing_helper)))
        fake_prefix = self.base/'fake-prefix'
        fake_bin = fake_prefix/'bin'
        fake_bin.mkdir(parents=True)
        (fake_bin/'sh').symlink_to(shell)
        node = fake_bin/'node'
        node.write_text(f'#!{shell}\nprintf "NODE:%s\\n" "$@"\n')
        node.chmod(0o755)
        sentinel = self.base/'policy-attempted'
        env = dict(self.env, PREFIX=str(fake_prefix),
                   LIGHTFLOW_TEST_POLICY_SENTINEL=str(sentinel))
        result = subprocess.run([shell, str(executable), 'resume'], env=env,
                                text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(sentinel.read_text(), 'attempted')
        self.assertIn('NODE:resume', result.stdout)

    def test_previous_legacy_managed_template_updates_to_fail_open(self):
        self.assert_install_ok()
        old_managed = self.target.read_bytes().replace(b' "$$" || :\n', b' "$$"\n')
        self.assertNotEqual(old_managed, self.target.read_bytes())
        self.target.write_bytes(old_managed)
        (self.state/'codex-launcher.managed').write_bytes(old_managed)
        self.assert_install_ok()
        self.assertIn(b' "$$" || :\n', self.target.read_bytes())
        self.assertEqual((self.state/'codex-launcher.managed').read_bytes(), self.target.read_bytes())
        self.assertEqual((self.state/'codex-launcher.original').read_bytes(), LAUNCHER)
        self.assert_install_ok('uninstall')
        self.assertEqual(self.target.read_bytes(), LAUNCHER)

    def test_previous_legacy_managed_template_uninstalls_without_upgrade(self):
        self.assert_install_ok()
        old_managed = self.target.read_bytes().replace(b' "$$" || :\n', b' "$$"\n')
        self.target.write_bytes(old_managed)
        (self.state/'codex-launcher.managed').write_bytes(old_managed)
        self.assert_install_ok('uninstall')
        self.assertEqual(self.target.read_bytes(), LAUNCHER)
        self.assertFalse((self.user/'codex-boot-id').exists())

    def test_interrupted_core_template_migration_recovers_next_boot(self):
        core, _ = self.use_default_core()
        self.assert_install_ok()
        installed = core.read_bytes()
        previous = installed.replace(b' "$$" || :\n', b' "$$"\n')
        self.assertNotEqual(previous, installed)
        # App-directory replacement succeeded; root metadata commit did not.
        (self.state/'codex-core-launcher.managed').write_bytes(previous)
        self.boot.write_text('recovered-boot\n')
        self.assert_install_ok()
        self.assertEqual(core.read_bytes(), installed)
        self.assertEqual((self.state/'codex-core-launcher.managed').read_bytes(), installed)
        self.assertEqual((self.user/'codex-boot-id').read_text(), 'recovered-boot\n')
        self.assertEqual((self.state/'codex-core-launcher.original').read_bytes(), CORE_LAUNCHER)

    def test_interrupted_core_template_migration_can_uninstall_directly(self):
        core, _ = self.use_default_core()
        self.assert_install_ok()
        previous = core.read_bytes().replace(b' "$$" || :\n', b' "$$"\n')
        (self.state/'codex-core-launcher.managed').write_bytes(previous)
        self.assert_install_ok('uninstall')
        self.assertEqual(core.read_bytes(), CORE_LAUNCHER)
        self.assertFalse((self.user/'codex-boot-id').exists())
        self.assertFalse((self.user/'codex-policy.sh').exists())

    def test_policy_gate_and_real_process_priority(self):
        self.user.mkdir()
        marker = self.user/'codex-boot-id'
        marker.write_text('old-boot\n')
        child = subprocess.Popen(['sleep', '20'])
        try:
            original = os.getpriority(os.PRIO_PROCESS, child.pid)
            affinity = os.sched_getaffinity(child.pid)
            command = ['sh', str(ROOT/'module/codex-policy.sh'), str(child.pid)]
            stale = subprocess.run(command, env=self.env, capture_output=True)
            self.assertEqual(stale.returncode, 0)
            self.assertEqual(os.getpriority(os.PRIO_PROCESS, child.pid), original)
            self.assertEqual(os.sched_getaffinity(child.pid), affinity)
            marker.write_text('test-boot\n')
            valid = subprocess.run(command, env=self.env, capture_output=True)
            self.assertEqual(valid.returncode, 0, valid.stderr.decode())
            self.assertEqual(os.getpriority(os.PRIO_PROCESS, child.pid), max(original, 5))
            self.assertTrue(os.sched_getaffinity(child.pid).issubset(affinity))
            invalid = subprocess.run(['sh', str(ROOT/'module/codex-policy.sh'), 'bad-pid'],
                                     env=self.env, capture_output=True)
            self.assertNotEqual(invalid.returncode, 0)
        finally:
            child.terminate()
            child.wait(timeout=3)

    def test_already_lower_priority_is_preserved(self):
        self.user.mkdir()
        (self.user/'codex-boot-id').write_text('test-boot\n')
        child = subprocess.Popen(['nice', '-n', '19', 'sleep', '20'])
        try:
            # Wait for the exec/nice operation, without a timed benchmark.
            import time
            for _ in range(50):
                priority = os.getpriority(os.PRIO_PROCESS, child.pid)
                if priority >= 9:
                    break
                time.sleep(.01)
            self.assertGreaterEqual(priority, 9)
            result = subprocess.run(['sh', str(ROOT/'module/codex-policy.sh'), str(child.pid)],
                                    env=self.env, capture_output=True)
            self.assertEqual(result.returncode, 0)
            self.assertEqual(os.getpriority(os.PRIO_PROCESS, child.pid), priority)
        finally:
            child.terminate()
            child.wait(timeout=3)


if __name__ == '__main__':
    unittest.main()
