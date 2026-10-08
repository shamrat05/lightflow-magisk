import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]


class WifiDiagnosticsTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory()
        self.base=Path(self.tmp.name)
        self.bin=self.base/'bin'
        self.bin.mkdir()
        self.log=self.base/'probes'
        self.env=dict(os.environ,PATH=str(self.bin)+':'+os.environ['PATH'],
                      WIFI_TEST_LOG=str(self.log), WIFI_TEST_DEADLINES=str(self.base/'deadlines'),
                      WIFI_TEST_ROUTE='default via 192.168.7.1 dev wlan0 table 1010',
                      WIFI_TEST_PING_EXIT='0')
        commands={
            'cmd':'''#!/system/bin/sh
if [ "$2" = status ]; then
  echo 'Wifi is enabled'
  echo 'Wifi is connected to "Private AP"'
  echo 'WifiInfo: SSID: "Private AP", BSSID: aa:bb:cc:dd:ee:ff, RSSI: -59, Link speed: 864Mbps, Frequency: 5805MHz, IP: 192.168.7.9'
  echo 'WifiInfo: RSSI: -55, Link speed: 720Mbps, Frequency: 5805MHz, IP: 192.168.7.9'
else
  echo disabled
fi
''',
            'ip':'''#!/system/bin/sh
printf '%s\n' "$WIFI_TEST_ROUTE"
''',
            'timeout':'''#!/system/bin/sh
printf '%s\\n' "$1" >> "$WIFI_TEST_DEADLINES"
shift
exec "$@"
''',
            'ping':'''#!/system/bin/sh
printf '%s\n' "$*" >> "$WIFI_TEST_LOG"
echo 'PING private-router (192.168.7.1)'
echo '12 packets transmitted, 12 received, 0% packet loss, time 11000ms'
echo 'rtt min/avg/max/mdev = 5/10/20/2 ms'
exit "$WIFI_TEST_PING_EXIT"
'''}
        for name,source in commands.items():
            p=self.bin/name;p.write_text(source);p.chmod(0o755)

    def tearDown(self):self.tmp.cleanup()

    def run_diagnostic(self,*args):
        return subprocess.run(['/system/bin/sh',str(ROOT/'module/wifi-diagnostics.sh'),*args],
                              env=self.env,capture_output=True,text=True)

    def test_status_has_no_probe_traffic_and_hides_network_identity(self):
        p=self.run_diagnostic()
        self.assertEqual(p.returncode,0)
        self.assertFalse(self.log.exists())
        self.assertIn('Signal: -59 dBm',p.stdout)
        self.assertIn('Negotiated link: 864 Mbps',p.stdout)
        self.assertIn('Frequency: 5805 MHz',p.stdout)
        self.assertEqual(p.stdout.count('Signal:'),1)
        self.assertEqual(p.stdout.count('Negotiated link:'),1)
        for private in ('Private AP','aa:bb','192.168'):self.assertNotIn(private,p.stdout)

    def test_manual_probe_is_bound_to_wifi_and_finite(self):
        p=self.run_diagnostic('probe')
        self.assertEqual(p.returncode,0)
        calls=self.log.read_text().splitlines()
        self.assertEqual(len(calls),2)
        self.assertEqual((self.base/'deadlines').read_text().splitlines(), ['15','15'])
        for c in calls:self.assertIn('-I wlan0 -c 12 -i 1 -W 2',c)
        self.assertTrue(calls[0].endswith('192.168.7.1'))
        self.assertTrue(calls[1].endswith('1.1.1.1'))
        self.assertIn('0% packet loss',p.stdout)
        self.assertNotIn('192.168',p.stdout)
        self.assertNotIn('private-router',p.stdout)

    def test_missing_ipv4_route_skips_all_probes(self):
        self.env['WIFI_TEST_ROUTE']=''
        p=self.run_diagnostic('probe')
        self.assertEqual(p.returncode,0)
        self.assertIn('No IPv4 Wi-Fi gateway',p.stdout)
        self.assertFalse(self.log.exists())

    def test_non_wifi_route_does_not_probe(self):
        self.env['WIFI_TEST_ROUTE']='default via 10.0.0.1 dev tun0'
        self.assertEqual(self.run_diagnostic('probe').returncode,0)
        self.assertFalse(self.log.exists())

    def test_malformed_gateway_is_rejected_before_packets(self):
        for addr in ('192.168.1.999','192.168.1.1.','192..1.1','example.com','1.1.1'):
            with self.subTest(addr=addr):
                self.env['WIFI_TEST_ROUTE']=f'default via {addr} dev wlan0'
                self.assertNotEqual(self.run_diagnostic('probe').returncode,0)
                self.assertFalse(self.log.exists())

    def test_probe_failure_is_reported(self):
        self.env['WIFI_TEST_PING_EXIT']='1'
        p=self.run_diagnostic('probe')
        self.assertEqual(p.returncode,1)
        self.assertIn('ICMP can be blocked',p.stdout)

    def test_unknown_mode_is_rejected(self):
        self.assertEqual(self.run_diagnostic('always-on').returncode,2)
        self.assertFalse(self.log.exists())


if __name__=='__main__':unittest.main()
