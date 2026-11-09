# Maintenance

## Adding a new pre-built binary

Order matters: always **strip -> patchelf -> bzip2**. Stripping after patchelf
corrupts `.dynstr`.

```bash
# 1. Strip, set RPATH, compress
cp /path/to/binary /tmp/mybinary_tmp
/usr/bin/strip /tmp/mybinary_tmp
/usr/bin/patchelf --set-rpath '$ORIGIN/../lib64:$ORIGIN/../lib' /tmp/mybinary_tmp
bzip2 -k /tmp/mybinary_tmp
cp /tmp/mybinary_tmp.bz2 payload/el8.x86_64.glibc2p28/bin/mybinary.bz2

# 2. Update strip manifest
./build/strip-all-elf-binaries

# 3. Register in the package registry (payload/packages.json, schema_version 3)
#    {"mybinary": {"kind": "bin", "bins": ["mybinary"], "version": "X.Y.Z",
#                  "platforms": ["linux"], "tags": ["..."],
#                  "description": "..."}}
#    Add "mybinary" to a curated group's members list in packages.json if it
#    should ship in that set. A non-env package is already part of @shared-all.

# 4. Smoke-test and commit
tests/prebuilt-binaries --keep   # or just ./build/release --dry-run
git add payload/ .strip-manifest
git commit
```

See [`build/ADDING_BINARIES.md`](../build/ADDING_BINARIES.md) for the
full workflow including dependency auditing, Go binary flags,
`farm-versions` registration, and the `schema_version: 3` registry fields.

## Importing a new portable Python build

```bash
build/import-portable-python /path/to/portable-python-X.Y.Z-tag/
./build/strip-all-elf-binaries   # skips BOLT-optimized Python archive automatically
git add payload/ .strip-manifest
git commit
```

> Cutting a release? Follow [`docs/RELEASE.md`](RELEASE.md) — it is the
> authoritative, ordered procedure (currency sweep, security data, the
> mandatory post-payload chain, gates by release class).

## Updating tmux plugins

```bash
./build/update tmux-plugins
git add envs/tmux/vendor/
git commit
```

## Rebuilding Tree-sitter parsers

```bash
./build/treesitter/build_parsers
git add payload/treesitter/prebuilt/
git commit
```

## Onboarding a new developer

After extracting a release and running
`./loadout install @shared-all` to install the runtime, run
`./build/dev-onboard` once to add the system-level packages, dev headers, and
per-user toolchains required to rebuild any bundled tool from source. Six
phases: dnf repos -> toolchains (gcc-toolset-14, llvm, go) -> dev headers
(X11 / Qt5 / GTK3 / ncurses / Octave) -> release / CI (gh, docker) ->
per-user (rustup, nvm, uv tool meson) -> sanity checks. Idempotent;
`--check` for dry-run, `--yes` for non-interactive.

## Retired envs (state a deleted env left in $HOME)

When an env bundle is removed from the tree, the files it wrote into `$HOME`
are not owned by anything any more -- nothing re-writes them and nothing
removes them, so they outlive the env and can break tools long after the
retirement. `env-cargo` is the case that exists: it was deleted in commit
`b1aac32` (the offline Rust subsystem went with it), but `~/.cargo/config.toml`
survived on every box that ever installed it, still declaring

```toml
[source.crates-io]
replace-with = "local-registry"

[source.local-registry]
local-registry = "<store that no longer exists>"
```

which makes **every** `cargo fetch` / `build` / `install` fail with

```text
local registry path is not a directory: <store that no longer exists>
```

