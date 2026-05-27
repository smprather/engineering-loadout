# Architecture

Internal design of the Engineering Loadout package manager and configuration system.
For installation and usage, see the [README](../README.md).

---

## Package Registry

The installer is driven by `pre_built/packages.json` (`schema_version: 2`) — a typed
registry that names every installable thing: binary, library bundle, runtime archive,
config bundle, font, data cache, Python tool.

### Package kinds (`kind` field)

| Kind | Description |
|------|-------------|
| `bin` | Pre-built binary/binaries (`.bz2` → `~/.local/bin`) |
| `lib-bundle` | Group of shared libraries (`.bz2` → `~/.local/lib64`) |
| `runtime` | Runtime archive (`.tar.bz2` → unpacked destination) |
| `typelib` | GObject `.typelib` file → `~/.local/lib/girepository-1.0/` |
| `python-base` | Portable Python archive, installed via bundled `install.sh` |
| `python-tool` | PyPI tool installed via `uv tool install` from bundled wheels |
| `env` | Config bundle (dotfiles, editor configs) |
| `font` | Font archive → `~/.local/share/fonts/` |
| `data` | Data archive (tldr pages, YARA rules, etc.) |
| `group` | Virtual group — no artifacts; just a `members` list |

Every package also declares:
- `default: true|false` — included in default install set or not
- `platforms: [linux|macos|windows]` — resolver filters by current platform
- `tags: [...]` — free-form labels for `list --tag T`
- Per-kind artifact fields: `bins`, `libs`, `archive`, `wheels`, `uv_tool`, etc.
- `version`, `description`, `homepage`
- Optional upstream version tracking: `version_url`, `version_pattern`,
  `version_url_accept`, `version_url_ua`

### Groups

Entries whose keys start with `@` carry a `members` list and expand recursively
with cycle detection. The synthetic `@default` group expands at runtime to every
`default: true` package.

### Dependencies

- `depends` — hard dep. If a depender is selected and the dep is skipped, the
  resolver raises `ResolverError` (unless `--no-deps` or `--force`).
- `recommends` — soft dep. Auto-pulled when available; silently dropped if
  skipped or unknown.

---

## Resolver

`resolve_tool_selection(args, registry)` runs at install time:

1. Parse `--skip` (expand groups).
2. Build initial set:
   - `--only X,@Y,…` → exactly those packages (bypass defaults).
   - Default: every `default: true` package ∪ `--add` packages.
3. Subtract `--skip`.
4. Walk hard `depends` — raise `ResolverError` on skipped hard dep
   (unless `--no-deps` or `--force`).
5. Walk soft `recommends` — silently drop skipped/unknown.
6. Filter by current platform.

### CLI surface

```bash
# Inspect the registry
./engineering-loadout list                            # all packages
./engineering-loadout list --groups                   # all @-groups + member counts
./engineering-loadout list --tag editor               # filter by tag
./engineering-loadout describe gvim                   # metadata + reverse-deps + group memberships
./engineering-loadout describe @core-cli              # group members
./engineering-loadout resolve gvim                    # dry-run; prints resolved set by kind
./engineering-loadout doctor                          # platform + registry integrity check

# Selection flags (apply to install, resolve, --dry-run)
./engineering-loadout --add octave                    # add to default set
./engineering-loadout --add @gui-suite                # add a group (expands recursively)
./engineering-loadout --skip @fonts-all               # drop all font packages
./engineering-loadout --skip tldr-data                # skip tldr cache install
./engineering-loadout --only @core-cli,vim            # exact set (bypasses defaults)
./engineering-loadout --profile engineering-loadout   # alias for --only @engineering-loadout
./engineering-loadout --no-deps --only gvim           # skip dep walking entirely
./engineering-loadout --force --skip gui_libs --add gvim  # warn on conflict, continue
./engineering-loadout --dry-run --add octave          # resolve + print; no writes
```

---

## Pre-Built Binary Pipeline

