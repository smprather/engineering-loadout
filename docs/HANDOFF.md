# Current Handoff

## Archive

Older entries and superseded documents live in `docs/archive/` -- history, not
a sync target:

- `docs/archive/HANDOFF-2026-07-to-09.md` -- handoff entries before 2026-10-01
- `docs/archive/HANDOFF-2026-10-01-to-11.md` -- handoff entries 2026-10-01 to 2026-10-11
- `docs/archive/SESSION-HANDOFF-2026-10-02.md` -- the 2026-10-02 session handoff
- `docs/archive/PROPOSAL-2026-10-05-dest-default-and-group-removal.md` -- the
  proposal behind the 2026-10-05 XDG default root and group retirement
- `docs/archive/2026-09-04-enhancement-request-permissions-management.md` -- the
  permissions-management request fielded and implemented 2026-09-04

## 2026-10-30: independent `/code-review high` of `e85fd11..HEAD`

Closes entry (2026-10-28) item 5. The review (unverified by design at that
level) reported 10 findings; the user asked to fix 1-3, each confirmed and
fixed test first (RED observed, tests/unit-install-steps):

1. The end-of-install ldd check saw only payload `bin/*.bz2` names, so ELFs a
   runtime archive puts in `<prefix>/bin` (node -- the libatomic.so.1 class)
   were never checked; an install of only runtime packages skipped the check
   entirely. `install_runtime_archives` and `install_mate_terminal_runtime`
   now return their `<prefix>/bin` names (also on the unchanged-stamp path,
   via `_InstallStamps.step_rels`), unioned into the check. End to end:
   `install nodejs --dest-dir` under strace now runs ldd on node/npm/npx;
   HEAD ran nothing.
2. `_rmtree_healing` retried `func(path)` for any failing func; on 3.15's
   fd-based rmtree that can be `os.open` (TypeError: missing flags) for a
   hardened unreadable dir, a traceback instead of a FAIL row. Unreadable
   dirs now get u+rwx and a nested rmtree (once per path).
3. `_bz2.release` ran only after a successful extraction; a failed one left
   the rejoined chunked archive in the temp root while the runtime phase
   moved on. Now in a `finally` at all four sites (generic runtime, vim,
   mate-terminal, nvim-qt).

**Open -- validated 2026-10-30, fixed in entry (2) above:**
4. CONFIRMED. `loadout_private_dir` and its four twins refuse the user's OWN
   0775 dir instead of tightening it (reproduced: 0755 -> tightened to 700,
   0775 -> rc=1, left 0775). Pre-`f7644eb` bashrc made `/dev/shm/$(id -u)`
   with a bare `mkdir -p` and Python made `/dev/shm/$USER/pycache`, both 0775
   under RHEL's UPG umask 002 -- where the group is the user's own, so the
   refusal guards nothing. Self-heals at reboot (/dev/shm) or tmp cleanup;
   until then shells fall back silently and the installer refuses to stage.
5. CONFIRMED by reading (not raced in practice). Two first runs that both
   read `.complete` before either `mv`: the second `rm -rf` deletes the tree
   the first already exec'd from; window is milliseconds. Separately, the
   stale-tmp sweep's `kill -0 <pid>` deletes a LIVE bootstrap from another
   host sharing an NFS clone.
6. CONFIRMED, latent. `_place_staged_tree` rmtrees a real dir where an archive
   has a file/symlink (deliberate per its docstring; `b4ca584` did not call
   out that `extractall` used to fail loudly). A scan of all 40 runtime
   archives plus payload bin/lib64 found 0 file/dir clashes today; the
   exposure is user or foreign content in the prefix.
7. CONFIRMED, latent. `install A --skip N` with A recommends R, R depends N:
   HEAD raises ResolverError. (The review misdescribed the old behaviour:
   `e85fd11` installed R WITHOUT N, not "dropped R".) Expected: drop R. No
   registry entry today has a recommend whose target has depends.
8. CONFIRMED, plus a parity gap: bash sets PYTHONPYCACHEPREFIX AFTER its
   non-interactive return (bashrc:65-70, 126), tcsh (`tcshrc:147`) and zsh
   (`zshrc:95`) on EVERY startup. Measured: the tcsh helper is ~3 ms per
   startup vs ~52 ms for a whole non-interactive `tcsh -c true`.
9. CONFIRMED (reproduced): with `~/.config` symlinked out of HOME, the backup
   stores `.tcshrc` absolute and a `filter="data"` extract raises
   AbsoluteLinkError. The realpath-based rewrite cannot fix it (the relative
   link would escape the backup); the relpath must be lexical, from the link
   text.
10. CONFIRMED. `paths.lua`: `M.data`'s doc block (lines 65-67) runs into
    `M.private_dir`'s; `M.data` (line 94) has none.

## 2026-10-28: review follow-ups -- every open item fixed or ruled on

The user asked to "fix everything, including deferred items" left by entry (4)
below (pushed first: `e85fd11..eab6ed3`). Commits `a5649c5..febe89f`, test
first, each RED observed before GREEN:

| Commit | Item | What changed |
|---|---|---|
| `a5649c5` | TOOL-5, deferred minor | `build/release`: `_publish_reused_release` checks every `gh` exit status (an ignored edit failure used to publish with the previous notes); the tag message is read with `with` |
| `8c98bc3` | deferred minor | nvim with no git anywhere skips plugins instead of aborting `init.lua` with E475 (tests/env-nvim-no-git) |
| `c881d6c` | found while fixing | the shells' online-verdict cache never falls back to a shared `/tmp/.loadout-net` (same class as SEC-2..5, missed by Task 2) |
| `728edcd` | ROB-2 rest | chunked font zips are read in place through `_PartsReader`; nothing is rejoined into the temp root |
| `1f3e197` | open item | `loadout clean --font-backups` + a doctor report + a fonts-phase hint for the old `fonts.bak[.N]` dirs; files not from the bundle are kept and listed |
| `5101c2b` | open item | the Task 1 two-account check is automated: tests/private-state-two-users (Tier 3 container, two real users); the pre-fix tree fails it |
| `2dd8fbe` | ROB-6 | install stamps (`<prefix>/.loadout-stamps/`): a no-op `install @shared --dest-dir` 207 s -> 14 s; `reinstall` now really reinstalls (209 s) |
| `2a32f27` | DEBT-1 | 30 dead cp314 wheels pruned (238 MB); cicwave, jupyterlab, time-plot re-enabled on cp315 numpy/pandas/pyqt6-sip/markupsafe; the closure gate fails on any wheel the interpreter cannot install; build-cicwave/parity-plot target 3.15 |
| `febe89f` | DEBT-2 | tests/needed-closure, the repo-wide NEEDED auditor; its first run fixed 15 minimal-install gaps in the registry (a minimal ruby install on a newer host could not `require 'fiddle'`) |

Also: `docs/HANDOFF.md` split again -- entries 2026-10-01..11 moved to
`docs/archive/HANDOFF-2026-10-01-to-11.md`.

**Rulings (user decides whether they stand):**
- Not done, still disabled: librelane (klayout, zstandard), parity-plot (orjson,
  frozenlist) and pygwalker (pins duckdb<2) -- no cp315 wheel upstream on
  2026-10-28, and building klayout/duckdb from source or adding a Rust
  toolchain to the image (orjson) is a build project of its own. Each
  `disabled_reason` names the exact blocker.
- Not done: the GUI-toolkit ceiling (a private GTK 3.24 stack, entry 2026-10-12
  (1)) -- a new-stack build, not a defect fix.
- Open: firefox's libxul NEEDs `libasound.so.2`, which stock EL8 lacks; libxul
  has no RPATH, so only a copy co-located in the firefox archive can serve it
  (needs a firefox rebuild). Recorded as a `HOST_CONTRACT` in needed-closure.
- `reinstall` diverges from `install` now (it ignores the stamps). Tests that
  pin HOW a rewrite happens (inode swap) run with stamps ignored.

