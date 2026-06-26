# Current Handoff

Last updated: 2026-06-26.

## Repository State

- Branch: `main`
- Remote: `origin/main` (in sync after the latest push)
- Latest work on `main` (all pushed): the offline **Rust toolchain + crate
  store** (build + rebuild the loadout's own rust tools with no crates.io
  access), the `liberty-tools` wheel bump, the `scan_for_malware` chunk/store
  coverage fix, the merged Windows PowerShell 7.6.3 bundle + AHK robustness
  work, and this cold-start Markdown sync.
- Current uncommitted work at this handoff: the cold-start Markdown sync (this
  file plus `README.md`, `CLAUDE.md`, `AGENTS.md`,
  `.github/copilot-instructions.md`, `docs/ARCHITECTURE.md`,
  `docs/INSTALLATION.md`); committed together with the README package-table
  squaring (rust rows + liberty-tools version).
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
  `python3 -m py_compile loadout_main.py`, and `bash -n bash/global/bashrc`.
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
  hooks/pre-commit`, `bash -n bash/global/aliases.sh bash/global/bashrc
  bash/bashrc`, `zsh -n zsh/zshrc`, `python3 -m json.tool
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
- The prompt/WezTerm/Starship block in `bash/global/bashrc` is order-sensitive;
  verify with a real PTY, not only `bash -lic`.
