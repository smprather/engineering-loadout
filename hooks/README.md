# Git Hooks

Git hooks for this repo. Install manually when developing this repo:

```bash
cp hooks/* .git/hooks/ && chmod +x .git/hooks/*
```

## pre-commit

Four steps, in order. The hook never runs `git add -A`: every re-stage names
the paths it means, so untracked files stay out of the commit.

1. **Embedded `.git` cleanup.** For each path this commit stages that is an
   embedded repository (a staged gitlink -- a directory with its own `.git`),
   removes that `.git` and re-stages the directory as plain files. Nothing else
   in the worktree is looked at: local clones kept in ignored directories are
   left alone, and an untracked (not ignored) repository only gets a note.
   **Why:** bundled plugins (tmux, vim) arrive with their own `.git`;
   committing them as-is creates "embedded git repository" gitlinks instead
   of files.
2. **Strip ELF payloads.** When staged paths look like binaries or archives
   (`bin/`, `lib64/`, `parser/`, `*.so`, tarballs), runs
   `build/strip-all-elf-binaries` with the bundled interpreter on `PATH` and
   re-stages the candidates, converted `.tar.bz2` names and `.strip-manifest`.
3. **Python syntax + format.** Staged Python files (`.py` and extensionless
   files with a python shebang, excluding `installer_vendor/`) are compiled
   with the bundled interpreter (the label shows its real version; the error
   file is a `mktemp` under `$TMPDIR`), then `ruff format` and
   `ruff check --fix`.
4. **Chunk large payload files.** A staged `payload/` file over 40 MiB is split
   by `build/strip-all-elf-binaries --chunk-only` (bundled interpreter on
   `PATH`) and its chunks re-staged. If chunking fails, or a file is still over
   40 MiB afterwards, the commit is blocked.

The bundled interpreter is found the way `./loadout` finds it: the default
install root, then `~/.local/bin`, then this clone's `.loadout-bootstrap`; the
minor version comes from `loadout_main.py`'s `_BUNDLED_PY`.

`tests/pre-commit-hook` (Tier 1) runs the hook in a throwaway repo.

**Always install this hook** when developing this repo or working with bundled
plugins. Normal end-user installs do not need repo git hooks.
