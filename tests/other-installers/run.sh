#!/bin/sh
# Simulates no-more-disclaimer.sh and hud-eu-region.sh in BusyBox, as on the head unit.
#
#   docker run --rm --tmpfs /usb -v "$PWD:/repo:ro" busybox:1.36 sh /repo/tests/other-installers/run.sh
#
# /usb must be a mount point: each installer finds the USB drive in /proc/mounts.
set -u
REPO=${1:-/repo}
FAILS=0
CHECKS=0
if ! grep -q " /usb " /proc/mounts; then
  echo "ERROR: /usb is not a mount point (docker run --tmpfs /usb ...)"
  exit 2
fi

mkdir -p /stub /jci/tools /tmp
for c in hwclock mount sleep; do
  printf '#!/bin/sh\necho "[stub] %s $*" >> /tmp/events\n' "$c" > "/stub/$c"
done
printf '#!/bin/sh\necho "[stub] reboot" >> /tmp/events\n' > /stub/reboot
# jci-dialog: answers --question and --3-button-dialog from /tmp/ans (one number per
# question: 0 = first button, 1 = second, 2 = third). --info dialogs return 0. Out of
# answers: the last button (Exit/Reboot later), so a test never installs by accident.
cat > /jci/tools/jci-dialog <<'EOF'
#!/bin/sh
case "$*" in
  *--3-button-dialog*) last=2;;
  *--question*) last=1;;
  *) exit 0;;
