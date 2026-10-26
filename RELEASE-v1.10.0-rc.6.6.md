# LightFlow v1.10.0-rc.6.6

Large per-line hosts lists add parsing work to ordinary Android DNS lookups.
This release provides the verified compact-overlay formatter from RC6.5 with
a native read-only bind helper built in GitHub Actions for Android arm64.
The helper pins its source file, rejects symlinks and unlinked files, uses
direct bind/remount syscalls, verifies the resulting inode and read-only
filesystem flag, and removes only its own mount after a failed verification.

This corrects RC6.5's device-runtime deployment failure: mount tools that
consulted filtered `/proc/mounts` failed or crashed during read-only remount.
RC6.5 rolled its overlay back, preserving the original blocklist.

Up to 16 zero-address blocked names share a line. The formatter verifies every
ordered address/name mapping and leaves the source list untouched. Localhost,
nonzero records and comments retain their original lines. The policy runs
once at boot with no daemon, polling or additional network traffic. It skips
mismatched source/live lists and stale deleted mounts. Uninstall removes only
the overlay whose inode still belongs to LightFlow. Source-list updates are
picked up when the overlay is rebuilt after reboot.

An `AI_CANONNAME` lookup of a blocked alias can return the first name of its
group; the blocking address remains `0.0.0.0`. Permitted lookups and localhost
retain their existing address/canonical behavior.

Validation includes the native helper's mount/unmount and rejection tests in
an isolated CI mount namespace, policy rollback/ownership fixtures, full
ordered-map comparison, and on-device DNS A/B/A comparisons. Lookup latency
improvement is measured; standby battery savings and app frame-rate changes
are not established by those tests. The signed system guard APK is unchanged.
