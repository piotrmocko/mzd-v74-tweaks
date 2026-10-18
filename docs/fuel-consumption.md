# Fuel Consumption tweaks – details, build and patch instructions

Three independent tweaks for the Fuel Consumption app (`fuel-consumption.sh`). Tested in a Mazda 6 (GJ, 2019, EU), CMU 74.00.324A, with i-stop + i-ELOOP and cylinder deactivation. In this car i-stop is switched off at every engine start by a small OBD device, the same way as with the i-stop OFF button.

| Tweak | Changes |
|---|---|
| **Bar values** – the L/100km value above every bar of both graphs | `/jci/gui/apps/ecoenergy/controls/FuelConsumption/js/FuelConsumptionCtrl.js` ← `jci-mods/FuelConsumptionCtrl.js` |
| **Fuel ending screen** – at ignition off show the Fuel Consumption screen instead of the i-stop screen, for 7 s instead of 5 s | `/jci/gui/apps/ecoenergy/js/ecoenergyApp.js` ← `jci-mods/ecoenergyApp.js` |
| **Fuel ending data** – on i-stop cars the ending screen also gets its data (graphs filled) | `/data_persist/fuel-ending/fuel_ending_mmui.so` ← `jci-shims/fuel_ending_mmui.so`, plus one LD_PRELOAD line for `jciMMUI` in `/jci/sm/sm.conf` and `sm_WCP.conf` |

| | Stock | Tweak |
|---|---|---|
| Fuel Consumption screen | ![stock](../images/fuel-bar-values-stock.jpg) | ![tweak](../images/fuel-bar-values-tweak.jpg) |
| At ignition off (i-stop car) | ![stock](../images/fuel-ending-stock.jpg) | ![tweak](../images/fuel-ending-tweak.jpg) |

