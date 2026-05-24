# CLAUDE.md

Offline-first pkg mgr + dotfiles bundle for **Electrical Engineering work environments**: multi-platform (RedHat 7/8/9, Suse, x86_64/ARM/PowerPC), offline (plugins/binaries bundled), no root, multi-org (global/corp/site/project/user layer hierarchy). `./engineering-loadout` Python 3.6-compatible installer driven by typed pkg registry (`pre_built/packages.json`, `schema_version: 2`) with named packages, `@`-prefixed groups, hard/soft deps, resolver. Installs Bash, Vim/Neovim, Tmux, Helix, Starship, 50+ pre-built CLI binaries, GUI lib bundles, runtime archives, fonts, data caches.

## Key Commands

**Linux:**
```bash
# Install engineering-loadout (copies everything — no repo references remain)
./engineering-loadout

# Stage an install into a temp or test root instead of $HOME
./engineering-loadout --dest-dir /tmp/loadout-home

# Skip the existing-dotfile backup
./engineering-loadout --no-backup

# Run an explicit corp/site/user installer after global install steps
./engineering-loadout --post-install-hook ~/corp-dotfiles/install.sh

# Subcommands: list, describe, resolve, doctor, restore-backup
./engineering-loadout list                            # show all packages
./engineering-loadout list --groups                   # show all groups with member counts
./engineering-loadout list --tag editor               # filter by tag
./engineering-loadout describe gvim                   # full package metadata + reverse deps
./engineering-loadout describe @core-cli              # group membership
./engineering-loadout resolve gvim                    # dry-run resolver; prints set by kind
./engineering-loadout --dry-run --add gvim            # resolve + print only, no install
./engineering-loadout doctor                          # platform + registry integrity check
./engineering-loadout restore-backup loadout_backups/backup.1.tar.bz2

# Package selection (names + groupings defined in pre_built/packages.json)
./engineering-loadout --add octave                    # add package(s); deps (octave-runtime) auto-pulled
./engineering-loadout --add @gui-suite                # add a group; expands recursively
./engineering-loadout --add gvim,@fonts-all           # mix packages and @groups
./engineering-loadout --skip @fonts-all               # remove every font package
./engineering-loadout --skip tldr-data                # skip the tldr cache install
./engineering-loadout --skip @fonts-all,gnuplot,kak   # remove package(s) and group(s) from defaults
./engineering-loadout --only @core-cli,vim,nvim       # exact set (bypass defaults; still walks deps)
./engineering-loadout --only @engineering-loadout     # install everything
./engineering-loadout --profile engineering-loadout   # alias for --only @engineering-loadout
./engineering-loadout --no-deps --only gvim           # install gvim without walking depends/recommends
./engineering-loadout --force --skip gui_libs --add gvim  # WARN on conflict, continue

# Manually install repo-development git hooks
cp hooks/* .git/hooks/ && chmod +x .git/hooks/*
```

**Windows** (no elevation required — copies files):
```powershell
.\engineering-loadout-pwsh-bootstrap.ps1   # if starting from Windows PowerShell 5.1
.\engineering-loadout.ps1
```

## Repository Structure

```
bash/
  bashrc                    - Main entry point → ~/.bashrc, ~/.bash_profile, ~/.bash_login, and ~/.profile
  functions.sh              - Shared functions loaded before any layer (path_*, is_truthy, etc.)
  global/                   - Canonical config (upstream here, don't modify locally)
    config.sh               - LOADOUT_CFG_* preference variables and defaults (exported scalars)
    bashrc                  - PATH setup, colors, history, aliases, prompt, completions
    completions/            - bat, rg, zoxide, hyperfine, watchexec completions
    github.scop.bash-completion/  - Bundled bash-completion library (offline)
    grc/                    - Generic Colorizer binaries and configs
  corp/                     - Corporation-level overrides (user-created)
  site/                     - Site-level overrides (user-created)
  project/                  - Project-level overrides (user-created)
  user/                     - Personal overrides (user-created)

nvim/
  init.lua                  - Thin layer dispatcher (loads global→corp→site→project→user)
  lazy-lock.json            - Locked plugin versions
  lsp/                      - LSP server configs
  lua/global/               - Global layer (bundled, repo-managed)
    config.lua              - vim.g.cfg_* defaults (colorscheme, feature toggles, dpc, swap_dir)
    init.lua                - Options, keymaps, autocmds, LSP setup
    plugins/                - One .lua file per plugin (lazy.nvim specs)
    utils.lua               - Shared helpers (buf_smaller_than)
  lua/corp/                 - Corporation-level overrides (user-created, not bundled)
  lua/site/                 - Site-level overrides (user-created)
  lua/project/              - Project-level overrides (user-created)
  lua/user/                 - Personal overrides (user-created)
  after/ftplugin/           - Filetype overrides (tcl, yaml)

treesitter/
  build_parsers             - Builds all vendored nvim-treesitter parsers
  vendor/                   - Vendored nvim-treesitter and parser registry
  prebuilt/<platform>/      - Tracked parser `.so.bz2` files, queries, build metadata

vim/
  vimrc                     - Vim config → ~/.vimrc
  vim/pack/vendor/start/    - Auto-loaded plugins (nerdtree, SimpylFold, vim-liberty)
  vim/pack/vendor/opt/      - Optional plugins

tmux/
  tmux.conf                 - Tmux config → ~/.tmux.conf
  tmux-word-separators      - Expands tmux double-click word separators with emoji ranges
  tmux/vendor/plugins/      - Bundled plugins (tpm, resurrect, continuum, better-mouse-mode)

pre_built/
  <platform>/               - Platform dir, e.g. el8.x86_64.glibc2p28
    bin/*.bz2               - Compressed binaries → ~/.local/bin
    lib64/*.bz2             - Compressed shared libs → ~/.local/lib64
    runtime/                - Runtime archives (platform-matched)
      helix.tar.bz2         - Helix runtime → ~/.config/helix/runtime/
      vim92.tar.bz2         - Vim 9.2 runtime → ~/.local/share/vim/vim92/
      nvim.tar.bz2          - Neovim runtime → ~/.local/share/nvim/runtime/
      octave.tar.bz2        - Octave m-files + .oct plugins → ~/.local/share/octave/11.1.0/ + ~/.local/lib/octave/11.1.0/oct/
      runtime_config.toml   - Runtime install metadata
    portable-python-*.tar.bz2 - BOLT-optimized Python archive (NOSTRIP — never run strip on it)
  build_scripts/            - Helper scripts (not installed)
    import-portable-python  - Package a portable-python dir → pre_built/<platform>/*.tar.bz2
    farm-versions           - Query installed binary versions (json/tsv/text output)
    check-versions          - Compare bundled package versions against upstream (GitHub releases / PyPI)
    build-kakoune.sh        - Build kakoune from source
    build-jq.sh             - Build jq from source
    build-ncdu.sh           - Build ncdu from source
    build-octave.sh         - Build GNU Octave from source (without Qt/Java/X11; gnuplot backend)
    build-gvim.sh           - Build GTK3 GUI vim (gvim.bin + gvim wrapper script) from source
    build-nedit-ng.sh       - Build nedit-ng Qt5 NEdit rewrite from source (CMake, single binary)
    reproduce-llvm-build.sh - LLVM build reproduction script
  .strip-manifest           - sha256/tar-meta cache for strip_all_elf_binaries

kak/
  kakrc                     - Default kakoune config (copy of share/kak/kakrc from build); copied to ~/.config/kak/kakrc only if not already present

helix/                      - (empty; runtime archive moved to pre_built/<platform>/runtime/)

editorconfig/
  editorconfig              - → ~/.editorconfig

python/
  pip.conf                  - → ~/.config/pip/pip.conf (require-virtualenv = true)

starship/
  config-schema.json        - Vendored schema for editor completions on Linux
  starship.linux.toml       - Linux Starship config → ~/.config/starship/starship.toml
  starship.windows.toml     - Windows Starship config → %USERPROFILE%\.config\starship\starship.toml

powershell/
  Microsoft.PowerShell_profile.ps1  - PowerShell profile (aliases, coreutils wrappers, PSReadLine, Starship, zoxide, PSFzf, Invoke-PatchDOSStub)

wezterm/
  wezterm.lua               - WezTerm config

autohotkey/
  hotkeys.ahk               - Windows AutoHotKey flat script with installer-patched feature flags

hooks/
  pre-commit                - Removes embedded .git dirs before commits. Manual install only: cp hooks/* .git/hooks/ && chmod +x .git/hooks/*

engineering-loadout         - Python 3.6-compatible Linux installer executable (shebang: #!/usr/bin/python3)
engineering-loadout.ps1                 - Windows installation script (PowerShell)
engineering-loadout-pwsh-bootstrap.ps1 - Windows PowerShell 5.1 bootstrapper for pwsh via winget
update_tmux_plugins         - Re-clones all tmux plugins listed in tmux.conf from GitHub (strips .git on next commit)
update_tldr_cache           - Bundles tealdeer pages as tldr/tldr-pages.tar.bz2 for offline installs
strip_all_elf_binaries      - Python 3.6-compatible helper that strips repo ELF payloads and normalizes tar archives to .tar.bz2
tests/install_linux_tmp_home - Runs Linux installer against a temp HOME for fresh-user smoke testing
```

