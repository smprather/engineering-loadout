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
| `Prefix+Ctrl-s` | Save session (resurrect) |
| `Prefix+Ctrl-r` | Restore session (resurrect) |

tmux-continuum auto-saves every 60 minutes.

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
