# Copilot Instructions

After a context clear, read `docs/HANDOFF.md` first for current branch state,
verification gates, and user-home follow-up that cannot be inferred from Git
alone.

Engineering-loadout: offline-first, no-root package manager for
engineering / compute work environments. Multi-platform (RedHat 7/8/9, Suse,
x86_64/ARM/PowerPC), layered configuration (global -> corp -> site -> team -> project -> user).
`./loadout` is a POSIX-sh shim that bootstraps bundled Python 3.14 and execs `loadout_main.py` (Python 3.14+, shebang `#!/usr/bin/env python3.14`),
driven by `payload/packages.json` (`schema_version: 3`).

## Key Commands

```bash
# Linux install (copies files -- no repo references remain)
# Bare 'install' errors (dnf/apt style); always name packages or groups.
./loadout install @engineering-loadout

# Subcommands (dnf/apt verbs)
./loadout list                                  # all packages
./loadout list vim helix                        # names matching either filter
./loadout list --groups                         # all @-groups
./loadout list --tag editor                     # filter by tag
./loadout search vim                            # name/desc/tag substring search
./loadout info gvim                             # metadata + reverse-deps
./loadout info @core-cli                        # group members
./loadout resolve gvim                          # dry-run resolver
./loadout install gvim --dry-run                # resolve + print, no writes
./loadout doctor                                # platform + registry sanity check
./loadout snapshot list
./loadout snapshot restore loadout_backups/backup.1.tar.bz2

# Stage an install into a temp/test root
./loadout install @engineering-loadout --dest-dir /tmp/loadout-home

# Selection (positional packages/@groups, plus --skip)
./loadout install octave                        # single package; deps auto-pulled
./loadout install @gui-suite                    # group; expands recursively
./loadout install @engineering-loadout --skip @fonts-all   # curated set minus fonts
./loadout install @engineering-loadout --skip tldr-data
./loadout install @core-cli vim                 # exact set
./loadout install gvim --no-deps                # install verbatim, no dep walk
./loadout install gvim --skip gui_libs --force  # warn on conflict, continue

# Reload bash after changes
exec bash

# Install repo-development git hooks manually
cp hooks/* .git/hooks/ && chmod +x .git/hooks/*

# Smoke-test a fresh Linux home install
./tests/install-linux-tmp-home
```

```powershell
# Windows install (copies files, no elevation required)
.\loadout.cmd
# or: pwsh -NoProfile -ExecutionPolicy Bypass -File .\loadout.ps1
```

Use `sh -n loadout` for the POSIX-sh shim,
`python3 -m py_compile loadout_main.py` for the Python installer, and
`bash -n envs/bash/global/bashrc`
after installer or shell edits. `./tests/install-linux-tmp-home` runs the Linux
installer against a temp `HOME` with temp XDG cache/state dirs from `/tmp`, then
smoke-tests offline Tree-sitter with headless Neovim. It explicitly selects
`@envs-all` for broad config coverage; normal `@envs` is Bash-only.

## Architecture

### Package registry (`payload/packages.json`)

`schema_version: 3`. Every installable thing is a named package with:

- `kind` -- `bin`, `lib-bundle`, `runtime`, `typelib`, `python-base`, `python-tool`,
  `env`, `font`, `data`, or `group`.
- `platforms` -- list from `linux`, `macos`, `windows`. Resolver filters.
- `tags` -- free-form labels for filtering.
- `depends` -- hard-dependency package names (or `@group` refs). Resolver auto-pulls.
- `recommends` -- soft-dependency package names. Auto-pulled when available, silently
  dropped when skipped or unknown.
- Per-kind artifact fields: `bins`, `libs`, `wheels`, `uv_tool`, `uv_extras`, `typelibs`,
  `archive`, `install_to`, `source`, `extra_links`, `supports_layers`, `members`.

Groups (`@`-prefixed keys) have a `members` list and expand recursively with
cycle detection. Synthetic runtime groups: `@shared` (every non-env,
non-optional package), `@shared-all` (same plus optionals), `@envs` (Bash
configuration only), and `@envs-all` (every env config bundle). The bare
keyword `all` is rejected; users always name packages or groups explicitly
(dnf/apt style).