## Installation Details

**Default install** (no flags): Copies files from repo — no symlinks remain. Re-run `./engineering-loadout` after repo changes; most steps idempotent so re-runs fast. Installer resolves repo from script path, runs from any cwd. `./engineering-loadout` checks Python version before running.

### Package registry (pre_built/packages.json)

Installer driven by typed pkg registry at `pre_built/packages.json` (`schema_version: 2`). Every installable thing — binary, lib bundle, runtime archive, config bundle ("env"), font, data archive — is named package with `kind`. Packages declare hard deps (`depends`) and soft deps (`recommends`); groups (keys starting with `@`) bundle related packages.

Package kinds: `bin`, `lib-bundle`, `runtime`, `typelib`, `python-base`, `python-tool`, `env`, `font`, `data`, `group`. Every package also has `default: true/false`, `platforms: [...]`, optional `tags`, legacy fields (`bins`, `libs`, `wheels`, etc.) for current install handlers.

### Resolver and CLI selection

When installer runs, `resolve_tool_selection(args, registry)` performs:
1. Parse `--skip` (groups expanded).
2. Build initial set:
   - `--only X,@Y,…` → exactly those (groups expanded; bypasses defaults).
   - default (every `default: true` package) ∪ `--add …` (groups expanded).
3. Subtract `--skip`.
4. Walk hard `depends` — if depended-upon pkg was skipped, raise `ResolverError` (unless `--no-deps` or `--force`).
5. Walk soft `recommends` — silently drop skipped/unknown.
6. Filter by current platform (`linux`/`macos`/`windows`).

Group expansion (`expand_groups`) recursive, cycle-detected. Synthetic `@default` group expands at runtime to every `default: true` package.

### Subcommands

Installer dispatches on first non-flag arg (defaulting to `install`):

- `./engineering-loadout` — default; full install pipeline.
- `./engineering-loadout list` — package table. `--groups` switches to group table. `--tag T` filters.
- `./engineering-loadout describe <pkg|@group>` — kind, version, platforms, deps, recommends, reverse-deps, file lists, group memberships, full metadata dump.
- `./engineering-loadout resolve [<pkg>...]` — runs resolver, prints resolved set grouped by `kind`. Positional args treated as `--add`.
- `./engineering-loadout --dry-run` — resolve + print; no writes. Combine with selection flags.
- `./engineering-loadout doctor` — platform/registry sanity check; verifies archive paths for every `runtime`/`data`/`font`/`python-base` pkg; flags unresolved `depends`/`recommends`.
- `./engineering-loadout restore-backup <dir-or-tar.bz2>` — restore dotfiles from numbered backup (uncompressed dir or `.tar.bz2` archive).

### Selection flags (apply to `install`, `resolve`, `--dry-run`)

- `--only NAMES` — install exactly listed packages/`@groups` (still walks deps unless `--no-deps`). `all` = every non-group package.
- `--add NAMES` — add packages/`@groups` to default install set.
- `--skip NAMES` — remove packages/`@groups` from install set.
- `--profile NAME` — alias for `--only @NAME` (e.g. `--profile engineering-loadout`).
- `--no-deps` — install named set verbatim; no `depends`/`recommends` walk.
- `--force` — continue past resolver errors (e.g. hard dep in skip set), printing `WARNING:` row instead of erroring.

### Per-phase selection gating

