#requires -Version 5.1

param(
    [Parameter(Mandatory = $false)]
    [string]$AppDirectory = $PSScriptRoot,

    [Parameter(Mandatory = $false)]
    [switch]$Auto
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
        $Value = (Get-Content -LiteralPath $Path -Raw -ErrorAction Stop).Trim()
        return [version]$Value
    }
    catch {
        return [version]"0.0.0"
    }
}

function Test-PowerShellFile {
    param([string]$Path)

    $Tokens = $null
    $Errors = $null

    [System.Management.Automation.Language.Parser]::ParseFile(
        $Path,
        [ref]$Tokens,
        [ref]$Errors
    ) | Out-Null

    if ($Errors.Count -gt 0) {
        if (-not $Auto) {
            Write-Host ""
            Write-Host "PowerShell syntax validation failed for:"
            Write-Host $Path
            Write-Host ""
            $Errors | ForEach-Object { Write-Host $_.Message }
        }
        return $false
    }

    return $true
}

function Finish-Interactive {
    param([string]$Message)

    if (-not $Auto) {
        Write-Host ""
        if ($Message) { Write-Host $Message }
        Write-Host ""
        Read-Host "Press Enter to close"
    }
}

$TempRoot = $null

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    if (-not $Auto) {
        Clear-Host
        Write-Host "============================================================"
        Write-Host "             PC MAINTENANCE UPDATE CHECK"
        Write-Host "============================================================"
        Write-Host ""
        Write-Host "Repository: https://github.com/$RepoOwner/$RepoName"
        Write-Host ""
    }

    $LocalVersionPath = Join-Path $AppDirectory "version.txt"
    $LocalVersion = Read-VersionFile $LocalVersionPath

    if (-not $Auto) {
        Write-Host "Installed version: $LocalVersion"
        Write-Host "Checking GitHub..."
        Write-Host ""
    }

    try {
        $RemoteText = Invoke-WebRequest `
            -Uri "$RawBase/version.txt" `
            -UseBasicParsing `
            -Headers @{ "Cache-Control" = "no-cache" } `
            -TimeoutSec 10 `
            -ErrorAction Stop
    }
    catch {
        if (-not $Auto) {
            Write-Host "Could not check GitHub for updates."
            Write-Host "The current installed version was not changed."
            Finish-Interactive "You can continue using PC Maintenance normally."
        }
        exit 0
    }

    $RemoteVersion = [version]$RemoteText.Content.Trim()

    if ($RemoteVersion -le $LocalVersion) {
        if (-not $Auto) {
            Write-Host "GitHub version:    $RemoteVersion"
            Write-Host ""
            Finish-Interactive "PC Maintenance is already up to date."
        }
        exit 0
    }

    if (-not $Auto) {
        Write-Host "GitHub version:    $RemoteVersion"
        Write-Host ""
        Write-Host "A newer version is available: $RemoteVersion"
        Write-Host ""
        $Answer = Read-Host "Download and install this update? [Y/n]"

        if ($Answer -match '^[Nn]$') {
            Finish-Interactive "Update cancelled."
            exit 0
        }
    }
    else {
        Write-Host "PC Maintenance update found: $LocalVersion -> $RemoteVersion"
        Write-Host "Installing update..."
    }

    $TempRoot = Join-Path $env:TEMP ("PC-Maintenance-Update-" + [guid]::NewGuid().ToString())
    $ZipPath = Join-Path $TempRoot "update.zip"
    $ExtractPath = Join-Path $TempRoot "extracted"

    New-Item -ItemType Directory -Path $TempRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $ExtractPath -Force | Out-Null

    Invoke-WebRequest `
        -Uri $ArchiveUrl `
        -OutFile $ZipPath `
        -UseBasicParsing `
        -TimeoutSec 60 `
        -ErrorAction Stop

    Expand-Archive -LiteralPath $ZipPath -DestinationPath $ExtractPath -Force

    $SourceRoot = Get-ChildItem -LiteralPath $ExtractPath -Directory -ErrorAction Stop |
        Where-Object {
            Test-Path -LiteralPath (Join-Path $_.FullName "PC-Maintenance.ps1")
        } |
        Select-Object -First 1

    if ($null -eq $SourceRoot) {
        throw "Downloaded repository does not contain PC-Maintenance.ps1 in its root."
    }

    foreach ($File in $RequiredFiles) {
        $Candidate = Join-Path $SourceRoot.FullName $File
        if (-not (Test-Path -LiteralPath $Candidate)) {
            throw "Downloaded update is missing required file: $File"
        }
    }

    $DownloadedVersion = Read-VersionFile (Join-Path $SourceRoot.FullName "version.txt")

    if ($DownloadedVersion -ne $RemoteVersion) {
        throw "Downloaded version.txt does not match the advertised GitHub version."
    }

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

    foreach ($File in $RequiredFiles) {
        $CurrentFile = Join-Path $AppDirectory $File
        if (Test-Path -LiteralPath $CurrentFile) {
            Copy-Item -LiteralPath $CurrentFile -Destination $BackupFolder -Force
        }
    }

    try {
        foreach ($File in $RequiredFiles) {
            $SourceFile = Join-Path $SourceRoot.FullName $File
            Copy-Item -LiteralPath $SourceFile -Destination $AppDirectory -Force
        }

        foreach ($OptionalFile in @("README.md", "START-HERE.txt")) {
            $SourceFile = Join-Path $SourceRoot.FullName $OptionalFile
            if (Test-Path -LiteralPath $SourceFile) {
                Copy-Item -LiteralPath $SourceFile -Destination $AppDirectory -Force
            }
        }
    }
    catch {
        foreach ($BackupFile in Get-ChildItem -LiteralPath $BackupFolder -File -ErrorAction SilentlyContinue) {
            Copy-Item -LiteralPath $BackupFile.FullName -Destination $AppDirectory -Force
        }
        throw
    }

    $InstalledVersion = Read-VersionFile (Join-Path $AppDirectory "version.txt")
    if ($InstalledVersion -ne $RemoteVersion) {
        throw "Post-install version verification failed."
    }

    if ($Auto) {
        Write-Host "Updated successfully to version $RemoteVersion."
    }
    else {
        Write-Host ""
        Write-Host "============================================================"
        Write-Host "UPDATE COMPLETE"
        Write-Host "============================================================"
        Write-Host ""
        Write-Host "Installed version: $RemoteVersion"
        Write-Host "Backup: $BackupFolder"
        Finish-Interactive "The new version will be used the next time PC Maintenance starts."
    }

    if ($TempRoot -and (Test-Path -LiteralPath $TempRoot)) {
        Remove-Item -LiteralPath $TempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    exit 0
}
catch {
    if ($TempRoot -and (Test-Path -LiteralPath $TempRoot)) {
        Remove-Item -LiteralPath $TempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    if ($Auto) {
        Write-Warning "Automatic update skipped: $($_.Exception.Message)"
        Write-Host "Starting the currently installed version instead."
        exit 1
    }

    Write-Host ""
    Write-Host "============================================================"
    Write-Host "UPDATE FAILED"
    Write-Host "============================================================"
    Write-Host ""
    Write-Host $_.Exception.Message
    Write-Host ""
    Write-Host "The existing PC Maintenance installation was left in place or restored."
    Finish-Interactive "You can continue using the current version."
    exit 1
}
