# LightFlow v1.10.0-rc.6.1

## Activate the verified guard without another APK change

RC6 changes deployment scripts. Its guard source and APK remain identical to
RC5: APK version 1.10.0-rc.5 / code 38, module version 1.10.0-rc.6.1 / code 40.
GitHub Actions reuses the RC5 release APK only when the complete `guard` source
tree matches the pinned RC5 tree. It verifies the exact APK SHA-256, signature
and existing signing certificate before packaging. A different source tree
uses the existing fresh build and signing path.

Preparation records the verified installed APK path alongside its boot ID and
hash. Activation hashes that recorded file instead of depending on another
early-boot package-manager query. Preparation retains an earlier boot ID only
when the APK was already identical before preparation, no APK replacement
was attempted, the previous and current hashes agree, and the actual loaded guard
reports both hook targets, diagnostics and a passing policy self-check.
Otherwise the existing preparation and reboot gate remains in effect.

## Observed on this device

- The current boot loaded both guard targets (`installedTargets=3`), exposed
  diagnostics and passed its isolated policy self-check. The guard enabled
  after a manual activation. Registration alone was not used as proof.
- Three bounded boot-time package reads failed; the same package query later
  succeeded manually. The reason remains unknown. Recording and verifying the
  installed APK path removes that read from activation.
- All 53 inspected Codex threads had nice >=5 and allowed CPUs 0–5 after boot.
  The volatile launch token and existing process ownership checks remain.
- After activation, the real counters reached 24 deferred routine cleanup
  requests and zero passed requests, with no recorded hook error and about
  2.1 GiB available RAM. This is a request count, not a count of apps saved.
  It proves callback execution; it does not establish an overall scrolling
  or battery improvement.

## Expected outcome

- This script-only update can activate the already loaded, verified RC5 guard
  without replacing its APK or requiring another reboot.
- Future activation avoids the observed early-boot package read failure while
  retaining byte verification and actual hook diagnostics.
- Codex keeps its existing launch scheduling. Heavy agent work may take longer
  while yielding CPU capacity to foreground apps. No new performance policy,
  thermal bypass or polling worker is added.

## CI correction

The first RC6 workflow stopped at the older test requiring module and APK
versions to match; it published no release. RC6.1 checks the intentional
component-version difference only against the exact unchanged guard source
tree and pinned APK/hash/signature verification contract. Runtime policy and
guard APK remain unchanged.
