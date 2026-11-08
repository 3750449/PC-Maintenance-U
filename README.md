# PC Maintenance U

Portable Windows maintenance, diagnostics, conversion, recovery-oriented file search, project/code search, WSL maintenance, and opt-in speech recognition utility.

Current version: **3.0.0**

## Run

Download/extract the folder and double-click `Run-PC-Maintenance.bat`.

No Git installation is required on client computers.

## Main menu

1. Scan Only
2. Standard Maintenance
3. Full Maintenance
4. Check for Program Updates
5. File Conversion
6. Deep File Search / Lost File Finder
7. Project / Code Search
8. WSL / Linux Terminal Maintenance
9. Speech Listener / Microphone
10. Drive Photo Search / Desktop Backup
11. External Drive Health / Diagnosis
12. Apple / Mac External Drive Reader & Rescue
13. Exit

## Project / Code Search

The code finder is intended for old projects that may have been renamed or moved.
It can use:

- project, folder, or source filename clues
- old folder/path origin clues
- programming language/code type
- library/import/include names
- class and function names
- algorithm/purpose keywords found in code, comments, README files, or configuration files
- common project-root markers such as `.git`, `CMakeLists.txt`, `package.json`, `requirements.txt`, `pyproject.toml`, `Cargo.toml`, `pom.xml`, `build.gradle`, `Makefile`, and `Dockerfile`

Matching source/configuration files are grouped into likely project roots and ranked. Results are exported to CSV and a selected project folder can be opened directly.

Purpose matching is keyword/content based rather than a full semantic AI index.

## WSL / Linux maintenance

The WSL menu can:

- display WSL status/version and installed distros
- check package updates in a selected distro
- update a selected distro
- run `wsl.exe --update`
- launch a selected distro terminal

Supported package-manager detection includes `apt`, `dnf`, `yum`, `pacman`, and `zypper`.

Linux package updates may ask for the distro user's sudo password.

## Speech Listener

The speech tool uses Windows `System.Speech` with the current default Windows recording device. It can list AudioEndpoint peripherals, run explicit 15/30/60-second listening sessions, and save recognized phrases/confidence values as CSV reports.

For an attached USB/Bluetooth headset or microphone, select that device as the Windows default input first. The program includes a shortcut to Windows Sound settings.

The listener is deliberately opt-in and does not remain as a hidden background recorder.

## Automatic updates

The launcher checks:

`https://github.com/3750449/PC-Maintenance-U`

before starting. The updater compares `version.txt`, downloads a newer repository archive, validates required files and PowerShell syntax, backs up the existing program, and installs the update.

## Publishing an update

Keep these synchronized:

- `$AppVersion = [version]"2.7.0"` in `PC-Maintenance.ps1`
- `version.txt` containing `2.7.0`

For the next release, change both values, test the package, and push the files to the root of the `main` branch.

## Required repository-root files

- `PC-Maintenance.ps1`
- `Run-PC-Maintenance.bat`
- `Update-PC-Maintenance.ps1`
- `version.txt`

Documentation files are optional but recommended.


## Drive Photo Search / Desktop Backup

Version 2.8.0 adds a photo rescue and backup module.

Search modes:

- Deep search all accessible fixed, removable, and network drives
- Search one selected drive
- Search one selected folder
- Quick search common photo locations such as Pictures, Desktop, Downloads, OneDrive Pictures, DCIM, Photos, and Camera folders

Recognized formats include common images and many camera formats:

- JPG / JPEG
- PNG
- HEIC / HEIF
- WEBP
- AVIF
- TIFF
- BMP / GIF
- DNG
- Canon CR2 / CR3
- Nikon NEF / NRW
- Sony ARW / SR2 / SRF
- Fujifilm RAF
- Olympus ORF
- Panasonic RW2
- Pentax PEF
- Samsung SRW
- and additional RAW formats

Search results are written to a CSV report.

When backup is selected, the program **copies** the discovered photos to a new dated folder on the **current Windows user's Desktop**. It preserves the source-drive/folder structure inside the backup so same-named photos from different folders do not overwrite each other.

Original files are never moved or deleted.

Each backup includes `Photo-Backup-Manifest.csv`, which records the source path, destination path, file size, modified time, and copy status.


## External Drive Health / Diagnosis

Version 2.9.0 adds read-only-first diagnostics for external HDDs, SSDs, USB storage, and storage attached through USB enclosures/adapters.

The tool can inspect:

- Whether Windows detects the external disk at all
- USB/bus type
- Disk capacity
- Online/offline state
- Read-only state
- Partition style
- Partitions and volumes
- Windows-readable filesystem
- RAW/unknown filesystem states
- Disk and volume health status
- PhysicalDisk health where exposed
- Storage reliability / SMART-style counters where the USB enclosure exposes them
- Read/write error counters
- Temperature and power-on hours where available
- Plug-and-Play storage devices when no disk is exposed

The diagnostic output tries to distinguish likely categories such as:

- cable / power / enclosure or USB-to-SATA bridge problem
- disk visible but no usable media
- disk offline
- missing or damaged partition table
- RAW filesystem
- unsupported filesystem such as APFS/HFS+ or Linux filesystems
- SMART/reliability warning
- no SMART pass-through through the current USB enclosure

The program does not automatically initialize, format, repair, or erase a drive.

If Windows asks to format an unfamiliar external drive and the data matters, choose **Cancel** until the filesystem and drive health are understood.


## Apple / Mac External Drive Reader & Rescue

Version 3.0.0 adds a dedicated workflow for external drives that were used or
formatted on a Mac.

The module can:

- Detect attached external disks
- Identify known GPT APFS and HFS/HFS+ partition type GUIDs
- Distinguish Windows-readable volumes such as exFAT from Apple partitions
- Warn when an Apple partition is visible but Windows has not mounted it
- Reuse External Drive Health / Diagnosis
- Open a readable external volume
- Launch Deep File Search for accessible external files
- Launch Drive Photo Search / Desktop Backup
- Launch Project / Code Search
- Make a copy-only backup of an entire readable external volume to the current user's Desktop
- Check installed Windows software for likely APFS/HFS filesystem support
- Open Disk Management

### Safety

The Apple-drive workflow does not automatically initialize, format, erase, or
repair the source drive.

If Windows asks to format an external Mac drive and its data matters, choose
Cancel.

A drive that is physically detected but has an APFS/HFS partition without a
Windows drive letter may require a compatible filesystem reader/driver or a Mac
before its files can be browsed. PC Maintenance does not bundle proprietary
filesystem drivers.

### Full-volume backup

When a readable external drive has a Windows drive letter, the program can use
Robocopy to create a dated copy-only backup on the Desktop.

The backup uses conservative retry settings and writes a Robocopy log into the
backup folder. Original source files are not moved or deleted.
