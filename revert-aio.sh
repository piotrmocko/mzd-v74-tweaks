#!/bin/sh

TITLE="AIO Tweaks Uninstaller"

/jci/tools/jci-dialog --question \
  --title="$TITLE" \
  --text="Would you like to uninstall AIO Tweaks?" \
  --ok-label="Uninstall" \
  --cancel-label="Exit"
CHOICE=$?

if [ "${CHOICE}" -ne 0 ]
then
  exit 0
fi

hwclock --hctosys

SELF=$(readlink -f "$0")
SELF_NAME=$(basename "$SELF")
MYDIR=$(dirname "$SELF")

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

/jci/tools/jci-dialog --info --title="$TITLE" \
  --text="Uninstalling AIO Tweaks...\nDo not remove USB drive." --no-cancel &

RESTORE_FAILED=0

restore_config()
{
  FILE=$1
  BACKUP="${FILE}.org"

  if [ ! -f "${BACKUP}" ]
  then
    echo "WARNING: ${BACKUP} not found, skipping restore"
    RESTORE_FAILED=1
    return 1
  fi

  if ! cp -a "${BACKUP}" "${FILE}"
  then
    echo "ERROR: Failed to restore ${FILE} from ${BACKUP}"
    RESTORE_FAILED=1
    return 1
  fi

  FILE_SIZE=$(wc -c < "${FILE}")
  BACKUP_SIZE=$(wc -c < "${BACKUP}")
  if [ "${FILE_SIZE}" -ne "${BACKUP_SIZE}" ]
  then
    echo "ERROR: Restored ${FILE} size does not match ${BACKUP}"
    RESTORE_FAILED=1
    return 1
  fi

  if ! cmp -s "${BACKUP}" "${FILE}"
  then
    echo "ERROR: Restored ${FILE} does not match ${BACKUP}; keeping backup"
    RESTORE_FAILED=1
    return 1
  fi

  if ! rm "${BACKUP}"
  then
    echo "ERROR: Restored ${FILE}, but failed to remove ${BACKUP}"
    RESTORE_FAILED=1
    return 1
  fi

  echo "Restored ${FILE}; size and content match the original backup"
}

restore_config /jci/sm/sm.conf
restore_config /jci/opera/opera_home/opera.ini

FPS_FILE=/jci/opera/opera_dir/userjs/fps.js
FPS_BACKUP="${FPS_FILE}.org"
if [ -e "${FPS_BACKUP}" ]
then
  if mv "${FPS_BACKUP}" "${FPS_FILE}"
  then
    echo "Restored ${FPS_FILE} from ${FPS_BACKUP}"
  else
    echo "ERROR: Failed to move ${FPS_BACKUP} to ${FPS_FILE}"
    RESTORE_FAILED=1
  fi
else
  echo "WARNING: ${FPS_BACKUP} not found, skipping restore"
  RESTORE_FAILED=1
fi

sync
echo "=== $TITLE complete ==="

killall -q jci-dialog
if [ "${RESTORE_FAILED}" -eq 0 ]
then
  if /jci/tools/jci-dialog --question --title="$TITLE" \
    --text="Uninstall complete!\nRemove the USB drive and reboot." \
    --ok-label="Reboot now" --cancel-label="Reboot later"
  then
    reboot
  fi
else
  /jci/tools/jci-dialog --info --title="$TITLE" \
    --text="Uninstall encountered errors.\nDo not remove the USB drive.\nReview logs/${LOG_FILE}." --no-cancel
fi

exit "${RESTORE_FAILED}"
