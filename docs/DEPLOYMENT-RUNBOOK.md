# Deployment Runbook

Offline-first loadout deployment across three environments whose network
access changes without warning. Terse, imperative, copy-pasteable. Read the
table, find your state, run the commands.

## Environments and their states

| env | github access | shared FS | notes |
|---|---|---|---|
| **Windows laptop** | most reliable | n/a | **PowerShell 5.1 only.** No WSL, no VMs (policy). |
| **nDPC** (Linux) | **varies by day**: full / clone-pull only / blocked | **R/W** | clone/pull is enough for everything here. |
| **DPC** (Linux, air-gapped) | none | **R/O** | where the users actually are. |

The shared filesystem is the bridge: R/W from nDPC, R/O from DPC. The
loadout tree and the nvim plugin stash both live on it. DPC users consume
them read-only; nDPC maintains them.

**First, figure out today's nDPC state** (this determines which path you
take for every operation below):

```bash
# on nDPC
git ls-remote https://github.com/smprather/engineering-loadout.git HEAD \
  && echo "github: REACHABLE" || echo "github: BLOCKED"
```

- `REACHABLE` (full or clone/pull) → use the nDPC path.
- `BLOCKED` → use the laptop path (the Windows laptop can still reach github).
- Everything blocked → nothing to do; the last-good state keeps working.

---

## 1. First-time deployment of a shared tree

Goal: a shared tree on the shared FS that DPC users point at via
`LOADOUT_CFG_SHARED_PREFIX`, plus each user's per-user `@envs` in `$HOME`.

Run this **once** from nDPC (the box with R/W on the shared FS). It assumes
you have a checkout of the loadout repo on nDPC.

```bash
# on nDPC, from the loadout checkout
# <SHARED> is a directory on the shared filesystem, e.g. /mnt/shared/loadout
SHARED=/mnt/shared/loadout

# 1. Stage the shared tree: binaries, runtimes, fonts, data, the plugin
#    stash, AND the optional packages (git-nvim, surfer, rust, ...).
#    @shared-all = @shared + optionals. git-nvim is optional and lives here
#    so nvim can clone plugins on boxes with no system git.
#
#    NOTE: --dest-dir takes the ROOT, not the 'local' subdir. The installer
#    writes to <SHARED>/local/{bin,lib64,share,...}. Set
#    LOADOUT_CFG_SHARED_PREFIX=<SHARED>/local on the user side.
./loadout install @shared-all --dest-dir "$SHARED" --no-backup
```

Verify the shared tree:

```bash
ls "$SHARED"/local/bin/nvim "$SHARED"/local/bin/tmux "$SHARED"/local/bin/bash
ls "$SHARED"/local/share/nvim/loadout/vendor/plugin-stash   # the plugin stash
ls "$SHARED"/local/lib/loadout-git/bin/git                  # private git for nvim
```

If the plugin stash is missing from the shared tree, the `nvim-plugin-stash`
install phase was skipped. That happens when the stash archive is not in the
checkout (it is a release asset, not committed to git). See section 2 to
fetch it, then re-run the install.

### Per-user `@envs` (each DPC user, once)

Each user runs this **on the DPC** (air-gapped side, R/O shared FS). It writes
only into their `$HOME` and points at the shared tree:

```bash
# on DPC, as the user
export LOADOUT_CFG_SHARED_PREFIX=/mnt/shared/loadout/local
./loadout install @envs --no-backup
exec bash
```

`@envs` is the per-user config layer (bash/zsh/fish/tcsh, nvim config, tmux,
starship, etc.). It is decoupled from `@shared` -- no cross-recommends, no
extra flags. The installer bakes `LOADOUT_CFG_SHARED_PREFIX` into
`~/.config/bash/global/config.sh` so it survives future shells.

Verify per-user:

```bash
command -v nvim    # -> /mnt/shared/loadout/local/bin/nvim
ls ~/.local/share/nvim/lazy/lazy.nvim   # per-user plugin clones (real git repos)
nvim --headless -c 'qa!'                # nvim starts
```

---

## 2. Getting the nvim plugin stash

The stash is ~328 MB of bare git mirrors of every bundled nvim plugin. It is
a **release asset**, not committed to git (committing it added 328 MB to
`.git` on every refresh). Pick the path that matches today's network state.

### 2a. nDPC can reach github (full or clone/pull) -- the easy path

```bash
# on nDPC, from the loadout checkout
./fetch-stash                       # from the latest release
# or: ./fetch-stash --tag v2026.07.14
```

`fetch-stash` downloads `sha256sums.txt` and the stash asset, verifies the
sha256 against the signed release, and records the verified hash in
`.content-manifest.fetched` (gitignored). The installer trusts that file
identically to the committed manifest. An unverified file is deleted, never
left on disk.

Then stage it into the shared tree:

```bash
./loadout install @shared-all --dest-dir "$SHARED" --no-backup
# (or just: ./loadout install nvim-plugin-stash --dest-dir "$SHARED" --no-backup
#  if only the stash is new)
```

### 2b. github blocked on nDPC, but the laptop can reach it -- the scp path

