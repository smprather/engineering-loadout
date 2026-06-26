param(
    [string]$CorpUid = 'dummy.uid',
    [string]$CorpPassword = 'dummy.corp.password',
    [string]$PwManagerPassword = 'dummy.pwmanager.password',
    [string]$ThinLincServer = 'dummy.thinlinc.server',
    [string]$ThinLincUsername = 'dummy.thinlinc.username',
    [string]$ThinLincPassword = 'dummy.thinlinc.password',
    [switch]$ValidateOnly,
    [switch]$KeepOpen
)

$ErrorActionPreference = 'Stop'

$scriptPath = Join-Path $PSScriptRoot 'hotkeys.ahk'
if (-not (Test-Path $scriptPath)) {
    throw "Could not find AutoHotkey script at: $scriptPath"
}

$sandboxRoot = Join-Path $env:TEMP ("loadout-ahk-test-" + [guid]::NewGuid().ToString('N'))

New-Item -ItemType Directory -Path $sandboxRoot -Force | Out-Null

$sandboxScriptPath = Join-Path $sandboxRoot 'hotkeys.ahk'
Copy-Item -Path $scriptPath -Destination $sandboxScriptPath -Force

$sandboxContent = Get-Content -Path $sandboxScriptPath -Raw -ErrorAction Stop
$featureFlags = @(
    'cfg_feature_corp_logins',
    'cfg_feature_mouse_wiggle',
    'cfg_feature_cisco_secure_client_vpn',
    'cfg_feature_password_manager',
    'cfg_feature_tmux_hotkeys',
    'cfg_feature_f1f2f3_as_mouse_buttons',
    'cfg_feature_thinlinc_reconnect'
)

foreach ($flag in $featureFlags) {
    $sandboxContent = [regex]::Replace(
        $sandboxContent,
        '(?m)^' + [regex]::Escape($flag) + '\s*:=\s*(true|false)\s*$',
        $flag + ' := true'
    )
}

Set-Content -Path $sandboxScriptPath -Value $sandboxContent -Encoding UTF8

$scriptPath = $sandboxScriptPath

$ahkInstallDirs = @()
try {
    $ahkInstallDirs = Get-ChildItem -Path $env:USERPROFILE -Directory -Filter 'AutoHotkey_*' -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -ExpandProperty FullName
} catch {
    $ahkInstallDirs = @()
}

$ahkCandidates = @(
    (Get-Command 'AutoHotkey64.exe' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source),
    (Get-Command 'AutoHotkey.exe' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source),
    "$env:USERPROFILE\AutoHotkey_v2\AutoHotkey64.exe",
    "$env:USERPROFILE\AutoHotkey_v2\AutoHotkey.exe"
)

foreach ($dir in $ahkInstallDirs) {
    $ahkCandidates += (Join-Path $dir 'AutoHotkey64.exe')
    $ahkCandidates += (Join-Path $dir 'AutoHotkey.exe')
}

$ahkCandidates = $ahkCandidates |
    Where-Object { $_ -and (Test-Path $_) } |
    Select-Object -Unique

if (-not $ahkCandidates) {
    throw 'AutoHotkey executable not found. Install AutoHotkey v2 or add AutoHotkey64.exe to PATH.'
}

$ahkExe = @($ahkCandidates)[0]

$validateProcess = Start-Process -FilePath $ahkExe -ArgumentList @('/ErrorStdOut', '/Validate', $scriptPath) -NoNewWindow -Wait -PassThru
if ($validateProcess.ExitCode -ne 0) {
    throw "AutoHotkey validation failed for: $scriptPath"
}
Write-Host "Validated AutoHotkey script: $scriptPath"

if ($ValidateOnly) {
    exit 0
}

$testEnv = @{
    CORP_UID = $CorpUid
    CORP_PASSWORD = $CorpPassword
    PWMANAGER_PASSWORD = $PwManagerPassword
    THINLINC_SERVER = $ThinLincServer
    THINLINC_USERNAME = $ThinLincUsername
    THINLINC_PASSWORD = $ThinLincPassword
    AHK_ENABLE_MOUSE_WIGGLE = 'true'
}

foreach ($kv in $testEnv.GetEnumerator()) {
    Set-Item -Path ("Env:" + $kv.Key) -Value $kv.Value
}

Write-Host 'Launching hotkeys.ahk with test environment variables:'
Write-Host "  CORP_UID=$($testEnv.CORP_UID)"
Write-Host "  CORP_PASSWORD=$($testEnv.CORP_PASSWORD)"
Write-Host "  PWMANAGER_PASSWORD=$($testEnv.PWMANAGER_PASSWORD)"
Write-Host "  THINLINC_SERVER=$($testEnv.THINLINC_SERVER)"
Write-Host "  THINLINC_USERNAME=$($testEnv.THINLINC_USERNAME)"
Write-Host "  THINLINC_PASSWORD=$($testEnv.THINLINC_PASSWORD)"
Write-Host "  AHK_ENABLE_MOUSE_WIGGLE=$($testEnv.AHK_ENABLE_MOUSE_WIGGLE)"
Write-Host "  Test sandbox=$sandboxRoot"
Write-Host '  Feature mode=all optional repo features enabled in flat script'

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $ahkExe
$psi.Arguments = '"' + $scriptPath + '"'
$psi.WorkingDirectory = $sandboxRoot
$psi.UseShellExecute = $false

foreach ($kv in $testEnv.GetEnumerator()) {
    $psi.EnvironmentVariables[$kv.Key] = $kv.Value
}

[void][System.Diagnostics.Process]::Start($psi)

if ($KeepOpen) {
    Write-Host ''
    Write-Host 'Press Enter to exit this shell (AHK keeps running in its own process).'
    Read-Host | Out-Null
}
