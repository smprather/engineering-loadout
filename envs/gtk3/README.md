# GTK3 settings environment

Loadout-owned default for `~/.config/gtk-3.0/settings.ini`, the GTK3
`GtkSettings` file every GTK3 application reads (theme, icon/cursor theme,
font, Xft rendering, animations).

| File | Installed to | Read by |
|---|---|---|
| `settings.ini` | `~/.config/gtk-3.0/settings.ini` | GTK3 apps; no display server needed to parse it |

The file is **seeded once and then owned by the user**: GTK, desktop settings
daemons and theme switchers rewrite it, so a reinstall leaves it untouched and
it stays writable. Delete it to have the next install recreate it. Nothing else
under `~/.config/gtk-3.0/` is touched (`gtk.css`, `colors.css`, `bookmarks` and
theme-generated CSS stay exactly as the user/theme left them).

The seeded values are the operator's current desktop settings. They name host
themes and fonts (`Catppuccin-Mocha`, `breeze-dark`, `breeze_cursors`,
`Noto Sans`) that a given host may not have installed; GTK falls back to its
defaults for missing names, and a missing `colorreload-gtk-module` costs one
load warning. That is deliberate: the file records the environment, and a host
with those packages gets the intended look.

GTK4 has its own `~/.config/gtk-4.0/settings.ini` and is **not** covered by this
package; the two settings sets are not interchangeable.
