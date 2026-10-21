#!/bin/sh
# Simulates fuel-consumption.sh in busybox (the head unit's shell and tools) and checks
# the result of every case. No Mazda binaries: the JS originals come from jci-org/, the
# sm.conf files are the stand-ins next to this script, and the two MMUI libraries the
# installer checks are dummy files (the md5s in the test copy of the installer are
# replaced with theirs).
#
#   docker run --rm --tmpfs /usb -v "$PWD:/repo:ro" busybox:1.36 sh /repo/tests/fuel-consumption/installer/run.sh
#
# /usb must be a mount point (the USB drive): the installer finds the drive in /proc/mounts.
#
# Exit code: 0 if every check passed.
set -u
REPO=${1:-/repo}
T=$(dirname "$(readlink -f "$0")")
FAILS=0
CHECKS=0
if ! grep -q " /usb " /proc/mounts; then
  echo "ERROR: /usb is not a mount point (docker run --tmpfs /usb ...)"; exit 2
fi

# --- fake head unit -----------------------------------------------------------
ECO=/jci/gui/apps/ecoenergy/js/ecoenergyApp.js
FCC=/jci/gui/apps/ecoenergy/controls/FuelConsumption/js/FuelConsumptionCtrl.js
SO=/data_persist/fuel-ending/fuel_ending_mmui.so
mkdir -p /stub /jci/tools /jci/sm /jci/mmui/uia /jci/lib /data_persist /tmp \
  "$(dirname "$ECO")" "$(dirname "$FCC")"

for c in hwclock mount; do printf '#!/bin/sh\necho "[stub] %s $*" >> /tmp/events\n' "$c" > /stub/$c; done
printf '#!/bin/sh\necho "[stub] reboot" >> /tmp/events\n' > /stub/reboot
# sed/cp wrappers to inject failures: FAIL_SED=1 -> the LD_PRELOAD line is not added to
# sm_WCP.conf; FAIL_RESTORE=1 -> restoring from *.fuelend-orig fails.
cat > /stub/sed <<'EOF'
#!/bin/sh
if [ "${FAIL_SED:-0}" = "1" ]; then
  case "$*" in *jciMMUI*sm_WCP.conf) exit 0;; esac
fi
exec /bin/sed "$@"
EOF
cat > /stub/cp <<'EOF'
#!/bin/sh
if [ "${FAIL_RESTORE:-0}" = "1" ]; then
  case "$*" in *.fuelend-orig\ /jci/sm/*) exit 1;; esac
fi
exec /bin/cp "$@"
EOF
# jci-dialog: answers --question and --3-button-dialog from /tmp/ans (one number per
# question: 0 = first button, 1 = second, 2 = third). --info dialogs return 0. Out of
# answers: the last button (Skip/Exit/Reboot later), so a test never installs by accident.
cat > /jci/tools/jci-dialog <<'EOF'
#!/bin/sh
case "$*" in
  *--3-button-dialog*) last=2;;
  *--question*) last=1;;
  *) exit 0;;
esac
set -- $(cat /tmp/ans)
a=${1:-none}; [ $# -gt 0 ] && shift; echo "$*" > /tmp/ans
[ "$a" = "none" ] && { echo "[dialog] out of answers" >> /tmp/events; exit "$last"; }
exit "$a"
EOF
chmod +x /stub/* /jci/tools/jci-dialog
export PATH=/stub:$PATH

m5() { md5sum "$1" 2>/dev/null | cut -c1-32; }
ORG_ECO=$(m5 "$REPO/jci-org/ecoenergyApp.js.org")
ORG_FCC=$(m5 "$REPO/jci-org/FuelConsumptionCtrl.js.org")
MOD_ECO=$(m5 "$REPO/jci-mods/ecoenergyApp.js")
MOD_FCC=$(m5 "$REPO/jci-mods/FuelConsumptionCtrl.js")
MOD_SO=$(m5 "$REPO/jci-shims/fuel_ending_mmui.so")
SM=$(m5 "$T/sm.conf")
WCP=$(m5 "$T/sm_WCP.conf")

reset() {
  rm -rf /usb/* /data_persist/fuel-ending /jci/sm/* "$ECO".org "$FCC".org
  mkdir -p /usb/mp3   # the installer must leave it alone
  cp -r "$REPO/jci-mods" "$REPO/jci-org" "$REPO/jci-shims" /usb/
  cat "$REPO/jci-org/ecoenergyApp.js.org" > "$ECO"
  cat "$REPO/jci-org/FuelConsumptionCtrl.js.org" > "$FCC"
  chmod 755 "$ECO" "$FCC"
  cp "$T/sm.conf" "$T/sm_WCP.conf" /jci/sm/
  echo "stand-in libjciuiaecoenergy.so" > /jci/mmui/uia/libjciuiaecoenergy.so
  echo "stand-in svcjcimmui.so" > /jci/mmui/svcjcimmui.so
  echo "stand-in libjcieem_client.so" > /jci/lib/libjcieem_client.so
  echo 'JCI_SW_VER="MAZ_CMU-150_74.00.324"' > /jci/version.ini
  # test copy of the installer: md5s of the dummy MMUI libraries
  sed -e "s/^ECO_MD5=.*/ECO_MD5=$(m5 /jci/mmui/uia/libjciuiaecoenergy.so)/" \
      -e "s/^MMUI_MD5=.*/MMUI_MD5=$(m5 /jci/mmui/svcjcimmui.so)/" \
      "$REPO/fuel-consumption.sh" > /usb/fuel-consumption.sh
  (cd /usb && md5sum fuel-consumption.sh > fuel-consumption.sh.md5)
  unset FAIL_SED FAIL_RESTORE
}

