# nvim stash: release asset + ops-refreshable mirror (B+C)

Date: 2026-07-14
Status: approved (design)

## Problem

The nvim plugin stash is 328 MB of bz2'd git packfiles committed to the repo. Binary,
no delta reuse: **every plugin refresh adds ~328 MB to `.git` permanently.** `.git` is
already 3.6 GB. Refresh quarterly and every clone grows >1 GB/year, forever.

Worse, plugin updates are chained to loadout releases: an air-gapped user cannot get a
newer plugin until a whole new loadout ships.

## The environments this must survive

The constraints are dynamic — infosec policy changes without warning — so the design
must degrade, not break:

| env | github | writes | notes |
|---|---|---|---|
| **Windows laptop** | most reliable | — | **PowerShell only.** No WSL, no VMs. |
| **nDPC** (Linux) | *varies*: full / clone-pull only / blocked | R/W on the shared FS | today: clone/pull |
| **DPC** (Linux, air-gapped) | none | **R/O** on the shared FS | where the users are |

The shared filesystem is the bridge: **R/W from nDPC, R/O from DPC.**

## Design

### B — the stash is a release ASSET, not a git-committed payload

- `envs/nvim/vendor/plugins/nvim-plugin-stash.tar.bz2*` is **removed from git** and
  gitignored. `.git` stops growing with every refresh.
- `./build/release` attaches the stash to the GitHub release as a single asset (GitHub allows
  2 GB/asset; the 45 MB chunking existed only to dodge git's file-size warnings) and
  records its sha256 in `sha256sums.txt`, which is itself an asset covered by the
  **signed tag**.
- The installer already skips cleanly when the stash is absent, warning and naming the
  fix. A checkout with no stash yields nvim + no plugins, never a crash.

**Trust chain (the part that must not be hand-waved).** `.content-manifest` is a strict
allowlist -- `_verify_source_files` treats *any* file with no manifest entry as a hard
error, on purpose. A fetched stash is not in the committed manifest, so it would be
rejected. Rather than punch a hole in that:

```
signed tag  ->  sha256sums.txt (release asset)  ->  stash bytes  ->  .content-manifest.fetched
```

`fetch-stash` downloads `sha256sums.txt` and the asset, verifies the hash, and only then
writes the verified hash into `.content-manifest.fetched` (gitignored). The installer
loads that alongside `.content-manifest` and trusts it identically. Nothing is trusted
that was not verified against the signed release.

### C — the stash is refreshable in place, with no release

`refresh-stash <stash-dir>` runs on **nDPC** (which needs only clone/fetch, never push)
and updates the bare mirrors **directly in the shared filesystem**:

- existing mirrors: `git remote update --prune`
- plugins new to the lockfile/catalog: mirror them fresh
- removed plugins: left alone (a user may still have them enabled)

DPC users then pick up new plugin versions on their next `:Lazy update`, which fetches
from the shared stash. **Plugin cadence decouples from loadout cadence**, and nothing is
committed to git.

### The acquisition paths, in priority order

1. **nDPC can reach github** (today): `refresh-stash` directly into the shared FS. No
   release, no laptop.
2. **nDPC blocked, laptop only**: PowerShell downloads the release + stash asset and
   verifies the sha256; you `scp` them to nDPC; `fetch-stash --from-file` installs the
   asset into the checkout, then a normal `@shared-all` install stages it.
3. **Everything blocked**: the last-known-good stash on the shared FS keeps working
   indefinitely. It is read-only data; nothing expires.

## Components

| | what |
|---|---|
| `build/build-nvim-plugin-stash` | emits ONE `nvim-plugin-stash.tar.bz2` (no chunking) |
| `.gitignore` | stops the stash ever being committed again |
| `release` | attaches the stash + its sha256 to the GitHub release |
| `fetch-stash` | downloads + verifies the asset (or takes `--from-file` for the scp path); writes `.content-manifest.fetched` |
| `refresh-stash` | ops-side in-place mirror refresh into the shared tree (nDPC) |
| `tools/download-release.ps1` | Windows/PowerShell path: fetch release + asset, verify sha256 |
| `loadout_main.py` | loads `.content-manifest.fetched`; already skips cleanly with no stash |

## Testing

- installer with **no stash**: skips, warns, nvim core still starts (already covered).
- `fetch-stash --from-file` with a **corrupted** asset: refuses, and the installer still
  refuses the file afterwards (the fetched manifest must never record an unverified hash).
- `refresh-stash` against a scratch stash: mirrors update, a new lockfile plugin is added.
- the existing `tests/install-nvim-deployments` continues to pass with a fetched stash.

## Non-goals

- Hosting an internal git server. The shared filesystem *is* the mirror.
- Auto-fetching from the installer. Network access is a policy decision, not a default;
  the user runs `fetch-stash` deliberately.
