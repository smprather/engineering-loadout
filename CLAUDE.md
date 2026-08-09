# CLAUDE.md

Start with [`docs/HANDOFF.md`](docs/HANDOFF.md) after any context clear. It
records latest branch state, verification gates, and user-home follow-up that
cannot be inferred from Git alone.

## Build Machine Mandate

**ALL developers working on this project are MANDATED to be on an EL8 machine.**
Claude Code runs on **AlmaLinux 8.10 WSL2** (`uname -r: 6.6.87.2-microsoft-standard-WSL2`).
This IS the EL8 build machine -- glibc 2.28, gcc-toolset-14 at `/opt/rh/gcc-toolset-14/enable`.
There is no "separate EL8 machine" to SSH into. All build commands run in the current session.
**Never frame build steps as requiring a separate or remote system.**

---

Offline-first package manager for **engineering / compute work environments**: multi-platform (RedHat 7/8/9, Suse, x86_64/ARM/PowerPC), offline (plugins/binaries bundled), no root, multi-org (global/corp/site/team/project/user layer hierarchy). `./loadout` is a POSIX-sh shim that self-bootstraps the bundled portable Python 3.14 (no system Python required) and execs `loadout_main.py` under it; the installer is driven by typed pkg registry (`payload/packages.json`, `schema_version: 3`) with named packages, `@`-prefixed groups, hard/soft deps, resolver. Installs Bash, Vim/Neovim, Tmux, Helix, Starship, 100+ pre-built CLI binaries, GUI lib bundles, runtime archives, fonts, data caches.

## Key Commands

**Linux:**
```bash
# Install the curated bundled set (bare 'install' errors -- name what you want)
./loadout install @engineering-loadout

# Stage an install into a temp or test root instead of $HOME
./loadout install @engineering-loadout --dest-dir /tmp/loadout-home

# Skip the pre-install snapshot
./loadout install @engineering-loadout --no-backup

# Run an explicit corp/site/team/user installer after global install steps
./loadout install @engineering-loadout --post-install-hook ~/corp-dotfiles/install.sh

# Subcommands (dnf/apt verbs): install, reinstall, upgrade, list, search, info,
# resolve, doctor, snapshot {create|restore|list}, clean, completion
./loadout list                                        # show all packages
./loadout list vim helix                              # names matching either filter
./loadout list --groups                               # show all groups with member counts
./loadout list --tag editor                           # filter by tag
./loadout search vim                                  # case-insensitive substring search
./loadout info gvim                                   # full package metadata + reverse deps
./loadout info @core-cli                              # group membership
./loadout resolve gvim                                # dry-run resolver; prints set by kind
./loadout install gvim --dry-run                      # resolve + print only, no install
./loadout doctor                                      # platform + registry integrity check
./loadout snapshot list
./loadout snapshot restore loadout_backups/backup.1.tar.bz2

# Package selection (names + groupings defined in payload/packages.json)
./loadout install octave                              # single package; deps auto-pulled
./loadout install @gui-suite                          # group; expands recursively
./loadout install gvim @fonts-all                     # mix packages and @groups
./loadout install @engineering-loadout --skip @fonts-all               # curated set minus fonts
./loadout install @engineering-loadout --skip tldr-data                # skip the tldr cache
./loadout install @engineering-loadout --skip @fonts-all,gnuplot,micro   # multiple skips
./loadout install @core-cli vim nvim                  # exact set (deps still walked)
./loadout install @engineering-loadout                # install the curated bundled set
./loadout install gvim --no-deps                      # install gvim without walking depends/recommends
./loadout install gvim --skip gui_libs --force        # WARN on conflict, continue

# Manually install repo-development git hooks
cp hooks/* .git/hooks/ && chmod +x .git/hooks/*
```

**Windows** (no elevation required -- copies files):
```powershell
.\loadout.cmd                  # bootstraps/uses bundled user-local PowerShell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\loadout-pwsh-bootstrap.ps1  # explicit Windows PowerShell 5.1 bootstrap
pwsh -NoProfile -ExecutionPolicy Bypass -File .\loadout.ps1
```

## Repository Structure

The 15 per-user config-source dirs live under `envs/`. They mostly mirror the
15 `kind: env` packages, but not one-to-one: `envs/tealdeer/` is a template read
by `install_tealdeer_config`, while `env-cargo` is generated and has no
`envs/cargo/` source dir. The `@envs` group is intentionally Bash-only;
`@envs-all` selects every env package. Everything the installer reads at run
time lives under `payload/` (platform dirs, packages.json, fonts, tldr, yara,
crate-store, treesitter prebuilt+vendor, pending-daemon). Build tooling lives
under `build/`, the test suite under `tests/`; `hooks/`, `docs/`, and
`installer_vendor/` stay at the top level.

