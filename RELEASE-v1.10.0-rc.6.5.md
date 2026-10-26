# LightFlow v1.10.0-rc.6.5

Superseded by RC6.6. Device deployment found a read-only remount-tool crash;
the policy rolled back and retained the original hosts file. Use RC6.6's
Actions-built native bind helper.

Large per-line hosts lists add parsing work to ordinary Android DNS lookups.
This release adds a read-only compact overlay for the audited RMX3741 Android
15 device's existing `root-hosts-blocker` list. Up to 16 zero-address names
share a line; an ordered mapping digest verifies that no blocked name,
duplicate address record or precedence was lost. Nonzero records and comment
lines are retained. The original blocklist file is not modified or published.

The policy runs once at boot, adds no monitor, skips mismatched source/live
lists and stale deleted mounts, verifies its mounted inode and removes only
its own overlay on uninstall. A later replacement by another owner is
preserved. Source-list updates take effect after reboot, when the overlay is
rebuilt from the current source.

Compatibility: Android's hosts format supports aliases. An `AI_CANONNAME`
lookup of a blocked alias can return the first name on its grouped line;
the blocking address remains `0.0.0.0`. Ordinary permitted lookups and
localhost records retain their address/canonical behavior.

Validation includes an on-device A/B/A latency comparison, sampled blocked
aliases and localhost, full ordered address-map comparison, formatting limits,
mount rollback and ownership-preserving restore fixtures. Standby battery
savings and app frame-rate changes are not established by those checks.
The signed system guard APK and its hook behavior are unchanged.
