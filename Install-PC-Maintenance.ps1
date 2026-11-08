$ErrorActionPreference = "Stop"

$Source = $PSScriptRoot
$Destination = Join-Path $env:LOCALAPPDATA "DesmondPCMaintenance"

$Files = @(
    "PC-Maintenance.ps1",
    "Update-PC-Maintenance.ps1",
    "Run-PC-Maintenance.bat",
    "Install-PC-Maintenance.ps1",
    "Install-PC-Maintenance.bat",
    "update-config.json",
    "version.txt"
)

try {
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null

    foreach ($Name in $Files) {
        $From = Join-Path $Source $Name
        if (-not (Test-Path -LiteralPath $From)) {
            throw "Package file is missing: $Name"
        }
        Copy-Item -LiteralPath $From -Destination (Join-Path $Destination $Name) -Force
    }

    $Desktop = [Environment]::GetFolderPath("Desktop")
    $ShortcutPath = Join-Path $Desktop "PC Maintenance.lnk"
    $Shell = New-Object -ComObject WScript.Shell
    $Shortcut = $Shell.CreateShortcut($ShortcutPath)
    $Shortcut.TargetPath = Join-Path $Destination "Run-PC-Maintenance.bat"
    $Shortcut.WorkingDirectory = $Destination
    $Shortcut.Description = "Desmond PC Maintenance"
    $Shortcut.IconLocation = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe,0"
    $Shortcut.Save()

    Write-Host ""
    Write-Host "PC Maintenance installed successfully."
    Write-Host "Installed to: $Destination"
    Write-Host "Desktop shortcut: PC Maintenance"
    Write-Host ""
    $Run = Read-Host "Run PC Maintenance now? [Y/n]"
    if ($Run -notmatch '^[Nn]$') {
        Start-Process (Join-Path $Destination "Run-PC-Maintenance.bat")
    }
}
catch {
    Write-Host ""
    Write-Host "Installation failed: $($_.Exception.Message)"
    Write-Host ""
}

Read-Host "Press Enter to close"
