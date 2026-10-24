#!/bin/sh
# List Loop: targeted original-AIO changes for firmware 74.00.324.
set -u

# --- Tweak configuration and requested action ---
TITLE='List Loop'
TWEAK=list-loop
APP=/jci/gui/common/controls/List2/js/List2Ctrl.js
ORIGINAL=e111883b9dcbeb6bb154521826fcacac

SELF=$(readlink -f "$0") || exit 1
MYDIR=$(dirname "$SELF")
ACTION=${1:-dialog}

case "$ACTION" in
  dialog|status|install|uninstall|restore)
    ;;
  *)
    echo 'Usage: sh list-loop.sh [install|uninstall|restore|status]' >&2
    exit 1
    ;;
esac

UI=0
if [ "$ACTION" = dialog ]
then
  UI=1
fi


# --- Find the startup medium and keep diagnostics on USB ---
# Walk up from the script directory so a subfolder works as well as the root.
MP=$MYDIR
while [ "$MP" != / ] && ! grep -q " $MP " /proc/mounts
do
  MP=$(dirname "$MP")
done
mount -o rw,remount "$MP" || exit 1

REPORT="$MYDIR/logs/$TWEAK-$(date +%Y%m%d-%H%M%S)-$$"
mkdir -p "$REPORT" || exit 1
: > "$REPORT/run.log" || exit 1

# Preserve the caller's stdout for concise results; detailed output goes to USB.
exec 3>&1
exec 4>&2
exec > "$REPORT/run.log" 2>&1


# --- Cleanup state and error handling ---
# Restore only settings changed by this invocation. All tweaks modifying this
# List2Ctrl.js share the same lock, so their read/prepare/write steps cannot race.
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
hash() {
  md5sum "$1" | cut -d' ' -f1
}


# --- Validate this installer, the firmware and the target before editing ---
echo "$TITLE / action=$ACTION"
WANT=$(cut -c1-32 "${SELF}.md5" 2>/dev/null)
if [ -z "$WANT" ] || [ "$(hash "$SELF")" != "$WANT" ]
then
  fail 'Installer checksum mismatch.'
fi

awk '$0 == "JCI_SW_VER=\"MAZ_CMU-150_74.00.324\"" {found=1} END {exit !found}' /jci/version.ini || fail 'This tweak requires firmware 74.00.324.'
if [ ! -f "$APP" ] || [ -L "$APP" ]
then
  fail 'Target file is missing or is a symbolic link.'
fi

mkdir "$LOCK" || fail 'Another tweak for this file is running. Restart the CMU if an earlier run was interrupted.'
LOCKED=1


