# =============================================================================
# Navigation
# =============================================================================

$global:__prevLocation = $null

# This function is used to change the hash-code of an exe file which might help
# get around SentinelOne's over-zealous "malware" flagging. I made it specifically
# for AutoHotkey, but I'm sure it will come in helpful for other "malware".
function Invoke-PatchDOSStub {
    param (
        [Parameter(Mandatory=$true)]
        [string]$InputPath,

        [Parameter(Mandatory=$false)]
        [string]$OutputPath,

        [string]$OldString = "This program cannot be run in DOS mode",
        [string]$NewString = "This program cannot be run in D0S mode"
    )

    # 1. Validate File and String Lengths
    if (-not (Test-Path $InputPath)) { Throw "File not found: $InputPath" }
    if ($OldString.Length -ne $NewString.Length) {
        Throw "Error: Replacement string must be the exact same length as the original."
    }

    # Set default output path if none provided (adds _modified suffix)
    if (-not $OutputPath) {
        $OutputPath = $InputPath.Replace(".exe", "_modified.exe")
    }

    Write-Host "Reading file..." -ForegroundColor Cyan
    $bytes = [System.IO.File]::ReadAllBytes($InputPath)
    $searchPattern = [System.Text.Encoding]::ASCII.GetBytes($OldString)
    $replacePattern = [System.Text.Encoding]::ASCII.GetBytes($NewString)

    $found = $false

    # 2. Search and Replace Logic
    for ($i = 0; $i -le ($bytes.Length - $searchPattern.Length); $i++) {
        $match = $true
        for ($j = 0; $j -lt $searchPattern.Length; $j++) {
            if ($bytes[$i + $j] -ne $searchPattern[$j]) {
                $match = $false
                break
            }
        }

        if ($match) {
            for ($j = 0; $j -lt $replacePattern.Length; $j++) {
                $bytes[$i + $j] = $replacePattern[$j]
            }
            $found = $true
            Write-Host "Found target string at offset: $i" -ForegroundColor Green
            break
        }
    }

    # 3. Finalize and Compare
    if ($found) {
        [System.IO.File]::WriteAllBytes($OutputPath, $bytes)

        $oldHash = (Get-FileHash $InputPath -Algorithm SHA256).Hash
        $newHash = (Get-FileHash $OutputPath -Algorithm SHA256).Hash

        Write-Host "`n--- Success ---" -ForegroundColor Green
        Write-Host "Modified file: $OutputPath"
        Write-Host "Old SHA256: $oldHash"
        Write-Host "New SHA256: $newHash"
    } else {
        Write-Warning "Target string '$OldString' was not found in the binary."
    }
}

function Set-LocationEx {
    param([string]$Path = $env:USERPROFILE)
    if ($Path -eq '-') {
        if ($global:__prevLocation) {
            $prev = $global:__prevLocation
            $global:__prevLocation = (Get-Location).Path
            Set-Location $prev
        } else {
            Write-Warning "cd: no previous directory"
            return
        }
    } else {
        $global:__prevLocation = (Get-Location).Path
        Set-Location $Path
    }
    ls_func
}
Set-Alias -Name cd -Value Set-LocationEx -Option AllScope

function b    { Set-LocationEx .. }
function bb   { Set-LocationEx ..\.. }
function bbb  { Set-LocationEx ..\..\.. }
function bbbb      { Set-LocationEx ..\..\..\.. }
function bbbbb     { Set-LocationEx ..\..\..\..\.. }
function bbbbbb    { Set-LocationEx ..\..\..\..\..\.. }
function bbbbbbb   { Set-LocationEx ..\..\..\..\..\..\.. }
function bbbbbbbb  { Set-LocationEx ..\..\..\..\..\..\..\.. }
function bbbbbbbbb { Set-LocationEx ..\..\..\..\..\..\..\..\.. }
function bbbbbbbbbb { Set-LocationEx ..\..\..\..\..\..\..\..\..\.. }