All binaries and shared libs are stripped, patchelf'd, and bzip2-compressed before
commit. The installer is pure decompress + chmod — no runtime patchelf needed.

**Order is critical: strip → patchelf → bzip2.**
Patchelf after strip corrupts the binary (patchelf reorganizes ELF segments to fit
the new RPATH string; strip after patchelf sees `.dynstr` outside a `PT_LOAD` segment).

RPATH conventions:
- Executables: `$ORIGIN/../lib64:$ORIGIN/../lib`
- Shared libs (gui_libs group): `$ORIGIN` (libs find each other in the same flat dir)
- Shared libs (exclusively owned): no patchelf needed

The pre-baked `$ORIGIN` token is resolved by `ld.so` at load time, so baking it in
the repo is identical to setting it post-install. Avoids NFS lock issues on running
binaries.

Platform directory: `pre_built/el8.x86_64.glibc2p28`
- `bin/*.bz2` → `~/.local/bin`
- `lib64/*.bz2` → `~/.local/lib64`
- `runtime/*.tar.bz2` → unpacked per runtime installer function
- `wheels/` → offline PyPI wheels for `uv tool install`

Never bundle: `libc.so.6`, `libm.so.6`, `libpthread.so.0`, `libdl.so.2` (glibc —
must match system's `ld-linux.so.2`), `libGL.so.1`/`libGLX.so.0` (OpenGL dispatcher —
must be driver-linked), `libstdc++.so.6`/`libgcc_s.so.1` (C++ runtime).

See `pre_built/ADDING_BINARIES.md` for the full workflow and per-tool build notes.

---

## Configuration Layer System

Configuration flows `global → corp → site → team → project → user`. Each layer
overrides the previous without touching upstream files.

### Bash

Entry point: `bash/bashrc` sources `config.sh` then `bashrc` for each layer in order.
Layer dirs live at `~/.config/bash/<layer>/` — user-created, never committed here.

```
~/.config/bash/
  global/      ← repo-managed canonical config
  corp/        ← corporation overrides (user-created)
  site/        ← site overrides
  team/        ← team overrides
  project/     ← project overrides
  user/        ← personal overrides
```

Completions are auto-sourced from each layer's `completions/*.bash`.
See `bash/README.md` for hook injection points (numbered `global_hooks/N.sh`).

### Neovim

Entry point: `nvim/init.lua` — thin dispatcher with four phases:
1. Source `config.lua` per layer → sets `vim.g.cfg_*` defaults and overrides.
2. Bootstrap lazy.nvim (offline-safe: skips plugin setup if git clone fails).
3. Collect plugin specs from each layer's `plugins/` dir.
4. Source `init.lua` per layer → options, keymaps, autocmds, LSP.

Layer dirs live at `~/.config/nvim/lua/<layer>/` — user-created, never committed.

```
~/.config/nvim/lua/
  global/      ← repo-managed: config.lua, init.lua, plugins/
  corp/        ← user-created
  site/
  team/
  project/
  user/
```

---

## Installer Internals

`./engineering-loadout` — single Python 3.6-compatible executable (shebang
`#!/usr/bin/python3`). All subprocess calls use absolute paths resolved at startup
(`_LDD`, `_UNAME`, `_GETCONF` via `_find_tool()`) to avoid accidentally picking up
binaries being installed.

**Atomic writes:** All bz2 decompression uses `write_bz2_atomic` (write to temp file
in same directory + `os.rename`). Prevents SIGBUS when a running Python process has
memory-mapped a shared lib being overwritten.

**Per-phase gating:** Each install phase (`install_prebuilt_binaries`, `install_fonts`,
`install_tldr_cache`, etc.) receives `selected_tools` and short-circuits with a `SKIP`
row when its package(s) are not in the resolved set.

**Platform fallback:** If no exact platform directory exists, the installer may use a
compatible same-arch glibc build whose glibc version is not newer than the host's.

**Layer install scripts:** After the main install, `run_layer_install_scripts` runs
`~/.config/bash/<layer>/install.sh` for each non-global layer that has one.