`uv_extras` turns a Python tool requirement into `uv_tool[extra,...]`; bundle the
full locked wheel closure for every extra. `parity-plot` is pinned to stable
upstream tag `v0.5.0`; rebuild with `build/build-parity-plot.sh --tag v0.5.0`.
NiceGUI is now a core upstream dependency, not a `uv_extras` entry. Its
loadout-only patch corrects the stale module version and embeds Plotly in
generated HTML because the upstream CDN form is not offline-safe; retain it.
Kaleido static images still require an already-installed host Chrome/Chromium.

`openssh` is optional and must not expose bare `ssh`, `scp`, or `sftp`; loadout
owns `ssh10`, `ssh10.bin`, `ssh-keygen`, `ssh-add`, `ssh-agent`, and
`ssh-keyscan`. Mainline OpenSSH 10.x rejects Red Hat crypto-policy's
`GSSAPIKexAlgorithms`, so normal `ssh` must fall through to host `/usr/bin/ssh`.

### Resolver

`resolve_tool_selection(args, registry)` in `loadout` performs:

1. Parse `--skip` (groups expanded).
2. Build initial set from positional `PKG` args (groups expanded). Bare
   `install` errors with non-zero exit.
3. Subtract `--skip`.
4. Walk hard `depends` -- `ResolverError` if a depended-upon package was skipped,
   unless `--no-deps` or `--force`.
5. Walk soft `recommends` -- silently drop conflicts.
6. Filter by current platform.

Resolver helpers: `expand_groups`, `walk_depends`, `walk_recommends`,
`filter_by_platform`, `_current_platform`.

### Bash Layer System

`envs/bash/bashrc` is the single entry point (symlinked to `~/.bashrc`,
`~/.bash_profile`, `~/.bash_login`, and `~/.profile`). It sources files in layer
order across six layers: `global -> corp -> site -> team -> project -> user`. Each layer
directory lives under `~/.config/bash/` after install.

Loading sequence (`envs/bash/bashrc`):

1. Sources `envs/bash/functions.sh` (shared utilities available to all layers).
2. Sources `config.sh` per layer (sets `LOADOUT_CFG_*` preferences as exported
   scalars).
3. Sources `bashrc` per layer; each exits early if not interactive.

`source_if_exists <path>` is used throughout for safe optional sourcing.

The `envs/bash/global/` directory is the canonical upstream; the other layer dirs
(`corp/`, `site/`, `team/`, `project/`, `user/`) are user-created and not committed
to this repo.

### Hook Injection Points

Each layer can inject code into `global/bashrc` via numbered files in
`<layer>/global_hooks/`:

| File | Injection point |
|------|----------------|
| `1.sh` | After functions loaded |
| `2.sh` | After GLIBC detection |
| `3.sh` | After PATH setup |
| `4.sh` | After prompt configuration |
| `5.sh` | Before bash completions |
| `6.sh` | After bash completions loaded |
| `7.sh` | Late / final |

### Install behavior

- **Named install**: `./loadout install <PKG...>` copies files; re-run the
  same command to pick up repo changes. Bare `./loadout install` errors.
- **`--dest-dir <dir>`**: install into an alternate root instead of `$HOME`;
  used by installer tests and staging. It belongs after install-like verbs,
  e.g. `./loadout install @engineering-loadout --dest-dir /tmp/loadout-home`.
- **`--no-backup`**: skip backup creation (useful for clean reinstalls or
  automation).
- **`--post-install-hook <script>`**: execute an explicit corp/site/user add-on
  hook after global install steps; can be repeated and hooks run in argument
  order; each hook must be executable and provide its own shebang or binary
  format. Hooks receive `LOADOUT_REPO`, `LOADOUT_HOME`, `LOADOUT_BACKUP_DIR`,
  `LOADOUT_DEST_DIR`, `LOADOUT_NO_BACKUP`.

Backups are numbered (`loadout_backups/backup.N/`, always starting at `.1`; never bare `backup`). The installer skips targets
already pointing into the repo and never overwrites an existing backup. At the end of a successful install run, the
backup dir is compressed to `loadout_backups/backup.N.tar.bz2` and the uncompressed dir is removed; numbering checks
both `backup.N/` and `backup.N.tar.bz2` when picking the next N. Post-install hooks run before compression so
`LOADOUT_BACKUP_DIR` still resolves during hook execution. `./loadout snapshot restore <path>` accepts either the uncompressed dir or
the `.tar.bz2` archive. Backups intentionally exclude font files because vendored Nerd Font archives are large
and reproducible. The fonts phase has its own safety move: normal installs move
an existing `~/.local/share/fonts` to `fonts.bak*` before extraction, but
`--no-backup` reuses that directory in place and creates no font backup. Font
extraction counts real font members and renders a Rich progress bar like other
bulk phases.

