#requires -Version 5.1

$ErrorActionPreference = "Continue"
$AppVersion = [version]"2.2.0"
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

Clear-Host
Write-Host "============================================================"
Write-Host "          DESMOND PC MAINTENANCE $AppVersion"
Write-Host "============================================================"
Write-Host ""
Write-Host "1 - Scan Only"
Write-Host "2 - Standard Maintenance"
Write-Host "3 - Full Maintenance"
Write-Host "4 - Check for Program Updates"
Write-Host "5 - Exit"
Write-Host ""

do {
    $Choice = Read-Host "Choose 1, 2, 3, 4, or 5"
} until ($Choice -in @("1","2","3","4","5"))

if ($Choice -eq "5") {
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
