#!/bin/sh
# Independent list tweaks using the standard dialog and .org backup workflow.

TITLE="List Tweaks"

hwclock --hctosys

SELF=$(readlink -f "$0")
SELF_NAME=$(basename "$SELF")
MYDIR=$(dirname "$SELF")

# Make the USB drive writable: find its mount point (also works from a subfolder).
MP="$MYDIR"
while [ "$MP" != "/" ] && ! grep -q " $MP " /proc/mounts; do MP=$(dirname "$MP"); done
mount -o rw,remount "$MP"

mkdir -p "${MYDIR}/logs" || exit 1
LOG_FILE="${SELF_NAME%.sh}.log"
LOG="${MYDIR}/logs/${LOG_FILE}"

: > "$LOG" || exit 1
exec > "$LOG" 2>&1
echo "=== ${TITLE} start ==="
date

md5_of() { md5sum "$1" 2>/dev/null | cut -d' ' -f1; }
md5_from() { cut -c1-32 "$1" 2>/dev/null; }

dialog_kill() { killall -q jci-dialog; }

# Non-blocking status message.
info() {
  dialog_kill
  /jci/tools/jci-dialog --info --title="$TITLE" --text="$1" --no-cancel &
}

# Blocking status message.
confirm() {
  dialog_kill
  /jci/tools/jci-dialog --info --title="$TITLE" --text="$1" --no-cancel
}

# Blocking question; returns 0 for the OK button, non-zero otherwise.
ask() {
  dialog_kill
  # Display a 3-button dialog if a third button label is provided.
  if [ -n "$4" ]
  then
    /jci/tools/jci-dialog --3-button-dialog --title="$TITLE" --text="$1" --ok-label="$2" --cancel-label="$3" --button3-label="$4"
  else
    /jci/tools/jci-dialog --question --title="$TITLE" --text="$1" --ok-label="$2" --cancel-label="$3"
  fi
}

# --- Integrity of this script ---
_want=$(md5_from "${SELF}.md5")
if [ -z "$_want" ] || [ "$_want" != "$(md5_of "$SELF")" ]
then
  echo "ERROR: md5 of ${SELF_NAME} does not match ${SELF_NAME}.md5"
  sync
  confirm "The installer on the USB drive is damaged (md5).\nNOTHING was changed.\nCopy it again."
  exit 1
fi
echo "md5 OK   ${SELF_NAME}"

# --- Require CMU firmware V74.00.324 ---
CMU_VER=$(grep '^JCI_SW_VER=' /jci/version.ini | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1)
echo "CMU version: ${CMU_VER}"
if [ "${CMU_VER}" != "74.00.324" ]
then
  sync
  confirm "This installer only supports CMU firmware V74.00.324.\nDetected version: ${CMU_VER}\nNOTHING was changed."
  exit 1
fi

CHANGED=0
STOP=0
FATAL=0
RW_DONE=0

make_rw() {
  if [ "$RW_DONE" = "0" ]
  then
    echo 1 > /sys/class/gpio/Watchdog\ Disable/value
    mount -o rw,remount /
    RW_DONE=1
  fi
}

# All three options share List2Ctrl.js. Recognize the eight known combinations
# from their checksums; no separate installed-state file is needed.
APP=/jci/gui/common/controls/List2/js/List2Ctrl.js
BACKUP="${APP}.org"

variant_file() {
  if [ "$1" = 0 ]; then
    VARIANT="${MYDIR}/jci-org/List2Ctrl.js.org"
  else
    VARIANT="${MYDIR}/jci-mods/List2Ctrl-$1.js"
  fi
}

