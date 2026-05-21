# Adding Pre-Built Binaries

Reference for the build machine and the full workflow for adding a new binary.

## Build Machine

**AlmaLinux 8.10**, x86_64, glibc 2.28, running as WSL2 on Windows.
Platform directory: `el8.x86_64.glibc2p28`

```
uname -r  → 6.6.87.2-microsoft-standard-WSL2
ldd --version → ldd (GNU libc) 2.28
gcc --version → gcc 14.2.1 (gcc-toolset-14, enabled in ~/.config/bash/user/bashrc)
/usr/bin/gcc --version → gcc 8.5.0 (base system compiler, too old for most modern software)
```

GCC 14 is sourced via `gcc-toolset-14` from the `appstream` repo:
```bash
sudo dnf install -y gcc-toolset-14 gcc-toolset-14-gcc-c++
# Or it may already be active if it is in your user bashrc:
. /opt/rh/gcc-toolset-14/enable
```

User has `sudo` (wheel group). Enabled repos: appstream, baseos, epel, extras, powertools,
docker-ce-stable, gh-cli, rpmfusion-free-updates, rpmfusion-nonfree-updates.

### Notable devel packages already installed

X11 full stack, cairo, pango, readline, ncurses, libpng, freetype, fontconfig, bzip2, expat,
uuid, zlib, libwebp, libtiff, libjpeg-turbo, glib2, harfbuzz, fribidi, pixman, pcre/pcre2,
openssl, elfutils, libxml2, xxhash, lz4, zstd, libevent.

**Not available anywhere** (not in appstream/baseos/epel/powertools):
- `libgd-devel` — must build libgd from source if gd-based terminals needed

## Workflow

### 1. Get the binary

**From repo RPM** (easiest):
```bash
sudo dnf install -y <package>
which <binary>
```

**From source** (when repo version is too old or has unwanted deps):
```bash
cd /tmp
curl -L -o src.tar.gz <url>
tar xzf src.tar.gz && cd <srcdir>
./configure --prefix=/tmp/<name>-install [options]
make -j$(nproc) && make install
```

### 2. Audit dependencies

```bash
ldd /path/to/binary
```

Compare against already-bundled libs in `lib64/`. Anything already there: free.
Anything missing: decide whether to bundle or accept as system dependency.

**NEVER bundle these — they must come from the system:**

- **glibc components**: `libc.so.6`, `libm.so.6`, `libpthread.so.0`, `libdl.so.2`, `librt.so.1` — must match the system's `ld-linux.so.2` exactly or you get `undefined symbol: _dl_audit_symbind_alt, version GLIBC_PRIVATE` crashes. Every EL8 system has glibc 2.28; never needed in the bundle.
- **OpenGL dispatcher**: `libGL.so.1`, `libGLX.so.0`, `libGLdispatch.so.0` — must be the system's display-driver-linked version. Bundling causes crashes or wrong driver selection. Qt5 and GTK3 can be built without OpenGL (use `--no-opengl` or equivalent).
- **C++ runtime**: `libstdc++.so.6`, `libgcc_s.so.1` — present on all EL8 systems; version mismatches with C++ exceptions are subtle.

If any of these appear in `lib64/` from a previous mistake, remove them and purge from `~/.local/lib64` on deployed systems.

**Safe to bundle**: everything else — libz, libpng, libX11, libreadline, libncurses, libfreetype, libfontconfig, libevent, libxxhash, Qt5, GTK3, glib2, ICU, pango, cairo, xcb extensions, xkbcommon, Wayland client libs. See `gui_libs` in `packages.json` as a worked example of a large GUI lib bundle.

### 3. Minimize the dep chain

Before bundling 30 libs, check if the binary can be built with fewer features:

- **Qt5**: brings ICU (~75 MB), SSL, kerberos, GL — never worth it for home-dir installs
- **cairo + pango**: ~15 extra libs. Fine for a dedicated workstation, too heavy for ~4 GB quotas
- **libgd**: not in any EL8 repo; if needed, build from source or skip gd-based terminals
- **Lua**: adds `liblua-5.3.so`; usually optional (`--without-lua`)

