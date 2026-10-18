# LightFlow v1.9.10

Protect Bitwarden's accessibility/autofill service from ColorOS background
restriction.

## Change

- Adds `com.x8bit.bitwarden` to the existing `RUN_ANY_IN_BACKGROUND` and
  `RUN_IN_BACKGROUND` allowlist applied at boot.
- Keeps every module enabled; no vault data or Bitwarden permissions are
  removed.

## Validation

- Bitwarden AccessibilityService enabled and bound on RMX3741 / Android 15.
- Service remained bound after a manual Android `am kill-all` check.
- Existing LightFlow test suite passes.