Each phase installer (`install_prebuilt_binaries`, `install_fonts`, `install_tldr_cache`, `install_typelibs`, `install_portable_python`, `install_treesitter_parsers`, `install_nvim_treesitter_vendor`, `install_*_runtime`, `install_python_tools`) receives `selected_tools` and short-circuits with `SKIP` install-results row when its package(s) not in selected set. `--skip @fonts-all` short-circuits `install_fonts`; `--skip tldr-data` short-circuits `install_tldr_cache`; etc.

**Destination mode** (`--dest-dir <dir>`): Installs into alternate root instead of `$HOME`. Used by tests, useful for staging.

**No-backup mode** (`--no-backup`): Skips backup before installing. Useful for clean reinstalls or automated use.

**Skipping fonts**: Pass `--skip @fonts-all` to skip all vendored Nerd Font archives and font cache refresh. Individual families: `--skip font-firacode`, etc.

**Post-install hook** (`--post-install-hook <script>`): Runs add-on hooks after global install steps, before automatic layer `install.sh` scripts. Option can be provided multiple times; hooks run in arg order. Paths resolved before installer changes to `$HOME`; each hook must be executable with own shebang. Hook failure fails installer. Env passed: `LOADOUT_REPO`, `LOADOUT_HOME`, `LOADOUT_BACKUP_DIR` (absolute current backup dir, empty when backups skipped), `LOADOUT_DEST_DIR`, `LOADOUT_NO_BACKUP`.

**Install result behavior**: Before each install area writes files, installer verifies target dir writable. If not, refuses that area with warning, records failed row, continues with later areas. Every run ends with install results table: `yes`, `no`, or `skip`.

**Font behavior**: Extracts vendored fonts from top-level `fonts/*.zip` into `~/.local/share/fonts`. Large archives stored as split chunks `*.zip.part-000`, `*.zip.part-001`, etc.; use 45 MiB chunks to stay below GitHub's 50 MB warning. Installer rejoins under `/tmp/loadout-fonts.*` before extraction. Generates `fonts.scale`/`fonts.dir` when `mkfontscale`/`mkfontdir` present, refreshes fontconfig with `fc-cache`. Font discovery fontconfig-first for normal Linux desktop apps, WSLg, RHEL/Alma 8. Do not add `xset +fp` startup logic; X core font paths can fail when `$HOME` not traversable by X server. Windows Terminal reads fonts from Windows, not WSL fontconfig.

**Pre-built binary behavior**: Installer selects `pre_built/<platform>/` based on OS family, architecture, libc. Preferred platform names exact and ABI-oriented, e.g. `el8.x86_64.glibc2p28`. Files under `bin/*.bz2` decompressed to `~/.local/bin`, marked executable. Files under `lib64/*.bz2` decompressed to `~/.local/lib64`. All bz2 decompression uses `write_bz2_atomic` (temp file in same dir + `os.rename`) — prevents SIGBUS when running Python has memory-mapped a shared lib being overwritten. RPATH (`$ORIGIN/../lib64:$ORIGIN/../lib`) pre-baked into each binary before bzip2 compression in repo (see `pre_built/build_scripts/repatch-binaries` and `ADDING_BINARIES.md`), no post-install patchelf needed — installer is pure decompress + chmod. `$ORIGIN` is runtime-relative token resolved by `ld.so` at load time, so baking it in repo is identical to setting it post-install. If running binary like `tmux` cannot be replaced, installer continues and prints final retry notice. Then runs `ldd` on installed binaries, warns about missing `.so` deps. If no exact platform exists, installer may use compatible same-arch glibc build whose glibc version not newer than host. Installer shebang `#!/usr/bin/python3`; all subprocess calls use absolute paths (`_LDD`, `_UNAME`, `_GETCONF` resolved at startup via `_find_tool()`) to prevent accidentally picking up binaries being installed. **Never bundle these libs:**
- **glibc components** (`libc.so.6`, `libm.so.6`, `libpthread.so.0`, `libdl.so.2`, `librt.so.1`) — must match system's `ld-linux.so.2` exactly; version mismatch produces `undefined symbol: ..., version GLIBC_PRIVATE` crashes. Every EL8 target already has glibc 2.28.
- **OpenGL dispatcher** (`libGL.so.1`, `libGLX.so.0`, `libGLdispatch.so.0`) — must be system's display-driver-linked version; bundling causes crashes or wrong driver selection.
- **C++ runtime** (`libstdc++.so.6`, `libgcc_s.so.1`) — present on all EL8 systems; version mismatches with C++ code subtle and hard to diagnose. Run `./strip_all_elf_binaries` after adding binaries, libs, parser grammars, or tar archives. Strips raw ELF files in place, strips ELF payloads inside standalone `.bz2`, rewrites tar archives as `.tar.bz2`; processed tarballs skipped on later runs when size and mtime match strip manifest. Non-ELF `.bz2` payloads (e.g. `vim.bz2` shell wrapper) recorded in `.strip-manifest` after first check, skipped as manifest hits subsequently. Archives matching `NOSTRIP_ARCHIVE_PREFIXES` (currently `portable-python-*`) completely skipped — BOLT-optimized binaries must not be touched.

**Tree-sitter parser behavior**: Offline support targets Neovim v0.12+ only. Installer copies vendored `nvim-treesitter` and `treesitter-parser-registry` into `~/.local/share/nvim/loadout/vendor/`, looks for prebuilt artifacts under `treesitter/prebuilt/$(uname -s lower)-$(uname -m)-<glibc|musl>/`, decompresses `parser/*.so.bz2` to `parser/*.so`, copies `parser-info/`, `queries/`, `registry/`, `build-info/` into `~/.local/share/nvim/tree-sitter-parsers/`. Neovim appends that parser dir to `runtimepath`, starts native Tree-sitter on filetype buffers. Build all supported parsers with `./treesitter/build_parsers`; prebuilt `.so.bz2`, parser-info, queries, registry cache, `build-info/*.env` tracked.

**tldr cache behavior**: `./update_tldr_cache` writes `tldr/tldr-pages.tar.bz2` for offline tealdeer. Installer accepts `.tar.bz2` and legacy `.tar.gz`, replaces existing `~/.cache/tealdeer/tldr-pages` unless `--skip tldr-data`, `./strip_all_elf_binaries` normalizes tar archives to bzip2.

