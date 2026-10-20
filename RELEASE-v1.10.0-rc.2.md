# LightFlow 1.10.0-rc.2

RMX3741 / Android 15 / existing Zygisk Next + Vector only.

- Fixes the Codex scheduling integration for the verified `codex-core` route.
  The separate npm `codex` symlink remains intact. Per-target original backups
  prevent restoring an older launcher over the active core.
- Refreshes the current-boot gate, allowing the existing once-per-launch
  nice 5 / efficiency-CPU policy to run. No scheduler daemon or app scans.
- Preserves CLI startup if the helper fails and preserves user-edited files.
  Verified older managed wrappers can migrate and uninstall safely.
- Adds root/shell `dumpsys activity athena lightflow`: installed hooks, real
  request counters, last observation/error and an isolated policy self-check.
  Guard bootstrap and bounded decision/error messages also reach Vector logs.
- Corrects runtime status for the active launcher. Uses Android `ps` when
  stopping the retired watchdog, avoiding Magisk BusyBox column incompatibility.

The pressure policy is unchanged. No display timing, CPU frequency, thermal,
LMKD or social notification policy changes are included.

Device evidence before this fix: native Codex retained nice -10 and CPUs 0-7
because the installer rejected the separate npm symlink before refreshing a
stale boot marker. Controlled scrolling measured 3/898 janky Settings frames
(0.33%) and 15/392 Termux frames (3.83%). Native profiles identified substantial
Termux text rendering work; traces did not establish a universal memory-reclaim
or compositor failure.

Live correction was verified on 97 Codex-related threads: nice at least 5,
allowed CPUs 0-5. Native Codex and its code-mode host retained that state after
switching Settings/Termux, and the real core launcher still started the CLI.
The npm symlink and Termux ownership were preserved.

The repeated scroll sequence measured Settings 3/928 janky frames (0.32%) and
Termux 3/446 (0.67%). Termux p95/p99 frame times increased from 16/21 ms to
23/25 ms, and FrameTimeline still showed queued buffers and deadline misses.
The results are mixed; fewer counted janky frames do not establish universally
faster rendering. Temperature, changing terminal content and adaptive display
behavior also limit this comparison. No all-app smoothness claim is made.

Expected outcome: helper CPU work yields more readily to foreground UI.
Local commands may take longer. Keeping more cached apps can use more RAM.
This release does not establish universal smoothness or battery-life gains.
Updated guard diagnostics take effect after the APK loads at reboot; the
synthetic policy check does not prove live OEM interception or notification
delivery. Use real counters and observed device behavior for those conclusions.