Per-phase installers (`install_prebuilt_binaries`, `install_fonts`,
`install_tldr_cache`, `install_typelibs`, `install_portable_python`,
`install_treesitter_parsers`, `install_nvim_treesitter_vendor`,
`install_*_runtime`, `install_python_tools`) receive `selected_tools` and
short-circuit with a `SKIP` install-results row when their package(s) are not in
the selected set. `--skip @fonts-all` short-circuits `install_fonts`;
`--skip tldr-data` short-circuits `install_tldr_cache`; etc.

The Linux installer resolves the repo from the script path, not the current
working directory. It checks the Python version before running.

Before each install area writes files, the installer verifies that the target
directory is writable. Unwritable areas are refused with warnings, later areas
continue when possible, and the run ends with an install results table.

Pre-built Linux binaries live under `payload/<platform>/`, using names like
`el8.x86_64.glibc2p28`. `RPATH=$ORIGIN/../lib64:$ORIGIN/../lib` is pre-baked
into each binary in the repo before bzip2 compression -- the installer is pure
decompress + chmod, no runtime patchelf step. Installer runs `ldd` to warn
about missing `.so` dependencies. If a running binary cannot be replaced,
installer continues and prints a retry notice.

`vcd-toggle-profiler` is a runtime archive rather than a bare `bin/*.bz2`: the
C++ executable needs uPlot JS/CSS files at report-generation time. Its wrapper
in `bin/` derives the install prefix and passes bundled asset paths to the real
ELF under `lib/vcd-toggle-profiler/`. Build it with
`build/build-vcd-toggle-profiler.sh` using EL8 system
`/usr/bin/g++` 8.5; avoid upstream CMake Release because it enables
`-march=native`.

**Binary bundling order: strip -> patchelf -> bzip2.** Never strip after patchelf;
it corrupts `.dynstr` and causes segfaults or "undefined symbol" at runtime.
**Libs that must find each other** (e.g. the `gui_libs` group): patchelf with
`$ORIGIN` (not `$ORIGIN/../lib64`) -- they install flat into `~/.local/lib64/`
alongside each other.

**Never bundle**: glibc (`libc.so.6`, `libm.so.6`, etc.), OpenGL dispatcher
(`libGL.so.1`, `libGLX.so.0`, `libGLdispatch.so.0` -- must match display
driver), C++ runtime (`libstdc++.so.6`, `libgcc_s.so.1`). Mesa vendor/runtime
pieces are okay: `mesa3d_libs` ships `libEGL_mesa`, `libgbm`, `libglapi`, DRI
drivers, GLVND JSON, and `libLLVM-17`; wrappers must set `LD_LIBRARY_PATH`,
`LIBGL_DRIVERS_PATH`, and `__EGL_VENDOR_LIBRARY_DIRS`.

**Qt5 platform plugins** (`libqxcb.so`, `libqwayland-generic.so`) live flat in
`~/.local/lib64/`; `QT_QPA_PLATFORM_PLUGIN_PATH=$HOME/.local/lib64` set in
`envs/bash/global/bashrc` when present.

**WSLg cursor fix**: `QT_QPA_PLATFORM=wayland` in user bashrc -- Qt5 XCB backend
corrupts XWayland global cursor state for all X11 apps in the session; Wayland
backend avoids this.

**Go binaries: build with `go build -ldflags="-w -s"`**, not post-build strip.

