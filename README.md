# MZD v74 Tweaks - Mazda CMU Modifications

A collection of tweaks and modifications for the Mazda infotainment system (CMU - Connectivity Master Unit) running firmware version 74.00.324. These mods allow you to customize your Mazda Connect experience with additional features and improvements.

## System Requirements

- **Infotainment System**: MZD Connect (CMU firmware version **74.00.324 only**)
- **USB Drive**: FAT32 formatted USB flash drive (up to 32 GB)
- **Input Device**: USB keyboard for terminal access

## Installation Instructions

1. **Download and Prepare**
   - Clone or download all files from this repository
   - Place all files on a FAT32 formatted USB drive (max 32 GB)

2. **Connect to Vehicle**
   - Start ACC (Accessory mode) without igniting the engine
   - Connect the USB drive to the Mazda USB hub
   - Connect a USB keyboard to the Mazda USB hub

3. **Launch Terminal**
   - Navigate to the Entertainment menu
   - Open USB drive content to play music
   - Wait for the status window to appear and JCI Test Mode to launch
   - Wait for a black screen with buttons to appear
   - Click **NEXT** and then **TERMINAL**

4. **Execute a Script**
   - In the terminal, navigate to the USB drive by typing in the command: `cd /tmp/mnt/sda1` or `cd /tmp/mnt/sdb1` and confirm with ENTER key
   - Optionally, list files to verify contents: `ls`
   - Run the desired script: `sh NAME_OF_FILE.sh`
   - Follow the on-screen prompts
   - Wait 30-120 seconds (or more) for the system to restart
   - If returned to terminal, review `logs` directory and `exit` or `reboot`

## Available Scripts

### 1. `hud-eu-region.sh` - HUD Settings Europe Region Mod
**Purpose**: Enables Active Driving Display hidden settings in the Europe region and non-English/French/Spanish languages - **Street information: Always/At Maneuver/Off** with Windshield Head-Up Display only.

![MZD Active Driving Display Settings](images/WHUD-supported-CHUD-unsupported.jpg)

![MZD Active Driving Display Settings](images/mzd-hud.jpg)

![MZD Active Driving Display Settings > Display Information](images/mzd-hud-display-info.jpg)

![MZD Active Driving Display Settings > Street Information](images/mzd-hud-street-info.jpg)

**What it does**:
- Modifies the vehicle settings application to unlock HUD configuration options
- Allows customization of HUD display preferences
- Can be installed or uninstalled reversibly

**Installation/Uninstall**:
- Run the script and choose "Install" or "Uninstall" when prompted
- Original system files are automatically backed up before modification
- Logs are saved to `logs/install.log` or `logs/uninstall.log`
- After reboot navigate to **Settings** > **Active Driving Display** > **Display Information**

**Issues**:
- *Street Information* menu is grayed out - your HUD doesn't support displaying road name

### 2. `no-more-disclaimer.sh` - No More Disclaimer Mod
**Purpose**: Removes entirely the disclaimer/warning screen that appears on the system startup. With the stock behavior it disappears in 3.5 seconds.

![MZD Active Driving Display Settings](images/mzd-disclaimer.jpg)

**What it does**:
- Modifies the system application to skip disclaimer prompts
- Provides a cleaner boot experience without interruptions
- Can be installed or uninstalled reversibly

**Installation/Uninstall**:
- Run the script and choose "Install" or "Uninstall" when prompted
- Original system files are automatically backed up before modification
- Logs are saved to `logs/install.log` or `logs/uninstall.log`

### 3. `backup-jci.sh` - JCI Full System Backup
**Purpose**: Creates a complete backup of the JCI system directory.

**What it does**:
- Creates a ZIP archive of the entire `/jci` directory
- Automatically checks for sufficient free space on USB drive

**Requirements**:
- At least 170 MB of free space on USB drive

**Output**:
- Backup file: `JCI-[VERSION].zip`
- Log file: `logs/backup.log`
- Use this backup to restore your system to a known-good state

### 4. `revert-aio.sh` - Uninstall AIO base Tweaks only
**Purpose**: Removes previously installed base modifications of AIO (All-In-One) Tweaks from your system. It doesn't remove the targeted mods. Remove them with AIO scripts.

