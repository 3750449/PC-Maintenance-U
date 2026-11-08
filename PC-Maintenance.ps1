#requires -Version 5.1

$ErrorActionPreference = "Continue"
$AppVersion = [version]"3.0.0"
$AppDirectory = Split-Path -Parent $PSCommandPath

function Test-IsAdministrator {
    $principal = New-Object Security.Principal.WindowsPrincipal(
        [Security.Principal.WindowsIdentity]::GetCurrent()
    )
    return $principal.IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )
}

if (-not (Test-IsAdministrator)) {
    Start-Process powershell.exe -Verb RunAs -ArgumentList @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", "`"$PSCommandPath`""
    )
    exit
}

try { $Host.UI.RawUI.WindowTitle = "Desmond PC Maintenance $AppVersion" } catch {}

$Desktop = [Environment]::GetFolderPath("Desktop")
$Root = Join-Path $Desktop "Desmond-PC-Maintenance"
$Reports = Join-Path $Root "Reports"
$Backups = Join-Path $Root "Backups"
New-Item -ItemType Directory -Path $Reports -Force | Out-Null
New-Item -ItemType Directory -Path $Backups -Force | Out-Null

$Stamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$LogPath = Join-Path $Reports "Maintenance-$Stamp.log"
$SummaryPath = Join-Path $Reports "Maintenance-Summary-$Stamp.csv"

try { Start-Transcript -Path $LogPath -Append | Out-Null } catch {}

$script:Results = @()

function Add-Result {
    param(
        [string]$Component,
        [string]$Status,
        [string]$Details
    )
    $script:Results += [PSCustomObject]@{
        Component = $Component
        Status    = $Status
        Details   = $Details
    }
}

function Write-Section {
    param([string]$Title)
    Write-Host ""
    Write-Host "============================================================"
    Write-Host $Title
    Write-Host "============================================================"
    Write-Host ""
}

function Confirm-Action {
    param([string]$Message)
    $answer = Read-Host "$Message [y/N]"
    return ($answer -match '^[Yy]$')
}

function Format-Bytes {
    param([long]$Bytes)

    if ($Bytes -ge 1TB) { return "{0:N2} TB" -f ($Bytes / 1TB) }
    if ($Bytes -ge 1GB) { return "{0:N2} GB" -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return "{0:N2} MB" -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return "{0:N2} KB" -f ($Bytes / 1KB) }
    return "$Bytes bytes"
}

function Get-FolderSizeBytes {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) { return 0 }

    try {
        $sum = (
            Get-ChildItem -LiteralPath $Path -Force -Recurse -File -ErrorAction SilentlyContinue |
            Measure-Object -Property Length -Sum
        ).Sum

        if ($null -eq $sum) { return 0 }
        return [long]$sum
    }
    catch {
        return 0
    }
}

function Clear-FolderContents {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) { return }

    Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue |
        Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
}


# ============================================================
# FILE CONVERSION
# ============================================================

function Get-OptionalToolPath {
    param(
        [string[]]$CommandNames,
        [string[]]$KnownPaths = @()
    )

    foreach ($Name in $CommandNames) {
        try {
            $Command = Get-Command $Name -ErrorAction SilentlyContinue
            if ($null -ne $Command) {
                return $Command.Source
            }
        }
        catch {}
    }

    foreach ($Path in $KnownPaths) {
        if ([string]::IsNullOrWhiteSpace($Path)) {
            continue
        }

        if ($Path.Contains("*")) {
            try {
                $Match = Get-ChildItem -Path $Path -File -ErrorAction SilentlyContinue |
                    Select-Object -First 1

                if ($null -ne $Match) {
                    return $Match.FullName
                }
            }
            catch {}
        }
        elseif (Test-Path -LiteralPath $Path) {
            return $Path
        }
    }

    return $null
}


function Get-UniqueOutputPath {
    param(
        [string]$InputPath,
        [string]$OutputExtension
    )

    $Folder = [IO.Path]::GetDirectoryName($InputPath)
    $Base = [IO.Path]::GetFileNameWithoutExtension($InputPath)
    $CleanExtension = $OutputExtension.Trim().TrimStart(".").ToLowerInvariant()

    $Candidate = Join-Path $Folder "$Base-converted.$CleanExtension"

    if (-not (Test-Path -LiteralPath $Candidate)) {
        return $Candidate
    }

    $Counter = 2

    while ($true) {
        $Candidate = Join-Path $Folder "$Base-converted-$Counter.$CleanExtension"

        if (-not (Test-Path -LiteralPath $Candidate)) {
            return $Candidate
        }

        $Counter++
    }
}


