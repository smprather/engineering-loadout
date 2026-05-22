# Tree-sitter Offline Runtime

This tree vendors the new `nvim-treesitter` runtime and
`treesitter-parser-registry`, then stores prebuilt parser artifacts by platform
for offline Neovim installs.

Build all parsers supported by the vendored registry:

```bash
./treesitter/build_parsers
```

Build selected parsers while testing:

```bash
./treesitter/build_parsers python lua --max-jobs 2
```

Output is platform-specific:

```text
treesitter/prebuilt/<os>-<arch>-<libc>/parser/*.so.bz2
treesitter/prebuilt/<os>-<arch>-<libc>/parser-info/*.lua
treesitter/prebuilt/<os>-<arch>-<libc>/queries/*/*.scm
treesitter/prebuilt/<os>-<arch>-<libc>/registry/registry-cache.lua
treesitter/prebuilt/<os>-<arch>-<libc>/build-info/platform.env
```

The platform ID is `$(uname -s lower)-$(uname -m)-<glibc|musl>`, for example
`linux-x86_64-glibc`.

The Linux installer copies vendored plugins to:

```text
~/.local/share/nvim/loadout/vendor/
```

and decompresses matching prebuilt parsers to
`~/.local/share/nvim/tree-sitter-parsers/parser/*.so`, then copies queries and
metadata. Neovim v0.12+ then starts native Tree-sitter highlighting from the
offline parser directory.
