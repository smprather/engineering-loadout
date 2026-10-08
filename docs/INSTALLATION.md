# Installation -- Details

## Linux

End users install from the release tarball:

```bash
tar xzf engineering-loadout-v*.tar.gz
cd engineering-loadout-v*/
./loadout install @shared-all              # bundled tools, fonts, runtimes
./loadout install @envs-all                # per-user shell/editor configs
```

The shared tree installs to the **install root** -- by default
`$XDG_DATA_HOME/loadout` (`~/.local/share/loadout`); per-user configuration,
caches and Neovim data always stay under the real `$HOME`. Repo developers can
also `git clone` and run `./loadout` from a checkout -- the script resolves the
repo from its own path and works from any cwd.

`./loadout` is a POSIX-sh shim (~80 lines) that resolves a Python 3.14
interpreter (an installed `<prefix>/bin/python3.14` ->
`<repo>/.loadout-bootstrap/bin/python3.14`
-> cold-bootstrap from `payload/<platform>/portable-python-*.tar.bz2`) and
execs `loadout_main.py` under it. No system Python is required -- `bzip2` +
`tar` (always present on EL8/Suse/Debian) are the only host prerequisites.
`loadout_main.py` enforces Python >= 3.14 via a `sys.version_info` gate, and the
source uses PEP 758 syntax (`except A, B:` without parentheses; `except (A, B) as e:`
still when binding) -- a pre-3.14 interpreter cannot parse the file at all, so always
run it under the bundled interpreter or another 3.14+ build.

### Subcommands & options

```bash
./loadout install @shared-all                 # install every bundled tool (shared tree)
./loadout install @envs-all                   # install every per-user config bundle
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

./loadout install @shared-all @envs-all --dest-dir /tmp/test-home
./loadout install @shared-all @envs-all --no-backup
./loadout install @shared-all @envs-all --post-install-hook ~/corp/install.sh
./loadout install octave                      # single package; deps auto-pulled
./loadout install @gui-suite                  # group; expands recursively
./loadout install @shared-all --skip @fonts-all   # all tools minus fonts
./loadout install @shared-all --skip tldr-data
./loadout install @shared-all --skip gnuplot,micro
./loadout install vim nvim rg tmux            # install exactly this set
./loadout install gvim --no-deps              # install gvim verbatim, no dep walk
./loadout install gvim --dry-run              # resolve + print; no writes
```

### What gets installed

The install root (`<prefix>`: default `$XDG_DATA_HOME/loadout`, or the
`--dest-dir` / `config.toml` value) holds the shared payload. Per-user
configuration and state always go under the real `$HOME`.

Shared tree (`<prefix>`):

| Destination | Source |
|-------------|--------|
| `<prefix>/bin/` | `payload/<platform>/bin/*.bz2` (decompressed) |
| `<prefix>/lib64/` | `payload/<platform>/lib64/*.bz2` (decompressed) |
| `<prefix>/bin/python3.14` | `payload/<platform>/portable-python-*.tar.bz2` |
| `<prefix>/share/helix/runtime/` | `payload/<platform>/runtime/helix.tar.bz2` |
| `<prefix>/share/vim/vim92/` | `payload/<platform>/runtime/vim92.tar.bz2` |
| `<prefix>/share/nvim/runtime/` | `payload/<platform>/runtime/nvim.tar.bz2` |
| `<prefix>/share/terminfo/` | `payload/<platform>/runtime/st.tar.bz2` |
| `<prefix>/share/nvim/tree-sitter-parsers/` | 326 prebuilt Tree-sitter parsers |
| `<prefix>/share/nvim/loadout/vendor/plugin-stash/` | `nvim-plugin-stash` |
| `<prefix>/share/tealdeer/cache/tldr-pages/` | `payload/tldr/tldr-pages.tar.bz2` |

Per-user (`$HOME`):

