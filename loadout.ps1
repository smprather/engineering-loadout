#Requires -Version 5.1
<#
.SYNOPSIS
    Installs loadout on Windows by copying files into their expected locations.
.DESCRIPTION
    Copies WezTerm, Starship, Neovim, PowerShell profile, AutoHotKey, and
    EditorConfig configs. To update after repo changes, re-run this script.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Show-LoadoutWindowsHelp {
    Write-Host @'
loadout.ps1 - Windows loadout installer

Usage:
  .\loadout.cmd [--help]
  pwsh -NoProfile -ExecutionPolicy Bypass -File .\loadout.ps1
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\loadout-pwsh-bootstrap.ps1

Options:
  -h, --help, -?, /?    Show this help and exit.

Notes:
  - .\loadout.cmd uses bundled user-local PowerShell when present.
  - If pwsh.exe is missing, .\loadout.cmd bootstraps the bundled PowerShell
    archive with Windows PowerShell 5.1, then runs this installer under it.
  - No elevation required.
  - Copies Windows configs and installs/starts the user-local AutoHotkey script.
  - When running from a WSL UNC path, prefer loadout.cmd or the explicit pwsh
    command above. Direct .ps1 execution can be blocked by execution policy
    before this script starts.

Installed destinations:
  %USERPROFILE%\.local\opt\powershell\7\
      Bundled PowerShell extracted from:
      pre_built\windows.x86_64\powershell\PowerShell-*-win-x64.zip[.part-NNN]

  %LOCALAPPDATA%\Microsoft\Windows Terminal\Fragments\engineering-loadout\powershell.json
      Windows Terminal profile for bundled PowerShell.

  %LOCALAPPDATA%\nvim\
      Neovim config copied from envs\nvim\.

  %USERPROFILE%\.config\wezterm\wezterm.lua
      WezTerm config copied from envs\wezterm\wezterm.lua.

  %USERPROFILE%\.config\starship\starship.toml
      Starship config copied from envs\starship\starship.windows.toml.

  PowerShell profile locations
      envs\powershell\Microsoft.PowerShell_profile.ps1 is copied to the current
      $PROFILE plus existing WindowsPowerShell and PowerShell profile dirs under
      Documents.

  %USERPROFILE%\.editorconfig
      EditorConfig copied from envs\editorconfig\editorconfig.

  %USERPROFILE%\autohotkey\hotkeys.ahk
      AutoHotkey v2 script copied from envs\autohotkey\hotkeys.ahk. The script reads
      its feature selections from %USERPROFILE%\loadout_keys.toml at startup.

  Startup\hotkeys.lnk
      Startup shortcut pointing AutoHotkey64.exe at the installed hotkeys.ahk.

Configuration file:
  %USERPROFILE%\loadout_keys.toml

  Created on first run if missing. Existing files are preserved. hotkeys.ahk
  reads this file at startup to decide which features are active; the installer
  no longer patches booleans into the script, so editing loadout_keys.toml and
  reloading AutoHotkey (Ctrl+Alt+R) is enough to apply changes.
  Legacy [autohotkey.plugins] enabled arrays are still accepted.

Example loadout_keys.toml:
  version = 1

  [autohotkey]
  enabled = true

  [autohotkey.features]
  enabled = [
    "corp-logins",
    "cisco-secure-client-vpn",
    "password-manager",
    "thinlinc-reconnect",
  ]

  [autohotkey.features.cisco-secure-client-vpn]
  skip_wifi_ssids = [
    "Home WiFi",
    "Phone Hotspot",
  ]

AutoHotkey global setting:
  [autohotkey]
  enabled = true | false
      false keeps the script installed but makes all optional features resolve
      as off when hotkeys.ahk starts.

  executable = "C:\path\to\AutoHotkey64.exe"
      Optional. Use this exact executable instead of discovering AutoHotkey_* in
      %USERPROFILE%. Environment variables (e.g. %USERPROFILE%) are expanded.
      Useful when AHK has been renamed (e.g. corp infosec policy).

AutoHotkey feature IDs:
  corp-logins
      Ctrl+Alt+I types CORP_PASSWORD then Tab.
      Ctrl+Alt+O types CORP_UID, Tab, CORP_PASSWORD, Enter.
      Ctrl+Alt+P types CORP_PASSWORD then Enter.

  mouse-wiggle
      Nudges the mouse after extended physical idle time. Runtime kill switch:
      set AHK_ENABLE_MOUSE_WIGGLE=false before launching AutoHotkey.

  cisco-secure-client-vpn
      Cisco Secure Client automation. Requires CORP_UID and CORP_PASSWORD.
      Skips while the workstation is locked, while AHK is idle-suspended, and
      while connected to any SSID listed in skip_wifi_ssids.

  password-manager
      Ctrl+Alt+B types PWMANAGER_PASSWORD then Enter.

  tmux-hotkeys
      RAlt/RWin send Ctrl+\ z for tmux zoom toggle.
      Ctrl+; sends tmux last-pane toggle.

  f1f2f3-as-mouse-buttons
      In mspaint.exe, etxc.exe, and wezterm-gui.exe:
      F1 holds left mouse, F2 holds right mouse, F3 double-left-clicks then
      right-clicks.

  thinlinc-reconnect
      Auto-dismisses ThinLinc connection errors, relaunches after error
      dismissals, and auto-fills THINLINC_SERVER / THINLINC_USERNAME /
      THINLINC_PASSWORD when the main client window is present.

AutoHotkey always-available hotkeys:
  Ctrl+Alt+R    Reload hotkeys.ahk.
  Ctrl+Alt+A    Suspend/resume hotkeys and pause/resume VPN auto-login.

Feature-specific diagnostic hotkeys:
  Ctrl+Alt+V    Toggle Cisco VPN auto-login when cisco-secure-client-vpn is on.
  Ctrl+Alt+T    Show ThinLinc reconnect diagnostics when thinlinc-reconnect is on.

Environment variables used by AutoHotkey:
  CORP_UID
  CORP_PASSWORD
  PWMANAGER_PASSWORD
  AHK_ENABLE_MOUSE_WIGGLE=false
  LOADOUT_KEYS_TOML
  THINLINC_SERVER
  THINLINC_USERNAME
  THINLINC_PASSWORD

PowerShell runtime bundle:
  The bundled PowerShell ZIP is optional for source-tree development but should
  be present in release archives. If absent, loadout.ps1 warns and skips
  installing the user-local runtime. loadout.cmd still uses system pwsh.exe
  when available.
'@
}