**Helix runtime behavior**: Installer looks for `helix.tar.bz2` in `pre_built/<platform>/runtime/` first, falls back to legacy `helix/helix_runtime.tar.bz2`. Safely extracts into `~/.config/helix/`, replacing existing `~/.config/helix/runtime`. Correct install has `~/.config/helix/runtime/tutor`. Archive contains `./runtime/...`, extracts directly to `~/.config/helix/`.

**Vim runtime behavior**: Installer looks for `vim92.tar.bz2` in `pre_built/<platform>/runtime/` first, falls back to legacy `vim/runtime.tar.bz2`. Extracts to `~/.local/share/vim/`, renames `runtime/` to `vim92/`, verifies `filetype.vim` present. Correct install has `~/.local/share/vim/vim92/filetype.vim`.

**Neovim runtime behavior**: Installer looks for `nvim.tar.bz2` in `pre_built/<platform>/runtime/`. Extracts to `~/.local/share/nvim/`, replaces existing `~/.local/share/nvim/runtime`, verifies `runtime/filetype.lua` present. Release smoke gate runs installed `nvim` headless with `--clean`, asserts this runtime on `runtimepath`. Neovim config bootstraps `lazy.nvim` when available; if `lazy.nvim` missing and `git` cannot clone it, plugin layer disabled cleanly so core editor config still starts on locked-down machines.

