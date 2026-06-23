#Requires -Version 5.1
<#
.SYNOPSIS
    Bootstraps loadout's user-local bundled PowerShell on Windows.
.DESCRIPTION
    Intended for users starting from Windows PowerShell 5.1. Extracts the
    vendored PowerShell ZIP from pre_built/windows.x86_64/powershell into
    %USERPROFILE%\.local\opt\powershell\7, then optionally re-runs the main
    loadout installer under that pwsh.exe. No winget, Store, or elevation.
#>

param(
    [switch]$RunInstaller
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

foreach ($arg in $args) {
    if ($arg -eq '--run-installer') {
        $RunInstaller = $true
    }
}

$installerArgs = @()
foreach ($arg in $args) {
    if ($arg -ne '--run-installer') {
        $installerArgs += $arg
    }
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
        throw "Bundled PowerShell archive not found. Expected pre_built\windows.x86_64\powershell\PowerShell-*-win-x64.zip or .zip.part-000."
    }

    $version = Get-LoadoutPowerShellArchiveVersion -ArchiveName $archive.Name
    $installDir = Join-Path $env:USERPROFILE '.local\opt\powershell\7'
    $pwshExe = Join-Path $installDir 'pwsh.exe'
    $versionFile = Join-Path $installDir '.loadout-version'

    if ((Test-Path $pwshExe -PathType Leaf) -and (Test-Path $versionFile -PathType Leaf)) {
        $installedVersion = (Get-Content -Path $versionFile -ErrorAction SilentlyContinue | Select-Object -First 1)
        if ($installedVersion -eq $version) {
            Write-Host "Bundled PowerShell already installed: $pwshExe"
            return $pwshExe
        }
    }

    $tempRoot = Join-Path $env:TEMP ("loadout-pwsh-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    try {
        $zipPath = $archive.FullName
        if ($archive.Name.EndsWith('.part-000')) {
            Write-Host "Rejoining split PowerShell archive..."
            $zipPath = Join-LoadoutSplitArchive -PartZeroPath $archive.FullName -TempDir $tempRoot
        }

        $extractDir = Join-Path $tempRoot 'extract'
        New-Item -ItemType Directory -Path $extractDir -Force | Out-Null
        Write-Host "Extracting bundled PowerShell $version..."
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

    Write-Host "Installed bundled PowerShell: $pwshExe"
    return $pwshExe
}

$repoDir = $PSScriptRoot
$installScript = Join-Path $repoDir 'loadout.ps1'
$pwshPath = Install-LoadoutBundledPowerShell -RepoDir $repoDir

if ($RunInstaller) {
    Write-Host ''
    Write-Host 'Running loadout installer under bundled PowerShell...'
    & $pwshPath -NoProfile -ExecutionPolicy Bypass -File $installScript @installerArgs
    exit $LASTEXITCODE
}

Write-Host ''
Write-Host 'Bundled PowerShell install complete.'
Write-Host "Launch PowerShell 7 with: $pwshPath"
Write-Host 'Then rerun the loadout installer:'
Write-Host '  .\loadout.cmd'
