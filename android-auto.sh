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
    if ! echo 1 > /sys/class/gpio/Watchdog\ Disable/value
    then
      echo "ERROR: Could not disable the watchdog"
      return 1
    fi
    if ! mount -o rw,remount /
    then
      echo "ERROR: Could not remount / read-write"
      echo 0 > /sys/class/gpio/Watchdog\ Disable/value
      return 1
    fi
    RW_DONE=1
  fi
  return 0
}

make_ro() {
  if [ "$RW_DONE" = "1" ]
  then
    if ! mount -o ro,remount /
    then
      echo "ERROR: Could not remount / read-only"
      return 1
    fi
    if ! echo 0 > /sys/class/gpio/Watchdog\ Disable/value
    then
      echo "ERROR: Could not re-enable the watchdog"
      return 1
    fi
    RW_DONE=0
  fi
  return 0
}

fail() {
  echo "ERROR: $*"
  FATAL=1
}

copy_checked() {
  _copy_src=$1
  _copy_dst=$2
  _copy_label=$3
  if [ ! -f "$_copy_src" ] || ! cp "$_copy_src" "$_copy_dst" || ! cmp -s "$_copy_src" "$_copy_dst"
  then
    fail "Could not copy or verify ${_copy_label}"
    return 1
  fi
  return 0
}

