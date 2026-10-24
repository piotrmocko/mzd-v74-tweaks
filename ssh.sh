#!/bin/sh
# Existing launcher entry; all installation logic lives in the SSH worker.
set -u
SELF=$(readlink -f "$0") || exit 1
HERE=$(dirname "$SELF")
ACTION=${1:-dialog}
[ "$#" -le 1 ] || { echo 'Expected one action.' >&2; exit 1; }
case "$ACTION" in
  --help|-h) echo 'Usage: sh ssh.sh [install|uninstall|restore|status]'; exit 0 ;;
  dialog|install|uninstall|restore|status) ;;
  *) echo 'Unknown action.' >&2; exit 1 ;;
esac
EXPECTED=$(cut -c1-32 "$SELF.md5" 2>/dev/null)
ACTUAL=$(md5sum "$SELF" | cut -d' ' -f1)
[ -n "$EXPECTED" ] && [ "$EXPECTED" = "$ACTUAL" ] || { echo 'SSH launcher checksum mismatch.' >&2; exit 1; }
[ "$ACTION" != restore ] || ACTION=uninstall
if [ "$ACTION" != dialog ]; then
  exec /bin/sh "$HERE/services/ssh/run.sh" "$ACTION"
fi
/jci/tools/jci-dialog --3-button-dialog --title='SSH Access' --text='Native SSH on port 22. Login: cmu / jci.
What would you like to do?' --ok-label=Install --cancel-label=Uninstall --button3-label=Exit
CHOICE=$?
case "$CHOICE" in 0) ACTION=install ;; 1) ACTION=uninstall ;; *) exit 0 ;; esac
STATE=$(mktemp -d /tmp/mzd-ssh-dialog.XXXXXX) || exit 1
# Wait for the complete worker result, including rollback and cleanup.
/bin/sh "$HERE/services/ssh/run.sh" "$ACTION" > "$STATE/stdout" 2> "$STATE/stderr"
CODE=$?
cat "$STATE/stdout"
cat "$STATE/stderr" >&2
MESSAGE=$(cat "$STATE/stdout" "$STATE/stderr")
TITLE='SSH result'
if [ "$CODE" = 2 ]; then TITLE='SSH: manual check required'; fi
/jci/tools/jci-dialog --info --title="$TITLE" --text="$MESSAGE" --ok-label=OK --no-cancel || :
rm -f "$STATE/stdout" "$STATE/stderr"
rmdir "$STATE" || :
exit "$CODE"