```
envs/bash/
  bashrc                    - Main entry point -> ~/.bashrc, ~/.bash_profile, ~/.bash_login, and ~/.profile
  functions.sh              - Shared functions loaded before any layer (path_*, is_truthy, etc.)
  global/                   - Canonical config (upstream here, don't modify locally)
    config.sh               - LOADOUT_CFG_* preference variables and defaults (exported scalars)
    bashrc                  - PATH setup, colors, history, aliases, prompt, completions
    completions/            - bat, rg, zoxide, hyperfine, watchexec, loadout completions (loadout.bash generated by `loadout completion bash`)
    github.scop.bash-completion/  - Bundled bash-completion library (offline)
    grc/                    - Generic Colorizer binaries and configs
    icecream-bash/          - Vendored IceCream-Bash (MIT): ic/icp/ict/ictp debug-print helpers
    icecream-ext.sh         - loadout override: ic/ict also print arbitrary strings + mixed var/string args (vendored ic.sh kept pristine; icp/ictp stay force-literal)
    wezterm/                - Vendored WezTerm shell integration (wezterm.sh + PROVENANCE); OSC 133 zones / OSC 7 cwd / user vars; loaded from user-writable space, never /etc. See envs/bash/global/README.md "Prompt & shell integration"
  corp/                     - Corporation-level overrides (user-created)
  site/                     - Site-level overrides (user-created)
  team/                     - Team-level overrides (user-created)
  project/                  - Project-level overrides (user-created)
  user/                     - Personal overrides (user-created)

envs/nvim/
  init.lua                  - Thin layer dispatcher (loads global->corp->site->team->project->user)
  package.json/-lock.json   - Plugin catalog manifest; the actual plugin stash ships as the
                              gitignored GitHub release asset envs/nvim/vendor/plugins/nvim-plugin-stash.tar.bz2
  lsp/                      - LSP server configs
  lua/global/               - Global layer (bundled, repo-managed)
    config.lua              - vim.g.cfg_* defaults (colorscheme, feature toggles, dpc, swap_dir)
    init.lua                - Options, keymaps, autocmds, LSP setup
    plugins/                - One .lua file per plugin (lazy.nvim specs)
    utils.lua               - Shared helpers (buf_smaller_than)
  lua/corp/                 - Corporation-level overrides (user-created, not bundled)
  lua/site/                 - Site-level overrides (user-created)
  lua/team/                 - Team-level overrides (user-created)
  lua/project/              - Project-level overrides (user-created)
  lua/user/                 - Personal overrides (user-created)
  after/ftplugin/           - Filetype overrides (tcl, yaml)

envs/vim/
  vimrc                     - Vim config -> ~/.vimrc
  vim/pack/vendor/start/    - Auto-loaded plugins (nerdtree, SimpylFold, vim-liberty)
  vim/pack/vendor/opt/      - Optional plugins

envs/tmux/
  tmux.conf                 - Tmux config -> ~/.tmux.conf
  tmux-word-separators      - Expands tmux double-click word separators with emoji ranges
  tmux/vendor/plugins/      - Bundled plugins (tpm, resurrect, continuum, better-mouse-mode)

payload/                    - Everything the installer reads at run time (ships in releases)
  packages.json             - Typed package registry (schema_version 3)
  <platform>/               - Platform dir, e.g. el8.x86_64.glibc2p28
    bin/*.bz2               - Compressed binaries -> ~/.local/bin
    lib64/*.bz2             - Compressed shared libs -> ~/.local/lib64
    typelibs/               - GObject *.typelib files -> ~/.local/lib/girepository-1.0/
    wheels/                 - Bundled Python wheels for offline `uv tool install`
    runtime/                - Runtime archives (platform-matched)
      helix.tar.bz2         - Helix runtime -> ~/.local/share/helix/runtime/
      st.tar.bz2            - st terminfo entries -> ~/.local/share/terminfo/
      vim92.tar.bz2         - Vim 9.2 runtime -> ~/.local/share/vim/vim92/
      nvim.tar.bz2          - Neovim runtime -> ~/.local/share/nvim/runtime/
      octave.tar.bz2        - Octave m-files + .oct plugins -> ~/.local/share/octave/11.3.0/ + ~/.local/lib/octave/11.3.0/oct/
      runtime_config.toml   - Runtime install metadata
    portable-python-*.tar.bz2 - BOLT-optimized Python archive (NOSTRIP -- never run strip on it)
  windows.x86_64/powershell/ - Bundled PowerShell zip chunks for the Windows installer
  fonts/                    - Vendored Nerd Font zips (large ones split into .part-NNN chunks)
  tldr/                     - tldr-pages.tar.bz2 offline tealdeer cache
  yara/                     - YARA-Forge ruleset for scan-for-malware
  crate-store/              - Offline Cargo local-registry archive chunks (rust-crate-store)
  treesitter/
    prebuilt/<platform>/    - Tracked parser `.so.bz2` files, queries, build metadata
    vendor/                 - Vendored nvim-treesitter + parser registry (installed to ~/.local/share/nvim/loadout/vendor/)
  pending-daemon/           - loadout-pending-daemon (deferred-replace helper; must ship in releases)

build/                      - Build tooling (export-ignored; not in release tarballs)
  update                    - Unified dev-artifact updater (yara-rules, tldr-data, tmux-plugins, nodejs; rolling-git first-party wheels; guidance for build/download packages and for pinned `python-tool` wheel closures via the PYPI_WHEEL class)
  release                   - Runs parallel release gates, then tags + publishes a GitHub release
  strip-all-elf-binaries    - Strips repo ELF payloads and normalizes tar archives to .tar.bz2 (Python 3.14)
  scan-for-malware          - YARA + ClamAV scan of bundled payloads with clean-result cache
  split-bz2                 - Split a large .bz2/.tar.bz2 into 45 MiB .part-NNN chunks
  dev-onboard               - AlmaLinux build-machine bootstrap for new developers
  export                    - Verified, git-less publish to an install directory
  ADDING_BINARIES.md        - MANDATORY build notes for every bundled tool
  build-*.sh                - Per-tool source-build scripts (require --tag vX.Y.Z)
  farm-versions             - Query installed binary versions (json/tsv/text output)
  check-versions            - Compare bundled package versions against upstream (GitHub releases / PyPI)
  verify-binaries           - Check provenance of bundled tools against upstream releases
  import-nodejs, import-portable-python, repatch-binaries - Importers/fixups
  docker/                   - AlmaLinux 8.10 smoke/rust images + entrypoints
  cicwave/, mate-terminal/ - Per-tool patches and data files
  treesitter/build_parsers  - Builds all vendored nvim-treesitter parsers into payload/treesitter/prebuilt/
  reproduce-llvm-build.sh   - LLVM build reproduction script

tests/                      - Test suite (see tests/run-all)
  run-all                   - Single entry point: Tier 1 fast + Tier 2 integration; --fast / --container
  check-installer           - Fast installer sanity (shim syntax, doctor, resolver dry-runs)
  unit-resolver             - Unit tests for the pure resolver layer (synthetic registries)
  registry-integrity        - packages.json consistency vs loadout_main.py + build tooling
  tar-safety                - safe_extract_tar path-traversal/symlink/hardlink cases
  install-fonts-rejoin      - Font chunk rejoin + no-backup reuse behavior
  install-modules           - Fresh-HOME native Environment Modules install + per-shell init/load/unload smoke
  optional-packages         - openssh sign/verify + surfer + offscreen cicwave (packages @shared never probes)
  install-parity-plot       - Offline parity-plot CLI, self-contained HTML, and NiceGUI-designer smoke
  install-linux-tmp-home    - Curated loadout + explicit @envs-all into a temp HOME (fresh-user simulation)
  install-split-shared-envs - @shared into non-home tree + @envs with LOADOUT_CFG_SHARED_PREFIX
  install-xdesk             - Brings a nested display up through xdesk in a temp root; asserts
                              size / cookie enforcement / clean teardown; skips when $DISPLAY unset
  prebuilt-binaries         - Smoke-test every installed binary/runtime (used by ./build/release)
  prebuilt-binaries-almalinux8 - The same inside a clean almalinux:8.10 container; --full adds
                              doctor/resolver/unit tests + both integration installs (Tier 3 gate)
  rust-offline-almalinux8   - Offline rust toolchain + crate-store smoke in the container

.strip-manifest             - sha256/tar-meta cache for strip-all-elf-binaries

envs/helix/
  config.toml               - Helix editor config -> ~/.config/helix/config.toml

envs/editorconfig/
  editorconfig              - -> ~/.editorconfig

envs/pip/
  pip.conf                  - -> ~/.config/pip/pip.conf (require-virtualenv = true)

envs/starship/
  config-schema.json        - Vendored schema for editor completions on Linux
  starship.linux.toml       - Linux Starship config -> ~/.config/starship/starship.toml
  starship.windows.toml     - Windows Starship config -> %USERPROFILE%\.config\starship\starship.toml

envs/powershell/
  Microsoft.PowerShell_profile.ps1  - PowerShell profile (aliases, coreutils wrappers, PSReadLine, Starship, zoxide, PSFzf, Invoke-PatchDOSStub)

envs/wezterm/
  wezterm.lua               - WezTerm config

envs/autohotkey/
  hotkeys.ahk               - Windows AutoHotKey flat script; reads feature config from loadout_keys.toml at startup

hooks/
  pre-commit                - Removes embedded .git dirs before commits. Manual install only: cp hooks/* .git/hooks/ && chmod +x .git/hooks/*

tools/                      - Helper scripts that SHIP to users (not export-ignored)
  fetch-stash               - Fetch + verify the nvim plugin stash from a signed release
  refresh-stash             - Refresh the plugin stash in place in a shared tree (clone/fetch only)
  download-release.ps1      - Windows-only (PS 5.1) release downloader + verifier

The repo root is kept to entry points and config only, because GitHub renders it
first and a wall of utility scripts buries the README. Everything else lives in
build/ (dev-only, export-ignored as one line) or tools/ (ships):

loadout                     - POSIX-sh bootstrap shim; resolves portable Python 3.14 and execs loadout_main.py
loadout_main.py             - Installer body (Python 3.14, shebang `#!/usr/bin/env python3.14`)
.loadout-bootstrap/         - Per-clone Python 3.14 bootstrap cache (gitignored; created on first run when neither ~/.local nor a previous cache has python3.14)
loadout.ps1                 - Windows installation script (PowerShell)
loadout.cmd                 - Windows wrapper for loadout.ps1 with process-scoped ExecutionPolicy Bypass
loadout-pwsh-bootstrap.ps1  - Windows PowerShell 5.1 bootstrapper for bundled user-local PowerShell
README.md / CLAUDE.md / AGENTS.md, ruff.toml / ty.toml, .content-manifest,
.strip-manifest, .release-version, .gitattributes, .gitignore, .agentignore
```

## Installation Details

### Python bootstrap

`./loadout` is a **POSIX-sh shim** (~80 lines). It resolves a Python 3.14 interpreter in this order:
1. `~/.local/bin/python3.14` -- already installed via `loadout install portable-python`.
2. `<repo>/.loadout-bootstrap/bin/python3.14` -- warm bootstrap cache from a prior run.
3. Cold bootstrap: decompresses `payload/<platform>/portable-python-*.tar.bz2` into `<repo>/.loadout-bootstrap/` and uses that. Requires `bzip2` + `tar` in PATH (both ship with every supported base system).

Once an interpreter is found, the shim execs `loadout_main.py` under it. No system Python is required -- fresh extractions of the GitHub release tarball boot cleanly because the portable-python tar.bz2 is already inside `payload/` (not export-ignored).

`loadout_main.py` enforces Python >= 3.14 via a `sys.version_info` gate. The shim's bootstrap cache lives per-clone (alongside the script, not in `$HOME`) so the boot path never depends on `~/.local` existing yet. `.loadout-bootstrap/` is gitignored.

**Meld's `bin/meld` launcher is the only py3.6 holdout** -- it pins `/usr/bin/python3.6` because PyGObject <=3.30 (the last GLib-2.56-compatible version) breaks under py3.14. Independent of the loadout bootstrap; not affected by this work.

**Install behavior**: `./loadout install <PKG...>` copies files from repo -- no symlinks remain. Re-run after repo changes; most steps idempotent so re-runs fast. Installer resolves repo from script path, runs from any cwd. There is no "default install" -- users always name packages or groups explicitly (use `@engineering-loadout` for the curated bundled set). The Python copy helper intentionally replaces symlinked destination directories before syncing, refuses overlapping source/destination trees, and treats source entries that vanish mid-copy as non-fatal. This protects old layouts such as `~/.config/nvim/lsp -> ~/dotfiles/nvim/lsp`; following that symlink with delete semantics can delete the repo's `envs/nvim/lsp` files.

### Package registry (payload/packages.json)

Installer driven by typed pkg registry at `payload/packages.json` (`schema_version: 3`). Every installable thing -- binary, lib bundle, runtime archive, config bundle ("env"), font, data archive -- is named package with `kind`. Packages declare hard deps (`depends`) and soft deps (`recommends`); groups (keys starting with `@`) bundle related packages.

Package kinds: `bin`, `lib-bundle`, `runtime`, `typelib`, `python-base`, `python-tool`, `env`, `font`, `data`, `group`. Each package also has `platforms: [...]`, optional `tags`, and per-kind artifact fields (`bins`, `libs`, `wheels`, `archive`, etc.). There is no "default install" -- the user always names packages or groups explicitly (dnf/apt style).

### Resolver and CLI selection

When installer runs, `resolve_tool_selection(args, registry)` performs:
1. Parse `--skip` (groups expanded).
2. Build initial set from positional `PKG...` args (groups expanded). At least one package or group must be named; bare `install` errors.
3. Subtract `--skip`.
4. Walk hard `depends` -- if depended-upon pkg was skipped, raise `ResolverError` (unless `--no-deps` or `--force`).
5. Walk soft `recommends` -- silently drop skipped/unknown.
6. Filter by current platform (`linux`/`macos`/`windows`).

Group expansion (`expand_groups`) is recursive and cycle-detected. Synthetic groups expand at runtime (not stored in `packages.json`):

| group | set |
|---|---|
| `@shared` | every non-group, **non-`optional`** package with `kind != env` (a shared/read-only tree) |
| `@shared-all` | the same **plus** the optional ones (`surfer`, `cicwave`, `rust`, `rust-crate-store`) |
| `@envs` | `env-bash` only (plus its normal recommends): the Bash-only per-user setup |
| `@envs-all` | every `kind == env` config bundle, including optional `env-tcsh` and `env-cargo` |

**There is no bare `all`.** It used to mean "every *non-optional* package" -- the opposite of what the `-all` suffix means elsewhere -- so it was removed and now raises a `ResolverError` pointing at the replacements. Use `@engineering-loadout` for the curated bundled set (including its explicitly-listed env setup), or `@shared-all @envs-all` for literally every package and config bundle. **`optional: true` is the only optional-package gating field** (there is no `default` field): flagged shared packages install only when named explicitly, via an `-all` group, or when pulled by a group that lists them in `members` -- e.g. `surfer` (name-only), the `@rust` trio (`rust`, `rust-crate-store`, `env-cargo`, reachable via `@rust`), and `env-tcsh` (name-only or via `@envs-all`). `@envs` is intentionally narrower than the full env set: install other config bundles by name, or select `@envs-all`. Tools and env config bundles remain **fully decoupled** -- no cross-`recommends` in either direction -- so `./loadout install @shared --dest-dir ...` and `./loadout install @envs` are independent stages needing no `--skip`/`--no-deps`. All four synthetic groups surface in `list --groups` and `describe <@group>` (driven by `_SYNTHETIC_GROUPS`) despite not being registry entries.

### Subcommands

Installer uses Click/rich-click subcommands (dnf/apt verbs). Bare `loadout` and bare `loadout install` both print usage and exit non-zero. Top-level `-V` / `--version` prints the git-describe or release-stamp version and exits.

- `./loadout install <PKG...>` -- resolve + install the named packages/`@groups`.
- `./loadout reinstall <PKG...>` -- today identical to install; reserved for once persisted state lands.
- `./loadout upgrade <PKG...>` (alias `update`) -- targeted re-extract from the current checkout.
- `./loadout list [PATTERN...]` -- package table filtered by any case-insensitive name substring. `--groups` switches to group table; `--tag T` filters packages too; `--installed` is currently a stub that warns and falls back to the normal listing. Descriptions are not searched.
- `./loadout search <PATTERN>` -- case-insensitive substring search across name, description, tags.
- `./loadout info <pkg|@group>` (alias `describe`) -- kind, version, platforms, deps, recommends, reverse-deps, file lists, group memberships, full metadata dump.
- `./loadout resolve <PKG...>` -- runs resolver, prints resolved set grouped by `kind`.
- `./loadout doctor [--verify]` -- platform/registry sanity check; verifies archive paths for every `runtime`/`data`/`font`/`python-base` pkg; flags unresolved `depends`/`recommends`. `--verify` also sha256-checks every payload file against `.content-manifest`.
- `./loadout snapshot {create|restore|list}` -- manage destination snapshots (uncompressed dir or `.tar.bz2` archive).
- `./loadout clean [--logs|--pending|--all]` -- remove stale `/tmp/loadout*` state.
- `./loadout completion bash` -- print a static bash completion script (subcommands, per-verb flags, and the package/group/tag names baked in) to stdout. Regenerate the committed `envs/bash/global/completions/loadout.bash` with `./loadout completion bash > envs/bash/global/completions/loadout.bash` whenever the CLI verbs/flags or the package registry change. The completions dir is sourced at shell startup (static, not eval'd live) -- the generated script is self-contained (computes `cur`/`prev` itself; borrows bash-completion's `_filedir` only when present) and shellcheck-clean (uses `mapfile -t COMPREPLY`).

### Selection flags

- Positional `PKG...` -- install exactly these packages/`@groups` (deps still walked unless `--no-deps`). There is no bare `all`; use `@engineering-loadout` (curated bundled set) or `@shared-all @envs-all` (truly everything).
- `--skip NAMES` -- remove packages/`@groups` from install set (`install`, `reinstall`, `upgrade`, `resolve`).
- `--no-deps` -- install named set verbatim; no `depends`/`recommends` walk (`install`, `reinstall`, `upgrade`, `resolve`).
- `--force` -- continue past resolver errors (e.g. hard dep in skip set), printing `WARNING:` row instead of erroring (`install`, `reinstall`, `upgrade`, `resolve`).
- `--dry-run` -- resolve + print; no writes (`install`, `reinstall`, `upgrade`).
- `--allow-online-plugin-sync` -- allow install-like verbs to run Neovim `Lazy! restore` against the committed lockfile over the network; default uses the bundled stash/offline path (`install`, `reinstall`, `upgrade`).
- `--no-verify` -- skip sha256 verification of payload archives against `.content-manifest` (`install`, `reinstall`, `upgrade`).
- `--install-follows-symlinks [yes|no|auto]` -- choose how archive extraction treats existing directory symlinks; `auto` follows only when the target is writable (`install`, `reinstall`, `upgrade`).

### Per-phase selection gating

Each phase installer (`install_prebuilt_binaries`, `install_fonts`, `install_tldr_cache`, `install_typelibs`, `install_portable_python`, `install_treesitter_parsers`, `install_nvim_treesitter_vendor`, `install_*_runtime`, `install_python_tools`) receives `selected_tools` and short-circuits when its package(s) not in selected set. `--skip @fonts-all` short-circuits `install_fonts`; `--skip tldr-data` short-circuits `install_tldr_cache`; etc.

**env packages install config only.** An env-only selection (e.g. `./loadout install @envs`) writes nothing but `~/.config` and shell-rc text -- no binaries, libs, or nvim data. `install_prebuilt_binaries` skips entirely (including the always-on base libs) when the selection contributes no `bin`/`lib` (`_allowed_bins` and `_allowed_libs` both empty). Current Neovim phases split config from data: `install_nvim_plugin_bundle` and `install_nvim_lazy_update` gate on `env-nvim`, `install_nvim_treesitter_vendor` gates on `treesitter-parsers`, and `install_nvim_plugin_stash` gates on `nvim-plugin-stash`. `@engineering-loadout` includes all three, so a plain `./loadout install @engineering-loadout` installs the shared stash/parsers, writes nvim config, and seeds the per-user `lazy/` tree. A shared-tree-only selection that omits `env-nvim`, such as `./loadout install @shared --dest-dir ...`, installs the stash and parsers but seeds no per-user `lazy/`; install `env-nvim` in the user's env stage when the user config and seeded plugins are desired.

**Destination mode** (`--dest-dir <dir>`): per-verb option on `install` / `reinstall` / `upgrade` and the `snapshot` subcommands. Installs into alternate root instead of `$HOME`. Used by tests, useful for staging. Goes AFTER the subcommand: `./loadout install ... --dest-dir /opt/loadout/2026.06.11`. Read-only verbs (`list`, `search`, `info`, `resolve`, `doctor`, `clean`) do not accept it. **Dotted vs un-dotted tree:** the per-user dir is `.local` only when the install root is the real `$HOME`; for any other `--dest-dir` (a staged/shared tree) it is an un-dotted `local` -- dot-hiding only makes sense inside a HOME, a shared deployment is a normal filesystem location like `/usr/local`. Driven by `_local_name(home)` / `_resolve_install_to()` in `loadout_main.py`, applied to both the hardcoded `~/.local/...` joins and every `install_to: ~/.local/...` in `packages.json`. **Everything in the tree stays relocatable** (RPATH `$ORIGIN`, launcher-derived prefixes, uv-tool venvs install into the same `local/` so their shebangs bake the right path) -- so `local` works end-to-end without a post-install rename. `.config` and `.cache` are always left dotted (only written for HOME installs; an env package is never installed to a non-home dest).

**No-backup mode** (`--no-backup`): Skips backup before installing. Useful for clean reinstalls or automated use. Font install also honors this flag: instead of moving an existing `~/.local/share/fonts` to `fonts.bak*`, it reuses the directory in place and overwrites matching vendored font files.

**Skipping fonts**: Pass `--skip @fonts-all` to skip all vendored Nerd Font archives and font cache refresh. Individual families: `--skip font-firacode`, etc.

**Post-install hook** (`--post-install-hook <script>`): Runs add-on hooks after global install steps, before automatic layer `install.sh` scripts. Option can be provided multiple times; hooks run in arg order. Paths resolved before installer changes to `$HOME`; each hook must be executable with own shebang. Hook failure fails installer. Env passed: `LOADOUT_REPO`, `LOADOUT_HOME`, `LOADOUT_BACKUP_DIR` (absolute current backup dir, empty when backups skipped), `LOADOUT_DEST_DIR`, `LOADOUT_NO_BACKUP`.

**Install result behavior**: Before each install area writes files, installer verifies target dir writable. If not, refuses that area with warning, records failed row, continues with later areas. Output is package-manager style -- only what was actually done plus problems, never what was skipped. Phases that no-op (not selected / no artifact) print nothing: `skipped()` is silent and `record_result(..., "SKIP")` rows are omitted from the final table. There are no per-phase "Installing X..." banners; phases that do work print their own concise line. The run ends with a `Summary` table of `done`/`FAILED` areas (skips excluded; silent areas hidden unless they FAIL) followed by `Complete.` or `Completed with N problem(s)`; the `Processes Blocking Installation` table (ETXTBSY) and `--no-backup` data-loss warning still print as problems.

**Font behavior**: Extracts vendored fonts from `payload/fonts/*.zip` into `~/.local/share/fonts`. Large archives stored as split chunks `*.zip.part-000`, `*.zip.part-001`, etc.; use 45 MiB chunks to stay below GitHub's 50 MB warning. Installer rejoins under `/tmp/loadout-fonts.*` before extraction. If `~/.local/share/fonts` already exists, normal installs move it aside to `fonts.bak*` before extracting; `--no-backup` reuses it in place so no font backup is created. Extraction counts actual font members and displays a Rich progress bar like other bulk install phases; non-Rich fallback prints each archive. Generates `fonts.scale`/`fonts.dir` when `mkfontscale`/`mkfontdir` present, refreshes fontconfig with `fc-cache`. Font discovery fontconfig-first for normal Linux desktop apps, WSLg, RHEL/Alma 8. Do not add `xset +fp` startup logic; X core font paths can fail when `$HOME` not traversable by X server. Windows Terminal reads fonts from Windows, not WSL fontconfig.

**Pre-built binary behavior**: Installer selects `payload/<platform>/` based on OS family, architecture, libc. Preferred platform names exact and ABI-oriented, e.g. `el8.x86_64.glibc2p28`. Files under `bin/*.bz2` decompressed to `~/.local/bin`, marked executable. Files under `lib64/*.bz2` decompressed to `~/.local/lib64`. All bz2 decompression uses `write_bz2_atomic` (temp file in same dir + `os.rename`) -- prevents SIGBUS when running Python has memory-mapped a shared lib being overwritten. RPATH (`$ORIGIN/../lib64:$ORIGIN/../lib`) pre-baked into each binary before bzip2 compression in repo (see `build/repatch-binaries` and `ADDING_BINARIES.md`), no post-install patchelf needed -- installer is pure decompress + chmod. `$ORIGIN` is runtime-relative token resolved by `ld.so` at load time, so baking it in repo is identical to setting it post-install. If running binary like `tmux` cannot be replaced, installer continues and prints final retry notice. Then runs `ldd` on installed binaries, warns about missing `.so` deps. Tcl/Tk 9 shared libraries (`libtcl9.0.so`, `libtcl9tk9.0.so`) embed their script libraries via zipfs; do not strip those shared libs, only patchelf RPATH then bzip2. If no exact platform exists, installer may use compatible same-arch glibc build whose glibc version not newer than host. The installer body (`loadout_main.py`) runs under bundled Python 3.14, resolved by the POSIX-sh `loadout` shim; all subprocess calls use absolute paths (`_LDD`, `_UNAME`, `_GETCONF` resolved at startup via `_find_tool()`) to prevent accidentally picking up binaries being installed. **Never bundle these libs:**
- **glibc components** (`libc.so.6`, `libm.so.6`, `libpthread.so.0`, `libdl.so.2`, `librt.so.1`) -- must match system's `ld-linux.so.2` exactly; version mismatch produces `undefined symbol: ..., version GLIBC_PRIVATE` crashes. Every EL8 target already has glibc 2.28.
- **OpenGL dispatcher** (`libGL.so.1`, `libGLX.so.0`, `libGLdispatch.so.0`) -- must be system's display-driver-linked version; bundling causes crashes or wrong driver selection. Bundling Mesa's vendor/runtime side (`libEGL_mesa`, `libgbm`, `libglapi`, DRI drivers, GLVND JSON) is allowed when wrappers force `LD_LIBRARY_PATH`, `LIBGL_DRIVERS_PATH`, and `__EGL_VENDOR_LIBRARY_DIRS`.
- **C++ runtime** (`libstdc++.so.6`, `libgcc_s.so.1`) -- present on all EL8 systems; version mismatches with C++ code subtle and hard to diagnose. Run `./build/strip-all-elf-binaries` after adding binaries, libs, parser grammars, or tar archives. Strips raw ELF files in place, strips ELF payloads inside standalone `.bz2`, rewrites tar archives as `.tar.bz2`; processed tarballs skipped on later runs when size and mtime match strip manifest. Non-ELF `.bz2` payloads (e.g. `vim.bz2` shell wrapper) recorded in `.strip-manifest` after first check, skipped as manifest hits subsequently. Archives matching `NOSTRIP_ARCHIVE_PREFIXES` (currently `portable-python-*`) completely skipped -- BOLT-optimized binaries must not be touched.

**nvim plugin stash delivery (release asset, not a git payload)**: the stash is **not committed to git** -- it is 328 MB of bz2'd packfiles, so committing it would add ~328 MB on every refresh and make ordinary Git clone history grow. It ships as a **GitHub release asset**, gitignored locally, and `build/gen-content-manifest` excludes it explicitly (it is usually present on a build box; hashing it into the committed manifest would break `--check` for everyone who has not fetched it).

**Trust chain -- do not shortcut it:** `signed tag -> sha256sums.txt (release asset) -> stash bytes -> .content-manifest.fetched`. `.content-manifest` is a strict allowlist (`_verify_source_files` hard-errors on any payload file with no manifest entry, deliberately). `./tools/fetch-stash` is the **only** thing that may add the stash to `.content-manifest.fetched`, and only after the bytes match the sha256 published in the release; a mismatched file is **deleted**, never left on disk. `_load_content_manifest` loads both manifests and trusts them identically, so the allowlist property survives.

Three acquisition paths, because the network policy is dynamic:

| situation | command |
|---|---|
| the box can reach github | `./tools/fetch-stash` (latest release) or `./tools/fetch-stash --tag vX` |
| github blocked; file brought in by hand | `./tools/fetch-stash --from-file <stash> --sums <sha256sums.txt>` -- still verified |
| Windows-only (no WSL/VMs allowed) | `tools/download-release.ps1` (PS 5.1, no admin, no modules) downloads + verifies, then `scp` |

**`./tools/refresh-stash <stash-dir>` decouples plugin cadence from loadout cadence**: run it where the shared filesystem is R/W and github is reachable (it only ever clones/fetches -- never pushes, so a "clone/pull only" policy suffices). It updates the bare mirrors **in place** in the shared tree; air-gapped users then get the new plugin versions on their next `:Lazy update`, with **no new loadout release and nothing re-deployed**. It refuses to run against a read-only mount (the air-gapped side) with a message saying so. Fresh installs still clone at the `lazy-lock.json` pins, so refresh the lockfile + cut a release when you want the *default* set to move too.

With **no stash present**, nvim installs and works; the plugin phase is skipped with a **loud** warning naming `./tools/fetch-stash` (it must never be silent -- the user would otherwise get an empty editor with no explanation). A stash that is present but in **no** manifest is refused with a content-verification message, not a traceback.

**nvim plugin/parser deployment behavior (two-tier + offline git stash)**: nvim resolves *everything* from `stdpath("data")` = `$HOME/.local/share/nvim`, so anything in a shared tree is invisible to it unless the config looks there. `envs/nvim/lua/global/paths.lua` (`paths.data(rel)`, `paths.stash()`, `paths.ensure_git()`) resolves each nvim dir **user-copy-first, shared-tree-second** via `LOADOUT_CFG_SHARED_PREFIX`; `treesitter.lua` and `init.lua` go through it.

| artifact | tier | why |
|---|---|---|
| `loadout/vendor/plugin-stash` (79 full bare mirrors, 328 MB) | **shared** (`nvim-plugin-stash`, `kind: data`) | read-only library, installed once per tree (a user with an unconstrained HOME can hold it there instead -- `paths.data` prefers the user copy) |
| `tree-sitter-parsers` (251 MB) | **shared** (`treesitter-parsers`) | read-only; per-user copies would cost ~2.5 TB across 10k users |
| `lazy/` (active plugins) | **per-user** (`env-nvim`) | real git clones; `:Lazy update` writes here |

The stash is **bare git mirrors**, not plain directories: `<stash>/folke/snacks.nvim.git`. `init.lua` sets lazy's `git.url_format` to point at it, so lazy **clones from the stash** and `:Lazy update` / `:Lazy restore` **fetch from it with no network**. Before this, plugins shipped as plain dirs with no `.git` (the pre-commit hook strips embedded `.git` dirs), so `:Lazy update`/`sync` were silent no-ops and `lazy-lock.json`'s pins were decorative. The installer clones only the **24 pinned (active)** plugins into the user's `lazy/`; the **55 catalog** plugins (`plugins/catalog.lua`, all `enabled = false`) stay in the stash until a user enables one, at which point lazy clones it **from the stash, offline**. Build with `build/build-nvim-plugin-stash`, which does `git clone --mirror` -- **all refs, including TAGS**. That is deliberate and non-negotiable: `--single-branch` omits tags, so any lazy spec pinning `version`/a tag silently fails to resolve, and a **shallow** mirror is worse than useless (git cannot serve a partial clone from one -- the clone HANGS forever, freezing nvim at startup when a catalog plugin is enabled). It is shared space; spend the disk. The builder verifies every pinned commit is reachable and runs the content heuristics on the checked-out trees (a bare mirror hides source inside packfiles where YARA cannot see it).

**`git.filter = false` is load-bearing.** lazy defaults to `--filter=blob:none` (a partial clone), and **git cannot serve a partial clone from a shallow local mirror -- it hangs forever**, so enabling any catalog plugin would freeze nvim at startup. A partial clone buys nothing from a local path anyway (git hardlinks the objects). Never remove it while the stash is in use.

**git is required, and must never land on the user's PATH.** The loadout does not install `bin/git`: a loadout git would shadow the corp git and silently break its subcommands, credential helpers and git-lfs -- the same failure the openssh package documents (it ships `ssh10` and lets `/usr/bin/ssh` win). `_resolve_git()` uses the system git, else the optional private `git-nvim` package under `lib/loadout-git/bin/git`, which `paths.ensure_git()` prepends to **nvim's** `vim.env.PATH` only when the system has none. With no git anywhere, the plugin phase fails loudly and nvim core still starts.

`install_nvim_plugin_bundle` is gated on **`env-nvim`**, not on the data package: gating it on the shared-tree package meant a split deployment seeded `lazy/` into the *shared tree*, where nvim never looks, and `$HOME` got nothing -- the air-gapped `lazy.nvim unavailable; plugin setup skipped` failure. `tests/install-nvim-deployments` covers both shapes with the network blackholed and asserts: real git clones, origin = the stash, HEAD = the lockfile pin, `git fetch` works offline, the catalog stays opt-in, and enabling a catalog plugin installs it offline.

**Tree-sitter parser behavior**: Offline support targets Neovim v0.12+ only. Installer copies vendored `nvim-treesitter` and `treesitter-parser-registry` into `~/.local/share/nvim/loadout/vendor/`, looks for prebuilt artifacts under `payload/treesitter/prebuilt/$(uname -s lower)-$(uname -m)-<glibc|musl>/`, decompresses `parser/*.so.bz2` to `parser/*.so`, copies `parser-info/`, `queries/`, `registry/`, `build-info/` into `~/.local/share/nvim/tree-sitter-parsers/`. Neovim appends that parser dir to `runtimepath`, starts native Tree-sitter on filetype buffers. Build all supported parsers with `./build/treesitter/build_parsers`; prebuilt `.so.bz2`, parser-info, queries, registry cache, `build-info/*.env` tracked.

**tldr cache behavior**: `./build/update tldr-data` writes `payload/tldr/tldr-pages.tar.bz2` for offline tealdeer. Installer accepts `.tar.bz2` and legacy `.tar.gz`, replaces existing pages under the loadout local-root at `<localroot>/share/tealdeer/cache/tldr-pages` (`_resolve_install_to`: `~/.local/...` for HOME, un-dotted `local/...` for `--dest-dir`) unless `--skip tldr-data`; `./build/strip-all-elf-binaries` normalizes tar archives to bzip2. The cache is NOT in `~/.cache` -- `install_tealdeer_config` (env-side) writes `~/.config/tealdeer/config.toml` with an absolute `cache_dir` (tealdeer does not expand `~`/env; the deprecated `TEALDEER_CACHE_DIR` env var is avoided). When `LOADOUT_CFG_SHARED_PREFIX` is set, both the extract target and `cache_dir` resolve under it, so a separately-installed `@shared` tree and a per-user `@envs` run agree on one cache location. tealdeer 1.8.1 has no config key to silence the "cache is N days old" nag (hardcoded `MAX_CACHE_AGE`; only `--quiet` suppresses it).

**Helix runtime behavior**: Installer extracts `helix.tar.bz2` from `payload/<platform>/runtime/` into `~/.local/share/helix/`, replacing existing `~/.local/share/helix/runtime`. Correct install has `~/.local/share/helix/runtime/tutor`. Archive contains `./runtime/...`, extracts directly to `~/.local/share/helix/`.

**Vim runtime behavior**: Installer extracts `vim92.tar.bz2` from `payload/<platform>/runtime/` (archive name read from the registry `archive` field) to `~/.local/share/vim/`, renames `runtime/` to `vim92/`, verifies `filetype.vim` present. Correct install has `~/.local/share/vim/vim92/filetype.vim`. Vim/GVim wrappers derive their default `VIM`/`VIMRUNTIME` from the installed launcher path (`bin/..` -> install prefix), not `$HOME`, while preserving explicit user overrides; this keeps `--dest-dir` installs runnable with fake `HOME`.

**Neovim runtime behavior**: Installer looks for `nvim.tar.bz2` in `payload/<platform>/runtime/`. Extracts to `~/.local/share/nvim/`, replaces existing `~/.local/share/nvim/runtime`, verifies `runtime/filetype.lua` present. Release smoke gate runs installed `nvim` headless with `--clean`, asserts this runtime on `runtimepath`. Neovim config bootstraps `lazy.nvim` when available; if `lazy.nvim` missing and `git` cannot clone it, plugin layer disabled cleanly so core editor config still starts on locked-down machines.

**Octave runtime behavior**: Installer looks for `octave.tar.bz2` in `payload/<platform>/runtime/` only when `octave` in selected tools (part of the `@shared` sweep; install alone with `./loadout install octave`). Archive contains `./share/octave/11.3.0/` (m-files, fonts, data; doc excluded) and `./lib/octave/11.3.0/oct/` (.oct compiled plugins, patchelf'd to RPATH `$ORIGIN/../../../../../lib64`). Extracts into `~/.local/`, verifying `~/.local/share/octave/11.3.0/m/` present. Three octave core libs (`liboctave.so.13`, `liboctinterp.so.15`, `liboctmex.so.1`) bundled separately as `lib64/*.bz2` with RPATH `$ORIGIN`. Main binary `octave` is thin 16K launcher with RPATH `$ORIGIN/../lib64`. Total uncompressed ~163 MB, dominated by libopenblas + libopenblasp (~110 MB combined). Build with `build/build-octave.sh --tag <VERSION>` from an extracted source tarball; the script is version-scoped (install prefix `/tmp/octave-install-<VERSION>`) so successive builds cannot contaminate each other, and every versioned path in the registry entry (`version`, `sentinel`, the three `octave/<VERSION>` paths) must be bumped with it.

**gui_libs behavior**: `gui_libs` lib-bundle pkg (in the `@shared` sweep) bundling ~80 shared libs covering Qt5 5.15.3, GTK3 3.22, ICU 60, cairo, pango, glib2, xcb extensions, xkbcommon, Wayland client, X11 client libs. Install with `./loadout install gui_libs` or name it alongside GUI apps (for example `./loadout install gui_libs gvim nedit-ng`). Targets **headless compute farm / LSF nodes** lacking GUI libs but running GUI tools with `DISPLAY` forwarding. All gui_libs `.so` files patchelf'd with RPATH `$ORIGIN` (not `$ORIGIN/../lib64`). Qt5 XCB and Wayland platform plugins (`libqxcb.so`, `libqwayland-generic.so`) stored **flat in `~/.local/lib64/`**. `envs/bash/global/bashrc` sets `QT_QPA_PLATFORM_PLUGIN_PATH=$HOME/.local/lib64` when `libqxcb.so` present -- Qt finds platform plugin there directly. **WSLg / XWayland cursor corruption**: Qt5 XCB backend sends blank/null cursor on window entry, corrupting XWayland's global cursor state for all subsequent X11 apps. Fix: set `QT_QPA_PLATFORM=wayland` in `~/.config/bash/user/bashrc`. Routes Qt5 through Wayland compositor, bypassing XWayland for cursor management. Wayland backend requires `libqwayland-generic.so` + `libQt5WaylandClient.so.5`, both in gui_libs.

**mesa3d_libs behavior**: `mesa3d_libs` runtime pkg bundles the Mesa userspace vendor side from the system install: `libEGL_mesa.so.0`, `libgbm.so.1`, `libglapi.so.0`, DRI drivers under `~/.local/lib64/dri/`, `libLLVM-17.so`, libdrm helpers, and `share/glvnd/egl_vendor.d/50_mesa.json`. It deliberately does **not** bundle `libGL.so.1`, `libGLX.so.0`, or `libGLdispatch.so.0`; those remain host/display-driver dispatchers. Archive is large and chunked (`mesa3d_libs.tar.bz2.part-000..002`). `./loadout install wezterm` pulls `mesa3d_libs` through depends. Build with `build/build-wezterm.sh --tag <wezterm-version>` from the system Mesa/WezTerm install, then run `./build/strip-all-elf-binaries`. Wrappers using this runtime must prepend `<prefix>/lib64` to `LD_LIBRARY_PATH`, set `LIBGL_DRIVERS_PATH=<prefix>/lib64/dri`, and set `__EGL_VENDOR_LIBRARY_DIRS=<prefix>/share/glvnd/egl_vendor.d`.

**WezTerm runtime behavior (shanghai bundle)**: WezTerm `20260618_095146_c10636f3` is bundled from `/usr/bin/wezterm`, `/usr/bin/wezterm-gui`, `/usr/bin/wezterm-mux-server`, `/usr/bin/strip-ansi-escapes`, and `/usr/bin/open-wezterm-here` by `build/build-wezterm.sh`. Archive is chunked as `wezterm.tar.bz2.part-000..001`. Bundle extracts to `~/.local/` and installs PATH wrappers at `bin/wezterm`, `bin/wezterm-gui`, and `bin/wezterm-mux-server`; real upstream sibling binaries live under `lib/wezterm/` with RPATH `$ORIGIN/../../lib64:$ORIGIN`. Runtime also carries the desktop file, metainfo, app icon, and Nautilus extension. Keep the real binaries as siblings: `wezterm start` resolves and execs `wezterm-gui` next to the real `wezterm` binary. The wrapper derives prefix from installed `bin/..`, prepends Mesa lib paths, points GLVND at the bundled Mesa JSON, keeps the local portal restart workaround from `~/.local/bin/wezterm`, and execs `lib/wezterm/wezterm`. It is the sample app for `mesa3d_libs`; install with `./loadout install wezterm` or `@gui-suite`. Shell **completions** are env-owned: zsh uses `envs/zsh/site-functions/_wezterm`, and bash can generate dynamically with `wezterm shell-completion --shell bash`. Shell **integration** (OSC 133 semantic zones / OSC 7 cwd / user vars -- a *different* thing from completion) is NOT shipped in this runtime archive; it is vendored separately at `envs/bash/global/wezterm/wezterm.sh` and sourced by `envs/bash/global/bashrc` from user-writable space (never `/etc/profile.d/wezterm.sh`). See *Bash Configuration Architecture -> Prompt & shell integration*.

**Portable Python behavior**: Installer looks for `portable-python-*.tar.bz2` in platform dir. If found, extracts to temp dir under `/tmp` via `safe_extract_tar`, runs bundled `install.sh --prefix ~/.local --force --no-test`. Generic `python3`/`pip3` links left in place, so `python3` on PATH resolves to 3.14. Base-install protection: `envs/pip/pip.conf` installed to `~/.config/pip/pip.conf` with `require-virtualenv = true`, `PIP_REQUIRE_VIRTUALENV=1` exported from `envs/bash/global/bashrc` -- guard against accidental `pip install` to base env. Use `python3.14` and `pip3.14` for this build. Archive must never run through `strip-all-elf-binaries` (BOLT-optimized). To add/update portable Python: `build/import-portable-python <portable-dir>`.

**Python tool behavior (uv tool)**: PyPI tools that are Python-only or have manylinux binary wheels installed via `uv tool install` into per-tool isolated venvs at `~/.local/share/uv/tools/<tool>/`. Launchers auto-created at `~/.local/bin/`. Wheels bundled offline in `payload/<platform>/wheels/`. Installer runs `uv tool install <pkg> --python ~/.local/bin/python3.14 --no-index --find-links <wheels_dir> --no-cache` for each selected tool with `"uv_tool"` key in `packages.json`. A `"uv_extras": ["name", ...]` field turns that requirement into `<pkg>[name,...]`; bundle the complete locked closure for every listed extra, not just the base package. If no matching base wheel found in `wheels_dir`, tool skipped with warning. To add new Python tool: (1) bundle wheels with `PIP_REQUIRE_VIRTUALENV=0 pip3.14 download <pkg> --platform manylinux_2_28_x86_64 --platform manylinux2014_x86_64 --platform manylinux2010_x86_64 --platform manylinux1_x86_64 --platform any --python-version 3.14 --only-binary :all: -d payload/<platform>/wheels/` (pass EVERY acceptable tag -- see the exact-tag-match warning below); (2) add `packages.json` entry with `"uv_tool"`, `"wheels"`, optionally `"uv_extras"`, `"libs"` / `"typelibs"` / `"optional": true`; (3) add required C libs to `lib64/*.bz2` and typelibs to `typelibs/`. **EL8 wheel compatibility:** EL8 sits at the lower boundary of the current cibuildwheel default (manylinux_2_28) -- wheels targeting manylinux_2_29+ (RHEL9) will not run on EL8. **`pip --platform` matches wheel tags EXACTLY; it does not imply older, still-compatible tags.** A single `--platform manylinux_2_28_x86_64` therefore silently misses a `manylinux1`/`2010`/`2014` wheel that runs perfectly on EL8, and pip reports the version as simply unavailable -- `kaleido==0.2.1` was mis-diagnosed as gone from PyPI exactly this way (it is a `py2.py3-none-manylinux1_x86_64` wheel). Pass every acceptable tag when a package may ship an older one:
`--platform manylinux_2_28_x86_64 --platform manylinux2014_x86_64 --platform manylinux2010_x86_64 --platform manylinux1_x86_64`.
So an `--only-binary :all:` failure means "no wheel for the tags you asked for", NOT "no wheel exists" -- widen the tags before concluding the package must be built from source on the EL8 machine.

**Version conflicts between python-tools are a non-issue.** `uv tool install` gives each tool its own venv (pipx/uvx semantics), and the shared `--find-links` wheelhouse already carries several versions of the same dependency side by side (`anyio`, `click`, `fastapi`, `platformdirs`, `pyarrow`, `polars_runtime_*`). Two tools pinning different majors of the same package -- e.g. `kaleido==0.2.1` for one and `1.3.0` for another -- coexist fine; the only cost is payload weight. Do not ask a first-party project to re-pin for "compatibility" with another bundled tool.

**OpenSSH package behavior**: `openssh` is optional and exists mainly for `ssh-keygen -Y sign` on EL8, where stock OpenSSH 8.0 lacks the `-Y` signer used by git SSH signing. It deliberately does **not** install bare `ssh`, `scp`, or `sftp`: mainline OpenSSH 10.x rejects Red Hat crypto-policy's `GSSAPIKexAlgorithms`, so a PATH-visible loadout `ssh` breaks RHEL host-integrated SSH. The package owns `ssh10` (wrapper), `ssh10.bin` (real ELF), `ssh-keygen`, `ssh-add`, `ssh-agent`, and `ssh-keyscan`. `ssh10` runs `ssh10.bin` with `-F ~/.ssh/config` when present, otherwise `-F /dev/null`, unless the caller supplied `-F`. Any later binary install removes old loadout-owned `~/.local/bin/{ssh,scp,sftp}` by exact payload hash so system `/usr/bin/ssh` wins again. **Known limitation**: the libexec helpers (`ssh-sk-helper`, `ssh-pkcs11-helper`, `ssh-askpass`) are not bundled and the binaries reference them at a dead build prefix, so FIDO security keys (`ssh-keygen -t ed25519-sk`) and PKCS#11 tokens do not work through the loadout binaries -- use the system OpenSSH for those. Build/update with `build/build-openssh.sh`; do not reintroduce bare ssh/scp/sftp artifacts.

**Environment Modules runtime behavior**: `modules` is a pure-Tcl runtime which hard-depends on loadout `tcl`. Modules 5.6.1 has no Unix relocatable configure mode, so the build uses a distinctive ASCII placeholder prefix (`/__LOADOUT_RELOC_ROOT__`) and ships the **full upstream `make install` tree** rooted at `~/.local/lib/modules/`: `bin/`, `etc/`, `init/{bash,csh,fish,ksh,sh,tcsh,zsh}`, `lib/` (with `libtclenvmodules.so` built against loadout Tcl 9), `libexec/modulecmd.tcl`, `modulefiles/`, and `share/`. The installer's generic runtime relocation step (`relocate_token` + `relocate_root` registry fields) replaces the token with the deployed local root in every text file under `lib/modules`, asserts zero tokens remain, and rejects any token found in an ELF or NUL-containing file. Users select this install the standard way: `source <local>/lib/modules/init/<shell>`. `envs/bash/global/modules-init.bash` is now a thin selector that resolves `${LOADOUT_CFG_SHARED_PREFIX:-$HOME/.local}/lib/modules/init/bash`, unaliases `module`/`_module_raw`/`ml` (bash alias-parse rule), clears stale `MODULESHOME`/`MODULES_CMD`, and sources the native init; it does **not** set a default `MODULEPATH` (upstream init preserves a caller/site-selected one). Shell integration is opt-in with `LOADOUT_CFG_USE_LOADOUT_MODULES=1`; split `@shared` + `@envs` installs resolve through `LOADOUT_CFG_SHARED_PREFIX`. Do not call `libexec/modulecmd.tcl` directly. Build with `build/build-modules.sh --tag v5.6.1 --with-tcl <loadout-tcl-libdir>`; validate a fresh install with `tests/install-modules` (sources `init/bash` and `init/sh` unconditionally, and `init/{ksh,zsh,csh,tcsh}` when their interpreters are present, each doing a real `module load`/`unload`) and the split deployment with `tests/install-split-shared-envs` (drives `init/{bash,zsh,fish}` through the loadout's own bundled shells). Tier 3 container smoke installs `tcsh` + `ksh` (so `init/csh`, `init/tcsh`, and `init/ksh` get real coverage) and runs the modules fresh-home smoke via `tests/prebuilt-binaries-almalinux8 --full`.

**expect behavior**: `bin/expect` is a POSIX-sh wrapper (`build/expect/expect`) that execs `lib/expect/bin/expect.bin`; the Tcl 8.6 script library ships at `lib/expect/lib/{tcl8.6,tcl8}` so Tcl's own `<exedir>/../lib/tcl8.6` fallback resolves inside that private prefix (the ELF's compiled `tcl_library` is a dead temp build prefix). Two load-bearing constraints: **never install the trees to `<prefix>/lib/tcl8.6`** (portable-python owns that path at a different Tcl patchlevel; `init.tcl` does `package require -exact`, so cross-clobbering breaks one side), and **never export `TCL_LIBRARY`** (expect spawns child processes for a living; the variable would pin every spawned Tcl program, including the bundled Tcl 9 `tclsh`, to the wrong script library). `Tcl_Init failed` / `Can't find a usable init.tcl` are fatal probe output in `tests/prebuilt-binaries`. Build with `build/build-expect.sh --tag 5.45.4`; it stage-verifies with the temp Tcl prefix renamed away so the fallback path is actually exercised.

**ngspice behavior**: `ngspice` is packaged gvim-style: `bin/ngspice` (POSIX-sh wrapper from `build/ngspice/ngspice`) + `bin/ngspice.bin` (real ELF), with `runtime/ngspice.tar.bz2` carrying `share/ngspice/` (spinit + scripts) and `lib/ngspice/` (XSPICE `*.cm` + OSDI `*.osdi` codemodels). The ELF embeds its temp configure prefix (`NGSPICEDATADIR`), so the wrapper exports `SPICE_LIB_DIR=<prefix>/share/ngspice` (spinit discovery; user override wins) and passes `-D loadout_cmdir=<prefix>/lib/ngspice`; the packaged spinit loads codemodels via `$loadout_cmdir`, guarded by `if ... & $?loadout_cmdir` so direct `ngspice.bin` runs stay silent. Registry sentinel is `lib/ngspice/analog.cm`. Never smoke ngspice with `--version` alone -- a dead datadir is silent (plain analyses still work); `tests/prebuilt-binaries` runs an XSPICE `gain` netlist and asserts `V(2)=2`. Build with `build/build-ngspice.sh --tag ngspice-46`; the script fails if spinit retains the temp prefix or the staged tree cannot load `analog.cm`.

**VCD toggle profiler runtime behavior**: `vcd-toggle-profiler` is a C++17 runtime package built from `github.com/smprather/vcd-toggle-profiler` (C++ implementation only). The archive `payload/<platform>/runtime/vcd-toggle-profiler.tar.bz2` extracts to `~/.local/` and installs `bin/vcd-toggle-profiler` (POSIX-sh wrapper), `lib/vcd-toggle-profiler/vcd-toggle-profiler.bin` (real ELF), `share/vcd-toggle-profiler/uplot/{uPlot.iife.js,uPlot.min.css}`, and license files. The wrapper derives its prefix from its installed path and supplies `--uplot-js/--uplot-css` defaults so report generation works from any current directory while still allowing explicit user overrides. Build with `build/build-vcd-toggle-profiler.sh --rev <git-ref>` or `--source <checkout>`; it deliberately uses EL8 system `/usr/bin/g++` 8.5 with `-lstdc++fs`, not upstream CMake Release (`-march=native`), keeping the deployed binary portable across farm CPUs and capped at `GLIBCXX_3.4.21`. `pigz` is recommended so `.vcd.gz` input uses the bundled fast gzip path when available. Re-run `./loadout completion bash > envs/bash/global/completions/loadout.bash` after changing the package registry.

**Surfer behavior**: `surfer` is an `optional` (name-only) `bin` package -- a Rust egui/**glow (OpenGL)** waveform viewer (VCD/FST/GHW). Built from the latest stable tag on EL8 by `build/build-surfer.sh --tag vX.Y.Z` (native glibc-2.28; release profile has no `-march=native`). Packaged gvim-style: `bin/surfer.bz2` (POSIX-sh wrapper) + `bin/surfer.bin.bz2` (stripped ELF, RPATH `$ORIGIN/../lib64`). The wrapper mirrors wezterm's GL block (prepends `<prefix>/lib64` to `LD_LIBRARY_PATH`, sets `LIBGL_DRIVERS_PATH`/`__EGL_VENDOR_LIBRARY_DIRS`) before exec'ing `surfer.bin`. `depends: [gui_libs, mesa3d_libs]`; the ELF NEEDs only glibc + libgcc_s, winit/glow **dlopen** libGL/X11/wayland/xkbcommon at runtime (GLVND dispatcher stays host-provided, never bundled). Install: `./loadout install surfer` (auto-pulls gui_libs + mesa3d_libs). `surfer server` is a built-in headless mode. Build quirks (in `ADDING_BINARIES.md`): the v0.7.0 tag vendors f128 + instruction-decoder as **git submodules** (clone `--recurse-submodules`); the loadout's offline `~/.cargo/config.toml` registry-store must be bypassed with a fresh `CARGO_HOME`.

**GTKWave behavior**: `gtkwave` (`kind: bin`, member of `@eda`, `depends: [gui_libs]`) is the GTK3 waveform viewer plus the 16-tool batch converter suite (`fst2vcd`, `vcd2fst`, `vcd2vzt`, `vzt2vcd`, `vcd2lxt{,2}`, `lxt2vcd`, `*miner`, `evcd2vcd`, `xml2stems`, `twinwave`, `rtlbrowse`, `shmidcat`). Built from the **`gtkwave3-gtk3/` subdir** of the tag (`gtkwave3/` is the GTK2 tree; `master` is the unreleased GTK4 rewrite and GTK4 is not bundled). **It ships with NO wrapper, and that is a verified invariant**: nothing in the install embeds the configure prefix -- `share/gtkwave-gtk3/` holds only docs/examples, the `.desktop` file uses a bare `Exec=gtkwave`, and `twinwave` finds gtkwave via `execvp()` from PATH -- so `build/build-gtkwave.sh` greps every binary and every `share/` file for the prefix and hard-fails if a future release bakes one in. Do not weaken that guard; add a prefix-deriving wrapper instead. `--disable-tcl` is deliberate: gtkwave's Tcl layer (`gtkwave -S script.tcl`) would need a second tcl8.6 script library in a tree where portable-python already owns `lib/tcl8.6` at a different patchlevel (the `expect` hazard). Only new system assumption is `liblzma.so.5` (EL8 base, `rpm` itself links it). The 1.7 MB ODT manual is excluded from the runtime archive; the man pages are kept and man-db finds them with no `MANPATH` change. **Never smoke it with `--version` alone** -- `rtlbrowse`/`shmidcat`/`twinwave` have no version flag and exit 255 printing `Could not open '--version'`, which the generic probe scores as OK; `tests/prebuilt-binaries` round-trips the shipped `examples/des.fst` through FST->VCD->FST instead.

**Verilator behavior**: `verilator` (`kind: bin`, member of `@eda`) is a lint/coverage/regression tool, not a commercial-simulator replacement. **No wrapper needed**: upstream's Perl driver resolves `VERILATOR_ROOT` itself from `realpath("$RealBin/../share/verilator")`, and `build/build-verilator.sh` proves it by copying the staged tree elsewhere and running a full RTL->C++->`g++`->execute cycle there. The only non-relocatable artifact is `share/pkgconfig/verilator.pc`, handled with `relocate_token`/`relocate_root: share/pkgconfig` (the `modules` mechanism). **Nothing is bundled**: `verilator_bin` links only libpthread/libm/libc because Verilator builds `-static-libstdc++ -static-libgcc`, so there is no `GLIBCXX_*` requirement at all -- the build script *asserts* that stays true, since a dynamic libstdc++ would come from gcc-toolset-14 and break on stock EL8. **Host requirements the loadout does not satisfy**: `perl` (the driver and `verilator_coverage` are Perl -- both are in `HOST_REQUIRED_COMMANDS` in `tests/prebuilt-binaries`, same call as `cloc`) and the user's own `g++` to compile the generated model (EL8 system g++ 8.5 suffices). **`verilator --debug` is unavailable on purpose**: `verilator_bin_dbg` is 104 MB and only debugs Verilator itself. `help2man` is a build prerequisite -- without it `make` dies with exit 127 building man pages.

**KLayout behavior**: `klayout` (`kind: bin`, member of `@eda`, `depends: [gui_libs, mesa3d_libs, ruby, portable-python]`) is the GDSII/OASIS/DXF/CIF/LEF-DEF layout viewer/editor with scriptable DRC/LVS. **This is what the `ruby` package exists for.** KLayout installs *flat*, so the whole tree ships as `lib/klayout/` and `bin/` gets 13 copies of `build/klayout/klayout` that dispatch on their own basename (`klayout` + the 12 `strm*` converters). Four traps, each silently fatal: **(1)** ruby headers come from RPMs fetched **by direct URL** from the ruby:3.3 stream -- never `dnf module enable ruby:3.3`, which would replace the build box's system ruby; probing that interpreter needs `--disable-gems` or it loads EL8's 2.5 rubygems and dies. **(2)** `LD_LIBRARY_PATH` must point at portable-python's `lib` **at build time**: libklayout_pya.so links fine, but the `strm*` executables linking `-lklayout_pya` cannot resolve its transitive `libpython3.14.so.1.0` and the build dies with ~200 `undefined reference to 'PyList_GetItem'` after 20 minutes. **(3)** the launcher must export **`KLAYOUT_PYTHONHOME`, not `PYTHONHOME`** -- `src/pya/pya/pya.cc` deliberately unsets the latter, and without the former the embedded interpreter aborts with `Fatal Python error: Failed to import encodings module`. **(4)** `RUBYLIB` must include `share/rubygems` as well as `lib64/ruby:share/ruby`, or `gem_prelude` reaches `/usr/share/rubygems` and dies with `ruby lib version (2.5.9) doesn't match executable version (3.3.10)`. Qt `uitools`/`designer`/`multimedia`/`sql` are off (libs not bundled; cost is that macros cannot load `.ui` files), but **`-without-qt-xml` is NOT an acceptable shortcut** -- `.lyp` and `.lym` files are XML and there is no other parser, so `HAVE_QT_XML` stays on and `libQt5XmlPatterns.so.5` was added to `gui_libs`. `-nolibgit2` disables the network-dependent Salt package manager. Archive is ~53 MB and chunked. Standalone `import klayout` needs `PYTHONPATH=<prefix>/lib/klayout/pymod`; the embedded interpreter needs nothing. **Host GLVND is required even for batch use**: the `strm*` converters link the same `libklayout_lay`/`laybasic` set as the GUI, so a node with no OpenGL runs nothing in this package -- not `klayout -zz`, not `strm2gds` (EL8 supplies it via `mesa-libGL`; same contract as nedit-ng/nvim-qt/flameshot/Xephyr, but stronger because the batch tools inherit it). `tests/prebuilt-binaries` therefore resolves a wrapper's real ELF through `lib/*/<name>` as well as `bin/<name>.bin`, or these 13 launchers report a hard 127 in the clean container instead of skipping. **`klayout -v` proves nothing** -- smoke via a batch Ruby script (`-zz -r`) that writes and re-reads GDS2 + OASIS and checks the geometry, `strm2oas`, and a batch Python script (`-zz -rm`). Build with `build/build-klayout.sh --tag v0.30.10`.

**GObject typelib behavior**: Installer copies `*.typelib` files from `payload/<platform>/typelibs/` to `~/.local/lib/girepository-1.0/`. `envs/bash/global/bashrc` exports `GI_TYPELIB_PATH=$HOME/.local/lib/girepository-1.0` when that dir exists, allowing Python tools using `import gi` (PyGObject) to find bundled typelibs. Required typelibs documented in `"typelibs"` key of `packages.json` entries (reference only -- installer copies all typelibs unconditionally). Typelib files from EL8 RPMs: `gobject-introspection` (GLib/GObject/Gio/GIRepository), `gtk3` (Gtk/Gdk/GdkPixbuf), `gtksourceview3` (GtkSource-3.0). Plain files, no strip/patchelf needed.

**Meld runtime behavior (shanghai bundle)**: Meld 3.20.4 bundled as "shanghai" -- extracted from system-installed EL8 package, repacked into `payload/<platform>/runtime/meld.tar.bz2`. Uses **system Python 3.6** (`/usr/bin/python3.6`) with bundled PyGObject 3.28.3 (gi) and pycairo 1.16.3. Bundle extracts to `~/.local/` and installs: `lib/python3.6/site-packages/{gi,cairo,meld,meld3}/`, `share/meld/`, `bin/meld` (Python 3.6 launcher). Launcher derives its local prefix from installed `bin/meld`, exports `LOADOUT_LOCAL_PREFIX`, and sets `sys.path`, `GI_TYPELIB_PATH`, `LD_LIBRARY_PATH` before `import gi` -- `LD_LIBRARY_PATH` must be set before `import gi` so `dlopen()` for `_gi.cpython-36m.so` finds installed `lib64/libgirepository-1.0.so.1`. Bundled `meld/conf.py` has DATADIR patched to `LOADOUT_LOCAL_PREFIX/share/meld` (was `/usr/share/meld`; fallback remains `~/.local/share/meld` only for direct import outside the launcher). Exclusively-owned libs: `libgirepository-1.0.so.1`, `libgtksourceview-3.0.so.1` (both patchelf'd RPATH `$ORIGIN`). Installer function: `install_meld_runtime()`. Typically installed with gui_libs: `./loadout install gui_libs,meld`. Installer warns if meld selected without gui_libs (GTK3/Qt5/X11 libs all from gui_libs). To update meld: re-`yum install meld` on EL8 build machine, re-run shanghai extract steps (copy gi/cairo/meld packages + data files into bundle dir, patch conf.py, create tar.bz2, bzip2 new libs if version changed, update packages.json version), run `./build/strip-all-elf-binaries`, commit. **Why shanghai instead of PyPI wheels**: PyGObject has no binary wheels on PyPI (source-only, requires gobject-introspection headers). EL8 ships GLib 2.56.4; PyGObject >= 3.36 requires GLib >= 2.62; PyGObject <= 3.30 (works with GLib 2.56) incompatible with Python 3.14 (`Py_TYPE()` assignment removed). System Python 3.6 sidesteps all of this.

**mate-terminal runtime behavior (shanghai bundle)**: MATE Terminal 1.26.1 bundled as "shanghai" -- extracted from the EL8 EPEL `mate-terminal-1.26.1-1.el8.x86_64.rpm`, repacked into `payload/<platform>/runtime/mate-terminal.tar.bz2`. Uses **bundled GTK3 + VTE-2.91** (vte291 0.52.4 from EL8 AppStream) on top of the existing `gui_libs` GTK3 3.22 / GLib 2.56 stack. Bundle extracts to `~/.local/` and installs: `bin/mate-terminal` (POSIX-sh launcher), `bin/mate-terminal.bin` (the real ELF, RPATH=`$ORIGIN/../lib64`), `share/glib-2.0/schemas/org.mate.terminal.gschema.xml`, and the required minimal `org.mate.interface.gschema.xml` from `build/mate-terminal/` (mate-terminal reads `monospace-font-name` from this schema at startup; without it the binary aborts before opening with "Settings schema 'org.mate.interface' is not installed"). Launcher derives its local prefix from installed path, exports `XDG_DATA_DIRS=<prefix>/share:...` so GSettings finds the schema, and forces `GSETTINGS_BACKEND=keyfile` so the terminal **does not need `dconf-service` or a session D-Bus**. Settings persist to `~/.config/glib-2.0/settings/keyfile` instead of dconf. Post-extract the installer runs `glib-compile-schemas` on the staged schema dir; without `gschemas.compiled` mate-terminal aborts with "Settings schema 'org.mate.terminal.window' is not installed" or "Settings schema 'org.mate.interface' is not installed". Exclusively-owned libs: `libvte-2.91.so.0`, `libdconf.so.1` (both patchelf'd RPATH `$ORIGIN`). `libgnutls.so.30` is a NEEDED dep but is part of EL8 BaseOS and pulled in by openssh / NetworkManager / dnf itself -- assumed present on every farm node. Installer function: `install_mate_terminal_runtime()`. Typically installed with gui_libs: `./loadout install mate-terminal` (gui_libs auto-pulled via depends). To update: download newer RPM from EPEL, `rpm2cpio | cpio -idmv`, patchelf the binary with RPATH `$ORIGIN/../lib64`, copy `build/mate-terminal/org.mate.interface.gschema.xml` into `share/glib-2.0/schemas/`, rebuild the launcher, repack into mate-terminal.tar.bz2, run `./build/strip-all-elf-binaries`. **Why shanghai instead of source build**: mate-terminal's autotools chain on EL8 wants vte291-devel + mate-desktop-devel + dconf-devel + libSM-devel, which is a 200+ MB dev-package sprawl. The shipped RPM binary is GTK3-only (no GPU) and links cleanly against the bundled gui_libs GTK3 stack, so shanghai is dramatically simpler.

**Xephyr / xdesk behavior (shanghai bundle)**: Xephyr is a nested X server, shanghai'd from the EL8 AppStream RPM `xorg-x11-server-Xephyr-1.20.11-28.el8_10.3` (the full NVR is the package `version`; the `-28.el8_10.3` release field is where Red Hat's CVE backports live, so a bare upstream version is rejected by the build). It exists because on a locked-down host the DE is fixed by root-owned config -- NoMachine's `/usr/NX/etc/node.cfg` hardcodes its `DefaultDesktopCommand`, so the usual `~/.xsession` hook via `/etc/X11/xinit/Xsession default` does not apply -- and a nested X server sidesteps that entirely: it is an ordinary client window inside the session the user already has, and an X server for whatever runs inside it. **Chosen over Xvnc deliberately**, because a user-run `Xvnc` opens a listening TCP port (590x) and Xephyr binds no network socket. Packaging: `bin/Xephyr` (POSIX-sh wrapper) + `bin/Xephyr.bin` (real ELF, RPATH `$ORIGIN/../lib64`) + `bin/xdesk` (session launcher). Six bundled sonames: `libXdmcp.so.6`, `libXfont2.so.2`, `libfontenc.so.1`, `libxcb-glx.so.0`, `libxcb-xf86dri.so.0`, `libxcb-xv.so.0`. `depends: [gui_libs, mesa3d_libs]` -- `mesa3d_libs` already owns `libdrm.so.2` and `libxshmfence.so.1` at the same `lib64/` path, and two packages owning one path is an install hazard; it also gives the nested server a genuine Mesa vendor side for GLX. GLVND (`libGL.so.1`/`libGLX.so.0`/`libGLdispatch.so.0`) stays host-provided, never bundled. `libfontenc` is a dependency of *bundled* `libXfont2`, not of the binary -- a closure check that walked only the binary shipped green through Tier 1 and Tier 2 and was caught only by the clean-container gate; the build script's guard now walks the binary and every bundled lib. `/usr/share/X11/xkb` + `/usr/bin/xkbcomp` are assumed present, not bundled. `xdesk [-s WxH] [-f] [-d :N] [--no-dbus] [--no-auth] [-k] [-- command...]` load-bearing behaviours: **MIT-MAGIC-COOKIE auth by default** (a unix-socket X server is not access-controlled -- on a shared farm node another user could otherwise read the nested session's keystrokes); **readiness waits on either `/tmp/.X11-unix/X$N` or the abstract socket `@/tmp/.X11-unix/X$N` in `/proc/net/unix`**, because a host whose `/tmp/.X11-unix` has the wrong mode (WSLg, hardened hosts) makes Xephyr bind only the abstract socket and waiting on the filesystem socket alone times out against a perfectly healthy server; **one session bus only** (`start*` launchers run `dbus-launch` themselves); and the session is **forced onto X11 toolkits** (`WAYLAND_DISPLAY` unset, `GDK_BACKEND=x11`, `QT_QPA_PLATFORM=xcb`) so GTK/Qt clients cannot escape to the outer compositor -- note that this repo's own guidance to set `QT_QPA_PLATFORM=wayland` on WSLg would otherwise send every Qt app to the outer desktop. Under `-k/--keep` the state dir holding the cookie is **not** removed (deleting it leaves a nested X server with no access control), and the kept server inherits xdesk's stdout/stderr so a caller reading its output through a pipe or `$(...)` blocks. **Nested GNOME does not work** -- `gnome-shell` 3.32 exits with `TypeError: this._userProxy.Display is null` in `loginManager.js` because it asks logind for a graphical session a nested display does not have; not a GL problem, use a WM or a non-GNOME session. **Keyboard grabs:** Ctrl+Shift inside the Xephyr window toggles a full keyboard/pointer grab; bind nested WM shortcuts to Ctrl+Alt+letter. Build with `build/build-xephyr.sh --tag 1.20.11-28.el8_10.3` (full NVR -- the release field carries the CVE backports); **no `build/farm-versions` entry on purpose**, because X servers of this vintage reject `-version` and the stripped binary carries no version string, so the version lives in `packages.json` and is enforced against the RPM NVR by `--tag`. Smoke via `Xephyr -help` / `xdesk --help` and `tests/install-xdesk`.

**Firefox runtime behavior (shanghai bundle)**: Mozilla Firefox ESR 140.11.0 bundled as "shanghai" -- extracted from the AlmaLinux 8.10 BaseOS `firefox` RPM (`firefox-140.11.0-1.el8_10.alma.1.x86_64`), repacked into `payload/<platform>/runtime/firefox.tar.bz2` and auto-chunked to ~40 MiB shards (`firefox.tar.bz2.part-NNN`, four chunks ~ 136 MB total) by `strip-all-elf-binaries` so the archive stays under GitHub's per-file warn / hard cap. Bundle extracts to `~/.local/` and installs: `bin/firefox` (thin POSIX-sh launcher), `lib/firefox/` (full `/usr/lib64/firefox/` tree with libxul.so + libmoz*.so + omni.ja + langpacks), `share/applications/firefox.desktop`. Launcher derives prefix from `bin/..`, **prepends `<prefix>/lib/firefox` to `LD_LIBRARY_PATH`**, then execs `<prefix>/lib/firefox/firefox-bin`. The `LD_LIBRARY_PATH` prepend is load-bearing: the EL8 RPM's `firefox-bin` and `libxul.so` carry **no RPATH/RUNPATH** (an earlier "firefox-bin self-resolves via `RPATH=$ORIGIN`" claim was wrong) -- firefox-bin dlopens libxul by absolute path, but libxul's own NEEDED libs (nss, libmoz*) are then resolved by the system loader with no app-dir on its search path, so they must be placed there via `LD_LIBRARY_PATH`, exactly as the stock `/usr/bin/firefox` launcher does. Build script: `build/build-firefox.sh --tag X.Y.Z`. The script wipes any stale `firefox.tar.bz2.part-*` shards before re-tarring so a fresh build does not collide with prior chunks in the strip-manifest. Two absolute symlinks in the RPM are rewritten at build time: `lib/firefox/dictionaries -> /usr/share/myspell` is **deleted** (Firefox keeps its built-in spell data; users who want Hunspell extras install hunspell on the host); `lib/firefox/browser/defaults/preferences -> /usr/lib64/firefox/defaults/preferences` is **replaced with a real directory** holding a copy of the prefs (a relative symlink would work logically, but `add_tree_to_tar`'s `os.walk(followlinks=False)` never re-emits symlinks-to-directories, so a re-tarred archive silently drops them). Installer function: `install_firefox_runtime()`. Typically installed with gui_libs auto-pulled via `depends`. The Fedora-shipped `/usr/bin/firefox` launcher is intentionally NOT carried forward -- it hardcodes `/etc/gre.d/gre64.conf`, `/etc/fonts`, `/etc/firefox` langpack management, and SELinux `restorecon` paths that don't apply to a relocatable `$HOME` install. firefox-bin handles its own Wayland/X11 detection. **NSS / NSPR are BUNDLED** into `lib/firefox/` (13 `.so`: `libnss3`, `libnssutil3`, `libsmime3`, `libssl3`, `libnspr4`, `libplc4`, `libplds4` + the dlopen plugins `libsoftokn3`, `libfreebl3`, `libfreeblpriv3`, `libnssdbm3`, `libnssckbi`, `libnsssysinit`), each `patchelf --set-rpath '$ORIGIN'`. Firefox 140's `libxul.so` needs `NSS_3.107`, newer than the NSS AlmaLinux 8.10 shipped at GA (3.90); an un-patched farm node aborts with ``/lib64/libnss3.so: version `NSS_3.107' not found ... Couldn't load XPCOM``. The build box only had a new-enough `nss-3.112` because the firefox RPM pulled it in -- classic build-box masking (cf. the octave support libs). The wrapper's `LD_LIBRARY_PATH` prepend is what makes the bundled NSS win over the host's older `/lib64` copy. Still assumed present (NOT bundled): `libsqlite3.so.0` (softokn3 dep; EL8 base sqlite 3.26, never security-bumped, identical build+dest), `libtasn1.so.6` (nssckbi dep), `libasound2`, `libfreetype`, `libfontconfig`. gui_libs covers the GTK3 / cairo / pango / X11 / Wayland stack libxul dlopens at runtime.

