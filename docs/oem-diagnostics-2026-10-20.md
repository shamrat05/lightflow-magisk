# RMX3741 optional diagnostics audit — 2026-10-20

## Identity and scope

Actual device: RMX3741, Android 15/API35,
`RMX3741_15.0.0.1820(EX01)`, incremental `T.R4T2.231124a_d5daf`.
Kernel and sampled vendor module agree on
`6.6.82-android15-8-o-g3b30dff93dd7-4k`; the older public 4.19 source is not a
matching basis for kernel changes. This audit is bounded, not a full kernel or
OS correctness review. Private runtime traces and APKs are not published.

## Observed optional collection

The actual `/system_ext/etc/init/ostatsd.rc`, `ostats_tpd.rc`, and
`ostats_pullerd.rc` declare disabled-by-default init services with explicit
post-boot start/stop triggers on `persist.sys.<service>.enable=1/0`.
All three switches were 1 and services running before the change.

Shipped ELF identities:

| File | SHA-256 |
| --- | --- |
| ostatsd | `80b59132da08c1316d7159ebcec9d59413d3630864365c8f558bd5664f0dd004` |
| ostats_tpd | `555699034293c478a4936c11fef8a68e3f675d94014000e542866df391133deb` |
| ostats_pullerd | `4c92dcecc6388903553eeadb7b128b7aa9de87627cb4561941152b15ff247d30` |

Actual symbols/strings show trace events, statistics pulls, report compression
and DCS uploads. Thermal analysis reads temperature/status; the native thermal
controllers are separate processes and are not policy targets. Strings alone
do not prove every execution path. REA retained the puller symbol inspection as
`ev_9cb7526b37bb9798d4ffd90f9428bf66ce636eb7b7624da1043bf1a396db1865`;
the actual inspector was LLVM objdump (REA adapter label `gnu.objdump`).

LFEH 1.2.5, APK SHA-256
`3aa64477105a23529e4e864e1a4ab5b2bb85e2e67cd1b1e6b5f63a6c17f9a40b`,
declares `LogFileEncrypterService`, `UploadJobService`, a DCS scan receiver and
a charging receiver. These are diagnostic collection/upload roles, not phone,
launcher or social notification services. Package data is preserved.

OLC 15.0.67 and OneTrace 1.3.46 were already disabled for user 0 (`enabled=3`).
Their original disabled choice must not become an enabled choice on uninstall.
The existing per-package ownership receipts preserve that distinction.
GlobalSearch is retained: it has an actual launcher search function, although
its APK also declares preload, keepalive and advertising components. NAS/NHS
are retained because their manifests expose network, telephony and modem roles.

QualityProtect 15.0.79 remains enabled. Focused REA inspection of
`AbnormalEventDispatchService.b` shows jank-event dispatch via Messenger, not a
proven runaway loop. Evidence:
`ev_b937c8a28970697cc81d4c0dcddef201bc35848747b9d84a549ee7558c2c285c`.
The decompiler warned about duplicate blocks; those warnings do not prove a
firmware bug. No active QualityProtect service appeared in the sampled dump.

## Resource limits

- Process CPU deltas over 41.3 seconds: no measurable OStats/modem-logger CPU.
  This cannot exclude occasional future jobs.
- Later combined PSS of the three collectors: 179 KiB; logical SwapPss 3,760 KiB.
  Shared libraries in summed RSS are not fully recoverable physical RAM.
- Earlier process ownership census: about 2.85 GiB total process PSS. Roughly
  4.02 GiB logical compressed data occupied about 1.54 GiB actual ZRAM allocation.
  This does not establish 4–5 GiB of removable OEM waste.
- Whole-device CPU sampling found 64.34% idle capacity in its capture. Termux's
  visible text rendering and Codex accounted for more CPU than optional loggers.
  This does not prove idle behavior in all circumstances.

## Implementation and validation

`oem-diagnostics-policy.sh` changes only the three audited enable switches.
An exact firmware gate protects application; stopped state is verified with a
finite wait. Unknown values remain unchanged. Existing disabled settings are
not claimed. Failed stops attempt rollback; failed rollback receipts remain.
Restore preserves later re-enabling. There is no background monitor.

Live apply→restore→apply succeeded for all three collectors. Phone and thermal
Binder endpoints remained available, and native thermal control kept running.
These checks do not substitute for measured frame/battery results.

## Remaining questions

- No shared native scheduling/graphics defect has been established by the
  sampled profiles. No blanket C++/Zygisk performance hook is installed here.
- Frequency QoS tracing showed changing touch minimum votes and many unchanged
  maximum requests. Instant min=max observations did not prove a permanent lock.
- Removing the OEM's AUTO 60 Hz fallback is not yet a complete correction: later
  VRR logic can reintroduce 60 Hz. No unverified refresh hook ships in RC6.2.
- This cleanup prevents optional collection; broad scrolling and battery goals
  remain unproven and are not claimed as achieved by this release.
