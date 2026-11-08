param(
    [Parameter(Mandatory=$false)]
    [string]$AppRoot = $PSScriptRoot
)

$ErrorActionPreference = "Stop"

function Pause-And-Exit {
    param([string]$Message)
    Write-Host ""
    Write-Host $Message
    Write-Host ""
    Read-Host "Press Enter to close"
    exit
}

Clear-Host
Write-Host "============================================================"
Write-Host "             PC MAINTENANCE UPDATER"
Write-Host "============================================================"
Write-Host ""

$ConfigPath = Join-Path $AppRoot "update-config.json"
$LocalVersionPath = Join-Path $AppRoot "version.txt"
$MainScriptPath = Join-Path $AppRoot "PC-Maintenance.ps1"

if (-not (Test-Path -LiteralPath $ConfigPath)) {
    Pause-And-Exit "update-config.json is missing. Reinstall the package."
}

try {
    $Config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
}
catch {
    Pause-And-Exit "The update configuration could not be read: $($_.Exception.Message)"
}

$Owner = [string]$Config.owner
$Repo = [string]$Config.repository
$Branch = [string]$Config.branch

if ([string]::IsNullOrWhiteSpace($Owner) -or [string]::IsNullOrWhiteSpace($Repo) -or [string]::IsNullOrWhiteSpace($Branch)) {
    Pause-And-Exit "The GitHub update configuration is incomplete."
}

$LocalVersion = [version]"0.0.0"
if (Test-Path -LiteralPath $LocalVersionPath) {
    try {
        $LocalVersion = [version]((Get-Content -LiteralPath $LocalVersionPath -Raw).Trim())
    }
    catch {}
}

$RawBase = "https://raw.githubusercontent.com/$Owner/$Repo/$Branch"
$VersionUrl = "$RawBase/version.txt"
$ZipUrl = "https://github.com/$Owner/$Repo/archive/refs/heads/$Branch.zip"

Write-Host "Installed version: $LocalVersion"
Write-Host "Checking GitHub:    https://github.com/$Owner/$Repo"
Write-Host ""

# PowerShell 5.1 on older Windows can otherwise negotiate an older TLS version.
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
}
catch {}

$TempRoot = Join-Path $env:TEMP ("PC-Maintenance-Update-" + [guid]::NewGuid().ToString())
$ZipPath = Join-Path $TempRoot "update.zip"
$ExtractPath = Join-Path $TempRoot "extract"
New-Item -ItemType Directory -Path $TempRoot -Force | Out-Null
New-Item -ItemType Directory -Path $ExtractPath -Force | Out-Null

try {
    $RemoteVersionText = (Invoke-WebRequest -Uri $VersionUrl -UseBasicParsing).Content.Trim()
    $RemoteVersion = [version]$RemoteVersionText
}
catch {
    Remove-Item -LiteralPath $TempRoot -Force -Recurse -ErrorAction SilentlyContinue
    Pause-And-Exit "Could not check for updates. Make sure the PC is online and the GitHub repository exists."
}

Write-Host "Newest version:    $RemoteVersion"
Write-Host ""

if ($RemoteVersion -le $LocalVersion) {
    Remove-Item -LiteralPath $TempRoot -Force -Recurse -ErrorAction SilentlyContinue
    Pause-And-Exit "You already have the newest version."
}

$Answer = Read-Host "Version $RemoteVersion is available. Install it now? [Y/n]"
if ($Answer -match '^[Nn]$') {
    Remove-Item -LiteralPath $TempRoot -Force -Recurse -ErrorAction SilentlyContinue
    Pause-And-Exit "Update cancelled."
}

try {
    Write-Host ""
    Write-Host "Downloading update..."
    Invoke-WebRequest -Uri $ZipUrl -OutFile $ZipPath -UseBasicParsing

    Write-Host "Extracting update..."
    Expand-Archive -LiteralPath $ZipPath -DestinationPath $ExtractPath -Force

    $SourceRoot = Get-ChildItem -LiteralPath $ExtractPath -Directory | Select-Object -First 1
    if ($null -eq $SourceRoot) {
        throw "Downloaded package did not contain a repository folder."
    }

    $RequiredFiles = @(
        "PC-Maintenance.ps1",
        "Update-PC-Maintenance.ps1",
        "Run-PC-Maintenance.bat",
        "Install-PC-Maintenance.ps1",
        "Install-PC-Maintenance.bat",
        "version.txt"
    )

    foreach ($Name in $RequiredFiles) {
        $Candidate = Join-Path $SourceRoot.FullName $Name
        if (-not (Test-Path -LiteralPath $Candidate)) {
            throw "Update package is missing required file: $Name"
        }
    }

    # Syntax-check PowerShell files before replacing anything.
    foreach ($Name in @("PC-Maintenance.ps1", "Update-PC-Maintenance.ps1", "Install-PC-Maintenance.ps1")) {
        $Candidate = Join-Path $SourceRoot.FullName $Name
        $Tokens = $null
        $Errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile(
            $Candidate,
            [ref]$Tokens,
            [ref]$Errors
        ) | Out-Null

        if ($Errors.Count -gt 0) {
            $Messages = ($Errors | ForEach-Object { $_.Message }) -join "; "
            throw "PowerShell syntax validation failed for $Name : $Messages"
        }
    }

    # Make sure this installation folder can actually be updated.
    $WriteTest = Join-Path $AppRoot (".write-test-" + [guid]::NewGuid().ToString())
    Set-Content -LiteralPath $WriteTest -Value "test" -Encoding ASCII
    Remove-Item -LiteralPath $WriteTest -Force

    $Documents = [Environment]::GetFolderPath("MyDocuments")
    $ProgramBackupRoot = Join-Path $Documents "Desmond-PC-Maintenance\ProgramBackups"
    $BackupFolder = Join-Path $ProgramBackupRoot (Get-Date -Format "yyyy-MM-dd_HH-mm-ss")
    New-Item -ItemType Directory -Path $BackupFolder -Force | Out-Null

    foreach ($Name in $RequiredFiles) {
        $Existing = Join-Path $AppRoot $Name
        if (Test-Path -LiteralPath $Existing) {
            Copy-Item -LiteralPath $Existing -Destination (Join-Path $BackupFolder $Name) -Force
        }
    }

    Write-Host "Installing update..."
    foreach ($Name in $RequiredFiles) {
        Copy-Item -LiteralPath (Join-Path $SourceRoot.FullName $Name) -Destination (Join-Path $AppRoot $Name) -Force
    }

    Remove-Item -LiteralPath $TempRoot -Force -Recurse -ErrorAction SilentlyContinue

    Write-Host ""
    Write-Host "Update complete."
    Write-Host "Backup saved to:"
    Write-Host $BackupFolder
    Write-Host ""

    $Restart = Read-Host "Restart PC Maintenance now? [Y/n]"
    if ($Restart -notmatch '^[Nn]$') {
        Start-Process powershell.exe -ArgumentList @(
            "-NoProfile",
            "-ExecutionPolicy", "Bypass",
            "-File", "`"$MainScriptPath`""
        )
    }
}
catch {
    Remove-Item -LiteralPath $TempRoot -Force -Recurse -ErrorAction SilentlyContinue
    Pause-And-Exit "Update failed safely. The current program was left in place when possible. Error: $($_.Exception.Message)"
}