function Show-FileConversionMenu {

    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        Add-Type -AssemblyName System.Drawing -ErrorAction Stop
    }
    catch {
        Write-Host ""
        Write-Warning "Windows file-picker components could not be loaded."
        Read-Host "Press Enter to return"
        return
    }

    function Select-InputFile {
        $Dialog = New-Object System.Windows.Forms.OpenFileDialog
        $Dialog.Title = "Choose a file to convert"
        $Dialog.Filter = "All files (*.*)|*.*"
        $Dialog.Multiselect = $false
        $Dialog.CheckFileExists = $true

        if ($Dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            return $Dialog.FileName
        }

        return $null
    }

    function Convert-WithSystemDrawing {
        param(
            [string]$InputPath,
            [string]$OutputPath
        )

        $OutputExtension = [IO.Path]::GetExtension($OutputPath).TrimStart(".").ToLowerInvariant()
        $Image = $null

        try {
            $Image = [System.Drawing.Image]::FromFile($InputPath)

            switch ($OutputExtension) {
                "jpg"  { $Format = [System.Drawing.Imaging.ImageFormat]::Jpeg }
                "jpeg" { $Format = [System.Drawing.Imaging.ImageFormat]::Jpeg }
                "png"  { $Format = [System.Drawing.Imaging.ImageFormat]::Png }
                "bmp"  { $Format = [System.Drawing.Imaging.ImageFormat]::Bmp }
                "gif"  { $Format = [System.Drawing.Imaging.ImageFormat]::Gif }
                "tif"  { $Format = [System.Drawing.Imaging.ImageFormat]::Tiff }
                "tiff" { $Format = [System.Drawing.Imaging.ImageFormat]::Tiff }
                default { return $false }
            }

            $Image.Save($OutputPath, $Format)
            return $true
        }
        catch {
            return $false
        }
        finally {
            if ($null -ne $Image) {
                $Image.Dispose()
            }
        }
    }

    function Convert-OfficeToPdf {
        param(
            [string]$InputPath,
            [string]$OutputPath
        )

        $Extension = [IO.Path]::GetExtension($InputPath).TrimStart(".").ToLowerInvariant()

        if ($Extension -in @("doc","docx","rtf")) {
            $Word = $null
            $Document = $null

            try {
                $Word = New-Object -ComObject Word.Application
                $Word.Visible = $false
                $Word.DisplayAlerts = 0
                $Document = $Word.Documents.Open($InputPath, $false, $true)
                $Document.ExportAsFixedFormat($OutputPath, 17)
                return $true
            }
            catch {
                return $false
            }
            finally {
                if ($null -ne $Document) {
                    try { $Document.Close($false) } catch {}
                    try { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($Document) } catch {}
                }

                if ($null -ne $Word) {
                    try { $Word.Quit() } catch {}
                    try { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($Word) } catch {}
                }

                [GC]::Collect()
                [GC]::WaitForPendingFinalizers()
            }
        }

        if ($Extension -in @("xls","xlsx","xlsm","csv")) {
            $Excel = $null
            $Workbook = $null

            try {
                $Excel = New-Object -ComObject Excel.Application
                $Excel.Visible = $false
                $Excel.DisplayAlerts = $false
                $Workbook = $Excel.Workbooks.Open($InputPath)
                $Workbook.ExportAsFixedFormat(0, $OutputPath)
                return $true
            }
            catch {
                return $false
            }
            finally {
                if ($null -ne $Workbook) {
                    try { $Workbook.Close($false) } catch {}
                    try { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($Workbook) } catch {}
                }

                if ($null -ne $Excel) {
                    try { $Excel.Quit() } catch {}
                    try { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($Excel) } catch {}
                }

                [GC]::Collect()
                [GC]::WaitForPendingFinalizers()
            }
        }

        if ($Extension -in @("ppt","pptx","pptm")) {
            $PowerPoint = $null
            $Presentation = $null

            try {
                $PowerPoint = New-Object -ComObject PowerPoint.Application
                $Presentation = $PowerPoint.Presentations.Open($InputPath, $true, $false, $false)
                $Presentation.SaveAs($OutputPath, 32)
                return $true
            }
            catch {
                return $false
            }
            finally {
                if ($null -ne $Presentation) {
                    try { $Presentation.Close() } catch {}
                    try { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($Presentation) } catch {}
                }

                if ($null -ne $PowerPoint) {
                    try { $PowerPoint.Quit() } catch {}
                    try { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($PowerPoint) } catch {}
                }

                [GC]::Collect()
                [GC]::WaitForPendingFinalizers()
            }
        }

        return $false
    }

    function Convert-PublisherToFixedFormat {
        param(
            [string]$InputPath,
            [string]$OutputPath
        )

        $OutputExtension = [IO.Path]::GetExtension($OutputPath).TrimStart(".").ToLowerInvariant()

        if ($OutputExtension -eq "pdf") {
            $FixedFormatType = 2
        }
        elseif ($OutputExtension -eq "xps") {
            $FixedFormatType = 1
        }
        else {
            return $false
        }

        $Publisher = $null
        $Publication = $null

        try {
            $Publisher = New-Object -ComObject Publisher.Application
            $Publication = $Publisher.Open($InputPath, $true, $false)

            if ($null -eq $Publication) {
                $Publication = $Publisher.ActiveDocument
            }

            $Publication.ExportAsFixedFormat($FixedFormatType, $OutputPath)
            return (Test-Path -LiteralPath $OutputPath)
        }
        catch {
            return $false
        }
        finally {
            if ($null -ne $Publication) {
                try { $Publication.Close() } catch {}
                try { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($Publication) } catch {}
            }

            if ($null -ne $Publisher) {
                try { $Publisher.Quit() } catch {}
                try { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($Publisher) } catch {}
            }

            [GC]::Collect()
            [GC]::WaitForPendingFinalizers()
        }
    }

    function Convert-PublisherWithLibreOffice {
        param(
            [string]$InputPath,
            [string]$OutputPath,
            [string]$LibreOfficePath
        )

        if ([string]::IsNullOrWhiteSpace($LibreOfficePath)) {
            return $false
        }

        $OutputExtension = [IO.Path]::GetExtension($OutputPath).TrimStart(".").ToLowerInvariant()

        if ($OutputExtension -notin @("pdf","odg")) {
            return $false
        }

        try {
            $OutputFolder = [IO.Path]::GetDirectoryName($OutputPath)
            $ExpectedOutput = Join-Path $OutputFolder (
                [IO.Path]::GetFileNameWithoutExtension($InputPath) + "." + $OutputExtension
            )

            & $LibreOfficePath `
                --headless `
                --convert-to $OutputExtension `
                --outdir "$OutputFolder" `
                "$InputPath" | Out-Null

            if (Test-Path -LiteralPath $ExpectedOutput) {
                if ($ExpectedOutput -ne $OutputPath) {
                    Move-Item -LiteralPath $ExpectedOutput -Destination $OutputPath -Force
                }

                return $true
            }
        }
        catch {}

        return $false
    }

    function Convert-PublisherToDocx {
        param(
            [string]$InputPath,
            [string]$OutputPath,
            [string]$LibreOfficePath
        )

        $TemporaryPdf = Join-Path $env:TEMP (
            "Publisher-Rescue-" + [guid]::NewGuid().ToString() + ".pdf"
        )

        $Word = $null
        $Document = $null

        try {
            $MadePdf = Convert-PublisherToFixedFormat $InputPath $TemporaryPdf

            if (-not $MadePdf) {
                $MadePdf = Convert-PublisherWithLibreOffice $InputPath $TemporaryPdf $LibreOfficePath
            }

            if (-not $MadePdf) {
                return $false
            }

            $Word = New-Object -ComObject Word.Application
            $Word.Visible = $false
            $Word.DisplayAlerts = 0
            $Document = $Word.Documents.Open($TemporaryPdf, $false, $true)
            $Document.SaveAs2($OutputPath, 16)

            return (Test-Path -LiteralPath $OutputPath)
        }
        catch {
            return $false
        }
        finally {
            if ($null -ne $Document) {
                try { $Document.Close($false) } catch {}
                try { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($Document) } catch {}
            }

            if ($null -ne $Word) {
                try { $Word.Quit() } catch {}
                try { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($Word) } catch {}
            }

            Remove-Item -LiteralPath $TemporaryPdf -Force -ErrorAction SilentlyContinue

            [GC]::Collect()
            [GC]::WaitForPendingFinalizers()
        }
    }

    function Convert-PublisherBatchToPdf {
        param(
            [string]$FolderPath,
            [bool]$Recurse,
            [string]$LibreOfficePath
        )

        $PublisherFiles = @()

        try {
            if ($Recurse) {
                $PublisherFiles = @(
                    Get-ChildItem -LiteralPath $FolderPath -Filter "*.pub" -File -Recurse -Force -ErrorAction SilentlyContinue
                )
            }
            else {
                $PublisherFiles = @(
                    Get-ChildItem -LiteralPath $FolderPath -Filter "*.pub" -File -Force -ErrorAction SilentlyContinue
                )
            }
        }
        catch {
            return
        }

        Write-Host ""
        Write-Host "Publisher files found: $($PublisherFiles.Count)"

        if ($PublisherFiles.Count -eq 0) {
            return
        }

        $ExportRoot = Join-Path $Desktop (
            "Publisher-PDF-Exports-" + (Get-Date -Format "yyyy-MM-dd_HH-mm-ss")
        )

        New-Item -ItemType Directory -Path $ExportRoot -Force | Out-Null

        $BatchResults = @()
        $ConvertedCount = 0
        $FailedCount = 0

        for ($Index = 0; $Index -lt $PublisherFiles.Count; $Index++) {
            $Source = $PublisherFiles[$Index]
            $BaseName = [IO.Path]::GetFileNameWithoutExtension($Source.Name)
            $Destination = Join-Path $ExportRoot "$BaseName.pdf"

            if (Test-Path -LiteralPath $Destination) {
                $Counter = 2

                do {
                    $Destination = Join-Path $ExportRoot "$BaseName-$Counter.pdf"
                    $Counter++
                } while (Test-Path -LiteralPath $Destination)
            }

            Write-Progress `
                -Activity "Publisher rescue conversion" `
                -Status "$($Index + 1) of $($PublisherFiles.Count): $($Source.Name)" `
                -PercentComplete ((($Index + 1) / $PublisherFiles.Count) * 100)

            $Success = Convert-PublisherToFixedFormat $Source.FullName $Destination

            if (-not $Success) {
                $Success = Convert-PublisherWithLibreOffice $Source.FullName $Destination $LibreOfficePath
            }

            if ($Success) {
                $ConvertedCount++
                $Status = "Converted"
            }
            else {
                $FailedCount++
                $Status = "Failed"
            }

            $BatchResults += [PSCustomObject]@{
                Source      = $Source.FullName
                Destination = $Destination
                Status      = $Status
            }
        }

        Write-Progress -Activity "Publisher rescue conversion" -Completed

        $ReportPath = Join-Path $ExportRoot "Publisher-Conversion-Report.csv"
        $BatchResults | Export-Csv -LiteralPath $ReportPath -NoTypeInformation

        Write-Host ""
        Write-Host "Publisher batch conversion complete."
        Write-Host "Converted: $ConvertedCount"
        Write-Host "Failed:    $FailedCount"
        Write-Host ""
        Write-Host "Output folder:"
        Write-Host $ExportRoot
        Write-Host ""
        Write-Host "Report:"
        Write-Host $ReportPath
        Write-Host ""

        if (Confirm-Action "Open the Publisher export folder?") {
            Start-Process explorer.exe "$ExportRoot"
        }
    }

    function Convert-DataFile {
        param(
            [string]$InputPath,
            [string]$OutputPath
        )

        $InputExtension = [IO.Path]::GetExtension($InputPath).TrimStart(".").ToLowerInvariant()
        $OutputExtension = [IO.Path]::GetExtension($OutputPath).TrimStart(".").ToLowerInvariant()

        try {
            if ($InputExtension -eq "csv" -and $OutputExtension -eq "json") {
                Import-Csv -LiteralPath $InputPath |
                    ConvertTo-Json -Depth 20 |
                    Set-Content -LiteralPath $OutputPath -Encoding UTF8

                return $true
            }

            if ($InputExtension -eq "json" -and $OutputExtension -eq "csv") {
                $Objects = Get-Content -LiteralPath $InputPath -Raw |
                    ConvertFrom-Json

                @($Objects) |
                    Export-Csv -LiteralPath $OutputPath -NoTypeInformation

                return $true
            }

            if ($InputExtension -in @("txt","log","md","csv","json","xml","html","htm") -and $OutputExtension -eq "txt") {
                Get-Content -LiteralPath $InputPath -Raw |
                    Set-Content -LiteralPath $OutputPath -Encoding UTF8

                return $true
            }
        }
        catch {
            return $false
        }

        return $false
    }

    function Convert-ArchiveToZip {
        param(
            [string]$InputPath,
            [string]$OutputPath,
            [string]$SevenZipPath
        )

        if ([string]::IsNullOrWhiteSpace($SevenZipPath)) {
            return $false
        }

        $TemporaryFolder = Join-Path $env:TEMP ("PC-Maintenance-Archive-" + [guid]::NewGuid().ToString())

        try {
            New-Item -ItemType Directory -Path $TemporaryFolder -Force | Out-Null

            & $SevenZipPath x "-o$TemporaryFolder" "-y" "$InputPath" | Out-Null

            if ($LASTEXITCODE -ne 0) {
                return $false
            }

            Compress-Archive `
                -Path (Join-Path $TemporaryFolder "*") `
                -DestinationPath $OutputPath `
                -Force

            return (Test-Path -LiteralPath $OutputPath)
        }
        catch {
            return $false
        }
        finally {
            Remove-Item -LiteralPath $TemporaryFolder -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    $FFmpeg = Get-OptionalToolPath `
        @("ffmpeg.exe","ffmpeg") `
        @(
            "$env:ProgramFiles\ffmpeg\bin\ffmpeg.exe",
            "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\*\ffmpeg.exe"
        )

    $ImageMagick = Get-OptionalToolPath `
        @("magick.exe","magick") `
        @(
            "$env:ProgramFiles\ImageMagick-*\magick.exe"
        )

    $LibreOffice = Get-OptionalToolPath `
        @("soffice.exe","soffice") `
        @(
            "$env:ProgramFiles\LibreOffice\program\soffice.exe",
            "${env:ProgramFiles(x86)}\LibreOffice\program\soffice.exe"
        )

    $Pandoc = Get-OptionalToolPath `
        @("pandoc.exe","pandoc") `
        @(
            "$env:LOCALAPPDATA\Pandoc\pandoc.exe",
            "$env:ProgramFiles\Pandoc\pandoc.exe"
        )

    $SevenZip = Get-OptionalToolPath `
        @("7z.exe","7z") `
        @(
            "$env:ProgramFiles\7-Zip\7z.exe",
            "${env:ProgramFiles(x86)}\7-Zip\7z.exe"
        )

    $PublisherAvailable = $false
    $WordAvailable = $false

    try {
        $PublisherAvailable = ($null -ne [type]::GetTypeFromProgID("Publisher.Application"))
    }
    catch {}

    try {
        $WordAvailable = ($null -ne [type]::GetTypeFromProgID("Word.Application"))
    }
    catch {}

    while ($true) {
        Clear-Host
        Write-Host "============================================================"
        Write-Host "                 SMART FILE CONVERSION"
        Write-Host "============================================================"
        Write-Host ""
        Write-Host "This converter handles many common file families."
        Write-Host "No program can safely convert literally every file format."
        Write-Host "Extra installed tools automatically expand what is supported."
        Write-Host ""
        Write-Host "Detected conversion engines:"
        Write-Host "  Windows image engine : Built in"
        Write-Host "  Microsoft Office     : Used automatically when available"
        Write-Host "  Microsoft Publisher  : $PublisherAvailable"
        Write-Host "  FFmpeg               : $([bool]$FFmpeg)"
        Write-Host "  ImageMagick          : $([bool]$ImageMagick)"
        Write-Host "  LibreOffice          : $([bool]$LibreOffice)"
        Write-Host "  Pandoc               : $([bool]$Pandoc)"
        Write-Host "  7-Zip                : $([bool]$SevenZip)"
        Write-Host ""
        Write-Host "1 - Smart Convert Any Supported File"
        Write-Host "2 - Microsoft Publisher Rescue (.pub)"
        Write-Host "3 - Show Supported File Families"
        Write-Host "4 - Back"
        Write-Host ""

        $Choice = Read-Host "Choose 1, 2, 3, or 4"

        if ($Choice -eq "4") {
            return
        }

        if ($Choice -eq "2") {
            while ($true) {
                Clear-Host
                Write-Host "============================================================"
                Write-Host "               MICROSOFT PUBLISHER RESCUE"
                Write-Host "============================================================"
                Write-Host ""
                Write-Host "Publisher files use the .pub extension."
                Write-Host "Microsoft recommends converting old Publisher files for long-term access."
                Write-Host ""
                Write-Host "Microsoft Publisher installed: $PublisherAvailable"
                Write-Host "Microsoft Word installed:      $WordAvailable"
                Write-Host "LibreOffice detected:          $([bool]$LibreOffice)"
                Write-Host ""
                Write-Host "1 - Convert one .pub file to PDF"
                Write-Host "2 - Convert one .pub file to XPS"
                Write-Host "3 - Convert one .pub file to editable DOCX (best effort)"
                Write-Host "4 - Batch convert a folder of .pub files to PDF"
                Write-Host "5 - Back"
                Write-Host ""

                $PublisherChoice = Read-Host "Choose 1, 2, 3, 4, or 5"

                if ($PublisherChoice -eq "5") {
                    break
                }

                if ($PublisherChoice -in @("1","2","3")) {
                    $Dialog = New-Object System.Windows.Forms.OpenFileDialog
                    $Dialog.Title = "Choose a Microsoft Publisher file"
                    $Dialog.Filter = "Microsoft Publisher (*.pub)|*.pub|All files (*.*)|*.*"
                    $Dialog.Multiselect = $false
                    $Dialog.CheckFileExists = $true

                    if ($Dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
                        continue
                    }

                    $PublisherInput = $Dialog.FileName

                    if ($PublisherChoice -eq "1") {
                        $PublisherOutput = Get-UniqueOutputPath $PublisherInput "pdf"
                        $PublisherConverted = Convert-PublisherToFixedFormat $PublisherInput $PublisherOutput

                        if (-not $PublisherConverted) {
                            $PublisherConverted = Convert-PublisherWithLibreOffice $PublisherInput $PublisherOutput $LibreOffice
                        }
                    }
                    elseif ($PublisherChoice -eq "2") {
                        $PublisherOutput = Get-UniqueOutputPath $PublisherInput "xps"
                        $PublisherConverted = Convert-PublisherToFixedFormat $PublisherInput $PublisherOutput
                    }
                    else {
                        $PublisherOutput = Get-UniqueOutputPath $PublisherInput "docx"
                        $PublisherConverted = Convert-PublisherToDocx $PublisherInput $PublisherOutput $LibreOffice
                    }

                    Write-Host ""

                    if ($PublisherConverted) {
                        Write-Host "Publisher conversion complete:"
                        Write-Host $PublisherOutput
                        Write-Host ""

                        if ($PublisherChoice -eq "3") {
                            Write-Host "Note: Publisher to Word is a best-effort conversion."
                            Write-Host "Complex layouts can change because the file passes through PDF."
                            Write-Host ""
                        }

                        if (Confirm-Action "Reveal the converted file in Explorer?") {
                            Start-Process explorer.exe -ArgumentList "/select,`"$PublisherOutput`""
                        }
                    }
                    else {
                        Write-Warning "Publisher conversion failed."
                        Write-Host ""
                        Write-Host "For PDF: install a working Publisher version or LibreOffice."
                        Write-Host "For XPS: Microsoft Publisher is required."
                        Write-Host "For DOCX: Word plus a working PDF conversion path are required."
                        Write-Host "The original .pub file was not changed."
                    }

                    Write-Host ""
                    Read-Host "Press Enter to return to Publisher Rescue"
                    continue
                }

                if ($PublisherChoice -eq "4") {
                    $FolderDialog = New-Object System.Windows.Forms.FolderBrowserDialog
                    $FolderDialog.Description = "Choose a folder containing Publisher .pub files"
                    $FolderDialog.ShowNewFolderButton = $false

                    if ($FolderDialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
                        continue
                    }

                    $RecurseAnswer = Read-Host "Include subfolders? [Y/n]"
                    $Recurse = ($RecurseAnswer -notmatch '^[Nn]$')

                    Convert-PublisherBatchToPdf $FolderDialog.SelectedPath $Recurse $LibreOffice
                    Read-Host "Press Enter to return to Publisher Rescue"
                }
            }

            continue
        }

        if ($Choice -eq "3") {
            Write-Host ""
            Write-Host "Built-in / automatic support:"
            Write-Host "  Images: JPG, JPEG, PNG, BMP, GIF, TIFF"
            Write-Host "  Data: CSV <-> JSON, text-like files -> TXT"
            Write-Host "  Office -> PDF when Word/Excel/PowerPoint is installed"
            Write-Host "  Publisher PUB -> PDF/XPS when Microsoft Publisher is installed"
            Write-Host "  Publisher PUB -> PDF/ODG with LibreOffice (supported Publisher versions)"
            Write-Host "  Publisher PUB -> DOCX best effort through PDF + Microsoft Word"
            Write-Host ""
            Write-Host "With ImageMagick:"
            Write-Host "  Many additional image formats such as WEBP, HEIC, ICO, PDF images"
            Write-Host ""
            Write-Host "With FFmpeg:"
            Write-Host "  Common audio/video formats such as MP3, WAV, FLAC, AAC, M4A,"
            Write-Host "  OGG, OPUS, WMA, MP4, MKV, AVI, MOV, WEBM, M4V and more"
            Write-Host ""
            Write-Host "With LibreOffice:"
            Write-Host "  DOC/DOCX/ODT/RTF, XLS/XLSX/ODS/CSV, PPT/PPTX/ODP and PDF export"
            Write-Host ""
            Write-Host "With Pandoc:"
            Write-Host "  Markdown, HTML, DOCX, ODT, RTF and many text/document formats"
            Write-Host ""
            Write-Host "With 7-Zip:"
            Write-Host "  Repack common archives such as 7Z/RAR/TAR/GZ/BZ2/XZ into ZIP"
            Write-Host ""
            Read-Host "Press Enter to return"
            continue
        }

        if ($Choice -ne "1") {
            continue
        }

        $InputPath = Select-InputFile

        if (-not $InputPath) {
            continue
        }

        $InputExtension = [IO.Path]::GetExtension($InputPath).TrimStart(".").ToLowerInvariant()

        Write-Host ""
        Write-Host "Selected:"
        Write-Host $InputPath
        Write-Host ""
        Write-Host "Enter the output extension you want."
        Write-Host "Examples: pdf, xps, docx, odg, jpg, png, webp, mp3, wav, mp4, mkv, odt, json, csv, zip"
        Write-Host ""

        $OutputExtension = (Read-Host "Output extension").Trim().TrimStart(".").ToLowerInvariant()

        if ([string]::IsNullOrWhiteSpace($OutputExtension)) {
            continue
        }

        if ($OutputExtension -eq $InputExtension) {
            Write-Warning "Input and output extensions are the same."
            Read-Host "Press Enter to return"
            continue
        }

        $OutputPath = Get-UniqueOutputPath $InputPath $OutputExtension
        $Converted = $false

        $BuiltInImages = @("jpg","jpeg","png","bmp","gif","tif","tiff")
        $CommonImages = @("jpg","jpeg","png","bmp","gif","tif","tiff","webp","heic","heif","ico","avif","svg","pdf","psd")
        $AudioVideo = @(
            "mp3","wav","flac","aac","m4a","ogg","opus","wma",
            "mp4","mkv","avi","mov","webm","m4v","mpeg","mpg","ts","mts","m2ts","3gp"
        )
        $OfficeDocuments = @("doc","docx","rtf","odt")
        $OfficeSheets = @("xls","xlsx","xlsm","csv","ods")
        $OfficeSlides = @("ppt","pptx","pptm","odp")
        $PublisherDocuments = @("pub")
        $PandocDocuments = @("md","markdown","html","htm","docx","odt","rtf","txt","epub")
        $Archives = @("zip","7z","rar","tar","gz","bz2","xz","tgz")

        Write-Host ""
        Write-Host "Converting..."

        if (-not $Converted -and $InputExtension -in $BuiltInImages -and $OutputExtension -in $BuiltInImages) {
            $Converted = Convert-WithSystemDrawing $InputPath $OutputPath
        }

        if (-not $Converted -and $null -ne $ImageMagick -and $InputExtension -in $CommonImages) {
            try {
                & $ImageMagick "$InputPath" "$OutputPath" | Out-Null
                $Converted = (($LASTEXITCODE -eq 0) -and (Test-Path -LiteralPath $OutputPath))
            }
            catch {}
        }

        if (-not $Converted -and $null -ne $FFmpeg -and $InputExtension -in $AudioVideo) {
            try {
                & $FFmpeg -y -i "$InputPath" "$OutputPath"
                $Converted = (($LASTEXITCODE -eq 0) -and (Test-Path -LiteralPath $OutputPath))
            }
            catch {}
        }

        if (-not $Converted -and $InputExtension -eq "pub" -and $OutputExtension -in @("pdf","xps")) {
            $Converted = Convert-PublisherToFixedFormat $InputPath $OutputPath
        }

        if (-not $Converted -and $InputExtension -eq "pub" -and $OutputExtension -in @("pdf","odg")) {
            $Converted = Convert-PublisherWithLibreOffice $InputPath $OutputPath $LibreOffice
        }

        if (-not $Converted -and $InputExtension -eq "pub" -and $OutputExtension -eq "docx") {
            $Converted = Convert-PublisherToDocx $InputPath $OutputPath $LibreOffice
        }

        if (-not $Converted -and $OutputExtension -eq "pdf" -and $InputExtension -in ($OfficeDocuments + $OfficeSheets + $OfficeSlides)) {
            $Converted = Convert-OfficeToPdf $InputPath $OutputPath
        }

        if (-not $Converted -and $null -ne $LibreOffice -and $InputExtension -in ($OfficeDocuments + $OfficeSheets + $OfficeSlides + $PublisherDocuments)) {
            try {
                $OutputFolder = [IO.Path]::GetDirectoryName($OutputPath)
                $ExpectedLibreOutput = Join-Path $OutputFolder (
                    [IO.Path]::GetFileNameWithoutExtension($InputPath) + "." + $OutputExtension
                )

                & $LibreOffice `
                    --headless `
                    --convert-to $OutputExtension `
                    --outdir "$OutputFolder" `
                    "$InputPath" | Out-Null

                if (Test-Path -LiteralPath $ExpectedLibreOutput) {
                    if ($ExpectedLibreOutput -ne $OutputPath) {
                        Move-Item -LiteralPath $ExpectedLibreOutput -Destination $OutputPath -Force
                    }

                    $Converted = $true
                }
            }
            catch {}
        }

        if (-not $Converted -and $null -ne $Pandoc -and $InputExtension -in $PandocDocuments -and $OutputExtension -in @("docx","odt","rtf","html","htm","md","markdown","txt","epub")) {
            try {
                & $Pandoc "$InputPath" "-o" "$OutputPath"
                $Converted = (($LASTEXITCODE -eq 0) -and (Test-Path -LiteralPath $OutputPath))
            }
            catch {}
        }

        if (-not $Converted -and $OutputExtension -in @("json","csv","txt")) {
            $Converted = Convert-DataFile $InputPath $OutputPath
        }

        if (-not $Converted -and $OutputExtension -eq "zip" -and $InputExtension -in $Archives) {
            $Converted = Convert-ArchiveToZip $InputPath $OutputPath $SevenZip
        }

        if ($Converted) {
            Write-Host ""
            Write-Host "Conversion complete:"
            Write-Host $OutputPath
            Write-Host ""

            if (Confirm-Action "Open the converted file's folder?") {
                Start-Process explorer.exe -ArgumentList "/select,`"$OutputPath`""
            }
        }
        else {
            Write-Host ""
            Write-Warning "No safe converter available for this exact input/output combination."
            Write-Host ""
            Write-Host "The file was not modified."
            Write-Host "Installing FFmpeg, ImageMagick, LibreOffice, Pandoc, or 7-Zip"
            Write-Host "can expand the supported formats."
        }

        Write-Host ""
        Read-Host "Press Enter to return to File Conversion"
    }
}


# ============================================================
# DEEP FILE SEARCH / LOST FILE FINDER
# ============================================================

function Show-FileSearchMenu {

    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
    }
    catch {
        Write-Host ""
        Write-Warning "Windows folder-picker components could not be loaded."
        Read-Host "Press Enter to return"
        return
    }

    function Normalize-SearchText {
        param([string]$Text)

        if ([string]::IsNullOrWhiteSpace($Text)) {
            return ""
        }

        return [regex]::Replace(
            $Text.ToLowerInvariant(),
            "[^a-z0-9]",
            ""
        )
    }

    function Get-LevenshteinDistance {
        param(
            [string]$First,
            [string]$Second
        )

        if ($First -eq $Second) {
            return 0
        }

        if ($First.Length -eq 0) {
            return $Second.Length
        }

        if ($Second.Length -eq 0) {
            return $First.Length
        }

        $Previous = New-Object int[] ($Second.Length + 1)
        $Current = New-Object int[] ($Second.Length + 1)

        for ($J = 0; $J -le $Second.Length; $J++) {
            $Previous[$J] = $J
        }

        for ($I = 1; $I -le $First.Length; $I++) {
            $Current[0] = $I

            for ($J = 1; $J -le $Second.Length; $J++) {
                $Cost = 1

                if ($First[$I - 1] -eq $Second[$J - 1]) {
                    $Cost = 0
                }

                $Deletion = $Previous[$J] + 1
                $Insertion = $Current[$J - 1] + 1
                $Substitution = $Previous[$J - 1] + $Cost

                $Current[$J] = [Math]::Min(
                    [Math]::Min($Deletion, $Insertion),
                    $Substitution
                )
            }

            $Temporary = $Previous
            $Previous = $Current
            $Current = $Temporary
        }

        return $Previous[$Second.Length]
    }

    function Get-NameSearchScore {
        param(
            [System.IO.FileInfo]$File,
            [string]$Query,
            [string]$PathHint
        )

        if ([string]::IsNullOrWhiteSpace($Query)) {
            return 10
        }

        $NameLower = $File.Name.ToLowerInvariant()
        $BaseLower = [IO.Path]::GetFileNameWithoutExtension($File.Name).ToLowerInvariant()
        $QueryLower = $Query.ToLowerInvariant().Trim()

        if ($QueryLower.Contains("*") -or $QueryLower.Contains("?")) {
            if ($File.Name -like $QueryLower) {
                return 100
            }

            return 0
        }

        $Score = 0

        if ($NameLower -eq $QueryLower) {
            $Score = 120
        }
        elseif ($BaseLower -eq $QueryLower) {
            $Score = 115
        }
        elseif ($NameLower.StartsWith($QueryLower)) {
            $Score = 100
        }
        elseif ($BaseLower.StartsWith($QueryLower)) {
            $Score = 98
        }
        elseif ($NameLower.Contains($QueryLower)) {
            $Score = 92
        }
        elseif ($BaseLower.Contains($QueryLower)) {
            $Score = 90
        }
        else {
            $Tokens = @(
                [regex]::Split($QueryLower, "[^a-z0-9]+") |
                    Where-Object { $_.Length -ge 2 }
            )

            if ($Tokens.Count -gt 0) {
                $MatchedTokens = 0

                foreach ($Token in $Tokens) {
                    if ($NameLower.Contains($Token)) {
                        $MatchedTokens++
                    }
                }

                if ($MatchedTokens -gt 0) {
                    $Score = 45 + [Math]::Round(
                        35 * ($MatchedTokens / $Tokens.Count)
                    )
                }
            }
        }

        $NormalizedQuery = Normalize-SearchText $QueryLower
        $NormalizedBase = Normalize-SearchText $BaseLower

        if (
            $Score -lt 90 -and
            $NormalizedQuery.Length -ge 4 -and
            $NormalizedBase.Length -ge 4 -and
            $NormalizedQuery.Length -le 80 -and
            $NormalizedBase.Length -le 80
        ) {
            $LengthDifference = [Math]::Abs(
                $NormalizedQuery.Length - $NormalizedBase.Length
            )

            $AllowedDifference = [Math]::Max(
                5,
                [Math]::Round($NormalizedQuery.Length * 0.5)
            )

            $FirstLetterMatches = (
                $NormalizedQuery.Substring(0,1) -eq
                $NormalizedBase.Substring(0,1)
            )

            $PrefixProbeLength = [Math]::Min(2, $NormalizedQuery.Length)
            $PrefixProbe = $NormalizedQuery.Substring(0, $PrefixProbeLength)

            if (
                $LengthDifference -le $AllowedDifference -and
                ($FirstLetterMatches -or $NormalizedBase.Contains($PrefixProbe))
            ) {
                $Distance = Get-LevenshteinDistance `
                    $NormalizedQuery `
                    $NormalizedBase

                $Longest = [Math]::Max(
                    $NormalizedQuery.Length,
                    $NormalizedBase.Length
                )

                if ($Longest -gt 0) {
                    $Similarity = 1 - ($Distance / $Longest)

                    if ($Similarity -ge 0.50) {
                        $FuzzyScore = [Math]::Round(35 + (50 * $Similarity))

                        if ($FuzzyScore -gt $Score) {
                            $Score = $FuzzyScore
                        }
                    }
                }
            }
        }

        if (
            -not [string]::IsNullOrWhiteSpace($PathHint) -and
            $File.DirectoryName.ToLowerInvariant().Contains(
                $PathHint.ToLowerInvariant()
            )
        ) {
            $Score += 8
        }

        return [int]$Score
    }

    function Choose-SearchRoots {
        Write-Host ""
        Write-Host "Where should I search?"
        Write-Host ""
        Write-Host "1 - My files"
        Write-Host "    Searches your Windows user folder, including Desktop/Documents/Downloads/OneDrive."
        Write-Host ""
        Write-Host "2 - All accessible drives (deep search)"
        Write-Host "    Searches fixed, removable, and connected filesystem drives."
        Write-Host ""
        Write-Host "3 - Choose one folder"
        Write-Host ""

        do {
            $ScopeChoice = Read-Host "Choose 1, 2, or 3"
        } until ($ScopeChoice -in @("1","2","3"))

        if ($ScopeChoice -eq "1") {
            return @($env:USERPROFILE)
        }

        if ($ScopeChoice -eq "2") {
            $Roots = @()

            foreach ($Drive in [IO.DriveInfo]::GetDrives()) {
                try {
                    if (
                        $Drive.IsReady -and
                        $Drive.DriveType -in @(
                            [IO.DriveType]::Fixed,
                            [IO.DriveType]::Removable,
                            [IO.DriveType]::Network
                        )
                    ) {
                        $Roots += $Drive.RootDirectory.FullName
                    }
                }
                catch {}
            }

            return @($Roots | Select-Object -Unique)
        }

        $Dialog = New-Object System.Windows.Forms.FolderBrowserDialog
        $Dialog.Description = "Choose the folder to search"
        $Dialog.ShowNewFolderButton = $false

        if ($Dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            return @($Dialog.SelectedPath)
        }

        return @()
    }

    function Search-FilesDeep {
        param(
            [string[]]$Roots,
            [string]$SearchText,
            [string]$Extension,
            [Nullable[int]]$ModifiedWithinDays,
            [Nullable[double]]$MinimumSizeMB,
            [Nullable[double]]$MaximumSizeMB,
            [Nullable[double]]$ApproximateSizeMB,
            [string]$PathHint
        )

        $Results = New-Object System.Collections.ArrayList
        $script:FileSearchScanned = 0
        $script:FileSearchMatches = 0

        $CleanExtension = ""

        if (-not [string]::IsNullOrWhiteSpace($Extension)) {
            $CleanExtension = $Extension.Trim().TrimStart(".").ToLowerInvariant()
        }

        $CutoffDate = $null

        if ($null -ne $ModifiedWithinDays -and $ModifiedWithinDays -gt 0) {
            $CutoffDate = (Get-Date).AddDays(-1 * $ModifiedWithinDays.Value)
        }

        foreach ($Root in $Roots) {
            if (-not (Test-Path -LiteralPath $Root)) {
                continue
            }

            $Stack = New-Object System.Collections.Stack
            $Stack.Push($Root)

            while ($Stack.Count -gt 0) {
                $CurrentDirectory = [string]$Stack.Pop()

                try {
                    $FilePaths = [IO.Directory]::GetFiles($CurrentDirectory)
                }
                catch {
                    $FilePaths = @()
                }

                foreach ($FilePath in $FilePaths) {
                    $script:FileSearchScanned++

                    if (($script:FileSearchScanned % 1000) -eq 0) {
                        Write-Progress `
                            -Activity "Deep file search" `
                            -Status "$($script:FileSearchScanned) files checked; $($script:FileSearchMatches) matches" `
                            -CurrentOperation $CurrentDirectory
                    }

                    try {
                        $File = New-Object System.IO.FileInfo($FilePath)

                        if (
                            -not [string]::IsNullOrWhiteSpace($CleanExtension) -and
                            $File.Extension.TrimStart(".").ToLowerInvariant() -ne $CleanExtension
                        ) {
                            continue
                        }

                        $SizeMB = $File.Length / 1MB

                        if ($null -ne $MinimumSizeMB -and $SizeMB -lt $MinimumSizeMB.Value) {
                            continue
                        }

                        if ($null -ne $MaximumSizeMB -and $SizeMB -gt $MaximumSizeMB.Value) {
                            continue
                        }

                        if ($null -ne $CutoffDate -and $File.LastWriteTime -lt $CutoffDate) {
                            continue
                        }

                        $Score = Get-NameSearchScore $File $SearchText $PathHint

                        if (
                            -not [string]::IsNullOrWhiteSpace($SearchText) -and
                            $Score -lt 35
                        ) {
                            continue
                        }

                        if ($null -ne $ApproximateSizeMB -and $ApproximateSizeMB.Value -gt 0) {
                            $Difference = [Math]::Abs(
                                $SizeMB - $ApproximateSizeMB.Value
                            )

                            $Tolerance = [Math]::Max(
                                1,
                                $ApproximateSizeMB.Value * 0.35
                            )

                            if ($Difference -le $Tolerance) {
                                $Score += 15
                            }
                        }

                        [void]$Results.Add(
                            [PSCustomObject]@{
                                Score        = $Score
                                Name         = $File.Name
                                Extension    = $File.Extension
                                SizeMB       = [Math]::Round($SizeMB, 2)
                                Modified     = $File.LastWriteTime
                                Created      = $File.CreationTime
                                Folder       = $File.DirectoryName
                                FullName     = $File.FullName
                            }
                        )

                        $script:FileSearchMatches++

                        if ($Results.Count -ge 5000) {
                            Write-Progress -Activity "Deep file search" -Completed
                            return @($Results)
                        }
                    }
                    catch {}
                }

                try {
                    $Directories = [IO.Directory]::GetDirectories($CurrentDirectory)
                }
                catch {
                    $Directories = @()
                }

                foreach ($DirectoryPath in $Directories) {
                    try {
                        $Attributes = [IO.File]::GetAttributes($DirectoryPath)

                        if (
                            ($Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0
                        ) {
                            $Stack.Push($DirectoryPath)
                        }
                    }
                    catch {}
                }
            }
        }

        Write-Progress -Activity "Deep file search" -Completed
        return @($Results)
    }

    function Show-SearchResults {
        param(
            [object[]]$Results
        )

        if ($null -eq $Results -or $Results.Count -eq 0) {
            Write-Host ""
            Write-Host "No matches were found."
            Write-Host ""
            Write-Host "Try:"
            Write-Host "  - fewer words from the filename"
            Write-Host "  - leaving the extension blank"
            Write-Host "  - All accessible drives"
            Write-Host "  - a wider date or size range"
            Write-Host ""
            Read-Host "Press Enter to return"
            return
        }

        $Sorted = @(
            $Results |
                Sort-Object `
                    @{ Expression = "Score"; Descending = $true },
                    @{ Expression = "Modified"; Descending = $true }
        )

        $ReportPath = Join-Path `
            $Reports `
            "FileSearch-$((Get-Date).ToString('yyyy-MM-dd_HH-mm-ss')).csv"

        $Sorted |
            Export-Csv `
                -LiteralPath $ReportPath `
                -NoTypeInformation

        $Top = @($Sorted | Select-Object -First 100)
        $DisplayRows = @()

        for ($Index = 0; $Index -lt $Top.Count; $Index++) {
            $DisplayRows += [PSCustomObject]@{
                Number   = $Index + 1
                Score    = $Top[$Index].Score
                Name     = $Top[$Index].Name
                SizeMB   = $Top[$Index].SizeMB
                Modified = $Top[$Index].Modified
                Folder   = $Top[$Index].Folder
            }
        }

        Clear-Host
        Write-Host "============================================================"
        Write-Host "                  FILE SEARCH RESULTS"
        Write-Host "============================================================"
        Write-Host ""
        Write-Host "Files checked: $script:FileSearchScanned"
        Write-Host "Matches:       $($Sorted.Count)"
        Write-Host ""
        Write-Host "Best matches are shown first."
        Write-Host ""

        $DisplayRows |
            Select-Object -First 40 |
            Format-Table `
                Number,
                Score,
                Name,
                SizeMB,
                Modified,
                Folder `
                -AutoSize

        Write-Host ""
        Write-Host "Full results report:"
        Write-Host $ReportPath
        Write-Host ""

        while ($true) {
            $Selection = Read-Host "Enter a result number to reveal it in Explorer, or press Enter to return"

            if ([string]::IsNullOrWhiteSpace($Selection)) {
                break
            }

            $Number = 0

            if (
                [int]::TryParse($Selection, [ref]$Number) -and
                $Number -ge 1 -and
                $Number -le $Top.Count
            ) {
                $SelectedPath = $Top[$Number - 1].FullName

                try {
                    Start-Process explorer.exe -ArgumentList "/select,`"$SelectedPath`""
                }
                catch {
                    Write-Host $SelectedPath
                }
            }
        }
    }

    while ($true) {
        Clear-Host
        Write-Host "============================================================"
        Write-Host "              DEEP FILE SEARCH / LOST FILE FINDER"
        Write-Host "============================================================"
        Write-Host ""
        Write-Host "1 - Easy Search"
        Write-Host "    Partial filename + optional extension."
        Write-Host ""
        Write-Host "2 - Find a Lost or Accidentally Moved File"
        Write-Host "    Uses approximate names, old paths, size, date and fuzzy ranking."
        Write-Host ""
        Write-Host "3 - Find Recently Modified Files"
        Write-Host "    Useful when you do not remember the filename."
        Write-Host ""
        Write-Host "4 - Advanced Search"
        Write-Host "    Name/wildcard + extension + size + date filters."
        Write-Host ""
        Write-Host "5 - Find Microsoft Publisher Files (.pub)"
        Write-Host "    Finds old Publisher documents so you can rescue/convert them."
        Write-Host ""
        Write-Host "6 - Back"
        Write-Host ""

        $Choice = Read-Host "Choose 1, 2, 3, 4, 5, or 6"

        if ($Choice -eq "6") {
            return
        }

        if ($Choice -notin @("1","2","3","4","5")) {
            continue
        }

        $SearchText = ""
        $Extension = ""
        $ModifiedWithinDays = $null
        $MinimumSizeMB = $null
        $MaximumSizeMB = $null
        $ApproximateSizeMB = $null
        $PathHint = ""

        if ($Choice -eq "1") {
            Write-Host ""
            $SearchText = Read-Host "Enter any part of the filename"
            $Extension = Read-Host "Extension if known (example: pdf, docx, jpg) or press Enter"
        }

        if ($Choice -eq "2") {
            Write-Host ""
            Write-Host "You can paste the OLD full path if you remember it."
            Write-Host "Example: C:\Users\Name\Documents\school\report.docx"
            Write-Host ""
            $Remembered = Read-Host "Old filename, old path, or part of the name"

            if ($Remembered.Contains("\") -or $Remembered.Contains("/")) {
                try {
                    $SearchText = [IO.Path]::GetFileName($Remembered)

                    $OldDirectory = [IO.Path]::GetDirectoryName($Remembered)

                    if (-not [string]::IsNullOrWhiteSpace($OldDirectory)) {
                        $PathHint = [IO.Path]::GetFileName($OldDirectory)
                    }
                }
                catch {
                    $SearchText = $Remembered
                }
            }
            else {
                $SearchText = $Remembered
            }

            $Extension = Read-Host "Extension if known, or press Enter"

            $SizeText = Read-Host "Approximate size in MB if known, or press Enter"
            $ParsedSize = 0.0

            if ([double]::TryParse($SizeText, [ref]$ParsedSize)) {
                $ApproximateSizeMB = [Nullable[double]]$ParsedSize
            }

            $DaysText = Read-Host "Modified within the last how many days? Press Enter if unknown"
            $ParsedDays = 0

            if ([int]::TryParse($DaysText, [ref]$ParsedDays)) {
                $ModifiedWithinDays = [Nullable[int]]$ParsedDays
            }
        }

        if ($Choice -eq "3") {
            Write-Host ""
            $DaysText = Read-Host "Show files modified within the last how many days?"
            $ParsedDays = 0

            if (-not [int]::TryParse($DaysText, [ref]$ParsedDays)) {
                $ParsedDays = 7
            }

            $ModifiedWithinDays = [Nullable[int]]$ParsedDays
            $Extension = Read-Host "Extension if known, or press Enter for any file type"
        }

        if ($Choice -eq "4") {
            Write-Host ""
            $SearchText = Read-Host "Filename text or wildcard (example: project*final*)"
            $Extension = Read-Host "Extension, or press Enter for any"

            $MinimumText = Read-Host "Minimum size in MB, or press Enter"
            $MaximumText = Read-Host "Maximum size in MB, or press Enter"
            $DaysText = Read-Host "Modified within last N days, or press Enter"

            $ParsedMinimum = 0.0
            $ParsedMaximum = 0.0
            $ParsedDays = 0

            if ([double]::TryParse($MinimumText, [ref]$ParsedMinimum)) {
                $MinimumSizeMB = [Nullable[double]]$ParsedMinimum
            }

            if ([double]::TryParse($MaximumText, [ref]$ParsedMaximum)) {
                $MaximumSizeMB = [Nullable[double]]$ParsedMaximum
            }

            if ([int]::TryParse($DaysText, [ref]$ParsedDays)) {
                $ModifiedWithinDays = [Nullable[int]]$ParsedDays
            }
        }

        if ($Choice -eq "5") {
            Write-Host ""
            Write-Host "Publisher rescue search selected."
            Write-Host "The search will only return Microsoft Publisher .pub files."
            Write-Host ""
            $SearchText = ""
            $Extension = "pub"
        }

        $Roots = @(Choose-SearchRoots)

        if ($Roots.Count -eq 0) {
            continue
        }

        Clear-Host
        Write-Host "============================================================"
        Write-Host "                       SEARCHING"
        Write-Host "============================================================"
        Write-Host ""
        Write-Host "Search roots:"
        $Roots | ForEach-Object { Write-Host "  $_" }
        Write-Host ""
        Write-Host "Deep searches across an entire drive can take a while."
        Write-Host "The search includes hidden files and skips reparse-point loops."
        Write-Host ""

        $Results = @(
            Search-FilesDeep `
                -Roots $Roots `
                -SearchText $SearchText `
                -Extension $Extension `
                -ModifiedWithinDays $ModifiedWithinDays `
                -MinimumSizeMB $MinimumSizeMB `
                -MaximumSizeMB $MaximumSizeMB `
                -ApproximateSizeMB $ApproximateSizeMB `
                -PathHint $PathHint
        )

        Show-SearchResults $Results

        if ($Choice -eq "5" -and $Results.Count -gt 0) {
            Write-Host ""

            if (Confirm-Action "Open Microsoft Publisher Rescue conversion now?") {
                Show-FileConversionMenu
                return
            }
        }
    }
}


# ============================================================
# PROJECT / CODE SEARCH
# ============================================================

function Show-ProjectCodeSearchMenu {

    function Get-SearchRoots {
        param([string]$ScopeChoice)

        if ($ScopeChoice -eq "1") {
            return @($env:USERPROFILE)
        }

        if ($ScopeChoice -eq "2") {
            return @(
                Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue |
                    Where-Object { $_.Root -and (Test-Path -LiteralPath $_.Root) } |
                    Select-Object -ExpandProperty Root
            )
        }

        if ($ScopeChoice -eq "3") {
            try {
                Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
                $Dialog = New-Object System.Windows.Forms.FolderBrowserDialog
                $Dialog.Description = "Choose the folder to search for projects/code"
                if ($Dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                    return @($Dialog.SelectedPath)
                }
            }
            catch {}
        }

        return @()
    }

    function Get-CodeLanguage {
        param([string]$Path)

        $Name = [IO.Path]::GetFileName($Path).ToLowerInvariant()
        $Ext = [IO.Path]::GetExtension($Path).ToLowerInvariant()

        if ($Name -eq "cmakelists.txt" -or $Ext -eq ".cmake") { return "CMake" }
        if ($Name -eq "makefile") { return "Make" }
        if ($Name -eq "dockerfile") { return "Docker" }

        $Map = @{
            ".c"="C"; ".h"="C/C++ Header"; ".cpp"="C++"; ".cc"="C++"; ".cxx"="C++"; ".hpp"="C++ Header";
            ".py"="Python"; ".ipynb"="Jupyter"; ".js"="JavaScript"; ".jsx"="JavaScript/React"; ".ts"="TypeScript"; ".tsx"="TypeScript/React";
            ".java"="Java"; ".kt"="Kotlin"; ".kts"="Kotlin"; ".cs"="C#"; ".fs"="F#"; ".vb"="Visual Basic";
            ".go"="Go"; ".rs"="Rust"; ".php"="PHP"; ".rb"="Ruby"; ".swift"="Swift"; ".scala"="Scala";
            ".sh"="Shell"; ".bash"="Shell"; ".zsh"="Shell"; ".ps1"="PowerShell"; ".bat"="Batch"; ".cmd"="Batch";
            ".sql"="SQL"; ".html"="HTML"; ".htm"="HTML"; ".css"="CSS"; ".scss"="SCSS"; ".sass"="Sass";
            ".xml"="XML"; ".json"="JSON"; ".yaml"="YAML"; ".yml"="YAML"; ".toml"="TOML";
            ".md"="Markdown"; ".rst"="reStructuredText"; ".lua"="Lua"; ".r"="R"; ".m"="MATLAB/Objective-C"
        }

        if ($Map.ContainsKey($Ext)) { return $Map[$Ext] }
        return "Other"
    }

    function Test-CodeLikeFile {
        param([System.IO.FileInfo]$File)

        $Names = @("CMakeLists.txt","Makefile","Dockerfile","package.json","requirements.txt","pyproject.toml","Cargo.toml","pom.xml","build.gradle","build.gradle.kts","docker-compose.yml","docker-compose.yaml","README.md")
        if ($File.Name -in $Names) { return $true }

        $CodeExtensions = @(
            ".c",".h",".cpp",".cc",".cxx",".hpp",".py",".ipynb",".js",".jsx",".ts",".tsx",".java",".kt",".kts",
            ".cs",".fs",".vb",".go",".rs",".php",".rb",".swift",".scala",".sh",".bash",".zsh",".ps1",".bat",".cmd",
            ".sql",".html",".htm",".css",".scss",".sass",".xml",".json",".yaml",".yml",".toml",".md",".rst",".lua",".r",".m",".cmake"
        )

        return ($File.Extension.ToLowerInvariant() -in $CodeExtensions)
    }

    function Find-ProjectRoot {
        param([string]$StartDirectory)

        $Markers = @(
            ".git","CMakeLists.txt","package.json","requirements.txt","pyproject.toml","Cargo.toml","pom.xml",
            "build.gradle","build.gradle.kts","Makefile","Dockerfile","docker-compose.yml","docker-compose.yaml",
            "README.md"
        )

        try { $Current = Get-Item -LiteralPath $StartDirectory -ErrorAction Stop } catch { return $StartDirectory }
        $Fallback = $Current.FullName

        for ($Depth = 0; $Depth -lt 8 -and $null -ne $Current; $Depth++) {
            foreach ($Marker in $Markers) {
                if (Test-Path -LiteralPath (Join-Path $Current.FullName $Marker)) {
                    return $Current.FullName
                }
            }
            $Current = $Current.Parent
        }

        return $Fallback
    }

    Write-Section "PROJECT / CODE SEARCH"
    Write-Host "Search old programming projects by name, structure, filenames, libraries, purpose, language, or old folder origin."
    Write-Host ""
    Write-Host "Search scope:"
    Write-Host "1 - My Windows user folder"
    Write-Host "2 - All accessible drives"
    Write-Host "3 - Choose a folder"
    Write-Host "4 - Return"
    Write-Host ""

    $ScopeChoice = Read-Host "Choose 1, 2, 3, or 4"
    if ($ScopeChoice -eq "4") { return }
    if ($ScopeChoice -notin @("1","2","3")) { return }

    $Roots = Get-SearchRoots $ScopeChoice
    if ($Roots.Count -eq 0) {
        Write-Warning "No search location was selected."
        Read-Host "Press Enter to return"
        return
    }

    Write-Host ""
    $NameClue = Read-Host "Project/folder/file name clue (optional)"
    $ContentClue = Read-Host "Code/library/class/function/purpose keywords, comma separated (optional)"
    $LanguageClue = Read-Host "Language/code type such as C++, Python, Java, PowerShell (optional)"
    $OldOrigin = Read-Host "Old folder/path clue if you remember where it came from (optional)"

    if ([string]::IsNullOrWhiteSpace($NameClue) -and
        [string]::IsNullOrWhiteSpace($ContentClue) -and
        [string]::IsNullOrWhiteSpace($LanguageClue) -and
        [string]::IsNullOrWhiteSpace($OldOrigin)) {
        Write-Warning "Enter at least one clue."
        Read-Host "Press Enter to return"
        return
    }

    $Terms = @()
    if (-not [string]::IsNullOrWhiteSpace($ContentClue)) {
        $Terms = @($ContentClue.Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    }

    $ProjectScores = @{}
    $ProjectDetails = @{}
    $ScannedFiles = 0
    $MatchedFiles = 0

    foreach ($Root in $Roots) {
        Write-Host ""
        Write-Host "Searching: $Root"

        $Files = Get-ChildItem -LiteralPath $Root -File -Force -Recurse -ErrorAction SilentlyContinue |
            Where-Object { Test-CodeLikeFile $_ }

        foreach ($File in $Files) {
            $ScannedFiles++
            $Score = 0
            $Reasons = New-Object System.Collections.Generic.List[string]
            $Language = Get-CodeLanguage $File.FullName

            if (-not [string]::IsNullOrWhiteSpace($NameClue)) {
                if ($File.Name -like "*$NameClue*") { $Score += 40; $Reasons.Add("filename") }
                if ($File.DirectoryName -like "*$NameClue*") { $Score += 25; $Reasons.Add("folder name") }
            }

            if (-not [string]::IsNullOrWhiteSpace($LanguageClue)) {
                if ($Language -like "*$LanguageClue*") { $Score += 25; $Reasons.Add("language/type") }
                elseif ($File.Extension -like "*$LanguageClue*") { $Score += 15; $Reasons.Add("extension") }
            }

            if (-not [string]::IsNullOrWhiteSpace($OldOrigin)) {
                $OldLeaf = Split-Path $OldOrigin -Leaf
                $OldParent = Split-Path $OldOrigin -Parent
                if ($OldLeaf -and $File.FullName -like "*$OldLeaf*") { $Score += 15; $Reasons.Add("old path leaf") }
                if ($OldParent) {
                    $OldParentLeaf = Split-Path $OldParent -Leaf
                    if ($OldParentLeaf -and $File.DirectoryName -like "*$OldParentLeaf*") { $Score += 10; $Reasons.Add("old folder clue") }
                }
            }

            if ($Terms.Count -gt 0 -and $File.Length -le 5MB) {
                try {
                    $Text = Get-Content -LiteralPath $File.FullName -Raw -ErrorAction Stop
                    foreach ($Term in $Terms) {
                        if ($Text -match [regex]::Escape($Term)) {
                            $Score += 20
                            $Reasons.Add("content:$Term")
                        }
                    }
                }
                catch {}
            }

            if ($Score -gt 0) {
                $MatchedFiles++
                $RootPath = Find-ProjectRoot $File.DirectoryName

                if (-not $ProjectScores.ContainsKey($RootPath)) {
                    $ProjectScores[$RootPath] = 0
                    $ProjectDetails[$RootPath] = New-Object System.Collections.Generic.List[object]
                }

                $ProjectScores[$RootPath] += $Score
                $ProjectDetails[$RootPath].Add([PSCustomObject]@{
                    File = $File.FullName
                    Language = $Language
                    Score = $Score
                    Reasons = (($Reasons | Select-Object -Unique) -join "; ")
                })
            }
        }
    }

    $Results = @()
    foreach ($ProjectRoot in $ProjectScores.Keys) {
        $TopFiles = @($ProjectDetails[$ProjectRoot] | Sort-Object Score -Descending | Select-Object -First 5)
        $Languages = @($ProjectDetails[$ProjectRoot] | Select-Object -ExpandProperty Language -Unique) -join ", "
        $ReasonText = @($TopFiles | Select-Object -ExpandProperty Reasons) -join " | "
        $ExampleFiles = @($TopFiles | ForEach-Object { [IO.Path]::GetFileName($_.File) }) -join ", "

        $Results += [PSCustomObject]@{
            Score = $ProjectScores[$ProjectRoot]
            ProjectRoot = $ProjectRoot
            Languages = $Languages
            ExampleFiles = $ExampleFiles
            MatchReasons = $ReasonText
            MatchedFileCount = $ProjectDetails[$ProjectRoot].Count
        }
    }

    $Results = @($Results | Sort-Object Score -Descending)
    $ReportPath = Join-Path $Reports "Project-Code-Search-$Stamp.csv"
    $Results | Export-Csv -Path $ReportPath -NoTypeInformation

    Write-Host ""
    Write-Host "Code files scanned: $ScannedFiles"
    Write-Host "Matching files:     $MatchedFiles"
    Write-Host "Likely projects:    $($Results.Count)"
    Write-Host ""

    $Display = @($Results | Select-Object -First 50)
    for ($i = 0; $i -lt $Display.Count; $i++) {
        Write-Host "[$($i + 1)] Score $($Display[$i].Score)"
        Write-Host "    $($Display[$i].ProjectRoot)"
        Write-Host "    Languages: $($Display[$i].Languages)"
        Write-Host "    Files: $($Display[$i].ExampleFiles)"
        Write-Host ""
    }

    Write-Host "Full CSV report:"
    Write-Host $ReportPath
    Write-Host ""

    if ($Display.Count -gt 0) {
        $Pick = Read-Host "Enter a result number to open that project folder, or press Enter"
        $Number = 0
        if ([int]::TryParse($Pick, [ref]$Number)) {
            if ($Number -ge 1 -and $Number -le $Display.Count) {
                Start-Process explorer.exe "`"$($Display[$Number - 1].ProjectRoot)`""
            }
        }
    }

    Read-Host "Press Enter to return"
}


# ============================================================
# WSL / LINUX TERMINAL MAINTENANCE
# ============================================================

function Show-LinuxMaintenanceMenu {

    function Get-WSLDistros {
        try {
            $Raw = & wsl.exe -l -q 2>$null
            return @($Raw | ForEach-Object { $_.Trim([char]0).Trim() } | Where-Object { $_ })
        }
        catch { return @() }
    }

    function Get-LinuxUpdateCommand {
        param([string]$Distro)

        $Detect = & wsl.exe -d $Distro -- sh -lc 'if command -v apt >/dev/null 2>&1; then echo apt; elif command -v dnf >/dev/null 2>&1; then echo dnf; elif command -v yum >/dev/null 2>&1; then echo yum; elif command -v pacman >/dev/null 2>&1; then echo pacman; elif command -v zypper >/dev/null 2>&1; then echo zypper; else echo unknown; fi' 2>$null
        $Manager = (($Detect | Select-Object -Last 1) -as [string]).Trim()

        switch ($Manager) {
            "apt"    { return "sudo apt update && sudo apt upgrade" }
            "dnf"    { return "sudo dnf upgrade --refresh" }
            "yum"    { return "sudo yum update" }
            "pacman" { return "sudo pacman -Syu" }
            "zypper" { return "sudo zypper refresh && sudo zypper update" }
            default   { return $null }
        }
    }

    while ($true) {
        Write-Section "WSL / LINUX TERMINAL MAINTENANCE"
        Write-Host "1 - Show WSL status and installed Linux distributions"
        Write-Host "2 - Check package updates in a Linux distribution"
        Write-Host "3 - Update packages in a Linux distribution"
        Write-Host "4 - Update the Windows WSL engine/kernel"
        Write-Host "5 - Open a Linux distribution terminal"
        Write-Host "6 - Return"
        Write-Host ""

        $Choice = Read-Host "Choose 1, 2, 3, 4, 5, or 6"
        if ($Choice -eq "6") { return }

        $Distros = Get-WSLDistros

        if ($Choice -eq "1") {
            Write-Host ""
            & wsl.exe --status
            Write-Host ""
            & wsl.exe --version
            Write-Host ""
            Write-Host "Installed distributions:"
            if ($Distros.Count -eq 0) { Write-Host "  None detected." }
            for ($i=0; $i -lt $Distros.Count; $i++) { Write-Host "  $($i+1) - $($Distros[$i])" }
            Read-Host "Press Enter to continue"
            continue
        }

        if ($Choice -eq "4") {
            if (Confirm-Action "Run wsl.exe --update now?") {
                & wsl.exe --update
            }
            Read-Host "Press Enter to continue"
            continue
        }

        if ($Distros.Count -eq 0) {
            Write-Warning "No WSL Linux distributions were detected."
            Read-Host "Press Enter to continue"
            continue
        }

        Write-Host ""
        for ($i=0; $i -lt $Distros.Count; $i++) { Write-Host "$($i+1) - $($Distros[$i])" }
        $Pick = Read-Host "Choose a distribution number"
        $Index = 0
        if (-not [int]::TryParse($Pick, [ref]$Index) -or $Index -lt 1 -or $Index -gt $Distros.Count) {
            Write-Warning "Invalid distribution selection."
            Read-Host "Press Enter to continue"
            continue
        }

        $Distro = $Distros[$Index - 1]

        if ($Choice -eq "5") {
            Start-Process wsl.exe -ArgumentList @("-d", $Distro)
            continue
        }

        $Manager = (& wsl.exe -d $Distro -- sh -lc 'if command -v apt >/dev/null 2>&1; then echo apt; elif command -v dnf >/dev/null 2>&1; then echo dnf; elif command -v yum >/dev/null 2>&1; then echo yum; elif command -v pacman >/dev/null 2>&1; then echo pacman; elif command -v zypper >/dev/null 2>&1; then echo zypper; else echo unknown; fi' 2>$null | Select-Object -Last 1)
        $Manager = ([string]$Manager).Trim()

        if ($Choice -eq "2") {
            Write-Host ""
            Write-Host "Checking updates in $Distro using $Manager..."
            switch ($Manager) {
                "apt"    { & wsl.exe -d $Distro -- sh -lc 'apt list --upgradable 2>/dev/null' }
                "dnf"    { & wsl.exe -d $Distro -- sh -lc 'dnf check-update || true' }
                "yum"    { & wsl.exe -d $Distro -- sh -lc 'yum check-update || true' }
                "pacman" { & wsl.exe -d $Distro -- sh -lc 'pacman -Qu || true' }
                "zypper" { & wsl.exe -d $Distro -- sh -lc 'zypper list-updates || true' }
                default   { Write-Warning "Supported package manager not detected." }
            }
            Read-Host "Press Enter to continue"
            continue
        }

        if ($Choice -eq "3") {
            $Command = Get-LinuxUpdateCommand $Distro
            if ($null -eq $Command) {
                Write-Warning "Supported package manager not detected."
                Read-Host "Press Enter to continue"
                continue
            }

            Write-Host ""
            Write-Host "Linux command: $Command"
            Write-Host "Your Linux sudo password may be requested."
            if (Confirm-Action "Update $Distro now?") {
                & wsl.exe -d $Distro -- sh -lc $Command
            }
            Read-Host "Press Enter to continue"
        }
    }
}


# ============================================================
# SPEECH LISTENER / AUDIO INPUT
# ============================================================

function Show-SpeechListenerMenu {

    function Show-AudioEndpoints {
        Write-Host ""
        Write-Host "Detected audio endpoints/peripherals:"
        Write-Host ""
        try {
            $Endpoints = Get-PnpDevice -Class AudioEndpoint -ErrorAction Stop |
                Select-Object Status, FriendlyName, InstanceId
            if ($null -eq $Endpoints) {
                Write-Host "No AudioEndpoint devices were returned."
            }
            else {
                $Endpoints | Format-Table Status, FriendlyName -AutoSize
            }
        }
        catch {
            Write-Warning "Audio endpoint enumeration is unavailable on this Windows installation."
            try {
                Get-CimInstance Win32_SoundDevice -ErrorAction Stop |
                    Select-Object Status, Name, Manufacturer |
                    Format-Table -AutoSize
            }
            catch {}
        }
    }

    function Invoke-SpeechListeningSession {
        param([int]$Seconds = 30)

        try {
            Add-Type -AssemblyName System.Speech -ErrorAction Stop
        }
        catch {
            Write-Warning "System.Speech is not available on this Windows installation."
            return
        }

        $Recognizer = $null
        try {
            $Recognizer = New-Object System.Speech.Recognition.SpeechRecognitionEngine
            $Grammar = New-Object System.Speech.Recognition.DictationGrammar
            $Recognizer.LoadGrammar($Grammar)
            $Recognizer.SetInputToDefaultAudioDevice()
        }
        catch {
            Write-Warning "Speech recognition could not initialize."
            Write-Host "Make sure a microphone is connected, enabled, and selected as the default Windows input device."
            if ($null -ne $Recognizer) { try { $Recognizer.Dispose() } catch {} }
            return
        }

        $Transcript = New-Object System.Collections.Generic.List[object]
        $Deadline = (Get-Date).AddSeconds($Seconds)

        Write-Host ""
        Write-Host "Listening through the CURRENT DEFAULT Windows microphone for $Seconds seconds."
        Write-Host "This only listens while this session is active. It does not run secretly in the background."
        Write-Host "Speak normally..."
        Write-Host ""

        while ((Get-Date) -lt $Deadline) {
            try {
                $Remaining = $Deadline - (Get-Date)
                if ($Remaining.TotalSeconds -le 0) { break }
                $Window = [TimeSpan]::FromSeconds([math]::Min(5, $Remaining.TotalSeconds))
                $Result = $Recognizer.Recognize($Window)

                if ($null -ne $Result -and -not [string]::IsNullOrWhiteSpace($Result.Text)) {
                    $Line = [PSCustomObject]@{
                        Time = Get-Date
                        Confidence = [math]::Round($Result.Confidence, 3)
                        Text = $Result.Text
                    }
                    $Transcript.Add($Line)
                    Write-Host "[$($Line.Confidence)] $($Line.Text)"
                }
            }
            catch {}
        }

        try { $Recognizer.Dispose() } catch {}

        $TranscriptPath = Join-Path $Reports "Speech-Transcript-$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').csv"
        $Transcript | Export-Csv -Path $TranscriptPath -NoTypeInformation

        Write-Host ""
        Write-Host "Listening stopped."
        Write-Host "Recognized phrases: $($Transcript.Count)"
        Write-Host "Transcript: $TranscriptPath"
    }

    while ($true) {
        Write-Section "SPEECH LISTENER / MICROPHONE"
        Write-Host "1 - List built-in and attached audio endpoints"
        Write-Host "2 - Listen for 15 seconds"
        Write-Host "3 - Listen for 30 seconds"
        Write-Host "4 - Listen for 60 seconds"
        Write-Host "5 - Open Windows Sound settings to choose microphone"
        Write-Host "6 - Return"
        Write-Host ""
        Write-Host "Speech input uses the current DEFAULT Windows recording device."
        Write-Host "An attached USB/Bluetooth headset or microphone works after Windows makes it the default input."
        Write-Host ""

        $Choice = Read-Host "Choose 1, 2, 3, 4, 5, or 6"
        switch ($Choice) {
            "1" { Show-AudioEndpoints; Read-Host "Press Enter to continue" }
            "2" { Invoke-SpeechListeningSession 15; Read-Host "Press Enter to continue" }
            "3" { Invoke-SpeechListeningSession 30; Read-Host "Press Enter to continue" }
            "4" { Invoke-SpeechListeningSession 60; Read-Host "Press Enter to continue" }
            "5" { Start-Process "ms-settings:sound" }
            "6" { return }
        }
    }
}



# ============================================================
# DRIVE PHOTO SEARCH / DESKTOP BACKUP
# ============================================================

function Get-PhotoExtensions {
    return @(
        ".jpg", ".jpeg", ".jpe", ".jfif",
        ".png", ".gif", ".bmp",
        ".tif", ".tiff",
        ".webp", ".heic", ".heif", ".avif",
        ".dng", ".cr2", ".cr3", ".nef", ".nrw",
        ".arw", ".sr2", ".srf",
        ".raf", ".orf", ".rw2", ".pef", ".srw",
        ".x3f", ".3fr", ".fff", ".rwl", ".iiq",
        ".kdc", ".erf", ".mos", ".mrw"
    )
}

function Get-ReadyPhotoDrives {
    $Ready = @()

    try {
        $Drives = [System.IO.DriveInfo]::GetDrives()

        foreach ($Drive in $Drives) {
            try {
                if (-not $Drive.IsReady) {
                    continue
                }

                if (
                    $Drive.DriveType -eq [System.IO.DriveType]::Fixed -or
                    $Drive.DriveType -eq [System.IO.DriveType]::Removable -or
                    $Drive.DriveType -eq [System.IO.DriveType]::Network
                ) {
                    $Ready += $Drive
                }
            }
            catch {
            }
        }
    }
    catch {
    }

    return $Ready
}

function Get-PhotoFilesFromRoot {

    param(
        [string]$Root,
        [System.Collections.Generic.List[object]]$Results,
        [string]$DestinationRoot
    )

    if (-not (Test-Path -LiteralPath $Root)) {
        return
    }

    $Extensions = @(Get-PhotoExtensions)

    Write-Host ""
    Write-Host "Searching:"
    Write-Host "  $Root"
    Write-Host ""

    try {

        Get-ChildItem `
            -LiteralPath $Root `
            -File `
            -Force `
            -Recurse `
            -ErrorAction SilentlyContinue |
        ForEach-Object {

            $Item = $_

            try {
                if (
                    $DestinationRoot -and
                    $Item.FullName.StartsWith(
                        $DestinationRoot,
                        [System.StringComparison]::OrdinalIgnoreCase
                    )
                ) {
                    return
                }

                $Extension = $Item.Extension.ToLowerInvariant()

                if ($Extensions -contains $Extension) {

                    $Results.Add(
                        [PSCustomObject]@{
                            FullName      = $Item.FullName
                            Name          = $Item.Name
                            Extension     = $Extension
                            Length        = $Item.Length
                            LastWriteTime = $Item.LastWriteTime
                            Root          = $Root
                        }
                    )
                }
            }
            catch {
            }
        }

    }
    catch {
        Write-Warning "Some folders under this location could not be searched."
    }
}

function Get-SafeBackupRelativePath {

    param(
        [string]$SourcePath
    )

    $Full = [System.IO.Path]::GetFullPath($SourcePath)
    $Root = [System.IO.Path]::GetPathRoot($Full)

    if ([string]::IsNullOrWhiteSpace($Root)) {
        return [System.IO.Path]::GetFileName($Full)
    }

    $RootLabel = $Root.TrimEnd("\").Replace(":", "").Replace("\", "_").Replace("/", "_")

    if ([string]::IsNullOrWhiteSpace($RootLabel)) {
        $RootLabel = "Drive"
    }

    $Relative = $Full.Substring($Root.Length).TrimStart("\", "/")

    return (Join-Path ("Drive_" + $RootLabel) $Relative)
}

function Copy-PhotoBackupToDesktop {

    param(
        [object[]]$Photos
    )

    if ($null -eq $Photos -or $Photos.Count -eq 0) {
        Write-Host ""
        Write-Host "No photos were found to back up."
        return
    }

    $DesktopPath = [Environment]::GetFolderPath("Desktop")
    $PhotoBackupRoot = Join-Path $DesktopPath ("Photo-Backup-" + (Get-Date -Format "yyyy-MM-dd_HH-mm-ss"))

    New-Item `
        -ItemType Directory `
        -Path $PhotoBackupRoot `
        -Force `
        -ErrorAction Stop | Out-Null

    $Manifest = New-Object System.Collections.Generic.List[object]
    $Copied = 0
    $Failed = 0
    $CopiedBytes = [long]0

    Write-Host ""
    Write-Host "Backing up photos to:"
    Write-Host "  $PhotoBackupRoot"
    Write-Host ""

    foreach ($Photo in $Photos) {

        $Source = $Photo.FullName
        $Status = "Copied"
        $Destination = ""

        try {

            $Relative = Get-SafeBackupRelativePath -SourcePath $Source
            $Destination = Join-Path $PhotoBackupRoot $Relative
            $DestinationDirectory = Split-Path -Parent $Destination

            New-Item `
                -ItemType Directory `
                -Path $DestinationDirectory `
                -Force `
                -ErrorAction SilentlyContinue | Out-Null

            if (Test-Path -LiteralPath $Destination) {

                $Base = [System.IO.Path]::GetFileNameWithoutExtension($Destination)
                $Ext = [System.IO.Path]::GetExtension($Destination)
                $Dir = Split-Path -Parent $Destination
                $Counter = 2

                do {
                    $Destination = Join-Path $Dir ("{0} ({1}){2}" -f $Base, $Counter, $Ext)
                    $Counter++
                }
                until (-not (Test-Path -LiteralPath $Destination))
            }

            Copy-Item `
                -LiteralPath $Source `
                -Destination $Destination `
                -Force `
                -ErrorAction Stop

            $Copied++
            $CopiedBytes += [long]$Photo.Length
        }
        catch {
            $Status = "Failed: " + $_.Exception.Message
            $Failed++
        }

        $Manifest.Add(
            [PSCustomObject]@{
                Source        = $Source
                Destination   = $Destination
                SizeBytes     = $Photo.Length
                LastWriteTime = $Photo.LastWriteTime
                Status        = $Status
            }
        )
    }

    $ManifestPath = Join-Path $PhotoBackupRoot "Photo-Backup-Manifest.csv"

    $Manifest |
        Export-Csv `
            -Path $ManifestPath `
            -NoTypeInformation `
            -Encoding UTF8

    Write-Host ""
    Write-Host "Photo backup complete."
    Write-Host "Copied: $Copied"
    Write-Host "Failed: $Failed"
    Write-Host "Copied size: $(Format-Bytes $CopiedBytes)"
    Write-Host "Manifest:"
    Write-Host "  $ManifestPath"
    Write-Host ""

    if (Confirm-Action "Open the photo backup folder?") {
        Start-Process explorer.exe "`"$PhotoBackupRoot`""
    }
}

function Show-DrivePhotoSearchMenu {

    while ($true) {

        Write-Section "DRIVE PHOTO SEARCH / DESKTOP BACKUP"

        Write-Host "Supported photo types include:"
        Write-Host "JPG, JPEG, PNG, HEIC, HEIF, WEBP, AVIF, TIFF, BMP, GIF,"
        Write-Host "and many camera RAW formats such as DNG, CR2/CR3, NEF, ARW, RAF, ORF, RW2."
        Write-Host ""
        Write-Host "Backups are COPIED to the current Windows user's Desktop."
        Write-Host "Original photos are never moved or deleted."
        Write-Host ""
        Write-Host "1 - Deep search ALL accessible drives"
        Write-Host "2 - Search ONE drive"
        Write-Host "3 - Search ONE folder"
        Write-Host "4 - Quick search common photo folders"
        Write-Host "5 - Return"
        Write-Host ""

        $PhotoChoice = Read-Host "Choose 1, 2, 3, 4, or 5"

        if ($PhotoChoice -eq "5") {
            return
        }

        $Photos = New-Object System.Collections.Generic.List[object]
        $Roots = @()

        if ($PhotoChoice -eq "1") {

            $ReadyDrives = @(Get-ReadyPhotoDrives)

            if ($ReadyDrives.Count -eq 0) {
                Write-Warning "No accessible drives were found."
                Read-Host "Press Enter to continue"
                continue
            }

            Write-Host ""
            Write-Host "This performs a deep recursive search and can take a while on large drives."
            Write-Host ""

            foreach ($Drive in $ReadyDrives) {
                $Roots += $Drive.RootDirectory.FullName
            }
        }
        elseif ($PhotoChoice -eq "2") {

            $ReadyDrives = @(Get-ReadyPhotoDrives)

            if ($ReadyDrives.Count -eq 0) {
                Write-Warning "No accessible drives were found."
                Read-Host "Press Enter to continue"
                continue
            }

            Write-Host ""
            for ($i = 0; $i -lt $ReadyDrives.Count; $i++) {
                $Drive = $ReadyDrives[$i]

                $Label = ""
                try {
                    $Label = $Drive.VolumeLabel
                }
                catch {
                }

                Write-Host ("[{0}] {1}  {2}  {3}" -f ($i + 1), $Drive.Name, $Drive.DriveType, $Label)
            }

            Write-Host ""
            $DriveNumberText = Read-Host "Enter drive number"

            $DriveNumber = 0
            if (-not [int]::TryParse($DriveNumberText, [ref]$DriveNumber)) {
                Write-Warning "Invalid drive number."
                Read-Host "Press Enter to continue"
                continue
            }

            if ($DriveNumber -lt 1 -or $DriveNumber -gt $ReadyDrives.Count) {
                Write-Warning "Invalid drive number."
                Read-Host "Press Enter to continue"
                continue
            }

            $Roots += $ReadyDrives[$DriveNumber - 1].RootDirectory.FullName
        }
        elseif ($PhotoChoice -eq "3") {

            try {
                Add-Type -AssemblyName System.Windows.Forms

                $Dialog = New-Object System.Windows.Forms.FolderBrowserDialog
                $Dialog.Description = "Choose a folder to search for photos"
                $Dialog.ShowNewFolderButton = $false

                if ($Dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
                    continue
                }

                $Roots += $Dialog.SelectedPath
            }
            catch {
                Write-Warning "The Windows folder picker could not be opened."
                Read-Host "Press Enter to continue"
                continue
            }
        }
        elseif ($PhotoChoice -eq "4") {

            $CandidateRoots = @()

            $UserPictures = [Environment]::GetFolderPath("MyPictures")
            $DesktopPath = [Environment]::GetFolderPath("Desktop")
            $Downloads = Join-Path $env:USERPROFILE "Downloads"
            $OneDrivePictures = Join-Path $env:USERPROFILE "OneDrive\Pictures"
            $OneDrivePhotos = Join-Path $env:USERPROFILE "OneDrive\Photos"

            $CandidateRoots += $UserPictures
            $CandidateRoots += $DesktopPath
            $CandidateRoots += $Downloads
            $CandidateRoots += $OneDrivePictures
            $CandidateRoots += $OneDrivePhotos

            foreach ($Drive in @(Get-ReadyPhotoDrives)) {
                $CandidateRoots += (Join-Path $Drive.RootDirectory.FullName "DCIM")
                $CandidateRoots += (Join-Path $Drive.RootDirectory.FullName "Pictures")
                $CandidateRoots += (Join-Path $Drive.RootDirectory.FullName "Photos")
                $CandidateRoots += (Join-Path $Drive.RootDirectory.FullName "Camera")
            }

            $Roots = @(
                $CandidateRoots |
                    Where-Object {
                        $_ -and (Test-Path -LiteralPath $_)
                    } |
                    Select-Object -Unique
            )
        }
        else {
            continue
        }

        $DesktopPath = [Environment]::GetFolderPath("Desktop")

        foreach ($Root in ($Roots | Select-Object -Unique)) {
            Get-PhotoFilesFromRoot `
                -Root $Root `
                -Results $Photos `
                -DestinationRoot $DesktopPath
        }

        $FoundPhotos = @(
            $Photos |
                Sort-Object FullName -Unique
        )

        $TotalBytes = [long]0

        foreach ($Photo in $FoundPhotos) {
            $TotalBytes += [long]$Photo.Length
        }

        Write-Host ""
        Write-Host "============================================================"
        Write-Host "PHOTO SEARCH RESULTS"
        Write-Host "============================================================"
        Write-Host ""
        Write-Host "Photos found: $($FoundPhotos.Count)"
        Write-Host "Total size:   $(Format-Bytes $TotalBytes)"
        Write-Host ""

        $PhotoSearchReport = Join-Path `
            $Reports `
            ("Photo-Search-" + (Get-Date -Format "yyyy-MM-dd_HH-mm-ss") + ".csv")

        $FoundPhotos |
            Select-Object `
                FullName,
                Name,
                Extension,
                Length,
                LastWriteTime |
            Export-Csv `
                -Path $PhotoSearchReport `
                -NoTypeInformation `
                -Encoding UTF8

        Write-Host "Search report:"
        Write-Host "  $PhotoSearchReport"
        Write-Host ""

        if ($FoundPhotos.Count -gt 0) {

            $FoundPhotos |
                Sort-Object LastWriteTime -Descending |
                Select-Object `
                    -First 25 `
                    Name,
                    Extension,
                    @{
                        Name = "SizeMB"
                        Expression = {
                            [math]::Round($_.Length / 1MB, 2)
                        }
                    },
                    LastWriteTime,
                    FullName |
                Format-Table -AutoSize

            Write-Host ""
            Write-Host "Only the newest 25 results are shown here."
            Write-Host "The CSV report contains the full result list."
            Write-Host ""

            if (Confirm-Action "Copy ALL found photos to a dated backup folder on the Desktop?") {
                Copy-PhotoBackupToDesktop -Photos $FoundPhotos
            }
        }

        Read-Host "Press Enter to return"
    }
}


# ============================================================
# EXTERNAL DRIVE HEALTH / DIAGNOSIS
# ============================================================

function Get-ExternalDiskCandidates {

    $Items = @()

    try {
        $Disks = @(Get-Disk -ErrorAction SilentlyContinue)

        foreach ($Disk in $Disks) {

            $BusType = ""
            try { $BusType = [string]$Disk.BusType } catch {}

            $IsExternal = $false

            if ($BusType -match 'USB|SD|MMC|1394|Thunderbolt') {
                $IsExternal = $true
            }

            if ($IsExternal) {
                $Items += $Disk
            }
        }
    }
    catch {
    }

    return $Items
}

function Get-PhysicalDiskMatchForDisk {

    param(
        [object]$Disk
    )

    try {
        $Physical = @(Get-PhysicalDisk -ErrorAction SilentlyContinue)

        foreach ($P in $Physical) {

            $Match = $false

            try {
                if ($P.DeviceId -eq [string]$Disk.Number) {
                    $Match = $true
                }
            }
            catch {
            }

            if (-not $Match) {
                try {
                    if (
                        $Disk.FriendlyName -and
                        $P.FriendlyName -and
                        $Disk.FriendlyName -eq $P.FriendlyName
                    ) {
                        $Match = $true
                    }
                }
                catch {
                }
            }

            if ($Match) {
                return $P
            }
        }
    }
    catch {
    }

    return $null
}

function Show-ExternalDriveDiagnosis {

    Write-Section "EXTERNAL DRIVE HEALTH / DIAGNOSIS"

    Write-Host "This section performs read-only diagnostics by default."
    Write-Host "It does NOT format, initialize, repair, or erase the drive."
    Write-Host ""
    Write-Host "It can help distinguish:"
    Write-Host "- USB/enclosure/cable detection problems"
    Write-Host "- Drive present but no readable media"
    Write-Host "- Offline disks"
    Write-Host "- RAW or unknown filesystems"
    Write-Host "- Missing/invalid partitions"
    Write-Host "- SMART / storage-health warnings when the USB bridge exposes them"
    Write-Host "- Mac-formatted drives that Windows cannot natively mount"
    Write-Host ""

    $ExternalDisks = @(Get-ExternalDiskCandidates)

    if ($ExternalDisks.Count -eq 0) {

        Write-Warning "No external disks were detected by Windows Storage Management."
        Write-Host ""
        Write-Host "Possible causes include:"
        Write-Host "- bad USB cable"
        Write-Host "- insufficient power"
        Write-Host "- failing enclosure / USB-to-SATA bridge"
        Write-Host "- drive electronics failure"
        Write-Host "- device visible to Plug and Play but not exposed as a disk"
        Write-Host ""

        Write-Host "USB / storage devices currently visible to Windows:"
        Write-Host ""

        try {
            Get-PnpDevice `
                -PresentOnly `
                -ErrorAction SilentlyContinue |
                Where-Object {
                    $_.Class -in @("DiskDrive","USB","SCSIAdapter","Storage")
                } |
                Select-Object Status, Class, FriendlyName, InstanceId |
                Format-Table -AutoSize
        }
        catch {
            Write-Warning "Could not enumerate Plug and Play devices."
        }

        return
    }

    Write-Host "External disks detected:"
    Write-Host ""

    for ($i = 0; $i -lt $ExternalDisks.Count; $i++) {

        $Disk = $ExternalDisks[$i]

        Write-Host ("[{0}] Disk {1} - {2} - {3} - {4}" -f `
            ($i + 1),
            $Disk.Number,
            $Disk.FriendlyName,
            $Disk.BusType,
            (Format-Bytes ([long]$Disk.Size))
        )
    }

    Write-Host ""
    $SelectionText = Read-Host "Choose a disk number from the list"

    $Selection = 0

    if (-not [int]::TryParse($SelectionText, [ref]$Selection)) {
        Write-Warning "Invalid selection."
        return
    }

    if ($Selection -lt 1 -or $Selection -gt $ExternalDisks.Count) {
        Write-Warning "Invalid selection."
        return
    }

    $Disk = $ExternalDisks[$Selection - 1]

    Write-Host ""
    Write-Host "============================================================"
    Write-Host "DISK SUMMARY"
    Write-Host "============================================================"
    Write-Host ""

    Write-Host "Disk Number:        $($Disk.Number)"
    Write-Host "Name:               $($Disk.FriendlyName)"
    Write-Host "Serial Number:      $($Disk.SerialNumber)"
    Write-Host "Bus Type:           $($Disk.BusType)"
    Write-Host "Partition Style:    $($Disk.PartitionStyle)"
    Write-Host "Operational Status: $($Disk.OperationalStatus)"
    Write-Host "Health Status:      $($Disk.HealthStatus)"
    Write-Host "Offline:            $($Disk.IsOffline)"
    Write-Host "Read Only:          $($Disk.IsReadOnly)"
    Write-Host "Size:               $(Format-Bytes ([long]$Disk.Size))"
    Write-Host ""

    $Findings = New-Object System.Collections.Generic.List[string]

    if ($Disk.IsOffline) {
        $Findings.Add("Disk is OFFLINE. Windows sees the disk but is not currently using it.")
    }

    if ($Disk.Size -le 0) {
        $Findings.Add("Disk reports zero capacity or no usable media. Cable, enclosure/bridge, power, or hardware failure is possible.")
    }

    if ([string]$Disk.PartitionStyle -eq "RAW") {
        $Findings.Add("Partition style is RAW/unknown. The partition table may be missing, damaged, unsupported, or unreadable.")
    }

    if (
        $Disk.HealthStatus -and
        [string]$Disk.HealthStatus -notmatch '^Healthy$'
    ) {
        $Findings.Add("Windows reports disk health as $($Disk.HealthStatus).")
    }

    if (
        $Disk.OperationalStatus -and
        ([string]($Disk.OperationalStatus -join ",")) -notmatch 'Online|OK'
    ) {
        $Findings.Add("Operational status is $($Disk.OperationalStatus).")
    }

    Write-Host "Partitions and volumes:"
    Write-Host ""

    $Partitions = @()

    try {
        $Partitions = @(Get-Partition -DiskNumber $Disk.Number -ErrorAction SilentlyContinue)
    }
    catch {
    }

    if ($Partitions.Count -eq 0) {

        Write-Warning "No partitions were exposed by Windows."

        if ($Disk.Size -gt 0) {
            $Findings.Add("Disk has capacity but no readable partitions. It may be unpartitioned, have a damaged partition table, or use a filesystem/partition scheme Windows cannot interpret.")
        }
    }
    else {

        foreach ($Partition in $Partitions) {

            $Volume = $null

            try {
                $Volume = Get-Volume -Partition $Partition -ErrorAction SilentlyContinue
            }
            catch {
            }

            $DriveLetter = ""
            $FileSystem = ""
            $VolumeHealth = ""
            $VolumeSize = [long]0

            if ($null -ne $Volume) {
                $DriveLetter = $Volume.DriveLetter
                $FileSystem = [string]$Volume.FileSystem
                $VolumeHealth = [string]$Volume.HealthStatus
                $VolumeSize = [long]$Volume.Size
            }

            Write-Host ("Partition {0}: Drive={1}:  Type={2}  FS={3}  Health={4}  Size={5}" -f `
                $Partition.PartitionNumber,
                $DriveLetter,
                $Partition.Type,
                $FileSystem,
                $VolumeHealth,
                (Format-Bytes $VolumeSize)
            )

            if ([string]::IsNullOrWhiteSpace($FileSystem)) {
                $Findings.Add("Partition $($Partition.PartitionNumber) has no Windows-readable filesystem shown. This can happen with APFS/HFS+, Linux filesystems, damaged filesystems, or unformatted partitions.")
            }
            elseif ($FileSystem -eq "RAW") {
                $Findings.Add("Partition $($Partition.PartitionNumber) appears RAW. Do NOT format it if you need the data.")
            }
        }
    }

    Write-Host ""
    Write-Host "SMART / reliability information:"
    Write-Host ""

    $PhysicalDisk = Get-PhysicalDiskMatchForDisk -Disk $Disk

    if ($null -ne $PhysicalDisk) {

        Write-Host "Physical disk health:      $($PhysicalDisk.HealthStatus)"
        Write-Host "Operational status:        $($PhysicalDisk.OperationalStatus)"
        Write-Host "Media type:                $($PhysicalDisk.MediaType)"
        Write-Host "Cannot pool reason:        $($PhysicalDisk.CannotPoolReason)"
        Write-Host ""

        try {

            $Reliability = Get-StorageReliabilityCounter `
                -PhysicalDisk $PhysicalDisk `
                -ErrorAction Stop

            $Reliability |
                Select-Object `
                    Temperature,
                    TemperatureMax,
                    Wear,
                    PowerOnHours,
                    ReadErrorsTotal,
                    ReadErrorsUncorrected,
                    WriteErrorsTotal,
                    WriteErrorsUncorrected |
                Format-List

            if ($Reliability.ReadErrorsUncorrected -gt 0) {
                $Findings.Add("Uncorrected read errors were reported.")
            }

            if ($Reliability.WriteErrorsUncorrected -gt 0) {
                $Findings.Add("Uncorrected write errors were reported.")
            }

            if ($Reliability.Temperature -ge 55) {
                $Findings.Add("Drive temperature is high: $($Reliability.Temperature) C.")
            }
        }
        catch {

            Write-Host "Detailed SMART/reliability counters were not exposed."
            Write-Host "This is common with some USB enclosures and USB-to-SATA bridges."

            $Findings.Add("SMART data is unavailable through the current USB/enclosure interface. This does not prove the disk is healthy or unhealthy.")
        }
    }
    else {

        Write-Host "No matching PhysicalDisk object was found."
        Write-Host "The enclosure/bridge may not expose SMART information."

        $Findings.Add("Windows sees the logical disk, but SMART/reliability information is not available through this connection.")
    }

    Write-Host ""
    Write-Host "============================================================"
    Write-Host "DIAGNOSTIC FINDINGS"
    Write-Host "============================================================"
    Write-Host ""

    if ($Findings.Count -eq 0) {
        Write-Host "No obvious Windows storage-health problem was detected."
        Write-Host "If files still cannot be opened, the issue may be the filesystem, permissions, encryption, or application-level corruption."
    }
    else {
        foreach ($Finding in $Findings) {
            Write-Host "- $Finding"
        }
    }

    Write-Host ""
    Write-Host "IMPORTANT:"
    Write-Host "- If Windows asks to FORMAT an unfamiliar drive, choose Cancel if you need its data."
    Write-Host "- A spinning drive that powers on can still have bad heads, bad sectors, firmware problems, or a failing USB bridge."
    Write-Host "- If the drive repeatedly disconnects, clicks, grinds, or causes Windows to freeze, stop repeated scans and prioritize data recovery."
    Write-Host ""

    $DriveHealthReport = Join-Path `
        $Reports `
        ("External-Drive-Diagnosis-Disk{0}-{1}.txt" -f $Disk.Number, (Get-Date -Format "yyyy-MM-dd_HH-mm-ss"))

    $ReportLines = New-Object System.Collections.Generic.List[string]
    $ReportLines.Add("PC Maintenance U - External Drive Diagnosis")
    $ReportLines.Add("Date: $(Get-Date)")
    $ReportLines.Add("")
    $ReportLines.Add("Disk Number: $($Disk.Number)")
    $ReportLines.Add("Name: $($Disk.FriendlyName)")
    $ReportLines.Add("Serial Number: $($Disk.SerialNumber)")
    $ReportLines.Add("Bus Type: $($Disk.BusType)")
    $ReportLines.Add("Partition Style: $($Disk.PartitionStyle)")
    $ReportLines.Add("Operational Status: $($Disk.OperationalStatus)")
    $ReportLines.Add("Health Status: $($Disk.HealthStatus)")
    $ReportLines.Add("Offline: $($Disk.IsOffline)")
    $ReportLines.Add("Read Only: $($Disk.IsReadOnly)")
    $ReportLines.Add("Size: $(Format-Bytes ([long]$Disk.Size))")
    $ReportLines.Add("")
    $ReportLines.Add("Findings:")

    if ($Findings.Count -eq 0) {
        $ReportLines.Add("- No obvious Windows storage-health problem detected.")
    }
    else {
        foreach ($Finding in $Findings) {
            $ReportLines.Add("- $Finding")
        }
    }

    $ReportLines |
        Set-Content `
            -Path $DriveHealthReport `
            -Encoding UTF8

    Write-Host "Diagnostic report:"
    Write-Host "  $DriveHealthReport"
    Write-Host ""

    if (Confirm-Action "Open Windows Disk Management for a visual view of this drive?") {
        Start-Process diskmgmt.msc
    }
}

function Show-ExternalDriveHealthMenu {

    while ($true) {

        Write-Section "EXTERNAL DRIVE HEALTH"

        Write-Host "1 - Diagnose attached external HDD / SSD / USB storage"
        Write-Host "2 - Show all disks and volumes"
        Write-Host "3 - Open Disk Management"
        Write-Host "4 - Return"
        Write-Host ""

        $DriveChoice = Read-Host "Choose 1, 2, 3, or 4"

        switch ($DriveChoice) {

            "1" {
                Show-ExternalDriveDiagnosis
                Read-Host "Press Enter to continue"
            }

            "2" {

                Write-Host ""
                Write-Host "Disks:"
                Write-Host ""

                Get-Disk `
                    -ErrorAction SilentlyContinue |
                    Select-Object `
                        Number,
                        FriendlyName,
                        SerialNumber,
                        BusType,
                        PartitionStyle,
                        OperationalStatus,
                        HealthStatus,
                        IsOffline,
                        IsReadOnly,
                        Size |
                    Format-Table -AutoSize

                Write-Host ""
                Write-Host "Volumes:"
                Write-Host ""

                Get-Volume `
                    -ErrorAction SilentlyContinue |
                    Select-Object `
                        DriveLetter,
                        FileSystemLabel,
                        FileSystem,
                        HealthStatus,
                        OperationalStatus,
                        SizeRemaining,
                        Size |
                    Format-Table -AutoSize

                Read-Host "Press Enter to continue"
            }

            "3" {
                Start-Process diskmgmt.msc
            }

            "4" {
                return
            }
        }
    }
}


# ============================================================
# APPLE / MAC EXTERNAL DRIVE READER & RESCUE
# ============================================================

function Get-ApplePartitionClassification {

    param(
        [object]$Partition,
        [object]$Volume
    )

    $GptType = ""
    $FileSystem = ""

    try { $GptType = ([string]$Partition.GptType).ToUpperInvariant() } catch {}
    try { $FileSystem = ([string]$Volume.FileSystem).ToUpperInvariant() } catch {}

    if ($GptType -eq "{7C3457EF-0000-11AA-AA11-00306543ECAC}" -or
        $GptType -eq "7C3457EF-0000-11AA-AA11-00306543ECAC") {
        return "APFS"
    }

    if ($GptType -eq "{48465300-0000-11AA-AA11-00306543ECAC}" -or
        $GptType -eq "48465300-0000-11AA-AA11-00306543ECAC") {
        return "HFS/HFS+"
    }

    if ($GptType -eq "{426F6F74-0000-11AA-AA11-00306543ECAC}" -or
        $GptType -eq "426F6F74-0000-11AA-AA11-00306543ECAC") {
        return "Apple Boot"
    }

    if ($FileSystem -in @("EXFAT","FAT","FAT32","NTFS","REFS")) {
        return "Windows-readable"
    }

    if ([string]::IsNullOrWhiteSpace($FileSystem)) {
        return "Unknown/unsupported"
    }

    return $FileSystem
}

function Get-InstalledAppleFilesystemTools {

    $Matches = New-Object System.Collections.Generic.List[object]

    $RegistryPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    foreach ($Path in $RegistryPaths) {
        try {
            Get-ItemProperty -Path $Path -ErrorAction SilentlyContinue |
                Where-Object {
                    $_.DisplayName -and
                    $_.DisplayName -match 'Paragon|APFS|HFS|MacDrive|Mac Disk|MacDisk'
                } |
                ForEach-Object {
                    $Matches.Add(
                        [PSCustomObject]@{
                            Name    = $_.DisplayName
                            Version = $_.DisplayVersion
                        }
                    )
                }
        }
        catch {
        }
    }

    return @($Matches | Sort-Object Name, Version -Unique)
}

function Get-ReadableExternalVolumes {

    $Items = New-Object System.Collections.Generic.List[object]

    foreach ($Disk in @(Get-ExternalDiskCandidates)) {

        try {
            $Partitions = @(Get-Partition -DiskNumber $Disk.Number -ErrorAction SilentlyContinue)

            foreach ($Partition in $Partitions) {

                $Volume = $null
                try { $Volume = Get-Volume -Partition $Partition -ErrorAction SilentlyContinue } catch {}

                if (
                    $null -ne $Volume -and
                    $Volume.DriveLetter -and
                    -not [string]::IsNullOrWhiteSpace([string]$Volume.FileSystem)
                ) {
                    $Items.Add(
                        [PSCustomObject]@{
                            DiskNumber      = $Disk.Number
                            DiskName        = $Disk.FriendlyName
                            PartitionNumber = $Partition.PartitionNumber
                            DriveLetter     = [string]$Volume.DriveLetter
                            FileSystem      = [string]$Volume.FileSystem
                            Label           = [string]$Volume.FileSystemLabel
                            Size            = [long]$Volume.Size
                            Classification  = Get-ApplePartitionClassification -Partition $Partition -Volume $Volume
                        }
                    )
                }
            }
        }
        catch {
        }
    }

    return @($Items)
}

function Show-AppleDriveDetection {

    Write-Section "APPLE / MAC EXTERNAL DRIVE DETECTION"

    $ExternalDisks = @(Get-ExternalDiskCandidates)

    if ($ExternalDisks.Count -eq 0) {
        Write-Warning "No external disks are currently exposed by Windows Storage Management."
        Write-Host ""
        Write-Host "If the drive powers on but does not appear here, use:"
        Write-Host "  External Drive Health / Diagnosis"
        Write-Host "to check whether Windows can see the USB/enclosure hardware."
        return
    }

    foreach ($Disk in $ExternalDisks) {

        Write-Host "------------------------------------------------------------"
        Write-Host "Disk $($Disk.Number): $($Disk.FriendlyName)"
        Write-Host "Bus: $($Disk.BusType)"
        Write-Host "Size: $(Format-Bytes ([long]$Disk.Size))"
        Write-Host "Partition style: $($Disk.PartitionStyle)"
        Write-Host ""

        $Partitions = @()

        try {
            $Partitions = @(Get-Partition -DiskNumber $Disk.Number -ErrorAction SilentlyContinue)
        }
        catch {
        }

        if ($Partitions.Count -eq 0) {
            Write-Host "No partitions exposed by Windows."
            Write-Host ""
            continue
        }

        foreach ($Partition in $Partitions) {

            $Volume = $null
            try { $Volume = Get-Volume -Partition $Partition -ErrorAction SilentlyContinue } catch {}

            $Class = Get-ApplePartitionClassification -Partition $Partition -Volume $Volume

            $DriveLetter = ""
            $FileSystem = ""
            $Label = ""

            if ($null -ne $Volume) {
                $DriveLetter = [string]$Volume.DriveLetter
                $FileSystem = [string]$Volume.FileSystem
                $Label = [string]$Volume.FileSystemLabel
            }

            Write-Host "Partition $($Partition.PartitionNumber)"
            Write-Host "  Classification: $Class"
            Write-Host "  GPT type:       $($Partition.GptType)"
            Write-Host "  File system:    $FileSystem"
            Write-Host "  Drive letter:   $DriveLetter"
            Write-Host "  Label:          $Label"
            Write-Host ""

            if ($Class -eq "APFS" -or $Class -eq "HFS/HFS+") {
                if ([string]::IsNullOrWhiteSpace($DriveLetter)) {
                    Write-Host "  Windows detected an Apple-style partition but has not mounted it."
                    Write-Host "  DO NOT FORMAT IT if you need the data."
                    Write-Host ""
                }
            }
        }
    }
}

function Select-ReadableExternalVolume {

    $Volumes = @(Get-ReadableExternalVolumes)

    if ($Volumes.Count -eq 0) {
        Write-Warning "No readable external volumes with drive letters are currently available."
        return $null
    }

    Write-Host ""
    Write-Host "Readable external volumes:"
    Write-Host ""

    for ($i = 0; $i -lt $Volumes.Count; $i++) {
        $V = $Volumes[$i]

        Write-Host ("[{0}] {1}:\  {2}  {3}  {4}  {5}" -f `
            ($i + 1),
            $V.DriveLetter,
            $V.Label,
            $V.FileSystem,
            $V.Classification,
            (Format-Bytes $V.Size)
        )
    }

    Write-Host ""
    $ChoiceText = Read-Host "Choose a volume number"

    $ChoiceNumber = 0

    if (-not [int]::TryParse($ChoiceText, [ref]$ChoiceNumber)) {
        return $null
    }

    if ($ChoiceNumber -lt 1 -or $ChoiceNumber -gt $Volumes.Count) {
        return $null
    }

    return $Volumes[$ChoiceNumber - 1]
}

function Backup-ReadableExternalVolumeToDesktop {

    $Selected = Select-ReadableExternalVolume

    if ($null -eq $Selected) {
        return
    }

    $Source = "$($Selected.DriveLetter):\"
    $DesktopPath = [Environment]::GetFolderPath("Desktop")
    $SafeLabel = $Selected.Label

    if ([string]::IsNullOrWhiteSpace($SafeLabel)) {
        $SafeLabel = "Drive-$($Selected.DriveLetter)"
    }

    $SafeLabel = $SafeLabel -replace '[\\/:*?"<>|]', '_'

    $Destination = Join-Path `
        $DesktopPath `
        ("Mac-Drive-Backup-{0}-{1}" -f $SafeLabel, (Get-Date -Format "yyyy-MM-dd_HH-mm-ss"))

    Write-Host ""
    Write-Host "Source:"
    Write-Host "  $Source"
    Write-Host ""
    Write-Host "Backup destination:"
    Write-Host "  $Destination"
    Write-Host ""
    Write-Host "This is COPY-ONLY. Original files will not be moved or deleted."
    Write-Host ""

    if (-not (Confirm-Action "Begin full readable-volume backup?")) {
        return
    }

    New-Item `
        -ItemType Directory `
        -Path $Destination `
        -Force `
        -ErrorAction Stop | Out-Null

    $Log = Join-Path $Destination "robocopy-backup-log.txt"

    Write-Host ""
    Write-Host "Copying accessible files..."
    Write-Host "Large drives can take a long time."
    Write-Host ""

    & robocopy.exe `
        "$Source" `
        "$Destination" `
        /E `
        /COPY:DAT `
        /DCOPY:T `
        /R:1 `
        /W:1 `
        /XJ `
        /FFT `
        /TEE `
        /LOG:"$Log"

    $RoboExit = $LASTEXITCODE

    Write-Host ""
    Write-Host "Robocopy exit code: $RoboExit"
    Write-Host "Backup log:"
    Write-Host "  $Log"
    Write-Host ""

    if ($RoboExit -le 7) {
        Write-Host "Backup completed without a fatal Robocopy error."
    }
    else {
        Write-Warning "Robocopy reported one or more failures. Review the backup log."
    }

    if (Confirm-Action "Open the backup folder?") {
        Start-Process explorer.exe "`"$Destination`""
    }
}

function Show-AppleFilesystemSupport {

    Write-Section "APPLE FILESYSTEM SUPPORT"

    Write-Host "Windows can normally read exFAT/FAT/NTFS volumes directly."
    Write-Host ""
    Write-Host "APFS and HFS/HFS+ commonly require additional Windows filesystem software."
    Write-Host "PC Maintenance does not install or bundle proprietary filesystem drivers."
    Write-Host ""

    $Tools = @(Get-InstalledAppleFilesystemTools)

    if ($Tools.Count -eq 0) {
        Write-Host "No obvious third-party APFS/HFS filesystem package was detected."
    }
    else {
        Write-Host "Possible Apple filesystem tools detected:"
        Write-Host ""

        $Tools |
            Format-Table Name, Version -AutoSize
    }

    Write-Host ""
    Write-Host "If an Apple partition is detected but has no drive letter:"
    Write-Host "1. Do NOT initialize or format it if the files matter."
    Write-Host "2. Diagnose the hardware first."
    Write-Host "3. Use a compatible read-capable APFS/HFS solution or connect the drive to a Mac."
    Write-Host "4. Once Windows exposes a drive letter, PC Maintenance can search and copy its files."
    Write-Host ""
}

function Show-AppleDriveReaderMenu {

    while ($true) {

        Write-Section "APPLE / MAC EXTERNAL DRIVE READER & RESCUE"

        Write-Host "Read/search/backup first. This section does not format Apple drives."
        Write-Host ""
        Write-Host "1 - Detect Apple / Mac-formatted external drives"
        Write-Host "2 - Diagnose external drive hardware / health"
        Write-Host "3 - Open a readable external volume"
        Write-Host "4 - Search readable drives for files / lost files"
        Write-Host "5 - Search readable drives for photos / photo backup"
        Write-Host "6 - Search readable drives for code / projects"
        Write-Host "7 - Back up an entire readable external volume to Desktop"
        Write-Host "8 - Check APFS / HFS Windows support"
        Write-Host "9 - Open Disk Management"
        Write-Host "10 - Return"
        Write-Host ""

        $AppleChoice = Read-Host "Choose 1 through 10"

        switch ($AppleChoice) {

            "1" {
                Show-AppleDriveDetection
                Read-Host "Press Enter to continue"
            }

            "2" {
                Show-ExternalDriveDiagnosis
                Read-Host "Press Enter to continue"
            }

            "3" {
                $Selected = Select-ReadableExternalVolume

                if ($null -ne $Selected) {
                    Start-Process explorer.exe "$($Selected.DriveLetter):\"
                }
            }

            "4" {
                Write-Host ""
                Write-Host "Use the Deep File Search tool and choose the external drive as the search scope."
                Write-Host ""
                Show-FileSearchMenu
            }

            "5" {
                Show-DrivePhotoSearchMenu
            }

            "6" {
                Show-ProjectCodeSearchMenu
            }

            "7" {
                Backup-ReadableExternalVolumeToDesktop
                Read-Host "Press Enter to continue"
            }

            "8" {
                Show-AppleFilesystemSupport
                Read-Host "Press Enter to continue"
            }

            "9" {
                Start-Process diskmgmt.msc
            }

            "10" {
                return
            }
        }
    }
}

Clear-Host
Write-Host "============================================================"
Write-Host "          DESMOND PC MAINTENANCE $AppVersion"
Write-Host "============================================================"
Write-Host ""
Write-Host "1 - Scan Only"
Write-Host "2 - Standard Maintenance"
Write-Host "3 - Full Maintenance"
Write-Host "4 - Check for Program Updates"
Write-Host "5 - File Conversion"
Write-Host "6 - Deep File Search / Lost File Finder"
Write-Host "7 - Project / Code Search"
Write-Host "8 - WSL / Linux Terminal Maintenance"
Write-Host "9 - Speech Listener / Microphone"
Write-Host "10 - Drive Photo Search / Desktop Backup"
Write-Host "11 - External Drive Health / Diagnosis"
Write-Host "12 - Apple / Mac External Drive Reader & Rescue"
Write-Host "13 - Exit"
Write-Host ""

do {
    $Choice = Read-Host "Choose 1 through 13"
} until ($Choice -in @("1","2","3","4","5","6","7","8","9","10","11","12","13"))

if ($Choice -eq "13") {
    try { Stop-Transcript | Out-Null } catch {}
    exit
}

if ($Choice -eq "12") {
    Show-AppleDriveReaderMenu
    try { Stop-Transcript | Out-Null } catch {}
    exit
}

if ($Choice -eq "11") {
    Show-ExternalDriveHealthMenu
    try { Stop-Transcript | Out-Null } catch {}
    exit
}

if ($Choice -eq "10") {
    Show-DrivePhotoSearchMenu
    try { Stop-Transcript | Out-Null } catch {}
    exit
}

if ($Choice -eq "9") {
    Show-SpeechListenerMenu
    try { Stop-Transcript | Out-Null } catch {}
    exit
}

if ($Choice -eq "8") {
    Show-LinuxMaintenanceMenu
    try { Stop-Transcript | Out-Null } catch {}
    exit
}

if ($Choice -eq "7") {
    Show-ProjectCodeSearchMenu
    try { Stop-Transcript | Out-Null } catch {}
    exit
}

if ($Choice -eq "6") {
    Show-FileSearchMenu
    try { Stop-Transcript | Out-Null } catch {}
    exit
}

if ($Choice -eq "5") {
    Show-FileConversionMenu
    try { Stop-Transcript | Out-Null } catch {}
    exit
}

if ($Choice -eq "4") {
    $Updater = Join-Path $AppDirectory "Update-PC-Maintenance.ps1"

    if (-not (Test-Path -LiteralPath $Updater)) {
        Write-Host ""
        Write-Warning "Update-PC-Maintenance.ps1 is missing from this folder."
        Write-Host "Keep all PC Maintenance files together in the same folder."
        Write-Host ""
        Read-Host "Press Enter to close"
        try { Stop-Transcript | Out-Null } catch {}
        exit
    }

    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Updater -AppDirectory $AppDirectory
    Write-Host ""
    Write-Host "If an update was installed, close this window and run PC Maintenance again."
    Write-Host ""
    Read-Host "Press Enter to close"
    try { Stop-Transcript | Out-Null } catch {}
    exit
}

$ScanOnly = ($Choice -eq "1")
$FullMaintenance = ($Choice -eq "3")

# 1. SYSTEM INFORMATION
Write-Section "[1/14] SYSTEM INFORMATION"

try {
    $OS = Get-CimInstance Win32_OperatingSystem
    $Computer = Get-CimInstance Win32_ComputerSystem
    $CPU = Get-CimInstance Win32_Processor | Select-Object -First 1
    $RAM = [math]::Round($Computer.TotalPhysicalMemory / 1GB, 2)
    $Uptime = (Get-Date) - $OS.LastBootUpTime

    Write-Host "Computer: $env:COMPUTERNAME"
    Write-Host "Windows:  $($OS.Caption)"
    Write-Host "Build:    $($OS.BuildNumber)"
    Write-Host "CPU:      $($CPU.Name)"
    Write-Host "RAM:      $RAM GB"
    Write-Host "Uptime:   $([math]::Round($Uptime.TotalHours, 1)) hours"

    Add-Result "System Information" "OK" "$($OS.Caption), Build $($OS.BuildNumber), $RAM GB RAM"
}
catch {
    Add-Result "System Information" "Warning" $_.Exception.Message
}

# 2. STORAGE / DISK HEALTH
Write-Section "[2/14] STORAGE AND DISK HEALTH"

try {
    $DriveLetter = $env:SystemDrive.TrimEnd(":")
    $Volume = Get-Volume -DriveLetter $DriveLetter -ErrorAction Stop
    $Used = $Volume.Size - $Volume.SizeRemaining

    Write-Host "System Drive: $env:SystemDrive"
    Write-Host "Capacity:     $(Format-Bytes $Volume.Size)"
    Write-Host "Used:         $(Format-Bytes $Used)"
    Write-Host "Free:         $(Format-Bytes $Volume.SizeRemaining)"
    Write-Host "Health:       $($Volume.HealthStatus)"

    Add-Result "System Drive" "$($Volume.HealthStatus)" "$(Format-Bytes $Volume.SizeRemaining) free"
}
catch {
    Add-Result "System Drive" "Warning" $_.Exception.Message
}

try {
    $PhysicalDisks = @(Get-PhysicalDisk -ErrorAction Stop)
    $PhysicalDisks |
        Select-Object FriendlyName, MediaType, Size, HealthStatus, OperationalStatus |
        Export-Csv (Join-Path $Reports "PhysicalDisks-$Stamp.csv") -NoTypeInformation

    $PhysicalDisks |
        Select-Object FriendlyName, MediaType, HealthStatus, OperationalStatus |
        Format-Table -AutoSize

    Add-Result "Physical Disks" "Report" "$($PhysicalDisks.Count) disk(s) detected"
}
catch {
    Add-Result "Physical Disks" "Unavailable" $_.Exception.Message
}

# 3. TEMP / JUNK ANALYSIS
Write-Section "[3/14] TEMPORARY FILE AND JUNK ANALYSIS"

$UserTemp = $env:TEMP
$WindowsTemp = Join-Path $env:SystemRoot "Temp"
$CrashDumps = Join-Path $env:LOCALAPPDATA "CrashDumps"
$RecycleRoot = Join-Path $env:SystemDrive '$Recycle.Bin'

$UserTempSize = Get-FolderSizeBytes $UserTemp
$WindowsTempSize = Get-FolderSizeBytes $WindowsTemp
$CrashDumpSize = Get-FolderSizeBytes $CrashDumps
$RecycleSize = Get-FolderSizeBytes $RecycleRoot
$PotentialCleanup = $UserTempSize + $WindowsTempSize + $CrashDumpSize + $RecycleSize

Write-Host "User temp:      $(Format-Bytes $UserTempSize)"
Write-Host "Windows temp:   $(Format-Bytes $WindowsTempSize)"
Write-Host "Crash dumps:    $(Format-Bytes $CrashDumpSize)"
Write-Host "Recycle Bin:    $(Format-Bytes $RecycleSize)"
Write-Host "Potential total $(Format-Bytes $PotentialCleanup)"

Add-Result "Temporary Files" "Found" "$(Format-Bytes $PotentialCleanup) potentially removable"

if (-not $ScanOnly) {
    if (Confirm-Action "Clean temporary files, crash dumps, and Recycle Bin?") {
        Clear-FolderContents $UserTemp
        Clear-FolderContents $WindowsTemp
        Clear-FolderContents $CrashDumps

        try { Clear-RecycleBin -Force -Confirm:$false -ErrorAction Stop } catch {}

        $After = (
            (Get-FolderSizeBytes $UserTemp) +
            (Get-FolderSizeBytes $WindowsTemp) +
            (Get-FolderSizeBytes $CrashDumps) +
            (Get-FolderSizeBytes $RecycleRoot)
        )
        $Recovered = $PotentialCleanup - $After
        if ($Recovered -lt 0) { $Recovered = 0 }

        Write-Host "Approximately recovered: $(Format-Bytes $Recovered)"
        Add-Result "Temporary File Cleanup" "Completed" "$(Format-Bytes $Recovered) recovered"
    }
}

# 4. STARTUP APPLICATIONS
Write-Section "[4/14] STARTUP APPLICATIONS"

try {
    $StartupApps = @(Get-CimInstance Win32_StartupCommand -ErrorAction Stop)
    $StartupReport = Join-Path $Reports "StartupApps-$Stamp.csv"

    $StartupApps |
        Select-Object Name, Command, Location, User |
        Export-Csv $StartupReport -NoTypeInformation

    Write-Host "Startup entries found: $($StartupApps.Count)"
    $StartupApps | Select-Object Name, Location, User | Format-Table -AutoSize

    Add-Result "Startup Applications" "Report" "$($StartupApps.Count) startup entries"
}
catch {
    Add-Result "Startup Applications" "Warning" $_.Exception.Message
}

# 5. HEAVY PROCESSES
Write-Section "[5/14] RESOURCE-HEAVY PROCESSES"

try {
    $TopMemory = Get-Process -ErrorAction SilentlyContinue |
        Sort-Object WorkingSet64 -Descending |
        Select-Object -First 15 ProcessName, Id,
            @{Name="MemoryMB";Expression={[math]::Round($_.WorkingSet64 / 1MB, 2)}},
            CPU

    $ProcessReport = Join-Path $Reports "HeavyProcesses-$Stamp.csv"
    $TopMemory | Export-Csv $ProcessReport -NoTypeInformation
    $TopMemory | Format-Table -AutoSize

    Add-Result "Running Processes" "Report" "Top 15 memory consumers recorded"
}
catch {
    Add-Result "Running Processes" "Warning" $_.Exception.Message
}

# 6. BROKEN SHORTCUTS
Write-Section "[6/14] BROKEN SHORTCUT SCAN"

function Get-BrokenLocalShortcuts {
    $Shell = New-Object -ComObject WScript.Shell

    $Folders = @(
        [Environment]::GetFolderPath("Desktop"),
        [Environment]::GetFolderPath("CommonDesktopDirectory"),
        [Environment]::GetFolderPath("StartMenu"),
        [Environment]::GetFolderPath("CommonStartMenu")
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique

    foreach ($Folder in $Folders) {
        $Links = Get-ChildItem -LiteralPath $Folder -Filter "*.lnk" -File -Recurse -ErrorAction SilentlyContinue

        foreach ($Link in $Links) {
            try {
                $Shortcut = $Shell.CreateShortcut($Link.FullName)
                $Target = $Shortcut.TargetPath

                if ([string]::IsNullOrWhiteSpace($Target)) { continue }

                if ($Target -match '^[A-Za-z]:\\' -and -not (Test-Path -LiteralPath $Target -ErrorAction SilentlyContinue)) {
                    [PSCustomObject]@{
                        Shortcut = $Link.FullName
                        Target   = $Target
                    }
                }
            }
            catch {}
        }
    }
}

$BrokenShortcuts = @(Get-BrokenLocalShortcuts)
$BrokenShortcutReport = Join-Path $Reports "BrokenShortcuts-$Stamp.csv"
$BrokenShortcuts | Export-Csv $BrokenShortcutReport -NoTypeInformation

Write-Host "Broken local shortcuts found: $($BrokenShortcuts.Count)"
if ($BrokenShortcuts.Count -gt 0) {
    $BrokenShortcuts | Format-Table Shortcut, Target -AutoSize
}

Add-Result "Broken Shortcuts" "Found" "$($BrokenShortcuts.Count) broken local shortcuts"

if (-not $ScanOnly -and $BrokenShortcuts.Count -gt 0) {
    if (Confirm-Action "Back up and remove the broken local shortcuts?") {
        $ShortcutBackup = Join-Path $Backups "BrokenShortcuts-$Stamp"
        New-Item -ItemType Directory -Path $ShortcutBackup -Force | Out-Null
        $Removed = 0

        foreach ($Broken in $BrokenShortcuts) {
            try {
                $OriginalName = [IO.Path]::GetFileNameWithoutExtension($Broken.Shortcut)
                $BackupName = "$OriginalName-$([guid]::NewGuid().ToString()).lnk"
                Copy-Item -LiteralPath $Broken.Shortcut -Destination (Join-Path $ShortcutBackup $BackupName) -Force
                Remove-Item -LiteralPath $Broken.Shortcut -Force -ErrorAction Stop
                $Removed++
            }
            catch {}
        }

        Add-Result "Broken Shortcut Cleanup" "Completed" "$Removed removed after backup"
    }
}

# 7. MUICACHE
Write-Section "[7/14] MUICACHE REGISTRY CHECK"

$MuiKey = "HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\MuiCache"
$StaleMuiEntries = @()

try {
    $MuiProperties = (Get-ItemProperty -Path $MuiKey -ErrorAction Stop).PSObject.Properties |
        Where-Object { $_.Name -match '\.(FriendlyAppName|ApplicationCompany)$' }

    foreach ($Property in $MuiProperties) {
        $Path = $Property.Name -replace '\.(FriendlyAppName|ApplicationCompany)$',''

        $SafeUserPath = (
            $Path.StartsWith($env:USERPROFILE, [System.StringComparison]::OrdinalIgnoreCase) -or
            $Path.StartsWith($env:LOCALAPPDATA, [System.StringComparison]::OrdinalIgnoreCase)
        )

        if ($SafeUserPath -and -not (Test-Path -LiteralPath $Path -ErrorAction SilentlyContinue)) {
            $StaleMuiEntries += [PSCustomObject]@{
                Property = $Property.Name
                Path     = $Path
            }
        }
    }

    $MuiReport = Join-Path $Reports "MuiCache-$Stamp.csv"
    $StaleMuiEntries | Export-Csv $MuiReport -NoTypeInformation
    Write-Host "Safe stale MuiCache entries: $($StaleMuiEntries.Count)"

    Add-Result "MuiCache" "Found" "$($StaleMuiEntries.Count) safe stale entries"
}
catch {
    Add-Result "MuiCache" "Warning" $_.Exception.Message
}

if (-not $ScanOnly -and $StaleMuiEntries.Count -gt 0) {
    if (Confirm-Action "Back up MuiCache and remove safe stale entries?") {
        $MuiBackup = Join-Path $Backups "MuiCache-$Stamp.reg"

        reg.exe export `
            "HKCU\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\MuiCache" `
            "$MuiBackup" /y | Out-Null

        $RemovedMui = 0

        foreach ($Entry in $StaleMuiEntries) {
            try {
                Remove-ItemProperty -Path $MuiKey -Name $Entry.Property -ErrorAction Stop
                $RemovedMui++
            }
            catch {}
        }

        Add-Result "MuiCache Cleanup" "Completed" "$RemovedMui removed after backup"
    }
}

# 8. SHAREDDLL SCAN
Write-Section "[8/14] SHAREDDLL REGISTRY CHECK"

$SharedDllRegistryPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\SharedDLLs",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\SharedDLLs"
)

$BrokenSharedDllEntries = @()

foreach ($RegistryPath in $SharedDllRegistryPaths) {
    if (-not (Test-Path -LiteralPath $RegistryPath)) { continue }

    try {
        $Properties = (Get-ItemProperty -Path $RegistryPath -ErrorAction Stop).PSObject.Properties |
            Where-Object {
                $_.Name -notin @("PSPath","PSParentPath","PSChildName","PSDrive","PSProvider")
            }

        foreach ($Property in $Properties) {
            $FilePath = [Environment]::ExpandEnvironmentVariables($Property.Name.Trim('"'))

            if ($FilePath -match '^[A-Za-z]:\\' -and -not (Test-Path -LiteralPath $FilePath -ErrorAction SilentlyContinue)) {
                $BrokenSharedDllEntries += [PSCustomObject]@{
                    RegistryPath = $RegistryPath
                    Property     = $Property.Name
                    Count        = $Property.Value
                }
            }
        }
    }
    catch {}
}

$SharedDllReport = Join-Path $Reports "SharedDLL-$Stamp.csv"
$BrokenSharedDllEntries | Export-Csv $SharedDllReport -NoTypeInformation

Write-Host "Missing SharedDLL local-file references: $($BrokenSharedDllEntries.Count)"
Add-Result "SharedDLL Registry" "Found" "$($BrokenSharedDllEntries.Count) missing local-file references"

if ($FullMaintenance -and $BrokenSharedDllEntries.Count -gt 0) {
    Write-Host ""
    Write-Host "This cleanup is optional and will back up the relevant registry keys first."

    if (Confirm-Action "Remove detected missing SharedDLL references?") {
        $Key64 = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\SharedDLLs"
        $Key32 = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\SharedDLLs"

        if (Test-Path -LiteralPath $Key64) {
            reg.exe export "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\SharedDLLs" `
                (Join-Path $Backups "SharedDLL-64-$Stamp.reg") /y | Out-Null
        }

        if (Test-Path -LiteralPath $Key32) {
            reg.exe export "HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\SharedDLLs" `
                (Join-Path $Backups "SharedDLL-32-$Stamp.reg") /y | Out-Null
        }

        $RemovedShared = 0

        foreach ($Entry in $BrokenSharedDllEntries) {
            try {
                Remove-ItemProperty -Path $Entry.RegistryPath -Name $Entry.Property -ErrorAction Stop
                $RemovedShared++
            }
            catch {}
        }

        Add-Result "SharedDLL Cleanup" "Completed" "$RemovedShared removed after registry backup"
    }
}

# 9. DISM / SFC
Write-Section "[9/14] WINDOWS SYSTEM INTEGRITY"

if ($ScanOnly) {
    & DISM.exe /Online /Cleanup-Image /ScanHealth
    $DismExit = $LASTEXITCODE
    Add-Result "DISM Scan" "Completed" "Exit code $DismExit"

    & sfc.exe /verifyonly
    $SfcExit = $LASTEXITCODE
    Add-Result "SFC Verify" "Completed" "Exit code $SfcExit"
}
else {
    & DISM.exe /Online /Cleanup-Image /RestoreHealth
    $DismExit = $LASTEXITCODE
    Add-Result "DISM Repair" "Completed" "Exit code $DismExit"

    & sfc.exe /scannow
    $SfcExit = $LASTEXITCODE
    Add-Result "SFC Repair" "Completed" "Exit code $SfcExit"

    if ($FullMaintenance -and (Confirm-Action "Run Windows component-store cleanup?")) {
        & DISM.exe /Online /Cleanup-Image /StartComponentCleanup
        Add-Result "Component Store Cleanup" "Completed" "Exit code $LASTEXITCODE"
    }
}

# 10. WINDOWS UPDATE
Write-Section "[10/14] WINDOWS UPDATE CHECK"

try {
    $Session = New-Object -ComObject Microsoft.Update.Session
    $Searcher = $Session.CreateUpdateSearcher()
    $SearchResult = $Searcher.Search("IsInstalled=0 and IsHidden=0")

    $Updates = @()
    foreach ($Update in $SearchResult.Updates) {
        $Updates += [PSCustomObject]@{ Title = $Update.Title }
    }

    $UpdateReport = Join-Path $Reports "WindowsUpdates-$Stamp.csv"
    $Updates | Export-Csv $UpdateReport -NoTypeInformation

    Write-Host "Pending Windows updates: $($Updates.Count)"
    if ($Updates.Count -gt 0) { $Updates | Format-Table -AutoSize }

    Add-Result "Windows Update" "Report" "$($Updates.Count) available updates detected"
}
catch {
    Add-Result "Windows Update" "Warning" $_.Exception.Message
}

# 11. WINGET APP UPDATES
Write-Section "[11/14] APPLICATION UPDATE CHECK"

$Winget = Get-Command winget.exe -ErrorAction SilentlyContinue

if ($null -ne $Winget) {
    $WingetReport = Join-Path $Reports "WingetUpdates-$Stamp.txt"

    & $Winget.Source upgrade --accept-source-agreements 2>&1 |
        Tee-Object -FilePath $WingetReport

    Add-Result "Application Updates" "Report" "winget update report generated"

    if ($FullMaintenance -and (Confirm-Action "Update all applications supported by winget?")) {
        & $Winget.Source upgrade --all --accept-source-agreements --accept-package-agreements --disable-interactivity
        Add-Result "Application Update Installation" "Completed" "winget exit code $LASTEXITCODE"
    }
}
else {
    Add-Result "Application Updates" "Unavailable" "winget.exe not found"
}

# 12. SECURITY / DEFENDER / FIREWALL
Write-Section "[12/14] WINDOWS SECURITY"

try {
    $AntivirusProducts = @(Get-CimInstance -Namespace root/SecurityCenter2 -ClassName AntiVirusProduct -ErrorAction Stop)
    $AntivirusProducts | Select-Object displayName | Format-Table -AutoSize
    Add-Result "Registered Antivirus" "Report" "$($AntivirusProducts.Count) antivirus product(s) registered"
}
catch {
    Add-Result "Registered Antivirus" "Warning" $_.Exception.Message
}

$DefenderAvailable = $false

if (Get-Command Get-MpComputerStatus -ErrorAction SilentlyContinue) {
    try {
        $Defender = Get-MpComputerStatus
        $DefenderAvailable = $true

        Write-Host "Defender Antivirus enabled:    $($Defender.AntivirusEnabled)"
        Write-Host "Defender Real-time protection: $($Defender.RealTimeProtectionEnabled)"

        Add-Result "Microsoft Defender" "Report" "AV=$($Defender.AntivirusEnabled), RealTime=$($Defender.RealTimeProtectionEnabled)"
    }
    catch {}
}

if ($FullMaintenance -and $DefenderAvailable -and (Confirm-Action "Run a Microsoft Defender Quick Scan?")) {
    try {
        Start-MpScan -ScanType QuickScan -ErrorAction Stop
        Add-Result "Defender Quick Scan" "Completed" "Quick scan command completed"
    }
    catch {
        Add-Result "Defender Quick Scan" "Unavailable" $_.Exception.Message
    }
}

try {
    $FirewallProfiles = @(Get-NetFirewallProfile -ErrorAction Stop)
    $FirewallProfiles | Select-Object Name, Enabled | Format-Table -AutoSize
    $DisabledProfiles = @($FirewallProfiles | Where-Object { -not $_.Enabled })

    Add-Result "Windows Firewall" "Report" "$($DisabledProfiles.Count) disabled profile(s)"

    if (-not $ScanOnly -and $DisabledProfiles.Count -gt 0 -and (Confirm-Action "Enable disabled Windows Firewall profiles?")) {
        foreach ($Profile in $DisabledProfiles) {
            try {
                Set-NetFirewallProfile -Profile $Profile.Name -Enabled True -ErrorAction Stop
            }
            catch {}
        }

        Add-Result "Windows Firewall Repair" "Completed" "Disabled profiles were enabled where possible"
    }
}
catch {
    Add-Result "Windows Firewall" "Warning" $_.Exception.Message
}

# 13. NETWORK / VPN / ONEDRIVE
Write-Section "[13/14] NETWORK DIAGNOSTICS"

try {
    $NetworkReport = Join-Path $Reports "Network-$Stamp.txt"

    Get-NetIPConfiguration |
        Format-List * |
        Out-String |
        Out-File -FilePath $NetworkReport -Encoding UTF8

    $HttpsWorking = Test-NetConnection -ComputerName "www.microsoft.com" -Port 443 -InformationLevel Quiet -WarningAction SilentlyContinue

    $DnsWorking = $false
    try {
        $DnsResult = Resolve-DnsName microsoft.com -ErrorAction Stop | Select-Object -First 1
        if ($null -ne $DnsResult) { $DnsWorking = $true }
    }
    catch {}

    Write-Host "HTTPS connectivity: $HttpsWorking"
    Write-Host "DNS resolution:     $DnsWorking"

    Add-Result "Network" "Report" "HTTPS=$HttpsWorking, DNS=$DnsWorking"
}
catch {
    Add-Result "Network" "Warning" $_.Exception.Message
}

if (Get-Command Get-VpnConnection -ErrorAction SilentlyContinue) {
    try {
        $VpnConnections = @(Get-VpnConnection -ErrorAction SilentlyContinue)
        $VpnConnections | Export-Csv (Join-Path $Reports "VPN-$Stamp.csv") -NoTypeInformation
        Add-Result "VPN" "Report" "$($VpnConnections.Count) Windows VPN connection(s)"
    }
    catch {}
}

$OneDrive = Get-Process OneDrive -ErrorAction SilentlyContinue

if ($null -ne $OneDrive) {
    Add-Result "OneDrive" "Running" "OneDrive process detected"
}
else {
    Add-Result "OneDrive" "Not Running" "No OneDrive process detected"
}

# 14. BATTERY REPORT
Write-Section "[14/14] BATTERY REPORT"

$BatteryReport = Join-Path $Reports "battery-report-$Stamp.html"

try {
    & powercfg.exe /batteryreport /output "$BatteryReport"

    if (Test-Path -LiteralPath $BatteryReport) {
        Write-Host "Battery report:"
        Write-Host $BatteryReport
        Add-Result "Battery Report" "Completed" $BatteryReport
    }
    else {
        Add-Result "Battery Report" "Unavailable" "No report was created"
    }
}
catch {
    Add-Result "Battery Report" "Warning" $_.Exception.Message
}

# FINAL SUMMARY
Write-Section "MAINTENANCE SUMMARY"

$script:Results | Format-Table Component, Status, Details -AutoSize
$script:Results | Export-Csv -Path $SummaryPath -NoTypeInformation

Write-Host ""
Write-Host "Reports: $Reports"
Write-Host "Backups: $Backups"
Write-Host "Summary: $SummaryPath"
Write-Host "Log:     $LogPath"
Write-Host ""

try { Stop-Transcript | Out-Null } catch {}

if (Confirm-Action "Open the maintenance report folder?") {
    Start-Process explorer.exe "`"$Reports`""
}

Write-Host ""
Write-Host "Press Enter to close."
Read-Host
