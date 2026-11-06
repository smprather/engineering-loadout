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

## 2026-11-06 (8): persistent package exclusions

`config.toml` carries an `exclude` list (`LOADOUT_CFG_EXCLUDE` is the
environment form) that `install` / `reinstall` / `upgrade` / `resolve` /
`--dry-run` subtract exactly like `--skip`, which it unions with. Tokens are
package names, `@groups` or globs; a directly named excluded package fails with
an error naming the key, a group/glob sweep drops it with one
`note: excluded by policy` line, and excluding a hard dependency of a selected
package keeps the existing dependency error (`--force` / `--no-deps`). Removing
the entry is the only override. `doctor` prints an `Exclusions` section and
flags any declared binary a previous install left in `<prefix>/bin` (the policy
stops future installs, it never uninstalls). Design:
`docs/superpowers/specs/2026-11-06-persistent-package-exclusion-design.md`;
plan: `docs/superpowers/plans/2026-11-06-persistent-package-exclusion.md`.
Issue `smprather/engineering-loadout#13`.

**Class C** (any `loadout_main.py` change; no payload, registry or schema
change). Commits `000ccc5` resolver policy + `tests/config-toml-exclude` (T1),
`d8d2672` fail on a directly demanded excluded package, `ce090a3` CLI wiring
and the single-note `--dry-run`, `060d8b0` `tests/install-exclude-policy`
(T2), `084bfbf` the doctor section; this entry's docs commit updates
`README.md`, `docs/INSTALLATION.md` and `AGENTS.md`. A review fix on top
forwards a bare `all` policy token to `expand_groups()` so it raises its
"bare 'all' is not a group" error instead of being warned away as an unknown
name -- expansion errors in the policy are never swallowed (spec D3) -- pinned
by `tests/config-toml-exclude` case 10b.

**Gates run** (dev host, 2026-11-06, HEAD `084bfbf` plus the docs commit and
its review fix):

- `tests/docs-sync`: 9 passed, 0 failed (~1 s).
- `tests/run-all --fast` (T1, after the fix): `Tier 1 passed.`, 54/54 PASS,
  181 s (18:36:30-18:39:30Z, `skipped=0`; slowest `payload-interpreter-abi`
  73 s, `config-toml-exclude` 4 s). Its rows are the last 55-row block in
  `assurance/release-timings.tsv`, ending `test:total 181 PASS
  flags=--fast skipped=0`.
- `tests/config-toml-exclude`: 47/47 checks PASS, ~3.7 s (includes the
  bare-`all` case).
- `tests/unit-resolver`: 98 passed, 0 failed.
- `tests/install-exclude-policy` (T2): PASS, <1 s (`Install exclude policy
  OK`).
- Real-surface smoke, throwaway `HOME`, `exclude = ["gnuplot"]` (1.3 s total):
  `./loadout resolve @shared-all` -> exit 0, `Resolved 161 packages`, no
  `gnuplot`, `note: excluded by policy (config.toml exclude): gnuplot` on
  stderr; `./loadout resolve gnuplot` -> exit 1,
  `package(s) excluded by the persistent policy` naming the source; `./loadout
  doctor` -> exit 0, `Exclusions (config.toml exclude):` with
  `gnuplot: excluded by policy`, no traceback. With `exclude = ["all"]` instead,
  `./loadout resolve @shared` -> exit 1 and the bare-`all` group error (151 ms),
  no install.

**Not run:** Tier 2 beyond `install-exclude-policy` (the other integration
tests install into temp roots), Tier 3 (`tests/run-all --container`) and
`build/release`. Class C makes Tier 3 required before the next release, so that
release block must run it.

## 2026-11-06 (7): payload ABI gate caches findings and scans in parallel

Class A (test only). `tests/payload-interpreter-abi` decompressed ~3 GB and
spawned `readelf` once per ELF on every payload/loader/build edit -- 71 s, and
a one-line registry edit counted as a payload edit.

- Findings (ELF `DT_NEEDED`, shebang interpreter picks) are computed per
  payload ARTIFACT and cached on its (mtime_ns, size) in
  `~/.cache/engineering-loadout/payload-abi-scan-v1.json`; a registry edit
  re-runs the gate but re-reads nothing. `ANALYSE_VERSION` guards the
  derivation itself.
- Artifacts are decompressed and analysed in parallel (up to 8 threads), and
  the scan no longer holds every decompressed file in memory -- only findings.
- The three audits are unchanged; the registry / `_BUNDLED_PY` / build-script
  checks are untouched.

Measured: 71 s -> 11.4 s cold, 0.31 s warm; touching one 118 MB artifact
re-reads only that artifact (3.4 s). The gate still fails on synthetic
defects -- a payload ELF whose NEEDED says `libpython3.14` and a shebang
`env python3.10` were both reported, including from a warm cache.

## 2026-11-06 (6): Tier 1 runs in parallel; the size gate reuses measurements

Class A (tests + build tooling + docs). Follow-up to (5): the cache made a
repeat run cheap, but a changed file still ran its tests one at a time, and
`gen-installed-sizes --check` decompressed ~3 GB on every env edit.

- Tier 1 runs min(4, nproc) tests at a time (`--serial`, or
  `LOADOUT_TEST_JOBS=N`). `auto` (Tier 2) tests never overlap: they arm the
  repo-global dependency-capture marker. Each job writes its own log and exit
  status; the parent replays the log and counts FAIL/SKIP from the status.
- The `all`/`container`/group verdicts are precomputed once per run, in
  parallel, and handed to workers via `GROUP_STATE`/`SIDECAR_OK`; the
  end-of-run sidecars are written in parallel too.
- `gen-installed-sizes` caches each measured size keyed on the source's
  mtime+size (`~/.cache/engineering-loadout/installed-sizes-v1.json`); only
  changed artifacts are decompressed. Unreadable artifacts are never cached,
  so a transient failure retries instead of freezing a wrong number.
- Groups widened after auditing what each test opens: `docs-sync` now covers
  build/, tools/, tests/ and the shim; `payload-interpreter-abi` adds
  loader+build; `python-suite` adds build; `install-noop-stamps` adds envs;
  `nodejs-runpath` adds loader. The harness itself (`tests/run-all`,
  `build/fingerprint.py`) is a required input of every group, so editing the
  runner invalidates all group verdicts.
- `content-manifest matches export` is keyed on `.content-manifest` plus the
  git refs (it verifies HEAD), so working-tree edits stop re-running it.
- Fixed a counting bug this exposed: `_run_test` fell through with the status
  of its last assignment, so a failing test reported success to the parallel
  parent (and a 77 would have aborted `--serial` at `set -e`). It now returns
  0 / 1 / 77 explicitly, and the serial wrapper swallows the status.

Measured here (Tier 1, 53 tests): warm 4.1 s (52 CACHED, one 2 s gate runs);
`touch envs/zsh/global/zshrc` 18 s (was 49); `touch payload/packages.json`
90 s (was 144, and 70 s of it is the single-threaded payload ABI walk); cold
116 s. `gen-installed-sizes --check`: 23.5 s cold -> 1.0 s warm.

## 2026-11-06 (5): test results cache per dependency group; `--fast` uses it

Class A (tests + docs). Two flaws made every small change pay for the whole
suite:

1. `--fast` set `CACHE_ACTIVE=0`, so the dev loop never read or wrote the
   result cache; every `--fast` re-ran all of Tier 1 (175 s here).
2. Every Tier 1 test was keyed on ONE fingerprint over
   payload+envs+installer+tests, so one env byte invalidated all of them.

What changed in `tests/run-all`:

- `--fast` uses the cache (`--no-cache` still forces a full run).
- `run_test NAME --deps <group>[+<group>] ...` keys a test on named roots --
  `envs`, `payload`, `loader`, `build`, `sonames`, `locks`, `readme`,
  `stfonts` (`DEP_GROUP`). Each group has its own sidecar, verified once per
  run and written at the end, including the `--fast` early exit (which
  previously skipped the write entirely, so a `--fast` run could never warm
  the cache).
- `--deps-key FILE` caches a gate whose script lives outside `tests/`: the
  gen-* `--check` gates (installed-sizes, parser-locks, st-font, README table)
  use their own generator as the test-script hash, and their inputs/outputs
  are in the group roots. `content-manifest in sync` and `matches export` stay
  uncached -- they read git tracking state, which has no fingerprint.
- The `all` and `container` verdicts are computed once per run, not per test.
- A FAIL now drops any older PASS for that test, so a failure on unchanged
  inputs can no longer be masked by the previous run's green.

Measured on this host (Tier 1, 53 tests): cold 178 s; warm unchanged 14 s
(51 CACHED); `touch envs/zsh/global/zshrc` 49 s with every payload/loader test
still CACHED; `touch payload/packages.json` 144 s with every env test still
CACHED. Omitted groups default to `all`, so opting in is what needs review --
a group that names too little is a stale green, not a fast run.

## 2026-11-06 (4): zsh reads the online-detection cache

Class B (payload env only; installer, registry and package artifacts
untouched). `envs/zsh/global/zshrc` called `loadout_detect_online`, so every
fresh zsh login that did not inherit `LOADOUT_ONLINE` paid the TCP probe; bash
(`envs/bash/global/bashrc`) and tcsh (`envs/tcsh/global/helpers/detect-online`)
both read the once-per-day verdict. zsh now calls
`loadout_detect_online_cached`, the function bash uses: it is zsh-safe
(`setopt LOCAL_OPTIONS KSH_ARRAYS SH_WORD_SPLIT`) and falls back to a live
probe when there is no `XDG_RUNTIME_DIR`. Everything else is unchanged --
`LOADOUT_CFG_ONLINE_DETECT` still forces 1/0, `LOADOUT_CFG_ONLINE_CACHE_TTL=0`
still disables caching, inherited `LOADOUT_ONLINE` still short-circuits.

Verified: `zsh -n envs/zsh/global/zshrc`; the real rc under `zsh -i` in a temp
HOME (seeded verdict 0 wins over a live online probe; an expired entry
re-probes); `tests/install-env-zsh` PASS, and its new cache assertions FAIL on
the old call (`FAIL: seeded online verdict not read from the cache`).
`payload/installed-sizes.json` regenerated (zshrc 22165 -> 22453 bytes);
`assurance/release-timings.tsv` gained this run's T1 rows.
`tests/run-all --fast` green. `tests/run-all` Tier 2 (other than
install-env-zsh) and the Tier 3 container gates not run for this change -- no
installer code touched; run them before the next release.

## 2026-11-06 (3): release 2026.11.2 -- open-eda-file-tools is one package

**PUBLISHED and verified 2026-11-06** (tag on `988e6c9`, Good ED25519
signature, tag binds `sha256sums.txt sha256 54fbce69...`, which matches the
published asset; four assets, not a draft; stash 344538464 bytes, sha256 equal
to the local one; `origin/main` = tag commit). Gates on `988e6c9`:
`tests/run-all --container` `All tests passed.` (1919 s; 92/92, nothing cached
or skipped; Tier 3 smoke 317 binaries OK, 23 skipped, plus dynamic analysis,
private-state-two-users and interactive-shell-almalinux8 PASS);
`build/release` 164 s after a 233 s dry run (malware scan CLEAN -- content-cached
from the dry run, 0 detections across 75,487 files, YARA-Forge 20261103 +
ClamAV 28175; smoke 339 binaries OK, 1 skipped; vuln-scan CLEAN; secret scan
tree + history CLEAN; manifest export 4584 files).