foreach ($arg in $args) {
    if ($arg -in @('--help', '-h', '-?', '/?')) {
        Show-LoadoutWindowsHelp
        exit 0
    }
}

if ($args.Count -gt 0) {
    Write-Error "Unknown argument(s): $($args -join ' '). Use --help for usage."
}

if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Warning "This installer requires PowerShell 7+."
    Write-Warning "Run .\loadout.cmd to bootstrap the bundled user-local PowerShell, or run powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\loadout-pwsh-bootstrap.ps1."
    exit 1
}

function Copy-Config {
    param(
        [string]$Source,
        [string]$Dest
    )

    if (-not (Test-Path $Source)) {
        Write-Warning "  Skipping '$Dest' -- source not found: $Source"
        return
    }

    $parentDir = Split-Path $Dest -Parent
    if ($parentDir -and -not (Test-Path $parentDir)) {
        New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
    }

    if (Test-Path $Source -PathType Container) {
        robocopy $Source $Dest /E /NFL /NDL /NJH /NJS | Out-Null
        if ($LASTEXITCODE -ge 8) {
            Write-Warning "  robocopy reported errors copying '$Source' (exit code: $LASTEXITCODE)"
            return
        }
    } else {
        Copy-Item -Path $Source -Destination $Dest -Force
    }
    Write-Host "  Copied: $Source -> $Dest"
}