# run "<answers>"; keeps the USB drive as it is between runs, like a real re-run
run() {
  echo "$1" > /tmp/ans
  : > /tmp/events
  rm -rf /usb/logs
  sh /usb/fuel-consumption.sh
  LOG=/usb/logs/fuel-consumption.log
}

ok()   { CHECKS=$((CHECKS + 1)); }
fail() { CHECKS=$((CHECKS + 1)); FAILS=$((FAILS + 1)); echo "    FAIL: $*"; }
is()   { [ "$2" = "$3" ] && ok || fail "$1: expected '$3', got '$2'"; }
logged()     { grep -q "$1" "$LOG" && ok || fail "log should contain: $1"; }
not_logged() { grep -q "$1" "$LOG" && fail "log should not contain: $1" || ok; }
rebooted()   { is "reboot" "$(grep -c 'stub\] reboot' /tmp/events)" "$1"; }
mp3_kept()   { [ -d /usb/mp3 ] && [ ! -e /usb/mp3_off ] && ok || fail "the mp3 folder must not be touched"; }
not_in_events() { grep -q "$1" /tmp/events && fail "unexpected event: $1" || ok; }
answers_used()  { is "unused answers" "$(cat /tmp/ans)" ""; not_in_events "out of answers"; }
shim_lines() { echo "$(grep -c fuel_ending_mmui /jci/sm/sm.conf)/$(grep -c fuel_ending_mmui /jci/sm/sm_WCP.conf)"; }
after_mmui() { grep -A1 'name="jciMMUI"' "/jci/sm/$1" | tail -n 1 | grep -c fuel_ending_mmui; }
js_state()   { is "ecoenergyApp.js" "$(m5 $ECO)" "$1"; is "FuelConsumptionCtrl.js" "$(m5 $FCC)" "$2"; }
confs_are()  { is "sm.conf" "$(m5 /jci/sm/sm.conf)" "$1"; is "sm_WCP.conf" "$(m5 /jci/sm/sm_WCP.conf)" "$2"; }
no_conf_backups() { is "conf backups" "$(ls /jci/sm | grep -c fuelend-orig)" "0"; }
shim_off() { is "shim lines" "$(shim_lines)" "0/0"; [ -e "$SO" ] && fail "$SO should not exist" || ok; }
shim_on() {
  is "shim lines" "$(shim_lines)" "1/1"
  is "line after jciMMUI (sm.conf)" "$(after_mmui sm.conf)" "1"
  is "line after jciMMUI (sm_WCP.conf)" "$(after_mmui sm_WCP.conf)" "1"
  is "shim file" "$(m5 $SO)" "$MOD_SO"
}
case_() { echo "### $*"; }