patch_service() {
  _patch_conf=$1
  _patch_service=$2
  _patch_library=$3
  _patch_line="env_value=\"/data_persist/oem-aa-mod/${_patch_library}\""

  if grep -qF "$_patch_line" "$_patch_conf"
  then
    echo "${_patch_library} already configured in ${_patch_conf}"
    return 0
  fi
  if ! grep -q "name=\"${_patch_service}\"" "$_patch_conf"
  then
    fail "Service ${_patch_service} not found in ${_patch_conf}"
    return 1
  fi
  if ! sed -i "/name=\"${_patch_service}\"/a\\            <environ_var env_name=\"LD_PRELOAD\" env_value=\"/data_persist/oem-aa-mod/${_patch_library}\"/>" "$_patch_conf" ||
     ! grep -qF "$_patch_line" "$_patch_conf"
  then
    fail "Could not patch ${_patch_service} in ${_patch_conf}"
    return 1
  fi
  echo "Patched ${_patch_service} in ${_patch_conf}"
  return 0
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
FATAL=0
OPERATION=""

if [ $CHOICE -eq 0 ]
then
  # ============================================================
  # INSTALL
  # ============================================================
  echo "=== $TITLE install start ==="
  OPERATION="install"

  if ! make_rw
  then
    fail "Could not make the system partition writable"
  fi
  if [ "$RW_DONE" = "1" ]
  then
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
      if [ ! -f "/jci/sm/${conf}" ]
      then
        fail "Missing /jci/sm/${conf}"
        continue
      fi
      if [ ! -e "/jci/sm/${conf}.orig" ]
      then
        if cp -a "/jci/sm/${conf}" "/jci/sm/${conf}.orig" &&
           cmp -s "/jci/sm/${conf}" "/jci/sm/${conf}.orig"
        then
          echo "Backed up ${conf}"
        else
          fail "Could not back up ${conf}; leaving it unmodified"
          continue
        fi
      else
        if [ ! -f "/jci/sm/${conf}.orig" ]
        then
          fail "${conf}.orig is not a regular file; leaving ${conf} unmodified"
          continue
        fi
        echo "${conf} backup already exists"
      fi

      patch_service "/jci/sm/${conf}" "jciAAPA" "libpatch-blmjciaapa.so"
      patch_service "/jci/sm/${conf}" "jcinavi" "libpatch-svcjcinavi.so"

      if [ "${USE_PROTOCOL_V16}" = "true" ]
      then
        patch_service "/jci/sm/${conf}" "aap_service" "libpatch-aap_service.so"
      else
        echo "use_protocol_v1_6 is false, skipping aap_service patch in ${conf}"
      fi
    done

    # --- Install libraries ---
    if ! mkdir -p /data_persist/oem-aa-mod
    then
      fail "Could not create /data_persist/oem-aa-mod"
    else
      copy_checked "${MYDIR}/jci-shims/libpatch-blmjciaapa.so" "/data_persist/oem-aa-mod/libpatch-blmjciaapa.so" "libpatch-blmjciaapa.so"
      copy_checked "${MYDIR}/jci-shims/libpatch-svcjcinavi.so" "/data_persist/oem-aa-mod/libpatch-svcjcinavi.so" "libpatch-svcjcinavi.so"
      if [ "${USE_PROTOCOL_V16}" = "true" ]
      then
        copy_checked "${MYDIR}/jci-shims/libpatch-aap_service.so" "/data_persist/oem-aa-mod/libpatch-aap_service.so" "libpatch-aap_service.so"
      else
        echo "use_protocol_v1_6 is false, skipping libpatch-aap_service.so copy"
      fi
      copy_checked "${MYDIR}/config/libpatch.conf" "/data_persist/oem-aa-mod/libpatch.conf" "libpatch.conf"
      if ! chmod 0644 /data_persist/oem-aa-mod/libpatch-*.so
      then
        fail "Could not set permissions on installed libraries"
      fi
    fi

    # --- Backup and install XML configs ---
    for xml in aap_system_attributes.xml aap_system_attributes_UCP.xml
    do
      if [ ! -f "/etc/${xml}" ]
      then
        fail "Missing /etc/${xml}"
        continue
      fi
      if [ ! -e "/etc/${xml}.orig" ]
      then
        if cp -a "/etc/${xml}" "/etc/${xml}.orig" &&
           cmp -s "/etc/${xml}" "/etc/${xml}.orig"
        then
          echo "Backed up ${xml}"
        else
          fail "Could not back up ${xml}; leaving it unmodified"
          continue
        fi
      else
        if [ ! -f "/etc/${xml}.orig" ]
        then
          fail "${xml}.orig is not a regular file; leaving ${xml} unmodified"
          continue
        fi
        echo "${xml}.orig already exists, skipping backup"
      fi
      copy_checked "${MYDIR}/config/${xml}" "/etc/${xml}" "${xml}"
    done

    sync
    echo "=== $TITLE install complete ==="
  fi

elif [ $CHOICE -eq 1 ]
then
  # ============================================================
  # UNINSTALL
  # ============================================================
  echo "=== $TITLE uninstall start ==="
  OPERATION="uninstall"

  if ! make_rw
  then
    fail "Could not make the system partition writable"
  fi
  if [ "$RW_DONE" = "1" ]
  then
    info "Uninstalling $TITLE...\nDo not remove USB drive."

    # --- Restore sm.conf and sm_WCP.conf ---
    for conf in sm.conf sm_WCP.conf
    do
      if [ ! -f "/jci/sm/${conf}" ]
      then
        fail "Missing /jci/sm/${conf}"
        continue
      fi
      if ! sed -i '/env_value="\/data_persist\/oem-aa-mod\//d' "/jci/sm/${conf}" ||
         grep -qF '/data_persist/oem-aa-mod/' "/jci/sm/${conf}"
      then
        fail "Could not remove OEM Android Auto entries from ${conf}"
      else
        echo "Removed OEM Android Auto entries from ${conf}"
        if [ -e "/jci/sm/${conf}.orig" ]
        then
          if rm "/jci/sm/${conf}.orig"
          then
            echo "Removed ${conf}.orig"
          else
            echo "WARNING: Could not remove ${conf}.orig"
          fi
        fi
      fi
    done

    # --- Restore XML configs ---
    for xml in aap_system_attributes.xml aap_system_attributes_UCP.xml
    do
      if [ -e "/etc/${xml}.orig" ]
      then
        if cp -a "/etc/${xml}.orig" "/etc/${xml}" &&
           cmp -s "/etc/${xml}.orig" "/etc/${xml}"
        then
          if rm "/etc/${xml}.orig"
          then
            echo "Restored ${xml} and removed its backup"
          else
            echo "WARNING: Restored ${xml}, but could not remove its backup"
          fi
        else
          fail "Could not restore ${xml}; backup retained at /etc/${xml}.orig"
        fi
      else
        echo "WARNING: ${xml}.orig not found, skipping restore"
      fi
    done

    # --- Remove installed libraries and config ---
    for file in libpatch-blmjciaapa.so libpatch-svcjcinavi.so libpatch-aap_service.so libpatch.conf
    do
      if ! rm -f "/data_persist/oem-aa-mod/${file}"
      then
        echo "WARNING: Could not remove ${file}"
      else
        echo "Removed ${file}"
      fi
    done
    rmdir /data_persist/oem-aa-mod 2>/dev/null && echo "Removed /data_persist/oem-aa-mod directory"

    sync
    echo "=== $TITLE uninstall complete ==="
  fi

else
  # ============================================================
  # CANCEL (Cancel button, or the dialog failed): change nothing, no reboot
  # ============================================================
  exit 0
fi

sync
if [ "$FATAL" = "1" ]
then
  echo "=== $TITLE stopped after the ${OPERATION} operation failed, no reboot ==="
  confirm "The ${OPERATION} operation failed.\nDo NOT reboot\nCheck logs/${LOG_FILE}."
  exit 1
fi

if ask "The ${OPERATION} completed successfully.\nRemove the USB drive and reboot." "Reboot now" "Reboot later"
then
  reboot
else
  # Operation requires reboot to take effect, but user chose to reboot later.
  # Rstoring the system partition to read-only. Do not report the failre as reboot is required.
  make_ro
fi
exit 0