| Destination | Source |
|-------------|--------|
| `~/.bashrc`, `~/.bash_profile` | -> `envs/bash/bashrc` |
| `~/.config/bash/` | Layered bash config |
| `~/.config/vim/{vimrc,pack,after}/` | `envs/vim/` -- read natively by vim >= 9.0 (XDG); no `~/.vimrc`/`~/.vim` symlinks |
| `~/.config/tmux/tmux.conf` | managed dispatcher, read natively by tmux >= 3.1 (settings-global -> settings-user -> `tmux-global.conf` then preserved `tmux-user.conf`; no `~/.tmux.conf` symlink) |
| `~/.config/tmux/plugins/` | `envs/tmux/vendor/plugins/` (TPM's XDG path; no `~/.tmux` symlink) |
| `~/.editorconfig` | `envs/editorconfig/editorconfig` |
| `~/.config/nvim/` | `envs/nvim/` |
| `~/.config/helix/` | `envs/helix/` |
| `~/.config/starship/starship.toml` | `envs/starship/starship.linux.toml` + `envs/starship/config-schema.json` |
| `~/.local/share/fonts/` | `payload/fonts/*.zip` (Nerd Font archives; a shared tree outside `$HOME` installs them once to `<prefix>/share/fonts` instead, with a generated `<prefix>/etc/fonts/loadout-fonts.conf`) |
| `~/.local/share/nvim/lazy/`, `~/.local/state/nvim/` | per-user plugin clones and Neovim state |
| `~/.config/engineering-loadout/config.toml` | your `dest_dir` / `prefer` / `prefer_off` settings |

`~/.profile` is **not** the bashrc: it is a POSIX shim (`~/.config/bash/profile`) that
sources the bash environment only under bash. RHEL-family X sessions read `~/.profile`
(`/etc/X11/xinit/Xsession` → `xinitrc-common`: `[ -r $HOME/.profile ] && . $HOME/.profile`),
which is how a `startx`/X11 session gets the loadout PATH and terminfo; POSIX login
shells (dash) read it too, where sourcing the bash-only bashrc would be a syntax error
that aborts the caller. `.bash_login` (bash) and `.cshrc` (tcsh) are **retired
entrypoints**: `.bash_login` is unreachable while `.bash_profile` exists, and only plain
csh reads `.cshrc`. A pre-2026-10-08 install's links are pruned on the next `@envs` run
(and stay in the backup list for one release); a legacy `~/.profile` → `bashrc` link is
healed to the shim.

With `dest_dir = "~"` (legacy HOME mode) the shared entries gain a `.local`
level (`~/.local/bin/`, `~/.local/lib64/`, `~/.local/share/...`); the per-user
entries are unchanged.

After install, reload your shell:

```bash
exec bash
```

### Smoke testing

Simulate a completely fresh user environment:

```bash
./tests/install-linux-tmp-home
```

### Install root, layout and `config.toml`

The shared tree installs to the **install root**. Resolution order:

1. an explicit `--dest-dir DIR` on the command line,
2. `dest_dir` in `~/.config/engineering-loadout/config.toml`,
3. the XDG default `$XDG_DATA_HOME/loadout` -- i.e. `~/.local/share/loadout`
   unless `XDG_DATA_HOME` is set and absolute.

The root is used as a plain prefix for everything that is not `$HOME`:
`<root>/bin`, `<root>/lib64`, `<root>/share/...`. A root of exactly `$HOME`
keeps the legacy dotted layout (`$HOME/.local/bin`, ...), so
`dest_dir = "~"` restores the old behavior. The old un-dotted `<root>/local/`
level no longer exists.

Two roots are threaded through an install. The shared payload goes to the
install root; per-user configuration, caches and Neovim data always resolve
under the real `$HOME` (`~/.config`, `~/.cache`, `~/.local/share/nvim`). Fonts
are the one exception that follows the tree: a root of `$HOME` (or one inside
it, e.g. the default `~/.local/share/loadout`) keeps them per-user in
`~/.local/share/fonts`, while a root outside `$HOME` gets them once in
`<prefix>/share/fonts` plus a generated `<prefix>/etc/fonts/loadout-fonts.conf`
-- a shared tree must not put ~2 GB into every user's home. A mixed selection
-- one that names any non-`env`
package -- writes its `env` config to `$HOME` even when `--dest-dir` was given.
An **env-only** selection is the exception: with an explicit `--dest-dir D`,
the whole HOME is staged under `D` (tests and previews rely on this); without
the flag, config goes to `$HOME` and a configured `dest_dir` is ignored with a
`note: env bundles always install under $HOME; ...` line.

`config.toml` keys:

```toml
dest_dir   = "~/.loadout"    # pin the install root (default: ~/.local/share/loadout)
prefer     = ["firefox"]     # opt a tool ahead of the system copy (see PATH below)
prefer_off = ["tmux"]        # opt out of a package's default preference
```

`dest_dir` mirrors the flag name exactly. A missing file is not an error, and
a malformed file (or a key of the wrong type) degrades to "no default" rather
than aborting an install.

`--dest-dir` also stages non-default roots for tests and previews, e.g.
`./loadout install octave --dest-dir /tmp/test-home`, and it still overrides a
pinned `dest_dir` for that one run.

### PATH and the `prefer` mechanism

The loadout ships its own coreutils, bash, node and python, and those builds
are not always newer than the distribution's -- an early `PATH` match would
silently downgrade the system toolchain. So the shared `bin` is **appended**
after the system directories; the distribution's copies keep priority.

An explicitly preferred tool is the deliberate exception. The installer writes
a small exec shim under `<prefix>/prefer/<tool>`, and that directory is
**prepended** (after `~/.local/bin`, so it outranks any legacy copy):

```sh
#!/bin/sh
# loadout prefer shim
exec "<prefix>/bin/<tool>" "$@"
```

The active set is the registry defaults of every installed `env` package that
declares `prefer`, plus `config.toml`'s `prefer`, minus `prefer_off`. The only
default today is `env-tmux` -> `tmux`: installing the tmux config makes the
bundled tmux win, because tmux client and server must agree on protocol version
(opt out with `prefer_off = ["tmux"]`). Shims are pruned only when their
content still carries the loadout marker; a foreign file with a colliding name
is left alone with a warning, and a missing target warns instead of creating a
dangling shim.

When the install root is not the default, the shell has to be told. Split
installs bake `LOADOUT_CFG_SHARED_PREFIX` into
`~/.config/bash/global/config.sh` and `~/.config/tcsh/global/config.csh`; to
re-point an existing env install at a different tree, re-run it with the
variable set:

```bash
LOADOUT_CFG_SHARED_PREFIX="$HOME/.loadout" ./loadout install @envs-all
```

All three shells derive the shared prefix, `TERMINFO_DIRS`, the Qt plugin path,
`GI_TYPELIB_PATH`, `NVIM_QT_RUNTIME_PATH`, `FONTCONFIG_FILE` (only when the tree
carries `etc/fonts/loadout-fonts.conf`) and the gnuplot driver dir from the
same variable, falling back to `$HOME/.local/share/loadout` when it is unset.
(For a legacy `dest_dir = "~"` install the value is `$HOME/.local`.)

### Shared / read-only deployments

For a single install shared by many users, do not mutate the live tree in
place. Install only the shared artifacts -- every package except the
per-user `env` config bundles -- with the synthetic `@shared` group:

```bash
./loadout install @shared \
  --dest-dir /opt/engineering-loadout/releases/2026-06-04.2
```

The destination is a prefix (`/opt/.../2026-06-04.2/bin`, `.../share`, ...) --
there is no `local/` level. `LOADOUT_CFG_SHARED_PREFIX=/opt/.../2026-06-04.2`
is therefore the value per-user env installs need (baked automatically by a
split env install).

The shared tree carries the fonts too: `@shared` installs them once into
`<dest>/share/fonts` and writes `<dest>/etc/fonts/loadout-fonts.conf`, which
re-includes `/etc/fonts/fonts.conf` (the system dirs and any user fontconfig
file keep working) and adds that one `<dir>`. The shell layer exports
`FONTCONFIG_FILE` for it, so a per-user `@envs` install with
`LOADOUT_CFG_SHARED_PREFIX=<dest>` is all a user needs -- their `$HOME` gets no
font files and no per-user `~/.local/share/fonts`.

`@shared` = all non-`env`, non-`optional` packages (binaries, libs,
runtimes, fonts, data, python tools); `@shared-all` = the same with the
`optional: true` packages folded back in (surfer, cicwave, rust)
-- the full shared tree in one name. `@envs` = the Bash and
tcsh configuration, installed into each user's `$HOME` with
`./loadout install @envs`. Install other config bundles by
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
./tools/fetch-stash                      # from the latest release, verified
./loadout install @shared-all --dest-dir /opt/engineering-loadout/releases/...
```

Refresh plugins later without a new loadout release with `./tools/refresh-stash`, and
override the stash location with `LOADOUT_CFG_NVIM_PLUGIN_STASH_DIR` if needed.
Neovim itself needs `git` to clone from the stash; `git-nvim` (in `@shared-all`)
provides a private one for boxes with no system git. See the full behavior in
`AGENTS.md` -> "nvim plugin stash delivery".

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
- The fonts directory is deliberately different from both: a symlink at the
  fonts path is left alone (only a dangling link or one that resolves into the
  repository checkout is replaced). Pointing `~/.local/share/fonts` at a shared
  font directory is a supported way to share one font set between users, and
  replacing it would silently duplicate ~2 GB into each home.

Backups/snapshots can restore displaced user files when backups are enabled.

### Corporate / site add-ons

```bash
./loadout install @shared-all @envs-all \
  --post-install-hook ~/corp-dotfiles/install.sh \
  --post-install-hook ~/site-dotfiles/install.sh
```

Hooks receive these environment variables: `LOADOUT_REPO`, `LOADOUT_HOME`,
`LOADOUT_BACKUP_DIR`, `LOADOUT_DEST_DIR`, `LOADOUT_NO_BACKUP`.

### Migrating an existing install

An install made before the XDG default lives in `~/.local` (config in
`~/.config`). The new default is `~/.local/share/loadout`, and `~/.local/bin`
should end up holding nothing the loadout owns. `loadout doctor` reports what
it finds -- the install root and layout mode, EL-managed names still sitting in
`~/.local/bin`, and prefer shims whose targets are missing -- but it changes
nothing. Migrate in this order:

1. **Back up `~/.local/bin`** before touching it:

   ```bash
   cp -a ~/.local/bin ~/.local/bin.premigrate
   ```

2. **Install the shared tree at the new root.** For the default:

   ```bash
   ./loadout install @shared-all -y
   ```

   For a corp/site prefix, pass it explicitly:

   ```bash
   ./loadout install @shared-all --dest-dir /corp/prefix -y
   ```

3. **Re-point the env config bundles** so `config.sh` / `config.csh` bake the
   new shared prefix:

   ```bash
   ./loadout install @envs-all -y
   # split / custom tree:
   LOADOUT_CFG_SHARED_PREFIX=/corp/prefix ./loadout install @envs-all -y
   ```

4. **Prune the legacy `~/.local/bin` copies by name.** They are EL builds from
   the previous deployment -- same names, different hashes -- and they sit ahead
   of the system directories, so they must go. `loadout doctor` lists the names.
   Delete them by name with an **absolute** `/usr/bin/rm`: a relative `rm`
   resolved through `~/.local/bin` disappears mid-loop, and the later iterations
   then fail.

   ```bash
   /usr/bin/rm -f ~/.local/bin/nvim ~/.local/bin/rg ...   # names from `loadout doctor`
   ```

   Only the names `doctor` reports are the loadout's; anything else in
   `~/.local/bin` is yours to keep.

5. **Remove the legacy payload subtrees** under `~/.local` after inspecting
   them -- `~/.local/lib64`, `~/.local/lib`, `~/.local/share/{helix,vim,tealdeer}`
   and the shipped Neovim dirs
   `~/.local/share/nvim/{runtime,tree-sitter-parsers,loadout}`. Keep
   `~/.local/share/nvim/lazy` (your own plugin clones) and
   `~/.local/share/fonts`. If the fonts live in a shared tree, that path may
   instead be a symlink to it -- keeping the symlink is supported, and a
   `@shared` install leaves the fonts in the tree rather than copying them into
   each home. This matters: `paths.lua` prefers a per-user
   directory over the shared tree, so a stale
   `~/.local/share/nvim/tree-sitter-parsers` would shadow the new one.

6. **Open new terminals.** Shells started before the migration carry the old
   `PATH` and an old Starship binary path. A new terminal re-reads both. In a
   shell you cannot replace, re-initialize Starship and clear its command
   cache:

   ```bash
   eval "$(starship init bash)"; hash -r
   ```

   `hash -r` alone is not enough: `starship init` bakes an absolute binary path
   into the `starship_precmd` function body, so the stale path lives in shell
   state, not in the command hash.

7. **GUI sessions.** The graphical session's `PATH` is built by the login
   chain and does not include the install root. `prefer` shims only help when
   their directory is on `PATH`, so a GUI-launched editor may not see the
   preferred tool. There is no per-user fix: session-wide `PATH` needs
   `/etc/environment` (via `pam_env`), and systemd's `DefaultEnvironment`
   cannot override an already-populated environment block. Terminal work is
   unaffected.

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

Snapshots protect per-user config, so they operate on the real `$HOME`; a
configured `dest_dir` deliberately does **not** move them. Only an explicit
`--dest-dir` typed on the `snapshot` command line stages the snapshot elsewhere.

## Windows / macOS

Not supported. Windows and macOS support was retired 2026-08-31 and
offloaded to a separate personal repository (`windows-dotfiles`); this
installer is Linux-only. There is no Windows or macOS install path here,
and the package registry's `platforms` field accepts `'linux'` only.
