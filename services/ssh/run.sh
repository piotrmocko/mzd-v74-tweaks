#!/bin/sh
# SSH Access for Mazda firmware 74.00.324.
# Self-contained worker; maintained directly in this file.
#
# Reading guide:
#   1. Validate the requested action without changing the system.
#   2. Define local reporting, system-state and patch helpers.
#   3. Set this tweak's paths/checksum in the configuration section below.
#   4. Run the installation flow at the end of the file.
# The manifest describes the tweak for discovery; this script executes it.
set -u

# Help and invalid actions return before reports, mounts or system changes.
mzd_worker_usage() {
    echo 'Usage: sh run.sh <install|uninstall|status>'
    echo 'No arguments or --help: show usage without changing anything.'
}

if [ "$#" -gt 1 ]
then
    echo 'Expected exactly one action, or no arguments for usage.' >&2
    mzd_worker_usage >&2
    exit 1
fi
ACTION=${1:-}
case "$ACTION" in
    ''|--help|-h)
        mzd_worker_usage
        exit 0
        ;;
    install|uninstall|status)
        ;;
    *)
        echo 'Unknown action. Use install, uninstall or status.' >&2
        exit 1
        ;;
esac

# All helpers are defined in this script. The copied tweak folder
# needs no launcher, shared lib directory, Python or build tools.
SELF=$(readlink -f "$0") || exit 1
HERE=$(dirname "$SELF")

# --- Local common helpers ---
# Functions using scratch variables run in subshells to isolate caller state.
mzd_hash() (
  md5sum "$1" | cut -d' ' -f1
)

mzd_check_asset() (
  expected=$(cut -c1-32 "$1.md5" 2>/dev/null)
  [ -n "$expected" ] && [ -f "$1" ] && [ ! -L "$1" ] &&
    [ "$(mzd_hash "$1")" = "$expected" ]
)

mzd_require_assets() (
  for asset in "$@"
  do
    mzd_check_asset "$asset" || mzd_fail "Asset checksum mismatch: $asset"
  done
)

mzd_require_tools() (
  for tool in "$@"
  do
    command -v "$tool" >/dev/null 2>&1 || mzd_fail "Missing tool: $tool"
  done
)

# Exact line comparison supported by the CMU's BusyBox awk. Its grep has no -x.
mzd_line_is() (
  awk -v expected="$1" '$0 == expected {found=1} END {exit !found}' "$2"
)

# This check has no target-file or patch dependency.
mzd_validate_firmware() (
  mzd_line_is "JCI_SW_VER=\"MAZ_CMU-150_$1\"" /jci/version.ini ||
    mzd_fail "This tweak requires firmware $1."
)

mzd_report_message() {
  printf '%s\n' "$*"
  printf '%s\n' "$*" >&3
}

# Before begin, errors use stderr only. During an operation they also reach USB.
mzd_fail() {
  if [ -n "${MZD_REPORT:-}" ]
  then
    printf 'ERROR: %s\n' "$*"
    printf 'ERROR: %s\nReports: %s\n' "$*" "$MZD_REPORT" >&4
    : > "$MZD_REPORT/error-reported" 2>/dev/null || :
  else
    printf 'ERROR: %s\n' "$*" >&2
  fi
  exit "${MZD_FAILURE_CODE:-1}"
}

# Persist severity because patch helpers run in subshells.
# Exit 2 means manual intervention is required; never continue or reboot.
mzd_fatal() {
  printf '%s\n' "$*" > "$MZD_REPORT/critical-error" || :
  MZD_FAILURE_CODE=2
  mzd_fail "$@"
}

