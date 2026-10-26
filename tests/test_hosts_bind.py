import ctypes
import errno
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


class HostsBindTests(unittest.TestCase):
    def setUp(self):
        binary = os.environ.get('LIGHTFLOW_HOSTS_BIND_TEST_BINARY')
        if not binary:
            self.skipTest('Native helper is built/tested in GitHub Actions')
        self.binary = binary
        self.tmp = tempfile.TemporaryDirectory()
        self.base = Path(self.tmp.name)
        self.source = self.base / 'source'
        self.target = self.base / 'target'
        self.source.write_text('0.0.0.0 ads.invalid\n')
        self.target.write_text('original\n')
        self.mounted = False

    def tearDown(self):
        if hasattr(self, 'tmp'):
            if self.mounted:
                libc = ctypes.CDLL(None, use_errno=True)
                self.assertEqual(libc.umount2(os.fsencode(self.target), 2), 0)
            self.tmp.cleanup()

    def call(self, *args):
        return subprocess.run([self.binary, *map(str, args)], capture_output=True, text=True)

    def test_verified_readonly_bind_and_original_after_unmount(self):
        result = self.call(self.source, self.target)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.mounted = True
        self.assertEqual(self.target.read_bytes(), self.source.read_bytes())
        self.assertEqual(self.target.stat().st_ino, self.source.stat().st_ino)
        with self.assertRaises(OSError) as failure:
            os.open(self.target, os.O_WRONLY)
        self.assertEqual(failure.exception.errno, errno.EROFS)
        libc = ctypes.CDLL(None, use_errno=True)
        self.assertEqual(libc.umount2(os.fsencode(self.target), 2), 0)
        self.mounted = False
        self.assertEqual(self.target.read_text(), 'original\n')

    def test_source_symlink_is_rejected(self):
        link = self.base / 'link'
        link.symlink_to(self.source)
        self.assertNotEqual(self.call(link, self.target).returncode, 0)
        self.assertEqual(self.target.read_text(), 'original\n')

    def test_target_symlink_is_rejected(self):
        link = self.base / 'link'
        link.symlink_to(self.target)
        self.assertNotEqual(self.call(self.source, link).returncode, 0)
        self.assertEqual(self.target.read_text(), 'original\n')

    def test_directories_and_relative_paths_are_rejected(self):
        self.assertNotEqual(self.call(self.base, self.target).returncode, 0)
        self.assertNotEqual(self.call('source', self.target).returncode, 0)
        self.assertEqual(self.target.read_text(), 'original\n')
