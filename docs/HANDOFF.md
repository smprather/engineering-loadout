# Current Handoff

Last updated: 2026-08-03 (deep review of the xephyr + xdesk package; 12 findings fixed).

## Currency sweep, 2026-08-03 -- what moved, what did not, and why

Ran the sweep the previous entry said was owed. It cleared a good part of the
debt and turned up two destructive bugs in `./update` itself, both now fixed.

**Bumped and verified** (15 packages): `rg` 15.2.0, `fzf` 0.74.2, `uv` 0.12.1,
`ruff` 0.16.1, `ty` 0.0.65, `just` 1.57.0, `lazygit` 0.63.1, `btm` 0.14.7,
`amux` 0.0.20, `agent-deck` 1.11.0, `biome` 2.5.6, `nodejs` 26.6.0,
`fish` 4.8.1, `numr` 0.8.0, `flameshot` 14.0.0. Plus `text-serdes` -> `e624d2d`
and the YARA-Forge ruleset.

**Two `./update` bugs, both silent, both would have shipped:**

- `./update env-nvim` repacked *this box's* `~/.local/share/nvim/lazy` over the
  plugin stash: 328 MB of bare mirrors replaced by 47 MB of flat plugin dirs
  that lazy cannot clone from. The stash is gitignored *and* excluded from
  `.content-manifest`, so there was no baseline to diff and no gate to fail;
  recovery needed `./fetch-stash` against a published release.
- `./update nodejs` with no `--tag` runs `nvm install --lts` and bundled the
  build box's own v26.2.0, stamping the registry *backwards* from 26.5.0. A
  bare `./update` -- what the procedure told you to run -- did this.

Both are fixed, and `./update` now hard-errors on any version that goes
backwards (`--allow-downgrade` to override).

**Left undone, deliberately** -- the remaining packages are all source builds
and this was cut as a "ship what is verified" release rather than claiming a
class C it did not meet:

- `vim`/`gvim` 9.2.0901 and `octave` 11.3.0. **`build-gvim.sh` and
  `build-octave.sh` take no `--tag`** and want a source checkout you supply --
  CLAUDE.md's claim that all `build/build-*.sh` enforce `--tag` is wrong for
  these two.
- `htop`, `rsync`, `xsel`, `yank`, `yara`: **no build script and no
  `ADDING_BINARIES.md` note at all.** Bumping them means authoring the
  procedure first, which the repo mandates anyway.
- `tree-sitter` 0.26.11 and `fresh` 0.4.6: upstream prebuilts need GLIBC 2.39
  and 2.35 against EL8's 2.28, so both become EL8 source builds.
- `gnuplot` 6.0.5, `jupyterlab` 4.6.2 (wheel closure).
- **`rust-crate-store` is stale.** fish 4.8.1 only built after bypassing the
  offline store with a fresh `CARGO_HOME`, because upstream added
  `fish-fluent`/`unic-langid`. The shipped binary is fine but that build is no
  longer offline-reproducible, and the same wall is waiting for every other
  Rust package. Refreshing the store is the real fix and should come before the
  next Rust bump.

`pdftotext` stays pinned (poppler >= 23.01 needs freetype >= 2.10; EL8 has
2.9.1).

**Also fixed here:** the README package table finally has a generator,
`build/gen-readme-table`, gated by `--check` in Tier 1. It found 16 stale rows
on its first run. That was failure-catalogue entry 8, open since the table was
last found carrying 30 wrong versions -- the instruction to "regenerate from the
registry" had never had a tool behind it.

## Release debt carried by the xephyr release (2026-08-03) -- SUPERSEDED, see above

The xephyr release is **class C** by the rules in `docs/RELEASE.md` §0
(`payload/packages.json` group membership changed: `@gui-suite` gained
`xephyr`), but it was cut with §2 **deliberately deferred**. This is a recorded
deviation, not an oversight, and the debt is real:

- **28 packages are behind upstream** as of this date. Four are build-class and
  need `build/build-<tool>.sh` on this EL8 box: `fish` 4.8.0 -> 4.8.1,
  `vim`/`gvim` 9.2.0782 -> 9.2.0901, `octave` 11.1.0 -> 11.3.0. The rest are
  download-class one-liners. Re-derive the current list with
  `build/check-versions --outdated-only` and `./update --list-outdated` --
  do not trust this snapshot.
