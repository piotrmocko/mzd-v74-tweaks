# List Loop

Wrap between the first and last selectable entries in the four multicontroller
handlers. Normal scrolling across the visible-page threshold is preserved.
Disabled entries are skipped; missing/unloaded data is not treated as a boundary.

Run list-loop.sh from the existing launcher, or use
`sh list-loop.sh install|uninstall|restore|status`. restore removes this tweak
only and preserves unrelated changes. The current package can also remove the
previous List Loop version: uninstall it, then install to apply the correction.
A direct install over that old version is refused with these instructions.

The portable scoped AWK transform validates exact original/installed contexts
and verifies the complete inverse before writing. A shared verified OEM .org
backup, per-target lock, USB rollback copy and logs protect the operation.
No complete OEM JavaScript file is included in this PR.

Validation: isolated installer/transform checks on committed excerpts and the
private complete OEM file; legacy removal; result/cleanup failure tests; 36
JavaScript boundary/disabled/missing-data regressions. A separate local check
verifies all 36 install/uninstall order combinations of the three List2 tweaks.
The corrected behavior and wrappers still require a physical CMU test.

Reboot manually after changing GUI code; the worker CLI never reboots.
The existing interactive launcher can offer a reboot only after successful cleanup.

## Result contract

Capture stdout, stderr and the exit code separately. Exit 0 means success,
1 an ordinary failure, and 2 a critical failure requiring manual intervention.
A critical failure must stop subsequent actions and must not offer a reboot.
Final success/status output is emitted only after cleanup and result recording.
Interrupted install/uninstall actions are treated as critical because their
changes may be incomplete. Exact firmware/lock checks use CMU-compatible awk;
BusyBox grep on this CMU does not support -x.