list_change() {
  _name=$1
  _bit=$2
  _enable=$3
  _original=$(md5_from "${MYDIR}/jci-org/List2Ctrl.js.org.md5")
  [ -n "$_original" ] || { RESULT="${_name}:\nOriginal checksum is missing."; return 1; }
  _current=$(md5_of "$APP")
  _mask=unknown
  for _candidate in 0 1 2 3 4 5 6 7; do
    variant_file "$_candidate"
    _expected=$(md5_from "${VARIANT}.md5")
    if [ -n "$_expected" ] && [ "$_current" = "$_expected" ]; then
      _mask=$_candidate
      break
    fi
  done
  if [ "$_mask" = unknown ]; then
    RESULT="${_name}:\nThe file on the head unit is not a known original or list-tweak combination.\nNothing was changed."; return 1
  fi
  if [ "$_enable" = 1 ]; then
    _next=$((_mask | _bit))
  else
    _next=$((_mask & ~_bit))
  fi
  if [ "$_mask" = "$_next" ]; then
    RESULT="${_name}:\nRequested setting is already present.\nNothing was changed."; return 0
  fi
  # An existing modified file is only accepted with its verified OEM backup.
  if [ -e "$BACKUP" ]; then
    if [ "$(md5_of "$BACKUP")" != "$_original" ]; then
      RESULT="${_name}:\nThe .org backup is not the known original.\nNothing was changed."; return 1
    fi
  elif [ "$_mask" != 0 ]; then
    RESULT="${_name}:\nThe .org backup is missing.\nNothing was changed."; return 1
  fi
  variant_file "$_next"
  _wanted=$(md5_from "${VARIANT}.md5")
  if [ -z "$_wanted" ] || [ "$(md5_of "$VARIANT")" != "$_wanted" ]; then
    RESULT="${_name}:\nThe USB payload is missing or damaged (md5).\nNothing was changed."; return 1
  fi
  info "${_name}:\nUpdating list settings...\nDo not remove the USB drive."
  make_rw
  if [ ! -e "$BACKUP" ]; then
    cp -a "$APP" "$BACKUP" && sync
    if [ "$(md5_of "$BACKUP")" != "$_original" ]; then
      rm -f "$BACKUP"; sync
      RESULT="${_name}:\nThe backup failed.\nNothing was changed."; return 1
    fi
  fi
  # Retain the entire previous combination for a failed-copy rollback.
  _before="${MYDIR}/logs/list-tweaks-before.js"
  cp "$APP" "$_before" && sync
  if [ "$(md5_of "$_before")" != "$_current" ]; then
    RESULT="${_name}:\nThe rollback copy failed.\nNothing was changed."; return 1
  fi
  cat "$VARIANT" > "$APP" && sync
  [ "$(md5_of "$APP")" = "$_wanted" ] || { cat "$VARIANT" > "$APP"; sync; }
  if [ "$(md5_of "$APP")" != "$_wanted" ]; then
    cat "$_before" > "$APP"; sync
    if [ "$(md5_of "$APP")" = "$_current" ]; then
      RESULT="${_name}:\nThe copy failed.\nThe previous settings were restored."; return 1
    fi
    RESULT="${_name}:\nCopy AND restore failed!\nDo NOT reboot, check logs/${LOG_FILE}."; STOP=1; FATAL=1; return 1
  fi
  [ "$_next" = 0 ] && rm -f "$BACKUP"
  CHANGED=1
  RESULT="${_name}:\nSetting updated. Other list tweaks are preserved."
  echo "List combination: $_mask -> $_next ($APP = $_wanted)"
  return 0
}

run_step() {
  [ "$STOP" = 1 ] && return
  _title=$1
  _flag=$2
  if ask "$1:\n$3\nWhat would you like to do?" "Install" "Uninstall" "Skip"; then
    list_change "$_title" "$_flag" 1
  elif [ $? -eq 1 ]; then
    list_change "$_title" "$_flag" 0
  else
    echo "--- $1: skipped"
    return
  fi
  echo "$(echo "$RESULT" | sed 's/\\n/ /g')"
  sync
  if ! ask "$RESULT" "OK" "Exit"; then STOP=1; fi
}

run_step "No list beep" 1 "Mute the two long multicontroller list beeps."
run_step "Shorter list delay" 2 "Reduce list autoscroll delays and intervals."
run_step "List loop" 4 "Wrap from the last selectable list item to the first and back."

sync
if [ "$FATAL" = 1 ]; then
  confirm "A restore failed.\nDo NOT reboot, check logs/${LOG_FILE}."
  exit 1
elif [ "$CHANGED" = 1 ]; then
  if ask "Completed.\nRemove the USB drive and reboot." "Reboot now" "Reboot later"; then reboot; fi
else
  confirm "Completed. Nothing was changed."
fi
exit 0