The Windows laptop has the most reliable github access but PowerShell only.
`tools/download-release.ps1` downloads the release + stash, verifies sha256
on the Windows side, and prints the scp command.

```powershell
# on the Windows laptop, from a clone of the repo (or a release source tarball)
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tools\download-release.ps1 -Tag v2026.07.14
# default output dir: .\loadout-release
```

The script verifies every asset against `sha256sums.txt` (the trust root,
covered by the signed tag). If a hash mismatches, the file is deleted and
the script exits non-zero. It prints the scp command at the end.

Copy the files to nDPC (the script prints the exact command):

```powershell
scp "C:/path/to/loadout-release/*" <user>@<ndpc-host>:~/loadout-release/
```

Then on nDPC, install from the copied files -- still verified:

```bash
# on nDPC, from the loadout checkout
./fetch-stash --from-file ~/loadout-release/nvim-plugin-stash.tar.bz2 \
    --sums ~/loadout-release/sha256sums.txt
```

`fetch-stash` re-verifies the sha256 against the sums file and writes
`.content-manifest.fetched`. Then stage into the shared tree:

```bash
./loadout install @shared-all --dest-dir "$SHARED" --no-backup
```

### 2c. Everything blocked -- nothing to do

The last-good stash on the shared FS keeps working indefinitely. It is
read-only data; nothing expires. DPC users keep getting the same plugins on
`:Lazy update` (fetching from the local mirrors) and fresh installs keep
cloning at the `lazy-lock.json` pins. Do not delete or move the stash.

---

## 3. Refreshing plugins WITHOUT a loadout release

Plugin cadence is decoupled from loadout cadence. Run `refresh-stash` on nDPC
(it only ever clones/fetches -- never pushes -- so a "clone/pull only"
network policy is enough). It updates the bare mirrors **in place** in the
shared tree.

```bash
# on nDPC (R/W on the shared FS, github reachable)
# Point it at the INSTALLED stash in the shared tree:
./refresh-stash "$SHARED"/local/share/nvim/loadout/vendor/plugin-stash

# dry-run first if you want to see what would change:
./refresh-stash "$SHARED"/local/share/nvim/loadout/vendor/plugin-stash --dry-run

# only mirror plugins that are missing (skip the in-place fetch of existing ones):
./refresh-stash "$SHARED"/local/share/nvim/loadout/vendor/plugin-stash --add-only
```

What it does:
- existing mirrors: `git remote update --prune`
- plugins new to the lockfile/catalog: mirror them fresh
- removed plugins: left alone (a user may still have them enabled)

What happens for DPC users:
- Existing users get the new plugin versions on their next `:Lazy update`
  inside nvim (fetch from the local mirrors, no network).
- **Fresh installs still clone at the `lazy-lock.json` pins** until a new
  loadout release moves them. `refresh-stash` prints a NOTE when mirrors
  advanced past the lockfile, reminding you to refresh the lockfile + cut a
  release when you want the *default* set to move too.

Do NOT run `refresh-stash` on the DPC: the shared FS is mounted read-only
there and it will refuse with `ERROR: <stash> is not writable.`

---

## 4. Updating the loadout itself (new release)

A new loadout release means a new source tarball, new binaries, new
`.content-manifest`, and (when the plugin set moved) a new stash asset.
Path depends on today's network state.

### 4a. nDPC can reach github

```bash
# on nDPC, from a checkout (git pull, or extract a fresh release tarball)
git pull                          # or: tar xzf engineering-loadout-v*.tar.gz
./fetch-stash                     # if the release carries a new stash asset
./loadout install @shared-all --dest-dir "$SHARED" --no-backup
```

Users on the DPC do not need to re-run anything unless they want the new
`@envs` config; if they do, they run `./loadout install @envs --no-backup`
with `LOADOUT_CFG_SHARED_PREFIX` set (same as section 1).

For a versioned-rollover deployment (atomic, no `Text file busy`):

```bash
# install the new release into a NEW versioned dir, then atomically swap a symlink
./loadout install @shared-all --dest-dir /mnt/shared/loadout/releases/v2026.07.15 --no-backup
ln -s /mnt/shared/loadout/releases/v2026.07.15 /mnt/shared/loadout/.current.new
mv -Tf /mnt/shared/loadout/.current.new /mnt/shared/loadout/current
```

Users pointing at `current` pick up the new tree on their next shell. Keep
the previous release for rollback.

### 4b. github blocked on nDPC, laptop can reach it

```powershell
# on the Windows laptop
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tools\download-release.ps1 -Tag v2026.07.15
scp "C:/path/to/loadout-release/*" <user>@<ndpc-host>:~/loadout-release/
```

```bash
# on nDPC
# extract the new source tarball into a new checkout (or git pull if clone/pull works)
tar xzf ~/loadout-release/engineering-loadout-v2026.07.15.tar.gz
cd engineering-loadout-v2026.07.15
./fetch-stash --from-file ~/loadout-release/nvim-plugin-stash.tar.bz2 \
    --sums ~/loadout-release/sha256sums.txt
./loadout install @shared-all --dest-dir "$SHARED" --no-backup
```

