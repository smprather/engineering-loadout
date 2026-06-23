# Current Handoff

Last updated: 2026-06-22.

## Repository State

- Branch: `main`
- Remote: `origin/main`
- Work expected to be merged: none. `fix/bash-prompt-wezterm-integration` and
  `ahk-plugin-dev` were merged/deleted; `git branch -a --no-merged main` should
  be empty.
- Recent loadout/bundling work is in `main` through:
  - `a46e26a` - document env install and shell startup gotchas
  - `9a02e0f` - fix env sync over repo symlinks
  - `15f071e` - harden shared loadout smoke coverage
  - `d2427b0` - restore Starship prompt on login and own WezTerm shell integration

## Verified Test Gates

These checks passed after the recent changes:

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
