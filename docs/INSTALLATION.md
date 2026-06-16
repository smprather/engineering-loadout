# Installation -- Details

## Linux

End users install from the release tarball:

```bash
tar xzf engineering-loadout-v*.tar.gz
cd engineering-loadout-v*/
./loadout install @engineering-loadout
```

Repo developers can also `git clone` and run `./loadout` from a checkout --
the script resolves the repo from its own path and works from any cwd.

`./loadout` is a POSIX-sh shim (~80 lines) that resolves a Python 3.14
interpreter (`~/.local/bin/python3.14` -> `<repo>/.loadout-bootstrap/bin/python3.14`
-> cold-bootstrap from `pre_built/<platform>/portable-python-*.tar.bz2`) and
execs `loadout_main.py` under it. No system Python is required -- `bzip2` +
`tar` (always present on EL8/Suse/Debian) are the only host prerequisites.
`loadout_main.py` enforces Python >= 3.14 via a `sys.version_info` gate.

### Subcommands & options

```bash
./loadout install @engineering-loadout        # install the full bundled set
./loadout list                                # show all packages
./loadout list --groups                       # show all @groups
./loadout list --tag editor                   # filter packages by tag
./loadout search vim                          # case-insensitive substring search
./loadout info gvim                           # full package metadata + reverse-deps
./loadout info @core-cli                      # group membership
./loadout resolve gvim                        # dry-run resolver, prints set by kind
./loadout doctor                              # platform + registry integrity check
./loadout snapshot list
./loadout snapshot restore loadout_backups/backup.1.tar.bz2

./loadout install @engineering-loadout --dest-dir /tmp/test-home
./loadout install @engineering-loadout --no-backup
./loadout install @engineering-loadout --post-install-hook ~/corp/install.sh
./loadout install octave                      # single package; deps auto-pulled
./loadout install @gui-suite                  # group; expands recursively
./loadout install @engineering-loadout --skip @fonts-all   # full set minus fonts
./loadout install @engineering-loadout --skip tldr-data
./loadout install @engineering-loadout --skip gnuplot,micro
./loadout install vim nvim rg tmux            # install exactly this set
./loadout install gvim --no-deps              # install gvim verbatim, no dep walk
./loadout install gvim --dry-run              # resolve + print; no writes
```

### What gets installed

| Destination | Source |
|-------------|--------|
| `~/.bashrc`, `~/.bash_profile`, `~/.bash_login`, `~/.profile` | -> `bash/bashrc` |
| `~/.config/bash/` | Layered bash config |
| `~/.vimrc` | `vim/vimrc` |
| `~/.vim/` | `vim/vim/` |
| `~/.tmux.conf` | `tmux/tmux.conf` |
| `~/.tmux/` | `tmux/tmux/` |
| `~/.editorconfig` | `editorconfig/editorconfig` |
| `~/.config/nvim/` | `nvim/` |
| `~/.config/starship/starship.toml` | `starship/starship.linux.toml` + `starship/config-schema.json` |
| `~/.config/helix/runtime/` | `pre_built/<platform>/runtime/helix.tar.bz2` |
| `~/.local/share/vim/vim92/` | `pre_built/<platform>/runtime/vim92.tar.bz2` |
| `~/.local/share/nvim/runtime/` | `pre_built/<platform>/runtime/nvim.tar.bz2` |
| `~/.local/bin/` | `pre_built/<platform>/bin/*.bz2` (decompressed) |
| `~/.local/lib64/` | `pre_built/<platform>/lib64/*.bz2` (decompressed) |
| `~/.local/bin/python3.14` | `pre_built/<platform>/portable-python-*.tar.bz2` |
| `~/.local/share/fonts/` | `fonts/*.zip` (Nerd Font archives) |
| `~/.local/share/nvim/tree-sitter-parsers/` | 326 prebuilt Tree-sitter parsers |
| `~/.local/share/tealdeer/cache/tldr-pages/` | `tldr/tldr-pages.tar.bz2` |

After install, reload your shell:

```bash
exec bash
```

### Smoke testing

Simulate a completely fresh user environment:

```bash
./tests/install_linux_tmp_home
```

### Shared / read-only deployments

For a single install shared by many users, do not mutate the live tree in
place. Install only the shared artifacts -- every package except the
per-user `env` config bundles -- with the synthetic `@shared` group:

```bash
./loadout install @shared \
  --dest-dir /opt/engineering-loadout/releases/2026-06-04.2
```

`@shared` = all non-`env` packages (binaries, libs, runtimes, fonts, data,
python tools); its complement `@envs` = the config bundles each user
installs into their own `$HOME` with `./loadout install @envs`. Tools and
config bundles are fully decoupled (no cross-`recommends`), so `@shared`
and `@envs` need no extra `--skip` / `--no-deps` flags. Preview either set
with `./loadout resolve @shared` / `./loadout resolve @envs`.

