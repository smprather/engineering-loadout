# Dotfiles

Modern, layered dotfiles for **Electrical Engineering work environments** — and anyone who lives
in a terminal and refuses to apologize for it.

Built from 30+ years of EE workflow experience. Hardened against the constraints that define
real engineering environments: **no internet, no root, no mercy**. Installs to `$HOME` on any
Linux box in under two minutes and gets out of your way.

---

## What's Inside

| Component | Description |
|-----------|-------------|
| **[Bash](https://www.gnu.org/software/bash/)** | Layered config (global→corp→site→project→user), 100+ power aliases, fzf/zoxide/eza/bat integration |
| **[Neovim](https://neovim.io)** | Kickstart.nvim base, Lazy.nvim, LSP, 326 offline Tree-sitter parsers, locked plugin versions |
| **[Vim](https://www.vim.org)** | Bundled plugins (NERDTree, SimpylFold, vim-liberty), vendored runtime, pre-built binary |
| **[Tmux](https://github.com/tmux/tmux)** | Bundled plugins (resurrect, continuum, better-mouse-mode), `Ctrl-\` prefix |
| **[Helix](https://helix-editor.com)** | Vendored runtime archive, ready to run offline |
| **[Starship](https://starship.rs)** | Cross-shell prompt, `starship/starship.linux.toml` and `starship/starship.windows.toml` |
| **[PowerShell](https://github.com/PowerShell/PowerShell)** | Aliases, Unix coreutils wrappers, PSReadLine, Starship, zoxide, PSFzf |
| **[WezTerm](https://wezfurlong.org/wezterm/)** | Terminal emulator config |
| **[AutoHotKey](https://www.autohotkey.com)** | AHK v2 flat script, optional features via `dotkeys_config.toml` |
| **[EditorConfig](https://editorconfig.org)** | Consistent formatting across all editors |
| **Pre-built binaries** | 52 modern CLI tools, zero internet required — see table below |
| **Nerd Fonts** | 6 font families, split-archive support for GitHub's 50 MB limit |

---

## Security

All binaries shipped in this repo pass a three-layer scan before each release.

### Steps taken

**1 — Decompress.** All `.bz2` blobs are extracted to a temp directory (raw ELF
files, not compressed archives). Scanning is performed on the decompressed
binaries.

**2 — ClamAV** (updated signature database):

```bash
freshclam                           # pull latest signatures
find pre_built/ -name '*.bz2' -exec sh -c 'bzcat "$1" | clamscan -' _ {} \;
# Or extract all first:
tmpdir=$(mktemp -d)
for f in pre_built/el8.x86_64.glibc2p28/bin/*.bz2; do
    bzcat "$f" > "$tmpdir/$(basename "${f%.bz2}")"
done
clamscan -r "$tmpdir"
rm -rf "$tmpdir"
```

Result: **0 detections** (ClamAV 28005 / 355455+ signatures).

**3 — [YARA-Forge](https://github.com/YARAHQ/yara-forge) full ruleset** (11,679 rules from
ReversingLabs, elastic, and community sources; YARA-QA filtered to ≥ quality 20, ≥ score 40):

```bash
# Install: https://github.com/YARAHQ/yara-forge (packages/full/yara-rules-full.yar)
tmpdir=$(mktemp -d)
for f in pre_built/el8.x86_64.glibc2p28/bin/*.bz2; do
    bzcat "$f" > "$tmpdir/$(basename "${f%.bz2}")"
done
yara -r /etc/yara/packages/full/yara-rules-full.yar "$tmpdir"
rm -rf "$tmpdir"
```

Result: **0 detections**.

**4 — Upstream hash verification** (`pre_built/build_scripts/verify-binaries`):
Downloads each tool's official GitHub release, applies the same bundling
transformation (strip → patchelf RPATH for dynamic ELFs), and compares SHA-256
against the decompressed bundled binary.

```bash
pre_built/build_scripts/verify-binaries        # verify all
pre_built/build_scripts/verify-binaries rg bat uv   # spot-check
pre_built/build_scripts/verify-binaries -v     # verbose (shows download URLs)
```

Three outcomes:
- **PASS**: byte-for-byte match with upstream release (after strip + patchelf)
- **PASS** (patchelf layout delta): identical NEEDED libs + near-identical size; only RPATH section layout differs — functionally the same binary
- **SKIP**: source build, dev version, or no matching upstream binary release
- **FAIL**: different shared library dependencies or significant size difference — warrants investigation

Many tools (bash, rg, bat, jq, eza, fd, tmux, vim, gnuplot, rsync, htop, kak, octave, etc.)
are intentionally built from source on EL8 targets rather than downloaded from GitHub releases,
so they are SKIP in the hash verification step but covered by the ClamAV + YARA scans above.

---

## Design Goals

**Offline-first.** Plugins, parsers, fonts, and binaries are all bundled. Nothing is fetched at
install time. Ship it to an air-gapped EDA workstation and it just works.

**No root.** Everything lands in `$HOME`. No package manager, no `sudo`, no IT ticket.

**Multi-platform.** RedHat 7/8/9, Suse, x86_64/ARM/PowerPC, and Windows. Platform directories
(`el8.x86_64.glibc2p28`) select binaries by OS family, architecture, and glibc version. A
compatible-ABI build is used when an exact match is absent.

**Layered.** Configuration flows from lowest to highest precedence:

```
Global → Corp → Site → Project → User
```

Each layer overrides the previous without touching upstream files. Corp secrets, site-specific
EDA tool paths, and personal tweaks all coexist without forking. Pull a dotfiles update and your
overrides still work.

**Opinionated but escapable.** Sensible defaults ship out of the box. Every preference is a
`DOTFILES_CFG_*` variable you can override in your user layer:

```bash
# bash/user/config.sh
export DOTFILES_CFG_PREFERRED_VI=vim        # use vim instead of nvim
export DOTFILES_CFG_ENABLE_STARSHIP=0       # use the built-in prompt
export DOTFILES_CFG_ATTACH_TO_TMUX=1        # auto-attach tmux on login
```

---

## Pre-Built Binaries — `el8.x86_64.glibc2p28`

All binaries are stripped, bzip2-compressed, and verified clean before release. `RPATH` is
pre-baked into each binary in the repo (`$ORIGIN/../lib64:$ORIGIN/../lib`) so the installer
is pure decompress + chmod — no runtime `patchelf`, no `LD_LIBRARY_PATH` hacks.

### Tools

| Binary | Version | Description |
|--------|---------|-------------|
| agent-deck | 1.9.12 | TUI dashboard for AI agent orchestration |
| [bash](https://www.gnu.org/software/bash/) | 5.3.9 | The GNU Bourne Again SHell |
| [bat](https://github.com/sharkdp/bat) | 0.26.1 | `cat` with syntax highlighting and Git integration |
| [broot](https://dystroy.org/broot/) | 1.56.2 | Interactive tree navigator and fuzzy finder |
| [btm](https://github.com/ClementTsang/bottom) | 0.12.3 | Cross-platform system monitor (CPU, memory, process tree) |
| [btop](https://github.com/aristocratos/btop) | 1.4.7 | Resource monitor — `top` for people who care about aesthetics |
| [bzip2](https://sourceware.org/bzip2/) | 1.0.8 | High-quality block-sorting file compressor |
| [choose](https://github.com/theryangeary/choose) | 1.3.7 | Human-friendly `cut` and `awk` replacement |
| [dasel](https://github.com/TomWright/dasel) | 3.8.1 | Select, update, and convert data across JSON/YAML/TOML/XML/CSV |
| [delta](https://github.com/dandavison/delta) | 0.19.2 | Git diff pager with syntax highlighting and line numbers |
| [duf](https://github.com/muesli/duf) | 0.9.1 | `df` replacement with colored disk usage table |
| [dust](https://github.com/bootandy/dust) | 1.2.4 | Intuitive `du` — shows disk usage by size, at a glance |
| [eza](https://github.com/eza-community/eza) | 0.23.4 | Modern `ls` with color, icons, Git status, and tree view |
| [fd](https://github.com/sharkdp/fd) | 10.4.2 | Fast, ergonomic `find` replacement |
| [fzf](https://github.com/junegunn/fzf) | 0.62.0 | Blazing-fast fuzzy finder for files, history, anything |
| [gnuplot](http://www.gnuplot.info) | 6.0.2 | Portable command-line graphing utility |
| [gping](https://github.com/orf/gping) | 1.20.1 | `ping` with a real-time ASCII graph |
| [htop](https://htop.dev) | 3.2.1 | Interactive process viewer — the original `top` upgrade |
| [hx](https://helix-editor.com) | 25.07.1 | Helix modal editor — Kakoune-inspired, batteries included |
| [hyperfine](https://github.com/sharkdp/hyperfine) | 1.20.0 | Command-line benchmarking tool with statistical output |
| [jq](https://jqlang.github.io/jq/) | 1.8.1 | Lightweight and flexible command-line JSON processor |
| [just](https://github.com/casey/just) | 1.50.0 | Command runner — sane `make` replacement for project tasks |
| [kak](https://kakoune.org) | 2026.04.12 | Kakoune — selection-first modal editor |
| [lazygit](https://github.com/jesseduffield/lazygit) | 0.61.1 | TUI git client for staging, committing, and rebasing |
| [micro](https://micro-editor.github.io) | 2.0.15 | Modern, intuitive terminal text editor — Ctrl+S just works |
| [miller](https://github.com/johnkerl/miller) | 6.18.1 | CSV/TSV/JSON/NDJSON/XML data processor (`mlr`) |
| [nvim](https://neovim.io) | 0.12.2 | Hyperextensible Vim-based text editor |
| [patchelf](https://github.com/NixOS/patchelf) | 0.12 | Modify ELF binary RPATHs and interpreters at install time |
| [pigz](https://zlib.net/pigz/) | 2.8 | Parallel gzip — multi-core `gzip`/`gunzip` replacement |
| [procs](https://github.com/dalance/procs) | 0.14.11 | `ps` replacement with colors and process tree |
| [pv](https://www.ivarch.com/programs/pv.shtml) | 1.6.6 | Monitor progress of data through a pipe |
| [resize](https://invisible-island.net/xterm/) | 331 | XTerm terminal resize utility — fixes `$COLUMNS`/`$LINES` |
| [rg](https://github.com/BurntSushi/ripgrep) | 15.1.0 | ripgrep — recursive search that respects `.gitignore` |
| [rsync](https://rsync.samba.org) | 3.4.1 | Fast, incremental file transfer |
| [ruff](https://github.com/astral-sh/ruff) | 0.15.12 | Extremely fast Python linter and formatter, written in Rust |
| [sd](https://github.com/chmln/sd) | 1.0.0 | Intuitive `sed` replacement — `sd 'old' 'new'` just works |
| [shfmt](https://github.com/mvdan/sh) | 3.13.1 | Shell script formatter (bash/sh/mksh/bats) |
| [starship](https://starship.rs) | 1.25.1 | Cross-shell prompt — fast, informative, configurable |
| [stylua](https://github.com/JohnnyMorganz/StyLua) | 2.4.1 | Opinionated Lua code formatter |
| [tealdeer / tldr](https://github.com/dbrgn/tealdeer) | 1.8.1 | Fast `tldr` client with offline page cache |
| [tkdiff](https://sourceforge.net/projects/tkdiff/) | 6.0 | Tcl/Tk visual diff and merge tool (requires `wish`) |
| [tmux](https://github.com/tmux/tmux) | 3.6a | Terminal multiplexer |
| [tree-sitter](https://tree-sitter.github.io/tree-sitter/) | 0.26.8 | Parser generator tool and incremental parsing library |
| [ty](https://github.com/astral-sh/ty) | 0.0.35 | Extremely fast Python type checker by Astral |
| [uv](https://github.com/astral-sh/uv) | 0.11.13 | Extremely fast Python package installer and resolver |
| [vim](https://www.vim.org) | 9.2 | Vim 9.2 pre-built binary + shell wrapper |
| [xsel](https://github.com/kfish/xsel) | 1.2.0 | X11 clipboard command-line access tool |
| [xterm](https://invisible-island.net/xterm/) | 331 | X Window System terminal emulator |
| [yank](https://github.com/mptre/yank) | 1.3.0 | Select terminal output and copy to clipboard |
| [yara](https://virustotal.github.io/yara/) | 4.5.5 | Malware pattern matching and classification |
| [yq](https://github.com/mikefarah/yq) | 4.53.2 | `jq` for YAML, JSON, XML, CSV, TOML, and properties files |
| [zoxide](https://github.com/ajeetdsouza/zoxide) | 0.9.9 | Smarter `cd` — learns your most-used directories |

### Optional Tools

Not installed by default. Add with `./install --add-tools <name>` or view all with `./install --list-tools`.

| Binary | Version | Description |
|--------|---------|-------------|
| [gvim](https://www.vim.org) | 9.2 | GTK3 GUI vim — `gvim.bin` (stripped binary) + `gvim` wrapper setting VIM/VIMRUNTIME |
| [nedit-ng](https://github.com/eteran/nedit-ng) | 2025.1 | Qt5 rewrite of NEdit — single self-contained binary, no runtime files |
| [octave](https://www.gnu.org/software/octave/) | 11.1.0 | GNU Octave scientific computing (~163 MB uncompressed; see notes below) |
| [gui\_libs](https://github.com/smprather/dotfiles) | — | ~80 bundled Qt5/GTK3/xcb/Wayland shared libs for headless farm nodes |
| [visidata](https://www.visidata.org) | 3.3 | TUI spreadsheet for exploring CSV/TSV/JSON/NDJSON data |
| [meld](https://meldmerge.org) | 3.20.4 | GTK3 visual diff and merge tool (shanghai bundle — system py3.6 + PyGObject) |

**gui_libs** targets headless EE farm/LSF nodes that have no GUI libraries but run GUI tools with `DISPLAY` forwarded back to a workstation. It includes Qt5 5.15.3, GTK3 3.22, ICU 60, cairo, pango, xcb extensions, xkbcommon, and Wayland client libs. All are patchelf'd with `$ORIGIN` RPATH so they find each other in `~/.local/lib64/`.

```bash
# Install GUI editors + all their shared library deps in one shot
./install --no-backup --no-fonts --no-tldr-cache --add-tools gui_libs,gvim,nedit-ng
```

**WSLg note:** Qt5's XCB backend corrupts XWayland's global cursor state (all X11 apps in the session lose their cursor). Fix: add `export QT_QPA_PLATFORM=wayland` to `~/.config/bash/user/bashrc`. The Wayland backend (included in gui_libs) routes cursor management through the compositor directly, bypassing XWayland.

### Python

| Package | Version | Description |
|---------|---------|-------------|
| [Python](https://www.python.org) | 3.14.4 | LLVM BOLT-optimized portable Python build for EL8. Installs to `~/.local` via bundled `install.sh`. Generic `python3`/`pip3` entries are removed post-install so EDA tools find the system Python at `/usr/bin/python3`. Use `python3.14` and `pip3.14` for this build. |

### Vendored Shared Libraries

Runtime dependencies vendored alongside binaries — no system library assumptions.

**Always installed** (core deps for default tools):

| Library | Provides |
|---------|---------|
| `libbz2.so.1` | bzip2 compression (bat, tmux, and others) |
| `libevent_core-2.1.so.6` | Event loop (tmux) |
| `libexpat.so.1` | XML parsing |
| `libfontconfig.so.1` | Font discovery (xterm) |
| `libfreetype.so.6` | Font rendering (xterm) |
| `libICE.so.6` | Inter-Client Exchange (X11) |
| `libjq.so` | jq shared library |
| `libncurses.so.6` | Terminal UI (gnuplot, htop) |
| `libonig.so.5` | Oniguruma regex (jq) |
| `libpng16.so.16` | PNG image support (xterm) |
| `libreadline.so.7` | GNU readline (gnuplot, bash) |
| `libSM.so.6` | Session Management (X11) |
| `libtinfo.so.6` | Terminal info (ncurses) |
| `libuuid.so.1` | UUID generation |
| `libX11.so.6` | Core X11 client library |
| `libXau.so.6` | X11 authorization |
| `libXaw.so.7` | X11 Athena Widgets (xterm UI) |
| `libxcb.so.1` | X protocol C-language Binding |
| `libXext.so.6` | X11 extensions |
| `libXft.so.2` | X FreeType font rendering |
| `libXinerama.so.1` | Multi-monitor extension |
| `libXmu.so.6` | X11 miscellaneous utilities |
| `libXpm.so.4` | X PixMap (xterm icon) |
| `libXrender.so.1` | X Render extension |
| `libXt.so.6` | X Toolkit Intrinsics |
| `libxxhash.so.0` | Fast non-cryptographic hash |
| `libz.so.1` | zlib compression |

**gui_libs optional package** (~80 libs, opt in with `--add-tools gui_libs`):

Qt5 5.15.3: `libQt5Core`, `libQt5Gui`, `libQt5Widgets`, `libQt5DBus`, `libQt5Network`, `libQt5PrintSupport`, `libQt5XcbQpa`, `libQt5Xml`, `libQt5WaylandClient` + platform plugins `libqxcb.so`, `libqwayland-generic.so` (flat in `~/.local/lib64/`). GTK3 3.22: `libgtk-3`, `libgdk-3`, `libgdk_pixbuf-2.0`, `libatk-1.0`, `libatk-bridge-2.0`, `libatspi`. ICU 60: `libicudata`, `libicui18n`, `libicuuc` (~27 MB). Cairo/Pango: `libcairo`, `libpango-1.0`, `libharfbuzz`, `libfribidi`, `libgraphite2`. xcb extensions: `libxcb-icccm`, `libxcb-image`, `libxcb-keysyms`, `libxcb-randr`, `libxcb-render`, `libxcb-render-util`, `libxcb-shape`, `libxcb-shm`, `libxcb-sync`, `libxcb-util`, `libxcb-xfixes`, `libxcb-xinerama`, `libxcb-xinput`, `libxcb-xkb`. Wayland: `libwayland-client`, `libwayland-cursor`, `libwayland-egl`. xkbcommon: `libxkbcommon`, `libxkbcommon-x11`. glib2 family: `libglib-2.0`, `libgobject-2.0`, `libgio-2.0`, `libgmodule-2.0`, `libgthread-2.0`. Fonts: `libfontconfig`, `libfreetype`, `libpixman-1`, `libpng16`. All patchelf'd with `$ORIGIN` RPATH so they find each other in `~/.local/lib64/`.

---

## Neovim — 326 Offline Tree-sitter Parsers

The full `nvim-treesitter` parser registry is prebuilt and bundled for
`linux-x86_64-glibc`. All 326 language parsers install offline to
`~/.local/share/nvim/tree-sitter-parsers/` with queries, parser-info, and
build metadata. Build your own or refresh with `./treesitter/build_parsers`.

---

## Nerd Fonts

Six font families bundled and installed to `~/.local/share/fonts`:

| Font | Notes |
|------|-------|
| [Envy Code R](https://damieng.com/blog/2008/05/26/envy-code-r-preview-7-coding-font) | Clean, distinctive coding font |
| [Fira Code](https://github.com/tonsky/FiraCode) | Ligature-rich monospace |
| [Hack](https://sourcefoundry.org/hack/) | Designed for source code |
| [Inconsolata](https://levien.com/type/myfonts/inconsolata.html) | Humanist monospace |
| [Iosevka Term](https://typeof.net/Iosevka/) | Ultra-narrow, highly legible |
| [JetBrains Mono](https://www.jetbrains.com/lp/mono/) | Designed for long coding sessions |
| [Source Code Pro](https://github.com/adobe-fonts/source-code-pro) | Adobe's open-source workhorse |

Large archives are split into `*.zip.part-*` chunks (≤ 45 MiB) to stay below
GitHub's 50 MB file warning. The installer rejoins them in `/tmp` before
extracting. Use `./install --no-fonts` to skip.

---

## Installation

### Linux

```bash
git clone https://github.com/smprather/dotfiles.git
cd dotfiles
./install
```

The installer is a single Python 3.6-compatible executable. It can be invoked
from any working directory — it resolves the repo from the script path.

**Options:**

```bash
./install --dev                              # dev mode: repo symlinks instead of copies
./install --dest-dir /tmp/test-home          # stage install into alternate root
./install --no-backup                        # skip backup of existing files
./install --no-fonts                         # skip font extraction
./install --no-tldr-cache                    # skip bundled tldr page cache
./install --post-install-hook ~/corp/install.sh  # run corp/site add-on hooks
./install --list-tools                       # show all tools with default install status
./install --add-tools octave                 # add optional tool(s) to defaults
./install --skip-tools gnuplot,kak           # remove tool(s) from defaults
./install --tools vim,nvim,rg,tmux           # install exactly this set
```

**What gets installed:**

| Destination | Source |
|-------------|--------|
| `~/.bashrc`, `~/.bash_profile`, `~/.bash_login`, `~/.profile` | → `bash/bashrc` |
| `~/.config/bash/` | Layered bash config |
| `~/.vimrc` | `vim/vimrc` |
| `~/.vim/` | `vim/vim/` |
| `~/.tmux.conf` | `tmux/tmux.conf` |
| `~/.tmux/` | `tmux/tmux/` |
| `~/.editorconfig` | `editorconfig/editorconfig` |
| `~/.config/nvim/` | `nvim/` |
| `~/.config/starship/starship.toml` | `starship/starship.linux.toml` + `starship/config-schema.json` |
| `~/.config/helix/runtime/` | `pre_built/<platform>/runtime/helix.tar.bz2` |
| `~/.local/share/vim/vim92/` | `pre_built/<platform>/runtime/vim92.tar.bz2` |
| `~/.local/share/nvim/runtime/` | `pre_built/<platform>/runtime/nvim.tar.bz2` |
| `~/.local/bin/` | `pre_built/<platform>/bin/*.bz2` (decompressed) |
| `~/.local/lib64/` | `pre_built/<platform>/lib64/*.bz2` (decompressed) |
| `~/.local/bin/python3.14` | `pre_built/<platform>/portable-python-*.tar.bz2` |
| `~/.local/share/fonts/` | `fonts/*.zip` (Nerd Font archives) |
| `~/.local/share/nvim/tree-sitter-parsers/` | 326 prebuilt Tree-sitter parsers |
| `~/.cache/tealdeer/tldr-pages/` | `tldr/tldr-pages.tar.bz2` |

**After install**, reload your shell:

```bash
exec bash
```

#### Smoke testing

Simulate a completely fresh user environment:

```bash
./tests/install_linux_tmp_home
```

#### Corporate / site add-ons

```bash
./install --post-install-hook ~/corp-dotfiles/install.sh \
           --post-install-hook ~/site-dotfiles/install.sh
```

Hooks receive these environment variables: `DOTFILES_REPO`, `DOTFILES_HOME`,
`DOTFILES_MODE` (`copy` or `dev`), `DOTFILES_BACKUP_DIR`, `DOTFILES_DEST_DIR`,
`DOTFILES_NO_BACKUP`, `DOTFILES_NO_FONTS`, `DOTFILES_NO_TLDR_CACHE`.

#### Restore a backup

```bash
./install --restore-backup dotfiles_backups/backup.1
```

Numbered backups are created in `dotfiles_backups/backup.N/` before each install.
Font files are excluded from backups (large and reproducible).

---

### Windows

**PowerShell 7+ (recommended):**

```powershell
.\install.ps1
```

**Starting from Windows PowerShell 5.1:**

```powershell
.\install-powershell-latest.ps1   # installs pwsh via winget
# then reopen as pwsh:
.\install.ps1
```

No elevation required. Files are copied, not symlinked — re-run `.\install.ps1`
after repo updates.

**Windows destinations:**

| Destination | Source |
|-------------|--------|
| `%LOCALAPPDATA%\nvim\` | `nvim/` |
| `%USERPROFILE%\.config\wezterm\wezterm.lua` | `wezterm/wezterm.lua` |
| `%USERPROFILE%\.config\starship\starship.toml` | `starship/starship.windows.toml` |
| `%USERPROFILE%\.editorconfig` | `editorconfig/editorconfig` |
| `%USERPROFILE%\autohotkey\hotkeys.ahk` | `autohotkey/hotkeys.ahk` (feature-patched) |
| `%USERPROFILE%\dotkeys_config.toml` | Created if missing — choose AHK features |
| PowerShell profile (5.1 + 7+) | `powershell/Microsoft.PowerShell_profile.ps1` |

**AutoHotKey feature flags** (edit `%USERPROFILE%\dotkeys_config.toml`):

| Feature | Description |
|---------|-------------|
| `corp-logins` | Corp credential entry hotkeys |
| `mouse-wiggle` | Idle mouse nudge to prevent lock screens |
| `cisco-secure-client-vpn` | Cisco Secure Client auto-reconnect |
| `password-manager` | Password manager quick-type hotkey |
| `tmux-hotkeys` | `RAlt`/`RWin` zoom toggle, `Ctrl+;` last-pane toggle |
| `f1f2f3-as-mouse-buttons` | F1/F2/F3 mouse remaps for mspaint/etxc/wezterm-gui |
| `thinlinc-reconnect` | Auto-dismiss ThinLinc errors and reconnect |

---

## Bash Configuration

### Layer System

```
bash/global/    ← upstream, managed here — do not modify locally
bash/corp/      ← corporation-level overrides  (user-created)
bash/site/      ← site-level overrides         (user-created)
bash/project/   ← project-level overrides      (user-created)
bash/user/      ← personal overrides            (user-created)
```

Each layer sources `config.sh` (preferences) then `bashrc` (aliases/prompt).
Override any `DOTFILES_CFG_*` variable in your layer's `config.sh`:

```bash
# bash/user/config.sh
export DOTFILES_CFG_PREFERRED_VI=nvim
export DOTFILES_CFG_ENABLE_STARSHIP=1
export DOTFILES_CFG_ENABLE_FZF=1
export DOTFILES_CFG_PREFERRED_BASH=/home/user/.local/bin/bash
```

### Hook Injection Points

Insert code at precise points in the shell startup sequence:

| Hook | Fires after |
|------|-------------|
| `global_hooks/1.sh` | Functions loaded |
| `global_hooks/2.sh` | glibc detection |
| `global_hooks/3.sh` | PATH setup |
| `global_hooks/4.sh` | Prompt configured |
| `global_hooks/5.sh` | Before completions |
| `global_hooks/6.sh` | Completions loaded |

Example — inject a site-specific EDA tool path at hook 3:

```bash
# bash/site/global_hooks/3.sh
path_prepend_if_dir /tools/cadence/bin
path_prepend_if_dir /tools/synopsys/bin
```

### Notable Aliases

```bash
b / bb / bbb …        # cd .. up 1–10 levels
cdd / cddd …          # cd to Nth most-recently-modified directory
p / cdp               # bookmark cwd / return to it
g                     # ripgrep (falls back to grep -r -i)
f                     # fd (falls back to find .)
vi / vim              # DOTFILES_CFG_PREFERRED_VI
v                     # nvim -n -R - (read stdin, read-only)
fvi                   # fzf file picker → open in editor
t                     # exec bash (reload shell)
w                     # type -a (where is this defined?)
we                    # watchexec --clear --poll 500
ga / gs / gc / gp     # git add / status / commit / push
gsp                   # git stash, pull, pop
lh / la / lah         # ls --human / --all / both
rs                    # rsync with progress, excludes .snapshot/
du / dum              # disk usage sorted by size (GB / MB)
extract_rpm           # rpm2cpio | cpio -idmv
```

---

## Tmux

Prefix: **`Ctrl-\`** (not `Ctrl-b` — your fingers will thank you)

| Binding | Action |
|---------|--------|
| `Shift+←/→/↑/↓` | Navigate panes |
| `Prefix+←/→/↑/↓` | Resize pane (repeatable) |
| `Ctrl+←/→` | Previous/next window |
| `Ctrl+Shift+←/→` | Reorder windows |
| `Prefix+1–5` | Layout presets |
| `Prefix+o` | 4-pane layout |
| `Prefix+v` | Capture pane buffer → nvim |
| `Prefix+r` | Reload config |
| `Prefix+Ctrl-s` | Save session (resurrect) |
| `Prefix+Ctrl-r` | Restore session (resurrect) |

tmux-continuum auto-saves every 60 minutes.

---

## Maintenance

### Adding a new pre-built binary

Order matters: always **strip → patchelf → bzip2**. Stripping after patchelf corrupts `.dynstr`.

```bash
# 1. Strip, set RPATH, compress
cp /path/to/binary /tmp/mybinary_tmp
/usr/bin/strip /tmp/mybinary_tmp
/usr/bin/patchelf --set-rpath '$ORIGIN/../lib64:$ORIGIN/../lib' /tmp/mybinary_tmp
bzip2 -k /tmp/mybinary_tmp
cp /tmp/mybinary_tmp.bz2 pre_built/el8.x86_64.glibc2p28/bin/mybinary.bz2

# 2. Update strip manifest
./strip_all_elf_binaries

# 3. Smoke-test and commit
pre_built/build_scripts/test-prebuilt-binaries --keep  # or just ./release --dry-run
git add pre_built/ .strip-manifest
git commit
```

See `pre_built/ADDING_BINARIES.md` for the full workflow including dependency auditing,
go binary flags, and `farm-versions` registration.

### Importing a new portable Python build

```bash
pre_built/build_scripts/import-portable-python /path/to/portable-python-X.Y.Z-tag/
./strip_all_elf_binaries   # skips BOLT-optimized Python archive automatically
git add pre_built/ .strip-manifest
git commit
```

### Updating tldr pages

```bash
./update_tldr_cache
git add tldr/
git commit
```

### Updating tmux plugins

```bash
./update_tmux_plugins
git add tmux/vendor/
git commit
```

### Rebuilding Tree-sitter parsers

```bash
./treesitter/build_parsers
git add treesitter/prebuilt/
git commit
```

---

## Development Mode

```bash
./install --dev
```

For **nvim**: `~/.config/nvim/` is a real directory with file-level symlinks —
`init.lua`, `lazy-lock.json`, `lsp/`, `after/` point into the repo; `lua/global/`
symlinks to `repo/nvim/lua/global/`; user layer dirs (`lua/corp/`, `lua/site/`,
`lua/project/`, `lua/user/`) are preserved as real directories and never touched.

For **vim/tmux/editorconfig**: whole-directory symlinks. Starship uses file-level symlinks for the selected OS config and, on Linux, `config-schema.json`.

For **bash**: symlinks individual managed files (`global/`, `functions.sh`, `bashrc`)
while leaving user layer dirs as real directories.

Installs repo git hooks:

- **pre-commit** — strips ELF payloads from newly staged binaries and archives,
  normalizes tarballs to `.tar.bz2`, updates `.strip-manifest`. Removes any
  embedded `.git` dirs from vendored plugins. Run `./release --dry-run` before
  creating a release to smoke-test all binaries via a temp install.

---

## Related

**[EE Linux Tools](https://github.com/smprather/ee-linux-tools)** — companion repo
providing pre-built modern CLI binaries (RipGrep, Tmux, EZA, and more) for
offline/locked-down Linux environments. The tools in this dotfiles repo are
also available there in standalone form.
