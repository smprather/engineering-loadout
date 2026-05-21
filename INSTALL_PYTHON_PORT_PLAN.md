# Python Installer Port Plan

> **Status: COMPLETED.** `install` is now the Python 3.6-compatible executable directly
> (shebang `#!/usr/bin/python3`). No separate Bash shim was needed.

## Goal

Replace the growing Bash installer implementation with a Python 3.6-compatible
installer while keeping `./engineering-loadout` as the stable command entrypoint.

## Constraints

- Target systems guarantee Python 3.6.
- Preserve offline-first, no-root behavior.
- Preserve current CLI flags and observable install behavior.
- Do not require network access during install.
- Keep `tests/install_linux_tmp_home` as the main behavior contract.
- Ask before destructive Git/repo operations. Normal file edits for this port
  are expected; no `git reset`, destructive checkout, or force push.

## Implementation Steps

1. Add `install.py`.
   - Use only Python 3.6-compatible syntax and standard library.
   - Keep subprocess calls for existing system tools: `rsync`, `unzip`,
     `mkfontscale`, `mkfontdir`, `fc-cache`, `patchelf`, `ldd`.
   - Resolve the repo from the script path, not the current working directory.
   - Resolve repeated `--post-install-hook` paths before changing to `$HOME`.

2. Replace `install` with a small Bash shim.
   - Find `python3`.
   - Execute `install.py` next to the shim.
   - Preserve argument forwarding.

3. Preserve install behavior.
   - Copy mode and dev mode. `--links` has been retired.
   - Bash layer preservation for `corp`, `site`, `project`, and `user`.
   - Managed shell entrypoint symlinks:
     `~/.bashrc`, `~/.bash_profile`, `~/.bash_login`, `~/.profile`.
   - Backup behavior, including font-file excludes.
   - Absolute `LOADOUT_BACKUP_DIR` for hooks.
   - Multiple post-install hooks in argument order.
   - Optional font install from top-level `fonts/`.
   - Pre-built binary install from `pre_built/<platform>/`, RPATH is pre-baked
     in repo binaries (no runtime patchelf step), `ldd` warnings on install.
   - Vendored Tree-sitter plugin/parser install.
   - `--dev` git hook install only.
   - Automatic layer `install.sh` sourcing/execution behavior after explicit
     hooks.

4. Update docs.
   - `README.md`, `CLAUDE.md`, `AGENTS.md`, `.github/copilot-instructions.md`
     should note that `./engineering-loadout` is a Bash shim over Python.
   - Keep cold-start notes current.

5. Validate.
   - `bash -n install`
   - `python3 -m py_compile install.py`
   - `bash -n tests/install_linux_tmp_home`
   - `git diff --check`
   - `./tests/install_linux_tmp_home`
   - Direct `./engineering-loadout --help` sanity check.

## Handoff Notes

- If parity fails, compare install output and temp-home tree against the last
  Bash behavior, but prefer fixing Python rather than restoring Bash.
- Keep the old Bash installer available from Git history; do not add a second
  live installer unless rollback is explicitly requested.
