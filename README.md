# Engineering Loadout

A self-contained, offline-first toolkit for **engineering work environments**.

- Old Linux distros
- Limited or no internet access
- No `sudo` / no root
- Built from 30+ years of engineering workflow experience
- All built on AlmaLinux 8.10 (RHEL 8 clone), glibc 2.28
  - Compatible with RHEL 9.x and beyond

Drop the release tarball onto a locked-down workstation, run one command,
and you have modern Linux tooling and sane configurations in your `$HOME` —
no installer, no admin, no internet.

---

## Installation

### Linux

Download **Source code (tar.gz)** from the
[latest release](https://github.com/smprather/engineering-loadout/releases/latest),
then extract and run:

```bash
tar xzf engineering-loadout-v*.tar.gz
cd engineering-loadout-v*/
./loadout install @engineering-loadout
```

That installs the full bundled set — 100+ CLI tools, editors, fonts, and
configuration — into `~/.local` and `~/.config`. Reload your shell with
`exec bash` when it finishes.

Re-run the same command against a newer release tarball to update.
Unchanged files are skipped, so re-runs are quick.

### Picking what to install

There is no "default install" — you always name what you want, the same way
`dnf` or `apt` works:

```bash
./loadout install @engineering-loadout                    # the full set
./loadout install octave                                  # one package
./loadout install @gui-suite                              # a group
./loadout install @engineering-loadout --skip @fonts-all  # everything but fonts
./loadout list                                            # browse packages
./loadout list --tag editor                               # filter by tag
./loadout search vim                                      # substring search
./loadout info gvim                                       # details for one package
./loadout install octave --dry-run                        # preview only
```

### Windows

```powershell
.\loadout.ps1                  # PowerShell 7+
.\loadout-pwsh-bootstrap.ps1   # if starting from PowerShell 5.1
```

No elevation required.

---

## What's Inside

| Component | Description |
|-----------|-------------|
| **[Bash](https://www.gnu.org/software/bash/)** | Layered config, 100+ power aliases, fzf / zoxide / eza / bat integration |
| **[Neovim](https://neovim.io)** | Lazy.nvim, LSP, 326 offline Tree-sitter parsers, locked plugin versions |
| **[Vim](https://www.vim.org)** | Bundled plugins (NERDTree, SimpylFold, vim-liberty), vendored runtime |
| **[Tmux](https://github.com/tmux/tmux)** | Bundled plugins (resurrect, continuum, better-mouse-mode), `Ctrl-\` prefix |
| **[Helix](https://helix-editor.com)** | Ready to run offline |
| **[Starship](https://starship.rs)** | Cross-shell prompt, Linux and Windows configs |
| **[PowerShell](https://github.com/PowerShell/PowerShell)** | Aliases, Unix coreutils wrappers, PSReadLine, Starship, zoxide, PSFzf |
| **[WezTerm](https://wezfurlong.org/wezterm/)** | Terminal emulator config |
| **[AutoHotKey](https://www.autohotkey.com)** | AHK v2 flat script, optional features via `loadout_keys.toml` |
| **[EditorConfig](https://editorconfig.org)** | Consistent formatting across all editors |
| **CLI tools** | 50+ modern command-line tools, ready offline — see table below |
| **Nerd Fonts** | 7 font families |

---

## Design Goals

**Offline-first.** Plugins, parsers, fonts, and binaries are bundled. Nothing
is fetched at install time. Ship it to an air-gapped workstation and it just
works.

**No root.** Everything lands in `$HOME`. No package manager, no `sudo`, no
IT ticket.

**Multi-platform.** RedHat 7 / 8 / 9, Suse, x86_64 / ARM / PowerPC, and
Windows.

**Layered configuration.** Settings flow from lowest to highest precedence:

```
Global → Corp → Site → Team → Project → User
```

Each layer overrides the previous without touching the upstream files.
Personal tweaks, team conventions, and corporate defaults all coexist
without forking anything. Pull a loadout update and your overrides still
work.

**Opinionated but escapable.** Sensible defaults out of the box. Every
preference is a `LOADOUT_CFG_*` variable you can override in your user layer:

```bash
# bash/user/config.sh
export LOADOUT_CFG_PREFERRED_VI=vim        # use vim instead of nvim
export LOADOUT_CFG_ENABLE_STARSHIP=0       # use the built-in prompt
export LOADOUT_CFG_ATTACH_TO_TMUX=1        # auto-attach tmux on login
```

---

## CLI Tools

| Binary | Version | Description |
|--------|---------|-------------|
| [agent-deck](https://github.com/asheshgoplani/agent-deck) | 1.9.12 | TUI dashboard for AI agent orchestration |
| [bash](https://www.gnu.org/software/bash/) | 5.3.9 | The GNU Bourne Again SHell |
| [bat](https://github.com/sharkdp/bat) | 0.26.1 | `cat` with syntax highlighting and Git integration |
| [biome](https://biomejs.dev) | 2.4.15 | Fast JSON / JS / TS / CSS formatter, linter, and LSP |
| [broot](https://dystroy.org/broot/) | 1.56.2 | Interactive tree navigator and fuzzy finder |
| [btm](https://github.com/ClementTsang/bottom) | 0.12.3 | Cross-platform system monitor (CPU, memory, process tree) |
| [btop](https://github.com/aristocratos/btop) | 1.4.7 | Resource monitor — `top` for people who care about aesthetics |
| [bzip2](https://sourceware.org/bzip2/) | 1.0.8 | High-quality block-sorting file compressor |
| [choose](https://github.com/theryangeary/choose) | 1.3.7 | Human-friendly `cut` and `awk` replacement |
| [dasel](https://github.com/TomWright/dasel) | 3.8.1 | Select, update, and convert data across JSON / YAML / TOML / XML / CSV |
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
| [lazygit](https://github.com/jesseduffield/lazygit) | 0.61.1 | TUI git client for staging, committing, and rebasing |
| [micro](https://micro-editor.github.io) | 2.0.15 | Modern, intuitive terminal text editor — Ctrl+S just works |
| [miller](https://github.com/johnkerl/miller) | 6.18.1 | CSV / TSV / JSON / NDJSON / XML data processor (`mlr`) |
| [nvim](https://neovim.io) | 0.12.2 | Hyperextensible Vim-based text editor |
| [pigz](https://zlib.net/pigz/) | 2.8 | Parallel gzip — multi-core `gzip` / `gunzip` replacement |
| [procs](https://github.com/dalance/procs) | 0.14.11 | `ps` replacement with colors and process tree |
| [pv](https://www.ivarch.com/programs/pv.shtml) | 1.6.6 | Monitor progress of data through a pipe |
| [rg](https://github.com/BurntSushi/ripgrep) | 15.1.0 | ripgrep — recursive search that respects `.gitignore` |
| [rsync](https://rsync.samba.org) | 3.4.1 | Fast, incremental file transfer |
| [ruff](https://github.com/astral-sh/ruff) | 0.15.12 | Extremely fast Python linter and formatter |
| [sd](https://github.com/chmln/sd) | 1.0.0 | Intuitive `sed` replacement — `sd 'old' 'new'` just works |
| [shfmt](https://github.com/mvdan/sh) | 3.13.1 | Shell script formatter (bash / sh / mksh / bats) |
| [starship](https://starship.rs) | 1.25.1 | Cross-shell prompt — fast, informative, configurable |
| [stylua](https://github.com/JohnnyMorganz/StyLua) | 2.4.1 | Opinionated Lua code formatter |
| [tealdeer / tldr](https://github.com/dbrgn/tealdeer) | 1.8.1 | Fast `tldr` client with offline page cache |
| [tkdiff](https://sourceforge.net/projects/tkdiff/) | 6.0 | Tcl/Tk visual diff and merge tool |
| [tmux](https://github.com/tmux/tmux) | 3.6a | Terminal multiplexer |
| [ty](https://github.com/astral-sh/ty) | 0.0.35 | Extremely fast Python type checker |
| [uv](https://github.com/astral-sh/uv) | 0.11.13 | Extremely fast Python package installer and resolver |
| [vim](https://www.vim.org) | 9.2 | Vim 9.2 |
| [xsel](https://github.com/kfish/xsel) | 1.2.0 | X11 clipboard command-line access tool |
| [xterm](https://invisible-island.net/xterm/) | 410 | X Window System terminal emulator |
| [yank](https://github.com/mptre/yank) | 1.3.0 | Select terminal output and copy to clipboard |
| [yq](https://github.com/mikefarah/yq) | 4.53.2 | `jq` for YAML, JSON, XML, CSV, TOML, and properties files |
| [zoxide](https://github.com/ajeetdsouza/zoxide) | 0.9.9 | Smarter `cd` — learns your most-used directories |

### Optional tools

Not part of `@engineering-loadout`. Install with `./loadout install <name>`.

| Binary | Version | Description |
|--------|---------|-------------|
| [gvim](https://www.vim.org) | 9.2 | GTK3 GUI vim |
| [nedit-ng](https://github.com/eteran/nedit-ng) | 2025.1 | Qt5 rewrite of NEdit |
| [nvim-qt](https://github.com/equalsraf/neovim-qt) | 0.2.19 | Qt5 GUI frontend for Neovim |
| [octave](https://www.gnu.org/software/octave/) | 11.1.0 | GNU Octave scientific computing |
| [visidata](https://www.visidata.org) | 3.3 | TUI spreadsheet for exploring CSV / TSV / JSON / NDJSON data |
| [meld](https://meldmerge.org) | 3.20.4 | GTK3 visual diff and merge tool |
| [mate-terminal](https://github.com/mate-desktop/mate-terminal) | 1.26.1 | GTK3 terminal emulator |
| [zsh](https://www.zsh.org) | 5.9 | Z shell — advanced tab completion, powerful scripting |
| [fish](https://fishshell.com) | 4.7.1 | Fish shell — autosuggestions, syntax highlighting, no config needed |
| [jupyterlab](https://jupyter.org) | 4.5.7 | Web-based interactive notebooks (opens in browser) |
| [urxvt](http://software.schmorp.de/pkg/rxvt-unicode.html) | 9.31 | rxvt-unicode — X11 terminal with Unicode and Xft |
| [st](https://st.suckless.org) | 0.9.3 | suckless st — minimal X11 terminal |
| [liberty-tools](https://github.com/smprather/liberty-tools) | 1.0.1 | Fast Liberty `.lib` parser and browser-based viewer |
| [time-plot](https://github.com/smprather/time-plot) | 0.1.0 | Plot arbitrary data vs. zero-based time, uPlot HTML output |
| [text-serdes](https://github.com/smprather/text-serdes) | 0.1.1 | Short-lived encrypted text transport for copy/paste workflows |
| [pygwalker](https://github.com/Kanaries/pygwalker) | 0.5.0.1 | Interactive Tableau-style data explorer for pandas DataFrames |
| [expect](https://core.tcl-lang.org/expect/) | 5.45.4 | Tcl-based tool for automating interactive CLI programs |

For GUI tools on headless compute farm / LSF nodes, install `gui_libs`
alongside them — it provides the Qt5 / GTK3 / X11 / Wayland libraries those
nodes don't ship:

```bash
./loadout install gvim nedit-ng --no-backup --skip @fonts-all,tldr-data
# Or the bundled group:
./loadout install @gui-suite --no-backup
```

### Python

[Python](https://www.python.org) **3.14.4** — a portable Python build that
installs to `~/.local`. Use `python3.14` and `pip3.14` to pin this build.

---

## Neovim — 326 Offline Tree-sitter Parsers

The full `nvim-treesitter` parser registry is bundled and installs offline
to `~/.local/share/nvim/tree-sitter-parsers/`. All 326 languages work out
of the box, no internet required.

---

## Nerd Fonts

Seven font families bundled and installed to `~/.local/share/fonts`:

| Font | Notes |
|------|-------|
| [Envy Code R](https://damieng.com/blog/2008/05/26/envy-code-r-preview-7-coding-font) | Clean, distinctive coding font |
| [Fira Code](https://github.com/tonsky/FiraCode) | Ligature-rich monospace |
| [Hack](https://sourcefoundry.org/hack/) | Designed for source code |
| [Inconsolata](https://levien.com/type/myfonts/inconsolata.html) | Humanist monospace |
| [Iosevka Term](https://typeof.net/Iosevka/) | Ultra-narrow, highly legible |
| [JetBrains Mono](https://www.jetbrains.com/lp/mono/) | Designed for long coding sessions |
| [Source Code Pro](https://github.com/adobe-fonts/source-code-pro) | Adobe's open-source workhorse |

Use `./loadout install … --skip @fonts-all` to skip every font, or
`--skip font-firacode` to skip a single family.

---

## Bash Configuration

Six-layer override chain (`global → corp → site → team → project → user`),
`LOADOUT_CFG_*` knobs, and a curated alias set:

- `b` / `bb` / `bbb` … — `cd ..` up 1, 2, 3 levels
- `cdd` / `cddd` … — `cd` to the N-th most recently modified directory
- `g` — ripgrep with sensible defaults (smart case, hidden, no-ignore)
- `f` — `fd` with sensible defaults, falls back to `find`
- `gs` / `gc` / `gp` / `gd` / `ga` — git status / commit / push / diff / add
- `vi` / `vim` — your preferred editor (`nvim` by default)
- `cat` — `bat` with no paging
- `ll` / `la` / `lh` — `ls` variants (sizes, all files, human-readable)

---

## Tmux

Prefix `Ctrl-\`. Shift-arrows for pane navigation, Ctrl-arrows for windows,
`Prefix+1`–`5` for layout presets, `Prefix+v` to capture the pane buffer
into nvim. tmux-resurrect and tmux-continuum bundled — your sessions come
back after a reboot.
