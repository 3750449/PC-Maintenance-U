#requires -Version 5.1

param(
    [Parameter(Mandatory = $false)]
    [string]$AppDirectory = $PSScriptRoot
)

$ErrorActionPreference = "Stop"

$RepoOwner = "3750449"
$RepoName = "PC-Maintenance-U"
$Branch = "main"

$RawBase = "https://raw.githubusercontent.com/$RepoOwner/$RepoName/$Branch"
$ArchiveUrl = "https://github.com/$RepoOwner/$RepoName/archive/refs/heads/$Branch.zip"

$RequiredFiles = @(
    "PC-Maintenance.ps1",
    "Run-PC-Maintenance.bat",
    "Update-PC-Maintenance.ps1",
    "version.txt"
)

function Read-VersionFile {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return [version]"0.0.0"
    }

    try {
        $value = (Get-Content -LiteralPath $Path -Raw -ErrorAction Stop).Trim()
        return [version]$value
    }
    catch {
        return [version]"0.0.0"
    }
}

function Test-PowerShellFile {
    param([string]$Path)

    $tokens = $null
    $errors = $null

    [System.Management.Automation.Language.Parser]::ParseFile(
        $Path,
        [ref]$tokens,
        [ref]$errors
    ) | Out-Null

    if ($errors.Count -gt 0) {
        Write-Host ""
        Write-Host "PowerShell syntax validation failed for:"
        Write-Host $Path
        Write-Host ""
        $errors | ForEach-Object {
            Write-Host $_.Message
        }
        return $false
    }

    return $true
}

