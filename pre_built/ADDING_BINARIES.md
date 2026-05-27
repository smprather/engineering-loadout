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

## nvim-qt build notes (v0.2.19, added 2026-05-2x)

Qt5 GUI frontend for Neovim. CMake build — no Rust, no GPU renderer. No Docker needed.
At runtime the binary resolves Qt5 from `~/.local/lib64` (gui_libs) via pre-baked RPATH,
so users don't need a system Qt5 install.

**Prerequisites:**
```bash
sudo dnf install -y cmake git gcc gcc-c++ bzip2 qt5-qtbase-devel qt5-qtsvg-devel
sudo dnf config-manager --set-enabled powertools   # needed for qt5-qtsvg-devel
. /opt/rh/gcc-toolset-14/enable
```

**Build:**
```bash
git clone --filter=blob:none https://github.com/equalsraf/neovim-qt.git /tmp/nvim-qt-build-0.2.19
cd /tmp/nvim-qt-build-0.2.19
git fetch --tags && git checkout v0.2.19
cmake -B build -S . \
    -DCMAKE_BUILD_TYPE=Release \
    -DENABLE_TESTS=OFF \
    -DCMAKE_SKIP_RPATH=ON
cmake --build build -j$(nproc)
# Binary at build/bin/nvim-qt
```

**Packaging (strip → patchelf → bzip2):**
```bash
cp build/bin/nvim-qt /tmp/nvim-qt_tmp
/usr/bin/strip /tmp/nvim-qt_tmp
~/.local/bin/patchelf --set-rpath '$ORIGIN/../lib64:$ORIGIN/../lib' /tmp/nvim-qt_tmp
bzip2 -k /tmp/nvim-qt_tmp
cp /tmp/nvim-qt_tmp.bz2 pre_built/el8.x86_64.glibc2p28/bin/nvim-qt.bz2
```

nvim-qt depends on `gui_libs` at runtime. The `packages.json` entry sets
`"depends": ["gui_libs"]` so the resolver auto-pulls gui_libs when nvim-qt is selected.

**WSLg runtime note:** Qt5's XCB backend corrupts XWayland's global cursor state for
all X11 apps (all windows lose their cursor after nvim-qt opens). This is a runtime
issue, not a build issue. Fix: `export QT_QPA_PLATFORM=wayland` in
`~/.config/bash/user/bashrc`. Routes Qt5 through the Wayland compositor instead of
XWayland. Wayland backend is included in gui_libs (`libqwayland-generic.so`).

See `pre_built/build_scripts/build-nvim-qt.sh` for the full recipe.

## xterm build notes (410, added 2026-05-26)

Produces two binaries from a single source build: `xterm` and `resize`.

**Prerequisites:**
```bash
sudo dnf install -y gcc make libX11-devel libXft-devel libXt-devel libXext-devel \
                   fontconfig-devel freetype-devel utempter-devel
. /opt/rh/gcc-toolset-14/enable
```

**Build:**
```bash
curl -fsSL https://invisible-island.net/archives/xterm/xterm-410.tgz | \
    tar xz -C /tmp && cd /tmp/xterm-410
./configure \
    --prefix=/tmp/xterm-install \
    --enable-256-color \
    --enable-wide-chars \
    --with-xft \
    --with-utempter
make -j$(nproc) && make install
# Binaries at /tmp/xterm-install/bin/xterm and /tmp/xterm-install/bin/resize
```

**Packaging (strip → patchelf → bzip2, both binaries):**
```bash
for b in xterm resize; do
    cp /tmp/xterm-install/bin/$b /tmp/${b}_tmp
    /usr/bin/strip /tmp/${b}_tmp
    ~/.local/bin/patchelf --set-rpath '$ORIGIN/../lib64:$ORIGIN/../lib' /tmp/${b}_tmp
    bzip2 -k /tmp/${b}_tmp
    cp /tmp/${b}_tmp.bz2 pre_built/el8.x86_64.glibc2p28/bin/${b}.bz2
done
```

`resize` is listed under the `xterm` packages.json entry (`"bins": ["xterm", "resize"]`).
See `pre_built/build_scripts/build-xterm.sh` for the full recipe.

## expect build notes (5.45.4 + Tcl 8.6.16, added 2026-05-26)

Tcl-based CLI automation tool. Requires Tcl 8.6 built from source into a staging prefix
so `libtcl8.6.so` can be bundled alongside `expect`.

