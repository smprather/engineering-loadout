# Independent review items 4-10 + stale-lock advisory: fix report

Date: 2026-10-30
Base revision: `889e87c` (`docs(handoff): session-close open items ...`)
State: uncommitted working tree. Nothing in this report was committed.

This report is the external-review record for:

- items 4-10 left open by the 2026-10-30 independent `/code-review high`;
- the follow-up advisory that stale-lock reclamation in the new bootstrap
  claim was itself racy.

The working tree also contains the earlier fixes for review items 1-3 and an
unrelated pre-existing change to `assurance/release-timings.tsv`; those are not
part of this report.

## Result summary

| Item | Finding | Fix | Regression proof | Status |
|---|---|---|---|---|
| 4 | Own 0775 private dirs (UPG umask 002) were refused instead of tightened | Tighten any real dir owned by us to 0700; keep refusing foreign owners and symlinks | `tests/unit-private-state`; `tests/env-private-dirs` loose-dir cases | fixed |
| 5 | Two cold bootstraps could both extract; the loser's `rm -rf` could delete the tree the winner exec'd from. The temp sweep also PID-checked other hosts | Atomic `mkdir` claim; waiters poll `.complete`; host-qualified temps; sweep only same-host dead PIDs (foreign/legacy after a day) | `tests/shim-bootstrap`; 10-way concurrent stress | fixed |
| 5a | Advisory: two waiters could both reclaim the same stale claim, and the delayed waiter could `rm -rf` the fresh lock the first waiter re-acquired | Serialized reclamation through `.loadout-bootstrap.lock.reclaim`; owner re-read AFTER acquiring the recovery claim; same-host live PID never stale by age | Deterministic two-waiter slow-rm/slow-tar case: old code 2 extractions, fixed code 1 | fixed |
| 6 | `_place_staged_tree` rmtree'd a real directory when an archive had a file/symlink there | Raise `InstallRefused` instead; matches extractall's loud failure | `tests/unit-install-steps` file + symlink cases | fixed |
| 7 | A recommend whose own hard dep was skipped made the next `walk_depends` raise | `walk_recommends` drops the recommendation when its hard-deps closure cannot be satisfied | `tests/unit-resolver` skipped/disabled cases + end-to-end resolve | fixed |
| 8 | bash set `PYTHONPYCACHEPREFIX` after its non-interactive return while zsh/tcsh set it every startup | bash exports `PIP_REQUIRE_VIRTUALENV`, `PYTHON_KEYRING_BACKEND`, `PYTHONPYCACHEPREFIX`, `EGL_LOG_LEVEL` before the return | `tests/env-private-dirs` non-interactive cases | fixed |
| 9 | With `~/.config` symlinked outside HOME, an absolute `.tcshrc` was archived absolute and restore failed with `AbsoluteLinkError`; the realpath-based rewrite could also produce `../outside` | Lexical relpath from the link text; map real-target-under-HOME back lexically. Restore copies top-level entries individually so a backup dir can land on a symlinked `~/.config` | `tests/snapshot-restore` symlinked-config case; old traceback reproduced first | fixed |
| 10 | `M.data`'s doc block ran into `M.private_dir`'s; `M.data` had none | Moved the data-dir block back above `M.data` | nvim case in `tests/env-private-dirs` loads the file | fixed |

## Code changes

### Item 4: private dirs

- `loadout_main.py::_secure_private_dir`: accepts a real dir owned by our uid
  and tightens it to 0700. Foreign owner/symlink still warns and returns False.
  The message is now `(owner/symlink)`; mode is no longer a refusal reason.
- `payload/pending-daemon/loadout-pending-daemon::secure_pending_dir`: same
  rule.
- `envs/bash/functions.sh::loadout_private_dir` (shared with zsh): removed the
  group/other-write refusal; any mode other than 700 is chmod'd to 700.
- `envs/tcsh/global/helpers/private-dir`: same.
- `envs/nvim/lua/global/paths.lua::M.private_dir`: same; compares the
  permission bits to 0700 directly.
- Docs updated: `AGENTS.md`, `docs/BASH.md`, `envs/bash/global/README.md`,
  `envs/tcsh/README.md`, daemon/function docstrings.

Security rationale: a 0775 dir owned by the user under RHEL's UPG umask 002
has the user's own group as its group, so it is not a co-tenant substitution.
Refusing it made shells silently fall back and made the installer refuse to
stage until reboot/tmp cleanup. A foreign owner or symlink is still refused.

### Item 5: bootstrap claim

