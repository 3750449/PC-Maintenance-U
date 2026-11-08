# PC Maintenance U

Portable Windows maintenance, diagnostics, malware scanning, file search, conversion, drive rescue, backup, Linux/WSL maintenance, and support tooling.

**Current version: 3.2.0**

Repository:

`https://github.com/3750449/PC-Maintenance-U`

---

## What this project is

PC Maintenance U is a portable PowerShell-based Windows maintenance utility designed to be usable on multiple computers without requiring Git, GitHub Desktop, Visual Studio Code, or a traditional installer.

The normal user workflow is:

1. Download the ZIP.
2. Extract it.
3. Open the folder.
4. Double-click `Run-PC-Maintenance.bat`.
5. Approve the Windows UAC prompt.
6. Choose a tool from the grouped menu.

The application can also automatically check GitHub for newer releases when it starts.

---

# Main Menu

Version 3.2.0 uses grouped menus instead of one long list.

```text
============================================================
          DESMOND PC MAINTENANCE 3.2.0
============================================================

1 - Recommended Safe Scan
2 - System Health & Maintenance
3 - Security & Malware Sweep
4 - Files, Search & Conversion
5 - Drives, Photos & Backup
6 - Developer & Linux Tools
7 - Speech & Accessibility
8 - Program Updates
9 - Exit
```

This keeps common tools simple while advanced tools remain available in logical categories.

---

# 1. Recommended Safe Scan

The recommended option is intended for normal users who want a general health check without navigating advanced tools.

It performs diagnostic checks and creates reports without intentionally performing destructive operations.

Typical checks include:

- Windows system information
- Storage and disk health
- Temporary/junk file analysis
- Startup applications
- Resource-heavy processes
- Broken shortcuts
- MuiCache checks
- SharedDLL checks
- DISM health scan
- SFC verification
- Windows Update detection
- Application update detection
- Windows Security status
- Firewall status
- Network diagnostics
- Battery report

---

# 2. System Health & Maintenance

This group contains:

```text
1 - Scan Only
2 - Standard Maintenance
3 - Full Maintenance
4 - Return
```

## Scan Only

Performs diagnostics and reporting without intentionally performing repairs or cleanup.

## Standard Maintenance

Adds Windows repair and optional safe cleanup actions.

Examples:

- `DISM /RestoreHealth`
- `sfc /scannow`
- temporary-file cleanup
- Recycle Bin cleanup
- broken shortcut cleanup
- safe MuiCache cleanup
- firewall repair when needed

## Full Maintenance

Adds more advanced optional actions such as:

- component-store cleanup
- optional SharedDLL cleanup after backup
- application updates through `winget`
- optional Defender Quick Scan

---

# 3. Security & Malware Sweep

The Malware Sweep module is designed to use Microsoft's current Defender infrastructure rather than maintaining its own static malware signature list.

Menu:

```text
1 - Security / antivirus status
2 - Update Defender security intelligence now
3 - Quick Malware Sweep
4 - Full Malware Sweep
5 - Custom Folder Malware Sweep
6 - Recent Defender threat detections
7 - Microsoft Defender Offline Scan
8 - Fresh Microsoft Safety Scanner
9 - Apply recommended Defender scan settings
10 - Open Windows Security
11 - Return
```

## Defender intelligence refresh

Before Quick, Full, and Custom Defender scans, PC Maintenance attempts to refresh Microsoft Defender security intelligence.

The program displays:

- Defender status
- signature version
- signature last-update time
- engine version
- product/platform version
- real-time protection state
- behavior monitoring state
- cloud/MAPS-related settings where available
- potentially unwanted application protection status

## Quick Malware Sweep

Runs a Microsoft Defender Quick Scan after attempting to update signatures.

## Full Malware Sweep

Runs a full Microsoft Defender scan after attempting to update signatures.

This can take a long time on large systems.

## Custom Folder Malware Sweep

Lets the user select a specific folder using a Windows folder picker, then scans that folder with Microsoft Defender.

