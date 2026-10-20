#!/bin/sh
# Fuel Consumption tweaks installer/uninstaller for Mazda CMU v74.00.324
#
# Three independent tweaks, each one can be installed, uninstalled or skipped:
#   1. Bar values          - L/100km value above every bar of both Fuel Consumption graphs
#                            (jci-mods/FuelConsumptionCtrl.js)
#   2. Fuel ending screen  - at ignition off show the Fuel Consumption screen instead of the
#                            i-stop screen, for 7 s instead of 5 s (jci-mods/ecoenergyApp.js)
#   3. Fuel ending data    - LD_PRELOAD shim for jciMMUI (jci-shims/fuel_ending_mmui.so):
#                            on i-stop cars the ending screen also gets its data (graphs filled)
#
# Safety:
#   - nothing is changed before the first "Continue" and the per-tweak "Install"/"Uninstall",
#   - md5 of this script (fuel-consumption.sh.md5) and of every file it brings (*.md5 next to it),
#   - a file on the head unit is only replaced if it is the exact known original
#     (jci-org/*.org.md5); backups: <file>.org and /jci/sm/*.fuelend-orig,
#   - every write is checked with md5 (one retry); on error that tweak is restored,
#   - files are written with "cat >" so their permissions are kept,
#   - reboot only at the end and only if something was changed.
# Log: logs/fuel-consumption.log
# ASCII only, LF line endings.

TITLE="Fuel Consumption Tweaks"

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
  [ -z "$4" ] && /jci/tools/jci-dialog --question --title="$TITLE" --text="$1" --ok-label="$2" --cancel-label="$3"
  [ -n "$4" ] && /jci/tools/jci-dialog --3-button-dialog --title="$TITLE" --text="$1" --ok-label="$2" --cancel-label="$3" --button3-label="$4"
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

# ======================================================================
# JS tweak: replace one GUI file with its jci-mods version
#   $1 name   $2 file on the head unit   $3 file name in jci-mods / jci-org
# Sets RESULT to the message for the user; returns 1 on error.
# ======================================================================
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
# Shim tweak: LD_PRELOAD for the jciMMUI service
# ======================================================================
SHIM_DIR=/data_persist/fuel-ending
SHIM=fuel_ending_mmui.so
SHIM_LINE='            <environ_var env_name="LD_PRELOAD" env_value="/data_persist/fuel-ending/fuel_ending_mmui.so"/>'
# Head unit files the shim was written for (analysed versions).
ECO=/jci/mmui/uia/libjciuiaecoenergy.so
ECO_MD5=ac44a5f1bbcbe32d83d4076e6e6f4562
MMUI=/jci/mmui/svcjcimmui.so
MMUI_MD5=3b63fa37aa2ae4989c1febaa18c1f292
EEM=/jci/lib/libjcieem_client.so

# Copy sm.conf and sm_WCP.conf to *.fuelend-orig right before they are edited.
# An existing copy is overwritten, so a restore always goes back to the state
# just before this run, never to an older copy. Returns 1 if a copy failed
# (then no copy is left behind).
shim_backup_confs() {
  for _c in sm.conf sm_WCP.conf
  do
    cp -a "/jci/sm/${_c}" "/jci/sm/${_c}.fuelend-orig"
    if [ "$(md5_of "/jci/sm/${_c}.fuelend-orig")" != "$(md5_of "/jci/sm/${_c}")" ]
    then
      echo "backup of ${_c} failed"
      shim_remove_backups
      return 1
    fi
    echo "backup done: /jci/sm/${_c}.fuelend-orig"
  done
  sync
  return 0
}

shim_remove_backups() {
  rm -f /jci/sm/sm.conf.fuelend-orig /jci/sm/sm_WCP.conf.fuelend-orig
  sync
}

# Undo a failed install: the conf files back from the copies made by
# shim_backup_confs, then the shim file. A copy is deleted once its file is
# restored and verified. Returns 0 if both conf files were restored (the shim
# file alone is harmless without the LD_PRELOAD line), 1 otherwise.
shim_restore_all() {
  _rc=0
  for _r in sm.conf sm_WCP.conf
  do
    _orig="/jci/sm/${_r}.fuelend-orig"
    if [ ! -e "$_orig" ]
    then
      echo "restore ${_r}: no copy"; _rc=1; continue
    fi
    _want=$(md5_of "$_orig")
    cp -a "$_orig" "/jci/sm/${_r}" && sync
    [ "$(md5_of "/jci/sm/${_r}")" = "$_want" ] || { cp -a "$_orig" "/jci/sm/${_r}"; sync; }
    if [ "$(md5_of "/jci/sm/${_r}")" = "$_want" ]
    then
      echo "restore ${_r}: OK"
      rm -f "$_orig"
    else
      echo "restore ${_r}: FAILED, copy kept: ${_orig}"; _rc=1
    fi
  done
  rm -f "${SHIM_DIR}/${SHIM}"
  rmdir "$SHIM_DIR" 2>/dev/null
  sync
  return $_rc
}