**Two mandatory patches for EL8 + gcc-toolset-14 (GCC 14):**

### Patch 1: GCC 14 implicit-int errors in configure
GCC 14 promotes `-Wimplicit-int`, `-Wimplicit-function-declaration`, and
`-Wincompatible-pointer-types` to errors. expect's autoconf test code is C89-style and
trips all three. Without this fix, the `struct termios` detection fails, PTY detection
fails, and configure selects the wrong `pty_.c` — the build may succeed but expect won't
work correctly.

Add to CFLAGS for both Tcl and expect configure:
```
-Wno-implicit-int -Wno-implicit-function-declaration -Wno-return-type -Wno-incompatible-pointer-types
```

### Patch 2: exp_chan.c Tcl_ChannelType field order
Modern Tcl (8.6+) requires `TCL_CHANNEL_VERSION_4` as the second field of
`Tcl_ChannelType`. expect 5.45.4 puts `ExpBlockModeProc` there directly (old API).
GCC 14 now errors on the incompatible pointer type. Patch `exp_chan.c` before `make`:

```c
/* Old (broken with GCC 14 + modern Tcl): */
Tcl_ChannelType expChannelType = {
    "exp",
    ExpBlockModeProc,   /* WRONG: this slot is now for version, not blockModeProc */
    ...
};

/* Fixed: */
Tcl_ChannelType expChannelType = {
    "exp",                      /* Type name. */
    TCL_CHANNEL_VERSION_4,      /* Version. */         ← inserted
    ExpCloseProc,               /* Close proc. */
    ExpInputProc,               /* Input proc. */
    ExpOutputProc,              /* Output proc. */
    NULL,                       /* Seek proc. */
    NULL,                       /* Set option proc. */
    NULL,                       /* Get option proc. */
    ExpWatchProc,               /* Initialize notifier. */
    ExpGetHandleProc,           /* Get OS handles out of channel. */
    NULL,                       /* Close2 proc */
    ExpBlockModeProc,           /* Set blocking/nonblocking mode. */ ← moved to slot 12
};
```

`build-expect.sh` applies this patch automatically via embedded Python.

### Build procedure

```bash
# Step 1: Build Tcl 8.6 into a staging prefix
TCL_INSTALL=/tmp/tcl-install-8.6.16
curl -fsSL https://prdownloads.sourceforge.net/tcl/tcl8.6.16-src.tar.gz -o /tmp/tcl8.6.16-src.tar.gz
mkdir -p /tmp/tcl-src-8.6.16 && tar xzf /tmp/tcl8.6.16-src.tar.gz -C /tmp/tcl-src-8.6.16 --strip-components=1
cd /tmp/tcl-src-8.6.16/unix
./configure --prefix=$TCL_INSTALL --enable-shared --disable-static \
    CFLAGS="-O2 -fstack-protector-strong"
make -j$(nproc) && make install

# Step 2: Build expect
curl -fsSL "https://sourceforge.net/projects/expect/files/Expect/5.45.4/expect5.45.4.tar.gz/download" \
    -o /tmp/expect5.45.4.tar.gz
mkdir -p /tmp/expect-src-5.45.4 && tar xzf /tmp/expect5.45.4.tar.gz -C /tmp/expect-src-5.45.4 --strip-components=1
cd /tmp/expect-src-5.45.4

# Apply exp_chan.c patch (see build-expect.sh for the embedded Python patcher)

./configure \
    --prefix=/tmp/expect-install-5.45.4 \
    --with-tcl=$TCL_INSTALL/lib \
    --with-tclinclude=$TCL_INSTALL/include \
    CFLAGS="-O2 -fstack-protector-strong -Wno-implicit-int -Wno-implicit-function-declaration -Wno-return-type -Wno-incompatible-pointer-types"
make -j$(nproc) && make install
```

**Binary location quirk:** `make install` puts the `expect` binary in the **Tcl prefix**
(`$TCL_INSTALL/bin/expect`), not in the expect `--prefix`. Always pick it up from there.