# Explicit session start: script path, tweak ID, optional cleanup function.
# Only MZD_USB/MZD_REPORT/MZD_CLEANUP are shared session variables.
mzd_begin() {
  MZD_CLEANUP=${3:-}
  MZD_USB=$(dirname "$1")
  while [ "$MZD_USB" != / ] && ! grep -q " $MZD_USB " /proc/mounts
  do
    MZD_USB=$(dirname "$MZD_USB")
  done
  if [ "$MZD_USB" = / ]
  then
    echo 'Cannot identify the startup storage mount.' >&2
    exit 1
  fi
  mount -o rw,remount "$MZD_USB" || exit 1
  MZD_REPORT="$MZD_USB/reports/diffpatch/$2-$(date +%Y%m%d-%H%M%S)-$$"
  mkdir -p "$MZD_REPORT" || exit 1
  : > "$MZD_REPORT/run.log" || exit 1
  exec 3>&1
  exec 4>&2
  exec > "$MZD_REPORT/run.log" 2>&1
  trap mzd_finish 0
  trap 'exit 130' INT
  trap 'exit 143' TERM
}

# Cleanup is an optional worker-supplied function name, never evaluated code.
mzd_finish() {
  MZD_EXIT=$?
  trap - 0
  case "${ACTION:-}:$MZD_EXIT" in
    install:130|install:143|uninstall:130|uninstall:143)
      printf 'ERROR: The operation was interrupted; changes may be incomplete. Do NOT reboot.\nReports: %s\n' "$MZD_REPORT" >&4
      MZD_EXIT=2 ;;
  esac
  if [ -n "$MZD_CLEANUP" ] && ! "$MZD_CLEANUP"
  then
    printf 'ERROR: Cleanup failed; system state could not be fully restored. Do NOT reboot.\nReports: %s\n' "$MZD_REPORT" >&4
    MZD_EXIT=2
  fi
  if [ -f "$MZD_REPORT/critical-error" ]
  then
    MZD_EXIT=2
  fi
  if [ "$MZD_EXIT" != 0 ] && [ ! -f "$MZD_REPORT/error-reported" ]
  then
    printf 'ERROR: Operation failed or was interrupted (exit %s). Check the report before continuing.\nReports: %s\n' "$MZD_EXIT" "$MZD_REPORT" >&4
  fi
  if ! printf 'exit_code=%s\n' "$MZD_EXIT" > "$MZD_REPORT/status.txt"
  then
    printf 'ERROR: Cannot save the final result. Check USB storage.\nReports: %s\n' "$MZD_REPORT" >&4
    [ "$MZD_EXIT" = 0 ] && MZD_EXIT=1
  fi
  sync
  # Never announce success before cleanup and result recording have succeeded.
  if [ "$MZD_EXIT" = 0 ] && [ -n "${MZD_SUCCESS:-}" ]
  then
    mzd_report_message "$MZD_SUCCESS"
  fi
  if [ "$MZD_EXIT" = 0 ] && [ -n "${MZD_STATUS:-}" ]
  then
    printf '%s\n' "$MZD_STATUS" >&3
  fi
  exit "$MZD_EXIT"
}

# --- Local system helpers ---
# Uses the local helpers and an explicit mzd_begin session.


# USB state records allow multiple locks/mounts without shell variable collisions.
mzd_system_begin() {
  MZD_SYSTEM="$MZD_REPORT/system"
  mkdir "$MZD_SYSTEM" || mzd_fail 'Cannot initialize system cleanup state.'
  : > "$MZD_SYSTEM/locks" || mzd_fail 'Cannot initialize locks.'
  : > "$MZD_SYSTEM/mounts" || mzd_fail 'Cannot initialize mounts.'
}

