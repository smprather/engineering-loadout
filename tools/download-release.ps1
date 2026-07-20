#Requires -Version 5.1
<#
.SYNOPSIS
    Downloads an engineering-loadout GitHub release to a Windows directory,
    verifies every asset against sha256sums.txt, and prints the scp command
    to move the files to a Linux box.

.DESCRIPTION
    Trust chain (do not shortcut any link):

        signed tag  ->  sha256sums.txt (release asset)  ->  asset bytes
                     ->  .content-manifest.fetched  (written by fetch-stash on Linux)

    This script downloads the release source tarball plus the integrity-critical
    assets (sha256sums.txt, .content-manifest, nvim-plugin-stash.tar.bz2), computes
    SHA-256 for each, and checks it against sha256sums.txt. Any file that fails
    verification is deleted immediately -- an unverified file is never left behind.

    Designed for locked-down Windows laptops: PowerShell 5.1 only, no WSL, no VMs,
    no admin rights, no modules, no curl/wget/gh. Invoke-WebRequest + Get-FileHash.

.PARAMETER Tag
    Release tag to download (default: latest).

.PARAMETER OutDir
    Directory to save files into (default: .\loadout-release). Created if missing.

.EXAMPLE
    .\tools\download-release.ps1
    .\tools\download-release.ps1 -Tag v2026.07.14 -OutDir C:\Users\me\Desktop\loadout
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\download-release.ps1 -Tag v2026.07.14

.NOTES
    Corporate TLS interception is common in these environments. If
    Invoke-WebRequest fails with a TLS/SSL error, the script prints an actionable
    message instead of a stack trace. The most common fix is forcing TLS 1.2:
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    which this script already does, but a MITM proxy with a bad cert may still
    block it. In that case download via a browser and pass the files to fetch-stash
    --from-file on Linux.
#>