**Packaging:**
```bash
# expect binary (from TCL prefix, not expect prefix)
cp $TCL_INSTALL/bin/expect /tmp/expect_work
/usr/bin/strip /tmp/expect_work
~/.local/bin/patchelf --set-rpath '$ORIGIN/../lib64:$ORIGIN/../lib' /tmp/expect_work
bzip2 -k /tmp/expect_work
cp /tmp/expect_work.bz2 pre_built/el8.x86_64.glibc2p28/bin/expect.bz2

# libtcl8.6.so (from Tcl staging install)
cp $TCL_INSTALL/lib/libtcl8.6.so /tmp/libtcl86_work
/usr/bin/strip /tmp/libtcl86_work
~/.local/bin/patchelf --set-rpath '$ORIGIN' /tmp/libtcl86_work
bzip2 -k /tmp/libtcl86_work
cp /tmp/libtcl86_work.bz2 pre_built/el8.x86_64.glibc2p28/lib64/libtcl8.6.so.bz2
```

Max glibc symbol: GLIBC_2.17 — well within EL8's 2.28 ceiling.

See `pre_built/build_scripts/build-expect.sh` for the full recipe (includes the
exp_chan.c patcher and automatic packages.json version update).

---

## Python wheel packaging notes

### manylinux platform flag for pip download

**Always use `--platform manylinux_2_28_x86_64`** when downloading wheels for the EL8 bundle:

```bash
PIP_REQUIRE_VIRTUALENV=0 pip3.14 download <pkg> \
  --platform manylinux_2_28_x86_64 \
  --python-version 3.14 \
  --only-binary :all: \
  -d pre_built/el8.x86_64.glibc2p28/wheels/
```

`manylinux_2_28_x86_64` accepts all wheels with minimum glibc ≤ 2.28:
manylinux1 (2.5) → manylinux2010 (2.12) → manylinux2014/manylinux_2_17 → ... → manylinux_2_28.
It does NOT pull manylinux_2_29+ wheels (those require RHEL9/glibc 2.29+, won't run on EL8).

**Do NOT use `--platform manylinux2014_x86_64`** — that is equivalent to manylinux_2_17 and
will miss wheels tagged manylinux_2_18 through manylinux_2_28 (e.g. numpy 2.x for cp314
ships as manylinux_2_27 minimum; `--platform manylinux2014_x86_64` won't find it).

If `pip download` fails even with `manylinux_2_28_x86_64 --only-binary :all:`, the package
has no pre-built cp314 wheel compatible with EL8 and must be built from source (see below).

### duckdb — pending cp314 wheel (blocker for pygwalker)

**Status:** duckdb ≥ 1.1 does not ship cp314 (Python 3.14) wheels on PyPI as of 2026-05.
Only cp313 and earlier are available. This blocks `pygwalker` installation (duckdb is
a hard dep of pygwalker).

**Resolution path A — wait for upstream:**
duckdb is actively maintained. Check for cp314 wheels in new releases:
```bash
pip3.14 download duckdb --platform manylinux_2_28_x86_64 --python-version 3.14 \
  --only-binary :all: -d /tmp/test-wheels/
```
Once a cp314 wheel appears, run the full pygwalker wheel download and commit.

**Resolution path B — build duckdb wheel from source on EL8:**
duckdb uses a bundled CMake build that links nothing from the system (self-contained).
The resulting wheel will be tagged `linux_x86_64` (not manylinux), which uv accepts
for local install via `--find-links`:

```bash
source /opt/rh/gcc-toolset-14/enable
sudo dnf install -y cmake ninja-build python3-devel

# Clone at latest stable tag
git clone --depth 1 --branch v1.3.0 https://github.com/duckdb/duckdb.git
cd duckdb

# Build Python extension
pip3.14 install build
python3.14 -m build --wheel

# Resulting wheel in dist/
ls dist/duckdb-*.whl   # tagged cp314-cp314-linux_x86_64

# Verify glibc requirement (should be ≤ 2.28):
readelf -V dist/duckdb-*.whl | grep -oE 'GLIBC_[0-9]+\.[0-9]+' | sort -V | tail -1

cp dist/duckdb-*.whl pre_built/el8.x86_64.glibc2p28/wheels/
./strip_all_elf_binaries
git add pre_built/ .strip-manifest
git commit -m "feat(pygwalker): bundle duckdb cp314 wheel (source build)"
```

Note: `python3.14 -m build` builds against the current environment's glibc (2.28).
The wheel will NOT be portable to glibc < 2.28 systems, but all EL8 systems have glibc 2.28
exactly, so this is fine for the loadout's fleet target.
