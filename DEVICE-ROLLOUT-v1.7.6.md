# LightFlow 1.7.6 device rollout

Applied to RMX3741, Android 15. This is a mechanical validation report, not an
FPS, battery-life or controlled app benchmark.

## Verified

- Installed module version is 1.7.6 and remains enabled. All 17 installed payload files match the reviewed local source by SHA-256.
- 26 policy tests pass, covering failure reads/writes, rollback, unknown and
  edited launchers, interrupted first-install recovery, boot gating and child
  priority/affinity. Every module shell script passes Android shell syntax.
- A root fixture installation and restoration passed before live installation.
- The installation child runs as Termux UID 10482. Effective, permitted,
  inheritable and ambient Linux capabilities are all zero. `/data/adb` remains
  private; the app UID cannot write the protected staging parent.
- A real `codex --version` invocation verified nice 5 and CPUs 0–5 in both the
  launcher Node process and its native Codex child. It exited without errors.
- The one-time current-agent change saved original attributes before writes.
  All 66 checked threads passed readback. A subsequent check verified 50 living
  launcher, native-agent and tool-host threads. No Android app threads were
  selected. Termux UI retained access to all eight CPUs.
- The live boot gate matches the current boot. Android's freezer and adaptive
  saving remain enabled. Automatic battery-saver trigger mode remains 0.
- MGLRU remains 0x0003, page-cluster remains 0, and both CPU policies retain
  the vendor `sugov_ext` governor. No global CPU boost, thermal override, RAM
  cleaner, extra optimizer schedule or new Zygisk hook was installed.
- Module ZIP CRC, payload bytes and required script execution modes pass.
- Source review resolved privileged staging races, restore validation and UID
  guards. No source blockers remained at final review.

## Limits

Full reboot persistence has not been exercised. Persistence is implemented by
LightFlow's enabled boot service installing/checking the known launcher hook.
Direct native launches and unknown future launcher versions bypass this hook.

The post-update thermal service reported status 2 during active phone work,
with battery temperature 36.7 °C. This is not an idle measurement or evidence
that scheduling caused a temperature change. Foreground smoothness and battery
savings require matched-workload comparisons; neither is claimed here.

## Recovery

A private pre-update copy of the installed module, state and launcher exists
under `/data/adb/lightflow-backups`. The `latest-1.7.6` file names it. That backup
contains root-only `rollback.sh` and `restore-agent-threads.sh` scripts. Thread
restoration checks UID and start time, so exited/reused thread IDs are skipped.
The recovery scripts pass syntax checks; the complete live rollback was not
run because it would undo the installed update.

Diagnostic logs and thread snapshots are local ignored artifacts. They are
not release contents and should not be uploaded. The phone rollout was completed
before the separately authorized GitHub publication.
