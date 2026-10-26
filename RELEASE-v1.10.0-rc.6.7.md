# LightFlow v1.10.0-rc.6.7

The compact hosts overlay now isolates the target leaf mount before binding.
On this device, Magisk's existing file mount shares a propagation group with
its backing filesystem. Without isolation, an overlay could also appear at
the blocklist owner's source path and prevent updates while active. The
source file's underlying contents were not overwritten; restore recovered
the original list. RC6.7 keeps that source visible and writable throughout.

The native helper is built in GitHub Actions for Android arm64. It pins its
source file, rejects symlinks/unlinked files, performs direct mount syscalls,
and verifies inode, read-only filesystem state and an EROFS write-open result.
It removes only its own bind after failed verification. The policy adds no
daemon or polling, runs once at boot and removes its owned overlay on restore.
The isolated leaf mount remains private until reboot after overlay removal;
the original file contents remain available.

The formatter preserves every ordered address/name mapping, including
duplicates and precedence. Localhost, nonzero records and comments retain
their original lines. Blocked aliases may report their group's first name
with AI_CANONNAME, while their blocking address remains 0.0.0.0. Source-list
updates are used when the overlay is rebuilt after reboot.

Validation includes isolated native mount tests, a shared-mount regression,
policy rollback/ownership fixtures, full mapping comparison, on-device
restore/reapply and DNS latency/CPU comparisons. The existing signed guard
APK is unchanged. Lower resolver CPU use is measured; standby battery-life
and frame-rate gains are not established by these checks.
