# st runtime configuration — design

Date: 2026-07-13
Status: approved (design); implementation not started

## Problem

`st` is suckless: every setting lives in `config.h` and is baked into the binary
at compile time. The loadout builds `st` once on the EL8 build machine
(`build/build-st.sh`, stock `config.h` + the undercurl patch) and ships the ELF
in `payload/el8.x86_64.glibc2p28/bin/st.bz2`.

The destination systems — farm nodes, LSF hosts, locked-down workstations — have
no compiler and no `libX11-devel`. A user who wants a different font, font size,
or color scheme has no path at all today. "Rebuild st" is not a user-facing
answer on those machines.

## Goals

- Change **font** (family, size, style) and **colors / theme** after deployment,
  with no compiler on the destination.
- **Live reload**: changes apply to already-running `st` windows, not just the
  next launch.
- Config files are **self-documenting**: every legal value and every bundled
  font's exact Xft string is listed in-file as comments, so nobody has to hunt
  for the fontconfig family name.
- Fit the existing loadout layer model (`global → corp → site → team → project →
  user`) and the split `@shared` / `@envs` deployment shape.

## Non-goals

- **Keybindings / mouse shortcuts stay compile-time.** No upstream runtime-config
  patch covers them; supporting them means hand-written C that parses a shortcut
  table, re-broken on every st tag bump. Explicitly out of scope.
- Behavior knobs beyond what the resource table below covers.
- Auto-reload on file mtime (stat loop in the hot path; rejected).

## Design

### 1. One loadout-owned patch

`build/st/0001-runtime-xresources-config.patch`, derived from the upstream
`xresources` and `xresources-with-reload` patches (st is MIT; note provenance in
the patch header and in `ADDING_BINARIES.md`).

Rationale for one curated patch rather than stacking two upstream diffs: the repo
already learned this lesson with undercurl, where two hunks rejected against st
0.9.3 and `build-st.sh` carries manual `st.c` fixups. One patch = one thing to
re-verify per tag bump.

The patch adds:

**a. `config_init(Display *dpy)`** — builds an `XrmDatabase`:

1. Seed from `XResourceManagerString(dpy)` if non-NULL, so users who already live
   in `xrdb` / `~/.Xresources` keep working.
2. For each colon-separated path in `$ST_XRESOURCES`, in order:
   `XrmCombineFileDatabase(path, &db, /*override=*/True)` — later file wins.
   Missing/unreadable files are skipped silently (a layer that does not exist is
   not an error).
3. Look up the resource table; anything unset falls through to the compiled
   `config.h` value. **st with no config files behaves exactly as it does today.**

Resource table (`ST_STRING` / `ST_INT` / `ST_FLOAT`, as in the upstream patch):

| resource | type | maps to |
|---|---|---|
| `st.font` | string | `font` |
| `st.background`, `st.foreground`, `st.cursorColor` | string | `colorname[defaultbg/fg/cs]` |
| `st.color0` … `st.color15` | string | `colorname[0..15]` |
| `st.cursorshape` | int | `cursorshape` |
| `st.borderpx` | int | `borderpx` |
| `st.blinktimeout` | int | `blinktimeout` |
| `st.bellvolume` | int | `bellvolume` |
| `st.tabspaces` | int | `tabspaces` |
| `st.termname` | string | `termname` |
| `st.shell` | string | `shell` |
| `st.cwscale`, `st.chscale` | float | cell width/height scale |

**b. `SIGUSR1` reload** — handler sets a `volatile sig_atomic_t` only (no X calls
in a signal handler). The `run()` main loop sees the flag and re-runs
`config_init()` → `xloadcols()` → font reload (`xunloadfonts` / `xloadfonts`) →
`cresize()` → full redraw. Font changes therefore re-derive cell dimensions and
resize correctly.

**c. `Ctrl+Shift+R`** — `config.h` shortcut calling the same reload path from
inside the terminal. This one key is compile-time by construction; accepted.

### 2. `bin/st` becomes a wrapper

Follows the existing gvim / ngspice / fish pattern: `bin/st` is a POSIX-sh
wrapper, `bin/st.bin` is the real ELF (RPATH `$ORIGIN/../lib64`, unchanged).

The wrapper's only job: if the caller has not already exported `ST_XRESOURCES`,
set it to the layer chain, then `exec st.bin "$@"`. An explicit user-set
`ST_XRESOURCES` always wins.

