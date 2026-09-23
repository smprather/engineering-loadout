# envs/btop — btop configuration and themes

Layout mirrors the other env packages (compare `envs/st/`, `envs/helix/`):

```
envs/btop/
  btop.conf        the managed config: copied to ~/.config/btop/btop.conf
  themes/*.theme   the curated theme set: packed into the btop package's
                   runtime archive and installed to
                   <prefix>/share/btop/themes, where btop looks by itself
```

`env-btop` is the per-user config bundle (`btop.conf` only); the `btop`
package (kind `bin`) provides the binary, the `btop-theme-tour` helper, and the
theme set. Install `env-btop` for the config, `btop` for the tool and themes.

## How btop finds the themes

btop resolves its theme directory from the REAL binary's location
(`/proc/self/exe` -> `<dir>/../share/btop/themes`) — src/btop.cpp in v1.4.7.
Because the payload installs the real binary at `<prefix>/bin/btop`, the
bundled themes land at `<prefix>/share/btop/themes` and are found with **no
wrapper and no command-line flags**. Search order is:

1. `custom_theme_dir` — the `--themes-dir` option, if given,
2. `user_theme_dir` — `<config_dir>/themes`, i.e. `~/.config/btop/themes`,
3. `theme_dir` — `<real binary>/../share/btop/themes`, then the two system
   directories `/usr/local/share/btop/themes` and `/usr/share/btop/themes`.

**No wrapper is shipped, deliberately.** Two independent reasons, both in
btop's own source (src/btop_theme.cpp):

- `--themes-dir` OUTRANKS the user's own theme directory. A wrapper that always
  passed the bundled directory would hide `~/.config/btop/themes` from the
  Options menu — including the themes the user downloaded themselves, and the
  directory btop itself writes to when a theme is picked from that menu.
- The flag buys nothing: `<real binary>/../share/btop/themes` is already one of
  btop's defaults, so the explicit directory is searched anyway.

The one case where a caller does want the flag is the theme tour (below), which
passes `--themes-dir` only when the caller sets `BTOP_CYCLE_THEMES` explicitly.

Why the managed set does not live in `~/.config/btop/themes`: that directory
belongs to the user — hand-downloaded third-party themes live there, and btop
writes there itself. The managed set therefore stays in the data tree; a
reinstall replaces `~/.config/btop/btop.conf` and `<prefix>/share/btop/themes`
and touches nothing else.

`btop-theme-tour` (installed to `<prefix>/bin/btop-theme-tour`) walks every
theme the user can see — `~/.config/btop/themes` first, then the bundled set —
one btop run per theme, then offers to set `color_theme` in the config.

## What env-btop manages vs. what it preserves

| Path | Owner | Behaviour |
|------|-------|-----------|
| `~/.config/btop/btop.conf` | managed | replaced on install/reinstall |
| `<prefix>/share/btop/themes/` | managed | replaced on install/reinstall |
| `~/.config/btop/themes/` | user | never touched by the installer |

## Theme provenance

`themes/` contains 84 themes: the 41 shipped upstream in btop v1.4.7
(`themes/` in the btop repository — byte-identical, verified), the bpytop
collection upstream also carries, plus third-party themes. Most carry their own
attribution header inside the file (author and/or source URL); several
well-known ones — catppuccin, rose-pine, tokyo-night, everforest — do not, so
provenance for those is recorded here rather than re-derived later.

Upstream btop (41): adapta, adwaita, adwaita-dark, ayu, dracula, dusklight,
elementarish, everforest-dark-hard, everforest-dark-medium,
everforest-light-medium, flat-remix, flat-remix-light, flexoki-dark,
flexoki-light, gotham, greyscale, gruvbox_dark, gruvbox_dark_v2,
gruvbox_light, gruvbox_material_dark, horizon, HotPurpleTrafficLight,
kanagawa-dragon, kanagawa-lotus, kanagawa-wave, kyli0x, matcha-dark-sea,
monokai, night-owl, nord, onedark, orange, paper, solarized_dark,
solarized_light, tokyo-night, tokyo-storm, tomorrow-night, twilight,
whiteout, white — plus the bpytop-* variants upstream ships for the older
bpytop palette format.

Third-party (43): 0x96f, amethyst-dream, carbonfox, catppuccin_frappe,
catppuccin_latte, catppuccin_macchiato, catppuccin_mocha, cybrcore, damin,
dawnfox, dayfox, ddlc-btop-dark, ddlc-btop-light, default_black,
dollar-oligarchy, duskfox, ElegantKid, florentine, gruvppuccin, nightfox,
noctalia, nordfox, phoenix-night, red, rose-pine, rose-pine-dawn,
rose-pine-moon, terafox, WiemanTheme, yozakura-hiru, yozakura-yoru.

The `carbonfox` / `dawnfox` / `dayfox` / `duskfox` / `nightfox` / `nordfox` /
`terafox` set is the nightfox.nvim palette (EdenEast/nightfox.nvim); `damin` is
miniex/btop-theme-damin; `cybrcore` is cybrcore/cybr-btop.

Adding or replacing themes: drop the `.theme` file into `envs/btop/themes/` and
run the payload chain:

```
python3.14 build/build-btop.sh --tag 1.4.7   # repack themes + tour
./build/strip-all-elf-binaries               # normalizes the archive; regen sizes+manifest
python3.14 build/build-btop.sh --tag 1.4.7 --check
```