Screenshots from the [mzd-emu](https://github.com/ScorpAL/mzd-emu) emulator with test data (see [Testing in mzd-emu](#testing-in-mzd-emu)).

## How it works

### Fuel ending screen and data

With "Show screen at ignition off" enabled, the screen is chosen in `/jci/mmui/uia/libjciuiaecoenergy.so` (MMUI). There is no setting for it. The ending state machine checks two guards, in this order: `UIA_ECOENERGY_isPrevEngRunNEndingSetOnNEndingIsEffectiveness`, then `...IsFuelConsumption`. Both read the equipped-feature type:

| Feature type | Ending screen |
|---|---|
| `ISTOP`, `ISTOP_IELOOP`, `ISTOP_MHYBRID` | i-stop effectiveness |
| `NONE`, `IELOOP`, `MHYBRID` | fuel consumption |
| HEV | its own guard (untouched) |

`ecoenergy_dbus_start_EndingScreenStatus` then asks the EEM service (`/jci/eem/svcjcieem.so`) for data with `EEM_SetEEMUpdateScreenEnable(handle, code, cb, 0)`. Code **11** sends the i-stop data, code **12** sends the fuel data (`SendDrvAvgFuelEconomy`, `Drv1AvlFuel_BarGraph`, `CumlAvgEfficiencyReset_BarGraph`, `CumlFuelEff_Current`). These are the same four senders the normal fuel screen (code 8) uses. Code 11 is used nowhere else.

- **`ecoenergyApp.js`** wraps `handleContext`: an `EndingEffectiveness` context is shown as `EndingFuelConsumption`. It also changes `_startEndingTimer` from 5000 to 7000 ms. Only the GUI times the ending screen: it sends `EndingTimeout`, and the MMUI has no timeout of its own. Without the shim, only the "Current" value is filled, because EEM still sends the i-stop data.
- **`fuel_ending_mmui.so`** (LD_PRELOAD for `jciMMUI`) interposes three functions:
  - Effectiveness guard → 0,
  - Fuel guard → original fuel OR original effectiveness,
  - `EEM_SetEEMUpdateScreenEnable`: 11 → 12.

  This works because the state table reaches the guards through `R_ARM_ABS32` symbol relocations, and the EEM call goes through the PLT.
  - The originals are found in the defining library's own dynamic symbol table (`dl_iterate_phdr`, GNU/SYSV hash), not via `dlsym`, so the shim cannot resolve back to itself. Only if `EEM_SetEEMUpdateScreenEnable` is not found that way, `dlsym(RTLD_NEXT, ...)` is tried, and a result that points back into the shim is rejected.
  - Nothing runs at load time. If a guard is not found, the stock behaviour is kept (the remap is only active when both guards were found). If the original EEM function is not found at all, the call returns -1 and does nothing (logged).
  - `jciMMUI` is `reset_board="yes"`, so a crash would reboot the head unit.

#### CPU load and logging

- The two guards are only evaluated by the ending state machine, at ignition off. `EEM_SetEEMUpdateScreenEnable` is called when an Eco/Fuel screen requests its data from EEM (when a screen opens, or the ending screen starts), not for every bar update. The bars are drawn by the GUI (`FuelConsumptionCtrl.js`) from the data EEM sends; the shim is not involved there. For codes other than 11 the shim adds one comparison and forwards the call.
- Log: `/tmp/fuel-ending-mmui.log` (tmpfs, so RAM only, gone after a reboot; nothing is written to flash). One `init` line on the first call, then three short lines per ignition off (two guards + the 11 -> 12 remap). Nothing is logged for other EEM codes. Each line is one `stat` + `fopen`/`fprintf`/`fclose`. Logging stops at 32 KB (roughly 200 ignition-offs).

### Bar values

`FuelConsumptionCtrl.js` gets a `_modSetBarLabel()` helper, called from `_setCFERGraphBarHeight(s)` (history bars) and `_setCDFEGraphBarHeight(s)[Right]` (this-drive 1-min and 10-min bars). It adds a label inside each bar `div`, so the label follows the bar and its animations. The HEV branches are untouched.

- The graph areas clip at 109 px, so a tall bar gets its value inside the bar.
- The 1-min bars are only 21 px wide, so they use a smaller font, and 4-character values (e.g. `12.8`) are slightly tighter.
- The 1-minute slide animation ends with Presto's `oTransitionEnd`, which calls `_setCDFEGraphBarHeights` and so redraws the labels. Chrome-based emulators do not fire this event.

## Files and checksums

Every file the installer brings has an `.md5` next to it (`md5sum` format). The installer reads the expected values from these files, and CI checks that every `.md5` matches its file.

| File | md5 |
|---|---|
| `jci-org/ecoenergyApp.js.org` (original on the head unit) | `32f3607cbbbb0532f28bb726882e990b` |
| `jci-mods/ecoenergyApp.js` | `65b6008c19b52041232e0ead96ad22a6` |
| `jci-org/FuelConsumptionCtrl.js.org` (original on the head unit) | `9b0443778acc8ab1ac89ea6561f1b153` |
| `jci-mods/FuelConsumptionCtrl.js` | `266f2fb5876cc89287efda4cdc8ad52e` |
| `jci-shims/fuel_ending_mmui.so` | `554ca237fcf6f11dbdd8b34d142ca544` |
| `/jci/mmui/uia/libjciuiaecoenergy.so` (checked on the head unit) | `ac44a5f1bbcbe32d83d4076e6e6f4562` |
| `/jci/mmui/svcjcimmui.so` (checked on the head unit) | `3b63fa37aa2ae4989c1febaa18c1f292` |

If you change `fuel-consumption.sh`, a `jci-mods` file or a shim, update its `.md5` (`md5sum file > file.md5`). CI fails otherwise.

## Creating the modified JS files yourself

The scripts in `jci-patches/` create the `jci-mods` files from the originals and check the md5 of the input:

```sh
python3 jci-patches/ecoenergyApp-patch.py         jci-org/ecoenergyApp.js.org         jci-mods/ecoenergyApp.js
python3 jci-patches/FuelConsumptionCtrl-patch.py  jci-org/FuelConsumptionCtrl.js.org  jci-mods/FuelConsumptionCtrl.js
```

CI runs the same commands and checks that the output equals `jci-mods/`.

## Building the shim

You normally don't need to. The `Release` workflow builds it with the toolchain pinned by the `mazda/m3-toolchain` submodule, and opens a PR when `jci-shims/` changes.

Locally (Linux x86_64):

```sh
git submodule update --init mazda/m3-toolchain   # uses Git LFS
sh build/build.sh                                # or: sh build/build.sh /path/to/m3-toolchain
```

`build/build.sh` compiles every `mazda/patches/<name>/*.c` into `jci-shims/<name>.so` and writes `jci-shims/<name>.so.md5`. The build is reproducible: the same source gives the same md5 wherever the repo is checked out. Shims may only link against libc/libdl/libpthread. On this old glibc, `clock_gettime` lives in librt, so use `time()`.

## Is i-stop required?

No. The ending screen is chosen from the equipped-feature type that the EEM service reports (table above), not from whether i-stop is switched on at the moment.

| Car | Bar values | Fuel ending screen | Fuel ending data |
|---|---|---|---|
| Equipped with i-stop (`ISTOP`, `ISTOP_IELOOP`, `ISTOP_MHYBRID`) | yes | Fuel Consumption instead of i-stop, 7 s | fills the graphs |
| Without i-stop (`NONE`, `IELOOP`, `MHYBRID`) | yes | already Fuel Consumption in stock; now 7 s | no change (passes through) |
| HEV | yes | no change | no change |

- **i-stop turned off with its button:** the equipped type stays the same, so it makes no difference. Tested: the test car has i-stop switched off at every engine start (a small OBD device does what the button does), and all three tweaks work there as described. Turning it off in the Instrument Cluster settings should behave the same (not tested).
- **i-stop disabled in the as-built data (FORScan):** if the EEM then reports a type without i-stop, the car behaves like the "Without i-stop" row.
- Only a car equipped with i-stop + i-ELOOP (`ISTOP_IELOOP`) was tested.

## Testing

### Testing in mzd-emu

The JS changes and the screenshots were made in [mzd-emu](https://github.com/ScorpAL/mzd-emu) (74.00.324 EU):

1. Copy `jci-mods/ecoenergyApp.js` to `jci/gui/apps/ecoenergy/js/` and `jci-mods/FuelConsumptionCtrl.js` to `jci/gui/apps/ecoenergy/controls/FuelConsumption/js/` in the emulator's `jci` folder, start it, and do a hard reload in the browser.
2. For English screens, set `"languageId": "LANGS_US_ENGLISH"` in `server/data/user-settings.json` (restart after changing it).
3. mzd-emu sends only zeros for the Fuel Consumption data, so paste this test data into the browser console (F12):

```js
// Fuel Consumption test data for mzd-emu. Paste into the browser console (F12).
// Values are tenths of L/100km, as the MMUI sends them (82 = 8.2).
//   showFuel('FuelConsumption')      - the normal Fuel Consumption screen
//   showFuel('EndingEffectiveness')  - the i-stop ending screen at ignition off; with
//                                      jci-mods/ecoenergyApp.js it becomes EndingFuelConsumption
function showFuel(ctxtId) {
  function send(msgId, payload) {
    framework.routeMmuiMsg({ msgType: 'msg', uiaId: 'ecoenergy', msgId: msgId, params: { payload: payload } });
  }
  // This drive: 10 one-minute bars (newest first), then 5 ten-minute bars (newest first)
  var drive = [64, 71, 58, 92, 128, 77, 69, 85, 101, 74, 66, 72, 81, 69, 95];
  // Average history: bars 2..6 (2 = newest)
  var history = [79, 85, 74, 91, 68];
  send('FuelType', { FuelType: 'GAS' });
  send('CurrEquippedFeature', { CurrFeature: 'ISTOP' });
  send('CurrDrvEcoPerInstBarGraph', { CurrDrvFuelEco_BarGraph: {
    EEM_CurDrvAvgFuelEco: drive.map(function (v) { return { Drv1AvlFuelE: v }; }) } });
  send('CumFuelResetEcoGraphData', { CumFuelResetEcoGraph: {
    EEM_cumAvgFuelEffAfterReset: history.map(function (v) { return { cumlAvgEfficiency: v }; }) } });
  framework.debug.fakeCtxtChgMsgs('ecoenergy', ctxtId, { payload: { celebrationCriteria: false } });
  setTimeout(function () {
    // "Average (this drive)" and the "Current" history bar
    send('CurrAvgDriveFuelEco', { CurrentAvgFuelEco: {
      CurdrvAvlFuel: { Drv1AvlFuelE: 82 }, CurdrvAvlFuel_unit: 'L100KM' } });
    send('CumulativeAvgFuelEconomy', { CumulativeAvgFuelEco: {
      cntrlstat_fuelEff: { cumlAvgEfficiency: 78 }, cumlEff_unit: 'L100KM' } });
  }, 500);
}
showFuel('FuelConsumption');
```

Then run `showFuel('EndingEffectiveness')` to see what an i-stop car shows at ignition off. In the emulator the snippet always provides the data, so this shows the ending screen as it looks with the shim. Chrome does not fire Presto's `oTransitionEnd`, so after the 1-minute slide animation run `showFuel(...)` again to redraw the bar values.

### Other tests

- **Shim:** tested in qemu against the real `libjciuiaecoenergy.so` (with stubbed dependencies), calling the real state-table entries and `ecoenergy_dbus_start_EndingScreenStatus`. CI runs the same kind of checks (`tests/fuel-consumption/shim/run.sh`) against a small stand-in library, because the Mazda library cannot be in the repo: i-stop and non-i-stop feature types, HEV, ending screen off, other EEM codes untouched, guards missing, EEM library with a SONAME, and the shim in an unrelated process.
- **Installer:** CI simulates `fuel-consumption.sh` in busybox (`tests/fuel-consumption/installer/run.sh`) with stand-in `sm.conf` files: install, reinstall, uninstall, uninstall again, Exit, skip all, Exit after the first step, damaged installer/JS/shim, missing `.md5`, unknown original on the head unit, other firmware, other MMUI version, another preload on `jciMMUI`, a preload on another service (left untouched), a failed `sm.conf` edit (restored), and the `mp3` folder handling. Before the PR it was also run with the real `sm.conf` files.
- All three tweaks are installed and working in the car mentioned above.