## Defender Offline Scan

Can launch Microsoft Defender Offline Scan.

This restarts the computer and scans outside the normal Windows session.

The user is warned to save work before continuing.

## Fresh Microsoft Safety Scanner

PC Maintenance can download a fresh copy of Microsoft's Safety Scanner directly from Microsoft's official download endpoint.

Before running it, PC Maintenance verifies the downloaded executable's Microsoft Authenticode signature.

The temporary scanner copy is deleted afterward so a future run downloads a fresh copy.

## Important malware limitation

No antivirus can guarantee detection of every:

- zero-day threat
- custom malware sample
- fileless attack
- firmware-level threat
- new threat that has not yet been identified

PC Maintenance keeps Defender as current as the available Microsoft update and cloud infrastructure allows, but it does not claim perfect malware detection.

---

# 4. Files, Search & Conversion

This group contains:

```text
1 - File Conversion / Publisher Rescue
2 - Deep File Search / Lost File Finder
3 - Return
```

---

## File Conversion

The converter uses the best available conversion engine on the current computer.

Built-in support includes:

- JPG / JPEG / PNG / BMP / GIF / TIFF image conversion
- CSV to JSON
- JSON to CSV
- text-like files to UTF-8 TXT
- Microsoft Office documents to PDF when Office is installed

Optional conversion engines are detected automatically:

- FFmpeg
- ImageMagick
- LibreOffice
- Pandoc
- 7-Zip

These can expand support to many more formats.

Examples may include:

- PNG -> JPG
- HEIC -> PNG
- WEBP -> JPG
- MP4 -> MP3
- MOV -> MP4
- WAV -> MP3
- DOCX -> PDF
- ODT -> DOCX
- PPTX -> PDF
- CSV -> JSON
- JSON -> CSV
- RAR -> ZIP
- 7Z -> ZIP

No converter can meaningfully convert every possible file type into every other file type.

Unsupported or unsafe conversions are refused rather than forcing a destructive conversion.

---

## Microsoft Publisher Rescue

Publisher support includes:

- `.pub` file search
- `.pub -> PDF`
- `.pub -> XPS` when Microsoft Publisher is available
- best-effort `.pub -> DOCX`
- batch conversion of Publisher files
- optional recursive folder processing
- conversion reporting

Original `.pub` files are left untouched.

The conversion system can use Microsoft Publisher when installed and may use LibreOffice as a fallback for supported Publisher formats.

---

## Deep File Search / Lost File Finder

Designed for files that were:

- accidentally moved
- renamed
- placed in the wrong folder
- copied to another drive
- buried in an old backup

Search capabilities include:

- exact filename
- partial filename
- wildcard search
- fuzzy/approximate filename matching
- old path clues
- extension filters
- minimum size
- maximum size
- approximate size ranking
- modified-date filters
- recent-file search
- user-folder search
- selected-folder search
- all-drive search
- hidden-file traversal
- CSV result reports
- Explorer reveal for selected files

The tool searches existing files.

It is not deleted-file recovery software.

---

# 5. Drives, Photos & Backup

This group contains:

```text
1 - Drive Photo Search / Desktop Backup
2 - External Drive Health / Diagnosis
3 - Apple / Mac External Drive Reader & Rescue
4 - Return
```

---

## Drive Photo Search / Desktop Backup

Can scan:

- internal drives
- USB drives
- external HDDs
- external SSDs
- accessible network drives
- selected folders
- common photo folders

Recognized formats include:

- JPG / JPEG
- PNG
- HEIC / HEIF
- WEBP
- AVIF
- TIFF
- BMP
- GIF
- DNG
- CR2 / CR3
- NEF / NRW
- ARW
- RAF
- ORF
- RW2
- PEF
- SRW
- additional RAW formats

Search results are saved to CSV.

If backup is selected, files are **copied** to a dated Desktop backup folder.

Original files are not moved or deleted.

A backup manifest records:

- source path
- destination path
- file size
- modified time
- copy status

---

## External Drive Health / Diagnosis

Designed for:

- external HDDs
- external SSDs
- USB flash drives
- SATA-to-USB adapters
- USB drive enclosures

The diagnostic workflow is read-only by default.

It can check:

- whether Windows detects the disk
- USB/bus type
- capacity
- online/offline state
- read-only state
- partition style
- partitions
- volumes
- filesystem
- RAW filesystem state
- disk health
- volume health
- SMART/reliability data where exposed
- temperature
- power-on hours
- read/write error counters
- Plug-and-Play storage devices

Possible diagnostic categories include:

- bad cable
- insufficient power
- failing USB enclosure
- failing USB-to-SATA bridge
- drive visible but no media
- disk offline
- damaged partition table
- RAW filesystem
- unsupported filesystem
- SMART warning
- missing SMART pass-through

Some USB bridges do not expose SMART data.

Lack of SMART data does not prove that a drive is healthy.

If Windows asks to format an unfamiliar drive containing important data, choose **Cancel** until the drive's condition and filesystem are understood.

---

## Apple / Mac External Drive Reader & Rescue

Designed for external drives originally used on macOS.

It can:

- detect external disks
- identify known APFS partition type GUIDs
- identify HFS/HFS+ partition type GUIDs
- identify Windows-readable exFAT/FAT/NTFS volumes
- reuse External Drive Health diagnostics
- open readable external volumes
- run lost-file searches
- run photo searches
- run code/project searches
- create copy-only Desktop backups
- check for installed APFS/HFS Windows filesystem software
- open Windows Disk Management

PC Maintenance does **not** automatically:

- initialize the drive
- format the drive
- erase the drive
- repair the drive

If Windows detects an APFS/HFS partition but does not mount it with a drive letter, a compatible filesystem reader/driver or a Mac may be required before files can be browsed.

PC Maintenance does not bundle proprietary APFS/HFS filesystem drivers.

---

# 6. Developer & Linux Tools

This group contains:

```text
1 - Project / Code Search
2 - WSL / Linux Terminal Maintenance
3 - Return
```

---

## Project / Code Search

Designed for finding old programming projects even when the project was moved or renamed.

Search clues can include:

- project name
- folder name
- filename
- source filename
- libraries
- imports
- `#include` statements
- function names
- class names
- README text
- comments
- code purpose keywords
- programming language
- old folder origin
- previous path

Recognized project markers include:

- `.git`
- `CMakeLists.txt`
- `Makefile`
- `package.json`
- `requirements.txt`
- `pyproject.toml`
- `Cargo.toml`
- `pom.xml`
- `build.gradle`
- `Dockerfile`
- `docker-compose.yml`
- `README.md`
- Visual Studio solution/project files

The tool attempts to group files into likely project roots rather than only listing individual source files.

Results can be ranked and saved to CSV.

---

## WSL / Linux Terminal Maintenance

Can detect installed WSL distributions and supported package managers.

Supported package-management workflows include:

- `apt`
- `dnf`
- `yum`
- `pacman`
- `zypper`

Features include:

- show WSL status
- list installed distributions
- check package updates
- update a selected Linux distribution
- update WSL itself
- open a selected Linux terminal

Linux authentication is not bypassed.

If `sudo` requires a password, the user must enter it normally.

---

# 7. Speech & Accessibility

This group includes both speech tools and display/accessibility controls.

## Font Size Changer

PC Maintenance can change its own console font size without intentionally changing the system-wide Windows display scale.

Available presets:

- Small: 14
- Normal: 16
- Large: 20
- Extra Large: 24
- Huge: 30
- Custom: 10 through 40

The selected size is stored in `settings.json` next to the program and is applied on future launches.

Some Windows Terminal configurations control font size independently and may not allow the classic console API to resize the active terminal. For those systems, PC Maintenance includes a shortcut to Windows Text Size settings.