# Reject multiline record entries. Paths are data, never shell commands.
mzd_system_path() (
  case "$1" in
    /*) ;;
    *) mzd_fail 'An absolute system path is required.' ;;
  esac
  case "$1" in
    *'
'*) mzd_fail 'Multiline system paths are unsupported.' ;;
  esac
)

mzd_system_lock() (
  mzd_system_path "$1" || exit 1
  if mzd_line_is "$1" "$MZD_SYSTEM/locks"
  then
    return 0
  fi
  mkdir "$1" || mzd_fail 'Another tweak for this file is running. Restart the CMU if a previous run was interrupted.'
  if ! printf '%s\n' "$1" >> "$MZD_SYSTEM/locks"
  then
    rmdir "$1"
    mzd_fail 'Cannot record the owned lock.'
  fi
)

# Disabling the watchdog is explicit, separate from a mount or file operation.
mzd_system_watchdog_disable() (
  value=$(cat /sys/class/gpio/Watchdog\ Disable/value) || mzd_fail 'Cannot read watchdog state.'
  case "$value" in
    0)
      # Record before changing so cleanup also handles a caught interruption.
      : > "$MZD_SYSTEM/watchdog" || mzd_fail 'Cannot record watchdog state.'
      echo 1 > /sys/class/gpio/Watchdog\ Disable/value || mzd_fail 'Cannot disable watchdog.'
      ;;
    1) ;;
    *) mzd_fail 'Unknown watchdog state.' ;;
  esac
)

# Accept any explicit mount point, not only root or resources.
mzd_system_remount_rw() (
  mzd_system_path "$1" || exit 1
  mode=$(awk -v path="$1" '$2==path && $3!="rootfs" {print $4; exit}' /proc/mounts)
  case ",$mode," in
    *,rw,*) return 0 ;;
    *,ro,*) ;;
    *) mzd_fail "Unknown mount state: $1" ;;
  esac
  if ! mzd_line_is "$1" "$MZD_SYSTEM/mounts"
  then
    printf '%s\n' "$1" >> "$MZD_SYSTEM/mounts" || mzd_fail 'Cannot record mount state.'
  fi
  mount -o rw,remount "$1" || mzd_fail "Cannot remount $1 read-write."
)

# Restore only recorded changes; never remove somebody else's lock.
mzd_system_cleanup() (
  [ -n "${MZD_SYSTEM:-}" ] && [ -d "$MZD_SYSTEM" ] || exit 0
  result=0
  if [ -f "$MZD_SYSTEM/mounts" ]
  then
    # Restore nested mounts before their parents.
    awk '{line[NR]=$0} END {for (i=NR;i>0;i--) print line[i]}' "$MZD_SYSTEM/mounts" > "$MZD_SYSTEM/restore-mounts" || result=1
    while IFS= read -r path
    do
      mount -o ro,remount "$path" || result=1
    done < "$MZD_SYSTEM/restore-mounts"
  fi
  if [ -f "$MZD_SYSTEM/watchdog" ]
  then
    echo 0 > /sys/class/gpio/Watchdog\ Disable/value || result=1
  fi
  if [ -f "$MZD_SYSTEM/locks" ]
  then
    while IFS= read -r path
    do
      rmdir "$path" || result=1
    done < "$MZD_SYSTEM/locks"
  fi
  exit "$result"
)

# --- Local patch helpers ---
# Every operation takes explicit paths/context; no APP/PATCH_FILE/STATE globals.
# The worker owns locks, writable mounts and multi-file orchestration.


# Native BusyBox has no dry-run. Probe a copy and require an exact inverse.
mzd_patch_probe() (
  context=$1
  direction=$2
  patch_file=$3
  work="$context/$direction"
  mkdir -p "$work/inverse" || exit 1
  cp "$context/before.data" "$work/target.data" || exit 1
  if [ "$direction" = install ]
  then
    (cd "$work" && patch -N -p0 -i "$patch_file" < /dev/null) > "$work/patch.log" 2>&1 || exit 1
    inverse=-R
  else
    (cd "$work" && patch -N -R -p0 -i "$patch_file" < /dev/null) > "$work/patch.log" 2>&1 || exit 1
    inverse=
  fi
  cmp -s "$context/before.data" "$work/target.data" && exit 1
  cp "$work/target.data" "$work/inverse/target.data" || exit 1
  # inverse is either the fixed -R flag or empty; never caller-provided code.
  (cd "$work/inverse" && patch -N $inverse -p0 -i "$patch_file" < /dev/null) > "$work/inverse.log" 2>&1 || exit 1
  cmp -s "$context/before.data" "$work/inverse/target.data"
)

# Prepare a unique USB context: target, patch, known OEM hash, context directory.
# No target writes or mount changes happen here. Call while holding its lock.
mzd_patch_prepare() (
  target=$1
  patch_file=$2
  original=$3
  context=$4
  mzd_require_tools patch diff cp cmp md5sum || exit 1
  mzd_require_assets "$patch_file" || exit 1
  if [ ! -f "$target" ] || [ -L "$target" ]
  then
    mzd_fail 'Target is missing or is a symbolic link.'
  fi
  case "$target:$patch_file:$context" in
    *'
'*) mzd_fail 'Multiline patch paths are unsupported.' ;;
  esac
  case "$target:$patch_file:$context" in
    /*:/*:/*) ;;
    *) mzd_fail 'Absolute patch paths are required.' ;;
  esac
  case "$original" in
    ''|*[!0-9a-f]*) mzd_fail 'Invalid OEM checksum.' ;;
  esac
  [ "${#original}" = 32 ] || mzd_fail 'Invalid OEM checksum.'
  # CMU readlink -f requires the path to exist. Resolve the existing parent
  # first, then validate the new leaf before creating the unique context.
  parent=$(readlink -f "$(dirname "$context")") || mzd_fail 'Cannot resolve patch context parent.'
  case "$parent" in
    "$MZD_REPORT"|"$MZD_REPORT"/*) ;;
    *) mzd_fail 'Patch contexts must stay in the startup USB report.' ;;
  esac
  leaf=${context##*/}
  case "$leaf" in ''|.|..) mzd_fail 'Invalid patch context leaf.' ;; esac
  context="$parent/$leaf"
  mkdir "$context" || mzd_fail 'Cannot create a unique patch context.'
  printf '%s\n' "$target" > "$context/target.path" || exit 1
  printf '%s\n' "$original" > "$context/original.md5" || exit 1
  cp "$target" "$context/before.data" || mzd_fail 'Cannot save the USB rollback copy.'
  before=$(mzd_hash "$target")
  [ "$(mzd_hash "$context/before.data")" = "$before" ] || mzd_fail 'USB rollback copy mismatch.'
  printf '%s\n' "$before" > "$context/before.md5" || exit 1
  forward=0
  reverse=0
  mzd_patch_probe "$context" install "$patch_file" && forward=1
  mzd_patch_probe "$context" uninstall "$patch_file" && reverse=1
  case "$forward:$reverse" in
    1:0) state=uninstalled; direction=install ;;
    0:1) state=installed; direction=uninstall ;;
    *) mzd_fail 'Patch state is unknown, partial or ambiguous. No system file changed.' ;;
  esac
  mzd_hash "$context/$direction/target.data" > "$context/desired.md5" || exit 1
  printf '%s\n' "$state" > "$context/state" || exit 1
)

