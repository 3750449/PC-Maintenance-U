# Windows PC Maintenance

Portable Windows maintenance and diagnostics utility written in PowerShell.

## End-user use
- **Portable:** double-click `Run-PC-Maintenance.bat`.
- **Install:** double-click `Install-PC-Maintenance.bat`; it installs per-user under `%LOCALAPPDATA%\DesmondPCMaintenance` and creates a Desktop shortcut.
- **Update:** start the program and select **4 - Check for Program Updates**.

## GitHub updater
The included `update-config.json` points to `3750449/Windows-PC-Maintenance` on branch `main`.
The repository must be public for unattended family-member updates without GitHub credentials.

To publish an update, increment the embedded `$AppVersion` in `PC-Maintenance.ps1`, update `version.txt` to the same value, then commit/push the changed files. The updater downloads the branch archive, validates required files and PowerShell syntax, backs up the installed program files, and replaces the program files.

## Data location
Reports and program backups are stored in the current user's Documents folder under `Desmond-PC-Maintenance`, so the program itself can run from a USB drive or any folder.