**Release gate: `./release --dry-run`** runs independent pre-release gates in
parallel: `scan-for-malware`, `tests/prebuilt-binaries`,
`build/farm-versions --format tsv`, and `sha256sums.txt` generation. Final
tag/release work waits for those gates; malware scan, binary smoke, and
checksum generation are mandatory. `scan-for-malware` caches only clean results
under `${XDG_CACHE_HOME:-~/.cache}/engineering-loadout/malware-scan-v1/`; its
key hashes the source payload bytes, scanner script, YARA binary/rules/tag, scan
flags, and ClamAV engine/signature fingerprint, so payload/rule/script/signature
changes force a fresh scan. `--no-cache` forces a fresh scan and `--clear-cache`
deletes cached clean results. `tests/prebuilt-binaries` installs `@shared`
into a temp `--dest-dir`, probes every executable in `<dest>/local/bin` with
`PATH=<dest>/local/bin:/usr/bin:/bin:/usr/sbin:/sbin`, checks editor runtime
sentinels, and runs installed `nvim` headless against its installed runtime
before any tag is created. Portable Python keeps generic `python3`/`pip3` links in
`~/.local/bin` so `python3` on PATH resolves to 3.14; the only hard py3.6
holdout is Meld's `bin/meld` launcher, which pins `/usr/bin/python3.6` for
PyGObject compatibility (independent of the loadout bootstrap).
Run `tests/install-split-shared-envs` for the production deployment shape:
`@shared` into a temp non-home tree, then `@envs` into a separate temp HOME with
`LOADOUT_CFG_SHARED_PREFIX=<shared>/local`; it smokes Bash startup, shared
PATH, terminfo, WezTerm completions, and core tool startup.
That smoke also protects the env-copy contract: `@envs` must copy config into
the target HOME, replace old symlinked config subdirs that point back into the
repo, and never mutate files under the checkout.
When Docker is available, `tests/prebuilt-binaries-almalinux8`
is the maximum-coverage variant: clean `almalinux:8.10`, read-only repo bind
mount, in-container copy, `./loadout` bootstrap of the bundled Python, then the
same `@shared` binary/runtime smoke. Expected host-contract skips are explicit:
`cloc` needs host Perl, `meld` needs EL8 `/usr/bin/python3.6`, and GL GUI apps
need host GLVND/OpenGL dispatcher libs (`libGL.so.1`, etc.).

The Helix runtime lives at `payload/<platform>/runtime/helix.tar.bz2`; the
installer extracts it to `~/.local/share/helix/runtime`; `runtime/tutor` is the
sentinel file. The Vim runtime lives at `payload/<platform>/runtime/vim92.tar.bz2`;
the installer extracts it to `~/.local/share/vim/vim92`; `filetype.vim` is the
sentinel file. Vim/GVim wrappers derive default runtime paths from installed
`bin/..`, not `$HOME`, so `--dest-dir` installs work with fake `HOME`. Fish
does same for `__fish_data_dir`, `__fish_bin_dir`, and `__fish_sysconf_dir`,
and must ensure `<prefix>/etc/fish` exists before execing `fish.bin`; fish
only enters relocatable mode when both `<prefix>/share/fish` and
`<prefix>/etc/fish` exist, otherwise it falls back to the baked
`/tmp/fish-install-4.7.1` prefix. `st.tar.bz2` extracts to
`~/.local/share/terminfo`; `envs/bash/global/bashrc` prepends that path to
`TERMINFO_DIRS` so ncurses resolves `st-256color` for normal and `--dest-dir`
installs instead of relying on implicit `~/.terminfo`. The Neovim runtime lives at `payload/<platform>/runtime/nvim.tar.bz2`;
the installer extracts it to `~/.local/share/nvim/runtime`; `filetype.lua` is
the sentinel file. `mesa3d_libs.tar.bz2` installs Mesa under
`~/.local/lib64` / `~/.local/lib64/dri` and is chunked as `.part-000..002`.
`wezterm.tar.bz2.part-000..001` installs PATH wrappers for `wezterm`,
`wezterm-gui`, and `wezterm-mux-server`; the real upstream sibling binaries live under
`~/.local/lib/wezterm/` so `wezterm start` can exec `wezterm-gui` correctly.
It also includes `strip-ansi-escapes`, `open-wezterm-here`, the app icon, and
the Nautilus extension. WezTerm zsh completion is env-owned at
`envs/zsh/site-functions/_wezterm`; bash completion is generated by
`wezterm shell-completion --shell bash`. WezTerm *shell integration* (OSC 133
semantic zones / OSC 7 cwd / user vars -- not completion) is NOT in this runtime
archive; it is vendored at `envs/bash/global/wezterm/wezterm.sh` and sourced by
`envs/bash/global/bashrc` from user-writable space, never `/etc`. Off-WezTerm shells
still source it for bash-preexec, but `bashrc` sets the integration skip vars
while sourcing so no WezTerm OSC hooks register. This prevents raw OSC text in
GNOME Terminal and prompt stalls in `wezterm set-working-directory`.