`loadout`:

- Cold bootstrap takes `mkdir "$boot_dir.lock"` (`.loadout-bootstrap.lock`).
- A concurrent first run polls `.complete`; it never extracts while a claim is
  held. After acquiring the claim the shim re-checks the stamp (a run may have
  published between the warm-cache probe and `mkdir`).
- Temp dirs are `.loadout-bootstrap.tmp.<host>.<pid>`.
- Sweep rules: same-host name + dead PID -> remove; foreign-host or legacy
  no-host name -> only after 1440 minutes (`find -mmin +1440`). This is the
  fix for `kill -0` on an NFS clone, where a local PID check says nothing
  about the other host.
- Claim owner file: line 1 hostname, line 2 PID.
- Reclamation (advisory fix): `.loadout-bootstrap.lock.reclaim` is an atomic
  recovery claim. Its holder re-reads the lock owner after acquiring it and
  removes the lock only if still stale. A waiter that loses the recovery claim
  never touches the lock. A same-host live PID is never stale regardless of
  age; a foreign or ownerless claim is stale after 5 minutes.
- A crashed reclaimer leaves `.loadout-bootstrap.lock.reclaim`; waiters fail
  closed after 120 s with a message naming both paths to remove manually.
- `.gitignore` now ignores `.loadout-bootstrap.lock*/` (lock and reclaim).
- Docs updated: `AGENTS.md`, `docs/ARCHITECTURE.md`, `docs/HANDOFF.md`.

### Item 6: staged-tree clash

`loadout_main.py::_place_staged_tree`: when the staged source entry is a file or
symlink and the target is a real directory, raise `InstallRefused` with the
relative path. The stage cleanup still runs in `extract_tar_replacing`'s
`finally`. A scan in the independent review found 0 such clashes in the 40
runtime archives plus payload bin/lib64, so no shipped archive relies on the
old destructive behavior.

### Item 7: blocked recommends

`loadout_main.py::walk_recommends`: before adding a recommended package `r`,
run `walk_depends({r}, ...)`; if it raises `ResolverError` (skipped or disabled
hard dep), drop `r`. An explicitly selected package raises when a hard dep is
skipped, unless `--force` is set, which downgrades that to a warning. A
recommendation stays SOFT under
`--force` too: because `walk_recommends` always walks its hard deps without
`force`, a recommended package whose hard dep is skipped/disabled is still
dropped rather than pulling in a package the user explicitly excluded. The
new `--force does not resurrect a blocked recommend` assertion pins this.

### Item 8: shell startup parity

`envs/bash/global/bashrc`: moved the shared block above the non-interactive
return. This is the environment zsh's shared block and tcsh's rc already set on
every startup. `EGL_LOG_LEVEL` was included because zsh/tcsh also set it before
their interactive-only section, closing the same class of drift.

### Item 9: backup symlinks

`loadout_main.py`:

- `_path_under_lexical`: containment without resolving symlinks.
- `_backup_symlink_target`: for an absolute link, first try the lexical
  relpath from the link text (this is what a symlinked `~/.config` needs); if
  the real target is under HOME but the lexical text is not, map it back to a
  HOME-relative lexical path. Otherwise keep the original absolute text.
- `_restore_backup_dir`: copy top-level entries one at a time. If a backup
  directory would land on a symlink to a directory, use
  `cp -rPp src/. dest/`; plain `cp -rPp . home` refuses that shape with
  "cannot overwrite non-directory with directory".

### Item 10: paths.lua comments

`envs/nvim/lua/global/paths.lua`: `M.data`'s doc block is directly above
`M.data`; `M.private_dir` has its own block. No behavior change.

## Registration and generated artifacts

- No new test files: the new cases live in existing registered tests
  (`unit-private-state`, `unit-install-steps`, `unit-resolver`,
  `env-private-dirs`, `shim-bootstrap`, `snapshot-restore`).
- The pending daemon is payload, so the change invalidated both generated
  payload manifests. Ran, in order:
  - `.loadout-bootstrap/bin/python3.15 build/gen-installed-sizes`
  - `.loadout-bootstrap/bin/python3.15 build/gen-content-manifest`
- `.content-manifest` and `payload/installed-sizes.json` are in the diff.

## RED evidence (tests written first)

