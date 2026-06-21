# Git Hooks

Git hooks for this repo. Install manually when developing this repo:

```bash
cp hooks/* .git/hooks/ && chmod +x .git/hooks/*
```

## pre-commit

Scans for embedded `.git` directories in subdirectories, removes them, and
re-stages the affected files before the commit proceeds. The hook deliberately
prunes the repository's top-level `.git` directory before scanning; it must not
treat sandbox or worktree internals such as `./.git/.git` as vendored repos.

**Why:** Bundled plugins (tmux, vim) include their own `.git` directories.
Committing them as-is produces "embedded git repository" warnings and can
accidentally create git submodules. This hook strips them so they're committed
as plain directories.

**Always install this hook** when developing this repo or working with bundled
plugins. Normal end-user installs do not need repo git hooks.
