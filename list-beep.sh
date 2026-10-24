#!/bin/sh
# No List Beep: targeted original-AIO changes for firmware 74.00.324.
set -u
TITLE='No List Beep'
TWEAK=list-beep
APP=/jci/gui/common/controls/List2/js/List2Ctrl.js
ORIGINAL=e111883b9dcbeb6bb154521826fcacac
SELF=$(readlink -f "$0") || exit 1
MYDIR=$(dirname "$SELF")
ACTION=${1:-dialog}
case "$ACTION" in dialog|status|install|uninstall|restore) ;; *) echo 'Usage: sh list-beep.sh [install|uninstall|restore|status]' >&2; exit 1 ;; esac
UI=0
[ "$ACTION" = dialog ] && UI=1
MP=$MYDIR
while [ "$MP" != / ] && ! grep -q " $MP " /proc/mounts; do MP=$(dirname "$MP"); done
mount -o rw,remount "$MP" || exit 1
REPORT="$MYDIR/logs/$TWEAK-$(date +%Y%m%d-%H%M%S)-$$"
mkdir -p "$REPORT" || exit 1
: > "$REPORT/run.log" || exit 1
exec 3>&1
exec 4>&2
exec > "$REPORT/run.log" 2>&1
ROOT_CHANGED=0
WATCHDOG_CHANGED=0
LOCKED=0
SUCCESS=''
OFFER_REBOOT=0
FAILURE=''
CRITICAL=0
LOCK=/tmp/mzd-List2Ctrl-tweak.lock
# Public outcomes: 0 success, 1 ordinary failure, 2 critical failure.
# Keep the final GUI/terminal result until cleanup has finished.
fail() {
  FAILURE=$*
  echo "ERROR: $*"
  exit 1
}
fatal() {
  CRITICAL=1
  fail "$@"
}
finish() {
  _code=$?
  trap - 0
  case "${ACTION:-}:$_code" in
    install:130|install:143|uninstall:130|uninstall:143)
      FAILURE='Operation interrupted; changes may be incomplete.'
      CRITICAL=1 ;;
  esac
  if [ "$ROOT_CHANGED" = 1 ] && ! mount -o ro,remount /
  then
    FAILURE="${FAILURE}${FAILURE:+
}Could not restore the read-only system mount."
    CRITICAL=1
  fi
  if [ "$WATCHDOG_CHANGED" = 1 ] && ! echo 0 > /sys/class/gpio/Watchdog\ Disable/value
  then
    FAILURE="${FAILURE}${FAILURE:+
}Could not restore the watchdog state."
    CRITICAL=1
  fi
  if [ "$LOCKED" = 1 ] && ! rmdir "$LOCK"
  then
    FAILURE="${FAILURE}${FAILURE:+
}Could not release the tweak lock."
    CRITICAL=1
  fi
  [ "$CRITICAL" = 1 ] && _code=2
  if [ "$_code" != 0 ] && [ -z "$FAILURE" ]
  then
    FAILURE="Operation failed or was interrupted (exit $_code). Check the report before continuing."
  fi
  if ! printf 'exit_code=%s\n' "$_code" > "$REPORT/status.txt"
  then
    FAILURE="${FAILURE}${FAILURE:+
}Cannot save the final result. Check USB storage."
    [ "$_code" = 0 ] && _code=1
  fi
  sync
  if [ "$_code" != 0 ]
  then
    [ "$CRITICAL" = 1 ] && FAILURE="$FAILURE
Do NOT reboot the CMU. Manual intervention is required."
    printf 'ERROR: %s\nReports: %s\n' "$FAILURE" "$REPORT" >&4
    if [ "$UI" = 1 ]; then /jci/tools/jci-dialog --info --title="$TITLE" --text="$FAILURE
See USB logs." --no-cancel; fi
  elif [ -n "$SUCCESS" ]
  then
    printf '%s\nReports: %s\n' "$SUCCESS" "$REPORT" >&3
    if [ "$UI" = 1 ]; then
      killall -q jci-dialog
      if [ "$OFFER_REBOOT" = 0 ]; then
        /jci/tools/jci-dialog --info --title="$TITLE" --text="$SUCCESS" --no-cancel
      elif /jci/tools/jci-dialog --question --title="$TITLE" --text="$SUCCESS
