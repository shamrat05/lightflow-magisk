# LightFlow v1.10.0-rc.6.2

## Changes

- Stop optional native `ostatsd`, `ostats_tpd`, and `ostats_pullerd` collection
  through their actual OEM init property switches. Apply only on
  `RMX3741:35:T.R4T2.231124a_d5daf`.
- Record original enable settings, verify each service stops, attempt restoration
  on failure and restore owned settings on uninstall. No resident polling.
- Disable the LFEH diagnostic log encryption/upload package for user 0. Preserve
  the phone's existing user-disabled OLC and OneTrace choices. Keep original
  package data and the existing uninstall restoration mechanism.
- Make optional-package state checks, force-stop and restoration explicitly
  target user 0.
- Expose native collector state through the action button and status script.
- Keep the exact signed RC5 guard APK and its current loaded system_server hooks.
  Builds and packaging remain in GitHub Actions.

## Verified on the actual device before release

- All three native collectors transitioned from enable1/running to
  enable 0/stopped. A real restore returned all three to enable 1/running, then
  reapplication stopped them again. Core phone and thermal Binder services
  remained available; the native thermal service remained running.
- The pre-change 41.3-second process window recorded no CPU ticks for the three
  collectors or modem loggers. Combined OStats PSS at the later check was 179 KiB;
  shared-inclusive RSS is not counted as recoverable RAM.
- LFEH declares log encryption, upload jobs and charging-triggered DCS scans.
  OLC and OneTrace were already user-disabled before this update.
- The read crash-buffer snapshot contained no `FATAL EXCEPTION`, `Fatal signal`
  or `ANR in` entries. This is a bounded observation, not proof of no crashes.

## Expected outcome

- Less optional OEM diagnostic collection, trace handling and upload work.
- Diagnostic log collection/upload features are unavailable while disabled.
- No established large immediate RAM gain, lower temperature, battery gain or
  general scrolling improvement. The measured collectors were quiet; this
  cleanup does not resolve the broader jank investigation.
- No reboot is required to apply these property/package changes. Boot execution
  is integrated into the same LightFlow module; no new injection engine or
  separate module is installed.

Native collector rollback can also be requested manually:

```sh
su -c 'sh /data/adb/modules/lightflow/oem-diagnostics-policy.sh restore'
```

The next enabled LightFlow boot reapplies the policy. Disabling a Magisk module
does not itself reverse persistent settings; use restore or uninstall.