It reads no shell-startup state, so `st` launched from a `.desktop` file, dmenu,
or a bare `ssh host st` behaves identically to `st` from an interactive bash.

### 3. Layer chain

Mirrors `~/.config/bash/{global,corp,site,team,project,user}`:

```
${XDG_CONFIG_HOME:-$HOME/.config}/st/global/st.xresources   <- shipped by env-st
                                    corp/st.xresources       \
                                    site/st.xresources        |  user-created,
                                    team/st.xresources        |  later wins
                                    project/st.xresources    /
                                    user/st.xresources       <- personal; seeded
                                                                as a commented
                                                                template
```

Config lives in `$HOME`; the binary lives in the shared tree. A split
`@shared` (non-home) + `@envs` (HOME) deployment needs no
`LOADOUT_CFG_SHARED_PREFIX` plumbing for st — the wrapper resolves the chain
against `XDG_CONFIG_HOME`/`$HOME` at exec time.

### 4. Reload UX

`bin/st-reload` (POSIX-sh, shipped in the `st` package):

- Default scope: `st.bin` processes owned by the calling uid whose
  `/proc/<pid>/environ` `DISPLAY` matches the caller's `$DISPLAY`.
- `--all`: every `st.bin` owned by the caller, any display.
- Sends `SIGUSR1`. Prints how many instances were signalled.

Plus `Ctrl+Shift+R` from inside any st window.

### 5. Self-documenting config files

Both shipped files (`envs/st/global/st.xresources` and the seeded
`user/st.xresources` template) carry the full cheatsheet as `!` comments: every
key, its legal values, and — the load-bearing part — **every bundled font's exact
Xft string**.

This is not cosmetic. The fontconfig family name is not the zip name for a third
of what the loadout ships:

| `payload/fonts/*.zip` | actual fontconfig family |
|---|---|
| `CascadiaCode.zip` | `CaskaydiaCove Nerd Font` |
| `SourceCodePro.zip` | `SauceCodePro Nerd Font` |
| `DejaVuSansMono.zip` | `DejaVuSansM Nerd Font` |
| `Meslo.zip` | `MesloLGS Nerd Font` (also LGL / LGM) |

A hand-written font list will be wrong. So it is **generated**.

**`build/gen-st-font-comments`**: for each `payload/fonts/*.zip` (rejoining
`.part-NNN` chunks the way the installer does), extract the faces to a temp dir,
run `fc-scan --format '%{family[0]}\n'` on each `.ttf`/`.otf`, dedup, and rewrite
the block between the markers

```
! BEGIN generated font list
! END generated font list
```

in `envs/st/global/st.xresources` and in the user template. Same shape as the
existing `./loadout completion bash > envs/bash/global/completions/loadout.bash`
regeneration step, and it gets the same guard: a **sync-diff test** in
`tests/run-all` regenerates into a temp file and diffs, failing if the committed
block is stale. Adding a font zip then tells you to re-run the generator.

Emitted block (illustrative):

```
! ---- Fonts bundled by loadout (exact Xft strings) ----
! BEGIN generated font list
!   st.font: CaskaydiaCove Nerd Font:size=12      (CascadiaCode.zip)
!   st.font: DejaVuSansM Nerd Font:size=12        (DejaVuSansMono.zip)
!   st.font: EnvyCodeR Nerd Font:size=12
!   st.font: FiraCode Nerd Font:size=12
!   st.font: Hack Nerd Font:size=12
!   st.font: Inconsolata Nerd Font:size=12
!   st.font: IosevkaTerm Nerd Font:size=12
!   st.font: JetBrainsMono Nerd Font:size=12
!   st.font: MesloLGS Nerd Font:size=12           (Meslo.zip; also LGL / LGM)
!   st.font: RobotoMono Nerd Font:size=12
!   st.font: SauceCodePro Nerd Font:size=12       (SourceCodePro.zip)
!   st.font: UbuntuMono Nerd Font:size=12
! END generated font list
!
! Syntax: <family>:size=<pt>[:style=Bold][:antialias=true][:autohint=false]
! Check what X resolves:  fc-match 'JetBrainsMono Nerd Font'
! List everything:        fc-list : family | sort -u
```

Every other key is documented the same way, inline:

