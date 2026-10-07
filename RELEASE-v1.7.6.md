# LightFlow 1.7.6

Makes Codex agent work yield CPU time to foreground phone apps. It extends the
existing agent scheduling approach to the exact inspected Termux launcher,
without a resident optimizer or new Zygisk module.

## Behavior

- Request nice 5, preserving an already lower scheduling priority.
- Use the lowest-capacity CPU cluster when Android exposes a heterogeneous
  topology. On this RMX3741 that means CPUs 0–5, instead of CPUs 0–7.
- New threads and child commands inherit the policy. Agent CPU work may take
  longer; Termux UI and Android app threads are not changed.
- Run once at launch, as Termux, without a root prompt or background monitor.
- Skip unknown launchers. Preserve later user edits and app SELinux labels.
- Gate the hook with the boot ID written by the enabled module's boot service.
- Keep the vendor CPU governor, thermal protection, ZRAM size and memory policy.

Power-state backups now reject failed, empty and unknown reads. Restoration
validates saved states and retains backups if restoring fails. The module no
longer requests a particular automatic battery-saver trigger; it leaves that
selection to the user and vendor while enabling adaptive saving independently.

## Recovery

Uninstall restores the original Codex launcher only while it matches the
managed copy. Disable/remove the module and reboot to invalidate the launch
gate. Already running agents keep their inherited scheduling until restarted.
Changing an active session back to its saved negative nice priority requires
root; the on-device rollout saves thread identities and original attributes
before making that one-time change.

## Validation boundary

Source policy tests and shell syntax checks pass. Mechanical on-device checks
are recorded in [the device rollout report](DEVICE-ROLLOUT-v1.7.6.md). No measured FPS improvement, battery
saving, full reboot test, or zero-lag guarantee is claimed. Compare the same app
interaction at similar brightness, temperature and background workload before
attributing an improvement to these settings.

Install `LightFlow-v1.7.6.zip` through Magisk Modules. It is a Magisk module
package, not a custom-recovery installer. This release does not update the
companion camera module.