mzd_patch_state() (
  cat "$1/state"
)

mzd_patch_validate_backup() (
  context=$1
  target=$(cat "$context/target.path") || exit 1
  original=$(cat "$context/original.md5") || exit 1
  before=$(cat "$context/before.md5") || exit 1
  backup="$target.org"
  if [ -e "$backup" ] || [ -L "$backup" ]
  then
    if [ ! -f "$backup" ] || [ -L "$backup" ] || [ "$(mzd_hash "$backup")" != "$original" ]
    then
      mzd_fail 'The .org backup is not the known OEM original.'
    fi
  elif [ "$before" != "$original" ]
  then
    mzd_fail 'The shared OEM .org backup is missing. Nothing changed.'
  fi
)

# Write one prepared target. Worker must make the appropriate mount writable.
# A failure restores that target's complete previous contents, including other tweaks.
mzd_patch_apply() (
  context=$1
  action=$2
  state=$(mzd_patch_state "$context") || exit 1
  case "$action:$state" in
    install:installed|uninstall:uninstalled) exit 0 ;;
    install:uninstalled|uninstall:installed) ;;
    *) mzd_fail 'Invalid patch action or context state.' ;;
  esac
  mzd_patch_validate_backup "$context" || exit 1
  target=$(cat "$context/target.path") || exit 1
  original=$(cat "$context/original.md5") || exit 1
  before=$(cat "$context/before.md5") || exit 1
  desired=$(cat "$context/desired.md5") || exit 1
  [ "$(mzd_hash "$context/before.data")" = "$before" ] || mzd_fail 'Rollback copy changed.'
  prepared="$context/$action/target.data"
  [ "$(mzd_hash "$prepared")" = "$desired" ] || mzd_fail 'Prepared patch copy changed.'
  [ "$(mzd_hash "$target")" = "$before" ] || mzd_fail 'Target changed while preparing the tweak.'
  diff -U 3 "$context/before.data" "$prepared" > "$context/changes.diff"
  [ "$?" = 1 ] || mzd_fail 'Cannot record the prepared change.'
  backup="$target.org"
  if [ ! -e "$backup" ]
  then
    cp -a "$target" "$backup" && sync
    if [ "$(mzd_hash "$backup")" != "$original" ]
    then
      rm -f "$backup"
      mzd_fail 'Original backup failed.'
    fi
  fi
  cat "$prepared" > "$target"
  sync
  if [ "$(mzd_hash "$target")" != "$desired" ]
  then
    cat "$prepared" > "$target"
    sync
  fi
  if [ "$(mzd_hash "$target")" != "$desired" ]
  then
    cat "$context/before.data" > "$target"
    sync
    [ "$(mzd_hash "$target")" = "$before" ] || mzd_fatal 'Write AND rollback failed. Do NOT reboot the CMU.'
    mzd_fail 'Write failed; the complete previous file was restored.'
  fi
)

