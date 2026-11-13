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
| `Prefix+7` | Reapply the 3-column layout with the previous pane pinned left |
| `Prefix+o` | New seven-pane 3-column work window |
| `Prefix+v` | Capture pane buffer -> nvim |
| `Prefix+r` | Reload config |
| `Prefix+X` | Confirm-before kill-session |
| `Prefix+Ctrl-s` | Save session (tmux-persist) |
| `Prefix+Ctrl-r` | Restore session (tmux-persist) |

tmux-persist ([hyoretsu/tmux-persist](https://github.com/hyoretsu/tmux-persist),
the maintained fork of the abandoned tmux-resurrect) auto-saves pane contents
and layout per session on detach/exit/start, and restores a session when one of
the same name is created -- so this replaces tmux-resurrect and tmux-continuum's
automatic restore. It does not replace continuum's periodic save: no clean
detach/exit means no save, so a hard crash loses everything since the last one.
See *Autosave across crashes* below. Snapshots live under
`${XDG_DATA_HOME:-~/.local/share}/tmux/`
(override with `set -g @persist-dir '<path>'`) and older than 7 days are pruned
(`@persist-delete-backup-after`). Coming from resurrect, existing snapshots
are migrated on first load and unset `@persist-*` options fall back to the old
`@resurrect-*` names.

## Autosave across crashes (tmux-persist-autosave)

tmux-persist saves on clean detach/exit/start and when a session is created. A
hard crash while a client is still attached triggers none of those, and a
session with no attached client never reaches the status-line save at all. The
companion
[tmux-persist-autosave](https://github.com/theredspoon/tmux-persist-autosave)
runs tmux-persist's `scripts/save.sh` from a systemd timer. It is not vendored
and has no installer here.

The helper defaults to `~/.tmux/plugins/tmux-persist`, the pre-XDG location,
and exits 0 with a `skipped` line when the directory is absent -- so the timer
can look healthy while saving nothing after `env-tmux` moves the tree to
`~/.config/tmux/plugins`. If `~/.local/bin/persist-autosave.sh` and
`~/.config/systemd/user/tmux-persist-autosave.service` already exist,
`loadout install env-tmux` writes
`~/.config/systemd/user/tmux-persist-autosave.service.d/50-loadout-plugin-path.conf`:

```ini
[Service]
Environment=TMUX_PERSIST_PLUGIN_DIR=%h/.config/tmux/plugins/tmux-persist
```

The installer reloads the user manager (`systemctl --user daemon-reload`) after
writing the drop-in when the target HOME is the live user home; if no user
manager is reachable it prints the command to run. Env-only `--dest-dir`
staging writes the drop-in into the staged HOME but skips the reload (the live
manager cannot see that tree). A hand-wired timer needs the same drop-in. If
the helper lives elsewhere, set `TMUX_PERSIST_PLUGIN_DIR` to that directory in
a drop-in instead.
`loadout doctor` reports user units and drop-ins that still reference
`~/.tmux/plugins`. Do not recreate `~/.tmux`: the retired layout is not
supported.

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
`@theme` choice (defaulting to `loadout2`, the fixed dark tmux 3.8 theme;
`loadout1` is the pre-2026-10-01 rollback) and the
`focus-follows-mouse` default (on) -- and the global layer loads the
selected `themes/tmux-theme-<name>.conf` plus the generated
`word-separators.conf` (regenerate with `scripts/tmux-word-separators`).
Helper scripts live in `scripts/`.

### Themes (tmux 3.8)

Each theme file is a real tmux 3.8 theme: it sets the server-scoped `theme`
option, fills the ten `dark-theme-*` (loadout2) or dark/light (loadout1)
palette slots, and writes styles with the `themeblack`/`themewhite`/...
colour names.

- **loadout2** is `theme dark` with a literal-hex palette. Forcing the mode
  means it does not follow the terminal's light/dark report; colours with no
  palette slot -- the pane fills, the peach message fill, the frame and dim
  greys -- stay literal hex, so the render is identical on every terminal.
- **loadout1** is `theme terminal` with an ANSI-name palette. Its old
  `red`/`blue`/`white`/`black` styles now use the equivalent theme names and
  still resolve against the terminal palette, preserving the rollback
  appearance.

The palette also feeds tmux's built-in UI that this config does not pin
(tree selection, fill character, display-panes border, copy-mode defaults),
so those components stay inside the same design. Because the theme file runs
after the settings layers, its `theme` choice is part of the theme. loadout2
supports `dark` only: it defines no `light-theme-*` slots and its pane fills
are literal, so overriding it to `detect`, `light`, or `terminal` in
`tmux-user.conf` is unsupported -- the palette would leave the design while
the fills stayed dark. loadout1 is safe under any mode because both of its
palettes are ANSI names. Themes require tmux 3.8; the bundled tmux is 3.8.

The seeded `tmux-settings-user.conf` documents the choice and defaults to
`loadout2`. It is seeded when absent **or empty**, so a zero-byte file cannot
hide the theme section; a non-empty file is always preserved.

### Permissions

The managed tree is read-only: `tmux.conf`, `tmux-settings-global.conf`,
`tmux-global.conf`, `word-separators.conf` (0444), and `themes/`, `scripts/`,
`plugins/` (0555, executable files stay executable). Writable: the two user
layers (`tmux-settings-user.conf`, `tmux-user.conf`), the top-level
`~/.config/tmux` directory, and `plugins-local/` (0755, created empty at
install; see *Local (non-vendored) plugins*). Managed files are replaced by the
next `loadout install env-tmux`; edit the repo (or the user layers), not the
installed managed files.

## Optional plugins (`tmux-yank`)

[tmux-yank](https://github.com/tmux-plugins/tmux-yank) copies selections to the
system clipboard (and yanks paths/URLs out of the pane). It is **off by
default**: it needs a clipboard tool on the host (`xclip`/`xsel` for X11,
`wl-copy` for Wayland) and a session that actually reaches a clipboard, which
headless farm nodes do not have; it also takes over the default copy behaviour.

The plugin ships **vendored** at `envs/tmux/vendor/plugins/tmux-yank` (installed
to `~/.config/tmux/plugins/tmux-yank`), so enabling it works offline -- TPM sees
the directory already present and skips cloning. Enable it in the preserved user
layer:

```tmux
# ~/.config/tmux/tmux-user.conf
set -g @plugin 'tmux-plugins/tmux-yank'
```

then reload (`Prefix+r` -- TPM runs on every config load) or restart tmux.

One caveat: `build/update tmux-plugins` discovers `set -g @plugin` declarations
in the managed `tmux-global.conf` only, so a user-layer declaration is **not**
refreshed by the updater. The vendored copy stays at the version in the repo
until the global layer declares it (or you update it yourself).

For a plugin that is **not** vendored here, `@plugin` cannot work: TPM clones
into the read-only `plugins/` tree. Use `plugins-local/` and `run-shell`
instead -- see *Local (non-vendored) plugins* below.

## Local (non-vendored) plugins

`plugins/` is the vendored, sealed tree. TPM clones `@plugin` declarations into
it, and `sync_dir` replaces its contents on every `loadout install env-tmux`, so
anything you clone there is lost. A plugin that loadout does not vendor
therefore belongs in `plugins-local/`: `env-tmux` creates it empty (0755),
never replaces it, never prunes it, and never seals it. Source the plugin's
entry point from the preserved user layer:

```tmux
# ~/.config/tmux/tmux-user.conf -- plugin options FIRST, entry LAST
set -g @example-plugin-opt 'off'
run-shell 'bash ~/.config/tmux/plugins-local/example/example.tmux'
```

Ordering is load-bearing: the entry reads its `@...` options when it is
sourced, so an option set after the `run-shell` line is ignored. Updating the
clone is your job (`git pull` in it): `build/update tmux-plugins` reads the
managed layer's `@plugin` declarations only, exactly as for a user-layer
`@plugin`. A clone in `plugins-local/` is outside `plugins/`, so
`TMUX_PLUGIN_MANAGER_PATH` (pinned to `plugins/`) never sees it.

### Hook names reserved by tmux-persist

`tmux-persist` reads `@persist-hook-post-save-all` and
`@persist-hook-post-restore-all` and falls back to the legacy
`@resurrect-hook-*` names **only while the `@persist-*` name is unset**
(`scripts/helpers.sh`, `get_tmux_option`). The managed layers therefore never
set either name: a managed value would silently disable every external
post-save/post-restore hook -- including a `plugins-local/` plugin whose only
symptom is that nothing is restored after a reboot. `tests/tmux-managed-hook-names`
(Tier 1) pins that. If the managed layer ever needs one of those hooks, it must
**chain** the existing value rather than shadow it.

## Mouse wheel and cursor

The cursor is pinned to a steady block (`set -g -w cursor-style block`):
alacritty only applies its `[cursor] style.shape` when a terminal is created,
and an application can override it with DECSCUSR -- while tmux's cursor-style is
enforced on every draw.

Wheel scrolling moves **three lines per notch** (stock tmux uses five) and
leaves copy-mode when the bottom is reached, independent of how the mode was
entered. Entry takes `-e` where it can (`Prefix+[`, `Prefix+PgUp`, and the bare
`PgUp` binding -- which used to enter with plain `copy-mode -u`, so the wheel
stalled at the bottom); inside copy-mode `PgDn`/`C-f` send `scroll-exit-on`
before `page-down`, and both wheel-down bindings send it before `scroll-down`
(`%if`-guarded to tmux >= 3.7, where that copy-mode command first appeared), so
even a command-line `copy-mode` exits. `j`, `Down` and `G` do not consult
`scroll_exit`, so they carry their own test: they leave copy-mode when the view
is already at the live bottom and the cursor is on the last row, and when a
scroll-back move reaches the bottom. An active selection keeps the mode alive in
every case -- `v` + `Down` extends it, and a wheel scroll with a selection only
moves the view. `Esc` and `Enter` both leave copy-mode (`Enter` copies;
`Esc` cancels -- stock `copy-mode-vi` bound it to `clear-selection`, which left
the pane in the mode); `C-c` and `q` also cancel.

The bundled `better-mouse-mode` plugin is **not declared** (dropped 2026-10-20),
so the managed root-wheel binds above are the ones in effect. They fix a
first-wheel-up case the plugin gets wrong; the copy-mode binds are owned by the
managed layer, not the plugin. The plugin remains vendored only as historical
payload.

The managed layer sets `default-terminal` from `LOADOUT_CFG_TMUX_TERM`
(default `xterm-256color`, exported by the bash/tcsh config), falling back to
`xterm-256color` when the server was started outside a loadout shell. A
`client-attached` hook re-applies the attaching client's value, so a changed
setting reaches new panes after the next attach; existing panes keep their
TERM. The layer also sets `allow-passthrough on`, and marker-guards the
`terminal-overrides` / `terminal-features` array appends so a reload cannot
grow them.

The managed layer deliberately does **not** pin `default-shell`: new windows
and panes use tmux's normal `$SHELL`/passwd default, so a tcsh login gets tcsh
panes. Helpers that need bash (`tmux-popout`, the layout/state scripts) invoke
it explicitly.

Panes are login shells started from `$SHELL`, which is how
`LOADOUT_CFG_INTERACTIVE_SHELL` (README, "Choosing your interactive shell")
reaches them without a pin. A server started before the change still switches
pane by pane: each new pane is the passwd shell as a login shell, and its rc
execs the chosen shell. A server started from a switched shell runs the chosen
shell directly, and its global environment carries the marker
`LOADOUT_SHELL_EXEC`, so after a later change its new panes keep the old shell.
To migrate such a server, never `kill-server` (it destroys every session):

```bash
tmux set -g default-shell /path/to/new/shell   # new panes start the new shell
tmux set-environment -gu LOADOUT_SHELL_EXEC    # new panes start the old shell, which then switches
```

`EXTENDED_KEYS_SUPPORTED` is exported by bash/zsh/tcsh from the same
`check_extended_keys` logic: kitty/alacritty and an existing tmux server whose
`extended-keys` is already on are answered cheaply; otherwise a Secondary-DA
probe runs, refusing to consume pending type-ahead. tcsh runs the probe through
`envs/tcsh/global/helpers/check-extended-keys`, so a bare xterm login now
exports `0` like bash instead of leaving the variable unset. The config only
forces `extended-keys off` when the variable is explicitly `0`; an unset value
leaves the default `extended-keys on` alone, so a tcsh login never disables
extended keys server-wide.

## Focus follows mouse (FFM)

`focus-follows-mouse` (tmux >= 3.7, and the bundled tmux is 3.8) focuses the
pane under the mouse pointer on hover, no click needed. The managed baseline
sets it **on**; opt out per user in `tmux-settings-user.conf`, which is
sourced after the baseline and therefore wins:

```tmux
set -g focus-follows-mouse off
```

It needs mouse mode, which `tmux-global.conf` already turns on.

On a fresh install, loadout seeds `tmux-user.conf` only when absent, and
`tmux-settings-user.conf` when absent or empty; a non-empty settings layer is
preserved. If the older `~/.tmux.local.conf` exists, an interactive install
offers to move it; the legacy file is no longer loaded, so unattended or
declined migrations need a manual move into `tmux-user.conf`. When both files
exist, neither is changed and `tmux-user.conf` wins.
