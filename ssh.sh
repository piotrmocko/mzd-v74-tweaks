#!/bin/sh
# Persistent SSH access using the CMU native OpenSSH server.

TITLE="SSH Access"

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

SERVICE=/tmp/mnt/resources/mzd-v74-tweaks/ssh
SOURCE="${MYDIR}/services/ssh"
APP=/jci/scripts/stage_wifi.sh
BACKUP="${APP}.org"
ORIGINAL=d740449dea568696660a62fce0fb35bd
HOOK='sh /tmp/mnt/resources/mzd-v74-tweaks/ssh/service.sh boot >/dev/null 2>&1 &'
CHANGED=0
FATAL=0

make_rw() {
  echo 1 > /sys/class/gpio/Watchdog\ Disable/value
  mount -o rw,remount / && mount -o rw,remount /tmp/mnt/resources
}

payload_ok() {
  for _file in service.sh sshd_config password.hash; do
    _want=$(md5_from "${SOURCE}/${_file}.md5")
    [ -n "$_want" ] && [ "$(md5_of "${SOURCE}/${_file}")" = "$_want" ] || return 1
  done
}

installed_payload_ok() {
  _dir=${1:-$SERVICE}
  [ -d "$_dir" ] && [ ! -L "$_dir" ] || return 1
  for _file in service.sh sshd_config password.hash; do
    [ ! -L "${_dir}/${_file}" ] && cmp -s "${SOURCE}/${_file}" "${_dir}/${_file}" || return 1
  done
}

write_hook() {
  cat "${MYDIR}/jci-org/stage_wifi.sh.org"
  printf '%s\n' '# MZD v74 SSH' "$HOOK"
}

restore_hook() {
  cp -a "$BACKUP" "$APP" && sync
  [ "$(md5_of "$APP")" = "$ORIGINAL" ] || { cp -a "$BACKUP" "$APP"; sync; }
  [ "$(md5_of "$APP")" = "$ORIGINAL" ]
}

ssh_install() {
  if ! payload_ok || [ "$(md5_of "${MYDIR}/jci-org/stage_wifi.sh.org")" != "$ORIGINAL" ]; then
    RESULT="SSH:\nThe USB payload is missing or damaged (md5).\nNothing was changed."; return 1
  fi
  _current=$(md5_of "$APP")
  _hook=$(write_hook | md5sum | cut -d' ' -f1)
  if [ "$_current" != "$ORIGINAL" ] && [ "$_current" != "$_hook" ]; then
    RESULT="SSH:\nThe startup file is not a known original or SSH hook.\nNothing was changed."; return 1
  fi
  if [ -e "$BACKUP" ]; then
    if [ "$(md5_of "$BACKUP")" != "$ORIGINAL" ]; then
      RESULT="SSH:\nThe .org backup is not the known original.\nNothing was changed."; return 1
    fi
  elif [ "$_current" != "$ORIGINAL" ]; then
    RESULT="SSH:\nThe original .org backup is missing.\nNothing was changed."; return 1
  fi
  _check="$SOURCE"
  if [ -e "$SERVICE" ]; then
    if ! installed_payload_ok; then
      RESULT="SSH:\nExisting service files differ.\nNothing was overwritten."; return 1
    fi
    _check="$SERVICE"
  fi
  # This refuses another listener on 22; the OEM listener on 36000 is untouched.
  if ! sh "${_check}/service.sh" check; then
    RESULT="SSH:\nPrerequisite check failed (possibly port 22 in use).\nNothing was changed. Check logs/${LOG_FILE}."; return 1
  fi
  info "SSH:\nInstalling...\nDo not remove the USB drive."
  if ! make_rw; then RESULT="SSH:\nCould not make system storage writable."; return 1; fi
  if [ ! -e "$BACKUP" ]; then
    cp -a "$APP" "$BACKUP" && sync
    if [ "$(md5_of "$BACKUP")" != "$ORIGINAL" ]; then
      rm -f "$BACKUP"; sync
      RESULT="SSH:\nThe startup backup failed.\nNothing was enabled."; return 1
    fi
  fi
  if [ ! -e "$SERVICE" ]; then
    mkdir -p "$(dirname "$SERVICE")" || { RESULT="SSH:\nCould not create service parent directory."; return 1; }
    _stage="${SERVICE}.new-$$"
    mkdir "$_stage" || { RESULT="SSH:\nCould not prepare service directory."; return 1; }
    for _file in service.sh sshd_config password.hash; do
      cp "${SOURCE}/${_file}" "${_stage}/${_file}" || break
    done
    chmod 700 "$_stage/service.sh"
    chmod 600 "$_stage/sshd_config" "$_stage/password.hash"
    sync
    if ! installed_payload_ok "$_stage"; then
      for _file in service.sh sshd_config password.hash; do rm -f "${_stage}/${_file}"; done
      rmdir "$_stage"
      RESULT="SSH:\nCopying the service failed.\nNothing was enabled."; return 1
    fi
    if ! mv "$_stage" "$SERVICE"; then
      RESULT="SSH:\nPublishing the service failed.\nNothing was enabled."; return 1
    fi
  fi
  write_hook > "$APP"; sync
  [ "$(md5_of "$APP")" = "$_hook" ] || { write_hook > "$APP"; sync; }
  if [ "$(md5_of "$APP")" != "$_hook" ]; then
    if restore_hook; then
      RESULT="SSH:\nWriting the startup hook failed.\nThe original was restored."; return 1
    fi
    RESULT="SSH:\nWriting AND restoring the startup hook failed!\nDo NOT reboot, check logs/${LOG_FILE}."; FATAL=1; return 1
  fi
  printf 'enabled\n' > "$SERVICE/enabled"
  sync
  sh "$SERVICE/service.sh" boot "$MYDIR" >/dev/null 2>&1 &
  sleep 2
  if ! sh "$SERVICE/service.sh" status; then
    rm -f "$SERVICE/enabled"
    if sh "$SERVICE/service.sh" stop && restore_hook; then
      RESULT="SSH:\nThe service did not start.\nThe startup hook and runtime changes were reverted."; return 1
    fi
    RESULT="SSH:\nStartup and rollback failed!\nDo NOT reboot, check logs/${LOG_FILE}."; FATAL=1; return 1
  fi
  CHANGED=1
  RESULT="SSH:\nEnabled on port 22.\nUser: cmu\nPassword: jci\nWi-Fi must be enabled and connected."
  return 0
}