shim_install() {
  _name="Fuel ending data"
  _src="${MYDIR}/jci-shims/${SHIM}"
  _so_md5=$(md5_from "${_src}.md5")
  echo "--- ${_name}: install"
  if [ -z "$_so_md5" ] || [ "$(md5_of "$_src")" != "$_so_md5" ]
  then
    RESULT="${_name}:\njci-shims/${SHIM} is missing or damaged (md5).\nNothing was changed."; return 1
  fi
  echo "md5 OK   $_src"
  if [ "$(md5_of "$ECO")" != "$ECO_MD5" ] || [ "$(md5_of "$MMUI")" != "$MMUI_MD5" ]
  then
    echo "head unit: $ECO = $(md5_of "$ECO"), $MMUI = $(md5_of "$MMUI")"
    RESULT="${_name}:\nthe head unit's fuel module or MMUI is another\nversion than the analysed one.\nNothing was changed."; return 1
  fi
  if [ ! -f "$EEM" ]
  then
    RESULT="${_name}:\nmissing: ${EEM}\nNothing was changed."; return 1
  fi
  _already=1
  for _c in sm.conf sm_WCP.conf
  do
    _f="/jci/sm/$_c"
    _n=$(grep -c 'name="jciMMUI"' "$_f")
    _after=$(grep -A1 'name="jciMMUI"' "$_f" | tail -n 1)
    echo "$_c: jciMMUI lines = $_n, next line: $_after"
    if [ "$_n" != "1" ]
    then
      RESULT="${_name}:\nunexpected ${_c} layout.\nNothing was changed."; return 1
    fi
    if [ "$_after" != "$SHIM_LINE" ]
    then
      _already=0
      if echo "$_after" | grep -q "environ_var"
      then
        RESULT="${_name}:\njciMMUI already has another preload (${_c}).\nNothing was changed."; return 1
      fi
    fi
  done
  if [ "$_already" = "1" ] && [ "$(md5_of "${SHIM_DIR}/${SHIM}")" = "$_so_md5" ]
  then
    RESULT="${_name}:\nalready installed.\nNothing was changed."; return 0
  fi
  info "${_name}:\ninstalling...\nDo not remove the USB drive."
  make_rw
  if ! shim_backup_confs
  then
    RESULT="${_name}:\nthe backup of sm.conf failed.\nNothing was changed."; return 1
  fi
  mkdir -p "$SHIM_DIR"
  cat "$_src" > "${SHIM_DIR}/${SHIM}" && chmod 0644 "${SHIM_DIR}/${SHIM}" && sync
  if [ "$(md5_of "${SHIM_DIR}/${SHIM}")" != "$_so_md5" ]
  then
    echo "wrong after copy, retrying"
    cat "$_src" > "${SHIM_DIR}/${SHIM}" && chmod 0644 "${SHIM_DIR}/${SHIM}" && sync
    if [ "$(md5_of "${SHIM_DIR}/${SHIM}")" != "$_so_md5" ]
    then
      rm -f "${SHIM_DIR}/${SHIM}"
      rmdir "$SHIM_DIR" 2>/dev/null
      shim_remove_backups
      RESULT="${_name}:\ncopying the shim failed (md5).\nNothing was enabled."; return 1
    fi
  fi
  ls -la "${SHIM_DIR}/${SHIM}"
  for _c in sm.conf sm_WCP.conf
  do
    _f="/jci/sm/$_c"
    grep -q "$SHIM" "$_f" || sed -i "/name=\"jciMMUI\"/a\\${SHIM_LINE}" "$_f"
    _n=$(grep -c "$SHIM" "$_f")
    _after=$(grep -A1 'name="jciMMUI"' "$_f" | tail -n 1)
    grep -n -A2 'name="jciMMUI"' "$_f"
    if [ "$_n" != "1" ] || [ "$_after" != "$SHIM_LINE" ]
    then
      if shim_restore_all
      then
        RESULT="${_name}:\nediting ${_c} failed.\nEverything was restored."; return 1
      fi
      RESULT="${_name}:\nediting ${_c} failed and the restore failed!\nDo NOT reboot, check logs/${LOG_FILE}."; STOP=1; FATAL=1; return 1
    fi
  done
  CHANGED=1
  RESULT="${_name}:\ninstalled."
  return 0
}