function cdd {
    $dir = Get-ChildItem -Directory | Sort-Object LastWriteTime -Descending | Select-Object -Index 0
    if ($dir) { Set-LocationEx $dir.FullName }
    else      { Write-Warning "No subdirectories found" }
}
function cddd {
    $dir = Get-ChildItem -Directory | Sort-Object LastWriteTime -Descending | Select-Object -Index 1
    if ($dir) { Set-LocationEx $dir.FullName }
    else      { Write-Warning "No subdirectories found" }
}
function cdddd {
    $dir = Get-ChildItem -Directory | Sort-Object LastWriteTime -Descending | Select-Object -Index 2
    if ($dir) { Set-LocationEx $dir.FullName }
    else      { Write-Warning "No subdirectories found" }
}
function cddddd {
    $dir = Get-ChildItem -Directory | Sort-Object LastWriteTime -Descending | Select-Object -Index 3
    if ($dir) { Set-LocationEx $dir.FullName }
    else      { Write-Warning "No subdirectories found" }
}

function mkd {
    param([string]$Path)
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
    Set-LocationEx $Path
}

# =============================================================================
# File operations
# =============================================================================

function touch {
    param([string]$Path)
    if (Test-Path $Path) { (Get-Item $Path).LastWriteTime = Get-Date }
    else                 { New-Item $Path -ItemType File | Out-Null }
}

function head {
    param([int]$n = 10, [string]$Path)
    if ($Path) { Get-Content $Path -TotalCount $n }
    else       { $input | Select-Object -First $n }
}

function tail {
    param([int]$n = 10, [string]$Path)
    if ($Path) { Get-Content $Path -Tail $n }
    else       { $input | Select-Object -Last $n }
}

# =============================================================================
# Search
# =============================================================================

function g    { rg --smart-case --search-zip --hidden --no-ignore @args }
function grep { rg --smart-case --search-zip --hidden --no-ignore @args }

function ls_func {
    $argList = @('--sort', 'modified', '--time', 'modified', '--long') + $args
    $proc = Start-Process 'eza' -ArgumentList $argList -NoNewWindow -PassThru
    if (-not $proc.WaitForExit(5000)) {
        $proc.Kill()
        Write-Warning "eza: timed out"
    }
}
function fd_func { fd --unrestricted --full-path @args }

# =============================================================================
# Utilities
# =============================================================================

function rps  { Start-Process PowerShell; exit }
function open { Invoke-Item @args }
function which { (Get-Command $args[0]).Path }

function Get-DefinitionPath {
    param([string]$Name)
    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if (-not $command) { Write-Host "Command or function '$Name' not found."; return }
    switch ($command.CommandType) {
        'Function'    {
            if ($command.ScriptBlock.File) { Write-Host "Definition path: $($command.ScriptBlock.File)" }
            else                           { Write-Host "Function is defined in the current session." }
            Write-Host $command.Definition
        }
        'Application' { Write-Host "Definition path: $($command.Path)" }
        'Cmdlet'      { Write-Host "Cmdlet: $($command.Name)" }
        'Alias'       { Write-Host "Alias: $($command.Definition)"; Get-DefinitionPath $command.Definition }
        default       { Write-Host "Command type '$($command.CommandType)' is not supported." }
    }
}

# =============================================================================
# Aliases
# =============================================================================

# Replace PowerShell Unix-like aliases with real coreutils when available (e.g. Git for Windows).
# sort/tee/kill/ps are intentionally skipped -- they're used heavily in PS object pipelines.
# Find the coreutils directory once via a sentinel file (faster than per-command Get-Command calls).
$__coreutilsDir = $env:PATH -split ';' |
    Where-Object { $_ -and (Test-Path (Join-Path $_ 'rm.exe')) } |
    Select-Object -First 1
