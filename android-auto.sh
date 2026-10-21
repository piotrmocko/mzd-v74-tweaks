#!/bin/sh
# oem-aa-mod installer/uninstaller for Mazda CMU
# initially created by Bijan
# https://github.com/VitaliyKurokhtin/oem-aa-mod

TITLE="OEM Android Auto Mods"

hwclock --hctosys

SELF=$(readlink -f "$0")
SELF_NAME=$(basename "$SELF")
MYDIR=$(dirname "$SELF")
mount -o rw,remount ${MYDIR}

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

RW_DONE=0
make_rw() {
  if [ "$RW_DONE" = "0" ]
  then
    echo 1 > /sys/class/gpio/Watchdog\ Disable/value
    mount -o rw,remount /
    RW_DONE=1
  fi
}

mkdir -p "${MYDIR}/logs"
LOG_FILE="${SELF_NAME%.sh}.log"
LOG="${MYDIR}/logs/${LOG_FILE}"

exec > "$LOG" 2>&1
echo "=== ${TITLE} start ==="
date

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
  echo "ERROR: This installer only supports CMU firmware V74.00.324, detected version: ${CMU_VER}"
  sync
  confirm "This installer only supports CMU firmware V74.00.324.\nDetected version: ${CMU_VER}\nNOTHING was changed."
  exit 1
fi

ask "What would you like to do?" "Install" "Uninstall" "Cancel"
CHOICE=$?
FATAL=0 # TODO: set to 1 if any fatal error occurs: failed to copy or patch. Adjust the ending message accordingly, for example: "A restore failed.\nDo NOT reboot, check logs/${LOG_FILE}."

if [ $CHOICE -eq 0 ]
then
  # ============================================================
  # INSTALL
  # ============================================================
  echo "=== $TITLE install start ==="

  make_rw
  info "Installing $TITLE...\nDo not remove USB drive."

  # --- Read use_protocol_v1_6 from the config being deployed ---
  # aap_service is only needed for GAL 1.6; default (missing file or key) is false.
  CONF="${MYDIR}/config/libpatch.conf"
  USE_PROTOCOL_V16="false"
  if [ -f "${CONF}" ]
  then
    val=$(sed 's/#.*//' "${CONF}" \
            | grep -i '^[[:space:]]*use_protocol_v1_6[[:space:]]*=' \
            | tail -n1 | cut -d'=' -f2- | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
    case "${val}" in
      true|1|yes|on) USE_PROTOCOL_V16="true" ;;
    esac
  fi
  echo "use_protocol_v1_6 = ${USE_PROTOCOL_V16} (from ${CONF})"

  # --- Backup and patch jciAAPA in sm.conf and sm_WCP.conf ---
  for conf in sm.conf sm_WCP.conf
  do
    if [ ! -e "/jci/sm/${conf}.orig" ]
    then
      cp -a "/jci/sm/${conf}" "/jci/sm/${conf}.orig"
      # TODO validate if backup was successful
      echo "Backed up ${conf}"
    else
      echo "${conf} backup already exists"
    fi

    if ! grep -q "libpatch-blmjciaapa" "/jci/sm/${conf}"
    then
      sed -i '/name="jciAAPA"/a\            <environ_var env_name="LD_PRELOAD" env_value="/data_persist/oem-aa-mod/libpatch-blmjciaapa.so"/>' "/jci/sm/${conf}"
      # TODO validate if patch was successful
      echo "Patched jciAAPA in ${conf}"
    else
      echo "jciAAPA already patched in ${conf}, skipping"
    fi

    if ! grep -q "libpatch-svcjcinavi" "/jci/sm/${conf}"
    then
      sed -i '/name="jcinavi"/a\            <environ_var env_name="LD_PRELOAD" env_value="/data_persist/oem-aa-mod/libpatch-svcjcinavi.so"/>' "/jci/sm/${conf}"
      # TODO validate if patch was successful
      echo "Patched jcinavi in ${conf}"
    else
      echo "jcinavi already patched in ${conf}, skipping"
    fi

    if [ "${USE_PROTOCOL_V16}" = "true" ]
    then
      if ! grep -q "libpatch-aap_service" "/jci/sm/${conf}"
      then
        sed -i '/name="aap_service"/a\            <environ_var env_name="LD_PRELOAD" env_value="/data_persist/oem-aa-mod/libpatch-aap_service.so"/>' "/jci/sm/${conf}"
        # TODO validate if patch was successful
        echo "Patched aap_service in ${conf}"
      else
        echo "aap_service already patched in ${conf}, skipping"
      fi
    else
      echo "use_protocol_v1_6 is false, skipping aap_service patch in ${conf}"
    fi
  done

  # --- Install libraries ---
  mkdir -p /data_persist/oem-aa-mod
  cp "${MYDIR}/jci-shims/libpatch-blmjciaapa.so" /data_persist/oem-aa-mod/
  echo "libpatch-blmjciaapa.so has been copied"
  cp "${MYDIR}/jci-shims/libpatch-svcjcinavi.so" /data_persist/oem-aa-mod/
  echo "libpatch-svcjcinavi.so has been copied"
  if [ "${USE_PROTOCOL_V16}" = "true" ]
  then
    cp "${MYDIR}/jci-shims/libpatch-aap_service.so" /data_persist/oem-aa-mod/
    echo "libpatch-aap_service.so has been copied"
  else
    echo "use_protocol_v1_6 is false, skipping libpatch-aap_service.so copy"
  fi
  cp "${MYDIR}/config/libpatch.conf" /data_persist/oem-aa-mod/
  echo "libpatch.conf has been copied"
  chmod 0644 /data_persist/oem-aa-mod/libpatch-*.so

  # --- Backup and install XML configs ---
  for xml in aap_system_attributes.xml aap_system_attributes_UCP.xml
  do
    if [ ! -e "/etc/${xml}.orig" ]
    then
      cp -a "/etc/${xml}" "/etc/${xml}.orig"
      echo "Backed up ${xml}"
    else
      echo "${xml}.orig already exists, skipping backup"
    fi
    cp "${MYDIR}/config/${xml}" "/etc/${xml}"
    echo "Installed ${xml}"
  done

  sync
  echo "=== $TITLE install complete ==="

  # TODO ask the user to Rebbot now or Reboot later, and reboot only if the user chooses to reboot now. If Reboot later, then revert make_rw
  info "Installation complete!\nYou can remove the USB drive.\nRebooting in 15 seconds..."