# --- Exact original/installed context blocks and scoped AWK transform ---
# Each pair describes one insertion in an existing multicontroller handler.
# Form 0 is the OEM block; form 1 contains the corrected boundary checks. These are
# literal JS lines, not generated helper functions or whole-file replacements.
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
    size[2,1] = 27
    block[2,1,1] = ""
    block[2,1,2] = "            // get relative focussed index after moving the focus"
    block[2,1,3] = "            rfi = this._getRelativeFocussedIndex();"
    block[2,1,4] = ""
    block[2,1,5] = "            if (this._getFocussedIndex() == currentFocussedIndex) //didn't move"
    block[2,1,6] = "            {"
    block[2,1,7] = "                if (this.dataList && this.dataList.items && this.dataList.itemCount > 0)"
    block[2,1,8] = "                {"
    block[2,1,9] = "                    // An unchanged focus can also mean normal scrolling."
    block[2,1,10] = "                    // Wrap only if no selectable item remains in this direction."
    block[2,1,11] = "                    var nextIndex = currentFocussedIndex + 1;"
    block[2,1,12] = "                    while (nextIndex < this.dataList.itemCount && this.dataList.items[nextIndex] && this.dataList.items[nextIndex].disabled) nextIndex++;"
    block[2,1,13] = "                    if (nextIndex >= this.dataList.itemCount)"
    block[2,1,14] = "                    {"
    block[2,1,15] = "                        var index = 0;"
    block[2,1,16] = "                        while (index < this.dataList.itemCount && this.dataList.items[index] && this.dataList.items[index].disabled) index++;"
    block[2,1,17] = "                        if (index < this.dataList.itemCount && this.dataList.items[index] && !this.dataList.items[index].disabled)"
    block[2,1,18] = "                        {"
    block[2,1,19] = "                            this._manageFocus(index);"
    block[2,1,20] = "                            return 'consumed';"
    block[2,1,21] = "                        }"
    block[2,1,22] = "                    }"
    block[2,1,23] = "                }"
    block[2,1,24] = "            }"
    block[2,1,25] = "        }"
    block[2,1,26] = ""
    block[2,1,27] = "        // attempt scroll if the focus has passed the threshold"
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
    size[4,1] = 27
    block[4,1,1] = ""
    block[4,1,2] = "            // get relative focussed index after moving the focus"
    block[4,1,3] = "            rfi = this._getRelativeFocussedIndex();"
    block[4,1,4] = ""
    block[4,1,5] = "            if (this._getFocussedIndex() == currentFocussedIndex) //didn't move"
    block[4,1,6] = "            {"
    block[4,1,7] = "                if (this.dataList && this.dataList.items && this.dataList.itemCount > 0)"
    block[4,1,8] = "                {"
    block[4,1,9] = "                    // An unchanged focus can also mean normal scrolling."
    block[4,1,10] = "                    // Wrap only if no selectable item remains in this direction."
    block[4,1,11] = "                    var nextIndex = currentFocussedIndex - 1;"
    block[4,1,12] = "                    while (nextIndex >= 0 && this.dataList.items[nextIndex] && this.dataList.items[nextIndex].disabled) nextIndex--;"
    block[4,1,13] = "                    if (nextIndex < 0)"
    block[4,1,14] = "                    {"
    block[4,1,15] = "                        var index = this.dataList.itemCount - 1;"
    block[4,1,16] = "                        while (index >= 0 && this.dataList.items[index] && this.dataList.items[index].disabled) index--;"
    block[4,1,17] = "                        if (index >= 0 && this.dataList.items[index] && !this.dataList.items[index].disabled)"
    block[4,1,18] = "                        {"
    block[4,1,19] = "                            this._manageFocus(index);"
    block[4,1,20] = "                            return 'consumed';"
    block[4,1,21] = "                        }"
    block[4,1,22] = "                    }"
    block[4,1,23] = "                }"
    block[4,1,24] = "            }"
    block[4,1,25] = "        }"
    block[4,1,26] = ""
    block[4,1,27] = "        // attempt scroll if the focus is at the first item"
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
    size[6,1] = 27
    block[6,1,1] = ""
    block[6,1,2] = "                // get relative focussed index after moving the focus"
    block[6,1,3] = "                rfi = this._getRelativeFocussedIndex();"
    block[6,1,4] = ""
    block[6,1,5] = "                if (this._getFocussedIndex() == currentFocussedIndex) //didn't move"
    block[6,1,6] = "                {"
    block[6,1,7] = "                    if (this.dataList && this.dataList.items && this.dataList.itemCount > 0)"
    block[6,1,8] = "                    {"
    block[6,1,9] = "                        // An unchanged focus can also mean normal scrolling."
    block[6,1,10] = "                        // Wrap only if no selectable item remains in this direction."
    block[6,1,11] = "                        var nextIndex = currentFocussedIndex + 1;"
    block[6,1,12] = "                        while (nextIndex < this.dataList.itemCount && this.dataList.items[nextIndex] && this.dataList.items[nextIndex].disabled) nextIndex++;"
    block[6,1,13] = "                        if (nextIndex >= this.dataList.itemCount)"
    block[6,1,14] = "                        {"
    block[6,1,15] = "                            var index = 0;"
    block[6,1,16] = "                            while (index < this.dataList.itemCount && this.dataList.items[index] && this.dataList.items[index].disabled) index++;"
    block[6,1,17] = "                            if (index < this.dataList.itemCount && this.dataList.items[index] && !this.dataList.items[index].disabled)"
    block[6,1,18] = "                            {"
    block[6,1,19] = "                                this._manageFocus(index);"
    block[6,1,20] = "                                return 'consumed';"
    block[6,1,21] = "                            }"
    block[6,1,22] = "                        }"
    block[6,1,23] = "                    }"
    block[6,1,24] = "                }"
    block[6,1,25] = "            }"
    block[6,1,26] = "            // attempt scroll if the focus has passed the threshold"
    block[6,1,27] = "            if (rfi > bottomFocusThreshold)"
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
    size[8,1] = 27
    block[8,1,1] = ""
    block[8,1,2] = "                // get relative focussed index after moving the focus"
    block[8,1,3] = "                rfi = this._getRelativeFocussedIndex();"
    block[8,1,4] = ""
    block[8,1,5] = "                if (this._getFocussedIndex() == currentFocussedIndex) //didn't move"
    block[8,1,6] = "                {"
    block[8,1,7] = "                    if (this.dataList && this.dataList.items && this.dataList.itemCount > 0)"
    block[8,1,8] = "                    {"
    block[8,1,9] = "                        // An unchanged focus can also mean normal scrolling."
    block[8,1,10] = "                        // Wrap only if no selectable item remains in this direction."
    block[8,1,11] = "                        var nextIndex = currentFocussedIndex - 1;"
    block[8,1,12] = "                        while (nextIndex >= 0 && this.dataList.items[nextIndex] && this.dataList.items[nextIndex].disabled) nextIndex--;"
    block[8,1,13] = "                        if (nextIndex < 0)"
    block[8,1,14] = "                        {"
    block[8,1,15] = "                            var index = this.dataList.itemCount - 1;"
    block[8,1,16] = "                            while (index >= 0 && this.dataList.items[index] && this.dataList.items[index].disabled) index--;"
    block[8,1,17] = "                            if (index >= 0 && this.dataList.items[index] && !this.dataList.items[index].disabled)"
    block[8,1,18] = "                            {"
    block[8,1,19] = "                                this._manageFocus(index);"
    block[8,1,20] = "                                return 'consumed';"
    block[8,1,21] = "                            }"
    block[8,1,22] = "                        }"
    block[8,1,23] = "                    }"
    block[8,1,24] = "                }"
    block[8,1,25] = "            }"
    block[8,1,26] = ""
    block[8,1,27] = "            // attempt scroll if the focus is at the first item"
}
function same(at, h, form,    j, length_) {
    length_ = size[h, form]
    if (at + length_ - 1 > NR) {
        return 0
    }

    for (j = 1; j <= length_; j++) {
        if (line[at+j-1] != block[h,form,j]) {
            return 0
        }
    }
    return 1
}