**Octave runtime behavior**: Installer looks for `octave.tar.bz2` in `pre_built/<platform>/runtime/` only when `octave` in selected tools (`optional: true` in `packages.json` — opt in with `./engineering-loadout --add octave`). Archive contains `./share/octave/11.1.0/` (m-files, fonts, data; doc excluded) and `./lib/octave/11.1.0/oct/` (.oct compiled plugins, patchelf'd to RPATH `$ORIGIN/../../../../../lib64`). Extracts into `~/.local/`, verifying `~/.local/share/octave/11.1.0/m/` present. Three octave core libs (`liboctave.so.13`, `liboctinterp.so.15`, `liboctmex.so.1`) bundled separately as `lib64/*.bz2` with RPATH `$ORIGIN`. Main binary `octave` is thin 16K launcher with RPATH `$ORIGIN/../lib64`. Total uncompressed ~163 MB, dominated by libopenblas + libopenblasp (~110 MB combined). Build with `pre_built/build_scripts/build-octave.sh` from extracted source tarball.

**gui_libs behavior**: `gui_libs` optional pkg (`"optional": true` in `packages.json`) bundling ~80 shared libs covering Qt5 5.15.3, GTK3 3.22, ICU 60, cairo, pango, glib2, xcb extensions, xkbcommon, Wayland client, X11 client libs. Install with `./engineering-loadout --add gui_libs` (often `--add gui_libs,gvim,nedit-ng`). Targets **headless EE farm/LSF nodes** lacking GUI libs but running GUI tools with `DISPLAY` forwarding. All gui_libs `.so` files patchelf'd with RPATH `$ORIGIN` (not `$ORIGIN/../lib64`). Qt5 XCB and Wayland platform plugins (`libqxcb.so`, `libqwayland-generic.so`) stored **flat in `~/.local/lib64/`**. `bash/global/bashrc` sets `QT_QPA_PLATFORM_PLUGIN_PATH=$HOME/.local/lib64` when `libqxcb.so` present — Qt finds platform plugin there directly. **WSLg / XWayland cursor corruption**: Qt5 XCB backend sends blank/null cursor on window entry, corrupting XWayland's global cursor state for all subsequent X11 apps. Fix: set `QT_QPA_PLATFORM=wayland` in `~/.config/bash/user/bashrc`. Routes Qt5 through Wayland compositor, bypassing XWayland for cursor management. Wayland backend requires `libqwayland-generic.so` + `libQt5WaylandClient.so.5`, both in gui_libs.

**Portable Python behavior**: Installer looks for `portable-python-*.tar.bz2` in platform dir. If found, extracts to temp dir under `/tmp` via `safe_extract_tar`, runs bundled `install.sh --prefix ~/.local --force --no-test`. Generic `python3`/`pip3` links left in place, so `python3` on PATH resolves to 3.14. Base-install protection: `python/pip.conf` installed to `~/.config/pip/pip.conf` with `require-virtualenv = true`, `PIP_REQUIRE_VIRTUALENV=1` exported from `bash/global/bashrc` — guard against accidental `pip install` to base env. Use `python3.14` and `pip3.14` for this build. Archive must never run through `strip_all_elf_binaries` (BOLT-optimized). To add/update portable Python: `pre_built/build_scripts/import-portable-python <portable-dir>`.

**Python tool behavior (uv tool)**: PyPI tools that are Python-only or have manylinux binary wheels installed via `uv tool install` into per-tool isolated venvs at `~/.local/share/uv/tools/<tool>/`. Launchers auto-created at `~/.local/bin/`. Wheels bundled offline in `pre_built/<platform>/wheels/`. Installer runs `uv tool install <pkg> --python ~/.local/bin/python3.14 --no-index --find-links <wheels_dir> --no-cache` for each selected tool with `"uv_tool"` key in `packages.json`. If no matching wheel found in `wheels_dir`, tool skipped with warning. To add new Python tool: (1) bundle wheels with `PIP_REQUIRE_VIRTUALENV=0 pip3.14 download <pkg> --platform manylinux2014_x86_64 --python-version 3.14 --only-binary :all: -d pre_built/<platform>/wheels/`; (2) add `packages.json` entry with `"uv_tool"`, `"wheels"`, optionally `"libs"` / `"typelibs"` / `"optional": true`; (3) add required C libs to `lib64/*.bz2` and typelibs to `typelibs/`.

**GObject typelib behavior**: Installer copies `*.typelib` files from `pre_built/<platform>/typelibs/` to `~/.local/lib/girepository-1.0/`. `bash/global/bashrc` exports `GI_TYPELIB_PATH=$HOME/.local/lib/girepository-1.0` when that dir exists, allowing Python tools using `import gi` (PyGObject) to find bundled typelibs. Required typelibs documented in `"typelibs"` key of `packages.json` entries (reference only — installer copies all typelibs unconditionally). Typelib files from EL8 RPMs: `gobject-introspection` (GLib/GObject/Gio/GIRepository), `gtk3` (Gtk/Gdk/GdkPixbuf), `gtksourceview3` (GtkSource-3.0). Plain files, no strip/patchelf needed.

**Meld runtime behavior (shanghai bundle)**: Meld 3.20.4 bundled as "shanghai" — extracted from system-installed EL8 package, repacked into `pre_built/<platform>/runtime/meld.tar.bz2`. Uses **system Python 3.6** (`/usr/bin/python3.6`) with bundled PyGObject 3.28.3 (gi) and pycairo 1.16.3. Bundle extracts to `~/.local/` and installs: `lib/python3.6/site-packages/{gi,cairo,meld,meld3}/`, `share/meld/`, `bin/meld` (Python 3.6 launcher). Launcher sets `sys.path`, `GI_TYPELIB_PATH`, `LD_LIBRARY_PATH` before `import gi` — `LD_LIBRARY_PATH` must be set before `import gi` so `dlopen()` for `_gi.cpython-36m.so` finds `~/.local/lib64/libgirepository-1.0.so.1`. Bundled `meld/conf.py` has DATADIR patched to `~/.local/share/meld` (was `/usr/share/meld`). Exclusively-owned libs: `libgirepository-1.0.so.1`, `libgtksourceview-3.0.so.1` (both patchelf'd RPATH `$ORIGIN`). Installer function: `install_meld_runtime()`. Typically installed with gui_libs: `./engineering-loadout --add gui_libs,meld`. Installer warns if meld selected without gui_libs (GTK3/Qt5/X11 libs all from gui_libs). To update meld: re-`yum install meld` on EL8 build machine, re-run shanghai extract steps (copy gi/cairo/meld packages + data files into bundle dir, patch conf.py, create tar.bz2, bzip2 new libs if version changed, update packages.json version), run `./strip_all_elf_binaries`, commit. **Why shanghai instead of PyPI wheels**: PyGObject has no binary wheels on PyPI (source-only, requires gobject-introspection headers). EL8 ships GLib 2.56.4; PyGObject ≥ 3.36 requires GLib ≥ 2.62; PyGObject ≤ 3.30 (works with GLib 2.56) incompatible with Python 3.14 (`Py_TYPE()` assignment removed). System Python 3.6 sidesteps all of this.

**Zsh binary behavior**: `zsh` optional pre-built binary (`optional: true` in `packages.json` — opt in with `./engineering-loadout --add zsh`). No runtime archive needed; binary self-contained. Links against `libncurses.so.6` and `libreadline.so.7` (both always-installed bundled libs). Built from source on EL8 with `--disable-pcre` (avoids bundling `libpcre.so.1`); POSIX ERE regex still works via zsh `regex` module. Build with `pre_built/build_scripts/build-zsh.sh --tag <version>`. Tag format: bare version number, e.g. `5.9` (no `v` prefix — zsh upstream convention).

**Fish runtime behavior**: `fish` optional pre-built binary (`optional: true` — opt in with `./engineering-loadout --add fish`). Binary requires standard library (functions, completions, themes) shipped as `pre_built/<platform>/runtime/fish.tar.bz2`. Archive contains `./share/fish/...`, extracts to `~/.local/` so standard library lands at `~/.local/share/fish/`. Installer function: `install_fish_runtime()`. Binary links against `libncurses.so.6` and `libpcre2-8.so.0` (both bundled — `libpcre2-8.so.0` owned by `gui_libs` but installed as lib64 dep). fish 4.x written in Rust; build with cmake+cargo via `pre_built/build_scripts/build-fish.sh --tag <version>`.

**JupyterLab Python tool behavior**: `jupyterlab` optional `uv_tool` (`optional: true` — opt in with `./engineering-loadout --add jupyterlab`). Installed via `uv tool install jupyterlab` using bundled wheels. After install, `jupyter` and `jupyter-lab` launchers at `~/.local/bin/`. Users run `jupyter lab`; JupyterLab opens in system browser. Requires accessible browser (WSL2: Windows browser via WSL interop; headless farm nodes: point `BROWSER` to VNC-accessible browser or use `--no-browser --port=8888` with port forwarding). Wheels must be downloaded with `PIP_REQUIRE_VIRTUALENV=0 pip3.14 download jupyterlab --platform manylinux2014_x86_64 --python-version 3.14 --only-binary :all: -d pre_built/<platform>/wheels/` — JupyterLab has ~80 dependency packages.

**Backup behavior**: Numbered backups in `loadout_backups/backup.N/` (always starts at `.1`; never bare `backup`). Skips files already pointing to repo. Never overwrites existing backups. At end of successful install, backup dir compressed to `loadout_backups/backup.N.tar.bz2`, uncompressed dir removed; numbering checks both `backup.N/` and `backup.N.tar.bz2` when picking next N. Post-install hooks (receive `LOADOUT_BACKUP_DIR`) run before compression. `restore-backup` accepts uncompressed dir or `.tar.bz2` archive (extracts to `/tmp`, restores). Backups exclude font files (`*.ttf`, `*.otf`, `*.pcf`, `*.bdf`, `*.woff`, `*.woff2`, etc.) — large and reproducible.

**Tmux plugin behavior**: All bundled plugins always copied/linked from repo. Run `./update_tmux_plugins` to re-clone from GitHub (pre-commit hook strips `.git` dirs on next commit).

**Tmux selection behavior**: `tmux/tmux-word-separators` run from `tmux.conf` to append broad emoji ranges to `word-separators`. Tmux only supports literal separator chars, not Unicode classes — keep helper in sync with `tmux.conf` if double-click word selection starts capturing prompt icons like Starship's read-only lock.

**Linux symlink map:**
- `~/.bashrc`, `~/.bash_profile`, `~/.bash_login`, `~/.profile` → `~/.config/bash/bashrc` → `repo/bash/bashrc`
- `~/.vimrc` → `~/.config/vim/vimrc`
- `~/.vim` → `~/.config/vim/vim`
- `~/.tmux.conf` → `~/.config/tmux/tmux.conf`
- `~/.tmux` → `~/.config/tmux/tmux`
- `~/.editorconfig` → `~/.config/editorconfig/editorconfig`
- `~/.config/starship/starship.toml` ← `repo/starship/starship.linux.toml`
- `~/.config/starship/config-schema.json` ← `repo/starship/config-schema.json`
- `~/.config/helix/runtime/` ← `repo/pre_built/<platform>/runtime/helix.tar.bz2`
- `~/.local/share/vim/vim92/` ← `repo/pre_built/<platform>/runtime/vim92.tar.bz2`
- `~/.local/share/nvim/runtime/` ← `repo/pre_built/<platform>/runtime/nvim.tar.bz2`
- `~/.local/bin/python3.14` etc. ← `repo/pre_built/<platform>/portable-python-*.tar.bz2` (via install.sh)

**Windows copy destinations** (files copied, not symlinked — re-run `.\engineering-loadout.ps1` after repo changes):
- `%LOCALAPPDATA%\nvim` ← `repo/nvim`
- `%USERPROFILE%\.config\wezterm\wezterm.lua` ← `repo/wezterm/wezterm.lua`
- `%USERPROFILE%\.config\starship\starship.toml` ← `repo/starship/starship.windows.toml`
- `%USERPROFILE%\.editorconfig` ← `repo/editorconfig/editorconfig`
- `%USERPROFILE%\autohotkey\hotkeys.ahk` ← `repo/autohotkey/hotkeys.ahk`
- `%USERPROFILE%\loadout_keys.toml` — user-local AHK feature selection config (created if missing)
- `engineering-loadout.ps1` patches feature flags in `%USERPROFILE%\autohotkey\hotkeys.ahk` based on enabled feature list
- `%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\hotkeys.lnk` — `.lnk` shortcut pointing to `AutoHotkey64.exe "%USERPROFILE%\autohotkey\hotkeys.ahk"` (AHK not system-wide to avoid SentinelOne flagging). AHK extracted to `%USERPROFILE%\AutoHotkey_*\`; if none exists, installer downloads latest stable from GitHub, removes `AutoHotkey32.exe`.
- `%USERPROFILE%\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1` ← `repo/powershell/Microsoft.PowerShell_profile.ps1` (PS 5.1)
- `%USERPROFILE%\Documents\PowerShell\Microsoft.PowerShell_profile.ps1` ← same (PS 7+)

## Bash Configuration Architecture

### Layer System

Files sourced in order: `global → corp → site → project → user`. Each layer overrides previous. Layer dirs (`bash/corp/`, `bash/site/`, `bash/project/`, `bash/user/`) user-created, not bundled.

**Loading sequence** (see `bash/bashrc`):
1. Sources `bash/functions.sh` (shared utilities, available to all layers)
2. Sources `config.sh` per layer (sets `LOADOUT_CFG_*` preferences)
3. Sources `bashrc` per layer (PATH, aliases, prompt, completions); each layer's `bashrc` exits early if not interactive

### Hook System

Each layer can have `global_hooks/1.sh` through `7.sh` injected at these points in `global/bashrc`:

| Hook | Execution point |
|------|----------------|
| 1.sh | After functions loaded |
| 2.sh | After GLIBC detection |
| 3.sh | After PATH setup |
| 4.sh | After prompt configuration |
| 5.sh | Before bash completions |
| 6.sh | After bash completions loaded |
| 7.sh | Late / final |

### Configuration Variables (`bash/global/config.sh`)

All variables exported scalars (`export LOADOUT_CFG_*=value`) — propagate to child processes, visible in `env | grep LOADOUT_CFG_`. Override in user layer's `config.sh` with same form.

| Variable | Default | Purpose |
|----------|---------|---------|
| `LOADOUT_CFG_PREFERRED_BASH` | `""` | Full path to preferred bash binary; re-execs into it at startup if set, differs from current bash, and is executable |
| `LOADOUT_CFG_PREFERRED_LS` | `eza` | ls replacement (`eza`, `lsd`, `ls`) |
| `LOADOUT_CFG_PREFERRED_VI` | `nvim` | Editor (`nvim`, `vim`) |
| `LOADOUT_CFG_PREFERRED_CAT` | `bat` | cat replacement (used by aliases) |
| `LOADOUT_CFG_ENABLE_GRC` | `1` | Generic Colorizer |
| `LOADOUT_CFG_ENABLE_FZF` | `0` | fzf shell integration |
| `LOADOUT_CFG_ENABLE_ZOXIDE` | `0` | zoxide shell integration (`z`/`zi` commands) |
| `LOADOUT_CFG_ENABLE_STARSHIP` | `1` | Starship prompt (falls back to built-in prompt) |
| `LOADOUT_CFG_STARSHIP_USERIDS_TO_HIGHLIGHT` | `""` | Space-separated list of usernames; if `whoami` matches, username shown in prompt |
| `LOADOUT_CFG_ENABLE_FASTNVIM` | `0` | Fast nvim mode |
| `LOADOUT_CFG_ENABLE_TMUX_PATH_STORE` | `1` | tmux_path_store alias injection |
| `LOADOUT_CFG_PROMPT_COLOR_NORMAL` | `$PROMPT_YELLOW` | Normal session prompt color |
| `LOADOUT_CFG_PROMPT_COLOR_FARM` | `$PROMPT_RED` | Farm/LSF session prompt color |
| `LOADOUT_CFG_PROMPT_INCLUDE_HOST` | `0` | Include hostname in prompt |
| `LOADOUT_CFG_ATTACH_TO_TMUX` | `0` | Auto-attach tmux on login |
| `LOADOUT_CFG_ATTACH_TO_TMUX_WITH_DETACH_OTHERS` | `0` | Detach other clients when attaching |

### Key Functions (`bash/functions.sh`)

- `path_append`, `path_prepend`, `path_remove`, `path_trim` — PATH colon-list manipulation
- `path_prepend_if_dir`, `path_append_if_dir` — prepend/append only if dir exists
- `source_if_exists` — source file only if readable
- `is_truthy` — boolean check (`1`/`true`/`yes`/`on`/`enabled` → true)
- `fpcmp N OP N` — floating-point comparison (`fpcmp 2.17 -gt 2.0`)
- `vercomp`, `verlte`, `verlt`, `ver_between` — version string comparison
- `array_slice` — Python-style array slicing (`array_slice 1:-1 "${arr[@]}"`)
- `join_by` — join array with delimiter
- `auto_attach_to_tmux` — attaches/creates tmux session if `LOADOUT_CFG_ATTACH_TO_TMUX` set (available for manual call from user layer)
- `unset_bashrc_local_vars` — unsets all `_*` variables before bashrc exits

### Notable Aliases (`bash/global/bashrc`)

**Navigation:**
- `b` / `bb` / `bbb` … `bbbbbbbbbb` — `cd ..` up 1–10 levels
- `cdd` / `cddd` / `cdddd` … — cd to N-th most recently modified directory
- `cd-` — `cd -` (previous directory)
- `p` — print and save cwd to `/tmp/p_dir`; `cdp` — cd back to it
- Custom `cd()`: accepts file path (goes to parent), offers to create missing dirs with `mkdir -p`, runs `ls` after

**Listing:**
- `ll` / `lr` / `sl` / `rl` — all alias to `ls`
- `lh` — `human_readable=1 ls`
- `la` — `list_all=1 ls`
- `lg` — `show_group=1 ls`
- `lah` / `lha` — both size and all

**Editing:**
- `vi` / `vim` — `LOADOUT_CFG_PREFERRED_VI`
- `vic` — nvim with clean vimrc only
- `vii` — open most recently modified file
- `vid` — diff mode
- `fvi` — open fzf-selected file
- `v` — `nvim -n -R -` (read stdin, read-only)
- `new` — touch + chmod +x + open

**Search:**
- `g` — `rg --smart-case --search-zip --hidden --no-ignore` (falls back to `grep -r -i`)
- `sg` — same but limited to 100K files
- `gv` — inverted grep
- `gf` — fixed-string grep
- `gpy` / `gtcl` — grep Python / Tcl files
- `f` — `fd --unrestricted --full-path` (falls back to `find .`)
- `h` — `history | g`
- `hg` — `history | grep -i`
- `gah` — grep all bash history files across all PIDs

**Git:**
- `ga` — `git add [all]` then `git status`
- `gs` — `git status`
- `gc` — `git commit`
- `gp` — `git push`
- `gd` — `git d`
- `gsp` — stash, pull, pop

**Utilities:**
- `cat` — `bat --paging=never` (if bat available); `catp` — bat with paging
- `t` — `exec bash` (reload shell)
- `lns` — safe symlink (removes existing link first)
- `latest` — create/follow a `latest` symlink to a dir, then cd into it
- `w` — `type -a` (where is this defined?)
- `x` — `chmod +x`
- `rs` — rsync with progress, no `.snapshot/`
- `du` / `dum` — disk usage sorted by size (GB/MB)
- `rm` — `rm -f`
- `mkdir` — `mkdir -p`
- `we` — `watchexec --clear --poll 500`
- `extract_rpm` — `rpm2cpio | cpio -idmv`
- `zhead` — zcat + head
- `rp` — realpath (cwd if no arg)
- `gzip` / `gunzip` — pigz / unpigz
- `vnc` — start VNC server (no args) or pass through to vncserver

## Component Reference

### Tmux (`tmux/tmux.conf`)

- Prefix: `Ctrl-\`
- Pane navigation: `Shift+arrows`; Pane resize: `Prefix+arrows` (repeatable)
- Window navigation: `Ctrl+left/right`; Window reorder: `Ctrl+Shift+left/right`
- Layout presets: `Prefix+1-5`; 4-pane layout: `Prefix+o`; Reload: `Prefix+r`
- Capture pane buffer to nvim: `Prefix+v`
- Plugins: tmux-resurrect (save: `Prefix+Ctrl-s`, restore: `Prefix+Ctrl-r`), tmux-continuum (auto-save every 60min), tmux-better-mouse-mode

### PowerShell (`powershell/Microsoft.PowerShell_profile.ps1`)

Key aliases: `ls`/`lr` → eza, `vi` → nvim, `f` → fd, `cat` → bat, `g`/`grep` → rg, `b`/`bb`/`bbb` → cd up, `cdd` → cd to most recently modified dir, `gs`/`gc`/`gp`/`gd`/`ga`/`gsp` → git shortcuts, `w` → `Get-DefinitionPath`.

Integrations (conditional, cached init): zoxide (`z`/`zi`), PSFzf (`Ctrl+T` file picker, `Ctrl+R` history), Starship prompt. Falls back gracefully when tools absent.

`Invoke-PatchDOSStub` — byte-patches DOS stub string in exe to change its hash, useful for bypassing SentinelOne hash-based flagging of tools like AutoHotkey.

coreutils wrappers (via Git for Windows path): `rm`, `cp`, `mv`, `diff`, `rmdir`, `mkdir`, `wc`, `sed`, `awk`, `cut`, `xargs`.

### AutoHotKey (`autohotkey/hotkeys.ahk`)

Requires AHKv2. `hotkeys.ahk` single flat script. `engineering-loadout.ps1` copies to `%USERPROFILE%\autohotkey\hotkeys.ahk`, patches feature-flag booleans from `%USERPROFILE%\loadout_keys.toml`.

Key hotkeys:
- `Ctrl+Alt+R` → reload script
- `Ctrl+Alt+A` → pause/resume all hotkeys
- `Ctrl+Alt+V` → toggle VPN auto-login when Cisco VPN feature enabled

Optional features:
- `corp-logins` — corp credential entry hotkeys using `CORP_UID` / `CORP_PASSWORD`
- `mouse-wiggle` — idle mouse nudge; set `AHK_ENABLE_MOUSE_WIGGLE=false` to suppress
- `cisco-secure-client-vpn` — Cisco Secure Client reconnect + credential automation
- `password-manager` — `Ctrl+Alt+B` types `PWMANAGER_PASSWORD` + Enter
- `tmux-hotkeys` — `RAlt`/`RWin` zoom toggle and `Ctrl+;` last-pane toggle for tmux
- `f1f2f3-as-mouse-buttons` — F1/F2/F3 mouse remaps for mspaint/etxc/wezterm-gui
- `thinlinc-reconnect` — auto-dismiss ThinLinc "Connection error" dialogs, relaunch `tlclient.exe`, auto-fill Server/Username/Password from `THINLINC_SERVER` / `THINLINC_USERNAME` / `THINLINC_PASSWORD` (pings server before launching/connecting; user-initiated closes respected). `Ctrl+Alt+T` shows live diagnostic (tick count, last-seen state, env, window matches, ping).

Existing `%USERPROFILE%\loadout_keys.toml` files with legacy plugin IDs remain accepted by installer and mapped onto flat-script feature flags.

**Layer architecture** (analogous to bash `global→corp→site→project→user`): `nvim/init.lua` thin dispatcher that sources `config.lua` per layer (Phase 1), bootstraps lazy.nvim (Phase 2), collects plugin specs from each layer's `plugins/` dir via `{ import = "LAYER.plugins" }` (Phase 3), sources `init.lua` per layer (Phase 4). `vim.g.cfg_*` variables set in `global/config.lua` are defaults; later layers override. Plugin manager: Lazy.nvim (versions locked in `lazy-lock.json`). Key plugins: blink.cmp, snacks.nvim, gitsigns.nvim, conform.nvim, nvim-lint, nvim-treesitter, tokyonight.nvim. `vim.g.cfg_dpc` guards update-checker and notifications on offline machines. `vim.g.loadout_plugins_enabled` false when lazy.nvim bootstrap fails offline — core editor still starts cleanly.

Snacks dashboard provides no-argument `nvim` startup screen (`filetype=snacks_dashboard`). `mini.trailspace` highlights trailing whitespace with window-local matches, so dashboard cleanup must disable `vim.b.minitrailspace_disable`, turn off local `list`, delete existing `MiniTrailspace` matches on dashboard open/update.

### Vim (`vim/vimrc`)

Native Vim 8 package management. Plugins in `vim/pack/vendor/{start,opt}/`. Basic settings: UTF-8, 4-space tabs, line numbers.

### Modern CLI Tools Expected

`eza`, `bat`, `rg` (aliased `g`), `zoxide`, `fzf`, `fd`/`fdfind`, `grc`, `pigz`

Falls back gracefully: eza → lsd → ls, bat → cat, fd → find. Handles Debian (`batcat`, `fdfind`) vs RedHat naming.

## Git Hooks

**pre-commit**: Scans for `.git` dirs in subdirectories, removes them, re-stages. Required because bundled plugins (tmux, vim) include own `.git` dirs causing "embedded git repository" warnings.

## Common Patterns

### Add a layer override

```bash
# Create the file — it will automatically override global/
bash/user/config.sh      # LOADOUT_CFG_* variable overrides
bash/user/bashrc         # alias/function overrides
bash/corp/global_hooks/5.sh  # hook injection at point 5
```

### Add a new bundled plugin (vim/tmux)

1. Copy plugin dir into `vim/vim/pack/vendor/start/` or `tmux/vendor/plugins/`
2. Pre-commit hook strips `.git` dirs automatically on next commit
3. Relevant env handler (`_install_env_vim` / `_install_env_tmux`) already rsyncs whole vendor dir — no installer change needed.

### Stable-release policy for bundled binaries

All bundled tools must come from **stable tagged releases** — never from git HEAD, nightly branches, or dev builds. Tagged releases have known changelogs, upstream testing, verifiable provenance.

**Rules:**
- All `build_scripts/build-*.sh` scripts require `--tag vX.Y.Z` (enforced at runtime).
- Tag must be stable release tag from tool's official GitHub releases page.
- Dev builds (e.g. `nvim 0.13-dev`, `micro 2.0.16-dev`) **not accepted** — rebuild from latest stable tag.
- Source builds with long upstream release cycles (tmux, bash) acceptable but must use most recent **stable** tag, not HEAD.
- Some tools have no EL8-compatible official prebuilt (e.g. nvim — official releases require GLIBC_2.34, EL8 has 2.28). These must be source-built from stable tag on EL8 build machine. Bundled binary still stable; just compiled locally.
- Opt-in unstable stream may be added in future; until then, all bundled binaries must be stable.

**Verify provenance after adding:**
```bash
pre_built/build_scripts/verify-binaries          # check all tools
pre_built/build_scripts/verify-binaries rg bat   # check specific tools
```
Tools built from EL8 source (different NEEDED libs than upstream musl/gnu release) or with patchelf layout deltas documented in `verify-binaries`'s `_SKIP_REASONS` / PASS reasoning; all must still come from tagged releases.

### Add a new pre-built binary

```bash
bzip2 -k mybinary
cp mybinary.bz2 pre_built/el8.x86_64.glibc2p28/bin/
./strip_all_elf_binaries          # strips, updates .strip-manifest
git add pre_built/ .strip-manifest
git commit                        # pre-commit hook re-strips and re-records
```

For shared libraries, put `.bz2` in `lib64/` instead.

### Import or update portable Python

```bash
pre_built/build_scripts/import-portable-python /path/to/portable-python-X.Y.Z-tag/
# Do NOT run strip_all_elf_binaries on the result — BOLT-optimized, already in NOSTRIP list
git add pre_built/ .strip-manifest
git commit
```

### Query installed binary versions

```bash
pre_built/build_scripts/farm-versions --format text    # aligned table
pre_built/build_scripts/farm-versions --format tsv     # for spreadsheets / README tables
pre_built/build_scripts/farm-versions --format json    # machine-readable
pre_built/build_scripts/farm-versions --missing-only   # find gaps
```

When adding new binary, add entry to `TOOLS` in `farm-versions` with right strategy.

### Check bundled versions against upstream

```bash
pre_built/build_scripts/check-versions                 # current vs latest, text table
pre_built/build_scripts/check-versions --outdated-only # only rows where current < latest
pre_built/build_scripts/check-versions --include-na    # include pkgs with no upstream API
pre_built/build_scripts/check-versions --format tsv    # tab-separated, for spreadsheets
pre_built/build_scripts/check-versions --format json   # machine-readable
pre_built/build_scripts/check-versions --offline       # skip network; just list current versions
```

Reads `packages.json` for bundled `version` and `farm-versions`'s TOOLS table for homepage URLs. Queries `api.github.com/.../releases/latest` (falling back to `/tags`) for GitHub-hosted projects and `pypi.org/pypi/<name>/json` for `python-tool` packages with `uv_tool` field. Authenticates against GitHub via `$GITHUB_TOKEN`/`$GH_TOKEN` or `gh auth token` for 5000/hr authenticated quota vs 60/hr unauthenticated. Packages whose homepage isn't on GitHub/PyPI marked `n/a` (skipped from default view).

### Create a GitHub release

```bash
./release              # smoke-tests all binaries, then tags + publishes
./release --dry-run    # smoke-test only, no tag or GitHub release
./release --tag v2026.05.12   # explicit tag instead of today's date
```

`./release` runs `pre_built/build_scripts/test-prebuilt-binaries` (full temp install + probe of every binary) before creating tag. Blocked if any binary fails.
Generates binary version table from `farm-versions --format tsv` for release notes.

GitHub auto-generates `Source code (tar.gz)` and `Source code (zip)` containing full repo.

### History

Per-PID history files at `$XDG_RUNTIME_DIR/bash_history.$$`. Child bash inherits parent history. New shells start from most recently modified history. `HISTSIZE=10000`, `HISTCONTROL=ignorespace:erasedups`.