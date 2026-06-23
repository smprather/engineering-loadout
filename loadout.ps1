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

Options:
  -h, --help, -?, /?    Show this help and exit.

Notes:
  - Requires PowerShell 7+ for install.
  - No elevation required.
  - Copies Windows configs and installs/starts the user-local AutoHotkey script.
  - When running from a WSL UNC path, prefer loadout.cmd or the explicit pwsh
    command above. Direct .ps1 execution can be blocked by execution policy
    before this script starts.
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
    Write-Warning "Run powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\loadout-pwsh-bootstrap.ps1 from Windows PowerShell 5.1, then rerun .\loadout.cmd or .\loadout.ps1 from pwsh."
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
        '# loadout.ps1 patches feature flags in hotkeys.ahk from this list.',
        '# Legacy [autohotkey.plugins] entries are still accepted for existing installs.',
        '',
        '[autohotkey]',
        'enabled = true',
        '',
        '[autohotkey.features]',
        'enabled = ['
    )

    foreach ($feature in $FeatureDefinitions) {
        $lines += "  # `"$($feature.Id)`",  # $($feature.Description)"
    }

    $lines += ']'

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

function Set-AhkFeatureFlags {
    param(
        [string]$AhkScriptPath,
        [bool]$AutoHotkeyEnabled,
        [string[]]$EnabledFeatureIds,
        [object[]]$FeatureDefinitions
    )

    $content = Get-Content -Path $AhkScriptPath -Raw -ErrorAction Stop

    foreach ($feature in $FeatureDefinitions) {
        $value = if ($AutoHotkeyEnabled -and ($EnabledFeatureIds -contains $feature.Id)) { 'true' } else { 'false' }
        $pattern = '(?m)^' + [regex]::Escape($feature.FlagName) + '\s*:=\s*(true|false)\s*$'
        $replacement = $feature.FlagName + ' := ' + $value
        $newContent = [regex]::Replace($content, $pattern, $replacement)
        if ($newContent -eq $content) {
            Write-Warning "  Could not find feature flag '$($feature.FlagName)' in $AhkScriptPath"
        }
        $content = $newContent
    }

    Set-Content -Path $AhkScriptPath -Value $content -Encoding UTF8
}

$repoDir = $PSScriptRoot
Write-Host "Loadout repo: $repoDir"
Write-Host ""

Write-Host "Neovim..."
Copy-Config "$repoDir\nvim" "$env:LOCALAPPDATA\nvim"

Write-Host "WezTerm..."
Copy-Config "$repoDir\wezterm\wezterm.lua" "$env:USERPROFILE\.config\wezterm\wezterm.lua"

Write-Host "Starship..."
Copy-Config "$repoDir\starship\starship.windows.toml" "$env:USERPROFILE\.config\starship\starship.toml"

Write-Host "PowerShell profile..."
$psProfileSource = "$repoDir\powershell\Microsoft.PowerShell_profile.ps1"
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
Copy-Config "$repoDir\editorconfig\editorconfig" "$env:USERPROFILE\.editorconfig"

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

Copy-Config "$repoDir\autohotkey\hotkeys.ahk" $ahkScript
Set-AhkFeatureFlags -AhkScriptPath $ahkScript -AutoHotkeyEnabled $loadoutAhkConfig.AutoHotkeyEnabled -EnabledFeatureIds $loadoutAhkConfig.EnabledFeatureIds -FeatureDefinitions $ahkFeatureDefinitions

if ($loadoutAhkConfig.AutoHotkeyEnabled) {
    if ($loadoutAhkConfig.EnabledFeatureIds.Count -gt 0) {
        Write-Host "  Enabled AHK features: $($loadoutAhkConfig.EnabledFeatureIds -join ', ')"
    } else {
        Write-Host "  Enabled AHK features: (none)"
    }
} else {
    Write-Host "  AutoHotKey is globally disabled in loadout_keys.toml; optional AHK features were written as off."
}

$legacyGeneratedFile = Join-Path $ahkHomeDir '_autoload_plugins.generated.ahk'
if (Test-Path $legacyGeneratedFile -PathType Leaf) {
    Remove-Item -Path $legacyGeneratedFile -Force
    Write-Host "  Removed legacy generated plugin include file: $legacyGeneratedFile"
}

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
    $ahkExe = Join-Path $ahkDir "AutoHotkey64.exe"
    if (-not (Test-Path $ahkExe)) {
        Write-Warning "  AutoHotkey64.exe not found in $ahkDir -- skipping."
    } else {
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

        Get-Process -Name 'AutoHotkey*' -ErrorAction SilentlyContinue | Stop-Process -Force
        Start-Process -FilePath $ahkExe -ArgumentList "`"$ahkScript`""
        Write-Host "  AutoHotKey started"
        Write-Host "  AutoHotKey will launch automatically on next login via the startup shortcut."
    }
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
