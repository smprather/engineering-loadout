# st runtime configuration

st bakes every setting (font, colors, cursor shape, padding, shell) into
`config.h` at compile time. The loadout ships a patched `st` (0.9.3) that also
reads an X resource database at runtime, so you can change font and colors by
editing a text file -- no compiler, no `xrdb`, no restart of the window.

## The layer chain

`bin/st` is a POSIX-sh wrapper. Before execing the real ELF (`bin/st.bin`) it
exports `ST_XRESOURCES` as a colon-separated list of six files, looked up under
`${XDG_CONFIG_HOME:-$HOME/.config}/st`:

```
global/st.xresources -> corp/st.xresources -> site/st.xresources ->
team/st.xresources  -> project/st.xresources -> user/st.xresources
```

st merges them in that order, **later file wins**. Missing files are skipped
silently -- an unused layer simply does not exist. Each file is X resource
syntax: lines of `st.<key>: <value>`, comments start with `!`.

| Layer      | Who owns it                                                            |
|------------|------------------------------------------------------------------------|
| `global/`  | The loadout. Reinstalled (synced, delete semantics) on every `env-st` (re)install. Do not edit; your changes will be overwritten. |
| `user/`    | You. Seeded once from a fully-commented template, then never touched again by the installer. |
| `corp/`, `site/`, `team/`, `project/` | You (or your dotfiles). The loadout never creates or deletes these. Create the directory and drop a `st.xresources` in it; nothing else is required. |

The full precedence, lowest to highest, is:

1. compiled `config.h` defaults (the fallback for any key left unset),
2. the X server's `RESOURCE_MANAGER` property (set by `xrdb`, honored for
   people who already use it),
3. each file in `ST_XRESOURCES` in order, later wins.

So st with no config files at all behaves exactly like an unpatched build --
stock black background, compiled font, no surprises.

## Change the font

Open `~/.config/st/user/st.xresources` (seeded for you, every line commented
out) and uncomment or append a `st.font:` line. The shipped `global` layer
defaults to `JetBrainsMono Nerd Font:size=12`; override it:

```
st.font: FiraCode Nerd Font:size=14
```

Apply it to the already-running window without restarting (see *Reload*
below). To start a brand-new window with the new font, just run `st` again --
it reads the files at startup.

### Worked example: swap to a bigger Hack font and a blue background

```sh
$ mkdir -p ~/.config/st/user
$ cat >> ~/.config/st/user/st.xresources <<'EOF'
st.font: Hack Nerd Font Mono:size=16
st.background: #0d1b2a
EOF
$ st-reload
st-reload: reloaded 1 st instance(s)
```

The running window re-renders at 16pt Hack on the new background. The grid is
re-laid-out from the new cell metrics (the window keeps its pixel size; the
column/row count adjusts).

A font set on the command line (`st -f 'GoMono Nerd Font:size=20'`) still
beats the config files -- `st-reload` re-derives the font from `opt_font`
first, so a `-f` launch keeps its command-line font across reloads.

### Bundled fonts and the generated list

The loadout installs a set of Nerd Font families under
`~/.local/share/fonts`. The shipped `global` and `user` files both carry a
`! BEGIN generated font list` ... `! END generated font list` block listing
every bundled family as a ready-to-paste `st.font:` line. **Do not hand-edit
that block** -- it is regenerated from the actual font metadata by
`build/gen-st-font-comments`, and a Tier 1 test (`st font list in sync`) fails
the build if the committed block has drifted.

The fontconfig family name is not the zip name for roughly a third of what we
ship, which is why the list exists:

| Zip in `payload/fonts/` | Xft family name to use                  |
|-------------------------|-----------------------------------------|
| `CascadiaCode.zip`      | `CaskaydiaCove Nerd Font`               |
| `SourceCodePro.zip`     | `SauceCodePro Nerd Font`                |
| `DejaVuSansMono.zip`    | `DejaVuSansM Nerd Font`                 |
| `Meslo.zip`             | `MesloLGL` / `MesloLGM` / `MesloLGS` (and `...DZ` variants) |