esac
set -- $(cat /tmp/ans)
a=${1:-none}
[ $# -gt 0 ] && shift
echo "$*" > /tmp/ans
[ "$a" = "none" ] && { echo "[dialog] out of answers" >> /tmp/events; exit "$last"; }
exit "$a"
EOF
chmod +x /stub/* /jci/tools/jci-dialog
PATH=/stub:$PATH
export PATH

m5() { md5sum "$1" 2>/dev/null | cut -c1-32; }
is() {
  if [ "$2" = "$3" ]; then
    CHECKS=$((CHECKS + 1))
  else
    CHECKS=$((CHECKS + 1))
    FAILS=$((FAILS + 1))
    echo "    FAIL: $1: expected '$3', got '$2'"
  fi
}
logged() {
  if grep -q "$1" "$LOG"; then
    CHECKS=$((CHECKS + 1))
  else
    CHECKS=$((CHECKS + 1))
    FAILS=$((FAILS + 1))
    echo "    FAIL: log should contain: $1"
  fi
}
rebooted() { is "reboot count" "$(grep -c 'stub\] reboot' /tmp/events)" "$1"; }
answers_used() {
  is "unused answers" "$(cat /tmp/ans)" ""
  is "out of answers" "$(grep -c 'out of answers' /tmp/events)" "0"
}
mp3_kept() {
  [ -d /usb/mp3 ] && [ ! -e /usb/mp3_off ] && is "mp3 folder untouched" yes yes || is "mp3 folder untouched" no yes
}
run() {
  echo "$1" > /tmp/ans
  : > /tmp/events
  rm -rf /usb/logs
  sh "/usb/$SCRIPT" >/dev/null 2>&1 || :
  LOG="/usb/logs/${SCRIPT%.sh}.log"
}

for TARGET in no-more-disclaimer; do
  case "$TARGET" in
    no-more-disclaimer)
      SCRIPT=no-more-disclaimer.sh
      APP=/jci/gui/apps/system/js/systemApp.js
      ORG=systemApp.js.org
      MOD=systemApp.js
      ;;
    hud-eu-region)
      SCRIPT=hud-eu-region.sh
      APP=/jci/gui/apps/vehsettings/js/vehsettingsApp.js
      ORG=vehsettingsApp.js.org
      MOD=vehsettingsApp.js
      ;;
  esac
  ORG_MD5=$(m5 "$REPO/jci-org/$ORG")
  MOD_MD5=$(m5 "$REPO/jci-mods/$MOD")

  reset() {
    rm -rf /usb/* "$APP" "$APP.org"
    mkdir -p /usb/mp3 "$(dirname "$APP")"   # the installer must leave mp3/ alone
    cp -r "$REPO/jci-mods" "$REPO/jci-org" /usb/
    cp "$REPO/$SCRIPT" "/usb/$SCRIPT"
    (cd /usb && md5sum "$SCRIPT" > "$SCRIPT.md5")
    cat "$REPO/jci-org/$ORG" > "$APP"
    chmod 755 "$APP"
    echo 'JCI_SW_VER="MAZ_CMU-150_74.00.324"' > /jci/version.ini
  }
  app_is() { is "$APP state" "$(m5 "$APP")" "$1"; }
  case_() { echo "### $TARGET: $*"; }

  # Answers, in order: Install/Uninstall/Exit (0/1/2); then Reboot now/Reboot later (0/1),
  # only if something was changed.
  case_ "install creates a verified backup, preserves permissions, and reboots"
  reset
  run "0 0"
  app_is "$MOD_MD5"
  is "backup state" "$(m5 "$APP.org")" "$ORG_MD5"
  is "permissions kept" "$(ls -l "$APP" | cut -c1-10)" "-rwxr-xr-x"
  rebooted 1
  answers_used
  mp3_kept
  logged "installed."

  case_ "install again reports already installed, no reboot question"
  run "0"
  app_is "$MOD_MD5"
  rebooted 0
  answers_used
  logged "already installed."

  case_ "uninstall restores the original and removes its backup"
  run "1 0"
  app_is "$ORG_MD5"
  [ -e "$APP.org" ] && is "backup removed" yes no || is "backup removed" no no
  rebooted 1
  answers_used
  logged "uninstalled, the original is back."

  case_ "uninstall again leaves the original, no reboot question"
  run "1"
  app_is "$ORG_MD5"
  rebooted 0
  answers_used
  logged "not installed"

  case_ "install, reboot later: installed, no reboot"
  reset
  run "0 1"
  app_is "$MOD_MD5"
  rebooted 0
  answers_used

  case_ "Exit in the install/uninstall dialog makes no changes"
  reset
  run "2"
  app_is "$ORG_MD5"
  [ -e "$APP.org" ] && is "no backup" yes no || is "no backup" no no
  rebooted 0
  answers_used
  logged "Exit requested by the user"

  case_ "the dialog gives no answer: no changes"
  reset
  run ""
  app_is "$ORG_MD5"
  rebooted 0
  logged "Exit requested by the user"

  case_ "damaged installer is rejected"
  reset
  echo "#" >> "/usb/$SCRIPT"
  run ""
  app_is "$ORG_MD5"
  rebooted 0
  logged "ERROR: md5 of $SCRIPT"

  case_ "unsupported firmware is rejected"
  reset
  echo 'JCI_SW_VER="MAZ_CMU-150_70.00.100"' > /jci/version.ini
  run ""
  app_is "$ORG_MD5"
  rebooted 0
  logged "CMU version: 70.00.100"

  case_ "damaged mod is rejected without changing the app"
  reset
  echo x >> "/usb/jci-mods/$MOD"
  run "0"
  app_is "$ORG_MD5"
  [ -e "$APP.org" ] && is "backup not created" yes no || is "backup not created" no no
  rebooted 0
  answers_used
  logged "is missing or damaged (md5)"

  case_ "unknown app file is left untouched"
  reset
  echo "// unknown change" >> "$APP"
  UNKNOWN_MD5=$(m5 "$APP")
  run "0"
  app_is "$UNKNOWN_MD5"
  [ -e "$APP.org" ] && is "unknown file not backed up" yes no || is "unknown file not backed up" no no
  rebooted 0
  answers_used
  logged "not the known original"

  case_ "unknown backup prevents installation"
  reset
  echo "unknown backup" > "$APP.org"
  run "0"
  app_is "$ORG_MD5"
  is "unknown backup preserved" "$(cat "$APP.org")" "unknown backup"
  rebooted 0
  answers_used
  logged "there is an unknown backup"
done

echo
echo "$CHECKS checks, $FAILS failed"
[ "$FAILS" = "0" ]
