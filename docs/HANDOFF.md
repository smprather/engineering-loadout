# Current Handoff

Last updated: 2026-07-23 (release-time reduction: stash-asset reuse + smoke content cache).

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
  tag `v0.4.0` (`261720c64b60fbfba09826183b315ce15dd6d560`). NiceGUI is now a
  core upstream dependency, not a `uv_extras` entry, so the local designer still
  installs offline. Its loadout patch corrects the stale Python module version and
  embeds Plotly in generated HTML, so reports render offline. Static image/PDF export
  still needs an already-installed Chrome/Chromium for Kaleido. Rebuild with
  `build/build-parity-plot.sh --tag v0.4.0`; it copies a supplied source checkout
  into a disposable build tree and first reuses the vendored lock closure offline.
  Upstream v0.4.0 has no explicit license file/metadata; the owner authorized this
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