# Count matches only inside the expected handler, rejecting duplicates later.
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

# Keep the original lines and their containing handler for scoped matching.
{
    if ($0 ~ /^[A-Za-z0-9_]+\.prototype\.[A-Za-z0-9_]+ = function\(/) {
        current = $0
    }
    line[NR] = $0
    part[NR] = current
    if ($0 == "};") {
        current = ""
    }
}

# Require all eight blocks to agree on one state before emitting any result.
# Replacements copy all unrelated lines unchanged, so other tweaks survive.
END {
    state = -1
    for (h = 1; h <= hunks; h++) {
        oldCount = locate(h,0)
        newCount = locate(h,1)
        if (oldCount == 1 && newCount == 0) {
            found = 0
        } else if (oldCount == 0 && newCount == 1) {
            found = 1
        } else {
            exit 2
        }

        # A half-applied tweak or overlapping blocks must not be rewritten.
        if (state != -1 && state != found) {
            exit 2
        }
        state = found
        if (h > 1 && position[h,found] <= position[h-1,found]+size[h-1,found]-1) {
            exit 2
        }
    }

    if (action == "status") {
        print state ? "installed" : "uninstalled"
        exit
    }
    if (action != "install" && action != "uninstall") {
        exit 2
    }

    wanted = (action == "install") ? 1 : 0
    nextLine = 1
    for (h = 1; h <= hunks; h++) {
        at = position[h,state]
        while (nextLine < at) {
            print line[nextLine++]
        }
        for (j = 1; j <= size[h,wanted]; j++) {
            print block[h,wanted,j]
        }
        nextLine = at + size[h,state]
    }
    while (nextLine <= NR) {
        print line[nextLine++]
    }
}
TWEAK_PROGRAM_END

# Previous version is retained only for detection and selective removal.
cat > "$REPORT/legacy.awk" <<'LEGACY_PROGRAM_END'
BEGIN {
    hunks = 8

    # Clockwise rotation: remember the current focus before attempting a move.
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

    # Clockwise rotation: wrap to the first enabled item if focus did not move.
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

    # Counterclockwise rotation: remember the current focus before the move.
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

    # Counterclockwise rotation: wrap to the last enabled item.
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

    # Down tilt: remember the current focus before attempting a move.
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

    # Down tilt: wrap to the first enabled item if focus did not move.
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

    # Up tilt: remember the current focus before attempting a move.
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

    # Up tilt: wrap to the last enabled item.
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

# Compare the complete literal block; whitespace inside JS lines is significant.
function same(at, h, form,    j, length_) {
    length_ = size[h, form]
    if (at + length_ - 1 > NR) {
        return 0
    }

    for (j = 1; j <= length_; j++) {
        if (line[at+j-1] != block[h,form,j]) {
            return 0
        }
    }
    return 1
}

# Count matches only inside the expected handler, rejecting duplicates later.
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

# Keep the original lines and their containing handler for scoped matching.
{
    if ($0 ~ /^[A-Za-z0-9_]+\.prototype\.[A-Za-z0-9_]+ = function\(/) {
        current = $0
    }
    line[NR] = $0
    part[NR] = current
    if ($0 == "};") {
        current = ""
    }
}

# Require all eight blocks to agree on one state before emitting any result.
# Replacements copy all unrelated lines unchanged, so other tweaks survive.
END {
    state = -1
    for (h = 1; h <= hunks; h++) {
        oldCount = locate(h,0)
        newCount = locate(h,1)
        if (oldCount == 1 && newCount == 0) {
            found = 0
        } else if (oldCount == 0 && newCount == 1) {
            found = 1
        } else {
            exit 2
        }

        # A half-applied tweak or overlapping blocks must not be rewritten.
        if (state != -1 && state != found) {
            exit 2
        }
        state = found
        if (h > 1 && position[h,found] <= position[h-1,found]+size[h-1,found]-1) {
            exit 2
        }
    }

    if (action == "status") {
        print state ? "installed" : "uninstalled"
        exit
    }
    if (action != "install" && action != "uninstall") {
        exit 2
    }

    wanted = (action == "install") ? 1 : 0
    nextLine = 1
    for (h = 1; h <= hunks; h++) {
        at = position[h,state]
        while (nextLine < at) {
            print line[nextLine++]
        }
        for (j = 1; j <= size[h,wanted]; j++) {
            print block[h,wanted,j]
        }
        nextLine = at + size[h,state]
    }
    while (nextLine <= NR) {
        print line[nextLine++]
    }
}
LEGACY_PROGRAM_END
transform() {
  awk -v action="$1" -f "$REPORT/transform.awk" "$2"
}


# --- Detect this tweak's state without changing the system file ---
LEGACY=0
if ! STATE=$(transform status "$APP")
then
  cp "$REPORT/transform.awk" "$REPORT/corrected.awk" || fail 'Cannot save corrected transform.'
  cp "$REPORT/legacy.awk" "$REPORT/transform.awk" || fail 'Cannot select legacy transform.'
  STATE=$(transform status "$APP") || fail 'Unknown or partially modified patch locations. Nothing changed.'
  [ "$STATE" = installed ] || fail 'Unknown or partially modified patch locations. Nothing changed.'
  LEGACY=1
fi
echo "state=$STATE"

if [ "$ACTION" = status ]
then
  STATUS_RESULT=$STATE
  exit 0
fi


# --- Choose the action and stop early if the requested state is present ---
# Direct shell actions skip the dialog; the existing launcher uses dialog mode.
if [ "$UI" = 1 ]
then
  killall -q jci-dialog
  if /jci/tools/jci-dialog --3-button-dialog --title="$TITLE" --text='Wrap between the first and last selectable list items.\nWhat would you like to do?' --ok-label=Install --cancel-label=Uninstall --button3-label=Exit
  then
    ACTION=install
  elif [ $? -eq 1 ]
  then
    ACTION=uninstall
  else
    echo 'Cancelled. Nothing changed.'
    exit 0
  fi
fi

# Restore removes this tweak only, preserving other edits to the shared file.
if [ "$ACTION" = restore ]
then
  ACTION=uninstall
fi

if [ "$LEGACY:$ACTION" = 1:install ]
then
  fail 'Legacy List Loop is installed. Uninstall it, then install the corrected version.'
fi

if { [ "$ACTION" = install ] && [ "$STATE" = installed ]; } ||
   { [ "$ACTION" = uninstall ] && [ "$STATE" = uninstalled ]; }
then
  SUCCESS='Requested setting is already present.'
  exit 0
fi


# --- Retain a verified shared OEM backup ---
# An existing modified file is acceptable only when its OEM backup is present.
# Never replace that backup with a file containing another tweak's changes.
BACKUP="${APP}.org"
if [ -e "$BACKUP" ] || [ -L "$BACKUP" ]
then
  if [ ! -f "$BACKUP" ] || [ -L "$BACKUP" ] ||
     [ "$(hash "$BACKUP")" != "$ORIGINAL" ]
  then
    fail 'The .org backup is not the known OEM original.'
  fi
else
  if [ "$(hash "$APP")" != "$ORIGINAL" ]
  then
    fail 'The shared OEM .org backup is missing. Nothing changed.'
  fi
fi


# --- Prepare the change on USB and verify an exact inverse round trip ---
# The rollback copy includes every change already present, not just OEM bytes.
cp "$APP" "$REPORT/before.js" || fail 'Could not save USB rollback copy.'
BEFORE=$(hash "$APP")
if [ "$(hash "$REPORT/before.js")" != "$BEFORE" ]
then
  fail 'USB rollback copy mismatch.'
fi

transform "$ACTION" "$APP" > "$REPORT/desired.js" || fail 'Could not prepare targeted change.'
INVERSE=install
if [ "$ACTION" = install ]
then
  INVERSE=uninstall
fi

if ! transform "$INVERSE" "$REPORT/desired.js" > "$REPORT/reversed.js" ||
   ! cmp -s "$REPORT/reversed.js" "$REPORT/before.js"
then
  fail 'Inverse check failed. Nothing changed.'
fi
DESIRED=$(hash "$REPORT/desired.js")


# --- Enable writes only after the preparation and backup checks pass ---
WATCHDOG=$(cat /sys/class/gpio/Watchdog\ Disable/value) || fail 'Could not read watchdog state.'
case "$WATCHDOG" in
  0)
    echo 1 > /sys/class/gpio/Watchdog\ Disable/value || fail 'Could not disable watchdog.'
    WATCHDOG_CHANGED=1
    ;;
  1)
    ;;
  *)
    fail 'Unknown watchdog state.'
    ;;
