# Session handoff — 2026-10-02 (context flush)

## Repo state

`/home/mylesp/engineering-loadout`, branch `main`, **10 commits ahead of origin/main**, HEAD = `7d19b48`.

Recent commits (all verified green before landing):
- `7d19b48` tmux env: move persistence from resurrect+continuum to tmux-persist
- `9c9da2b` prettier 3.8.1 + yamlfmt 0.21.0: the last two conform.nvim formatters
- `e5c36ef` mdformat 1.0.0: markdown formatting actually works in env-nvim
- `f4f222f` librelane: verify the io_place fix end to end -- flow reaches stage 80
- `ba98fbc` librelane: patch io_place.py for the OpenROAD getArea() unit change

**IMPORTANT — there is UNCOMMITTED work in `envs/tmux/` that I did NOT create and have
not verified the provenance of:**

```text
envs/tmux/tmux-word-separators   (modified, +25 -4)
envs/tmux/tmux.conf               (modified, +2)
envs/tmux/tmux.global.conf        (modified, +26 -4)
envs/tmux/themes/                 (untracked: tmux_theme_loadout1.conf, tmux_theme_loadout2.conf)
envs/tmux/tmux-settings.conf      (untracked)
```

mtimes are 10-02 09:45–10:03 — i.e. *newer than my last commit*, and shaped like a
half-finished copy of the live config. **Confirm with the user whose these are before
building on them** (they may be another session's work-in-progress).

## The task in flight (not started)

> "treat my current tmux setup as golden and update the loadout env, with one change,
> make the loadout1 color theme the default setting."

## Facts needed to do it

### Live setup = `~/.config/tmux` (this is the "golden" source)

```text
tmux.conf  tmux-global.conf  tmux-settings-global.conf  tmux-settings-user.conf
tmux-user.conf  word-separators.conf
scripts/{shell-state-export.sh,tmux-3col-layout.sh,tmux-popin.sh,tmux-popout.sh}
themes/{tmux-theme-loadout1.conf (1488B), tmux-theme-loadout2.conf (4832B)}
plugins/            (tpm, tmux-persist, tmux-better-mouse-mode, tmux-yank)
~/.tmux -> .config/tmux/tmux    (symlink; recreated by the installer)
```

Live layer order (`~/.config/tmux/tmux.conf`, 454 B):
```tmux
source-file ~/.config/tmux/tmux-settings-global.conf
source-file ~/.config/tmux/tmux-settings-user.conf
source-file ~/.config/tmux/tmux-global.conf
source-file ~/.config/tmux/tmux-user.conf
run '~/.tmux/plugins/tpm/tpm'
```
(i.e. **settings layers are sourced first**, then global/user; tpm last.)

Live theme wiring (`tmux-global.conf` line 27):
```tmux
source-file -F "~/.config/tmux/themes/tmux-theme-#{@theme}.conf"
```
Live `@theme` values: **`tmux-settings-global.conf` → `loadout1`**,
**`tmux-settings-user.conf` → `loadout2`** (user layer wins, so live is effectively
loadout2).

### Live-vs-repo drift (the work to reconcile)

| | live | repo (HEAD `7d19b48`) |
| --- | --- | --- |
| theme files | `tmux-theme-<v>.conf` (hyphen) | `tmux_theme_<v>.conf` (underscore) |
| global conf | `tmux-global.conf` (10197 B) | `tmux.global.conf` (8158 B) |
| settings layer | `tmux-settings-global.conf` + `tmux-settings-user.conf` | `tmux-settings.conf` (one file) |
| word separators | `word-separators.conf` (14392 B) | `tmux-word-separators` |
| helper scripts | `scripts/` subdir | top-level `envs/tmux/*.sh` |
| `@theme` default | loadout1 (global) / loadout2 (user) | `loadout2` in `tmux-settings.conf` |

Note the repo working tree (uncommitted) has already moved toward the live shape:
`tmux-settings.conf` exists, `themes/` exists, and `tmux.global.conf` gained a
`source-file -F -q "~/.config/tmux/themes/tmux_theme_#{@theme}.conf"` line — but with
**underscore** naming, i.e. it does NOT yet match live.

The single requested change: **make `loadout1` the default theme.** In the live layout
the managed baseline already says `loadout1` and the user layer overrides to
`loadout2`; in the repo the single settings file says `loadout2`. Decide whether
"default" means only the managed baseline flips to loadout1 (keeping the user layer's
loadout2 as their choice) or the user-layer override is dropped too.

### Installer coupling (`loadout_main.py::_install_env_tmux`, ~line 4648)

- `remove_if_exists(~/.tmux.conf)` and `remove_if_exists(~/.tmux)`
- `sync_dir(envs/tmux/vendor/plugins -> ~/.config/tmux/tmux/plugins, delete=True)`
- `install_path` for: `tmux.conf`, `tmux.global.conf`, `tmux-3col-layout.sh`,
  `tmux-word-separators`, and helpers `shell-state-export.sh`/`tmux-popin.sh`/`tmux-popout.sh`
- `tmux-settings.conf` and `themes/` are **not** installed by any current call —
  if the live shape is adopted, `_install_env_tmux` must be extended (and
  `tests/install-linux-tmp-home` asserts the helper set).

### Verification recipe that worked (isolated server; never touch the live session)

```bash
H=/var/tmp/tmux-test; mkdir -p $H/home/.config/tmux/tmux $H/home/.tmux $H/persist
cp -r envs/tmux/vendor/plugins $H/home/.config/tmux/tmux/plugins
cp -r envs/tmux/vendor/plugins/. $H/home/.tmux/plugins/       # tpm TMUX_PLUGIN_MANAGER_PATH
cp envs/tmux/tmux.conf envs/tmux/tmux.global.conf $H/home/.config/tmux/
printf "set -g @persist-dir '%s'\n" "$H/persist" > $H/home/.config/tmux/tmux.user.conf
HOME=$H/home tmux -L probe -f $H/home/.config/tmux/tmux.conf new-session -d -s t
```
**`tmux kill-server` is blocked by a security hook** (it protects the live tmux). Kill
test servers by PID, matched on their `-L <socket>` name, never by bare name.

## Live-machine facts (do not disturb)

- Live tmux server **PID 561435** (up 2d23h), session `0` with **11 windows, attached**;
  client PID 2899723. Restarting it is the user's call.
- `~/.local/bin/tmux` is **3.7b**; payload ships **3.7c** (latest stable upstream).
  An update is **staged** at `/var/tmp/loadout-pending-mylesp/files/tmux` (sha256
  `7957dc7a…`, byte-identical to the payload binary) and lands when the server exits.
  Re-running `./loadout install tmux -y` re-stages; it will refuse while in use.
- `~/loadout_backups/backup.14.tar.bz2` is the pre-`env-tmux`-install snapshot of the
  old `~/.config/tmux` (contains only plugin code; **no** resurrect/continuum snapshot
  files ever existed).
- RAM is tight (31 GB total, ~14 GB available, 20 GB swap in use, ~8 GB Chrome).
  Multi-GB installs get SIGKILLed; prefer reusing existing dest dirs, and background
  long runs with `setsid` + polling rather than a single long foreground call.
- 2 stale DrKonqi dialogs were cleared; root-owned coredumps need
  `sudo rm -f /var/lib/systemd/coredump/*`.

## Gates for any env change

```bash
./loadout completion bash > envs/bash/global/completions/loadout.bash
build/build-shell bash -c 'cd /repo && PY=.loadout-bootstrap/bin/python3.14 && \
    $PY build/gen-installed-sizes && $PY build/gen-content-manifest && $PY build/gen-readme-table'
TMPDIR=/var/tmp ./tests/run-all --fast
TMPDIR=/var/tmp ./tests/install-linux-tmp-home        # asserts tmux env + RPATH
```
Order matters (completion → sizes → manifest); the pre-commit hook runs
`strip-all-elf-binaries` at commit time, so if it rewrites bytes the manifest must be
regenerated after.

## Docs to sync for a tmux-env change

`README.md` (Tmux row + prose), `docs/TMUX.md`, `AGENTS.md` (Tmux component line),
`.github/copilot-instructions.md` (vendored plugin list),
`payload/packages.json` `env-tmux.description`, and `docs/HANDOFF.md` (new top entry).

## Standing hazards learned this session

- **Verify a named tool/option actually exists before wiring it into config.** The
  formatter bug class (config named binaries that were never shipped; conform silently
  fell through) — now gated by `tests/nvim-formatters-resolve`.
- `gen-installed-sizes` hashes vendored plugin trees: sizes went 6198→6357 artifacts and
  the manifest 4452→4611 files after the tmux-persist swap.
- Indexed/batched grep output can mangle words (e.g. `theme` rendered as `n`); read
  files directly before trusting a quoted line.