- **`yara` itself is behind** (4.5.5 -> 4.5.8) and `./update yara-rules` was
  **not** run.
- **The ClamAV signature DB was 17 days stale** (`daily.cld` dated 2026-07-17)
  when the release scan ran. `sudo freshclam` needs sudo and was not run. Per
  `docs/RELEASE.md` §2b a scan against stale signatures is a green light that
  means nothing -- so treat this release's CLEAN verdict as weaker evidence than
  usual.

What *was* fully gated: Tier 1 + Tier 2 (24/24), `tests/prebuilt-binaries`
(264/264), and Tier 3 on stock AlmaLinux 8.10 (`--full` 257 OK / 7 skipped,
`--dynamic` 10/10). The class C **container** requirement was met; the currency
and security-data requirements were not.

**The next release should be a real class C** and clear all of the above before
anything else. If you are reading this while planning a "quick" release, that is
exactly the situation the class rules exist for.

## Deep review of xephyr + xdesk (2026-08-03)

Reviewed the uncommitted xephyr work end to end against a real staged install.
Twelve findings, all fixed. Re-verified after the payload rebuild: Tier 1 + Tier 2
**24/24**, `tests/prebuilt-binaries` **264/264**, and Tier 3 on stock
AlmaLinux 8.10 -- `--full` **257 binaries OK (7 skipped)** and the network-isolated
`--dynamic` pass **10/10**. `Xephyr`/`Xephyr.bin` skip on `libGL.so.1` (host GLVND
dispatcher), alongside the existing flameshot / nedit-ng / nvim-qt skips; that is
the documented host contract, and it is the wrapper-sibling change in
`tests/prebuilt-binaries` doing its job -- before it, the `bin/Xephyr` wrapper
was exec-probed and returned 127 in the GL-less container.

**The one that mattered: `xdesk --keep` left a nested X server with no access
control.** `cleanup()` removed the state dir unconditionally, including under
`-k`, and that dir holds the MIT-MAGIC-COOKIE file passed to Xephyr with
`-auth`. Reproduced 3/3: after `xdesk -k` exited, `DISPLAY=:10 xdpyinfo` with no
cookie at all returned the vendor string. On a shared farm node that is exactly
the keystroke exposure the auth block exists to prevent. (The second failure
mode is milder but still fatal to the feature: when clients *had* connected, auth
stayed enforced but the cookie file was gone, so nothing new could ever attach.)
`cleanup()` now keeps both the server and its state dir under `-k` and prints
the display, pid, `XAUTHORITY` path and the `kill`/`rm -rf` disposal command.
`tests/install-xdesk` asserts it: cookie-less connection refused, cookie
connection accepted, state dir retained, then tears the server down itself.

**Second-worst: the nested session inherited the outer compositor's Wayland
environment.** `WAYLAND_DISPLAY` and `QT_QPA_PLATFORM=wayland` passed straight
through, and GTK/Qt prefer Wayland whenever it is set -- so apps launched inside
the nest rendered on the **outer** desktop. This repo's own WSLg guidance to set
`QT_QPA_PLATFORM=wayland` guaranteed it. `xdesk` now unsets `WAYLAND_DISPLAY` and
exports `GDK_BACKEND=x11` / `QT_QPA_PLATFORM=xcb` / `XDG_SESSION_TYPE=x11` for
the session.

**Provenance was half-pinned.** `--tag` pinned the Xephyr RPM while the six
support libs were `cp`'d out of the build box's `/usr/lib64` -- the exact
build-box-masking shape the closure guard next to it was written to catch. They
now come from their own downloaded RPMs (`libXdmcp`, `libXfont2`, `libfontenc`,
`libxcb`), resolved *within* the extracted tree (a bare `readlink -f` on an
absolute symlink would fall back to the host root and silently reintroduce it).
`--tag` is now the **full version-release** (`1.20.11-28.el8_10.3`) matched
exactly, because the release field is where Red Hat's CVE backports live and a
bare `1.20.11` reads as a 2021 X server; `payload/packages.json` records the same
NVR and the build fails if they disagree; every consumed RPM NVR is written to
`build/xephyr/PROVENANCE`. This matters more than usual here because the package
is deliberately absent from `farm-versions`/`check-versions`, so no currency
sweep covers it.