# Answers, in order: per tweak Install/Uninstall/Skip (0/1/2), then OK/Exit (0/1) after a
# step that ran; at the end Reboot now/Reboot later (0/1), only if something was changed.
ALL_INSTALL="0 0 0 0 0 0 0"
ALL_UNINSTALL="1 0 1 0 1 0 0"
SHIM_INSTALL="2 2 0 0 0"
SHIM_UNINSTALL="2 2 1 0 0"
NOTHING_INSTALL="0 0 0 0 0 0"     # every step ran, nothing changed: no reboot question
NOTHING_UNINSTALL="1 0 1 0 1 0"

case_ "A) install all three, reboot now"; reset; run "$ALL_INSTALL"
js_state "$MOD_ECO" "$MOD_FCC"; shim_on
is ".org backups" "$(m5 $ECO.org)/$(m5 $FCC.org)" "$ORG_ECO/$ORG_FCC"
is "sm.conf backup" "$(m5 /jci/sm/sm.conf.fuelend-orig)" "$SM"
is "sm_WCP.conf backup" "$(m5 /jci/sm/sm_WCP.conf.fuelend-orig)" "$WCP"
is "permissions kept" "$(ls -l $ECO | cut -c1-10)" "-rwxr-xr-x"
rebooted 1; answers_used; mp3_kept

case_ "B) install again -> already installed, no reboot question"; run "$NOTHING_INSTALL"
js_state "$MOD_ECO" "$MOD_FCC"; shim_on; rebooted 0; answers_used; logged "nothing changed"

case_ "C) uninstall all three, reboot now"; run "$ALL_UNINSTALL"
js_state "$ORG_ECO" "$ORG_FCC"; shim_off; confs_are "$SM" "$WCP"; no_conf_backups
[ -e "$ECO.org" ] || [ -e "$FCC.org" ] && fail ".org backups should be removed" || ok
[ -d /data_persist/fuel-ending ] && fail "shim folder should be removed" || ok
rebooted 1; answers_used

case_ "D) uninstall again -> not installed, no reboot question"; run "$NOTHING_UNINSTALL"
js_state "$ORG_ECO" "$ORG_FCC"; shim_off; rebooted 0; answers_used

case_ "E) install all three, reboot later -> installed, no reboot"; reset; run "0 0 0 0 0 0 1"
js_state "$MOD_ECO" "$MOD_FCC"; shim_on; rebooted 0; answers_used; logged "complete, rebooting"

case_ "F) skip all"; reset; run "2 2 2"
js_state "$ORG_ECO" "$ORG_FCC"; confs_are "$SM" "$WCP"; rebooted 0; answers_used
is "skipped" "$(grep -c skipped $LOG)" "3"; logged "nothing changed"; mp3_kept

case_ "G) damaged installer"; reset; echo "#" >> /usb/fuel-consumption.sh; run ""
js_state "$ORG_ECO" "$ORG_FCC"; confs_are "$SM" "$WCP"; rebooted 0; mp3_kept; logged "ERROR: md5 of fuel-consumption.sh"

case_ "H) other firmware"; reset; echo 'JCI_SW_VER="MAZ_CMU-150_70.00.100"' > /jci/version.ini; run ""
js_state "$ORG_ECO" "$ORG_FCC"; rebooted 0; logged "CMU version: 70.00.100"

case_ "I) bar values installed, then Exit -> the rest is skipped, reboot now"; reset; run "0 1 0"
js_state "$ORG_ECO" "$MOD_FCC"; confs_are "$SM" "$WCP"; rebooted 1; answers_used; logged "remaining steps skipped"

case_ "J) damaged jci-mods/FuelConsumptionCtrl.js -> that step fails, the rest is installed"; reset
echo x >> /usb/jci-mods/FuelConsumptionCtrl.js; run "$ALL_INSTALL"
js_state "$MOD_ECO" "$ORG_FCC"; shim_on; rebooted 1; answers_used; logged "ERROR: Bar values"

case_ "K) unknown ecoenergyApp.js on the head unit -> left alone"; reset; echo "//x" >> "$ECO"; K=$(m5 $ECO)
run "$ALL_INSTALL"
js_state "$K" "$MOD_FCC"; [ -e "$ECO.org" ] && fail "no backup of an unknown file" || ok; logged "not the known original"