Install each release into a versioned directory and atomically move a
stable symlink only after the new tree is complete:

```text
/opt/engineering-loadout/releases/2026-06-04.1/
/opt/engineering-loadout/releases/2026-06-04.2/
/opt/engineering-loadout/current -> /opt/engineering-loadout/releases/2026-06-04.2
```

```bash
ln -s /opt/engineering-loadout/releases/2026-06-04.2 /opt/engineering-loadout/.current.new
mv -Tf /opt/engineering-loadout/.current.new /opt/engineering-loadout/current
```

This avoids `Text file busy` failures from users running old binaries while
an update is unpacked. Existing processes keep their old inodes; new shells
resolve the new `current` target. Keep the previous release for rollback
and delete old releases only after no users still need them. `tmux` is a
special case -- clients and the server must agree on protocol / version, so
restart the tmux server before switching users to a tmux update.

Neovim catalog plugin source can live in the shared release tree instead of
every user's `~/.local/share/nvim`. Keep it read-only:

```bash
export LOADOUT_CFG_NVIM_PLUGIN_CATALOG_DIR=/opt/engineering-loadout/current/share/nvim/catalog-plugins
```

Users still enable catalog plugins in their Neovim user layer; this setting
only changes where `lazy.nvim` reads plugin source from. Plugins with build
steps must be prebuilt in the release tree or kept disabled from the shared
catalog.

### Symlink handling

If `$HOME` has existing symlinks where the loadout needs to create
directories (e.g. `~/.terminfo -> /usr/share/terminfo`), the default
(`--install-follows-symlinks=auto`) follows the symlink when its target is
writable, and otherwise removes the symlink and creates a real directory in
its place. Use `--install-follows-symlinks=yes` to always write into the
symlink target, or `=no` to always replace it with a real directory. The
displaced symlink is backed up and can be restored with
`./loadout snapshot restore`.

### Corporate / site add-ons

```bash
./loadout --post-install-hook ~/corp-dotfiles/install.sh \
           --post-install-hook ~/site-dotfiles/install.sh
```

Hooks receive these environment variables: `LOADOUT_REPO`, `LOADOUT_HOME`,
`LOADOUT_BACKUP_DIR`, `LOADOUT_DEST_DIR`, `LOADOUT_NO_BACKUP`.

### Restore a backup

```bash
./loadout snapshot restore loadout_backups/backup.1.tar.bz2
./loadout snapshot list                          # browse existing snapshots
./loadout snapshot create my-baseline            # take a snapshot without installing
```

Numbered backups are created in `loadout_backups/backup.N/` before each
install (numbering always starts at `.1`). At the end of a successful run
the backup dir is compressed to `loadout_backups/backup.N.tar.bz2` and
the uncompressed dir is removed. `snapshot restore` accepts either the
uncompressed dir or the `.tar.bz2` archive. Font files are excluded from
snapshots (large and reproducible).

## Windows

**PowerShell 7+ (recommended):**

```powershell
.\loadout.ps1
```

**Starting from Windows PowerShell 5.1:**

```powershell
.\loadout-pwsh-bootstrap.ps1   # installs pwsh via winget
# then reopen as pwsh:
.\loadout.ps1
```

No elevation required. Files are copied, not symlinked -- re-run
`.\loadout.ps1` after repo updates.

### Windows destinations

| Destination | Source |
|-------------|--------|
| `%LOCALAPPDATA%\nvim\` | `nvim/` |
| `%USERPROFILE%\.config\wezterm\wezterm.lua` | `wezterm/wezterm.lua` |
| `%USERPROFILE%\.config\starship\starship.toml` | `starship/starship.windows.toml` |
| `%USERPROFILE%\.editorconfig` | `editorconfig/editorconfig` |
| `%USERPROFILE%\autohotkey\hotkeys.ahk` | `autohotkey/hotkeys.ahk` (feature-patched) |
| `%USERPROFILE%\loadout_keys.toml` | Created if missing -- choose AHK features |
| PowerShell profile (5.1 + 7+) | `powershell/Microsoft.PowerShell_profile.ps1` |

### AutoHotKey feature flags

Edit `%USERPROFILE%\loadout_keys.toml`:

| Feature | Description |
|---------|-------------|
| `corp-logins` | Corp credential entry hotkeys |
| `mouse-wiggle` | Idle mouse nudge to prevent lock screens |
| `cisco-secure-client-vpn` | Cisco Secure Client auto-reconnect |
| `password-manager` | Password manager quick-type hotkey |
| `tmux-hotkeys` | `RAlt`/`RWin` zoom toggle, `Ctrl+;` last-pane toggle |
| `f1f2f3-as-mouse-buttons` | F1/F2/F3 mouse remaps for mspaint/etxc/wezterm-gui |
| `thinlinc-reconnect` | Auto-dismiss ThinLinc errors and reconnect |
