import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


class WeatherScopeTests(unittest.TestCase):
    def check_skip(self, packages):
        # Scope must be checked before app-ops are queried or modified.
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            marker = root / 'appops-called'
            shell = shutil.which('sh')
            commands = {
                'getprop': "printf 'RMX3741\\n'\n",
                'pm': "cat <<'PACKAGES'\n" + packages + '\nPACKAGES\n',
                'cmd': f'touch "{marker}"\nexit 1\n',
            }
            for name, body in commands.items():
                path = root / name
                path.write_text('#!' + shell + '\n' + body)
                path.chmod(0o755)
            script = Path(__file__).parents[1] / 'module/weather-policy.sh'
            result = subprocess.run([shell, str(script), 'apply'],
                                    env=dict(os.environ, PATH=str(root) + os.pathsep + os.environ['PATH']),
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertFalse(marker.exists())

    def test_shared_uid_is_not_restricted(self):
        self.check_skip('package:com.coloros.weather.service uid:10173\n'
                        'package:another.app uid:10173')

    def test_missing_weather_package_is_not_restricted(self):
        self.check_skip('package:another.app uid:10173')


if __name__ == '__main__':
    unittest.main()
