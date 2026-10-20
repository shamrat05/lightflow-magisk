# LightFlow 1.10.0-rc.1

Release candidate: live system_server behavior and battery improvements are
not yet verified. Designed only for RMX3741 / Android 15 / existing Vector.

- Replaces timer-based cache eviction with Zygisk-backed Vector system hooks.
- Gates verified OEM cached/smart-force requests before kill bookkeeping.
- Uses measured available RAM and memory PSI with emergency pass-through and
  recovery hysteresis. High swap utilization alone no longer clears apps.
- Keeps native LMKD, thermal recovery, manual actions, unknown requests and
  special/CPU-hog recovery on their original paths.
- Adds no package retention list, network permissions or background polling.
- Retires automatic/manual `am kill-all` and action-button app compilation.
- Restores only previously managed swappiness; leaves vendor changes intact.
- Rejects archives missing core scripts or the bundled hook APK.
- Provides live `sys.lightflow.guard=0` rollback.

Device evidence: current LightFlow directory contained only metadata and a
package list; its scripts were absent. OEM reason4010 (smart-force) and
CachedClean continued without a LightFlow daemon. CachedClean history recorded
three evictions with 2174 MB available. Termux exit history also contains genuine
low-memory and CPU/empty-limit kills that this RC does not promise to eliminate.

Expected, not yet measured: fewer premature cold launches and less repeated
reload work. More resident cached apps can use more RAM. No claim of 100%
retention, notification delivery, battery improvement or universal smoothness.

Verify after reboot: two LightFlowGuard installed-hook messages, decision
counters under real switching, OEM kill history and social notifications.