**Zsh binary behavior**: `zsh` pre-built binary (in the `@shared` sweep; install alone with `./loadout install zsh`). Binary links against `libzsh-5.9.so` (shipped in the runtime archive at `lib/zsh/`), `libpcre.so.1` (bundled for `zsh/pcre`), `libncursesw.so.6`, and `libcap.so.2`. Binary RPATH is `$ORIGIN/../lib/zsh:$ORIGIN/../lib64:$ORIGIN/../lib` so it finds `libzsh-5.9.so` and bundled lib64 deps. `libpcre.so.1` is bundled bzip2'd as `lib64/libpcre.so.1.bz2` (the installer only decompresses `lib64/*.bz2` -- a raw ELF there is silently never installed) and `bin/zsh` NEEDs it directly, so a target without system pcre1 cannot start zsh unless it ships. The runtime archive (`zsh.tar.bz2`) ships the shell function library (`share/zsh/5.9/functions/`) AND the full set of dynamically-loaded modules (`lib/zsh/5.9/zsh/*.so`): `zsh/regex`, `zsh/pcre`, `zsh/mathfunc`, `zsh/stat`, `zsh/mapfile`, `zsh/parameter`, `zsh/complist`, `zsh/zprof`, `zsh/zpty`, `zsh/net/socket`, `zsh/net/tcp`, `zsh/zftp`, `zsh/system`, `zsh/cap`, `zsh/clone`, `zsh/datetime`, `zsh/langinfo`, `zsh/terminfo` (static, linked in), `zsh/termcap` (static), `zsh/zutil` (static), `zsh/files`, `zsh/watch`, `zsh/newuser`, `zsh/attr`, `zsh/nearcolor`, `zsh/zselect`, `zsh/param/private`, plus the Zle modules (`zle`, `complete`, `compctl`, `complist`, `computil`, `zleparameter`). Module `.so` files are patchelf'd with an RPATH that reaches the bundled `lib64/` on their own (`$ORIGIN/../../../../lib64` for the flat modules at `lib/zsh/5.9/zsh/`, `$ORIGIN/../../../../../lib64` for the nested `net/` and `param/` ones), and `libzsh-5.9.so` carries `$ORIGIN/../../lib64` -- so `zsh/pcre` resolves `libpcre.so.1` itself rather than depending on `bin/zsh` having preloaded it (an earlier `$ORIGIN/../../..` pointed at `lib/`, which held no libs and only worked via that preload). Build with `build/build-zsh.sh --tag <version>`. **Two AC_TRY_RUN cache vars MUST be pre-seeded** (`zsh_cv_func_dlsym_needs_underscore=no`, `zsh_cv_shared_environ=yes`) or configure silently sets `dynamic=no` and no modules are built -- the sandbox breaks the dlopen/shared-environ probes. Tag format: bare version number, e.g. `5.9` (no `v` prefix -- zsh upstream convention). `env-zsh` installs env-owned completions under `~/.config/zsh/site-functions/`; `envs/zsh/global/completions.zsh` prepends that dir to `fpath` before `compinit`.