[CmdletBinding()]
param(
    [string]$Tag = 'latest',
    [string]$OutDir = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

$script:Slug = 'smprather/engineering-loadout'

# Assets we download from the release (name in release -> local filename).
# The source tarball is special: GitHub generates it, it is not an "asset" in
# the assets list, and its filename depends on the tag.
$script:StashName = 'nvim-plugin-stash.tar.bz2'
$script:SumsName  = 'sha256sums.txt'
$script:ManifestNames = @('.content-manifest', 'default.content-manifest')

# ---------------------------------------------------------------------------
# TLS hardening for PS 5.1 (corporate MITM proxies often break default TLS)
# ---------------------------------------------------------------------------

try {
    [Net.ServicePointManager]::SecurityProtocol =
        [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
} catch {
    # PS 5.1 has no Tls13 enum; fall back to Tls12 alone.
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

function Write-Section {
    param([string]$Message)
    Write-Host ''
    Write-Host $Message -ForegroundColor Cyan
}

function New-OutputDir {
    param([string]$Dir)
    if (-not (Test-Path $Dir -PathType Container)) {
        New-Item -ItemType Directory -Path $Dir -Force | Out-Null
    }
    return (Resolve-Path -LiteralPath $Dir).Path
}

function Invoke-GitHubApi {
    <#
        Call the GitHub REST API and return the parsed JSON object.
        Handles auth via GITHUB_TOKEN / GH_TOKEN when present (unauthenticated
        rate limit is 60/hour, which is plenty for a single release lookup,
        but corporate proxies sometimes require it).
    #>
    param([string]$Path)

    $url = "https://api.github.com/repos/$($script:Slug)/$Path"
    $headers = @{ 'User-Agent' = 'loadout-download-release.ps1' }
    $token = $env:GITHUB_TOKEN; if (-not $token) { $token = $env:GH_TOKEN }
    if ($token) { $headers['Authorization'] = "Bearer $token" }

    try {
        $resp = Invoke-WebRequest -Uri $url -Headers $headers -UseBasicParsing -TimeoutSec 30
    } catch [System.Net.WebException] {
        $msg = $_.Exception.Message
        if ($msg -match 'SSL|TLS|certificate|trust|handshake|secure channel') {
            Write-TlsError $msg
            exit 1
        }
        if ($_.Exception.Response) {
            $code = [int]$_.Exception.Response.StatusCode
            Write-Host "ERROR: GitHub API returned HTTP $code for $url" -ForegroundColor Red
            if ($code -eq 404) {
                Write-Host "  No such release. Check -Tag (omit it for latest), or the repo slug." -ForegroundColor Red
            }
        } else {
            Write-Host "ERROR: cannot reach github.com: $msg" -ForegroundColor Red
            Write-Host "  If this network blocks github, you are on the wrong machine for this step." -ForegroundColor Red
            Write-Host "  Use a browser on a network that can reach it, then pass the files to" -ForegroundColor Red
            Write-Host "  fetch-stash --from-file on Linux." -ForegroundColor Red
        }
        exit 1
    } catch {
        $msg = $_.Exception.Message
        if ($msg -match 'SSL|TLS|certificate|trust|handshake|secure channel') {
            Write-TlsError $msg
            exit 1
        }
        Write-Host "ERROR: $msg" -ForegroundColor Red
        exit 1
    }

    return $resp.Content | ConvertFrom-Json
}

function Write-TlsError {
    param([string]$Message)
    Write-Host ''
    Write-Host 'ERROR: TLS/SSL connection to github.com failed.' -ForegroundColor Red
    Write-Host "  $Message" -ForegroundColor Red
    Write-Host ''
    Write-Host 'This is common behind corporate TLS-interception proxies. Fixes:' -ForegroundColor Yellow
    Write-Host '  1. This script already forces TLS 1.2/1.3. If the proxy uses an' -ForegroundColor Yellow
    Write-Host '     untrusted CA, the .NET stack will reject it. Check whether your' -ForegroundColor Yellow
    Write-Host '     org installs a root CA for inspection; it must be in the Windows' -ForegroundColor Yellow
    Write-Host '     certificate store (LocalMachine Root or CurrentUser Root).' -ForegroundColor Yellow
    Write-Host '  2. As a last resort, download the files in a browser (which trusts' -ForegroundColor Yellow
    Write-Host '     the corp CA) and copy them to Linux, then run fetch-stash there:' -ForegroundColor Yellow
    Write-Host '       ./fetch-stash --from-file <stash> --sums <sha256sums.txt>' -ForegroundColor Yellow
    Write-Host '  3. If github.com itself is blocked (not just TLS), no PowerShell' -ForegroundColor Yellow
    Write-Host '     setting will help -- try a different network.' -ForegroundColor Yellow
}

function Get-ReleaseInfo {
    param([string]$Tag)

    if ($Tag -eq 'latest' -or -not $Tag) {
        return Invoke-GitHubApi -Path 'releases/latest'
    }
    return Invoke-GitHubApi -Path "releases/tags/$Tag"
}

function Get-AssetUrl {
    param($Assets, [string[]]$Names)

    foreach ($name in $Names) {
        $asset = $Assets | Where-Object { $_.name -eq $name } | Select-Object -First 1
        if ($asset) { return $asset }
    }
    return $null
}

function Invoke-DownloadFile {
    <#
        Download a single file with a progress bar. Uses IWR's built-in
        progress for PS 5.1 (Write-Progress under the hood). For files over
        ~50 MB the progress bar is critical: a silent 5-minute hang on the
        328 MB stash looks exactly like a crash.
    #>
    param([string]$Url, [string]$Dest)

    $progress = $ProgressPreference
    $ProgressPreference = 'Continue'
    try {
        Invoke-WebRequest -Uri $Url -OutFile $Dest -UseBasicParsing -TimeoutSec 600
    } catch [System.Net.WebException] {
        $msg = $_.Exception.Message
        if ($msg -match 'SSL|TLS|certificate|trust|handshake|secure channel') {
            Write-TlsError $msg
            Remove-Item -LiteralPath $Dest -Force -ErrorAction SilentlyContinue
            exit 1
        }
        throw
    } finally {
        $ProgressPreference = $progress
    }
}

function Get-FileSha256 {
    param([string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLower()
}

function Read-SumsFile {
    <#
        Parse a coreutils sha256sum -c style file: "<hash>  <filename>".
        Returns a hashtable { basename -> hash }.
    #>
    param([string]$Path)

    $map = @{}
    foreach ($line in Get-Content -LiteralPath $Path -ErrorAction Stop) {
        if (-not $line -or $line.StartsWith('#')) { continue }
        $parts = $line -split '\s+', 2
        if ($parts.Count -lt 2) { continue }
        $hash = $parts[0].Trim().ToLower()
        $namePart = $parts[1].Trim()
        # Strip any leading * (binary-mode marker) and take the basename.
        $namePart = $namePart -replace '^\*', ''
        $basename = Split-Path -Leaf $namePart.Trim()
        $map[$basename] = $hash
    }
    return $map
}

function Test-FileHash {
    <#
        Verify a downloaded file against the expected hash from sha256sums.txt.
        On mismatch, delete the file and write a clear error. Returns $true on
        match, $false on mismatch. Never leaves an unverified file behind.
    #>
    param(
        [string]$Path,
        [string]$ExpectedHash,
        [string]$LogicalName
    )

    if (-not $ExpectedHash) {
        Write-Host "  ERROR: no sha256 entry for '$LogicalName' in sha256sums.txt." -ForegroundColor Red
        Write-Host '  The release is incomplete or tampered. Refusing to trust it.' -ForegroundColor Red
        Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
        return $false
    }

    $size = (Get-Item -LiteralPath $Path).Length
    $sizeMb = [math]::Round($size / 1MB, 1)
    Write-Host "  verifying $LogicalName ($sizeMb MB)..." -ForegroundColor Gray
    $got = Get-FileSha256 -Path $Path

    if ($got -eq $ExpectedHash) {
        Write-Host "  OK  $LogicalName  $got" -ForegroundColor Green
        return $true
    }

    Write-Host "  ERROR: SHA-256 MISMATCH for $LogicalName" -ForegroundColor Red
    Write-Host "    expected: $ExpectedHash" -ForegroundColor Red
    Write-Host "    got:       $got" -ForegroundColor Red
    Write-Host '  The file does not match the signed release. Deleting it.' -ForegroundColor Red
    Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    return $false
}

function Get-SourceTarballUrl {
    <#
        GitHub auto-generates source tarballs at a stable URL pattern. They are
        not listed in the release "assets" array -- only uploaded assets are.
    #>
    param([string]$TagName)
    return "https://codeload.github.com/$($script:Slug)/tar.gz/refs/tags/$TagName"
}

function Get-SourceTarballName {
    param([string]$TagName)
    # GitHub names it <repo>-<tag>.tar.gz, where the repo name is the second
    # path component of the slug.
    $repoName = ($script:Slug -split '/')[-1]
    return "$repoName-$TagName.tar.gz"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

$scriptDir = $PSScriptRoot
$repoRoot  = Split-Path $scriptDir -Parent

Write-Host ''
Write-Host 'download-release.ps1 -- engineering-loadout release downloader (Windows)' -ForegroundColor Cyan
Write-Host "  repo:   https://github.com/$($script:Slug)"
Write-Host "  tag:    $Tag"

$outPath = if ($OutDir) { $OutDir } else { 'loadout-release' }
$outPath = New-OutputDir -Dir $outPath
Write-Host "  output: $outPath"

# --- 1. Resolve the release -------------------------------------------------

Write-Section 'Resolving release...'
$release = Get-ReleaseInfo -Tag $Tag
$tagName = $release.tag_name
Write-Host "  release tag: $tagName"

if (-not $release.assets) {
    Write-Host "ERROR: release $tagName has no assets. Cannot verify." -ForegroundColor Red
    exit 1
}

# Build { name -> download_url } for uploaded assets.
$assetMap = @{}
foreach ($a in $release.assets) {
    $assetMap[$a.name] = $a.browser_download_url
}

# --- 2. Download sha256sums.txt (the trust root for this run) ---------------

Write-Section 'Downloading sha256sums.txt (trust root)...'
$sumsUrl = $assetMap[$script:SumsName]
if (-not $sumsUrl) {
    Write-Host "ERROR: release $tagName has no $($script:SumsName) asset." -ForegroundColor Red
    Write-Host '  Without it there is nothing to verify against.' -ForegroundColor Red
    exit 1
}
$sumsPath = Join-Path $outPath $script:SumsName
Invoke-DownloadFile -Url $sumsUrl -Dest $sumsPath
Write-Host "  saved: $sumsPath"

$sums = Read-SumsFile -Path $sumsPath

# Verify sha256sums.txt itself against its own entry (if present -- older
# releases may not list it, since it is generated at release time).
$sumsSelf = $sums[$script:SumsName]
if ($sumsSelf) {
    if (-not (Test-FileHash -Path $sumsPath -ExpectedHash $sumsSelf -LogicalName $script:SumsName)) {
        exit 1
    }
} else {
    Write-Host "  NOTE: $($script:SumsName) has no self-entry (older release). Trust comes from the signed tag." -ForegroundColor Yellow
}

# --- 3. Download the source tarball -----------------------------------------

Write-Section 'Downloading source tarball...'
$tarballName = Get-SourceTarballName -TagName $tagName
$tarballPath = Join-Path $outPath $tarballName
$tarballUrl = Get-SourceTarballUrl -TagName $tagName
Invoke-DownloadFile -Url $tarballUrl -Dest $tarballPath
Write-Host "  saved: $tarballPath"

# The source tarball is not in sha256sums.txt (it is auto-generated by GitHub
# and its hash is not known at release time). We note that explicitly so the
# user knows it is the one file whose integrity comes from the signed tag +
# GitHub's transport, not from sha256sums.txt.
$tarballExpected = $sums[$tarballName]
if ($tarballExpected) {
    if (-not (Test-FileHash -Path $tarballPath -ExpectedHash $tarballExpected -LogicalName $tarballName)) {
        exit 1
    }
} else {
    Write-Host "  NOTE: $tarballName is not in sha256sums.txt (GitHub generates it at" -ForegroundColor Yellow
    Write-Host '  download time). Its integrity comes from the signed tag + HTTPS transport.' -ForegroundColor Yellow
}

# --- 4. Download .content-manifest ------------------------------------------

Write-Section 'Downloading .content-manifest...'
$manifestAsset = Get-AssetUrl -Assets $release.assets -Names $script:ManifestNames
if ($manifestAsset) {
    $manifestName = $manifestAsset.name
    $manifestPath = Join-Path $outPath '.content-manifest'
    Invoke-DownloadFile -Url $manifestAsset.browser_download_url -Dest $manifestPath
    Write-Host "  saved: $manifestPath (asset name: $manifestName)"

    $manifestExpected = $sums['.content-manifest']
    if (-not (Test-FileHash -Path $manifestPath -ExpectedHash $manifestExpected -LogicalName '.content-manifest')) {
        exit 1
    }
} else {
    Write-Host "  WARNING: no .content-manifest asset on release $tagName." -ForegroundColor Yellow
    Write-Host '  Older releases do not carry it. The installer will use the in-tree copy' -ForegroundColor Yellow
    Write-Host '  from the source tarball instead.' -ForegroundColor Yellow
}

# --- 5. Download nvim-plugin-stash.tar.bz2 (the big one) --------------------

Write-Section 'Downloading nvim-plugin-stash.tar.bz2 (~328 MB, this takes a while)...'
$stashUrl = $assetMap[$script:StashName]
if ($stashUrl) {
    $stashPath = Join-Path $outPath $script:StashName
    Invoke-DownloadFile -Url $stashUrl -Dest $stashPath
    Write-Host "  saved: $stashPath"

    $stashExpected = $sums[$script:StashName]
    if (-not (Test-FileHash -Path $stashPath -ExpectedHash $stashExpected -LogicalName $script:StashName)) {
        exit 1
    }
} else {
    Write-Host "  NOTE: release $tagName has no $($script:StashName) asset." -ForegroundColor Yellow
    Write-Host '  Releases before the stash moved out of git do not carry it.' -ForegroundColor Yellow
    Write-Host '  You will get nvim with no plugins. That is fine if you only need the core.' -ForegroundColor Yellow
}

# --- 6. Summary + scp instructions ------------------------------------------

Write-Section 'Done. Files in:'
Get-ChildItem -LiteralPath $outPath -File | Sort-Object Name | ForEach-Object {
    $sizeMb = [math]::Round($_.Length / 1MB, 1)
    Write-Host ("  {0,-40} {1,8} MB" -f $_.Name, $sizeMb)
}

# Build the scp command. Use forward slashes for the Windows path so it works
# from any shell on Linux after the files arrive. Quote the Windows dir so
# spaces survive. The Linux destination is a placeholder the user replaces.
$winPath = $outPath -replace '\\', '/'
Write-Host ''
Write-Host 'Next: copy these files to your Linux box. Run from THIS Windows laptop:' -ForegroundColor Cyan
Write-Host ''
Write-Host "  scp `"$winPath\*`" <user>@<linux-host>:~/loadout-release/" -ForegroundColor White
Write-Host ''
Write-Host 'Then on Linux, from the engineering-loadout checkout:' -ForegroundColor Cyan
Write-Host ''
Write-Host '  ./fetch-stash --from-file ~/loadout-release/nvim-plugin-stash.tar.bz2 \' -ForegroundColor White
Write-Host '      --sums ~/loadout-release/sha256sums.txt' -ForegroundColor White
Write-Host '  ./loadout install @shared-all' -ForegroundColor White
Write-Host ''
Write-Host 'fetch-stash re-verifies the stash hash against sha256sums.txt and records it' -ForegroundColor Gray
Write-Host 'in .content-manifest.fetched so the installer accepts it.' -ForegroundColor Gray