ssh_uninstall() {
  if ! payload_ok || [ "$(md5_of "${MYDIR}/jci-org/stage_wifi.sh.org")" != "$ORIGINAL" ]; then
    RESULT="SSH:\nThe USB payload is missing or damaged.\nNothing was changed."; return 1
  fi
  _current=$(md5_of "$APP")
  _hook=$(write_hook | md5sum | cut -d' ' -f1)
  if [ "$_current" != "$ORIGINAL" ] && [ "$_current" != "$_hook" ]; then
    RESULT="SSH:\nThe startup file has other changes.\nNothing was changed."; return 1
  fi
  if [ "$_current" = "$_hook" ] && [ "$(md5_of "$BACKUP")" != "$ORIGINAL" ]; then
    RESULT="SSH:\nThe original .org backup is missing or damaged.\nNothing was changed."; return 1
  fi
  if [ -e "$SERVICE" ] && ! installed_payload_ok; then
    RESULT="SSH:\nExisting service files differ.\nNothing was changed."; return 1
  fi
  if [ "$_current" = "$ORIGINAL" ] && [ ! -e "$SERVICE" ]; then
    RESULT="SSH:\nNot installed.\nNothing was changed."; return 0
  fi
  info "SSH:\nUninstalling...\nDo not remove the USB drive."
  if ! make_rw; then RESULT="SSH:\nCould not make system storage writable."; return 1; fi
  if [ "$_current" = "$_hook" ]; then
    if ! restore_hook; then
      RESULT="SSH:\nRestoring the startup file failed!\nDo NOT reboot, check logs/${LOG_FILE}."; FATAL=1; return 1
    fi
  fi
  if [ -d "$SERVICE" ]; then
    rm -f "$SERVICE/enabled"
    sync
    if ! sh "$SERVICE/service.sh" stop; then
      RESULT="SSH:\nThe startup hook was removed, but stopping the service failed.\nCheck logs/${LOG_FILE}."; FATAL=1; return 1
    fi
    for _file in service.sh sshd_config password.hash; do rm -f "${SERVICE}/${_file}"; done
    rmdir "$SERVICE" || { RESULT="SSH:\nService stopped; could not remove its directory."; return 1; }
  fi
  if [ "$(md5_of "$BACKUP")" = "$ORIGINAL" ]; then rm -f "$BACKUP"; fi
  sync
  CHANGED=1
  RESULT="SSH:\nUninstalled. Original startup file and account restored."
  return 0
}

if ask "SSH access:\nUse the CMU's native OpenSSH server on port 22.\nLogin: cmu / jci.\nWhat would you like to do?" "Install" "Uninstall" "Exit"; then
  ssh_install
elif [ $? -eq 1 ]; then
  ssh_uninstall
else
  echo 'Exit requested by the user'
  exit 0
fi
STATUS=$?
echo "$(echo "$RESULT" | sed 's/\\n/ /g')"
sync
confirm "$RESULT"
if [ "$FATAL" = 1 ]; then exit 1; fi
if [ "$CHANGED" = 1 ]; then
  if ask "Completed.\nRemove the USB drive and reboot." "Reboot now" "Reboot later"; then reboot; fi
fi
exit "$STATUS"

