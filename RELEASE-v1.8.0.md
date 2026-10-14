# LightFlow 1.8.0

This release is superseded by [LightFlow 1.9.0](RELEASE-v1.9.0.md), which
merges the safe Android 15 memory-pressure behavior into this single module.

Adds a bounded memory and thermal relief policy for the tested RMX3741.

- Lowers excessive `vm.swappiness` from the observed `160` to `60` when the
  kernel accepts the write, with a saved value and guarded uninstall restore.
- Reports memory availability, ZRAM use, swappiness, thermal status, and live
  CPU, skin, and battery readings through the status action.
- The Magisk action button requests Android cached-process cleanup and selects
  60 Hz only when thermal or memory-pressure thresholds are reached. It does
  not force-stop foreground apps, resize ZRAM, clear caches, change thermal
  limits, lock CPU frequencies, or run a resident monitor.
- Boot applies the swap policy after refresh preferences so a hot phone keeps
  its 60 Hz fallback.

On the tested device, the live diagnostic showed `vm.swappiness=160`, about
4.2 GB ZRAM used, and CPU temperature near 77 C. After reversible relief,
available memory rose above 2 GB, ZRAM use fell to about 2.6 GB, and current
CPU readings fell into the mid-50 C range. These are before/after device
readings under changing workloads, not a controlled battery benchmark.

All 36 policy tests pass. Shell syntax, ZIP creation, and module payload checks
pass. Full reboot persistence remains to be confirmed by the next reboot.
