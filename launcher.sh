#!/bin/sh

MENU_TITLE="MZD Scripts Launcher"

SELF=$(readlink -f "$0")
SELF_NAME=$(basename "$SELF")
SCRIPT_DIR=$(dirname "$SELF")

md5_of() { md5sum "$1" 2>/dev/null | cut -d' ' -f1; }
md5_from() { cut -c1-32 "$1" 2>/dev/null; }

dialog_kill() { killall -q jci-dialog; }

confirm() {
  dialog_kill
  /jci/tools/jci-dialog --info --title="$TITLE" --text="$1" --no-cancel
}

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

run_script() {
  script_path=$1
  script_title=$2

  if ask "Would you like to run:\n$script_title?" "Open" "Next" "Exit"
  then
    sh "$script_path"
    return 2
  elif [ $? -eq 1 ]
  then
    return 0
  else
    return 1
  fi
}

run_known_script() {
  script_name=$1
  script_title=$2
  script_path="$SCRIPT_DIR/$script_name"

  [ -f "$script_path" ] || return 0
  run_script "$script_path" "$script_title"
}

handle_script_result() {
  script_status=$1

  case "$script_status" in
    0) return 0 ;;
    1) exit 0 ;;
    *) return 2 ;;
  esac
}

is_known_script() {
  [ "$1" = "$SELF_NAME" ] && return 0

  case "$1" in
    android-auto.sh|touchscreen.sh|no-more-disclaimer.sh|hud-eu-region.sh|\
    fuel-consumption.sh|logs-collector.sh|backup-jci.sh|revert-aio.sh)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
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


while :; do
  run_known_script "android-auto.sh" "Android Auto Mods"
  handle_script_result "$?"
  [ "$?" -eq 2 ] && continue

  run_known_script "touchscreen.sh" "Touchscreen Enabled Tweak"
  handle_script_result "$?"
  [ "$?" -eq 2 ] && continue

  run_known_script "no-more-disclaimer.sh" "No More Disclaimer Tweak"
  handle_script_result "$?"
  [ "$?" -eq 2 ] && continue

  run_known_script "hud-eu-region.sh" "HUD Street Info in Europe Region Tweak"
  handle_script_result "$?"
  [ "$?" -eq 2 ] && continue

  run_known_script "fuel-consumption.sh" "Fuel Consumption Tweaks"
  handle_script_result "$?"
  [ "$?" -eq 2 ] && continue

  run_known_script "logs-collector.sh" "Running Logs Collector"
  handle_script_result "$?"
  [ "$?" -eq 2 ] && continue

  if ask "Would you like to open Terminal?" "Open" "Next" "Exit"
  then
    confirm "Terminal is not available yet." # TODO: implement terminal
  elif [ $? -eq 2 ]
    exit 0
  fi

  if ask "Would you like to open built-in MZD Scripts?" "Open" "Next" "Exit"
  then
    confirm "Built-in MZD Scripts are not available yet." # TODO: implement built-in scripts
  elif [ $? -eq 2 ]
    exit 0
  fi

  if ask "Would you like to reboot?" "Reboot" "Next" "Exit"
  then
    reboot
  elif [ $? -eq 2 ]
    exit 0
  fi

  run_known_script "backup-jci.sh" "Backup JCI"
  handle_script_result "$?"
  [ "$?" -eq 2 ] && continue

  run_known_script "revert-aio.sh" "Revert AIO Tweaks"
  handle_script_result "$?"
  [ "$?" -eq 2 ] && continue

  # Run any additional scripts found in the same directory that are not known scripts
  for extra_path in "$SCRIPT_DIR"/*.sh; do
    [ -f "$extra_path" ] || continue
    extra_name=${extra_path##*/}
    is_known_script "$extra_name" && continue
    extra_title=${extra_name%.sh}

    run_script "$extra_path" "$extra_title"
    handle_script_result "$?"
    [ "$?" -eq 2 ] && continue 2
  done

  if ! ask "Would you like to start over?" "Start over" "Exit"
  then
    exit 0
  fi
done
