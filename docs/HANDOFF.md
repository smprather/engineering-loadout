# Current Handoff

Last updated: 2026-06-27.

## Recent Integration

AutoHotkey runtime-config refactor was integrated from
`0001-ahk-read-feature-config-from-loadout_keys.toml-at-ru.patch`.
`envs/autohotkey/hotkeys.ahk` now reads `%USERPROFILE%\loadout_keys.toml` at startup
instead of having feature booleans stamped in by `loadout.ps1`.

Touched areas: `envs/autohotkey/hotkeys.ahk`, `loadout.ps1`,
`envs/autohotkey/test-run.ps1`, and cold-start docs. The AHK script also now has
`LOADOUT_KEYS_TOML` override support, `--print-config`, gated
`[autohotkey].logging`, and Cisco VPN SSID fallback through the
WLAN-AutoConfig event log when `netsh` reports no SSID.

`envs/bash/global/bashrc` now keeps the vendored WezTerm script as the bash-preexec
source outside real WezTerm sessions, but sets the integration skip vars while
sourcing it so semantic zones, user vars, and cwd OSC hooks do not register.
This prevents GNOME Terminal/tmux from printing raw OSC text and avoids prompt
stalls in `wezterm set-working-directory` when the loadout's `wezterm` wrapper
is on `PATH` but no WezTerm mux/GUI exists.

The mate-terminal runtime archive now includes the minimal
`org.mate.interface.gschema.xml` alongside `org.mate.terminal.gschema.xml`.
Without it, `mate-terminal.bin` aborts at startup with
`Settings schema 'org.mate.interface' is not installed` while reading
`monospace-font-name`.

`install_fonts` now honors `--no-backup`: normal font installs still move an
existing `<local>/share/fonts` to `fonts.bak*`, but no-backup installs reuse the
directory in place and overwrite only matching vendored font files. It also
counts actual font members and displays a Rich progress bar during extraction.

`vcd-toggle-profiler` was added from `github.com/smprather/vcd-toggle-profiler`
using the C++ implementation. It ships as
`pre_built/el8.x86_64.glibc2p28/runtime/vcd-toggle-profiler.tar.bz2` with a
wrapper, real ELF, uPlot assets, and licenses. Build script:
`pre_built/build_scripts/build-vcd-toggle-profiler.sh`; it uses EL8 system
`/usr/bin/g++` 8.5 rather than upstream CMake Release because the latter enables
`-march=native`.

## Repository State

- Branch: `main`
- Remote: `origin/main` (in sync after the latest push)
- Latest work on `main` (all pushed): AutoHotkey runtime config from
  `loadout_keys.toml`, the bash prompt off-WezTerm OSC hook skip guard, the
  mate-terminal interface GSettings schema fix, the offline **Rust toolchain +
  crate store**, the `liberty-tools` wheel bump, the `scan_for_malware`
  chunk/store coverage fix, the Windows PowerShell 7.6.3 bundle, and AHK
  robustness work.
- Current uncommitted work at this handoff: font no-backup/progress fix,
  `vcd-toggle-profiler` C++ runtime package, regenerated loadout bash
  completion, focused tests, and cold-start docs.
- Work expected to be merged: none. The `rust-offline-crate-store` branch is
  fully merged into `main` and slated for deletion;
  `git branch --no-merged main` should be empty.
- Recent loadout/bundling work is in `main` through:
  - `3ab8b1e` - merge `origin/main` (Windows PowerShell 7.6.3 bundle + AHK)
  - `42759ba` - merge offline Rust toolchain + crate store branch
  - `213639c` - update `liberty-tools` wheel to `v2026.06.01.1-33-gdc193c1`
  - `ca115e5` - `scan_for_malware`: cover chunked archives + top-level `rust/`
  - `65fedc5` - add offline Rust toolchain + crate store
  - `5d27709` / `c3773fe` - Windows PowerShell bundle + AHK Wi-Fi gating
  - `2a933b9` - Windows execution-policy-safe `loadout.cmd` wrapper

## Verified Test Gates

These checks passed after the recent changes:

- Passed for this Markdown sync: `git diff --check`, `sh -n loadout`,
  `python3 -m py_compile loadout_main.py`, and `bash -n envs/bash/global/bashrc`.
- Passed for the AutoHotkey runtime-config patch integration: `git diff
  --check`, `sh -n loadout`, `python3 -m py_compile loadout_main.py`, and
  `bash -n envs/bash/global/bashrc`. Windows-only checks (`AutoHotkey64.exe
  /Validate`, PowerShell parser/test-run) still need a Windows or PowerShell
  environment; `pwsh` was not available in this Linux sandbox.