Check what X actually resolves with `fc-match 'JetBrainsMono Nerd Font'`, and
list every installed family with `fc-list : family | sort -u`.

### What the "Nerd Font" / "Nerd Font Mono" / "Nerd Font Propo" suffixes mean

Every Nerd Font zip ships three subfamilies, differing only in how the added
icon glyphs are spaced:

- **`Nerd Font`** -- icons keep their natural (often double) width. Best for
  editors/statuslines that can handle a wide glyph.
- **`Nerd Font Mono`** -- every icon squeezed into exactly one cell. **Safest
  in a terminal** -- nothing overlaps the next column. This is the form the
  global layer defaults to (`JetBrainsMono Nerd Font` is the natural-width
  variant; if a glyph ever clips, switch to the `... Mono` line).
- **`Nerd Font Propo`** -- proportional icons. Rarely useful in a terminal.

## Change the colors

The global layer ships the tokyonight palette. Override any single key in your
user layer; you do not have to copy the whole block. Keys are `st.color0`
through `st.color15` (the 16 ANSI slots), `st.background`, `st.foreground`,
and `st.cursorColor`. Values are `#rrggbb` or an X color name.

```
! make the cursor red and the background pure black
st.cursorColor: #ff0000
st.background:  #000000
```

## Reload a running window

Three routes, all identical under the hood (st re-reads every file in
`ST_XRESOURCES`, reloads fonts, recolors, re-lays-out the grid, and redraws):

- **`st-reload`** -- signal every `st.bin` you own on the current `$DISPLAY`.
  This is the default scope because a config change is per-display in
  practice.
- **`st-reload --all`** -- every `st.bin` you own, on any display.
- **`Ctrl+Shift+R`** -- from inside an st window (the only built-in
  keybinding that is not compile-time).

`st-reload` returns non-zero with a clear message if no st is running. It
rejects unknown options rather than silently signalling everything.

No restart, no recompile. The reload is driven by `SIGUSR1`: the handler only
sets a flag (no X calls are safe from a signal handler), and st's main loop
services it on its next pass.

## What you cannot change at runtime

**Keybindings are compiled into st.** No runtime-config patch covers them.
The only exception is the reload key, `Ctrl+Shift+R`, which is built in. To
change any other binding (scrollback, font zoom, copy/paste shortcuts, etc.)
you would have to edit `config.def.h` and rebuild -- see
`build/ADDING_BINARIES.md` -> "st".

The set of *resources* you can set at runtime is fixed by the patch: `font`,
`color0`-`color15`, `background`, `foreground`, `cursorColor`, `termname`,
`shell`, `cursorshape`, `borderpx`, `blinktimeout`, `bellvolume`,
`tabspaces`, `cwscale`, `chscale`. Anything else in `config.def.h` (mouse
shortcuts, `alpha`, `chscale` for things not listed, etc.) stays
compile-time.

## The `ST_XRESOURCES` escape hatch

The wrapper sets `ST_XRESOURCES` only if you have not. If you want to point st
at your own file(s), set it yourself and the wrapper leaves it untouched:

```sh
ST_XRESOURCES=~/.config/st/user/st.xresources st
```

The value is a colon-separated list read in order, later wins, missing/empty
entries skipped -- so you can layer your own files however you like, including
outside `~/.config/st/` entirely.

## Regenerating the bundled-font comment block

After adding, removing, or updating a font zip under `payload/fonts/`, rerun
the generator and commit the result (the Tier 1 test will fail otherwise):

```sh
build/gen-st-font-comments            # rewrite the block in both config files
build/gen-st-font-comments --check    # exit 1 if the committed block drifted
```

It needs `fc-scan` (fontconfig) on PATH at build time. On the destination
machines nothing runs it -- the block is just text that ships in the files.