# Explicit rollback for a later worker-specific failure, e.g. SSH activation.
# Refuse to overwrite an intervening change or an unrelated prepared target.
mzd_patch_rollback() (
  context=$1
  target=$(cat "$context/target.path") || mzd_fatal 'Cannot read rollback target path. Do NOT reboot.'
  before=$(cat "$context/before.md5") || mzd_fatal 'Cannot read rollback original checksum. Do NOT reboot.'
  desired=$(cat "$context/desired.md5") || mzd_fatal 'Cannot read rollback prepared checksum. Do NOT reboot.'
  current=$(mzd_hash "$target")
  [ "$current" = "$before" ] && exit 0
  [ "$current" = "$desired" ] || mzd_fatal 'Rollback target changed. Do NOT reboot.'
  [ "$(mzd_hash "$context/before.data")" = "$before" ] || mzd_fatal 'Rollback copy changed. Do NOT reboot.'
  cat "$context/before.data" > "$target"
  sync
  [ "$(mzd_hash "$target")" = "$before" ] || mzd_fatal 'Rollback failed. Do NOT reboot.'
)

# --- Tweak configuration --------------------------------------------------
# Maintain these values together with manifest.json; offline tests check them.
# ORIGINAL identifies the unmodified OEM file, not a file with other tweaks.
# Tweaks editing the same file share LOCK to avoid simultaneous writes.
# JSON is not executed or parsed on the CMU.
ID=ssh
FIRMWARE=74.00.324
APP=/jci/scripts/stage_wifi.sh
ORIGINAL=d740449dea568696660a62fce0fb35bd
LOCK=/tmp/mzd-stage_wifi-tweak.lock
PATCH_FILE="$HERE/change.patch"

# --- SSH payload preparation ------------------------------------------------
# SSH owns a resources directory in addition to its patched startup hook.
# Keep service provisioning separate from the generic file-patching workflow.
SERVICE=/tmp/mnt/resources/mzd-v74-tweaks/ssh
PAYLOAD="$HERE"

