from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]


class SystemGuardTests(unittest.TestCase):
    def test_pressure_decisions(self):
        if not shutil.which('javac') or not shutil.which('java'):
            self.fail('JDK required to verify system guard pressure decisions')
        with tempfile.TemporaryDirectory() as directory:
            sources = [ROOT / 'guard/src/dev/lightflow/guard/PressurePolicy.java',
                       ROOT / 'guard/tests/PressurePolicyTest.java']
            subprocess.run(['javac', '-d', directory, *map(str, sources)], check=True,
                           capture_output=True, text=True, timeout=30)
            result = subprocess.run(['java', '-cp', directory,
                                     'dev.lightflow.guard.PressurePolicyTest'],
                                    capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_no_automatic_kill_commands_or_watchdog_start(self):
        for path in (ROOT / 'module').glob('*.sh'):
            executable = '\n'.join(line for line in path.read_text().splitlines()
                                   if not line.lstrip().startswith('#'))
            self.assertNotIn('am kill-all', executable, str(path))
        self.assertNotIn('memory-watchdog.sh" start', (ROOT / 'module/service.sh').read_text())

    def test_guard_has_no_permissions_or_exported_components(self):
        manifest = (ROOT / 'guard/AndroidManifest.xml').read_text()
        self.assertNotIn('uses-permission', manifest)
        for component in ('<activity ', '<service ', '<receiver ', '<provider '):
            self.assertNotIn(component, manifest)

    def test_module_and_guard_versions_match(self):
        metadata = dict(line.split('=', 1) for line in
                        (ROOT / 'module/module.prop').read_text().splitlines() if '=' in line)
        manifest = ET.parse(ROOT / 'guard/AndroidManifest.xml').getroot()
        namespace = '{http://schemas.android.com/apk/res/android}'
        guard_version = (manifest.attrib[namespace + 'versionName'],
                         manifest.attrib[namespace + 'versionCode'])
        if guard_version == (metadata['version'], metadata['versionCode']):
            return

        # Script-only releases may reuse this exact signed RC5 component.
        # A changed guard requires matching versions and a fresh APK build.
        self.assertEqual(guard_version, ('1.10.0-rc.5', '38'))
        self.assertGreater(int(metadata['versionCode']), 38)
        tree = 'b1f67279bbff591d75af382e802602cb7222367d'
        actual_tree = subprocess.run(['git', 'rev-parse', 'HEAD:guard'], cwd=ROOT,
                                     check=True, capture_output=True, text=True).stdout.strip()
        self.assertEqual(actual_tree, tree, 'changed guard must advance its APK version')
        changes = subprocess.run(['git', 'status', '--porcelain', '--untracked-files=all',
                                  '--', 'guard'], cwd=ROOT, check=True,
                                 capture_output=True, text=True).stdout
        self.assertFalse(changes, 'uncommitted guard changes cannot reuse the pinned APK')

        workflow = (ROOT / '.github/workflows/release.yml').read_text()
        self.assertIn(f'if [[ "$(git rev-parse HEAD:guard)" == {tree} ]]; then', workflow)
        reuse = workflow.split('      - name: Reuse verified Actions-built RC5 system guard\n', 1)[1]
        reuse = reuse.split('\n      - name:', 1)[0]
        self.assertIn("if: steps.guard_source.outputs.reuse == 'true'", reuse)
        self.assertIn('set -euo pipefail', reuse)
        self.assertIn("printf '%s  %s\\n' "
                      'bca5f0d896cbb09d6f23c18a2146c48bf6fe1b1ad3dbd521a70111198338b8a4 '
                      '\\\n            "$reuse_dir/guard.apk" | sha256sum -c -', reuse)
        self.assertIn('apksigner" verify --verbose --print-certs '
                      '\\\n            "$reuse_dir/guard.apk" > "$reuse_dir/apksigner.txt"', reuse)
        self.assertIn("grep -Fqx 'Signer #1 certificate SHA-256 digest: "
                      "ef4837bfc6394b1ada8b89ba46f196228441c5665203abd3dad5d01284b3ad7b' "
                      '\\\n            "$reuse_dir/apksigner.txt"', reuse)
