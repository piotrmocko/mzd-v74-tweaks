#!/bin/sh

TITLE="Touchscreen Enabled Tweak"

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

# --- Require CMU firmware V70 or later ---
CMU_VER=$(grep '^JCI_SW_VER=' /jci/version.ini | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1)
echo "CMU version: ${CMU_VER}"
if ! printf '%s\n' "$CMU_VER" | awk -F. 'NF == 3 && $1 >= 70 { ok=1 } END { exit !ok }'
then
  sync
  confirm "This installer requires CMU firmware V70 or later.\nDetected version: ${CMU_VER}\nNOTHING was changed."
  exit 1
fi

# ======================================================================
# Installation/Uninstallation
# ======================================================================

ACTION=""
TOUCHSCREEN_STATE=""
if ask "Do you want to enable touchscreen while moving\nby disabling LVDS Speed Restriction toggle?" "Yes" "No" "Exit"
then
  ACTION="disable"
  TOUCHSCREEN_STATE="enabled"
elif [ $? -eq 1 ]
then
  ACTION="enable"
  TOUCHSCREEN_STATE="disabled"
else
  echo "exit requested by the user"
  exit 0
fi
info "Changing LVDS Speed Restriction config..."
/jci/scripts/set_lvds_speed_restriction_config.sh "$ACTION"
if [ $? -ne 0 ]; then
  echo "Failed to ${ACTION} LVDS Speed Restriction config"
  echo "=== ${TITLE} complete, failed ==="
  sync
  confirm "Failed to ${ACTION} LVDS Speed Restriction.\nTouchscreen state was not changed.\n"
  exit 1
else
  echo "Successfully ${ACTION}d LVDS Speed Restriction config"
  echo "Touchscreen ${TOUCHSCREEN_STATE} while moving"
  echo "=== ${TITLE} complete, rebooting ==="
  sync
  if ask "Touchscreen successfully ${TOUCHSCREEN_STATE} while moving.\nLVDS Speed Restriction ${ACTION}d.\nRemove the USB drive and reboot." "Reboot now" "Reboot later"
  then
    reboot
  fi
  exit 0
fi
