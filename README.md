# MZD v74 Tweaks - Mazda CMU Modifications

A collection of tweaks and modifications for the Mazda infotainment system (CMU - Connectivity Master Unit) running firmware version 74.00.324. These mods allow you to customize your Mazda Connect experience with additional features and improvements.

## System Requirements

- **Infotainment System**: MZD Connect (CMU firmware version **74.00.324 only**)
- **USB Drive**: FAT32 formatted USB flash drive (up to 32 GB)
- **Input Device**: None for the launcher. A USB keyboard is needed only for the alternative terminal workflow.

## Installation Instructions

1. Download the latest release ZIP and unpack its contents directly onto a FAT32-formatted USB drive (up to 32 GB). Do not put the files inside another folder.
2. Turn the ignition to ACC and wait for MZD to finish loading.
3. Plug the USB drive into the Mazda USB hub and wait for the launcher dialog to appear.
4. Choose which available script to run and follow its on-screen prompts. No keyboard is needed for this launcher workflow.

### Launcher

`run.sh` automatically starts `launcher.sh` when the USB drive is loaded. The launcher displays on-screen dialog window with available scripts one at a time; choose **Open** to run the displayed script, **Next** to skip it, or **Exit** to leave the launcher. It also offers **Start over** after the list is complete.

The launcher includes entries for **Terminal** and **Built-in MZD Scripts**, but those features are not available in the current version. **Reboot** is available from the launcher. Additional `.sh` files placed in the root of the USB drive are also offered after the built-in script entries; select **Open** to run one.

### Alternative: run scripts from Terminal

To open Terminal instead of using the launcher, follow this method:

1. With the USB drive connected, open its contents from the MZD **Entertainment** menu as if starting music playback. This launches the service menu.
2. Select **Next > Terminal**. A USB keyboard is required for this method.
3. In Terminal, find the USB mount (usually `/tmp/mnt/sda1` or `/tmp/mnt/sdb1`), then run a script directly, for example `sh fuel-consumption.sh`.
4. Use the keyboard to inspect terminal output and logs while in the car. Follow the script's prompts.

The launcher is the recommended option for normal use. The terminal method is useful when you need to run a script manually or review its output directly in the car.

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

**Configuration**:
- After reboot navigate to **Settings** > **Active Driving Display** > **Display Information** to change **Street Information**

**Issues**:
- **Street Information** menu is grayed out - your HUD doesn't support displaying road name

### 2. `no-more-disclaimer.sh` - No More Disclaimer Mod
**Purpose**: Removes entirely the disclaimer/warning screen that appears on the system startup. With the stock behavior it disappears in 3.5 seconds.

![MZD Active Driving Display Settings](images/mzd-disclaimer.jpg)

**What it does**:
- Modifies the system application to skip disclaimer prompts
- Provides a cleaner boot experience without interruptions

### 3. `fuel-consumption.sh` - Fuel Consumption Tweaks
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

**Documentation**:
- Details of the fuel consumption tweaks: [docs/fuel-consumption.md](docs/fuel-consumption.md).

### 4. `logs-collector.sh` - Running Logs Collector
**Purpose**: Copies the CMU's `/var/log/running_log` files to the USB drive or changes their rotation size.

**Running**:
- Choose **Copy logs** to save the current running logs under `logs/` on the USB drive. Each collection is saved in its own numbered folder.
- Choose **Change size** and then **Enlarged 5MB** to increase the running log rotation size. This can help collect more logs when using an OEM AA Mods debug release. The CMU must reboot for the new size to take effect.
- To preserve diagnostic output, run **Copy logs before turning off the ignition**. Turning the ignition off first can cause the running logs you want to collect to be lost.

### 5. `touchscreen.sh` - Touchscreen Enabled Tweak
**Purpose**: Enables touchscreen input while the vehicle is moving.

### 6. `backup-jci.sh` - JCI Full System Backup
**Purpose**: Creates a complete backup of the JCI system directory.

**What it does**:
- Creates a ZIP archive of the entire `/jci` directory
- Automatically checks for sufficient free space on USB drive

**Requirements**:
- At least 170 MB of free space on USB drive