-- an error that reads like "the store is missing, rebuild it" and points at a
layout the tree abandoned (issue #21).

**What the installer does now:** a confirmed `loadout install` parks that file,
`~/.cargo/config.toml` -> `~/.cargo/config.toml.stale-env-cargo`, and says so,
but only when BOTH hold: the file carries the `# Managed by loadout (env-cargo)`
marker (so it is loadout's, not a hand-written config) and a source-replacement
directory it names does not exist (so it actually breaks cargo). A hand-written
config, and a managed one whose store still exists, are left untouched.
`loadout doctor` reports the state without changing it:

```text
Retired env-cargo config: ~/.cargo/config.toml [BROKEN]
  source replacement missing: /vols/.../registry-store
  every cargo command fails until it goes: `loadout install` parks it as
  config.toml.stale-env-cargo, or delete it yourself.
```

**Manual remedy on a box installed before this fix** (no install needed):

```bash
rm ~/.cargo/config.toml          # the parked copy keeps a record if you prefer `mv`
```

Gate: `tests/stale-env-cargo-config` (T2) drives a real install against a
fixture `$HOME` carrying the broken file and asserts it is parked byte-for-byte,
that a second install parks nothing again, and that hand-written / working
configs are never touched; `tests/unit-install-steps` covers the marker/path
matrix in-process.

When the next env is retired, add its `$HOME` artefacts to this section and to
the same cleanup step -- do not leave a second immortal file behind.

## Repo development

The repo is the source of truth; editing a file there and re-running
`./loadout install @shared-all @envs-all` is the canonical workflow. Most install steps are
idempotent (recursive copy, atomic bz2 decompress, byte-compare skip) so a re-run
finishes quickly.

Install repo git hooks manually:

```bash
cp hooks/* .git/hooks/ && chmod +x .git/hooks/*
```

Provides:

- **pre-commit** -- strips ELF payloads from newly staged binaries and archives,
  normalizes tarballs to `.tar.bz2`, updates `.strip-manifest`. Removes any
  embedded `.git` dirs from vendored plugins while pruning the repository's own
  top-level `.git` directory.

The installer uses its own Python recursive copy instead of requiring host
`rsync`. That copy path removes symlinked destination directories before
syncing, refuses overlapping source/destination trees, and tolerates source
files that vanish mid-copy. This matters for old config layouts where
`~/.config/nvim/lsp` or `after/` may still symlink back into the repo.

Known install traps to keep covered:

- Do not follow env destination symlinks back into this checkout. A stale
  `~/.config/nvim/lsp -> ~/dotfiles/nvim/lsp` plus delete-style sync can delete
  tracked repo files during `loadout install @envs`.
- Do not make host `rsync` or host Python mandatory. The POSIX `loadout` shim
  must bootstrap the bundled Python, then Python handles recursive copies.
- Do not let missing/vanished source entries abort the whole env install; users
  can be updating generated config trees in another session.
- Do not let the pre-commit embedded-`.git` scan walk the repository's own
  `.git` tree. Sandbox or unusual home/worktree layouts can expose
  `./.git/.git`; that is not a vendored plugin.
- In bash startup files, `bash -n` is not enough. Interactive shells expand
  aliases while parsing sourced files, so define alias-colliding functions only
  after `unalias name 2>/dev/null || true`.

Run `tests/run-all --container` for the full suite (Tier 1 fast checks,
Tier 2 integration installs, Tier 3 clean-container smoke). Stock
AlmaLinux 8 is the verification baseline for install behavior; the dev box
is not.

Run `./build/release --dry-run` before creating a release to smoke-test all
binaries via a temp install. When Docker is available, run
`tests/prebuilt-binaries-almalinux8` for the
maximum-coverage check against a clean AlmaLinux 8.10 base image. That Docker
path uses `./loadout` to bootstrap the bundled Python; it does not rely on a
system Python in the image. Expected host-contract skips are explicit: host
Perl for `cloc`, EL8 `/usr/bin/python3.6` for `meld`, and host GLVND/OpenGL
dispatcher libs for GL GUI apps.

Run `tests/install-split-shared-envs` for the main deployment model: `@shared`
to a non-home temp tree, then `@envs` to a separate temp HOME with
`LOADOUT_CFG_SHARED_PREFIX=<shared>`. It verifies shell startup resolves
shared PATH, terminfo, GUI runtime variables, WezTerm completions, and core tool
startup without relying on the user's real `~/.local/bin`.
