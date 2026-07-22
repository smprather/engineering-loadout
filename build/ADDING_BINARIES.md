# Adding Pre-Built Binaries

Reference for the build machine and the full workflow for adding a new binary.

## Build Machine

**AlmaLinux 8.10**, x86_64, glibc 2.28, running as WSL2 on Windows.
Platform directory: `el8.x86_64.glibc2p28`

```
uname -r  -> 6.6.87.2-microsoft-standard-WSL2
ldd --version -> ldd (GNU libc) 2.28
gcc --version -> gcc 14.2.1 (gcc-toolset-14, enabled in ~/.config/bash/user/bashrc)
/usr/bin/gcc --version -> gcc 8.5.0 (base system compiler, too old for most modern software)
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
- `libgd-devel` -- must build libgd from source if gd-based terminals needed

## Workflow

### 0. Use build/lib.sh in build scripts

New `build/build-*.sh` scripts should source the shared helper library
instead of re-pasting the boilerplate:

```sh
REPO="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib.sh
. "$REPO/build/lib.sh"
...
loadout_require_tag "$tag" "$0" "https://github.com/<org>/<tool>/releases" "vX.Y.Z"
loadout_enable_gcc_toolset
loadout_require_cmds cargo git            # or autoconf gcc make ...
...build...
loadout_package_bin "$BUILT_BIN" <stem>   # strip -> patchelf -> bzip2 -> payload bin dir
loadout_stamp_version <pkg> "${tag#v}"    # surgical packages.json version bump
loadout_report_max_glibc "$BUILT_BIN"
```

`build-models.sh`, `build-tmux.sh`, and `build-zsh.sh` are the converted
exemplars; the remaining scripts still inline the boilerplate and can be
converted opportunistically when next touched.

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

**NEVER bundle these -- they must come from the system:**

- **glibc components**: `libc.so.6`, `libm.so.6`, `libpthread.so.0`, `libdl.so.2`, `librt.so.1` -- must match the system's `ld-linux.so.2` exactly or you get `undefined symbol: _dl_audit_symbind_alt, version GLIBC_PRIVATE` crashes. Every EL8 system has glibc 2.28; never needed in the bundle.
- **OpenGL dispatcher**: `libGL.so.1`, `libGLX.so.0`, `libGLdispatch.so.0` -- must be the system's display-driver-linked version. Bundling causes crashes or wrong driver selection. Qt5 and GTK3 can be built without OpenGL (use `--no-opengl` or equivalent).
- **C++ runtime**: `libstdc++.so.6`, `libgcc_s.so.1` -- present on all EL8 systems; version mismatches with C++ exceptions are subtle.

If any of these appear in `lib64/` from a previous mistake, remove them and purge from `~/.local/lib64` on deployed systems.

**Safe to bundle**: everything else -- libz, libpng, libX11, libreadline, libncurses, libfreetype, libfontconfig, libevent, libxxhash, Qt5, GTK3, glib2, ICU, pango, cairo, xcb extensions, xkbcommon, Wayland client libs. See `gui_libs` in `packages.json` as a worked example of a large GUI lib bundle.

### 3. Minimize the dep chain

Before bundling 30 libs, check if the binary can be built with fewer features:

- **Qt5**: brings ICU (~75 MB), SSL, kerberos, GL -- never worth it for home-dir installs
- **cairo + pango**: ~15 extra libs. Fine for a dedicated workstation, too heavy for ~4 GB quotas
- **libgd**: not in any EL8 repo; if needed, build from source or skip gd-based terminals
- **Lua**: adds `liblua-5.3.so`; usually optional (`--without-lua`)

For gnuplot specifically: `--without-qt --without-cairo --without-lua --with-x --with-readline=gnu`
gives dumb, x11, svg, postscript, eps, epslatex -- enough for scientific plotting. Only 2 new libs
(readline, ncurses).

### 4. Bundle the binary

```bash
REPO=/path/to/engineering-loadout
BIN_DIR="$REPO/payload/el8.x86_64.glibc2p28/bin"
LIB_DIR="$REPO/payload/el8.x86_64.glibc2p28/lib64"

# Binary -- order: strip -> patchelf -> compress. CRITICAL: always strip BEFORE patchelf.
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

# Shared lib -- filename must be the SONAME (ldd shows "libfoo.so.3 => ...")
# Standalone libs (only needed by one binary with a fixed RPATH): no patchelf needed.
# GUI libs that must find EACH OTHER (e.g. gui_libs group in lib64/): need RPATH $ORIGIN.
# Order for libs that need patchelf: strip -> patchelf -> bzip2 (same rule as binaries).
cp /lib64/libfoo.so.3.x.y /tmp/libfoo_tmp
/usr/bin/strip /tmp/libfoo_tmp
# If this lib needs to find sibling libs in the same lib64/ dir:
~/.local/bin/patchelf --set-rpath '$ORIGIN' /tmp/libfoo_tmp
bzip2 -k /tmp/libfoo_tmp
cp /tmp/libfoo_tmp.bz2 "$LIB_DIR/libfoo.so.3.bz2"
chmod 644 "$LIB_DIR/libfoo.so.3.bz2"
```

The installer decompresses `bin/*.bz2` -> `~/.local/bin` and `lib64/*.bz2` -> `~/.local/lib64`.
RPATH is pre-baked into each binary in the repo (see above), so no post-install patchelf is needed.

### 5. Strip

```bash
./strip-all-elf-binaries
```

Strips debug symbols from new `.bz2` payloads and records them in `.strip-manifest` so they're
skipped on subsequent runs. Typical savings: 60-75% size reduction before compression.
Never run on `portable-python-*.tar.bz2` (BOLT-optimized, in NOSTRIP list).

### 6. Update farm-versions

Add an entry to `TOOLS` in `build/farm-versions`. Entries are
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

# Custom extraction (e.g. gnuplot: "6.0 patchlevel 2" -> "6.0.2")
lambda binary: (lambda m: re.sub(r" patchlevel ", ".", m.group(1)) if m else None)(
    re.search(r"toolname ([0-9]+\.[0-9]+ patchlevel [0-9]+)", _run([binary, "--version"])))
```

### 7. Register in packages.json

Add an entry under `packages` in `payload/packages.json` (`schema_version: 3`):

```json
"mytool": {
  "kind": "bin",
  "bins": ["mytool"],
  "libs": ["libnewdep.so.3"],
  "version": "X.Y.Z",
  "platforms": ["linux"],
  "tags": ["data"],
  "description": "One-line description"
}
```

If the tool should ship with the curated bundled set, also add `"mytool"` to
the `@engineering-loadout` group's `members` list. There is no `default`
field in schema 3 -- users always name packages or groups explicitly.

Key rules:
- `kind` -- one of `bin`, `lib-bundle`, `runtime`, `typelib`, `python-base`,
  `python-tool`, `env`, `font`, `data`, `group`. For a normal pre-built binary use `bin`.
- `bins` -- every `bin/*.bz2` stem this build produces (e.g. `"vim"` lists `["vim", "vim.bin"]`,
  `"xterm"` lists `["xterm", "resize"]`).
- `libs` -- **only** lib64 stems that are *exclusively* owned by this tool (not needed by any
  other bundled tool). Shared deps (libX11, libncurses, etc.) should be omitted -- they are
  always installed regardless of tool selection.
- `optional: true` -- keep a large or niche tool out of `all` / `@shared` / the
  full loadout sweep. Users then opt in with `./loadout install mytool`.
- `platforms` -- list from `linux`, `macos`, `windows`. Resolver filters by current platform.
- `tags` -- free-form labels (`search`, `editor`, `monitor`, ...) used by `list --tag T`.
- `depends` -- list of hard-dep package names (or `@group` refs). Resolver auto-pulls them;
  skipping a hard dep raises `ResolverError` unless `--no-deps` or `--force`. Use for
  binary-needs-lib-bundle (e.g. `"gvim"` depends on `"gui_libs"` + `"vim92-runtime"`).
- `recommends` -- list of soft-dep package names. Silently dropped if skipped.
- `uv_extras` -- for `python-tool`: extras appended to `uv_tool` as
  `package[extra,...]`. Bundle the complete locked wheel closure for every extra;
  offline installs cannot fetch it later.

For a tool with a single binary, no exclusive libs, and no deps:
`"mytool": {"kind": "bin", "bins": ["mytool"], "version": "X.Y.Z", "platforms": ["linux"], "description": "..."}`.

There is no `default` field -- the registry is pure opt-in (bare `install` errors). A
plain non-`optional` package is swept into the synthetic `all` group, so it ships in the
full `@engineering-loadout` bundle automatically. Add it to an `@group` `members` list
elsewhere in `packages.json` (e.g. `@core-cli`, `@dev-tools`, `@editor-cli`) to make it
discoverable by group selection. Set `"optional": true` to keep it OUT of `all` /
`@shared` / `@engineering-loadout` so it installs only when named explicitly or pulled by
a group that lists it (e.g. `surfer`, the `@rust` trio).

### 8. Verify and commit

```bash
# Smoke-test decompressed binary
bunzip2 -k -c payload/el8.x86_64.glibc2p28/bin/mytool.bz2 > /tmp/t && chmod +x /tmp/t
ldd /tmp/t | grep "not found"   # must be empty
/tmp/t --version

# Check farm-versions picks it up
build/farm-versions --format text

git add payload/el8.x86_64.glibc2p28/bin/mytool.bz2 \
        payload/el8.x86_64.glibc2p28/lib64/libnew*.bz2 \
        build/farm-versions \
        payload/packages.json \
        .strip-manifest
git commit
```

## Neovim build notes (currently shipping v0.12.2 stable; procedure below first recorded for a 2026-05-12 nightly)

Built from source at `~/neovim` (stable tag; the stable-release policy forbids
shipping nightlies -- rebuild from the latest stable tag). CMake flags:
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
system. The resulting binary links only against glibc components -- no libs to bundle.

Binary: 33 MB unstripped (RelWithDebInfo) -> 5.9 MB stripped -> 2.6 MB compressed.
Runtime archive (`nvim.tar.bz2`): 27 MB uncompressed -> 4.8 MB compressed.
Installer extracts runtime to `~/.local/share/nvim/runtime/`.
See `build/build-nvim.sh` for the full rebuild recipe.

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
Runtime data (`share/gnuplot/6.0/`) not bundled -- binary works without it for core terminals
(svg, postscript, x11, dumb all tested OK). If help or color palettes are needed later,
package `share/gnuplot/` as `gnuplot-runtime.tar.bz2` and add installer support.

### gnuplot_x11 driver (added 2026-06-26)

gnuplot 6's `x11` terminal is **not in-process** -- gnuplot forks a separate helper
`gnuplot_x11` and pipes it a command stream. It resolves the helper via
`$GNUPLOT_DRIVER_DIR/gnuplot_x11`, falling back to the compiled-in
`<prefix>/libexec/gnuplot/6.0/gnuplot_x11`. The original build baked
`--prefix=/tmp/gnuplot-install`, so on a destination machine x11 plots died with
`Couldn't exec expected X11 driver: /tmp/gnuplot-install/libexec/gnuplot/6.0/gnuplot_x11`.
The helper was never bundled (only `bin/gnuplot`). Tools that default to the x11 terminal
(e.g. `tct plot`) failed on every plot.

Fix: bundle the helper as a runtime archive and point gnuplot at it via env var.

```bash
# Helper lives at <build-prefix>/libexec/gnuplot/6.0/gnuplot_x11 after the source build above.
PLAT=el8.x86_64.glibc2p28
STAGE=$(mktemp -d); DEST="$STAGE/libexec/gnuplot/6.0"; mkdir -p "$DEST"
cp /tmp/gnuplot-install/libexec/gnuplot/6.0/gnuplot_x11 "$DEST/gnuplot_x11"
/usr/bin/strip "$DEST/gnuplot_x11"
# Helper installs to ~/.local/libexec/gnuplot/6.0/; sibling libs are in ~/.local/lib64
# -> RPATH up three levels. Falls back to host /lib64 when gui_libs is absent.
~/.local/bin/patchelf --set-rpath '$ORIGIN/../../../lib64:$ORIGIN/../../../lib' "$DEST/gnuplot_x11"
chmod 755 "$DEST/gnuplot_x11"
tar -C "$STAGE" -cf - ./libexec | bzip2 -9 > "payload/$PLAT/runtime/gnuplot.tar.bz2"
rm -rf "$STAGE"
./strip-all-elf-binaries          # normalizes the archive, records it in .strip-manifest
```

Wiring:
- `packages.json` `gnuplot` entry gains `sentinel`/`install_to`/`archive_name`/`chmod_sentinel`/
  `remove_before_extract`, so the generic `install_runtime_archives` extracts it to
  `~/.local/libexec/gnuplot/6.0/` (un-dotted `local/...` under `--dest-dir`).
- `bash/global/bashrc` exports `GNUPLOT_DRIVER_DIR=$_loadout_local_prefix/libexec/gnuplot/6.0`
  when the helper is present (shared-prefix aware).

The helper links `libX11`/`libxcb`/`libXau`. No hard dep on `gui_libs` is added: the main
gnuplot binary is headless (no X linkage), and the helper resolves X libs from `gui_libs`
(via RPATH) or the host's `/lib64`. Pure compute nodes with no X libs need `gui_libs`.

## Octave build notes (11.1.0, added 2026-05-13)

Built without Qt, Java, OpenGL, FLTK, or X11. Plots work via gnuplot backend (already bundled).
RapidJSON disabled to avoid a GCC 14 read-only-member compile error.

```bash
# Enable GCC 14 (required -- GCC 8.5 from base is too old for Octave 11)
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

See `build/build-octave.sh` for the full bundling recipe.

**Binary layout:**
- `bin/octave.bz2` -- thin 16K launcher (stripped), RPATH = `$ORIGIN/../lib64`
- `lib64/liboctave.so.13.bz2`, `liboctinterp.so.15.bz2`, `liboctmex.so.1.bz2` -- core libs, RPATH = `$ORIGIN`
- 35 exclusive dep libs in `lib64/` (FFTW, HDF5, BLAS, SuiteSparse, GFortran, audio, GLPK, QHull, ...)
- `runtime/octave.tar.bz2` -- m-files (`share/octave/11.1.0/`) + compiled plugins (`lib/octave/11.1.0/oct/`, patchelf'd RPATH = `$ORIGIN/../../../../../lib64`)

**What is NOT bundled:** doc (saves ~5.6 MB), Qt/FLTK/X11 (no display on headless machines).

**Total uncompressed install size:** ~163 MB. Dominated by libopenblas + libopenblasp (~110 MB combined). This is why octave is `optional: true` in `packages.json`.

## Disk quota considerations

Home directory quotas on shared compute systems are typically small (~4-10 GB). Rough sizes after stripping:

| Category                 | Example                          | Approx size (uncompressed) |
|--------------------------|----------------------------------|---------------------------|
| Rust/Go binaries         | rg, fd, bat, eza, starship       | 0.5-3 MB each             |
| C binaries               | gnuplot, htop, tmux              | 0.3-1.5 MB each           |
| Qt5/GTK3 + xcb + Wayland | gui_libs optional package        | ~200 MB total             |
|   `- ICU data alone      | libicudata.so.60                 | ~26 MB                    |
|   `- Qt5 Core            | libQt5Core.so.5                  | ~14 MB                    |
|   `- GTK3                | libgtk-3.so.0                    | ~13 MB                    |
| Cairo+pango chain        | (subset of gui_libs)             | ~15 MB                    |
| gvim (optional)          | GTK3 GUI vim 9.2                 | ~5 MB                     |
| nedit-ng (optional)      | Qt5 NEdit rewrite                | ~8 MB                     |
| Portable Python          | python3.14                       | ~40 MB                    |
| Treesitter parsers       | all platforms                    | ~20 MB                    |
| Octave (optional)        | octave 11.1.0                    | ~163 MB                   |

Future: consider splitting payload into lightweight (-> `~/.local`) and heavyweight
(-> shared filesystem, symlinked from `~/.local`). See memory file `project_prebuilt_bifurcation.md`.

## PowerShell 7.6.3 -- Windows x64 portable ZIP

Windows installs use a user-local PowerShell runtime so `.\loadout.cmd` can run
without admin rights, winget, Store/App Installer, or a system `pwsh.exe`.
Bundle the official Microsoft ZIP under:

```powershell
payload\windows.x86_64\powershell\PowerShell-<version>-win-x64.zip
```

Refresh from GitHub releases, then split into 45 MiB parts:

```powershell
New-Item -ItemType Directory -Force payload\windows.x86_64\powershell | Out-Null
gh release download v7.6.3 -R PowerShell/PowerShell `
  -p PowerShell-7.6.3-win-x64.zip `
  -D payload\windows.x86_64\powershell --clobber
Get-FileHash payload\windows.x86_64\powershell\PowerShell-7.6.3-win-x64.zip -Algorithm SHA256
python .\split-bz2 --chunk-mb 45 payload\windows.x86_64\powershell\PowerShell-7.6.3-win-x64.zip
```

Update `payload/windows.x86_64/powershell/README.md` with the source URL and
SHA256. The Windows bootstrap rejoins `.zip.part-NNN` files before extraction.

## vim + gvim build notes (vim 9.2.0782; originally added 2026-05-16 at 9.2.458)

One vim source checkout produces all three artifacts: terminal `vim.bin`,
GUI `gvim.bin`, and the `vim92.tar.bz2` runtime archive. Clone the stable
patch tag: `git clone --depth 1 --branch v9.2.0782 https://github.com/vim/vim`.
Requires gcc-toolset-14 active.

### Terminal vim (vim.bin) + runtime archive

```bash
cd <vim-checkout>
./configure --with-features=huge --enable-gui=no --without-x --without-wayland \
  --enable-multibyte \
  CFLAGS="-O2 -fno-strength-reduce -Wall -Wno-deprecated-declarations \
          -D_REENTRANT -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=1"
make -j$(nproc)
# strip -> patchelf '$ORIGIN/../lib64:$ORIGIN/../lib' -> bzip2 -> bin/vim.bin.bz2
```

`--without-wayland` is load-bearing: vim 9.2.07xx gained Wayland clipboard
support and would otherwise link `libwayland-client.so.0`, which terminal vim
must not depend on (that lib ships in gui_libs; plain `vim` has no gui_libs
dependency). Expected NEEDED: libm, libtinfo, libselinux, librt, libacl,
libdl, libc only.

The runtime archive is packed from the **source tree's `runtime/` directory**
(not `make install` output -- install drops the spell binaries and source-tree
extras), excluding the test bloat:

```bash
cp -a <vim-checkout>/runtime stage/runtime
find stage/runtime -type d -name testdir -prune -exec rm -rf {} +  # ~2200 test files
# sanity: stage/runtime/filetype.vim and stage/runtime/spell/en.utf-8.spl exist
tar cjf payload/el8.x86_64.glibc2p28/runtime/vim92.tar.bz2 -C stage ./runtime
```

### gvim (gvim.bin)

GTK3 GUI build from the same checkout (run `make distclean` in between).

**Prerequisites:**
```bash
sudo dnf install -y gcc make ncurses-devel gtk3-devel libX11-devel libXt-devel libSM-devel libICE-devel
. /opt/rh/gcc-toolset-14/enable
```

**Build:**
```bash
cd <vim-checkout>
make distclean   # important if previously built without GTK3
./configure \
  --with-features=huge \
  --enable-gui=gtk3 \
  --with-x \
  --enable-multibyte \
  CFLAGS="-O2 -fno-strength-reduce -Wall -Wno-deprecated-declarations \
          -D_REENTRANT -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=1"
make -j$(nproc)
# Binary at src/vim
```

(The old `--disable-perl/--disable-ruby/...` flags were never real configure
options -- vim warns "unrecognized"; those interfaces are simply off by
default. gvim's NEEDED list legitimately includes libwayland-client via GTK3;
gvim depends on gui_libs which bundles it.)

**Packaging (strip -> patchelf -> bzip2):**
```bash
cp src/vim /tmp/gvim_tmp
/usr/bin/strip /tmp/gvim_tmp
~/.local/bin/patchelf --set-rpath '$ORIGIN/../lib64:$ORIGIN/../lib' /tmp/gvim_tmp
bzip2 -k /tmp/gvim_tmp
cp /tmp/gvim_tmp.bz2 payload/el8.x86_64.glibc2p28/bin/gvim.bin.bz2
```

**gvim wrapper** (`gvim.bz2`): shell script that sets `VIM`/`VIMRUNTIME` and execs `gvim.bin -g "$@"` to force GUI mode regardless of argv[0]. Not an ELF -- recorded in `.strip-manifest` as a non-ELF skip.

Binary sizes: 4.5 MB unstripped -> 1.9 MB stripped -> ~740 KB bzip2.
See `build/build-gvim.sh` for the full recipe.

## nedit-ng build notes (v2.0.1, commit 72661f5, added 2026-05-16)

Qt5 CMake rewrite of NEdit. Single self-contained binary -- Qt .qrc embeds all resources, no runtime files needed. Requires gcc-toolset-14 and Qt5 devel packages.

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

**Packaging (strip -> bzip2, no patchelf -- Qt5 libs already in lib64/):**
```bash
cp build/nedit-ng /tmp/nedit_tmp
/usr/bin/strip /tmp/nedit_tmp
bzip2 -k /tmp/nedit_tmp
cp /tmp/nedit_tmp.bz2 payload/el8.x86_64.glibc2p28/bin/nedit-ng.bz2
```

nedit-ng is `optional: true` in `packages.json` because it requires `gui_libs`. Install together:
`./loadout install gui_libs,nedit-ng`.

Binary sizes: 3.8 MB unstripped -> 3.1 MB stripped -> ~1.1 MB bzip2.
See `build/build-nedit-ng.sh` for the full recipe.

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

**Critical: never bundle** `libGL.so.1`, `libGLX.so.0`, `libGLdispatch.so.0` -- these must be
the system's display-driver version. Qt5 and GTK3 work fine without them for non-OpenGL GUIs.

**Transitive dep closure script** used to find all deps recursively:
```bash
# Recursive ldd with never-bundle filter
seen=(); queue=(/path/to/binary); while [[ ${#queue[@]} -gt 0 ]]; do ...
```
See session history for the full `/tmp/dep_closure.sh` script.

## nvim-qt build notes (v0.2.19, added 2026-05-2x)

Qt5 GUI frontend for Neovim. CMake build -- no Rust, no GPU renderer. No Docker needed.
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

**Packaging (strip -> patchelf -> bzip2):**
```bash
cp build/bin/nvim-qt /tmp/nvim-qt_tmp
/usr/bin/strip /tmp/nvim-qt_tmp
~/.local/bin/patchelf --set-rpath '$ORIGIN/../lib64:$ORIGIN/../lib' /tmp/nvim-qt_tmp
bzip2 -k /tmp/nvim-qt_tmp
cp /tmp/nvim-qt_tmp.bz2 payload/el8.x86_64.glibc2p28/bin/nvim-qt.bz2
```

nvim-qt depends on `gui_libs` at runtime. The `packages.json` entry sets
`"depends": ["gui_libs"]` so the resolver auto-pulls gui_libs when nvim-qt is selected.

**WSLg runtime note:** Qt5's XCB backend corrupts XWayland's global cursor state for
all X11 apps (all windows lose their cursor after nvim-qt opens). This is a runtime
issue, not a build issue. Fix: `export QT_QPA_PLATFORM=wayland` in
`~/.config/bash/user/bashrc`. Routes Qt5 through the Wayland compositor instead of
XWayland. Wayland backend is included in gui_libs (`libqwayland-generic.so`).

See `build/build-nvim-qt.sh` for the full recipe.

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

**Packaging (strip -> patchelf -> bzip2, both binaries):**
```bash
for b in xterm resize; do
    cp /tmp/xterm-install/bin/$b /tmp/${b}_tmp
    /usr/bin/strip /tmp/${b}_tmp
    ~/.local/bin/patchelf --set-rpath '$ORIGIN/../lib64:$ORIGIN/../lib' /tmp/${b}_tmp
    bzip2 -k /tmp/${b}_tmp
    cp /tmp/${b}_tmp.bz2 payload/el8.x86_64.glibc2p28/bin/${b}.bz2
done
```

`resize` is listed under the `xterm` packages.json entry (`"bins": ["xterm", "resize"]`).
See `build/build-xterm.sh` for the full recipe.

## expect build notes (5.45.4 + Tcl 8.6.16, added 2026-05-26)

Tcl-based CLI automation tool. Requires Tcl 8.6 built from source into a staging prefix
so `libtcl8.6.so` can be bundled alongside `expect`.

**Two mandatory patches for EL8 + gcc-toolset-14 (GCC 14):**

### Patch 1: GCC 14 implicit-int errors in configure
GCC 14 promotes `-Wimplicit-int`, `-Wimplicit-function-declaration`, and
`-Wincompatible-pointer-types` to errors. expect's autoconf test code is C89-style and
trips all three. Without this fix, the `struct termios` detection fails, PTY detection
fails, and configure selects the wrong `pty_.c` -- the build may succeed but expect won't
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
    TCL_CHANNEL_VERSION_4,      /* Version. */         <- inserted
    ExpCloseProc,               /* Close proc. */
    ExpInputProc,               /* Input proc. */
    ExpOutputProc,              /* Output proc. */
    NULL,                       /* Seek proc. */
    NULL,                       /* Set option proc. */
    NULL,                       /* Get option proc. */
    ExpWatchProc,               /* Initialize notifier. */
    ExpGetHandleProc,           /* Get OS handles out of channel. */
    NULL,                       /* Close2 proc */
    ExpBlockModeProc,           /* Set blocking/nonblocking mode. */ <- moved to slot 12
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
cp /tmp/expect_work.bz2 payload/el8.x86_64.glibc2p28/bin/expect.bz2

