# Engineering Loadout

A self-contained, offline-first package manager + dotfiles bundle for **Engineering work environments**.
- Old Linux distro versions
- Limited, or no, internet access
- No sudo/root
- Built from 30+ years of Electrical Engineering workflow experience
- All built on AlmaLinux8.10 (Redhat 8.10 clone), GLIBC2.28
  - Compatible with RHEL9.X and beyond
  - Redhat7 is EoL. If you see any Redhat7 zombies 🧟 walking around, please stab them in the head 🔪.

If you can get the singular tar file into your work environment (an sftp pipeline is usually available),
then you can start working with modern Linux tools and "sane" configurations.
"Sane" as defined by me of course :smiley:.

The Loadout is a typed package registry (`pre_built/packages.json`, `schema_version: 2`) that
names every installable thing — binary, library bundle, runtime archive,
config bundle, font, data cache. Packages declare dependencies; groups
bundle them; a built-in resolver walks the graph; the CLI gives you
`list` / `describe` / `resolve` / `doctor` subcommands and `--add` /
`--skip` / `--only` selection flags.
In other words, it does basic package-management stuff.

---

## What's Inside

| Component | Description |
|-----------|-------------|
| **Package manager** | `./engineering-loadout` — typed registry, group expansion, depends/recommends resolver, kind-dispatched install (`bin`/`lib-bundle`/`runtime`/`env`/`font`/`data`/...) |
| **[Bash](https://www.gnu.org/software/bash/)** | Layered config (global→corp→site→project→user), 100+ power aliases, fzf/zoxide/eza/bat integration |
| **[Neovim](https://neovim.io)** | Kickstart.nvim base, Lazy.nvim, LSP, 326 offline Tree-sitter parsers, locked plugin versions |
| **[Vim](https://www.vim.org)** | Bundled plugins (NERDTree, SimpylFold, vim-liberty), vendored runtime, pre-built binary |
| **[Tmux](https://github.com/tmux/tmux)** | Bundled plugins (resurrect, continuum, better-mouse-mode), `Ctrl-\` prefix |
| **[Helix](https://helix-editor.com)** | Vendored runtime archive, ready to run offline |
| **[Starship](https://starship.rs)** | Cross-shell prompt, `starship/starship.linux.toml` and `starship/starship.windows.toml` |
| **[PowerShell](https://github.com/PowerShell/PowerShell)** | Aliases, Unix coreutils wrappers, PSReadLine, Starship, zoxide, PSFzf |
| **[WezTerm](https://wezfurlong.org/wezterm/)** | Terminal emulator config |
| **[AutoHotKey](https://www.autohotkey.com)** | AHK v2 flat script, optional features via `loadout_keys.toml` |
| **[EditorConfig](https://editorconfig.org)** | Consistent formatting across all editors |
| **Pre-built binaries** | 52 default + 9 optional modern CLI tools, zero internet required — see table below |
| **Nerd Fonts** | 7 font families, split-archive support for GitHub's 50 MB limit |

---

## Security

All binaries shipped in this repo pass a three-layer scan (ClamAV + YARA-Forge + upstream SHA-256) before each release. [Details](docs/SECURITY.md)

---

## Package Manager

`./engineering-loadout` reads `pre_built/packages.json` (`schema_version: 2`)
and resolves a selection into a flat install set.

**Package kinds** (`kind` field): `bin`, `lib-bundle`, `runtime`, `typelib`,
`python-base`, `python-tool`, `env`, `font`, `data`, `group`. Every package
also has `default: true|false`, `platforms: [...]`, optional `tags`, and per-kind
artifact fields (`bins` / `libs` / `archive` / `source` / `wheels` / etc.).

**Groups** are entries whose names start with `@` and carry a `members` list.
They expand recursively with cycle detection. The synthetic `@default` group
expands at runtime to every `default: true` package.

**Dependencies** are declared per package:

- `depends` — hard. Skipping one while a depender is selected raises `ResolverError`
  unless `--no-deps` or `--force`.
- `recommends` — soft. Auto-pulled when available; silently dropped if skipped or
  unknown.

**Resolution order** (`resolve_tool_selection`): parse `--skip` → build initial set
from `@default` ∪ `--add` (or `--only`) → subtract `--skip` → walk hard `depends`
→ walk soft `recommends` → filter by current platform.

```bash
./engineering-loadout list                     # every package
./engineering-loadout list --groups            # every @-group + member count
./engineering-loadout list --tag editor        # filter by tag
./engineering-loadout describe gvim            # full metadata + reverse-deps + group memberships
./engineering-loadout describe @core-cli       # group members
./engineering-loadout resolve gvim             # dry-run resolver; prints set grouped by kind
./engineering-loadout doctor                   # platform + registry integrity check
./engineering-loadout --dry-run --add octave   # resolve + print; no writes
./engineering-loadout --add @gui-suite         # add a group
./engineering-loadout --skip @fonts-all        # drop all font packages
./engineering-loadout --profile engineering-loadout   # alias for --only @engineering-loadout
```

See the full CLI surface under [Installation → Subcommands & options](#installation) below.

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
EDA tool paths, and personal tweaks all coexist without forking. Pull a loadout update and your
overrides still work.

**Opinionated but escapable.** Sensible defaults ship out of the box. Every preference is a
`LOADOUT_CFG_*` variable you can override in your user layer:

```bash
# bash/user/config.sh
export LOADOUT_CFG_PREFERRED_VI=vim        # use vim instead of nvim
export LOADOUT_CFG_ENABLE_STARSHIP=0       # use the built-in prompt
export LOADOUT_CFG_ATTACH_TO_TMUX=1        # auto-attach tmux on login
```

---

## Pre-Built Binaries — `el8.x86_64.glibc2p28`

All binaries are stripped, bzip2-compressed, and verified clean before release. `RPATH` is
pre-baked into each binary in the repo (`$ORIGIN/../lib64:$ORIGIN/../lib`) so the installer
is pure decompress + chmod — no runtime `patchelf`, no `LD_LIBRARY_PATH` hacks.

### Tools

| Binary | Version | Description |
|--------|---------|-------------|
| [agent-deck](https://github.com/asheshgoplani/agent-deck) | 1.9.12 | TUI dashboard for AI agent orchestration |
| [bash](https://www.gnu.org/software/bash/) | 5.3.9 | The GNU Bourne Again SHell |
| [bat](https://github.com/sharkdp/bat) | 0.26.1 | `cat` with syntax highlighting and Git integration |
| [biome](https://biomejs.dev) | 2.4.15 | Fast Rust JSON/JS/TS/CSS formatter, linter, and LSP (static-pie musl build, no glibc dep) |
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

Not installed by default. Add with `./engineering-loadout --add <name>` or view all with `./engineering-loadout list`.

| Binary | Version | Description |
|--------|---------|-------------|
| [gvim](https://www.vim.org) | 9.2 | GTK3 GUI vim — `gvim.bin` (stripped binary) + `gvim` wrapper setting VIM/VIMRUNTIME |
| [nedit-ng](https://github.com/eteran/nedit-ng) | 2025.1 | Qt5 rewrite of NEdit — single self-contained binary, no runtime files |
| [octave](https://www.gnu.org/software/octave/) | 11.1.0 | GNU Octave scientific computing (~163 MB uncompressed; see notes below) |
| [gui\_libs](https://github.com/smprather/engineering-loadout) | — | ~80 bundled Qt5/GTK3/xcb/Wayland shared libs for headless farm nodes |
| [visidata](https://www.visidata.org) | 3.3 | TUI spreadsheet for exploring CSV/TSV/JSON/NDJSON data |
| [meld](https://meldmerge.org) | 3.20.4 | GTK3 visual diff and merge tool (shanghai bundle — system py3.6 + PyGObject) |
| [zsh](https://www.zsh.org) | — | Z shell — advanced tab completion, powerful scripting |
| [fish](https://fishshell.com) | 4.7.1 | Fish shell — autosuggestions, syntax highlighting, no config needed |
| [jupyterlab](https://jupyter.org) | 4.5.7 | Web-based interactive notebooks (Python via `uv tool`, opens in browser) |
| [urxvt](http://software.schmorp.de/pkg/rxvt-unicode.html) | 9.31 | rxvt-unicode — X11 terminal with Unicode, Xft, and daemon mode (`urxvt`/`urxvtc`/`urxvtd`; perl extensions disabled) |
| [st](https://st.suckless.org) | 0.9.3 | suckless st — minimal X11 terminal with [undercurl patch](https://st.suckless.org/patches/undercurl/) (`UNDERCURL_CURLY` style for LSP/spell-check diagnostics) |
| [time-plot](https://github.com/smprather/time-plot) | 0.1.0 | Plot arbitrary data vs. zero-based time with pluggable file-parser plugins (uPlot HTML output) |

**gui_libs** targets headless EE farm/LSF nodes that have no GUI libraries but run GUI tools with `DISPLAY` forwarded back to a workstation. It includes Qt5 5.15.3, GTK3 3.22, ICU 60, cairo, pango, xcb extensions, xkbcommon, and Wayland client libs. All are patchelf'd with `$ORIGIN` RPATH so they find each other in `~/.local/lib64/`.

```bash
# Install GUI editors — gui_libs + vim92-runtime are auto-pulled as dependencies.
./engineering-loadout --no-backup --skip @fonts-all,tldr-data --add gvim,nedit-ng
# Or use the bundled group:
./engineering-loadout --no-backup --add @gui-suite
```

**WSLg note:** Qt5's XCB backend corrupts XWayland's global cursor state (all X11 apps in the session lose their cursor). Fix: add `export QT_QPA_PLATFORM=wayland` to `~/.config/bash/user/bashrc`. The Wayland backend (included in gui_libs) routes cursor management through the compositor directly, bypassing XWayland.

### Python

| Package | Version | Description |
|---------|---------|-------------|
| [Python](https://www.python.org) | 3.14.4 | LLVM BOLT-optimized portable Python build for EL8. Installs to `~/.local` via bundled `install.sh`. Generic `python3`/`pip3` links are left in place, so `python3` on PATH resolves to 3.14. Tools that hard-require system Python 3.6 must invoke `/usr/bin/python3` explicitly. Use `python3.14` and `pip3.14` to pin this build. |

### Vendored Shared Libraries

Runtime dependencies vendored alongside binaries — no system library assumptions. ~28 always-installed core libs + ~80 in the opt-in `gui_libs` bundle for Qt5/GTK3/xcb/Wayland on headless farm nodes. [Details](docs/SHARED_LIBS.md)

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
extracting. Use `./engineering-loadout --skip @fonts-all` to skip every font, or
`--skip font-firacode` to skip a single family.

---

## Installation

### Linux

```bash
git clone https://github.com/smprather/engineering-loadout.git
cd engineering-loadout
./engineering-loadout
```

Single Python 3.6-compatible executable. Re-run after each `git pull`
(idempotent; unchanged files skip the install step). Reload your shell with
`exec bash` afterward.

### Windows

```powershell
.\engineering-loadout.ps1                  # PowerShell 7+
.\engineering-loadout-pwsh-bootstrap.ps1   # if starting from PowerShell 5.1
```

No elevation required.

Full subcommand reference, install destinations, post-install hooks, backup
restore, and Windows AHK feature flags: [Details](docs/INSTALLATION.md)

---

## Bash Configuration

Five-layer override chain (`global → corp → site → project → user`), `LOADOUT_CFG_*` knobs, 7 startup hook-injection points, and a curated alias set (`b/bb/…` directory hopping, `g/f` for `rg`/`fd` with fallbacks, `gs/gc/gp` git shortcuts, etc.). [Details](docs/BASH.md)

---

## Tmux

Prefix `Ctrl-\`. Shift-arrows for pane nav, Ctrl-arrows for windows, `Prefix+1–5` layouts, `Prefix+v` capture-to-nvim, tmux-resurrect + continuum bundled. [Details](docs/TMUX.md)

---

## Maintenance

Recipes for adding/updating pre-built binaries (strip → patchelf → bzip2), importing portable Python, refreshing tldr/tmux-plugins/Tree-sitter parsers, and installing the repo git hooks: [Details](docs/MAINTENANCE.md). Per-tool update playbook (check-versions → per-kind build path → smoke + commit + release) covered there too.

### Onboarding a new developer

After cloning the repo and running `./engineering-loadout` to install the runtime, run `./dev-onboard` once to add the system-level packages, dev headers, and per-user toolchains required to rebuild any bundled tool from source. Six phases: dnf repos → toolchains (gcc-toolset-14, llvm, go) → dev headers (X11/Qt5/GTK3/ncurses/Octave) → release/CI (gh, docker) → per-user (rustup, nvm, uv tool meson) → sanity checks. Idempotent; `--check` for dry-run, `--yes` for non-interactive.

---

## Related

**[EE Linux Tools](https://github.com/smprather/ee-linux-tools)** — companion repo
providing pre-built modern CLI binaries (RipGrep, Tmux, EZA, and more) for
offline/locked-down Linux environments. The tools in engineering-loadout are
also available there in standalone form.