resources_rw() {
    mzd_system_remount_rw /tmp/mnt/resources || exit 1
}

# Never replace an unknown service payload, even if the boot hook looks known.
ssh_payload_ok() {
    if [ ! -d "$SERVICE" ] || [ -L "$SERVICE" ]
    then
        return 1
    fi
    for _file in service.sh sshd_config password.hash
    do
        if [ -L "$SERVICE/$_file" ] || ! cmp -s "$PAYLOAD/$_file" "$SERVICE/$_file"
        then
            return 1
        fi
    done
}

ssh_prepare() {
    for _file in service.sh sshd_config password.hash usb-log-marker.txt
    do
        mzd_check_asset "$PAYLOAD/$_file" || mzd_fail 'SSH asset checksum mismatch.'
    done

    if [ -e "$SERVICE" ]
    then
        ssh_payload_ok || mzd_fail 'Existing SSH service files differ. Nothing overwritten.'
    elif [ "$STATE" = installed ]
    then
        mzd_fail 'The SSH boot hook is installed but the service payload is missing.'
    fi

    if [ "$ACTION" != install ]
    then
        return 0
    fi

    # Check account layout, executable/config compatibility and port ownership
    # before copying anything into resources or changing the startup hook.
    _check=$PAYLOAD
    if [ -d "$SERVICE" ]
    then
        _check=$SERVICE
    fi
    sh "$_check/service.sh" check || mzd_fail 'SSH prerequisites failed; an unrelated port 22 listener is never replaced.'

    if [ ! -e "$SERVICE" ]
    then
        resources_rw
        mkdir -p "$(dirname "$SERVICE")" || mzd_fail 'Cannot create SSH parent directory.'
        _stage="$SERVICE.new-$$"
        mkdir "$_stage" || mzd_fail 'Cannot prepare SSH service directory.'

        # Publish a directory only after all three payload files are verified.
        for _file in service.sh sshd_config password.hash
        do
            if ! cp "$PAYLOAD/$_file" "$_stage/$_file" || ! cmp -s "$PAYLOAD/$_file" "$_stage/$_file"
            then
                rm -f "$_stage/service.sh" "$_stage/sshd_config" "$_stage/password.hash"
                rmdir "$_stage"
                mzd_fail 'Cannot copy and verify SSH service payload.'
            fi
        done
        if ! chmod 700 "$_stage/service.sh" ||
            ! chmod 600 "$_stage/sshd_config" "$_stage/password.hash"
        then
            mzd_fail 'Cannot set SSH payload permissions.'
        fi
        sync
        mv "$_stage" "$SERVICE" || mzd_fail 'Cannot publish SSH service directory.'
    fi

    cp "$PAYLOAD/usb-log-marker.txt" "$USB/diffpatch-ssh-log-marker.txt" || mzd_fail 'Cannot save USB runtime-log marker.'
}


# --- SSH activation, selective removal and startup rollback ------------------
ssh_rollback_hook() {
    if [ "$NO_CHANGE" = 0 ]
    then
        mzd_patch_rollback "$CONTEXT" || exit $?
    fi
}