**zsh environment behavior**: `env-zsh` **TRACKS `envs/bash/`** (same policy as tcsh -- see the tcsh entry), but by **REUSE, not reimplementation**: zsh has functions/arrays/`local`, so `envs/zsh/zshrc` sources `envs/bash/functions.sh`, `envs/bash/global/config.sh` (+ the corp..user layers) and `envs/bash/global/aliases.sh` directly. That is why `env-zsh` depends on `env-bash`, and why the alias surface tracks **automatically** rather than by discipline. **The corollary is that those three files are SHARED CODE and a bashism in any of them is a zsh bug** -- five such bugs were found and fixed on 2026-08-08, all of which were also latent for bash users: `path_modify`/`path_trim`/`std_paths` used `${!var}` + 0-based indexing (documented two-arg `path_append LD_LIBRARY_PATH /opt/lib` died with `bad substitution`; the one-arg PATH form worked, which made it look fine), `pl` used bash-4 `${var,,}`, `a` used `declare -f` (`typeset -f` works in both), `check_extended_keys` **ate the user's type-ahead** (its `read -r -d 'c'` consumed input up to the first `c` when the terminal did not answer the DA query -- typing `echo MARK` ran `ho MARK`; it now answers from TERM/tmux first and refuses the probe when input is pending, and `tests/shell-typeahead` pins it), and `loadout_detect_online` backgrounded probes directly so zsh printed `[9] + done` job notices on every startup (the fan-out now runs inside one subshell). Layout under `envs/zsh/global/`: `zshrc`, `config.zsh` (zsh-ONLY vars -- the shared defaults are never duplicated), `keybinds.zsh`, `completions.zsh`, `modules-init.zsh`, `wezterm-integration.zsh`. **All three of `~/.zshenv`, `~/.zshrc`, `~/.zprofile` link to the entry point**: zsh splits startup files by shell TYPE and `.zshrc` is **interactive-only**, so linking only `.zshrc`/`.zprofile` (as this package used to) left `zsh script.zsh` with no PATH and no exported env; `.zshenv` fixes that and the entry point carries a non-exported `_LOADOUT_ZSH_SOURCED` re-entry guard for the resulting double-source. **Custom `_install_env_zsh` handler** for the same reason as env-st/env-tcsh: the generic handler's `install_path()` syncs with `delete=True` and was **deleting `~/.config/zsh/{corp,site,team,project,user}` on every reinstall** while the shipped zshrc went on sourcing them (`supports_layers` in the registry does not prevent this -- it is only read by `loadout info` for display). **Hooks are registered by appending to the `${hook}_functions` arrays directly, never via `add-zsh-hook`** -- that is an autoloaded function from the zsh function library, which an env-only HOME does not have, so hooks registered through it silently never fire. Prefer zsh-native mechanisms: **`chpwd`** gives "every cd lists" with no `cd` wrapper and no call site that can forget (bash needs it inside `cd()` plus a `__zoxide_cd` override), **`AUTO_CD`** replaces the ERR-trap hack, and native `precmd`/`preexec` carry **full OSC 133** semantic zones (the vendored `wezterm.sh` is the bash-preexec variant with no zsh path, so `wezterm-integration.zsh` implements the protocol directly). **starship needs the `zsh/mathfunc` MODULE** (its init calls `int()`), so it is probed with `zmodload -i` first -- otherwise an env-only HOME fails loudly on every prompt with `failed to load module: zsh/mathfunc` / `unknown function: int`. Genuinely absent: IceCream-Bash only (`${!var}` + `export -f`). `tmux-path-store` gained `--zsh` and `--csh`/`--tcsh` upstream in v1.1.0 and is now wired into all three shells. `tests/install-env-zsh` (Tier 2) and `tests/shell-typeahead` (Tier 1) cover it; the zsh test carries the **same third harness trap as tcsh's** -- `script` gives the child a PTY so zsh's own diagnostics land on **stdout** while stderr stays empty, and three real startup complaints shipped through that hole (`no matches found: ...zsh_history.*` from zsh's NOMATCH on an unmatched glob, the mathfunc failure, and job notices), so `assert_no_zsh_noise` scans the output too. Its `env -i` is also load-bearing: without it the surrounding loadout bash session's exported `LOADOUT_CFG_*`/PATH leak in and the test measures the developer's shell instead of a fresh farm HOME.

**Fish runtime behavior**: `fish` pre-built binary (in the `@shared` sweep; install alone with `./loadout install fish`). **fish >= 4.8 embeds its standard library in the binary** -- upstream deleted the `install(DIRECTORY share/{functions,completions,prompts,themes,tools})` rules from `cmake/Install.cmake`, so `ninja install` populates `share/fish` with nothing but the empty `vendor_*.d` drop-in dirs, and `payload/<platform>/runtime/fish.tar.bz2` is correspondingly tiny (~342 bytes). That is correct: the shipped binary defines `fish_prompt`, carries the full function set, and completes with no `share/fish` data on disk. The archive exists only to create the `vendor_functions.d` / `vendor_completions.d` / `vendor_conf.d` drop-in dirs, and the registry `sentinel` is `share/fish/vendor_functions.d` (a **directory** -- `sentinel_ok` accepts `isfile` or `isdir`). Do **not** "fix" the small archive by restoring a stdlib tree, and do not point the sentinel back at `functions/fish_prompt.fish`: that file does not exist in fish >= 4.8, and the stale sentinel is what made every fish install print a bogus `WARNING: fish runtime ... not found` and every test summary carry a red `fish runtime FAILED` row. `build-fish.sh` now asserts the invariant that actually matters -- the built fish must define `fish_prompt` and >20 functions -- rather than a file layout upstream is free to move again; the 4.8.0 bump shipped a stdlib-less archive precisely because the only check was the file-layout sentinel. Installed launcher is a small POSIX-sh wrapper (`bin/fish`) that derives its prefix from installed `bin/..`, ensures `<prefix>/etc/fish` exists so fish's relocatable-tree probe succeeds, exports `__fish_data_dir`, `__fish_bin_dir`, and `__fish_sysconf_dir`, then execs `bin/fish.bin`; explicit user overrides still win. This keeps `--dest-dir` installs and shared-tree deployments from falling back to fish's build-time prefix. Installer function: `install_fish_runtime()`. Binary links against `libncurses.so.6` and `libpcre2-8.so.0` (both bundled -- `libpcre2-8.so.0` owned by `gui_libs` but installed as lib64 dep). fish 4.x written in Rust; build with cmake+cargo via `build/build-fish.sh --tag <version>`.

**st terminfo behavior**: `st` ships its terminfo entries as `payload/<platform>/runtime/st.tar.bz2`. Archive contains `./share/terminfo/...`, extracts to `~/.local/`, and installs `share/terminfo/s/st-256color` plus the sibling `st*` entries under `~/.local/share/terminfo/`. `envs/bash/global/bashrc` prepends `$HOME/.local/share/terminfo` to `TERMINFO_DIRS` because Linux ncurses does not search that path by default; this keeps normal installs, `--dest-dir` staging, and shared-tree deploys able to resolve `st-256color` without relying on `~/.terminfo`. (`build-st.sh` once staged `./.terminfo/s/` and tarred `./.terminfo`, disagreeing with both the archive and the sentinel -- the next tag bump would have installed to `~/.local/.terminfo` and failed its own sentinel. It now stages `./share/terminfo/s/`; do not revert.)

**tcsh environment behavior**: `env-tcsh` (`kind: env`, **`optional: true`** -- deliberately NOT in `@envs` or `@engineering-loadout`; opt in with `./loadout install env-tcsh` or `@envs-all`) installs `envs/tcsh/` to `~/.config/tcsh` and links both `~/.tcshrc` and `~/.cshrc` at the entry point. Same six-layer chain as bash (`global -> corp -> site -> team -> project -> user`, two passes: every layer's `config.csh`, then every layer's `tcshrc`). Custom `_install_env_tcsh` handler for the same reason as `env-st`: `install_path()` on a directory syncs with `delete=True` and would wipe the user's own layers. **`envs/tcsh/` TRACKS `envs/bash/` (and `envs/zsh/`)** -- a bash-env change is not finished until the tcsh form lands. This **reversed** the policy that stood 2026-07-13..2026-08-08, which called tcsh a deliberate one-time port and refused a drift test on the grounds that its expected user count was near zero. That premise was wrong: **the EE community this project serves is ~90% tcsh**, so it is the majority shell of the target audience. Every argument for not tracking rested on the bad premise. If you find text elsewhere asserting "one-time port / does not track", it is stale -- fix it. **"csh has no functions" selects the implementation, not whether the feature ships**: a one-line wrapper becomes an alias (they take args -- `\!:1`, `\!*`, `\!:2-`); anything needing loops/locals/`case` becomes a POSIX-sh helper under `envs/tcsh/global/helpers/` that is aliased; anything that must mutate the caller's cwd/PATH/env becomes a helper that *prints* the command, run through `` eval `helper` ``. `git-branch.sh` is the precedent. Only five things are genuinely absent, all because upstream ships no tcsh target: **Starship** (`starship init` has no tcsh), **fzf keybindings** (`fzf --bash|--zsh|--fish` only), **zoxide** (`zoxide init` has no tcsh), **OSC 133 semantic zones** (needs bash-preexec; OSC 7 cwd is carried by tcsh's `precmd` and does ship), and **IceCream-Bash** (relies on `${!var}` and `export -f`). Prefer csh-native answers where they beat the bash mechanism: **`cwdcmd`** runs on every directory change (so "every cd lists" needs no `cd` wrapper) and **`set implicitcd`** replaces bash's ERR-trap directory-execution hack. **Startup silence remains a hard requirement** -- a warning on startup is a bug -- but it is the floor now, not the goal. `envs/tcsh/global/git-branch.sh` exists because **csh cannot redirect stderr separately from stdout** (no `2>/dev/null`): an inline `|&` branch lookup merges git's error text into the prompt, and an unborn HEAD then renders git's "Use `--` to separate paths from revisions" hint at the user; the helper does the redirect in sh and uses `symbolic-ref` (which resolves an unborn HEAD, unlike `rev-parse --abbrev-ref`), falling back to a short sha when detached. Never `exit` from the rc files: tcsh sources `~/.tcshrc` for **non-interactive** shells too, so an early `exit` kills every tcsh script the user runs -- gate interactive work with `if ( $?prompt )`. Layout under `envs/tcsh/global/`: `tcshrc` (PATH/env/options/history/prompt/integrations), `config.csh`, `aliases.csh`, `completions.csh` (hand-written `complete` rules -- bash-completion is bash-only and no bundled tool emits csh), `keybinds.csh` (`bindkey`), `grc-aliases.csh` (the vendored `grc.sh` is sh syntax ending in `return 0` and cannot be sourced by csh), `modules-init.csh`, `git-branch.sh`, and `helpers/` (POSIX-sh, shellcheck-clean; see `helpers/README.md` for the three calling shapes). **`exit` from a SOURCED csh file exits the SHELL, not the source** -- guards use nested `if`, never an early `exit`, in the helper-sourced files as well as the rc files. Two helpers encode non-obvious facts: **`prompt-color`** exists because `LOADOUT_CFG_PROMPT_COLOR_*` is shared with the bash env and **exported** there, so a tcsh launched from a loadout bash shell inherits a *bash* prompt string wrapped in readline's `\[`/`\]` zero-width markers, which tcsh prints literally (it strips them and converts a literal `\033`/`\e` to a real ESC; `%{...%}` is tcsh's own zero-width wrapper); **`seed-history`** derives the parent pid from `/proc` because **tcsh has no `$PPID`** -- naming it makes every interactive shell print `PPID: Undefined variable.`. Also: **`!` triggers history expansion inside DOUBLE quotes too**, so `--glob='!*.snapshot*'` in an alias body must be `\!`. `tests/install-env-tcsh` asserts empty stderr on startup and needs a real PTY (`script -qec`) because `tcsh -i -c CMD` does **not** set `$prompt` and therefore silently skips the whole interactive block (a silence test written that way passes without running the code under test), and a piped tcsh with no tty prints `Warning: no access to tty` to stderr. **A THIRD harness trap matters just as much**: `script` gives the child a PTY, so tcsh's own diagnostics arrive on **stdout** while the stderr file stays empty -- the headline silence assertion cannot see a shell complaining on every startup, and both the `$PPID` and unescaped-`!` bugs shipped green through that hole. `assert_no_csh_noise` now scans the captured output for tcsh's error vocabulary; both bugs were re-introduced deliberately to confirm it fails. Tier 3's `almalinux8.10-smoke.Dockerfile` installs tcsh; `script` is in the base image.

**st runtime config behavior**: `st` (0.9.3, `build/build-st.sh --tag 0.9.3`) is patched (`build/st/0001-runtime-xresources-config.patch`, derived from the upstream `xresources` + `xresources-with-reload` patches) to merge an `XrmDatabase` at runtime instead of baking everything into `config.h`. Precedence, lowest to highest: compiled `config.h` defaults < the X server's `RESOURCE_MANAGER` (seed) < each file in the colon-separated `$ST_XRESOURCES` in order (later file wins, missing/unreadable files skipped via `access(path, R_OK)`). Unset resources keep their `config.h` defaults, so st with no config files behaves exactly as an unpatched build. `bin/st` is a POSIX-sh wrapper that builds `ST_XRESOURCES` as the six-layer chain under `${XDG_CONFIG_HOME:-$HOME/.config}/st` -- `global -> corp -> site -> team -> project -> user` -- and execs `bin/st.bin`; a caller-set `ST_XRESOURCES` wins untouched, and the wrapper reads no shell-startup state so `st` from `.desktop`/dmenu/`ssh host st` resolves the same config as an interactive shell. The wrapper split ships `bin/st` (script), `bin/st.bin` (ELF, RPATH `$ORIGIN/../lib64:$ORIGIN/../lib`, strip -> patchelf -> bzip2), and `bin/st-reload` (script). Reload is driven by `SIGUSR1`: the handler only sets a `sig_atomic_t` flag (no X calls from a handler), and `run()` services it on its next pass (`config_init` -> re-derive `usedfont` from `opt_font` so an explicit `-f` still beats the files -> `xunloadfonts`/`xloadfonts` -> `xloadcols` -> `cresize(0,0)` -> `redraw` -> `xhints`). `Ctrl+Shift+R` calls the same `xreload()` path. `st-reload` signals every `st.bin` you own on `$DISPLAY` (default) or everywhere you own (`--all`); non-zero exit if none running; rejects unknown options. Keybindings other than `Ctrl+Shift+R` are compile-time; the runtime-config patch covers only the fixed resource set (`font`, `color0`-`color15`, `background`, `foreground`, `cursorColor`, `termname`, `shell`, `cursorshape`, `borderpx`, `blinktimeout`, `bellvolume`, `tabspaces`, `cwscale`, `chscale`). `env-st` (`kind: env`) ships the `global` layer (loadout-owned, synced with delete semantics on every reinstall) and seeds `user/st.xresources` once from `envs/st/user/st.xresources.template` (fully commented, inert) -- never overwriting the user's copy. It uses a custom handler `_install_env_st`, not the generic env handler: `install_path()` on a directory calls `sync_dir(delete=True)`, which would wipe the user's own `corp/site/team/project/user` layers on every reinstall. Both shipped config files must end with a trailing newline -- users append settings with `>>`; without it the appended directive glues onto the final comment line and is silently ignored (`tests/install-env-st` asserts it). The shipped files carry a `! BEGIN generated font list` / `! END generated font list` block regenerated by `build/gen-st-font-comments` from `payload/fonts/*.zip` via `fc-scan`, because the fontconfig family name is not the zip name for ~1/3 of the bundle (`CascadiaCode` -> `CaskaydiaCove`, `SourceCodePro` -> `SauceCodePro`, `DejaVuSansMono` -> `DejaVuSansM`, `Meslo` -> `MesloLG{L,M,S}[DZ]`); `gen-st-font-comments --check` is a Tier 1 sync test. `build-st.sh` does `rm -f config.h` before building: st's Makefile only copies `config.def.h` -> `config.h` when `config.h` is absent and `make clean` does not remove it, so a stale `config.h` silently drops every `config.def.h` change.

**Rolling-git wheel behavior**: First-party `python-tool` packages can be tagged `"rolling_git": "<clone-url>"` in `packages.json` (currently `lefdef-tools`, `liberty-tools`, `text-serdes`, `time-plot`). `./build/update <name>` (and bare `./build/update`, which now includes all rolling pkgs) rebuilds these from source instead of using a hand-bundled wheel: cheap `git ls-remote` skip-check -> fresh `git clone --filter=blob:none` (keeps tags so `describe` works; falls back to full clone) -> `uv build --wheel` (handles maturin **and** hatchling backends) -> prune previous `<dist>-*.whl` -> copy new wheel into `payload/<platform>/wheels/` -> surgically stamp the package's `version` to `git describe --tags --always --dirty`. Rebuild happens **only when the source commit changed**; `./build/update <name> --rebuild` forces. `./build/update --list[-outdated]` shows rolling rows with latest = remote HEAD sha. **maturin gotcha:** under PEP517 maturin tags a bare `linux_x86_64` wheel; `update` sets `MATURIN_PEP517_ARGS="--compatibility manylinux_2_28"` for maturin backends so the wheel is portable + auditwheel-checked. Builds need network + `~/.cache/uv` write (run on the EL8 build machine). Add a 4th rolling project by adding the `rolling_git` field -- `./build/update` discovers it automatically. To add a new third-party (pinned) Python tool instead, see *Python tool behavior* below.

**cicwave Python tool behavior**: `cicwave` optional `uv_tool` (`optional: true` -- opt in with `./loadout install cicwave`; not in any bulk group). PyQtGraph waveform viewer (ngspice/Xyce/VCD/CSV). It is a **loadout PyQt6 fork** of the upstream PySide6 app: PySide6 has **no wheel that is both EL8 (glibc 2.28) and Python 3.14** -- 6.9.x is `manylinux_2_28` but `python<3.14`; 6.10+ added 3.14 but jumped to `manylinux_2_34` (glibc 2.34/RHEL9, a one-way ratchet). PyQt6 satisfies both (`PyQt6 6.9.1` abi3 cp39, `PyQt6-Qt6 6.9.2` `manylinux_2_28` with `libQt6Core` floor `GLIBC_2.28`, `PyQt6-sip` cp314). The fork lives as `build/cicwave/0001-port-pyside6-to-pyqt6.patch` (PySide6->PyQt6 imports, `pyqtSignal as Signal`, **25 strict-enum scopings** like `Qt.AlignCenter -> Qt.AlignmentFlag.AlignCenter`, two dynamic `getattr(QPalette.ColorRole, ...)` / `ShortcutContext` fixes, and the pyproject `PySide6 -> PyQt6` dep so the wheel resolves offline). Build/bundle with `build/build-cicwave.sh --tag 0.5.2` (clones stable tag, applies patch, `uv build`, downloads the PyQt6 + matplotlib closure as EL8/cp314 wheels, splits the ~79 MB `pyqt6_qt6` wheel into `.whl.part-NNN` -- the installer's `_prepare_wheels_dir` rejoins it like the polars/pyarrow wheels). numpy/pandas/click/pyyaml/packaging/python_dateutil/six are reused from the existing bundle. Headless-verify with `QT_QPA_PLATFORM=offscreen` + `CICSIM_USE_OPENGL=0` (offscreen Qt has no GL); interactive paths need a real X/WSLg smoke after a version bump. See `ADDING_BINARIES.md` -> "cicwave".

**parity-plot Python tool behavior**: `parity-plot` is non-optional (therefore included in `@shared`) and also lives in `@python-tools-extra`. It is pinned to stable upstream tag `v0.7.0` (`2fc29243`); rebuild with `build/build-parity-plot.sh --tag v0.7.0`. The script builds the pure project wheel, exports runtime dependencies from upstream's lock, and downloads the whole EL8/cp314 wheel closure. It first validates/reuses the vendored lock closure, so a same-lock rebuild is offline; if a release tag has stale lock metadata, the builder runs `uv lock` only in the disposable checkout before exporting hash-locked requirements. NiceGUI is a core upstream dependency, not a `uv_extras` entry, so `uv tool install parity-plot` installs both CLI and designer offline. **There is no loadout patch any more.** Through v0.6.0 we carried one that rewrote plotly's CDN reference to an inlined copy so generated HTML renders air-gapped. v0.7.0 adopted that natively and went further: `[output].plotlyjs` selects `inline`/`cdn`/`directory`/`none`, and a standalone document defaults to `inline` precisely so it opens with no network (embedded *fragments*, `[output].embed = true`, default to `none` because the host page loads plotly once itself). Upstream's default is exactly what we used to patch for, so the patch was **deleted, not rewritten** -- along with the `PATCH` variable and the `git apply` step in the build script. What guards the property now is behavioural rather than textual: `tests/install-parity-plot` asserts the generated HTML embeds the plotly runtime and carries no CDN reference, so a future upstream default flip fails the test instead of silently shipping CDN-dependent reports. Inlining costs about 4.9 MiB per HTML report and no extra wheel payload, because Plotly already ships its minified JS. PNG/SVG/PDF export uses Kaleido and still requires a compatible Chrome/Chromium already installed on the host; do not invoke a downloader during an offline install. **The CLI is TOML-only since v0.6.0**: `parity-plot plot` takes a config file (default `parity.toml`), not a CSV path. `parity-plot init` writes a fully-commented starter config and `parity-plot example` generates sample data and renders it. `tests/install-parity-plot` installs into a temp tree, verifies CLI and module versions, drives `plot` through a generated TOML config, exercises `init` and `example`, inspects the HTML for an embedded Plotly runtime and no CDN reference, imports the designer dependencies, and probes the local designer server where host policy permits loopback sockets. Its expected version is **read from `packages.json`** rather than hard-coded -- the literal went stale on every bump, and what the test needs to prove is that the installed artifact matches what the registry claims to ship.

**JupyterLab Python tool behavior**: `jupyterlab` `uv_tool` (in the `@shared` sweep; install alone with `./loadout install jupyterlab`). Installed via `uv tool install jupyterlab` using bundled wheels. After install, `jupyter` and `jupyter-lab` launchers at `~/.local/bin/`. Users run `jupyter lab`; JupyterLab opens in system browser. Requires accessible browser (WSL2: Windows browser via WSL interop; headless farm nodes: point `BROWSER` to VNC-accessible browser or use `--no-browser --port=8888` with port forwarding). Wheels must be downloaded with `PIP_REQUIRE_VIRTUALENV=0 pip3.14 download jupyterlab --platform manylinux_2_28_x86_64 --python-version 3.14 --only-binary :all: -d payload/<platform>/wheels/` -- JupyterLab has ~80 dependency packages.

**Backup behavior**: Numbered backups in `loadout_backups/backup.N/` (always starts at `.1`; never bare `backup`). Skips files already pointing to repo. Never overwrites existing backups. At end of successful install, backup dir compressed to `loadout_backups/backup.N.tar.bz2`, uncompressed dir removed; numbering checks both `backup.N/` and `backup.N.tar.bz2` when picking next N. Post-install hooks (receive `LOADOUT_BACKUP_DIR`) run before compression. `./loadout snapshot restore <path>` accepts uncompressed dirs or `.tar.bz2` archives (extracts to `/tmp`, restores). Main backups exclude font files (`*.ttf`, `*.otf`, `*.pcf`, `*.bdf`, `*.woff`, `*.woff2`, etc.) -- large and reproducible. The fonts phase has its own `fonts.bak*` move for normal installs and suppresses it under `--no-backup`.

**Tmux plugin behavior**: All bundled plugins always copied/linked from repo. Run `./build/update tmux-plugins` to re-clone from GitHub (pre-commit hook strips `.git` dirs on next commit).

**Tmux selection behavior**: `envs/tmux/tmux-word-separators` is run from `envs/tmux/tmux.conf` to append broad emoji ranges to `word-separators`. Tmux only supports literal separator chars, not Unicode classes -- keep helper in sync with `tmux.conf` if double-click word selection starts capturing prompt icons like Starship's read-only lock.

**Linux symlink map:**
- `~/.bashrc`, `~/.bash_profile`, `~/.bash_login`, `~/.profile` -> `~/.config/bash/bashrc` -> `repo/envs/bash/bashrc`
- `~/.vimrc` -> `~/.config/vim/vimrc`
- `~/.vim` -> `~/.config/vim/vim`
- `~/.tmux.conf` -> `~/.config/tmux/tmux.conf`
- `~/.tmux` -> `~/.config/tmux/tmux`
- `~/.editorconfig` -> `~/.config/editorconfig/editorconfig`
- `~/.config/starship/starship.toml` <- `repo/envs/starship/starship.linux.toml`
- `~/.config/starship/config-schema.json` <- `repo/envs/starship/config-schema.json`
- `~/.local/share/helix/runtime/` <- `repo/payload/<platform>/runtime/helix.tar.bz2`
- `~/.local/share/vim/vim92/` <- `repo/payload/<platform>/runtime/vim92.tar.bz2`
- `~/.local/share/nvim/runtime/` <- `repo/payload/<platform>/runtime/nvim.tar.bz2`
- `~/.local/bin/python3.14` etc. <- `repo/payload/<platform>/portable-python-*.tar.bz2` (via install.sh)

**Windows copy destinations** (files copied, not symlinked -- re-run `.\loadout.cmd` or `.\loadout.ps1` after repo changes):
- `%USERPROFILE%\.local\opt\powershell\7\` <- bundled `payload/windows.x86_64/powershell/PowerShell-*-win-x64.zip[.part-NNN]`
- `%LOCALAPPDATA%\Microsoft\Windows Terminal\Fragments\engineering-loadout\powershell.json` -- Windows Terminal profile for bundled PowerShell
- `%LOCALAPPDATA%\nvim` <- `repo/nvim`
- `%USERPROFILE%\.config\wezterm\wezterm.lua` <- `repo/envs/wezterm/wezterm.lua`
- `%USERPROFILE%\.config\starship\starship.toml` <- `repo/envs/starship/starship.windows.toml`
- `%USERPROFILE%\.editorconfig` <- `repo/envs/editorconfig/editorconfig`
- `%USERPROFILE%\autohotkey\hotkeys.ahk` <- `repo/envs/autohotkey/hotkeys.ahk`
- `%USERPROFILE%\loadout_keys.toml` -- user-local AHK feature selection config (created if missing); `[autohotkey].executable` overrides AHK exe discovery (useful when AHK has been renamed for corp infosec compliance); `[autohotkey.features.cisco-secure-client-vpn].skip_wifi_ssids` is read by AHK at runtime to skip Cisco automation on named Wi-Fi networks; `[autohotkey].logging = true` (default false) makes the script append timestamped diagnostics (SSID source, VPN skip decision, auto-login actions) to `%USERPROFILE%\autohotkey\hotkeys.log`
- `hotkeys.ahk` reads its enabled-feature list from `%USERPROFILE%\loadout_keys.toml` at startup (no install-time patching; the installer just copies the script). Override the config path with `LOADOUT_KEYS_TOML`; run `AutoHotkey64.exe hotkeys.ahk --print-config` to dump the resolved config and exit
- `%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\hotkeys.lnk` -- `.lnk` shortcut pointing to `AutoHotkey64.exe "%USERPROFILE%\autohotkey\hotkeys.ahk"` (AHK not system-wide to avoid SentinelOne flagging). AHK extracted to `%USERPROFILE%\AutoHotkey_*\`; if none exists, installer downloads latest stable from GitHub, removes `AutoHotkey32.exe`.
- `%USERPROFILE%\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1` <- `repo/envs/powershell/Microsoft.PowerShell_profile.ps1` (PS 5.1)
- `%USERPROFILE%\Documents\PowerShell\Microsoft.PowerShell_profile.ps1` <- same (PS 7+)

## Bash Configuration Architecture

### Layer System

Files sourced in order: `global -> corp -> site -> team -> project -> user`. Each layer overrides previous. Layer dirs (`envs/bash/corp/`, `envs/bash/site/`, `envs/bash/team/`, `envs/bash/project/`, `envs/bash/user/`) user-created, not bundled.

**Loading sequence** (see `envs/bash/bashrc`):
1. Sources `envs/bash/functions.sh` (shared utilities, available to all layers)
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

### Configuration Variables (`envs/bash/global/config.sh`)

All variables exported scalars (`export LOADOUT_CFG_*=value`) -- propagate to child processes, visible in `env | grep LOADOUT_CFG_`. Override in user layer's `config.sh` with same form.

| Variable | Default | Purpose |
|----------|---------|---------|
| `LOADOUT_CFG_PREFERRED_BASH` | `""` | Full path to preferred bash binary; re-execs into it at startup if set, differs from current bash, and is executable |
| `LOADOUT_CFG_SHARED_PREFIX` | `""` | Local-root of a separately-installed shared/read-only tree (dir holding `bin/`/`share/`/`lib64/`, e.g. `/foo/bar/local`). Set it in the env of `loadout install @envs`; `_mirror_shared_prefix` bakes it into the installed `config.sh`. PATH, TERMINFO_DIRS, and the tealdeer cache resolve against `${LOADOUT_CFG_SHARED_PREFIX:-$HOME/.local}`. Empty = user's own `~/.local` |
| `LOADOUT_CFG_PREFERRED_LS` | `eza` | ls replacement (`eza`, `lsd`, `ls`) |
| `LOADOUT_CFG_PREFERRED_VI` | `nvim` | Editor (`nvim`, `vim`) |
| `LOADOUT_CFG_PREFERRED_CAT` | `bat` | cat replacement (used by aliases) |
| `LOADOUT_CFG_ENABLE_GRC` | `1` | Generic Colorizer |
| `LOADOUT_CFG_ENABLE_ICECREAM` | `1` | Source vendored IceCream-Bash (`ic`/`icp`/`ict`/`ictp` debug-print helpers); `export -f`'d so child scripts inherit them |
| `LOADOUT_CFG_ENABLE_FZF` | `0` | fzf shell integration |
| `LOADOUT_CFG_ENABLE_ZOXIDE` | `0` | zoxide shell integration (`z`/`zi` commands) |
| `LOADOUT_CFG_ENABLE_STARSHIP` | `1` | Starship prompt (falls back to built-in prompt) |
| `LOADOUT_CFG_STARSHIP_USERIDS_TO_HIGHLIGHT` | `""` | Space-separated list of usernames; if `whoami` matches, username shown in prompt |
| `LOADOUT_CFG_ENABLE_WEZTERM_SHELL_INTEGRATION` | `1` | Source the loadout-owned `wezterm.sh` (OSC 133 semantic zones, OSC 7 cwd, user vars). Self-skips `dumb`/`linux` and non-interactive shells; off-WezTerm shells source it with WezTerm output hooks skipped, keeping bash-preexec without raw OSC output or `wezterm set-working-directory` prompt stalls |
| `LOADOUT_CFG_WEZTERM_SHELL_INTEGRATION` | `""` | Explicit path to `wezterm.sh`; empty auto-resolves (vendored copy -> wezterm-binary-relative -> `${LOADOUT_CFG_SHARED_PREFIX:-$HOME/.local}`). Set from a `--dest-dir` installer to pin it. Never `/etc` |
| `LOADOUT_CFG_ENABLE_FASTNVIM` | `0` | Fast nvim mode |
| `LOADOUT_CFG_ENABLE_TMUX_PATH_STORE` | `1` | tmux-path-store alias injection (variable name stays SCREAMING_SNAKE -- a shell variable cannot take a dash) |
| `LOADOUT_CFG_PROMPT_COLOR_NORMAL` | `$PROMPT_YELLOW` | Normal session prompt color |
| `LOADOUT_CFG_PROMPT_COLOR_FARM` | `$PROMPT_RED` | Farm/LSF session prompt color |
| `LOADOUT_CFG_PROMPT_INCLUDE_HOST` | `0` | Include hostname in prompt |
| `LOADOUT_CFG_ATTACH_TO_TMUX` | `0` | Auto-attach tmux on login |
| `LOADOUT_CFG_ATTACH_TO_TMUX_WITH_DETACH_OTHERS` | `0` | Detach other clients when attaching |
| `LOADOUT_CFG_ENABLE_ONLINE_UPDATES` | `auto` | Online mode: `auto` (parallel TCP probe on startup) \| `1` (force online) \| `0` (force offline). Exports `LOADOUT_ONLINE=1/0` inherited by child shells/tmux panes |
| `LOADOUT_CFG_ONLINE_DETECT_TIMEOUT` | `0.15` | Per-host TCP connect timeout in seconds (GNU `timeout`; decimal OK). Total wall time ~ this value |
| `LOADOUT_CFG_ONLINE_DETECT_HOSTS` | `github.com:443 raw.githubusercontent.com:443 pypi.org:443` | Space-separated `host:port` pairs probed in parallel. Override in `user/config.sh` to use corporate mirror hosts |
| `LOADOUT_CFG_USE_LOADOUT_MODULES` | `0` | Source `modules-init.bash` on shell startup (selects the loadout-bundled Environment Modules install by sourcing its native `init/bash`). Off by default -- opt-in per user/site layer |
| `LOADOUT_CFG_PRESERVE_FUNCTIONS` | `module _module_raw ml` | Space-separated function names exempted from the clean-slate `unset -f` in `envs/bash/bashrc` (which clears all functions so a re-source / `exec bash` starts fresh). Listed names survive that reset -- e.g. Environment Modules functions inherited via `export -f` from a parent shell. As an exported scalar it is in the env before config.sh re-sources, so it applies on the very `exec bash` that would otherwise wipe them. Empty = clear all |

### Key Functions (`envs/bash/functions.sh`)

- `path_append`, `path_prepend`, `path_remove`, `path_trim` -- PATH colon-list manipulation
- `path_prepend_if_dir [VAR] DIR`, `path_append_if_dir [VAR] DIR` -- prepend/append `DIR` only if it exists and is not already present; one arg targets PATH, two targets the named colon-list variable (e.g. `path_append_if_dir LD_LIBRARY_PATH /opt/lib`)
- `source_if_exists` -- source file only if readable
- `is_truthy` -- boolean check (`1`/`true`/`yes`/`on`/`enabled` -> true)
- `fpcmp N OP N` -- floating-point comparison (`fpcmp 2.17 -gt 2.0`)
- `vercomp`, `verlte`, `verlt`, `ver_between` -- version string comparison
- `array_slice` -- Python-style array slicing (`array_slice 1:-1 "${arr[@]}"`)
- `join_by` -- join array with delimiter
- `auto_attach_to_tmux` -- attaches/creates tmux session if `LOADOUT_CFG_ATTACH_TO_TMUX` set (available for manual call from user layer)
- `loadout_detect_online [timeout]` -- parallel TCP probe against `LOADOUT_CFG_ONLINE_DETECT_HOSTS`; returns 0 (reachable) or 1 (blocked). Called automatically by bashrc when `LOADOUT_CFG_ENABLE_ONLINE_UPDATES=auto`; callable from user layer scripts
- `loadout_add_precmd <fn>` -- register a before-prompt callback portably: appends to `precmd_functions` when a preexec framework (bash-preexec/ble.sh/wezterm) is live, else prepends to `PROMPT_COMMAND`; never clobbers an existing driver, dedups on re-source. Used for `loadout_restore_echo`. See *Prompt & shell integration*
- `loadout_find_wezterm_shell_integration` -- resolve the vendored/installed `wezterm.sh` path (explicit var -> vendored copy -> wezterm-binary-relative -> shared prefix; never `/etc`); echoes first match
- `loadout_restore_echo` -- before-prompt echo restore (re-enables `stty echo` only when actually off, preserving `$?`); no-fork, type-ahead-safe replacement for the old `stty '$(stty -g)'` snapshot
- `unset_bashrc_local_vars` -- unsets all `_*` variables before bashrc exits

### Prompt & shell integration

The prompt block in `envs/bash/global/bashrc` is **clobber-sensitive** -- treat it as load-bearing, not boilerplate. Two facts drive its shape:

1. **The loadout does not own `PROMPT_COMMAND`**, and **Starship does not always hook through it.** `starship init bash` auto-detects an active preexec framework: with `precmd_functions` (bash-preexec) or `ble.sh` it registers `starship_precmd` into the **array** and leaves `PROMPT_COMMAND` alone; only with no framework does it use `PROMPT_COMMAND`.
2. **A framework is often already live at login.** `/etc/profile.d/wezterm.sh` (+`vte.sh`) load bash-preexec and register `precmd_functions` + a `PROMPT_COMMAND` install stub *before* our `bashrc`. Our clean-slate `unset -f $(declare -F ...)` then deletes those framework functions, leaving dangling references.

The old code (`unset PROMPT_COMMAND` + `export PROMPT_COMMAND="/bin/stty '$(stty -g)';$PROMPT_COMMAND"`) wiped the framework's driver, so `starship_precmd` never fired -- **Starship prompt absent on the first login shell but present after `exec bash`** (non-login shells never read `/etc/profile`, so no framework). The block now runs, in this fixed order: **(1)** reset framework state (`unset precmd_functions preexec_functions __bp_imported bash_preexec_imported PROMPT_COMMAND`) -> **(2)** source the loadout-owned `envs/bash/global/wezterm/wezterm.sh` (re-installs working bash-preexec + wezterm hooks from user-writable space; serves raw wezterm and tmux-in-wezterm; off-WezTerm shells set the integration skip vars while sourcing so no WezTerm OSC hooks register) -> **(3)** `eval "$(starship init bash)"` and let it self-hook (never `unset`/overwrite `PROMPT_COMMAND` around it) -> **(4)** `loadout_add_precmd loadout_restore_echo`. This converges login and `exec bash`, and serves the full terminal matrix (raw wezterm, tmux-in-wezterm, tmux-in-st, st/xterm, `dumb`/`linux`). Verify with a **real PTY** (tmux send-keys), never `bash -lic` (no prompt cycle -> bug hides), and test both login and `exec bash`. Full rationale: `envs/bash/global/README.md` -> "Prompt & shell integration"; agent guardrail in `AGENTS.md` -> "Lessons Learned".

### Notable Aliases (`envs/bash/global/bashrc`)

**Navigation:**
- `b` / `bb` / `bbb` ... `bbbbbbbbbb` -- `cd ..` up 1-10 levels
- `cdd` / `cddd` / `cdddd` ... -- cd to N-th most recently modified directory
- `cd-` -- `cd -` (previous directory)
- `p` -- print and save cwd to `/tmp/p_dir`; `cdp` -- cd back to it
- Custom `cd()`: accepts file path (goes to parent), offers to create missing dirs with `mkdir -p`, runs `ls` after

**Listing:**
- `ll` / `lr` / `sl` / `rl` -- all alias to `ls`
- `lh` -- `human_readable=1 ls`
- `la` -- `list_all=1 ls`
- `lg` -- `show_group=1 ls`
- `lah` / `lha` -- both size and all

**Editing:**
- `vi` / `vim` -- `LOADOUT_CFG_PREFERRED_VI`
- `vic` -- nvim with clean vimrc only
- `vii` -- open most recently modified file
- `vid` -- diff mode
- `fvi` -- open fzf-selected file
- `v` -- `nvim -n -R -` (read stdin, read-only)
- `new` -- touch + chmod +x + open

**Search:**
- `g` -- `rg --smart-case --search-zip --hidden --no-ignore`; fallback grep searches stdin when piped and recursively searches `.` only when stdin is a TTY
- `sg` -- same but limited to 100K files
- `gv` -- inverted grep
- `gf` -- fixed-string grep
- `gpy` / `gtcl` -- grep Python / Tcl files
- `f` -- `fd --unrestricted --full-path` (falls back to `find .`)
- `h` -- `history | g`
- `hg` -- `history | grep -i`
- `gah` -- grep all bash history files across all PIDs

**Git:**
- `ga` -- `git add [all]` then `git status`
- `gs` -- `git status`
- `gc` -- `git commit`
- `gp` -- `git push`
- `gd` -- `git d`
- `gsp` -- pull with a temporary tracked-change stash only when needed; never pops an older unrelated stash

**Utilities:**
- `cat` -- `bat --paging=never` when `LOADOUT_CFG_PREFERRED_CAT=bat` and bat is available; `catp` -- bat with paging
- `t` -- `exec bash` (reload shell)
- `lns` -- safe symlink (removes existing link first)
- `latest` -- create/follow a `latest` symlink to a dir, then cd into it
- `w` -- `type -a` (where is this defined?)
- `x` -- `chmod +x`
- `rs` -- rsync with progress, no `.snapshot/`
- `du` / `dum` -- disk usage sorted by size (GB/MB)
- `rm` -- `rm -f`
- `mkdir` -- `mkdir -p`
- `we` -- `watchexec --clear --poll 500`
- `extract_rpm` -- `rpm2cpio | cpio -idmv`
- `zhead` -- zcat + head
- `rp` -- realpath (cwd if no arg)
- `gzip` / `gunzip` -- pigz / unpigz when available
- `vnc` -- start VNC server (no args) or pass through to vncserver

When adding a bash function whose name may already be an alias from a system,
site, or earlier layer, unalias it first. Interactive bash expands aliases while
parsing sourced files, so `df() { ... }` can become `df -h() { ... }` and fail
on `exec bash` even though `bash -n` passes. Use:

```bash
unalias df 2>/dev/null || true
df() { ...; }
```

## Component Reference

### Tmux (`envs/tmux/tmux.conf`)

- Prefix: `Ctrl-\`
- Pane navigation: `Shift+arrows`; Pane resize: `Prefix+arrows` (repeatable)
- Window navigation: `Ctrl+left/right`; Window reorder: `Ctrl+Shift+left/right`
- Layout presets: `Prefix+1-5`; 4-pane layout: `Prefix+o`; Reload: `Prefix+r`
- Capture pane buffer to nvim: `Prefix+v`
- Plugins: tmux-resurrect (save: `Prefix+Ctrl-s`, restore: `Prefix+Ctrl-r`), tmux-continuum (auto-save every 60min), tmux-better-mouse-mode

### PowerShell (`envs/powershell/Microsoft.PowerShell_profile.ps1`)

Key aliases: `ls`/`lr` -> eza, `vi` -> nvim, `f` -> fd, `cat` -> bat, `g`/`grep` -> rg, `b`/`bb`/`bbb` -> cd up, `cdd` -> cd to most recently modified dir, `gs`/`gc`/`gp`/`gd`/`ga`/`gsp` -> git shortcuts, `w` -> `Get-DefinitionPath`.

Integrations (conditional, cached init): zoxide (`z`/`zi`), PSFzf (`Ctrl+T` file picker, `Ctrl+R` history), Starship prompt. Falls back gracefully when tools absent.

`Invoke-PatchDOSStub` -- byte-patches DOS stub string in exe to change its hash, useful for bypassing SentinelOne hash-based flagging of tools like AutoHotkey.

coreutils wrappers (via Git for Windows path): `rm`, `cp`, `mv`, `diff`, `rmdir`, `mkdir`, `wc`, `sed`, `awk`, `cut`, `xargs`.

### AutoHotKey (`envs/autohotkey/hotkeys.ahk`)

Requires AHKv2. `hotkeys.ahk` single flat script. `loadout.ps1` copies it to `%USERPROFILE%\autohotkey\hotkeys.ahk`. The script reads its feature config from `%USERPROFILE%\loadout_keys.toml` at startup (override path via `LOADOUT_KEYS_TOML`; `--print-config` dumps the resolved config and exits). Undefined settings fall back to defaults (`[autohotkey].enabled` default true; every optional feature default off). Set `[autohotkey].logging = true` to append timestamped runtime diagnostics (SSID resolution, Cisco VPN skip decision, auto-login actions) to `<scriptdir>\hotkeys.log` via the `loadout_log` helper; off by default.

Key hotkeys:
- `Ctrl+Alt+R` -> reload script
- `Ctrl+Alt+A` -> pause/resume all hotkeys
- `Ctrl+Alt+V` -> toggle VPN auto-login when Cisco VPN feature enabled

Optional features:
- `corp-logins` -- corp credential entry hotkeys using `CORP_UID` / `CORP_PASSWORD`
- `mouse-wiggle` -- idle mouse nudge; set `AHK_ENABLE_MOUSE_WIGGLE=false` to suppress
- `cisco-secure-client-vpn` -- Cisco Secure Client reconnect + credential automation; skips when current Wi-Fi SSID is listed in `[autohotkey.features.cisco-secure-client-vpn].skip_wifi_ssids`
- `password-manager` -- `Ctrl+Alt+B` types `PWMANAGER_PASSWORD` + Enter
- `tmux-hotkeys` -- `RAlt`/`RWin` zoom toggle and `Ctrl+;` last-pane toggle for tmux
- `f1f2f3-as-mouse-buttons` -- F1/F2/F3 mouse remaps for mspaint/etxc/wezterm-gui
- `thinlinc-reconnect` -- auto-dismiss ThinLinc "Connection error" dialogs, relaunch `tlclient.exe`, auto-fill Server/Username/Password from `THINLINC_SERVER` / `THINLINC_USERNAME` / `THINLINC_PASSWORD` (pings server before launching/connecting; user-initiated closes respected). `Ctrl+Alt+T` shows live diagnostic (tick count, last-seen state, env, window matches, ping).

Existing `%USERPROFILE%\loadout_keys.toml` files with legacy plugin IDs (`[autohotkey.plugins]`, numeric-prefixed ids) remain accepted: the script maps them onto current feature ids at startup.

**Layer architecture** (analogous to bash `global->corp->site->team->project->user`): `envs/nvim/init.lua` thin dispatcher that sources `config.lua` per layer (Phase 1), bootstraps lazy.nvim (Phase 2), collects plugin specs from each layer's `plugins/` dir via `{ import = "LAYER.plugins" }` (Phase 3), sources `init.lua` per layer (Phase 4). `vim.g.cfg_*` variables set in `global/config.lua` are defaults; later layers override. Plugin manager: Lazy.nvim (plugin stash installed offline from the gitignored GitHub release asset `envs/nvim/vendor/plugins/nvim-plugin-stash.tar.bz2`; catalog manifest in `envs/nvim/package.json`). Key plugins: blink.cmp, snacks.nvim, gitsigns.nvim, conform.nvim, nvim-lint, nvim-treesitter, tokyonight.nvim. `vim.g.cfg_dpc` guards update-checker and notifications on offline machines. `vim.g.loadout_plugins_enabled` false when lazy.nvim bootstrap fails offline -- core editor still starts cleanly.

Snacks dashboard provides no-argument `nvim` startup screen (`filetype=snacks_dashboard`). `mini.trailspace` highlights trailing whitespace with window-local matches, so dashboard cleanup must disable `vim.b.minitrailspace_disable`, turn off local `list`, delete existing `MiniTrailspace` matches on dashboard open/update.

### Vim (`envs/vim/vimrc`)

Native Vim 8 package management. Plugins in `envs/vim/pack/vendor/{start,opt}/`. Basic settings: UTF-8, 4-space tabs, line numbers.

### Modern CLI Tools Expected

`eza`, `bat`, `rg` (aliased `g`), `zoxide`, `fzf`, `fd`/`fdfind`, `grc`, `pigz`

Falls back gracefully: eza -> lsd -> ls, bat -> cat, fd -> find. Handles Debian (`batcat`, `fdfind`) vs RedHat naming.

## Git Hooks

**pre-commit**: Scans for embedded `.git` dirs in subdirectories, removes them, re-stages. It prunes the repository's own top-level `.git` before scanning, so sandbox/worktree internals such as `./.git/.git` are ignored. Required because bundled plugins (tmux, vim) include own `.git` dirs causing "embedded git repository" warnings.

## Common Patterns

### Add a layer override

```bash
# Create the file -- it will automatically override global/
envs/bash/user/config.sh      # LOADOUT_CFG_* variable overrides
envs/bash/user/bashrc         # alias/function overrides
envs/bash/corp/global_hooks/5.sh  # hook injection at point 5
```

### Add a new bundled plugin (vim/tmux)

1. Copy plugin dir into `envs/vim/vim/pack/vendor/start/` or `envs/tmux/vendor/plugins/`
2. Pre-commit hook strips `.git` dirs automatically on next commit
3. Relevant env handler (`_install_env_vim` / `_install_env_tmux`) already copies the whole vendor dir with delete semantics -- no installer change needed.

### Stable-release policy for bundled binaries

All bundled tools must come from **stable tagged releases** -- never from git HEAD, nightly branches, or dev builds. Tagged releases have known changelogs, upstream testing, verifiable provenance.

**Exception -- first-party rolling-git tools.** Projects we own (currently `liberty-tools`, `text-serdes`, `time-plot` under github.com/smprather) may be tagged `"rolling_git"` in `packages.json` and built fresh from source HEAD by `./build/update` (see *Rolling-git wheel behavior*). Their `packages.json` version is a `git describe` string, not a release tag. The stable-release rules below apply only to third-party bundled tools.

**Rules:**
- All `build/build-*.sh` scripts require `--tag vX.Y.Z` (enforced at runtime).
- Tag must be stable release tag from tool's official GitHub releases page.
- Dev builds (e.g. `nvim 0.13-dev`, `micro 2.0.16-dev`) **not accepted** -- rebuild from latest stable tag.
- Source builds with long upstream release cycles (tmux, bash) acceptable but must use most recent **stable** tag, not HEAD.
- Some tools have no EL8-compatible official prebuilt (e.g. nvim -- official releases require GLIBC_2.34, EL8 has 2.28). These must be source-built from stable tag on EL8 build machine. Bundled binary still stable; just compiled locally.
- Opt-in unstable stream may be added in future; until then, all bundled binaries must be stable.

**Verify provenance after adding:**
```bash
build/verify-binaries          # check all tools
build/verify-binaries rg bat   # check specific tools
```
Tools built from EL8 source (different NEEDED libs than upstream musl/gnu release) or with patchelf layout deltas documented in `verify-binaries`'s `_SKIP_REASONS` / PASS reasoning; all must still come from tagged releases.

### Add a new pre-built binary

**MANDATORY: Record build notes in `build/ADDING_BINARIES.md` before committing.**

Every tool added to this repo -- whether built from source, extracted from an RPM, or
imported from a portable archive -- MUST have its final build procedure documented in
`build/ADDING_BINARIES.md`. The note must be complete enough that anyone can
reproduce the build without re-deriving anything. Optional: document failed approaches
and pitfalls. Required: the working procedure.

Minimum content for a build note:
- Tool name and version
- Prerequisites (`dnf install`, toolchain enable, etc.)
- Configure/cmake/cargo flags actually used (not a template -- the real flags)
- Any patches applied to source code (full before/after if the change is non-trivial)
- Packaging steps: strip -> patchelf -> bzip2, with exact commands
- Any non-obvious quirks (e.g. binary lands in wrong prefix, GCC 14 compat flags needed)

See existing entries in `ADDING_BINARIES.md` (gnuplot, octave, gvim, nedit-ng, nvim-qt,
xterm, expect) as examples of the required level of detail.

```bash
bzip2 -k mybinary
cp mybinary.bz2 payload/el8.x86_64.glibc2p28/bin/
./build/strip-all-elf-binaries          # strips, updates .strip-manifest
git add payload/ .strip-manifest
git commit                        # pre-commit hook re-strips and re-records
```

For shared libraries, put `.bz2` in `lib64/` instead.

### Import or update portable Python

```bash
build/import-portable-python /path/to/portable-python-X.Y.Z-tag/
# Do NOT run strip-all-elf-binaries on the result -- BOLT-optimized, already in NOSTRIP list
git add payload/ .strip-manifest
git commit
```

### Query installed binary versions

```bash
build/farm-versions --format text    # aligned table
build/farm-versions --format tsv     # for spreadsheets / README tables
build/farm-versions --format json    # machine-readable
build/farm-versions --missing-only   # find gaps
```

When adding new binary, add entry to `TOOLS` in `farm-versions` with right strategy.

### Check bundled versions against upstream

```bash
build/check-versions                 # current vs latest, text table
build/check-versions --outdated-only # only rows where current < latest
build/check-versions --include-na    # include pkgs with no upstream API
build/check-versions --format tsv    # tab-separated, for spreadsheets
build/check-versions --format json   # machine-readable
build/check-versions --offline       # skip network; just list current versions
```

Reads `packages.json` for bundled `version` and `farm-versions`'s TOOLS table for homepage URLs. Queries `api.github.com/.../releases/latest` (falling back to `/tags`) for GitHub-hosted projects and `pypi.org/pypi/<name>/json` for `python-tool` packages with `uv_tool` field. Authenticates against GitHub via `$GITHUB_TOKEN`/`$GH_TOKEN` or `gh auth token` for 5000/hr authenticated quota vs 60/hr unauthenticated. Packages whose homepage isn't on GitHub/PyPI marked `n/a` (skipped from default view).

### Create a GitHub release

**Follow [`docs/RELEASE.md`](docs/RELEASE.md).** It is the authoritative, ordered
procedure -- release class, auth-at-kickoff, the currency sweep, security-data
refresh, the mandatory post-payload chain, assurance re-pin, doc sync, gates by
class, post-publish verification, and a catalogue of every mistake that has
actually shipped. `./build/release` runs the *gates*; it cannot tell that a step
before it was skipped. The notes below describe what `./build/release` itself does.

```bash
./build/release              # runs pre-release gates, then tags + publishes
./build/release --dry-run    # pre-release gates only, no tag or GitHub release
./build/release --tag v2026.05.12   # explicit tag instead of today's date
./build/release --no-cache   # re-run the smoke test + malware scan even if a cached pass matches
./build/release --clear-cache   # delete cached smoke/scan results first, then run fresh
```

`./build/release` starts independent pre-release gates in parallel: `scan-for-malware`, `tests/prebuilt-binaries`, `build/farm-versions --format tsv`, and `sha256sums.txt` generation. The final tag/GitHub-release step waits for those gates and is blocked if the malware scan, binary smoke, or checksum generation fails. `scan-for-malware` caches only clean verdicts under `${XDG_CACHE_HOME:-~/.cache}/engineering-loadout/malware-scan-v1/`; the key hashes the source scan corpus, scanner script, vendored YARA binary/rules/tag, scan flags, and ClamAV engine/signature fingerprint. Use `./build/scan-for-malware --no-cache` to force a fresh scan and `--clear-cache` to delete cached clean results. The binary smoke installs `@shared` into a temp `--dest-dir`, then probes every executable in `<dest>/local/bin` with `PATH=<dest>/local/bin:/usr/bin:/bin:/usr/sbin:/sbin` so staged wrappers cannot accidentally call binaries from the build host or the user's `~/.local/bin`. The version table feeds release notes.

**Binary-smoke content cache** (release-time only): the ~4.5 min smoke test is the slowest gate, and its result is a pure function of the bytes it installs + the code that installs/probes them, so `./build/release` caches a *pass* under `${XDG_CACHE_HOME:-~/.cache}/engineering-loadout/release-smoke-v1/` and reuses it when the fingerprint is unchanged. The fingerprint parallel-hashes **actual bytes** -- all of `payload/**` plus `loadout`, `loadout_main.py`, and `tests/prebuilt-binaries` -- deliberately a *superset* of what `@shared` installs (a missed input would false-green a shipped-but-untested binary; an extra input only costs a needless re-run). It is keyed with the platform `uname`+glibc and only ever caches `returncode == 0`. The hash runs inside the smoke worker thread, overlapping the parallel version gate, so a cache hit turns the slowest gate into a few-second hash. The cache lives in `./build/release`, not in `tests/prebuilt-binaries`, so the test invoked directly (or via `tests/run-all`) **always** runs. `--no-cache` / `--clear-cache` force a fresh run.

**nvim plugin stash reuse**: the ~328 MB stash rides as a release **asset**. A routine re-release whose stash bytes are unchanged reuses the existing release's asset instead of re-uploading it: the release object is kept (it holds the asset) and only the tag is moved, so the path must **undraft** the release (GitHub drafts a release whose tag was deleted, and recreating the tag does not republish) and clobber only the small assets. Reuse is gated on a signed tag plus a byte-match (present asset + size + matching SHA-256 in the previous release's `sha256sums.txt`), and after republishing `release` re-reads the release and asserts it is published (not an invisible draft) and still carries the stash -- self-healing with a full upload on any doubt rather than shipping a broken release.

### Testing policy

**Stock EL8 is the verification baseline for install behavior; the dev box is not.** The dev machine is far from stock, so anything that touches install behavior, payload paths, or repo layout must pass the clean-container gate before it is trusted (build-box masking is a recurring failure class -- see the NSS/firefox and octave support-lib incidents).

- `tests/run-all` -- single suite entry point. Default runs Tier 1 (syntax/lint, resolver/registry/tar safety, payload and generated-file sync, assurance, installer/wrapper checks) plus Tier 2 (font/modules/env/optional-package/parity-plot installs, fresh-home and split deployments, nvim deployment, completion and crate-store checks). `--fast` stops after Tier 1; `--container` adds Tier 3.
- Tier 3: `tests/prebuilt-binaries-almalinux8 --full` -- inside a clean `almalinux:8.10` container (repo mounted read-only, copied inside, bundled Python cold-bootstrapped through `./loadout`): doctor, resolver dry-runs, completion diff, the unit/registry/tar-safety tests, the fresh-user temp-HOME install, the split shared/envs install, and the full binary/runtime probe. Expected host-contract skips are explicit: `cloc` needs host Perl, `meld` needs EL8 `/usr/bin/python3.6`, GL GUI apps need host GLVND/OpenGL dispatcher libs (`libGL.so.1`, etc.), and `firefox` / `idle3` / `idle3.14` need host CAPABILITIES rather than libraries -- user namespaces and a loadable Tk respectively. Those three are gated by `HOST_REQUIRED_CAPABILITIES`, which PROBES the facility (`unshare -U true`, `python3.14 -c "import tkinter"`) and skips only when it is genuinely absent, so on a capable host they must still exit 0. **The probe's pass condition is exit 0**; any non-zero exit needs an `EXPECT_NONZERO` entry pinning flags, code and required output. The old rule accepted anything outside `{126,127,139}`, which scored 42 of 300 binaries green on a non-zero exit -- several off their own error text.
- Pure-Python unit tests (`tests/unit-resolver`, `tests/registry-integrity`) run locally under the bundled Python 3.14 -- `loadout_main.py` uses PEP 758 syntax that older interpreters cannot parse.
- `tests/install-split-shared-envs` is the production deployment shape: `@shared` into a temp non-home tree, then Bash-only `@envs` into a separate temp HOME with `LOADOUT_CFG_SHARED_PREFIX=<shared>/local`; smokes Bash startup, shared PATH, terminfo, WezTerm completions, and core tool startup.

GitHub auto-generates `Source code (tar.gz)` and `Source code (zip)` containing full repo.

### History

Per-PID history files at `$XDG_RUNTIME_DIR/bash_history.$$`. Child bash inherits parent history. New shells start from most recently modified history. `HISTSIZE=10000`, `HISTCONTROL=ignorespace:erasedups`.
