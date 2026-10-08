# LightFlow 1.7.7

Adds bKash to the existing targeted ART optimization action and provides a
manual, bounded Wi-Fi latency diagnostic without background probing.

- Official package: `com.bKash.customerapp`. Existing profile-based compilation,
  thermal guards and native Android scheduling are preserved.
- Wi-Fi status sends no test packets. Opt-in probe mode tests the actual IPv4
  Wi-Fi gateway and Cloudflare using twelve requests each, with a fifteen-second
  bound per destination. SSID, MAC and private gateway addresses stay hidden.
- Invalid routes are rejected. Disconnected or IPv6-only links skip IPv4 probes.
- Modern Android no longer receives the unused `wifi_sleep_policy` boot write.
- No radio power-saving override, periodic test, DNS/MTU/TCP forcing or new daemon.

On the tested phone, bKash was already `speed-profile`; no forced repeat compile
was needed. Wi-Fi power saving and scan throttling were enabled, logging was off,
and public samples had no packet loss. One Facebook DNS timeout recovered on
repeat requests. No measured network-speed or battery improvement is claimed.
See [measurement results](WIFI-RESULTS-v1.7.7.md).

Run either command manually when needed:

```sh
su -c 'sh /data/adb/modules/lightflow/wifi-diagnostics.sh status'
su -c 'sh /data/adb/modules/lightflow/wifi-diagnostics.sh probe'
```

Install `LightFlow-v1.7.7.zip` through Magisk Modules. It is not a recovery ZIP.
Controlled battery/performance comparisons and full reboot validation remain
pending. The companion camera module is not changed.