**A dead assertion.** `tests/install-xdesk` guarded its orphan check with
`pgrep -x Xephyr`, which never matches -- the process name is `Xephyr.bin`
(`bin/Xephyr` is a wrapper that `exec`s it), so the check had never run. Also,
the test rewrote `HOME` without carrying `XAUTHORITY`, which would have failed
on any host whose outer display uses cookie auth -- i.e. the NoMachine/GDM hosts
this package exists for. It passed only because WSLg has no outer auth at all.

Smaller: `XDESK_SESSION=" "` died with a `set -u` "unbound variable" instead of
an error message; `--size` accepted `0x0` and `1x2x3`; dead `status=$?` after a
`set -e` exec; the build script's header still said "five" sonames and omitted
`libfontenc` from the bundled list -- the very lib whose omission shipped broken;
`CLAUDE.md` had no xephyr/xdesk coverage at all while every comparable package
has a behavior section; and the `Xephyr` wrapper's exported `LD_LIBRARY_PATH` is
inherited by the host helpers Xephyr forks (`xkbcomp`), which is benign on EL8
but is now recorded in a comment.

## xephyr + xdesk (2026-08-02)

New `xephyr` package (`bin`, non-optional, in `@gui-suite` -> `@shared` ->
`@engineering-loadout`): Xephyr `1.20.11-28.el8_10.3` shanghai'd from the EL8
AppStream RPM, plus an `xdesk` launcher. **Uncommitted.**

The problem it solves: on a NoMachine host the desktop is fixed by root-owned
`/usr/NX/etc/node.cfg`, which hardcodes
`DefaultDesktopCommand "... gnome-session --session=gnome"` rather than
`/etc/X11/xinit/Xsession default` -- so the usual per-user `~/.xsession` hook
does not apply and there is no no-root way to change the session. A nested X
server needs none of that. Xvnc was rejected deliberately: it opens a listening
port (590x), Xephyr binds no network socket.

Verified by hand on the dev box: full nested XFCE 4.16 session (xfwm4, panel,
xfdesktop, Thunar, xfsettingsd), clean Logout. **Nested GNOME does not work** --
`gnome-shell` 3.32 dies with `this._userProxy.Display is null` in
`loginManager.js` because it asks logind for a graphical session that a nested
display does not have. Not a GL problem, not fixable from our side; run a WM or
a non-GNOME session inside the nest.

Three things worth remembering:

- **The clean container was the only gate that caught the real bug.** Tier 1 and
  Tier 2 were both green while `libfontenc.so.1` was missing from the payload.
  It is a dependency of *bundled* `libXfont2`, not of the binary, so a closure
  check that walked only the binary never saw it -- and the build box has the X
  libs installed, so nothing local could. The guard in `build/build-xephyr.sh`
  now walks the binary **and every bundled lib**, and immediately found a second
  one (`libfreetype.so.6`, already owned by `gui_libs`, so a depends not a
  bundle). Textbook build-box masking, same shape as the NSS/firefox incident.
- **`mesa3d_libs` already owns `libdrm.so.2` and `libxshmfence.so.1`** at the
  same `lib64/` path, so `xephyr` declares it as a `depends` rather than
  duplicating them. Two packages owning one path is an install hazard. It costs
  nothing: `mesa3d_libs` is non-optional already.
- **`tests/prebuilt-binaries` could not skip wrapper scripts.** `bin/Xephyr`
  (POSIX sh) cannot be ldd-checked, so it was exec-probed in the GL-less
  container and returned 127 while `bin/Xephyr.bin` skipped correctly. The loop
  now resolves a non-ELF `bin/<name>` to its `bin/<name>.bin` sibling for the
  host-`.so` skip decision **only** -- anything missing that is not
  host-required still falls through to the exec probe, so the change can add
  skips but never mask a failure. This helps every wrapper+`.bin` package.

