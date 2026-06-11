# Installation — Details

## Linux

```bash
git clone https://github.com/smprather/engineering-loadout.git
cd engineering-loadout
./loadout install @engineering-loadout
```

Single Python 3.6-compatible executable. Can be invoked from any working
directory — it resolves the repo from the script path.

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
| `~/.bashrc`, `~/.bash_profile`, `~/.bash_login`, `~/.profile` | → `bash/bashrc` |
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
| `~/.cache/tealdeer/tldr-pages/` | `tldr/tldr-pages.tar.bz2` |

After install, reload your shell:

```bash
exec bash
```

### Smoke testing

Simulate a completely fresh user environment:

```bash
./tests/install_linux_tmp_home
```

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

No elevation required. Files are copied, not symlinked — re-run
`.\loadout.ps1` after repo updates.

### Windows destinations

| Destination | Source |
|-------------|--------|
| `%LOCALAPPDATA%\nvim\` | `nvim/` |
| `%USERPROFILE%\.config\wezterm\wezterm.lua` | `wezterm/wezterm.lua` |
| `%USERPROFILE%\.config\starship\starship.toml` | `starship/starship.windows.toml` |
| `%USERPROFILE%\.editorconfig` | `editorconfig/editorconfig` |
| `%USERPROFILE%\autohotkey\hotkeys.ahk` | `autohotkey/hotkeys.ahk` (feature-patched) |
| `%USERPROFILE%\loadout_keys.toml` | Created if missing — choose AHK features |
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
