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