# libtcl8.6.so (from Tcl staging install)
cp $TCL_INSTALL/lib/libtcl8.6.so /tmp/libtcl86_work
chmod u+w /tmp/libtcl86_work   # make install writes it 555; strip rewrites in place
/usr/bin/strip /tmp/libtcl86_work
~/.local/bin/patchelf --set-rpath '$ORIGIN' /tmp/libtcl86_work
bzip2 -k /tmp/libtcl86_work
cp /tmp/libtcl86_work.bz2 payload/el8.x86_64.glibc2p28/lib64/libtcl8.6.so.bz2

# Private expect runtime (real ELF + Tcl 8.6 script library) -> runtime archive
mkdir -p /tmp/expect-stage/lib/expect/{bin,lib}
cp $TCL_INSTALL/bin/expect /tmp/expect-stage/lib/expect/bin/expect.bin
strip /tmp/expect-stage/lib/expect/bin/expect.bin
~/.local/bin/patchelf --set-rpath '$ORIGIN/../../../lib64:$ORIGIN/../../../lib' \
    /tmp/expect-stage/lib/expect/bin/expect.bin
cp -a $TCL_INSTALL/lib/tcl8.6 $TCL_INSTALL/lib/tcl8 /tmp/expect-stage/lib/expect/lib/
tar cjf payload/el8.x86_64.glibc2p28/runtime/expect.tar.bz2 -C /tmp/expect-stage ./lib
# bin/expect.bz2 is build/expect/expect (POSIX-sh wrapper), bzip2'd as-is
```

**Relocation (do not regress this):** libtcl8.6's compiled `tcl_library` is the
temp build prefix (`/tmp/tcl-install-*/lib/tcl8.6`), dead once deployed. Without
the script library on disk **every expect start fails** with `Tcl_Init failed:
Can't find a usable init.tcl` -- it shipped that way for a while because the
build box still had the temp prefix (classic build-box masking; the Tier 3
container caught it once the probe learned that banner is fatal). Three
constraints shape the fix:

1. The script library must ship, and Tcl's own search falls back to
   `<exedir>/../lib/tcl8.6` -- so the real ELF lives at
   `lib/expect/bin/expect.bin` with the trees at `lib/expect/lib/{tcl8.6,tcl8}`
   and `bin/expect` is a dumb exec wrapper (`build/expect/expect`).
2. **Never install the trees to `<prefix>/lib/tcl8.6`** -- portable-python owns
   that path at a different Tcl patchlevel, and `init.tcl` does
   `package require -exact Tcl <patchlevel>`, so cross-clobbering breaks
   whichever side loses the install-order race.
3. **No `TCL_LIBRARY` export** -- expect spawns child processes for a living
   and the variable would leak into every spawned Tcl program (including the
   bundled Tcl 9 `tclsh`), pinning them to the wrong script library.

Extension dirs (itcl, sqlite3, tdbc*, thread) are deliberately not shipped.
`build-expect.sh` verifies the staged payload with the temp prefix renamed away
so the fallback path is what actually gets exercised.

Max glibc symbol: GLIBC_2.17 -- well within EL8's 2.28 ceiling.

