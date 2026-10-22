# Native SSH access

`ssh.sh` adds the CMU native OpenSSH server on port 22, with user `cmu` and
password `jci`. The launcher discovers the script automatically. The account
has uid 0; devices with network access to the CMU can attempt to log in.
Wi-Fi must be enabled and connected; this tweak does not change Wi-Fi settings.

The installer follows the existing screen-dialog, checksum and adjacent `.org`
backup conventions. It stores its runtime files in
`/tmp/mnt/resources/mzd-v74-tweaks/ssh` and adds a boot call to the known original
`/jci/scripts/stage_wifi.sh`. The native OpenSSH executable is resolved to an
absolute path. The existing OEM host key is used; no personal keys are shipped.
The factory account file is not rewritten: the default password uses a bind
mount of a RAM-only account copy. A separate firewall chain allows port 22.

An unrelated listener on port 22, unknown startup files, or different installed
service files are refused. The OEM listener on port 36000 is untouched.
Uninstall restores the original startup file, stops the managed listener,
removes the password overlay and firewall chain, and removes the service files.
The boot hook is reached during normal startup; this is not early-boot recovery.

Installer logs are in `logs/ssh.log` on the startup USB. Runtime logs are in
`reports/ssh-*/run.log` only when a writable USB with
`services/ssh/usb-log-marker.txt` is attached. Without one, runtime output is
discarded. The service itself works without USB.

## Confirmed vehicle tests

On the owner's 74.00.324A EU CMU, installation and a real password login were
verified, the service survived a full reboot, and login worked without USB.
Deinstallation was also verified: the exact OEM startup checksum was restored,
the listener stopped, the account overlay and firewall chain were removed,
and the installed service payload was removed. Original startup MD5:
`d740449dea568696660a62fce0fb35bd`.

Those device tests used the earlier installer. This contribution adapts the
same service to this repository's dialogs, `.org` backup and service directory;
that installer integration still needs a vehicle test. Actual boot with Wi-Fi
disabled/absent and other firmware/region variants are not hardware-verified.

## Automated checks

- `python3 tests/ssh-installer/run.py`: isolated install, repeat install,
  uninstall, occupied port, failed startup rollback, unknown startup files,
  corrupt backups and damaged payloads, with a stand-in service.
- `python3 tests/ssh-service/run.py`: real supervisor with fake kernel,
  network/firewall and sshd commands, including WLAN absence and later changes,
  duplicate start, account-overlay cleanup and firewall recovery.
- `python3 tests/ssh-installer/check-package.py`: executes the local release
  copy recipe and verifies the complete SSH payload and checksums in a USB ZIP.

Tests run without root and never start a real SSH daemon or modify host mounts.
On Windows, Git for Windows supplies the shell; Linux uses `/bin/sh`.