`tests/install-xdesk` is new in Tier 2 and covers what no headless gate can:
nested display comes up at the requested size, a cookie-less connection is
refused (an unauthenticated nested server is readable by any other user on a
shared farm node), and the server plus its state dir are gone afterwards. It
**skips** when `$DISPLAY` is unset. Its predecessor bug is the reason it exists:
`xdesk` first waited for `/tmp/.X11-unix/X$N` and timed out against a healthy
server, because a host whose `/tmp/.X11-unix` has the wrong mode (WSLg, and
hardened hosts) makes Xephyr bind **only** the Linux abstract socket.

No `build/farm-versions` entry on purpose -- X servers of this vintage reject
`-version` and the stripped binary carries no version string, so every strategy
would report a permanent gap.

## Deep review (2026-07-25)

A full consistency/lint/docs pass. Everything below is landed and Tier 1+2 green
(23/23). The two findings worth remembering:

- **`@engineering-loadout` had silently lost 9 env bundles.** Commit `e3f4857`
  narrowed `@envs` from "every non-optional env package" to "env-bash only". The
  curated group listed `@envs` as a member and was never edited, so it inherited
  the narrowing: `env-nvim`, `env-vim`, `env-tmux`, `env-helix`, `env-st`,
  `env-zsh`, `env-editorconfig` and `env-pip` all vanished from the headline
  `./loadout install @engineering-loadout`. Since the nvim plugin/parser phases
  gate on `env-nvim`, that install shipped the 328 MB stash and 251 MB of parsers
  while writing no nvim config and seeding no `lazy/`. The group now lists its ten
  env packages **explicitly** rather than via `@envs`, so a future redefinition of
  `@envs` cannot silently re-narrow it. Lesson: a group that references another
  group inherits every future redefinition of it, including the ones nobody
  connected to this group.
- **Six scripts declared `#!/usr/bin/env python3` but contained PEP 758
  (`except A, B:`) syntax**, which only parses on 3.14: `build/check-versions`,
  `build/farm-versions`, `release`, `scan-for-malware`, `strip-all-elf-binaries`,
  `tests/prebuilt-binaries`. Stock EL8 `python3` is 3.6.8, so all six were dead
  on a clean box and worked here only because `~/.local/bin/python3` is 3.14 --
  textbook build-box masking. All six now say `python3.14`.

Lint infrastructure was the root enabler and is now fixed:

- `ruff.toml`'s excludes were all **pre-reboot paths matching nothing**, so
  `ruff check .` reported 3363 errors (all vendored) and was unusable; and
  `select = ["I", "UP"]` **replaced** ruff's default set, silently disabling
  pyflakes entirely. Excludes repointed (plus the vendored `grc` tree),
  `F,E4,E7,E9,B` enabled, `E402` ignored for the deliberate post-`pwd` imports.
- `tests/run-all` linted exactly **one** file, behind `if command -v ruff` -- a
  missing ruff was a silent skip. It now lints and `py_compile`s every
  first-party Python file and treats a missing ruff as a hard FAIL. This gate is
  what caught the remaining strays (`fetch-stash` B904, `import-nodejs` E741).
- `ty` is wired up but deliberately **advisory, not a gate**. All 11 diagnostics
  on `loadout_main.py` are proven false positives (vendored `rich`/`rich_click`
  lack type info; `_progress_task` is guarded via a correlated variable ty cannot
  narrow). Documented in `ty.toml` with reproduction commands. **Do not add
  blanket `[rules]` suppressions to make it go green** -- an investigation was
  first "fixed" that way and reverted.

Also fixed: `./update` never regenerated `.content-manifest` after mutating
`payload/` (Tier 1 failed on drift as a result) -- now automatic on every
payload-mutating path plus all three guidance printers; `./update tmux-plugins`
cloned a commented-out `@plugin` line (unanchored `re.search`); two writers of
`assurance/downloads.log` disagreed on date format (now ISO-8601 UTC);
`vercomp` glob-matched its RHS; a duplicated unreachable gate in
`install_nvim_lazy_update`; README's package table had 30 stale versions and 6
missing packages (regenerated from the registry, 122 rows, now exact).

