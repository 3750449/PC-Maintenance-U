@echo off
setlocal
set "APPDIR=%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%APPDIR%PC-Maintenance.ps1"
endlocal
