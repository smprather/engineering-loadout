# Deployment Runbook

Offline-first loadout deployment across three environments whose network
access changes without warning. Terse, imperative, copy-pasteable. Read the
table, find your state, run the commands.

## Environments and their states

| env | github access | shared FS | notes |
|---|---|---|---|
| **offsite box** (any OS with github + scp) | most reliable | n/a | Personal-utility role: fetch release assets by any means, hand-carry them. |
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
- `BLOCKED` → fetch release assets on any github-capable machine and scp them
  over (section 2b). How you download them there is out of scope for this repo
  (a browser is fine; verify with the release's `sha256sums.txt`).
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

`@envs` is the Bash-only per-user config layer (plus its Starship
recommendation). Add any other config bundle explicitly, for example
`./loadout install env-nvim env-tmux --no-backup`; use `@envs-all` only when
every shell/editor config, including csh and zsh, is intentionally wanted. It
is decoupled from `@shared` -- no cross-recommends, no extra flags. The
installer bakes `LOADOUT_CFG_SHARED_PREFIX` into
`~/.config/bash/global/config.sh` so it survives future shells.

Verify per-user:

```bash
bash -ic 'test -f ~/.config/bash/bashrc'
command -v bash    # -> /mnt/shared/loadout/local/bin/bash
```

---

## 2. Getting the nvim plugin stash

The stash is ~328 MB of bare git mirrors of every bundled nvim plugin. It is
a **release asset**, not committed to git (committing it added 328 MB to
`.git` on every refresh). Pick the path that matches today's network state.

### 2a. nDPC can reach github (full or clone/pull) -- the easy path

```bash
# on nDPC, from the loadout checkout
./tools/fetch-stash                       # from the latest release
# or: ./tools/fetch-stash --tag v2026.07.14
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

### 2b. github blocked on nDPC, but some other box can reach it -- the scp path

Download the release + stash on any machine with github access, verify every
asset against `sha256sums.txt` (the trust root, covered by the signed tag),
and copy the files to nDPC:

```text
# on the github-capable box: fetch, from the release page or with any client:
#   engineering-loadout-v<TAG>.tar.gz
#   nvim-plugin-stash.tar.bz2
#   sha256sums.txt
# verify before copying:
sha256sum -c sha256sums.txt --ignore-missing
# then copy them over:
scp <files> <user>@<ndpc-host>:~/loadout-release/
```

Then on nDPC, install from the copied files -- still verified:

```bash
# on nDPC, from the loadout checkout
./tools/fetch-stash --from-file ~/loadout-release/nvim-plugin-stash.tar.bz2 \
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
./tools/refresh-stash "$SHARED"/local/share/nvim/loadout/vendor/plugin-stash

# dry-run first if you want to see what would change:
./tools/refresh-stash "$SHARED"/local/share/nvim/loadout/vendor/plugin-stash --dry-run

# only mirror plugins that are missing (skip the in-place fetch of existing ones):
./tools/refresh-stash "$SHARED"/local/share/nvim/loadout/vendor/plugin-stash --add-only
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
./tools/fetch-stash                     # if the release carries a new stash asset
./loadout install @shared-all --dest-dir "$SHARED" --no-backup
```

Users on the DPC do not need to re-run anything unless they want the new
Bash `@envs` config; if they do, they run `./loadout install @envs --no-backup`
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

### 4b. github blocked on nDPC, some other box can reach it

Fetch the release assets on the github-capable box (source tarball, stash,
`sha256sums.txt`; verify with `sha256sum -c`), scp them to nDPC, then:

```bash
# on nDPC
# extract the new source tarball into a new checkout (or git pull if clone/pull works)
tar xzf ~/loadout-release/engineering-loadout-v2026.07.15.tar.gz
cd engineering-loadout-v2026.07.15
./tools/fetch-stash --from-file ~/loadout-release/nvim-plugin-stash.tar.bz2 \
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
  release asset, not a git payload. `./tools/fetch-stash` is the only thing that
  may add it to `.content-manifest.fetched` (after verifying the sha256
  against the signed release). Run `./tools/fetch-stash` (online) or
  `./tools/fetch-stash --from-file <f> --sums <sha256sums.txt>` (scp'd copy).
- **Your checkout is corrupt or was modified.** Re-clone, or re-run
  `./build/strip-all-elf-binaries` if you changed the payload deliberately.

### `ERROR: sha256 MISMATCH -- the stash does not match the signed release.`

`fetch-stash` deleted the downloaded file. The bytes you got are not the
bytes the release signed. Do not use them. Re-download (section 2a or 2b);
if it mismatches again, the release or your transport is compromised --
stop and investigate.

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

Or make a system git available. Then install or re-run the user's `env-nvim`
bundle (the plugin clone happens on the per-user side); `@envs` alone is
Bash-only.

### `ERROR: GitHub API 404 for ...` (fetch-stash)

No such release tag. Omit `--tag` for the latest, or check the tag spelling.
Releases before the stash moved out of git do not carry the stash asset.

### `ERROR: cannot reach github.com: ...` (fetch-stash)

github is blocked from this box. If this is nDPC and another box can reach
github, use the scp path (section 2b). If everything is blocked, section 2c
applies -- the existing stash keeps working.

### TLS/SSL error while downloading on another box

Corporate TLS interception. If the proxy uses an untrusted CA, command-line
clients reject it. Fix: ensure the corp root CA is trusted on that box, or
download the files in a browser (which trusts the corp CA) and pass them to
`fetch-stash --from-file` on nDPC.

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
| per-user Bash config | DPC (each user) | `LOADOUT_CFG_SHARED_PREFIX=<SHARED>/local ./loadout install @envs --no-backup` |
| fetch stash (online) | nDPC | `./tools/fetch-stash` |
| fetch stash (scp'd) | nDPC | `./tools/fetch-stash --from-file <f> --sums <sha256sums.txt>` |
| fetch stash (blocked nDPC) | offsite box | download release assets, `sha256sum -c`, scp to nDPC |
| refresh plugins (no release) | nDPC | `./tools/refresh-stash "$SHARED"/local/share/nvim/loadout/vendor/plugin-stash` |
| update loadout | nDPC | pull + `./tools/fetch-stash` + `./loadout install @shared-all --dest-dir "$SHARED" --no-backup` |

`<SHARED>` = the root dir on the shared filesystem. The installer writes to
`<SHARED>/local/...`. Users set `LOADOUT_CFG_SHARED_PREFIX=<SHARED>/local`.