**Release 2026.10.8 (class C: installer + registry changed) -- PUBLISHED and
verified 2026-10-28** (tag on `5232eba`, Good ED25519 signature, tag binds
`sha256sums.txt sha256 73d4c694...`, four assets, stash size matches,
`origin/main` = tag commit; `fetch-stash --tag 2026.10.8 --from-file` passes
the signed-tag check). Gates per docs/RELEASE.md. Currency sweep run, nothing bumped (ruling: a fix release;
2026.10.7 swept four days earlier, and each bump needs its own build + smoke).
`build/check-versions --outdated-only` on 2026-10-28 lists 19 behind upstream
-- btop 1.4.8, fzf 0.74.5, gnuplot 6.0.6, gopls 0.24.0, gvim/vim 9.2.1252,
just 1.59.0, lazygit 0.66.2, librelane 3.0.17, marktext 0.23.0, numr 0.9.0,
ruff 0.17.3, sqlite 3.54.1, strace 7.3, stylua 2.6.0, tmux-path-store
2026.10.2, ty 0.0.93, uv 0.13.6, valgrind 3.28.0 (pdftotext pinned; ncdu
lookup 503'd) -- the next class C sweep's worklist. `./build/update --currency`:
only python-loaded and open-eda-file-tools are DUE (never auto-updated);
yara-rules held (refreshed 2026-10-23). The first release run was BLOCKED by
the vulnerability gate (msgpack 1.2.2, GHSA-j586-36cw-2gc2); the wheel was
refreshed to 1.2.3 with a closure-preservation proof (ADDING_BINARIES, wheel
notes) before the release was re-run. This is the first release whose signed
tag binds `sha256sums.txt`, so plain `./tools/fetch-stash` works again from it
on.

**Still open (outside this repo or the user's call):**
1. The deployed shared tree (entry (3) item 1) still runs pre-review code;
   reinstall it from `main`.
2. The review plan file stays untracked (memory: project-review-plan-untracked).
3. candelise push still held (entry (3) item 3).
4. The dev host's `~/.local/share/fonts.bak` (1.9 GB, all superseded) and
   `fonts.bak.4` (2.3 GB; 50 files not from the bundle, e.g. MapleMono and
   licenses, would be KEPT) are still there: `./loadout clean --font-backups`
   frees about 4 GB. Not run -- it deletes the user's files; their call.
5. DONE 2026-10-30 (entry above): an independent `/code-review high` of
   `e85fd11..HEAD` ran; findings 1-3 fixed, 4-10 listed there as open.

## 2026-10-27 (4): review plan executed -- all 18 tasks committed on main (pushed 2026-10-28)

The 2026-10-27 code and doc review plan
(`docs/superpowers/plans/2026-10-27-code-and-doc-review.md`, still untracked)
was executed inline, task by task, test first, on `main` (pushed 2026-10-28 as
`e85fd11..eab6ed3`).
Decisions D-A to D-D took the plan's recommended options. Gates at `d1e81bb`
(Tasks 1-18): `tests/run-all` all green, and
`tests/prebuilt-binaries-almalinux8 --full` PASS (311 binaries OK, 23 skipped,
583 s). The fix-pass commit after it (shim concurrency) reran `tests/run-all`.

| Task | Commit | Closes |
|---|---|---|
| 1 private pending dir + run log | `4b61c26` | SEC-1, SEC-6, ROB-5 |
| 2 private runtime dirs (shells, nvim) | `f7644eb` | SEC-2, SEC-3, SEC-4, SEC-5 |
| 3 verify every payload file, fail closed | `e0bcdeb` | SEC-7, SEC-8 |
| 4 sums bound into the signed tag | `e4ff606` | SEC-9, DOC-8 |
| 5 reinstall/upgrade keep --dest-dir | `cbb0448` | COR-1 |
| 6 sealed-tree snapshot/restore, one target table | `ee05354` | COR-2, COR-8, COR-9, COR-19 |
| 7 doctor + symlinked system bins | `94cbe1f` | COR-3 |
| 8 inode-swap extraction | `b4ca584` | COR-4, ROB-2 (partly: see below) |
| 9 phase failures are rows | `08e8594` | COR-5, COR-6, COR-7, ROB-3 |
| 10 nvim clone cleanup + sync timeout | `d679532` | COR-10, COR-11 |
| 11 bash env correctness | `dd21735` | COR-12, COR-13, COR-14 |
| 12 shim order, atomic bootstrap, one minor | `6847c33` | COR-15, COR-16, ROB-4, DOC-7 |
| 13 fonts in place, no fonts.bak | `b78c622` | ROB-1 |
| 14 resolver fixed point | `9835792` | COR-17 |
| 15 pre-commit hook safety | `8253bac` | TOOL-1, TOOL-2, TOOL-3, DOC-11 |
| 16 quoting, shell-free nvim probes, patchelf | `9067160` | SEC-10, COR-18, DOC-9, TOOL-4, TOOL-6 |
| 17 docs sync + tests/docs-sync | `796f8f6` | DOC-1 to DOC-6 |
| 18 archive + HANDOFF split | `d1e81bb` | DOC-10 |
| review fix: shim concurrent bootstrap | (this commit) | -- |

Not addressed (as the plan said): ROB-6 and TOOL-5 (noted only), DEBT-1, DEBT-2.

**User-visible changes to know before pushing or releasing:**
- **fetch-stash refuses until the next release.** The latest published
  release's tag binds no sums file, so plain `./tools/fetch-stash` now fails
  the trust check; add `--allow-unverified-sums` (HTTPS-only trust) until a
  release made by the new `build/release` exists. `--from-file` now needs
  `--tag`.
- **A missing `.content-manifest` refuses the install** unless `--no-verify`.
- **Fonts are no longer moved to `fonts.bak*`.** Existing `fonts.bak*` dirs from
  earlier installs are not cleaned up; delete them by hand to get the space back.
- **tcsh/zsh entrypoints are relative symlinks now**, like bash's.
- **The local `.git/hooks/pre-commit` was updated** to the fixed hook.
- **The repo's `.loadout-bootstrap/` was re-extracted once** (no stamp); the old
  3.14 tree in it is gone.

**Open** (status 2026-10-28 in the entry above: 1 and 5 are closed, 4 still
applies to both entries):
1. CLOSED (`5101c2b`, tests/private-state-two-users). The Task 1 manual
   two-account check (user B pre-creates
   `/tmp/loadout-pending-<A>` 0777; user A reinstalls with a loadout binary
   running) was not run: one account, no root here. Expected result:
   docs/SECURITY.md section 9.
2. Deployed trees (e.g. the shared tree in the deployed-shared-tree note) still
   run the old code until reinstalled from `main`.
3. The plan file is still untracked. Its security findings are fixed in these
   commits, but deployed trees are not yet updated; decide whether to commit
   it before or after redeploying.
4. Final review was a self-review (no fresh reviewer agent). A fresh
   `/code-review` of `e85fd11..HEAD` before pushing is recommended.
5. CLOSED (`a5649c5`, `8c98bc3`, `728edcd`, `2a32f27`, the 2026-10-28 HANDOFF
   split). Deferred minors: `build/release` reads the tag message without `with`;
   `envs/nvim/init.lua` prints E475 when no git exists anywhere (pre-existing);
   all font zips are still rejoined before the fonts phase extracts (ROB-2 peak
   tmpfs unchanged there); HANDOFF is 2261 lines after the split;
   `build/build-cicwave.sh` and `build/build-parity-plot.sh` still run pip3.14
   (DEBT-1).

Ledger with every ruling: `.superpowers/sdd/2026-10-27-code-and-doc-review/progress.md`
(gitignored).

## 2026-10-27 (3): session close -- open items for the next session

**Shipped.** `74ed71f` (node RUNPATH fix, entry (2) below) is pushed to
`origin/main`. It is not in a release yet; the next release carries it.

**Open items, in priority order.**
1. **Deployed shared tree.** `/vols/anvil_release/psg/tools/loadout-shared/latest`
   was installed from `main` between `fb63b2d` and `74ed71f`, so its `bin/node`
   has no RUNPATH. Repair it by reinstalling `nodejs` from current `main`, or
   in place as described in ADDING_BINARIES' Node.js section. It is unconfirmed
   whether this has been done.
2. **Review plan, untracked on purpose.** (Executed since: see entry (4) above.)
   `docs/superpowers/plans/2026-10-27-code-and-doc-review.md` holds the
   2026-10-27 top-to-bottom code and doc review: a findings register and 18
   test-first tasks. This repo is PUBLIC, and the plan describes security
   findings that are not fixed yet. Keep it out of git until those fixes land,
   or until the user decides otherwise. It still needs the user's review,
   decisions D-A to D-D, and a choice between subagent-driven and native
   execution.
3. **candelise push held.** `bcf1f50` (repowise removal) is committed in
   `~/candelise` but NOT pushed. That remote holds only the 2026-08-31 initial
   commit, so pushing publishes 742 commits for the first time, and candelise's
   own AGENTS.md reserves pushing for the human. The user said "push all"; the
   other four repos were pushed, and candelise waits for an explicit yes.

**Machine state changed this session.** repowise was removed completely at the
user's request: the four session hooks in `~/.claude/settings.json`, the
user-scope MCP server, the uv tool, `~/.repowise`, `~/.config/repowise`, and
the `.repowise/` indexes in five repos. Generated repowise blocks and repowise
instructions were removed from candelise's agent docs; the `.gitignore` rules
went from candelise, watchglass (`~/dev/keepwatch`), cachyos-config and
janestreet-blog-serial-protocol-emulator. Do not reintroduce it.

**Noted, not acted on.** `build/build-bash.sh`, `build-expect.sh` and
`build-gtkwave.sh` hard-code `PATCHELF="${HOME}/.local/bin/patchelf"`. All three
are `set -eu`, so they fail loudly rather than ship broken output. They fail
everywhere today, though: on the host because the XDG default install root no
longer populates `~/.local/bin`, and inside `build/build-shell` because the
container sets `HOME=/tmp` and `LOADOUT_PATCHELF=/usr/bin/patchelf`, and these
scripts honor neither. Fix them before the next rebuild of bash, expect or
gtkwave by following the `build-fio.sh` pattern (`LOADOUT_PATCHELF`, then
`command -v patchelf`). This is recorded as finding TOOL-6 in the review plan.

## 2026-10-27 (2): bundled node lost its RUNPATH again -- `libatomic.so.1` not found on deployed EL8

**Symptom.** A deployed shared tree (`.../loadout-shared/latest`, installed from
`main` after 2026-10-24) failed with `bin/node: error while loading shared
libraries: libatomic.so.1: cannot open shared object file`. Every node-launched
package failed with it: npm, npx, pyright, typescript-language-server, prettier,
netlistsvg.

**Cause.** The 26.12.1 bump (`fb63b2d`) was imported on the CachyOS host.
`build/import-nodejs` probed for patchelf only in `LOADOUT_PATCHELF`,
`~/.local/bin`, `/usr/bin` and `/usr/local/bin`. Since the default install root
moved to `$XDG_DATA_HOME/loadout`, this host's patchelf lives in
`~/.local/share/loadout/bin`, so the probe found nothing. The script printed
"skipping RPATH patch" and packaged node with **no RUNPATH at all** (26.11.1 had
`$ORIGIN/../lib64:$ORIGIN/../lib`). This is the same failure as `0eefd39`
(26.8.2). Native gates stayed green because the host has
`/usr/lib/libatomic.so.1`, and the last Tier 3 run (2026-10-23) predates the
bump. **Release 2026.10.7 is not affected**: it was cut before `fb63b2d` and
ships 26.11.1 with the RUNPATH.

**Fix.**
- `build/import-nodejs`: `find_patchelf()` probes `LOADOUT_PATCHELF`, the XDG
  install root, `~/.local/bin`, `/usr/bin`, `/usr/local/bin` and PATH at call
  time. `patchelf_rpath()` dies when patchelf is missing or fails, or when
  `readelf` does not read back exactly `$ORIGIN/../lib64:$ORIGIN/../lib`.
- node 26.12.1 was re-imported inside `build/build-shell` from the same nvm
  prefix (staged into `/cache`), and `strip-all-elf-binaries` (sizes and
  manifest) was run in the container.
- New Tier 1 test `tests/nodejs-runpath` reads the payload archive directly and
  pins the importer's refusal paths.
- Docs: AGENTS.md (runtime-archives note, test list) and the first Node.js
  section in `build/ADDING_BINARIES.md` (procedure, why the RUNPATH matters, and
  the in-place repair for deployed trees).

**Verified.**
- The old binary reproduced the exact error in `almalinux:8.10`
  (`--network=none`, `libatomic` rpm absent). Patched, it printed `v26.12.1`.
- The new archive, unpacked as a prefix in the same container: `ldd` resolves
  `libatomic.so.1 => /p/bin/../lib64/libatomic.so.1`, and `node --version`,
  `npm --version` and a SharedArrayBuffer `Atomics.add` all succeed.
- `tests/nodejs-runpath` FAILED before the re-import (RUNPATH absent) and passes
  after.
- `tests/run-all --container` passed: 1660 s total, Tier 3 container smoke 580 s
  PASS. The smoke image also lacks the `libatomic` rpm, so its bin probes cover
  node and the node-launched tools.

**Deployed trees from `main` between `fb63b2d` and this fix** need either a
reinstall of `nodejs` or the in-place repair in ADDING_BINARIES' Node.js section
(patchelf a copy, then `mv` over `bin/node`).

Also untracked: `docs/superpowers/plans/2026-10-27-code-and-doc-review.md`, the
top-to-bottom review plan written earlier today, pending the user's review and
four decisions (D-A to D-D).

## 2026-10-27: python-loaded `versions/` layout -- why the venv path is indirection

Design Q&A only; no code change. `share/python-loaded/venv` is a symlink to
`versions/<lockdate>-<lockhash8>/venv` because the venv tree is immovable after
creation: `uv pip install` writes absolute interpreter paths into every console
script (47 in the `/tmp/el-test` install), and `uv venv --relocatable` is
rejected (it swaps those shebangs for `sh` trampolines). `pyvenv.cfg` records
only `home = <prefix>/bin` -- it does NOT contain the venv path -- and
`venv/bin/python` -> `<prefix>/bin/python3`. The things that embed the
versioned path and make the tree immovable are console-script shebangs, the
activation scripts (`activate`, `activate.csh`, `activate.fish`, `activate.nu`,
`activate.bat` each set `VIRTUAL_ENV` to the absolute path), and wheel-supplied
`scripts/` files rewritten by `_suite_fix_shebangs`; `pyvenv.cfg` is not part
of the constraint. The stable symlink is for user/external references and
is the documented user shebang target; uv's own scripts point into the
versioned directory, which is never renamed.

Sweep behavior, confirmed by reading `install_python_suite`: old version dirs
are deleted only after a successful build and symlink swap (`:2643-2647`). The
stamp fast-path (`:2566`) returns before the sweep, so debris can survive a
no-op reinstall only when the run was interrupted after the stamp commit
(`os.replace` at `:2641`) and before the sweep. Interruption before that commit
leaves a mismatched or missing stamp, so the next run rebuilds and removes the
partial target at `:2573` (or via the post-success sweep). Concurrent installs
are unguarded.

Considered and not adopted: (a) also prune strays on the SKIP path via a
`_suite_prune_versions(dest, current)` helper; (b) flatten `versions/` to a
top-level `venv-<id>` + symlink (identical semantics, one fewer directory
level). No decision; the current layout stays. `main` was clean at `bb1c299`
before this docs commit.

## 2026-10-24 (4): tmux-persist-autosave keeps saving after the XDG plugin move

**Issue #12.** `_install_env_tmux()` puts the plugin tree at
`~/.config/tmux/plugins` and removes `~/.tmux`. The external
`tmux-persist-autosave` helper still defaults to
`~/.tmux/plugins/tmux-persist`, so after a reinstall every timer tick logged
`save: ... skipped` and exited 0: systemd reported `Finished` while nothing was
saved. Clean detach/exit still saved through tmux-persist's own hooks, so the
loss stayed invisible until a hard crash.

**Change.** When `~/.local/bin/persist-autosave.sh` and
`~/.config/systemd/user/tmux-persist-autosave.service` both exist,
`_install_env_tmux()` now writes a loadout-owned drop-in
`.../tmux-persist-autosave.service.d/50-loadout-plugin-path.conf` containing
`Environment=TMUX_PERSIST_PLUGIN_DIR=%h/.config/tmux/plugins/tmux-persist`
(0644, rewritten only when the content differs). User drop-ins are preserved;
the `50-` ordering lets a later user drop-in override it. The install runs
`systemctl --user daemon-reload` itself (also when the content was already
current); if no user manager is reachable it warns with the manual command.
Env-only `--dest-dir` staging writes the drop-in into the staged HOME but skips
the reload: the live manager cannot see that tree. A unit without the helper
(or a helper without the unit) gets no drop-in.
`loadout doctor` now reports
`ExecStart=`/`Environment=` lines in user units/drop-ins that still reference
`~/.tmux/plugins`. `docs/TMUX.md` and `AGENTS.md` no longer claim tmux-persist
replaces continuum's no-client periodic autosave. The helper is external and
not vendored; its own preferred fix (resolve
`TMUX_PLUGIN_MANAGER_PATH` from the live server) belongs upstream.

**Shipped.**
- `76adcb5` -- drop-in writer, automatic `systemctl --user daemon-reload`,
  doctor stale-path report, docs/tests.
- `a92bb68` -- assign-then-close convention: `Fixes #12` closed the issue
  automatically (`closedAt` 22:19:08Z); it is assigned to `@smprather`, the
  acting account.
- `afc34e9` -- skip the reload for staged env-only `--dest-dir` HOMEs while
  still writing the drop-in there.

`main` is clean and synced to `origin/main` at `afc34e9`; no open tasks remain
for #12. The external helper's own preferred fix (resolve
`TMUX_PLUGIN_MANAGER_PATH` from the live server) belongs upstream.

**Verified.** `tests/install-env-tmux-nvim-layers` passes
(14 s, focused): no drop-in on a plain install, drop-in written when helper+unit
exist, the stubbed `systemctl --user daemon-reload` is invoked and reported, a
staged `--dest-dir` HOME writes the drop-in without calling the stub, user
drop-in preserved, unit-only home untouched, a stock-TPM home with no XDG
plugin tree stays quiet, and doctor names the stale line and the XDG path.
Live doctor on this host is warning-free because its drop-in is correct.
Live unit from the pre-existing manual drop-in: `systemctl --user show` has
`Environment=TMUX_PERSIST_PLUGIN_DIR=/home/mylesp/.config/tmux/plugins/tmux-persist`;
the 17:00 tick logged
`done (1 sessions saved, 0 reverted, 0 guard-skipped)`. `py_compile`,
`ruff check`, `ruff format --check`, and `tests/doctor-system-newer` pass;
`tests/release-timings` is 15/15.

## 2026-10-24 (3): pane TERM configurable, currently xterm-256color

**Cause.** The 2026-10-20 home-layer merge set
`default-terminal "tmux-256color"`. Corp tools hard-check
`TERM=xterm-256color` and reject the tmux-specific name.

**Change.** `envs/bash/global/config.sh` and `envs/tcsh/global/config.csh`
export `LOADOUT_CFG_TMUX_TERM` (default `xterm-256color`).
`envs/tmux/tmux-global.conf` expands it with `set -sF` and an
`xterm-256color` fallback for servers started outside a loadout shell; a
guarded `client-attached` hook plus an `update-environment` entry re-apply the
attaching client's value, so a changed setting reaches new panes after the
next attach. Existing panes keep their original TERM. The test asserts the
default, an env override, the fallback, and a fresh pane's `$TERM`.

**Capability note.** The outer client TERM is unchanged (xterm-256color), so
tmux's own rendering is unaffected. Inside panes, xterm-256color is the richer
terminfo entry for most capabilities (bce, ccc, initc, keypad, margins, XM,
ech) but lacks tmux-256color's `Smulx` (undercurl), title capabilities
(`tsl`/`fsl`/`TS`), `U8#1`, and differs in `khome`/`kend`/`kmous`/`flash`.
Clipboard `Ms`, cursor `Ss`/`Se`, 256 colours and 65536 pairs remain. Existing
panes keep tmux-256color until respawned; new panes pick up the new value
after the next client attach (or a new server).

## 2026-10-24 (2): tmux themes rewritten as tmux 3.8 themes

**Cause.** tmux 3.8 added the server-scoped `theme` option and the ten
`*-theme-*` palette slots. The loadout theme files still pinned styles to raw
hex (loadout2) or ANSI names (loadout1), so tmux's own built-in components
(tree selection, fill character, display-panes border, copy-mode defaults)
did not read the loadout design.

**Change.** `envs/tmux/themes/tmux-theme-loadout1.conf` and
`tmux-theme-loadout2.conf` are now real 3.8 themes:

- `loadout2`: `set -s theme dark` plus all ten `dark-theme-*` slots set to the
  existing literal hexes. Styles use `themeblack`, `themewhite`,
  `themelightgrey`, `themedarkgrey`, `themeyellow`, `themered`, `themeblue`;
  colours with no slot (pane fills, peach, the #45475a frame, the #6c7086 dim
  grey) stay literal hex. The forced palette keeps the render identical and
  terminal-independent. Green/cyan/magenta (unused by pinned styles) use
  catppuccin mocha values so built-ins stay in-palette.
- `loadout1`: `set -s theme terminal`, both palettes defined to the same ANSI
  names; its five settings now use theme names, preserving the ANSI rollback.

`tmux-settings-global.conf`, `docs/TMUX.md`, and `AGENTS.md` document the
mode: loadout2 supports `dark` only (no `light-theme-*` slots; `detect`,
`light`, and `terminal` would leave the design while the literal fills stay
dark), while loadout1 is safe under any mode because both palettes are ANSI
names. The bundled-version note is updated to 3.8.
`tests/install-env-tmux-nvim-layers` accepts a palette-backed theme name in
the file-level pin list and asserts the live server's mode, palette,
`status-style`, pane fills, and the loadout1 mode.

**Empty user settings re-seeded.** The live
`~/.config/tmux/tmux-settings-user.conf` was zero bytes, so it carried no
theme choice or documentation, and the old seed-only-if-absent rule preserved
it forever. `_seed_tmux_settings_user` now seeds when the file is absent or
empty (non-empty layers are still preserved), and the seed documents
loadout2/loadout1 plus the loadout2 dark-only rule. The test empties the file,
reinstalls, and asserts the theme section and default return.

**Verified.** Fresh `env-tmux` install + `tmux -f tmux.conf`: `theme dark`,
`dark-theme-blue "#89b4fa"`, `status-style "fg=themewhite bg=themedarkgrey"`,
`window-style "fg=themewhite bg=#000000"`. An attached client's captured
output contained the resolved RGB: `38;2;205;214;244` (themewhite),
`48;2;16;23;58` (themedarkgrey), `48;2;137;180;250` (themeblue). With
`@theme "loadout1"` the same chain yields `theme terminal` and
`window-status-current-style "fg=themewhite bg=themeblue"`.
`tests/install-env-tmux-nvim-layers` passes.

## 2026-10-24: 2026.10.7 shipped; tldr/xdesk retired; registry-sourced release notes; vim 9.2.1225

**2026.10.7** released (signed, verified): python-loaded, tldr retirement,
xdesk retirement, aiohttp 3.14.4 / nbconvert 7.17.2. Currency for that release
was a deliberate partial sweep (24 outdated packages deferred by owner
decision), recorded here rather than silently.

**tldr/tealdeer retired.** The tldr binary, bundled page cache, tealdeer config
and cache-dir baking, refresh path, completions, tests and docs are gone. The
working tree had carried that change uncommitted; it was verified
(registry/content/sizes/README) and committed before the python-loaded merge.

**xdesk retired, Xephyr kept.** The launcher's T2 gate needed host `xauth`,
which is not a reasonable deployment contract. `xephyr` now ships only the
nested X server (`Xephyr`, `Xephyr.bin`); the smoke is `Xephyr -help`.

**less 710.** Upstream removed the standalone `lesskey` helper in 710, so the
package ships `less` + `lessecho` and dropped it from the build script, bins,
docs, and probes. EL8 build, POSIX regex, glibc 2.14 floor; functional paging
verified.

**Release-notes version table fixed** (RELEASE.md failure entry 9): built from
`payload/packages.json` (`_version_table_from_registry`, 151 rows) instead of
`farm-versions` (which probes the build box). Also added the missing version
step to the low-memory sequential gate path.

**Currency batch:** ruff 0.17.2, uv 0.13.5, ty 0.0.91, starship 1.27.0,
biome 2.6.2, fresh 0.5.4 (NEEDED closures re-checked). `lefdef-tools` and
`time-plot` were already current. Blocked on this host: `liberty-tools`
(maturin rejects host GLIBC 2.33/2.34 — needs the EL8 image), `nodejs`
(`import-nodejs` needs nvm, now available — rerun). Remaining: 8 source
builds (nvim, lua-language-server, tmux, tree-sitter, typescript-language-
server, xterm, yosys, and vim/gvim are now done) and `liberty-filter`'s
date-vs-semver mismatch. Comparator mismatches for iverilog/openroad/
patchelf/rust-analyzer/z3 are documented as `pin_reason`.

**python-loaded is now `@shared-all`-only (2026-10-24, revised D9).** The
`standalone` flag was removed; the package is `optional: true`, so `@shared`
does not install it while `@shared-all` and `@all` do. `tests/registry-integrity`
pins that membership, and `tests/install-linux-tmp-home` (which selects
`@shared-all`) now builds the suite as part of its gate.

**vim + gvim 9.2.1225.** One EL8 checkout produces `vim.bin`, `gvim.bin` and
the `vim92.tar.bz2` runtime. Vim 9.2.12xx added Sixel support; its pixman
backend auto-enables when `pixman-1` is visible via pkg-config, which coupled
terminal vim to `gui_libs` on the first build (NEEDED `libpixman-1.so.0`).
`--disable-pixman` is now passed alongside `--without-wayland`, and
`build-vim.sh` fails if either reappears. Terminal vim closure stays
libm/tinfo/selinux/rt/dl/c only. No cmake involved in this build.

## 2026-10-23: python-loaded -- one curated import environment, no shared-bin links

`python-loaded` (`kind: python-suite`) is a single `uv venv` on the bundled
portable Python, built from `payload/python-loaded/requirements.in` (50 tops)
through a hashed lock and a **private** wheelhouse
(`payload/python-loaded/wheels`, 130 wheels, 243 MB, pyarrow chunked). It adds
nothing to `<prefix>/bin`. The user-facing shebang target is
`<prefix>/share/python-loaded/venv/bin/python3`, a symlink to
`versions/<lockdate>-<lockhash8>/venv`; uv's generated console scripts carry
absolute shebangs into the versioned directory, which is never renamed.

```bash
./loadout install python-loaded          # explicit only; in no sweep
./loadout info python-loaded             # lock date, abi, pins, tops, installed stamp
./build/update python-loaded             # full refresh (Docker + AlmaLinux 8)
./build/build-python-loaded.sh --print-plan
```

Rules that are load-bearing:

- **Patch vs minor.** The stamp is `{abi, lock_sha256}`. A 3.15.x patch needs
  no action: the venv symlink re-resolves through the replaced
  `bin/python3.15`, and cp315 extensions stay valid. A 3.15 -> 3.16 bump makes
  the installer FAIL with the exact regeneration command; the release that
  bumps `portable-python` must rerun the build.
- **Resolve on EL8.** `uv 0.13.1` mis-evaluates `python_version` markers for
  3.15, so the build resolves with pip on the real 3.15 interpreter. The
  wheelhouse is private because `uv tool install` for the existing python-tools
  is unpinned and would silently pick the suite's newer numpy/pandas.
- **Repair at build time.** `auditwheel repair --plat manylinux_2_28_x86_64`
  bundles non-policy libraries; locally built pure wheels are retagged
  `py3-none-any`. Install is decompression + `uv pip install --require-hashes`,
  never patchelf.
- **Excluded:** `evidently` (0.7.23 imports a pandas symbol removed in pandas 3,
  the only major with cp315 wheels), `uWSGI` (binary, not an import library),
  `kaleido` (needs a ~300 MB chrome-headless-shell; separate future package),
  `bst`/`pdfutil`/`pdf2jpg` (wrong/abandoned packages), CUDA/NCCL.
- Measured: build 125 s; install test 30 s.

## 2026-10-22 (4): STARSHIP_SHELL is per-shell and load-bearing -- tcsh was pinning the one value that breaks it

Reported from elsewhere: pinning `STARSHIP_SHELL=bash` in tcsh breaks
formatting. Validated, and the mechanism turned out to control TWO things,
which is why no single value is right for every shell:

| `STARSHIP_SHELL` | zero-width markers emitted | `when` shell |
|---|---|---|
| `bash` | readline `\[ \]` | bash |
| `zsh` | `%{ %}` | zsh |
| `tcsh` | `%{ %}` | **tcsh** |
| `sh` / unset | **none** | POSIX sh |

**The tcsh pin was wrong twice over.** `bash` gave the prompt readline's
`\[ \]`, which tcsh prints literally -- tcsh has no readline. That is what
`global/helpers/prompt-markers` exists to strip, so the pin CREATED the
problem the helper solves. And the reason for the pin was also wrong: it was
set to make the shared config's `when` snippets parseable, but `sh` already
does that.

**The trap that made "just unset it" wrong too:** `starship init tcsh
--print-full-init` exports `STARSHIP_SHELL=tcsh` ITSELF (line 1 of its
output). Unpinned, the `when` expressions run under tcsh, where
`custom.username`'s `for u in $VAR; do ... done` cannot parse at all -- that
module silently never appears, with no error. So the value has to be
explicitly `sh`, set AFTER the init so it overrides starship's own export.

**Fixed:** `setenv STARSHIP_SHELL sh` after the init in
`envs/tcsh/global/tcshrc`. `sh` is the only value that is both POSIX for the
snippets and marker-free.

While there, the same measurement corrected the bash and zsh envs from the
previous commit: bash pins `bash` (PS1 needs readline's markers to compute
the prompt width) and zsh pins `zsh` (`%{ %}`, and `starship init zsh`
exports it anyway) -- the zsh env had been pinned to `bash`, which would
have handed zsh readline's markers verbatim.

**Verified in a real PTY tcsh session** with a probe module:
`STARSHIP_SHELL=sh`, probe renders, `custom.username` renders, literal `\[`
count 0, literal `%{` count 0. Both wrong values RED-proven against the gate
(pin removed -> FAIL, pin set to `bash` -> FAIL); 20/20 with `sh`.

`tests/env-tcsh-starship` now asserts the pin is `sh` (it used to assert
`bash`, i.e. it was pinning the bug), `tests/env-shell-parity` 24/24.

## 2026-10-22 (3): every starship command runs under bash, whatever the outer shell -- and why not `--norc --noprofile`

Request: make every shell command starship runs use `/bin/bash --norc
--noprofile`, even when the outer shell is not bash. Two corrections to how
that can be done, both measured on the shipped starship (1.27.0):

**`STARSHIP_SHELL` is the switch, not `STARSHELL`.** A module's `shell`
falls back to `STARSHIP_SHELL`, and only then to `sh`
(`starship.rs/config/#custom-command-shell`). `starship init <shell>` does
NOT export it -- so every env has to. The tcsh env already did, deliberately
(`setenv STARSHIP_SHELL bash`, with the reason in a comment); the bash and
zsh envs did not, and were relying on `/bin/sh` -- which is dash on plenty
of hosts, where the shared config's `when` snippets behave differently.

**Fixed:** `export STARSHIP_SHELL=bash` in the bash and zsh envs, next to
their `starship init` calls, so all three envs now pin the same shell.

**Verified, in real PTY sessions with a probe module in the prompt:**

| outer shell | starship's command ran as |
|---|---|
| bash | `SHELL=bash INTERP=/usr/bin/bash` |
| tcsh | `SHELL=bash INTERP=/usr/bin/bash` |

**`--norc --noprofile` are NOT part of the fix, and the reason is worth
keeping.** `STARSHIP_SHELL` is a shell name, so flags can only go in a
module's own `shell = [...]` -- and they would buy nothing:

```
bash -c 'echo ran'                      → runs, no rc sourced
BASH_ENV=x bash -c 'echo ran'           → x IS sourced      (the hole)
BASH_ENV=x bash --norc --noprofile -c   → x IS STILL sourced (flags don't help)
```

A non-interactive bash reads no startup files already; the ONE file it does
read is `$BASH_ENV`, and neither flag suppresses it. Only `unset BASH_ENV`
closes that hole, and it would close it for every subshell rather than only
starship's. Not done here -- say the word if you want it.

**Also settled while checking "are starship modules customizable by env
var":** there is no config-time substitution. `style = "$FOO"` is emitted
verbatim by `print-config` and rendered as a literal, so a config VALUE
cannot follow a `LOADOUT_CFG_*` switch. Only `when` (whether the module
appears) and `command` (what it prints at run time) can -- and a built-in
module's `detect_env_vars` tests variable PRESENCE, not value, which
always-exported switches cannot express.

Localized gates: `tests/env-shell-parity` 24/24, `tests/env-tcsh-starship`
20/20 (the twin config was not touched).

## 2026-10-22 (2): the starship prompt honors LOADOUT_CFG_PROMPT_INCLUDE_HOST -- and the config file loses its "linux" suffix

**The switch did nothing under starship.** `LOADOUT_CFG_PROMPT_INCLUDE_HOST` is
exported by every shell env and honored by the hand-rolled fallback prompts
(bash/zsh/tcsh), but starship drives the prompt BY DEFAULT in bash and tcsh --
and the starship config had no hostname module at all. So the preference was
silently ignored in exactly the configuration that ships by default. (The
vendored schema confirms built-in modules carry no `when`, so this has to be a
`custom` module -- the `custom.lsf` pattern.)

**Fixed, in the shared config and the tcsh twin** (the twin gate requires them
to be identical apart from the directory style):

```toml
[custom.host]
when = 'test "$LOADOUT_CFG_PROMPT_INCLUDE_HOST" = "1" && test -z "$LSB_JOBID"'
command = "hostname -s"
format = "[$output]($style) "
style = "bold dimmed white"
```

The `LSB_JOBID` guard is not cosmetic: `custom.lsf` already renders
`LSF:<host>` on a farm node, so without it the host would appear twice.

**The bash built-in prompt had the same disease, differently.** `set_prompt`
COMPUTED the farm tag and the host into `prompt_joined` and then never used the
variable -- a dead one. So under starship the switch did nothing, and without
starship it did nothing either. `PS1` now renders `prompt_joined`, and `sp2`
(which passed an `include_host` argument that `set_prompt` ignored) is now the
zsh-shaped `LOADOUT_CFG_PROMPT_INCLUDE_HOST=1 set_prompt`. `sp1` drops it
again.

**Verified, not assumed:**

- real `starship prompt` renders: switch 0 -> no host; switch 1 -> the short
  hostname; switch 1 + `LSB_JOBID` -> `LSF:<host>` once, not twice; the tcsh
  twin renders the same.
- a real PTY **tcsh** session (starship-driven) starts with the host in the
  prompt.
- a real PTY **bash** session with starship disabled: `PS1` gains `:host` with
  the switch on; `sp2` adds it, `sp1` removes it.
- `env-starship` installs `~/.config/starship/starship.toml` +
  `config-schema.json` (the installer source path moved with the rename).

**New permanent checks** (both RED-proven -- they fail when the behavior is
removed):

- `tests/env-tcsh-starship`: both configs must PARSE, and the format string
  must reference a custom module whose `when` tests
  `LOADOUT_CFG_PROMPT_INCLUDE_HOST`.
- `tests/env-shell-parity`: the bash `PS1` assignment must use
  `prompt_joined` (the dead-variable regression), and the tcsh prompt must
  still assemble `_loadout_host`.

**The rename.** `envs/starship/starship.linux.toml` -> `envs/starship/starship.toml`.
Windows/macOS were retired from this repo on 2026-08-31, so the platform
qualifier in the file name was a leftover (and the tcsh twin is called
`starship-tcsh.toml`, not `starship.linux-csh.toml`). Updated: the installer's
source path (`loadout_main.py`), `tests/env-tcsh-starship`, the twin's
comment, `docs/INSTALLATION.md`, `AGENTS.md`'s repo map, the README's Starship
row, and the registry description -- which still read "Starship prompt config
(Linux/macOS variant)", a claim that has been false since 2026-08-31.

Regenerated `payload/installed-sizes.json` and `.content-manifest` (the env
packages ship the `envs/` trees, so their sizes moved).

## 2026-10-22 (1): the tcsh env's ssh-agent switch was a DEAD SWITCH -- and the parity gate let it pass

Found by a drift audit of the `LOADOUT_CFG_*` switches across the two envs:
exactly one variable the tcsh env READS but never DEFINES --
`LOADOUT_CFG_ENABLE_SSH_AGENT`.

**Why it was invisible.** `envs/tcsh/global/tcshrc` gates its fixed-socket
ssh-agent block on `if ( $?LOADOUT_CFG_ENABLE_SSH_AGENT ) then`, and
`envs/tcsh/global/config.csh` never defined the variable: `env-tcsh` does NOT
depend on `env-bash`, so the bash env's `export` never reached a tcsh session.
In tcsh `$?name` is 1 when the variable IS set and 0 when it is not, so the
guard evaluated FALSE and the block was skipped -- SILENTLY. No error, no
startup noise, no feature. The bash env's own copy of the switch was masked by
the assumption that "the variable is shared"; the rc comment even said so
("defined once in envs/bash/global/config.sh").

**The gate was part of the problem.** `tests/env-shell-parity` computed the
tcsh side as `config_names(read(TCSH_CONFIG)) | config_names(read(TCSH_TCSHRC))`
-- the rc's READ of a variable counted as coverage. Reading a variable is not
defining it, so the switch passed a gate whose stated job is to police exactly
this ("every LOADOUT_CFG_* the bash env defines is either defined in the tcsh
config or explicitly recorded as inapplicable").

**What changed:**

- `envs/tcsh/global/config.csh` now defines `LOADOUT_CFG_ENABLE_SSH_AGENT`
  (default `0`, same value and same meaning as the bash env's).
- `envs/tcsh/global/tcshrc`'s comment no longer claims the switch is "defined
  once in envs/bash/global/config.sh".
- `tests/env-shell-parity` separates DEFINITIONS from READS and fails on
  three new shapes: a variable either env READS but never DEFINES (a dead
  switch), a variable EXCUSED as inapplicable that the tcsh env still reads
  (the excuse is wrong, or the read is dead code), and the same dead-switch
  shape on the bash side. RED proof: removing the new definition fails two
  checks; the test is 22/22 with it.
- Functional proof (real PTY, `script`): with the switch on, the tcsh session
  exports `SSH_AUTH_SOCK=$HOME/.ssh/loadout-agent.sock` and the socket is live
  (`srw-------`, `ssh-add -l` reaches it); with the default `0` nothing starts
  and the rc stays silent.

The general rule this establishes: **the tcsh env owns its own copies of every
switch it reads** (it does not depend on `env-bash`), and a READ is not
coverage. `envs/tcsh/README.md` and `AGENTS.md` carry the rule.

## 2026-10-21 (3): yosys and sby are back -- the pyosys module is built for 3.15

`yosys` and `sby` are back in service. The `yosys -y` bridge (the LibreLane
synthesis path) needs a pyosys extension module built for the shipped
interpreter, and upstream publishes pyosys only per CPython ABI -- cp310 to
cp314t, no cp315 -- so the cp314 wheel refuses to load under 3.15 ("Python
version mismatch"). The module is now built from the yosys source against
portable-python 3.15.

**Five build-script bugs** (all in `build/build-yosys.sh`, all found by the
ABI gate the script already had):

- `python -m pybind11 --includes` prints COMPILER FLAGS (`-I<dir>`), so the
  leading `-I` made the include path fail the directory test and the build was
  skipped with "pybind11 headers not found".
- Upstream's `FindPyosysEnv.cmake` detects the pybind11/cxxheaderparser
  environment itself and overwrites the `PyosysEnv_PYTHON` cache variable, so
  `-DPyosysEnv_PYTHON` never survives ("Could NOT find PyosysEnv"). Its
  "virtualenv" strategy reads `$VIRTUAL_ENV` -- that is what has to be set.
- A comment line between the backslashes of a continued command ENDS the
  command: the remaining flags ran as a command of their own.
- The pyosys package installs into the INTERPRETER's site-packages
  (`YOSYS_INSTALL_PYTHON_SITEDIR` defaults to `Python3_SITEARCH`), which here
  is the repo's own bootstrap tree -- the build was writing into the checkout.
- **`YOSYS_BUILD_PYTHON_ONLY` is a DEPENDENT option.** Upstream forces it OFF
  unless neither the driver nor the library is installed
  (`cmake_dependent_option(... NOT (YOSYS_INSTALL_DRIVER OR
  YOSYS_INSTALL_LIBRARY) AND YOSYS_INSTALL_PYTHON)`), so the build produced
  the yosys CORE library -- also named `libyosys.so`, also 49MB, and not a
  Python module at all ("dynamic module does not define module export
  function"). Both install switches have to be off for the extension to be
  what gets built.

**The build is cached** (the pattern `build/build-openroad.sh` uses for
OR-Tools): the source tree, the cmake build tree and the installed module
live under `$LOADOUT_BUILD_CACHE`, so a re-run is incremental instead of
another 15-minute compile. The stamp is written only after the ABI gate has
passed -- a stamp written earlier could mark the core library as a usable
module. `YOSYS_NO_CACHE=1` forces a rebuild.

**The package ships ONLY `pyosys/{__init__.py,libyosys.so}`** (plus the
vendored click). Upstream's install directory also holds the techlib
`share/` tree and a second `yosys-abc`, and those are moved out of the
package rather than packed: `__init__.py` prefers a package-local `share/`
over the one next to the yosys binary, so shipping them would duplicate
every data file in the tree AND make the `-y` path read its techlib from the
package -- i.e. from the build host -- instead of from the prefix it was
installed into. The relocation smoke now asserts that: it fails if
`sys._pyosys_share_dirname` is set, so the data tree provably comes from the
relocated prefix. The `yosys-abc` IS carried by the package, as a RELATIVE
symlink to the prefix's own `bin/yosys-abc`: the module looks for it next
to itself, and the tree still holds only one copy.

**Two wrapper fixes the build's own smoke could not see** (the build host
has `libffi.so.6` in `/usr/lib64` and its `/tmp` is not the target's):

- The `-y` path execs the interpreter, and the module is `dlopen()`ed *by
  the interpreter*, which has no RPATH of its own -- so the import of
  `libyosys.so` failed on `libffi.so.6` even though the yosys package
  installs it into `<prefix>/lib64`. The wrapper now puts the prefix's
  `lib64`/`lib` on `LD_LIBRARY_PATH`.
- The module copies the genlib and the netlist into a temp directory and
  reads them back BY NAME. The wrapper now points `TMPDIR` into the prefix
  (unless the caller set one), so the module's temp files stay on the
  prefix's own filesystem. This does NOT fix the failure below -- it only
  changes where the temp directory lives.

**End-to-end check, and an OPEN host-only failure.** Installing the shipped
payload (`loadout install yosys portable-python --dest-dir ...`) and
running `yosys -y` with a real synthesis and ABC passes in the EL8
container: `E2E_OK 0.69+post`.

On THIS dev host the same install fails with `ABC: execution of script
... failed: return code 127` (ABC cannot read the genlib the module copied
into its temp directory). What is known:

- It is NOT the filesystem of the prefix: the container run used a prefix
  under the host's `/tmp` (the same tmpfs) and PASSED, and the host run
  also failed with a prefix on the host's nvme-backed home.
- It is NOT fixed by moving `TMPDIR` into the prefix (the temp directory
  moved; the failure did not).
- The build's own relocation smoke passes -- but it runs in the container,
  where the end-to-end also passes.

So the difference is between the container's mount namespace and the host's
-- or something else host-side -- and it is NOT yet explained. The payload
is correct on the target platform; the host-only failure is unresolved.
Reproduction, for whoever picks it up:

```
D=/home/mylesp/e2e-prefix; H=/home/mylesp/e2e-home
env -i HOME="$H" PATH=/usr/bin:/bin XDG_DATA_HOME="$H/.local/share" \
  ./loadout install yosys portable-python --dest-dir "$D" --yes
cd "$D" && PATH="$D/bin:/usr/bin:/bin" "$D/bin/yosys" -y smoke.py
```

(the same prefix directory mounted into the container passes).

**Gate state:** 62 PASS / 1 FAIL at the time of that session. The failure was
`install-xdesk` ("nested server accepted a connection with no cookie"), an
environmental X-server assertion (the host has no `xauth`). The `xdesk`
launcher and its gate were retired 2026-10-23; `xephyr` now ships only the
nested X server.

**The binary smoke test.** `tests/prebuilt-binaries` (and its container
variant) had three failures on a fresh install, all now fixed:
`idle3.15` had no `PROBE_FLAGS` entry, so it got the default probe --
IDLE rejects `--version` but accepts `-h`; and `pip3`/`pip3.15` are 185-byte
shebang scripts whose exec needs a lookup of a file the installer created
moments earlier, which on some kernels returns ENOENT while `readdir()`
So a probe that cannot exec a shebang script now runs it through the
interpreter named next to the script, with the script copied to a fresh
path. Both variants are green: the host variant passes idle3, idle3.15,
pip3 and pip3.15; the container variant reports "All 312 binaries OK (23
skipped)" -- idle3 and idle3.15 among the skipped, because the container has
no loadable Tk (the host-capability entry names all three), and the yosys -y
probe passes there too.

## 2026-10-21 (2): `@shared-all --dest-dir` audit -- the 3.15 sweep never rebuilt the payloads that embed the interpreter

Operator request: run a `@shared-all` install into a `--dest-dir` and audit it
so that NO local (dev-host) dependency can shroud a missing one on another
system.

**The audit.** `loadout install @shared-all --dest-dir <prefix>` (clean
`env -i`, temp HOME/XDG) produced a 5.9 GB tree, then every ELF in it was
resolved twice with the SAME script: once on the dev host (CachyOS, glibc
2.44) and once inside a clean `almalinux:8.10` container with only the tree
mounted. Diffing the two runs per (binary, soname) is the whole point --
a library that resolves on the dev host but NOT in the container was satisfied
by a HOST library the payload never bundled.

The diff was NOT empty: **307 (binary, library) pairs resolved differently**.
287 of them resolved on the dev host and were MISSING in the EL8 container.

**Four real defects, all the same root cause.** The 2026-10-10 Python 3.15
sweep (commit `817d636`) replaced the payload interpreter (portable-python
3.14.7 -> 3.15.0) and swept every *reference* to the new version across build
scripts, docs and tests -- but it did not REBUILD the payloads that embed or
invoke that interpreter. The repo templates were all correct; the shipped
artifacts were not:

| Payload | Symptom on a clean EL8 host | Masked on the dev host by |
|---|---|---|
| `klayout` | every launcher died: `error while loading shared libraries: libpython3.14.so.1.0` | the host's `/usr/lib/libpython3.14.so.1.0` (Arch `python 3.14.8`) |
| `openroad` | same: `libpython3.14.so.1.0` not found | the same host library |
| `sby` | `sby: no python3 found` -- the wrapper ran `$prefix/bin/python3.14`, then fell back to `command -v python3.14` | the host's `/usr/bin/python3.14` |
| `yosys` | `yosys: -y needs the bundled interpreter, but <prefix>/bin/python3.14 is missing` (no fallback -- dead everywhere) | nothing; it was broken on the dev host too |

52 ELFs in the tree linked `libpython3.14.so.1.0` (all of KLayout) and one more
was `openroad`. The KLayout `pymod/klayout/*.so` extension modules were
`cpython-314` ABI as well.

**The fixes.**

- **OpenROAD (FIXED, shipped):** `build/build-openroad.sh` already extracted the
  payload's own portable-python for the embed; a rebuild was all that was
  needed. The binary now links `libpython3.15.so.1.0`.
- **KLayout (DISABLED, not shipped):** rebuilding needs MORE than a rebuild --
  upstream v0.30.12 uses `PyWeakref_GetObject`, which Python 3.15 REMOVED, so
  the pya build fails with `error: 'PyWeakref_GetObject' was not declared in
  this scope; did you mean 'PyWeakref_GetRef'?`. `build/build-klayout.sh` now
  applies upstream's own fix (the 3.15 branch of
  `src/pya/pya/pyaSignalHandler.cc`, from klayout master) as a guarded patch
  and ASSERTS it applied -- a silent no-op there is how the stale payload
  shipped in the first place. The patch is in place and the build was proven
  to get past it, but the ~25 min EL8 source build was NOT completed in this
  pass, so the package is DISABLED rather than shipped broken. Rebuilding it
  is the next step; the build script is ready for it.
- **yosys (DISABLED, not shipped):** the upstream `pyosys` wheels are published
  per CPython ABI (cp310..cp314t) and there is NO cp315 wheel -- and a cp314
  extension REFUSES to load under 3.15 (`ImportError: Python version mismatch:
  module was compiled for Python 3.14, but the interpreter version is
  incompatible: 3.15.0`). The wheel route therefore made `yosys -y` -- which
  every LibreLane stage-5 script execs -- dead on arrival. The fix (building
  the pyosys module for the shipped interpreter from the yosys source tree,
  upstream's `YOSYS_WITH_PYTHON=ON` path) is FEASIBLE and was proven to
  configure correctly against portable-python 3.15, but it needs a full yosys
  rebuild; deferred, so the package is DISABLED rather than shipped broken.
  `build/build-yosys.sh` carries the source-build path (with a venv that
  picks a python whose pip can resolve pybind11 3.x -- EL8's system python3 is
  3.6, whose pip 9.0.3 cannot) and an ABI GATE: the staged module must
  actually import under python3.15 or the build fails.
- **sby (DISABLED, not shipped):** it hard-depends on `yosys`, so it is taken
  offline by the same cascade (see below) rather than installing a tool that
  cannot run. Its own build fixes ARE in place for the day yosys comes back:
  `build/build-sby.sh` now resolves the interpreter the way
  `build/build-klayout.sh` does (`LOADOUT_PY_PREFIX`, then the repo's own
  bootstrap tree, then PATH) instead of calling a bare `python3.15` that the
  build image does not have, and two more gaps in the same script were fixed:
  the stage-verify staged `yosys` but not `yosys.bin` (the payload ships the
  real ELF under that name since the wrapper split), and the staged `sby` fell
  back to the build image's python3.6 -- which dies on click's `from __future__
  import annotations` (a 3.7+ feature), so the prove smoke could never have
  passed.

**NEW MECHANISM: `disabled` -- taking a package out of service.** The registry
gained a `disabled` flag (with a `disabled_reason` string) so a package whose
payload is known-broken can be withdrawn from every deployment without
deleting it. Semantics, as decided by the operator:

- A disabled package is excluded from EVERY sweep (`@shared`, `@shared-all`,
  `@envs-all`, `@all`) and REFUSED when named directly, with the reason
  printed.
- The cascade runs **UP** the dependency chain only, and only through HARD
  dependencies: a package that hard-depends on a disabled one is offline too
  (that is how `sby` goes offline with `yosys`), but a package the offline one
  depends on is NOT (offlining `klayout` leaves `portable-python` alone), and
  a SOFT `recommends` edge never propagates (a recommendation never forces
  anything, so it never takes a package out of service).
- A disabled package pulled in by a GROUP is skipped with a warning (a group
  is a sweep, not a demand); named directly, it is a hard error.
- Terminuology note: this is NOT the project's "offline" (which means "no
  network needed" -- the #1 feature of an offline-first package manager). The
  flag is called `disabled` for exactly that reason.

**The new gate.** `tests/payload-interpreter-abi` (Tier 1) audits the PAYLOAD
(not the repo templates) so this class cannot ship again silently: no payload
ELF may link a `libpython3.X` other than the shipped version; no shipped
script may PICK an interpreter other than the shipped version (the shapes that
count are `.../bin/python3.X`, `command -v python3.X` and `env python3.X` --
a mere mention does not, which is why cloc's language table and taplo's uv
schema catalog are not false positives); and no shipped extension module may
carry a `cpython-3XX` tag other than the shipped ABI. It also asserts the
registry's `portable-python` version matches the shipped archive. Artifacts
belonging to a DISABLED package are reported but not failed: they cannot reach
a deployment.

**Why the existing gates missed it.** `tests/prebuilt-binaries` DOES run
`ldd` in the clean EL8 container and WOULD have failed on `libpython3.14.so.1.0`
-- but it is a Tier 3 gate (needs `--container`), and no Tier 3 run happened
after the 3.15 sweep. The new Tier 1 gate needs no container, so it runs on
every commit.

**THE DURABLE FIX -- fail in seconds, not at release time.** The operator's
point, and the reason this took hours to unpick: the whole wave was
INVISIBLE until a user installed on a node that did not have the dev host's
libraries. The expensive gate (the Tier 3 container smoke) runs at RELEASE
time, so the feedback loop was "merge -> hours of release prep -> a failed
install on a farm node -> hours of rebuild". Two gates now close that loop at
COMMIT time, in seconds, with no container and no network:

- `tests/payload-interpreter-abi` -- the payload must agree with the shipped
  interpreter (no ELF linking another `libpython3.X`, no script picking
  another interpreter, no extension module with another ABI tag).
- `tests/wheelhouse-closure` -- every ENABLED python-tool must resolve
  offline from the bundled wheelhouse under the shipped interpreter. This is
  the gate that catches the cp314-wheel-under-a-cp315-interpreter class: it
  walks each tool's dependency closure over the wheelhouse and requires an
  installable wheel (cp315 / abi3 / pure-python) at every step, evaluating
  environment markers so `tomli; python_version < "3.11"` is correctly not a
  dependency. RED-proof: re-enabling `librelane` in the registry makes it
  fail with the exact offending wheels named.

Both are in the Tier 1 suite (`tests/run-all --fast`, ~2 min) AND in the
release gate: `build/release` gained a "Step 0b: Verifying the payload agrees
with the shipped interpreter" step, so a release can no longer ship a payload
whose interpreter and contents disagree. The rule this restores: **a payload
change must be provable by a gate that runs in seconds**; the container smoke
is the last line of defence, not the first detector.

**Also fixed in passing:** `build/build-shell` now puts the repo's own
python3.15 bootstrap on PATH inside the build container (the build image
deliberately does not install python3.15, and several repo scripts carry a
`#!/usr/bin/env python3.15` shebang -- `strip-all-elf-binaries`,
`gen-installed-sizes`, `gen-content-manifest` -- so they died with "env:
'python3.15': No such file or directory"; this is what broke
`build/build-klayout.sh`'s final strip step). `build/build-sby.sh` (interpreter
resolution, `yosys.bin` staging, stage interpreter),
`build/build-klayout.sh` (the 3.15 weakref patch), `build/build-yosys.sh` (the
pyosys source-build path + ABI gate).

## 2026-10-21 (1): shared nvim stash is found from the binary, not only LOADOUT_CFG_SHARED_PREFIX

Reported split-deployment failure: userA installs `@shared-all` (shared nvim +
stash + private git), userB installs only `env-nvim` and puts the shared
`<root>/bin` on PATH. Starting nvim fell back to `https://github.com` for
`lazy.nvim` and failed offline -- the shared stash was present but invisible.

Reproduced with two temp HOMEs and a temp prefix: with a clean environment
(`env -i`, no `LOADOUT_CFG_SHARED_PREFIX`) and github blackholed, nvim reported
`plugins=false` and `fatal: unable to access 'https://github.com/...'`. The
stash resolved to `~/.local/share/nvim/loadout/vendor/plugin-stash` (absent)
because `paths.lua` only consulted the env var.

Fix in `envs/nvim/lua/global/paths.lua`:
- `shared_roots()` returns `LOADOUT_CFG_SHARED_PREFIX` first, then the root
  inferred from the running binary (`vim.v.progpath` -> `<root>/bin/nvim`, with
  `<root>/share/nvim` present, realpath-resolved). `M.data`/`M.share` search the
  user path first, then every root.
- `M.stash()` honors `LOADOUT_CFG_NVIM_PLUGIN_STASH_DIR` /
  `vim.g.cfg_nvim_plugin_stash_dir` (documented override; previously set but
  never read).
- `M.ensure_git()` searches the derived roots too and prepends
  `<root>/lib64:<root>/lib` for the EL8 private git, whose `libcrypto.so.1.1`
  is absent on OpenSSL-3-only hosts.

New T2 `tests/install-nvim-shared-stash`: installs `nvim` +
`nvim-plugin-stash` + `git-nvim` into a temp prefix and `env-nvim` into a temp
HOME, then runs the shared nvim with `env -i`, PATH containing only the shared
bin (no system git; a `dirname` shim lets the private-git wrapper run) and
github blackholed. Asserts `loadout_plugins_enabled`, the resolved stash path,
`lazy.nvim` origin == the shared stash, and >=2 cloned plugins. Verified:
`plugins=true`, private git discovered, 24 plugins cloned from the shared stash
with no network. `install-nvim-deployments` and Tier 1 stay green.

## 2026-10-20 (5): home-dir tmux config merged into the managed layers

The live `~/.config/tmux/tmux-user.conf` still carried three settings that the
managed layer did not: `allow-passthrough on`, `default-terminal
"tmux-256color"`, and a guarded `terminal-features 'xterm-256color:sync'`
append. Merged into `envs/tmux/tmux-global.conf`; the live user file is reset to
the shipped seed (comments + optional tmux-yank). The older
`tmux-user.conf.aside` content (FFM, block cursor, wheel binds, j/Down/G) was
already merged 2026-10-12 and remains a backup only.

Details:
- `default-terminal` replaces `set -s default-terminal "$TERM"` -- the explicit
  name keeps terminfo stable across reloads/clients.
- `allow-passthrough` is a SESSION option despite the name: `set -s` writes a
  phantom server entry and leaves the effective value `off` (same trap as
  cursor-style). The merged line is `set -g allow-passthrough on`.
- The sync append is marker-guarded like `xterm*:extkeys`; `terminal-overrides`
  and `terminal-features` no longer grow on `Prefix+r` (verified: 3 overrides
  and 5 feature entries after three loads, unchanged).
- The operator's working-tree edits are included: `nhdaly/tmux-better-mouse-mode`
  is no longer declared, so the managed root-wheel binds are active (resolves
  the 2026-10-12 open question); array reload guards added.
- `tmux-theme-loadout2.conf` drops `window-status-activity-style`: the activity
  flag cannot fire because `monitor-activity` is off (tmux default), and the
  test now asserts that instead of requiring the unused pin. The bell style
  stays pinned -- `bell-action none` suppresses the action, not the flag.

Verification: `tests/install-env-tmux-nvim-layers` asserts the merged lines,
the plugin is not declared, live-server values (`default-terminal`,
`allow-passthrough on`, sync feature), and the activity-off invariant. A live
scratch server with the installed dispatcher reports `default-terminal
tmux-256color`, `allow-passthrough on`, sync+extkeys, 3 overrides after reloads.
Live install re-sealed the managed tree; `tmux-user.conf` is 644 and the seed.

## 2026-10-20 (4): portable Python gets the host CA store -- check-versions/update HTTPS works with no env var

The EL8 portable Python compiled OpenSSL's cert paths to
`/opt/cpython3150p/ssl` (absent after deployment) and its original
`sitecustomize.py` only probed `/etc/pki/tls/certs/ca-bundle.crt` (RHEL).
On Arch/Debian-family hosts every HTTPS request failed:
`CERTIFICATE_VERIFY_FAILED: unable to get local issuer certificate` -- 111 of
158 `check-versions` lookups; `SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt`
was the workaround.

Fix: `build/portable-python-sitecustomize.py` probes
`/etc/ssl/certs/ca-certificates.crt`, `/etc/pki/tls/certs/ca-bundle.crt`,
`/etc/ssl/cert.pem` in order and sets `SSL_CERT_FILE` only when the caller set
neither `SSL_CERT_FILE` nor `SSL_CERT_DIR`. `build/import-portable-python`
injects it into the archive's **stdlib** `lib/pythonX.Y/sitecustomize.py`
(site-packages would be shadowed); the build's own hook (OPENSSL_MODULES,
TCL_LIBRARY, TK_LIBRARY + its single RHEL path) is renamed to
`sitecustomize_portable.py` and imported afterwards. The current
`portable-python-3.15.0-el8-clang23.tar.bz2` was repacked with the hook;
`installed-sizes.json` and `.content-manifest` regenerated.

Verification: `tests/portable-python-ca` extracts the payload interpreter,
proves the host bundle is selected with no env, `create_default_context()`
loads 121 certs, the build hook still sets TCL_LIBRARY, and a caller-set
`SSL_CERT_FILE` wins. Re-running `check-versions --outdated-only` with no SSL
variables: 0 TLS failures (only the ncdu 503 remains). The warm
`.loadout-bootstrap` cache was patched in place; older warm caches need
deletion or a reinstall to pick up the archive hook.

Canonical notes (why, precedence, stale copies, internal CAs, rebuild):
`docs/PYTHON-CA-TLS.md`.

## 2026-10-20 (3): every managed env config is read-only -- agentic edits cannot be lost to the next install

Operator follow-up: agentic AI experiments on installed configs routinely edit
files that `loadout install` overwrites, silently discarding the work. The
2026-10-20 (2) tmux fix generalized to all env handlers.

`_seal_managed()` now runs at the end of every env handler (after in-place
rewrites such as `_mirror_shared_prefix`, helix relocation, and tealdeer
regeneration): bash/tcsh/zsh managed trees + entrypoints, nvim
init/lua/global/lsp/after-lsp/shipped ftplugins, vim vimrc + pack/vendor,
tmux managed tree, st global, starship, helix, editorconfig, pip, tealdeer,
and generic-file envs (btop, wezterm). Files 0444, dirs 0555, exec bits kept.

Deliberately writable surfaces: bash/tcsh/zsh corp..user layers, nvim
`lua/user` and `lazy-lock.json` (Lazy rewrites it), st user layer, tmux user
layers, and seed-once app-owned files (`env-xfce4-terminal`, which the
terminal rewrites). Reinstalls re-heal the dirs and re-seal.

`tests/env-managed-readonly` (new Tier 2 gate) installs every env into a temp
HOME, asserts managed 0444/0555 vs user-writable surfaces, rejects a write
through a managed path (non-root), and proves reinstall re-seals drift.
`install-env-tcsh` still fails its pre-existing completion assertion on this
host (prompt-prefixed `grep -c` output); reproduced identically on the
unmodified HEAD worktree, so it is not from this change.

## 2026-10-20 (2): env-tmux managed tree is read-only; only the user layers stay writable

Operator report: after `loadout install env-tmux`, every file under
`~/.config/tmux` was owner-writable. The documented intended-permissions rule
was the opposite ("every installed file/dir gets owner-write"), so this is a
policy change, not a regression fix: managed config and vendored content are
replaced by the next install and must not be edited in place.

New `_seal_managed(path)` clears write bits recursively, preserving read and
execute bits (plugins/scripts keep running) and skipping symlinks. At the end
of `_install_env_tmux`:

- `tmux.conf`, `tmux-settings-global.conf`, `tmux-global.conf`,
  `word-separators.conf` -> 0444;
- `themes/`, `scripts/`, `plugins/` -> 0555 (exec files 0555);
- `tmux-user.conf` and `tmux-settings-user.conf` -> owner-writable (the
  top-level `~/.config/tmux` also stays writable because it holds them).

Every reinstall re-heals the dirs through `require_writable_dir`/`sync_dir`
and re-seals at the end, so `chmod u+w` drift (and the reinstall test's stale
markers) is repaired. `tests/install-env-tmux-nvim-layers` now asserts the
fresh-install modes, re-seals after simulated drift, keeps user layers
writable, and re-opens the tree in cleanup before `rm -rf`. Backup-enabled
reinstall over the read-only tree verified manually (backup contains the
files and both installs exit 0).

## 2026-10-20 (1): env-xfce4-terminal -- operator's 1.2.0 config absorbed and translated for the EL build

New `env-xfce4-terminal` package (`envs/xfce4-terminal/`). The operator's live
Xfconf channel was absorbed verbatim from
`~/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-terminal.xml` (twelve
properties: font, palette, scrolling, copy-on-select, right-click paste,
unsafe-paste dialog, URL highlight, menubar, blink mode, maximize).

**Two formats, one setting set.** xfce4-terminal 1.1.0+ reads xfconf; the
loadout build (1.0.4, EPEL8 shanghai) reads `~/.config/xfce4/terminal/terminalrc`
with each property's **blurb** as the key (`terminal-preferences.c`:
`xfce_rc_read_entry (rc, g_param_spec_get_blurb (pspec), ...)`).
`envs/xfce4-terminal/terminalrc` is the 1.0.4 translation; both files are
**seeded once** by `_install_env_xfce4_terminal` (only when absent) and then
owned by the user: xfce4-terminal rewrites them when preferences change, so a
reinstall must not clobber them and they stay writable. Per-file install, not
`install_path()` on `~/.config/xfce4`, which would sync with delete=True and
remove other apps' xfconf channels.

**Compatibility, 12 settings -> 11 exact + 1 gap.** Every key exists in 1.0.4
and enum spellings match (`TERMINAL_SCROLLBAR_NONE`,
`TERMINAL_RIGHT_CLICK_ACTION_PASTE_SELECTION`,
`TERMINAL_TEXT_BLINK_MODE_NEVER`); `ColorPalette` keeps the `rgb()` form
because 1.0.4 parses it with `gdk_rgba_parse()`. The gap is
`misc-maximize-default`: no `MiscMaximizeDefault` exists in the 1.0.4 property
table, so `terminalrc` deliberately omits it (1.0.4 offers only the
`--maximize` CLI flag). The XML keeps the setting for 1.1+ hosts.

**Proof:** `tests/install-env-xfce4-terminal` asserts both seeded files are
byte-identical to the shipped copies and mode 644, an unrelated xfconf channel
survives fresh install and reinstall, user edits and a pre-existing config are
preserved across reinstall, and mechanically enforces the 1.2.0 -> 1.0.4
mapping (every XML property has an exact terminalrc key or is the one
documented exception; terminalrc has no extra keys).

## 2026-10-19 (1): issue #4 -- env-bash now creates its five override layers

`install_bash()` installed `global/` plus the entrypoint files but never created
`~/.config/bash/{corp,site,team,project,user}`, while `_install_env_tcsh` and
`_install_env_zsh` both did. The shipped `envs/bash/bashrc` sources all five via
`source_if_exists`, and a post-install hardening step (psg-env) makes
`~/.config/bash` read-only and re-opens only `~/.config/bash/user` -- on a fresh
HOME that path did not exist and could no longer be created.

Fix: `install_bash()` loops `BASH_LAYERS` with `ensure_dir` after installing the
managed files, so a fresh install creates the directories and a reinstall leaves
user contents untouched (only `global/` is synced with delete semantics).
Regression proof: new `tests/install-env-bash` (registered in `tests/run-all`
Tier 2) asserts all five directories after a fresh install and after a reinstall
that must preserve a user `bashrc`.

## 2026-10-12 (4): the operator's personal tmux user layer merged into the managed global layer -- and the installed-tree drift ported

**Goal (operator):** everything running on this host is the loadout out-of-box
experience. So `tmux-user.conf` + `tmux-settings-user.conf` (the two personal
layers) move into the managed global layers, and the installed-tree drift found
by the earlier inventory gets ported at the same time.

**Merged into `envs/tmux/tmux-global.conf`** (order-preserving: inserted after
every active binding the user layer used to override, before the commented-out
legacy mouse graveyard):

- `set -g -w cursor-style block` -- **scope FIXED.** The user-layer original was
  `set -s cursor-style block`, but `cursor-style` is a WINDOW option
  (`options-table.c`: scope `OPTIONS_TABLE_WINDOW|OPTIONS_TABLE_PANE`), so `-s`
  wrote a phantom server entry and the window option stayed `default` (verified
  on the live server and on a fresh scratch server). The block cursor the
  operator saw was alacritty's own default, not tmux's. Visually identical on
  this host; the difference appears only where an application uses DECSCUSR.
- Copy-mode entry with `-e` (`Prefix+[` / `PgUp` / `PgDn`), the 3-line wheel-notch
  and root-wheel binds, the `j` / `Down` / `G` bottom-exit handling.
- FFM and the theme were already in the settings layers with identical values,
  so nothing was duplicated.

**Discovery: the user layer's wheel block has been dead code since it was
written.** `nhdaly/tmux-better-mouse-mode` is still declared in
`tmux-global.conf`, and TPM sources plugins after the user layer, so the
plugin's generated bindings win at runtime. Evidence: the live root
`WheelUpPane` binding's innermost else is `copy-mode -e -t= ; send-keys -M x3`
(the plugin's script-built shape, odd whitespace included), not the user file's
`-X -N 3 scroll-up`. The user file's comment claiming the plugin was "removed
from tmux-global.conf" was simply wrong. **Decision: keep the declaration** --
the instruction was "exactly what I have right now", and today's behaviour is the
plugin's -- and ship the block with an explicit SHADOWED comment naming the
one-line activation (drop the `@plugin` line), which restores the documented
first-wheel-up fix. **Open question for the operator: drop it or keep it.**

Related semantic check, recorded because it is easy to get wrong: `set -g
@plugin X` **replaces**, it does not accumulate (`show-options -g @plugin` after
two sets shows only the last value, in both `-g` and `-gA` list form). Three
declarations still work in practice because TPM sources plugin *directories*;
the declaration list is not the source of truth for what gets sourced.

**Ported from the installed tree** (the drift the 2026-10-12 inventory found):
`bind-key 7` -> `tmux-3col-layout.sh --left-last`, and the newer
`scripts/tmux-3col-layout.sh` (154 lines: `move_to_index`,
`pane_last`-based left-last mode, 35/35/30 widths) replacing the older
classic-only 73-line version. Nothing was lost -- the repo-only lines in the
diff were the old implementation of the same classic path.

**Equivalence proof** (two scratch servers, full `show-options -gA` /
`-g -w -A` / `-s -A` + `list-keys` dumps):
A = today's layering (installed managed files + personal user files);
B = post-merge (repo managed files + shipped user templates = a fresh install);
B' = B with the user's verbatim `-s` cursor line.

- A vs B': **identical** -- the merge is behaviour-preserving.
- A vs B: **one line** -- `cursor-style default -> block`, the intended fix.

**Gates/docs.** `tests/install-env-tmux-nvim-layers` gained a merged-defaults
block (key 7 + `--left-last` support, the cursor pin, the wheel binds, the
copy-mode-vi exit binds), so a future refactor cannot silently drop them.
README, `docs/TMUX.md` (new "Mouse wheel and cursor" section + `Prefix+7` row)
and AGENTS.md synced. Env sources changed -> `gen-installed-sizes` then
`gen-content-manifest` regenerated in that order.

**Deploy note for the operator's own test:** the merged `tmux-global.conf` was
copied into `~/.config/tmux/` (the 3col script there already matched). The
dispatcher sources both user files unconditionally, so *removing* them makes the
next reload print a `source-file` error; leave empty files, or re-run
`loadout install env-tmux -y` after moving them aside (it re-seeds the templates
only when absent).

## 2026-10-12 (3): shipped tmux defaults flipped -- @theme=loadout2 and focus-follows-mouse ON

Both user-facing defaults in the managed tmux settings layers changed. The
mechanism is unchanged; only the shipped values are.

- `tmux-settings-global.conf` and the seeded `tmux-settings-user.conf`:
  `@theme "loadout1"` -> `"loadout2"`. loadout2 is the fully-pinned,
  terminal-independent theme from entry (2); loadout1 is now purely the
  pre-2026-10-01 rollback. This also removes the hazard the baseline used to
  document about itself -- a missing or broken user layer fell back to
  loadout1's 1.19:1 active window under catppuccin mocha. The baseline is now
  the safe one.
- `focus-follows-mouse`: OFF -> ON in the managed baseline (still `%if`-guarded
  on tmux >= 3.7). The 2026-10-06 trial entry below concluded positively, and
  hovering only means anything with mouse mode, which `tmux-global.conf`
  enables. The seeded user layer now carries the commented OPT-OUT
  (`set -g focus-follows-mouse off`) where it used to carry the opt-in.

Preservation semantics are unchanged: user layers are seeded only when absent,
so existing installs keep whatever their `tmux-settings-user.conf` already says
-- only fresh installs (and new users on a shared tree) pick up the new
defaults. On this dev host nothing visibly changes: the preserved user layer
already selected loadout2 and FFM on.

`tests/install-env-tmux-nvim-layers` updated to pin the new defaults (theme in
both layers; baseline FFM on plus the user opt-out hint) and to prove the
layering in the other direction on a real server (baseline on, user override to
off). The reinstall-preservation case now appends `loadout1` to the user layer
and asserts it survives -- i.e. a user choice that contradicts the new default
is not reset. README, `docs/TMUX.md`, AGENTS.md and the Copilot instructions
were synced; `docs/TMUX.md` was added to the AGENTS.md doc-sync list, since it
had drifted unnoticed (it documented both old defaults).

## 2026-10-12 (2): tmux loadout2 theme made terminal-independent -- window-style pinned (the pane-fill cue used to invert on non-black terminals)

**Symptom.** On this host the active pane is a slightly raised dark-gray over
black inactive panes; a friend on Windows Terminal saw it *backwards* --
near-black active over dark-gray inactive -- on the same tmux version (3.7c).

**Cause (proved).** loadout2 painted only the ACTIVE pane. `window-active-style
"bg=#090909"` was set; `window-style` was set nowhere, so it stayed at tmux's
`default`. tmux's own options table defines `window-style` as *"Default style of
panes that are not the active pane"*, and `default` there means **paint
nothing**: `tty.c` fills `cached_gc` from `window-style` and `cached_active_gc`
from `window-active-style`, and a default marker leaves the cell to the
terminal. So the inactive fill was whatever the terminal paints -- pure black
here (alacritty pins `background = "0x000000"`), a lighter gray on Windows
Terminal. The two fills are only 1.055:1 apart, so a background lighter than
#090909 flips which one reads as raised; the theme's own comment had already
predicted "the active pane reads as a sunken hole instead of a raised block".
Nothing version-dependent -- each machine rendered exactly what its terminal
supplied.

**Fix -- the theme no longer delegates any colour to the terminal**
(`envs/tmux/themes/tmux-theme-loadout2.conf`):

- `window-style "fg=#cdd6f4 bg=#000000"` (the regression) and
  `window-active-style "fg=#cdd6f4 bg=#090909"`. Both pane classes are now
  painted, and `fg` is pinned too, so default-coloured application text is
  theme-coloured instead of terminal-coloured.
- Every previously ANSI-named tmux default, pinned: `mode-style`,
  `copy-mode-{match,current-match,mark,line-number,current-line-number}-style`,
  `message-style` / `message-command-style` (with `fill=`),
  `clock-mode-colour` + `clock-mode-style 24`, `display-panes-colour` /
  `-active-colour`, `menu-{style,selected-style,border-style}`,
  `popup-{style,border-style}`, `pane-scrollbars-style` (geometry kept:
  `width=1,pad=0`), `cursor-colour`. WCAG ratio beside each pair.
- `default` is retained only where it means *inherit a pinned base* (not
  "terminal decides"): `status-right-style`, `window-status-last-style`,
  `copy-mode-selection-style`/`-position-style` (`#{E:mode-style}`),
  `pane-status-*`/`session-status-*` (unused pane/session status formats).
  Reasoning recorded at the bottom of the theme file.
- loadout1 is NOT touched: it is the pre-2026-10-01 rollback theme, deliberately
  ANSI/stock, with no pane fill of its own.

**Verification.** 21 candidate options probed on a scratch socket against the
bundled tmux 3.7c: zero parse errors (all values resolved to the intended hex).
NOTE for future config work: starting a server with `-f FILE` does NOT report
config errors -- `tmux source-file FILE` does. Negative control (`fg=#zzz`,
bogus option) => `invalid style` / `invalid option`, rc=1; the theme => silent,
rc=0. A pty capture of a real tmux client running the theme emitted exactly two
background codes for the whole session, `48;2;0;0;0` and `48;2;9;9;9` -- both
fills painted, no terminal default anywhere. `tests/install-env-tmux-nvim-layers`
extended with (a) a 27-option file-level pin list (value must be a literal hex)
and (b) live-server checks of both fill values; both were confirmed to fail when
the pin is deleted (deleted-line negative control).

**Deploy note.** On this host the theme was copied into
`~/.config/tmux/themes/` directly; a full `install env-tmux` would also sync it
but would clobber the local `tmux-global.conf` drift (an added
`bind-key 7 ... tmux-3col-layout.sh --left-last` line plus a newer
`tmux-3col-layout.sh` that exists only in the installed tree). That drift is
still un-reconciled.

**Resolved in (3):** the shipped default is now `loadout2`, so the pinning above
is what a fresh install gets; loadout1 is opt-in rollback only.

## 2026-10-12 (1): xfce4-terminal 1.2.0 evaluated -- GUI toolkits are the one inherited distro dependency (knowledge recorded, not pursued)

Follow-up to the RMB-paste question: **1.0.4 already has it** --
`MiscRightClickAction` = `TERMINAL_RIGHT_CLICK_ACTION_CONTEXT_MENU` (default) |
`..._PASTE_CLIPBOARD` | `..._PASTE_SELECTION`, set via Preferences -> Advanced
or `~/.config/xfce4/terminal/terminalrc` (1.1.0+ moved settings to xfconf:
channel `xfce4-terminal`, property `/misc-right-click-action`).

**Can we ship upstream 1.2.0 (tag `xfce4-terminal-1.2.0`, 2026-03-08)? No --
not on the EL8 floor.** Verified against upstream `meson.build` and
libxfce4ui's `configure.ac.in`:

| dep | 1.2.0 needs | EL8 has |
|---|---|---|
| glib | >= 2.44 | 2.56.4 ok |
| gtk+-3.0 | >= 3.22 | 3.22.30 ok |
| vte-2.91 | >= 0.51.3 | 0.52.x (bundled stem) ok |
| libxfce4util | >= 4.16 | 4.16.0 ok |
| libxfconf-0 | >= 4.16 | 4.16.0 ok |
| **libxfce4ui-2** | **>= 4.17.5** | **4.16.0 -- BLOCKED** |

The 4.18 line (what >= 4.17.5 points at; 4.17.5 is its dev snapshot) requires
**GTK >= 3.24, GLib >= 2.66, libxfce4util >= 4.17.2**, and 1.2.0 links
`libxfce4kbd-private-3` (shared shortcuts-editor API added in that cycle) -- so
relaxing version checks cannot work either. EPEL8 cannot ship 4.18 (its GTK is
3.22), so there is no RPM to wait for. 1.2.0 is also bugfix-only (tab-title CPU,
DnD URI escaping), and its xfconf-only settings would not persist without
xfconfd (deliberately unbundled). **Decision: stay on 1.0.4.**

**Generalized gap worth keeping:** binaries are source-built for the EL8 floor
(no lag), but **GUI toolkits are inherited**: `gui_libs` is an EL8-era
GTK 3.22/Qt5 5.15 stack, so any app needing GTK > 3.22 is blocked until a
private newer stack exists.

**Escape-hatch shape (design only, not scheduled):**
1. *Host-first probe*, following the existing GL/fontconfig wrapper blocks:
   wrappers export bundled paths only when the host cannot supply them. For
   GTK, probe the host's `libgtk-3.so.0` for the symbols the newer build needs
   (`readelf --dyn-syms`; GTK symbols are unversioned, so symbol presence is
   the reliable test), run bare when adequate, else point the loader at the
   bundled stack. Same `LOADOUT_GUI_HOST_*` knob shape.
2. *Private newer stack* when needed: per-app co-located (precedent: xschem's
   private Tcl/Tk, marktext's Chromium closure, firefox's NSS/FFmpeg) for one
   app; a shared `gtk324` lib-bundle (GTK 3.24 + GLib 2.66 + libxfce4util 4.17
   + libxfce4ui 4.18) built from source in the EL8 container once several apps
   need it (glibc 2.28 does not care that GTK is new).
3. *Hard rule*: NEVER a second `libgtk-3.so.0` on `<prefix>/lib64` or any
   default loader path -- the modern stack is wrapper-selected or privately
   co-located, like xschem's Tcl.

Trigger: the first must-have GUI app that needs GTK > 3.22.
Already-unblocked precedent: **wezterm** (own GL window stack, not GTK) is the
modern terminal for EL8 nodes today.

**EL9 note (operator):** RHEL EOL pressure moves the fleet onward regardless of
corporate lag; EL9's stack (GTK 3.24 / GLib 2.68) dissolves this specific
class, so a private-EL8-stack project should be judged against the fleet's EL9
timeline -- it may never be worth building for EL8 alone.