if ($__coreutilsDir) {
    foreach ($__cmd in @(
        @{ name = 'rm';    remove = 'Alias' }
        @{ name = 'cp';    remove = 'Alias' }
        @{ name = 'mv';    remove = 'Alias' }
        @{ name = 'diff';  remove = 'Alias' }
        @{ name = 'rmdir'; remove = 'Alias' }
        @{ name = 'mkdir'; remove = 'Function' }
    )) {
        $__exe = Join-Path $__coreutilsDir ($__cmd.name + '.exe')
        if (Test-Path $__exe) {
            Remove-Item -Path "$($__cmd.remove):$($__cmd.name)" -Force -ErrorAction SilentlyContinue
            $__sb = [scriptblock]::Create("& '$__exe' @args")
            New-Item -Path "Function:$($__cmd.name)" -Value $__sb.GetNewClosure() -Force | Out-Null
        }
    }
    foreach ($__name in @('wc', 'sed', 'awk', 'cut', 'xargs')) {
        $__exe = Join-Path $__coreutilsDir ($__name + '.exe')
        if (Test-Path $__exe) {
            $__sb = [scriptblock]::Create("& '$__exe' @args")
            New-Item -Path "Function:$__name" -Value $__sb.GetNewClosure() -Force | Out-Null
        }
    }
}
Remove-Variable __coreutilsDir, __cmd, __name, __exe, __sb -ErrorAction SilentlyContinue

Set-Alias -Name ls   -Value ls_func            -Option AllScope
Set-Alias -Name lr   -Value ls_func            -Option AllScope
Set-Alias -Name vi   -Value nvim               -Option AllScope
Set-Alias -Name f    -Value fd_func            -Option AllScope
Set-Alias -Name w    -Value Get-DefinitionPath -Option AllScope
Set-Alias -Name p    -Value Get-Location       -Option AllScope
Set-Alias -Name cat  -Value bat                -Option AllScope

# =============================================================================
# ls variants
# =============================================================================

function ll  { eza -l @args }
function la  { eza -a @args }
function lh  { eza -lh @args }
function lah { eza -lah @args }
function lg  { eza -l --git @args }
function lsg { eza --git @args }
function tree { eza -T @args }

# =============================================================================
# Git
# =============================================================================

function gs  { git status }
function gc  { git commit @args }
function gp  { git push @args }
function gd  { git diff @args }
function gsp { git stash; git pull; git stash pop }
function ga {
    if ($args.Count -eq 0) { git add --all . }
    else                   { git add @args }
    git status
}

# =============================================================================
# Editor
# =============================================================================

function vii     { nvim (Get-ChildItem | Sort-Object LastWriteTime -Descending | Select-Object -First 1).Name }
function vid     { nvim -d @args }
function vimdiff { nvim -d @args }

# =============================================================================
# History / search
# =============================================================================

function hg    { param([string]$Pattern) Get-History | Where-Object { $_.CommandLine -match $Pattern } }
function h     { param([string]$Pattern) Get-History | Where-Object { $_.CommandLine -match $Pattern } }
function agrep { param([string]$Pattern) Get-Alias  | Where-Object { $_.Name -match $Pattern -or $_.Definition -match $Pattern } }

# =============================================================================
# Path / system
# =============================================================================

function pl { $i = 1; $env:PATH -split ';' | ForEach-Object { "$i`t$_"; $i++ } }
function rp { if ($args[0]) { Resolve-Path $args[0] } else { Resolve-Path . } }
function c  { Clear-Host }

# =============================================================================
# Archive
# =============================================================================

function tx { tar -xvf @args }
function tt { tar -tvf @args }

# =============================================================================
# Misc
# =============================================================================