tmux plugins are now genuinely commit-pinned: `envs/tmux/vendor/plugins.lock`
exists with 4 pins (the fixed regex correctly excludes the disabled
`tmux-yank`). `docs/SECURITY.md` had claimed this pin for some time while the
lockfile had never been committed.

## Dependency bumps (2026-07-25)

- **parity-plot v0.5.0 -> v0.6.0** (`e98f08fecb7f250af508e0d81c9c94349cc6b1ea`).
  Two things made this a non-routine bump:
  - **The patch stopped applying.** Upstream re-sorted imports, breaking the
    context of the patch's `__version__` hunk. That hunk was always redundant --
    `build-parity-plot.sh` stamps the real tag into `parity_plot/__init__.py`
    with a `count != 1` assertion right after applying the patch, so the hunk
    set `0.0.0` only to be immediately overwritten. The patch is now a **single
    hunk** (`include_plotlyjs="cdn"` -> `True`, at line 574). Fewer contexts,
    fewer false failures on the next bump.
  - **v0.6.0 is a breaking CLI change**: TOML-only. `parity-plot plot` takes a
    config file (default `parity.toml`), not a CSV path. The old smoke test fed
    it a bare CSV and died with `invalid TOML: Expected '=' after a key`.
    `tests/install-parity-plot` now generates a real `parity.toml`, and also
    covers `init` (documented entry point) and `example` (a second exercise of
    the patched `save()`).
  - The test's expected version is now **read from `packages.json`** instead of
    hard-coded; the literal had gone stale on every previous bump.
  - Dependency closure unchanged -- only `parity_plot-0.5.0-*.whl` replaced by
    `0.6.0`.

## Dependency bumps (2026-07-24)

- **parity-plot v0.4.0 -> v0.5.0** (`ed16b6a446837db78d7502d9062a98d276a66dd4`).
  Rebuilt with `build/build-parity-plot.sh --tag v0.5.0`. The offline-HTML patch
  applies clean to v0.5.0 (the `include_plotlyjs="cdn" -> True` line moved 418->487
  but the context matched; `__version__` still `0.1.0` upstream). Dependency closure
  unchanged vs the vendored wheels -- only `parity_plot-0.5.0-*.whl` replaced
  `0.4.0`. `tests/install-parity-plot` updated to assert 0.5.0 and passes (CLI +
  module version, self-contained Plotly HTML, local NiceGUI designer).
- **Astral tools** via `build/update-prebuilt ruff=0.16.0 ty=0.0.63 uv=0.11.32`:
  ruff 0.15.21->0.16.0, ty 0.0.58->0.0.63, uv 0.11.28->0.11.32. Downloaded, stripped,
  patchelf'd (`$ORIGIN/../lib64:$ORIGIN/../lib`), bz2'd, versions stamped. Astral was
  acquired by OpenAI -- release cadence/URLs unchanged for now; watch for redirects.
- Post-payload chain run: `./strip-all-elf-binaries` (3 new bz2 recorded),
  `build/gen-content-manifest` (4312 files, `--check` OK). Bash completion diff = no
  change (only versions/wheels moved, not package names/verbs).

## Release-time reduction (2026-07-23)

Two structural wastes in `./release` removed, both on the release critical path:

