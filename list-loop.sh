#!/bin/sh
# List Loop: targeted original-AIO changes for firmware 74.00.324.
set -u
TITLE='List Loop'
TWEAK=list-loop
APP=/jci/gui/common/controls/List2/js/List2Ctrl.js
ORIGINAL=e111883b9dcbeb6bb154521826fcacac
SELF=$(readlink -f "$0") || exit 1
MYDIR=$(dirname "$SELF")
ACTION=${1:-dialog}
case "$ACTION" in dialog|status|install|uninstall|restore) ;; *) echo 'Usage: sh list-loop.sh [install|uninstall|restore|status]' >&2; exit 1 ;; esac
UI=0
[ "$ACTION" = dialog ] && UI=1
MP=$MYDIR
while [ "$MP" != / ] && ! grep -q " $MP " /proc/mounts; do MP=$(dirname "$MP"); done
mount -o rw,remount "$MP" || exit 1
REPORT="$MYDIR/logs/$TWEAK-$(date +%Y%m%d-%H%M%S)-$$"
mkdir -p "$REPORT" || exit 1
: > "$REPORT/run.log" || exit 1
exec 3>&1
exec > "$REPORT/run.log" 2>&1
ROOT_CHANGED=0
WATCHDOG_CHANGED=0
LOCKED=0
REBOOT=0
LOCK=/tmp/mzd-List2Ctrl-tweak.lock
fail() {
  echo "ERROR: $*"
  printf 'ERROR: %s\nReports: %s\n' "$*" "$REPORT" >&3
  if [ "$UI" = 1 ]; then /jci/tools/jci-dialog --info --title="$TITLE" --text="$*\nSee USB logs." --no-cancel; fi
  exit 1
}
finish() {
  _code=$?
  trap - 0
  if [ "$ROOT_CHANGED" = 1 ]; then mount -o ro,remount / || _code=1; fi
  if [ "$WATCHDOG_CHANGED" = 1 ]; then echo 0 > /sys/class/gpio/Watchdog\ Disable/value || _code=1; fi
  if [ "$LOCKED" = 1 ]; then rmdir "$LOCK" || _code=1; fi
  printf 'exit_code=%s\n' "$_code" > "$REPORT/status.txt"
  sync
  if [ "$_code" = 0 ] && [ "$REBOOT" = 1 ]; then reboot; fi
  exit "$_code"
}
trap finish 0
trap 'exit 130' INT
trap 'exit 143' TERM
hash() { md5sum "$1" | cut -d' ' -f1; }
echo "$TITLE / action=$ACTION"
WANT=$(cut -c1-32 "${SELF}.md5" 2>/dev/null)
[ -n "$WANT" ] && [ "$(hash "$SELF")" = "$WANT" ] || fail 'Installer checksum mismatch.'
grep -q '^JCI_SW_VER="MAZ_CMU-150_74\.00\.324"$' /jci/version.ini || fail 'This tweak requires firmware 74.00.324.'
[ -f "$APP" ] && [ ! -L "$APP" ] || fail 'Target file is missing or is a symbolic link.'
mkdir "$LOCK" || fail 'Another tweak for this file is running. Restart the CMU if an earlier run was interrupted.'
LOCKED=1
cat > "$REPORT/transform.awk" <<'TWEAK_PROGRAM_END'
BEGIN {
    hunks = 8
    scope[1] = "List2Ctrl.prototype._handleMCCW = function()"
    size[1,0] = 6
    block[1,0,1] = "            // get relative focussed index before moving the focus"
    block[1,0,2] = "            var rfi = this._getRelativeFocussedIndex();"
    block[1,0,3] = ""
    block[1,0,4] = "            // attempt focus move"
    block[1,0,5] = "            if (rfi <= bottomFocusThreshold)"
    block[1,0,6] = "            {"
    size[1,1] = 8
    block[1,1,1] = "            // get relative focussed index before moving the focus"
    block[1,1,2] = "            var rfi = this._getRelativeFocussedIndex();"
    block[1,1,3] = ""
    block[1,1,4] = "            var currentFocussedIndex = this._getFocussedIndex();"
    block[1,1,5] = ""
    block[1,1,6] = "            // attempt focus move"
    block[1,1,7] = "            if (rfi <= bottomFocusThreshold)"
    block[1,1,8] = "            {"
    scope[2] = "List2Ctrl.prototype._handleMCCW = function()"
    size[2,0] = 6
    block[2,0,1] = ""
    block[2,0,2] = "            // get relative focussed index after moving the focus"
    block[2,0,3] = "            rfi = this._getRelativeFocussedIndex();"
    block[2,0,4] = "        }"
    block[2,0,5] = ""
    block[2,0,6] = "        // attempt scroll if the focus has passed the threshold"
    size[2,1] = 20
    block[2,1,1] = ""
    block[2,1,2] = "            // get relative focussed index after moving the focus"
    block[2,1,3] = "            rfi = this._getRelativeFocussedIndex();"
    block[2,1,4] = ""
    block[2,1,5] = "            if (this._getFocussedIndex() == currentFocussedIndex) //didn't move"
    block[2,1,6] = "            {"
    block[2,1,7] = "                if (this.dataList && this.dataList.items)"
    block[2,1,8] = "                {"
    block[2,1,9] = "                    var index = 0;"
    block[2,1,10] = "                    while (index < this.dataList.items.length && this.dataList.items[index].disabled) index++;"
    block[2,1,11] = "                    if (index < this.dataList.items.length)"
    block[2,1,12] = "                    {"
    block[2,1,13] = "                        this._manageFocus(index);"
    block[2,1,14] = "                        return 'consumed';"
    block[2,1,15] = "                    }"
    block[2,1,16] = "                }"
    block[2,1,17] = "            }"
    block[2,1,18] = "        }"
    block[2,1,19] = ""
    block[2,1,20] = "        // attempt scroll if the focus has passed the threshold"
    scope[3] = "List2Ctrl.prototype._handleMCCCW = function()"
    size[3,0] = 6
    block[3,0,1] = "            // get relative focussed index before moving the focus"
    block[3,0,2] = "            var rfi = this._getRelativeFocussedIndex();"
    block[3,0,3] = ""
    block[3,0,4] = "            // attempt focus move"
    block[3,0,5] = "            if (rfi >= 1)"
    block[3,0,6] = "            {"
    size[3,1] = 8
    block[3,1,1] = "            // get relative focussed index before moving the focus"
    block[3,1,2] = "            var rfi = this._getRelativeFocussedIndex();"
    block[3,1,3] = ""
    block[3,1,4] = "            var currentFocussedIndex = this._getFocussedIndex();"
    block[3,1,5] = ""
    block[3,1,6] = "            // attempt focus move"
    block[3,1,7] = "            if (rfi >= 1)"
    block[3,1,8] = "            {"
    scope[4] = "List2Ctrl.prototype._handleMCCCW = function()"
    size[4,0] = 6
    block[4,0,1] = ""
    block[4,0,2] = "            // get relative focussed index after moving the focus"
    block[4,0,3] = "            rfi = this._getRelativeFocussedIndex();"
    block[4,0,4] = "        }"
    block[4,0,5] = ""
    block[4,0,6] = "        // attempt scroll if the focus is at the first item"
    size[4,1] = 20
    block[4,1,1] = ""
    block[4,1,2] = "            // get relative focussed index after moving the focus"
    block[4,1,3] = "            rfi = this._getRelativeFocussedIndex();"
    block[4,1,4] = ""
    block[4,1,5] = "            if (this._getFocussedIndex() == currentFocussedIndex) //didn't move"
    block[4,1,6] = "            {"
    block[4,1,7] = "                if (this.dataList && this.dataList.items)"
    block[4,1,8] = "                {"
    block[4,1,9] = "                    var index = this.dataList.items.length - 1;"
    block[4,1,10] = "                    while (index >= 0 && this.dataList.items[index].disabled) index--;"
    block[4,1,11] = "                    if (index >= 0)"
    block[4,1,12] = "                    {"
    block[4,1,13] = "                        this._manageFocus(index);"
    block[4,1,14] = "                        return 'consumed';"
    block[4,1,15] = "                    }"
    block[4,1,16] = "                }"
    block[4,1,17] = "            }"
    block[4,1,18] = "        }"
    block[4,1,19] = ""
    block[4,1,20] = "        // attempt scroll if the focus is at the first item"
    scope[5] = "List2Ctrl.prototype._handleMCDown = function()"
    size[5,0] = 6
    block[5,0,1] = "                // get relative focussed index before moving the focus"
    block[5,0,2] = "                var rfi = this._getRelativeFocussedIndex();"
    block[5,0,3] = ""
    block[5,0,4] = "                // attempt focus move"
    block[5,0,5] = "                if (rfi <= bottomFocusThreshold)"
    block[5,0,6] = "                {"
    size[5,1] = 8
    block[5,1,1] = "                // get relative focussed index before moving the focus"
    block[5,1,2] = "                var rfi = this._getRelativeFocussedIndex();"
    block[5,1,3] = ""
    block[5,1,4] = "                var currentFocussedIndex = this._getFocussedIndex();"
    block[5,1,5] = ""
    block[5,1,6] = "                // attempt focus move"
    block[5,1,7] = "                if (rfi <= bottomFocusThreshold)"
    block[5,1,8] = "                {"
    scope[6] = "List2Ctrl.prototype._handleMCDown = function()"
    size[6,0] = 6
    block[6,0,1] = ""
    block[6,0,2] = "                // get relative focussed index after moving the focus"
    block[6,0,3] = "                rfi = this._getRelativeFocussedIndex();"
    block[6,0,4] = "            }"
    block[6,0,5] = "            // attempt scroll if the focus has passed the threshold"
    block[6,0,6] = "            if (rfi > bottomFocusThreshold)"
    size[6,1] = 20
    block[6,1,1] = ""
    block[6,1,2] = "                // get relative focussed index after moving the focus"
    block[6,1,3] = "                rfi = this._getRelativeFocussedIndex();"
    block[6,1,4] = ""
    block[6,1,5] = "                if (this._getFocussedIndex() == currentFocussedIndex) //didn't move"
    block[6,1,6] = "                {"
    block[6,1,7] = "                    if (this.dataList && this.dataList.items)"
    block[6,1,8] = "                    {"
    block[6,1,9] = "                        var index = 0;"
    block[6,1,10] = "                        while (index < this.dataList.items.length && this.dataList.items[index].disabled) index++;"
    block[6,1,11] = "                        if (index < this.dataList.items.length)"
    block[6,1,12] = "                        {"
    block[6,1,13] = "                            this._manageFocus(index);"
    block[6,1,14] = "                            return 'consumed';"
    block[6,1,15] = "                        }"
    block[6,1,16] = "                    }"
    block[6,1,17] = "                }"
    block[6,1,18] = "            }"
    block[6,1,19] = "            // attempt scroll if the focus has passed the threshold"
    block[6,1,20] = "            if (rfi > bottomFocusThreshold)"
    scope[7] = "List2Ctrl.prototype._handleMCUp = function()"
    size[7,0] = 6
    block[7,0,1] = "                // get relative focussed index before moving the focus"
    block[7,0,2] = "                var rfi = this._getRelativeFocussedIndex();"
    block[7,0,3] = ""
    block[7,0,4] = "                // attempt focus move"
    block[7,0,5] = "                if (rfi >= 1)"
    block[7,0,6] = "                {"
    size[7,1] = 8
    block[7,1,1] = "                // get relative focussed index before moving the focus"
    block[7,1,2] = "                var rfi = this._getRelativeFocussedIndex();"
    block[7,1,3] = ""
    block[7,1,4] = "                var currentFocussedIndex = this._getFocussedIndex();"
    block[7,1,5] = ""
    block[7,1,6] = "                // attempt focus move"
    block[7,1,7] = "                if (rfi >= 1)"
    block[7,1,8] = "                {"
    scope[8] = "List2Ctrl.prototype._handleMCUp = function()"
    size[8,0] = 6
    block[8,0,1] = ""
    block[8,0,2] = "                // get relative focussed index after moving the focus"
    block[8,0,3] = "                rfi = this._getRelativeFocussedIndex();"
    block[8,0,4] = "            }"
    block[8,0,5] = ""
    block[8,0,6] = "            // attempt scroll if the focus is at the first item"
    size[8,1] = 20
    block[8,1,1] = ""
    block[8,1,2] = "                // get relative focussed index after moving the focus"
    block[8,1,3] = "                rfi = this._getRelativeFocussedIndex();"
    block[8,1,4] = ""
    block[8,1,5] = "                if (this._getFocussedIndex() == currentFocussedIndex) //didn't move"
    block[8,1,6] = "                {"
    block[8,1,7] = "                    if (this.dataList && this.dataList.items)"
    block[8,1,8] = "                    {"
    block[8,1,9] = "                        var index = this.dataList.items.length - 1;"
    block[8,1,10] = "                        while (index >= 0 && this.dataList.items[index].disabled) index--;"
    block[8,1,11] = "                        if (index >= 0)"
    block[8,1,12] = "                        {"
    block[8,1,13] = "                            this._manageFocus(index);"
    block[8,1,14] = "                            return 'consumed';"
    block[8,1,15] = "                        }"
    block[8,1,16] = "                    }"
    block[8,1,17] = "                }"
    block[8,1,18] = "            }"
    block[8,1,19] = ""
    block[8,1,20] = "            // attempt scroll if the focus is at the first item"
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
if [ "$ACTION" = status ]; then printf '%s\n' "$STATE" >&3; exit 0; fi
if [ "$UI" = 1 ]; then
  killall -q jci-dialog
  if /jci/tools/jci-dialog --3-button-dialog --title="$TITLE" --text='Wrap between the first and last selectable list items.\nWhat would you like to do?' --ok-label=Install --cancel-label=Uninstall --button3-label=Exit; then
    ACTION=install
  elif [ $? -eq 1 ]; then
    ACTION=uninstall
  else
    echo 'Cancelled. Nothing changed.'; exit 0
  fi
fi
[ "$ACTION" = restore ] && ACTION=uninstall
if { [ "$ACTION" = install ] && [ "$STATE" = installed ]; } || { [ "$ACTION" = uninstall ] && [ "$STATE" = uninstalled ]; }; then
  printf 'Requested setting is already present.\n' >&3
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
  [ "$(hash "$APP")" = "$BEFORE" ] || fail 'Write AND rollback failed. Do NOT reboot the CMU.'
  fail 'Write failed; the complete previous file was restored.'
fi
printf '%s completed. Other changes were preserved.\nReports: %s\n' "$ACTION" "$REPORT" >&3
if [ "$UI" = 1 ]; then
  killall -q jci-dialog
  if /jci/tools/jci-dialog --question --title="$TITLE" --text='Completed. Reboot to reload the GUI.' --ok-label='Reboot now' --cancel-label='Reboot later'; then
    REBOOT=1
  fi
fi
exit 0
