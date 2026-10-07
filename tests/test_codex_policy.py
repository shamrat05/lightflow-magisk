import hashlib
import os
from pathlib import Path
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