function Get-AhkFeatureDefinitions {
    return @(
        [PSCustomObject]@{ Id = 'corp-logins'; FlagName = 'cfg_feature_corp_logins'; LegacyIds = @('10-corp-logins'); Description = 'corp credential entry hotkeys' },
        [PSCustomObject]@{ Id = 'mouse-wiggle'; FlagName = 'cfg_feature_mouse_wiggle'; LegacyIds = @('20-mouse-wiggle'); Description = 'idle mouse nudge' },
        [PSCustomObject]@{ Id = 'cisco-secure-client-vpn'; FlagName = 'cfg_feature_cisco_secure_client_vpn'; LegacyIds = @('30-cisco-secure-client-vpn'); Description = 'Cisco Secure Client VPN automation' },
        [PSCustomObject]@{ Id = 'password-manager'; FlagName = 'cfg_feature_password_manager'; LegacyIds = @('40-password-manager'); Description = 'Ctrl+Alt+B password helper' },
        [PSCustomObject]@{ Id = 'tmux-hotkeys'; FlagName = 'cfg_feature_tmux_hotkeys'; LegacyIds = @('50-tmux-hotkeys'); Description = 'tmux helper hotkeys' },
        [PSCustomObject]@{ Id = 'f1f2f3-as-mouse-buttons'; FlagName = 'cfg_feature_f1f2f3_as_mouse_buttons'; LegacyIds = @('60-f1f2f3-as-mouse-bottons', 'f1f2f3_as_mouse_bottons'); Description = 'F1/F2/F3 mouse remaps' },
        [PSCustomObject]@{ Id = 'thinlinc-reconnect'; FlagName = 'cfg_feature_thinlinc_reconnect'; LegacyIds = @(); Description = 'ThinLinc client auto-reconnect and auto-connect' }
    )
}

