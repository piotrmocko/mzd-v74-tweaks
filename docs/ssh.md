# Native SSH access

ssh.sh remains the existing launcher entry. It delegates to the independently
callable services/ssh/run.sh worker; the same corrected implementation is used
by the standalone tweak. The worker owns startup-hook patching, verified OEM
backup, selective uninstall, USB reports, watchdog/mount restoration and rollback.

The native server listens on port 22 (cmu / jci), with the existing host key,
a RAM-only account overlay and an owned firewall chain. The OEM listener is
preserved and an unrelated listener on 22 is refused. There is no automatic reboot.
The core supervisor behavior was tested previously on the vehicle; this worker
and launcher integration still need a physical CMU test.

Use `sh ssh.sh install|uninstall|restore|status` or invoke
`sh services/ssh/run.sh install|uninstall|status` directly. No arguments on ssh.sh
opens Install/Uninstall/Exit; no arguments on the worker only prints usage.
The result dialog is shown after the worker has completed its cleanup.

Status checks the hook plus deployed service files and enabled marker. A stopped
runtime service alone does not imply that the persistent installation is absent.
Reports are under reports/diffpatch on the startup USB. Runtime logs are stored
only when the attached USB has the marker copied by install; otherwise discarded.

Checks:
- tests/ssh-installer/run.py: 19 isolated worker/entry checks with controlled
  mounts, target files, GPIO and service double, including rollback and cleanup.
- tests/ssh-installer/test_results.py: final output and critical result contract.
- tests/ssh-service/run.py: real supervisor with fake kernel/network/sshd commands.
- tests/ssh-installer/check-package.py: release copy recipe and full payload ZIP.

## Result contract

Capture stdout, stderr and the exit code separately. Exit 0 means success,
1 an ordinary failure, and 2 a critical failure requiring manual intervention.
A critical failure must stop subsequent actions and must not offer a reboot.
Final success/status output is emitted only after cleanup and result recording.
Interrupted install/uninstall actions are treated as critical because their
changes may be incomplete. Exact firmware/lock checks use CMU-compatible awk;
BusyBox grep on this CMU does not support -x.
