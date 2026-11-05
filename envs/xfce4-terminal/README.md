# xfce4-terminal environment

Loadout-owned settings for Xfce Terminal, shipped in both storage formats the
upstream project has used.

| File | Installed to | Read by |
|---|---|---|
| `xfce4-terminal.xml` | `~/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-terminal.xml` | xfce4-terminal 1.1.0+ (Xfconf channel `xfce4-terminal`) |
| `terminalrc` | `~/.config/xfce4/terminal/terminalrc` | xfce4-terminal 1.0.x, including the loadout build |

The xfconf XML is the absorbed operator config (`xfconf-query -c
xfce4-terminal -l` shows the same twelve properties). `terminalrc` is its
translation for 1.0.4, whose rc reader takes each property's blurb as the key
(`terminal/terminal-preferences.c`).

Both files are **seeded once and then owned by the user**: xfce4-terminal
rewrites them when preferences change, so a reinstall leaves them untouched
and they stay writable. Delete a seeded file to have the next install recreate
it. Nothing else under `~/.config/xfce4` is touched -- install_path() runs per
file, not on the directory, so unrelated Xfce apps and xfconf channels are
never deleted.

## 1.2.0 -> 1.0.4 compatibility

Eleven of the twelve settings map exactly. `tests/install-env-xfce4-terminal`
enforces the mapping, so a new 1.2.0 property cannot silently ship without a
1.0.4 decision.

| 1.2.0 xfconf property | 1.0.4 terminalrc key | Notes |
|---|---|---|
| `scrolling-bar` | `ScrollingBar` | same enum names |
| `scrolling-on-keystroke` | `ScrollingOnKeystroke` | |
| `misc-copy-on-select` | `MiscCopyOnSelect` | |
| `misc-show-unsafe-paste-dialog` | `MiscShowUnsafePasteDialog` | |
| `font-use-system` | `FontUseSystem` | |
| `font-name` | `FontName` | |
| `text-blink-mode` | `TextBlinkMode` | same enum names |
| `misc-menubar-default` | `MiscMenubarDefault` | |
| `color-palette` | `ColorPalette` | 1.0.4 parses the `rgb()` form via `gdk_rgba_parse()` |
| `misc-right-click-action` | `MiscRightClickAction` | same enum names |
| `misc-highlight-urls` | `MiscHighlightUrls` | |
| `misc-maximize-default` | *(none)* | **not representable in 1.0.4** |

`MiscMaximizeDefault` does not exist in the 1.0.4 property table, so it is
intentionally absent from `terminalrc` (an unknown key would be ignored, and
writing a key the version cannot honour would be misleading). On 1.0.4 the
equivalent behaviour is the CLI flag `xfce4-terminal --maximize`; the xfconf
setting still applies to 1.1.0+ hosts.