The font-size menu also includes a reset to the Normal size.

## Speech Listener

The speech listener can:

- list Windows audio endpoints
- use the current default recording device
- listen for 15 seconds
- listen for 30 seconds
- listen for 60 seconds
- work with built-in microphones
- work with USB microphones
- work with wired headsets
- work with Bluetooth headsets where Windows exposes them as the active input
- save recognized speech to a local CSV transcript
- open Windows Sound settings

The speech listener is opt-in.

It does not run as a hidden permanent microphone listener.

---

# 8. Program Updates

PC Maintenance supports automatic updates from:

`https://github.com/3750449/PC-Maintenance-U`

The launcher can check GitHub before the program starts.

Update flow:

```text
Start PC Maintenance
        |
        v
Check GitHub version
        |
        v
Newer version?
   /          \
 Yes          No
  |            |
  v            v
Download      Continue
  |
  v
Validate required files
  |
  v
Syntax-check PowerShell
  |
  v
Back up current version
  |
  v
Install newer version
  |
  v
Restart / continue
```

Client computers do **not** need Git installed.

They do not need:

- Git
- GitHub Desktop
- VS Code
- a GitHub account

For simple family use, the GitHub repository should remain public.

---

# Publishing an Update

Keep these two version values synchronized.

Inside `PC-Maintenance.ps1`:

```powershell
$AppVersion = [version]"3.1.0"
```

Inside `version.txt`:

```text
3.1.0
```

For a future release, for example `3.2.0`:

1. Change `$AppVersion` to `3.2.0`.
2. Change `version.txt` to `3.2.0`.
3. Test the scripts.
4. Commit/push the new files to the root of the `main` branch.
5. Existing auto-update installations can retrieve the new release.

---

# Required Repository Files

The repository root should contain:

```text
PC-Maintenance.ps1
Run-PC-Maintenance.bat
Update-PC-Maintenance.ps1
version.txt
README.md
START-HERE.txt
```

The first four are required for normal operation and updating.

---

# Reports and Backups

PC Maintenance creates reports and backups locally.

Depending on the tool, output may include:

- maintenance summary CSV
- PowerShell transcript log
- startup-app report
- heavy-process report
- Windows Update report
- `winget` update report
- broken-shortcut report
- MuiCache report
- SharedDLL report
- network report
- battery report
- project search results
- lost-file search results
- photo search results
- photo backup manifest
- external-drive diagnostic report
- Publisher conversion reports
- speech transcripts

---

# Safety Design

PC Maintenance intentionally favors inspection, reporting, backup, and confirmation before destructive actions.

Examples:

- registry changes are backed up first
- broken shortcuts are backed up before removal
- photo backups copy instead of move
- external-drive diagnosis is read-only by default
- Apple/Mac drive tools do not format disks
- malware scans refresh available Defender intelligence first
- downloaded Microsoft Safety Scanner binaries are signature-checked
- updater validates PowerShell syntax before replacing the working copy

No system-maintenance utility can remove all risk.

Important files should always have independent backups.

---

# Intended Use

PC Maintenance U is useful for:

- personal Windows maintenance
- family computer support
- help-desk style diagnostics
- finding lost files
- recovering access to old project folders
- checking old external drives
- backing up photos
- working with old Mac-formatted external drives
- Publisher document rescue
- Windows/WSL maintenance
- malware sweeps
- generating troubleshooting reports

The project is intended to remain portable and easy to run from a normal extracted folder.


---

# Version 3.2.0 - Font Size / Accessibility Update

Version 3.2.0 adds a persistent PC Maintenance font-size changer under
**Speech & Accessibility**.

Features:

- Small, Normal, Large, Extra Large, and Huge presets
- Custom size from 10 through 40
- Reset to Normal
- Saves the preference in `settings.json`
- Applies the saved size on later launches
- Shortcut to Windows Text Size settings
- Does not intentionally change system-wide display scaling

The setting file is user-generated and does not need to be committed to GitHub.
