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
-> cold-bootstrap from `payload/<platform>/portable-python-*.tar.bz2`) and
execs `loadout_main.py` under it. No system Python is required -- `bzip2` +
`tar` (always present on EL8/Suse/Debian) are the only host prerequisites.
`loadout_main.py` enforces Python >= 3.14 via a `sys.version_info` gate.

### Subcommands & options

```bash
./loadout install @engineering-loadout        # install the curated bundled set
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
./loadout install @engineering-loadout --skip @fonts-all   # curated set minus fonts
./loadout install @engineering-loadout --skip tldr-data
./loadout install @engineering-loadout --skip gnuplot,micro
./loadout install vim nvim rg tmux            # install exactly this set
./loadout install gvim --no-deps              # install gvim verbatim, no dep walk
./loadout install gvim --dry-run              # resolve + print; no writes
```

### What gets installed

| Destination | Source |
|-------------|--------|
| `~/.bashrc`, `~/.bash_profile`, `~/.bash_login`, `~/.profile` | -> `envs/bash/bashrc` |
| `~/.config/bash/` | Layered bash config |
| `~/.vimrc` | `envs/vim/vimrc` |
| `~/.vim/` | `envs/vim/vim/` |
| `~/.tmux.conf` | `envs/tmux/tmux.conf` |
| `~/.tmux/` | `envs/tmux/vendor/plugins/` |
| `~/.editorconfig` | `envs/editorconfig/editorconfig` |
| `~/.config/nvim/` | `envs/nvim/` |
| `~/.config/starship/starship.toml` | `envs/starship/starship.linux.toml` + `envs/starship/config-schema.json` |
| `~/.config/helix/runtime/` | `payload/<platform>/runtime/helix.tar.bz2` |
| `~/.local/share/vim/vim92/` | `payload/<platform>/runtime/vim92.tar.bz2` |
| `~/.local/share/nvim/runtime/` | `payload/<platform>/runtime/nvim.tar.bz2` |
| `~/.local/bin/` | `payload/<platform>/bin/*.bz2` (decompressed) |
| `~/.local/lib64/` | `payload/<platform>/lib64/*.bz2` (decompressed) |
| `~/.local/bin/python3.14` | `payload/<platform>/portable-python-*.tar.bz2` |
| `~/.local/share/fonts/` | `payload/fonts/*.zip` (Nerd Font archives) |
| `~/.local/share/nvim/tree-sitter-parsers/` | 326 prebuilt Tree-sitter parsers |
| `~/.local/share/tealdeer/cache/tldr-pages/` | `payload/tldr/tldr-pages.tar.bz2` |

After install, reload your shell:

```bash
exec bash
```

### Smoke testing

Simulate a completely fresh user environment:

```bash
./tests/install-linux-tmp-home
```

### Shared / read-only deployments

For a single install shared by many users, do not mutate the live tree in
place. Install only the shared artifacts -- every package except the
per-user `env` config bundles -- with the synthetic `@shared` group:

```bash
./loadout install @shared \
  --dest-dir /opt/engineering-loadout/releases/2026-06-04.2
```

`@shared` = all non-`env`, non-`optional` packages (binaries, libs,
runtimes, fonts, data, python tools); `@shared-all` = the same with the
`optional: true` packages folded back in (surfer, cicwave, rust,
rust-crate-store) -- the full shared tree in one name. `@envs` = Bash
configuration only (plus its normal recommends), installed into each user's
`$HOME` with `./loadout install @envs`. Install other config bundles by
name, or use `@envs-all` when every shell and editor config is intentional.
Tools and config bundles are fully decoupled (no cross-`recommends`), so
`@shared` and `@envs` need no extra `--skip` / `--no-deps` flags. Preview
any set with `./loadout resolve @shared` / `@shared-all` / `@envs`.

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

The Neovim plugin **stash** (bare git mirrors of every bundled plugin) lives
in the shared tree, read-only, and each user's `lazy/` is cloned from it. It
is a **GitHub release asset**, not part of the release tarball -- fetch it once
into the checkout before staging the shared tree:

```bash
./fetch-stash                      # from the latest release, verified
./loadout install @shared-all --dest-dir /opt/engineering-loadout/releases/...
```

Refresh plugins later without a new loadout release with `./refresh-stash`, and
override the stash location with `LOADOUT_CFG_NVIM_PLUGIN_STASH_DIR` if needed.
Neovim itself needs `git` to clone from the stash; `git-nvim` (in `@shared-all`)
provides a private one for boxes with no system git. See the full behavior in
`CLAUDE.md` -> "nvim plugin stash delivery".

**Deploying to a farm or an air-gapped site** -- where the network policy varies
and a shared filesystem is read-only on the secure side -- is documented
step-by-step, per network state, in
[`docs/DEPLOYMENT-RUNBOOK.md`](DEPLOYMENT-RUNBOOK.md). That is the canonical ops
guide; this section is only the shared-tree mechanics.

### Symlink handling

Archive extraction and env config copying intentionally handle symlinks
differently:

- Runtime/archive extraction uses `--install-follows-symlinks`. The default
  (`auto`) follows an existing directory symlink only when its target is
  writable; otherwise it removes the symlink and creates a real directory. Use
  `--install-follows-symlinks=yes` to always write into symlink targets, or
  `=no` to always replace them with real directories.
- Env config installs (including `@envs` for Bash and explicitly named
  bundles such as `env-nvim`) always copy config into the target HOME and
  replace symlinked config subdirectories with real
  directories. This is deliberate: stale links such as
  `~/.config/nvim/lsp -> ~/dotfiles/nvim/lsp` must not let delete-style config
  sync mutate the repository checkout.

Backups/snapshots can restore displaced user files when backups are enabled.

### Corporate / site add-ons

```bash
./loadout install @engineering-loadout \
  --post-install-hook ~/corp-dotfiles/install.sh \
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

**Recommended:**

```powershell
.\loadout.cmd
# or: pwsh -NoProfile -ExecutionPolicy Bypass -File .\loadout.ps1
```

`.\loadout.cmd` prefers `%USERPROFILE%\.local\opt\powershell\7\pwsh.exe`.
If it is missing and no `pwsh.exe` is already on `PATH`, it uses Windows
PowerShell 5.1 to extract the bundled PowerShell ZIP and then re-runs the
installer under that user-local `pwsh.exe`.

**Explicit Windows PowerShell 5.1 bootstrap:**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\loadout-pwsh-bootstrap.ps1
.\loadout.cmd
```

No elevation required. Files are copied, not symlinked -- re-run
`.\loadout.cmd` or `.\loadout.ps1` after repo updates.

### Windows destinations

| Destination | Source |
|-------------|--------|
| `%LOCALAPPDATA%\nvim\` | `envs/nvim/` |
| `%USERPROFILE%\.config\wezterm\wezterm.lua` | `envs/wezterm/wezterm.lua` |
| `%USERPROFILE%\.config\starship\starship.toml` | `envs/starship/starship.windows.toml` |
| `%USERPROFILE%\.editorconfig` | `envs/editorconfig/editorconfig` |
| `%USERPROFILE%\autohotkey\hotkeys.ahk` | `envs/autohotkey/hotkeys.ahk` (feature-patched) |
| `%USERPROFILE%\loadout_keys.toml` | Created if missing -- choose AHK features |
| `%USERPROFILE%\.local\opt\powershell\7\` | Bundled PowerShell ZIP from `payload/windows.x86_64/powershell/` |
| `%LOCALAPPDATA%\Microsoft\Windows Terminal\Fragments\engineering-loadout\powershell.json` | Windows Terminal profile for bundled PowerShell |
| PowerShell profile (5.1 + 7+) | `envs/powershell/Microsoft.PowerShell_profile.ps1` |

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

### AutoHotKey feature settings

The Cisco Secure Client automation can skip VPN login attempts on named Wi-Fi
networks. Add exact SSID names under `%USERPROFILE%\loadout_keys.toml`:

```toml
[autohotkey.features.cisco-secure-client-vpn]
skip_wifi_ssids = [
  "Home WiFi",
  "Phone Hotspot",
]
```