ssh_complete() {
    if [ "$ACTION" = install ]
    then
        resources_rw
        if ! printf 'enabled\n' > "$SERVICE/enabled"
        then
            rm -f "$SERVICE/enabled"
            ssh_rollback_hook || exit $?
            mzd_fail 'Cannot enable the SSH service. The new boot hook was reverted.'
        fi
        sync

        # Close both caller streams in the detached supervisor. It handles its
        # own USB runtime logs and does not require WLAN to have an address yet.
        sh "$SERVICE/service.sh" boot "$USB" >/dev/null 2>&1 3>&- 4>&- &
        sleep 2
        if ! sh "$SERVICE/service.sh" status
        then
            rm -f "$SERVICE/enabled"
            sh "$SERVICE/service.sh" stop || mzd_fatal 'SSH startup and service cleanup failed. Do NOT reboot.'
            ssh_rollback_hook || exit $?
            mzd_fail 'SSH did not start. The new boot hook and runtime changes were reverted.'
        fi
        printf 'SSH: port 22, user cmu, password jci.\n' >&3

    elif [ -d "$SERVICE" ]
    then
        # The generic inverse patch has already removed the startup hook.
        # Stop the owned service before removing only its verified payload.
        resources_rw
        rm -f "$SERVICE/enabled"
        sync
        sh "$SERVICE/service.sh" stop || mzd_fatal 'Boot hook removed; service cleanup failed. Do NOT reboot.'
        for _file in service.sh sshd_config password.hash
        do
            rm -f "$SERVICE/$_file"
        done
        rmdir "$SERVICE" || mzd_fail 'SSH stopped; service directory is not empty.'
        printf 'Managed SSH service, password overlay and firewall access removed.\n' >&3
    fi
}

# --- Execution flow -------------------------------------------------------
# Open USB reports and register cleanup before acquiring a lock. Cleanup restores
# only the mount/watchdog state changed by this invocation, including on failure.
mzd_begin "$SELF" "$ID" mzd_system_cleanup
mzd_system_begin
mzd_require_tools awk md5sum cp cmp || exit 1
mzd_require_assets "$SELF" "$HERE/manifest.json" || exit 1
mzd_validate_firmware "$FIRMWARE" || exit 1
mzd_system_lock "$LOCK" || exit 1

# Probe both patch directions on USB copies before making the target writable.
# Keep a complete pre-change copy so rollback preserves other installed tweaks.
CONTEXT="$MZD_REPORT/target"
mzd_patch_prepare "$APP" "$PATCH_FILE" "$ORIGINAL" "$CONTEXT" || exit 1
STATE=$(mzd_patch_state "$CONTEXT") || exit 1
if [ "$ACTION" = status ]
then
    # Installed means a complete persistent installation, not merely its hook.
    # A stopped runtime service does not by itself mean it is uninstalled.
    if [ "$STATE" = installed ]
    then
        ssh_prepare || exit $?
        [ -f "$SERVICE/enabled" ] && [ ! -L "$SERVICE/enabled" ] &&
            mzd_line_is enabled "$SERVICE/enabled" ||
            mzd_fail 'SSH hook is installed but its enabled marker is missing or invalid.'
    elif [ -e "$SERVICE/enabled" ] || [ -L "$SERVICE/enabled" ]
    then
        mzd_fail 'SSH payload is enabled but its startup hook is missing.'
    fi
    MZD_STATUS=$STATE
    exit 0
fi

# Repeated install/uninstall is a successful no-op for the patch itself.
NO_CHANGE=0
case "$ACTION:$STATE" in
    install:installed|uninstall:uninstalled) NO_CHANGE=1 ;;
esac
if [ "$NO_CHANGE" = 0 ]
then
    mzd_patch_validate_backup "$CONTEXT" || exit 1
fi

# Prepare/validate the SSH payload before changing the boot hook. Activate the
# service afterwards; activation failure rolls the newly added hook back.
USB=$MZD_USB
REPORT=$MZD_REPORT
mzd_report_message "$ACTION in progress. Do not remove the USB drive."
ssh_prepare || exit $?
if [ "$NO_CHANGE" = 0 ]
then
    mzd_system_watchdog_disable || exit 1
    mzd_system_remount_rw / || exit 1
    mzd_patch_apply "$CONTEXT" "$ACTION" || exit $?
fi
ssh_complete || exit $?

# Report completion; the launcher owns dialogs and any reboot decision.
if [ "$NO_CHANGE" = 1 ]
then
    MZD_SUCCESS="Requested setting is already present.
Reports: $MZD_REPORT"
else
    MZD_SUCCESS="$ACTION completed. Other changes were preserved.
Reports: $MZD_REPORT"
fi
