#!/bin/sh

TITLE="JCI Backup"

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

if ! ask "Create ZIP backup of JCI directory.\nIt may take 20-30 minutes.\nAt least 170 MB of free space is required on the USB drive.\nPress brake pedal every 20 minutes." "Start" "Exit"
then
  exit 0
fi

hwclock --hctosys

MYDIR=$(dirname "$(readlink -f "$0")")
SELF=$(readlink -f "$0")
SELF_NAME=$(basename "$SELF")

# Make the USB drive writable: find its mount point (also works from a subfolder).
MP="$MYDIR"
while [ "$MP" != "/" ] && ! grep -q " $MP " /proc/mounts; do MP=$(dirname "$MP"); done
mount -o rw,remount "$MP"

echo 1 > /sys/class/gpio/Watchdog\ Disable/value
mount -o rw,remount /

mkdir -p "${MYDIR}/logs"
LOG_FILE="${SELF_NAME%.sh}.log"
LOG="${MYDIR}/logs/${LOG_FILE}"

exec > "$LOG" 2>&1
echo "=== ${TITLE} start ==="
date

show_error()
{
  MESSAGE=$1
  echo "ERROR: ${MESSAGE}" >&2
  confirm "${MESSAGE}"
}

confirm_without_space_check()
{
  MESSAGE=$1
  echo "WARNING: ${MESSAGE}" >&2
  ask "${MESSAGE}\nFree space cannot be verified. Continue anyway?" "OK" "Cancel"
}

DF_OUTPUT=$(df -Pk "${MYDIR}" 2>&1)
DF_STATUS=$?
if [ "${DF_STATUS}" -ne 0 ]
then
  echo "df failed with status ${DF_STATUS}: ${DF_OUTPUT}" >&2
  confirm_without_space_check "Unable to check free space on the USB drive."
  if [ "$?" -ne 0 ]
  then
    exit 0
  fi
else
  AVAILABLE_KB=$(printf '%s\n' "${DF_OUTPUT}" | awk 'NR == 2 { print $4 }')
  case "${AVAILABLE_KB}" in
    ''|*[!0-9]*)
      confirm_without_space_check "Unable to determine free space on the USB drive."
      if [ "$?" -ne 0 ]
      then
        exit 0
      fi
      ;;
    *)
      if [ "${AVAILABLE_KB}" -lt 174080 ]
      then
        show_error "At least 170 MB of free space is required on the USB drive."
        exit 1
      fi
      ;;
  esac
fi

if ! command -v zip >/dev/null 2>&1
then
  show_error "The zip utility is not available."
  exit 1
fi

get_cmu_sw_version()
{
  _ver=$(grep "^JCI_SW_VER=" /jci/version.ini | sed 's/^.*_\([^_]*\)\"$/\1/')
  _patch=$(grep "^JCI_SW_VER_PATCH=" /jci/version.ini | sed 's/^.*\"\([^\"]*\)\"$/\1/')
  _flavor=$(grep "^JCI_SW_FLAVOR=" /jci/version.ini | sed 's/^.*_\([^_]*\)\"$/\1/')

  if [ -n "${_flavor}" ]
  then
    echo "${_ver}${_patch}-${_flavor}"
  else
    echo "${_ver}${_patch}"
  fi
}

CMU_SW_VER=$(get_cmu_sw_version)
if [ -z "${CMU_SW_VER}" ]
then
  show_error "Unable to determine the CMU software version."
  exit 1
fi

BACKUPZIP="${MYDIR}/JCI-${CMU_SW_VER}.zip"
ZIP_TMP="${BACKUPZIP}.tmp.$$"

echo "=== ${TITLE} start ==="
echo "Creating ${BACKUPZIP}"
info "Creating ZIP backup of JCI directory...\nIt may take 20-30 minutes.\nDo not remove the USB drive.\nPress brake pedal every 20 minutes."

zip -r "${ZIP_TMP}" /jci
ZIP_STATUS=$?
if [ "${ZIP_STATUS}" -ne 0 ]
then
  rm -f "${ZIP_TMP}"
  echo "ERROR: ZIP creation failed with status ${ZIP_STATUS}"
  show_error "JCI backup failed.\nCheck logs/${LOG_FILE} before removing the USB drive."
  exit 1
fi

if ! mv -f "${ZIP_TMP}" "${BACKUPZIP}"
then
  rm -f "${ZIP_TMP}"
  echo "ERROR: Failed to save ${BACKUPZIP}"
  show_error "JCI backup failed while saving the ZIP file.\nCheck logs/${LOG_FILE} before removing the USB drive."
  exit 1
fi

sync
echo "=== JCI backup complete ==="
killall -q jci-dialog
confirm "JCI backup saved successfully to the USB drive."
exit 0
