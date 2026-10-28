# Current Handoff

## Archive

Older entries and superseded documents live in `docs/archive/` -- history, not
a sync target:

- `docs/archive/HANDOFF-2026-07-to-09.md` -- handoff entries before 2026-10-01
- `docs/archive/SESSION-HANDOFF-2026-10-02.md` -- the 2026-10-02 session handoff
- `docs/archive/PROPOSAL-2026-10-05-dest-default-and-group-removal.md` -- the
  proposal behind the 2026-10-05 XDG default root and group retirement
- `docs/archive/2026-09-04-enhancement-request-permissions-management.md` -- the
  permissions-management request fielded and implemented 2026-09-04

## 2026-10-27 (4): review plan execution, in progress

Executing the 2026-10-27 code and doc review plan inline, task by task, on
`main` (not pushed). The plan file stays untracked until its security tasks
have all landed. Decisions D-A to D-D took the plan's recommended options.

Landed:
- **Task 1** (SEC-1, SEC-6, ROB-5): the pending-ops dir and the run log are
  private-checked before use (`_secure_private_dir`, `_open_private_append`,
  the daemon's `secure_pending_dir()`); `_tmp_user()` falls back to the uid.
  Gate: `tests/unit-private-state` (T1). The plan's manual two-account check
  (user B pre-creates `/tmp/loadout-pending-<A>` 0777, user A reinstalls with
  a loadout binary running) was NOT run: this session had one account and no
  root. Run it on a farm node with a second account; expected result is in
  docs/SECURITY.md section 9.
- **Task 2** (SEC-2..SEC-5): shells and nvim use per-user runtime dirs under
  `LOADOUT_CFG_SHM_DIR` only when private (`loadout_private_dir`,
  `helpers/private-dir`, `global.paths.private_dir`). Gate: `tests/env-private-dirs` (T2).
- **Task 3** (SEC-7, SEC-8): every payload file a phase installs is verified;
  a missing manifest fails closed. Gate: `tests/content-verify`. Only Tier 1 was
  run for Task 3; the full `tests/run-all` (Tier 2 installs) is still owed.

- Task 3's full `tests/run-all` has since run: all green.
- **Task 4** (SEC-9, DOC-8): the signed tag message now binds
  `sha256sums.txt sha256 <hex>`; `tools/fetch-stash` verifies it
  (`verify_tag_binding`), `--from-file` needs `--tag`, and
  `--allow-unverified-sums` is the HTTPS-only escape. **User-visible until the
  next release ships:** plain `./tools/fetch-stash` refuses, because the latest
  published release's tag binds no sums file -- add `--allow-unverified-sums`.
  Gate: `tests/fetch-stash-trust` (T1).

Next: Task 5 (reinstall/upgrade --dest-dir). Ledger with rulings:
`.superpowers/sdd/2026-10-27-code-and-doc-review/progress.md` (gitignored).
Run `tests/run-all` with the default TMPDIR: a long TMPDIR makes
python-suite-install fail (uv writes a /bin/sh shebang trampoline).

## 2026-10-27 (3): session close -- open items for the next session

**Shipped.** `74ed71f` (node RUNPATH fix, entry (2) below) is pushed to
`origin/main`. It is not in a release yet; the next release carries it.

**Open items, in priority order.**
1. **Deployed shared tree.** `/vols/anvil_release/psg/tools/loadout-shared/latest`
   was installed from `main` between `fb63b2d` and `74ed71f`, so its `bin/node`
   has no RUNPATH. Repair it by reinstalling `nodejs` from current `main`, or
   in place as described in ADDING_BINARIES' Node.js section. It is unconfirmed
   whether this has been done.
2. **Review plan, untracked on purpose.**
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

## 2026-10-11 (1): Python 3.15.0 lands in the payload (W2, UNRELEASED)

`portable-python` is now **3.15.0**, built in the EL8 container exactly like
3.14.7 (clang-23, PGO + full LTO + BOLT) **plus**
`--enable-experimental-jit=yes-off`: the JIT is compiled in, off by default,
enabled per process with `PYTHON_JIT=1` (verified: `sys._jit.is_available()
== True`, `is_enabled() == False`, env toggle True). The import's dynsym gate
reproduced the BOLT bug on the new `libpython3.15.so.1.0` and repaired **2001
entries** (text 1808 / data 181 / rodata 12), re-check clean.

- Payload: `portable-python-3.15.0-el8-clang23.tar.bz2` (26.1 MiB) replaces
the 3.14.7 archive; registry `portable-python` version -> 3.15.0; the removed
archive's installed-sizes entry is gone (6369 artifacts).
- Sweep: every bundled-interpreter reference `python3.14` -> `python3.15`
across 95 files (shim, installer, build/, tests, hooks, current docs). The
`>= 3.14` floor and PEP 758 notes are unchanged: 3.14 stays the minimum, the
bundled interpreter is a runtime choice.
- Sync chain regenerated and green: installed-sizes, README table (version
cells; two hand-owned description rows updated), content-manifest.
- T1 `tests/run-all --fast` green; bootstrap verified (`./loadout -V`
cold-extracts 3.15 into `.loadout-bootstrap/`; the bundled python reports
3.15.0 with JIT available/off).
- Build-side lessons (full record:
`docs/superpowers/specs/2026-10-10-python-315-and-tcl-path-design.md`): the
JIT's unwind-info generator needs `llvm-dwarfdump`, absent from the LLVM 23
toolchain -- built from the LLVM 23 source tree -- and upstream's
`third-party/siphash` header, missing from the trimmed checkout. Staging
placeholder replacements must be EXACT-length: a 16->15 placeholder
corrupted `libzstd.so.1.5.7` ("ELF load command past end of file") and the
old `readelf -d` validation missed it; `repair.sh` now ends with strict
`readelf -lW` validation. `audit.sh`'s `| head` pipes needed `|| true` under
`pipefail` (flaky SIGPIPE 141).

**W3 status (2026-10-11):** the deterministic burn-down is **DONE**.

- 14 same-version cp315 wheels fetched in-container (tag-verified; cp314
  predecessors pruned) -- commit `93446a9`.
- `liberty_tools` + `lefdef_tools` rebuilt as cp315 via
  `build/update --rebuild` (`95eb09f`); `lefdef_tools` needs
  `PYO3_USE_ABI3_FORWARD_COMPATIBILITY=1` (its pinned PyO3 0.27.2 caps at 3.14).
- `lln_libparse` 0.56.0 rebuilt from sdist + manylinux retag (`ed1b933`).
- `build/security_tools.py`: explicit guards so a malformed pin table is
  reported instead of crashing the validator (`fec5087`).

Wheelhouse is now **cp314=29 / cp315=17** (238 total). The 29 remaining
pinned cp314 versions have NO cp315 upstream at the pinned version (upstream
released cp315 only in newer versions), so their refresh is a version-bump
pass with per-tool closure proofs -- deferred to the **3.15.1 checkpoint
(PEP 790: bugfixes every 2 months, ~2026-12-08)**. Also deferred:
`pyosys` (needs a yosys bump; `build/build-yosys.sh` hardcodes `cp314`),
`klayout` (heavy pymod wheel), `duckdb` (pygwalker-only, opt-in).

**W4 (interpreter half) done:** A/B on the bundled 3.15 (`PYTHON_JIT` toggle
verified): startup 8-10 ms and stdlib imports ~230 ms are identical across
modes; a 4e6-iteration pure-Python loop runs ~7% faster with JIT on
(237 vs 254-264 ms); RSS identical (15.7 MB). Decision: **no wrapper sets
`PYTHON_JIT=1` yet** -- the app-level benchmarks (LibreLane smoke, jupyterlab)
need the complete cp315 wheelhouse and run at the checkpoint; a win there
would make it a per-tool wrapper, never a global default. Full table in the
spec.

**Operational note:** after the version sweep, repo scripts with python
shebangs (`build/security_tools.py`, `tests/security-pipeline`, ...) need
python3.15 on PATH. The dev tree still has 3.14 until
`./loadout reinstall portable-python -y` (or prefix
`.loadout-bootstrap/bin`, which T1/`tests/run-all` already does).

## 2026-10-09 (1): `loadout search` GROUPS column -- direct + synthetic membership (UNRELEASED)

Operator request: see which groups contain each search hit. Bounded change
(approved in-session, option b: direct + synthetic).

- `loadout_main.py`: `cmd_search` gains a GROUPS column between VERSION and
  DESCRIPTION, rendered by the same `_list_table` two-elastic-column optimiser
  `list` already uses (GROUPS wraps at commas). Each hit lists the registry
  @groups that name it directly (nested groups included, matching `info`'s
  `groups:` line) plus the synthetic sweeps it belongs to (@shared /
  @shared-all / @envs / @envs-all / @all). Group hits show their parent
  groups; synthetic groups hold leaf packages only, so they never add
  group-on-group entries. `cmd_list`'s inline direct reverse map is factored
  out as `_direct_pkg_groups()`; new `_synthetic_pkg_groups()` expands each
  synthetic group once per invocation.
- New T1 `tests/search-groups` (read-only, no install): pins the GROUPS
  header, vim -> @editor-cli + @shared/@shared-all/@all, env-tmux NOT in
  @shared but in @envs-all, env-bash in @envs, `@editor-cli` -> parent
  `@editor-suite`, a `list` direct-only regression guard, and the unchanged
  no-match path (message + rc 1). Wired into `tests/run-all` T1.
- Docs synced: AGENTS CLI verb + test list, README/INSTALLATION/ARCHITECTURE/
  copilot `search` one-liners, `search` short_help/docstring. Completion
  regenerated-checked: unchanged (no verb/flag change).
- Release class: next release is class C (`loadout_main.py` touched).
  Payload/manifest untouched -- `.content-manifest` roots do not include
  `loadout_main.py`/docs/tests; a regen ran as a no-op and installed-sizes is
  in sync.

Gates: `tests/run-all --fast` green (including the new `search-groups`);
manual `search`/`list`/`--tag` probes; py_compile + ruff check/format.

## 2026-10-08 (14): housekeeping -- stale `codex/…` branch pruned, `--fonts-dir` closed

Small post-release sweep of the loose ends named in entry (13).

- **Git**: `codex/tmux-nvim-two-layer` (`48fecae`, fully merged into
  `origin/main`) and its prunable `/tmp/engineering-loadout-tmux-nvim-layers`
  worktree registration are gone (`git worktree prune` + `git branch -d`).
  `/var/tmp/mk-baseline` (detached `b6e769a`) is left alone as the baseline.
- **`--fonts-dir` / `LOADOUT_FONTS_DIR`: closed, no flag.** The routing covers
  the reported shared-tree case, and a CLI flag is the wrong shape for a
  deployment-wide location -- repeating it per install invites two roots to
  disagree about where the generated `loadout-fonts.conf` lives and which
  `<dir>` it advertises. Manual escape hatch stays `--skip font-*` + a symlink
  (or a caller-set `FONTCONFIG_FILE`). Reopen only on a real
  destination-lifecycle need.
- **`tests/install-linux-tmp-home` stale-prefix follow-up (entry (6)): fixed in
  W6** -- the test unsets a caller's `LOADOUT_CFG_SHARED_PREFIX`, and entry (6)
  now says so.

Still open, unchanged: the release-notes version table defect (RELEASE.md
failure catalogue entry 9, `farm-versions` instead of `packages.json`); a 503
retry path for scrape-style version sources in `check-versions` (`ncdu`); vim
rebuild hygiene -- drop the spurious `libpixman-1.so.0` NEEDED and its registry
declaration (entry (4)).

## 2026-10-08 (13): 2026.10.6 RELEASED and verified (envs cleanup W1-W5)

Class C release cut from `da81ee4` via `docs/RELEASE.md` §0-§9. Signed tag
**2026.10.6** (SSH/ED25519), release published 2026-10-08T20:35Z, four assets:

| asset | size (bytes) |
|---|---|
| `sha256sums.txt` | 525 |
| `default.content-manifest` | 647898 |
| `nvim-plugin-stash.tar.bz2` | 344538464 (= local file) |
| `sbom.cdx.json` | 1340166 |

§9 re-read: `isDraft=false`; `git tag -v` prints `Good "git" signature for
smprather@gmail.com` (ED25519); `origin/main` == `git rev-parse 2026.10.6^{commit}` ==
`da81ee4`; the stash asset's byte size matches the local file.

Shipped (all class C gates green, `tests/run-all --container` included, and
`build/release` pre-release gates green): vim XDG-native config + plugins (W1);
deleted `extra_links` (W2); dead shell entrypoints trimmed with `~/.profile`
restored as the POSIX X-session shim (W3 + correction); deleted the cosmetic
`supports_layers` (W4); documented the `tmux-yank` opt-in (W5). Also in this
release: the agent-facing PEP 758 guardrails and the T1 `ruff format check`.

Carried debt, recorded (outdated but NOT due by cadence): marktext 0.20.0 ->
0.21.1, tree-sitter 0.27.0 -> 0.27.1, tmux 3.7c -> 3.8 (re-check the tmux >= 3.7
FFM guard on any bump), plus the two pinned rows (`less` 704, `pdftotext`
26.04.0). `ncdu`'s version lookup was an upstream 503 during the sweep, so that
row is INCOMPLETE, not clean. ClamAV daily and the YARA ruleset were current.

**Next:** W6 is done and the envs-cleanup spec is fully landed (W1-W6). Open
follow-ups not part of it: the release-notes version table defect (RELEASE.md
failure catalogue entry 9, sourced from `farm-versions` instead of
`packages.json`); the `--fonts-dir`/`LOADOUT_FONTS_DIR` decision; the
`ncdu`-style scrape sources needing a 503 retry path in `check-versions`.

## 2026-10-08 (12): envs cleanup W6 -- class C release 2026.10.6 (W1-W5 + W3 correction) (RELEASE PREP)

Class C per RELEASE.md §0 (installer + registry touched). Sequence followed from §0:

- §1 auth at kickoff: `gh auth` OK; the fixed socket `~/.ssh/loadout-agent.sock` holds
  the ED25519 key, so the signing preflight passed (throwaway tag, no tty).
- §2 currency sweep: `check-versions --outdated-only` + `update --list-outdated` +
  `update --currency`. **Nothing due** -- every cadenced artifact is held (last updates
  1-45 days ago). Behind upstream but NOT due (recorded, not bumped): marktext
  0.20.0 -> 0.21.1, tree-sitter 0.27.0 -> 0.27.1, tmux 3.7c -> 3.8 (re-check the FFM
  >=3.7 guard on any bump), plus the two pinned rows (less 704, pdftotext 26.04.0).
  `ncdu` failed with an upstream 503 twice -- the report is INCOMPLETE for that row.
  `yara-rules` already at 20261004; ClamAV daily.cld is from today.
  tldr-data not re-fetched: 1 day old, cadence-held, and payload repacking belongs in
  the EL8 container per the build mandate.
- §4 post-payload chain: `strip-all-elf-binaries` no-op (0 processed, 830 manifest
  hits); completion untouched (no verb/flag/package-name change); gen-installed-sizes
  then gen-content-manifest regenerated **in that order** and both `--check` prove out.
- §5 docs sync: README table `--check` green; AGENTS/copilot/INSTALLATION/TMUX/HANDOFF
  carry the W1-W5 changes and the W3 correction.
- §6 gates: `tests/run-all --container` green (T1 + T2 + both Tier 3 tests). One real
  finding: `tests/install-linux-tmp-home` inherited a caller's exported
  `LOADOUT_CFG_SHARED_PREFIX`, so a dev shell with a stale value failed its tealdeer
  assertion for the wrong reason -- the test now unsets it (the W3-era follow-up item).
- §7/§8: release prep committed; `build/release --dry-run` green (malware scan CACHED
  CLEAN, vuln-scan CLEAN, secret scan tree+history CLEAN, manifest-export OK, binary
  smoke 348 OK / 1 skipped), derived tag **2026.10.6**.

W1-W5 recap: vim XDG-native (W1), dead `extra_links` deleted (W2), dead shell
entrypoints trimmed with `~/.profile` restored as the POSIX X-session shim (W3 +
correction), cosmetic `supports_layers` deleted (W4), `tmux-yank` opt-in documented (W5).

**Next:** §9 verification results land in the entry above once published (draft=false,
four assets, good signature, released commit on `origin/main`). The new
`tests/env-bash-profile-shim` dash half runs wherever dash exists -- the Tier 3 image
has it, so the class C run covered it.

## 2026-10-08 (11): envs cleanup W5 -- tmux-yank opt-in documented (UNRELEASED)

Per spec D5/F5. The plugin was already vendored and its `@plugin` line already
commented in the managed global layer; the gap was documentation, not dead weight.

- `envs/tmux/tmux-global.conf`: the commented line is now a documented catalog block
  (off-by-default rationale: needs xclip/xsel or wl-copy and a clipboard; offline
  because the copy is vendored; updater-scope note).
- `envs/tmux/tmux-user.conf`: the concrete opt-in block (uncomment one line, reload
  or restart) -- the user layer is the documented place to enable it.
- `docs/TMUX.md`: new "Optional plugins (tmux-yank)" section: what it does, why it is
  off, the offline vendored copy, the enable snippet, and the
  `build/update tmux-plugins` caveat (it discovers declarations in the global layer
  only).
- AGENTS tmux paragraph carries the same one-liner.
- Regen chain: the `envs/tmux` edits feed `gen-installed-sizes`, so
  installed-sizes.json then .content-manifest were regenerated in order.

Gates: `install-env-tmux-nvim-layers` green; the class C suite runs in W6.

**Next:** W6 -- docs sync + class C release.

## 2026-10-08 (10): W3 correction -- ~/.profile is the X-session hook, not dead weight (UNRELEASED)

Operator challenged W3 ("I added them for a reason"). They were right about `~/.profile`:

- EL8 `/etc/X11/xinit/Xsession` is `#!/bin/bash` and line 31 sources
  `/etc/X11/xinit/xinitrc-common`; line 20 there is
  `[ -r $HOME/.profile ] && . $HOME/.profile`. A startx/X11 session therefore sources
  `~/.profile`, and the old `~/.profile -> .config/bash/bashrc` symlink exported the
  loadout PATH/TERMINFO_DIRS/plugin paths into the whole GUI session. EL8 `/bin/sh` is
  bash, so the bash-only target was fine there; it is Debian (dash) where the old link
  died (`Syntax error: "(" unexpected`, rc=2, aborts the caller) -- and Debian's
  Xsession does not source `.profile`, so there it was merely dead.
- `.bash_login` stays retired: bash reads only the first existing of
  .bash_profile/.bash_login/.profile and .bash_profile is always created.

Fix: new `envs/bash/profile`, a POSIX shim that sources the bashrc only when
`$BASH_VERSION` is set and ends with `:` so a guard miss can never fail an `&&` or
`set -e` caller. `install_bash` installs it to `.config/bash/profile` and links
`~/.profile` at it; `_install_env_bash` sweeps live+profile+retired so a legacy
`~/.profile -> bashrc` link is healed; backup/restore lists carry `.profile` again
(live) plus the retired `.bash_login`/`.cshrc`.

- Tests: new T1 `tests/env-bash-profile-shim` (bash applies the env; dash is a clean
  no-op, with a negative control proving the bashrc itself still fails under dash);
  `tests/install-linux-tmp-home` asserts the healed symlink target and that
  `.bash_login`/`.cshrc` are pruned.
- Docs: AGENTS entrypoint list + symlink map, INSTALLATION retirement note, copilot
  layer section, `envs/bash/README.md` file map, spec W3 correction note.

**Next:** W5 (`tmux-yank` opt-in note), then W6 (docs sync + class C release).

## 2026-10-08 (9): envs cleanup W4 -- delete supports_layers (UNRELEASED)

Per spec D4/F4. The field was cosmetic: its only consumers were a comment in
`_install_env_zsh`, one `cmd_describe` field-list entry, registry validation and one
test block -- and its values had already drifted (env-bash omitted global/team, env-tcsh
had none). Layer support is a property of each handler, not registry metadata.

- `payload/packages.json`: the field and its `_schema` description are gone from
  env-bash / env-zsh / env-nvim / env-tmux.
- `loadout_main.py`: dropped from `cmd_describe`'s field tuple and from the
  `_install_env_zsh` docstring.
- `tests/install-env-tmux-nvim-layers`: the registry assertion block is replaced with a
  comment pointing at the dispatcher-order assertions (tmux dispatcher order at
  settings-global -> settings-user -> global -> user -> TPM, plus the nvim layer
  layout), which is the behavior that actually matters.
- Docs: copilot registry field list, AGENTS zsh/shell notes.
- Regen chain: packages.json is manifest-covered, so installed-sizes then
  .content-manifest were regenerated in order.

Gates: T1 `tests/run-all --fast` green; registry-integrity 16/16;
`loadout info env-tmux` no longer prints the field; `install-env-tmux-nvim-layers` and
`install-split-shared-envs` green.

**Next:** W5 (`tmux-yank` opt-in note), then W6 (docs sync + class C release).

## 2026-10-08 (8): envs cleanup W3 -- trim dead shell entrypoints (UNRELEASED)

Per spec D3/F3 (`docs/superpowers/specs/2026-10-08-envs-xdg-and-dead-code-trim-design.md`;
W3 marked LANDED): `.bash_login`/`.profile` were never read -- bash takes the first
existing of `.bash_profile`/`.bash_login`/`.profile` and `.bash_profile` is always
created, and `.profile` additionally linked a bash-only bashrc into POSIX login
shells. `.cshrc` is only read by plain csh, which this project does not support.

- `BASH_ENTRYPOINTS` -> `(".bashrc", ".bash_profile")`; new
  `BASH_ENTRYPOINTS_RETIRED` / `TCSH_ENTRYPOINTS` / `TCSH_ENTRYPOINTS_RETIRED`
  constants make the retired set explicit at every consumer.
- `_install_env_bash` sweeps live + retired entrypoints (install_bash recreates only
  the live two); `_install_env_tcsh` creates `~/.tcshrc` and prunes `~/.cshrc`.
- Safety net: the retired names stay in `backup_existing` for one release (P4; the
  numbered backup runs before the prune). Bug found while wiring it: the tcsh
  entrypoints had never been in the backup list at all -- `~/.tcshrc` was replaced by
  `lns()` with no backup -- so `.tcshrc`/`.cshrc` were added.
- `_restore_backup_dir`: a retired entrypoint is removed before a restore only when
  the snapshot actually contains it (the `.tmux.local.conf` rule) -- a user-owned
  `~/.profile` must not be deleted by a snapshot that never had one.
- Tests: `tests/install-linux-tmp-home` pre-creates the three legacy links and asserts
  all three are gone, and that `.bashrc`/`.bash_profile`/`.tcshrc` are present;
  `tests/install-env-tcsh` pre-creates a legacy `.cshrc` and asserts it is pruned while
  `.tcshrc` still drives a clean interactive shell.
- Docs: INSTALLATION per-user table + retirement note, AGENTS entrypoint list + symlink
  map, copilot layer sections, `envs/bash/README.md`, `envs/tcsh/README.md`,
  `envs/tcsh/tcshrc` header.
- Regen chain: the `envs/*` edits feed `gen-installed-sizes`, so
  `payload/installed-sizes.json` then `.content-manifest` were regenerated in order.

Gates: T1 `tests/run-all --fast` green; `install-linux-tmp-home`, `install-env-tcsh`,
`install-split-shared-envs` green.

**Next:** W4 (`supports_layers`), W5 (`tmux-yank` opt-in note), then W6 (docs sync +
class C release).

## 2026-10-08 (7): PEP 758 guardrails -- the bare `except A, B:` form is canonical here (UNRELEASED)

Operator report: AI agents keep "fixing" the 3.14 `except` syntax -- adding
parentheses, or rewriting the handler around them. Verified semantics (bundled
3.14 + PEP 758 + ruff 0.16.10): `except A, B:` is valid and identical to
`except (A, B):` (Py2's catch-A-bind-B semantics were NOT reintroduced);
parentheses are REQUIRED with `as` (`except (A, B) as e:`; the bare form is
`SyntaxError: multiple exception types must be parenthesized when using 'as'`);
`except A, B if flag else C:` parses as `Tuple([A, IfExp(...)])`;
`ruff format` with `target-version = "py314"` strips the parens and leaves the
`as` form alone.

- `AGENTS.md`: the Cold Start note is now the full contract -- valid forms, the
  `as` rule, "re-adding parentheses is churn", and "a pre-3.14 interpreter or
  analyzer rejects the whole file with the stale message -- never rewrite a
  handler over it". The Gates line names the format gate; copilot-instructions
  and INSTALLATION carry short echoes.
- `tests/run-all`: new T1 `ruff format check` (`ruff format --check
  --force-exclude`, same first-party file set as `ruff check`), so a skipped
  pre-commit format step (ruff off PATH -- what happened in f4ebda9) can no
  longer let non-canonical formatting land. Tree was already clean: 60/60.
- pi-lens ast-grep rule: written, then DROPPED by operator decision. Two
  findings worth keeping: (1) the invalid bare-with-`as` form is not
  structurally matchable -- tree-sitter error-nodes it (pattern
  `except $A, $B as $E:` matches nothing under the napi engine), and
  ruff/pyright/mypy already report it with the exact message; (2) a project
  rule added mid-session is not picked up by the running lens daemon (a fresh
  session is needed to validate firing), and `ast_grep_search`'s rule/nodeKind
  modes shell out to an offline `npx ast-grep`, so they cannot validate a rule
  here. Do not re-litigate without a way to prove firing.
- No payload/shipped-data change: no `installed-sizes.json` / `.content-manifest`
  regen.

Gates: T1 `tests/run-all --fast` green, including the new `ruff format check`.

## 2026-10-08 (6): shared fonts -- install once per tree, never per home (UNRELEASED)

Reported from an Anvil `/vols/...` shared-tree install: `@shared --dest-dir`
wrote all 12 Nerd Font families (~2 GB installed; IosevkaTerm alone 1.09 GB)
into the invoking user's `~/.local/share/fonts` and died with `[Errno 122]
Disk quota exceeded` -- after deleting a symlink the user had pointed at a
shared font directory. Fonts are identical for every user of a tree; the
per-user copy was pure duplication and, on a quota'd account, impossible.

- Routing: `install_fonts(..., shared_root=...)`; the call site passes the
  install root when it lives OUTSIDE the real `$HOME` (the `--dest-dir` /
  multi-user case). Fonts then install once into `<prefix>/share/fonts`, and
  `<prefix>/etc/fonts/loadout-fonts.conf` is generated (re-includes
  `/etc/fonts/fonts.conf`, adds the one `<dir>`). `envs/bash/global/bashrc`,
  `envs/zsh/global/zshrc` and `envs/tcsh/global/tcshrc` export
  `FONTCONFIG_FILE` when that file exists; a caller-set value wins. A root of
  `$HOME` or inside it (default `~/.local/share/loadout`, `dest_dir = "~"`)
  keeps the old per-user behavior.
- Symlink policy: a symlink at the fonts path is RESPECTED (`SKIP` + message)
  unless it is dangling or resolves into the repo checkout. The old
  unconditional `unlink()` is what destroyed the user's sharing mechanism and
  then filled their home.
- `fc-cache` runs on the shared dir at install time (while it is writable), so
  the valid cache lives in the tree and clients never build a per-user cache
  there. A foreign file at the snippet path is warned about and left alone
  (prefer-shim policy).
- Tests: `tests/install-fonts-rejoin` (fast unit test, no payload needed) now
  covers both symlink paths and the shared tree + snippet (9 cases); new T2
  `tests/install-fonts-shared`
  drives the CLI (`font-inconsolata --dest-dir <tree>`), asserts `$HOME` stays
  empty, sources the installed shell entry to prove the `FONTCONFIG_FILE`
  export, and pins that a default HOME-mode install still lands in
  `~/.local/share/fonts`. The new T2 is wired into `tests/run-all` and the
  Tier 3 full smoke entrypoint.
- Regen chain: the `envs/*` rc/README edits feed `gen-installed-sizes`
  (directory sources count their whole tree), so `payload/installed-sizes.json`
  and then `.content-manifest` were regenerated in order.
- Gates: T1 `tests/run-all --fast` PASS; T2 `install-fonts-rejoin`,
  `install-fonts-shared`, `env-routing-dest-dir`, `install-env-tcsh`,
  `install-env-zsh`, `install-split-shared-envs`, `install-linux-tmp-home`
  PASS; Tier 3 `tests/prebuilt-binaries-almalinux8 --full` PASS (326 binaries,
  23 host-contract skips) and it ran the new test inside stock el8.
- Follow-up (pre-existing, not touched): `tests/install-linux-tmp-home`
  inherits a caller's `LOADOUT_CFG_SHARED_PREFIX` (it overrides HOME/XDG but
  not that), so a dev shell whose baked prefix is stale fails its tealdeer
  assertion. It passes with the variable unset and in the container. **FIXED
  in W6** (the class C run hit it; the test now unsets the variable -- entry
  (12)).
- Explicitly NOT done: `--fonts-dir` / `LOADOUT_FONTS_DIR`. The routing covers
  the reported case and a second destination surface needs a lifecycle
  decision; `--skip font-*` plus a symlink remains the manual escape hatch.

## 2026-10-08 (5): envs cleanup -- W2 extra_links removal (UNRELEASED)

Spec: same as (4). **W2 landed** per D2. `extra_links` was inert registry data:
its only consumer was `_install_env_generic`, and every declarer
(`env-bash`/`env-vim`/`env-zsh`/`env-starship`) has a dedicated handler that
hardcodes its links. It also hid W1's dead `~/.vim` link.

- Registry: the field is gone from `env-bash`, `env-zsh`, `env-starship`
  (`env-vim`'s was dropped in W1) and from `_schema`; `tests/registry-integrity`
  enforces `_schema` == fields in use.
- Installer: `_install_env_generic`'s link loop, `cmd_describe`'s field list,
  and `_artifact_paths`' extra_links resolver are deleted. The dedicated
  handlers still create every link they did before -- no behavior change.
- Sizing (D2's consequence): `env-starship`'s `source` is now the directory
  `envs/starship/`, so the directory walk counts `config-schema.json` beside
  `starship.toml`; `_artifact_paths('env-starship')` verified to return
  both files. `gen-installed-sizes` regenerated (map unchanged, 6368
  artifacts), then `.content-manifest`.
- Docs: AGENTS sizing note rewritten (directory sources count their tree),
  copilot field list trimmed.
- Advisory-noise note: pi-lens' pyright runner reports 26 pre-existing
  diagnostics on `loadout_main.py` (rich/rich_click live in `installer_vendor/`,
  which the runner is not configured with; `ty.toml` documents the same class).
  Proven identical at HEAD and dispositioned as false-positives -- no config or
  code suppression added, per repo policy.

**Next:** W3 (dead entrypoints `.bash_login`/`.profile`/`.cshrc`), W4
(`supports_layers`), W5 (`tmux-yank` opt-in note). Each its own commit; class C
at the next release.

## 2026-10-08 (4): envs cleanup -- spec + W1 vim XDG migration (UNRELEASED)

Spec of record: `docs/superpowers/specs/2026-10-08-envs-xdg-and-dead-code-trim-design.md`
(findings F1-F6 from the envs audit, decisions D1-D5, workstreams W1-W6). The
operator closed the three open questions: prefer-vim = yes, drop plain csh =
yes, XDG hook sibling = yes. **W2-W5 are the remaining workstreams; the spec's
checklists are the source of truth.**

**W1 landed and gated.** Vim is XDG-native now:

- `envs/vim/vim/{pack,after}` -> `envs/vim/{pack,after}`; installed to
  `~/.config/vim/{vimrc,pack/vendor,after}`; `~/.vimrc`/`~/.vim` are no longer
  created (pruned on install, kept in the backup list for one release).
- `env-vim` gains `prefer: ["vim"]` (the bundled 9.2 wins on PATH; trade:
  `/usr/bin/vim` 8.0 never sees the config -- inherent to XDG, recorded in the
  spec) and drops its `extra_links` entries (the mechanism itself is W2).
- `envs/vim/vimrc` sources `~/.config/vim/vimrc_hook.bottom` first, the legacy
  `~/.vimrc_hook.bottom` second.
- **The change exposed a pre-existing packaging bug: `install vim` alone
  shipped a broken binary.** `vim.bin` NEEDs `libselinux.so.1`, a payload stem
  claimed only by `gui_libs`, so a vim-only selection skipped it -- dead on
  hosts without a system libselinux (Arch/CachyOS), masked on EL8 BaseOS. It
  also carries a spurious `libpixman-1.so.0` NEEDED (`vim --version` reports
  `-X11`; the loader still requires the soname). Both are now declared in the
  `vim` entry's `libs`. Build-hygiene follow-up: a vim rebuild could drop the
  pixman link and its declaration.
- New T2 test `tests/install-env-vim-xdg`, wired into `tests/run-all` T2 **and**
  the Tier 3 smoke entrypoint: installs `vim` + `env-vim` into a temp HOME and
  probes the bundled vim **through a PTY** (`vim -es` does not read the vimrc --
  a non-PTY probe would pass while proving nothing), asserting `$MYVIMRC`,
  XDG-first `&packpath`, the shipped plugins and after/ftplugin; a stray
  `~/.vimrc` control flips the probe back to legacy mode so the assertions are
  proven able to fail. `tests/install-linux-tmp-home` asserts the XDG layout and
  the absence of the legacy symlinks.
- Gates: focused tests + T1 green; full `tests/run-all --container` green, with
  `install-env-vim-xdg: OK` running inside the Tier 3 container smoke.

**Next:** W2 (delete `extra_links`: 3 remaining declarers + generic loop +
validation + sizes branch; `env-starship` `source` -> `envs/starship/`), then
W3 (dead entrypoints `.bash_login`/`.profile`/`.cshrc`), W4 (`supports_layers`),
W5 (`tmux-yank` opt-in note). Each lands as its own commit; class C at the next
release.

## 2026-10-08 (3): tmux XDG cleanup -- plugin tree + config symlink off legacy paths (RELEASED as 2026.10.5)

Operator call: the extra `~/.config/tmux/tmux/` level and the `~/.tmux` symlink
are legacy compat not worth keeping. The plugin tree now lives at TPM's own XDG
path, `~/.config/tmux/plugins/`; the dispatcher's `run` line and the
`TMUX_PLUGIN_MANAGER_PATH` pin in `tmux-global.conf` both point there (the pin
no longer has to defeat TPM's auto-detection). The installer prunes the nested
`~/.config/tmux/tmux/` tree and stops creating `~/.tmux` and `~/.tmux.conf`;
`.tmux`/`.tmux.conf` stay in the BACKUP list so a first reinstall preserves an
old tree, and env-tmux's `extra_links` key is gone entirely (both entries).

Personal box migrated first: the flat `~/.config/tmux/plugins/` tree was
byte-identical to the nested one, so the nested copy + symlink were removed. An
isolated-server probe with the new config confirms
`TMUX_PLUGIN_MANAGER_PATH=/home/mylesp/.config/tmux/plugins/` and
`@persist-initialized 1`. Snapshots were already XDG data
(`~/.local/share/tmux/resurrect` -- the plugin's fallback, since no
`~/.tmux/persist` existed); docs now say XDG data instead of `~/.tmux/persist`.
The running session keeps the old paths until `Prefix+r` or a server restart.

Tests: `tests/install-env-tmux-nvim-layers` asserts no `~/.tmux`, no nested tree,
TPM at `~/.config/tmux/plugins/tpm/tpm`, and the new pin. Docs synced: AGENTS,
TMUX.md, INSTALLATION, README, copilot-instructions, ARCHITECTURE.

**Stale-PATH trap found while verifying (not caused by the migration).** The
operator's long-running server (started 2026-10-06, PATH ending in the deleted
legacy `~/.loadout/local/bin`) had no `tmux` on the PATH it hands to `run-shell`
children. Every TPM/plugin script shells out to `tmux`, so reload failed with
`'~/.config/tmux/plugins/tpm/tpm' returned 1`. Most plugin scripts mask the
failure (persist ends `return 0`; better-mouse-mode's version check skips its
binds); `tmux-yank` is the one that does not, which is how the missing binary
was confirmed. Fix on the live server:
`tmux set-environment -g PATH "<prefix>/prefer:<prefix>/bin:<old minus legacy>"`
then `Prefix+r`. Verified: TPM rc=0, the `@resurrect-*-script-path` options
repointed at the new plugin tree, and a save round-trip wrote a fresh snapshot
to `~/.local/share/tmux/resurrect`. Diagnostic one-liner:
`tmux run-shell 'command -v tmux'`. A server started from a post-migration
login shell never has this; long-lived panes may still need `exec bash`.

**Also retired: the `~/.tmux.conf` symlink.** tmux >= 3.1 reads
`~/.config/tmux/tmux.conf` natively (probed on 3.7c, including a non-default
`XDG_CONFIG_HOME`), so the installer no longer creates the link and Prefix+r
now sources the XDG dispatcher. Trade recorded: tmux < 3.1 (EL8's system 2.7,
if invoked directly instead of the bundled/preferred 3.7c) would no longer see
the loadout config. Docs synced in the same change (TMUX.md, INSTALLATION,
README, ARCHITECTURE, copilot, AGENTS symlink map).

**RELEASED 2026.10.5 (class C).** Gates: full `tests/run-all --container` green
(T1 + T2 + T3 `--full` + `--dynamic`) -- the first run caught the missed
`~/.tmux.conf` assertion in `tests/install-linux-tmp-home` (the T3 smoke runs
that test inside the container too), fixed as `94d732b` before the second,
green run. `./build/release` passed every gate and published. Section 9
verified: `isDraft=false`; four assets (`sha256sums.txt` 525 B,
`default.content-manifest` 647,898 B, `nvim-plugin-stash.tar.bz2`
344,538,464 B matching local, `sbom.cdx.json` 1,340,180 B); the downloaded
`default.content-manifest` is byte-identical to the local file (e9283b3b...);
`git tag -v` prints a Good ED25519 signature; `origin/main` ==
`2026.10.5^{commit}` (`94d732b`).

## 2026-10-08 (2): class C release prep -- currency + security sweep (RELEASED as 2026.10.4)

Preparing the release on top of the offline-Rust retirement (payload ~3.0 GB,
manifest 4452).

- **nodejs 26.10.0 -> 26.11.1**: `build/import-nodejs /tmp/node-v26.11.1-linux-x64`,
  in-container, from the official tarball sha256-verified against nodejs.org's
  `SHASUMS256.txt`; the importer's GLIBC_2.28 audit passed. nvm is NOT needed for
  a targeted bump -- the importer takes a prefix dir -- but a bare
  `./build/update nodejs` still wants nvm (dev tool, not installed here).
- **tldr-data refreshed** (984,862 -> 985,198 B canonical; 7569 members).
- **yara-rules** already current (20261004, digest verified); **ClamAV** DB
  2026-10-07 (`freshclam` is log-locked by the running daemon -- benign, seen
  before).
- `check-versions`: the only remaining outdated entries are `less` and
  `pdftotext` (deliberately pinned) and `ncdu`, whose upstream lookup still
  503s -- an INCOMPLETE report, not a clean bill. No Rust tool is outdated.

- **Tier 3 harness fixes found by the full `--container` run** (the `--full`
  smoke never exercises these paths):
  - `build/docker/almalinux8.10-smoke-entrypoint` hardcoded the dynamic smoke's
    `--bindir /work/dyn/local/bin`; since the 2026-10-05 XDG re-architecture a
    non-`$HOME` `--dest-dir` is a plain prefix, so nvim lands at `/work/dyn/bin`.
    Fixed (`3f1796b`) and verified standalone (`--dynamic`: 10 passed, 0 failed).
  - `tests/run-all`'s container cache key did not include the smoke harness
    (`build/docker/*`), so a stale pre-XDG `.pass` blessed the broken test as
    CACHED PASS right after it had failed. Container tests now use
    `FP_ROOTS_CONTAINER` (`578ffc7`); all-mode caching is unchanged.

- **vuln-scan `--no-resolve` (release-blocking find).** The first dry-run
  aborted at Step 5: osv-scanner 2.6.0's transitive resolver hard-fails on
  `lefdef-tools` ("package System(7):lefdef-tools: not found", exit 127) -- a
  first-party wheel that will never be on PyPI. The same scanner and wheelhouse
  passed earlier runs, so the resolver's external lookups make that path
  non-deterministic; the wheelhouse listing is already the complete dependency
  closure, so transitive resolution adds nothing and is now disabled. CLEAN:
  215 wheels, 0 advisories.

Gates: full `tests/run-all --container` green afterwards -- T1 + T2 + T3
`--full` + `--dynamic`, 22m52s fresh, both T3 tests genuinely re-run. Assurance
re-pin is NOT owed (none of nvim/rust/treesitter/git-nvim was bumped). Next:
`./build/release` -> 2026.10.4.

**RELEASED 2026.10.4 (class C).** Gates: fresh `tests/run-all --container`
green (T1 + T2 + T3 `--full` + `--dynamic`), then a release dry-run that first
caught the two T3-harness issues and the vuln-scan resolver problem above -- all
fixed before publishing. Section 9 verified: `isDraft=false`; four assets
(`sha256sums.txt` 525 B, `default.content-manifest` 647,898 B,
`nvim-plugin-stash.tar.bz2` 344,538,464 B matching local, `sbom.cdx.json`
1,340,125 B); the downloaded `default.content-manifest` is byte-identical to
the local file (a5601d5d...); `git tag -v` prints a Good ED25519 signature;
`origin/main` == `2026.10.4^{commit}` (`46246f9`).

## 2026-10-08: offline-Rust subsystem retired -- uv unpinned and bumped (in 2026.10.4)

**Decision (operator):** offline `cargo build` on farm nodes was aspirational.
The crate store + its wiring are gone; the shipped Rust **toolchain** (`rust`
runtime) and every prebuilt Rust **tool** stay, and build-host cargo for
fish/tokei/numr/models/surfer + first-party maturin wheels was never the store.

**Removed** (payload 3.3 GB -> 3.0 GB):
- `payload/crate-store/` (10 parts, 364 MB), registry `rust-crate-store` +
  `env-cargo` + `@rust`, and the installer's crate-store phase / env-cargo
  handler / hardcoded gate.
- Shell: bash `cargo()` wrapper + `loadout_net_probe` +
  `LOADOUT_CFG_CARGO_PROBE_HOSTS`/`LOADOUT_NET_PROBE_TTL`; tcsh `helpers/cargo-wrap`
  + alias/config wiring.
- Build: `build-crate-store.sh`, `build-tool-crate-store.sh`,
  `verify-crate-store`, `rust-crate-list.txt`, `rust-tool-locks.txt`,
  `docker/almalinux8.10-rust.{Dockerfile,entrypoint}`; the crate-store inputs in
  `sbom` / `vuln-scan` (which lost `--strict-rust`) / `scan-for-malware`;
  `enhancement-request-cargo-offline-fallback.md`.
- Tests: `cargo-offline-fallback` + `rust-offline-almalinux8` (T1/T3 entries);
  the rust-lock cases in `security-pipeline`; `crate-store.lock`,
  `crate-store-tools.tsv`, `records/crate-store.toml`. Kept: `records/rust.toml`.

**Kept:** `rust` 1.96.0 runtime (5 chunks, NOSTRIP), `build/build-rust.sh`, all
Rust tools. `./loadout install rust` now installs a toolchain with no bundled
registry -- bring your own dependency source (network, `cargo vendor`, mirror).

**Bumped/unpinned:** uv 0.12.17 -> 0.12.23, then the rest of the pinned quartet --
ty 0.0.82 -> 0.0.85, delta 0.19.2 -> 0.20.1, hyperfine 1.20.0 -> 2.0.0 (commit
`2c7e672`); all via in-container `build/update-prebuilt`. No Rust tool remains
outdated (`check-versions`). Also bumped vim + gvim 9.2.1169 -> 9.2.1172
(`build/build-vim.sh --tag v9.2.1172`, in-container; the vim92 runtime archive
came out byte-identical -- nothing in the runtime changed between patches -- so
only the two bins changed). `build/update-prebuilt` now resolves patchelf via
`LOADOUT_PATCHELF` -> PATH -> legacy `~/.local/bin` (the XDG migration moved it)
and fails clearly when missing.

**Verified:** registry/completion/README regenerated (stale `rust-crate-store`
README row removed by hand -- the generator only warns); `content-manifest` OK
(4620 -> 4452 across both changes), `installed-sizes` OK (6368), README table OK,
strip pass clean. T1 focused: registry-integrity, security-pipeline,
assurance-check, content-verify, update-cadence, check-installer PASS; full
`tests/run-all` T1+T2 green. T2 focused: `install-linux-tmp-home` (@shared-all
@envs-all; with the stale `LOADOUT_CFG_SHARED_PREFIX` unset) and `uv-launchers`
PASS. `tests/prebuilt-binaries` on the bumped payload: All 348 binaries OK
(1 skipped), runtimes OK. `ty` advisory unchanged (7 diagnostics before/after;
the stale "11" note in ty.toml corrected).

**Release implication:** registry + installer change => the next release is
class C (Tier 3 + currency sweep required).

## 2026-10-07 (2): .content-manifest shipped-set fix -- the export blocker (RELEASED as 2026.10.3)

**The defect.** The committed `.content-manifest` in 2026.10.2 listed 158 files
under `envs/tmux/vendor/plugins/tmux-persist/{.agents,.codex,.claude}`. Those
files existed on this host (the vendored tree was cloned here) but are
gitignored and untracked, so they are not in the commit. `gen-content-manifest`
walked the filesystem; `--check` therefore passed here and every clean clone or
`git archive` export failed with 158 MISSING entries, and PSG's
`deploy-loadout` wrapper (`./build/export ...`) refused to publish. A signed tag
does not catch this: the tag signs the commit, and the commit's manifest named
files the commit does not contain. (The `.content-manifest` asset itself was
also wrong -- it is the same file `sha256sums.txt` pins.)

**One shipped-set rule, three layers.**

- `build/gen-content-manifest` now skips untracked+ignored files
  (`git ls-files -o -i --exclude-standard`: any-depth `.gitignore`,
  `.git/info/exclude`, `core.excludesFile`). Tracked-but-ignored files
  (`git add -f`) and untracked-not-ignored files stay covered, because both are
  part of the documented payload chain (build -> copy -> gen -> `git add`);
  symlinks are still skipped. `--check` now reports a manifest entry that is
  present on the host but not shipped as `NOT-SHIPPED`, so the generating host
  can no longer false-green. A git checkout that cannot be queried is a hard
  error, not a silent fallback to the unfiltered walk; the git call carries
  `-c safe.directory=REPO`, so a foreign-owned bind mount (the EL8 build
  container running as root) still filters instead of failing.
- `build/verify-manifest-export` (NEW) reads `HEAD:.content-manifest` and
  streams `git archive HEAD` through a tar reader, requiring every manifest
  entry to be an exported regular file with a matching sha256, and every
  exported regular file under the manifest roots to be listed. Symlinks are
  skipped. The stash exception is untouched: the stash is untracked, so it is
  on neither side, and its `sha256sums.txt` -> `.content-manifest.fetched`
  chain is unchanged.
- Wiring: Tier 1 `content-manifest matches export` (uncached -- `test_script`
  resolves to nothing, so no cache can stand on stale HEAD), `build/export`
  preflight (prints `manifest : ...`, refuses with the drift list),
  `build/release` Step 3b (uncached, mandatory). `tests/run-all`'s
  `FP_ROOTS` now includes both scripts so the cached shipped-set regression
  test cannot stand on stale tooling. `tests/content-manifest-shipped-set`
  (NEW, T1) pins the ignored-vendored-file class in a synthetic repo with RED
  controls: host NOT-SHIPPED, clean-export MISSING, gate MISSING-FROM-EXPORT,
  and a manifest whose hash matches a dirty tree rather than HEAD.

**Manifest regenerated wholesale: 4620 -> 4462 entries, exactly the 158
ignored-untracked deletions** (no other line changed; the 29 ignored-untracked
`.claude/skills/*` symlinks were never in the manifest).

**Verified.** RED before the fix: new `--check` = 158 `NOT-SHIPPED`; the gate =
158 `MISSING-FROM-EXPORT`; `build/export`'s new preflight returns False with
that list (tested in-process -- the real command refuses at `check_clean_tree`
while the fix is uncommitted). GREEN after regeneration + commit: `--check` OK
(4462); gate OK; synthetic regression test all PASS; `tests/run-all --fast`
green. Full T1+T2 green except `install-linux-tmp-home`, which fails only
because this session inherited the stale pre-XDG
`LOADOUT_CFG_SHARED_PREFIX=/home/mylesp/.loadout/local` (test-harness env leak:
the test overrides HOME/XDG but inherits the rest) and passes under
`env -u LOADOUT_CFG_SHARED_PREFIX` -- same stale-session class as the PATH note
above.

**End-to-end export proof (the blocked PSG path).** `./build/export <dir>` now
runs clean: `manifest : verify-manifest-export: OK (4462 files match
.content-manifest at HEAD)`, `payload : content-manifest verified: 4463 files`,
stash copied + re-verified. `./loadout doctor --verify` inside the exported
git-less tree: `content-manifest verified: 4463 files match`, rc=0. Container
path exercised too: as root on the foreign-owned bind mount, plain git fails
"dubious ownership" while the fixed generator reports OK (4462). Class A change
(no payload bytes -- manifest metadata + export-ignored tooling), so Tier 3 was
not required.

**RELEASED 2026.10.3 (class A).** Bumped rather than overwriting 2026.10.2:
that release was section-9-verified and trusted, and an overwritten tag is
invisible to offline consumers (`-V` unchanged) -- policy in docs/RELEASE.md
section 8. `./build/release` ran the standard gates plus the new Step 3b
(`verify-manifest-export: OK (4462 files match .content-manifest at HEAD)`),
pushed `main` (5cad458 -> 00dd80b), signed the tag, and published. Section 9
verified: `isDraft=false`; four assets present (`sha256sums.txt`,
`default.content-manifest` 649,128 B, `nvim-plugin-stash.tar.bz2` 344,538,464 B
-- bytes unchanged, `sbom.cdx.json`); the downloaded
`default.content-manifest` asset is byte-identical to the working-tree file
(fe8e55ae...); `git tag -v` prints a Good ED25519 signature; `origin/main` ==
`2026.10.3^{commit}` (`00dd80b`).

## 2026-10-07: uv/uvx launchers + xfce4-terminal (release 2026.10.2)

**uv/uvx.** `uv` was already a package but bare upstream: no `uvx`, and
`uv venv` / `uv tool install` / `uv run` created environments with whatever
interpreter uv discovered. Now `bin/uv` (POSIX-sh launcher) + `bin/uv.bin`
(official 0.12.17 release binary) + `bin/uvx` (-> `uv tool run`), built by
`./build/update-prebuilt uv=0.12.17` from `build/uv-launcher.sh` /
`build/uvx-launcher.sh` (LAUNCHERS table, output stem `uv.bin`), so a bump is
one command. Pin semantics are measured, not assumed: `UV_PYTHON` is set to
`<prefix>/bin/python3` for `uv venv` / `uv tool install` / `uv run`, but NOT
for `uv pip` -- on 0.12.17 `UV_PYTHON` outranks `VIRTUAL_ENV`, so a pinned
`uv pip install` inside an activated venv would install into the managed
Python instead of the venv. Without the pin, uv's native target discovery
refuses a bare install and honors the venv / `--python` / `--system`; an
explicit `--python` or caller-set `UV_PYTHON` always wins. `tests/uv-launchers`
(T2, network blackholed) gates all of it. `uvx --version` is special-cased to
uv's version (`uv tool run --version` errors upstream). `uv self update` may
replace `uv.bin` in place -- accepted (an explicit user action; the wrapper
keeps working).

**xfce4-terminal 1.0.4** (EPEL8 shanghai repack, `build/build-xfce4-terminal.sh`):
`bin/xfce4-terminal` launcher (gui + gtk3 shared blocks) +
`bin/xfce4-terminal.bin`, four bundled lib stems (`libxfce4ui-2.so.0`,
`libxfce4util.so.7`, `libxfconf-0.so.3`, `libstartup-notification-1.so.0`) plus
the `libvte-2.91.so.0` stem shared with mate-terminal (declared in both
entries). `libstartup-notification-1` is a NEEDED of our bundled libxfce4ui and
is absent from stock almalinux:8.10 -> bundled (the Xephyr/libfontenc class;
the build's closure guard walks every shipped ELF for this reason). Measured:
starts, maps a window and opens Preferences with NO session bus and no xfconfd;
preferences simply do not persist, so xfconfd is deliberately not bundled.
Member of @gui-suite; build notes in build/ADDING_BINARIES.md.

**Gates:** T1+T2 `tests/run-all` green; Tier 3
`tests/prebuilt-binaries-almalinux8 --full` (--network=none) green -- 326
binaries OK, runtimes OK. Dev-host gotcha, recorded because it bit this
session: a shell started before the XDG migration still had the OLD
`~/.loadout/local/bin` on PATH (now deleted), so `ruff`/`tmux` lookups failed
and `tests/run-all` reported three false failures. Prefix
`~/.local/share/loadout/bin` to PATH on a migrated box -- a fresh login shell
gets it via appended PATH; a long-lived tool session predating the migration
does not.

**Released 2026-10-07 as `2026.10.2`** -- branch pushed before tag, ED25519
signed tag verified, all four assets present (sha256sums.txt,
default.content-manifest 674914 B matching local, nvim-plugin-stash.tar.bz2
344538464 B matching local, sbom.cdx.json), `git ls-remote origin
refs/heads/main` == `git rev-parse 2026.10.2^{commit}`.

## 2026-10-06 (post-2026.10.1): tmux focus-follows-mouse preference

`focus-follows-mouse` is now a layered tmux preference: the managed baseline
sets it **off** (guarded with `%if "#{>=:#{version},3.7}"` -- the option landed
in tmux 3.7, the bundle is 3.7c), the seeded `tmux-settings-user.conf` carries
a commented opt-in, and `tests/install-env-tmux-nvim-layers` asserts both the
defaults and a real-server override (managed off -> user layer on).
`docs/TMUX.md` documents it. The operator's live user layer enables it.

Last updated: 2026-10-08 (**released 2026.10.5**; in flight: the envs cleanup
spec + W1 vim XDG migration -- W2-W5 pending, spec is the checklist).
Previous: 2026.10.5 (class C: tmux XDG cleanup; section-9 verified).
Previous: 2026.10.4 (offline-Rust retirement, uv/ty/delta/hyperfine/vim/gvim/
nodejs sweep, T3 harness + vuln-scan fixes; section-9 verified).
Previous: 2026.10.3 (`.content-manifest` shipped-set fix + clean-export gate,
class A; section-9 verified: signed tag, 4 assets, origin/main == tag).
2026.10.2 (uv/uvx launchers + xfce4-terminal; verified 2026-10-07).
Prior releases: 2026.10.1 (October currency sweep on top of the XDG
re-architecture), `v2026.09.23` RELEASED + verified
(release commit `032c1d0`). Committed since v2026.09.18: `b6e769a` (librelane
end-to-end, btop themes, nethogs, xclip), `032c1d0` (marktext + fused-line
launcher fix + gate fixes), the three 2026-09-24 gates (versioning scheme,
scanner de-productification, security pipeline), the 2026-09-25 security wheel
refresh, and the 2026-09-27 xschem onboarding.

## 2026-10-06: October currency sweep (released as 2026.10.1)

Class C release prep on top of the XDG re-architecture. `build/check-versions`
started at ~23 outdated; after the sweep:

Bumped (16): nodejs 26.9.0 -> 26.10.0, vim + gvim 9.2.1119 -> 9.2.1169, rsync
3.5.0 -> 3.5.1, fio 3.42 -> 3.43, typescript-language-server 6.0.0 -> 6.0.1,
marktext 0.19.1 -> 0.20.0, librelane 3.0.14 -> 3.0.16, ruff 0.16.8 -> 0.16.10,
miller 6.21.0 -> 6.22.0, lazygit 0.65.1 -> 0.66.0, yq 4.53.6 -> 4.54.1, broot
1.60.1 -> 1.61.0, biome 2.5.14 -> 2.5.15, fresh 0.5.1 -> 0.5.2. Security data:
yara-rules 20261004, tldr-data refreshed (1.0 MB archive). Pinned by design:
less, pdftotext (pre-existing reasons).

**Pinned in THIS sweep (4) -- crate-store coupling, not upstream choice:** uv,
ty, delta, hyperfine carry `pin_reason`: the EL8 build image cannot rebuild the
crate store because `cargo-local-registry` (latest and 0.2.7 both tried) fails
to compile -- its dependency chain pulls a curl-sys that requires OpenSSL 3
`OPENSSL_VERSION_STRING`, EL8 ships OpenSSL 1.1.1 headers. The image also could
not be rebuilt during this sweep (ftp.gnu.org unreachable at the autoconf
layer), so the follow-up is to bake EPEL `openssl3-devel` (3.5.5 available) plus
a working cargo-local-registry (or move the sync off cargo). Until then,
bumping any of the four flips `tests/run-all`'s crate-store policy red, by
design.

Build-tooling fixes riding along:

- `build/Dockerfile`: `libatomic` baked (node stage-smokes run the bundled
  Node; it NEEDs libatomic.so.1, a host contract EL8 BaseOS supplies).
- `build/build-marktext.sh`: tarball sha256 pinned PER VERSION from the GitHub
  release asset digest; an unknown version now fails instead of silently
  reusing 0.19.1's hash (the first 0.20.0 attempt hit exactly that).
- `build/build-simple-c.sh`: stamp the registry without a leading `v` (rsync
  stamped `v3.5.1` against the registry's `3.5.1` convention).
- `build/update-prebuilt`: delta + hyperfine musl entries added (ready for the
  day the crate-store block lifts).
- librelane 3.0.16: wheelhouse gained its wheel; the closure kept the LOCALLY
  BUILT `lln_libparse-0.56.0-cp314` wheel -- upstream publishes no cp314 wheel
  at all, so that artifact's provenance is a local EL8 build. Offline install
  proved with `--network=none` plus launcher exec.

False positives / incomplete lookups: lefdef-tools + time-plot `--outdated` is
a format artifact -- the GitHub "latest" SHA IS the tag commit (`git describe`
== registry version; the updater correctly skips). bash, octave and ncdu
upstream lookups failed (unreachable / 503), so those results are incomplete,
not a clean bill; none is known-outdated.

Gates: T1+T2 `tests/run-all` 48/48; Tier 3
`tests/prebuilt-binaries-almalinux8 --full` green (322 binaries, 23 skipped,
runtimes OK). ClamAV DB current (1.5.4/28145, 2026-10-06) -- no
`sudo freshclam` needed before the malware scan. Next: `./build/release`.

Security refresh after the first gate run: `build/vuln-scan` flagged two
unbaselined WHEELHOUSE advisories (urllib3 2.7.0, multidict 6.7.1 -- both
pre-existing wheels, not from this sweep). Refreshed to urllib3 2.8.0 and
multidict 6.9.1 (aiohttp requires multidict<7.0), pruned the superseded
wheels, and proved preservation before/after with a per-tool offline `uv pip
compile` (only the two intended version changes appeared; nothing regressed)
plus end-to-end network-disabled installs of jupyterlab (jupyter-lab 4.6.4)
and parity-plot. `build/vuln-scan` is now CLEAN with 0 baseline entries. The
same proof surfaced PRE-EXISTING incomplete closures: cicwave (pyqt6-qt6
absent), liberty-tools and pygwalker do not resolve offline against the
wheelhouse -- unchanged by the refresh, recorded here as debt.

Dev-host scratch: full T2 runs and the release gates now need disk-backed
scratch (`TMPDIR=/var/tmp/...`). The 16 GB `/tmp` tmpfs filled during the
aborted dry-run (the malware scan alone extracted ~12 GB) and produced seven
false ENOSPC test failures; after cleaning, T2 + Tier 3 re-ran green.

**RELEASED 2026.10.1** (signed tag, commit 7b214fa, 2026-10-06). Gates green:
T1+T2 48/48, Tier 3 `--full` (322 binaries / 23 skipped), and every release
gate (malware scan, binary smoke, version table, checksums + SBOM, secret
scan, vulnerability scan). §9 verified: `isDraft=false`, four assets
(`sha256sums.txt`, `default.content-manifest`, `nvim-plugin-stash.tar.bz2`
344,538,464 bytes matching local, `sbom.cdx.json`), `git tag -v` prints Good
signature, and `origin/main` equals the tag commit.

## 2026-10-05: XDG default root, group retirement, prefer shims (COMMITTED dabaadf..46ecdea, UNRELEASED)

Behavioral re-architecture that stops the loadout silently shadowing system
binaries, and lands the preconditions for a future uninstall. Spec
`docs/superpowers/specs/2026-10-05-dest-default-and-group-removal-design.md`,
plan `docs/superpowers/plans/2026-10-05-dest-default-and-group-removal.md`.

What landed:

- **Default install root** is `$XDG_DATA_HOME/loadout` (fallback
  `~/.local/share/loadout`). Resolution: explicit `--dest-dir` > `config.toml`
  `dest_dir` > XDG default; `dest_dir = "~"` restores the legacy `$HOME/.local`
  layout. (`69af0a2`)
- **Prefix layout + two-root routing**: the shared tree is a plain prefix for
  any non-`$HOME` root (`_local_root`), so `<root>/local/` is gone; config,
  cache and per-user nvim data always resolve under the real `$HOME`. A mixed
  selection never drags config into a dest tree; env-only + explicit
  `--dest-dir` stages a whole HOME (tests/previews); env-only + config
  `dest_dir` ignores it with a printed note. Snapshot targets the real `$HOME`
  unless `--dest-dir` was typed on the command line. (`dabaadf`)
- **`prefer/` mechanism**: registry `prefer` field (env-tmux → tmux) +
  `config.toml` `prefer`/`prefer_off`; `install_prefer_shims()` writes
  marker-carrying exec shims under `<prefix>/prefer/<tool>`, prunes only its
  own, warns on foreign files and missing targets. (`0e5bb2a`, `bf354c7`)
- **`@engineering-loadout` retired**: `_RETIRED_GROUPS` raises a loud resolver
  error naming `@shared-all` then `@envs-all` (superset, 177 vs 167 names);
  completions regenerated. (`d74de05`)
- **`doctor` layout audit**: read-only "Install layout" section -- root + mode,
  legacy `~/.local/bin` EL-managed names, names ahead of system dirs on PATH,
  prefer shims with missing targets; exit status unchanged. (`bc85bfb`)
- **Shell PATH**: `<prefix>/bin` appended (system copies keep priority),
  `<prefix>/prefer` prepended last, fallback
  `${LOADOUT_CFG_SHARED_PREFIX:-$HOME/.local/share/loadout}` in bash/zsh/tcsh;
  `LOADOUT_CFG_SHARED_PREFIX` now baked unconditionally by split env installs
  (`_local_root(install_root)`). (`a6cb682`)

Tests: new gates `dest-layout-and-env-routing`, `env-routing-dest-dir`,
`prefer-shims`, `doctor-shadow-audit` (plus updated `config-toml-dest-dir`,
`registry-integrity`, `unit-resolver`, `check-installer`, `env-shell-parity`,
`install-linux-tmp-home`, `install-split-shared-envs`, `install-nvim-deployments`).
Run green: T1 + **full T2** (`tests/run-all`); **Tier 3**
`tests/prebuilt-binaries-almalinux8 --full` (network disabled): 322 binaries OK,
23 skipped, runtimes OK. Tier 3 caught one test-harness bug the host missed: the
tmp-home hook2 resolved its python via a test-scope `$prefix` (undefined in the
hook); CachyOS has `/bin/python3.14` so the host passed, EL8 does not. Fixed to
use `LOADOUT_DEST_DIR` from the hook environment.

Pending:

- Class C release per `docs/RELEASE.md` (currency sweep, assurance re-pin,
  post-payload chain, tag, publish, post-publish verification).
- Docs synced in this change: README, `docs/INSTALLATION.md` (new migration
  section), `docs/ARCHITECTURE.md`, AGENTS, copilot-instructions,
  `envs/bash/global/README.md`, `envs/nvim/lua/global/paths.lua` comment.
- **Uninstall remains a future spec** (this change lands its preconditions:
  dedicated root, config separation, doctor footprint reporting).
- Known gap: the GUI session `PATH` does not include the install root; systemd
  `DefaultEnvironment` cannot override it, so session-wide changes need
  `/etc/environment` via `pam_env`.

## 2026-10-04: tmux env synced to the live golden tree, loadout1 default (uncommitted)

The live `~/.config/tmux` had diverged from what the installer manages (hyphen
names live vs dotted names in repo; settings + theme layering lived only in
the live tree). Per the user's call -- live is golden, except the shipped
default theme is loadout1 -- the repo now mirrors the live tree byte-for-byte
with one deliberate difference: both shipped settings layers select `loadout1`
(live's global baseline already did; live's user layer says `loadout2`).

Layout change (repo `envs/tmux/`): `tmux.global.conf` -> `tmux-global.conf`,
`tmux.user.conf` -> `tmux-user.conf`, helpers into `scripts/` (including the
bash *generator* `scripts/tmux-word-separators`, which replaces the old Python
run-shell script), new `tmux-settings-global.conf` +
`tmux-settings-user.conf` (seed), new `word-separators.conf` (committed
generated output, 3812 chars), new `themes/tmux-theme-loadout{1,2}.conf`
(hyphen names; byte-identical to live apart from two comment lines whose
filenames were fixed to the new names). Dispatcher drops `-q` and the legacy
`~/.tmux.local.conf` fallback (live policy: missing files fail loud; the file
is no longer loaded). Installer: managed settings-global/themes/word-separators,
seed-if-absent settings-user, dotted `tmux.user.conf` migrated forward,
superseded top-level managed files pruned. `build/update tmux-plugins` follows
the rename. `tests/install-env-tmux-nvim-layers` covers dispatcher order
(settings-global -> settings-user -> global -> user -> TPM), the loadout1
defaults, settings preservation, dotted migration, and pruning;
`tests/install-linux-tmp-home` asserts the new tree.

Verified: isolated-server smoke (`@theme` = loadout1, prefix, theme values,
3812-char separators, reload OK, server killed by PID, live untouched);
`install-env-tmux-nvim-layers` OK; `install-linux-tmp-home` OK;
`run-all --fast` green; sizes (6362 artifacts) + manifest (4611 files)
regenerated, README table OK.

Two notes for the operator: (1) the live `tmux-settings-user.conf` still says
`loadout2` and is preserved on reinstall, so the running session stays on
loadout2 until that file is flipped by hand; (2) the next `env-tmux` install
refreshes the live theme files' header comments to the fixed filenames.
