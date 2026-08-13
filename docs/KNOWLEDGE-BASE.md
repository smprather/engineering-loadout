# Knowledge base / notes

The loadout bundles **markdown-oxide**, a PKM (personal knowledge management)
language server. It gives wikilinks, backlinks, daily notes and
unresolved-link creation over a plain directory of markdown files, in both
bundled editors, offline, on a farm node.

```bash
./loadout install markdown-oxide        # or it arrives with @engineering-loadout
```

## What is and is not shipped

| thing | who provides it |
|---|---|
| `markdown-oxide` binary | **the loadout** |
| nvim + helix LSP wiring | **the loadout** |
| the vault -- your actual notes | **you / your org, never this repo** |

**This repo ships tools and configuration, never content.** It ships `vim` and
not your source, `nvim` config and not your notes. A vault holding
organisation-specific engineering knowledge must never be committed here or
attached to a release -- this repo is public. Org content belongs in the
unbundled `corp/`, `site/`, `team/`, `project/` and `user/` layers, or on org
infrastructure entirely, and can be placed by a `--post-install-hook` script.

## Obsidian

**Obsidian is deliberately not bundled, and cannot be.** Its terms grant a
*"non-sublicensable, non-transferable"* license to install and execute it
*"on machines operated by or for you"*, and separately forbid the customer to
*"distribute or share the Services or Software or make any of them available
for access by third parties"*. Putting it in `payload/` and publishing that as
a release is exactly what those clauses prohibit. Obsidian being free for
commercial **use** is not permission to **redistribute** it.

That is not a problem in practice, because nothing about a vault is
proprietary: it is a directory of markdown files. So:

- Install Obsidian yourself through whatever channel your organisation uses,
  under your own acceptance of its terms, and point it at your vault.
- The loadout's `markdown-oxide` indexes **that same vault** from nvim or
  helix, on machines where a GUI is not available -- a compute farm node, an
  ssh session, a locked-down host.

Both tools read the same plain files, so there is no import, export or sync
step. Obsidian on the desktop and `nvim` on a farm node are two views of one
directory.

## Vault layout

A vault is just a directory. markdown-oxide treats one as its root when it
finds any of `.obsidian/`, `.moxide.toml`, or `.git` (see
`envs/nvim/lsp/markdown_oxide.lua`).

```
~/notes/                 <- vault root
  .obsidian/             <- created by Obsidian; also the root marker
  .moxide.toml           <- optional markdown-oxide config (below)
  daily/
    2026-08-10.md
  projects/
    some-chip.md
  index.md
```

If you do not use Obsidian at all, `git init` or an empty `.moxide.toml` is
enough to mark the root -- you do not need a `.obsidian/` directory.

## `.moxide.toml`

Optional, at the vault root. The setting worth knowing is where daily notes
live and how they are named, because the `:LspToday` / `:LspTomorrow` /
`:LspYesterday` commands (registered in `envs/nvim/lsp/markdown_oxide.lua`)
create and open files by that pattern:

```toml
daily_notes_folder = "daily"
daily_notes_template = "%Y-%m-%d"
```

Match these to Obsidian's own daily-notes settings if you use both, or the two
tools will create daily notes in different places.

## Editor behaviour

**nvim** enables `markdown_oxide` in `envs/nvim/lua/global/init.lua`. On a
markdown buffer you get completion on `[[`, go-to-definition on a wikilink,
backlinks via references, and a code action to create an unresolved note.
`:LspToday`, `:LspTomorrow` and `:LspYesterday` open daily notes.

**helix** is wired in `envs/helix/languages.toml` to the same server.

Both explicitly name `markdown-oxide` rather than accepting the default. The
built-in default for markdown in both editors is `marksman`, which this repo
does **not** bundle -- on an offline node that server never starts and fails
silently. Naming one server also avoids attaching two markdown servers to the
same buffer, which doubles completions and go-to-definition results.

### helix asks before it starts any language server

The first time you open a workspace in helix you get a modal:

> Trust this workspace? Trusted workspaces may load local config files and
> auto-start language servers. Config and language servers can execute
> arbitrary code.

**Until it is answered, helix starts NO language server** -- not
`markdown-oxide`, not `taplo`. Dismissing it leaves a working editor with
silently no LSP, which looks like a broken install and is not one.

**The shipped config turns that prompt off**: `envs/helix/config.toml` sets
`[editor] insecure = true`, so servers start immediately and you should never
see the modal. If you are ever in a tree where LSP is dead and the status line
says *"Current workspace is not trusted"*, run `:workspace-trust`
(`:workspace-untrust` reverses it; the answer persists in `trusted_workspaces`
under `~/.local/share/helix`).

That setting is a deliberate, owner-made decision for this deployment, not a
default. What it trades: on a shared filesystem, any directory you open --
including another user's -- has its local `.helix/` config honoured and its
language servers launched, which is the arbitrary-code path helix's own warning
describes. It is accepted here because the target is a closed, highly controlled
engineering environment where who can place files on the shared tree is already
governed by controls outside the editor. **Deploying this loadout anywhere that
is not true means turning it back off.** The full rationale and the revisit
conditions live in the comment block at the top of `envs/helix/config.toml`.

Upstream's narrower `[editor.workspace-trust] level = "servers"` would trust
server launches while still gating local config -- strictly better here -- but
**no released helix has it**: 25.07.1 (2025-07-18) is still latest as of
2026-08-13 and rejects the key, which makes helix discard the whole config file
and fall back to defaults. Prefer it over `insecure` once it ships.

## Why this is not Obsidian

markdown-oxide covers the linking and navigation layer, not the GUI: no graph
view, no canvas, no community plugin ecosystem, no live preview pane. If you
want those, run Obsidian on your desktop against the same vault. What you get
on a farm node is the part that matters in a terminal -- following and
creating links, finding backlinks, and reaching today's note in one command.
