# LightFlow 1.7.0

LightFlow now applies a reversible root-level policy for the whole device:

- Explicit cached-app freezer when ActivityManager reports kernel freezer support.
- Android app standby and adaptive dynamic power saving through the native power service.
- Existing MGLRU and zero ZRAM read-ahead policy retained.
- Read-only status reports raw reclaim, CPU governor/frequency, freezer, pressure, thermal, and adaptive-power state.

The module still has no resident daemon, process scanner, governor/frequency lock, thermal override, ZRAM resize, or blanket app killing. Vendor CPU/core-control and thermal policy remain authoritative. Prior settings are saved and restored by the uninstall script. Full service changes apply after the next Magisk reboot.
