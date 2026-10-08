# Tmux

Prefix: **`Ctrl-\`** (not `Ctrl-b` -- your fingers will thank you)

| Binding | Action |
|---------|--------|
| `Shift+<-/->/^/v` | Navigate panes |
| `Prefix+<-/->/^/v` | Resize pane (repeatable) |
| `Ctrl+<-/->` | Previous/next window |
| `Ctrl+Shift+<-/->` | Reorder windows |
| `Prefix+1-5` | Layout presets |
| `Prefix+6` | Reapply the 3-column layout |
| `Prefix+o` | New seven-pane 3-column work window |
| `Prefix+v` | Capture pane buffer -> nvim |
| `Prefix+r` | Reload config |
| `Prefix+X` | Confirm-before kill-session |
| `Prefix+Ctrl-s` | Save session (tmux-persist) |
| `Prefix+Ctrl-r` | Restore session (tmux-persist) |

tmux-persist ([hyoretsu/tmux-persist](https://github.com/hyoretsu/tmux-persist),
the maintained fork of the abandoned tmux-resurrect) auto-saves pane contents
and layout per session on detach/exit/start, and restores a session when one of
the same name is created -- so this replaces both tmux-resurrect and
tmux-continuum. Snapshots live under `${XDG_DATA_HOME:-~/.local/share}/tmux/`
(override with `set -g @persist-dir '<path>'`) and older than 7 days are pruned
(`@persist-delete-backup-after`). Coming from resurrect, existing snapshots
are migrated on first load and unset `@persist-*` options fall back to the old
`@resurrect-*` names.

## Configuration layers

tmux reads the dispatcher natively from
`~/.config/tmux/tmux.conf` (tmux >= 3.1; no `~/.tmux.conf` symlink). It sources
the loadout-managed
`tmux-settings-global.conf`, then the preserved `tmux-settings-user.conf`
(which wins), then the managed `tmux-global.conf`, then the preserved
`tmux-user.conf`, and initializes TPM last so the user layer can declare
plugins. Plugins live at `~/.config/tmux/plugins/` -- TPM's own XDG location;
the dispatcher's `run` line and the `TMUX_PLUGIN_MANAGER_PATH` pin in
`tmux-global.conf` both point there, and there is no `~/.tmux` symlink. The settings layers hold user-facing knobs -- the
`@theme` choice (defaulting to `loadout1`) and the `focus-follows-mouse`
default (off) -- and the global layer loads the
selected `themes/tmux-theme-<name>.conf` plus the generated
`word-separators.conf` (regenerate with `scripts/tmux-word-separators`).
Helper scripts live in `scripts/`.

## Focus follows mouse (FFM)

`focus-follows-mouse` (tmux >= 3.7, and the bundled tmux is 3.7c) focuses the
pane under the mouse pointer on hover, no click needed. The managed baseline
sets it **off**; opt in per user in `tmux-settings-user.conf`, which is
sourced after the baseline and therefore wins:

```tmux
set -g focus-follows-mouse on
```

It needs mouse mode, which `tmux-global.conf` already turns on.

On a fresh install, loadout seeds `tmux-user.conf` and
`tmux-settings-user.conf` only when absent. If
the older `~/.tmux.local.conf` exists, an interactive install offers to move
it; the legacy file is no longer loaded, so unattended or declined migrations
need a manual move into `tmux-user.conf`. When both files exist, neither is changed and
`tmux-user.conf` wins.
