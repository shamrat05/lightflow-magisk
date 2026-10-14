# LightFlow 1.9.0

Merges the safe memory-pressure behavior from the A1Memory review into the
existing LightFlow module for Realme RMX3741 / Android 15.

## Compatibility

- Replaces A1Memory's unsupported Android 15 automatic-configuration path with
  `module/memory-pressure-policy.sh`.
- Runs one bounded boot check; no resident memory daemon or recursive service.
- Uses Android's `am kill-all` only below explicit memory, ZRAM, or PSI pressure
  thresholds. Android chooses cached processes that are safe to kill.
- Guards execution to model `RMX3741` and SDK `35`; other devices are no-op.

## Removed from the merged payload

- A1Memory `HC_memory` stripped native executable.
- A1Memory Xposed/LSPosed APK and lmkd hook library.
- A1Memory `system.prop` overrides, UI binaries, updater metadata, and generic
  child-process kill list.
- Separate A1Memory module requirement.

The merged LightFlow ZIP has no network client or downloader. Existing
LightFlow Wi-Fi diagnostics remain manual and unchanged.

## Validation

- Shell syntax checks pass.
- Memory-pressure policy tests cover healthy no-op, high-swap relief, and
  unsupported-device no-op behavior.
- Existing LightFlow policy tests remain required.
- ZIP inspection must contain `memory-pressure-policy.sh` and no `HC_memory`,
  APK, lmkd library, `system.prop`, or UI binary.

This is a pressure-control integration, not a battery benchmark. Android's
thermal governor and active foreground workloads remain outside LightFlow's
control.