function new {
    param([string]$file)
    New-Item $file -ItemType File | Out-Null
    nvim $file
}
function wip { nvim "$HOME\wip.txt" }
function du {
    Get-ChildItem @args | ForEach-Object {
        $size = if ($_.PSIsContainer) {
            (Get-ChildItem $_.FullName -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
        } else { $_.Length }
        [PSCustomObject]@{ 'Size(MB)' = [math]::Round($size / 1MB, 2); Name = $_.Name }
    } | Sort-Object 'Size(MB)' -Descending
}

# =============================================================================
# fzf shortcuts (conditional)
# =============================================================================

if (Get-Command fzf -ErrorAction SilentlyContinue) {
    function fls  { Get-ChildItem (fzf) }
    function fvi  { nvim (fzf) }
    function fcat { bat (fzf) }
}

# =============================================================================
# Interactive shell integrations
# =============================================================================

$profileIsInteractive = $Host.Name -in @('ConsoleHost', 'Visual Studio Code Host')
$profileIsSandbox = $env:USERNAME -eq 'CodexSandboxOffline'
$profileHasTerminalOutput = -not [Console]::IsOutputRedirected
$profileSupportsVT = $false
try {
    $profileSupportsVT = [bool]$Host.UI.SupportsVirtualTerminal
} catch {
    $profileSupportsVT = $false
}
$profileCanUsePromptTools = $profileIsInteractive -and -not $profileIsSandbox -and $profileHasTerminalOutput
$profileCanUsePSReadLine = $profileCanUsePromptTools -and $profileSupportsVT

if ($profileCanUsePSReadLine) {
    try {
        Set-PSReadLineOption -EditMode Emacs
        Set-PSReadLineOption -HistorySearchCursorMovesToEnd
        Set-PSReadLineOption -BellStyle None
        Set-PSReadLineKeyHandler -Key UpArrow   -Function HistorySearchBackward
        Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
        Set-PSReadLineKeyHandler -Key Tab       -Function MenuComplete
    } catch {
        Write-Verbose "PowerShell profile: skipped PSReadLine keybind setup due to terminal limitations."
        $profileCanUsePSReadLine = $false
    }

    # Inline prediction (requires PSReadLine 2.2+ / PS 7.2+)
    if ($profileCanUsePSReadLine) {
        try {
            Set-PSReadLineOption -PredictionSource HistoryAndPlugin
            Set-PSReadLineOption -PredictionViewStyle ListView
        } catch {
            Set-PSReadLineOption -PredictionSource History
        }
    }
}

if ($profileCanUsePromptTools) {
    # Invoke-CachedInit: runs "<exe> <args>" and caches the output script.
    # Re-generates only when the binary is newer than the cache file.
    function Invoke-CachedInit {
        param([string]$Exe, [string[]]$InitArgs, [string]$Cache)
        $exeCmd = Get-Command $Exe -ErrorAction SilentlyContinue
        if (-not $exeCmd) { return }
        $cacheDir = Split-Path $Cache
        if (-not (Test-Path $cacheDir)) { New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null }
        if (-not (Test-Path $Cache) -or
                (Get-Item $exeCmd.Source).LastWriteTime -gt (Get-Item $Cache).LastWriteTime) {
            & $exeCmd.Source @InitArgs | Set-Content $Cache -Encoding UTF8
        }
        Get-Content $Cache -Raw | Invoke-Expression
    }
    $__initCache = "$env:LOCALAPPDATA\Microsoft\Windows\PowerShell\ProfileCache"

    # zoxide (smarter cd -- use 'z' and 'zi' for interactive)
    try {
        Invoke-CachedInit zoxide @('init', 'powershell') "$__initCache\zoxide.ps1"
    } catch {
        Write-Verbose "PowerShell profile: skipped zoxide initialization."
    }

    # PSFzf -- Ctrl+T file picker, Ctrl+R fuzzy history; falls back to built-in Ctrl+R if unavailable
    if ($profileCanUsePSReadLine) {
        # Test-Path on each module dir is much faster than Get-Module -ListAvailable,
        # which walks and parses every module manifest on the system.
        $__psfzf = $env:PSModulePath -split ';' |
            ForEach-Object { Join-Path $_ 'PSFzf' } |
            Where-Object { Test-Path $_ } |
            Select-Object -First 1
        if ($__psfzf) {
            try {
                Import-Module $__psfzf
                Set-PsFzfOption -PSReadlineChordProvider 'Ctrl+t' -PSReadlineChordReverseHistory 'Ctrl+r'
            } catch {
                Write-Verbose "PowerShell profile: skipped PSFzf setup."
            }
        } else {
            try {
                Set-PSReadLineKeyHandler -Chord 'Ctrl+r' -Function ReverseSearchHistory
            } catch {
                Write-Verbose "PowerShell profile: skipped reverse search keybinding."
            }
        }
    }

    # Starship prompt
    try {
        Invoke-CachedInit starship @('init', 'powershell') "$__initCache\starship.ps1"
    } catch {
        Write-Verbose "PowerShell profile: skipped Starship prompt."
    }

    Remove-Variable __initCache -ErrorAction SilentlyContinue
    Remove-Item Function:Invoke-CachedInit -ErrorAction SilentlyContinue
}
