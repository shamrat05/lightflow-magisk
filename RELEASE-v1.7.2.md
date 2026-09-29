# LightFlow 1.7.2

RMX3741-only userdata read-ahead cap: 128 KiB, down from the observed 512 KiB.

- Resolves the live `/data` device rather than hardcoding a device-mapper number.
- Requires a `userdata` mapping and readable/writable read-ahead control.
- Saves the prior setting once; verifies writes; leaves smaller settings alone.
- Restores on uninstall without overwriting later user/vendor changes.
- Integrates with boot and the read-only status report; no resident process.

Expected benefit is reduced speculative I/O and cache churn in mixed workloads.
Sequential-read throughput may decrease. Real-use speed, app retention, and
battery gains require measurement; a successful setting write does not prove them.

Verified on the rooted RMX3741 without reboot: live 128 KiB readback,
repeat application preserving the original 512 KiB backup, rollback to 512 KiB,
preservation of a later 256 KiB setting, and leaving a smaller 64 KiB value alone.
An unsupported-model check made no change. Boot persistence is wired into the
service but has not been tested by rebooting. Shell syntax and ZIP integrity
checks passed.