**What it does**:
- Restores original configurations:
  - `/jci/sm/sm.conf` - System Manager configuration
  - `/jci/opera/opera_home/opera.ini` - Opera browser settings
  - `/jci/opera/opera_dir/userjs/fps.js` - Frame rate settings
- Verifies file integrity before completion
- Logs all operations for troubleshooting

**Running**:
- Run the script and confirm when prompted
- System will reboot automatically upon completion
- Check `logs/uninstall.log` if errors occur

### 5. `fuel-consumption.sh` - Fuel Consumption Tweaks
**Purpose**: Three tweaks for the Fuel Consumption app. Each one can be installed, uninstalled or skipped on its own:
- **Bar values**: the L/100km value above every bar of both graphs. Stock firmware shows it only above "Current".
- **Fuel ending screen**: at ignition off, show the Fuel Consumption screen instead of the i-stop screen (cars with i-stop always get the i-stop screen), for 7 s instead of 5 s.
- **Fuel ending data**: on i-stop cars, the ending screen also gets its data (graphs filled). This is a small shim for the MMUI service (`jci-shims/fuel_ending_mmui.so`).

**Is i-stop required?** No. The head unit picks the ending screen from the *equipped* features (reported by the EEM service), not from whether i-stop is switched on right now:
- **Bar values** works on every car.
- **Fuel ending screen**: on a car equipped with i-stop it replaces the i-stop ending screen. Without i-stop, the stock ending screen already is the Fuel Consumption screen, so the tweak only makes it 7 s long.
- **Fuel ending data** only changes something on a car equipped with i-stop; otherwise it passes everything through unchanged.
- Turning i-stop off with its button makes no difference (tested: in the test car i-stop is switched off at every engine start, the same way as with the button). The Instrument Cluster setting should behave the same (not tested). If i-stop was disabled in the as-built data (FORScan) and the EEM then reports no i-stop, the car behaves like one without i-stop (not tested). See [docs/fuel-consumption.md](docs/fuel-consumption.md#is-i-stop-required).

| | Stock | Tweak |
|---|---|---|
| Fuel Consumption screen | ![stock](images/fuel-bar-values-stock.jpg) | ![tweak](images/fuel-bar-values-tweak.jpg) |
| At ignition off (i-stop car) | ![stock](images/fuel-ending-stock.jpg) | ![tweak](images/fuel-ending-tweak.jpg) |

**Running**:
- Run `sh fuel-consumption.sh`. First answer **Continue** or **Exit** (Exit changes nothing).
- For each tweak, choose **Continue** or **Skip**, then **Install** or **Uninstall**, then **OK** (or **Exit** to skip the remaining tweaks).
- The system reboots at the end, but only if something was changed.
- Everything is checked with md5 before any change: the script itself (`fuel-consumption.sh.md5`), every file it brings (`*.md5`), and the exact original on the head unit. Backups: `<file>.org` and `/jci/sm/*.fuelend-orig`. On an error, that tweak is restored.
- While it runs, the script renames `mp3/` to `mp3_off/` on the USB drive, so the head unit does not jump back to the JCI Test Mode after you leave the terminal. It renames it back at the end. Only if a restore failed ("Do NOT reboot") does it stay `mp3_off`: then rename it back to `mp3` on your PC before the next run.
- At the end, remove the USB drive. If nothing was changed, type `exit` to leave the terminal (the HOME button does not work there).
- Log: `logs/fuel-consumption.log`.
- Details, checksums, how to rebuild the shim or re-create the JS files: [docs/fuel-consumption.md](docs/fuel-consumption.md).

## File Structure

```
mzd-v74-tweaks/
├── README.md                          # This file
├── images/                            # Screenshosts for documentation
├── hud-eu-region.sh                   # HUD settings modification script
├── no-more-disclaimer.sh              # Disclaimer removal script
├── fuel-consumption.sh                # Fuel Consumption tweaks (+ fuel-consumption.sh.md5)
├── backup-jci.sh                      # System backup script
├── revert-aio.sh                      # AIO tweaks uninstaller
├── jci-mods/                          # Modified application files (+ .md5)
│   ├── vehsettingsApp.js              # Modified vehicle settings app
│   ├── systemApp.js                   # Modified system app
│   ├── ecoenergyApp.js                # Modified Fuel Consumption app
│   └── FuelConsumptionCtrl.js         # Modified Fuel Consumption graphs
├── jci-org/                           # Original backup files (+ .md5)
│   ├── vehsettingsApp.js.org          # Original vehicle settings app
│   ├── systemApp.js.org               # Original system app
│   ├── ecoenergyApp.js.org            # Original Fuel Consumption app
│   └── FuelConsumptionCtrl.js.org     # Original Fuel Consumption graphs
├── jci-patches/                       # Scripts that create jci-mods files from jci-org
├── jci-shims/                         # Prebuilt shims (+ .md5), built by the Release workflow
│   └── fuel_ending_mmui.so            # LD_PRELOAD shim for jciMMUI
├── mazda/
│   ├── m3-toolchain/                  # Cross toolchain (git submodule, Git LFS)
│   └── patches/fuel_ending_mmui/      # Shim source
├── build/build.sh                     # Builds mazda/patches/* into jci-shims/
├── docs/                              # Details, build and patch instructions
├── tests/                             # CI tests: installer in busybox, shims in qemu-arm
├── js/                                # JavaScript utility files
│   └── run.js                         # Execution script
├── mp3/                               # Audio files for testing
|   └── a.mp3, b.mp3, c.mp3, d.mp3     # Audio test files
└── mp3title.txt                       # Metadata for audio loading
```

## Common Issues & Troubleshooting

### "no such file or directory"
- **Cause**: USB drive not detected or incorrect path
- **Solution**:
  - Verify USB drive is properly connected to the Mazda USB hub
  - Try the alternate path: if `sda1` doesn't work, try `sdb1`
  - Ensure USB drive is formatted as FAT32 and not larger than 32 GB
  - Check the path is typed correctly (case-sensitive)

### "command not found"
- **Cause**: command is misspelled or incorrect syntax
- **Solution**:
  - Type the command carefully, paying attention to capitalization and spacing

### "sh: 0: cannot open ...: No such file"
- **Cause**: misspelled filename
- **Solution**:
  - Verify the exact filename: use `ls` to list files
  - Ensure you're using the correct script name with the `.sh` extension
  - Type the command carefully, paying attention to capitalization and spacing
  - Press TAB key to autocomplete the filename

## Technical Details

### How Installation Works
1. Scripts disable the hardware watchdog to prevent timeout during operations
2. File system is remounted in read-write mode
3. Original system files are backed up with `.org` extension
4. Modified files are copied to system directories
5. File integrity is verified after copying
6. System automatically reboots to apply changes

## Support & Debugging

If you encounter issues:
1. Check the log files in the `logs/` directory
2. Verify your firmware version is exactly 74.00.324
3. Ensure USB drive is properly formatted (FAT32)
4. Try a different USB port on the vehicle
5. Review the error messages in the dialog boxes carefully

## Contributing

- Every file an installer brings, and the installer itself, has an `.md5` next to it (`md5sum` format). The **CI** workflow fails if any `.md5` does not match its file. It also checks that `jci-patches/` reproduces `jci-mods/`, that the shell scripts parse, and that `jci-shims/` matches what `mazda/patches/` builds to.
- CI also runs the tests in `tests/`: `fuel-consumption/installer/run.sh` simulates `fuel-consumption.sh` in busybox (`docker run --rm --tmpfs /usb -v "$PWD:/repo:ro" busybox:1.36 sh /repo/tests/fuel-consumption/installer/run.sh`), and `fuel-consumption/shim/run.sh` runs the shims under qemu-arm against stand-in libraries (needs the m3-toolchain and `qemu-user`). The Release workflow runs both before it publishes anything.
- The **Release** workflow builds the shims with the pinned m3-toolchain. On `main` it opens a PR when `jci-shims/` changes. On an `X.Y.Z` tag it publishes a release with a ready-to-copy USB drive ZIP.

## Disclaimer

These modifications alter system files on your Mazda infotainment system. Use at your own risk. Always create backups before installing any modifications. The author is not responsible for any damage or issues resulting from the use of these tweaks.

## License

Original modifications by the community.
The terminal access based on https://github.com/shunceyb/mzd74-tweaks-no-touch.
MZD UI changes tested and screenshoted with https://github.com/ScorpAL/mzd-emu.
