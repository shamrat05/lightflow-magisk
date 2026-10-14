from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]


class ConsumerPackagePolicyTests(unittest.TestCase):
    def test_optional_list_does_not_contain_protected_runtime_packages(self):
        entries = {
            line.strip()
            for line in (ROOT / 'module/disabled-background-packages.conf').read_text().splitlines()
            if line.strip() and not line.lstrip().startswith('#')
        }
        protected = {
            'android',
            'com.android.phone',
            'com.android.systemui',
            'com.android.providers.telephony',
            'com.google.android.gms',
            'com.google.android.gsf',
            'com.oplus.athena',
            'com.oplus.battery',
            'com.oplus.nas',
            'com.oplus.nhs',
        }
        self.assertTrue(protected.isdisjoint(entries))

    def test_optional_list_has_no_duplicates(self):
        entries = [
            line.strip()
            for line in (ROOT / 'module/disabled-background-packages.conf').read_text().splitlines()
            if line.strip() and not line.lstrip().startswith('#')
        ]
        self.assertEqual(len(entries), len(set(entries)))


if __name__ == '__main__':
    unittest.main()
