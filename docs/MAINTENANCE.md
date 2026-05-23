# Maintenance

## Adding a new pre-built binary

Order matters: always **strip → patchelf → bzip2**. Stripping after patchelf
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

# 3. Register in the package registry (pre_built/packages.json)
#    {"mybinary": {"kind": "bin", "bins": ["mybinary"], "version": "X.Y.Z",
#                  "platforms": ["linux"], "default": true,
#                  "description": "..."}}

# 4. Smoke-test and commit
pre_built/build_scripts/test-prebuilt-binaries --keep   # or just ./release --dry-run
git add pre_built/ .strip-manifest
git commit
```

See [`pre_built/ADDING_BINARIES.md`](../pre_built/ADDING_BINARIES.md) for the
full workflow including dependency auditing, Go binary flags,
`farm-versions` registration, and the schema-2 registry fields.

## Importing a new portable Python build

```bash
pre_built/build_scripts/import-portable-python /path/to/portable-python-X.Y.Z-tag/
./strip_all_elf_binaries   # skips BOLT-optimized Python archive automatically
git add pre_built/ .strip-manifest
git commit
```

## Updating tldr pages

```bash
./update_tldr_cache
git add tldr/
git commit
```

## Updating tmux plugins

```bash
./update_tmux_plugins
git add tmux/vendor/
git commit
```

## Rebuilding Tree-sitter parsers

```bash
./treesitter/build_parsers
git add treesitter/prebuilt/
git commit
```

## Repo development

The repo is the source of truth; editing a file there and re-running
`./engineering-loadout` is the canonical workflow. Most install steps are
idempotent (rsync, atomic bz2 decompress, byte-compare skip) so a re-run
finishes quickly.

Install repo git hooks manually:

```bash
cp hooks/* .git/hooks/ && chmod +x .git/hooks/*
```

Provides:

- **pre-commit** — strips ELF payloads from newly staged binaries and archives,
  normalizes tarballs to `.tar.bz2`, updates `.strip-manifest`. Removes any
  embedded `.git` dirs from vendored plugins.

Run `./release --dry-run` before creating a release to smoke-test all
binaries via a temp install.
