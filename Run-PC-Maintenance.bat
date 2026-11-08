@echo off
setlocal
cd /d "%~dp0"

REM Check GitHub for a newer validated version before every launch.
REM If the computer is offline or the update fails, continue with the current version.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Update-PC-Maintenance.ps1" -AppDirectory "%~dp0" -Auto

REM Start the installed/current maintenance program.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0PC-Maintenance.ps1"
pause