| Item | RED observation |
|---|---|
| 4 | `unit-private-state`: 7 failures (0777/0775 own dirs refused; daemon 0775 refused). `env-private-dirs`: `FAIL loose-dir/bash: .../shm/mylesp is 775, want 700` |
| 5 | `shim-bootstrap`: foreign-host dead temp was deleted; held-claim/stale-claim cases did not exist yet |
| 5a | Two-waiter slow-rm/slow-tar case: `FAIL stale-race: 2 extractions, want exactly 1` |
| 6 | `unit-install-steps`: file and symlink over a real dir were not refused; the user file was deleted |
| 7 | `unit-resolver`: recommend with skipped dep was added and end-to-end resolve raised `ResolverError`; added a pin that `--force` does not resurrect it |
| 8 | `env-private-dirs`: `FAIL non-interactive/bash: PYTHONPYCACHEPREFIX=` |
| 9 | `snapshot-restore`: `RuntimeError: unsafe tar link target: backup.1/.tcshrc -> /.../symlinked-config/.config/tcsh/tcshrc` (the data-filter failure); after the lexical rewrite the old restore also exposed the `cp` symlinked-dir refusal |
| 10 | comments only; no failing-test phase |

## GREEN evidence

Final focused runs:

| Command | Result |
|---|---|
| `.loadout-bootstrap/bin/python3.15 tests/unit-private-state` | 23 passed, 0 failed |
| `.loadout-bootstrap/bin/python3.15 tests/unit-install-steps` | 63 passed, 0 failed |
| `.loadout-bootstrap/bin/python3.15 tests/unit-resolver` | 86 passed, 0 failed |
| `tests/env-private-dirs` | OK (clean, non-interactive, loose-dir, symlink-dir, nvim, online-cache cases) |
| `tests/shim-bootstrap` | OK (cold, host-aware sweep, held claim, stale claim, two-waiter stale-claim race, warm-cache order, unstamped/stale cache, no-HOME) |
| `tests/snapshot-restore` | OK (sealed round-trip, absolute in-HOME link, symlinked `~/.config`, empty HOME) |
| `.loadout-bootstrap/bin/python3.15 tests/env-shell-parity` | 27 passed, 0 failed |
| `tests/install-env-bash`, `tests/install-env-tcsh` | OK |
| `.loadout-bootstrap/bin/python3.15 tests/prompt-no-rc` | 8 passed, 0 failed |
| `.loadout-bootstrap/bin/python3.15 tests/docs-sync` | 8 passed, 0 failed |

Gates and smoke:

- `sh -n loadout` — OK.
- `.loadout-bootstrap/bin/python3.15 -m py_compile loadout_main.py payload/pending-daemon/loadout-pending-daemon` — OK.
- `bash -n envs/bash/global/bashrc envs/bash/functions.sh` — OK.
- `ruff format --check` on changed Python files — clean.
- `ruff check` on changed Python files — clean.
- `tests/run-all --fast` — `Tier 1 passed` (final run after all changes).
- 10-way concurrent cold bootstrap on a scratch clone — 10/10 `STUB`, one
  cache, no temp or lock left.
- The first `run-all --fast` after the daemon edit correctly FAILED
  `content-manifest in sync` and `installed-sizes in sync`; after the regen
  chain both passed on every subsequent run.

## Residual risks / notes for the reviewer

1. No Tier 2 full-suite run and no Tier 3 container run were performed. The
   touched installer paths have focused T1/T2 coverage; `private-state-two-users`
   (foreign-owner pending dir) was not re-run. Its foreign-owner branch is
   unchanged.
2. Reclaimer crash: `.loadout-bootstrap.lock.reclaim` is intentionally not
   auto-deleted (deleting it automatically recreates the same double-delete
   race one level down). A crash in that small window fails closed after 120 s
   with a manual-removal hint.
3. Same-host PID reuse: a dead bootstrap whose PID is now a different live
   process is treated as live (safe, but may wedge until the timeout/manual
   removal). Chosen over deleting a possibly-live bootstrap.
4. Shell/Lua helpers cannot be tested against a foreign owner without a second
   account. The local tests cover own-dir tightening and symlink refusal; the
   Python installer has the two-account Tier 3 test.
5. The repo-wide `ruff format --check --force-exclude` with no file arguments
   flags 5 pre-existing Markdown code blocks (`build/ADDING_BINARIES.md` and
   four files under `docs/superpowers/plans/`). The project gate passes because
   it formats only tracked Python files. This report does not change those
   files.
6. Review items 1-3 and `assurance/release-timings.tsv` were already modified
   in the working tree before this work; this report does not claim them.
7. The untracked review plan file remains untracked by design
   (`docs/superpowers/plans/2026-10-27-code-and-doc-review.md`).