For gnuplot specifically: `--without-qt --without-cairo --without-lua --with-x --with-readline=gnu`
gives dumb, x11, svg, postscript, eps, epslatex — enough for EE plotting. Only 2 new libs
(readline, ncurses).

### 4. Bundle the binary

```bash
REPO=/path/to/engineering-loadout
BIN_DIR="$REPO/pre_built/el8.x86_64.glibc2p28/bin"
LIB_DIR="$REPO/pre_built/el8.x86_64.glibc2p28/lib64"

# Binary — order: strip → patchelf → compress. CRITICAL: always strip BEFORE patchelf.
# patchelf reorganizes ELF segments to fit the new RPATH string; strip after patchelf
# sees .dynstr outside a PT_LOAD segment and corrupts the binary (symptom: "no version
# information available" or symbol lookup errors at runtime).
# $ORIGIN is resolved by ld.so at load time, so baking it in the repo is identical to
# post-install patchelf. Pre-patching means the installer is pure decompress + chmod;
# no patchelf needed on the destination (avoids NFS lock issues on running binaries).
cp /path/to/binary /tmp/mytool_tmp
/usr/bin/strip /tmp/mytool_tmp
~/.local/bin/patchelf --set-rpath '$ORIGIN/../lib64:$ORIGIN/../lib' /tmp/mytool_tmp
bzip2 -k /tmp/mytool_tmp
cp /tmp/mytool_tmp.bz2 "$BIN_DIR/mytool.bz2"
chmod 644 "$BIN_DIR/mytool.bz2"   # bzip2 inherits source perms; normalize to 644

# Shared lib — filename must be the SONAME (ldd shows "libfoo.so.3 => ...")
# Standalone libs (only needed by one binary with a fixed RPATH): no patchelf needed.
# GUI libs that must find EACH OTHER (e.g. gui_libs group in lib64/): need RPATH $ORIGIN.
# Order for libs that need patchelf: strip → patchelf → bzip2 (same rule as binaries).
cp /lib64/libfoo.so.3.x.y /tmp/libfoo_tmp
/usr/bin/strip /tmp/libfoo_tmp
# If this lib needs to find sibling libs in the same lib64/ dir:
~/.local/bin/patchelf --set-rpath '$ORIGIN' /tmp/libfoo_tmp
bzip2 -k /tmp/libfoo_tmp
cp /tmp/libfoo_tmp.bz2 "$LIB_DIR/libfoo.so.3.bz2"
chmod 644 "$LIB_DIR/libfoo.so.3.bz2"
```

The installer decompresses `bin/*.bz2` → `~/.local/bin` and `lib64/*.bz2` → `~/.local/lib64`.
RPATH is pre-baked into each binary in the repo (see above), so no post-install patchelf is needed.

### 5. Strip

```bash
./strip_all_elf_binaries
```

Strips debug symbols from new `.bz2` payloads and records them in `.strip-manifest` so they're
skipped on subsequent runs. Typical savings: 60–75% size reduction before compression.
Never run on `portable-python-*.tar.bz2` (BOLT-optimized, in NOSTRIP list).

### 6. Update farm-versions

Add an entry to `TOOLS` in `pre_built/build_scripts/farm-versions`. Entries are
`(binary_name, display_name, homepage, version_strategy)`.

Common strategies:
```python
# Standard --version flag
strategy_flag(["--version"], r"toolname ([0-9]+\.[0-9]+\.[0-9]+)")

# Try multiple approaches
strategy_first(
    strategy_strings(r"toolname ([0-9]+\.[0-9]+\.[0-9]+)"),
    strategy_flag(["--version"], r"([0-9]+\.[0-9]+\.[0-9]+)"),
)

# Custom extraction (e.g. gnuplot: "6.0 patchlevel 2" → "6.0.2")
lambda binary: (lambda m: re.sub(r" patchlevel ", ".", m.group(1)) if m else None)(
    re.search(r"toolname ([0-9]+\.[0-9]+ patchlevel [0-9]+)", _run([binary, "--version"])))
```

### 7. Register in packages.json

Add an entry under `packages` in `pre_built/packages.json` (`schema_version: 2`):

