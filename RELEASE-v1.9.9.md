# LightFlow 1.9.9

Protect active camera and QR scans from cached-process cleanup on RMX3741 / Android 15.

## Change

- Skip LightFlow's bounded `am kill-all` request while the ColorOS native QR
  scanner, ML Kit scanner activity, or a supported camera client is active.
- Log the skip with the current memory and ZRAM measurements.
- Keep the existing cleanup thresholds, cooldown, Android process selection,
  and module state unchanged outside camera sessions.

## Validation

- Android shell syntax passes on both the installed module and update copy.
- Policy tests cover healthy no-op, pressure cleanup, cooldown, unsupported
  device, and active camera/QR protection.
- The installed module remains enabled; no Magisk/Zygisk module is disabled.