elif [ $CHOICE -eq 1 ]
then
  # ============================================================
  # UNINSTALL
  # ============================================================
  echo "=== $TITLE uninstall start ==="

  make_rw
  info "Uninstalling $TITLE...\nDo not remove USB drive."

  # --- Restore sm.conf and sm_WCP.conf ---
  for conf in sm.conf sm_WCP.conf
  do
    # TODO always remove the entry manually, never by restorying the backup, because the backup may be outdated if the user updated the CMU firmware after installing this mod.
    if [ -e "/jci/sm/${conf}.orig" ]
    then
      cp -a "/jci/sm/${conf}.orig" "/jci/sm/${conf}"
      # TODO remove the backup after validating that manual removal was successful and the mod line is no longer present
      rm "/jci/sm/${conf}.orig"
      echo "Restored ${conf} from backup"
    else
      echo "WARNING: ${conf}.orig not found; removing LD_PRELOAD lines manually"
      sed -i '/env_value="\/data_persist\/oem-aa-mod\//d' "/jci/sm/${conf}"
      echo "Removed LD_PRELOAD entries from ${conf}"
    fi
  done

  # --- Restore XML configs ---
  for xml in aap_system_attributes.xml aap_system_attributes_UCP.xml
  do
    if [ -e "/etc/${xml}.orig" ]
    then
      cp -a "/etc/${xml}.orig" "/etc/${xml}"
      # TODO remove the backup only if restoring (cp) was successful, otherwise keep it for manual restore
      rm "/etc/${xml}.orig"
      echo "Restored ${xml} from backup"
    else
      echo "WARNING: ${xml}.orig not found, skipping restore"
    fi
  done

  # --- Remove installed libraries and config ---
  rm -f /data_persist/oem-aa-mod/libpatch-blmjciaapa.so
  echo "Removed libpatch-blmjciaapa.so"
  rm -f /data_persist/oem-aa-mod/libpatch-svcjcinavi.so
  echo "Removed libpatch-svcjcinavi.so"
  rm -f /data_persist/oem-aa-mod/libpatch-aap_service.so
  echo "Removed libpatch-aap_service.so"
  rm -f /data_persist/oem-aa-mod/libpatch.conf
  echo "Removed libpatch.conf"
  rmdir /data_persist/oem-aa-mod 2>/dev/null && echo "Removed /data_persist/oem-aa-mod directory"

  sync
  echo "=== $TITLE uninstall complete ==="

  # TODO ask the user to Rebbot now or Reboot later, and reboot only if the user chooses to reboot now. If Reboot later, then revert make_rw
  info "Uninstall complete!\nYou can remove the USB drive.\nRebooting in 15 seconds..."

else
  # ============================================================
  # CANCEL (Cancel button, or the dialog failed): change nothing, no reboot
  # ============================================================
  sync
  confirm "Cancelled.\nNothing was changed.\nYou can remove the USB drive."
  exit 0
fi

sleep 15
dialog_kill
reboot
exit 0
