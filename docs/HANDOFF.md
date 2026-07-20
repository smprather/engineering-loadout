# Current Handoff

Last updated: 2026-07-20 (single-snapshot history reset after a complete verified archive).

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