The mate-terminal shanghai bundle must include both
`org.mate.terminal.gschema.xml` and `org.mate.interface.gschema.xml`, then run
`glib-compile-schemas` at install time. The interface schema source lives at
`build/mate-terminal/org.mate.interface.gschema.xml`; without
it, `mate-terminal.bin` aborts with `Settings schema 'org.mate.interface' is not
installed` before opening.

**Prompt block in `envs/bash/global/bashrc` is clobber-sensitive -- do not "simplify"
it.** The loadout does not own `PROMPT_COMMAND` and Starship does not always hook
through it (it registers into `precmd_functions` when a framework like
bash-preexec/wezterm/ble.sh is live). Login shells load that framework via
`/etc/profile`; `unset`-ing or overwriting `PROMPT_COMMAND` around `starship
init` wipes its driver, so the Starship prompt vanishes on login but works after
`exec bash`. Required order: reset framework state -> source loadout `wezterm.sh`
(with WezTerm output hooks skipped off-WezTerm) -> `starship init` (untouched `PROMPT_COMMAND`) -> `loadout_add_precmd
loadout_restore_echo`. Verify with a real PTY (tmux), not `bash -lic`. Full
detail: `envs/bash/global/README.md` and `AGENTS.md` "Lessons Learned".

Fresh Neovim config must start without network: if `lazy.nvim` is absent and
`git` cannot clone it, `envs/nvim/init.lua` disables the plugin layer cleanly
instead of erroring.

Use `./strip-all-elf-binaries` (Python 3.14) after adding vendored
binaries, libraries, parser grammars, or tar archives. It walks the repo
outside `.git`, strips raw ELF files in place, strips ELF payloads inside
standalone `.bz2`, and rewrites tar archives as `.tar.bz2`; processed tarballs
are skipped later when size and modification time match the strip manifest.

`./update tldr-data` writes `payload/tldr/tldr-pages.tar.bz2`; the installer also
accepts legacy `.tar.gz` and replaces any existing tealdeer cache unless
`--skip tldr-data` is passed (or `tldr-data` is not in the selected set).

### Bundled Plugins

Tmux and Vim plugins are vendored in-tree (no internet required):

- `envs/tmux/vendor/plugins/` -- tpm, resurrect, continuum, better-mouse-mode
- `envs/vim/vim/pack/vendor/start/` -- nerdtree, SimpylFold, vim-liberty (auto-loaded)
- `envs/vim/vim/pack/vendor/opt/` -- optional plugins

Run `./update tmux-plugins` to re-clone all tmux plugins from GitHub (pre-commit
hook strips `.git` dirs on the next commit).

Neovim uses Lazy.nvim with versions locked in `envs/nvim/lazy-lock.json`.

Tree-sitter offline support targets Neovim v0.12+ only. Vendored
`nvim-treesitter` and `treesitter-parser-registry` live under
`payload/treesitter/vendor/`; prebuilt parsers, parser-info, queries, and registry cache
live under `payload/treesitter/prebuilt/<platform>/`, where platform is
`$(uname -s lower)-$(uname -m)-<glibc|musl>`. Build or refresh the full parser
set with `./build/treesitter/build_parsers`; it stores parsers as `parser/*.so.bz2`.
The installer decompresses matching parser artifacts to installed `parser/*.so`
and copies metadata directories to `~/.local/share/nvim/tree-sitter-parsers/`.

## Key Conventions

### Variable Naming in Bash

