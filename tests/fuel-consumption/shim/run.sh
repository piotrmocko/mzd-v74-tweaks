#!/bin/sh
# Runs jci-shims/fuel_ending_mmui.so under qemu-arm against small stand-in libraries
# (eco.c, stubs.c; the Mazda libraries cannot be in the repo) and checks what the
# ending state machine does with and without the shim.
#
# Usage (Linux x86_64, needs qemu-user):  sh tests/fuel-consumption/shim/run.sh [path/to/m3-toolchain]
# Exit code: 0 if every check passed.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
TC="${1:-$ROOT/mazda/m3-toolchain}"
CC="$TC/bin/arm-cortexa9_neon-linux-gnueabi-gcc"
SYSROOT="$TC/arm-cortexa9_neon-linux-gnueabi/sysroot"
SHIM="$ROOT/jci-shims/fuel_ending_mmui.so"
LOG=/tmp/fuel-ending-mmui.log
A="-march=armv7-a -mtune=cortex-a9 -mfpu=neon --sysroot=$SYSROOT -std=gnu99 -O2 -Wall"
command -v qemu-arm >/dev/null || { echo "ERROR: qemu-arm not found (qemu-user)"; exit 2; }
[ -x "$CC" ] || { echo "ERROR: $CC not found"; exit 2; }

W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/lib" "$W/uia"
set -e
"$CC" $A -shared -fPIC -DEEM -o "$W/lib/libjcieem_client.so" "$ROOT/tests/fuel-consumption/shim/stubs.c"
"$CC" $A -shared -fPIC -o "$W/uia/libjciuiaecoenergy.so" "$ROOT/tests/fuel-consumption/shim/eco.c" -L"$W/lib" -ljcieem_client
"$CC" $A -shared -fPIC -DMMUI -o "$W/svcjcimmui.so" "$ROOT/tests/fuel-consumption/shim/stubs.c" -ldl
"$CC" $A -DLAUNCHER -o "$W/sm_svclauncher" "$ROOT/tests/fuel-consumption/shim/stubs.c" -ldl
set +e

FAILS=0
CHECKS=0
OUT=""

# run <FT> <ES> <preload or "">
run() {
  rm -f "$LOG"
  _env="ECO_LIB=$W/uia/libjciuiaecoenergy.so,LD_LIBRARY_PATH=$W/lib,FT=$1,ES=$2"
  [ -n "$3" ] && _env="$_env,LD_PRELOAD=$3"
  OUT=$(QEMU_LD_PREFIX="$SYSROOT" QEMU_SET_ENV="$_env" qemu-arm "$W/sm_svclauncher" "$W/svcjcimmui.so" 2>&1)
  RC=$?
  [ -f "$LOG" ] && OUT="$OUT
$(sed 's/^/log: /' "$LOG")"
}
check() {  # check <name> <0|1: must contain> <pattern>
  CHECKS=$((CHECKS + 1))
  if echo "$OUT" | grep -q -- "$3"; then _has=1; else _has=0; fi
  if [ "$_has" != "$2" ]; then
    FAILS=$((FAILS + 1))
    [ "$2" = "1" ] && echo "    FAIL ($1): missing: $3" || echo "    FAIL ($1): unexpected: $3"
    echo "$OUT" | sed 's/^/      | /'
  fi
}
exit_ok() { CHECKS=$((CHECKS + 1)); [ "$RC" = "0" ] || { FAILS=$((FAILS + 1)); echo "    FAIL ($1): exit code $RC"; }; }
# eem <name> <codes that must be requested...> ; every other ending code must not be
eem() {
  _n=$1; shift
  for _c in 11 12 14; do
    case " $* " in *" $_c "*) check "$_n" 1 "eem screen=$_c ";; *) check "$_n" 0 "eem screen=$_c ";; esac
  done
  check "$_n" 1 "eem screen=8 "     # the normal fuel screen is untouched
}

echo "### A) stock, i-stop + i-ELOOP (FT=3), no shim -> i-stop ending, code 11"
run 3 1 ""; exit_ok A; check A 1 "ending=ISTOP"; eem A 11

echo "### B) shim, FT=3 -> fuel ending, code 12"
run 3 1 "$SHIM"; exit_ok B; check B 1 "ending=FUEL"; check B 0 "ending=ISTOP"; eem B 12
check B 1 "log: .*ACTIVE"; check B 1 "log: .*EEM screen 11 -> 12"

for ft in 1 6; do
  echo "### C$ft) shim, i-stop type FT=$ft -> fuel ending, code 12"
  run $ft 1 "$SHIM"; exit_ok C$ft; check C$ft 1 "ending=FUEL"; eem C$ft 12
done

for ft in 0 2 5; do
  echo "### D$ft) shim, no i-stop FT=$ft -> fuel ending, code 12 (same as stock)"
  run $ft 1 "" ; check "D$ft stock" 1 "ending=FUEL"; eem "D$ft stock" 12
  run $ft 1 "$SHIM"; exit_ok D$ft; check D$ft 1 "ending=FUEL"; eem D$ft 12; check D$ft 0 "log: .*EEM screen 11"
done

echo "### E) shim, HEV (FT=4) -> HEV ending, untouched"
run 4 1 "$SHIM"; exit_ok E; check E 1 "ending=HEV"; check E 0 "ending=FUEL"; eem E

echo "### F) shim, ending screen switched off -> no ending screen"
run 3 0 "$SHIM"; exit_ok F; check F 1 "ending=none"; eem F

echo "### G) guards not found (other software) -> stock behaviour, code 11"
cp "$W/uia/libjciuiaecoenergy.so" "$W/eco.bak"
"$CC" $A -shared -fPIC -o "$W/uia/libjciuiaecoenergy.so" "$ROOT/tests/fuel-consumption/shim/eco.c" -L"$W/lib" -ljcieem_client \
  -DUIA_ECOENERGY_isPrevEngRunNEndingSetOnNEndingIsEffectiveness=X_eff \
  -DUIA_ECOENERGY_isPrevEngRunNEndingSetOnNEndingIsFuelConsumption=X_fuel
run 3 1 "$SHIM"; exit_ok G; check G 1 "ending=ISTOP"; eem G 11; check G 1 "log: .*passthrough"
cp "$W/eco.bak" "$W/uia/libjciuiaecoenergy.so"

echo "### H) EEM library with a SONAME -> same as B"
"$CC" $A -shared -fPIC -DEEM -Wl,-soname,libjcieem_client.so -o "$W/lib/libjcieem_client.so" "$ROOT/tests/fuel-consumption/shim/stubs.c"
run 3 1 "$SHIM"; exit_ok H; check H 1 "ending=FUEL"; eem H 12

echo "### I) shim preloaded into an unrelated process -> does nothing"
rm -f "$LOG"
OUT=$(QEMU_LD_PREFIX="$SYSROOT" QEMU_SET_ENV="LD_PRELOAD=$SHIM" qemu-arm "$W/sm_svclauncher" /nonexistent.so 2>&1)
check I 1 "dlopen: "; CHECKS=$((CHECKS + 1)); [ -f "$LOG" ] && { FAILS=$((FAILS + 1)); echo "    FAIL (I): shim wrote a log"; }

echo
echo "$CHECKS checks, $FAILS failed"
[ "$FAILS" = "0" ]
