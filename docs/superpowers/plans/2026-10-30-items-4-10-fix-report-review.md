# Review of the items 4-10 fix report

Date: 2026-10-30. Reviewer: Claude Code session (the one that fixed items 1-3).
Reviews: `2026-10-30-items-4-10-fix-report.md` against the uncommitted working
tree. State: nothing below is fixed yet; integration (commits + full gates) is
deferred until the concurrent tcsh agent (`omp`) is done.

## Verdicts

| Item | Verdict |
|---|---|
| 4 | **Over-corrected** -- must narrow before commit |
| 5 | Sound; one small hole (host-prefix match in the temp sweep) |
| 6 | Correct |
| 7 | Correct |
| 8 | Parity fixed; the per-startup tcsh cost the finding was about remains |
| 9 | **Regression** -- must fix before commit |
| 10 | Correct |

## Must fix

### Item 9: relative link text resolved against the CWD

`_backup_symlink_target` dropped the old `os.path.isabs(link_target)` guard.
`os.path.normpath`/`abspath` then resolve a RELATIVE link text against the
process CWD, not the link's directory. `cmd_install` does `os.chdir(work_root)`
before the backup, and for a mixed selection `work_root` is the install root --
by default `~/.local/share/loadout`, inside HOME. Reproduced with that layout:

```
HEAD:     backup .bashrc -> .config/bash/bashrc                       (resolves after restore)
WORKTREE: backup .bashrc -> .local/share/loadout/.config/bash/bashrc  (DANGLING after restore)
```

So the canonical `./loadout install @shared-all @envs-all` stores broken
`.bashrc`/`.bash_profile` (and zsh) links, and `snapshot restore` of that
backup breaks the login shell. `tests/snapshot-restore` misses it because
`snapshot create` chdirs to HOME first.

Fix: `if not os.path.isabs(link_target): return link_target` at the top. Test:
back up from a CWD inside HOME but not HOME (the install-root shape) and assert
the stored text is unchanged.

### Item 4: accepting ANY own dir trusts content others may have planted

The new rule accepts and tightens every dir we own, including 0777 (the test
flips "0777 dir is refused" to "accepted"). Tightening stops future writes but
trusts whatever is already inside:

- `bashrc:501` reuses an existing `<shm>/$USER/bin/eza` whenever it is newer
  than the source, so a planted copy runs on every `ls`;
- planted `.pyc` files under the pycache prefix run on import;
- a planted `pending.json` in the pending dir chooses which bytes the daemon
  copies into `bin/`.

The report's rationale (UPG umask 002 -> the group is the user's own) is right
for UPG only. EDA sites commonly use a SHARED primary group with umask 002;
there group members are co-tenants.

Narrower rule for all five implementations: refuse when the other-write bit is
set; accept group-write only when the dir's group is the user's private group
(group name == user name); then tighten to 0700. Shell: `stat -c %G` vs
`id -un`; tcsh: builtin `$group`/`$user`; Python: `grp`/`pwd`; Lua:
`uv.os_get_passwd()` + group lookup.

## Should fix

### Item 5: host-prefix collision in the stale-temp sweep

`".loadout-bootstrap.tmp.$host."*` also matches a temp from host
`$host.<suffix>` (e.g. `node1` vs `node1.lab`), and the sweep then
`/proc`-checks that foreign PID locally. Require the remainder after
`$host.` to be all digits.

### Item 8: tcsh still forks on every startup

Bash now sets the block before its non-interactive return (parity fixed), but
the finding was the cost: `sh helpers/private-dir` measured ~3 ms per
`tcsh -c` (vs ~52 ms for a whole non-interactive `tcsh -c true`). tcsh can do
the check with builtins only: `-d`, `! -l`, `-o`, `-P` (octal mode), and
`$user`/`$group` for the item 4 rule.

## Gates

Two full T1+T2 runs were made while integrating:

1. Fixes 1-3 only (before items 4-10 landed): all tests passed.
2. Current tree: Tier 1 FAIL `installed-sizes in sync` -- 12 entries stale
   (the tcsh env files and new helpers changed after the 09:53 regen; not from
   items 4-10). Tier 2 aborted after `optional-packages` (which passed) because
   `omp` ran `tests/run-all --fast` in the same repo at the same time, and
   `tests/dep-capture`'s EXIT trap deletes the shared `.loadout-deps.log`. Not
   reached: `install-split-shared-envs`, `install-nvim-deployments`,
   `install-nvim-shared-stash`, `install-linux-tmp-home`, `install-parity-plot`,
   `install-python-tool-upgrade`, `install-typescript-language-server`,
   `uv-launchers`, `completion in sync`.

## Integration plan (when the tcsh agent is done)

1. Fix item 9 and narrow item 4 (test first), fix the item 5 sweep, optionally
   make the tcsh helper fork-free.
2. Regenerate `payload/installed-sizes.json` then `.content-manifest`.
3. Full T1+T2 on a quiet tree (no concurrent run-all), plus Tier 3 for the
   install-behavior changes.
4. Separate commits: review items 1-3; items 4-10; the tcsh/tmux work (reviewed
   on its own -- it is not covered by the fix report).
