# Copilot Instructions

Dotfiles for Electrical Engineering work environments: multi-platform (RedHat 7/8/9, Suse, x86_64/ARM/PowerPC), offline-first (plugins bundled), no-root installs, with a layered configuration hierarchy (global → corp → site → project → user).

## Key Commands

```bash
# Linux install (copies files — no repo references remain)
./engineering-loadout

# Install with directory-level symlinks (easiest for editing)
./engineering-loadout --dev

# Stage an install into a temp/test root
./engineering-loadout --dest-dir /tmp/dotfiles-home

# Restore from numbered backup
./engineering-loadout --restore-backup loadout_backups/backup.1

# Skip optional large/offline payloads
./engineering-loadout --no-fonts
./engineering-loadout --no-tldr-cache

# Reload bash after changes
exec bash

# Install repo-development git hooks manually
cp hooks/* .git/hooks/ && chmod +x .git/hooks/*

# Smoke-test a fresh Linux home install
./tests/install_linux_tmp_home
```

```powershell
# Windows install (copies files, no elevation required)
.\install.ps1
```

Use `python3 -m py_compile install` and `bash -n bash/global/bashrc` after
installer or shell edits.
`./tests/install_linux_tmp_home` runs the Linux installer against a temp `HOME`
with temp XDG cache/state dirs from `/tmp`, then smoke-tests offline Tree-sitter
with headless Neovim.

## Architecture

### Bash Layer System

`bash/bashrc` is the single entry point (symlinked to `~/.bashrc`, `~/.bash_profile`, `~/.bash_login`, and `~/.profile`). It sources files in layer order across five layers: `global → corp → site → project → user`. Each layer directory lives under `~/.config/bash/` after install.

Loading sequence (`bash/bashrc`):
1. Sources `bash/functions.sh` (shared utilities available to all layers)
2. Sources `config.sh` per layer (sets `LOADOUT_CFG_*` preferences as exported scalars)
3. Sources `bashrc` per layer; each exits early if not interactive

`source_if_exists <path>` is used throughout for safe optional sourcing.

The `bash/global/` directory is the canonical upstream; the other layer dirs (`corp/`, `site/`, `project/`, `user/`) are user-created and not committed to this repo.

### Hook Injection Points

Each layer can inject code into `global/bashrc` via numbered files in `<layer>/global_hooks/`:

| File | Injection point |
|------|----------------|
| `1.sh` | After functions loaded |
| `2.sh` | After GLIBC detection |
| `3.sh` | After PATH setup |
| `4.sh` | After prompt configuration |
| `5.sh` | Before bash completions |
| `6.sh` | After bash completions loaded |
| `7.sh` | Late / deprecated |

### Install Modes

- **Production** (default): copies files; re-run `./engineering-loadout` to pick up repo changes
- **`--dev`**: directory-level symlinks for nvim/vim/tmux/editorconfig; for Starship, file-level symlinks to the selected OS config and Linux schema; for bash, symlinks individual repo-managed files (`global/`, `functions.sh`, `bashrc`) while preserving user layer dirs as real directories
- **`--dest-dir <dir>`**: install into an alternate root instead of `$HOME`; used by installer tests and staging
- **`--no-backup`**: skip backup creation (useful for clean reinstalls or automation)
- **`--no-fonts`**: skip vendored font extraction and font cache refresh
- **`--no-tldr-cache`**: skip bundled tealdeer/tldr page cache install
- **`--post-install-hook <script>`**: execute an explicit corp/site/user add-on hook after global install steps; can be repeated and hooks run in argument order; each hook must be executable and provide its own shebang or binary format
- **`--list-tools`**: print a two-column table (tool name, default install yes/no) and exit; takes priority over all other flags except `--help`
- **`--add-tools <names>`**: add optional tool(s) to the default install set (comma-separated); e.g. `--add-tools gui_libs,gvim,nedit-ng` for full GUI editor support on headless nodes
- **`--skip-tools <names>`**: remove tool(s) from the default install set
- **`--tools <names>`**: install exactly this set (replaces defaults entirely)