- `LOADOUT_CFG_*` variables are user-facing preferences defined in
  `envs/bash/global/config.sh` as `export LOADOUT_CFG_*=value`. They propagate to
  child processes and are visible in `env | grep LOADOUT_CFG_`. Override any
  variable in a user layer's `config.sh` with the same `export
  LOADOUT_CFG_*=value` form.
- Variables prefixed with `_` are treated as bashrc-local and cleaned up by
  `unset_bashrc_local_vars` (in `functions.sh`) before bashrc exits.
  `LOADOUT_CFG_*` are exported scalars and are intentionally retained so child
  processes and aliases/functions can reference them at runtime.

### Pre-commit Hook

`hooks/pre-commit` scans for nested `.git` directories (from bundled plugins),
removes them, and re-stages. It also runs `./strip-all-elf-binaries` when
staged binary/archive candidates change. Install this hook when developing this
repo or working with bundled plugins (`cp hooks/* .git/hooks/`). Normal
end-user installs do not need repo git hooks. The embedded `.git` cleanup may
broadly re-stage affected files; the binary stripping path restages only
tracked updates, staged candidates, converted `.tar.bz2` archives, and strip
manifests. Review staged files after it runs. For full binary smoke-testing
use `./release --dry-run`, not the pre-commit hook. The scan must prune
`./.git/*`; sandbox/worktree internals such as `./.git/.git` are not vendored
plugins.

### Bash Alias Parsing Trap

Interactive bash expands aliases while parsing sourced files. Before defining a
function whose name may be an alias (`df`, `grep`, `cat`, etc.), clear it with
`unalias name 2>/dev/null || true`. Otherwise `exec bash` can fail with
`syntax error near unexpected token '('` even when noninteractive syntax checks
pass.

### Adding a Bundled Plugin

1. Copy the plugin directory into `envs/vim/vim/pack/vendor/start/` or
   `envs/tmux/vendor/plugins/`.
2. The pre-commit hook strips `.git` dirs automatically on next commit.
3. The relevant env handler (`_install_env_vim` / `_install_env_tmux`) already
   copies the whole vendor dir with delete semantics, so no installer change is needed.

### Overriding Configuration

Create layer files that will be automatically picked up -- no changes to
`envs/bash/global/` needed:

```bash
envs/bash/user/config.sh       # LOADOUT_CFG_* variable overrides (export LOADOUT_CFG_FOO=value)
envs/bash/user/bashrc          # alias/function overrides
envs/bash/corp/global_hooks/3.sh  # inject code after PATH setup
```

### Tool Fallback Pattern

The bash config gracefully degrades when modern tools are absent:

- `eza` -> `lsd` -> `ls`
- `bat` -> `cat`
- `fd` / `fdfind` -> `find`

Handles distro naming differences: `batcat` (Debian) vs `bat` (RedHat),
`fdfind` vs `fd`.

### Windows

Files are **copied**, not symlinked. Re-run `.\loadout.cmd` after
repo changes. `.\loadout.cmd` uses bundled user-local PowerShell at
`%USERPROFILE%\.local\opt\powershell\7\pwsh.exe` when present, falls back to
system `pwsh.exe`, and otherwise uses Windows PowerShell 5.1 to extract
`payload/windows.x86_64/powershell/PowerShell-*-win-x64.zip[.part-NNN]`
without winget/admin. `loadout.ps1` writes a Windows Terminal profile fragment
at `%LOCALAPPDATA%\Microsoft\Windows Terminal\Fragments\engineering-loadout\powershell.json`.
AutoHotKey (`AutoHotkey64.exe`) is extracted to
`%USERPROFILE%\AutoHotkey_*\` rather than installed system-wide (avoids
SentinelOne flagging); if no such directory exists, the installer
auto-downloads the latest stable release from GitHub and removes
`AutoHotkey32.exe`. The PowerShell profile includes `Invoke-PatchDOSStub` -- a
byte-patcher that changes an exe's DOS stub string to alter its hash, useful
as a SentinelOne bypass for flagged binaries like AHK.

The AHK feature config lives at `%USERPROFILE%\loadout_keys.toml` (created if
missing). `hotkeys.ahk` reads the enabled-feature list from this file at startup
-- the installer no longer patches booleans into the script; it just copies it.
Undefined settings fall back to defaults (`[autohotkey].enabled` default true;
optional features default off). Override the config path with the
`LOADOUT_KEYS_TOML` env var; run `hotkeys.ahk --print-config` to dump the
resolved config and exit. The Cisco VPN feature also reads
`[autohotkey.features.cisco-secure-client-vpn].skip_wifi_ssids` directly at
runtime to skip automation on named Wi-Fi networks. Set
`[autohotkey].logging = true` (default false) to append timestamped diagnostics
(SSID source, VPN skip decision, auto-login actions) to
`%USERPROFILE%\autohotkey\hotkeys.log` for troubleshooting.
