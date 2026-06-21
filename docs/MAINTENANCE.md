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
cp /tmp/mybinary_tmp.bz2 pre_built/el8.x86_64.glibc2p28/bin/mybinary.bz2

# 2. Update strip manifest
./strip_all_elf_binaries

# 3. Register in the package registry (pre_built/packages.json, schema_version 3)
#    {"mybinary": {"kind": "bin", "bins": ["mybinary"], "version": "X.Y.Z",
#                  "platforms": ["linux"], "tags": ["..."],
#                  "description": "..."}}
#    Add "mybinary" to the @engineering-loadout group's members list if it
#    should ship in the full bundled set.

# 4. Smoke-test and commit
pre_built/build_scripts/test-prebuilt-binaries --keep   # or just ./release --dry-run
git add pre_built/ .strip-manifest
git commit
```

See [`pre_built/ADDING_BINARIES.md`](../pre_built/ADDING_BINARIES.md) for the
full workflow including dependency auditing, Go binary flags,
`farm-versions` registration, and the `schema_version: 3` registry fields.

## Importing a new portable Python build

```bash
pre_built/build_scripts/import-portable-python /path/to/portable-python-X.Y.Z-tag/
./strip_all_elf_binaries   # skips BOLT-optimized Python archive automatically
git add pre_built/ .strip-manifest
git commit
```

## Updating tldr pages

```bash
./update tldr-data
git add tldr/
git commit
```

## Updating tmux plugins

```bash
./update tmux-plugins
git add tmux/vendor/
git commit
```

## Rebuilding Tree-sitter parsers

```bash
./treesitter/build_parsers
git add treesitter/prebuilt/
git commit
```

## Onboarding a new developer

After extracting a release and running
`./loadout install @engineering-loadout` to install the runtime, run
`./dev-onboard` once to add the system-level packages, dev headers, and
per-user toolchains required to rebuild any bundled tool from source. Six
phases: dnf repos -> toolchains (gcc-toolset-14, llvm, go) -> dev headers
(X11 / Qt5 / GTK3 / ncurses / Octave) -> release / CI (gh, docker) ->
per-user (rustup, nvm, uv tool meson) -> sanity checks. Idempotent;
`--check` for dry-run, `--yes` for non-interactive.

## Repo development

The repo is the source of truth; editing a file there and re-running
`./loadout install @engineering-loadout` is the canonical workflow. Most install steps are
idempotent (recursive copy, atomic bz2 decompress, byte-compare skip) so a re-run
finishes quickly.

Install repo git hooks manually:

```bash
cp hooks/* .git/hooks/ && chmod +x .git/hooks/*
```

Provides:

- **pre-commit** -- strips ELF payloads from newly staged binaries and archives,
  normalizes tarballs to `.tar.bz2`, updates `.strip-manifest`. Removes any
  embedded `.git` dirs from vendored plugins.

Run `./release --dry-run` before creating a release to smoke-test all
binaries via a temp install. When Docker is available, run
`pre_built/build_scripts/test-prebuilt-binaries-almalinux8` for the
maximum-coverage check against a clean AlmaLinux 8.10 base image. That Docker
path uses `./loadout` to bootstrap the bundled Python; it does not rely on a
system Python in the image. Expected host-contract skips are explicit: host
Perl for `cloc`, EL8 `/usr/bin/python3.6` for `meld`, and host GLVND/OpenGL
dispatcher libs for GL GUI apps.

Run `tests/install_split_shared_envs` for the main deployment model: `@shared`
to a non-home temp tree, then `@envs` to a separate temp HOME with
`LOADOUT_CFG_SHARED_PREFIX=<shared>/local`. It verifies shell startup resolves
shared PATH, terminfo, GUI runtime variables, WezTerm completions, and core tool
startup without relying on the user's real `~/.local/bin`.
