# Release Procedure

The authoritative, ordered procedure for cutting a release. Release knowledge
used to live scattered across `CLAUDE.md`, `docs/SECURITY.md`,
`docs/MAINTENANCE.md`, `docs/HANDOFF.md` and the `./release` docstring; every
release then reconstructed it from memory and missed something different. This
file is the single source. If you change the release process, change it here.

**`./release` is not the procedure.** It runs the *gates* — malware scan, binary
smoke, version table, checksums, tag, publish. Everything that makes the payload
correct in the first place happens before you invoke it, and `./release` cannot
tell that you forgot it.

---

## 0. Pick the release class

The class decides which gates are mandatory. Be honest about it — the whole
point of the classes is that "it's a small change" is exactly when things get
skipped that should not have been.

| class | what changed | Tier 3 container | assurance re-pin | currency sweep |
|---|---|---|---|---|
| **A — no payload** | docs, tests, build tooling only (`build/` is export-ignored) | not required | no | no |
| **B — small payload** | one or more package artifacts, installer untouched | recommended | only if the package has a record | only the bumped packages |
| **C — full** | installer/registry/layout change, or a scheduled release | **required** | **yes** | **yes** |

Anything touching `loadout_main.py`, `payload/packages.json` group membership,
install paths, or repo layout is class C regardless of diff size. A one-line
change to what a group resolves to silently altered ~580 MB of install behavior
once (see *Failure catalogue*, entry 1).

A **scheduled/periodic release is always class C.** That is where the currency
and security work below actually gets done; if you never cut a class C, the
bundle quietly rots.

---

## 1. Authentication first, before any slow work

Settle every credential at kickoff, while you are still at the keyboard. The
gates take ~10 minutes and an unattended prompt at the end does not fail — it
**hangs**.

```bash
gh auth status                       # must be logged in, 'repo' scope
```

Tag signing needs a live ssh-agent holding the key. On WSL `ssh-add` is aliased
to spawn a *fresh keyless* agent, so never trust a bare `ssh-add` or an inherited
`$SSH_AUTH_SOCK`. Probe for the agent that actually holds the key:

```bash
FP=$(ssh-keygen -lf ~/.ssh/id_ed25519.pub | awk '{print $2}')
for s in /tmp/ssh-*/agent.*; do
  SSH_AUTH_SOCK=$s /usr/bin/ssh-add -l 2>/dev/null | grep -qF "$FP" && echo "USE: $s"
done
```

Then export that socket for the whole session and run `./release` with it.
`./release`'s `_preflight()` re-proves signing by signing a throwaway tag with no
tty, no askpass and no `DISPLAY`, and greps the object for a signature block — a
zero exit from the signer is not proof. It blocks the release unless
`--allow-unsigned`. Do not pass that flag; an unsigned tag breaks the top link of
the trust chain (`signed tag -> sha256sums.txt -> payload bytes`).

---

## 2. Currency sweep (class C; bumped packages only for class B)

### 2a. What is behind upstream

```bash
build/check-versions --outdated-only     # bundled vs upstream, GitHub + PyPI
./update --list-outdated                 # same, plus how each package updates
```

`./update --list` classifies every package: `automated`, `rolling-git`,
`build`, `import-script`, `download`. That classification tells you the work:

- **automated** (`yara-rules`, `nodejs`, `tldr-data`, `tmux-plugins`, `env-nvim`)
  — `./update <name>` does it end to end.
- **rolling-git** (`liberty-tools`, `text-serdes`, `time-plot`, `lefdef-tools`)
  — first-party; `./update <name>` rebuilds from source HEAD when the commit
  moved, `--rebuild` forces.
- **build** — needs `build/build-<tool>.sh --tag vX.Y.Z` on this EL8 box.
- **download** / **import-script** — `./update <name>` prints the exact recipe.

Bumping any of `nvim`, `rust`, `rust-crate-store`, `treesitter`, `git-nvim`,
`crate-store` **also requires an assurance re-pin** — see §4.

### 2b. Security data must be current, not merely present

```bash
./update yara-rules              # YARA-Forge ruleset -> payload/yara/
sudo freshclam                   # ClamAV signatures (needs sudo; do it yourself)
./update tldr-data               # offline tldr cache
```

A scan against stale signatures is a green light that means nothing. Check the
ClamAV DB date before trusting a CLEAN verdict; `docs/SECURITY.md` covers what
each layer does and what the allowlisted false positive is.

`./update yara-rules` records the download in `assurance/downloads.log`
(append-only TSV: ISO-8601 UTC timestamp, URL, sha256). That is trust-on-first-use
provenance — it records what was fetched, it does not verify it against a
published hash.

---

## 3. Build and bump

