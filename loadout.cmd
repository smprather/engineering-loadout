@echo off
setlocal

set "SCRIPT_DIR=%~dp0"
set "INSTALL_SCRIPT=%SCRIPT_DIR%loadout.ps1"
set "BOOTSTRAP_SCRIPT=%SCRIPT_DIR%loadout-pwsh-bootstrap.ps1"
set "BUNDLED_PWSH=%USERPROFILE%\.local\opt\powershell\7\pwsh.exe"

if exist "%BUNDLED_PWSH%" (
    "%BUNDLED_PWSH%" -NoProfile -ExecutionPolicy Bypass -File "%INSTALL_SCRIPT%" %*
    exit /b %ERRORLEVEL%
)

where pwsh.exe >nul 2>&1
if errorlevel 1 (
    echo PowerShell 7+ ^(pwsh.exe^) was not found.
    echo Bootstrapping bundled PowerShell with Windows PowerShell 5.1...
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%BOOTSTRAP_SCRIPT%" --run-installer %*
    exit /b %ERRORLEVEL%
)

pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "%INSTALL_SCRIPT%" %*
exit /b %ERRORLEVEL%