Backups are numbered (`loadout_backups/backup.N/`). The installer skips targets already pointing into the repo and never overwrites an existing backup.
Backups intentionally exclude font files because vendored Nerd Font archives are large and reproducible.

Repo git hooks are installed only by `./engineering-loadout --dev`; normal end-user installs skip them.
The Linux installer resolves the repo from the `install` script path, not the
current working directory. `install` is a Python 3.6-compatible executable and
checks the Python version before running.
Before each install area writes files, the installer verifies that the target
directory is writable. Unwritable areas are refused with warnings, later areas
continue when possible, and the run ends with an install results table.
Pre-built Linux binaries live under `pre_built/<platform>/`, using names like
`el8.x86_64.glibc2p28`. `RPATH=$ORIGIN/../lib64:$ORIGIN/../lib` is pre-baked
into each binary in the repo before bzip2 compression — the installer is pure
decompress + chmod, no runtime patchelf step. Installer runs `ldd` to warn
about missing `.so` dependencies. If a running binary cannot be replaced,
installer continues and prints a retry notice.
**Binary bundling order: strip → patchelf → bzip2.** Never strip after patchelf;
it corrupts `.dynstr` and causes segfaults or "undefined symbol" at runtime.
**Libs that must find each other** (e.g. the `gui_libs` group): patchelf with `$ORIGIN` (not
`$ORIGIN/../lib64`) — they install flat into `~/.local/lib64/` alongside each other.
**Never bundle**: glibc (`libc.so.6`, `libm.so.6`, etc.), OpenGL dispatcher (`libGL.so.1`,
`libGLX.so.0`, `libGLdispatch.so.0` — must match display driver), C++ runtime (`libstdc++.so.6`,
`libgcc_s.so.1`). Everything else is safe to bundle.
**Qt5 platform plugins** (`libqxcb.so`, `libqwayland-generic.so`) live flat in `~/.local/lib64/`;
`QT_QPA_PLATFORM_PLUGIN_PATH=$HOME/.local/lib64` set in `bash/global/bashrc` when present.
**WSLg cursor fix**: `QT_QPA_PLATFORM=wayland` in user bashrc — Qt5 XCB backend corrupts
XWayland global cursor state for all X11 apps in the session; Wayland backend avoids this.
**Go binaries: build with `go build -ldflags="-w -s"`**, not post-build strip.
**Release gate: `./release --dry-run`** runs `pre_built/build_scripts/test-prebuilt-binaries`,
which does a full temp install, probes every binary, checks editor runtime sentinels,
runs installed `nvim` headless against its installed runtime, and asserts portable
Python does not shadow system `python3`/`pip3` before any tag is created.
The Helix runtime lives at `pre_built/<platform>/runtime/helix.tar.bz2`; the installer
extracts it to `~/.config/helix/runtime`; `runtime/tutor` is the sentinel file.
The Vim runtime lives at `pre_built/<platform>/runtime/vim92.tar.bz2`; the installer
extracts it to `~/.local/share/vim/vim92`; `filetype.vim` is the sentinel file.
The Neovim runtime lives at `pre_built/<platform>/runtime/nvim.tar.bz2`; the installer
extracts it to `~/.local/share/nvim/runtime`; `filetype.lua` is the sentinel file.
Fresh Neovim config must start without network: if `lazy.nvim` is absent and `git`
cannot clone it, `nvim/init.lua` disables the plugin layer cleanly instead of erroring.
Use the Python 3.6-compatible `./strip_all_elf_binaries` after adding vendored
binaries, libraries, parser grammars, or tar archives. It walks the repo
outside `.git`, strips raw ELF files in place, strips ELF payloads inside
standalone `.bz2`, and rewrites tar archives as `.tar.bz2`; processed tarballs are skipped
later when size and modification time match the strip manifest.
`./update_tldr_cache` writes `tldr/tldr-pages.tar.bz2`; the installer also
accepts legacy `.tar.gz` and replaces any existing tealdeer cache unless
`--no-tldr-cache` is passed.

