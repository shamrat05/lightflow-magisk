# LightFlow v1.10.0-rc.5

## Prepared Codex scheduling survives a stale boot marker

Two observed boots left the existing app-owned Codex boot marker unchanged.
The wrapper and helper bytes were correct, but the launch gate silently skipped
the nice/CPU policy. Running the same installer manually after boot succeeded;
the exact earlier failing step was not logged and remains unknown.

The enabled module now publishes the current boot ID in volatile
`sys.lightflow.codex.boot` before slow launcher jobs. A prepared helper reads it
once at launch. A failed property read stops scheduling; explicit `0` or a
stale token rejects even a matching legacy file. Only a successfully empty
property permits the old marker fallback. Uninstall invalidates the property
first. No resident monitor or repeated process scan is added.

The Magisk installer also prepares the known helper interactively before
reboot, preserving the existing launcher hash/template and user-edit checks.
Optional helper preparation is bounded and cannot undo guard preparation.
A boot-time launcher refresh error is now logged instead of silently ignored.
This corrects future launches; changing a token does not reschedule an already
running process.

## Included Vector deployment fix

RC4's literal `system/0` scope, bounded cold-start deadlines, verified APK
preparation and real runtime diagnostic gate are retained. Source, signed APK
and ZIP are built and released through GitHub Actions with the existing key.

## Device observations and expected outcome

- The active Codex wrapper, Node process and native process were corrected
  separately; all 46 observed threads read back nice >=5 and CPUs 0–5.
  Future launches should retain that policy after reboot. Heavy agent work may
  take longer while yielding CPU capacity to the foreground app.
- The shared memory guard is intended to defer needless routine OEM cleanup
  when pressure is healthy. Its actual loaded hooks and callback counters must
  be read after the corrected deployment boots; registration alone is not proof.
- A reversible OEM refresh test reached 60/90/60 Hz after enabling the exact
  Secure override gate found in shipped code. Rendered frames were 343/506/346;
  gfx jank was 1.75%/1.38%/0.87%. Timing and CPU results were affected by warming
  and do not establish a universal improvement or battery saving. The gate and
  test customization were restored; no permanent 90 Hz policy is included.
- No thermal bypass, app-data removal, timed cache killer or per-app keepalive
  list is introduced. Build success alone is not a scrolling or battery result.