case_ "L) other MMUI version -> shim not installed"; reset; echo x >> /jci/mmui/svcjcimmui.so; run "$SHIM_INSTALL"
shim_off; confs_are "$SM" "$WCP"; no_conf_backups; rebooted 0; logged "another"

case_ "M) another preload on jciMMUI -> shim not installed"; reset
sed -i '/name="jciMMUI"/a\            <environ_var env_name="LD_PRELOAD" env_value="/x.so"/>' /jci/sm/sm.conf; M=$(m5 /jci/sm/sm.conf)
run "$SHIM_INSTALL"
confs_are "$M" "$WCP"; no_conf_backups; rebooted 0; logged "another preload"

case_ "N) missing jci-shims/fuel_ending_mmui.so.md5"; reset; rm /usb/jci-shims/fuel_ending_mmui.so.md5; run "$SHIM_INSTALL"
shim_off; confs_are "$SM" "$WCP"; no_conf_backups; rebooted 0

case_ "O) damaged shim file"; reset; echo x >> /usb/jci-shims/fuel_ending_mmui.so; run "$SHIM_INSTALL"
shim_off; confs_are "$SM" "$WCP"; no_conf_backups; rebooted 0

case_ "P) preload on another service (jciBLMSettings) stays through install + uninstall"; reset
sed -i '/name="jciBLMSettings"/a\            <environ_var env_name="LD_PRELOAD" env_value="/data_persist/other.so"/>' /jci/sm/sm.conf; P=$(m5 /jci/sm/sm.conf)
run "$SHIM_INSTALL"; shim_on; is "other preload" "$(grep -c other.so /jci/sm/sm.conf)" "1"
run "$SHIM_UNINSTALL"; confs_are "$P" "$WCP"; no_conf_backups; shim_off

case_ "Q) an old *.fuelend-orig is overwritten, not reused"; reset
echo "old copy" > /jci/sm/sm.conf.fuelend-orig; echo "old copy" > /jci/sm/sm_WCP.conf.fuelend-orig
run "$SHIM_INSTALL"; shim_on
is "sm.conf backup" "$(m5 /jci/sm/sm.conf.fuelend-orig)" "$SM"
is "sm_WCP.conf backup" "$(m5 /jci/sm/sm_WCP.conf.fuelend-orig)" "$WCP"

case_ "R) editing sm_WCP.conf fails -> both confs back to the state before THIS run, copies removed"; reset
echo "old copy" > /jci/sm/sm.conf.fuelend-orig; echo "old copy" > /jci/sm/sm_WCP.conf.fuelend-orig
export FAIL_SED=1; run "$SHIM_INSTALL"; unset FAIL_SED
shim_off; confs_are "$SM" "$WCP"; no_conf_backups; rebooted 0
logged "restore sm.conf: OK"; logged "Everything was restored"; not_logged "STOPPED"

case_ "S) editing fails AND restoring sm.conf fails -> stop, no reboot question, its copy kept"; reset
export FAIL_SED=1 FAIL_RESTORE=1; run "$SHIM_INSTALL"; unset FAIL_SED FAIL_RESTORE
rebooted 0; mp3_kept; logged "STOPPED"; logged "copy kept"
is "sm.conf copy kept" "$(m5 /jci/sm/sm.conf.fuelend-orig)" "$SM"
# sm_WCP.conf was not edited (the edit failed), so it is unchanged and its copy is removed
is "sm_WCP.conf" "$(m5 /jci/sm/sm_WCP.conf)" "$WCP"

case_ "T) uninstall when it is not installed -> nothing changes"; reset; run "$NOTHING_UNINSTALL"
js_state "$ORG_ECO" "$ORG_FCC"; rebooted 0; answers_used; logged "not installed"

case_ "U) the dialog gives no answer -> every step is skipped"; reset; run ""
js_state "$ORG_ECO" "$ORG_FCC"; confs_are "$SM" "$WCP"; rebooted 0; is "skipped" "$(grep -c skipped $LOG)" "3"

echo
echo "$CHECKS checks, $FAILS failed"
[ "$FAILS" = "0" ]