See `build/build-expect.sh` for the full recipe (includes the
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
  -d payload/el8.x86_64.glibc2p28/wheels/
```

`manylinux_2_28_x86_64` accepts all wheels with minimum glibc <= 2.28:
manylinux1 (2.5) -> manylinux2010 (2.12) -> manylinux2014/manylinux_2_17 -> ... -> manylinux_2_28.
It does NOT pull manylinux_2_29+ wheels (those require RHEL9/glibc 2.29+, won't run on EL8).

**Do NOT use `--platform manylinux2014_x86_64`** -- that is equivalent to manylinux_2_17 and
will miss wheels tagged manylinux_2_18 through manylinux_2_28 (e.g. numpy 2.x for cp314
ships as manylinux_2_27 minimum; `--platform manylinux2014_x86_64` won't find it).

If `pip download` fails even with `manylinux_2_28_x86_64 --only-binary :all:`, the package
has no pre-built cp314 wheel compatible with EL8 and must be built from source (see below).

### duckdb cp314 status -- resolved in 1.4.2

**Status (verified 2026-05-27):** duckdb added Python 3.14 support in **v1.4.2** (November 2025,
via duckdb/duckdb-python#116). cp314 wheels are available on PyPI for duckdb >= 1.4.2.

The standard `pip download` command works:
```bash
pip3.14 download duckdb --platform manylinux_2_28_x86_64 --python-version 3.14 \
  --only-binary :all: -d payload/el8.x86_64.glibc2p28/wheels/
```

No source build required. pygwalker's duckdb dep is not a blocker.

## Environment Modules (modules)

**Package name:** `modules`  **Kind:** `runtime`  **Version:** 5.6.1  
**Source:** https://github.com/envmodules/modules/releases/tag/v5.6.1

Pure Tcl with one compiled extension (`libtclenvmodules.so`) built against loadout
Tcl 9. Modules 5.6.1 has no Unix relocatable configure mode, so the build uses a
distinctive ASCII placeholder prefix (`/__LOADOUT_RELOC_ROOT__`) and ships the
**full upstream `make install` tree** rooted at `lib/modules/`. The installer's
generic runtime relocation step (`relocate_token` + `relocate_root` registry
fields) replaces the token with the deployed local root in every text file under
`lib/modules` and asserts zero tokens remain. Users select this install the
standard way: `source <local>/lib/modules/init/<shell>`. Do not invoke
`libexec/modulecmd.tcl` directly.

### Prerequisites (EL8)

```bash
sudo dnf install gcc-toolset-14 make autoconf
```

Build Tcl 9 first, then pass its lib dir (containing `tclConfig.sh`):

```bash
./build/build-tcl.sh --tag core-9-0-3
./build/build-modules.sh --tag v5.6.1 \
    --with-tcl /tmp/loadout-tcl-instdir-9.0.3/lib
```

The build script:
1. Downloads the release tarball from GitHub.
2. Configures under `--prefix=/__LOADOUT_RELOC_ROOT__/lib/modules` with
   `--disable-versioning`, disabled PATH/MANPATH mutation, docs/add-ons/example
   modulefiles off, the bundled Tcl 9 as `--with-tclsh` and `--with-tcl`.
3. Runs `make TCLSH=/__LOADOUT_RELOC_ROOT__/bin/tclsh` so generated text bakes
   the deployed tclsh path (the installer rewrites the token), while the
   extension still links against the build-time Tcl.
4. Asserts the relocation token appears in >= 20 text files, in zero ELF files,
   that `libtclenvmodules.so` loads under the bundled Tcl, and that the token
   is absent from the extension.
5. Packs the full `make install` tree into `modules.tar.bz2` rooted at
   `lib/modules/`: `bin/`, `etc/`, `init/{bash,csh,fish,ksh,sh,tcsh,zsh}`,
   `lib/libtclenvmodules.so`, `libexec/modulecmd.tcl`, `modulefiles/`, and
   `share/licenses/modules/COPYING.GPLv2`.

`modules` hard-depends on the loadout `tcl` package.

### Post-build

```bash
./strip-all-elf-binaries   # strips the Tcl launcher binaries; updates .strip-manifest
tests/install-modules
git add payload/el8.x86_64.glibc2p28/runtime/modules.tar.bz2 .strip-manifest \
        payload/packages.json build/build-modules.sh
git commit -m 'feat(payload): native Environment Modules 5.6.1 runtime'
```

### Shell integration

Shell integration lives in `envs/bash/global/modules-init.bash`, sourced by
`bashrc` when `LOADOUT_CFG_USE_LOADOUT_MODULES=1`. It is a thin selector that
resolves `${LOADOUT_CFG_SHARED_PREFIX:-$HOME/.local}/lib/modules/init/bash`,
unaliases `module`/`_module_raw`/`ml` (bash alias-parse rule), clears stale
`MODULESHOME`/`MODULES_CMD`, and sources the native init. It does **not** set a
default `MODULEPATH` (upstream init preserves a caller/site-selected one). This
works both in a normal home and in a split `@shared` + `@envs` deployment.

### Install

```bash
./loadout install modules
```

Extracts the full native tree under `~/.local/lib/modules/` and relocates the
build token to `~/.local`. Enable `LOADOUT_CFG_USE_LOADOUT_MODULES=1` in a
user/site bash config; on next bash start (or `exec bash`) the `module`
function becomes available via the sourced native init.

### Validate

```bash
tests/install-modules              # fresh-home: per-shell init/load/unload
tests/install-split-shared-envs    # split: bash/zsh/fish native init
tests/prebuilt-binaries-almalinux8 --full   # Tier 3: installs tcsh + csh smoke
```

---

## Tcl 9.0.3

**Build script:** `build/build-tcl.sh --tag core-9-0-3`

### Note on tag format

Tcl upstream uses tag format `core-MAJOR-MINOR-PATCH` (e.g. `core-9-0-3`).
The build script derives the version (`9.0.3`) and tarball name (`tcl9.0.3-src.tar.gz`)
from the tag automatically.

### Prerequisites

```bash
# EL8 base packages -- usually already installed
dnf install gcc make
```

No `tcl-devel` needed -- builds only the runtime (no C extension).

### Build output

- `payload/el8.x86_64.glibc2p28/bin/tclsh.bz2` -- tclsh binary (15 KB stub; thin shim that calls into libtcl9.0.so)
- `payload/el8.x86_64.glibc2p28/lib64/libtcl9.0.so.bz2` -- shared library (contains ALL of Tcl including stdlib)

**No runtime archive needed.** Tcl 9.x embeds its entire standard library (`init.tcl`, `auto.tcl`, etc.)
inside `libtcl9.0.so` via zipfs (a built-in virtual filesystem).  At startup, the shared library mounts
its embedded zip as `//zipfs:/lib/tcl/tcl_library` -- no filesystem path required.  This is a fundamental
change from Tcl 8.6 (which required a separate `lib/tcl8.6/` directory).

### Standard library self-location

Tcl 9.0 stdlib is embedded in `libtcl9.0.so`. The `tclsh` stub finds it automatically via the
shared library -- no `TCL_LIBRARY` env var needed, no separate directory to deploy.

### patchelf layout

- `tclsh`: RPATH `$ORIGIN/../lib64` (finds bundled `libtcl9.0.so`)
- `libtcl9.0.so`: RPATH `$ORIGIN`

### tclConfig.sh for downstream builds

The install dir is left at `/tmp/loadout-tcl-instdir-<version>` after build so that
`build-modules.sh` can use `tclConfig.sh` for the C extension:

```bash
./build/build-tcl.sh --tag core-9-0-3
./build/build-modules.sh --tag v5.6.1 \
    --with-tcl /tmp/loadout-tcl-instdir-9.0.3/lib
```

### glibc

Built with gcc on EL8; max glibc symbol verified at GLIBC_2.17 or lower.

### Install

```bash
./loadout install tcl
```

Installs tclsh to `~/.local/bin/`, `libtcl9.0.so` to `~/.local/lib64/`.
No separate standard library directory -- stdlib is embedded in libtcl9.0.so.

---

## ngspice 46

**Build script:** `build/build-ngspice.sh --tag ngspice-46`

ngspice releases live on SourceForge, not GitHub. The build script downloads from:
`https://sourceforge.net/projects/ngspice/files/ng-spice-rework/46/ngspice-46.tar.gz/download`

### Prerequisites

```bash
dnf install readline-devel ncurses-devel fftw-devel gcc gcc-c++ make bison flex
# gcc-toolset-14 enabled automatically if present
```

### Build flags

```
./configure --with-readline=yes --without-x \
    --enable-xspice --enable-cider --enable-predictor \
    --disable-debug CFLAGS="-O2 -pipe"
```

- `--without-x`: no X11 Athena widget plot window; batch + interactive text work on headless nodes
- `--enable-xspice`: XSPICE code models (behavioral elements like A-devices)
- `--enable-cider`: CIDER numerical device simulation
- Built with KLU sparse solver (bundled in ngspice itself, no external SuiteSparse needed)

### Build output

- `payload/el8.x86_64.glibc2p28/bin/ngspice.bz2` -- `build/ngspice/ngspice`, a
  POSIX-sh wrapper (prefix-deriving relocation shim)
- `payload/el8.x86_64.glibc2p28/bin/ngspice.bin.bz2` -- the real ELF
- `payload/el8.x86_64.glibc2p28/runtime/ngspice.tar.bz2` -- `./share/ngspice/`
  (spinit + nutmeg scripts) **and** `./lib/ngspice/` (XSPICE `*.cm` codemodels,
  OSDI `*.osdi` models)

### Relocation (do not regress this)

The ELF embeds its configure prefix as `NGSPICEDATADIR`, and the generated
`spinit` embeds absolute `codemodel <prefix>/lib/ngspice/*.cm` paths -- both
point at the vanished temp build prefix once deployed (the Environment Modules
bug class; shipped for a while unnoticed because plain analyses work with a
silently missing spinit). The packaging therefore does three things:

1. `bin/ngspice` wrapper derives the install prefix from its own path, exports
   `SPICE_LIB_DIR=<prefix>/share/ngspice` (spinit is read from
   `$SPICE_LIB_DIR/scripts/spinit`; explicit user value wins), and execs
   `bin/ngspice.bin -D loadout_cmdir=<prefix>/lib/ngspice "$@"`.
2. The build seds `spinit`: absolute codemodel paths become
   `$loadout_cmdir/<name>.cm` (ngspice control-language variable substitution,
   fed by the wrapper's `-D`), and the `if $?xspice_enabled` / `if
   $?osdi_enabled` guards gain `& $?loadout_cmdir` so a direct `ngspice.bin`
   run skips codemodel loading silently instead of erroring per line.
3. The build fails if spinit still contains the temp prefix, if
   `lib/ngspice/analog.cm` is missing, or if a staged wrapper run cannot load
   the XSPICE `gain` codemodel and produce `V(2)=2` from a one-node netlist.

`tests/prebuilt-binaries` repeats the XSPICE gain smoke against the installed
tree -- `--version` probes cannot catch a dead datadir.

### Runtime library requirements

| Library | Source | Action |
|---------|--------|--------|
| `libfftw3.so.3` | Bundled (octave) | RPATH `$ORIGIN/../lib64` picks it up |
| `libreadline.so.7` | EL8 base package | Always available |
| `libncurses.so.6` / `libtinfo.so.6` | EL8 base | Always available |
| `libgomp.so.1` | EL8 gcc package | Always available when gcc installed |
| `libstdc++.so.6` | EL8 system | Never bundle (per policy); GLIBCXX_3.4 only |
| `libgcc_s.so.1` | EL8 system | Never bundle (per policy) |

### patchelf

Binary: RPATH `$ORIGIN/../lib64` (finds bundled libfftw3.so.3 from octave bundle).

### glibc

Max symbol: `GLIBC_2.14`. Max C++ ABI: `GLIBCXX_3.4` (GCC 3.4 era base ABI). Compatible with all EL8 machines.

### Install

```bash
./loadout install ngspice
```

Installs `ngspice` to `~/.local/bin/` and scripts to `~/.local/share/ngspice/scripts/`.

---

## p7zip 16.02

**Tool:** p7zip -- Unix port of 7-Zip; standalone `7za` binary  
**Version:** 16.02 (latest stable; SourceForge project stalled here)  
**Source:** https://sourceforge.net/projects/p7zip/files/p7zip/16.02/  
**Built:** 2026-05-30

### Prerequisites

```bash
dnf install gcc gcc-c++ make
```

gcc-toolset-14 works (with GCC 14 compat patches applied by build script).

### Build

```bash
./build/build-p7zip.sh --tag 16.02
```

Three GCC 14 compat patches applied inline by the script:

1. **`makefile.machine` OPTFLAGS**: add `-Wno-narrowing` -- suppresses narrowing
   warnings from HRESULT enum constants (`E_OUTOFMEMORY`, `E_INVALIDARG`) in
   `ErrorMsg.cpp`. GCC >= 7 treats these as errors.

2. **`CPP/7zip/Archive/7z/7zUpdate.cpp:817`**: change `file.Open(ui.Name)` to
   `file.Open(us2fs(ui.Name))`. `CInFile::Open()` takes `CFSTR` (i.e., `const char*`)
   but `ui.Name` is `UString` (wchar_t-based). The implicit conversion was accepted
   by older GCC but rejected by GCC 14.

3. **`CPP/7zip/Common/FileStreams.h`**: add `SetTime`/`SetMTime` no-op stubs inside
   `#else` of `#ifdef USE_WIN_FILE`. Called unconditionally from
   `ArchiveExtractCallback.cpp` and `Update.cpp`, but only defined under
   `USE_WIN_FILE`. When building `7za`, `makefile.list` defines `UNIX_USE_WIN_FILE`
   which activates `USE_WIN_FILE`, so the real implementations are used and the stubs
   are dead code. Stubs guard the `\!USE_WIN_FILE` case (other bundle targets).

**CRITICAL:** Do NOT pass `LOCAL_FLAGS=` on the make command line -- it overrides the
definition in `CPP/7zip/Bundles/Alone/makefile.list` which sets `-DUNIX_USE_WIN_FILE`,
`-DENV_UNIX`, `-DBREAK_HANDLER`, `-DUNICODE`, etc. All extra flags go in `makefile.machine`'s `OPTFLAGS`.

### Runtime library requirements

| Library | Source | Notes |
|---------|--------|-------|
| `libpthread.so.0` | EL8 glibc | Always available |
| `libstdc++.so.6` | EL8 system | Never bundle (per policy) |
| `libm.so.6` | EL8 glibc | Always available |
| `libgcc_s.so.1` | EL8 system | Never bundle (per policy) |
| `libc.so.6` | EL8 glibc | Always available |

No RPATH needed (zero bundled libs).

### glibc

Max symbol: `GLIBC_2.14`. Compatible with all EL8 machines.

### Install

```bash
./loadout install p7zip
```

Installs `7za` to `~/.local/bin/`. No runtime archive; binary is self-contained.

---

## pdftotext (poppler 22.12.0) -- EL8 source build

**Why 22.12.0, not latest**: poppler >= 23.01.0 requires Freetype >= 2.10; EL8 ships Freetype 2.9.1. Version 22.12.0 is the latest release requiring only Freetype 2.8. When EL8 advances its Freetype, rebuild with a newer poppler tag.

### Prerequisites

```bash
source /opt/rh/gcc-toolset-14/enable
# powertools repo must be enabled for lcms2-devel + openjpeg2-devel
sudo dnf install -y cmake gcc-c++ pkg-config \
    fontconfig-devel freetype-devel libjpeg-turbo-devel libpng-devel \
    libtiff-devel zlib-devel lcms2-devel openjpeg2-devel
```

### Build

```bash
./build/build-pdftotext.sh --tag 22.12.0            # poppler-data 0.4.12 default
./build/build-pdftotext.sh --tag 22.12.0 --data-tag 0.4.12
```

Source: `https://poppler.freedesktop.org/poppler-22.12.0.tar.xz` plus
`https://poppler.freedesktop.org/poppler-data-0.4.12.tar.gz`.

### Relocation + poppler-data (do not regress this)

Unix poppler resolves poppler-data (CJK CMaps, cidToUnicode, nameToUnicode,
unicodeMap) only from the compile-time `POPPLER_DATADIR` macro -- here the
temp build prefix, dead once deployed. Without the data, PDFs using
predefined CMaps with no embedded ToUnicode silently extract garbage
(`Missing language pack for 'Adobe-Japan1' mapping`). Three pieces fix it:

1. The build seds `poppler/GlobalParams.cc` so the constructor falls back to
   `getenv("POPPLER_DATADIR")` -- every datadir use site already prefers the
   constructor value, so one line covers all lookups.
2. `bin/pdftotext` is a POSIX-sh wrapper (`build/pdftotext/pdftotext`) that
   exports `POPPLER_DATADIR=<prefix>/share/poppler` (user override wins) and
   execs `bin/pdftotext.bin`; poppler-data ships as
   `runtime/pdftotext.tar.bz2` -> `share/poppler/`.
3. The build and `tests/prebuilt-binaries` both extract a generated
   predefined-CMap PDF (`build/pdftotext/make-cjk-smoke-pdf.py`, UniJIS-UCS2-H,
   no ToUnicode) and require the hiragana back -- `-v` probes cannot catch a
   dead datadir.

### Key CMake flags

| Flag | Value | Reason |
|------|-------|--------|
| `BUILD_SHARED_LIBS` | OFF | Static libpoppler -> single self-contained binary |
| `ENABLE_UTILS` | ON | Build pdftotext and other utils |
| `ENABLE_GLIB` | OFF | No GLib/GObject bindings needed; avoids glib >= 2.88 dep |
| `ENABLE_QT5/QT6` | OFF | No Qt bindings needed |
| `ENABLE_NSS3` | OFF | No PDF encryption support; avoids NSS dep |
| `ENABLE_LIBCURL` | OFF | No remote PDF URI support; avoids libcurl and transitive SSL deps |
| `ENABLE_LIBOPENJPEG` | openjpeg2 | JPEG2000 support (bundles libopenjp2.so.7) |
| `ENABLE_CPP` | OFF | No C++ wrapper lib; only utils needed |
| `ENABLE_BOOST` | OFF | No Boost dep |

### Runtime library table

| Library | Source | On EL8 base? |
|---------|--------|--------------|
| libfreetype.so.6 | EL8 system | OK always |
| libfontconfig.so.1 | EL8 system | OK always |
| libjpeg.so.62 | EL8 system | OK always |
| libpng16.so.16 | EL8 system | OK always |
| libtiff.so.5 | EL8 system | OK almost always |
| libpthread.so.0 | EL8 system (glibc) | OK always |
| libm.so.6, libc.so.6 | EL8 system (glibc) | OK always |
| libbz2.so.1 | EL8 system | OK always |
| libz.so.1 | EL8 system | OK always |
| libexpat.so.1 | EL8 system | OK always |
| libuuid.so.1 | EL8 system | OK always |
| libjbig.so.2.1 | EL8 system (libtiff dep) | OK with libtiff |
| libgcc_s.so.1, libstdc++.so.6 | EL8 system | OK always |
| **liblcms2.so.2** | **bundled** | X powertools only |
| **libopenjp2.so.7** | **bundled** | X powertools only |

Max glibc symbol: **GLIBC_2.14** -- compatible with all EL8 machines.

### Packaging

Build script:
1. Builds libpoppler.a statically (no companion `.so` needed)
2. Builds pdftotext binary linking against static libpoppler + system shared libs
3. Bundles `liblcms2.so.2` and `libopenjp2.so.7` from the EL8 build machine
4. `strip` -> `patchelf --set-rpath '$ORIGIN/../lib64'` -> `bzip2 -kf` -> copy to `payload/el8.x86_64.glibc2p28/bin/pdftotext.bz2`
5. Companion libs stripped -> `bzip2 -kf` -> copy to `payload/el8.x86_64.glibc2p28/lib64/`
6. RPATH `$ORIGIN/../lib64` lets the binary find bundled liblcms2/libopenjp2 when installed at `~/.local/bin/`

### Install

```bash
./loadout install pdftotext
```

Installs `pdftotext` to `~/.local/bin/`, `liblcms2.so.2` and `libopenjp2.so.7` to `~/.local/lib64/`.

### Usage

```bash
pdftotext file.pdf                  # stdout, best-effort encoding
pdftotext -layout file.pdf -        # preserve column layout, stdout
pdftotext -f 3 -l 5 file.pdf -     # pages 3-5 only
pdftotext file.pdf out.txt          # write to file
```

---

## cloc 2.08 -- Count Lines of Code (Perl script, not a build)

cloc is a single self-contained Perl script -- NOT a compiled binary. EL8 ships
perl 5.26.3 (`/usr/bin/perl`), and cloc embeds the few non-core modules it needs
(Regexp::Common, Algorithm::Diff) inside the script itself, so it runs with bare
system perl and zero CPAN deps.

### Add/update

```bash
VER=2.08
curl -fsSL -o cloc \
  "https://github.com/AlDanial/cloc/releases/download/v${VER}/cloc-${VER}.pl"
/usr/bin/perl cloc --version          # sanity: prints the bare version, e.g. 2.08
bzip2 -kf cloc
cp cloc.bz2 payload/el8.x86_64.glibc2p28/bin/cloc.bz2
chmod 644 payload/el8.x86_64.glibc2p28/bin/cloc.bz2
./strip-all-elf-binaries              # records cloc.bz2 as a non-ELF payload, skips stripping
```

- Shebang is `#\!/usr/bin/env perl` -- resolves to EL8's `/usr/bin/perl` at runtime.
- No patchelf, no bundled libs, no RPATH -- it's a script. `strip-all-elf-binaries`
  decompresses, sees a non-ELF payload, records the sha in `.strip-manifest`, and
  skips it on later runs (same handling as the `vim.bz2` shell wrapper).
- packages.json: `kind: bin`, `tags: ["dev","data"]`, no `libs`.
- farm-versions: `strategy_flag(["--version"], r"([0-9]+\.[0-9]+)")` (cloc prints a
  bare two-part version). check-versions resolves latest from the GitHub homepage.

Install: `./loadout install cloc` (also swept into the full `@engineering-loadout` bundle).

---

## scc 3.7.0 -- Sloc Cloc and Code (Go static prebuilt)

scc is a Go binary; official releases are statically linked. Just download and
package -- no glibc concern, no patchelf, no libs.

```bash
curl -fsSL -o scc.tgz \
  "https://github.com/boyter/scc/releases/download/v3.7.0/scc_Linux_x86_64.tar.gz"
tar xzf scc.tgz                       # yields ./scc
file scc                              # ELF ... version 1 (SYSV) -> statically linked
bzip2 -kf scc
cp scc.bz2 payload/el8.x86_64.glibc2p28/bin/scc.bz2
chmod 644 payload/el8.x86_64.glibc2p28/bin/scc.bz2
./strip-all-elf-binaries
```

packages.json `kind: bin`, `tags: [dev,data]`, no libs.
farm-versions: `strategy_flag(["--version"], r"scc version ([0-9]+\.[0-9]+\.[0-9]+)")`.

## tokei 14.0.0 -- code counter (Rust, EL8 SOURCE build)

tokei's latest stable tag (v14.0.0) ships **no prebuilt binaries**, and v13 is an
alpha (excluded by the stable-only policy). The older v12.1.2 has an official musl
static, but to stay on the latest stable we build v14.0.0 from source on EL8 -- which
also yields a native glibc-2.28 binary. cargo (1.95) is available; crates.io is not in
the sandbox allowlist, so the build needs network outside the sandbox.

```bash
source /opt/rh/gcc-toolset-14/enable
git clone --depth 1 --branch v14.0.0 https://github.com/XAMPPRocky/tokei.git
cd tokei
cargo build --release                 # ~25s; pulls crates from crates.io
TOK=target/release/tokei
readelf -V "$TOK" | grep -oE 'GLIBC_[0-9]+\.[0-9]+' | sort -V | tail -1   # GLIBC_2.28 OK
ldd "$TOK"                             # libgcc_s, libpthread, libdl, libc -- all EL8 base
strip "$TOK"
bzip2 -kf "$TOK"
cp "$TOK.bz2" payload/el8.x86_64.glibc2p28/bin/tokei.bz2   # (copy the stripped+bz2'd file)
chmod 644 payload/el8.x86_64.glibc2p28/bin/tokei.bz2
./strip-all-elf-binaries
```

- System libs only -> no bundling, no RPATH. Max glibc 2.28 (native EL8 build).
- packages.json `kind: bin`, `tags: [dev,data]`, no libs.
- farm-versions: `strategy_flag(["--version"], r"tokei ([0-9]+\.[0-9]+\.[0-9]+)")`.
- When tokei resumes shipping prebuilts (>v14) or v14 gets binaries, a download is fine.

Install both: `./loadout install scc,tokei` (both swept into the full `@engineering-loadout` bundle).

---

## flameshot 13.3.0 -- GUI screenshot tool (Qt6->Qt5 EL8 back-port)

flameshot >=13.0 is **Qt6-only upstream**, and NO prebuilt channel ships a
glibc<=2.28 binary (fc41/42 = 2.38/2.40, deb = 2.35/2.36/2.39, **AppImage = 2.34**).
EL8 has only Qt5 5.15 (what gui_libs bundles) and no Qt6. So we back-port the
current release to Qt5 with a small, stable patch set and build natively -> glibc 2.27.

**This is a MAINTAINED FORK-PATCH.** `build-flameshot.sh` applies the patches via a
Python block that **fails loudly if any target string is missing** -- so a breaking
upstream change surfaces at build time. Re-derive on each flameshot bump.

### Build

```bash
sudo dnf install -y cmake qt5-qtbase-devel qt5-qtsvg-devel qt5-qttools-devel libxcb-devel
./build/build-flameshot.sh --tag v13.3.0
```

### The Qt6->Qt5 patch set (all stock idioms)

| File | Qt6 -> Qt5 |
|------|-----------|
| `src/CMakeLists.txt` | `qt6_{create,add}_translation` -> `qt5_...` (command names can't be `-D`-parameterized) |
| `src/config/generalconf.cpp` | `QStringDecoder/Encoder(System)` -> `QString::fromLocal8Bit / toLocal8Bit` (both versions) |
| `notifierbox.{h,cpp}`, `pinwidget.{h,cpp}` | `enterEvent(QEnterEvent*)` -> `QEvent*` (guarded `#if QT_VERSION >= 6`) |
| `draggablewidgetmaker.cpp` | `QMouseEvent::globalPosition()` -> `globalPos()` |
| `capturewidget.cpp` | `QList<QPair> << std::pair(` -> `qMakePair(` (Qt6 made `QPair`==`std::pair`) |
| `tools/text/textconfig.cpp` | `QFontDatabase::families()` (static) -> `QFontDatabase().families()` (instance) |
| `main.cpp` | `QLibraryInfo::path` -> `location`; add `#include <QDebug>` |

### CMake flags (set by the script)

`-DQT_VERSION_MAJOR=5 -DQT_DEFAULT_MAJOR_VERSION=5` (flameshot's own CMake is
parameterized by `Qt${QT_VERSION_MAJOR}`), `-DUSE_KDSINGLEAPPLICATION=OFF` (its
find_package is hardcoded `-qt6`; this only loses single-instance enforcement),
`-DUSE_WAYLAND_CLIPBOARD=OFF` (needs KF6GuiAddons, absent on EL8).

### Packaging / runtime

GUI tool, links Qt5 (Core/Gui/Widgets/Network/DBus/Svg) + X11/xcb -- **all from gui_libs**.
strip -> `patchelf --set-rpath '$ORIGIN/../lib64'` -> bzip2. `depends: ["gui_libs"]`,
non-optional, in `@gui-suite`. Needs `DISPLAY`. Max glibc GLIBC_2.27. ~2.2M bin.

Install: `./loadout install gui_libs,flameshot`

## firefox 140.11.0 -- Mozilla Firefox ESR (shanghai bundle from EL8 BaseOS RPM)

Mozilla Firefox does not get a source build -- its Rust + autoconf +
gn build chain is enormous and not in scope for this repo. Instead we
shanghai the EL8 BaseOS RPM: refresh the system install to the freshest
ESR, copy the runtime tree, and add a thin POSIX-sh launcher.

### Build

```bash
sudo dnf upgrade -y firefox
rpm -q firefox                # capture exact version, e.g. firefox-140.11.0-1.el8_10.alma.1.x86_64
./build/build-firefox.sh --tag 140.11.0
```

Script:
- Verifies `rpm -q firefox` matches `--tag` so the bundled version
  and the binaries can't drift.
- Stages `/usr/lib64/firefox/` -> `$STAGE/lib/firefox/` via `cp -a`.
- Drops a thin POSIX-sh wrapper at `$STAGE/bin/firefox` that derives
  prefix from `$0` and exec's `$prefix/lib/firefox/firefox-bin`.
- Rewrites two absolute symlinks the RPM ships:
  - `lib/firefox/dictionaries -> /usr/share/myspell` -- deleted (the
    built-in Firefox dictionaries still ship in the bundle; users
    wanting Hunspell extras install hunspell on the host).
  - `lib/firefox/browser/defaults/preferences -> /usr/lib64/firefox/defaults/preferences`
    -- replaced with a real directory containing a copy of the prefs.
    Why not a relative symlink: `strip-all-elf-binaries`'s tar
    re-creation step uses `os.walk(followlinks=False)` and silently
    drops symlinks-to-directories on rewrite, so the symlink would
    disappear from the bundled archive.
- Copies `/usr/share/applications/firefox.desktop` (best-effort).
- Wipes any stale `firefox.tar.bz2.part-*` chunks before tarring so
  strip-all-elf-binaries' chunk0-sha manifest cache doesn't block a fresh
  rewrite.
- `tar cjf` to `runtime/firefox.tar.bz2`, updates `packages.json`
  version, runs `./strip-all-elf-binaries` which strips ELFs inside
  the archive and auto-chunks the final ~136 MB output into
  `firefox.tar.bz2.part-NNN` shards (4 x ~40 MiB).

### Bundle layout

```
./bin/firefox                            # POSIX-sh launcher
./lib/firefox/                           # full /usr/lib64/firefox/ tree
    firefox-bin                          # RPATH=$ORIGIN -- finds bundled libmoz*.so
    libxul.so                            # ~150 MB, all the Mozilla code
    libmozsandbox.so, libgkcodecs.so, ...  # bundled, $ORIGIN-resolved
    omni.ja, browser/omni.ja             # packed JS/CSS/XUL frontend
    browser/extensions/langpack-*.xpi    # bundled langpacks
    browser/defaults/preferences/        # real dir (was symlink)
./share/applications/firefox.desktop     # XDG menu entry
```

### NSS / NSPR are BUNDLED (the version-`NSS_3.107`-not-found trap)

Firefox 140's `libxul.so` requires `NSS_3.107`. AlmaLinux 8.10 shipped
`nss-3.90` at GA; the symbol only appears in `nss >= 3.107`. The build
box happened to have `nss-3.112` **only because the firefox RPM pulled
it in as a dep**, so `ldd`/`--version` looked clean here -- classic
build-box masking (same trap as the octave support libs). On an
un-patched farm node firefox aborts at startup:

```
/lib64/libnss3.so: version `NSS_3.107' not found (required by .../libxul.so)
Couldn't load XPCOM.
```

`firefox --version` then silently falls through to the 115-ESR
`/usr/bin/firefox`, which *looks* like "the bundle didn't update."

Fix = carry the full NSS runtime closure (13 `.so`) inside the bundle
and force the loader to prefer it:

- 7 NEEDED: `libnss3 libnssutil3 libsmime3 libssl3 libnspr4 libplc4 libplds4`
- 6 dlopen plugins: `libsoftokn3 libfreebl3 libfreeblpriv3 libnssdbm3 libnssckbi libnsssysinit`

The build script copies these from `/usr/lib64/` into `lib/firefox/`,
`strip`s then `patchelf --set-rpath '$ORIGIN'` each (strip-before-
patchelf per the ELF rule; the strip-script's `elf_has_rpath` guard
then skips them).

**RPATH alone is not enough.** The EL8 RPM's `firefox-bin` and
`libxul.so` have **no RPATH/RUNPATH** -- firefox-bin dlopens libxul by
absolute path, but libxul's NEEDED libs (nss, libmoz*) get resolved by
the loader with no app-dir on the search path. So the wrapper must
`export LD_LIBRARY_PATH="$libdir:$LD_LIBRARY_PATH"` (mirrors the stock
`/usr/bin/firefox` launcher). Verify after a build with:

```bash
env -i PATH=/usr/bin:/bin LD_DEBUG=libs <stage>/bin/firefox --version 2>&1 \
  | grep 'libnss3.so' | grep 'calling init'
# must print the BUNDLE path, not /lib64
```

### Runtime libs still assumed present on EL8 (NOT bundled)

- glibc + libstdc++ + libgcc_s -- policy
- `libsqlite3.so.0` -- softokn3 dep; EL8 base sqlite (3.26), identical on
  build + dest, never security-bumped, so safe to leave external
- `libtasn1.so.6` -- nssckbi dep; EL8 base, stable
- libasound2 -- alsa-lib, present on every EL8 desktop/farm node
- libfreetype, libfontconfig -- already declared in gui_libs anyway

`depends: ["gui_libs"]` pulls in the GTK3 / cairo / pango / X11 /
Wayland stack libxul.so dlopens at runtime.

### Packaging / runtime

`kind: bin`, empty `bins` (launcher is inside the archive),
`archive: payload/PLATFORM/runtime/firefox.tar.bz2`, `depends:
["gui_libs"]`. In both `@gui-suite` (explicit member) and
`@engineering-loadout` (via the `all` synthetic group). Installer
function: `install_firefox_runtime()` in `loadout_main.py`. Needs
`DISPLAY` or `WAYLAND_DISPLAY` for the GUI; `--headless` works too.

The Fedora-shipped `/usr/bin/firefox` launcher is intentionally **not**
carried forward. It hardcodes `/etc/gre.d/gre64.conf`, `/etc/fonts`,
`/etc/firefox` langpack management, and SELinux `restorecon` paths
that don't apply to a relocatable `$HOME` install. firefox-bin
handles its own Wayland/X11 detection (`WAYLAND_DISPLAY` /
`XDG_SESSION_TYPE` env).

Install: `./loadout install gui_libs,firefox` (or just `firefox` --
gui_libs is auto-pulled via depends).

### Updating

```bash
sudo dnf upgrade -y firefox
rpm -q firefox
./build/build-firefox.sh --tag <new-version>
git add payload/el8.x86_64.glibc2p28/runtime/firefox.tar.bz2.part-* \
        .strip-manifest payload/packages.json
git commit -m 'feat(payload): firefox <version> shanghai bundle'
```

The shanghai approach means the bundle is only as fresh as the EL8
RPM. AlmaLinux tracks Firefox ESR closely -- typically only a few
days behind upstream ESR. No special action needed beyond
`dnf upgrade`.

## fio 3.42 -- Flexible I/O tester (storage/filesystem benchmark, EL8 SOURCE build)

fio measures storage and filesystem performance (random/sequential
read/write, IOPS, bandwidth, latency) across many ioengines.

Build script: `build/build-fio.sh --tag fio-3.42`.

### Prerequisites

```bash
sudo dnf install -y libaio-devel zlib-devel    # headers for the two linked libs
. /opt/rh/gcc-toolset-14/enable
```

### Configure flags (the real ones)

```bash
./configure --disable-native --disable-http
```

- `--disable-native` -- no `-march=native`; the binary must run on every
  farm CPU generation, not just the build box.
- `--disable-http` -- **critical.** With curl-devel present, configure
  auto-enables the `http` ioengine and links `libcurl.so.4`, dragging in
  the entire `libssl/libcrypto/libnghttp2/libidn2/libssh/libpsl/krb5/ldap/
  brotli/sasl` closure (~25 extra NEEDED libs) -- heavy, not guaranteed on
  a minimal node, and useless for a filesystem benchmark. Disabling it
  cuts the closure down to libaio + zlib + glibc.

zlib and libaio are auto-detected (both `-devel` installed) and kept --
libaio is the realistic async-I/O engine; zlib is iolog compression.

### Linked libs

After `--disable-http`, `ldd fio` (non-glibc only):

| lib | source | handling |
|-----|--------|----------|
| `libaio.so.1` | EL8 `libaio` RPM (`/usr/lib64/libaio.so.1`) | **bundled** -> `lib64/libaio.so.1.bz2`, soname `libaio.so.1`, RPATH `$ORIGIN` |
| `libz.so.1` | already bundled in `lib64/` | reused (declared in fio's `libs`) |

Everything else (`librt`, `libpthread`, `libm`, `libmvec`, `libdl`,
`libc`) is glibc 2.28 -- present on every EL8 target, never bundled.

> **Self-contained check (octave lesson):** the build box has
> `libaio.so.1` in system `/lib64`, so a naive `ldd` on the build box
> masks a missing RPATH. Always verify against an isolated tree:
> decompress `bin/fio` + `lib64/{libaio,libz}.so.1` into
> `/tmp/x/local/{bin,lib64}` and confirm `ldd` resolves both libs to the
> bundle path, not `/lib64`.

### Packaging

The build script does strip -> patchelf -> bzip2 for both fio and libaio,
then you run the strip normalizer (skips both via the RPATH guard):

```bash
./build/build-fio.sh --tag fio-3.42
./strip-all-elf-binaries
git add payload/el8.x86_64.glibc2p28/bin/fio.bz2 \
        payload/el8.x86_64.glibc2p28/lib64/libaio.so.1.bz2 \
        .strip-manifest payload/packages.json \
        build/build-fio.sh \
        build/farm-versions \
        build/ADDING_BINARIES.md
git commit -m 'feat(payload): fio 3.42 storage/filesystem benchmark'
```

### Install / usage

```bash
./loadout install fio
fio --name=test --ioengine=libaio --rw=randread --size=1g --filename=./tf
```

`fio` is in `@engineering-loadout` automatically (the synthetic `all`
expansion covers every non-group package).

---

## numr 0.5.5 -- text calculator with vim-style TUI (Rust, EL8 SOURCE build)

numr is a cargo workspace (`crates/numr-{core,cli,editor,tui}`). The headline
command is the TUI binary `numr`, built from `crates/numr-tui`. It ships no
official EL8 prebuilt (Homebrew/AUR/`cargo install` only), so we build from the
latest stable tag on EL8, which also yields a native glibc-2.28 binary. cargo
(1.95) is available; crates.io is not in the sandbox allowlist, so the build
needs network outside the sandbox.

The whole thing is one self-contained binary -- **no runtime data files**, so
unlike fish there is no runtime tarball.

**TLS/openssl trap (avoided):** numr-tui pulls numr-core with the `fetch`
feature for live currency rates. `fetch` uses reqwest, which would normally drag
in openssl (-> `libssl`/`libcrypto` NEEDED, neither bundled). But the workspace
manifest pins `reqwest = { default-features = false, features = ["json",
"rustls-tls"] }`, so TLS is pure-Rust rustls and the binary has **no openssl
NEEDED entry**. Confirmed below. Live rates simply no-op offline; all other math
(units, variables, static conversions) needs no network.

```bash
build/build-numr.sh --tag v0.5.5
```

What the script does (run from any cwd):

```bash
source /opt/rh/gcc-toolset-14/enable
git clone --filter=blob:none https://github.com/nasedkinpv/numr.git
cd numr && git checkout v0.5.5
cargo build --release -p numr-tui          # produces target/release/numr
N=target/release/numr
readelf -V "$N" | grep -oE 'GLIBC_[0-9]+\.[0-9]+' | sort -V | tail -1   # GLIBC_2.28 OK
readelf -d "$N" | grep NEEDED              # libgcc_s, libpthread, libm, libdl, libc -- all EL8 base
strip "$N"
patchelf --set-rpath '$ORIGIN/../lib64:$ORIGIN/../lib' "$N"
bzip2 -kf "$N"
cp "$N.bz2" payload/el8.x86_64.glibc2p28/bin/numr.bz2
chmod 644 payload/el8.x86_64.glibc2p28/bin/numr.bz2
./strip-all-elf-binaries
```

- System libs only (glibc + libgcc_s) -> no bundling. RPATH set anyway, harmless.
- `numr --version` prints `numr-tui 0.5.5` (the package name, not `numr`) --
  farm-versions regex must allow the suffix: `r"numr(?:-tui)? ([0-9]+\.[0-9]+\.[0-9]+)"`.
- packages.json `kind: bin`, `tags: [tui,math]`, no libs; member of `@core-cli`.
- The TUI opens when run with no FILE arg; `numr <file>` opens/persists a sheet.

Install: `./loadout install numr` (also pulled by `@core-cli` and the full
`@engineering-loadout` bundle).

---

## shellcheck 0.11.0 -- shell-script static-analysis linter (static prebuilt)

shellcheck is a Haskell binary; building the GHC toolchain on EL8 is a sprawl,
but upstream ships a **fully static** linux.x86_64 release (no `ld-linux`, no
glibc syms -- `ldd` says "not a dynamic executable"). So download and package --
no glibc concern, no patchelf, no libs. The asset is already `strip`ped.

```bash
curl -fsSL -o sc.tar.xz \
  "https://github.com/koalaman/shellcheck/releases/download/v0.11.0/shellcheck-v0.11.0.linux.x86_64.tar.xz"
tar xf sc.tar.xz                                  # yields ./shellcheck-v0.11.0/shellcheck
file shellcheck-v0.11.0/shellcheck                # ELF ... statically linked, stripped
ldd  shellcheck-v0.11.0/shellcheck                # "not a dynamic executable"
bzip2 -kf shellcheck-v0.11.0/shellcheck
cp shellcheck-v0.11.0/shellcheck.bz2 payload/el8.x86_64.glibc2p28/bin/shellcheck.bz2
chmod 644 payload/el8.x86_64.glibc2p28/bin/shellcheck.bz2
./strip-all-elf-binaries
```

- packages.json `kind: bin`, `tags: [shell,lint]`, no libs; member of `@dev-tools`
  (next to its formatter sibling `shfmt`).
- `shellcheck --version` prints `version: 0.11.0` -> farm-versions strategy
  `r"version:\s*([0-9]+\.[0-9]+\.[0-9]+)"`.
- The `.tar.gz` and `.tar.xz` assets carry the same binary; `.tar.xz` is smaller.

Install: `./loadout install shellcheck` (also pulled by `@dev-tools` and the full
`@engineering-loadout` bundle).

---

## amux 0.0.19 -- TUI for orchestrating parallel coding agents (Go static prebuilt)

amux is a Go binary (goreleaser); the official `linux_amd64` release tarball is
statically linked (`ldd` says "not a dynamic executable", no glibc syms). So it
is a plain download-and-bzip2 -- no glibc concern, no patchelf, no libs. The
`go1.26` toolchain is available if a source build is ever needed
(`go install github.com/andyrewlee/amux/cmd/amux@vX.Y.Z`), but the prebuilt is
preferred.

```bash
curl -fsSL -o amux.tgz \
  "https://github.com/andyrewlee/amux/releases/download/v0.0.19/amux_0.0.19_linux_amd64.tar.gz"
tar xzf amux.tgz                                  # yields ./amux + LICENSE + README.md
file amux                                         # ELF ... statically linked, stripped
ldd  amux                                         # "not a dynamic executable"
bzip2 -kf amux
cp amux.bz2 payload/el8.x86_64.glibc2p28/bin/amux.bz2
chmod 644 payload/el8.x86_64.glibc2p28/bin/amux.bz2
./strip-all-elf-binaries
```

- packages.json `kind: bin`, `tags: [agent,tui,dev]`, member of `@dev-tools`.
  `depends: [tmux]` -- amux drives each agent in its own tmux session (needs
  tmux >= 3.2, which the bundled `tmux` provides).
- `amux --version` prints `amux 0.0.19 (commit: ...)` -> farm-versions strategy
  `r"amux ([0-9]+\.[0-9]+\.[0-9]+)"`.
- Runtime: also shells out to coding-agent CLIs (claude/codex/etc.) -- those are
  not bundled; amux works without them, just with fewer agent backends.

Install: `./loadout install amux` (pulls `tmux`; also in `@dev-tools` and the
full `@engineering-loadout` bundle).

---

## yazi 26.5.6 -- terminal file manager (Rust, musl static prebuilt)

yazi is a Rust TUI file manager. The official `x86_64-unknown-linux-musl` zip is
**static-pie** (`ldd` says "statically linked", no glibc syms), so it runs on EL8
with no patchelf/libs. The zip carries TWO binaries -- `yazi` (the TUI) and `ya`
(the CLI companion: plugin/package manager, `ya emit`, `ya pub`) -- bundle both.

```bash
curl -fsSL -o yazi.zip \
  "https://github.com/sxyazi/yazi/releases/download/v26.5.6/yazi-x86_64-unknown-linux-musl.zip"
unzip -q yazi.zip                                 # -> yazi-x86_64-unknown-linux-musl/{yazi,ya,README.md,LICENSE}
D=yazi-x86_64-unknown-linux-musl
file "$D/yazi"; ldd "$D/yazi"                      # static-pie, "statically linked"
for b in yazi ya; do
    bzip2 -kf "$D/$b"
    cp "$D/$b.bz2" "payload/el8.x86_64.glibc2p28/bin/$b.bz2"
    chmod 644 "payload/el8.x86_64.glibc2p28/bin/$b.bz2"
done
./strip-all-elf-binaries
```

- packages.json `kind: bin`, `bins: [yazi, ya]`, `tags: [nav,tui,file]`, member of
  `@core-cli`. `recommends: [fd, rg, fzf, zoxide]` -- yazi integrates with them for
  find/search/jump (all already bundled); none are required, previews degrade
  gracefully without optional host tools (file, ffmpegthumbnailer, poppler, etc.).
- `yazi --version` prints `Yazi 26.5.6 (...)` -> farm-versions strategy
  `r"Yazi ([0-9]+\.[0-9]+\.[0-9]+)"` (capital Y).

Install: `./loadout install yazi` (also in `@core-cli` and the full
`@engineering-loadout` bundle).

---

## glow 2.1.2 -- terminal markdown renderer (Go static prebuilt)

glow is a Go binary (charmbracelet, goreleaser); the official `Linux_x86_64`
release tarball is statically linked (`ldd` says "not a dynamic executable", no
glibc syms). Plain download-and-bzip2 -- no glibc concern, no patchelf, no libs.

```bash
curl -fsSL -o glow.tgz \
  "https://github.com/charmbracelet/glow/releases/download/v2.1.2/glow_2.1.2_Linux_x86_64.tar.gz"
tar xzf glow.tgz                                  # -> glow_2.1.2_Linux_x86_64/glow + docs
D=glow_2.1.2_Linux_x86_64
file "$D/glow"; ldd "$D/glow"                      # statically linked
bzip2 -kf "$D/glow"
cp "$D/glow.bz2" payload/el8.x86_64.glibc2p28/bin/glow.bz2
chmod 644 payload/el8.x86_64.glibc2p28/bin/glow.bz2
./strip-all-elf-binaries
```

- packages.json `kind: bin`, `tags: [markdown,viewer,tui]`, member of `@core-cli`.
- `glow --version` prints `glow version 2.1.2 (...)` -> farm-versions strategy
  `r"glow version ([0-9]+\.[0-9]+\.[0-9]+)"`.

Install: `./loadout install glow` (also in `@core-cli` and the full
`@engineering-loadout` bundle).

---

## keyb 0.8.0 -- TUI keybinding/alias cheatsheet (Go static prebuilt)

keyb is a Go binary; the official `linux-amd64` release tarball is statically
linked (`ldd` says "not a dynamic executable", no glibc syms). Plain
download-and-bzip2 -- no glibc concern, no patchelf, no libs.

```bash
curl -fsSL -o keyb.tgz \
  "https://github.com/kencx/keyb/releases/download/v0.8.0/keyb-v0.8.0-linux-amd64.tar.gz"
tar xzf keyb.tgz                                  # -> ./keyb + README/CHANGELOG/LICENSE
file keyb; ldd keyb                                # statically linked
bzip2 -kf keyb
cp keyb.bz2 payload/el8.x86_64.glibc2p28/bin/keyb.bz2
chmod 644 payload/el8.x86_64.glibc2p28/bin/keyb.bz2
./strip-all-elf-binaries
```

- packages.json `kind: bin`, `tags: [tui,reference]`, member of `@core-cli`.
- `keyb --version` prints `v0.8.0` -> farm-versions `r"v?([0-9]+\.[0-9]+\.[0-9]+)"`.

Install: `./loadout install keyb`.

---

## gocheat 0.1.1 -- interactive terminal cheatsheet (Go, EL8 SOURCE build)

gocheat is pure Go (no `import "C"`), but the **upstream prebuilt does not run on
EL8**: goreleaser builds the official `linux_amd64` tarball with cgo on a newer
host, so it is dynamically linked and needs `GLIBC_2.34` (EL8 has 2.28):

```text
gocheat: /lib64/libc.so.6: version `GLIBC_2.34' not found (required by gocheat)
```

Rebuild from the stable tag with `CGO_ENABLED=0` -> fully static, no glibc dep.
Use the build script (go1.26 + network for the module proxy, outside the sandbox):

```bash
build/build-gocheat.sh --tag v0.1.1
# CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o gocheat .  (asserts static + no glibc syms)
```

- packages.json `kind: bin`, `tags: [tui,reference]`, member of `@core-cli`.
- **Not in farm-versions:** gocheat has no `--version` flag -- any argument drops
  straight into the TUI and opens `/dev/tty` (`could not open a new TTY`), so a
  version probe would hang. Version is tracked only in packages.json.

Install: `./loadout install gocheat`.

---

## models 0.12.3 -- TUI/CLI to browse AI models + benchmarks (Rust, EL8 SOURCE build)

`models` (crate `modelsdev`, github.com/reyamira/models) is a Rust TUI/CLI for
browsing models.dev data. The ONLY official linux prebuilt is `*-linux-gnu`,
built on a modern host -- it needs **GLIBC_2.39** and aborts on EL8 (glibc 2.28):

```text
models: /lib64/libc.so.6: version `GLIBC_2.29' not found (required by models)
```

Source-build to get a native glibc-2.28 binary. The crate also defines an
internal `transform` bin -- build/ship ONLY `models` via `--bin models`.

```bash
build/build-models.sh --tag v0.12.3
# source /opt/rh/gcc-toolset-14/enable
# git clone --depth 1 --branch v0.12.3 https://github.com/reyamira/models.git
# cargo build --release --bin models      # ~90s; max GLIBC symbol 2.28
# strip; patchelf --set-rpath '$ORIGIN/../lib64:$ORIGIN/../lib'; bzip2
```

- System libs only (glibc + libgcc_s) -> no bundling. RPATH set anyway, harmless.
  The TUI fetches data from models.dev over HTTPS (reqwest/rustls -- no openssl
  NEEDED); needs network for live data, starts fine offline.
- packages.json `kind: bin`, `tags: [tui,reference,agent]`, member of `@core-cli`.
- `models --version` prints `models 0.12.3` -> farm-versions
  `r"models ([0-9]+\.[0-9]+\.[0-9]+)"`.
- NOTE: the command name `models` is generic -- watch for PATH collisions with
  other tools of the same name (this is upstream's binary name).

Install: `./loadout install models`.

## zsh 5.9 -- Z shell (EL8 SOURCE build; sandboxed-build probe traps)

zsh has no EL8-compatible official prebuilt (source tarballs only), so it is
built from the tagged release on the EL8 box:

```bash
build/build-zsh.sh --tag 5.9
```

The tag is mapped to the real ref `zsh-5.9` inside the script (a bare `5.9` is
NOT a ref -- an earlier version checked out `5.9`, silently stayed on a dev
commit, and shipped `5.8.0.1-dev`; the script now refuses any `*-dev` build).

**The non-obvious quirk -- FIVE autoconf run-tests misfire under a sandboxed /
no-controlling-tty build environment.** zsh's configure has `AC_TRY_RUN` probes
that COMPILE AND RUN small programs which fork children and poke signals /
process groups / shared-library loading. When the build runs inside a
restricted environment (sandbox, no tty, ptrace/seccomp) those probes get the
wrong answer:

**Signal probes** (set `BROKEN_*` defines):
```text
BROKEN_KILL_ESRCH       (zsh_cv_sys_killesrch=no)
BROKEN_POSIX_SIGSUSPEND (zsh_cv_sys_sigsuspend=no -- nested under killesrch=no)
BROKEN_TCSETPGRP        (zsh_cv_sys_tcsetpgrp=no)
```
`BROKEN_POSIX_SIGSUSPEND` is the killer: it swaps zsh's race-free
`sigsuspend()` child-wait (`Src/signals.c` `signal_suspend()`) for a `pause()`
fallback with a lost-wakeup race -- SIGCHLD is reaped in the handler, then zsh
calls `pause()` waiting for a SIGCHLD that already fired. Result: **every
command substitution `$(...)` and every job-wait hangs forever** (e.g.
`x=$(echo hi)` never returns; `compinit` appears to "hang" because compdump
runs a `$(typeset +fm '_*')` substitution). `strace` shows the final syscall is
`pause(`, not `sigsuspend(`.

**Dynamic-module probes** (set `dynamic=no`, silently disabling ALL
dynamically-loaded modules):
```text
zsh_cv_func_dlsym_needs_underscore=failed  (dlopen probe fails in sandbox)
zsh_cv_shared_environ=no                   (fork/exec environ probe fails)
```
When `dynamic=no`, every `link=dynamic` module (zsh/regex, zsh/pcre,
zsh/mathfunc, zsh/stat, zsh/mapfile, zsh/zprof, zsh/zpty, zsh/socket,
zsh/tcp, zsh/zftp, zsh/system, zsh/cap, zsh/clone, zsh/files, zsh/watch,
zsh/newuser, zsh/nearcolor, zsh/zselect, zsh/attr, zsh/param/private)
gets `link=no` and is never compiled. The `link=either` modules
(parameter, complist, datetime, langinfo, terminfo, zutil) fall back to
static, which works but bloats the binary and prevents `zmodload -u`.

On real EL8 (glibc 2.28) all five probes have correct answers -- they only
failed because of WHERE we built. The build script pre-seeds all five cache
vars on the `./configure` line (the `${var+:}` guard in configure skips the
run-test when the var is already set), baking in the correct target answer:

```sh
zsh_cv_sys_killesrch=yes \
zsh_cv_sys_sigsuspend=yes \
zsh_cv_sys_tcsetpgrp=yes \
zsh_cv_func_dlsym_needs_underscore=no \
zsh_cv_shared_environ=yes \
./configure ...
```

Verify after a build: `grep BROKEN_ config.h` must show all three `#undef`,
`zsh -fc 'x=$(echo hi); print $x'` must print `hi` (not hang), and
`zsh -c 'zmodload zsh/regex; [[ a =~ ^a ]]'` must succeed. If you ever build
another autoconf tool from source on a sandboxed box and it behaves as if
signals/job-control are broken or dynamic modules are missing, suspect the
same class of run-test misdetection.

Other build details:
- `--enable-pcre` (zsh/pcre module); `libpcre.so.1` is bundled (EL8 BaseOS
  package, not guaranteed on every locked-down target).
- Modules are **dynamic** (`.so` files at `lib/zsh/5.9/zsh/`); they ship in
  `runtime/zsh.tar.bz2` alongside the shell **function library** (compinit,
  add-zsh-hook, the `_*` completions at `share/zsh/5.9/functions/`). Module
  RPATH is `$ORIGIN/../../..` (finds `lib64/` deps from `lib/zsh/5.9/zsh/`).
  The binary RPATH is `$ORIGIN/../lib/zsh:$ORIGIN/../lib64:$ORIGIN/../lib`
  (finds `libzsh-5.9.so` at `lib/zsh/` + bundled lib64 deps).
- `libzsh-5.9.so` (the shared zsh core lib) ships at `lib/zsh/`; RPATH
  `$ORIGIN/../..` (finds `lib64/` deps).
- Links `libncursesw.so.6`, `libcap.so.2` (both bundled / EL8 base), `libpcre.so.1` (bundled).
- Config: `loadout install env-zsh` (depends `env-bash` for the shared layers).

## rust 1.96.0 -- Rust toolchain + offline crate store (repacked rustup stable)

Two coupled artifacts, built by `build/build-rust.sh` and
`build/build-crate-store.sh`. Both are arch/source archives,
NOT stripped/patchelf'd: `rust.tar.bz2` is in `strip-all-elf-binaries`'
`NOSTRIP_ARCHIVE_PREFIXES` (stripping rustc_driver/LLVM corrupts the compiler).

### Toolchain runtime (`payload/<platform>/runtime/rust.tar.bz2`, chunked)
- Source: the rustup-installed **stable** toolchain (`rustup default 1.96.0`).
  rustup pulls the official static.rust-lang.org binaries, so the repacked bytes
  ARE the upstream stable release -- this just trims to the compile subset.
- `build-rust.sh --tag 1.96.0` stages:
  `bin/{rustc,cargo}`, `lib/librustc_driver-*.so`, `lib/libLLVM*` (the real lib is
  `libLLVM.so.22.1-rust-<ver>` with NO trailing `.so` plus a 42-byte ld stub --
  copy every `libLLVM*`, an earlier `libLLVM-*.so` glob missed the real object),
  and the full `lib/rustlib/x86_64-unknown-linux-gnu/` (std rlibs + libstd dylib
  + rust-lld + crt objects). Drops docs/clippy/rustfmt/rust-analyzer/src.
- Relocatable as-is: rustc/cargo already carry RPATH `$ORIGIN/../lib`; rustc
  derives its sysroot from `bin/..`. The script smoke-compiles a binary from the
  staged tree (isolated PATH) before packing. ~554 MB staged -> ~171 MB bz2 ->
  5 `.part-NNN` chunks (build-rust.sh pre-splits at 40 MiB since NOSTRIP archives
  are not chunked by the strip pass; installer rejoins via `_bz2.resolve`).
- Host prerequisite at compile time: a C toolchain (`gcc`/`cc` + `ld`) -- rustc
  shells out to `cc` for the final link. The only thing the offline store can't
  remove; the AlmaLinux test image installs `gcc glibc-devel`.
- Package: `rust` (kind runtime, sentinel `bin/cargo`, install_to `~/.local`).

### Offline crate store (`rust/crate-store.tar.bz2`, chunked)
Two builders write the same archive; the **superset** is what ships.

- **Lean user store** -- `build-crate-store.sh` reads
  `build/rust-crate-list.txt` (curated top crates, offline-first:
  online/TLS/wasm crates removed -- see that file's REMOVED block), builds a seed
  manifest, `cargo generate-lockfile` for the full transitive closure, then
  `cargo local-registry --sync`. Ban guardrail (`aws-lc-sys aws-lc-rs`) FAILS the
  build if a forbidden crate re-enters (with the `cargo tree -i` path). 219 seeds
  -> 733 crates, ~106 MB bz2 / 3 chunks. Use this for a lean user-only store.

- **Superset store (SHIPPED)** -- `build-tool-crate-store.sh` unions the curated
  seed closure with **every loadout rust tool's `Cargo.lock`**
  (`build/rust-tool-locks.txt`), so a farm node can rebuild the loadout's
  own rust binaries offline. Mechanism: `cargo local-registry --sync` only
  downloads what ONE manifest+lock resolves to and prunes the rest, so it syncs
  each tool's clone into a per-tool store (exact pinned versions an offline tool
  build needs), then **unions the per-tool stores** -- copy each `.crate` once and
  union the per-crate index lines (the local-registry index is one JSON line per
  version, so this is a clean merge; re-resolving to latest would drift off the
  tools' pins). Here the ban is a WARNING, not a failure: a tool may legitimately
  pin aws-lc (uv does). **17 stores -> 2101 crates, ~301 MB bz2 / 8 chunks.**
  Covered: seeds + bat eza fd just ripgrep zoxide starship delta hyperfine stylua
  uv fish numr models liberty-tools lefdef-tools. NOT covered (lock-gen failed at
  build, fix later): `ty`, `time-plot`, `text-serdes` (uv's closure overlaps most
  of ty). Verified: `models` and `ripgrep 15.1.0` both `cargo build --offline`
  against this store on a clean AlmaLinux 8.10 (`--network none`).

- Package: `rust-crate-store` (kind data; `install_crate_store` extracts to
  `~/.local/share/cargo/registry-store`).

### Wiring + config
- `env-cargo` (custom `_install_env_cargo`) writes `~/.cargo/config.toml` with a
  `[source.crates-io] replace-with = "local-registry"` source replacement
  pointing at the installed store. Honors `LOADOUT_CFG_SHARED_PREFIX` and
  `--dest-dir` (store path tracks `_resolve_install_to`). No manual edits.
- Group `@rust` = `rust` + `rust-crate-store` + `env-cargo`. Install offline:
  `./loadout install @rust`.
- Test offline on clean AlmaLinux 8.10:
  `tests/rust-offline-almalinux8` (runs `--network none`).
  Installs to `$HOME` then `--dest-dir /tmp/loadout-alt`, `cargo build --offline`s
  a crate using anyhow/serde/serde_json/ratatui in each, then rebuilds
  `ripgrep 15.1.0` from a build-time-baked source against the bundled store.

## vcd-toggle-profiler 891a391 -- VCD signal toggle profiler (C++17, EL8 SOURCE build)

C++17 reimplementation from `github.com/smprather/vcd-toggle-profiler`. Parses a
VCD waveform, counts per-signal toggles, and writes a self-contained offline
HTML report (uPlot charts inlined). Built and packaged by
`build/build-vcd-toggle-profiler.sh`:

```bash
build/build-vcd-toggle-profiler.sh --rev main
# or from an existing checkout:
build/build-vcd-toggle-profiler.sh --source /tmp/vcd-toggle-profiler
```

**Prerequisites:** `git`, EL8 system `/usr/bin/g++` (8.5), `tar`, `bzip2`. No
gcc-toolset, no CMake, no devel packages -- the source is a single translation
unit plus header-only CLI11.

**Why a plain `g++` build, not upstream CMake Release.** Upstream's CMake Release
profile enables `-march=native -mtune=native`, which bakes in the build box's CPU
features and would SIGILL on older farm CPUs. The script compiles one TU with
EL8 base GCC 8 so the artifact stays portable AND the libstdc++ symbol floor
stays at `GLIBCXX_3.4.21` (GCC 8's max) -- no newer-than-EL8 C++ ABI symbol can
sneak in:

```bash
/usr/bin/g++ -std=c++17 -O2 -DNDEBUG -Wall -Wextra \
    -I"$src/third_party/CLI11/include" \
    "$src/src/main.cpp" \
    -lstdc++fs \
    -o vcd-toggle-profiler.bin
```

`-lstdc++fs` is required: GCC 8 keeps `std::filesystem` in the separate
`libstdc++fs` archive (it folded into `libstdc++` only in GCC 9+).

**Why a runtime archive, not a bare `bin/*.bz2`.** Report generation needs the
uPlot JS/CSS at runtime, so the package ships them alongside the ELF and uses a
wrapper. Archive layout (`runtime/vcd-toggle-profiler.tar.bz2`):

```text
bin/vcd-toggle-profiler                          POSIX-sh wrapper
lib/vcd-toggle-profiler/vcd-toggle-profiler.bin  real C++ ELF
share/vcd-toggle-profiler/uplot/uPlot.iife.js    runtime HTML assets
share/vcd-toggle-profiler/uplot/uPlot.min.css
share/licenses/vcd-toggle-profiler/{LICENSE,LICENSE-uPlot.txt,LICENSE-CLI11.txt}
```

The wrapper derives its prefix from `bin/..`, then injects
`--uplot-js <prefix>/share/.../uPlot.iife.js` and the matching `--uplot-css`
**only if the user did not pass them**, so reports work from any cwd while
explicit overrides still win. ELF is a normal dynamic binary (links host
libstdc++/libc), no RPATH/patchelf needed.

**Packaging:** the build script tars the stage tree, stamps
`packages.json` `vcd-toggle-profiler.version` to `git describe --tags --always
--dirty`, then runs `./strip-all-elf-binaries` (rewrites/normalizes the tar.bz2
and records its size+mtime in `.strip-manifest`). Package kind `runtime`,
sentinel `bin/vcd-toggle-profiler`, install_to `~/.local`, `recommends pigz` (so
`.vcd.gz` input uses the fast bundled gzip path). Re-run
`./loadout completion bash > bash/global/completions/loadout.bash` after the
registry change.

**Verify:** `ldd lib/vcd-toggle-profiler/vcd-toggle-profiler.bin` (host libs
only), symbol-version floor `GLIBC <= 2.14` / `GLIBCXX <= 3.4.21`, and a wrapper
run against a sample VCD producing an HTML report.

---

## surfer v0.7.0 -- waveform viewer (Rust egui/glow OpenGL GUI, EL8 SOURCE build)

Surfer (`gitlab.com/surfer-project/surfer`) is a VCD/FST/GHW waveform viewer for
digital hardware debugging, written in Rust on `eframe` with the **glow**
(OpenGL) backend + winit (x11 + wayland). Upstream prebuilts target newer glibc,
so we build the latest stable tag from source on EL8 -> native glibc-2.28
binary. Packaged as a `bin`-package pair like gvim (wrapper + real ELF), `optional`
so it stays out of the full `@engineering-loadout` bundle.

```bash
build/build-surfer.sh --tag v0.7.0
./strip-all-elf-binaries
./loadout completion bash > envs/bash/global/completions/loadout.bash
```

**Prerequisites / quirks (all handled by the build script):**
- **Toolchain:** repo's bundled rust (`cargo 1.96`); surfer MSRV is 1.92. The
  f128 submodule's `__float128` shim wants a quadmath-capable C compiler, so the
  script enables `gcc-toolset-14`. glibc floor stays 2.28 regardless of gcc.
- **Submodules:** the **v0.7.0 tag** vendors `f128` and `instruction-decoder` as
  git submodules (path deps); `main` later switched them to `git =` deps. Clone
  with `--recurse-submodules` or the workspace fails to resolve `f128`.
- **Offline crate-store trap:** the loadout's own `~/.cargo/config.toml`
  (env-cargo) replaces crates-io with the offline `registry-store`, which only
  holds the curated crate subset and lacks surfer's pins (e.g. `camino 1.2.1`).
  The script sets a fresh `CARGO_HOME` so the build hits real crates.io.
- **Build:** `cargo build --release -p surfer`; release profile is `opt-level=3
  lto=true` with **no** `-march/target-cpu=native`, so the ~47 MB binary is
  farm-portable. Pulls extism/wasmtime + reqwest/rustls (plugin + online
  features) -> ~700 crates; first build is slow, LTO link dominates.

**Packaging:** strip, `patchelf --set-rpath '$ORIGIN/../lib64'` (Mesa vendor libs
sit one level up from `bin/`), then bzip2 both the stripped ELF (`surfer.bin.bz2`)
and the POSIX-sh wrapper (`surfer.bz2`) into `payload/<platform>/bin/`. The
wrapper mirrors wezterm's GL block: derive prefix from `bin/..`, prepend
`<prefix>/lib64` to `LD_LIBRARY_PATH`, set `LIBGL_DRIVERS_PATH=<prefix>/lib64/dri`
and `__EGL_VENDOR_LIBRARY_DIRS=<prefix>/share/glvnd/egl_vendor.d`, then exec
`surfer.bin`. packages.json `kind: bin`, `bins: [surfer, surfer.bin]`,
`optional: true`, `depends: [gui_libs, mesa3d_libs]`, tags `gui/opengl/waveform/eda`.

**Runtime libs:** the ELF itself NEEDs only glibc base + `libgcc_s` -- winit/glow
**dlopen** everything else at runtime (`libGL.so.1`, `libX11`, `libwayland-client`,
`libxkbcommon`, ...). X11/Wayland/xkbcommon come from `gui_libs`; the Mesa vendor
side (software `swrast`/`llvmpipe` for headless farm nodes) from `mesa3d_libs`;
the GLVND dispatcher `libGL.so.1` stays host-provided (never bundled). Install:
`./loadout install surfer` (auto-pulls gui_libs + mesa3d_libs).

**Verify:** `readelf -V surfer.bin` glibc floor `<= 2.28`, `ldd` shows host libs
only, and a real-X/WSLg `surfer --version` + a headed launch on a sample
`.vcd`/`.fst`.

---

## parity-plot 0.4.0 -- offline Plotly parity plots + NiceGUI designer

`parity-plot` is the first-party Python CLI at
`https://github.com/smprather/parity-plot`. The bundled snapshot is upstream
stable tag `v0.4.0` (`261720c64b60fbfba09826183b315ce15dd6d560`). It is a pure
wheel requiring Python 3.14. NiceGUI is a core upstream dependency now, so
`parity-plot design` is usable after an offline install without a separate extra.

### Licensing note

The v0.4.0 upstream tree currently contains no `LICENSE`/`COPYING` file or
project license metadata. Its owner authorized this first-party bundle; do not
claim a license or redistribute it on another party's behalf until upstream
adds explicit terms.

### Offline patch

Upstream currently writes HTML with `include_plotlyjs="cdn"`. That output is
tiny, but a browser on an air-gapped machine cannot render it. The loadout-only
patch `build/parity-plot/0001-inline-plotly-js-for-offline-html.patch` changes
this to `include_plotlyjs=True`, embedding Plotly from the already-installed
wheel. Keep this patch and its positive HTML smoke: it costs about 4.9 MiB per
generated report, but no extra bundled wheel bytes because Plotly contains its
own `plotly.min.js`. It also corrects upstream module metadata that still
reported version 0.1.0.

PNG/SVG/PDF are a different boundary: Kaleido needs a compatible local
Chrome/Chromium. Do **not** run `plotly_get_chrome` from the installer or add a
network fallback. The package supports static output when the host already has
a browser; it guarantees only HTML rendering entirely offline.

### Build + bundle

```bash
build/build-parity-plot.sh --tag v0.4.0            # repeat the pinned stable release
build/build-parity-plot.sh --tag vNEXT             # deliberate stable-tag update
./loadout completion bash > envs/bash/global/completions/loadout.bash
./build/gen-content-manifest
./tests/install-parity-plot
```

The builder clones/apply-checks the patch, builds the project wheel with `uv`,
exports upstream runtime dependencies, and first validates the already-vendored
lock closure for an offline rebuild. If a release tag has stale lock metadata,
the builder refreshes it only inside the disposable checkout before exporting
hash-locked requirements. A changed lock falls back to downloading its
hash-locked EL8-compatible CPython 3.14 wheels. It replaces only
old `parity_plot-*.whl` root wheels; dependency wheels are shared with other
tools and are additive. It also stamps the registry's exact source tag and
wheel list. Wheels above 40 MiB are split before commit, though this closure
does not currently need splitting.

Registry shape: non-optional `python-tool`, `uv_tool: parity-plot`,
`depends: [portable-python, uv]`; it participates in
`@shared` and `@python-tools-extra`. `tests/install-parity-plot` does a real
offline temp-tree install, generates a small self-contained HTML report, checks
the designer imports and command, then starts/probes the local designer server.
The last probe explicitly skips only where the test host prohibits loopback
socket binding; it is expected to run on a normal host/container.

## cicwave 0.5.2 -- PyQtGraph waveform viewer (Python uv_tool, loadout PyQt6 fork)

cicwave (`github.com/wulffern/cicwave`) is a pure-Python PyQtGraph waveform
viewer (ngspice `.raw` / Xyce `.prn` / VCD / CSV / parquet ...). Upstream imports
**PySide6**, which has **no wheel that is both EL8 (glibc 2.28) and Python 3.14**:

| PySide6 | python | manylinux | EL8 (glibc 2.28)? |
|---------|--------|-----------|-------------------|
| 6.9.3   | `<3.14`| 2_28      | yes, but not 3.14 |
| 6.10.0+ | 3.14 ok| **2_34**  | **no** (needs glibc 2.34 / RHEL9; `QtCore.abi3.so` floor `GLIBC_2.34`) |

6.10 added 3.14 support *and* bumped the glibc floor in the same release -- a
one-way ratchet, so "wait for PySide6" never helps EL8. **PyQt6** does satisfy
both: `PyQt6 6.9.1` is `cp39-abi3` (runs on 3.14), `PyQt6-Qt6 6.9.2` is
`manylinux_2_28` (`libQt6Core.so` floor **GLIBC_2.28**), `PyQt6-sip 13.11.1` is a
`cp314` wheel on ancient manylinux. So we carry a small fork.

### The PyQt6 port patch (`build/cicwave/0001-port-pyside6-to-pyqt6.patch`)

Touches only `wave_pg.py` + `pyproject.toml` (56 +/- lines). Upstream is shiboken
(PySide6), which tolerates unscoped enums; PyQt6 is sip, which **removed** them.
The patch is fully reproducible:

1. **Imports:** `from PySide6.* -> from PyQt6.*`, `from PySide6 import QtCore ->
   from PyQt6 import QtCore`.
2. **Signal:** `from PyQt6.QtCore import Qt, pyqtSignal as Signal, ...` (alias
   keeps the 7 `xxx = Signal(...)` class-attr definitions untouched).
3. **Strict enums (25 distinct tokens, ~58 sites):** scope every one, e.g.
   `Qt.AlignCenter -> Qt.AlignmentFlag.AlignCenter`,
   `Qt.UserRole -> Qt.ItemDataRole.UserRole`,
   `QHeaderView.Stretch -> QHeaderView.ResizeMode.Stretch`,
   `QEvent.Drop -> QEvent.Type.Drop`,
   `QFontDatabase.FixedFont -> QFontDatabase.SystemFont.FixedFont`,
   `QPalette.Text -> QPalette.ColorRole.Text`, `QDialog.Accepted ->
   QDialog.DialogCode.Accepted`, ...
4. **Two dynamic enum lookups** sed cannot see statically:
   `getattr(QPalette, role_name) -> getattr(QPalette.ColorRole, role_name)` (theme
   palette) and `_Qt.ApplicationShortcut -> _Qt.ShortcutContext.ApplicationShortcut`.
5. **pyproject dependency** `PySide6 -> PyQt6` (else the built wheel still
   declares PySide6 and `uv tool install` cannot resolve offline).

### Build + bundle

```bash
build/build-cicwave.sh --tag 0.5.2
./loadout completion bash > envs/bash/global/completions/loadout.bash
```

The script clones the **stable tag**, applies the patch, `uv build`s the wheel
into `wheels/`, downloads the PyQt6 + matplotlib dependency closure as EL8/cp314
wheels, and `split`s any wheel over 40 MiB into `.whl.part-NNN`
(`pyqt6_qt6` is ~79 MB -> 2 parts; the installer's `_prepare_wheels_dir` rejoins
them before `uv tool install`, same as the polars/pyarrow wheels).
numpy/pandas/click/pyyaml/packaging/python_dateutil/six are **reused** from the
existing bundle, not re-fetched. packages.json: `kind: python-tool`,
`uv_tool: cicwave`, `optional: true`, `depends: [portable-python, uv]`.

### Verify (headless)

The GUI can't open in CI, but `QT_QPA_PLATFORM=offscreen` constructs real Qt
widgets, so the enum/API port is exercised by rendering to a file (Qt offscreen
has no GL, so force the raster path with `CICSIM_USE_OPENGL=0`):

```bash
./loadout install cicwave --dest-dir /tmp/t --no-backup   # offline, rejoins + uv tool install
QT_QPA_PLATFORM=offscreen /tmp/t/local/bin/cicwave --help
# construct window + plot waves + matplotlib export (exercises pen-style/palette enums):
QT_QPA_PLATFORM=offscreen CICSIM_USE_OPENGL=0 <tool-venv>/bin/python -c \
  "from cicwave.wave_pg import CmdWavePg; c=CmdWavePg('time'); c.openFile('s.csv'); \
   c.win._plot_all_visible_waves(); c.exportAndExit('out.png')"
```

Interactive-only paths (drag/drop `QEvent.Type.*`, context menus, keyboard
modifiers) are statically scoped but not headlessly exercised -- smoke them on a
real X/WSLg display after a version bump. **Updating:** re-run
`build-cicwave.sh --tag <new>`; if upstream restructures `wave_pg.py` the patch
may need refreshing (`git apply --reject`, fix `.rej`, regenerate). When PySide6
ships a manylinux_2_28 + python>=3.14 wheel (unlikely; the floor only rises), the
fork could be dropped for a stock PySide6 uv_tool.

## openssh 10.4p1 -- OpenSSH signer tools + ssh10 client (EL8 SOURCE build; enables `git tag -s`)

**Why it exists:** git SSH commit/tag signing shells out to `ssh-keygen -Y sign`,
added in OpenSSH **8.2**. Stock EL8 ships **8.0p1**, whose `ssh-keygen` has no
`-Y` subcommand, so `git tag -s` dies with `unknown option -- Y` and a usage
dump. Bundling modern signer tools gives every node a working `ssh-keygen`.
The package also exposes an explicit `ssh10` client for hosts like GitHub, but
normal `ssh` stays the system `/usr/bin/ssh`. This is the tool that makes
`./release` produce a signed tag on EL8 -- see docs/SECURITY.md section 6.

```bash
build/build-openssh.sh --tag V_10_4_P1
```

Tag form is the openssh-portable git tag `V_<maj>_<min>_P<n>`; the script maps
it to the release string `10.4p1` for the registry version and a banner check
(refuses anything whose built `ssh -V` is not `OpenSSH_10.4p1`, and refuses a
`ssh-keygen` with no `-Y`).

**Prereqs (EL8):** `gcc make autoconf automake openssl-devel zlib-devel`
(gcc-toolset-14 optional). The GitHub source tree has no generated `./configure`
(unlike the openbsd.org tarball), so the script runs `autoreconf` first.

**Build shape:**
- Client-only: `make ssh ssh-keygen ssh-add ssh-agent ssh-keyscan` --
  **sshd, scp, and sftp are deliberately not built or shipped.**
- The built `ssh` is packaged as `ssh10.bin`; `ssh10` is a shell wrapper that
  passes `-F ~/.ssh/config` when present, otherwise `-F /dev/null`. A caller's
  explicit `-F` is honored unchanged.
- No bare `ssh` is shipped. Mainline OpenSSH does not understand Red Hat's
  `GSSAPIKexAlgorithms` crypto-policy directive, so a PATH-visible loadout
  `ssh` breaks RHEL hosts that stock `/usr/bin/ssh` handles correctly.
- `--with-ssl-dir=/usr` links the system OpenSSL. No RPATH gymnastics are
  needed: the binaries NEED only glibc 2.28, `libcrypto.so.1.1` (openssl-libs),
  and `libz.so.1` -- all present on every EL8 host and **never bundled** (per
  the glibc/openssl never-bundle policy). So `openssh` declares **no depends**.
- Each binary goes through `loadout_package_bin` (strip -> patchelf RPATH
  `$ORIGIN/../lib64:$ORIGIN/../lib` -> bzip2 -> `payload/<platform>/bin/`).

**Non-obvious quirks:**
- `build-box masking`: the maintainer's own signer came from this same build.
  The dev box only had a working `ssh-keygen -Y sign` after this package existed;
  before it, `./release` could not sign on EL8 at all. If you ever build on a
  truly stock EL8 with only 8.0p1, `git tag -s` fails until `~/.local/bin/ssh-keygen`
  (this package) is on PATH ahead of `/usr/bin`.
- **Passphrase-protected keys**: `ssh-keygen -Y sign` needs the private key
  unlocked. On a headless box with no `$DISPLAY`, it tries `gnome-ssh-askpass`
  and fails. Load the key into an `ssh-agent` first (`ssh-add`), then signing
  is non-interactive.
- **`optional: true`**: the signer is opt-in, but even `@shared-all` is safe:
  the package owns `ssh10`, `ssh10.bin`, `ssh-keygen`, `ssh-add`, `ssh-agent`,
  and `ssh-keyscan`, not bare `ssh`/`scp`/`sftp`. Reinstall removes old
  loadout-owned bare clients by hash so system SSH wins again.

**Updating:** re-run `build-openssh.sh --tag V_<new>`; the version stamp and
banner check derive from the tag. Then `./strip-all-elf-binaries` (the script
already calls it) and regenerate the bash completion.

## st 0.9.3 -- suckless terminal (EL8 SOURCE build; undercurl + runtime-config patch)

One source checkout produces the ELF (`st.bin`), the wrapper (`st`), the reload
helper (`st-reload`), and the `st.tar.bz2` terminfo runtime archive. Build with:

```bash
build/build-st.sh --tag 0.9.3
```

**Prerequisites (EL8):**
```bash
sudo dnf install -y gcc make pkg-config patch curl bzip2 ncurses-devel \
                   libX11-devel libXft-devel fontconfig-devel freetype-devel
. /opt/rh/gcc-toolset-14/enable
# patchelf at ~/.local/bin/patchelf (bundled in this repo)
```

Runtime deps are bundled: `libX11`, `libXft`, `libfontconfig`, `libfreetype`,
`libxcb`, `libpng16`, `libICE`, `libSM` (all via the `gui_libs` package, which
`st` depends on). System deps on EL8: `libm`, `librt`, `libutil`, `libc` only.
Never bundle glibc components.

**Upstream:** `https://dl.suckless.org/st/` (tarball) and
`https://st.suckless.org/patches/undercurl/` (undercurl patch). Stable tags
only -- never build from HEAD.

**Patch order on a fresh tree (both applied by `build-st.sh`, in this order):**

1. **Upstream undercurl patch** (`st-undercurl-0.9-20240103.diff`) plus three
   fixups `build-st.sh` performs by hand because the undercurl patch does not
   apply cleanly against st 0.9.3:
   - **fixup 1** (st.c): insert the `readcolonargs()` call after `p = np` in
     `csiparse`. st 0.9.3 added its own colon-subparam SGR handling and the
     patch hunk rejects here.
   - **fixup 2** (st.c): delete st 0.9.3's no-op `case 58:` stub so the patch's
     ucolor-applying SGR 58 case wins.
   - **fixup 3** (st.info): add `Smulx` and `Setulc` terminfo caps to the
     `st-256color` entry so nvim and other apps emit SGR 4:3 / 58:2:r:g:b
     undercurls instead of falling back to plain underline.
   - `UNDERCURL_STYLE` is forced to `UNDERCURL_CURLY` (the classic smooth-wave
     look); available alternatives in the patch are `SPIKY`, `CAPPED`.
   - A fourth, unrelated fixup silences `erresc: unknown csi / set/reset mode`
     stderr spam from modern apps probing features st does not have (mode 2026
     synchronized output, DECLRMM mode 69, etc.).

2. **`build/st/0001-runtime-xresources-config.patch`** -- the loadout
   runtime-config patch. Derived from the upstream `xresources` and
   `xresources-with-reload` patches (MIT-licensed like st), with two loadout
   deltas:
   - `config_init(Display *)` builds one `XrmDatabase` seeded from
     `RESOURCE_MANAGER`, then `XrmCombineFileDatabase()` over each
     colon-separated path in `$ST_XRESOURCES` in order (later file wins;
     missing/unreadable files skipped with `access(path, R_OK)`). Unset
     resources keep their compiled `config.h` defaults, so st with no config
     files behaves exactly as an unpatched build. This keeps per-user config
     in a plain file and works over X-forwarding with no `xrdb`.
   - `Ctrl+Shift+R` calls the same `xreload()` path as `SIGUSR1`.

   The patch must apply cleanly with `patch -p1 --forward`; `build-st.sh` fails
   loudly and points here on reject. If you bump the st tag, re-derive the
   patch against the new tree (re-apply the two upstream diffs, resolve rejects
   by hand, `git diff --cached > build/st/0001-runtime-xresources-config.patch`,
   re-add the provenance header) and re-verify the three undercurl fixups still
   apply -- see *On a tag bump* below.

**The stale `config.h` trap.** st's Makefile only copies `config.def.h` ->
`config.h` when `config.h` is **absent**, and `make clean` does **not** remove
it. A `config.h` left over from an earlier build silently drops every
`config.def.h` change (the reload shortcut, the writable `colorname[]`,
`UNDERCURL_STYLE`) and produces a plausible-looking binary that ignores its own
config. `build-st.sh` does `rm -f config.h` before building -- never remove
that line.

**Packaging (wrapper split, gvim/ngspice style):**

```
bin/st        POSIX-sh wrapper (build/st/st)        -- names the ST_XRESOURCES chain, execs bin/st.bin
bin/st.bin    the real ELF
bin/st-reload POSIX-sh helper (build/st/st-reload)  -- SIGUSR1 to running st
```

The wrapper resolves its install prefix from `$0` and builds `ST_XRESOURCES`
as the six-layer chain under `${XDG_CONFIG_HOME:-$HOME/.config}/st`
(global -> corp -> site -> team -> project -> user). A caller-set
`ST_XRESOURCES` wins untouched. It reads no shell-startup state on purpose so
`st` from a `.desktop` file, dmenu, or `ssh host st` resolves the same config
as an interactive shell.

ELF packaging order is the project-mandated **strip -> patchelf -> bzip2**
(stripping after patchelf corrupts `.dynstr` placement):

```bash
WORK="/tmp/st_work_${tag}"
cp st "$WORK"
strip "$WORK"
~/.local/bin/patchelf --set-rpath '$ORIGIN/../lib64:$ORIGIN/../lib' "$WORK"
bzip2 -kf "$WORK"
cp "${WORK}.bz2" payload/el8.x86_64.glibc2p28/bin/st.bin.bz2

# Plain POSIX-sh scripts -- no strip, no patchelf, just bzip2.
for helper in st st-reload; do
    bzip2 -kfc build/st/$helper > payload/el8.x86_64.glibc2p28/bin/${helper}.bz2
done
```

RPATH is `$ORIGIN/../lib64:$ORIGIN/../lib` so `st.bin` finds the bundled
`gui_libs` shared libs at runtime. `bin/st` and `bin/st-reload` are not ELF --
`.strip-manifest` records them as non-ELF skips.

**Terminfo archive layout.** `build-st.sh` compiles `st.info` with `tic -x`
and packs the entries under `./share/terminfo/s/`:

```bash
tic -x -o "$TI_DIR" st.info
mkdir -p "$STAGING/share/terminfo/s"
cp "$TI_DIR"/s/st* "$STAGING/share/terminfo/s/"
( cd "$STAGING" && tar -cjf "$RUNTIME_DIR/st.tar.bz2" ./share )
```

This path is load-bearing on three counts: the registry sentinel is
`share/terminfo/s/st-256color`, `install_to` is `~/.local` (so entries land at
`~/.local/share/terminfo/s/`), and `envs/bash/global/bashrc` prepends
`$HOME/.local/share/terminfo` to `TERMINFO_DIRS`. An earlier version of this
script staged `./.terminfo/s/` and tarred `./.terminfo`, which disagreed with
both the shipped archive and the sentinel -- the next tag bump would have
installed to `~/.local/.terminfo` and failed its own sentinel check. Do not
revert to `.terminfo`.

`build-st.sh` then runs `./strip-all-elf-binaries`, regenerates
`.content-manifest`, and bumps the `st` version in `packages.json`.

**Registry (`payload/packages.json`):**
```json
"st": {
  "kind": "bin",
  "bins": ["st", "st.bin", "st-reload"],
  "depends": ["gui_libs"],
  "version": "0.9.3",
  "archive": "payload/PLATFORM/runtime/st.tar.bz2",
  "sentinel": "share/terminfo/s/st-256color",
  "install_to": "~/.local",
  ...
}
"env-st": {
  "kind": "env",
  "source": "envs/st/",
  "install_to": "~/.config/st",
  ...
}
```

`st` and `env-st` are deliberately decoupled (no cross-dep): `./loadout install st`
gives you the terminal and terminfo; `./loadout install env-st` gives you the
config layer files. Install both for the runtime-config feature.

**Verify after a rebuild:**
```bash
build/verify-binaries st
DEST=$(mktemp -d /tmp/st-dest.XXXXXX)
./loadout install st env-st --dest-dir "$DEST" --no-backup
file "$DEST/local/bin/st" "$DEST/local/bin/st.bin"   # POSIX script + ELF
"$DEST/local/bin/st" -v                              # st 0.9.3
tar -tjf payload/el8.x86_64.glibc2p28/runtime/st.tar.bz2 | head -1   # ./share/...
tests/run-all                                         # st-wrapper, install-env-st, st font list in sync
```

`st` is a GUI app, so `tests/prebuilt-binaries` is an explicit host-contract
skip; the container gate proves the install behavior (wrapper chain, `env-st`
seeding, font-list sync, registry integrity) on stock EL8, not the X render
path. After a build, do the manual X smoke the container cannot:
`./loadout install st env-st`, launch `st`, edit `~/.config/st/user/st.xresources`,
run `st-reload`, and confirm the running window changes.

**On a tag bump:**

1. Re-derive the runtime-config patch against the new tree: download the two
   upstream `xresources` diffs from `https://st.suckless.org/patches/xresources/`
   (upstream renames these per release -- read the page, do not hardcode a
   filename), apply both, resolve the rejects by hand, `git diff --cached >
   build/st/0001-runtime-xresources-config.patch`, and re-prepend the
   provenance header.
2. Re-verify the three undercurl fixups (readcolonargs insertion, SGR 58 stub
   removal, `Smulx`/`Setulc` st.info caps) still apply cleanly -- st 0.9.3's
   SGR handling is what made them necessary and a future tag could shift the
   surrounding lines again.
 3. Rebuild through `build/build-st.sh --tag <new>`; confirm the
   `./share/terminfo/s/` archive layout and the sentinel; run the suite.

## git (shanghai, PRIVATE prefix -- never on PATH)

Shanghai bundle of the EL8 system git, installed to a **private prefix**
(`lib/loadout-git/`) and deliberately never linked into `bin/`. The only
consumer is nvim/lazy; the user's shell never sees it. This is the same
isolation discipline the **openssh** package uses (it ships `ssh10` and
never a bare `ssh`, so `/usr/bin/ssh` keeps winning -- see the openssh
entry above). A loadout `git` on the user's PATH would shadow the
corp-provided git and silently break its subcommands, credential helpers,
and git-lfs, which all resolve against the corp git's exec-path and config.

**Source:** the EL8 system RPM (`git-2.43.7-1.el8_10` / `git-core`) on the
build box itself -- this box IS the EL8 build machine, same shanghai
technique as meld / mate-terminal / firefox. Deps are all EL8 BaseOS
(`libpcre2-8`, `libz`, `libcrypto`/openssl 1.1, glibc) -- nothing is
bundled, per CLAUDE.md's never-bundle list. No patchelf/RPATH needed.

**Package:** `git-nvim`, `kind: runtime`, `optional: true`. Reachable via
`@shared-all` or by name; deliberately NOT in `@shared` or
`@engineering-loadout`. Archive:
`payload/el8.x86_64.glibc2p28/runtime/git.tar.bz2` (registry sets
`archive_name = "git.tar.bz2"` because the installer would otherwise
derive `<pkg>.tar.bz2` from the package name). Installs to
`lib/loadout-git/{bin,libexec,share}` under `~/.local` (or the shared tree).
**Nothing is linked into `bin/`.**

**Only consumer:** nvim. `envs/nvim/lua/global/paths.lua` `ensure_git()`
prepends `lib/loadout-git/bin` to *nvim's* `vim.env.PATH`, and only when
the system has no git at all (the user's shell is untouched).

```bash
build/build-git.sh              # bundle the system git
build/build-git.sh --check      # report what would be bundled
```

### Why a wrapper (`bin/git`)

RHEL/AlmaLinux git is built **without `RUNTIME_PREFIX`**, so the binary
hard-codes `/usr/libexec/git-core` as its exec-path. Relocated, it cannot
find its own helpers (`git-remote-https`, `git-fetch-pack`, ...) and even
`git clone` fails. `bin/git` is a POSIX-sh wrapper that derives its prefix
from its own path and exports `GIT_EXEC_PATH` (and `GIT_TEMPLATE_DIR` when
the templates are present) before exec'ing `bin/git.bin`. Explicit user
values for those env vars always win.

### The subtle one -- libexec symlinks and argv[0]

The `git-core` tree has 164 entries; **137 are symlinks to `../../bin/git`**.
In this layout that symlink target is the **wrapper**, and routing the
libexec helpers through it destroys `argv[0]` -- which is exactly how git
dispatches `git-upload-pack`, `git-receive-pack`, etc. (every helper would
run as plain `git` and `git clone` would fail). The build script repoints
those symlinks at the real ELF (`../../bin/git.bin`); invoking a symlink
preserves `argv[0]` = the link name, which is the whole dispatch mechanism.
Without this, `git clone` fails with
`git-upload-pack: ... libexec/bin/git.bin: No such file or directory`.

`cp -a` preserves the hardlinks inside `git-core` (164 entries share a few
inodes; a naive copy would balloon 14 MB into ~500 MB). `scalar` and
`git-shell` are copied because two libexec symlinks point at them.

### Bundle layout

```
./lib/loadout-git/bin/git          POSIX-sh wrapper (derives prefix, exports GIT_EXEC_PATH/GIT_TEMPLATE_DIR)
./lib/loadout-git/bin/git.bin      the real ELF (cp -a of /usr/bin/git)
./lib/loadout-git/bin/scalar       cp -a of /usr/bin/scalar (libexec symlink target)
./lib/loadout-git/bin/git-shell    cp -a of /usr/bin/git-shell (libexec symlink target)
./lib/loadout-git/libexec/git-core full /usr/libexec/git-core tree (hardlinks preserved; symlinks repointed at ../../bin/git.bin)
./lib/loadout-git/share/git-core/templates  cp -a of /usr/share/git-core/templates (only if present)
```

### Verify (these actually prove it works)

```bash
./loadout install git-nvim --dest-dir D
D/local/lib/loadout-git/bin/git --version
D/local/lib/loadout-git/bin/git clone <a local bare repo>   # proves libexec + argv[0] dispatch
test ! -e D/local/bin/git                                   # proves corp git is safe (never linked)
```

## espresso 1.1.1 -- Berkeley two-level logic minimizer (EDA)

Reduces a boolean function (PLA truth table / cover) to a minimal sum-of-products.
The classic UC Berkeley espresso, via the modernized buildable re-host
`classabbyamp/espresso-logic` (MIT + original Berkeley license; repo archived
read-only since 2021, so tags are stable).

**Tag: `v1.1.1`.** Do NOT use `2.0.0` -- despite the higher number it is a broken
mid-history "node project" experiment whose `make` fails at a prepare step; the repo
was "converted back to a plain CLI executable" in commits *after* it. `v1.1.1` is the
last good CLI tag and builds clean on modern gcc with no patches.

**Prerequisites:** `git`, `make`, `cc`, `strip`, `bzip2`. No dev packages -- pure C.

**Build:** `build/build-espresso.sh --tag v1.1.1`. It clones, `make`s
(`espresso-src/`, the Makefile uses plain `cc`), smoke-tests the fresh binary
(3-input majority must minimize to 3 product terms), then strips + bzip2s to
`bin/espresso.bz2`.

**Deps:** links `libc.so.6` ONLY, glibc floor `GLIBC_2.7` (far under EL8's 2.28).
Nothing to bundle, no patchelf, no RPATH -- the simplest possible packaging.

**Registry:** `espresso` (`kind: bin`), member of `@scientific` (so it rides in
`@engineering-loadout`), tags `eda`/`logic`/`minimizer`. Functional smoke in
`tests/prebuilt-binaries` asserts `.p 3` from the majority PLA -- a mis-built binary
could still run and mis-reduce, so `--version` is not enough.

**Verify after building:** `./strip-all-elf-binaries && build/gen-content-manifest &&
./loadout completion bash > envs/bash/global/completions/loadout.bash`, then
`./loadout install espresso --dest-dir <d>` and feed it a PLA.

## restic 0.19.1 -- user-space backup (dedup / compression / incremental)

Fast, secure backup to a repo on any filesystem: content-defined deduplication, zstd
compression, incremental snapshots, authenticated encryption. Runs fully in user space
-- no root, no FUSE/cron/dbus (the reason backintime was rejected: it is a
system-integrated Python app; restic is a single static Go binary that fits the
loadout's no-root/relocatable model).

**Tag: latest stable (v0.19.1).** BSD-2-Clause.

**Prerequisites:** `git`, `go` (>=1.24; this box has 1.26), `strip`, `bzip2`.

**Build:** `build/build-restic.sh --tag v0.19.1`. It clones, `CGO_ENABLED=0 go build`
(so the binary is fully STATIC -- links no shared libs, runs on any EL8 regardless of
glibc, nothing to bundle/patchelf), asserts the result is `statically linked`, then runs
an init -> backup -> restore -> content-match ROUNDTRIP (a backup tool that runs but
cannot restore is worthless, and `--version` can't detect that), then strips + bzip2s to
`bin/restic.bz2` (~13 MB).

**Registry:** `restic` (`kind: bin`, tags `backup`/`dedup`), a plain bin -> rides the
`@shared` sweep like rsync (no group edit). `tests/prebuilt-binaries` runs the same
roundtrip on the INSTALLED binary.

**Usage:** `restic init --repo /path/repo`; `restic -r /path/repo backup ~/work`;
`restic -r /path/repo snapshots`; `restic -r /path/repo restore latest --target DIR`.