Class C (registry + installer + payload). Carries the merge in (2):
`open-eda-file-tools` installs liberty-tools, lef-tools and def-tools from one
package; the split entries and the absorbed `lefdef-tools` are gone. Currency
sweep re-run the same day (37 outdated rows, nothing bumped; worklist in the
2026.11.1 entry). No migration needed for a 2026.11.1 tree: the distributions
keep the same venv names, so reinstalling `open-eda-file-tools` updates all
three; the retired package names no longer resolve.

## 2026-11-06 (2): open-eda-file-tools is one package, three distributions

**Ruling:** `lefdef-tools` was absorbed into `open-eda-file-tools` upstream
(`smprather/open-eda-file-tools` commit `8e9759a`, release v2026.11.1), so
loadout exposes the project as ONE package. 2026.11.1 briefly shipped three
registry entries from that clone (`open-eda-file-tools`, `lef-tools`,
`def-tools`); they are merged here.

**What changed.** The registry field `uv_tools` (list) installs several
self-contained distributions as separate uv tools for one package.
`open-eda-file-tools` now carries `uv_tools: [liberty-tools, lef-tools,
def-tools]`, all four CLIs in `bins`, the union wheel closure, and
`rolling_subdirs: [".", "lef_tools", "def_tools"]` for `./build/update`
(which builds one wheel per directory). `rolling_subdir` is retired
(subsumed by the list), and the two split entries plus their
`@python-tools-extra` membership are gone. `tests/registry-integrity` pins
the `uv_tools` shape, `tests/wheelhouse-closure` walks every distribution's
closure, and `tests/install-open-eda-file-tools` (new, T2) installs the single
package and asserts four launchers and three tool venvs.

Verified so far: unit-resolver 98/98, registry-integrity 21/21,
wheelhouse-closure OK (14 python-tools), install-open-eda-file-tools PASS,
docs-sync 9/9. Released as 2026.11.2 (entry 3).

## 2026-11-06: release 2026.11.1 -- interactive shell selection, split LEF/DEF tools, bundled Python 3.12/3.13

**PUBLISHED and verified 2026-11-06** (tag on `7972609`, Good ED25519
signature, tag binds `sha256sums.txt sha256 4f91014a...`, which matches the
published asset; four assets, not a draft; stash 344538464 bytes, sha256 equal
to the local one; `origin/main` = tag commit). Gates on `7972609`:
`tests/run-all --container` `All tests passed.` (1748 s; 91/91, nothing cached
or skipped; Tier 3 smoke 317 binaries OK, 23 skipped, plus dynamic analysis,
private-state-two-users and interactive-shell-almalinux8 PASS); `build/release`
163 s after a 341 s dry run (malware scan CLEAN -- 0 detections across 75,487
files, YARA-Forge 20261103 + ClamAV 28175, content-cached from the dry run;
vuln-scan CLEAN; secret scan tree + history CLEAN; manifest export 4584 files).

Class C (installer + registry + payload changed since 2026.10.9). What shipped:

- New installs open xfce4-terminal windows as login shells (`CommandLoginShell=TRUE`, seeded once; existing users keep their file).
- `LOADOUT_CFG_INTERACTIVE_SHELL` chooses your interactive shell for every terminal, `ssh` session, console and tmux pane: one line in your login shell's user layer (README "Choosing your interactive shell"). It replaces `LOADOUT_CFG_PREFERRED_BASH`/`_ZSH`/`_TCSH`; a typed `bash`, `t` or `tcsh` no longer switches.
- Settings cut over without aliases (`loadout doctor` names any left in your layers): tmux auto-attach (`LOADOUT_CFG_ATTACH_TO_TMUX*`), `LOADOUT_CFG_ENABLE_FASTNVIM` and `LOADOUT_CFG_WEZTERM_SHELL_INTEGRATION` are removed; `LOADOUT_CFG_ENABLE_ONLINE_UPDATES` is now `LOADOUT_CFG_ONLINE_DETECT`, `LOADOUT_ONLINE_CACHE_TTL` is now `LOADOUT_CFG_ONLINE_CACHE_TTL`.
- A first login bash keeps `/etc/profile.d`'s `module` (every fresh EL8 bash login used to delete it).
- `python-3.12` and `python-3.13` are now bundled CPython builds with `module load python/3.12|3.13` modulefiles; the default `python3` is unchanged.
- `lef-tools` and `def-tools` replace the retired `lefdef-tools` (LEF and DEF parsing split into two tools). Existing trees keep the old installed files; remove `$prefix/bin/lefdef-tools` and `$prefix/share/uv/tools/lefdef-tools/` by hand.
- `watchglass` 2026.11.3: the TUI is live (not read-only), with conpty failure classification.
- The resolver's `--skip` accepts glob patterns and may be repeated.
- The `uv` launcher honors `LOADOUT_PYTHON` without overriding per-project pins.

Currency sweep run, nothing bumped (a feature release six days after the last
sweep; the worklist is the next class-C job): biome 2.6.5, broot 1.62.0,
btm 0.15.0, btop 1.4.8, dust 1.2.7, fd 10.5.1, fresh 0.5.7, fzf 0.74.5,
gnuplot 6.0.6, gopls 0.24.0, gvim/vim 9.2.1302, ipython 9.18.1,
jupyterlab 4.6.5, just 1.59.0, klayout 0.30.13, lazygit 0.66.2,
librelane 3.0.17, linelight 2026.10.32, marktext 0.23.0, nodejs 26.13.0,
numr 0.9.3, rsync 3.5.2, ruff 0.17.4, sqlite 3.54.1, strace 7.3,
stylua 2.6.0, tmux-path-store 2026.10.5, ty 0.0.98,
typescript-language-server 6.0.3, uv 0.13.7, valgrind 3.28.0, verilator 5.054,
visidata 3.5, watchglass 2026.11.3.2, yq 4.54.2; rolling-git
open-eda-file-tools and time-plot moved. pdftotext stays pinned (poppler
>=26.06 needs fontconfig >=2.15; EL8 ships 2.13.1). ncdu's lookup 503'd.
Security data is current: YARA-Forge 20261103, ClamAV 28175 (2026-11-06).

The HANDOFF follow-up that blocked a class-C release is closed: a whole-test
SKIP now exits 77, and `tests/run-all` (9272cad) reports it as SKIP, counts it
separately and never caches it as a PASS.

## 2026-11-05 (2): interactive shell selection (`LOADOUT_CFG_INTERACTIVE_SHELL`) landed

One setting now chooses the interactive shell for every terminal, `ssh` session,
console and tmux pane, with no root, `chsh` or terminal config: a top-level
interactive bash, zsh or tcsh/csh replaces itself with the chosen shell once,
before any PATH work, keeping login-ness (`-l`). It replaces
`LOADOUT_CFG_PREFERRED_{BASH,ZSH,TCSH}`. Design (rev 3, with the rulings made
during execution): `docs/superpowers/specs/2026-11-05-interactive-shell-design.md`;
plan: `docs/superpowers/plans/2026-11-05-interactive-shell.md`. User-facing
rules: README "Choosing your interactive shell".

**What landed** (main, pushed to origin 2026-11-06):

| Task | Commits | Change |
|---|---|---|
| design | `7521999` | spec + plan |
| 1, settings clean-up (D11) | `6fe25dd` | tmux auto-attach, `ENABLE_FASTNVIM` and the explicit wezterm integration path removed; `ENABLE_ONLINE_UPDATES` -> `ONLINE_DETECT`, `LOADOUT_ONLINE_CACHE_TTL` -> `LOADOUT_CFG_ONLINE_CACHE_TTL` |
| 2, zsh home layers (D6) | `cd5585b` | zsh reads the home corp..user layers under a shared config root |
| 3, bash + zsh switch (D1-D4) | `3500357`, `d5a8ed0` | the switch; `PREFERRED_BASH`/`ZSH` retired; target probed with `-c :` before the exec; PATH walk takes absolute entries only |
| 4, tcsh + csh switch (D5) | `dbb8d8c` | the tcsh/csh switch; `PREFERRED_TCSH` retired; csh charset allowlist |
| 5, doctor (D7) | `02713b2`, `bf25e3d` | doctor's "Interactive shell" section and retired-setting report |
| 6, xfce4-terminal (D8) | `ff8fada` (+ `d7142f5`, `a9d4e23`) | `CommandLoginShell=TRUE` seeded once. The change was first swept into the other agent's `ae682c4` through the shared git index; `d7142f5` backs our hunks out of it, `ff8fada` re-lands them as their own commit, `a9d4e23` restores the test's 100755 mode. No history was rewritten. |
| 7, Settings table + gate | `534f8e7` | one Settings table in `envs/bash/README.md`; `tests/docs-sync` requires every defined setting documented |
| 8, Tier 3 | `e150665`, `c6ce7e1` | bash keeps the documented function list on a first login and silences `ps` where procps is absent; `tests/interactive-shell-almalinux8` |
| 9, close-out | `e2eeaca`, this entry | spec rev 3, doc-accuracy fixes, the docs/TMUX.md migration paragraph (D9) |
| final review | `4b7153e`, `e167e8c`, `d6c4237`, `db3106b` | spec rev 4: `bash -i FILE`/`zsh -i FILE` no longer switch (bash < 5.2 reads `/proc/$$/cmdline`); doctor notes a PATH-found target; the Settings gate requires a table row; doc corrections |
| cleanup | the commit after `db3106b` | `tests/env-interactive-shell`, `tests/env-tcsh-prompt-resize` and `tests/install-env-tmux-nvim-layers` remove their private tmux socket files on exit (tmux leaves the socket behind when a server exits; 72 stale ones had piled up in `/tmp/tmux-$UID`), and `build/secret-scan` keeps its default report in a `TemporaryDirectory` (it leaked one `.loadout-secret-scan-*` dir per run; 57 had piled up). The stale leftovers were removed by hand. |

Final gate on the pushed tree: `tests/run-all --container` at `db3106b`,
**91/91 PASS in 1927 s** (2026-11-06 04:55-05:27 UTC), including
interactive-shell-almalinux8 with T3-a..f and R7.

Interleaved on main, for context only (another agent's work, not part of this
plan): `e759592`, `7c86657`, `85ff7c9`, `ae682c4` (lef-tools/def-tools), then
`6de4aba`, `008b42e`, `a881a33` (lefdef-tools retired), `7b151c9` (tmux
copy-mode fix) and `aecea1d` (gate timings). Entry (1) calls the then-uncommitted
`envs/tmux/tmux-global.conf` / `docs/TMUX.md` edits part of this line of work;
they are `7b151c9`'s copy-mode change, which is separate. This work's only
docs/TMUX.md change is `e2eeaca`'s migration paragraph.

**Gates** (2026-11-05/06 UTC, dev host + `loadout-smoke:almalinux8.10`):

