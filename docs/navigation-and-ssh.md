# Navigation tweaks and SSH

## Integration

The navigation changes are targeted ports of the original community AIO
`list-beep`, `shorter-delay`, `list-loop`, and `main-menu-loop` tweaks. The v74
OEM files are retained; only those changes are applied. No new vehicle GUI
helpers or event handlers were added.

The installers follow this project's `jci-dialog`, `.md5`, `jci-org`,
`jci-mods`, and adjacent `.org` backup conventions. There is no external AIO
installer, file manager, installed-state database, or web-builder dependency.

All three list settings modify the same file. `List2Ctrl-N.js` identifies a
prebuilt combination: bit 1 means no beep, bit 2 shorter delay, bit 4 loop.
`list-tweaks.sh` identifies the current combination by checksum, changes the
chosen bit, and copies the verified corresponding payload. The original `.org`
backup remains until all three settings are removed. Unknown file versions and
missing or corrupt originals are rejected. A USB rollback copy retains the
previous entire combination if a write fails.

The Python scripts in `jci-patches/` reproduce the distributed navigation
payloads from the exact OEM files. `list-loop-functions.js` contains only the
four original AIO handlers used by the loop port. It is build input and is not
injected separately into the GUI.

## SSH

`ssh.sh` installs the native-OpenSSH service payload in `services/ssh/` and
adds the boot call to the verified original `stage_wifi.sh`. The original is
saved as `stage_wifi.sh.org`. Existing unknown startup scripts, modified service
payloads, and unrelated port-22 listeners are refused. In particular, an SSH
service from another installer is not silently adopted or replaced.

The supervisor uses an absolute `sshd` executable path (required by native
OpenSSH), its own firewall chain and process records, and a password overlay in
RAM. It binds to all IPv4 addresses and has no dependency on a WLAN interface
or address being present when it starts. It does not enable Wi-Fi or connect
to a network. The factory host key and account file are preserved.

This is access after the normal startup sequence reaches `stage_wifi.sh`, not
a guarantee of recovery from earlier boot failures. User `cmu` has uid 0. The
default password is `jci`; only use this on a network where that is acceptable.

## Vehicle evidence (2026-10-22)

On one CMU running **74.00.324A EU**:

- Main-menu loop was installed alone, confirmed by the owner, and uninstalled
  with the exact OEM checksum restored.
- The three list options were installed together. Their combined MD5 was
  `c02699ee8cf22def4393ff09c5a85f06`; the owner confirmed their effects.
- The SSH service implementation allowed a real password login on port 22,
  started after full reboot, and worked without USB attached. The absolute
  executable-path fix is included here.
- Ordinary `reboot` over SSH brought the display back and retained the saved
  WLAN connection. Restarting Opera alone produced a black display even with
  original GUI files restored; use full reboot for these tests.

Those tests used the earlier installer. The new dialog installers, resource
directory, boot-hook integration, and release packaging in this contribution
still need a vehicle test. Not every list combination has a vehicle test.
Boot with Wi-Fi absent or disabled has isolated tests, not a hardware test.
Other firmware versions and regional builds have not been validated.

## Automated checks

- `python3 tests/navigation/run.py`: all 48 per-setting transitions across the
  eight list combinations, selective uninstall, `.org` originals, unknown-file
  rejection, missing/corrupt backups, damaged payloads, failed-copy rollback,
  firmware refusal, main-menu install/uninstall, and SSH installer orchestration
  with a stand-in service. Reproduces all navigation payloads from OEM input.
- `python3 tests/ssh-service/run.py`: the real supervisor with fake kernel,
  network, firewall and sshd commands. Covers unavailable WLAN, later address
  changes, another listener, duplicate start, account-overlay cleanup, failed
  startup and firewall-rule recovery. It never starts a real SSH server.
- The existing BusyBox installer suite also exercises `main-menu-loop.sh`.
- Existing checksum and JS syntax jobs cover the new payloads. The release
  workflow includes `services/`, so SSH runtime files and its USB log marker
  are present in the downloadable package.

On Windows, the Python test scripts use Git for Windows' shell by default.
Navigation tests also accept its path as the first argument; the supervisor
tests accept `--bash`. All device paths are redirected to temporary fixtures.