- **nvim plugin stash reuse.** The ~328 MB stash asset was re-uploaded on every
  re-release even when byte-identical. `./release` now keeps the existing release
  object (it holds the asset), moves only the tag, **undrafts** it (deleting a tag
  drafts its release; recreating the tag does not republish -- verified empirically),
  and clobbers only the small assets. Gated on a signed tag + a byte-match (present
  asset, size, and matching SHA-256 in the previous release's `sha256sums.txt`), then
  a post-publish re-read asserts published-not-draft + stash present, self-healing
  with a full upload on any doubt. See CLAUDE.md -> "Create a GitHub release".
- **Binary-smoke content cache.** The ~4.5 min smoke gate (the slowest) is now cached
  under `release-smoke-v1/`, keyed on a parallel hash of **actual bytes** (all of
  `payload/**` + `loadout` + `loadout_main.py` + `tests/prebuilt-binaries`, a
  deliberate superset) plus platform `uname`/glibc; pass-only, double-checked key.
  The hash (~a few seconds, parallelised) runs inside the smoke worker so it overlaps
  the version gate. Cache lives in `./release`, so `tests/prebuilt-binaries` run
  directly still always executes. `--no-cache` / `--clear-cache` force fresh.

Net: a routine re-release whose payload is unchanged skips both the 328 MB upload and
the 4.5 min smoke re-run. A real payload change re-fingerprints and re-runs, so the
false-green surface is only an *over*-cover (needless re-run), never an under-cover.

## Release signing: the 2026-07-22 unsigned-tag incident

The first `v2026.07.22` release shipped an **unsigned** tag (GitHub reported
`verification.reason = "unsigned"`), silently. `./release` decided whether to sign
from `_signing_configured()`, which only asked `git config --get user.signingkey`.
When that resolved empty the script took the `git tag -a` fallback, printed a warning
into a long unattended log, and dropped the `git tag -v` line from the release notes.
Nobody was at the keyboard to notice. The top link of the trust chain was missing.

`./release` now runs `_preflight()` **before any gate**, because the gates are slow and
the operator is only reliably present at kickoff:

- checks `gh auth status`;
- proves signing works by signing a throwaway tag with `SSH_ASKPASS_REQUIRE=never`,
  no `DISPLAY`, `stdin=DEVNULL` and a 60s timeout, then greps the resulting object for
  `BEGIN SSH SIGNATURE` -- a zero exit from the signer is not proof;
- blocks with remediation unless `--allow-unsigned` is passed;
- after the real `git tag -s`, re-reads the tag object and aborts (deleting the tag)
  if no signature block is present.

Signing needs a live ssh-agent. **Probe for one before asking anyone to run `ssh-add`** --
it is normally already running and only `SSH_AUTH_SOCK` is missing from tool shells.
Two traps: the agent socket probe fails under a sandbox with `unix_listener: socket:
Operation not permitted` (a sandbox artifact, not a broken agent), and `ssh-add` is
aliased on this box to `eval "$(ssh-agent -s)" && command ssh-add ...`, so a bare call
spawns a fresh **keyless** agent. Use `/usr/bin/ssh-add -l` against each
`/tmp/ssh-*/agent.*` and match the fingerprint of `~/.ssh/id_ed25519.pub`.

## State

- `main` intentionally has a two-commit bootstrap snapshot containing the current tree.
  GitHub enforces a 2 GiB per-push limit, so the snapshot is split only to transfer the
  normal offline payloads safely. All earlier commits and release tags were removed to
  expunge obsolete binary blobs; current payloads remain ordinary Git objects, never LFS.
- A complete pre-reset worktree + `.git` archive was checksum-verified before rewrite.
  It is user-local recovery material, not clone state.
- Current tree carries espresso, restic, reproducible archive stripping, correct
  shared-library check ordering, and the Tier 3 assurance gate. The nvim plugin stash
  remains a GitHub release asset (`nvim-plugin-stash.tar.bz2`) with its checksum and
  content-manifest trust chain; it is not a Git payload.
- `parity-plot` is bundled as a non-optional Linux Python tool from stable upstream
  tag `v0.5.0` (`ed16b6a446837db78d7502d9062a98d276a66dd4`). NiceGUI is now a
  core upstream dependency, not a `uv_extras` entry, so the local designer still
  installs offline. Its loadout patch corrects the stale Python module version and
  embeds Plotly in generated HTML, so reports render offline. Static image/PDF export
  still needs an already-installed Chrome/Chromium for Kaleido. Rebuild with
  `build/build-parity-plot.sh --tag v0.5.0`; it copies a supplied source checkout
  into a disposable build tree and first reuses the vendored lock closure offline.
  Upstream still ships no explicit license file/metadata; the owner authorized this
  first-party bundle, but add explicit terms upstream before third-party redistribution.
- `@envs` now intentionally expands only `env-bash` (then its `env-starship`
  recommendation). Install another config bundle by name, or use `@envs-all` for
  every env package. The fresh-home integration test explicitly selects
  `@engineering-loadout @envs-all` to retain broad Nvim/editor/shell coverage.

## Audit 2026-07-18 (pre-reset tree; all gates green)

- `loadout doctor`: clean. `tests/run-all` (Tier 1+2): all pass, incl. assurance-check
  33/33, completion sync, crate-store 2101/2101.
- `scan-for-malware`: CLEAN, 71210 files, 1 documented allowlisted FP (firefox omni.ja).
  User ran `sudo freshclam` 2026-07-17 (sigs were 10 days old).
- `build/verify-binaries`: 9 pass / 0 fail / 139 documented skips. `git fsck`: clean.
- Outdated vs upstream (22 pkgs, mostly patch bumps): htop 3.2.1→3.5.1,
  octave 11.1.0→11.3.0, flameshot 13→14, fish 4.8.0→4.8.1, rg 15.1→15.2, gnuplot
  6.0.2→6.0.4, vim/gvim 9.2.0782→.0785, plus small bumps (`build/check-versions
  --outdated-only` for the list). pdftotext correctly pinned (freetype floor). No
  outdated Python tools.
- git "unable to access '.gitmodules': Permission denied" inside Claude Code sandboxed
  commands is a sandbox artifact, NOT repo state (file doesn't exist outside the
  sandbox). Never "fix" it. See project memory `gitmodules-sandbox-mask`.

## Audit 2026-07-21 (Parity Plot + Bash-only @envs)

- `tests/run-all --container`: PASS. Tier 1/2 integration, the stock
  AlmaLinux 8.10 full smoke (250 binaries OK, 5 documented skips, runtimes OK),
  and isolated dynamic analysis all passed.
- Focused `tests/install-parity-plot`: PASS. It verifies CLI/module 0.4.0,
  self-contained Plotly HTML, `farm-versions` reporting, and a local NiceGUI
  designer page with no external page assets.
- `@envs` resolves exactly `env-bash` plus `env-starship`; the split
  deployment smoke asserts no zsh config is created. `@envs-all` resolves all
  12 env bundles and is selected only by the broad fresh-home coverage test.

## Audit 2026-07-22 (Parity Plot v0.4.0)

- `tests/run-all --container`: PASS (`/tmp/loadout-final-suite-v040.log`).
  Tier 1/2 integration, the stock AlmaLinux 8.10 full smoke (250 binaries OK,
  5 documented skips, runtimes OK), and isolated dynamic analysis all passed.
- Focused `tests/install-parity-plot`: PASS after the v0.4.0 update. It
  verifies CLI/module 0.4.0, self-contained Plotly HTML, `farm-versions`
  reporting, and a local NiceGUI designer page with no external page assets.
- Release gate components: PASS. `./scan-for-malware` reports cached CLEAN
  across 75051 files with the known Firefox `omni.ja` allowlisted FP;
  `tests/prebuilt-binaries` reports `All 255 binaries OK; runtimes OK`;
  release checksum/version steps passed and refreshed `sha256sums.txt`.

## Bash env: every directory change lists

`cd()` in `envs/bash/global/bashrc` is the **only** thing that runs the follow-up `ls`,
so anything reaching `builtin cd` silently skips it. Fixed: `loadout_cd_recent_dir`
(backing `cdd`/`cddd`/...) and `latest` in `envs/bash/global/aliases.sh` now call the
`cd` function, and the zoxide block overrides `__zoxide_cd` -- zoxide funnels every jump
through that one generated function, so overriding it covers `z`, `zi` and future verbs.
The `--` was dropped at those call sites: the wrapper does not accept one, and `find`
always emits `./`-prefixed paths. `alias bcd="builtin cd"` stays as the escape hatch.

Verify with a real PTY (`script -qec`) driving `cdd`/`z` in a scratch dir with a marker
file, and check the negative control -- the same harness against a tree without the fix
must print no listing. `bash -lic` will not do: no prompt cycle, so the bug hides.

`cds()` / `cd-surfer` was a failed experiment and is deleted. Unrelated `cds` hits
elsewhere (Cadence `cds.lib` in vim-liberty, SAP `cds-lsp` in nvim) are not related.

## Next steps

1. **Exercise the laptop path for real**: use the current GitHub release tag with
   `tools/download-release.ps1 -Tag <release-tag>` on the Windows laptop, scp to nDPC,
   then run `./fetch-stash --from-file`. Runbook section 2b documents it; this remains
   unvalidated against a real asset-bearing release.
2. Version bumps from the audit list, priority to the ones users notice: htop
   3.2.1→3.5.1, octave 11.1.0→11.3.0 (needs `build/build-octave.sh` + runtime re-pack),
   flameshot 13→14, fish 4.8.0→4.8.1 (patch; the sentinel is `vendor_functions.d`, do
   NOT resurrect the stdlib check). Full list: `build/check-versions --outdated-only`.
   Version bumps of nvim/rust/rust-crate-store/treesitter/git-nvim also require a ledger
   re-pin (see "Assurance ledger interactions").

Release mechanics (for #2 bumps): `./release` attaches the stash automatically when
present; build it first with `build/build-nvim-plugin-stash` if the checkout lacks it.
Signing needs a usable agent socket — memory `release-tag-signing-wsl`: user runs
`ssh-add`, probe `ls -t /tmp/ssh-*/agent.*` for one where `SSH_AUTH_SOCK=$s ssh-add -l`
lists a key, run `SSH_AUTH_SOCK=<sock> ./release`. (Note: on WSL a bare `ssh-add` alias
here re-spawns a fresh keyless agent each call — probe existing sockets for the keyed one
rather than trusting `$SSH_AUTH_SOCK`.)

## Lessons (all fixed; keep respecting them)

### A green test that never ran the code is the most dangerous result there is

- **st:** pixel (3,3) sampled the unfocused cursor's outline box → returned cursor color
  for every case. Sample away from the cursor.
- **worker harness:** `opencode … | tee log` makes `$?` *tee's* status. Use
  `set -o pipefail` + `${PIPESTATUS[0]}`.
- **tcsh:** `tcsh -i -c CMD` does not set `$prompt`, silently skipping the interactive
  block under test. Drive a real PTY (`script -qec`).

Before believing a passing test, ask what it would have printed had the feature been absent.

### A stale check trains people to ignore real signal

The fish `FAILED` row was noise for weeks and got logged as "pre-existing" three times.
Same family: the false zsh "may not run" warning (fixed). Assert behavior, not
file layout; never leave a known-false warning in place.

### Silent-no-op patching

Textual patching without a positive assertion is a silent-no-op factory: version stamps
are `json.load/dump` keyed on the exact package name; every `sed` of an artifact is
followed by `grep -q || exit 1`; `build-st.sh` does `rm -f config.h` (Makefile only
copies `config.def.h` when absent).

### Probe leniency masks real breakage

`--version` proves nothing. Fatal-banner patterns plus functional smokes (XSPICE
netlist, tkinter `Tcl()`, pdftotext CJK, restic backup/restore roundtrip) live in
`tests/prebuilt-binaries` — extend that set.

### The pre-commit hook stages everything

It runs `git add -A`. Partial commits: precise staging + `--no-verify` after running the
hook's checks manually, or keep the tree clean (memory `pre-commit-hook-stages-everything`).

## Assurance ledger interactions

Version bumps of nvim/rust/rust-crate-store/treesitter/git-nvim/crate-store must re-pin
`assurance/records/<pkg>.toml` (version, ref, artifact hashes) and honestly re-run the
malware scan and the dynamic detonation (`tests/prebuilt-binaries-almalinux8
--dynamic`). `assurance-check` now runs in BOTH run-all Tier 1 and the stock-EL8 Tier 3
`--full` gate, so a stale record fails on the container baseline too — but the re-pin is
still a manual step; the checks catch drift, they do not fix it.

## Delegating work to glm-5.2 workers

Subagent work can run on the user's Ollama plan via external `opencode` workers
(`opencode run -m ollama-cloud/glm-5.2`) in a tmux pane — Claude Code's Agent tool
cannot (fixed Anthropic model enum). Traps and pane conventions: memory
`glm5-tmux-worker-delegation`.

## Open low-priority items

- WSLg `SSH_ASKPASS` popup root-cause: gnome-ssh-askpass doesn't appear from background
  shells despite `DISPLAY` + `SSH_ASKPASS` set. Agent workaround reliable and in project
  memory. Optional; pin the fix in `dev-onboard`/docs if found.
