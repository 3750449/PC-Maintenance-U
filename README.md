# PC Maintenance U

Portable Windows maintenance, diagnostics, file conversion, Publisher rescue, and lost-file search utility.

Current version: **2.6.0**

## Run

Download/extract the folder and double-click:

`Run-PC-Maintenance.bat`

No Git installation is required on the client computer.

## Main menu

1. Scan Only
2. Standard Maintenance
3. Full Maintenance
4. Check for Program Updates
5. File Conversion
6. Deep File Search / Lost File Finder
7. Exit

## Automatic updates

The launcher checks the public GitHub repository before every run:

`https://github.com/3750449/PC-Maintenance-U`

The updater compares `version.txt`, downloads the repository ZIP when a newer
version exists, validates the required files and PowerShell syntax, backs up the
current program files, and installs the newer version.

## Microsoft Publisher rescue

Version 2.6.0 adds dedicated `.pub` support.

Under **File Conversion -> Microsoft Publisher Rescue**:

- Convert one Publisher `.pub` file to PDF.
- Convert `.pub` to XPS when Microsoft Publisher is installed.
- Create a best-effort editable DOCX copy through PDF + Microsoft Word.
- Batch convert all `.pub` files in a selected folder, optionally including subfolders, to PDF.

Conversion order is conservative:

1. Microsoft Publisher automation is used when a working installed Publisher is available.
2. For PDF/ODG, LibreOffice can be used as a fallback for Publisher formats its import filter supports.
3. DOCX is a best-effort rescue conversion through PDF and can change complex layouts.

The original `.pub` source is not modified.

## Publisher file finder

Under **Deep File Search / Lost File Finder** choose:

**Find Microsoft Publisher Files (.pub)**

It can search:

- the current Windows user profile,
- all accessible fixed/removable/network filesystem drives,
- or one selected folder.

This is useful for locating old Publisher files before converting or archiving them.

## General file conversion

The conversion system chooses an available engine based on the input and output
format.

Built-in capabilities include:

- JPG/JPEG/PNG/BMP/GIF/TIFF image conversion
- CSV to JSON
- JSON to CSV
- text-like formats to UTF-8 TXT
- Microsoft Word/Excel/PowerPoint to PDF when the corresponding Office app is installed

Optional installed engines are detected automatically:

- **FFmpeg** for broad audio/video formats
- **ImageMagick** for additional image formats
- **LibreOffice** for additional office-document formats and supported Publisher imports
- **Pandoc** for document/markup formats
- **7-Zip** for common archive formats and repacking to ZIP

This intentionally does not claim that arbitrary unrelated/proprietary file
formats can always be converted. If a safe engine is unavailable, the source
file is not changed.

## Deep File Search / Lost File Finder

The search tool is designed for hard-to-find or accidentally moved files.

Features include:

- Partial-name search
- Wildcards
- Fuzzy filename similarity ranking
- Old path/old filename clues
- Extension filters
- Minimum/maximum size filters
- Approximate-size ranking
- Modified-date filtering
- Recently modified file search
- Dedicated Microsoft Publisher `.pub` search
- User-folder search
- Deep all-drive search
- Hidden-file traversal
- Reparse-point loop avoidance
- CSV result reports
- Direct Explorer reveal for selected results

A deep all-drive search can take time on very large disks because it actually
walks accessible folders rather than pretending every location is indexed.

## Publishing an update

Keep these two versions synchronized:

`$AppVersion = [version]"2.6.0"` in `PC-Maintenance.ps1`

and:

`version.txt`

For a later release, for example 2.7.0, change both to `2.7.0`, test the files,
then commit/push them to the root of the `main` branch.

## Required repository-root files

- `PC-Maintenance.ps1`
- `Run-PC-Maintenance.bat`
- `Update-PC-Maintenance.ps1`
- `version.txt`

Documentation files are optional but recommended.
