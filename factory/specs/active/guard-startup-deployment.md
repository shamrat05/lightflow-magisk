# Guard startup deployment

Owner: device user / Codex. Target: RMX3741 Android 15 with existing Vector/Zygisk Next.

## Grill Gate

Problem: on verified boot `9ee986b4-e8a1-472c-abd7-a88158f236cc`, Vector loaded the older installed guard into system_server before LightFlow service attempted its APK update. The update failed with `Failed transaction (2147483646)` and left sys.lightflow.guard=0. Installed and packaged hashes differed. The identical APK installed successfully later in that boot. Installing the guard after system_server starts also requires another restart before updated code can load.

Smallest acceptable implementation: prepare the signed guard APK and Vector scope during interactive Magisk installation, before the planned reboot. Record prepared boot ID and verified APK hash. Never install an APK from boot activation. Activate only on a different boot with matching installed bytes, correct scope, both runtime hooks, and passing isolated policy check. Keep all PM/Vector calls bounded and fail with a useful error. A preparation does not claim live hook activation.

Riskiest assumption: package registration can differ from code already loaded in system_server. Boot identity plus an actual read-only diagnostic must gate activation. Failed preparation can leave a verified helper APK installed; report this partial result rather than uninstalling data or claiming rollback.

Out of scope: changing pressure thresholds, thermal or CPU policies, refresh overrides, per-app keepalive lists, new polling, app data removal, forced system_server restart, or automatic reboot. This fixes deployment of the existing system-level optimization, not all scrolling jank.

Decisions: use documented BOOTMODE/MODPATH/abort installer API; require normal Android/Magisk app installation, not recovery. Preflight Android PM and Vector before external changes. Use unique temporary staging, verified hashes, bounded retries, accurate scope readback requiring Vector’s literal system/0 entry, and atomic root-private preparation receipt.

Acceptance criteria:

- Fresh preparation installs once, verifies actual bytes and scope, and leaves runtime enable unchanged.
- Matching APK avoids reinstall but still records the planned activation boot boundary.
- Temporary install error retries within fixed per-command deadlines; permanent failures cannot write a valid new receipt or claim preparation success.
- Successful command output with wrong APK bytes fails verification.
- Wrong-user scope and disabled/missing module readback cannot enable protection.
- Same-boot activation is refused; a later boot requires matching receipt/package/installed hashes and successful real hook diagnostics before property1 is written.
- Missing diagnostic, incomplete hook mask, failed self-check, or failed property readback leaves stock policy enabled.
- Recovery/unavailable services abort before external changes; staged files and normal updates retain executable permissions.
- Build/sign/release in GitHub Actions, preserve installed signing identity, install resulting release before requesting another user reboot.

Verification commands: targeted Python deployment tests; existing system guard policy tests; portable release test gate; shell syntax checks; independent diff review through Loop Factory. Device evidence must distinguish prepared APK, running system_server code, and real cleanup callbacks. Never invoke a cleanup action merely to make a counter increase.

## RC4 correction from actual device and framework source

RC3's reboot did not load the module. Exact Vector 3080 commit `88f8e1fa` shows `ModuleDatabase.systemServerModuleRows()` querying only `app_pkg_name="system"`; ConfigCache maps that row to system_server. The CLI scope setter deletes previous entries before writing its supplied list. The earlier assumption that android/0 automatically expands into system/0 was false and is rejected by the revised test fixture. Require system/0 in readback; preserve android/0 additionally for package compatibility.

Live CLI module inventory also exceeded the original five-second deadline. PM reads now have fifteen-second deadlines, CLI reads/writes twenty seconds, and the diagnostic twelve seconds with its own ten-second dumpsys timeout. Transient package read failures retry at most three times without installing anything during boot. Exact Vector legacy callback source confirms packageName="android" and the server ClassLoader, so the Java entry filter remains correct.


## RC6 correction from the loaded RC5 reboot

Boot782e8d32 loaded all three hook bits, real procfs memory observation and the
read-only self-check. The boot helper nevertheless failed three package reads.
The exact same helper later passed and enabled the guard on this boot. The
transient failure source remains unknown; do not guess it was credential unlock.

New preparation stores the verified installed APK path in a third root-private
receipt line. Startup validates the Android package path and hashes that file,
removing the failing package-service transaction. Tampered, deleted or changed
files fail with stock behavior. Legacy two-line receipts keep their fallback.

A script-only update can preserve an existing prior-boot preparation only when
its exact APK hash is unchanged and real loaded hook diagnostics pass. This
allows the corrected bootstrap to activate without replacing the running APK
or requesting another reboot. The CI cache accepts only the exact unchanged
guard tree and the pinned, signature-verified Actions-built RC5 APK; other
source trees use the normal fresh signed build. Component APK38 and module39
versions intentionally differ. Regression checks cover absent PM, path
validation, byte changes and preservation/refusal of the existing boundary.