- First `tests/run-all` (T1+T2, 23:42-00:03 UTC, HEAD `e2eeaca`): 1284 s,
  86 PASS, 1 FAIL. `installed-sizes in sync` found `payload/installed-sizes.json`
  stale for 10 env files: nine from this work (env README, rc and xfce4-terminal
  edits in `534f8e7`, `ff8fada`, `e150665`, `e2eeaca`; the tasks ran focused
  tests, never this T1 sync gate) and `completions/loadout.bash` from `7c86657`.
  The other agent's `6de4aba` regenerated the file, and `gen-installed-sizes
  --check` is OK from there on. That run's rows went into `aecea1d`.
- Fresh `tests/run-all --container` (03:04-03:33 UTC, HEAD `aecea1d`, clean
  tree): **All tests passed**, 91/91, 1727 s. T1: 53 tests, ~183 s. T2: 34
  tests, ~1102 s (largest: install-linux-tmp-home 244 s, install-readonly-tree
  205 s, install-split-shared-envs 204 s; env-interactive-shell 31 s). T3: 4
  tests, 440 s: container smoke `--full` 422 s, dynamic analysis 13 s,
  private-state-two-users 2 s, **interactive-shell-almalinux8 3 s** (T3-a..e
  and the R7 check all PASS, really run, not a SKIP).
- Drift check (retired names outside archive/specs/HANDOFF): only README's
  "Retired and renamed settings" table, `RETIRED_SHELL_SETTINGS`, the
  `tests/doctor-shadow-audit` fixtures, and the three migration notes the spec
  asks for (README "Coming from `LOADOUT_CFG_PREFERRED_BASH`", `docs/BASH.md`,
  `envs/tcsh/README.md`).

**Deployment.** `e150665` fixes a loss that predates this work: the bashrc's
start-of-source `unset -f` kept only an INHERITED
`LOADOUT_CFG_PRESERVE_FUNCTIONS`, so every fresh EL8 bash login deleted
`/etc/profile.d`'s `module`. Deployed trees pick up the fix and the shell switch
only after `./loadout reinstall env-bash -y`, plus `env-tcsh` and `env-zsh` for
the switch from or to those shells. The deployed shared tree
(`.../loadout-shared/latest`, memory `reference-deployed-shared-tree`) is on
hosts this machine cannot reach; the user runs that reinstall there. Not run
from here.

**OPEN: manual X-session check -- NOT RUN.** No automated gate covers the
terminal side, and an agent cannot drive a real X session. In a real X session,
with `LOADOUT_CFG_INTERACTIVE_SHELL=zsh` set in the passwd shell's layer,
check that:

1. an xfce4-terminal window opened from the launcher starts as the passwd shell
   and switches to zsh as a login shell;
2. `xfce4-terminal` typed in a switched shell opens zsh directly;
3. with xfce4-terminal already running (it is single-instance), changing the
   preference and opening a window from the launcher shows whether the first
   instance's marker carries over (D3).

Record each result here. If step 3 shows the marker carrying over, document it
as a single-instance caveat in README "Choosing your interactive shell".

**Follow-ups.**

1. ~~zsh does not cache the online verdict: `envs/zsh/global/zshrc` calls
   `loadout_detect_online`, bash calls `loadout_detect_online_cached`, so every
   zsh session that does not inherit `LOADOUT_ONLINE` (each new login) pays the
   probe instead of reading the once-a-day cache.~~ **Closed 2026-11-06**:
   zshrc now calls `loadout_detect_online_cached`; `tests/install-env-zsh`
   seeds a verdict and asserts the cache is read (it fails on the old call).
2. D4 residual: a non-login origin gives a non-login target, and a non-login
   bash target gets no `/etc/profile.d` (accepted in the spec; sourcing
   `/etc/bashrc` is out of scope).
3. Other `/etc/profile.d` functions are still wiped at every bash login: the
   keep list is only `module _module_raw ml`, and any other function the system
   init defined before the bashrc is lost. Loadout's own functions are never
   exported, so in a fresh process the wipe can only remove the system's and
   inherited ones; question whether it should run there at all, or only on a
   re-source in the same shell.
4. **FIXED 2026-11-06.** `tests/run-all` cached a whole-test SKIP (exit 0) as
   a PASS (`interactive-shell-almalinux8`, `private-state-two-users`). Whole-run
   skips now exit 77; run-all reports `SKIP`, counts it separately, drops any
   stale `.pass`, and never caches it as green. The same convention was applied
   to every other whole-run skip (env-helix-config, env-nvim-no-git,
   env-nvim-smart-quit, install-env-vim-xdg, env-interactive-shell,
   install-env-tcsh, install-env-zsh, env-tcsh-prompt-resize). Partial skips
   inside a test that still runs its other cases keep exit 0.
5. D3, single-instance terminals: depends on step 3 of the manual check.
6. A change to any file under `envs/`, a README included, changes
   `payload/installed-sizes.json` (env sources are sized as whole trees), so it
   needs `build/gen-installed-sizes` and then `build/gen-content-manifest`
   before the commit. Only the T1 sync gate catches it; consider a pre-commit
   check.
7. The wezterm resolver step still falls back to
   `${LOADOUT_CFG_SHARED_PREFIX:-$HOME/.local}`, not the canonical
   `~/.local/share/loadout`.
8. `unset_bashrc_local_vars` is bash-only (`compgen`); add
   `[ -n "${BASH_VERSION:-}" ] || return 0` before any zsh caller appears.
9. `envs/zsh/zshrc`'s root-vs-home `[[ ... != ${_home_*:A} ]]` has an unquoted
   RHS, so a HOME with glob characters mis-compares.
10. `tests/env-interactive-shell` depends on `ps` with no SKIP; use
    `readlink /proc/$$/exe` like Tier 3.
11. No regression case for the bash→bash non-login `--init-file` exec form
    (verified by hand, again after `4b7153e`).
12. tcsh: no tcsh-origin cases for symlink-to-self or an unknown basename (no
    `-l`); the inherited-SHELL charset guard and the helpers-dir half are
    untested; `envs/tcsh/README.md` should name the config-root path among the
    guarded values.
13. AGENTS.md's interactive-shell paragraph overclaims ("every value shape";
    the Python mirror is not in tc-ae's comparison). Feed tc-ae's value list to
    `_resolve_interactive_shell` too (R4's shared case list).
14. doctor: no no-false-positive test for "set in the passwd-family layer";
    `tests/doctor-shadow-audit`'s `(EL rc: no)` branch reuses `$out` from an
    earlier run; `_env_installed` checks only the first root's `global/`
    (false findings under a manual shared config root).
15. `tests/install-env-xfce4-terminal` checks XML properties by name only, not
    by value.
16. `tests/interactive-shell-almalinux8`: `timeout` sits mid-pipeline (a hang
    shows as `got []`), and nothing bounds the install or the `docker run`.
17. T3-f (EL8 bash 4.4 given a script runs it; the only gate on the
    `/proc/$$/cmdline` half of the script-operand guard) was written in
    `4b7153e` and has since passed at `db3106b`: alone in 6 s, and inside the
    full `tests/run-all --container` (91/91, 1927 s). The guard still misreads
    bash's undocumented single-dash long options (`-norc`, `-noprofile`,
    `-rcfile F`, `-posix`) as option clusters, so `bash -norc -i FILE` on
    bash < 5.2 switches and drops FILE; rare, not fixed.
18. zsh's `ZSH_SCRIPT` guard is checked on zsh 5.9 (dev host, the payload zsh)
    only. EL8's system zsh 5.5.1 is unchecked; no local image has it.

## 2026-11-05 (1): `lef-tools` + `def-tools` (open-eda-file-tools distributions 2 and 3)

`open-eda-file-tools` grew from one distribution to three. The registry had only
`liberty-tools` (root of the clone); the LEF and DEF projects are now packages:

- `lef-tools` (`rolling_subdir: lef_tools`) — `lef-tools` CLI.
- `def-tools` (`rolling_subdir: def_tools`) — `def-tools` CLI (`instances`,
  `net-shapes`, `cache`, `clock-instances`, `configure-io`).
- Both `rolling_git` on the same clone URL as `open-eda-file-tools`; the registry
  `version` is `git describe` of the clone root (`v2026.11.2-1-g515a151`), which
  all three share, while each wheel's version comes from its own `pyproject.toml`.

Shipped wheels: `lef_tools-2026.11.0-cp315-cp315-manylinux_2_28_x86_64.whl`,
`def_tools-2026.11.2.dev0-cp315-cp315-manylinux_2_28_x86_64.whl`.

`build/update` (rolling path) gained three things, each with its reason:

- `rolling_subdir` — build the wheel from `<clone>/<subdir>`; absent means root.
  Documented in the registry `_schema` (which `tests/registry-integrity` enforces)
  and in `build/ADDING_BINARIES.md`.
- A **glibc guard**: a maturin backend on a host newer than glibc 2.28 is refused
  with the container command. Host-built, maturin's audit rejected lef-tools for
  `GLIBC_2.30/2.33/2.34`; the alternative outcome is a wheel that dies on RHEL 8.
- `UV_PYTHON` defaults to the repo's 3.15 bootstrap, so the wheel is cp315
  (upstream `requires-python >=3.14`, and uv otherwise picks a 3.14).
- A **workaround for an upstream defect**: their `.gitignore:11` is `build/`,
  which also drops `vendor/cargo/zstd-sys/zstd/build/**` while
  `.cargo-checksum.json` still lists it, so `cargo` fails checksumming on every
  clean clone. The rolling path moves the clone's `.cargo/config.toml` aside for
  the build (throwaway clone, network available) and says so. Remove it if
  upstream fixes their `.gitignore`.

`build/container-rust` provisions rustup + uv inside the container into the
persistent `/cache` mount (the image ships none by design) and writes
`/cache/env`, because rustup's shims need `RUSTUP_HOME` as well as PATH.

**Verification.** In-container build `real 1m49s` (toolchain cached; includes two
clones, crates compile, wheel copy, sizes + manifest regen).
`tests/wheelhouse-closure` OK (244 wheels, 17 python-tools resolve offline under
cp315); `tests/registry-integrity` 20/20; `build/gen-readme-table` in sync after
adding the two hand-owned rows; offline smoke
`uv tool install --no-index --find-links payload/el8.x86_64.glibc2p28/wheels`
into a scratch `UV_TOOL_DIR`, then `lef-tools --help` and `def-tools --help`
both run. `tests/run-all --fast` PASS (174 s). Scratch-dest install through the
real installer: `lef-tools, version 2026.11.0` and
`def-tools, version 2026.11.2.dev0`.
`tests/prebuilt-binaries-almalinux8 --full` PASS (606 s; 318 binaries OK, 23
skipped) — it caught the stale bash completion (Tier 2 only, so `--fast` missed
it), now regenerated.

**Not part of this entry:** the interactive-shell work landed separately
(`3500357`, `d5a8ed0`, `dbb8d8c` plus the design doc in `7521999`). The working
tree also carries uncommitted edits to `envs/tmux/tmux-global.conf` and
`docs/TMUX.md` from that line of work; nothing here depends on them, and they
are not staged with these changes.

**`lefdef-tools` retired (2026-11-05, same day).** The unsplit predecessor
(separate repo, `v2026.9.0`; same five DEF subcommands plus LEF queries) is
gone: registry entry, wheel, `@python-tools-extra` membership, README row,
rolling-git lists and its `build/currency-state.json` row. `lef-tools` +
`def-tools` are the replacement. Verified: registry-integrity 20/20,
wheelhouse-closure OK (16 python-tools resolve offline; the orphan wheel is
gone), docs-sync 9/9, completion in sync, T1 `--fast` PASS (175 s),
`prebuilt-binaries-almalinux8 --full` PASS (611 s, 317 binaries — one fewer,
as expected).

Nothing prunes an install that already has it: there is no retired-package
sweep, so an existing tree keeps `bin/lefdef-tools` and
`share/uv/tools/lefdef-tools/`. Clean up by hand:

```sh
rm -rf "$prefix/bin/lefdef-tools" "$prefix/share/uv/tools/lefdef-tools"
```

**Follow-up.**
`_version_tuple()` parses a describe string as numbers, so a hand-pinned
dot-version placeholder (`2026.11.2.dev0`) looked like a downgrade against the
first `git describe` stamp and made `./build/update` exit non-zero **after**
writing the correct version. Observed once, self-correcting on the next run;
worth teaching `_version_tuple` about `-N-gSHA` suffixes the day a rolling
package is first added with a pinned placeholder.

## 2026-11-04 (1): `--skip` accepts glob patterns

`--skip` was literal-only: `--skip 'font-*'` warned `unknown package 'font-*'`
and skipped nothing, so "a bundle minus a family of packages" needed every
name spelled out. `resolve_tool_selection()` now runs a new
`_expand_glob_names()` over the parsed `--skip` list before `expand_groups()`.

- Patterns use `fnmatch` syntax (`*`, `?`, `[...]`) and match case-sensitively
  against package and `@group` names; a matched group then expands normally, so
  `--skip '@fonts-*'` works too.
- Exact names keep their old meaning and a list can mix both:
  `--skip 'font-firacode,font-j*'`.
- A pattern with no matches is the same no-op as an unknown package (one
  warning, nothing removed). A pattern matching a disabled package is a sweep,
  not a demand: warn and continue, like a group member.
- Subtraction still happens before dependency walking: a selected package whose
  hard dep is skipped raises `ResolverError` unless `--no-deps`/`--force`.
- Scope is `--skip` only. Positional/`--only` globs are NOT expanded;
  `cmd_install_v2` still exits with `no match for argument` for them.
- `--skip` is repeatable (`multiple=True`): occurrences are unioned, and each
  value may still be a comma list or a pattern. `_parse_namelist()` accepts a
  string or an iterable, so `--skip a,b --skip c` == `--skip a,b,c`.

`--skip` help/metavar and AGENTS.md, README.md, docs/ARCHITECTURE.md and
docs/INSTALLATION.md were updated with the pattern form.

**Verification.** `tests/unit-resolver` `test_skip_globs` (7 cases, written
failing first for `*`, `?`/class, mixed list, repeated occurrence, no-match,
disabled match; plus a repeated-occurrence case in `test_resolve_tool_selection`);
`tests/run-all --fast` PASS (181 s). CLI smoke: `resolve @fonts-all --skip
'font-*'` → 0 packages; `--skip 'font-?ack'` → 11; `resolve
@fonts-all,@core-cli --skip '@fonts-*'` → 22 bins (fonts gone, `@core-cli`
intact); `--skip font-firacode --skip font-hack` → 10, same as the comma form.

Branch `fix/skip-globs`. The uv-launcher fix in `4dd019b` below is an
independent change, not part of this one.

## 2026-11-03 (6): uv launcher dispatch -- review-fix follow-ups

A fresh review of the multi-Python launcher found the subcommand scan could
still be bypassed. Fixed in `build/uv-launcher.sh`:

- Every value-taking global option is consumed with its value, including
  `--trusted-host` and `--python-preference`; before, their value became the
  "subcommand" and the project-pin gate was skipped.
- Global options are recognized on either side of the subcommand (`uv venv
  --directory DIR`, `uv run --project DIR`), and `--directory`/`--project`
  move the pin walk's starting root. Previously the scan stopped at the
  subcommand, so a post-subcommand `--directory` left the walk in the old cwd.
- `--` ends option parsing, so a value after it can never be read as an
  option.
- A nonexistent relative `--directory`/`--project` no longer hangs the pin
  walk: failed `cd -P` absolutes the value against `$PWD`, and the walk also
  breaks on `dirname`'s fixed point. (This was the reported hang; the repro
  `uv --directory no-such-dir venv` now returns uv's own ENOENT, not 124.)
- The launcher always exports `UV_PYTHON_DOWNLOADS=never`, independent of a
  loaded module.

`tests/uv-launchers` is now 18 cases: global option before the subcommand,
`.python-versions` pin, launcher-level download guard, the nonexistent-dir
timeout, a non-subcommand value (`--trusted-host`), and post-subcommand
`--directory`/`--project` moving the walk. `tests/install-python-versions` now
runs `reinstall` and asserts the interpreter inode actually changed, so the
venv-stability half of Review Focus #2 is exercised rather than vacuous.

**Verification.** `tests/uv-launchers` PASS (18 cases);
`tests/install-python-versions` PASS; `tests/run-all --fast` PASS (179 s);
generated sizes/manifest `--check` PASS. Entry (5)'s "11 cases" and its
`.python-version`-only phrasing are superseded by this entry.

## 2026-11-03 (5): multi-Python core builds -- implemented and verified

`@python-versions` (`python-3.12`, `python-3.13`) is implemented end to end:
optional python-build-standalone `install_only_stripped` interpreters at the
stable per-minor path `<prefix>/opt/python/<minor>`, an installer phase that
writes `<prefix>/share/modulefiles/python/<minor>`, and a uv launcher that uses
`LOADOUT_PYTHON` as its default without overriding project pins. `python-loaded`
and EL's own Python tools remain on 3.15, and the new versions stay out of
`@shared` (they are in `@shared-all`/`@all` and in `@python-versions`).

**Pinned inputs.** PBS tag `20261026`; assets
`cpython-3.12.16+20261026-x86_64-unknown-linux-gnu-install_only_stripped.tar.gz`
sha256 `ce4f6d0a6cfdb3bed6e44c2f9affd85943c76a42e25ad3a259002f31d6fb8a20` and
`cpython-3.13.18+...` sha256
`df15fe60d3ff55bf9dcf25824b5572756bb8816ff93865a273d3301d7066a8b7`. Repacked
payload: 31,212,850 B / 99,018,994 B installed (3.12) and 31,925,122 B /
99,762,037 B (3.13). Highest GLIBC symbol 2.17, NEEDED glibc-only, no `gui_libs`
dependency. Build: `build/build-shell sh -c 'build/build-python-standalone.sh
--tag 20261026 --version 3.12.16 && ... 3.13.18'` (13.6 s).

**Behaviour.** `module load python/3.12` prepends that interpreter's `bin`, sets
`LOADOUT_PYTHON` and `UV_PYTHON_DOWNLOADS=never`, and sets no
`PYTHONPATH`/`PYTHONHOME`/`LD_LIBRARY_PATH`/`UV_PYTHON`. The uv launcher pins
`UV_PYTHON` from `LOADOUT_PYTHON` when executable, else `<prefix>/bin/python3`;
a project `.python-version` or `requires-python` disables the default for
`run`/`sync`/`lock`/`venv`/`add`/`remove`/`build`/`export`; `uv pip` and active
venvs keep their carve-outs. venvs built from `opt/python/<minor>/bin/python3`
survive in-place patch reinstalls. User docs: `docs/PYTHON-VERSIONS.md`.

**Verification.** `tests/run-all --fast` PASS (175 s). Targeted T2 PASS:
`tests/install-python-versions` (new), `tests/uv-launchers` (11 cases incl.
LOADOUT_PYTHON pin, `uv init` pin, `.python-version` and `requires-python`
precedence), `tests/install-modules`, `tests/install-watchglass`,
`tests/install-python-tool-upgrade`. Tier 3
`tests/prebuilt-binaries-almalinux8 --full` PASS (604 s): all 316 binaries OK,
23 skipped, and both interpreter probes report the right version with a
modulefile present. The first Tier 3 run failed only on the stale bundled bash
completion (`@python-versions` missing); fixed in `3ae4a88`.

**Open decisions.** (1) EOL: 3.12 ends October 2028, 3.13 October 2029 -- decide
then whether to drop or freeze them. (2) Only minor modulefiles ship
(`python/3.12`); exact-patch names are not offered. (3) A site running the
bundled Environment Modules (5.6.1) gets `family python` switching; a site's own
Modules needs 5.1+ for `family`, else wrap with `conflict python`. (4)
`@python-versions` is deliberately NOT in `@python-stack`, so a default stack
install stays single-version; revisit only if a real case asks for both.

## 2026-11-03 (4): multi-Python core builds -- plan written, implementation not started

The user approved shipping CPython 3.12 + 3.13 alongside 3.15, with modulefiles
and uv selection, and explicitly excluding per-version python-loaded. The
implementation plan is
`docs/superpowers/plans/2026-11-03-multi-python-core-builds.md` (Tasks 1-5,
estimated 6.5-9.5 engineer-days). Key decisions: python-build-standalone
`install_only_stripped` tag `20261026`, versions `3.12.16` and `3.13.18`; stable
`<prefix>/opt/python/<minor>` installed through the existing generic
runtime-archive machinery; installer-generated modulefiles at
`<prefix>/share/modulefiles/python/<minor>`; the uv launcher reads
`LOADOUT_PYTHON` and defers to a project `.python-version` or `requires-python`;
extra versions are optional and grouped as `@python-versions`; `python-loaded`
and EL's own 3.15 tools are untouched. No code or payload changed yet.

Next: execute Task 1 in a fresh session. Read the plan, then the parked design
at `docs/superpowers/specs/2026-11-03-multi-python-versions-parked-design.md`
for the measured uv behavior. The plan's Review Focus section lists the five
failure modes the tests must pin.

## 2026-11-03 (3): watchglass 2026.11.3 -- conpty failure classification

Upstream published 2026.11.3 on 2026-11-03 (tag `v2026.11.3`, PyPI), hours
after the 2026.11.2 bundle. Rebuilt from the tag with
`build/build-watchglass.sh --tag v2026.11.3` in `build/build-shell`; the
tag/version, console-script and closure checks passed and the Linux runtime
closure is unchanged, so no wheelhouse additions. `loadout_stamp_version` moved
`payload/packages.json` to 2026.11.3; sizes -> manifest -> README regenerated.

The release is Windows-only in effect: `password_mode = "conpty"` merges the
command's stderr into stdout, and the classifiers now read that merged console.
A rejected credential parks on the first auth failure instead of retrying to
`max_failures`; a `-p` transfer whose bytes arrived but whose times could not be
set is the usual warning; a vanished source raises `TransferMissing`; scp's
`C:\Program Files\OpenSSH\scp.EXE:` prefix is recognised, a remote
`/usr/bin/scp:` lookalike is not. Nothing a run printed to stderr changed, and
no Linux code path is affected.

**Verification.** Build 4 s; generators 24 s. `tests/install-watchglass` PASS
(9 s): offline install, launcher and `farm-versions` report 2026.11.3, closure
imports, reference docs, init/new/validate/poll --dry-run, no service
registered. `build/check-versions --format tsv` reports `watchglass 2026.11.3
2026.11.3 pypi current`. `tests/run-all --fast` PASS in 169 s.

## 2026-11-03 (2): watchglass 2026.11.2 -- poke a watch

The user asked to update watchglass if needed. Upstream published 2026.11.2 on
2026-11-02 (PyPI upload 17:04Z; tag `v2026.11.2`), one release after the bundled
2026.11.1. Rebuilt from the tag with `build/build-watchglass.sh --tag
v2026.11.2` in `build/build-shell`; the tag/version, console-script and
dependency-closure checks passed, and the closure is unchanged (Linux still
resolves rich, rich-click, textual, watchdog and their deps; `pywinpty` stays
behind the win32 marker), so no wheelhouse additions. `loadout_stamp_version`
moved `payload/packages.json` to 2026.11.2, and `gen-installed-sizes` ->
`gen-content-manifest` -> `gen-readme-table` regenerated the size map, manifest
and README row. New CLI surface: `watchglass poke NAME` and TUI `p`, an
off-interval poll request the running service consumes within a second. The
entry still has no GitHub `version_url` -- the Releases object skipped
`v2026.11.1` -- so `check-versions` reads PyPI.

**Incidental drift fixed.** `installed-sizes.json` was stale for
`envs/nvim/lua/global/init.lua` (19766 -> 20227 bytes): the 2026-11-02 nvim
`:q!` fix (`a0a7035`) changed the file without regenerating the size map, so
the T1 `installed-sizes in sync` gate would fail on that commit. This
regeneration records the current size; no nvim content changed here.

**Verification.** Build 4 s; generators 23 s. `tests/install-watchglass` PASS
(9 s): offline wheelhouse install, launcher and `farm-versions` both report
2026.11.2, the full closure imports, reference docs are present,
init/new/validate/poll --dry-run work, and no service is registered.
`build/check-versions --format tsv` reports `watchglass 2026.11.2 2026.11.2
pypi current`. `tests/run-all --fast` PASS in 171 s.

**T1 drift fixed in passing.** The first `--fast` run failed only
`env-tcsh-starship`: the exact-prompt assertion pinned the host's Python to
3.14.8, and the host had moved to 3.14.9. The gate now derives the version from
the same `python` on its fixture PATH (`108c0eb`), so a host patch bump cannot
red T1 again. No shell behavior changed.

## 2026-11-03 (1): multiple Python versions -- case-driven, design parked (knowledge recorded, not pursued)

Design conversation only; no code change. Asked: ship several CPython versions,
selectable with an Environment Module (`python/3.12`), with uv wired so
`uv init` does the right thing. **Decision: not built on speculation.** EL stays
on one interpreter (3.15) plus python-loaded. A second version is added only
when a specific script cannot be up-revved, usually by an AI agent. A dependency
missing a 3.15 build is temporary and is not a trigger. EDA tool bindings are
not a trigger either, because the tools ship their own Pythons.

Full record, with the triage, the parked design (python-build-standalone
interpreters at stable per-minor paths, EL-generated modulefiles, python-loaded
per minor, uv wiring), 16 uv/PEP 723 measurements on uv 0.12.17, the prior-art
survey and the open questions:
`docs/superpowers/specs/2026-11-03-multi-python-versions-parked-design.md`.
The measurement most likely to matter: a modulefile must never export
`UV_PYTHON`. It overrides a project's `.python-version` and silently rebuilt a
3.12-pinned `.venv` on 3.13.

## 2026-11-02 (2): nvim smart `:q` no longer breaks `:q!`

The global layer rewrites a bare `:q` to the user command `:Q`, which drops the
arglist before quitting (no "N more files to edit" nag). The rewrite is
`cnoreabbrev <expr> q (getcmdline() ==# 'q') ? 'Q' : 'q'`. That guard cannot
exclude `:q!`: the abbreviation expands the moment the non-keyword `!` is
typed, while `getcmdline()` still returns `q`. So `:q!` always arrived as
`:Q!`, and every `:q!` died with `E477: No ! allowed`.

`Q` now takes `bang = true`, and the bang path runs `quit!`. `:q!` keeps its
force-quit meaning on a modified buffer, and `:qa!` is unaffected
(`envs/nvim/lua/global/init.lua`). The new gate is `tests/env-nvim-smart-quit`
(T1, headless nvim with plugins and git absent). It covers modified `:q!`,
`:q` skipping the arglist nag, and `:qa!`. Negative control: with the fix
reverted, the gate fails with `E477`.

## 2026-11-02 (1): watchglass 2026.11.1 bundled as a python-tool

The user asked to add [smprather/watchglass](https://github.com/smprather/watchglass).
It is a pure-Python CLI (hatchling, `py3-none-any`) that polls watches, runs
observers/recipes, logs JSON lines and shows a read-only TUI. Packaged as a
non-optional `python-tool`, `uv_tool: watchglass`, `depends: [portable-python,
uv]`, member of `@system-monitor`; the build/verify recipe is
`build/build-watchglass.sh` and the mandatory note is in
`build/ADDING_BINARIES.md` ("watchglass 2026.11.1").

**Version.** 2026.11.1, built from tag `v2026.11.1` (the same version is on
PyPI). The GitHub *Releases* API still returns 2026.10.31.1, so the registry has
NO GitHub `version_url`; `check-versions` must read PyPI. The script refuses a
tag/pyproject mismatch, a pre-release, a console-script mismatch, a missing
runtime dependency, or a registry `wheels` list that no longer matches the
closure.

**Wheel closure.** The wheelhouse already had rich, rich-click, click,
markdown-it-py, mdurl, platformdirs, pygments and typing-extensions. Added:
`textual-8.2.8`, `watchdog-7.0.0` (py3-none-manylinux2014_x86_64),
`linkify_it_py-2.2.0`, `mdit_py_plugins-0.6.1` (sha256s and the one-time
`pip download` command in `build/ADDING_BINARIES.md`). `linkify-it-py` 2.2.0
has no base dep (no `uc-micro-py`); watchdog 7.0.0 has none either (PyYAML is
only the `watchmedo` extra). `pywinpty` is correctly excluded by its win32
marker. `tests/wheelhouse-closure` passes: all 15 enabled python-tools resolve
offline under cp315.

**Generators.** `gen-installed-sizes` must run BEFORE `gen-content-manifest`
(the manifest hashes `installed-sizes.json`); running the manifest first leaves
a MISMATCH and was caught by T1. README row, completion and manifest/sizes are
regenerated. `watchglass` was added to `build/farm-versions` with
`watchglass, version ([0-9][0-9.]*)`.

**Test.** `tests/install-watchglass` (T2, `--deps auto`): installs offline into
a temp root, asserts the installer passes `--no-index`/`--find-links`, checks
the launcher version against the registry, imports the full closure, runs
`docs agent`, then `init`/`new hello`/`validate hello`/`poll hello --dry-run`,
checks `build/farm-versions` reports the tagged version, and asserts no systemd
unit was registered. It never runs `watchglass install` (that is the user's
opt-in to the service).

**Docker bridge failure = reboot, not a workaround (rule set 2026-11-02).**
During this work `docker run` failed with `failed to add the host <=> sandbox
pair interfaces: operation not supported`; the user confirmed a pending kernel
update. The build and generators were run via `docker run --network host`
BEFORE the user ruled workarounds out; do NOT repeat that. On this failure,
stop and tell the user exactly: "can't run tests until you reboot." The
mandated `build/build-shell` entry point must not be bypassed. (The Tier 3
`--network none` result above is from the normal test mode and stands.)
A separate T1 trap: `tests/python-suite`'s D8 gate runs `git status --porcelain`
on the shared wheelhouse, so new wheels must be COMMITTED, not merely staged,
before T1 can pass.

**Verification.** Build 4 s; generators 23-25 s; T2 smoke 9 s; Tier 3
`tests/prebuilt-binaries-almalinux8 --no-build --full` PASS in 594 s (all 316
binaries OK, 23 skipped; the new `watchglass --version` probe reports
2026.11.1). `build/check-versions --format tsv` reports `watchglass 2026.11.1
2026.11.1 pypi current`. T1 fast `tests/run-all --fast` PASS in 173 s after the
wheelhouse commit (the D8 gate needs the wheels committed, not staged). Targeted
T2 after the amend: `completion in sync`, `optional-packages` and
`install-python-tool-upgrade` PASS (44 s total).

## 2026-10-31 (3): release 2026.10.9 -- tornado + pyasn1 security refresh

**PUBLISHED and verified 2026-10-31** (tag on `b2d4a49`, Good ED25519
signature, tag binds `sha256sums.txt sha256 a0f333f0...`, which matches the
published asset; four assets, not a draft; stash 344538464 bytes, sha256 equal
to the local one; `origin/main` = tag commit). Gates on `b2d4a49`:
`tests/run-all --container` `All tests passed.` (1480 s; Tier 3 smoke 315
binaries OK, 23 skipped); `build/release` 422 s (malware scan CLEAN across
65902 files, YARA-Forge 20261026 + ClamAV; vuln-scan CLEAN).

Class C (installer + registry changed since 2026.10.8: linelight, lsd
retired, `delete`'s `SHARED_ENV_HELPERS`, the review fixes). Currency sweep run,
nothing bumped (same ruling as 2026.10.8: a fix release, three days after the
last sweep). `build/check-versions --outdated-only` on 2026-10-31 lists 25
behind upstream -- the 2026-10-28 worklist (btop, fzf, gnuplot, gopls,
gvim/vim, just, lazygit, librelane, marktext, numr, ruff, sqlite, strace,
stylua, ty, uv, valgrind) plus biome 2.6.4, ipython 9.18.0, jupyterlab 4.6.5,
nodejs 26.13.0, visidata 3.5, tmux-path-store 2026.10.5 and linelight
2026.10.31-1 (upstream's fix for linelight#7, the tcsh `eval` form; loadout
sources the adapter from a file, so it does not need it). pdftotext pinned;
ncdu lookup 503'd. YARA-Forge rules refreshed 20261018 -> 20261026; ClamAV
daily DB from 2026-10-31.

The first `build/release` run was BLOCKED by the vulnerability gate, before any
tag: tornado 6.5.10 (jupyterlab) and pyasn1 0.6.4 (python-loaded) had new
advisories. Both wheels were refreshed with a closure-preservation proof
(build/ADDING_BINARIES.md, "2026-10-31 security refresh"); pyasn1's lock line
was re-pinned by hand rather than re-resolving the suite. Gates before the
refresh: `tests/run-all --container` `All tests passed.` (1817 s; Tier 3
smoke 315 binaries OK, 23 skipped). Release gates re-run after it.

`build/release` and `build/check-versions` need `python3.15` on PATH. This dev
host has none there (the default root has no portable Python installed), so
both died `env: 'python3.15': No such file or directory` until run with
`PATH="$PWD/.loadout-bootstrap/bin:$PATH"`.

## 2026-10-31 (2): `delete` -- rm -rf through read-only modes, and NFS .nfs* holders

The user supplied a bash `delete [-f] PATH...` (chmod -R u+w, then rm -rf) to
add to the shell envs, asked for it to detect `.nfs*` files that block a
delete and interactively offer to kill the processes holding them, and then
asked for ONE bash script that every shell runs, copied into each installed
env rather than linked.

**Shape.** `envs/bash/global/helpers/delete` (bash). bash/zsh: `delete()` in
global/aliases.sh runs `"$BASH_CONFIG_ROOT_DIR/global/helpers/delete"`. tcsh:
`alias delete "$_lo_helpers/delete"`, and `_install_env_tcsh` copies the file
into tcsh's global/helpers (`SHARED_ENV_HELPERS`; a copy, since env-tcsh
installs without env-bash). The name `delete` was free everywhere checked:
bash/zsh/tcsh builtins and reserved words, host PATH, almalinux:8.10, payload
bins, wheel console scripts, the installed tree.

**Defects in the pasted function, fixed:** (1) zsh -- `local path` is zsh's
tied `$PATH` array, so the loop variable replaced PATH; `rm` was "command not
found", nothing was deleted, exit 127. (2) `chmod -R u+w LINK` follows the
link: deleting a symlink unsealed the tree it pointed at. (3) `--` was
rejected. (4) a missing PATH returned 0 unless it was the last argument.
Changed on purpose: only DIRECTORIES are chmod'ed (u+rwx where unlistable,
else u+w) -- unlink needs write on the directory only, and chmod'ing files
changes every hard link's mode; usage errors return 2.

**NFS behaviour.** After rm -rf (plus the directory heal) still fails, delete
looks for `.nfs*` under the PATH, finds holders from /proc/PID/fd links and
/proc/PID/maps (a running binary or loaded library has no fd), and from a
terminal asks `kill PID n (cmd; running t; holds k files)? [y/N/a/q]`: TERM,
then KILL only after a second yes (`a` = yes to all, including KILL). Never
offered: the calling shell ($PPID: reported as "this shell ... close that file
descriptor") and the script itself (it inherits the shell's fds -- the first
version offered to kill itself; tests caught it). Holders it cannot see are
reported as another host's or another user's. Without a terminal it reports
and returns 1. After kills it retries for up to 5 s (the client drops a .nfs
file on its last close).

**Gates.** `tests/env-delete` (T2, 86 checks): installs @envs + env-zsh into a
temp HOME and runs every case in bash, zsh and tcsh from the INSTALLED trees,
with NFS emulated by a fake rm (EBUSY for an open .nfs*), real holder
processes and a real PTY. `build/delete-nfs-check` (MANUAL, outside run-all
at the user's request -- kept to support work on the script; 19 checks): a real
kernel NFSv4.2 mount between two privileged containers
(`build/docker/almalinux8.10-nfs.Dockerfile`), EL8's bash 4.4 / zsh 5.5 /
tcsh 6.20; it first proves the kernel facts (rename, EBUSY, /proc paths, the
.nfs file going on close). Negative control: with the maps scan disabled the
running-binary case fails in all three shells. `tests/install-env-tcsh` checks
the copy is installed, executable and identical.

**Teardown trap, left behind once.** The first NFS probe ran server and client
in ONE container. On exit, the client's unmount (DESTROY_SESSION, hard mount)
lost its server and retries forever in D state: container `c27cacb6931b`
(image almalinux:8.10) stays "Up" with a D-state `rpc.mountd` until the host
reboots. Harmless otherwise; `docker rm -f` will not clear it. The real test
uses two containers and removes the client first (AGENTS.md, Testing tiers).

**Verification:** a full `run-all --container` was stopped at the user's
request after T1 and most of T2 -- 72 tests, 0 failures, including docs-sync,
env-shell-parity, env-bash-runtime, install-env-bash/-tcsh/-zsh and
env-delete. After moving the real-NFS check out of the suite: env-delete
86/86, docs-sync, env-shell-parity, installed-sizes/content-manifest --check,
and build/delete-nfs-check 19/19. Tier 3 was not run for this change (the
installer change is the tcsh copy only).

## 2026-10-31: GRC retired; linelight 2026.10.31 colours the shells

The user asked to remove GRC from the shells, add their own project
[smprather/linelight](https://github.com/smprather/linelight), and integrate it.
Plan: `docs/superpowers/plans/2026-10-30-linelight-replaces-grc.md` (untracked,
like the other plan files). Executed inline on main, four commits:

1. `3d8a1bc` **package** -- `linelight` 2026.10.31 (`kind: bin`, `@core-cli`),
   imported from the upstream release asset with `build/update-prebuilt` inside
   `build/build-shell`. No EL8 source build: upstream's release workflow now
   links against glibc 2.28 in almalinux:8, checks NEEDED and smoke-tests there
   (linelight#6). Asset sha256 `2a8b876d...c8eb1` (full hash in
   build/ADDING_BINARIES.md). **Upstream moved tag v2026.10.31** (3bcc76d ->
   71e5e7b) and replaced the asset in place when fixing #6, so the version
   string alone does not identify the bytes -- the hash does. New generic
   guards found on the way: `update-prebuilt` `SHA256_SIDECARS` (checks an
   asset against its published `.sha256` before extracting; the tool verified
   nothing before) and registry-integrity "every bin package's bins have a
   payload file" (a registry entry whose file never landed passed every gate).
2. `4933581` **GRC removed** -- the vendored `envs/bash/global/grc/` tree,
   tcsh's `grc-aliases.csh`, the rc blocks, `LOADOUT_CFG_ENABLE_GRC`,
   `colourify`, and the grc exclusions in ruff/gitleaks/docs-sync. A reinstall
   prunes the sealed GRC files an old install left (install-env-bash/-tcsh).
3. `dee66b0` **shells** -- bash/zsh/tcsh run `linelight init <shell>` at
   interactive startup behind `LOADOUT_CFG_ENABLE_LINELIGHT` (default 1).
   Wrapped: `df diff dig free lsblk ping ps sensors ss` (those on PATH; `ls`
   off, `log` never). Opt-outs: `LINELIGHT_INIT=0`,
   `~/.config/linelight/adapters.toml` (`disable = [...]`). Loadout's own `df`
   (--block-size=G) goes through `linelight run` only when the adapter wrapped
   df, so every opt-out reaches it. Gate: `tests/env-linelight` (T2).
4. `aa48027` **tcsh review fix** -- the adapter output is code the shell
   SOURCES; the first version wrote it to a predictable name in
   `$XDG_RUNTIME_DIR`, which tcshrc leaves pointing at a non-private dir when
   both private-dir checks fail (and a read-only runtime dir silently disabled
   colour). It now goes into a fresh 0700 `mktemp -d -t .loadout-linelight.XXXXXX`
   dir. RED first: `env-linelight` `ro-runtime/tcsh`.

**Coverage narrowed on purpose.** GRC wrapped ~45 commands; linelight profiles
only commands without adequate native colour, and upstream closed linelight#5
as "no bulk import of grc's list". `mount`, `ip`, `make`, `gcc`, `netstat`, ...
are no longer coloured. Anyone calling `colourify` from their own layer must
drop it.

**Upstream tcsh bug (filed as linelight#7, 2026-10-31).** linelight's
documented `eval "`linelight init tcsh`"` defines nothing: csh joins a quoted
command substitution into one line, so the adapter's `if ... then ... endif`
blocks fall apart (`Badly placed (.` interactively, silent under `tcsh -c`).
Upstream CI only tests `init tcsh > file; source file`. Loadout's tcshrc
sources the output from a file in a fresh private mktemp dir, which keeps
working whether or not upstream fixes the eval form; tests/env-linelight's
negative control (tcshrc switched to eval) fails `tty/tcsh`.

**Upstream issues filed this session** (all closed by the user, 2026-10-31):
linelight#1 `run`, #2 `run --stderr`, #3 `run --pty`, #4 `init` adapters,
#5 profile coverage (closed: no bulk import), #6 glibc-2.28 release asset.

**Verification:** full T1+T2 `All tests passed.` (1175 s) on
`dee66b0`; after the fix T1 (168 s) and every tcsh/env T2 test again; Tier 3
`run-all --container` `All tests passed.` (1509 s) on `aa48027` -- the
almalinux8.10 `--full` smoke ran the linelight probe (`OK (colour)`). Native
`tests/prebuilt-binaries`: 337 binaries OK (221 s). `build/verify-binaries
linelight` PASS (payload == upstream asset after strip+patchelf). Manual, in a
private tmux server, bash and tcsh: `ping` streams line by line and Ctrl-C
keeps the coloured summary. EL8 tcsh 6.20 runs the tcsh block (df wrapped, no
leftover temp dir). The user confirmed coloured `df` in their own shell.
Final review: self-review only (agents are spawned only on the user's
request); its one finding is commit 4.

**Then, same day:** `2a5909f` tmux-path-store 2026.8.26 -> 2026.10.4 (same
`--bash/--zsh/--csh` interface and shortcut set; upstream dropped the `v` from
its tags; the build image has no `uv`, so the payload's own is used -- command
in build/ADDING_BINARIES.md). Its new bash/zsh hooks run `cd -- "$dir"`, which
exposed `2624e36`: loadout's `cd()` took `--` as the target and offered to
create a directory named `--`, so cd0..cd9 silently went elsewhere (the ERR
trap's `cd -- "$last_cmd"` had the same bug). Fixed in bash and zsh; tcsh was
unaffected. Gates: env-bash-runtime / install-env-zsh `cd -- DIR`, live tmux
sd0/cd0/`cd -` in all three shells, and a final full `run-all --container`
`All tests passed.` (1757 s; EL8 smoke shows tmux-path-store 2026.10.4).

**Open:** pushed to origin/main on the user's go-ahead (2026-10-31). The
deployed shared tree (memory `reference-deployed-shared-tree`) is on hosts
this machine cannot reach: the user reinstalls it from main, BEFORE users pick
up the new env config -- the envs no longer carry GRC, and colour now comes
from the shared tree's linelight. The tcsh upstream prompt issue was posted
on the user's OK (2026-10-31): tcsh-org/tcsh#128, linking the user's own
2019 report #15 (closed 2021 for no response). The workaround in
`helpers/prompt-markers` stays either way.

## 2026-10-30 (5): remaining tcsh audit gaps closed

Every item in entry (3)'s "Still to do" list except 16 is now closed. Test-first
per item; the new assertions were observed failing (or the behaviour was
reproduced on a PTY) before the fix.

**Shell config (`envs/tcsh`):**

- **`rm`** (gap 1): the `rm -f` alias is gone from both bash and tcsh.
  `set rmstar` now asks before `rm *` (RT: three files survive `rm *` + `n`).
  `du`/`dum` moved to functions (bash) / `helpers/disk-usage` (tcsh), so
  `du DIR` no longer sends DIR to `sort` (gap 14).
- **Listing** (gap 3): `ls` is `helpers/ls-command`; `ls -1` always execs
  `/bin/ls -1`, everything else follows `LOADOUT_CFG_PREFERRED_LS`. eza has no
  `-1` and could print nothing on a non-tty.
- **Arity** (gap 11): `new`/`extract_rpm` are `helpers/new-file` /
  `helpers/extract-rpm`; no argument prints usage instead of csh's
  `Bad ! arg selector`.
- **Prompt switches** (gap 13): `sp1`/`sp2` EXPORT
  `LOADOUT_CFG_PROMPT_INCLUDE_HOST` in bash, zsh and tcsh. Under starship tcsh
  touches only the env var (starship overwrites `prompt`); without starship it
  also reassigns the lead/prompt. The custom.host module runs in a child shell,
  which is why the old shell-local assignment was inert.
- **PATH/NVM/TERMINFO** (gaps 5, 6): the prepend list now matches bash's final
  order, NVM_BIN included after the user dirs. A direct tcsh login resolves
  `$HOME/.nvm/alias/default` (or the newest installed version) through
  `helpers/nvm-bin` when no parent exported NVM_BIN. `TERMINFO_DIRS` is
  prefix:home, matching bash. `HOME` unset is recovered from passwd (gap 12)
  before anything uses it.
- **Interactive-only env** (gap 7): `EDITOR`/`VISUAL`/`GIT_EDITOR` moved inside
  the `$?prompt` block, matching bash's non-interactive environment.
- **GRC** (gap 4): the tcsh config uses its own `global/grc/bin` if one exists,
  else env-bash's `~/.config/bash/global/grc/bin`; the default enablement is no
  longer dead on a direct login.
- **Extended keys** (gap 15): `helpers/check-extended-keys` ports bash's
  Secondary-DA probe (cheap TERM/TMUX answers; never consumes pending input;
  exports 0 when it cannot tell). tmux now sees the same value from tcsh as
  from bash. The helper is a POSIX wrapper: the bash-only `read -t 0` /
  `read -d c -t 0.1` pair lives inside an explicit `bash -c` probe, with the
  exception documented in `global/helpers/README.md`; without bash it exits 1
  without probing rather than eating type-ahead.
- **Minor** (gap 17): `LESS_TERMCAP_*` captures one ESC byte instead of seven
  `/usr/bin/printf` forks; the starship block's inner `if` was re-indented.

**Installer (`loadout_main.py`):**

- `preserve_layers_from_symlink()` is now shared by bash, tcsh and zsh (gap 10).
  A symlinked `~/.config/{bash,tcsh,zsh}` is materialized with every
  corp/site/team/project/user layer copied across first.
- The retired `~/.cshrc` is pruned only when it is a symlink (gap 9). A regular
  user file is left alone; `--no-backup` can no longer make its deletion
  permanent.

**Tests:** `tests/install-env-tcsh` gains PTY assertions for rmstar, `ls -1`,
GRC, PATH/NVM/TERMINFO order, interactive-only EDITOR, HOME-unset startup,
`new`/`extract_rpm` arity, exported sp2, `du DIR`, the extended-keys probe
value, regular-`.cshrc` preservation and symlinked-layer preservation.
`tests/env-shell-parity` pins the new structure; `tests/env-bash-runtime` and
`tests/install-env-zsh` cover the shared `du`/`sp1`/`sp2` and zsh layer
preservation. `tests/env-tcsh-starship` strips the DA query from its raw PTY
capture (a real terminal consumes it; `script(1)` does not).

**Gates:** full T1 (`tests/run-all --fast`) passed in 173.9 s; full T1+T2
(`tests/run-all`) passed in 1168.5 s, including the new T2 assertions. The
changed shell paths were also smoked against EL8's tcsh 6.20 / bash 4.4 /
coreutils 8.30 in `loadout-smoke:almalinux8.10` (startup, PATH/NVM/TERMINFO,
`ls -1`, `du DIR`, sp2, `new` arity, rmstar, HOME-unset, extended-keys
cheap + probe paths). Targeted suites passed: `install-env-tcsh`,
`install-env-zsh`, `install-env-bash`, `env-tcsh-starship`,
`env-tcsh-prompt-resize`, `env-bash-runtime`, `env-shell-parity` (42/42),
`unit-install-steps` (64/64), `docs-sync`.

Open: the upstream tcsh issue draft (entry (4) item 4) still awaits the user's
OK.

## 2026-10-30 (4): follow-ups in progress -- lsd retired; next tcsh PREFERRED_LS, tcsh prompt vs tmux zoom

The review integration (items 1-10, tcsh audit) is committed and passed T1+T2
and Tier 3 (`92f9a6b`, `3447c5c`, `4bcf866`, `cae2787`). Then the user asked
for three changes, each its own commit, test first. Written so any agent can
finish if this session stops (rate limits).

**Step 1 -- DONE (this commit): lsd retired, `LOADOUT_CFG_PREFERRED_LS` takes
`eza` or `ls`.** lsd was never a loadout package (not in packages.json, no
payload binary); only the envs fell back to it. bash/zsh/tcsh now treat any
value other than `ls` as `eza` (silently -- startup must stay quiet), then fall
back to plain ls when eza is not installed. `LSD_ARGS` and every lsd branch are
gone. Found on the way: the shared `tree()` (envs/bash/global/aliases.sh) used
`command -v tree`, which finds the function itself, so a host without a tree
binary ran `command tree` and failed instead of `/bin/ls -R`; it now does a
real PATH search (`type -P` / zsh `whence -p`). New T2 test
`tests/env-ls-choice` (fake eza/lsd print markers; PATH is a symlink copy of
/usr/bin minus the real eza/lsd). Harness trap found: this host's
/etc/csh.cshrc appends /usr/bin to tcsh's path BEFORE ~/.tcshrc, putting the
real eza back -- the test's tcsh user config.csh re-pins PATH, and the plain
case requires GNU long format (`-rw-...`; eza prints `.rw-...`).

**Step 2 -- DONE: tcsh honors `LOADOUT_CFG_PREFERRED_LS`** (closes entry (3)
item 2). tcsh normalizes the variable at `envs/tcsh/global/tcshrc:176-178` and
sources `aliases.csh` later (`tcshrc:377`), but the listing block in
`envs/tcsh/global/aliases.csh` (`if ( -X eza ) ... else ...`) ignores it. Fix:
`if ( "$LOADOUT_CFG_PREFERRED_LS" == "eza" ) then` (the normalization already
guarantees eza is installed when the value is eza). RED first: in
`tests/env-ls-choice` change the final loop `for sh in bash zsh` to
`for sh in bash zsh tcsh` -- `prefer-ls/tcsh` must fail before the fix.
Then mark entry (3) item 2 CLOSED.

**Step 3 -- DONE except the upstream issue draft (item 4 below): tcsh
multi-line starship prompt survives tmux zoom/resize.** Landed as designed, with
two refinements: the cache path is an env var (`LOADOUT_TCSH_PROMPT_CACHE`, set
once by tcshrc) instead of a helper argument -- csh cannot nest the quotes an
argument inside the precmd's backticks would need -- and it is named per tty
(`loadout-tcsh-prompt.pts-N`, `$$` only without a tty) so the runtime dir holds
one file per terminal, not one per shell. Verified on tcsh 6.24 and on EL8's
tcsh 6.20 (`loadout-smoke:almalinux8.10`, payload starship, no tmux/tput there:
prompt-redraw's printf clear fallback is what runs). Original plan:
Root cause (verified on a private tmux socket): tcsh renders `\n` inside
`prompt` by padding the row with spaces until the terminal autowraps, i.e. a
SOFT wrap. tmux (and any terminal that reflows on resize: WezTerm, kitty, VTE,
Windows Terminal) re-wraps soft-wrapped lines when the width changes, so the
two/three prompt lines merge (`~ ... ❯` on one row) and scramble on unzoom.
Minimal repro: `set prompt = "AAA\nBBB> "`, then `tmux capture-pane -J` shows
`AAA ... BBB>` joined. bash is unaffected (PS1 newline is a real LF); the
hand-rolled tcsh fallback prompt is single-line. Chosen design (user approved
"option a" + Ctrl-L binding; NOT vendoring tcsh -- loadout ships no tcsh and
users' login shell is the system one):
1. `envs/tcsh/global/helpers/prompt-markers`: split starship's output --
   every line but the LAST goes to STDERR as real output (raw SGR, real
   newlines, same path-colour and python-symbol rewrites, NO `%{ %}`) and is
   also written to a cache file named by its first argument; only the LAST
   line goes to STDOUT with `%{ %}` markers and no `\n`. The precmd alias in
   `global/tcshrc` (~line 454) passes the cache path, e.g.
   `"$XDG_RUNTIME_DIR/loadout-tcsh-prompt.$$"` (XDG_RUNTIME_DIR is already a
   private dir by then, tcshrc ~262-269).
2. In the starship-claimed branch of `global/tcshrc`, bind Ctrl-L:
   `bindkey -c ^L 'clear; cat "<cache>"'` (verified: `bindkey -c` runs the
   command, then tcsh redraws the prompt with the typed input intact).
   Check that `$$`/`$XDG_RUNTIME_DIR` in the bound command expand at key press.
3. Tests: T1 in `tests/env-tcsh-starship` -- feed a fake 3-line starship
   output to prompt-markers; assert stdout is one line with markers, stderr
   holds the two upper lines, the cache file matches. T2 in
   `tests/install-env-tcsh` (or a new test) -- a PRIVATE tmux socket
   (`tmux -L <name>`, NEVER the default server; see ~/.claude/CLAUDE.md), tcsh
   with starship, resize/zoom the pane, `capture-pane -J` must never join the
   prompt lines; Ctrl-L must bring the upper lines back. Verified manually so
   far on tcsh 6.24 only -- also check EL8's tcsh 6.20 in the
   `loadout-smoke:almalinux8.10` container.
4. Draft (do NOT post without the user's OK) an issue for tcsh-org/tcsh: prompt
   `\n` is emitted as padding + autowrap, which breaks under reflowing
   terminals; minimal repro above. Posted 2026-10-31 on the user's OK as
   tcsh-org/tcsh#128 (draft:
   `docs/superpowers/plans/2026-10-30-tcsh-upstream-issue-draft.md`, untracked).

**Result:** steps 1-3 committed (`02fb075`, `6fcace1`, `57a1844`); full T1+T2
on the final tree passed (81 tests, 1164 s, both new tests included). Nothing
pushed. Open: the upstream issue (item 4 above) and, from entry (3), the
remaining tcsh audit gaps.

**Per-step gates:** T1 (`TMPDIR=/var/tmp tests/run-all --fast`) plus the
touched T2 tests; regenerate `payload/installed-sizes.json` then
`.content-manifest` whenever envs/ or payload/ change; full T1+T2 once after
step 3. Never run two `tests/run-all` in this repo at once (they share
`.loadout-deps.log`). Timing rows run-all appends to
`assurance/release-timings.tsv` go in a final `chore:` commit.

## 2026-10-30 (3): tcsh env audit -- recommended fixes landed; remaining gaps recorded

Operator report: an obvious tcsh support problem in `envs/`. Read-only scan
(TcshEnvAudit / CrossEnvAudit / InstallerDocsAudit scouts + native PTY/tmux
repros) found the completion file using POSIX fd redirection, the `g` alias
family unusable, `unalias *` deleting site aliases, and a starship fallback
that could not be reached. Operator then asked for the recommended fixes only.

**Landed (uncommitted; working tree):**

- **Completions** (`envs/tcsh/global/completions.csh`): a `/` inside a
  `complete` list command terminates the spec, and `2>&1 |` is an "Ambiguous
  output redirect". Removed all `2>` from wordlists; added slash-free helper
  aliases `_lo_complete_{git_branches,loadout_packages,just_recipes}` backed by
  new `helpers/{git-branches,loadout-packages,just-recipes}`; module/`ml` use
  csh `|&`. `loadout-packages` also skips wrapped `loadout list` rows, which
  otherwise emitted a literal `+` completion.
- **`g` family** (`aliases.csh`): `g`/`sg`/`gpy`/`gtcl` now store
  `--glob='\\!*.snapshot*'`. The old single `\!` stored `!*`, which alias
  expansion consumed as the argument list, so rg never received a pattern;
  `gv`/`gf` failed with it. Verified with real rg and a fake-rg argv log.
- **Site aliases** (`envs/tcsh/tcshrc`): removed `unalias *`. `/etc/csh.cshrc`
  runs first and defines Environment Modules' `module`/`_module_raw`/`ml`,
  gawk helpers and site `precmd`; the blanket unalias deleted them. Loadout
  aliases still override same-name site aliases. Verified gawk aliases and a
  synthetic `module` survive.
- **Starship** (`global/tcshrc`): `LOADOUT_CFG_ENABLE_STARSHIP` is checked with
  `is-truthy`; the binary with `-X` (missing `which` writes its not-found text
  to STDOUT and was eval'd); the flag is set only after `starship init tcsh`
  succeeded and installed a `precmd` containing `STARSHIP_PATH`. This makes
  `ENABLE_STARSHIP=0` and a starship-less host reach the hand-rolled prompt
  silently instead of printing `Unmatched '`'`/`STARSHIP_PATH`/`Faulty alias`.
- **`LESS_TERMCAP_*`** (`global/tcshrc`): store real ESC bytes via
  `/usr/bin/printf`; csh `setenv` does not interpret `\033` and less does not
  process escapes, so the old values rendered as literal text.
- **`path_remove`/`path_trim`** (`aliases.csh` + new `helpers/path-remove`,
  `helpers/path-trim`): a csh alias executes only the first iteration of an
  inline `foreach`, so `path_remove /bin` dropped three of four entries and
  removing the first entry emptied PATH; `path_trim` aborted. The helpers print
  `set path = (...)` and are eval'd; both handle spaces.
- **`cd`/`latest`** (`aliases.csh` + new `helpers/cd-command`): `\!*` inside a
  double-quoted backtick nested quotes, so `cd "dir with space"`/`latest "dir
  with space"` failed with `Unmatched '`'`. `cd` now evals a helper that prints
  `chdir "<quoted>"`; `latest` evals unquoted. `cd -`, no-arg `cd`, `cd FILE`,
  `cdd`/`cdp`, and `cwdcmd` listing still work.
- **tmux** (`envs/tmux/tmux-global.conf`, `global/tcshrc`): removed the
  unconditional `set -g default-shell /bin/bash` (tcsh logins got bash panes
  with `SHELL=/bin/bash`). tcsh now exports `EXTENDED_KEYS_SUPPORTED=1` for
  kitty/alacritty or when an existing tmux server has `extended-keys on` (and
  mirrors an explicit `off`); the config forces `extended-keys off` only on an
  explicit `0`. Unset no longer disables it server-wide. Live tmux 3.8 verified.
- **Docs**: `AGENTS.md` tcsh paragraph (starship pin, absent list, `!` rule,
  site-alias preservation), `envs/tcsh/README.md` (ownership/entrypoint, site
  aliases, ESC values, OSC 7 table, alias caveat), `global/config.csh` (stale
  `starship-tcsh.toml`), `docs/TMUX.md` (shell/extended-keys policy).

**Regression coverage added:**

- `tests/env-shell-parity` (T1): no POSIX fd redirection in csh-syntax files;
  no entrypoint `unalias *`; `EXTENDED_KEYS_SUPPORTED` present; starship switch
  tested by value; rg glob double-escaped; path helpers used; tmux does not pin
  bash and only disables on explicit 0.
- `tests/install-env-tcsh` (T2): site-alias survival; `g` argv; path helpers;
  quoted `cd`/`latest`; real `LESS_TERMCAP` ESC bytes; `ENABLE_STARSHIP=0`;
  starship-less startup; git/module TAB parse; extended-keys value.
- New helpers added to the helper-executable assertion.

**Verification:** `tests/run-all --fast` -> Tier 1 passed (status 0, ~174 s:
`env-shell-parity` 35/35, `env-tcsh-starship` 31/31, `docs-sync`,
`content-manifest`, `installed-sizes`, `verify-manifest-export`). Regenerated
`payload/installed-sizes.json` and `.content-manifest` in `build/build-shell`;
all three `--check` gates pass. Manual PTY/tmux smokes cover the fixed paths.
Per operator instruction, no Tier-2 test was run after the interjection;
`tests/install-env-tcsh` had passed earlier with the new assertions.

**Still to do (not in the recommended fix set):** ALL CLOSED 2026-10-30 in
entry (5) above, except 16 (integration bookkeeping). The list is kept as the
audit record.

1. `aliases.csh:179` `alias rm 'rm -f'` defeats `set rmstar` in `tcshrc:191`:
   `rm *` no longer asks for confirmation. Fix by dropping `-f` or wrapping
   confirmation.
2. CLOSED 2026-10-30 (entry (4) step 2): the tcsh listing aliases (and `tree`)
   follow `LOADOUT_CFG_PREFERRED_LS` like bash.
3. `aliases.csh:77-82`: `ls -1` is not special-cased to `/bin/ls -1`; it emits a
   colored long listing and can be empty on a non-tty.
4. `tcshrc:316-322` + `grc-aliases.csh:20-21`: GRC is enabled by default but
   dead on a direct tcsh login -- `envs/tcsh/global` ships no `grc/bin`, and
   the bash env's `~/.config/bash/global/grc/bin` is not added. Ship a copy or
   add the bash path when present.
5. `tcshrc:52,86-103`: PATH order differs from bash (`NVM_BIN` first vs eighth;
   cargo/go/venv/opencode/node_modules order) and `TERMINFO_DIRS` is
   `home:prefix` vs bash's `prefix:home`. The comment claiming a match is false.
6. `tcshrc:86-93`: `NVM_BIN` is only added when already exported; a direct tcsh
   login never sources `nvm.sh`, so nvm node/npm are absent. Resolve
   `~/.nvm/versions/node/*` or document the gap.
7. `tcshrc:141-177`: non-interactive tcsh exports `EDITOR`/`VISUAL`/
   `GIT_EDITOR`; non-interactive bash does not. Align with bash or update the
   "same here" comment.
8. CLOSED 2026-10-30: lsd support was retired from every env, so `LSD_ARGS` is
   gone.
9. `loadout_main.py` `_install_env_tcsh`: `remove_if_exists` deletes a **regular**
   `~/.cshrc`, not only a loadout link; docs say links are pruned. Backups cover
   it, but `--no-backup` makes the deletion permanent. Remove only symlinks or
   update the docs.
10. `loadout_main.py` `_install_env_tcsh`: a symlinked `~/.config/tcsh` is
    unlinked and recreated without preserving corp/site/team/project/user
    layers. Bash has `preserve_bash_layers_from_symlink`; tcsh does not. Port it
    (zsh has the same gap).
11. `aliases.csh:121,195`: `new`/`extract_rpm` with no argument fall through to
    command lookup (`...: Command not found.`) instead of an arity error.
12. `tcshrc:29`: with `HOME` unset, every non-interactive tcsh prints
    `HOME: Undefined variable.` and the assignment aborts.
13. `aliases.csh:211-212`: under starship, `sp1`/`sp2` set `prompt`/
    `loadout_prompt_lead`, which starship overwrites; `sp2` does not export
    `LOADOUT_CFG_PROMPT_INCLUDE_HOST`, so the host module never sees it. Bash's
    pair is similarly inert.
14. `aliases.csh:183-184`: `du DIR` puts `DIR` after the pipe, so it becomes a
    `sort` operand; shared with bash (`envs/bash/global/aliases.sh:234`).
15. Extended-keys coverage is cheap-check only: a bare xterm tcsh login leaves
    `EXTENDED_KEYS_SUPPORTED` unset, so tmux leaves `extended-keys on` but does
    not add `terminal-features xterm*:extkeys`. A full port of bash's
    `check_extended_keys` DA probe is the remaining parity step.
16. DONE at integration: the new helpers are committed with this change and
    both manifests regenerated; the concurrent items 1-10 work went in as its
    own commits.
17. From the integration review (minor): the interactive startup now spends
    seven `/usr/bin/printf` forks on `LESS_TERMCAP_*`; one captured ESC would
    do. The starship block's new inner `if` was not re-indented (cosmetic).

## 2026-10-30 (2): independent review items 4-10 fixed

User asked to fix the seven items left open by the entry below. Test first, RED
observed per item:

4. Own group-writable private dirs (0775 from RHEL's UPG umask 002) are now
   tightened to 0700 instead of refused, in `loadout_private_dir` (bash/zsh),
   the tcsh `private-dir` helper, `global.paths.private_dir` and both Python
   checks. A foreign owner or a symlink is still refused; the group of one's
   own dir is one's own group, so the stale mode is ours to remove.
   `tests/unit-private-state`, `tests/env-private-dirs` (loose-dir cases; the
   symlink case remains the hostile one). NARROWED at integration (review:
   `docs/superpowers/plans/2026-10-30-items-4-10-fix-report-review.md`,
   untracked): accepting ANY own dir
   trusted content a co-tenant could have planted while it was writable (the
   eza copy the bash wrapper reuses, .pyc files, pending.json). Now other
   write is refused, and group write is accepted only when the dir's group is
   the user's private group (name == user); both left untouched when refused.
   Tests: own 0777/0757 refused, shared-group 0775 refused (chgrp to a
   supplementary group; skips without one), UPG 0775 tightened.
5. Cold bootstrap takes an atomic `mkdir .loadout-bootstrap.lock` claim; a
   second first run waits for the published `.complete` instead of racing the
   `rm -rf`/`mv` (the loser used to delete the tree the winner exec'd from).
   Temp dirs are `.loadout-bootstrap.tmp.<host>.<pid>`; the sweep PID-checks
   only this host and removes a foreign/legacy temp only after a day, so an
   NFS clone's live bootstrap is never killed by a local `kill -0`. Reclaiming
   a stale claim is itself serialized by `.loadout-bootstrap.lock.reclaim`;
   the reclaimer re-reads the owner after acquiring it, so two waiters cannot
   both decide the same lock is stale and one cannot delete the fresh claim the
   other just re-acquired. A same-host live PID is never stale regardless of
   age; a foreign/ownerless claim is stale after 5 minutes. A crashed reclaimer
   fails closed after 2 minutes with a removal hint. `tests/shim-bootstrap`
   covers the held claim, stale claim, host-aware sweep, and a two-waiter
   stale-claim race (slow rm/tar widen the old delete-fresh-lock window).
   Integration fix: the sweep matched this host's temps by PREFIX, so a temp
   from host `<host>.lab` was PID-checked locally; everything after `<host>.`
   must now be digits (shim-bootstrap case).
6. `_place_staged_tree` refuses a file/symlink that would replace an existing
   real directory (`InstallRefused`) instead of rmtree'ing it, matching the
   loud failure `extractall` produced. `tests/unit-install-steps`.
7. `walk_recommends` drops a recommended package whose own hard deps are
   skipped or disabled, instead of adding it and letting the next
   `walk_depends` raise for a package the user never named.
   `tests/unit-resolver`.
8. `bashrc` exports `PIP_REQUIRE_VIRTUALENV`, `PYTHON_KEYRING_BACKEND`,
   `PYTHONPYCACHEPREFIX` and `EGL_LOG_LEVEL` before its non-interactive
   return, matching zsh/tcsh
   for `ssh host cmd` and `bash -l` jobs. `tests/env-private-dirs`
   non-interactive cases. Follow-up (not done): the finding was the COST --
   the tcsh `private-dir` helper still forks `sh` (~3 ms measured) on every
   startup, non-interactive `tcsh -c` included; tcsh builtins (`-d`, `-l`,
   `-o`, `-P`, `$user`/`$group`) could do the same check fork-free.
9. Backup stores an absolute in-HOME symlink relative using the LEXICAL link
   text, so a `~/.config` symlinked outside HOME no longer yields an absolute
   entry (`AbsoluteLinkError`) or `../outside`; restore copies top-level
   entries individually so a backup dir can land on a symlinked `~/.config`.
   Reproduced the extraction failure on HEAD. `tests/snapshot-restore`.
   Integration fix: the new helper dropped the `isabs` guard, so a RELATIVE
   link text was resolved against the CWD -- `cmd_install` chdirs to the
   install root (inside HOME by default), and a full install stored
   `~/.bashrc -> .local/share/loadout/.config/bash/bashrc`, dangling after
   restore. Relative texts are stored verbatim again
   (`tests/unit-install-steps`, backup run from the install root).
10. `paths.lua`: `M.data`'s doc block is back on `M.data`; `private_dir` has
    its own. Comments only; the nvim case in `tests/env-private-dirs` loads
    the file.

Docs synced: AGENTS.md (shim, backup, resolver, shell startup, private dir,
atomicity, gitignore), docs/ARCHITECTURE.md, docs/BASH.md,
envs/{bash,tcsh}/README.md, `.gitignore` (`.loadout-bootstrap.lock/`). The
daemon script is payload, so `build/gen-installed-sizes` and
`build/gen-content-manifest` were rerun (the first `run-all --fast` correctly
failed both sync gates before that).
Verification: the focused tests above, `tests/env-shell-parity`,
`tests/install-env-{bash,tcsh}`, `tests/prompt-no-rc`, a 10-way concurrent
cold-bootstrap stress run (10/10 STUB, one cache, no temp/lock left),
`tests/run-all --fast`, `ruff check`, `sh -n loadout`, bundled `py_compile`.
Working tree only; nothing committed in this session. Per-item RED/GREEN
evidence, changed symbols, residual risks and the advisory race analysis are
recorded for external review in
`docs/superpowers/plans/2026-10-30-items-4-10-fix-report.md` (untracked, like
the review plan).

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

