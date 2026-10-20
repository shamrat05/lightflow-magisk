# LightFlow pressure guard

Owner: device user / Codex. Target: RMX3741 Android 15, installed Zygisk Next + Vector.

# Grill Gate

Problem: recurring LightFlow cached kills in historical logs; live LightFlow incomplete.
OEM CachedClean and smart-force evict apps despite ~2 GB available; Termux has
low-memory, too-many-empty, and child excessive-CPU exits. No package allowlist fix.

Smallest implementation: use existing Vector to gate two verified early OEM requests
inside system_server using real memory/PSI with hysteresis, emergency fail-open.
Remove LightFlow kill timer and all automatic kill-all commands. Do not intercept signals.
Scope only cached/smart-force; unknown, manual, thermal, leak and emergency recovery unchanged.
No network permissions, per-app modules, root IPC in hook, new background workers or scans.

Risk: retaining more cached apps may increase native LMKD pressure. Native LMKD must stay intact;
bad/unknown measurements must preserve stock behavior. Hook failure must log and leave stock.
No claim of 100% notification delivery, performance or battery gains from unit tests.

Acceptance: Java policy tests exercise healthy high swap, transient vs sustained pressure,
emergency, recovery hysteresis, malformed samples, unknown types. Hook validates exact
signatures/return types; bounded diagnostics. Build and release only via GitHub Actions.
Signed artifact verified; package, Vector scope, startup hooks and reboot runtime reported separately.

Verification: python -m unittest; pure javac policy harness; CI APK/ZIP verification;
Vector CLI health/scope; system_server LightFlowGuard logs after reboot; same-app switching
and social notification delivery versus exit-info/killaction history.

## RC2 evidence and implementation scope

Perfetto captured deadline misses in several apps, with distinct causes: actual
app UI work, transient runnable contention and queued buffer presentation.
Controlled Settings scrolling recorded 3/898 janky frames; Termux 15/392.
Native CPU samples identified text layout/drawing in Termux. Stock product
properties explain the 30 ms SF/17 ms app scheduling durations; these are not
measured frame CPU times. No display/kernel/thermal changes are justified.

Confirmed integration defect: the active Codex wrapper executes codex-core,
while the installer checks a separate npm symlink. It exits before refreshing
the boot gate. Native Codex consequently retained nice -10 and CPUs 0-7.
Support only the verified core bytes, with a separate backup namespace; never
replace the npm symlink or user edits. Preserve CLI startup on helper failure.
Accept only known legacy managed wrapper templates when migrating snapshots.

Add read-only guard counters/installation diagnostics and persistent error
logs, without changing pressure decisions or creating polling. AMS clears Binder
identity during dumps; preserve authorized root/shell identity only for the
exact diagnostic and restore nested ThreadLocal state. Synthetic policy checks
must be isolated from live state and invoke no OEM cleanup entry.

Acceptance: execute a managed core with a failing helper; verify Node still
runs. Exercise legacy upgrade/uninstall, npm preservation, user edits, tampered
snapshots, current-boot refresh, per-target backup isolation and idempotence.
Compile the hook against Android 35 and Xposed 82; independent diff review.
Verify actual live native thread priority/affinity, then repeat the controlled
scrolling measurement. Build/sign/release through GitHub Actions; distinguish
live launcher correction from reboot-staged guard diagnostics.