Reboot to reload the GUI." --ok-label='Reboot now' --cancel-label='Reboot later'; then
        reboot
      fi
    fi
  fi
  if [ "$_code" = 0 ] && [ -n "${STATUS_RESULT:-}" ]
  then
    printf '%s\n' "$STATUS_RESULT" >&3
  fi
  exit "$_code"
}
trap finish 0
trap 'exit 130' INT
trap 'exit 143' TERM
hash() { md5sum "$1" | cut -d' ' -f1; }
echo "$TITLE / action=$ACTION"
WANT=$(cut -c1-32 "${SELF}.md5" 2>/dev/null)
[ -n "$WANT" ] && [ "$(hash "$SELF")" = "$WANT" ] || fail 'Installer checksum mismatch.'
awk '$0 == "JCI_SW_VER=\"MAZ_CMU-150_74.00.324\"" {found=1} END {exit !found}' /jci/version.ini || fail 'This tweak requires firmware 74.00.324.'
[ -f "$APP" ] && [ ! -L "$APP" ] || fail 'Target file is missing or is a symbolic link.'
mkdir "$LOCK" || fail 'Another tweak for this file is running. Restart the CMU if an earlier run was interrupted.'
LOCKED=1
cat > "$REPORT/transform.awk" <<'TWEAK_PROGRAM_END'
BEGIN {
    hunks = 2
    scope[1] = "List2Ctrl.prototype.handleControllerEvent = function(eventID)"
    size[1,0] = 7
    block[1,0,1] = "                        this._tiltHoldTimeoutId = null;"
    block[1,0,2] = "                        log.debug('Schedule autoscroll tier 1');"
    block[1,0,3] = "                        this._tiltHoldTimeoutId = setTimeout(function() {                               // schedule first autoscroll tier"
    block[1,0,4] = "                            this._beep('Long', 'Multicontroller');                                      // produce beep"
    block[1,0,5] = "                            log.debug('Start autoscroll tier 1');"
    block[1,0,6] = "                            this._handleMCDown();                                                       // do the first scroll down"
    block[1,0,7] = "                            clearInterval(this._tiltHoldIntervalId);                                    // clear any redundand intervals"
    size[1,1] = 7
    block[1,1,1] = "                        this._tiltHoldTimeoutId = null;"
    block[1,1,2] = "                        log.debug('Schedule autoscroll tier 1');"
    block[1,1,3] = "                        this._tiltHoldTimeoutId = setTimeout(function() {                               // schedule first autoscroll tier"
    block[1,1,4] = "                        //  this._beep('Long', 'Multicontroller');                                      // produce beep"
    block[1,1,5] = "                            log.debug('Start autoscroll tier 1');"
    block[1,1,6] = "                            this._handleMCDown();                                                       // do the first scroll down"
    block[1,1,7] = "                            clearInterval(this._tiltHoldIntervalId);                                    // clear any redundand intervals"
    scope[2] = "List2Ctrl.prototype.handleControllerEvent = function(eventID)"
    size[2,0] = 7
    block[2,0,1] = "                        this._tiltHoldTimeoutId = null;"
    block[2,0,2] = "                        log.debug('Schedule autoscroll tier 1');"
    block[2,0,3] = "                        this._tiltHoldTimeoutId = setTimeout(function() {                             // schedule first autoscroll tier"
    block[2,0,4] = "                            this._beep('Long', 'Multicontroller');                                    // produce beep"
    block[2,0,5] = "                            log.debug('Start autoscroll tier 1');"
    block[2,0,6] = "                            this._handleMCUp();                                                       // do the first scroll up"
    block[2,0,7] = "                            clearInterval(this._tiltHoldIntervalId);                                  // clear any redundand intervals"
    size[2,1] = 7
    block[2,1,1] = "                        this._tiltHoldTimeoutId = null;"
    block[2,1,2] = "                        log.debug('Schedule autoscroll tier 1');"
    block[2,1,3] = "                        this._tiltHoldTimeoutId = setTimeout(function() {                             // schedule first autoscroll tier"
    block[2,1,4] = "                        //  this._beep('Long', 'Multicontroller');                                    // produce beep"
    block[2,1,5] = "                            log.debug('Start autoscroll tier 1');"
    block[2,1,6] = "                            this._handleMCUp();                                                       // do the first scroll up"
    block[2,1,7] = "                            clearInterval(this._tiltHoldIntervalId);                                  // clear any redundand intervals"
}
function same(at, h, form,    j, length_) {
    length_ = size[h, form]
    if (at + length_ - 1 > NR) return 0
    for (j = 1; j <= length_; j++)
        if (line[at+j-1] != block[h,form,j]) return 0
    return 1
}
function locate(h, form,    i, count) {
    count = 0
    for (i = 1; i <= NR; i++) {
        if (part[i] == scope[h] && same(i,h,form)) {
            count++
            position[h,form] = i
        }
    }
    return count
}
{
    if ($0 ~ /^[A-Za-z0-9_]+\.prototype\.[A-Za-z0-9_]+ = function\(/) current = $0
    line[NR] = $0
    part[NR] = current
    if ($0 == "};") current = ""
}
END {
    state = -1
    for (h = 1; h <= hunks; h++) {
        oldCount = locate(h,0)
        newCount = locate(h,1)
        if (oldCount == 1 && newCount == 0) found = 0
        else if (oldCount == 0 && newCount == 1) found = 1
        else exit 2
        if (state != -1 && state != found) exit 2
        state = found
        if (h > 1 && position[h,found] <= position[h-1,found]+size[h-1,found]-1) exit 2
    }
    if (action == "status") {print state ? "installed" : "uninstalled"; exit}
    if (action != "install" && action != "uninstall") exit 2
    wanted = (action == "install") ? 1 : 0
    nextLine = 1
    for (h = 1; h <= hunks; h++) {
        at = position[h,state]
        while (nextLine < at) print line[nextLine++]
        for (j = 1; j <= size[h,wanted]; j++) print block[h,wanted,j]
        nextLine = at + size[h,state]
    }
    while (nextLine <= NR) print line[nextLine++]
}
TWEAK_PROGRAM_END
transform() { awk -v action="$1" -f "$REPORT/transform.awk" "$2"; }
STATE=$(transform status "$APP") || fail 'Unknown or partially modified patch locations. Nothing changed.'
echo "state=$STATE"
if [ "$ACTION" = status ]; then STATUS_RESULT=$STATE; exit 0; fi
if [ "$UI" = 1 ]; then
  killall -q jci-dialog
  if /jci/tools/jci-dialog --3-button-dialog --title="$TITLE" --text='Mute the two long multicontroller list beeps.\nWhat would you like to do?' --ok-label=Install --cancel-label=Uninstall --button3-label=Exit; then
    ACTION=install
  elif [ $? -eq 1 ]; then
    ACTION=uninstall
  else
    echo 'Cancelled. Nothing changed.'; exit 0
  fi
fi
[ "$ACTION" = restore ] && ACTION=uninstall
if { [ "$ACTION" = install ] && [ "$STATE" = installed ]; } || { [ "$ACTION" = uninstall ] && [ "$STATE" = uninstalled ]; }; then
  SUCCESS='Requested setting is already present.'
  exit 0
fi
BACKUP="${APP}.org"
if [ -e "$BACKUP" ] || [ -L "$BACKUP" ]; then
  [ -f "$BACKUP" ] && [ ! -L "$BACKUP" ] && [ "$(hash "$BACKUP")" = "$ORIGINAL" ] || fail 'The .org backup is not the known OEM original.'
else
  [ "$(hash "$APP")" = "$ORIGINAL" ] || fail 'The shared OEM .org backup is missing. Nothing changed.'
fi
cp "$APP" "$REPORT/before.js" || fail 'Could not save USB rollback copy.'
BEFORE=$(hash "$APP")
[ "$(hash "$REPORT/before.js")" = "$BEFORE" ] || fail 'USB rollback copy mismatch.'
transform "$ACTION" "$APP" > "$REPORT/desired.js" || fail 'Could not prepare targeted change.'
INVERSE=install
[ "$ACTION" = install ] && INVERSE=uninstall
transform "$INVERSE" "$REPORT/desired.js" > "$REPORT/reversed.js" && cmp -s "$REPORT/reversed.js" "$REPORT/before.js" || fail 'Inverse check failed. Nothing changed.'
DESIRED=$(hash "$REPORT/desired.js")
WATCHDOG=$(cat /sys/class/gpio/Watchdog\ Disable/value) || fail 'Could not read watchdog state.'
case "$WATCHDOG" in
  0) echo 1 > /sys/class/gpio/Watchdog\ Disable/value || fail 'Could not disable watchdog.'; WATCHDOG_CHANGED=1 ;;
  1) ;;
  *) fail 'Unknown watchdog state.' ;;
