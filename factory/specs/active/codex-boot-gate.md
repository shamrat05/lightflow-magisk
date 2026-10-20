# Codex boot gate

Owner: device user / Codex. Target: prepared Termux launcher on RMX3741 Android15.

## Grill Gate

Observed failure: after two device reboots, the known wrapper/helper remained
correct but its app-owned boot marker was from an earlier boot. Every new
launch therefore skipped scheduling. Manual setup later succeeded. The exact
boot-time failure remains unknown; do not present credential unlock as proven.

Smallest correction: publish the current boot ID in a volatile system property
once, before slow boot jobs. Prepare the known helper during interactive module
installation. At launch, a failed property read refuses changes, nonempty
values must match current boot, and only empty property uses the old marker.
Uninstall publishes explicit0 before other work. Existing ownership, template,
priority and CPU-affinity protections remain. No process monitor is added.

Riskiest assumption: helper preparation and runtime publication are distinct.
The actual installed helper must match the release before reboot, and an
already running process is not fixed by changing the token.

Acceptance: actual-child regression checks cover matching token with missing
or stale marker, explicit0/stale token overriding a valid marker, failed read,
legacy fallback and preservation of lower priority. Source tests use a fake
property command rather than live device state. Device checks verify actual
property readback and helper bytes before requesting reboot. GitHub Actions
builds and signs the final ZIP; review the diff before installation.

Out of scope: UI priority changes, root app-directory writes, forced reboot,
universal jank elimination, unknown-launcher replacement or thermal overrides.
