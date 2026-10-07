# Responsive agent scheduling

## Objective

Make background Codex work yield to foreground phone apps without a resident
monitor, forced CPU boost, new Zygisk hooks, notification restrictions or changes
to vendor thermal, governor, ZRAM and app-retention policy.

## Evidence

RMX3741 Android 15 runs LightFlow 1.7.5. Freezer and MGLRU are active. The Codex
launcher and native process inherit nice -10 and CPUs 0–7. Existing LightFlow
scheduling covers only agy. Current compile states already include speed-profile
for Instagram, LinkedIn and YouTube. Concurrent root diagnostics contaminate the
initial CPU sample; it is not an idle-power or causal smoothness measurement.

## Requirements

- Back up and patch only the inspected regular Codex launcher, preserving args,
  environment, ownership, permissions and exec/signal behavior.
- An unprivileged launch helper uses nice 5 (preserving lower priority) and the
  available efficiency CPU cluster. No per-launch root call or polling daemon.
- The boot marker gates activity. Disabling the module and rebooting invalidates
  the old marker. Restore only managed files; preserve later user edits.
- Apply the same policy once to the current agent tree, saving thread identity,
  niceness and affinity for explicit restoration. Never touch Android app threads.
- Validate settings reads before backup or mutation. Respect vendor/user control
  of automatic battery-saver trigger mode; report its actual value.
- Test stale boot markers, invalid PIDs, unknown launchers, user edits, idempotent
  setup, restoration and real launch/thread inheritance. Verify module ZIP.
- Separate verified scheduling changes from unmeasured FPS and battery outcomes.

## Completion

Root module files and local source agree. Persistent hook verified by a real test
launch. Current thread readbacks verified. Code and recovery paths reviewed.
Full reboot and controlled app/battery A/B tests remain explicit limitations.
