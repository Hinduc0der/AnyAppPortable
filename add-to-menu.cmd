@echo off
chcp 65001 >nul
setlocal
set "PS=powershell.exe"
where pwsh.exe >nul 2>&1 && set "PS=pwsh.exe"
"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0New-PortableApp.ps1" %*
echo.
pause