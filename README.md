# Engineering Loadout

A self-contained, offline-first toolkit for **engineering work environments**.

- Old Linux distros
- Limited or no internet access
- No `sudo` / no root
- Built from 30+ years of engineering workflow experience
- All built on AlmaLinux 8.10 (RHEL 8 clone), glibc 2.28
  - Compatible with RHEL 9.x and beyond

Drop the release tarball onto a locked-down workstation, run one command,
and you have modern Linux tooling and sane configurations in your `$HOME` --
no installer, no admin, no internet.

---

## Installation

### Linux

Download the `.tar.gz` release archive from the
[latest release](https://github.com/smprather/engineering-loadout/releases/latest),
then extract and run -- nothing is built or compiled, the archive ships every
binary, library, font, and config file ready to install:

```bash
tar xzf engineering-loadout-v*.tar.gz
cd engineering-loadout-v*/
./tools/fetch-stash                        # Neovim plugins -- see below
./loadout install @engineering-loadout
```

That installs the `@engineering-loadout` group -- a curated set of
command-line tools, editors, fonts, and configuration files -- into
`~/.local` and `~/.config`. Reload your shell with `exec bash` when it
finishes.

### The Neovim plugin stash is a second download

The plugin stash is a **separate release asset**, not part of the tarball --
it is ~328 MB of bz2'd git packfiles, so committing it would grow every clone
permanently. `./tools/fetch-stash` downloads and verifies it against the release.

If this machine cannot reach GitHub, download `nvim-plugin-stash.tar.bz2` and
`sha256sums.txt` from the release elsewhere (on Windows,
`tools/download-release.ps1`), copy both over, and pair them by hand:

```bash
./tools/fetch-stash --from-file /path/to/nvim-plugin-stash.tar.bz2 \
              --sums     /path/to/sha256sums.txt
```

`--sums` is required: without it there is nothing to verify against, and a
stash that fails its hash is deleted rather than left on disk. Do **not** copy
the asset into place manually -- `.content-manifest` is a strict allowlist, so
a hand-placed stash is refused, not silently trusted.

Skipping it is safe: Neovim still installs and starts, and the plugin step is
skipped with a warning naming `fetch-stash`.

Re-run the same command against a newer release tarball to update.
Unchanged files are skipped, so re-runs are quick.

> **Deploying to a compute farm or an air-gapped site?** The steps above are the
> single-machine case. For a shared read-only tree, per-user config, the Neovim
> plugin stash, and getting everything across a network whose policy changes ---
> see the [Deployment Runbook](docs/DEPLOYMENT-RUNBOOK.md). Full install details
> are in [Installation](docs/INSTALLATION.md).

### Picking what to install

Name packages or groups the same way `dnf` or `apt` works:

```bash
./loadout install @engineering-loadout                    # the curated set
./loadout install octave                                  # one package
./loadout install parity-plot                             # parity-plot CLI + local designer
./loadout install @gui-suite                              # a group
./loadout install @engineering-loadout --skip @fonts-all  # curated set minus fonts
./loadout list                                            # browse packages
./loadout list vim helix                                  # name matches either filter
./loadout list --tag editor                               # filter by tag
./loadout search vim                                      # substring search
./loadout info gvim                                       # details for one package
./loadout install octave --dry-run                        # preview only
```

### Windows

```powershell
.\loadout.cmd                  # bootstraps/uses bundled user-local PowerShell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\loadout.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\loadout-pwsh-bootstrap.ps1  # explicit 5.1 bootstrap
```

No elevation required.

---

## What's Inside

| Component | Description |
|-----------|-------------|
| **[Bash](https://www.gnu.org/software/bash/)** | Layered shell config, 100+ aliases, fzf / zoxide / eza / bat integration |
| **[Neovim](https://neovim.io)** | LSP, 326 offline Tree-sitter parsers, curated plugin set |
| **[Vim](https://www.vim.org)** | Vim 9.2 with NERDTree, SimpylFold, and vim-liberty bundled |
| **[Tmux](https://github.com/tmux/tmux)** | Sessions that survive reboot (resurrect + continuum), `Ctrl-\` prefix |
| **[Helix](https://helix-editor.com)** | Ready to run offline |
| **[Starship](https://starship.rs)** | Cross-shell prompt, Linux and Windows configs |
| **[PowerShell](https://github.com/PowerShell/PowerShell)** | Aliases, Unix coreutils wrappers, Starship + zoxide integration |
| **[WezTerm](https://wezfurlong.org/wezterm/)** | Terminal emulator config |
| **[AutoHotKey](https://www.autohotkey.com)** | AHK v2 flat script; reads feature config from `loadout_keys.toml` at startup |
| **[EditorConfig](https://editorconfig.org)** | Consistent formatting across all editors |
| **Command-line tools** | 100+ modern CLI utilities, ready offline -- see table below |
| **Nerd Fonts** | 12 font families |

---

## Design Goals

**Offline-first.** Plugins, parsers, fonts, and binaries are bundled. Nothing
is fetched at install time. Ship it to an air-gapped workstation and it just
works.

**No root.** Everything lands in `$HOME` (or `--dest-dir`). No package
manager, no `sudo`, no IT ticket.

Shared-tree installs stay relocatable: bundled runtime/data assets live under
`~/.local/share` (or the staged prefix) and shell init exports the paths
needed for discovery, including `TERMINFO_DIRS` for bundled `st` terminfo.

**Multi-platform.** RedHat 7 / 8 / 9, Suse, x86_64 / ARM / PowerPC, and
Windows.

**Layered configuration.** Settings flow from lowest to highest precedence:

```
Global -> Corp -> Site -> Team -> Project -> User
```

Each layer overrides the previous without touching the upstream files.
Personal tweaks, team conventions, and corporate defaults all coexist
without forking anything. Pull a loadout update and your overrides still
work.

**Opinionated but escapable.** Sensible defaults out of the box. Every
preference is a `LOADOUT_CFG_*` variable you can override in your user layer:

```bash
# envs/bash/user/config.sh
export LOADOUT_CFG_PREFERRED_VI=vim        # use vim instead of nvim
export LOADOUT_CFG_ENABLE_STARSHIP=0       # use the built-in prompt
export LOADOUT_CFG_ATTACH_TO_TMUX=1        # auto-attach tmux on login
export LOADOUT_CFG_ENABLE_WEZTERM_SHELL_INTEGRATION=0   # disable wezterm OSC integration
```

---

## Smoke Testing

The whole suite has one entry point:

```bash
tests/run-all               # Tier 1 fast checks + Tier 2 integration installs
tests/run-all --fast        # Tier 1 only
tests/run-all --container   # adds the Tier 3 clean-container smoke (Docker)
```

Stock AlmaLinux 8 is the verification baseline for install behavior -- a
developer machine accumulates packages that mask missing-dependency bugs.

For maximum Linux binary coverage, run the AlmaLinux 8.10 container smoke. It
uses a clean base image, copies this checkout inside the container, installs
`@shared` into a temp `--dest-dir`, and probes every installed executable with
only the staged `local/bin` plus a basic system PATH. The container does not
install Python for the harness; it uses `./loadout` to bootstrap the bundled
Python 3.14 first. The smoke reports deliberate host contracts as skips: `cloc`
needs host Perl, `meld` needs EL8 `/usr/bin/python3.6`, and OpenGL GUI apps need
host GLVND dispatchers such as `libGL.so.1`.

```bash
tests/prebuilt-binaries-almalinux8          # binary probe only
tests/prebuilt-binaries-almalinux8 --full   # + doctor, resolvers, unit tests,
                                            #   and both integration installs
```

For the shared-tree deployment model, run the split install smoke. It installs
`@shared` into a temp non-home tree, installs `@envs` into a separate temp
`HOME` with `LOADOUT_CFG_SHARED_PREFIX=<shared>/local`, then checks Bash
startup, shared `PATH`, terminfo, WezTerm completions, and core tool startup.
`@envs` installs Bash configuration only (plus its Starship recommendation);
install other config bundles explicitly or use `@envs-all` when every shell
and editor config is intentional. Env installs copy config files into `~/.config`; old symlinked config
subdirectories that point back into the repo are replaced with real
directories so installs cannot mutate the checkout.

```bash
tests/install-split-shared-envs
```

---

## Bundled Packages

Each row is a package you can install by name with
`./loadout install <name>`. Groups (`@engineering-loadout`, `@gui-suite`,
`@core-cli`, ...) bundle related packages so you can install many at once.
Run `./loadout list` to see every package and every group, or
`./loadout list --groups` to see just the groups.
Add one or more positional filters to match package or group names
case-insensitively; any matching filter includes a row. Descriptions are not
searched, for example: `./loadout list vim helix` or
`./loadout list --groups editor cli`.

The optional `openssh` package provides modern `ssh-keygen` for SSH commit/tag
signing on EL8 and an explicit `ssh10` client. It does not install bare
`ssh`/`scp`/`sftp`, so normal SSH stays the host-integrated system client.
FIDO security keys (`-t ed25519-sk`) and PKCS#11 tokens are not supported by
the bundled binaries (their libexec helpers are not shipped) -- use the system
OpenSSH for those.

| Package | Kind | Version | Description |
|---------|------|---------|-------------|
| agent-deck | bin | 1.11.0 | TUI dashboard for AI agent orchestration |
| amux | bin | 0.0.20 | TUI for orchestrating parallel coding agents via git worktrees + tmux |
| bash | bin | 5.3.15 | Portable GNU Bash ahead of EL8 system version |
| bash-docs | runtime | 5.3.9 | GNU Bash man page (bash.1) and info pages; extracted from bash 5.3 source |
| bat | bin | 0.26.1 | cat clone with syntax highlighting and line numbers |
| biome | bin | 2.5.7 | Fast Rust JSON/JS/TS/CSS formatter, linter, and LSP (static-pie musl build, no glibc dep) |
| broot | bin | 1.58.0 | Interactive tree navigator with fuzzy search |
| gtkwave | bin | 3.3.116 | GTKWave — VCD/FST/LXT2/VZT waveform viewer (GTK3) plus the headless format-converter suite (fst2vcd, vcd2fst, vcd2vzt, ...); Tcl scripting not compiled in |
| ipython | python-tool | 9.16.1 | Enhanced interactive Python REPL (tab completion, magics, history, introspection) |
| klayout | bin | 0.30.10 | KLayout — GDSII/OASIS/DXF/CIF/LEF-DEF mask layout viewer and editor with scriptable DRC/LVS (Qt5); embeds the loadout Ruby 3.3 and portable Python 3.14 |
| verilator | bin | 5.050 | Verilator — Verilog/SystemVerilog to C++ simulator (lint, coverage, cycle-accurate regression models); needs host perl and the user’s own g++ |
| yazi | bin | 26.5.6 | Blazing-fast terminal file manager (static-pie musl build, no glibc dep); ships the `ya` CLI companion |
| btm | bin | 0.14.7 | Cross-platform system resource monitor (TUI) |
| btop | bin | 1.4.7 | Resource monitor with graphs and mouse support |
| liberty-filter | bin | 1.0.1 | liberty-filter — strip unneeded data from Liberty (.lib) timing files; Rust CLI, system-libs only |
| lefdef-tools | python-tool | b9ac43e | lefdef-tools — fast LEF/DEF parsing and query tools (Rust backend) |
| liberty-tools | python-tool | v2026.06.01.1-35-g73af358 | liberty-tools — Liberty .lib parser/query library (Rust backend) with liberty-format and liberty-view CLI tools |
| vcd-toggle-profiler | runtime | 891a391 | VCD toggle profiler — C++17 VCD signal toggle analysis with offline self-contained HTML reports |
| pdftotext | bin | 26.04.0 | pdftotext (poppler-utils) — extract plain text from PDF files; static libpoppler, bundles liblcms2+libopenjp2 and poppler-data (CJK CMaps) with a relocatable wrapper |
| p7zip | bin | 16.02 | p7zip — Unix port of 7-Zip; 7za standalone binary (LZMA2, zip, gzip, bzip2, tar, cab, etc.) |
| bzip2 | bin | 1.0.8 | Block-sorting file compressor |
| choose | bin | 1.3.7 | awk/cut alternative for column field selection |
| clang | bin | 23.0git | LLVM/Clang 23 compiler toolchain (clang, lld, clangd, clang-format, clang-tidy, llvm-ar/nm/objcopy/objdump/symbolizer/cov/profdata/link) |
| cloc | bin | 2.10 | Count Lines of Code by language (blank/comment/code). Self-contained Perl script; requires host perl |
| scc | bin | 3.7.0 | Sloc, Cloc and Code — fast code counter with complexity estimates (GitHub's counter). Go static binary, no deps |
| tokei | bin | 14.0.0 | Fast code counter by language. Rust; EL8 source build (v14 ships no prebuilt), links system libs only, glibc 2.28 |
| dasel | bin | 3.11.2 | Query and modify YAML/JSON/TOML/XML/CSV data |
| delta | bin | 0.19.2 | Git diff pager with syntax highlighting |
| duf | bin | 0.9.1 | df replacement with colored usage table |
| dust | bin | 1.2.4 | du replacement with visual bar chart |
| flameshot | bin | 14.0.0 | Flameshot — powerful GUI screenshot tool. flameshot 13.3.0 back-ported to Qt5 for EL8 (upstream is Qt6-only); needs gui_libs (Qt5/X11) + DISPLAY |
| expect | bin | 5.45.4 | Tcl-based tool for automating interactive CLI programs |
| eza | bin | 0.23.5 | ls replacement with icons, colors, git status |
| fd | bin | 10.4.2 | Fast and user-friendly find alternative |
| fio | bin | 3.42 | Flexible I/O tester — storage and filesystem performance benchmark |
| fzf | bin | 0.74.2 | General-purpose command-line fuzzy finder |
| gnuplot | bin | 6.0.5 | Command-line graphing and plotting utility |
| glow | bin | 2.1.2 | Terminal markdown renderer/pager with styles |
| gocheat | bin | 0.1.1 | Interactive terminal cheatsheet browser (EL8 source build, CGO_ENABLED=0 static) |
| keyb | bin | 0.8.0 | Customizable TUI cheatsheet for keybindings/aliases; fuzzy filter, fzf/rofi export |
| gping | bin | 1.20.4 | Ping with live graph visualization |
| htop | bin | 3.5.2 | Interactive process viewer and manager |
| hx | bin | 25.07.1 | Modern modal text editor with tree-sitter and LSP |
| hyperfine | bin | 1.20.0 | Command-line benchmarking tool |
| ncdu | bin | 2.9.2 | NCurses disk usage — interactive disk space analyzer (Zig v2) |
| openssh | bin | 10.4p1 | OpenSSH 10.4p1 signer tools plus explicit ssh10 client (ssh10/ssh10.bin/ssh-keygen/ssh-add/ssh-agent/ssh-keyscan), EL8 source build linking system libcrypto/zlib; provides `ssh-keygen -Y sign` for git commit/tag signing that stock EL8 8.0p1 lacks. Optional — opt in with `./loadout install openssh`; does not install bare ssh/scp/sftp, so normal ssh stays host-integrated. |
| jq | bin | 1.8.2 | Lightweight JSON processor and formatter |
| just | bin | 1.58.0 | Command runner, ergonomic Makefile alternative |
| lazygit | bin | 0.64.0 | TUI git client for staging, committing, rebasing |
| llvm-bolt | bin | 23.0git | LLVM BOLT binary optimizer + perf2bolt profile converter + merge-fdata |
| micro | bin | 2.0.15 | Beginner-friendly terminal text editor |
| miller | bin | 6.20.2 | CSV/TSV/JSON/NDJSON data processor (mlr) |
| ninja | bin | 1.13.2 | Fast build system used by CMake and LLVM |
| numr | bin | 0.8.0 | Text calculator for natural-language expressions with a vim-style TUI (units, currency, variables) |
| fresh | bin | 0.3.8 | Fresh text editor (Rust, tree-sitter, TypeScript/JavaScript config) |
| nvim | bin | 0.12.4 | Hyperextensible Vim-based text editor |
| patchelf | bin | 0.12 | Modify ELF RPATH and interpreter in-place |
| pigz | bin | 2.8 | Parallel implementation of gzip |
| procs | bin | 0.14.12 | ps replacement with colors and process tree |
| pv | bin | 1.6.6 | Monitor and show progress of data through a pipe |
| rg | bin | 15.2.0 | Extremely fast grep alternative (ripgrep) |
| restic | bin | 0.19.1 | Fast, secure, user-space backup to a local repo -- content-defined deduplication, zstd compression, incremental snapshots, authenticated encryption. Single static binary, no root. |
| rsync | bin | 3.4.4 | Efficient file sync with delta-transfer algorithm |
| ruby | bin | 3.3.10 | Ruby 3.3 interpreter from the AlmaLinux 8 ruby:3.3 module stream — stdlib, default gems and rubygems, relocated via a RUBYLIB-deriving launcher |
| ruff | bin | 0.16.2 | Extremely fast Python linter and formatter |
| sd | bin | 1.1.0 | sed alternative with simpler regex syntax |
| shfmt | bin | 3.13.1 | Shell script formatter and parser |
| shellcheck | bin | 0.11.0 | Static analysis linter for shell scripts |
| starship | bin | 1.26.0 | Cross-shell customizable minimal prompt |
| stylua | bin | 2.5.2 | Opinionated Lua code formatter |
| tkdiff | bin | 6.0 | Tcl/Tk visual diff and merge tool |
| tldr | bin | 1.8.1 | Simplified community man pages (tealdeer) |
| tmux | bin | 3.7b | Terminal multiplexer with session management |
| tree-sitter | bin | 0.26.12 | Incremental parser generator and query tool |
| ty | bin | 0.0.69 | Fast Python type checker (Astral) |
| gnu-coreutils | bin | 9.7 | GNU coreutils — individual binaries (ls, cp, mv, etc.) built from source on EL8 |
| uv | bin | 0.12.3 | Extremely fast Python package and project manager |
| vim | bin | 9.2.0901 | Vi IMproved text editor |
| gvim | bin | 9.2.0901 | GTK3 GUI Vim with clipboard and font rendering |
| nedit-ng | bin | 2025.1 | Qt5 GUI text editor, NEdit rewrite |
| surfer | bin | 0.7.0 | Surfer — waveform viewer (VCD/FST/GHW) for digital hardware debugging; egui/OpenGL GUI. Opt-in: install with ./loadout install surfer |
| nvim-qt | bin | 0.2.19 | Official Qt5 GUI frontend for Neovim (menus, tabs, mouse, floating windows; no GPU required) |
| mesa3d_libs | runtime | 23.1.4 | Mesa 3D userspace runtime — Mesa EGL vendor library, GBM, libglapi, DRI drivers, and LLVM runtime (no GLVND dispatcher libs) |
| gui_libs | lib-bundle |  | Qt5/GTK3/X11/Wayland shared library bundle (for headless compute farm GUI forwarding) |
| xsel | bin | 1.2.1 | X11 clipboard command-line access tool |
| yara | bin | 4.5.8 | Malware pattern matching and classification tool |
| xterm | bin | 410 | X11 terminal emulator with Unicode and color |
| urxvt | bin | 9.31 | rxvt-unicode — X11 terminal with Unicode, Xft, and daemon mode (perl extensions disabled) |
| wezterm | bin | 20260618_095146_c10636f3 | WezTerm terminal emulator — shanghai bundle from system install; sample app for bundled Mesa 3D runtime |
| st | bin | 0.9.3 | suckless st — minimal X11 terminal with undercurl patch (UNDERCURL_CURLY) |
| xephyr | bin | 1.20.11-28.el8_10.3 | Xephyr — nested X server, plus the xdesk launcher: run any window manager or desktop session in a window inside the session you already have (no root, no display-manager change, no listening port) |
| yank | bin | 1.4.0 | Select terminal output and copy to clipboard |
| yq | bin | 4.53.3 | YAML/JSON/XML/CSV processor (jq for YAML) |
| zellij | bin | 0.44.3 | Terminal workspace multiplexer (no-web build; WASM plugins disabled) |
| zoxide | bin | 0.10.0 | Smarter cd with frecency ranking (z/zi) |
| octave | bin | 11.3.0 | GNU scientific computing language (MATLAB-compatible) |
| ngspice | bin | 46 | ngspice — open-source mixed-level SPICE circuit simulator (XSPICE + CIDER enabled, no-X11 headless build); relocatable wrapper loads spinit + codemodels from the install prefix |
| spice-subckt-rc-reduce | bin | 0.1.1 | Reduce parasitic RC networks in SPICE .subckt models (TICER / merge), preserving port behavior to cut simulation time |
| visidata | python-tool | 3.4 | TUI spreadsheet for CSV/TSV/JSON data |
| meld | bin | 3.20.4 | GTK3 visual diff and merge tool (shanghai bundle — system py3.6 + bundled PyGObject/GtkSource) |
| mate-terminal | bin | 1.26.1 | MATE Terminal — GTK3 tabbed VTE terminal (shanghai bundle from EL8 EPEL; GSettings keyfile backend, no dconf-service needed) |
| firefox | bin | 140.11.0 | Mozilla Firefox ESR (shanghai bundle from EL8 BaseOS; thin POSIX-sh launcher exec's bundled firefox-bin) |
| zsh | bin | 5.9 | Z shell — powerful interactive shell with advanced tab completion; dynamically-loaded modules (regex, pcre, mathfunc, stat, mapfile, parameter, complist, zprof, zpty, socket, tcp, zftp, system, cap, clone, datetime, langinfo, terminfo, zutil, files, watch, attr, nearcolor, zselect) shipped via runtime archive |
| fish | bin | 4.8.1 | Fish shell — friendly interactive shell with autosuggestions and syntax highlighting |
| tcl | bin | 9.0.3 | Tcl scripting language — tclsh interpreter and runtime library |
| tk | bin | 9.0.3 | Tk GUI toolkit — wish interpreter and embedded Tk runtime |
| nodejs | bin | 26.7.0 | Node.js LTS JavaScript runtime with npm/npx/corepack (for LSP servers, JS tooling) |
| jupyterlab | python-tool | 4.6.1 | Web-based interactive development environment for notebooks, code, and data |
| time-plot | python-tool | 7e9859e | Plot arbitrary data vs. zero-based time with plugins for custom data file parsers |
| text-serdes | python-tool | 361bbf0 | text-serdes — short-lived encrypted text transport for copy/paste workflows (enc/dec) |
| cicwave | python-tool | 0.5.2 | cicwave — PyQtGraph waveform viewer (ngspice/Xyce/VCD/CSV). loadout PyQt6 fork of the upstream PySide6 app (PySide6 has no EL8 glibc-2.28 + Python 3.14 wheel). Opt-in: ./loadout install cicwave |
| parity-plot | python-tool | v0.7.0 | 45-degree Plotly parity plots with an offline NiceGUI designer; generated HTML embeds Plotly for air-gapped viewing |
| pygwalker | python-tool | 0.5.0.1 | Turn pandas DataFrames into an interactive Tableau-style data explorer (Jupyter or `pygwalker serve`) |
| portable-python | python-base | 3.14.4 | BOLT-optimized portable CPython build with bundled install.sh |
| gobject-typelibs | typelib |  | GObject introspection typelibs (GLib/Gtk3/GtkSource3/Pango/Atk/cairo) |
| tldr-data | data |  | Bundled tldr-pages cache for offline tealdeer use |
| treesitter-parsers | data |  | Pre-built tree-sitter parsers (.so), queries, parser-info, registry, and build-info for 300+ languages |
| git-nvim | runtime | 2.43.7 | PRIVATE git for nvim/lazy only -- installed to lib/loadout-git/, never on the user's PATH (a loadout git would shadow the corp git and break its subcommands/credential helpers, cf. openssh/ssh10). Optional: @shared-all or by name. nvim uses it only when the system has no git. |
| nvim-plugin-stash | data |  | Offline git stash for nvim plugins -- 24 bare mirrors + lazy.nvim, read-only, shared. lazy clones from it into the user's lazy/ and :Lazy update fetches from it, so plugin updates work with no network. Needs git (system, or the optional git-nvim package). |
| models | bin | 0.14.0 | TUI/CLI to browse AI models + benchmarks from models.dev (needs network for live data) |
| modules | runtime | 5.6.1 | Environment Modules — module load/unload for shell environment management (HPC-style) |
| rust | runtime | 1.96.0 | Rust toolchain — rustc + cargo + std libraries (offline source build target) |
| rust-crate-store | data |  | Offline Cargo local-registry (top crates.io crates + full dependency closure) |
| espresso | bin | 1.1.1 | Berkeley espresso two-level logic minimizer -- reduce a boolean function (PLA truth table) to a minimal sum-of-products |
| rust-analyzer | bin | 410 | Rust language server (LSP) — diagnostics, go-to-def, completions |
| gopls | bin | 0.23.0 | Go language server (LSP) — diagnostics, go-to-def, completions |
| iverilog | bin | 13.0 | Icarus Verilog — Verilog/SystemVerilog event simulator (`iverilog` compiler driver, `vvp` runtime, `iverilog-vpi` VPI module builder). Compiles to a .vvp file that runs directly; writes VCD for gtkwave/surfer. Unlike verilator this simulates rather than generating a C++ model, so it needs no host g++ to run a design |
| lua-language-server | bin | 3.19.0 | Lua language server (LSP) — useful for nvim config and Lua tooling |
| markdown-oxide | bin | 0.25.12 | PKM markdown language server — wikilinks, backlinks, daily notes and unresolved-link creation over a plain directory of markdown. Obsidian-vault compatible (reads a .obsidian root), so it indexes a vault a user maintains with Obsidian installed separately; Obsidian itself is not redistributable and is not bundled. Drives envs/nvim/lsp/markdown_oxide.lua. |
| pyright | python-tool | 1.1.411 | Python language server (LSP) — type-checking, go-to-def, completions |
| tmux-path-store | python-tool | 1.1.0 | Tmux window-name-keyed directory/file path store — shell aliases for per-window path bookmarks |
### Parity plots

`./loadout install parity-plot` installs the CLI and its local designer, with no
Python packages fetched at install time. `parity-plot plot measurements.csv
--no-open-browser --output parity.html` creates a self-contained HTML report:
the Plotly runtime is embedded so it renders on an air-gapped machine. PNG, SVG,
and PDF export still need a compatible Chrome/Chromium already on the host for
Kaleido; loadout deliberately does not download or bundle a browser.

If your machine doesn't already have GTK3 / Qt5 / X11 / Wayland libraries
installed (common on remote compute nodes), install `gui_libs` alongside
any GUI application:

```bash
./loadout install gvim nedit-ng gui_libs
# Or use the group, which pulls gui_libs for you:
./loadout install @gui-suite
```

GPU-accelerated apps such as WezTerm also pull `mesa3d_libs`, which installs
Mesa's EGL vendor library, GBM, DRI drivers, and LLVM runtime without bundling
host display-driver dispatchers like `libGL.so.1`. The WezTerm bundle keeps
`wezterm`, `wezterm-gui`, and `wezterm-mux-server` as sibling real binaries
under `~/.local/lib/wezterm/`, with PATH wrappers in `~/.local/bin`. Its zsh
completion is installed by `env-zsh`; bash completion can be generated with
`wezterm shell-completion --shell bash`. WezTerm *shell integration* (semantic
zones / OSC 7 cwd / user vars -- distinct from completion) is vendored at
`envs/bash/global/wezterm/wezterm.sh` and sourced by the bash config from
user-writable space (never `/etc`), so wezterm users get it with or without tmux;
toggle with `LOADOUT_CFG_ENABLE_WEZTERM_SHELL_INTEGRATION`. Outside a real
WezTerm session, bash still sources the vendored script for its bash-preexec
driver but disables all WezTerm OSC hooks, so other terminals do not print raw
escape sequences or stall in `wezterm set-working-directory`.

### Python

[Python](https://www.python.org) **3.14.4** -- a portable Python build that
installs to `~/.local`. Use `python3.14` and `pip3.14` to pin this build.

---

## Neovim -- 326 Offline Tree-sitter Parsers

The full `nvim-treesitter` parser registry is bundled and installs offline
to `~/.local/share/nvim/tree-sitter-parsers/`. All 326 languages work out
of the box, no internet required.

---

## Nerd Fonts

Twelve font families bundled and installed to `~/.local/share/fonts`:

| Font | Notes |
|------|-------|
| [Cascadia Code](https://github.com/microsoft/cascadia-code) | Microsoft coding font |
| [DejaVu Sans Mono](https://dejavu-fonts.github.io/) | Broad Unicode coverage |
| [Envy Code R](https://damieng.com/blog/2008/05/26/envy-code-r-preview-7-coding-font) | Clean, distinctive coding font |
| [Fira Code](https://github.com/tonsky/FiraCode) | Ligature-rich monospace |
| [Hack](https://sourcefoundry.org/hack/) | Designed for source code |
| [Inconsolata](https://levien.com/type/myfonts/inconsolata.html) | Humanist monospace |
| [Iosevka Term](https://typeof.net/Iosevka/) | Ultra-narrow, highly legible |
| [JetBrains Mono](https://www.jetbrains.com/lp/mono/) | Designed for long coding sessions |
| [Meslo LG](https://github.com/romkatv/powerlevel10k-media) | Powerlevel10k default family |
| [Roboto Mono](https://fonts.google.com/specimen/Roboto+Mono) | Google monospace family |
| [Source Code Pro](https://github.com/adobe-fonts/source-code-pro) | Adobe's open-source workhorse |
| [Ubuntu Mono](https://design.ubuntu.com/font) | Ubuntu monospace family |

Use `./loadout install ... --skip @fonts-all` to skip every font, or
`--skip font-firacode` to skip a single family. By default, an existing
`~/.local/share/fonts` directory is moved aside to `fonts.bak*` before the
vendored fonts are extracted. With `--no-backup`, the installer reuses the
existing fonts directory in place and overwrites only matching font files. Font
extraction uses the same progress bar style as other bulk install phases.

---

## Bash Configuration

Six-layer override chain (`global -> corp -> site -> team -> project -> user`),
`LOADOUT_CFG_*` knobs, and a curated alias set:

- `b` / `bb` / `bbb` ... -- `cd ..` up 1, 2, 3 levels
- `cdd` / `cddd` ... -- `cd` to the N-th most recently modified directory
- `g` -- ripgrep with sensible defaults (smart case, hidden, no-ignore)
- `f` -- `fd` with sensible defaults, falls back to `find`
- `gs` / `gc` / `gp` / `gd` / `ga` -- git status / commit / push / diff / add
- `vi` / `vim` -- your preferred editor (`nvim` by default)
- `cat` -- `bat` with no paging
- `ll` / `la` / `lh` -- `ls` variants (sizes, all files, human-readable)

---

## Tmux

Prefix `Ctrl-\`. Shift-arrows for pane navigation, Ctrl-arrows for windows,
`Prefix+1`-`5` for layout presets, `Prefix+v` to capture the pane buffer
into nvim. tmux-resurrect and tmux-continuum bundled -- your sessions come
back after a reboot.
