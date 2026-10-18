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
cat > /jci/tools/jci-dialog <<'EOF'
#!/bin/sh
case "$*" in *--question*) ;; *) exit 0;; esac
set -- $(cat /tmp/ans)
a=${1:-none}
[ $# -gt 0 ] && shift
echo "$*" > /tmp/ans
[ "$a" = "none" ] && { echo "[dialog] out of answers" >> /tmp/events; exit 1; }
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
run() {
  echo "$1" > /tmp/ans
  : > /tmp/events
  rm -rf /usb/logs
  [ -d /usb/mp3_off ] && [ ! -e /usb/mp3 ] && mv /usb/mp3_off /usb/mp3
  sh "/usb/$SCRIPT" >/dev/null 2>&1 || :
  LOG="/usb/logs/${SCRIPT%.sh}.log"
}

for TARGET in no-more-disclaimer hud-eu-region; do
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
    mkdir -p /usb/mp3 "$(dirname "$APP")"
    cp -r "$REPO/jci-mods" "$REPO/jci-org" /usb/
    cp "$REPO/$SCRIPT" "/usb/$SCRIPT"
    (cd /usb && md5sum "$SCRIPT" > "$SCRIPT.md5")
    cat "$REPO/jci-org/$ORG" > "$APP"
    chmod 755 "$APP"
    echo 'JCI_SW_VER="MAZ_CMU-150_74.00.324"' > /jci/version.ini
  }
  app_is() { is "$APP state" "$(m5 "$APP")" "$1"; }
  case_() { echo "### $TARGET: $*"; }

  case_ "install creates a verified backup, preserves permissions, and reboots"
  reset
  run "0 0"
  app_is "$MOD_MD5"
  is "backup state" "$(m5 "$APP.org")" "$ORG_MD5"
  is "permissions kept" "$(ls -l "$APP" | cut -c1-10)" "-rwxr-xr-x"
  rebooted 1
  [ -d /usb/mp3 ] && is "mp3 restored" yes yes || is "mp3 restored" no yes
  logged "installed."

  case_ "install again reports already installed without rebooting"
  run "0 0"
  app_is "$MOD_MD5"
  rebooted 0
  logged "already installed."
  logged "nothing changed"

  case_ "uninstall restores the original and removes its backup"
  run "0 1"
  app_is "$ORG_MD5"
  [ -e "$APP.org" ] && is "backup removed" yes no || is "backup removed" no no
  rebooted 1
  logged "uninstalled, the original is back."

  case_ "uninstall again leaves the original and does not reboot"
  run "0 1"
  app_is "$ORG_MD5"
  rebooted 0
  logged "not installed"

  case_ "declining the safety question makes no changes"
  reset
  run "1"
  app_is "$ORG_MD5"
  rebooted 0
  logged "exit requested by the user"

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
  run "0 0"
  app_is "$ORG_MD5"
  [ -e "$APP.org" ] && is "backup not created" yes no || is "backup not created" no no
  rebooted 0
  logged "is missing or damaged (md5)"

  case_ "unknown app file is left untouched"
  reset
  echo "// unknown change" >> "$APP"
  UNKNOWN_MD5=$(m5 "$APP")
  run "0 0"
  app_is "$UNKNOWN_MD5"
  [ -e "$APP.org" ] && is "unknown file not backed up" yes no || is "unknown file not backed up" no no
  rebooted 0
  logged "not the known original"

  case_ "unknown backup prevents installation"
  reset
  echo "unknown backup" > "$APP.org"
  run "0 0"
  app_is "$ORG_MD5"
  is "unknown backup preserved" "$(cat "$APP.org")" "unknown backup"
  rebooted 0
  logged "there is an unknown backup"
done

echo
echo "$CHECKS checks, $FAILS failed"
[ "$FAILS" = "0" ]