```json
"mytool": {
  "kind": "bin",
  "bins": ["mytool"],
  "libs": ["libnewdep.so.3"],
  "version": "X.Y.Z",
  "platforms": ["linux"],
  "default": true,
  "tags": ["data"],
  "description": "One-line description"
}
```

Key rules:
- `kind` — one of `bin`, `lib-bundle`, `runtime`, `typelib`, `python-base`,
  `python-tool`, `env`, `font`, `data`, `group`. For a normal pre-built binary use `bin`.
- `bins` — every `bin/*.bz2` stem this build produces (e.g. `"vim"` lists `["vim", "vim.bin"]`,
  `"xterm"` lists `["xterm", "resize"]`).
- `libs` — **only** lib64 stems that are *exclusively* owned by this tool (not needed by any
  other bundled tool). Shared deps (libX11, libncurses, etc.) should be omitted — they are
  always installed regardless of tool selection.
- `default: false` — if the tool should NOT be installed by default (e.g. large optional tools
  like `octave`). Users opt in with `./engineering-loadout --add mytool`. The legacy
  `optional: true` field still works but `default` is preferred.
- `platforms` — list from `linux`, `macos`, `windows`. Resolver filters by current platform.
- `tags` — free-form labels (`search`, `editor`, `monitor`, ...) used by `list --tag T`.
- `depends` — list of hard-dep package names (or `@group` refs). Resolver auto-pulls them;
  skipping a hard dep raises `ResolverError` unless `--no-deps` or `--force`. Use for
  binary-needs-lib-bundle (e.g. `"gvim"` depends on `"gui_libs"` + `"vim92-runtime"`).
- `recommends` — list of soft-dep package names. Silently dropped if skipped.

For a tool with a single binary, no exclusive libs, and no deps:
`"mytool": {"kind": "bin", "bins": ["mytool"], "version": "X.Y.Z", "platforms": ["linux"], "default": true, "description": "..."}`.

To make it discoverable by group selection, add it to an `@group` `members` list elsewhere
in `packages.json` (e.g. `@core-cli`, `@dev-tools`, `@editor-cli`).

### 8. Verify and commit

```bash
# Smoke-test decompressed binary
bunzip2 -k -c pre_built/el8.x86_64.glibc2p28/bin/mytool.bz2 > /tmp/t && chmod +x /tmp/t
ldd /tmp/t | grep "not found"   # must be empty
/tmp/t --version

# Check farm-versions picks it up
pre_built/build_scripts/farm-versions --format text

git add pre_built/el8.x86_64.glibc2p28/bin/mytool.bz2 \
        pre_built/el8.x86_64.glibc2p28/lib64/libnew*.bz2 \
        pre_built/build_scripts/farm-versions \
        pre_built/packages.json \
        .strip-manifest
git commit
```

## Neovim build notes (0.13.0-dev nightly, added 2026-05-12)

Built from source at `~/neovim` (commit `7ed5609439`, nightly tag). CMake flags:
```bash
cmake -B build \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX=/usr/local \
  -DENABLE_TRANSLATIONS=OFF \
  -G Ninja
ninja -C build -j$(nproc)
sudo ninja -C build install
```

All deps (libuv, tree-sitter, luajit, libvterm, etc.) are bundled statically by the build
system. The resulting binary links only against glibc components — no libs to bundle.

Binary: 33 MB unstripped (RelWithDebInfo) → 5.9 MB stripped → 2.6 MB compressed.
Runtime archive (`nvim.tar.bz2`): 27 MB uncompressed → 4.8 MB compressed.
Installer extracts runtime to `~/.local/share/nvim/runtime/`.
See `pre_built/build_scripts/build-nvim.sh` for the full rebuild recipe.

## Gnuplot build notes (6.0.2, added 2026-05-10)

Built from source to avoid Qt5 dep chain. Configure flags used:
```bash
./configure \
  --prefix=/tmp/gnuplot-install \
  --without-qt \
  --without-lua \
  --without-cairo \
  --without-libcerf \
  --with-readline=gnu \
  --with-x
```

New libs bundled: `libreadline.so.7`, `libncurses.so.6`.
Runtime data (`share/gnuplot/6.0/`) not bundled — binary works without it for core terminals
(svg, postscript, x11, dumb all tested OK). If help or color palettes are needed later,
package `share/gnuplot/` as `gnuplot-runtime.tar.bz2` and add installer support.

