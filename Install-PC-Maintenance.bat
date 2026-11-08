@echo off
setlocal
set "APPDIR=%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%APPDIR%Install-PC-Maintenance.ps1"
endlocal