```
! st.cursorshape:  2     ! 2=block 4=underline 6=bar; odd values blink (1/3/5)
! st.borderpx:     2     ! px padding inside the window
! st.blinktimeout: 800   ! ms; 0 disables blinking
! st.bellvolume:   0     ! -100..100; 0 = silent
! st.tabspaces:    8
! st.termname:     st-256color   ! must match a terminfo entry loadout ships
! st.shell:        /bin/bash
!
! Colors: st.background st.foreground st.cursorColor st.color0 .. st.color15
!   Accepts #rrggbb or an X color name. The loadout default (tokyonight, set in
!   global/) is shown commented below; override any single key here.
```

`envs/st/global/st.xresources` ships **live** (uncommented) opinionated defaults:
`JetBrainsMono Nerd Font:size=12` + the tokyonight palette, matching the nvim
colorscheme and starship. Consistent with how `envs/bash`, `envs/starship`, and
`envs/nvim` ship opinionated globals.

The seeded `user/st.xresources` ships **fully commented out**, so it changes
nothing until the user uncomments a line.

## File inventory

New:

- `build/st/0001-runtime-xresources-config.patch`
- `build/st/st` — wrapper (installed as `bin/st`)
- `build/st/st-reload` — reload helper (installed as `bin/st-reload`)
- `build/gen-st-font-comments` — font-list block generator
- `envs/st/global/st.xresources` — shipped global layer (live defaults)
- `envs/st/user/st.xresources.template` — commented cheatsheet, seeded on install
- `envs/st/README.md` — layer model, reload, how to regenerate the font block

Changed:

- `build/build-st.sh` — apply the new patch; build the wrapper/`st.bin` split;
  `need fc-scan`; re-verify the undercurl fixups still apply.
- `payload/packages.json` — `st.bins` → `["st", "st.bin", "st-reload"]`; new
  `env-st` package (`kind: env`, `source: envs/st/`, `install_to: ~/.config/st`,
  tags `env`,`terminal`).
- `loadout_main.py` — `_install_env_st` handler in `ENV_HANDLERS`. A custom
  handler (not `_install_env_generic`) because the seeding rule is
  non-destructive: sync `global/` with delete semantics, but write
  `user/st.xresources` **only if it does not already exist**, and never touch
  sibling layer dirs (`corp/`, `site/`, …).
- `envs/bash/global/completions/loadout.bash` — regenerate (registry changed).
- `build/ADDING_BINARIES.md` — st entry: patch provenance, the wrapper split, the
  font-generator step. Mandatory per CLAUDE.md.
- `CLAUDE.md` — "st runtime config behavior" section.

## Testing

X-free, run in the Tier 3 `almalinux:8.10` container gate:

- **Wrapper chain test**: `ST_XRESOURCES` unset → wrapper builds the expected
  six-element colon list against a fake `HOME`/`XDG_CONFIG_HOME`; `ST_XRESOURCES`
  pre-set → wrapper leaves it alone.
- **Font-comment sync diff**: re-run `build/gen-st-font-comments` into a temp
  file, diff against the committed block, fail if stale.
- **Seeding test**: fresh-HOME install creates `user/st.xresources`; a second
  install with a modified user file leaves it byte-identical.
- **Registry integrity**: `env-st` resolves, is in `@envs`, is not in `@shared`.

Color/font/reload behavior needs a real X server, which `tests/prebuilt-binaries`
cannot drive today (GUI apps are already an explicit host-contract skip in the
container). That stays a **documented manual smoke** on the dev box: launch `st`,
edit `user/st.xresources`, `st-reload`, confirm font and colors change live;
repeat with `Ctrl+Shift+R`.

## Risks

- **Tag-bump fragility.** The patch touches `csiparse`-adjacent code paths that
  undercurl already fixes up by hand. Mitigation: one patch, provenance and
  fixup notes in `ADDING_BINARIES.md`, and `build-st.sh` fails loudly on a
  rejected hunk rather than continuing.
- **`fc-scan` at build time.** Needs `fontconfig` on the EL8 build box (present).
  The generator is a build-time tool only; nothing at install/run time depends on
  it.
- **Font family names change upstream.** Nerd Fonts has renamed families before
  (`Caskaydia Cove` vs `CaskaydiaCove`). The sync-diff test catches this on the
  next font bump instead of shipping a stale comment.

## Open questions

None blocking. Deferred: a `st-theme` helper that drops a named palette into
`user/st.xresources` — trivial once the layer chain exists, not needed for v1.