**Output**:
- Backup file: `backup/JCI-[VERSION].zip`
- Use this backup to restore your system to a known-good state

### 7. `revert-aio.sh` - Uninstall AIO base Tweaks only
**Purpose**: Removes previously installed base modifications of AIO (All-In-One) Tweaks from your system. It doesn't remove the targeted mods. Remove them with AIO scripts.

**What it does**:
- Restores original configurations:
  - `/jci/sm/sm.conf` - System Manager configuration
  - `/jci/opera/opera_home/opera.ini` - Opera browser settings
  - `/jci/opera/opera_dir/userjs/fps.js` - Frame rate settings
- Verifies file integrity before completion
- Logs all operations for troubleshooting

## File Structure

```
mzd-v74-tweaks/
├── README.md
├── run.sh                             # Starts the launcher
├── launcher.sh                        # Offers scripts and launcher actions
├── fuel-consumption.sh                # Fuel Consumption tweaks
├── hud-eu-region.sh                   # HUD Street Info region tweak
├── no-more-disclaimer.sh              # Disclaimer removal tweak
├── touchscreen.sh                     # Touchscreen tweak
├── logs-collector.sh                  # Copy running logs / change rotation size
├── backup-jci.sh                      # Back up /jci to a ZIP on the USB drive
├── revert-aio.sh                      # Remove AIO base tweaks
├── autorun/                           # USB autorun files for the CMU
├── *.md5                              # Checksums for protected scripts and payload files
├── .github/workflows/                 # CI, Build, and Release workflows
├── jci-mods/                          # Modified application files
├── jci-org/                           # Original application files
├── jci-patches/                       # Rebuild modified JS files from originals
├── jci-shims/                         # Prebuilt ARM shims and checksums
├── mazda/                             # Toolchain submodule and shim source code
├── build/                             # Shim build and checksum tools
├── docs/                              # Additional technical documentation
├── tests/                             # Installer and shim tests
├── images/                            # README screenshots
├── js/                                # JavaScript utility files
├── mp3/                               # USB audio files used by the autorun setup
└── mp3title.txt                       # Audio metadata
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
6. System offers reboot to apply changes

## Support & Debugging

If you encounter issues:
1. Check the log files in the `logs/` directory
2. Verify your firmware version is exactly 74.00.324
3. Ensure USB drive is properly formatted (FAT32)
4. Try a different USB port on the vehicle
5. Review the error messages in the dialog boxes carefully

## Contributing

- Every file an installer brings, and the installer itself, has an `.md5` next to it (`md5sum` format). The **CI** workflow fails if any `.md5` does not match its file. It also checks that `jci-patches/` reproduces `jci-mods/`, that the shell scripts parse, and that `jci-shims/` matches what `mazda/patches/` builds to.
- CI also runs the tests in `tests/`: `fuel-consumption/installer/run.sh` simulates `fuel-consumption.sh` in busybox (`docker run --rm --tmpfs /usb -v "$PWD:/repo:ro" busybox:1.36 sh /repo/tests/fuel-consumption/installer/run.sh`), and `fuel-consumption/shim/run.sh` runs the shims under qemu-arm against stand-in libraries (needs the m3-toolchain and `qemu-user`). The **Build** and **Release** workflows run these tests as part of their validation.
- The **Build** workflow rebuilds shims with the pinned m3-toolchain and opens a PR when `jci-shims/` changes. The **Release** workflow is manual-only and publishes a ready-to-copy USB drive ZIP. Its version starts at `1.0.0`; later releases use semantic commit-message bumps (`feat` = minor, `fix` and other changes = patch, `BREAKING CHANGE` or `!` = major). Release descriptions list non-merge commit subjects since the previous release.

## Disclaimer

These modifications alter system files on your Mazda infotainment system. Use at your own risk. Always create backups before installing any modifications. The author is not responsible for any damage or issues resulting from the use of these tweaks.

## License

Original modifications by the community.
The terminal access based on https://github.com/shunceyb/mzd74-tweaks-no-touch.
MZD UI changes tested and screenshoted with https://github.com/ScorpAL/mzd-emu.
