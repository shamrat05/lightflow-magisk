from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]


def packages(path):
    return {
        line.strip()
        for line in path.read_text().splitlines()
        if line.strip() and not line.lstrip().startswith('#')
    }


class NotificationPackagePolicyTests(unittest.TestCase):
    def test_facebook_is_not_kept_alive_but_messenger_is(self):
        entries = packages(ROOT / 'module/notification-packages.conf')
        self.assertNotIn('com.facebook.katana', entries)
        self.assertIn('com.facebook.orca', entries)

    def test_upgrade_migration_resets_the_old_facebook_exemption_once(self):
        source = (ROOT / 'module/service.sh').read_text()
        self.assertIn('facebook-background-exemption-reset-v1.9.4', source)
        self.assertIn('RUN_ANY_IN_BACKGROUND default', source)
        self.assertIn('RUN_IN_BACKGROUND default', source)


if __name__ == '__main__':
    unittest.main()
