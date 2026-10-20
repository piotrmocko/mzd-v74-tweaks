#!/bin/sh
# No More Disclaimer mod installer/uninstaller for Mazda CMU

TITLE="No More Disclaimer Tweak"

hwclock --hctosys

SELF=$(readlink -f "$0")
SELF_NAME=$(basename "$SELF")
MYDIR=$(dirname "$SELF")

# Make the USB drive writable: find its mount point (also works from a subfolder).
MP="$MYDIR"
while [ "$MP" != "/" ] && ! grep -q " $MP " /proc/mounts; do MP=$(dirname "$MP"); done
mount -o rw,remount "$MP"

mkdir -p "${MYDIR}/logs"
LOG_FILE="${SELF_NAME%.sh}.log"
LOG="${MYDIR}/logs/${LOG_FILE}"

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

js_install() {
  _app=$2
  _bak="${_app}.org"
  _mod="${MYDIR}/jci-mods/$3"
  _mod_md5=$(md5_from "${_mod}.md5")
  _org_md5=$(md5_from "${MYDIR}/jci-org/$3.org.md5")
  echo "--- $1: install"
  if [ -z "$_mod_md5" ] || [ "$(md5_of "$_mod")" != "$_mod_md5" ]
  then
    RESULT="$1:\njci-mods/$3 is missing or damaged (md5).\nNothing was changed."; return 1
  fi
  if [ -z "$_org_md5" ]
  then
    RESULT="$1:\njci-org/$3.org.md5 is missing.\nNothing was changed."; return 1
  fi
  _cur=$(md5_of "$_app")
  echo "head unit: $_app = $_cur"
  if [ "$_cur" = "$_mod_md5" ]
  then
    RESULT="$1:\nalready installed.\nNothing was changed."; return 0
  fi
  if [ "$_cur" != "$_org_md5" ]
  then
    RESULT="$1:\nthe file on the head unit is not the known original\n(other version or other mod).\nNothing was changed."; return 1
  fi
  if [ -e "$_bak" ] && [ "$(md5_of "$_bak")" != "$_org_md5" ]
  then
    RESULT="$1:\nthere is an unknown backup:\n${_bak}\nNothing was changed."; return 1
  fi
  info "$1:\ninstalling...\nDo not remove the USB drive."
  make_rw
  if [ ! -e "$_bak" ]
  then
    cp -a "$_app" "$_bak" && sync
    if [ "$(md5_of "$_bak")" != "$_org_md5" ]
    then
      rm -f "$_bak"; sync
      RESULT="$1:\nthe backup failed.\nNothing was changed."; return 1
    fi
    echo "backup done: $_bak"
  fi
  cat "$_mod" > "$_app" && sync
  if [ "$(md5_of "$_app")" != "$_mod_md5" ]
  then
    echo "wrong after copy, retrying"
    cat "$_mod" > "$_app" && sync
    if [ "$(md5_of "$_app")" != "$_mod_md5" ]
    then
      cp -a "$_bak" "$_app" && sync
      if [ "$(md5_of "$_app")" = "$_org_md5" ]
      then
        RESULT="$1:\nthe copy failed.\nThe original was restored."; return 1
      fi
      RESULT="$1:\ncopy AND restore failed!\nDo NOT reboot, check logs/${LOG_FILE}."; STOP=1; FATAL=1; return 1
    fi
  fi
  ls -la "$_app" "$_bak"
  echo "md5 OK   $_app"
  CHANGED=1
  RESULT="$1:\ninstalled."
  return 0
}

js_uninstall() {
  _app=$2
  _bak="${_app}.org"
  _org_md5=$(md5_from "${MYDIR}/jci-org/$3.org.md5")
  echo "--- $1: uninstall"
  if [ -z "$_org_md5" ]
  then
    RESULT="$1:\njci-org/$3.org.md5 is missing.\nNothing was changed."; return 1
  fi
  _cur=$(md5_of "$_app")
  echo "head unit: $_app = $_cur"
  if [ "$_cur" = "$_org_md5" ]
  then
    RESULT="$1:\nnot installed (the original is in place).\nNothing was changed."; return 0
  fi
  if [ ! -e "$_bak" ]
  then
    RESULT="$1:\nno backup (${_bak}).\nNothing was changed."; return 1
  fi
  if [ "$(md5_of "$_bak")" != "$_org_md5" ]
  then
    RESULT="$1:\nthe backup is not the known original.\nNothing was changed."; return 1
  fi
  info "$1:\nuninstalling...\nDo not remove the USB drive."
  make_rw
  cp -a "$_bak" "$_app" && sync
  [ "$(md5_of "$_app")" = "$_org_md5" ] || { cp -a "$_bak" "$_app"; sync; }
  if [ "$(md5_of "$_app")" != "$_org_md5" ]
  then
    RESULT="$1:\nthe restore failed!\nDo NOT reboot, check logs/${LOG_FILE}."; STOP=1; FATAL=1; return 1
  fi
  rm -f "$_bak" && sync
  echo "md5 OK   $_app (original)"
  CHANGED=1
  RESULT="$1:\nuninstalled, the original is back."
  return 0
}

# ======================================================================
# Installation/Uninstallation
# ======================================================================
RESULT=""
if ask "What would you like to do?" "Install" "Uninstall" "Exit"
then
  js_install "$TITLE" /jci/gui/apps/system/js/systemApp.js systemApp.js
elif [ $? -eq 1 ]
then
  js_uninstall "$TITLE" /jci/gui/apps/system/js/systemApp.js systemApp.js
else
  echo "Exit requested by the user"
  echo "=== ${TITLE} complete ==="
  exit 0
fi
if [ $? -ne 0 ]; then
  echo "ERROR: $(echo "$RESULT" | sed 's/\\n/ /g')"
else
  echo "$(echo "$RESULT" | sed 's/\\n/ /g')"
fi
sync
confirm "$RESULT"

# ======================================================================
# Reboot (only if something was changed)
# ======================================================================
echo "=== ${TITLE} complete ==="
if [ "$FATAL" = "1" ]
then
  exit 1
elif [ "$CHANGED" = "1" ]
then
  sync
  if ask "Remove the USB drive and reboot." "Reboot now" "Reboot later"
  then
    reboot
  fi
fi
exit 0