### Bundled Plugins

Tmux and Vim plugins are vendored in-tree (no internet required):
- `tmux/vendor/plugins/` — tpm, resurrect, continuum, better-mouse-mode
- `vim/vim/pack/vendor/start/` — nerdtree, SimpylFold, vim-liberty (auto-loaded)
- `vim/vim/pack/vendor/opt/` — optional plugins

Run `./update_tmux_plugins` to re-clone all tmux plugins from GitHub (pre-commit hook strips `.git` dirs on the next commit).

Neovim uses Lazy.nvim with versions locked in `nvim/lazy-lock.json`.

Tree-sitter offline support targets Neovim v0.12+ only. Vendored
`nvim-treesitter` and `treesitter-parser-registry` live under
`treesitter/vendor/`; prebuilt parsers, parser-info, queries, and registry cache
live under `treesitter/prebuilt/<platform>/`, where platform is
`$(uname -s lower)-$(uname -m)-<glibc|musl>`. Build or refresh the full parser
set with `./treesitter/build_parsers`; it stores parsers as `parser/*.so.bz2`.
The installer decompresses matching parser artifacts to installed `parser/*.so`
and copies metadata directories to `~/.local/share/nvim/tree-sitter-parsers/`.

## Key Conventions

### Variable Naming in Bash

- `LOADOUT_CFG_*` variables are user-facing preferences defined in `bash/global/config.sh` as `export LOADOUT_CFG_*=value`. They propagate to child processes and are visible in `env | grep LOADOUT_CFG_`. Override any variable in a user layer's `config.sh` with the same `export LOADOUT_CFG_*=value` form.
- Variables prefixed with `_` are treated as bashrc-local and cleaned up by `unset_bashrc_local_vars` (in `functions.sh`) before bashrc exits. `LOADOUT_CFG_*` are exported scalars and are intentionally retained so child processes and aliases/functions can reference them at runtime.

### Pre-commit Hook

`hooks/pre-commit` scans for nested `.git` directories (from bundled plugins), removes them, and re-stages. It also runs `./strip_all_elf_binaries` when staged binary/archive candidates change. Install this hook when developing this repo or working with bundled plugins. Normal end-user installs do not need repo git hooks. The embedded `.git` cleanup may broadly re-stage affected files; the binary stripping path restages only tracked updates, staged candidates, converted `.tar.bz2` archives, and strip manifests. Review staged files after it runs. For full binary smoke-testing use `./release --dry-run`, not the pre-commit hook.

### Adding a Bundled Plugin

1. Copy the plugin directory into `vim/vim/pack/vendor/start/` or `tmux/vendor/plugins/`
2. The pre-commit hook strips `.git` dirs automatically on next commit
3. Update `install` / `install.ps1` if new symlink/copy logic is needed

### Overriding Configuration

Create layer files that will be automatically picked up — no changes to `bash/global/` needed:
```bash
bash/user/config.sh       # LOADOUT_CFG_* variable overrides (export LOADOUT_CFG_FOO=value)
bash/user/bashrc          # alias/function overrides
bash/corp/global_hooks/3.sh  # inject code after PATH setup
```

### Tool Fallback Pattern

The bash config gracefully degrades when modern tools are absent:
- `eza` → `lsd` → `ls`
- `bat` → `cat`
- `fd` / `fdfind` → `find`

Handles distro naming differences: `batcat` (Debian) vs `bat` (RedHat), `fdfind` vs `fd`.

### Windows

Files are **copied**, not symlinked. Re-run `.\install.ps1` after repo changes. AutoHotKey (`AutoHotkey64.exe`) is extracted to `%USERPROFILE%\AutoHotkey_*\` rather than installed system-wide (avoids SentinelOne flagging); if no such directory exists, the installer auto-downloads the latest stable release from GitHub and removes `AutoHotkey32.exe`. The PowerShell profile includes `Invoke-PatchDOSStub` — a byte-patcher that changes an exe's DOS stub string to alter its hash, useful as a SentinelOne bypass for flagged binaries like AHK.