esac
if awk '$2=="/" && $3!="rootfs" && $4 ~ /(^|,)ro(,|$)/ {f=1} END {exit !f}' /proc/mounts; then
  mount -o rw,remount / || fail 'Could not remount the system read-write.'
  ROOT_CHANGED=1
fi
if [ ! -e "$BACKUP" ]; then
  cp -a "$APP" "$BACKUP" && sync
  if [ "$(hash "$BACKUP")" != "$ORIGINAL" ]; then
    rm -f "$BACKUP"
    fail 'Original backup failed.'
  fi
fi
[ "$(hash "$APP")" = "$BEFORE" ] || fail 'Target changed while preparing the tweak.'
cat "$REPORT/desired.js" > "$APP"; sync
[ "$(hash "$APP")" = "$DESIRED" ] || { cat "$REPORT/desired.js" > "$APP"; sync; }
if [ "$(hash "$APP")" != "$DESIRED" ]; then
  cat "$REPORT/before.js" > "$APP"; sync
  [ "$(hash "$APP")" = "$BEFORE" ] || fatal 'Write AND rollback failed. Do NOT reboot the CMU.'
  fail 'Write failed; the complete previous file was restored.'
fi
OFFER_REBOOT=1
SUCCESS="$ACTION completed. Other changes were preserved."
exit 0
