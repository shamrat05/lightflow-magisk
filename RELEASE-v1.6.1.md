# LightFlow 1.6.1

The optimization action previously omitted YouTube and forced repeat compilation while hiding ART's output. It now includes YouTube alongside Facebook, Reddit, WhatsApp, WhatsApp Business, and LinkedIn, uses background priority when supported, and lets ART skip current artifacts. A battery-temperature check stops new requests at 40 °C.

The boot service now waits for boot completion with a bounded check. A new on-demand `status.sh` reports display policy, memory pressure, temperature, and compilation state. No resident optimizer, CPU boost, thermal override, or forced high-refresh floor was added.

Validation on RMX3741:

- Android shell syntax checks and ZIP integrity checks passed.
- The updated service ran successfully on the already booted phone. A reboot was not performed.
- ART reported `speed-profile` / `PERFORMED` for YouTube, Facebook, Reddit, WhatsApp Business, and LinkedIn; WhatsApp was already current and skipped.
- A repeat YouTube request returned `SKIPPED` with zero compiler CPU time.
- The read-only status script ran successfully.

These checks verify operation, not a measured improvement in scrolling or battery life. Compilation uses power once. A separate CPU-heavy terminal agent remains a possible source of contention; it was left running. Actual refresh rate remains controlled by apps and vendor policy.
