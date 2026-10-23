# LightFlow v1.10.0-rc.6.3

## Changes

- Add `radio-scan-policy.sh` to manage `wifi_scan_always_enabled` and
  `ble_scan_always_enabled` together. These allow discovery while the respective
  radio is off; ordinary Wi-Fi/Bluetooth connections are not disabled.
- Reuse the original Wi-Fi backup. Save both original values before applying,
  reject invalid state, verify readback and retain failed restoration backups.
- Bound each settings command to five seconds, with one second to terminate.
  Apply once at boot without a background worker or a periodic enforcer.
- Restore only settings still at the managed value. Preserve later user/vendor
  choices on uninstall. Add actual scan-setting state to the action/status UI.
- Keep the exact signed RC5 guard APK, its source and its loaded hooks unchanged.
  Packaging, signature verification and release remain in GitHub Actions.

## Device verification before release

- Both settings read 1 before application, 0 after application, their original
  values after restoration and 0 after reapplication. Every command succeeded.
- The Wi-Fi client manager, enabled state and active connection remained the
  same through that cycle. The changed scan-availability status line is not
  mistaken for a connection change.
- Ten regression cases cover original state, repeat application, legacy backup,
  missing/null settings, failed reads, invalid/non-file backup paths, failed or
  ineffective writes, restoration retry and later user choices.

## Expected outcome

- Avoid optional discovery while Wi-Fi or Bluetooth is off. Savings depend on
  whether anything was requesting those scans; no percentage gain is claimed.
- Location/discovery features that need scanning while a radio is off are
  unavailable until the setting is restored. Normal connected use is retained.
- No new process, injection engine, notification restriction, cache-killing
  timer, CPU frequency lock or thermal bypass is introduced.
- The script-only policy can be applied to the current boot without a reboot.
  This release does not establish a general scrolling or battery-life gain.

Manual rollback:

```sh
su -c 'sh /data/adb/modules/lightflow/radio-scan-policy.sh restore'
```

The next enabled LightFlow boot reapplies the policy. Disabling a Magisk module
does not itself restore persistent Android settings; use restore or uninstall.

## Sources checked on 2026-10-23

- [AOSP setting definitions](https://android.googlesource.com/platform/frameworks/base/+/0c9a514c20b6a45465aded26c9763ec86b73d701/core/java/android/provider/Settings.java)
- [Android Wi-Fi scanning](https://developer.android.com/develop/connectivity/wifi/wifi-scan)
- [Android power attribution](https://source.android.com/docs/core/power)

The private device usage logs and personal battery report are not release assets.