shim_uninstall() {
  _name="Fuel ending data"
  echo "--- ${_name}: uninstall"
  _n1=$(grep -c "$SHIM" /jci/sm/sm.conf)
  _n2=$(grep -c "$SHIM" /jci/sm/sm_WCP.conf)
  if [ "$_n1" = "0" ] && [ "$_n2" = "0" ] && [ ! -e "${SHIM_DIR}/${SHIM}" ]
  then
    RESULT="${_name}:\nnot installed.\nNothing was changed."; return 0
  fi
  info "${_name}:\nuninstalling...\nDo not remove the USB drive."
  make_rw
  for _c in sm.conf sm_WCP.conf
  do
    sed -i "/fuel_ending_mmui/d" "/jci/sm/$_c"
    _n=$(grep -c fuel_ending_mmui "/jci/sm/$_c")
    echo "$_c: lines now: $_n"
    if [ "$_n" != "0" ]
    then
      RESULT="${_name}:\nrestoring ${_c} failed!\nDo NOT reboot, check logs/${LOG_FILE}."; STOP=1; FATAL=1; return 1
    fi
    rm -f "/jci/sm/${_c}.fuelend-orig"
  done
  rm -f "${SHIM_DIR}/${SHIM}"
  rmdir "$SHIM_DIR" 2>/dev/null
  sync
  CHANGED=1
  RESULT="${_name}:\nuninstalled."
  return 0
}

# ======================================================================
# Steps
# ======================================================================
run_step() {
  # $1 name  $2 description  $3 install function  $4 uninstall function  (+ args)
  _sname=$1; _desc=$2; _inst=$3; _uninst=$4; shift 4
  [ "$STOP" = "1" ] && return
  RESULT=""
  if ask "${_sname}:\n${_desc}\nWhat would you like to do?" "Install" "Uninstall" "Skip"
  then
    $_inst "$_sname" "$@"
  elif [ $? -eq 1 ]
  then
    $_uninst "$_sname" "$@"
  else
    echo "--- ${_sname}: skipped"
    return
  fi
  if [ $? -ne 0 ]; then
    echo "ERROR: $(echo "$RESULT" | sed 's/\\n/ /g')"
  else
    echo "$(echo "$RESULT" | sed 's/\\n/ /g')"
  fi
  sync
  # Show the result of a step. OK goes on, Exit skips the remaining steps.
  if ! ask "$RESULT" "OK" "Exit"
  then
    echo "remaining steps skipped by the user"
    STOP=1
  fi
}

run_step "Bar values" \
  "L/100km value above every bar\nof both Fuel Consumption graphs." \
  js_install js_uninstall \
  /jci/gui/apps/ecoenergy/controls/FuelConsumption/js/FuelConsumptionCtrl.js FuelConsumptionCtrl.js

run_step "Fuel ending screen" \
  "at ignition off show the Fuel Consumption screen\ninstead of the i-stop screen, for 7 s." \
  js_install js_uninstall \
  /jci/gui/apps/ecoenergy/js/ecoenergyApp.js ecoenergyApp.js

shim_install_wrap() { shim_install; }
shim_uninstall_wrap() { shim_uninstall; }
run_step "Fuel ending data" \
  "on i-stop cars the ending screen\nalso gets its data (graphs filled)." \
  shim_install_wrap shim_uninstall_wrap

# ======================================================================
# Reboot (only if something was changed)
# ======================================================================
sync
if [ "$FATAL" = "1" ]
then
  echo "=== ${TITLE} STOPPED after a failed restore, no reboot ==="
  sync
  confirm "A restore failed.\nDo NOT reboot, check logs/${LOG_FILE}."
  exit 1
elif [ "$CHANGED" = "1" ]
then
  echo "=== ${TITLE} complete, rebooting ==="
  sync
  if ask "Completed.\nRemove the USB drive and reboot." "Reboot now" "Reboot later"
  then
    reboot
  fi
else
  echo "=== ${TITLE} complete, nothing changed ==="
  sync
  confirm "Completed. Nothing was changed."
fi
exit 0