### 4c. Everything blocked

No update is possible. The existing shared tree and stash keep working.
Wait for network to return; do not attempt partial updates.

---

## 5. Troubleshooting

Read the literal error message, find it here.

### `nvim plugins: no plugin stash found, so NO PLUGINS were installed.`

The checkout or shared tree has no plugin stash. nvim core still works; you
just have zero plugins. Fix: fetch the stash (section 2a or 2b), then
re-run the install. If you are a DPC user hitting this, your admin has not
staged the stash into the shared tree yet -- tell them.

### `CONTENT VERIFICATION FAILED: ...`

The payload on disk does not match `.content-manifest` (or is not listed in
it). The installer installed nothing from that file. Two causes:

- **The nvim plugin stash is present but not in a manifest.** The stash is a
  release asset, not a git payload. `./fetch-stash` is the only thing that
  may add it to `.content-manifest.fetched` (after verifying the sha256
  against the signed release). Run `./fetch-stash` (online) or
  `./fetch-stash --from-file <f> --sums <sha256sums.txt>` (scp'd copy).
- **Your checkout is corrupt or was modified.** Re-clone, or re-run
  `./strip-all-elf-binaries` if you changed the payload deliberately.

### `ERROR: sha256 MISMATCH -- the stash does not match the signed release.`

`fetch-stash` deleted the downloaded file. The bytes you got are not the
bytes the release signed. Do not use them. Re-download (section 2a or 2b);
if it mismatches again, the release or your transport is compromised --
stop and investigate.

### `ERROR: SHA-256 MISMATCH for nvim-plugin-stash.tar.bz2` (PowerShell side)

`tools/download-release.ps1` deleted the file. Same meaning as above, on the
Windows side. Re-run the download; if it persists, the release is bad or TLS
interception is corrupting the transfer (the script prints TLS guidance).

### `ERROR: <stash> is not writable.`

You ran `refresh-stash` on the air-gapped side (DPC), where the shared FS is
read-only. Run it on nDPC instead (the box with R/W on the shared FS). See
section 3.

### `nvim plugins: no git found, so the plugins were NOT installed.`

The stash needs git to clone from. There is no system git and no `git-nvim`
in the shared tree. Fix: install `git-nvim` into the shared tree (it is
optional, in `@shared-all`, and private to nvim -- it never goes on PATH):

```bash
# on nDPC
./loadout install git-nvim --dest-dir "$SHARED" --no-backup
```

Or make a system git available. Then re-run the user's `@envs` install (the
plugin clone happens on the per-user side).

### `ERROR: GitHub API 404 for ...` (fetch-stash)

No such release tag. Omit `--tag` for the latest, or check the tag spelling.
Releases before the stash moved out of git do not carry the stash asset.

### `ERROR: cannot reach github.com: ...` (fetch-stash)

github is blocked from this box. If this is nDPC and the laptop can reach
it, use the scp path (section 2b). If the laptop is also blocked, section 2c
applies -- the existing stash keeps working.

### TLS/SSL error on the Windows laptop

Corporate TLS interception. `download-release.ps1` forces TLS 1.2/1.3. If
the proxy uses an untrusted CA, the .NET stack rejects it. Fix: ensure the
corp root CA is in the Windows certificate store, or download the files in
a browser (which trusts the corp CA) and pass them to `fetch-stash
--from-file` on nDPC. The script prints this guidance inline.

### `ERROR: release <tag> has no sha256sums.txt -- cannot verify. Refusing.`

The release is incomplete or tampered. Do not trust it. Use a different
release tag, or re-create the release if you are the maintainer.

### Plugins did not update after `refresh-stash`

DPC users must run `:Lazy update` inside nvim (it fetches from the local
mirrors). `refresh-stash` only updates the mirrors; it does not touch user
clones. If a user enabled a catalog plugin that was missing, they run
`:Lazy install <plugin>` (it clones offline from the stash). Fresh installs
still pin to `lazy-lock.json` until a release moves them.

---

## Quick reference

| what | where | command |
|---|---|---|
| first shared tree | nDPC | `./loadout install @shared-all --dest-dir "$SHARED" --no-backup` |
| per-user env | DPC (each user) | `LOADOUT_CFG_SHARED_PREFIX=<SHARED>/local ./loadout install @envs --no-backup` |
| fetch stash (online) | nDPC | `./fetch-stash` |
| fetch stash (scp'd) | nDPC | `./fetch-stash --from-file <f> --sums <sha256sums.txt>` |
| download stash (Windows) | laptop | `tools/download-release.ps1 -Tag <tag>` |
| refresh plugins (no release) | nDPC | `./refresh-stash "$SHARED"/local/share/nvim/loadout/vendor/plugin-stash` |
| update loadout | nDPC | pull + `./fetch-stash` + `./loadout install @shared-all --dest-dir "$SHARED" --no-backup` |

`<SHARED>` = the root dir on the shared filesystem. The installer writes to
`<SHARED>/local/...`. Users set `LOADOUT_CFG_SHARED_PREFIX=<SHARED>/local`.