Run the per-package build script for each `build`-class bump. Two failure modes
recur here and both are silent if you are not looking:

**Patches drift.** A `build/<tool>/*.patch` is textual and its *context* breaks
on unrelated upstream churn — an import re-sort is enough. When a patch fails to
apply, do not mechanically re-roll it. Ask first whether it is still needed:
upstream may have absorbed it (parity-plot v0.7.0 did exactly that), in which
case **delete the patch** rather than rewriting it, and make sure a test asserts
the behavior the patch used to force. A patch only forces an input; a test
checks the result.

**Breaking CLI changes.** A version bump can change the tool's interface
(parity-plot v0.6.0 went TOML-only). The package's own test is what catches it —
run it directly, not just as part of the suite, so you see the failure clearly.

Never bundle from git HEAD, nightlies, or dev builds. Stable tagged releases
only; `build/*.sh` enforce `--tag`. The sole exception is the first-party
`rolling-git` set.

---

## 4. The post-payload chain — MANDATORY, IN THIS ORDER

Any change under `payload/` requires all four, in order. Skipping the manifest
step leaves Tier 1 red, and `./update --commit` will happily commit the drift.

```bash
./strip-all-elf-binaries                    # 1. strip/normalize/chunk; updates .strip-manifest
./loadout completion bash > envs/bash/global/completions/loadout.bash   # 2. only if verbs/flags/package names changed
python3.14 build/gen-content-manifest       # 3. re-pin every payload sha256
python3.14 build/gen-content-manifest --check   # 4. prove it
```

`./update` now runs steps 1 and 3 automatically for the paths it mutates. A
manual build script does **not** — you run them.

`.content-manifest` is regenerated **wholesale**; it cannot accept one file and
reject another. So settle any unrelated payload drift in the tree *before*
regenerating, or you will silently bake it in.

**Assurance ledger re-pin** — required when you bumped `nvim`, `rust`,
`rust-crate-store`, `treesitter`, `git-nvim`, or `crate-store`. Update the
package's `assurance/records/<pkg>.toml` (version, ref, artifact hashes) and
honestly re-run the scan and the dynamic detonation:

```bash
tests/prebuilt-binaries-almalinux8 --no-build --dynamic   # network-isolated
python3.14 tests/assurance-check
```

`assurance-check` detects drift; it does not fix it. The re-pin is manual and
deliberate — it is a claim you are making about provenance.

---

## 5. Documentation sync

Docs drift is not cosmetic here: `CLAUDE.md` is the contract the next session
reads, and a wrong statement in it causes wrong work later.

- **README package table** — every row's version must equal
  `payload/packages.json`. Regenerate from the registry; never hand-edit.
  Font and `env-*` packages are intentionally excluded.
- **`CLAUDE.md`** — package behavior sections, the repo-structure tree, group
  membership, CLI flags. If you deleted a patch or a package, grep for its name.
- **`AGENTS.md`** — carries its own per-package pins that drift independently of
  CLAUDE.md's.
- **`docs/HANDOFF.md`** — what the next session reads first. Record *why*, not
  just what.
- **`docs/SECURITY.md`** — only claim a control that exists. It claimed the tmux
  plugin lockfile pinned the bundle for weeks while that file had never been
  committed.

Verify every path you write actually exists. The repo reorganised into
`envs/` + `payload/`, and pre-reboot paths still surface in docs.

---

## 6. Test gates

```bash
./tests/run-all --fast        # Tier 1: syntax/lint, resolver, registry, manifests, assurance
./tests/run-all               # + Tier 2: integration installs into temp roots
./tests/run-all --container   # + Tier 3: stock AlmaLinux 8.10 (class C: REQUIRED)
```

**Stock EL8 is the verification baseline for install behavior; this box is not.**
The dev machine is far from stock and has repeatedly masked real breakage — the
build box had a new-enough NSS only because the firefox RPM pulled it in; six
scripts with `python3` shebangs contained 3.14-only syntax and "worked" solely
because `~/.local/bin/python3` is 3.14.

Expected Tier 3 skips, all host-contract and all fine: `cloc` (host perl),
`meld` (host `/usr/bin/python3.6`), and the GL GUI apps (`flameshot`,
`nedit-ng`, `nvim-qt` — host OpenGL dispatcher).

Before believing any pass, ask what the test would have printed had the feature
been absent.

---

## 7. Commit

The pre-commit hook runs `git add -A` in its embedded-git branch, so it sweeps
the whole tree. Make sure the tree contains only what you intend to ship.

The hook also runs `ruff format` **before** `ruff check`, so formatting can move
a `# noqa` off the line it was suppressing and fail its own lint step. Prefer a
real fix (e.g. binding loop variables as default args) over a suppression that
reformatting can dislodge.

---

