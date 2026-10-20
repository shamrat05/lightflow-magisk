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
        self.assertEqual(manifest.attrib[namespace + 'versionName'], metadata['version'])
        self.assertEqual(manifest.attrib[namespace + 'versionCode'], metadata['versionCode'])
