# No List Beep

Mute the two long multicontroller list beeps.

Run `list-beep.sh` from the existing launcher for Install/Uninstall dialogs,
or use `sh list-beep.sh install|uninstall|restore|status` in a terminal.
`restore` removes this tweak only; it does not replace the entire target file.
Reboot the CMU after changing GUI code. Restarting Opera alone is not a verified
reload method on the tested vehicle.

This is the original AIO tweak port for 74.00.324. The vehicle behavior was
confirmed on the owner's 74.00.324A EU CMU using the previous installer. This
new standalone targeted installer still needs a vehicle test.

## Targeted changes

The script contains 2 exact context blocks from the verified OEM and
patched versions of `List2Ctrl.js`. Its embedded BusyBox-compatible AWK program
recognizes one complete original or installed state. Missing, duplicate, mixed
or modified patch locations are refused. Only those blocks are replaced; lines
outside them are preserved. A change must pass an inverse byte comparison
before the system file can be written. No on-device diff/patch tool is needed.

The shared adjacent `List2Ctrl.js.org` backup must match the OEM checksum
`e111883b9dcbeb6bb154521826fcacac`. The first tweak creates it only from that exact OEM
file. Existing valid originals are retained. If another tweak is already
installed, its original backup is required. Normal uninstall never copies the
whole backup over the target, so other tweaks remain installed.

Logs, the prepared change and the complete previous-file rollback copy are
written under `logs/list-beep-*/` on the startup USB. Failed writes retry once,
then restore that previous file, including other tweaks. A per-target lock
prevents concurrent writes. System read-only and watchdog states are restored
on exit. USB logging has no internal-storage fallback.

## Tests

`python3 tests/list-beep/run.py` tests the embedded transform against committed
OEM excerpts, status, install/uninstall/restore, idempotency, foreign changes,
unknown/mixed/duplicate contexts, backup failures, write rollback, firmware
gating and installer checksum protection. Mounts, watchdog and commands are
isolated. It never changes the host's system files or starts a real reboot.

With a local complete OEM file, pass its path as the first argument to exercise
the same installer against it. The committed excerpts are test data, not GUI
payloads. Full-file compatibility and combination tests are also performed
locally against the vehicle backup; complete GUI files are not shipped here.
