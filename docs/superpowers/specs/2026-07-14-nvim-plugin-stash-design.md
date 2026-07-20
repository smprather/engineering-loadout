# nvim offline plugin stash (`:Lazy update` without a network) — design

Date: 2026-07-14
Status: approved (design)

## Problem

The bundled nvim plugins ship as **plain directories with no `.git`** — the repo's
pre-commit hook strips embedded `.git` dirs, which is why the history vanished.
lazy.nvim treats a populated `lazy/<name>` as installed, so plugins *load* fine
offline, but:

- `:Lazy update` / `:Lazy sync` / `:Lazy restore` are silent no-ops — there is no git
  repo to fast-forward and no remote to fetch from.
- `envs/nvim/lazy-lock.json` pins 24 commits that nothing can ever check out.
- On an air-gapped box there is no github to fall back to.

So the plugin set is frozen at whatever shipped, and the lockfile is decorative.

## Design

### Ship bare mirrors, let lazy clone from them

`payload` carries `nvim-plugin-stash.tar.bz2`: one **bare, single-branch, gc'd** git
mirror per plugin, laid out by upstream slug so lazy's `url_format` can address them
directly:

```
<catalog>/folke/snacks.nvim.git
<catalog>/Saghen/blink.cmp.git
...
```

Measured: **82 MB** for all 29 repos (full history, single-branch, `gc --aggressive`),
versus 47 MB for the current git-less worktrees. **+35 MB**, and it buys real git.

The stash **replaces** the worktree archive — one artifact, one source of truth. It
cannot drift from the checked-out trees because there are no separate checked-out
trees.

### nvim points lazy at the stash

`lazy.setup(specs, { git = { url_format = "<catalog>/%s.git" } })` **only when the
stash exists**; otherwise the upstream github default stands, so an online workstation
with no stash behaves exactly as it does today. The catalog path resolves through
`envs/nvim/lua/global/paths.lua` (user copy first, shared tree second), so a split
deployment finds it in the shared tree.

Consequences, all of which are the point:

- `lazy/<name>` becomes a **real git clone** whose `origin` is the stash.
- `:Lazy update` fetches **from the stash** — offline, no github.
- `:Lazy restore` checks out the pinned sha from `lazy-lock.json` — offline.
- Refreshing the stash on a connected build box (`./update nvim-plugins`) is how the
  fleet gets new plugin versions: users then `:Lazy update` against the new stash,
  fully air-gapped.

### The installer clones; it no longer copies

`install_nvim_plugin_bundle` clones each plugin from the stash into the user's
`lazy/<name>` and checks out its `lazy-lock.json` commit. Local clones are fast (same
filesystem, hardlinked objects).

`lazy/` stays **per-user and writable** (`:Lazy update` writes to it); the stash stays
**shared and read-only**. That is the two-tier split established in `c6ae3ec`.

### git: bundled, but never on the user's PATH

The stash requires git. git is not currently shipped, and is absent from the stock EL8
base image.

**A loadout `git` on PATH must never shadow the corp git.** Corp `git-lfs`, credential
helpers and custom `git-*` subcommands resolve against *their* git's exec-path and
config; a different git in front breaks them silently. This is the same failure the
openssh package already documents (why the loadout ships `ssh10` and lets
`/usr/bin/ssh` win) — see CLAUDE.md → "OpenSSH package behavior".

Therefore:

- Package `git-nvim` (working name), **`optional: true`** — reachable via `@shared-all`
  or by name. Never in `@shared`, never in `@engineering-loadout`.
- Installed to a **private prefix** (`lib/loadout-git/{bin,libexec}`), **not** `bin/git`.
  Nothing the user's shell resolves ever changes.
- **nvim alone** consumes it: the nvim config prepends that private dir to
  `vim.env.PATH` *only when the system has no usable git*. lazy shells out to `git`, so
  it picks up nvim's PATH, not the user's.
- Built "shanghai" from the AlmaLinux 8 AppStream RPM (git 2.43 + `libexec/git-core`),
  the technique already used for meld / mate-terminal / firefox. Deps
  (libcurl/openssl/pcre2/expat/zlib) are EL8 BaseOS and already assumed present.

### No git anywhere?

nvim core still starts; the plugin phase is skipped with an explicit warning naming the
cause. That is strictly better than today's failure mode (a silent bare editor), and it
cannot happen on the deployments that matter: `@shared-all` carries the bundled git.

## Testing

`tests/install-nvim-deployments` (added in `c6ae3ec`) grows assertions:

1. `lazy/<plugin>/.git` exists and `origin` points at the **stash**, not github.
2. `git -C lazy/<plugin> fetch` succeeds **with the network blackholed** — the proof
   that offline updates actually work.
3. `:Lazy restore` checks out the `lazy-lock.json` pin offline.
4. With git removed from `PATH` entirely: nvim still starts, and the installer emits
   the explicit "no git" warning rather than silently producing a bare editor.

The Tier 3 container installs git for this (the base image lacks it), which also proves
the bundled-git path when the system one is absent.

## Non-goals

- Bundling git for the user's shell. It is nvim's dependency, not theirs.
- Shipping plugin worktrees as a fallback. One artifact, one truth; the no-git case
  degrades loudly instead.
