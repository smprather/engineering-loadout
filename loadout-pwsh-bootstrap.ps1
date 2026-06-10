#Requires -Version 5.1
<#
.SYNOPSIS
    Bootstraps the latest PowerShell on Windows using winget.
.DESCRIPTION
    Intended for users starting from Windows PowerShell 5.1. Installs or updates
    Microsoft PowerShell via winget, then tells the user how to rerun the main
    loadout installer from PowerShell 7+.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$winget = Get-Command 'winget.exe' -ErrorAction SilentlyContinue
if (-not $winget) {
    Write-Error "winget.exe was not found. Install App Installer / winget first, then rerun this script."
}

$installScript = Join-Path $PSScriptRoot 'loadout.ps1'
$packageId = 'Microsoft.PowerShell'

Write-Host "Installing latest PowerShell via winget..."
& $winget.Source install --id $packageId --exact --source winget --accept-package-agreements --accept-source-agreements
if ($LASTEXITCODE -ne 0) {
    throw "winget failed to install $packageId (exit code: $LASTEXITCODE)."
}

$pwshCandidates = @()

$programFilesPwshRoot = Join-Path $env:ProgramFiles 'PowerShell'
if (Test-Path $programFilesPwshRoot -PathType Container) {
    $pwshCandidates += Get-ChildItem -Path $programFilesPwshRoot -Filter 'pwsh.exe' -Recurse -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending |
        Select-Object -ExpandProperty FullName
}

$pwshCandidates += Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\pwsh.exe'
$pwshCandidates = @($pwshCandidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique)

$pwshPath = $null
if ($pwshCandidates.Count -gt 0) {
    $pwshPath = $pwshCandidates[0]
}

Write-Host ''
Write-Host 'PowerShell install complete.'
if ($pwshPath) {
    Write-Host "Launch PowerShell 7 with: $pwshPath"
}
Write-Host 'Then rerun the loadout installer from PowerShell 7+:'
Write-Host "  pwsh -NoProfile -ExecutionPolicy Bypass -File `"$installScript`""