esac

if awk '$2=="/" && $3!="rootfs" && $4 ~ /(^|,)ro(,|$)/ {f=1} END {exit !f}' /proc/mounts
then
  mount -o rw,remount / || fail 'Could not remount the system read-write.'
  ROOT_CHANGED=1
fi

if [ ! -e "$BACKUP" ]
then
  cp -a "$APP" "$BACKUP" && sync
  if [ "$(hash "$BACKUP")" != "$ORIGINAL" ]
  then
    rm -f "$BACKUP"
    fail 'Original backup failed.'
  fi
fi


# --- Write the prepared file, retry once, then roll back on failure ---
# Recheck immediately before writing in case another tool ignored our lock.
if [ "$(hash "$APP")" != "$BEFORE" ]
then
  fail 'Target changed while preparing the tweak.'
fi

# Writing into the existing file preserves its permissions and ownership.
cat "$REPORT/desired.js" > "$APP"
sync
if [ "$(hash "$APP")" != "$DESIRED" ]
then
  cat "$REPORT/desired.js" > "$APP"
  sync
fi

if [ "$(hash "$APP")" != "$DESIRED" ]
then
  cat "$REPORT/before.js" > "$APP"
  sync
  if [ "$(hash "$APP")" != "$BEFORE" ]
  then
    fatal 'Write AND rollback failed. Do NOT reboot the CMU.'
  fi
  fail 'Write failed; the complete previous file was restored.'
fi


# --- Report completion; the exit trap performs cleanup before any reboot ---
OFFER_REBOOT=1
SUCCESS="$ACTION completed. Other changes were preserved."
exit 0