Clear-Host
Write-Host "============================================================"
Write-Host "             PC MAINTENANCE UPDATE CHECK"
Write-Host "============================================================"
Write-Host ""
Write-Host "Repository: https://github.com/$RepoOwner/$RepoName"
Write-Host ""

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    $LocalVersionPath = Join-Path $AppDirectory "version.txt"
    $LocalVersion = Read-VersionFile $LocalVersionPath

    Write-Host "Installed version: $LocalVersion"
    Write-Host "Checking GitHub..."
    Write-Host ""

    try {
        $RemoteText = Invoke-WebRequest `
            -Uri "$RawBase/version.txt" `
            -UseBasicParsing `
            -Headers @{ "Cache-Control" = "no-cache" } `
            -ErrorAction Stop
    }
    catch {
        Write-Host "Could not read version.txt from GitHub."
        Write-Host ""
        Write-Host "Make sure:"
        Write-Host "  1. The repository is PUBLIC."
        Write-Host "  2. The branch is named main."
        Write-Host "  3. version.txt is in the repository root."
        Write-Host ""
        Write-Host "Repository expected:"
        Write-Host "https://github.com/$RepoOwner/$RepoName"
        Write-Host ""
        Read-Host "Press Enter to close"
        exit 1
    }

    $RemoteVersion = [version]$RemoteText.Content.Trim()

    Write-Host "GitHub version:    $RemoteVersion"
    Write-Host ""

    if ($RemoteVersion -le $LocalVersion) {
        Write-Host "PC Maintenance is already up to date."
        Write-Host ""
        Read-Host "Press Enter to close"
        exit 0
    }

    Write-Host "A newer version is available: $RemoteVersion"
    Write-Host ""
    $Answer = Read-Host "Download and install this update? [Y/n]"

    if ($Answer -match '^[Nn]$') {
        Write-Host "Update cancelled."
        Write-Host ""
        Read-Host "Press Enter to close"
        exit 0
    }

    $TempRoot = Join-Path $env:TEMP ("PC-Maintenance-Update-" + [guid]::NewGuid().ToString())
    $ZipPath = Join-Path $TempRoot "update.zip"
    $ExtractPath = Join-Path $TempRoot "extracted"

    New-Item -ItemType Directory -Path $TempRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $ExtractPath -Force | Out-Null

    Write-Host ""
    Write-Host "Downloading update..."

    Invoke-WebRequest `
        -Uri $ArchiveUrl `
        -OutFile $ZipPath `
        -UseBasicParsing `
        -ErrorAction Stop

    Write-Host "Extracting update..."
    Expand-Archive -LiteralPath $ZipPath -DestinationPath $ExtractPath -Force

    $SourceRoot = Get-ChildItem -LiteralPath $ExtractPath -Directory -ErrorAction Stop |
        Where-Object {
            Test-Path -LiteralPath (Join-Path $_.FullName "PC-Maintenance.ps1")
        } |
        Select-Object -First 1

    if ($null -eq $SourceRoot) {
        throw "The downloaded repository does not contain PC-Maintenance.ps1 in its root."
    }

    foreach ($File in $RequiredFiles) {
        $Candidate = Join-Path $SourceRoot.FullName $File
        if (-not (Test-Path -LiteralPath $Candidate)) {
            throw "The downloaded update is missing required file: $File"
        }
    }

    $DownloadedVersion = Read-VersionFile (Join-Path $SourceRoot.FullName "version.txt")

    if ($DownloadedVersion -ne $RemoteVersion) {
        throw "Downloaded version.txt does not match the version reported by GitHub."
    }

    Write-Host "Validating PowerShell files..."

    if (-not (Test-PowerShellFile (Join-Path $SourceRoot.FullName "PC-Maintenance.ps1"))) {
        throw "PC-Maintenance.ps1 failed syntax validation."
    }

    if (-not (Test-PowerShellFile (Join-Path $SourceRoot.FullName "Update-PC-Maintenance.ps1"))) {
        throw "Update-PC-Maintenance.ps1 failed syntax validation."
    }

    $Documents = [Environment]::GetFolderPath("MyDocuments")
    $BackupRoot = Join-Path $Documents "Desmond-PC-Maintenance\ProgramBackups"
    $BackupFolder = Join-Path $BackupRoot (Get-Date -Format "yyyy-MM-dd_HH-mm-ss")

    New-Item -ItemType Directory -Path $BackupFolder -Force | Out-Null

    Write-Host "Backing up current program..."

    foreach ($File in $RequiredFiles) {
        $CurrentFile = Join-Path $AppDirectory $File
        if (Test-Path -LiteralPath $CurrentFile) {
            Copy-Item -LiteralPath $CurrentFile -Destination $BackupFolder -Force
        }
    }

    Write-Host "Installing version $RemoteVersion..."

    try {
        foreach ($Item in Get-ChildItem -LiteralPath $SourceRoot.FullName -File) {
            Copy-Item -LiteralPath $Item.FullName -Destination $AppDirectory -Force
        }
    }
    catch {
        Write-Host "Install failed. Restoring previous files..."

        foreach ($BackupFile in Get-ChildItem -LiteralPath $BackupFolder -File -ErrorAction SilentlyContinue) {
            Copy-Item -LiteralPath $BackupFile.FullName -Destination $AppDirectory -Force
        }

        throw
    }

    Write-Host ""
    Write-Host "============================================================"
    Write-Host "UPDATE COMPLETE"
    Write-Host "============================================================"
    Write-Host ""
    Write-Host "Installed version: $RemoteVersion"
    Write-Host "Backup: $BackupFolder"
    Write-Host ""
    Write-Host "Close PC Maintenance and open Run-PC-Maintenance.bat again."
    Write-Host ""

    Remove-Item -LiteralPath $TempRoot -Recurse -Force -ErrorAction SilentlyContinue
    Read-Host "Press Enter to close"
}
catch {
    Write-Host ""
    Write-Host "============================================================"
    Write-Host "UPDATE FAILED"
    Write-Host "============================================================"
    Write-Host ""
    Write-Host $_.Exception.Message
    Write-Host ""
    Write-Host "Your existing PC Maintenance files were left in place or restored."
    Write-Host ""
    Read-Host "Press Enter to close"
    exit 1
}