- Passed for the bash prompt off-WezTerm OSC hook skip guard: `git diff
  --check`, `bash -n envs/bash/global/bashrc`, non-PTY function-body smoke confirming
  no `__wezterm_*` hooks register off-WezTerm, and a real-PTY tmux smoke covering
  initial prompt plus `exec bash` with no `file://` / `tmux;` leakage.
- Passed for the mate-terminal schema fix: `python3 -m py_compile
  loadout_main.py`, temp `./loadout install mate-terminal --dest-dir ...`
  verified both XML schemas and `gschemas.compiled`, `mate-terminal.bin --help`
  returned 0, and a no-display launch reached only `Cannot open display` (no
  GSettings schema abort). Reinstalled `mate-terminal` into `~/.local` and
  verified the same `--help` behavior there.
- Passed for the font no-backup/progress fix: `tests/test_install_fonts_rejoin`,
  `python3 -m py_compile loadout_main.py`, `git diff --check`, `sh -n loadout`,
  and `bash -n envs/bash/global/bashrc`.
- Passed for `vcd-toggle-profiler`: build from local checkout, `strip_all_elf_binaries`
  archive rewrite, temp `./loadout install vcd-toggle-profiler --dest-dir ...`,
  installed wrapper run on `vcd-samples/random/random.vcd`, archive listing check,
  `ldd` on installed real ELF, and symbol-version check showing GLIBC floor
  <= 2.14 and GLIBCXX floor <= 3.4.21.
- This Markdown sync already reconciled user/agent docs with the current
  Click/rich-click CLI surface: `--dest-dir` belongs after install-like verbs,
  visible selection uses positional `PKG...` args (no user-facing `--only` /
  `--add`), backups restore via `./loadout snapshot restore <path>`, Windows
  installs prefer `.\loadout.cmd`, and the README package table is generated
  from `pre_built/packages.json` for all non-env/non-font installables.
- Offline Rust gates: `pre_built/build_scripts/test-rust-offline-almalinux8`
  (runs `--network none`) installs `@rust` to `$HOME` then `--dest-dir`,
  compiles a user crate in each, and rebuilds `ripgrep 15.1.0` from the bundled
  crate store. `models` + `ripgrep` also verified building fully offline.
- Malware scan clean: `scan_for_malware` (now rejoins chunked `.part-NNN`
  archives and scans the top-level `rust/` store); ClamAV 1.4.3 reported 0
  infected over the Rust toolchain (74 files) and crate store (2101 `.crate` ->
  3285 files, 5.96 GB).
- `tests/install_split_shared_envs`
- `pre_built/build_scripts/test-prebuilt-binaries`
- `pre_built/build_scripts/test-prebuilt-binaries-almalinux8 --no-build`
- temp `HOME` `./loadout install @envs --no-backup`
- temp `HOME` env install with `~/.config/nvim/{after,lsp}` symlinked back into
  the repo, confirming symlinked config dirs are replaced before copying
- `XDG_CACHE_HOME=/tmp/codex-nvim-cache XDG_STATE_HOME=/tmp/codex-nvim-state nvim --headless +qa`
- static checks: `python3 -m py_compile loadout_main.py
  pre_built/build_scripts/test-prebuilt-binaries`, `sh -n loadout
  hooks/pre-commit`, `bash -n envs/bash/global/aliases.sh envs/bash/global/bashrc
  envs/bash/bashrc`, `zsh -n envs/zsh/zshrc`, `python3 -m json.tool
  pre_built/packages.json`, `git diff --check`

## User-Home Follow-Up

Resolved before context clear. A read-only check found no symlinks remaining
under:

```text
~/.config/nvim
```

The earlier `~/.config/nvim/lsp` and `~/.config/nvim/after` symlinks back into
the repo were removed or replaced. Re-run env install only when normal config
refresh is desired:

```bash
./loadout install @envs --no-backup
exec bash
```

## Recent Gotchas Captured In Docs

- Env config sync must never follow destination symlinks back into the repo.
  `sync_dir` removes symlinked destination directories, refuses source/dest tree
  overlap, and tolerates vanished source entries.
- Host `rsync` and host Python are optional conveniences only. `./loadout`
  bootstraps the bundled portable Python and uses Python recursive copy.
- `hooks/pre-commit` must prune `./.git/*`; sandbox/worktree internals such as
  `./.git/.git` are not embedded vendored repos.
- Bash startup functions whose names may already be aliases need
  `unalias name 2>/dev/null || true` before `name() { ...; }`.
- The prompt/WezTerm/Starship block in `envs/bash/global/bashrc` is order-sensitive;
  verify with a real PTY, not only `bash -lic`.
- `hotkeys.ahk` reads `loadout_keys.toml` at startup (reusing its partial TOML
  parser); the installer no longer stamps feature booleans. Override the config
  path with `LOADOUT_KEYS_TOML`; `--print-config` dumps the resolved config.