## 8. Release

```bash
SSH_AUTH_SOCK=<keyed-socket> ./release --dry-run    # gates only, no tag/publish
SSH_AUTH_SOCK=<keyed-socket> ./release              # tag + publish
```

Useful flags: `--tag vX.Y.Z` (default `v<today>`), `--no-cache` / `--clear-cache`
(force fresh smoke + scan). Do **not** use `--skip-scan` or `--allow-unsigned`.

**What is incremental and what is not** (measured, 2026-07-25):

- **Stash reuse works and is the big win.** The ~328 MB nvim plugin stash is
  reused when the tag's release already exists and the bytes match (size +
  sha256 from the previous `sha256sums.txt`). Note the gate is
  `_remote_release_exists(tag)` — reuse only fires on a **same-tag re-release**.
  A brand-new tag always re-uploads, no matter how little changed.
- **The smoke and scan caches are all-or-nothing** on a hash of *all* of
  `payload/**` plus the installer and probe script. One changed wheel costs the
  same ~10 minutes as changing everything. That superset is deliberate — a
  missed input would false-green a shipped-but-untested binary — so treat a
  payload change as ~10 minutes of gates, always.

---

## 9. Verify after publishing

Never trust the publish exit code. Re-read the release:

```bash
gh release view <tag> --json tagName,isDraft,publishedAt,assets
git tag -v <tag>          # must print a Good signature
```

Confirm `isDraft=false` — deleting a tag drafts its release, and a draft is
invisible to `/releases/latest`, which is what `./fetch-stash` resolves. Confirm
all three assets are present (`sha256sums.txt`, `default.content-manifest`,
`nvim-plugin-stash.tar.bz2`) and the stash size matches local.

The 2026-07-22 release shipped an unsigned tag silently because nothing ever
re-read the object. Re-read it.

---

## Failure catalogue

Every entry is a mistake that actually shipped or was caught late. Each names
what now catches it — where nothing does, that is the open risk.

| # | mistake | now caught by |
|---|---|---|
| 1 | `@engineering-loadout` silently lost 9 env bundles when `@envs` was redefined; curated install shipped ~580 MB of nvim data with no config to use it | group now lists members explicitly; **no automated check** — verify `./loadout resolve @engineering-loadout` after any group edit |
| 2 | Six scripts had `python3` shebangs but 3.14-only syntax; dead on stock EL8, masked by the dev box's `~/.local/bin/python3` | `tests/run-all` py_compiles every first-party Python file |
| 3 | `ruff.toml` excludes were pre-reboot paths matching nothing, and `select` replaced ruff's defaults, disabling pyflakes entirely | excludes corrected; `F,E4,E7,E9,B` enabled |
| 4 | Lint gate ran on one file behind `if command -v ruff` — a silent skip | gate covers all first-party Python; missing ruff is a hard FAIL |
| 5 | `.content-manifest` never regenerated after `./update` mutated `payload/` | `./update` now regenerates it; Tier 1 `gen-content-manifest --check` |
| 6 | Unsigned release tag shipped silently | `_preflight()` proves signing before any gate; post-tag re-read aborts |
| 7 | `docs/SECURITY.md` claimed a tmux plugin pin whose lockfile had never been committed | lockfile now committed; **no automated check** that a documented control exists |
| 8 | README package table: 30 stale versions, 6 missing packages | regenerate from registry; **no `--check` gate** (unlike completions and st font list) |
| 9 | Release-notes version table reports the **build box's installed binaries**, not the registry — 29 of 93 rows wrong | **NOT FIXED** — see below |
| 10 | Test version literals (`0.5.0`) went stale on every bump | `tests/install-parity-plot` reads the expected version from `packages.json` |
| 11 | A patch's redundant hunk broke on upstream import re-sorts | patch reduced to the one hunk that carries meaning |
| 12 | `./update tmux-plugins` cloned a commented-out `@plugin` line | anchored regex skips comments |

### Open defect: release-notes version table (entry 9)

`./release` builds the "Pre-built binary versions" table from
`build/farm-versions --format tsv`, which probes **binaries installed on the
build box**, not `payload/packages.json`. On 2026-07-25 that published a table
claiming parity-plot 0.2.0 while the release shipped 0.7.0; 29 of 93 rows
disagreed with the registry (`vim`/`gvim`, `uv`, `ruff`, `fzf`, `tmux`, …).

This is also the root cause of the stale README table (entry 8) — `farm-versions`
documents itself as the source for README tables.

**Fix:** source the release-notes table from `packages.json` (what the release
contains) rather than from `farm-versions` (what the builder happens to have
installed). `farm-versions` remains the right tool for "what is installed here",
which is a different question. Until then, treat the version table in published
release notes as unreliable.