function New-LoadoutKeysConfig {
    param(
        [string]$ConfigPath,
        [object[]]$FeatureDefinitions
    )

    $lines = @(
        'version = 1',
        '',
        '# This file is user-local and not shared from the repo.',
        '# hotkeys.ahk reads this file at startup; reload AutoHotkey after edits.',
        '# Legacy [autohotkey.plugins] entries are still accepted for existing installs.',
        '',
        '[autohotkey]',
        'enabled = true',
        '',
        '# Override the AutoHotkey executable. If unset, loadout discovers',
        '# AutoHotkey64.exe (or similar) inside %USERPROFILE%\AutoHotkey_*.',
        '# Useful when AHK has been renamed (e.g. corp infosec policy).',
        '# executable = "%USERPROFILE%\AutoHotkey_2.1-alpha.22\foo.exe"',
        '',
        '[autohotkey.features]',
        'enabled = ['
    )

    foreach ($feature in $FeatureDefinitions) {
        $lines += "  # `"$($feature.Id)`",  # $($feature.Description)"
    }

    $lines += @(
        ']',
        '',
        '[autohotkey.features.cisco-secure-client-vpn]',
        '# Cisco VPN automation is skipped while connected to one of these Wi-Fi SSIDs.',
        '# skip_wifi_ssids = [',
        '#   "Home WiFi",',
        '#   "Phone Hotspot",',
        '# ]'
    )

    $parent = Split-Path $ConfigPath -Parent
    if ($parent -and -not (Test-Path $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    Set-Content -Path $ConfigPath -Value $lines -Encoding UTF8
    Write-Host "  Created default loadout-keys config: $ConfigPath"
}

function Get-LoadoutAhkConfig {
    param(
        [string]$ConfigPath,
        [object[]]$FeatureDefinitions
    )

    $result = [PSCustomObject]@{
        AutoHotkeyEnabled = $true
        EnabledFeatureIds = @()
        ExecutablePath    = ''
    }

    if (-not (Test-Path $ConfigPath -PathType Leaf)) {
        return $result
    }

    $featureMap = @{}
    foreach ($feature in $FeatureDefinitions) {
        $featureMap[$feature.Id] = $feature.Id
        foreach ($legacyId in $feature.LegacyIds) {
            $featureMap[$legacyId] = $feature.Id
        }
    }

    $currentSection = ''
    $inEnabledArray = $false
    $enabledFeatureIds = @()
    $unknownEntries = @()

    Get-Content -Path $ConfigPath -ErrorAction Stop | ForEach-Object {
        $line = $_
        $trimmed = $line.Trim()

        if (-not $inEnabledArray -and $trimmed -match '^\[(?<section>[^\]]+)\]$') {
            $currentSection = $Matches.section
            return
        }

        if ($trimmed -eq '' -or $trimmed.StartsWith('#')) {
            return
        }

        if ($inEnabledArray) {
            $quoted = [regex]::Matches($line, '"([^"]+)"')
            foreach ($q in $quoted) {
                $token = $q.Groups[1].Value
                if ($featureMap.ContainsKey($token)) {
                    $featureId = $featureMap[$token]
                    if ($enabledFeatureIds -notcontains $featureId) {
                        $enabledFeatureIds += $featureId
                    }
                } elseif ($unknownEntries -notcontains $token) {
                    $unknownEntries += $token
                }
            }

            if ($line -match '\]') {
                $inEnabledArray = $false
            }
            return
        }

        if ($currentSection -ceq 'autohotkey' -and $trimmed -match '^enabled\s*=\s*(?<value>true|false)\b') {
            $result.AutoHotkeyEnabled = ($Matches.value -ceq 'true')
            return
        }

        if ($currentSection -ceq 'autohotkey' -and $trimmed -match '^executable\s*=\s*"(?<value>[^"]*)"\s*$') {
            $result.ExecutablePath = [Environment]::ExpandEnvironmentVariables($Matches.value)
            return
        }

        if ((@('autohotkey.features', 'autohotkey.plugins') -contains $currentSection) -and $trimmed -match '^enabled\s*=\s*\[(?<rest>.*)$') {
            $rest = $Matches.rest
            $quoted = [regex]::Matches($rest, '"([^"]+)"')
            foreach ($q in $quoted) {
                $token = $q.Groups[1].Value
                if ($featureMap.ContainsKey($token)) {
                    $featureId = $featureMap[$token]
                    if ($enabledFeatureIds -notcontains $featureId) {
                        $enabledFeatureIds += $featureId
                    }
                } elseif ($unknownEntries -notcontains $token) {
                    $unknownEntries += $token
                }
            }

            if ($rest -notmatch '\]') {
                $inEnabledArray = $true
            }
            return
        }
    }

    foreach ($entry in $unknownEntries) {
        Write-Warning "  loadout_keys.toml enables unknown AHK feature '$entry'; ignoring."
    }

    $result.EnabledFeatureIds = $enabledFeatureIds
    return $result
}

function Get-LoadoutBundledPowerShellArchive {
    param([string]$RepoDir)

    $roots = @(
        (Join-Path $RepoDir 'pre_built\windows.x86_64\powershell'),
        (Join-Path $RepoDir 'pre_built\windows\powershell')
    )

    $candidates = @()
    foreach ($root in $roots) {
        if (-not (Test-Path $root -PathType Container)) {
            continue
        }
        $candidates += Get-ChildItem -Path $root -File -Filter 'PowerShell-*-win-x64.zip' -ErrorAction SilentlyContinue
        $candidates += Get-ChildItem -Path $root -File -Filter 'PowerShell-*-win-x64.zip.part-000' -ErrorAction SilentlyContinue
    }

    return @($candidates | Sort-Object Name -Descending | Select-Object -First 1)[0]
}

function Get-LoadoutPowerShellArchiveVersion {
    param([string]$ArchiveName)

    if ($ArchiveName -match '^PowerShell-(?<version>.+)-win-x64\.zip(?:\.part-000)?$') {
        return $Matches.version
    }
    return ''
}

function Join-LoadoutSplitArchive {
    param(
        [string]$PartZeroPath,
        [string]$TempDir
    )

    $basePath = $PartZeroPath.Substring(0, $PartZeroPath.Length - '.part-000'.Length)
    $partPattern = [System.IO.Path]::GetFileName($basePath) + '.part-*'
    $parts = @(Get-ChildItem -Path (Split-Path $PartZeroPath -Parent) -File -Filter $partPattern | Sort-Object Name)
    if ($parts.Count -eq 0) {
        throw "No split archive parts found for $basePath"
    }

    $joinedPath = Join-Path $TempDir ([System.IO.Path]::GetFileName($basePath))
    $outStream = [System.IO.File]::Open($joinedPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write)
    try {
        foreach ($part in $parts) {
            $inStream = [System.IO.File]::OpenRead($part.FullName)
            try {
                $inStream.CopyTo($outStream)
            } finally {
                $inStream.Dispose()
            }
        }
    } finally {
        $outStream.Dispose()
    }

    return $joinedPath
}

function Install-LoadoutBundledPowerShell {
    param([string]$RepoDir)

    $archive = Get-LoadoutBundledPowerShellArchive -RepoDir $RepoDir
    if (-not $archive) {
        Write-Warning "  Bundled PowerShell archive not found under pre_built\windows.x86_64\powershell; skipping runtime install."
        return $null
    }

    $version = Get-LoadoutPowerShellArchiveVersion -ArchiveName $archive.Name
    $installDir = Join-Path $env:USERPROFILE '.local\opt\powershell\7'
    $pwshExe = Join-Path $installDir 'pwsh.exe'
    $versionFile = Join-Path $installDir '.loadout-version'

    if ((Test-Path $pwshExe -PathType Leaf) -and (Test-Path $versionFile -PathType Leaf)) {
        $installedVersion = (Get-Content -Path $versionFile -ErrorAction SilentlyContinue | Select-Object -First 1)
        if ($installedVersion -eq $version) {
            Write-Host "  Already installed: $pwshExe"
            return $pwshExe
        }
    }

    $tempRoot = Join-Path $env:TEMP ("loadout-pwsh-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    try {
        $zipPath = $archive.FullName
        if ($archive.Name.EndsWith('.part-000')) {
            Write-Host "  Rejoining split PowerShell archive..."
            $zipPath = Join-LoadoutSplitArchive -PartZeroPath $archive.FullName -TempDir $tempRoot
        }

        $extractDir = Join-Path $tempRoot 'extract'
        New-Item -ItemType Directory -Path $extractDir -Force | Out-Null
        Write-Host "  Extracting bundled PowerShell $version..."
        Expand-Archive -Path $zipPath -DestinationPath $extractDir -Force

        if (-not (Test-Path (Join-Path $extractDir 'pwsh.exe') -PathType Leaf)) {
            throw "PowerShell archive did not contain pwsh.exe at the archive root."
        }

        $parent = Split-Path $installDir -Parent
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
        if (Test-Path $installDir) {
            Remove-Item -Path $installDir -Recurse -Force
        }
        Move-Item -Path $extractDir -Destination $installDir -Force
        Set-Content -Path $versionFile -Value $version -Encoding UTF8
    } finally {
        Remove-Item -Path $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    Write-Host "  Installed: $pwshExe"
    return $pwshExe
}

function Install-LoadoutWindowsTerminalProfile {
    param([string]$PwshPath)

    if (-not $PwshPath -or -not $env:LOCALAPPDATA) {
        return
    }

    $fragmentDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\Fragments\engineering-loadout'
    $fragmentPath = Join-Path $fragmentDir 'powershell.json'
    New-Item -ItemType Directory -Path $fragmentDir -Force | Out-Null

    $fragment = [ordered]@{
        profiles = @(
            [ordered]@{
                guid = '{1a53bafe-4b0f-5d49-9f9d-8afbcac8fb25}'
                name = 'Loadout PowerShell'
                commandline = ('"{0}" -NoLogo' -f $PwshPath)
                startingDirectory = '%USERPROFILE%'
            }
        )
    }

    $fragment | ConvertTo-Json -Depth 5 | Set-Content -Path $fragmentPath -Encoding UTF8
    Write-Host "  Windows Terminal profile: $fragmentPath"
}

$repoDir = $PSScriptRoot
Write-Host "Loadout repo: $repoDir"
Write-Host ""

Write-Host "PowerShell runtime..."
$bundledPwsh = Install-LoadoutBundledPowerShell -RepoDir $repoDir
if ($bundledPwsh) {
    Install-LoadoutWindowsTerminalProfile -PwshPath $bundledPwsh
}

Write-Host "Neovim..."
Copy-Config "$repoDir\envs\nvim" "$env:LOCALAPPDATA\nvim"

Write-Host "WezTerm..."
Copy-Config "$repoDir\envs\wezterm\wezterm.lua" "$env:USERPROFILE\.config\wezterm\wezterm.lua"

Write-Host "Starship..."
Copy-Config "$repoDir\envs\starship\starship.windows.toml" "$env:USERPROFILE\.config\starship\starship.toml"

Write-Host "PowerShell profile..."
$psProfileSource = "$repoDir\envs\powershell\Microsoft.PowerShell_profile.ps1"
$docRoots = @(
    [Environment]::GetFolderPath('MyDocuments'),
    "$HOME\Documents"
) | Sort-Object -Unique

$psProfileCandidates = @($PROFILE)
foreach ($root in $docRoots) {
    $psProfileCandidates += "$root\WindowsPowerShell\Microsoft.PowerShell_profile.ps1"
    $psProfileCandidates += "$root\PowerShell\Microsoft.PowerShell_profile.ps1"
}

$psProfileCandidates | Sort-Object -Unique | ForEach-Object {
    $profileDir = Split-Path $_ -Parent
    if ($_ -eq $PROFILE -or (Test-Path $profileDir)) {
        Copy-Config $psProfileSource $_
    }
}

Write-Host "EditorConfig..."
Copy-Config "$repoDir\envs\editorconfig\editorconfig" "$env:USERPROFILE\.editorconfig"

Write-Host "AutoHotKey..."
$startupDir  = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
$ahkHomeDir  = "$HOME\autohotkey"
$ahkScript   = "$ahkHomeDir\hotkeys.ahk"
$loadoutKeysConfigPath = Join-Path $HOME 'loadout_keys.toml'
$ahkFeatureDefinitions = Get-AhkFeatureDefinitions

if (-not (Test-Path $loadoutKeysConfigPath -PathType Leaf)) {
    New-LoadoutKeysConfig -ConfigPath $loadoutKeysConfigPath -FeatureDefinitions $ahkFeatureDefinitions
}

$loadoutAhkConfig = Get-LoadoutAhkConfig -ConfigPath $loadoutKeysConfigPath -FeatureDefinitions $ahkFeatureDefinitions
Write-Host "  Using config: $loadoutKeysConfigPath"

Copy-Config "$repoDir\envs\autohotkey\hotkeys.ahk" $ahkScript

if ($loadoutAhkConfig.AutoHotkeyEnabled) {
    if ($loadoutAhkConfig.EnabledFeatureIds.Count -gt 0) {
        Write-Host "  AHK features enabled in loadout_keys.toml: $($loadoutAhkConfig.EnabledFeatureIds -join ', ')"
    } else {
        Write-Host "  AHK features enabled in loadout_keys.toml: (none)"
    }
} else {
    Write-Host "  AutoHotKey is globally disabled in loadout_keys.toml; all optional AHK features are off."
}
Write-Host "  hotkeys.ahk reads loadout_keys.toml at startup; edit it and reload AutoHotkey (Ctrl+Alt+R) to apply changes."

$legacyGeneratedFile = Join-Path $ahkHomeDir '_autoload_plugins.generated.ahk'
if (Test-Path $legacyGeneratedFile -PathType Leaf) {
    Remove-Item -Path $legacyGeneratedFile -Force
    Write-Host "  Removed legacy generated plugin include file: $legacyGeneratedFile"
}

$ahkExe = $null

if ($loadoutAhkConfig.ExecutablePath) {
    if (Test-Path $loadoutAhkConfig.ExecutablePath -PathType Leaf) {
        $ahkExe = (Resolve-Path $loadoutAhkConfig.ExecutablePath).Path
        Write-Host "  Using configured AutoHotkey executable: $ahkExe"
    } else {
        Write-Warning "  loadout_keys.toml executable '$($loadoutAhkConfig.ExecutablePath)' not found -- falling back to discovery."
    }
}

if (-not $ahkExe) {
    $ahkDirs = @(Get-ChildItem -Path $HOME -Filter "AutoHotkey_*" -Directory -ErrorAction SilentlyContinue)
    $ahkDir  = $null

    if ($ahkDirs.Count -gt 1) {
        Write-Warning "  Multiple AutoHotkey directories found in $HOME."
        Write-Warning "  Remove all but one and re-run to set up AutoHotKey."
    } elseif ($ahkDirs.Count -eq 1) {
        $ahkDir = $ahkDirs[0].FullName
        Write-Host "  Found existing AutoHotkey: $ahkDir"
    } else {
        Write-Host "  No AutoHotkey found -- downloading latest stable release..."
        try {
            $release  = Invoke-RestMethod "https://api.github.com/repos/AutoHotkey/AutoHotkey/releases/latest" -UseBasicParsing
            $zipAsset = $release.assets | Where-Object { $_.name -like "AutoHotkey_*.zip" } | Select-Object -First 1
            if (-not $zipAsset) { throw "No zip asset found in latest release." }

            $zipName = $zipAsset.name
            $dirName = [System.IO.Path]::GetFileNameWithoutExtension($zipName)
            $zipPath = Join-Path $HOME $zipName
            $ahkDir  = Join-Path $HOME $dirName

            Write-Host "  Downloading $zipName..."
            Invoke-WebRequest -Uri $zipAsset.browser_download_url -OutFile $zipPath -UseBasicParsing
            New-Item -ItemType Directory -Path $ahkDir -Force | Out-Null
            Expand-Archive -Path $zipPath -DestinationPath $ahkDir -Force
            Remove-Item $zipPath
            Remove-Item (Join-Path $ahkDir "AutoHotkey32.exe") -Force -ErrorAction SilentlyContinue
            Write-Host "  Extracted to $ahkDir"
        } catch {
            Write-Warning "  Failed to download AutoHotkey: $_"
        }
    }

    if ($ahkDir) {
        $ahkExeCandidates = @('AutoHotkey64.exe', 'AutoHotkey.exe', 'AutoHotkey32.exe')
        foreach ($name in $ahkExeCandidates) {
            $candidate = Join-Path $ahkDir $name
            if (Test-Path $candidate -PathType Leaf) {
                $ahkExe = $candidate
                break
            }
        }
        if (-not $ahkExe) {
            $found = @(Get-ChildItem -Path $ahkDir -Filter 'AutoHotkey*.exe' -File -ErrorAction SilentlyContinue |
                Sort-Object Name | Select-Object -First 1)
            if ($found.Count -gt 0) { $ahkExe = $found[0].FullName }
        }
        if (-not $ahkExe) {
            Write-Warning "  No AutoHotkey*.exe found in $ahkDir -- skipping."
        }
    }
}

if ($ahkExe) {
    $oldAhk = "$startupDir\hotkeys.ahk"
    if (Test-Path $oldAhk) { Remove-Item $oldAhk -Force }

    $shortcutPath = "$startupDir\hotkeys.lnk"
    $shell = New-Object -ComObject WScript.Shell
    $lnk = $shell.CreateShortcut($shortcutPath)
    $lnk.TargetPath       = $ahkExe
    $lnk.Arguments        = "`"$ahkScript`""
    $lnk.WorkingDirectory = Split-Path $ahkScript -Parent
    $lnk.Save()
    Write-Host "  Created startup shortcut: $shortcutPath -> $ahkExe"

    $ahkProcName = [System.IO.Path]::GetFileNameWithoutExtension($ahkExe)
    Get-Process -Name $ahkProcName -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Process -FilePath $ahkExe -ArgumentList "`"$ahkScript`""
    Write-Host "  AutoHotKey started"
    Write-Host "  AutoHotKey will launch automatically on next login via the startup shortcut."
}

Write-Host "PSFzf..."
if (Get-Module -ListAvailable -Name PSFzf -ErrorAction SilentlyContinue) {
    Write-Host "  Already installed"
} else {
    Install-Module PSFzf -Scope CurrentUser -Force
    Write-Host "  Installed PSFzf"
}

Write-Host ""
Write-Host "Done!"