## Octave build notes (11.1.0, added 2026-05-13)

Built without Qt, Java, OpenGL, FLTK, or X11. Plots work via gnuplot backend (already bundled).
RapidJSON disabled to avoid a GCC 14 read-only-member compile error.

```bash
# Enable GCC 14 (required — GCC 8.5 from base is too old for Octave 11)
. /opt/rh/gcc-toolset-14/enable

./configure \
  --prefix=/tmp/octave-install \
  --without-qt \
  --without-java \
  --without-opengl \
  --without-fltk \
  --without-x \
  --disable-rapidjson \
  CFLAGS="-O2" CXXFLAGS="-O2" FFLAGS="-O2"
make -j$(nproc) && make install
```

See `pre_built/build_scripts/build-octave.sh` for the full bundling recipe.

**Binary layout:**
- `bin/octave.bz2` — thin 16K launcher (stripped), RPATH = `$ORIGIN/../lib64`
- `lib64/liboctave.so.13.bz2`, `liboctinterp.so.15.bz2`, `liboctmex.so.1.bz2` — core libs, RPATH = `$ORIGIN`
- 35 exclusive dep libs in `lib64/` (FFTW, HDF5, BLAS, SuiteSparse, GFortran, audio, GLPK, QHull, ...)
- `runtime/octave.tar.bz2` — m-files (`share/octave/11.1.0/`) + compiled plugins (`lib/octave/11.1.0/oct/`, patchelf'd RPATH = `$ORIGIN/../../../../../lib64`)

**What is NOT bundled:** doc (saves ~5.6 MB), Qt/FLTK/X11 (no display on headless machines).

**Total uncompressed install size:** ~163 MB. Dominated by libopenblas + libopenblasp (~110 MB combined). This is why octave is `optional: true` in `packages.json`.

## Disk quota considerations

Home directory quotas on EE systems are typically small (~4–10 GB). Rough sizes after stripping:

| Category                 | Example                          | Approx size (uncompressed) |
|--------------------------|----------------------------------|---------------------------|
| Rust/Go binaries         | rg, fd, bat, eza, starship       | 0.5–3 MB each             |
| C binaries               | gnuplot, htop, tmux              | 0.3–1.5 MB each           |
| Qt5/GTK3 + xcb + Wayland | gui_libs optional package        | ~200 MB total             |
|   └─ ICU data alone      | libicudata.so.60                 | ~26 MB                    |
|   └─ Qt5 Core            | libQt5Core.so.5                  | ~14 MB                    |
|   └─ GTK3                | libgtk-3.so.0                    | ~13 MB                    |
| Cairo+pango chain        | (subset of gui_libs)             | ~15 MB                    |
| gvim (optional)          | GTK3 GUI vim 9.2                 | ~5 MB                     |
| nedit-ng (optional)      | Qt5 NEdit rewrite                | ~8 MB                     |
| Portable Python          | python3.14                       | ~40 MB                    |
| Treesitter parsers       | all platforms                    | ~20 MB                    |
| Octave (optional)        | octave 11.1.0                    | ~163 MB                   |

Future: consider splitting pre_built into lightweight (→ `~/.local`) and heavyweight
(→ shared filesystem, symlinked from `~/.local`). See memory file `project_prebuilt_bifurcation.md`.

## gvim build notes (vim 9.2.458, added 2026-05-16)

Built as GTK3 GUI vim targeting el8.x86_64.glibc2p28. Requires gcc-toolset-14 active.

**Prerequisites:**
```bash
sudo dnf install -y gcc make ncurses-devel gtk3-devel libX11-devel libXt-devel libSM-devel libICE-devel
. /opt/rh/gcc-toolset-14/enable
```

**Build:**
```bash
cd /tmp/vim-src
make distclean   # important if previously built without GTK3
./configure \
  --prefix=/tmp/gvim-install \
  --with-features=huge \
  --enable-gui=gtk3 \
  --with-x \
  --enable-multibyte \
  --disable-perl --disable-ruby --disable-python3 --disable-tcl \
  CFLAGS="-O2 -fno-strength-reduce -Wall -Wno-deprecated-declarations \
          -D_REENTRANT -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=1"
make -j$(nproc)
# Binary at src/vim
```

**Packaging (strip → patchelf → bzip2):**
```bash
cp src/vim /tmp/gvim_tmp
/usr/bin/strip /tmp/gvim_tmp
~/.local/bin/patchelf --set-rpath '$ORIGIN/../lib64:$ORIGIN/../lib' /tmp/gvim_tmp
bzip2 -k /tmp/gvim_tmp
cp /tmp/gvim_tmp.bz2 pre_built/el8.x86_64.glibc2p28/bin/gvim.bin.bz2
```

**gvim wrapper** (`gvim.bz2`): shell script that sets `VIM`/`VIMRUNTIME` and execs `gvim.bin -g "$@"` to force GUI mode regardless of argv[0]. Not an ELF — recorded in `.strip-manifest` as a non-ELF skip.

Binary sizes: 4.5 MB unstripped → 1.9 MB stripped → ~740 KB bzip2.
See `pre_built/build_scripts/build-gvim.sh` for the full recipe.

## nedit-ng build notes (v2.0.1, commit 72661f5, added 2026-05-16)

Qt5 CMake rewrite of NEdit. Single self-contained binary — Qt .qrc embeds all resources, no runtime files needed. Requires gcc-toolset-14 and Qt5 devel packages.

**Prerequisites:**
```bash
sudo dnf install -y cmake gcc-c++ qt5-qtbase-devel qt5-qtsvg-devel qt5-linguist libXt-devel
. /opt/rh/gcc-toolset-14/enable
# qt5-linguist is required for lupdate/lrelease during the CMake build; easy to miss
```

**Build:**
```bash
git clone https://github.com/eteran/nedit-ng /tmp/nedit-ng-src
cd /tmp/nedit-ng-src
cmake -B build \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_CXX_FLAGS="-O2 -Wall"
cmake --build build -j$(nproc)
# Binary at build/nedit-ng
```

**Packaging (strip → bzip2, no patchelf — Qt5 libs already in lib64/):**
```bash
cp build/nedit-ng /tmp/nedit_tmp
/usr/bin/strip /tmp/nedit_tmp
bzip2 -k /tmp/nedit_tmp
cp /tmp/nedit_tmp.bz2 pre_built/el8.x86_64.glibc2p28/bin/nedit-ng.bz2
```

nedit-ng is `optional: true` in `packages.json` because it requires `gui_libs`. Install together:
`./engineering-loadout --add gui_libs,nedit-ng`.

Binary sizes: 3.8 MB unstripped → 3.1 MB stripped → ~1.1 MB bzip2.
See `pre_built/build_scripts/build-nedit-ng.sh` for the full recipe.

## gui_libs bundle notes (added 2026-05-16)

~80 shared libs covering Qt5 5.15.3, GTK3 3.22, ICU 60, cairo, pango, glib2, xcb extensions,
xkbcommon, Wayland client, and X11 client libs. All built from system packages on AlmaLinux 8.10.

**All libs use RPATH `$ORIGIN`** (not `$ORIGIN/../lib64`) so they find each other when installed
flat into `~/.local/lib64/`. This is different from binaries which use `$ORIGIN/../lib64:$ORIGIN/../lib`.

**Qt5 platform plugins** (`libqxcb.so`, `libqwayland-generic.so`): stored flat in `lib64/`
alongside the other Qt5 libs. `bash/global/bashrc` sets:
```bash
export QT_QPA_PLATFORM_PLUGIN_PATH=$HOME/.local/lib64
```
Qt finds plugins directly in that directory (no `platforms/` subdirectory needed).

**Critical: never bundle** `libGL.so.1`, `libGLX.so.0`, `libGLdispatch.so.0` — these must be
the system's display-driver version. Qt5 and GTK3 work fine without them for non-OpenGL GUIs.

**Transitive dep closure script** used to find all deps recursively:
```bash
# Recursive ldd with never-bundle filter
seen=(); queue=(/path/to/binary); while [[ ${#queue[@]} -gt 0 ]]; do ...
```
See session history for the full `/tmp/dep_closure.sh` script.
