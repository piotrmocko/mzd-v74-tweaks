#!/bin/sh
#
# Copy /var/log/running_log onto the removable drive or change its rotation size.

TITLE="Running Logs Collector"

SELF=$(readlink -f "$0")
SELF_NAME=$(basename "$SELF")
MYDIR=$(dirname "$SELF")

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

change_rotation_size() {
  KIB=$1
  CONF=/data/log/syslog-ng.conf
  info "Changing running logs rotation size to $KIB KiB..."

  if [ ! -f "$CONF" ]; then
    echo "error: configuration file not found: $CONF" >&2
    confirm "Failed to change the running logs rotation size:\n$CONF was not found."
    exit 1
  fi

  if ! grep -Fq '/var/log/running_log/ ' "$CONF"; then
    echo "error: running_log rotation entry not found in $CONF" >&2
    confirm "Failed to change the running logs rotation size:\nno running_log entry was found."
    exit 1
  fi

  if [ ! -e "$CONF.orig" ] && ! cp -p "$CONF" "$CONF.orig"; then
    echo "error: failed to back up $CONF to $CONF.orig" >&2
    confirm "Failed to back up $CONF.\nThe running logs rotation size was not changed."
    exit 1
  fi

  if ! sed -i "s|\(/var/log/running_log/ \)[0-9]*\"|\1$KIB\"|" "$CONF" ||
     ! grep -Fq "/var/log/running_log/ $KIB\"" "$CONF"; then
    echo "error: failed to set running_log rotation size to $KIB KiB in $CONF" >&2
    confirm "Failed to change the running logs rotation size to $KIB KiB."
    exit 1
  fi

  grep -n 'running_log/ ' "$CONF"
  echo "running_log rotation size set to $KIB KiB"
  if ask "Running logs rotation size set to $KIB KiB.\nRemove the USB drive and reboot." "Reboot now" "Reboot later"
  then
    reboot
  fi
  exit 0
}

copy_logs() {
  info "Copying running logs to the USB drive..."
  hwclock --hctosys

  SRC=/var/log/running_log
  MYDIR=$(dirname "$(readlink -f "$0")")

  # Make the USB drive writable: find its mount point (also works from a subfolder).
  MP="$MYDIR"
  while [ "$MP" != "/" ] && ! grep -q " $MP " /proc/mounts; do MP=$(dirname "$MP"); done
  mount -o rw,remount "$MP"

  LOGDIR="${MYDIR}/logs"
  if ! mkdir -p "$LOGDIR"; then
    echo "error: cannot create $LOGDIR" >&2
    confirm "Failed to create $LOGDIR on the USB drive."
    exit 1
  fi

  RW_DONE=0
  make_rw() {
    if [ "$RW_DONE" = "0" ]; then
      echo 1 > /sys/class/gpio/Watchdog\ Disable/value
      mount -o rw,remount /
      RW_DONE=1
    fi
  }

  # Each run goes into its own numbered folder: <dest>/1, <dest>/2, ...
  # Highest existing number wins, so a gap never causes a reuse.
  max=0
  for d in "$LOGDIR"/*; do
      [ -d "$d" ] || continue
      b=${d##*/}
      case "$b" in
          ''|*[!0-9]*) continue ;;
      esac
      # Trim leading zeros - the shell would read them as octal.
      while [ "$b" != "${b#0}" ] && [ "$b" != "0" ]; do
          b=${b#0}
      done
      [ "$b" -gt "$max" ] && max=$b
  done

  LOGDIR="$LOGDIR/$((max + 1))"

  # Plain mkdir, not -p: if it already exists something is off, so stop rather
  # than write into someone else's folder.
  if ! mkdir "$LOGDIR"; then
      echo "error: cannot create $LOGDIR" >&2
      confirm "Failed to create $LOGDIR\non the USB drive."
      exit 1
  fi

  # Plain -r, not -a: the card is usually vfat, where preserving owner/mode
  # fails and would abort the copy for no good reason.
  n=0
  for f in "$SRC"/*; do
      [ -e "$f" ] || continue
      sync
      make_rw
      if ! cp -r "$f" "$LOGDIR/"; then
          echo "error: failed to copy $f to $LOGDIR" >&2
          confirm "Failed to copy $f\nto $LOGDIR\non the USB drive."
          exit 1
      fi
      n=$((n + 1))
  done

  if [ "$n" -eq 0 ]; then
      sync
      echo "error: $SRC is empty - nothing copied (left empty $LOGDIR behind)" >&2
      confirm "Failed to copy logs from $SRC\nto $LOGDIR\non the USB drive."
      exit 1
  fi

  sync
  echo "copied $n entries from $SRC to $LOGDIR"
  confirm "Copied $n entries from $SRC\nto $LOGDIR\non the USB drive."
}

if ask "Would you like to copy running logs to the USB drive\nor change logs rotation size?" "Copy logs" "Change size" "Exit"
then
  copy_logs
elif [ $? -eq 1 ]
then
  if ask "What logs rotation size would you like to set?" "Stock 512KB" "Enlarged 5MB" "Exit"
  then
    change_rotation_size 512
  elif [ $? -eq 1 ]
  then
    change_rotation_size 5120
  fi
fi
exit 0
