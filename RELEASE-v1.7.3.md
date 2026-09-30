# LightFlow 1.7.3

Fixes the RMX3741 boot race between LightFlow and Realme's `readahead_init`.
The vendor's boot-completion initializer writes 512 KiB to userdata, which
can overwrite the 128 KiB cap applied by LightFlow 1.7.2.

The boot helper now requires ten seconds of stopped initializer state
before applying the cap. Waiting is bounded to one minute; if the service
does not settle, the helper skips rather than competing with it. There is
no resident polling loop. Immediate apply and rollback remain available.

Verified: vendor init trigger and script, live 128 KiB readback, simulated
initializer-running/stopped and timeout cases, shell syntax, and archive
integrity. Full reboot persistence remains untested. This release does not
claim additional speed, multitasking-capacity, or battery-life gains.
