# LightFlow 1.6.2

Persist the tested agy agent scheduling policy through a launch hook installed by the Magisk boot service: nice 5 and the smallest CPU-capacity cluster (CPUs 0–5 on RMX3741). The agent continues working; CPU-heavy work may take longer. There is no periodic process scanner or background optimizer.

Only the recognized Termux agy launcher is patched. Its original is backed up, later user edits are preserved, and disable/remove markers bypass the hook for new launches. Uninstall restores an unchanged managed launcher. Existing agent processes keep their current settings until restarted.

Validation: Android shell syntax, actual policy application and repeated application (nice remains 5), CPU mask 3f, launcher install/restore with matching original SHA-256. Battery-life improvement and reboot behavior were not measured.
