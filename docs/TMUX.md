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
tmux-continuum. Snapshots live in `~/.tmux/persist` (override with
`set -g @persist-dir '<path>'`) and older than 7 days are pruned
(`@persist-delete-backup-after`). Coming from resurrect, existing snapshots
are migrated on first load and unset `@persist-*` options fall back to the old
`@resurrect-*` names.

## Configuration layers

`~/.tmux.conf` links to the XDG dispatcher at
`~/.config/tmux/tmux.conf`. It sources the loadout-managed
`tmux.global.conf`, then the preserved `tmux.user.conf`, and initializes TPM
last so the user layer can declare plugins.

On a fresh install, loadout seeds `tmux.user.conf` only when it is absent. If
the older `~/.tmux.local.conf` exists, an interactive install offers to move
it; unattended or declined migrations keep loading it until the canonical
user layer exists. When both files exist, neither is changed and
`tmux.user.conf` wins.
