@echo off
setlocal

set "SCRIPT_DIR=%~dp0"
set "INSTALL_SCRIPT=%SCRIPT_DIR%loadout.ps1"
set "BOOTSTRAP_SCRIPT=%SCRIPT_DIR%loadout-pwsh-bootstrap.ps1"

where pwsh.exe >nul 2>nul
if errorlevel 1 (
    echo PowerShell 7+ ^(pwsh.exe^) was not found.
    echo Bootstrap it with:
    echo   powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%BOOTSTRAP_SCRIPT%"
    exit /b 1
)

pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "%INSTALL_SCRIPT%" %*
exit /b %ERRORLEVEL%
