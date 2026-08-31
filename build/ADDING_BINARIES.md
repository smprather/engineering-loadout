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
./build/strip-all-elf-binaries
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

## Neovim build notes (currently shipping v0.12.5 stable; procedure below first recorded for a 2026-05-12 nightly)

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

## Gnuplot build notes (6.0.5; first packaged 6.0.2 on 2026-05-10)

**Build:** `build/build-gnuplot.sh --tag 6.0.5`

The script was added 2026-08-09. Until then this note was prose with no script,
so every bump meant re-deriving the configure line by hand -- the gap HANDOFF
called out for the 2026-08-03 sweep. The script encodes the flags below, asserts
the EL8 glibc floor and the dependency closure, packages BOTH artifacts, and
stamps the registry version.

**VERSION-BEARING PATH:** the runtime archive and the registry `sentinel` both
embed MAJOR.MINOR (`libexec/gnuplot/6.0/gnuplot_x11`). A 6.1 bump must move the
sentinel with it; the script prints a reminder.

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
./build/strip-all-elf-binaries          # normalizes the archive, records it in .strip-manifest
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

## Octave build notes (11.3.0; first packaged 11.1.0 on 2026-05-13)

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
- `runtime/octave.tar.bz2` -- m-files (`share/octave/11.3.0/`) + compiled plugins (`lib/octave/11.3.0/oct/`, patchelf'd RPATH = `$ORIGIN/../../../../../lib64`)

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
| Octave (optional)        | octave 11.3.0                    | ~163 MB                   |

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

**PULLED FROM THE PAYLOAD as of 2026-08-30**, same reason and same fix path as
flameshot (see that section, above `## flameshot`): nedit-ng directly needs
`libQt5Network.so.5`, which is linked against `libssl.so.1.1`/`libcrypto.so.1.1`
-- absent on Arch/CachyOS, so the binary fails to load at all, not just a
degraded feature. Re-add once `gui_libs`' `libQt5Network.so.5` is fixed (see
flameshot's note for the two paths considered) by restoring the `"nedit-ng"`
entry in `payload/packages.json` (removed 2026-08-30, see git history) and its
membership in `@editor-gui`.

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

**PULLED FROM THE PAYLOAD as of 2026-08-30**, same reason and same fix path as
flameshot (see `## flameshot`, above): nvim-qt directly needs
`libQt5Network.so.5`, which is linked against `libssl.so.1.1`/`libcrypto.so.1.1`
-- absent on Arch/CachyOS, so the binary fails to load at all. Re-add once
`gui_libs`' `libQt5Network.so.5` is fixed by restoring the `"nvim-qt"` entry
in `payload/packages.json` (removed 2026-08-30, along with
`payload/el8.x86_64.glibc2p28/runtime/nvim-qt-runtime.tar.bz2` -- see git
history) and its membership in `@editor-gui`.

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
./build/strip-all-elf-binaries   # strips the Tcl launcher binaries; updates .strip-manifest
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

## less 704

**Tool:** less -- the standard terminal file pager
**Version:** 704 (upstream RECOMMENDED release)
**Source:** http://www.greenwoodsoftware.com/less/less-704.tar.gz
**Build script:** `build/build-less.sh --tag 704`

### Why 704 and not v708

upstream's own download page says "Download RECOMMENDED version 704".
`gwsw/less` publishes ZERO GitHub releases -- the v705-v708 git tags are
DEVELOPMENT tags with no release tarball. This repo's stable-release policy
forbids dev builds, so 704 is the only acceptable version until a new tarball
appears on www.greenwoodsoftware.com.

### Why POSIX regex and not PCRE2

`--with-regex=posix` is load-bearing. PCRE2 would add `libpcre2-8.so.0` to
NEEDED, and that lib is owned by the `gui_libs` package. Coupling a core CLI
pager to the GUI bundle is wrong -- a headless compute node with no gui_libs
would lose its pager. The POSIX regex backend needs only libc, so minimal
closure wins.

### Prerequisites (EL8)

```bash
source /opt/rh/gcc-toolset-14/enable
dnf install -y gcc make ncurses-devel
# patchelf at ~/.local/bin/patchelf (bundled in this repo)
```

### Configure flags

```bash
./configure \
    --prefix=/tmp/loadout-less-instdir-704 \
    --libexecdir=/tmp/loadout-less-instdir-704/bin \
    --with-regex=posix
```

`--libexecdir=$PREFIX/bin`: upstream installs `lessecho` to libexecdir and
`less`/`lesskey` to bindir. Setting libexecdir=bindir puts all three in bin/
so they can be packaged uniformly. The compiled-in `LIBEXECDIR` macro (used by
`less` to find `lessecho` for glob expansion and `less-osc8-open` for OSC8
hyperlink clicks) then points at the temp build prefix, which is dead once
deployed. That is acceptable:
- `lessecho` is installed to `~/.local/bin/` (on PATH), and the `LESSECHO` env
  var can override the compiled-in path if glob expansion is needed. When the
  dead path fails, `filename.c` falls back gracefully (returns the original
  filename) -- it does not crash.
- `less-osc8-open` is a shell script not shipped (scope: 3 binaries). OSC8
  hyperlink clicking is opt-in via `LESS_OSC8_OPEN_ANY` env var; without it,
  links simply are not clickable -- not a crash, not a regression versus EL8's
  less 530 which predates OSC8 support.

### Packaging (strip -> patchelf -> bzip2, all three binaries)

```bash
for b in less lessecho lesskey; do
    cp $INST_DIR/bin/$b /tmp/${b}_work
    strip /tmp/${b}_work
    ~/.local/bin/patchelf --set-rpath '$ORIGIN/../lib64' /tmp/${b}_work
    bzip2 -kf /tmp/${b}_work
    cp /tmp/${b}_work.bz2 payload/el8.x86_64.glibc2p28/bin/${b}.bz2
    chmod 644 payload/el8.x86_64.glibc2p28/bin/${b}.bz2
done
```

RPATH `$ORIGIN/../lib64` (repo standard for `bin/` binaries).

### Runtime library requirements

| Library | Source | Notes |
|---------|--------|-------|
| `libtinfo.so.6` | Bundled (lib64/) | RPATH `$ORIGIN/../lib64` picks it up |
| `libc.so.6` | EL8 glibc | Never bundle (per policy) |

All three binaries (`less`, `lessecho`, `lesskey`) have the same NEEDED closure:
`libtinfo.so.6`, `libc.so.6`. No `depends` on `gui_libs` or any other package.

### glibc

Max symbol: `GLIBC_2.14`. Compatible with all EL8 machines.

### Functional verification (not --version)

The build script verifies by actually paging: pipes multi-line input through
the built `less` with `-F` (quit-if-one-screen, exits without a tty) and
asserts every input line comes back out. Also runs `lesskey -V` and `lessecho`
with real arguments. A `--version` probe proves nothing -- a mis-built less can
print its banner and fail to page.

### Install

```bash
./loadout install less
```

Installs `less`, `lessecho`, and `lesskey` to `~/.local/bin/`. No runtime
archive; all three are self-contained binaries. Member of `@core-cli`.

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

## freetype 2.14.3 -- shared font rasterizer (EL8 SOURCE build)

**`build/build-freetype.sh` is the version authority for this lib.** `gui_libs`
owns `libfreetype.so.6` and is a `lib-bundle` with an empty `version` field, and
the payload file is named for the SONAME (`libfreetype.so.6.bz2`), so the
`6.20.6` minor is not recoverable from the tree. Bump the version here when you
bump `--tag`.

### Why it stopped being a shanghai'd EL8 lib (2026-08-10)

It was EL8's system freetype 2.9.1, extracted like the other 90 `gui_libs`
members. Two reasons that changed:

- 2.9.1 is a 2018 rasterizer, and it is the shared font engine for **every** GUI
  and terminal tool in the bundle: xterm, st, urxvt, gvim, Qt5, GTK3, cairo,
  pango, `libxul.so` (firefox), Xephyr, the octave fltk plugins.
- It pinned `pdftotext` at poppler 22.12.0 (poppler >= 23.01 wants freetype
  >= 2.10), stranding three years of poppler releases.

### Prerequisites

```bash
source /opt/rh/gcc-toolset-14/enable
sudo dnf install -y gcc make pkg-config bzip2-devel zlib-devel libpng-devel
# patchelf at ~/.local/bin/patchelf (bundled in this repo)
```

### Build

```bash
./build/build-freetype.sh --tag 2.14.3
./build/build-freetype.sh --tag 2.14.3 --deep-check   # + runtime archives, ~4 min
```

Source: `https://download.savannah.gnu.org/releases/freetype/freetype-2.14.3.tar.xz`.
Build is ~9 s. The install tree is deliberately **left behind** at
`/tmp/loadout-freetype-instdir-<TAG>` (version-scoped, per the `build-octave.sh`
lesson about fixed `/tmp` prefixes accumulating versions) because EL8's own
`freetype-devel` is 2.9.1, so anything that must *compile* against the loadout
freetype needs those headers -- see `build-pdftotext.sh --with-freetype`.

### Configure flags, all load-bearing

| Flag | Reason |
|------|--------|
| `--with-harfbuzz=no` | freetype >= 2.10 wants harfbuzz >= 2.0 for the autohinter; EL8 has harfbuzz 1.7.5, and harfbuzz links freetype **back** -- a circular bundled dep. EL8's own freetype is built the same way (the 2.9.1 payload copy had no `libharfbuzz` NEEDED), so this is not a regression. Cost: autohinter loses harfbuzz script coverage for complex scripts. |
| `--with-brotli=no` | WOFF2 only, and it would add `libbrotlidec.so.1` to NEEDED -- a lib this repo does not bundle. Leaving it on is textbook build-box masking: `brotli-devel` is installed on the build box and absent from a stock farm node. |
| `--with-png/zlib/bzip2=yes` | Matches the NEEDED set of the 2.9.1 payload copy exactly; all three are already in `lib64/`. |
| `--disable-static` | Only the shared lib ships. |

### The ABI is safe; the PIXELS are the risk -- so measure them

freetype keeps SONAME `libfreetype.so.6` and stays backwards-compatible across
this span, so the failure mode to expect from a bump is **cosmetic** -- glyph
rendering shifts across every GUI app -- not link errors. `ldd` clean proves
nothing about rendering, and eyeballing GUI apps is unreliable here (WSLg
caveats: Qt goes native Wayland and Weston reparents to an unnamed frame, so
`xwininfo` is not a verification tool either).

`build/freetype/compare-rendering.c` measures it instead. Compile it **once
against the OLD headers** and run it against each lib, which also exercises
the ABI claim directly (an old-header consumer driving the new shared object
-- what every already-built payload binary does after the swap). It reports
bitmap dimensions, pixel bytes and advance **separately**, because those have
very different blast radii.

Measured for 2.9.1 -> 2.14.3, over 8 faces x 24 chars x 7 pixel sizes:

| hint mode | pixels differ | bitmap dims | **advance** |
|---|---|---|---|
| `normal` (antialiased -- what GTK/Qt/cairo use) | 1.9% | 0 | **0** |
| `light` (`hintslight`, common fontconfig default) | 4.3% | 18 | **0** |
| `autohint` (forced) | 3.2% | 6 | 31 |
| `mono` (1-bit, unused by modern toolkits) | 38.4% | 16 | **0** |

Read that as: **no metric movement in the modes real applications use.**
Every advance change is confined to forced-autohint mode *and* to the
proportional `NerdFont-*` faces -- never the `NerdFontMono-*` ones, so a
terminal's cell grid cannot shift. The 38% in `mono` is the v35 -> v40
bytecode-interpreter change and only affects 1-bit unantialiased rendering.
What is left is sub-pixel antialiasing differences on a few percent of glyphs.

**Do not sanity-check a bump with one system font.** `DejaVuSans` and
`DejaVuSansMono` were **bit-identical** across this entire jump while every
`CascadiaCode`/`CaskaydiaCove` face moved -- a DejaVu-only check would have
reported a false all-clear. Test the bundled Nerd Fonts from
`payload/fonts/*.zip`.

2.14.3 removes exactly two exported symbols relative to 2.9.1 --
`FT_Outline_New_Internal` and `FT_Outline_Done_Internal`, both deprecated
internals. **Do not take that on faith on the next bump.** The script's
symbol-closure guard collects every undefined `FT_*` symbol across `bin/` and
`lib64/` (plus the runtime archives under `--deep-check`) and fails if the new
lib does not export one of them. A dropped symbol some consumer imports is an
undefined-symbol crash at first font load on a stock farm node, long after the
release -- precisely the build-box-masking class this repo keeps hitting.
Current closure: **66 distinct `FT_*` imports** from 14 consumers (`libcairo`,
`libXfont2`, `libQt5XcbQpa`, `libQt5WaylandClient`, `libfontconfig`,
`libharfbuzz`, `libpangoft2`, `liboctinterp`, `libXft`, `pdftotext.bin`,
`libpangocairo`, `xterm`, `libxul.so`, the octave fltk `.oct` plugins).

### Packaging

`strip` -> `patchelf --set-rpath '$ORIGIN'` -> `bzip2` ->
`payload/el8.x86_64.glibc2p28/lib64/libfreetype.so.6.bz2` (356K). Note the RPATH
is bare `$ORIGIN`, not the `$ORIGIN/../lib64` a `bin/` binary gets: `lib64/`
libs resolve their siblings in the same directory.

NEEDED: `libbz2.so.1 libpng16.so.16 libz.so.1 libpthread.so.0 libc.so.6`.
Max glibc symbol **GLIBC_2.14**. The script hard-fails on any NEEDED outside
that allowlist, which is what catches an accidental harfbuzz or brotli link.

---

## pdftotext (poppler 26.04.0) -- EL8 source build

**Why 26.04.0, not latest**: the ceiling is now **fontconfig**, not freetype.
poppler's own requirements by release (grep `FREETYPE_VERSION` /
`FONTCONFIG_VERSION` in its `CMakeLists.txt`):

| poppler | freetype | fontconfig | C++ |
|---|---|---|---|
| 23.12 | 2.10 | 2.13 | 17 |
| 24.08 .. 26.04 | 2.11 | 2.13 | 20 / 23 |
| 26.06+ | 2.13 | **2.15** | 23 |

EL8 has fontconfig 2.13.1, so **26.04.0 is the last buildable release**. Going
further means source-building and bundling fontconfig too -- a bigger blast
radius than freetype was, because fontconfig 2.15 also moves the font-cache
format and would force a cache rebuild for every user.

**This needs the loadout freetype, not EL8's.** EL8's `freetype-devel` headers
are 2.9.1, so cmake configures against those and fails the `>= 2.11` check.
`--with-freetype` is mandatory for that reason, and also guards the subtler
case: if a future EL8 point release nudged the system freetype just past the
minimum, the build would silently link against a freetype that is **not** the
one shipped in `lib64/`.

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
./build/build-freetype.sh --tag 2.14.3              # prerequisite, see above
./build/build-pdftotext.sh --tag 26.04.0 \
    --with-freetype /tmp/loadout-freetype-instdir-2.14.3
./build/build-pdftotext.sh --tag 26.04.0 \
    --with-freetype /tmp/loadout-freetype-instdir-2.14.3 --data-tag 0.4.12
```

Source: `https://poppler.freedesktop.org/poppler-26.04.0.tar.xz` plus
`https://poppler.freedesktop.org/poppler-data-0.4.12.tar.gz`.

### Relocation + poppler-data (do not regress this)

Unix poppler resolves poppler-data (CJK CMaps, cidToUnicode, nameToUnicode,
unicodeMap) only from the compile-time `POPPLER_DATADIR` macro -- here the
temp build prefix, dead once deployed. Without the data, PDFs using
predefined CMaps with no embedded ToUnicode silently extract garbage
(`Missing language pack for 'Adobe-Japan1' mapping`). Three pieces fix it:

1. The build seds `poppler/GlobalParams.cc` so the constructor seeds
   `popplerDataDir` from `getenv("POPPLER_DATADIR")` when the caller passed
   nothing -- the single datadir use site already prefers the constructor
   value, so one line covers all lookups. **The constructor signature is
   version-sensitive**: it took `const char *customPopplerDataDir` through
   poppler 22.x and takes `std::string` by 26.04, so the 22.12-era sed silently
   matched nothing on the first 26.04 attempt. The script greps for the applied
   expression *and* for the injected `#include <cstdlib>` and hard-fails --
   keep both, because a pdftotext built without the patch does not crash, it
   extracts CJK as garbage, so nothing downstream would notice.
2. `bin/pdftotext` is a POSIX-sh wrapper (`build/pdftotext/pdftotext`) that
   exports `POPPLER_DATADIR=<prefix>/share/poppler` (user override wins) and
   execs `bin/pdftotext.bin`; poppler-data ships as
   `runtime/pdftotext.tar.bz2` -> `share/poppler/`.
3. The build and `tests/prebuilt-binaries` both extract a generated
   predefined-CMap PDF (`build/pdftotext/make-cjk-smoke-pdf.py`, UniJIS-UCS2-H,
   no ToUnicode) and require the hiragana back -- `-v` probes cannot catch a
   dead datadir. The build's copy stages the **patchelf'd** binary next to a
   populated `lib64/` and runs it under `env -i`, so it exercises the deployed
   `$ORIGIN/../lib64` resolution rather than whatever the build box has in
   `/usr/lib64`. That matters most for freetype: EL8's 2.9.1 is *older* than
   what this binary links against, so an unpatched staged copy would be tested
   against the wrong lib, or pass here and die on a farm node.

### Key CMake flags

| Flag | Value | Reason |
|------|-------|--------|
| `BUILD_SHARED_LIBS` | OFF | Static libpoppler -> single self-contained binary |
| `ENABLE_UTILS` | ON | Build pdftotext and other utils |
| `ENABLE_GLIB` | OFF | No GLib/GObject bindings needed; avoids glib >= 2.88 dep |
| `ENABLE_QT5/QT6` | OFF | No Qt bindings needed |
| `ENABLE_NSS3` | OFF | No PDF encryption support; avoids NSS dep |
| `ENABLE_GPGME` | OFF | Digital-signature support poppler added after 22.12; wants Gpgmepp >= 1.19, which EL8 has no package for. Configure **errors** rather than degrading, so this is mandatory, not cosmetic. |
| `ENABLE_LIBTIFF` | OFF | poppler >= 25.x wants tiff >= 4.3; EL8 has 4.0.9. TIFF only feeds `pdfimages`/`pdftoppm` output formats, which this package does not ship, so it costs nothing here. |
| `ENABLE_LIBCURL` | OFF | No remote PDF URI support; avoids libcurl and transitive SSL deps |
| `ENABLE_LIBOPENJPEG` | openjpeg2 | JPEG2000 support (bundles libopenjp2.so.7) |
| `ENABLE_CPP` | OFF | No C++ wrapper lib; only utils needed |
| `ENABLE_BOOST` | OFF | No Boost dep |
| `CMAKE_PREFIX_PATH` / `Freetype_ROOT` | `--with-freetype` | Point cmake at the loadout freetype; see above |

### Runtime library table

| Library | Source | On EL8 base? |
|---------|--------|--------------|
| **libfreetype.so.6** | **bundled** (2.14.3, source-built) | EL8's own is 2.9.1 -- too old to link against |
| libfontconfig.so.1 | EL8 system | OK always |
| libjpeg.so.62 | EL8 system | OK always |
| libpng16.so.16 | EL8 system | OK always |
| libpthread.so.0 | EL8 system (glibc) | OK always |
| libm.so.6, libc.so.6 | EL8 system (glibc) | OK always |
| libz.so.1 | EL8 system | OK always |
| libgcc_s.so.1, libstdc++.so.6 | EL8 system | OK always |
| **liblcms2.so.2** | **bundled** | X powertools only |
| **libopenjp2.so.7** | **bundled** | X powertools only |

`libtiff.so.5` and its `libjbig.so.2.1` dep dropped out of NEEDED with
`ENABLE_LIBTIFF=OFF`; `libbz2`/`libexpat`/`libuuid` are no longer direct NEEDED
either (they arrive transitively through fontconfig and the bundled freetype).

Max glibc symbol: **GLIBC_2.17** -- compatible with all EL8 machines.

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
./build/strip-all-elf-binaries              # records cloc.bz2 as a non-ELF payload, skips stripping
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
./build/strip-all-elf-binaries
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
./build/strip-all-elf-binaries
```

- System libs only -> no bundling, no RPATH. Max glibc 2.28 (native EL8 build).
- packages.json `kind: bin`, `tags: [dev,data]`, no libs.
- farm-versions: `strategy_flag(["--version"], r"tokei ([0-9]+\.[0-9]+\.[0-9]+)")`.
- When tokei resumes shipping prebuilts (>v14) or v14 gets binaries, a download is fine.

Install both: `./loadout install scc,tokei` (both swept into the full `@engineering-loadout` bundle).

---

## flameshot 13.3.0 -- GUI screenshot tool (Qt6->Qt5 EL8 back-port)

**PULLED FROM THE PAYLOAD as of 2026-08-30 -- do not re-add without fixing the
root cause first.** flameshot depends on `gui_libs`' `libQt5Network.so.5`,
which EL8's qt5-qtbase RPM builds `-openssl-linked` against system
`libssl.so.1.1`/`libcrypto.so.1.1`. EL8 always has those (openssl-libs-1.1.1);
Arch/CachyOS never does (OpenSSL 3 only, no 1.1 compat by default) -- and
because ELF loading requires *every* NEEDED entry to resolve before a process
can even start, this is not a degraded feature, it is flameshot refusing to
launch at all: `error while loading shared libraries: libssl.so.1.1`.

Attempted fix: rebuild just `libQt5Network.so.5` from the same qt5-qtbase
source+patches, linked against OpenSSL 3 (`openssl3-devel`/`openssl3-libs`
from EPEL, `OPENSSL_LIBS`/`CPATH` env vars -- Qt's own OpenSSL config test is
a hardcoded compile check, not pkg-config, so a PKG_CONFIG_PATH shim is
silently ignored for this one library specifically). That configures and
compiles, but fails at the QtNetwork *link* step:
`undefined reference to 'SSL_get_peer_certificate'`,
`undefined reference to 'EVP_PKEY_base_id'`. Qt 5.15.3 (2021-03) predates
OpenSSL 3.0 (2021-09); its `qsslsocket_openssl_symbols.cpp` resolves every
OpenSSL function by name and doesn't know OpenSSL 3 renamed these. Real fix
exists upstream (later Qt 5.15.x point releases patched the OpenSSL glue for
3.0 compat) but requires sourcing and applying those actual commits, with an
unknown number of further symbol mismatches beyond the first two the linker
reports -- open-ended enough that it was deliberately deferred rather than
attempted blind. See `build/build-qt5network-openssl3.sh` for the full
attempt and exact failure.

The cheaper alternative not yet tried: reconfigure with `-openssl-runtime`
instead of `-openssl-linked` -- QtNetwork would `dlopen()` whatever OpenSSL is
present at actual runtime (1.1 on EL8, 3.x on Arch) with no hard link-time
dependency and no patches needed, gracefully degrading if none is found. This
would fix every `gui_libs` consumer's OpenSSL story at once, not just
flameshot's, and is probably the right first thing to try before attempting
the OpenSSL-3-symbol-compat patches above.

To re-add flameshot: fix `gui_libs`' `libQt5Network.so.5` by one of the above,
then restore the `"flameshot"` entry in `payload/packages.json` (removed
2026-08-30, see git history) and its membership in `@gui-suite`.

**Not the only casualty.** `nedit-ng` and `nvim-qt` hit the identical
`libQt5Network.so.5` dependency and were pulled the same day for the same
reason -- see their own sections (`## nedit-ng build notes`, `## nvim-qt build
notes`). Fixing `libQt5Network.so.5` once restores all three.

---

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

## firefox 140.14.0 -- Mozilla Firefox ESR (shanghai bundle from EL8 BaseOS RPM)

Mozilla Firefox does not get a source build -- its Rust + autoconf +
gn build chain is enormous and not in scope for this repo. Instead we
shanghai the EL8 BaseOS/AppStream RPM: refresh the system install to
the freshest ESR, copy the runtime tree, and add a thin POSIX-sh
launcher. **No self-update:** the bundle ships no `updater` binary and
upstream's would need root + the Mozilla install layout -- updates come
from build-firefox.sh bumps only (ESR point releases hit Alma 8
AppStream within days of upstream).

### Build

```bash
sudo dnf upgrade -y firefox
rpm -q firefox                # capture exact version, e.g. firefox-140.14.0-1.el8_10.alma.1.x86_64
./build/build-firefox.sh --tag 140.14.0
```

Offline / non-EL8 host (used for the 140.14.0 bump):

```bash
# download from https://repo.almalinux.org/almalinux/8/AppStream/x86_64/os/Packages/:
#   firefox-<ver>-*.rpm  nspr-*.rpm  nss-3*.rpm  nss-util-*.rpm
#   nss-softokn-*.rpm  nss-softokn-freebl-*.rpm
./build/build-firefox.sh --tag 140.14.0 --from-rpms <dir-with-the-rpms>
```

Script:
- Verifies `rpm -q firefox` matches `--tag` so the bundled version
  and the binaries can't drift (the --from-rpms path checks the rpm
  filename NVR instead).
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
  version, runs `./build/strip-all-elf-binaries` which strips ELFs inside
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

Fix = carry the NSS runtime closure inside the bundle and force the
loader to prefer it:

- 7 NEEDED: `libnss3 libnssutil3 libsmime3 libssl3 libnspr4 libplc4 libplds4`
- 5 dlopen plugins: `libsoftokn3 libfreebl3 libfreeblpriv3 libnssdbm3`

The build script copies these from `/usr/lib64/` into `lib/firefox/`,
`strip`s then `patchelf --set-rpath '$ORIGIN'` each (strip-before-
patchelf per the ELF rule; the strip-script's `elf_has_rpath` guard
then skips them).

### The trust module must stay SYSTEM-provided (SEC_ERROR_UNKNOWN_ISSUER trap)

`libnssckbi.so` and `libnsssysinit.so` are **NOT bundled** -- on purpose,
with a build-time guard that fails the build if they reappear. This is
also what Mozilla's official Linux tarballs do (they ship no ckbi).

On EL8/Fedora, `/usr/lib64/libnssckbi.so` is an alternatives symlink to
p11-kit's **trust proxy**, which reads the system trust store from
hardcoded distro paths (`/etc/pki/ca-trust/...`). Bundling that proxy
made every HTTPS site fail with `SEC_ERROR_UNKNOWN_ISSUER` on any
non-EL8 distro (Arch-family keeps trust in `/etc/ssl/certs`; the proxy
found no roots at all). Classic build-box masking: works on EL8, zero
TLS trust anywhere else -- and it evaded the dest-dir smoke because a
`--version`/screenshot run against `data:` URLs never verifies a cert.

Without a bundled ckbi, NSS dlopens the **host's** trust module
(`libnssckbi.so` on the default loader path -- classic compiled roots,
or the host's working p11-kit proxy). Every mainstream distro provides
one; the bundle no longer cares where that host keeps its roots.

Smoke (dest-dir shape, `env -i`, on a NON-EL8 host -- this is the only
way the masking gets caught):

```bash
<dest>/local/bin/firefox --headless --profile /tmp/p \
  --screenshot /tmp/x.png https://example.com
# must render; and no "Not Secure" interstitial for a well-known CA site
```

**RPATH alone is not enough.** The EL8 RPM's `firefox-bin` and
`libxul.so` have **no RPATH/RUNPATH** -- firefox-bin dlopens libxul by
absolute path, but libxul's NEEDED libs (nss, libmoz*) get resolved by
the loader with no app-dir on the search path. So the wrapper must
`export LD_LIBRARY_PATH="$libdir:$LD_LIBRARY_PATH"` (mirrors the stock
`/usr/bin/firefox` launcher) -- and NOTHING else. Do NOT add
`$prefix/lib64` (gui_libs): on hosts newer than EL8 that shadows the
host GTK3/dbus stack with EL8-era copies and breaks theme engines /
spawned helpers (symptom: firefox "reaches outside its install space"
and misbehaves). Keep the loader path inside the bundle; bundle any
soname the host can't supply (next section). Verify after a build
with:

```bash
env -i PATH=/usr/bin:/bin LD_DEBUG=libs <stage>/bin/firefox --version 2>&1 \
  | grep 'libnss3.so' | grep 'calling init'
# must print the BUNDLE path, not /lib64
```

### libffi.so.6 + libjpeg.so.62 are BUNDLED (the soname-gap-on-newer-hosts trap)

`libxul.so` NEEDEDs `libffi.so.6` and `libjpeg.so.62` (EL8 sonames the
build links against). EL8 hosts provide both in `/lib64`, and
`gui_libs` also ships copies to `~/.local/lib64` -- so the EL8 smoke
never failed. But hosts with newer userlands have **no such sonames at
all** (Arch-family: libffi 3.4 = `.so.8` only, libjpeg-turbo 3 =
`.so.8` only), and with the loader path inside the bundle there is
nothing to resolve them:

```
XPCOMGlueLoad error for file .../lib/firefox/libxul.so:
libffi.so.6: cannot open shared object file: No such file or directory
Couldn't load XPCOM.
```

Fix = bundle the host-gap sonames **co-located** in `lib/firefox/`
with `RPATH=$ORIGIN`, same staging loop as the NSS set (14th/15th
entries: `libffi.so.6`, `libjpeg.so.62`, copied from `/usr/lib64` on
the build box). The wrapper's existing `$libdir` prepend resolves
them. Rule of thumb for adding more: bundle only sonames the TARGET
host cannot provide; everything the host has, the host copy must win
(GTK/dbus/mesa...), which is why `$prefix/lib64` must stay OFF the
wrapper's loader path.

Verify with the dest-dir shape on a host that lacks the sonames --
`env -i` so the dev shell's `LD_LIBRARY_PATH` can't mask a gap:

```bash
<dest>/local/bin/firefox --version    # must print, not XPCOMGlueLoad
```

and assert the host stack stayed authoritative:

```bash
<dest>/local/bin/firefox --headless --screenshot /tmp/x.png data:text/html,ok
ldd-with-LD_LIBRARY_PATH=<bundle>/lib/firefox <bundle>/lib/firefox/libxul.so \
  | grep libgtk-3   # must resolve to /usr/lib, not ~/.local/lib64
```

### Runtime libs still assumed present on EL8 (NOT bundled)

- glibc + libstdc++ + libgcc_s -- policy
- `libsqlite3.so.0` -- softokn3 dep; EL8 base sqlite (3.26), identical on
  build + dest, never security-bumped, so safe to leave external
- `libtasn1.so.6` -- nssckbi dep; EL8 base, stable
- libasound2 -- alsa-lib, present on every EL8 desktop/farm node
- libfontconfig -- already declared in gui_libs anyway

`libfreetype` used to be on this list. It is now **bundled and source-built**
(2.14.3, see the freetype section) and still reached through `gui_libs`, so
`libxul.so` resolves the loadout copy rather than EL8's 2.9.1.

`libffi.so.6` and `libjpeg.so.62` used to be on this list implicitly
(EL8 base + `gui_libs` lib64 twins). Both are now **bundled
co-located** -- see the soname-gap section above; `libasound2` is the
remaining same-shape entry (every EL8 host has it; on soname-gap hosts
it resolves from the host or needs the same treatment if ever
reported).

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
# or, offline / off the EL8 box:
./build/build-firefox.sh --tag <new-version> --from-rpms <rpm-dir>
git add payload/el8.x86_64.glibc2p28/runtime/firefox.tar.bz2.part-* \
        .strip-manifest payload/packages.json README.md
git commit -m 'feat(payload): firefox <version> shanghai bundle'
```

(README.md too -- the package table is Tier-1 sync-gated on the version
via `build/gen-readme-table`.)

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
./build/strip-all-elf-binaries
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
./build/strip-all-elf-binaries
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
./build/strip-all-elf-binaries
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
./build/strip-all-elf-binaries
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
./build/strip-all-elf-binaries
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
./build/strip-all-elf-binaries
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
./build/strip-all-elf-binaries
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
  pin aws-lc (uv does). **19 stores -> 2272 crates, ~320 MB bz2 / 8 chunks.**
  Covered: seeds + bat eza fd just ripgrep zoxide starship delta hyperfine stylua
  uv fish numr models liberty-tools lefdef-tools. NOT covered (lock-gen failed at
  build, fix later): `ty`, `time-plot`, `text-serdes` (uv's closure overlaps most
  of ty). Verified: `models` and `ripgrep 15.1.0` both `cargo build --offline`
  against this store on a clean AlmaLinux 8.10 (`--network none`).

- Package: `rust-crate-store` (kind data; `install_crate_store` extracts to
  `~/.local/share/cargo/registry-store`).

### Wiring + config
- `env-cargo` (custom `_install_env_cargo`) writes a STOCK `~/.cargo/config.toml`
  (no source replacement -- online-first). The offline fallback is shell-level:
  the `cargo()` wrapper in envs/bash/functions.sh (tcsh: helpers/cargo-wrap)
  injects a `replace-with` pointing at the installed store via `--config` CLI
  args, only when crates.io is unreachable AND the store exists. Store path
  honors `LOADOUT_CFG_SHARED_PREFIX` and the HOME/`--dest-dir` layouts. No
  manual edits.
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
--dirty`, then runs `./build/strip-all-elf-binaries` (rewrites/normalizes the tar.bz2
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
./build/strip-all-elf-binaries
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

## parity-plot 0.7.0 -- offline Plotly parity plots + NiceGUI designer

`parity-plot` is the first-party Python CLI at
`https://github.com/smprather/parity-plot`. The bundled snapshot is upstream
stable tag `v0.7.0`. It is a pure
wheel requiring Python 3.14. NiceGUI is a core upstream dependency now, so
`parity-plot design` is usable after an offline install without a separate extra.

### Licensing note

The v0.7.0 upstream tree currently contains no `LICENSE`/`COPYING` file or
project license metadata. Its owner authorized this first-party bundle; do not
claim a license or redistribute it on another party's behalf until upstream
adds explicit terms.

### Offline HTML behavior

There is no loadout patch anymore. Through v0.6.0 we carried a patch that
changed Plotly's CDN reference into an inlined copy, so generated HTML rendered
air-gapped. v0.7.0 adopted that behavior upstream and added
`[output].plotlyjs` control; standalone documents default to inline Plotly.
Keep the behavioral smoke instead of reintroducing a patch:
`tests/install-parity-plot` asserts generated HTML embeds the Plotly runtime and
carries no CDN reference.

PNG/SVG/PDF are a different boundary: Kaleido needs a compatible local
Chrome/Chromium. Do **not** run `plotly_get_chrome` from the installer or add a
network fallback. The package supports static output when the host already has
a browser; it guarantees only HTML rendering entirely offline.

### Build + bundle

```bash
build/build-parity-plot.sh --tag v0.7.0            # repeat the pinned stable release
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
`./build/release` produce a signed tag on EL8 -- see docs/SECURITY.md section 6.

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
  before it, `./build/release` could not sign on EL8 at all. If you ever build on a
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
banner check derive from the tag. Then `./build/strip-all-elf-binaries` (the script
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

`build-st.sh` then runs `./build/strip-all-elf-binaries`, regenerates
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
bundled, per AGENTS.md's never-bundle list. No patchelf/RPATH needed.

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

**Verify after building:** `./build/strip-all-elf-binaries && build/gen-content-manifest &&
./loadout completion bash > envs/bash/global/completions/loadout.bash`, then
`./loadout install espresso --dest-dir <d>` and feed it a PLA.

## gtkwave 3.3.116 -- VCD/FST/LXT2/VZT waveform viewer + converters (EL8 SOURCE build, GTK3)

The incumbent open-source waveform viewer. Bundled *alongside* `surfer` (modern
Rust/egui) rather than instead of it, because industrial flows invoke `gtkwave` by
name from Makefiles and regression wrappers, and because the converter suite
(`fst2vcd`, `vcd2fst`, `vcd2vzt`, `vzt2vcd`, `vcd2lxt`, `lxt2vcd`, `fstminer`,
`vztminer`, `lxt2miner`, `evcd2vcd`, `xml2stems`) is used **headless in batch** with
no relation to the GUI.

**WHICH TREE -- this repo has two.** `gtkwave3/` is the GTK2 build; `gtkwave3-gtk3/`
is the GTK3 build and is the one we build, against the GTK3 3.22 stack already in
`gui_libs`. The repo's `master` branch is the **GTK4 rewrite** (gtkwave 4.x): it has
**no stable tag** (only a `nightly` tag and an `lts` branch), and GTK4 is not
bundled, so it is out of scope under the stable-release policy. Do not "upgrade" to
it by moving to `master`.

**Tag: `v3.3.116`** (highest 3.3.x tag). Tag form is enforced -- the script rejects
anything but `v3.3.*` with the GTK4 explanation, so nobody re-derives this.

**Prerequisites:**
```
dnf install gtk3-devel glib2-devel bzip2-devel xz-devel zlib-devel gperf flex bison make gcc
```
`gperf` is a **hard configure error** even though `configure.ac` comments that it is
"only needed if the user updates the gperf data". Install it or configure dies.

**Build:** `build/build-gtkwave.sh --tag v3.3.116`. Real flags:
```
./configure --prefix=/tmp/gtkwave-install-3.3.116 \
    --enable-gtk3 --disable-tcl --disable-mime-update --disable-schemas-compile \
    CFLAGS="-O2 -pipe"
```
- `--disable-mime-update` / `--disable-schemas-compile` stop `make install` from
  touching system-wide `/usr/share/mime` and the GSettings schema cache.
- **Neither `--with-gsettings` nor `--with-gconf`.** Both default off, and that is
  what we want: preferences then live in `~/.gtkwaverc`, needing neither a compiled
  schema nor a settings daemon. Turning on gsettings would drag in the
  `glib-compile-schemas` + `GSETTINGS_BACKEND=keyfile` dance that mate-terminal needs.
- Install prefix is **version-scoped** (`/tmp/gtkwave-install-<VERSION>`) so
  successive builds cannot contaminate each other, as with octave.

**NO WRAPPER -- and that is verified, not assumed.** Unlike ngspice/gvim/st/fish,
**nothing** in the GTKWave install embeds the configure prefix: `share/gtkwave-gtk3/`
holds only the ODT manual and examples, the `.desktop` file uses a bare
`Exec=gtkwave`, and `twinwave` locates gtkwave with `execvp()` from `PATH`. So the
ELFs ship directly (strip -> `patchelf --set-rpath '$ORIGIN/../lib64'` -> bzip2) with
no launcher. The build script **enforces this as an invariant**: it greps every
installed binary and every file under `share/` for the prefix and hard-fails if any
hit appears. If that guard ever fires, GTKWave needs a prefix-deriving wrapper
(model: `build/ngspice/ngspice`) -- do not weaken the guard instead.

**Binary set is pinned, not globbed.** `EXPECTED_BINS` lists all 16; the script fails
if upstream drops one *or* installs one not on the list, so a tool-set change is a
build failure rather than a silent payload diff. Keep it in sync with the `bins`
array in `packages.json`.

**KNOWN LIMITATION -- Tcl scripting is off (`--disable-tcl`).** GTKWave's Tcl layer
(`gtkwave -S script.tcl`, the `gtkwave::` command set) links system Tcl 8.6 and then
needs a Tcl script library (`init.tcl`) at run time. The loadout already owns
`<prefix>/lib/tcl8.6` for portable-python at a *different* Tcl patchlevel, and Tcl's
`init.tcl` does `package require -exact`, so a second tcl8.6 script library in that
tree breaks one side or the other -- the exact hazard documented for `expect` above.
Enabling it later means giving GTKWave a private script-library prefix the way
`build/build-expect.sh` does. Failure mode without it is **loud**: `gtkwave -S` exits
with an unrecognized-option error; it does not silently ignore the script.

**Deps:** GTK3/cairo/pango/glib/X11/Wayland from `gui_libs`; `libbz2.so.1`,
`libz.so.1`, `libpcre.so.1` already in payload `lib64/`. The only new system
assumption is **`liblzma.so.5`** (gtkwave's own `-llzma` for VZT), deliberately NOT
bundled: `rpm`'s own `librpmio` links it, so it is on every EL8 node including a
minimal install -- same class as `libsqlite3` / `libgnutls`. Everything else in the
`ldd` closure (systemd, selinux, gnutls, blkid, mount, lz4, gcrypt, ...) arrives
transitively via the glib/gio `gui_libs` already ships, so gtkwave adds nothing else.
Max glibc symbol is `GLIBC_2.14`. The script's closure check walks **every** binary
and not just `gtkwave` -- walking only one binary is how `libfontenc.so.1` shipped
missing for Xephyr.

**Runtime archive** (`runtime/gtkwave.tar.bz2`, ~370 KB): `share/gtkwave-gtk3`
(examples), `share/man` (16 man1 + `gtkwaverc.5`), plus `share/mime`, `share/icons`,
`share/applications` for desktop/MIME registration. The **1.7 MB `gtkwave.odt` user
manual is deleted before tarring**, matching octave's excluded doc tree; the man
pages are the offline reference actually usable from a terminal. man-db finds them
with no `MANPATH` change because `<prefix>/bin` on `PATH` maps to
`<prefix>/share/man`. `remove_before_extract` lists only `share/gtkwave-gtk3` --
`share/man`, `share/mime`, `share/icons`, `share/applications` are shared namespaces
and must not be deleted.

**Registry:** `gtkwave` (`kind: bin`, 16 `bins` + `archive`), `depends: [gui_libs]`,
sentinel `share/gtkwave-gtk3/examples/des.fst`, member of the new **`@eda`** group
which rides in `@engineering-loadout`. No `mesa3d_libs`: GTK3 renders through
cairo/X11 here, same as meld and mate-terminal. Total payload cost ~1.4 MB.

**Smoke: `--version` alone is NOT enough, and the generic probe is actively
misleading here.** `gtkwave --version` does exit 0 headless, but `rtlbrowse`,
`shmidcat` and `twinwave` have no version flag and exit **255** printing
`Could not open '--version'` -- 255 is not in `FATAL_EXIT_CODES`, so
`tests/prebuilt-binaries` scores them green off an error message and a totally
broken FST reader would pass. `smoke_runtime_layout` therefore round-trips the
shipped example: `fst2vcd des.fst` (must produce >1000 lines containing
`$enddefinitions`) -> `vcd2fst` -> `fst2vcd` again. The build script runs the same
round-trip against the staged tree before packaging.

**Verify after building:** `./build/strip-all-elf-binaries && build/gen-content-manifest &&
./loadout completion bash > envs/bash/global/completions/loadout.bash`, then
`./loadout install gtkwave --dest-dir <d>` and, with `<d>/local/bin` on `PATH`:
`gtkwave --version`, the FST round-trip, `twinwave` (must print usage, proving it
finds gtkwave on `PATH`), `man -w gtkwave`, and -- on a box with a display --
`gtkwave <d>/local/share/gtkwave-gtk3/examples/des.fst`, which must report
`FSTLOAD | Built 1287 signals and 145 aliases.` and open a window.

## klayout 0.30.10 -- GDSII/OASIS mask layout viewer + editor (EL8 SOURCE build, Qt5)

The standard open-source mask-layout tool: GDS2, OASIS, DXF, CIF, MAG, LEF/DEF; a
scriptable DRC and LVS engine; a Ruby and Python API; and the `strm*` batch
converters. **This is what the `ruby` package was originally added for** -- the ruby
note above calls it "the interpreter KLayout embeds for DRC/LVS scripting" -- but
KLayout itself had never been built. That intent lived only in a build note, never in
`docs/HANDOFF.md` and never in the registry.

**Tag: `v0.30.10`.**

**Prerequisites:**
```
dnf install qt5-qtbase-devel qt5-qtsvg-devel qt5-qtxmlpatterns-devel \
            gcc-c++ make curl cpio rpm-build
./loadout install portable-python     # headers + libpython3.14.so
```
`qt5-qtxmlpatterns-devel` is the easy miss: without it qmake stops with
`Project ERROR: Unknown module(s) in QT: xmlpatterns` after reading ~40 .pro files.

**Build:** `build/build-klayout.sh --tag v0.30.10` (~25 min). Real invocation:
```
./build.sh -qmake /usr/bin/qmake-qt5 -prefix /tmp/klayout-install-0.30.10 -release \
   -rbinc <rbtree>/usr/include -rbinc2 <rbtree>/usr/include \
   -rblib <rbtree>/usr/lib64/libruby.so.3.3.10 -rbvers 30310 \
   -python ~/.local/bin/python3.14 -pyinc ~/.local/include/python3.14 \
   -pylib ~/.local/lib/libpython3.14.so \
   -without-qt-uitools -without-qt-designer -without-qt-multimedia -without-qt-sql \
   -nolibgit2 -jN
```

### The five things that are not obvious

**1. Ruby headers WITHOUT switching the build box's dnf module stream.** EL8's default
ruby stream is 2.5 and the loadout ships 3.3, so
`dnf module reset ruby && dnf module enable ruby:3.3 && dnf install ruby-devel` would
**replace the system interpreter as a side effect**. Instead the script fetches
`ruby-devel`, `ruby-libs`, `ruby` and `rubygems` from the ruby:3.3 stream **by direct
URL** into a temp tree -- the technique `build/build-ruby.sh` already uses -- and
logs each fetch to `assurance/downloads.log`. Nothing on the build machine changes.
All four are needed: devel for headers, libs for the link + stdlib, `ruby` because the
script derives the ABI version code from the real interpreter rather than hardcoding
`30310`, and `rubygems` because ruby's `gem_prelude` requires it at startup.
Probing that interpreter needs **`--disable-gems`**, or it loads the SYSTEM
`/usr/share/rubygems` (2.5's) and dies with
``undefined method `=~' for an instance of Integer``.

**2. `LD_LIBRARY_PATH` is load-bearing at BUILD time.** libpython lives in
`~/.local/lib`, which is not on `ld`'s search path. `libklayout_pya.so` links fine
(shared objects tolerate undefined symbols) but when the `strm*` "buddy" executables
link `-lklayout_pya`, `ld` must resolve its `DT_NEEDED libpython3.14.so.1.0`
transitively, cannot find it, and the build dies with ~200
``undefined reference to `PyList_GetItem'`` **after twenty minutes of compiling**.
Exporting `LD_LIBRARY_PATH=~/.local/lib` fixes it. This is purely a link-time path;
the baked RPATHs are what resolve libpython at run time.

**3. `KLAYOUT_PYTHONHOME`, never `PYTHONHOME`.** `src/pya/pya/pya.cc` **deliberately
unsets `PYTHONHOME`** ("Python is not easily convinced to use an external path
properly. So we simply redirect PYTHONHOME") and honours only `KLAYOUT_PYTHONHOME`
and `KLAYOUT_PYTHONPATH`. Setting `PYTHONHOME` in the launcher is silently discarded
and the embedded interpreter aborts with
```
Could not find platform independent libraries <prefix>
Fatal Python error: Failed to import encodings module
```
because libpython3.14 cannot derive its prefix from `argv[0]` (= `klayout`).

**4. `RUBYLIB` must include `share/rubygems`.** KLayout embeds the loadout's
`libruby.so.3.3`, and EL8's ruby is not built `--enable-load-relative`, so its
compiled-in `$LOAD_PATH` points at `/usr`. Without `RUBYLIB` the embedded 3.3 loads
the system 2.5 stdlib and dies with
`ruby lib version (2.5.9) doesn't match executable version (3.3.10)`. Adding only
`lib64/ruby:share/ruby` is not enough -- `gem_prelude` then reaches
`/usr/share/rubygems` and fails the same way. The launcher exports the same
`RUBYLIB`/`GEM_HOME`/`GEM_PATH` triple `bin/ruby` does.

**5. Qt modules that are off, and why `-without-qt-xml` is NOT among them.** Disabled
because their libs are not bundled: `uitools` (EL8 ships no such lib at all),
`designer`, `multimedia`, `sql`. The cost is that KLayout macros cannot load `.ui`
files at run time; the macro IDE itself still works. `HAVE_QT_XML` is **kept**, which
pulls `Qt5XmlPatterns` -- a lib that was **not** previously bundled, so this build
adds `libQt5XmlPatterns.so.5` to `gui_libs`. Do not "solve" the missing devel package
with `-without-qt-xml`: KLayout reads `.lyp` layer-property files and `.lym` macros as
XML, and with neither QtXml nor expat there is no XML parser at all.

Also `-nolibgit2`: `HAVE_GIT2` defaults ON and drives KLayout's Salt package manager,
which downloads packages over the network -- useless offline, and libgit2 is EPEL-only
on EL8.

### Packaging

KLayout installs **flat**: one directory with the `klayout` binary, 12 `strm*` tools,
~35 `libklayout_*.so` (plus `.so`/`.so.0`/`.so.0.30` symlink chains), `db_plugins/`,
`lay_plugins/`, and `pymod/` (the standalone `import klayout` package). That tree ships
verbatim as `<prefix>/lib/klayout/`, with **13 copies of `build/klayout/klayout` in
`bin/`** that dispatch on their own basename -- one script, 13 names, the
wezterm/vcd-toggle-profiler shape.

RPATHs are per-depth, because the tree is flat and each level needs its own hop count
back to `<prefix>/lib64` (bundled Qt5/ruby/X11) and `<prefix>/lib` (portable-python's
`libpython3.14.so.1.0`):

| location | RPATH |
|---|---|
| `lib/klayout/` | `$ORIGIN:$ORIGIN/../../lib64:$ORIGIN/../../lib` |
| `lib/klayout/{db,lay}_plugins/` | `$ORIGIN:$ORIGIN/..:$ORIGIN/../../../lib64:$ORIGIN/../../../lib` |
| `lib/klayout/pymod/{klayout,pya}/` | `$ORIGIN:$ORIGIN/../..:$ORIGIN/../../../../lib64:$ORIGIN/../../../../lib` |

The build asserts no RUNPATH still points at the build prefix after patchelf, and that
the tree contains **zero symlinks-to-directories** -- those do not survive
`strip-all-elf-binaries`' re-tar (`add_tree_to_tar` walks with `followlinks=False` and
never re-emits them; the firefox lesson). The ~171 file symlinks are fine.

**Payload: ~53 MB** (186 MB uncompressed, already stripped by the release build), so
`strip-all-elf-binaries` chunks `runtime/klayout.tar.bz2` into `.part-NNN` shards.
Plus `lib64/libQt5XmlPatterns.so.5.bz2`.

**GL:** `libGL.so.1`/`libGLX.so.0`/`libGLdispatch.so.0` are direct NEEDEDs, so the
package `depends` on `mesa3d_libs` for the Mesa vendor side while the GLVND dispatcher
stays host-provided -- the surfer/wezterm arrangement, and the launcher carries the
same `LD_LIBRARY_PATH`/`LIBGL_DRIVERS_PATH`/`__EGL_VENDOR_LIBRARY_DIRS` block.
Full `depends`: `gui_libs`, `mesa3d_libs`, `ruby`, `portable-python`.

**LIMITATION -- host GLVND is required even for BATCH use.** The 12 `strm*`
converters link the same `libklayout_lay`/`libklayout_laybasic` set as the GUI, so
on a node with no OpenGL at all *nothing* in this package runs -- not `klayout -zz`,
not `strm2gds`. The clean-container gate showed exactly that: 13 launchers plus the
batch runtime probe all reporting
`libGL.so.1: cannot open shared object file`. That is the same host contract
`nedit-ng`, `nvim-qt`, `flameshot` and `Xephyr` already carry (EL8 provides it via
`mesa-libGL`/`libglvnd-glx`), and it is why those probes SKIP rather than FAIL --
but note it is a stronger constraint here than for a pure GUI app, because the
batch tools inherit it. Splitting the converters off would mean building a
GUI-less second copy of the whole library set; not worth it, but do not promise a
GL-less farm node that `strm2gds` will work.

**The skip needed teaching, and that was a test gap, not a packaging bug.**
`tests/prebuilt-binaries` resolved a wrapper's real ELF only as `bin/<name>.bin`,
which cannot find KLayout's binaries at `lib/klayout/<name>` -- so all 13
launchers exec'd and returned a hard 127 instead of skipping. `real_elf_for_wrapper()`
now also searches `lib/*/<name>[.bin]`. A `lib/<name>/<name>` guess would NOT have
worked: KLayout has one lib dir holding 13 differently-named launchers.

**Assumed present, not bundled** (beyond the usual glibc/libstdc++/GLVND): EL8 base
`libssl.so.1.1`/`libcrypto.so.1.1` and the krb5 set
(`libgssapi_krb5`, `libkrb5`, `libkrb5support`, `libk5crypto`, `libcom_err`,
`libkeyutils`), which openssl/curl pull onto every node. The closure check walks
**every** ELF in the tree, not just `bin/klayout` -- checking one binary is how
`libfontenc.so.1` shipped missing for Xephyr.

**`pymod` is not on `sys.path`.** Standalone `import klayout` from the user's own
Python needs `export PYTHONPATH=<prefix>/lib/klayout/pymod`. It is deliberately not
installed into portable-python's `site-packages`, which another package owns. The
*embedded* interpreter (`klayout -zz -rm script.py`) needs nothing extra.

**Smoke: `klayout -v` proves nothing** -- it prints a compiled-in string without
touching the db plugins, the stream writers, or either interpreter. The build script
instead runs a batch Ruby script (`-zz -r`) that writes a two-layer layout to **both**
GDS2 and OASIS, reads each back, and asserts the layer 1/0 area is exactly 2000000 DBU²
and layer 2/0 has one shape; then `strm2oas` converting GDS -> OASIS; then a batch
**Python** script (`-zz -rm`) that writes a layout, asserting `PYTHON_OK`. `-zz` is
batch mode with no GUI, so all of it runs headless.

**Verify after building:** `./build/strip-all-elf-binaries && build/gen-content-manifest &&
./loadout completion bash > envs/bash/global/completions/loadout.bash`, then
`./loadout install klayout --dest-dir <d>` (pulls gui_libs, mesa3d_libs, ruby,
portable-python) and re-run the Ruby/Python/strm2oas trio through
`<d>/local/bin/klayout` with **nothing** in the environment -- that is what proves the
launcher's own `RUBYLIB` and `KLAYOUT_PYTHONHOME` derivation, which the build-time
smoke has to supply by hand. On a box with a display, `klayout <file>.gds` should open
the layout window.

## verilator 5.050 -- Verilog/SystemVerilog -> C++ simulator (EL8 SOURCE build)

Compiles synthesizable Verilog/SystemVerilog into a C++ model that the user's own
`g++` then compiles. Positioned here as a **lint / coverage / regression** tool, not
a commercial-simulator replacement: the users this repo serves have paid simulators,
and Verilator does not event-simulate non-synthesizable testbench code.

**Tag: `v5.050`.** Upstream versions are `X.YYY` (not semver), so `farm-versions`
matches `Verilator ([0-9]+\.[0-9]+)`.

**Prerequisites:**
```
dnf install autoconf flex bison help2man gcc-c++ make perl python3
```
**`help2man` is required and easy to miss** -- `make` builds man pages and dies with
`[Makefile:205: verilator_gantt.1] Error 127` without it.

**Build:** `build/build-verilator.sh --tag v5.050` -- `autoconf` (the tag ships no
`configure`), `./configure --prefix=...`, `make`, `make install`. No patches, no
special flags.

**NO WRAPPER -- and it is verified, not assumed.** `bin/verilator` is upstream's Perl
driver and it resolves its own root:
```perl
my $verilator_pkgdatadir_relpath = "../share/verilator";
my $verilator_root = realpath("$RealBin/$verilator_pkgdatadir_relpath");
```
so it works wherever the tree lands, and the shims in `share/verilator/bin/` exec
through a relative `../../../bin`. The build script **proves** this by copying the
staged tree to a completely different path and running a full
RTL -> C++ -> `g++` -> execute cycle there, asserting the model prints `CNT=10`.
`verilator --version` would pass with a dead root, so do not weaken that to a version
check.

**The one non-relocatable artifact is `share/pkgconfig/verilator.pc`**, whose
`prefix=` is an absolute build path and which cannot self-derive. The build rewrites
it to `/__LOADOUT_RELOC_ROOT__` and the registry carries
`relocate_token` + `relocate_root: share/pkgconfig`, so the installer substitutes the
real deployment root -- the same mechanism `modules` uses. `share/pkgconfig` is owned
by no other package, and relocation only rewrites files that actually contain the
token, so scanning that one directory is safe. Leaving the dead prefix instead would
be worse than dropping the file: `pkg-config --cflags verilator` would emit
`-I/tmp/verilator-install-5.050/...` and silently produce a broken build.
`verilator-config.cmake` needs no fixup -- it is already relocatable.

**NOTHING TO BUNDLE.** `verilator_bin` links only `libpthread`/`libm`/`libc`:
Verilator builds with `-static-libstdc++ -static-libgcc`, so there is **no
`libstdc++.so.6` dependency and no `GLIBCXX_*` requirement at all**, and max glibc
symbol is `GLIBC_2.17`. No patchelf, no RPATH -- like espresso. The build script
**asserts** the C++ runtime stays static: if a future release links `libstdc++.so.6`
dynamically it would pick up gcc-toolset-14's newer copy, which this repo never
bundles, and fail on a stock EL8 node. Better to fail the build than ship that.

**HOST REQUIREMENT -- perl.** `bin/verilator` and `bin/verilator_coverage` are
`#!/usr/bin/env perl`; `verilator_gantt`, `verilator_profcfunc` and
`verilator_includer` are Python 3 (which resolves to the loadout's own 3.14). Perl is
not bundled, so both Perl entry points are listed in `HOST_REQUIRED_COMMANDS` in
`tests/prebuilt-binaries` -- the same call already made for `cloc`. Without perl on
PATH the failure is loud: `/usr/bin/env: 'perl': No such file or directory`. Users
also need their own `g++`; EL8's system g++ 8.5 is sufficient and is what the build
script's smoke deliberately uses (not gcc-toolset-14, which a farm node lacks).

**DELIBERATELY NOT SHIPPED -- `verilator_bin_dbg`.** 104 MB unstripped (~25 MB
compressed), which is more than every other file in this package combined. It is the
assertion-enabled build used only by `verilator --debug`, for debugging **Verilator
itself**, not user RTL. Dropping it makes `--debug` fail loudly. `verilator_coverage_bin_dbg`
IS shipped (320 KB): there is no release build of it, so `verilator_coverage` needs it.

**Payload:** 6 `bin/*.bz2` (`verilator`, `verilator_bin`, `verilator_coverage`,
`verilator_coverage_bin_dbg`, `verilator_gantt`, `verilator_profcfunc`; the two ELFs
stripped, the four scripts shipped as non-ELF bz2 like `vim.bz2`) plus
`runtime/verilator.tar.bz2` (~271 KB: `share/verilator/{include,bin,examples}`,
`share/man`, `share/pkgconfig`). ~5 MB total.

**Registry:** `verilator` (`kind: bin`), member of the **`@eda`** group, sentinel
`share/verilator/include/verilated.mk` -- the file whose absence means every
generated model fails to compile.

**Smoke:** `tests/prebuilt-binaries` runs `verilator --lint-only` on a generated
module, then lints a module referencing an **undefined signal** and requires that one
to FAIL. A lint that cannot fail is not a lint. It deliberately does *not* `--build`:
the clean almalinux:8.10 container has no `g++`, and linting already exercises root
resolution plus the whole SystemVerilog front end.

**Verify after building:** `./build/strip-all-elf-binaries && build/gen-content-manifest &&
./loadout completion bash > envs/bash/global/completions/loadout.bash`, then
`./loadout install verilator --dest-dir <d>` and check: `verilator.pc` contains the
real prefix and zero `__LOADOUT_RELOC_ROOT__`; `PKG_CONFIG_PATH=<d>/local/share/pkgconfig
pkg-config --cflags verilator` resolves; and a full `-cc ... --exe ... --build` cycle
runs and prints `CNT=10`.

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

## tmux-path-store 1.1.0 -- tmux window-name-keyed path store (first-party python-tool)

First-party (github.com/smprather/tmux-path-store). Stores a directory or file path
keyed by the current tmux window name, which is what the `p` / `cdp` aliases in
`envs/bash/global/bashrc` drive. Pure Python, one runtime dependency (`rich`), so
the wheel is `py3-none-any` -- no compiled artifact, nothing platform-specific.

**This note exists because the package had none.** Like liberty-filter, it was
bundled with no build script and no entry here, so nothing recorded where its wheel
came from or how to refresh it. Two packages hit this same gap in one session; if
you bundle a wheel by hand, write the script at the same time.

**Tag: `v1.1.0`** (added `--zsh` and `--csh`/`--tcsh` alias emitters alongside
`--bash`; v1.0.1 was the release that renamed the console script to kebab-case, and
it was `tmux_path_store` through v1.0.0).

**Build:** `build/build-tmux-path-store.sh --tag v1.1.0`

**Why v1.1.0 mattered here.** Through v1.0.1 the tool emitted `--bash` only, so
`LOADOUT_CFG_ENABLE_TMUX_PATH_STORE` was a documented gap in both the tcsh and zsh
envs and sat in `tests/env-shell-parity`'s exception table. v1.1.0 closed it, and
all three shells now wire it up: `--bash`, `--zsh`, and `--csh` for tcsh. The csh
emitter escapes its argument marker as `\!*` so csh stores a literal `!` rather
than expanding history -- do not re-quote that at the call site.

**Prerequisites:** `git`, `uv`, `python3.14`. No compiler, no dev packages.

**NOT `rolling_git`.** `./build/update`'s rolling path builds from source HEAD and
stamps a `git describe` version, which is right for the first-party tools upstream
does not tag (`text-serdes`, `time-plot`). This project tags releases, so it is
pinned like `parity-plot`: `--tag` only, no HEAD builds. The script also refuses a
version containing `dev`/`rc`.

### Two things the script checks against the ARTIFACT, not the repo

1. **The console-script name comes from the built wheel's `entry_points.txt`**, not
   from `pyproject.toml` and never assumed. It must be exactly
   `tmux-path-store`, and a mismatch hard-fails naming what was found -- the
   registry `bins` entry names the launcher the installer expects, so a
   disagreement ships a tool the user cannot run. When it changes, `EXPECT_SCRIPT`
   in the script, `bins` in `payload/packages.json`, and the binary-name key in
   `build/farm-versions` all move together.
2. **The runtime dependency closure must already be in the payload wheelhouse.**
   The script parses `Requires-Dist` out of the wheel's `METADATA` (skipping
   `extra` markers) and refuses to bundle anything whose deps are missing. An
   offline install cannot fetch a wheel later, so a new upstream dependency has to
   be bundled deliberately rather than discovered by a user on an air-gapped box.

It also prunes the previous `tmux_path_store-*.whl` before copying the new one: a
stale sibling leaves two versions of the same dist in `--find-links` and lets `uv`
resolve the wrong one.

**Verify after building:** `python3.14 build/gen-content-manifest &&
python3.14 build/gen-readme-table`, then `./loadout install tmux-path-store
--dest-dir <d>` and check `<d>/local/bin/tmux-path-store --version` reports the
tagged version and that no `tmux_path_store` launcher remains.

## liberty-filter 1.0.1 -- strip unneeded data from Liberty .lib files (EDA)

First-party (github.com/smprather/liberty-filter). Streams a Liberty timing file
and drops groups/cells by regex, so a multi-GB `.lib` becomes something a tool or
a human can actually work with. Reads `.gz` directly.

**A SEPARATE repo from `liberty-tools`**, which is the thing to get right here: the
two ship related CLIs and share a version lineage, but liberty-tools is a Python
wheel with a PyO3 cdylib (`rolling_git`, built by `./build/update`) while this is a
standalone Rust binary. It cannot use the rolling path -- `./build/update` builds
*wheels*, so it can never produce a Rust binary. Same reason `spice-subckt-rc-reduce`
is not `rolling_git`.

**This note exists because the package had none.** liberty-filter entered the
payload in the `ad63c48` bootstrap snapshot with no build script and no entry here,
so its provenance was recorded nowhere in this repo -- it had to be recovered from
the shipped binary's own strings, which named `/tmp/liberty-rebuild-*/liberty-filter`.
That is exactly what the "every tool gets a note" mandate at the top of this file is
for.

**Tag: `v2026.08.06.1`** (Cargo `version = 1.0.1`).

**Build:** `build/build-liberty-filter.sh --tag v2026.08.06.1`

**Prerequisites:** `rustc` + `cargo` (tested 1.96.0, `edition = "2021"`),
`patchelf` at `~/.local/bin/patchelf`. No dev packages.

### Offline build with no crate-store

Unlike spice-subckt-rc-reduce (zero dependencies), this crate depends on `flate2`
and `regex` -- but upstream **vendors the whole closure**: `vendor/` is committed
(466 files) alongside a `.cargo/config.toml` with
`replace-with = "vendored-sources"`. So the build runs `cargo build --release
--locked --offline` and needs neither the network nor `rust-crate-store`. The script
**asserts** both inputs before building, so a future upstream change that drops the
vendor tree fails loudly here rather than silently reaching for the network on a
build box that happens to have it.

### The executable name is read from upstream, not assumed

It was `liberty_filter` up to and including tag `v2026.06.01.1` and is
`liberty-filter` from commit `1503846` ("Use kebab-case executable names") onward.
The script parses `[[bin]] name` out of `Cargo.toml` and hard-fails if it is not the
expected value, naming the mismatch -- because the registry `bins` entry names the
payload stem `bin/<name>.bz2`, so a disagreement ships a package nothing can run.
**When it changes, three places move together:** `EXPECT_BIN` here, `bins` in
`payload/packages.json`, and both the binary-name key *and* the match regex in
`build/farm-versions`. Renaming a stem also means deleting the old
`bin/<old-name>.bz2`, or `doctor` reports an unregistered payload.

### Version: Cargo's, not the tag's

Upstream tags are date-based (`v2026.08.06.1`) while Cargo carries the semantic
version (`1.0.1`), and `--version` prints the Cargo one. The script stamps **Cargo's**
version so the registry agrees with what the binary reports; otherwise
`check-versions` and `farm-versions` disagree forever. It also **refuses a `-dev`
version**: HEAD after a release is a post-release bump (`1.0.2-dev`) and must not be
shipped as a release. `--rev <ref>` remains available for a `git describe` build of
untagged upstream state -- which is how the other first-party tools already ship
here -- but prefer `--tag`.

**Deps:** NEEDED is `libgcc_s.so.1`, `libpthread.so.0`, `libc.so.6` -- glibc and
libgcc only, both on the never-bundle list in AGENTS.md. Max glibc symbol
`GLIBC_2.28`, exactly the EL8 floor. No lib64 artifacts, no runtime data, so no
runtime tarball.

### Smoke: mind the filter flag semantics

`--filter-in-cells` is an **exception list to `--filter-out-cells`, not a standalone
allowlist**. The drop rule in `src/main.rs` is
`match_filter_out_cell && !match_filter_in_cell`, so `--filter-in-cells '^nand'`
*by itself drops nothing* -- upstream's own unit test pairs `^KEEP$` with
`filter_out_cells: ["."]`. Getting this wrong looks exactly like a pass-through bug
in the tool. "Keep only nand" is:

```sh
liberty-filter --in-file lib.gz --out-file out.lib \
    --filter-out-cells '.' --filter-in-cells '^nand'
```

The build script runs that against the real 1308-cell / 96 MB library upstream
ships and asserts the output shrank (1308 -> 149 cells), that every surviving cell
is a `nand`, and that the `library()` group is intact -- a pass-through or a
truncating write would both sail past `--version`.

**Verify after building:** `python3.14 build/gen-content-manifest &&
python3.14 build/gen-readme-table`, then `./loadout install liberty-filter
--dest-dir <d>` and run the filter above from the installed tree.

## spice-subckt-rc-reduce 0.1.0 -- SPICE .subckt parasitic RC reduction (EDA)

First-party (github.com/smprather). Simplifies parasitic RC networks inside
`.subckt` models while preserving electrical behavior at the port nodes, so
downstream simulation runs faster. Two algorithms: TICER (time-constant
elimination, the default) and small-resistor merge.

**Build:** `build/build-spice-subckt-rc-reduce.sh --tag v0.1.0`

```sh
git clone --filter=blob:none https://github.com/smprather/spice-subckt-rc-reduce.git
git checkout --detach v0.1.0
cargo build --release --locked
# -> target/release/spice-subckt-rc-reduce
```

Prereqs: `cargo`/`rustc` (tested 1.96.0; `edition = "2024"` needs >= 1.85, and
upstream's README asks for 1.96+), `patchelf` at `~/.local/bin/patchelf`.
Packaging is the standard strip -> patchelf -> bzip2 via `loadout_package_bin`.

**Why this one is unusually easy:** `Cargo.lock` resolves to exactly ONE package
-- itself. Zero external crates. So the build needs no network and no offline
crate-store (unlike `surfer` or the `@rust` trio), and there is nothing to
vendor. The build script asserts this invariant (`grep -c '^\[\[package\]\]'
Cargo.lock` must be 1) and fails loudly if upstream ever takes a dependency,
rather than silently reaching for the network on some future build box.

**No libs bundled.** NEEDED is `libgcc_s.so.1`, `libpthread.so.0`, `libm.so.6`,
`libc.so.6` -- all glibc/libgcc, all present on every EL8 target, and all on the
never-bundle list in AGENTS.md. Max glibc symbol is `GLIBC_2.28`, exactly the
EL8 floor. No runtime data files, so no runtime tarball.

**Name asymmetry (upstream's, and load-bearing here):**

| thing | value |
|---|---|
| repo / registry package | `spice-subckt-rc-reduce` (dashes) |
| installed binary, `[[bin]]` name | `spice-subckt-rc-reduce` (kebab, since v0.1.1) |
| cargo `[lib]` name | `rcreduce` |

The registry `"bins"` entry MUST use the underscore form -- it names the payload
stem `bin/spice-subckt-rc-reduce.bz2`, not the package.

**The asymmetry is gone as of v0.1.1.** Through v0.1.0 the `[[bin]]` name was
`spice_subckt_rc_reduce` while the package was dashed, and the registry had to use
the underscore form. v0.1.1 renamed the executable to kebab-case, so package, repo
and executable now agree. The build script reads the stem out of `Cargo.toml`
instead of assuming it and hard-fails on a mismatch; when it moves, `bins` in
`payload/packages.json` moves with it and the stale `bin/<old-name>.bz2` must be
deleted, or `doctor` reports an unregistered payload.

**Not `rolling_git`, despite being first-party.** `./build/update`'s rolling path
builds Python *wheels* (`uv build --wheel`), so it cannot produce a Rust binary.
Bump it with the build script and a stable tag like any other `build`-class
package.

**Not in `farm-versions`, deliberately.** The tool has no `--version` flag and
embeds no version string, so every probe strategy would report `missing`
forever. A permanently-red row is the "stale check trains people to ignore real
signal" failure this repo already learned from (the fish `FAILED` row), so it is
omitted instead. `tests/registry-integrity` only checks TOOLS -> registry, so
omission is safe. Add a row if upstream ever grows `--version`.

**Smoke:** `--version` does not exist and exit-0 proves nothing about a
reduction engine -- a mis-built binary can parse a netlist and reduce nothing.
Both the build script and `tests/prebuilt-binaries` therefore assert a real
reduction: the build script runs `testdata/large_mesh.subckt` at `--tau 1e-9`
and requires the node count to drop below its starting 105; the installed-binary
probe feeds a 6-node RC chain at `--tau 1e-6` and requires `Nodes: N -> M` with
`M < N` plus a non-empty output netlist.

**Group:** `@scientific` (beside `gnuplot`, `octave`, `ngspice`, `espresso`),
which is itself a member of `@engineering-loadout`, so it ships in the curated
set. Non-optional: 305 KB compressed, no dependencies.

**Usage:** `spice-subckt-rc-reduce in.subckt -o out.subckt -a ticer --tau 1e-12 -v`;
`--pg-tau` sets a separate threshold for power/ground nets; `--power-ports` /
`--ground-ports` default to `auto`; `-a merge --r-threshold R` selects the
small-resistor merge algorithm instead; `--subckt NAME` targets one subcircuit.

## ruby 3.3.10 -- Ruby interpreter (shanghai from AlmaLinux 8's ruby:3.3 stream)

The user-facing Ruby, and the interpreter KLayout embeds for DRC/LVS scripting.

**Build:** `build/build-ruby.sh --tag 3.3.10-7`

Repacked from AlmaLinux's own module stream rather than source-built, so CVE
fixes arrive by re-running the script against a newer NVR instead of a
source-build babysitting job. Find the current NVR + context with:

```sh
dnf module info ruby:3.3 | tr ' ' '\n' | grep -E '^ruby-0:' | sort -V | tail -3
build/build-ruby.sh --tag 3.3.10-7 --context module_el8.10.0+4210+b037b1ec
```

**Never ship EL8's default ruby stream (2.5)** -- EOL since March 2021, no
security updates. 3.3 is the newest stream AlmaLinux 8 carries.

RPM set: `ruby`, `ruby-libs`, `rubygems`, `ruby-bundled-gems`, and
`rubygem-{irb,json,bigdecimal,io-console,psych,rdoc}`. The `rubygem-*` ones are
**not optional**: in Ruby 3.3 json/psych/bigdecimal moved out of core into
default gems, so without them `require "json"` fails outright.

### Four fixups, each silently fatal if skipped

1. **83 absolute symlinks.** The stdlib entries for default gems are links into
   `/usr`, e.g. `share/ruby/psych.rb -> /usr/share/gems/gems/psych-5.1.2/lib/psych.rb`.
   They dangle the instant the tree leaves `/usr`. The script **materializes**
   them (replaces each with a real copy resolved inside the extracted tree)
   rather than rewriting them relative, because `add_tree_to_tar`'s
   `os.walk(followlinks=False)` never re-emits symlinks-to-directories -- a
   re-tarred archive would silently drop the 5 directory links (the firefox
   lesson).
2. **Split gem extensions.** Fedora/RHEL put compiled gem `.so` files under
   `/usr/lib64/gems/ruby/<g>-<v>/`, but relocated rubygems looks in
   `<prefix>/share/gems/extensions/x86_64-linux/3.3.0/<g>-<v>/`. Left alone,
   every extension gem prints `Ignoring <gem> because its extensions are not
   built` on stderr and fails to load. Do not try to fix this with `RUBYLIB` --
   the `gem.build_complete` marker is what rubygems actually checks.
3. **Not relocatable.** EL8's ruby is not built `--enable-load-relative`.
   `rbconfig`'s `TOPDIR` trick sets `prefix`, but `rubylibdir`/`rubyarchdir`
   stay absolute `/usr` paths, so `$LOAD_PATH` ignores where the tree lives.
   `bin/ruby` is therefore a POSIX-sh wrapper exporting `RUBYLIB` +
   `GEM_HOME`/`GEM_PATH` derived from its own installed path. `bin/{gem,irb,rdbg}`
   ship `#!/usr/bin/ruby` shebangs -- absolute, resolving to the SYSTEM ruby (2.5
   or absent) -- so they become wrappers too, with the real scripts under
   `libexec/ruby/`.
4. **Missing default-gem specs.** EL8 ships `share/gems/specifications/default/`
   **empty**, so psych/irb/debug declare runtime deps (`stringio`, `reline`,
   `date`, `forwardable`, `singleton`, `time`, `net-protocol`) that rubygems
   cannot resolve -- `irb` dies in `activate_bin_path` even though every one of
   those libraries is present and `require`s fine. The script generates the
   specs, reading each library's real `VERSION` at runtime rather than
   hardcoding. They go in `specifications/`, **not** `specifications/default/`:
   `Gem.default_specifications_dir` is a compiled-in `/usr` path that relocation
   cannot move, so anything written to the relocated `default/` dir is never
   scanned.

The script gates on all of this before packaging: it requires 0 remaining
absolute symlinks, 0 unsatisfied gem dependencies, a successful `require` of 13
stdlib/default-gem modules, and **silent stderr** on a clean require.

**Also drops** `lib/.build-id/` -- RPM debuginfo cross-links pointing
`../../../../usr/lib64/...`, which escape the archive root and make
`safe_extract_tar` (correctly) reject the whole tarball.

**Payload:** `bin/{ruby,ruby.bin,gem,irb,rdbg}.bz2`, `lib64/libruby.so.3.3.bz2`
(RPATH `$ORIGIN`, so KLayout and anything else embedding Ruby links this exact
copy), and `runtime/ruby.tar.bz2` (~3.9 MB: stdlib, gems, rubygems, libexec).
Non-optional, so it is in `@shared` and therefore in `@engineering-loadout`.

**Assumed present, not bundled:** `libcrypt.so.1` (libxcrypt, EL8 base -- same
assumption as `libgnutls` for mate-terminal). `libgmp.so.10` and `libz.so.1` are
already bundled by other packages.

**Smoke:** `ruby --version` proves nothing -- the interpreter starts fine with
its entire stdlib unreachable. `tests/prebuilt-binaries` instead requires 13
modules from the *installed* tree, asserts stderr is silent, and checks
`gem env`'s INSTALLATION DIRECTORY resolves inside the staged tree (which is what
catches the wrapper falling through to a system ruby).

## Xephyr 1.20.11-28.el8_10.3 -- nested X server + `xdesk` session launcher (shanghai from EL8 AppStream RPM)

Lets a user run a *different* desktop or window manager without root. On a
locked-down host the DE is chosen by root-owned config -- NoMachine's
`/usr/NX/etc/node.cfg` (`DefaultDesktopCommand "... gnome-session --session=gnome"`,
hardcoded, so the usual `~/.xsession` hook via `/etc/X11/xinit/Xsession default`
does **not** apply), or GDM's session list. Xephyr sidesteps all of it: it is an
ordinary client window inside the session the user already has, and an X server
for whatever runs inside it.

**Chosen over Xvnc deliberately.** A user-run `Xvnc` opens a listening TCP port
(590x), which is exactly the thing a security-minded site bans, and the repo's
own `vnc`/`killvnc` aliases imply farm nodes already run one. Xephyr binds no
network socket at all.

**Build:** `build/build-xephyr.sh --tag 1.20.11-28.el8_10.3`

`--tag` takes the full NVR version-release, not a bare upstream version: the
`-28.el8_10.3` release field is where Red Hat's CVE backports live, and the
build rejects a bare `1.20.11`. The script `dnf download`s the RPM into a temp
dir and extracts with `rpm2cpio | cpio` -- no root, and the bundled bits are
pinned to `--tag` rather than to whatever the build box happens to have
installed. `--rpm <file>` takes a hand-carried RPM on an offline box. The
script records every consumed RPM NVR in `build/xephyr/PROVENANCE` and **fails
unless `payload/packages.json` records the same NVR** as `--tag`, so the
registry and the payload cannot drift.

### Library split (the part that decides what ships)

Of Xephyr's 34 `NEEDED` sonames, only **six** needed bundling:
`libXdmcp.so.6 libXfont2.so.2 libfontenc.so.1 libxcb-glx.so.0 libxcb-xf86dri.so.0 libxcb-xv.so.0`.
The six support libs are sourced from their own downloaded RPMs (`libXdmcp`,
`libXfont2`, `libfontenc`, `libxcb`), not copied out of the build box's
`/usr/lib64` -- the old behaviour pinned Xephyr to `--tag` while leaving its
libraries at whatever the build box happened to have installed, so a lib bump
could ship silently. Each consumed RPM NVR is recorded in
`build/xephyr/PROVENANCE`.

`libfontenc` is there for a reason worth remembering: it is **not** a dependency
of the binary, it is a dependency of bundled `libXfont2`. The first cut of this
package checked only the binary's own `NEEDED` list, shipped green through Tier
1 and Tier 2, and was caught by the clean-container gate with
`libfontenc.so.1 => not found` -- the build box had the X libs installed, so
nothing local could see the gap. The closure guard now walks the binary **and
every bundled lib**. (`libXfont2` also pulls `libfreetype.so.6`, which
`gui_libs` already owns, so that one is a depends, not a bundle.)

- **`gui_libs`** already owns libX11, libX11-xcb, libXau, libdbus-1, libepoxy,
  libpixman-1, libfreetype and 9 of the `libxcb-*` extensions -> declared as a
  `depends`.
- **`mesa3d_libs`** already owns `libdrm.so.2` and `libxshmfence.so.1` at the
  same `lib64/` path this package would install to. Declared as a `depends`
  rather than duplicated -- two packages owning one path is a real install
  hazard -- and it has the side benefit of giving the nested server a genuine
  Mesa vendor side for GLX. It is non-optional already, so this adds no weight.
- **GLVND stays host-provided.** `libGL.so.1` / `libGLX.so.0` /
  `libGLdispatch.so.0` are NEEDED but must never be bundled (see AGENTS.md).
  `tests/prebuilt-binaries` skips the exec probe when the host lacks them.

The build script re-derives this closure with `objdump -p` on every run and
**fails** on any NEEDED soname not covered by the bundle, a declared dependency,
or the EL8-base allowlist. Without that guard a new upstream dep would ship
green from a build box that happens to have it (the NSS/firefox trap).

**Assumed present, not bundled:** `/usr/share/X11/xkb` (xkeyboard-config) and
`/usr/bin/xkbcomp`, which the server compiles its keymap through at startup.
Present on any host with an X server or GUI stack; without them Xephyr falls
back to a pre-XKB keymap rather than failing. Also the EL8-base set
(libsystemd, libudev, libaudit, libcap-ng, libselinux, libcrypto, libgcrypt).

### `xdesk` (build/xephyr/xdesk)

`xdesk [-s WxH] [-f] [-d :N] [--no-dbus] [--no-auth] [-k] [-- command...]`.
Picks a free display, starts Xephyr, runs the session, tears the server down.
With no command it tries `$XDESK_SESSION` then autodetects
(`xfce4-session startxfce4 mate-session startlxqt fluxbox icewm openbox i3 dwm twm`).

Three things in it are load-bearing:

1. **MIT-MAGIC-COOKIE auth by default.** A unix-socket X server is *not*
   access-controlled: on a shared farm node any other user could connect to the
   nested display and read its keystrokes. `xdesk` mints a cookie into a private
   state dir under writable `$XDG_RUNTIME_DIR`, writable `$TMPDIR`, or `/tmp`,
   then exports that private dir as `XDG_RUNTIME_DIR` plus `XAUTHORITY`. It
   warns loudly if `xauth`/`mcookie` are missing rather than silently running open.
   `--no-auth` exists for debugging only.
2. **Readiness waits on the right fact.** The first version waited for
   `/tmp/.X11-unix/X$N` to appear and timed out against a perfectly healthy
   server: when `/tmp/.X11-unix` has the wrong mode (WSLg mounts it 0755, and
   hardened hosts do the same) Xephyr logs `failed to create listener for unix`
   and binds **only** the Linux abstract socket. Clients connect through it
   fine. `server_ready()` therefore accepts either the filesystem socket or
   `@/tmp/.X11-unix/X$N` in `/proc/net/unix`; display selection checks both too.
3. **One session bus.** `dbus-launch --exit-with-session` wraps the session,
   except for `start*` launchers (`startxfce4` runs `dbus-launch` itself; a
   second bus would strand half the session's services on the wrong one).

It also warns when the inherited `XDG_RUNTIME_DIR` is not `drwx------`, and
falls back when it is not writable/searchable; read-only `/run/user/$uid`
mounts can appear in constrained test/container sessions.

Two more `xdesk` rules worth recording:

- **`-k/--keep` does not remove the state dir holding the cookie.** An X server
  whose auth file is gone before any client connects applies no access control
  at all -- verified: a cookie-less connection succeeds against a kept server
  whose state dir was deleted. The kept server also inherits xdesk's
  stdout/stderr, so a caller reading xdesk's output through a pipe or `$(...)`
  blocks until the server itself exits; redirect to a file when combining
  `--keep` with output capture.
- **The nested session is forced onto X11 toolkits.** `xdesk` unsets
  `WAYLAND_DISPLAY` and exports `GDK_BACKEND=x11` / `QT_QPA_PLATFORM=xcb` so
  GTK/Qt clients cannot escape to the outer compositor. Without it this repo's
  own guidance to set `QT_QPA_PLATFORM=wayland` on WSLg would send every Qt app
  in the nest to the outer desktop.

### Keyboard grabs -- expect them, they are not a defect

Three layers grab before the nested server sees anything: the local OS and
remote-desktop client (Alt+Tab, the NoMachine magic key `Ctrl+Alt+0`), then the
**outer** desktop's own passive grabs (Super, Super+\*, Alt+Tab, Ctrl+Alt+arrows,
Print). Inside the Xephyr window, **Ctrl+Shift** toggles a full keyboard/pointer
grab, which outranks those passive grabs and routes them into the nested
session. Bind nested WM shortcuts to **Ctrl+Alt+letter** to avoid the collision
outright; do not use Super (outer WM owns it) or Ctrl+Shift (that is the toggle).

### Verified

Nested full XFCE 4.16 session on an EL8 box: `_NET_WM_NAME = "Xfwm4"`, panel,
xfdesktop, Thunar, xfsettingsd, power-manager, clean Logout. `xfwm4` warns
`Unsupported GL renderer (llvmpipe)` and falls back from compositing -- expected
with software GL.

**Nested GNOME does not work, and it is not Xephyr's fault.** `gnome-session`
starts, and every `gsd-*` daemon plus ibus/yelp connect, but `gnome-shell` 3.32
exits with `TypeError: this._userProxy.Display is null` in
`loginManager.js:getCurrentSessionProxy` -- it asks logind for the user's
graphical session and gets nothing on a host where none is registered. No GL
error is involved. Use a WM or a non-GNOME session inside the nest.

**No `build/farm-versions` entry**, on purpose: X servers of this vintage take
single-dash options only, `-version` is unrecognized, and the stripped binary
carries no version string, so every strategy would report a permanent gap. The
version lives in `packages.json` and is enforced against the RPM NVR by
`--tag`.

**Smoke:** `Xephyr -help` (exit 0, no parent display needed) and
`xdesk --help`, wired into `PROBE_FLAGS` in `tests/prebuilt-binaries` --
`--version` exits 1 with `Unrecognized option`, which would score red.

`tests/prebuilt-binaries` also gained a general fix here: a **wrapper** script
cannot be ldd-checked, so `bin/Xephyr` was exec-probed in the GL-less container
and returned 127 for a package that was fine, while `bin/Xephyr.bin` skipped
correctly. The loop now resolves a non-ELF `bin/<name>` to its `bin/<name>.bin`
sibling (a repo-wide convention) for the host-`.so` skip decision only -- when
anything is missing that is *not* host-required it still falls through to the
normal exec probe, so the change can only add skips, never mask a real failure.

`tests/install-xdesk` covers what no headless gate can: it installs into a temp
root, brings up a nested display through `xdesk`, and asserts the size, that a
cookie-less connection is refused, and that the server and its state dir are
gone afterwards. It **skips** when `$DISPLAY` is unset, so the container and any
headless CI stay green.

## htop / rsync / xsel / yank / yara -- small C tools (EL8 source builds)

These five shipped for months with **no build script and no note here**, which
this file's own mandate forbids. Each bump therefore meant re-deriving the
procedure from scratch; the 2026-08-04 sweep did exactly that and wrote it down.

**Build:** `build/build-simple-c.sh --tool <name> --tag <version> --src <tarball>`

One script, five recipes, because the configure flags genuinely differ. What is
shared is the packaging contract every loadout binary owes: `strip` ->
`patchelf --set-rpath '$ORIGIN/../lib64:$ORIGIN/../lib'` -> `bzip2`, plus a hard
check that the result needs nothing newer than EL8's **glibc 2.28**. That last
check is not ceremony -- an upstream prebuilt for three of the tools bumped in
the same sweep needed glibc 2.34/2.35/2.39 and would have installed cleanly on
the build box while being dead on a stock farm node.

Per-tool notes, and why each flag is there:

| tool | configure | why |
|---|---|---|
| `yara` | `./bootstrap.sh && ./configure --disable-magic --disable-cuckoo --without-crypto` | the magic and cuckoo modules need libmagic and jansson, which the loadout does not bundle and EL8 does not guarantee. `scan-for-malware` only uses the core scanner. |
| `rsync` | `./configure --disable-md2man` | skips the man-page toolchain. Do **not** disable xxhash/lz4/zstd: `packages.json` ships `libxxhash.so.0` for rsync, and the rest are EL8 base. |
| `htop` | `./autogen.sh && ./configure --disable-unicode --enable-static=no` | dynamic against the bundled ncurses. |
| `xsel` | `./autogen.sh \|\| autoreconf -fi; ./configure` | upstream's `missing` script is older than the host automake, which prints a warning and is harmless. |
| `yank` | plain `make` | no configure; pure C, `libc` only. |

Verified NEEDED sets at the 2026-08-04 versions (yara 4.5.8, rsync 3.4.4,
htop 3.5.2, xsel 1.2.1, yank 1.4.0):

- `yank` -- `libc` only (max symbol GLIBC_2.3)
- `xsel` -- `libX11`, `libc` (GLIBC_2.14); libX11 comes from `gui_libs`
- `yara` -- `libm`, `libpthread`, `libc` (GLIBC_2.17)
- `htop` -- `libcap`, `libncurses`, `libtinfo`, `libdl`, `libm`, `libc` (GLIBC_2.17)
- `rsync` -- `libacl`, `libpopt`, `liblz4`, `libzstd`, `libxxhash`, `libcrypto`, `libc` (GLIBC_2.14)

`libpopt`, `liblz4`, `libzstd`, `libcrypto` and `libacl` are EL8 base and are
deliberately not bundled; only `libxxhash.so.0` is, because EL8 has no system
xxhash.

## lua-language-server 3.19.0 -- LSP server for Lua (upstream linux-x64 prebuilt)

**This note exists because the package had none.** It was bundled with no build
script and no entry here, so nothing recorded where its payload came from or how
to refresh it -- the same provenance gap liberty-filter, tmux-path-store and the
five small C tools had. If you bundle a binary by hand, write the script in the
same change.

**Build:** `build/build-lua-language-server.sh --tag 3.19.0`

**Tag format is a BARE version, no leading `v`** -- that is upstream's convention
(github.com/LuaLS/lua-language-server/releases). The script rejects a `v` prefix
rather than silently 404ing on the asset URL.

**NOT a source build.** Upstream's `lua-language-server-<tag>-linux-x64.tar.gz`
has an ELF floor of `GLIBC_2.17`, comfortably under EL8's 2.28, so the prebuilt
is usable as-is. The script **asserts** that instead of assuming it: a future
release built against a newer toolchain would install cleanly on this box and be
dead on a stock farm node. That is not hypothetical -- the same check rejected
`bottom` (2.34), `fresh` (2.35), `tree-sitter` (2.39 at 0.26.11, 2.35 at
0.26.12) and `htop`, each of which had to become an EL8 source build.

**Packaging shape -- TWO artifacts that must stay in sync:**

| artifact | contents |
|---|---|
| `bin/lua-language-server.bz2` | POSIX-sh wrapper |
| `runtime/lua-language-server.tar.bz2` | `./share/lua-language-server/` tree |

The server is **not a lone binary**: it needs `main.lua`, `meta/`, `script/` and
`locale/` beside it and resolves them relative to its own path. So the real ELF
lives at `share/lua-language-server/bin/lua-language-server` and the wrapper
execs it from there, deriving its prefix from its own installed location so that
`--dest-dir` and shared-tree installs work with no build-time prefix baked in.
The registry `sentinel` is that inner binary, not the wrapper.

**No RPATH and nothing bundled.** The ELF NEEDs only glibc components
(`libc`, `libm`, `libpthread`, `libdl`, `ld-linux`), which are never bundled --
they must match the host `ld.so` exactly. The script fails on any other NEEDED
entry rather than letting a new shared-library dependency be discovered by a
user at runtime.

**Smoke:** run the WRAPPER, not the inner ELF -- `lua-language-server --version`
should print the bare version (`3.19.0`). Running the inner binary directly would
pass even if the wrapper's relative path were wrong.


## ty / mlr -- upstream single-binary prebuilt imports

**Build:** `build/build-prebuilt-bin.sh --tool ty --tag 0.0.70`
and `build/build-prebuilt-bin.sh --tool mlr --tag v6.21.0`.

> **`ty` is currently held at 0.0.69, and the script is not the reason.** `ty` is
> a Rust tool, so bumping the registry without re-pinning
> `build/rust-tool-locks.txt` makes `verify-crate-store --check-policy` fail:
> the shipped crate store is built from those refs, so a stale one means the
> store can no longer rebuild that tool **offline**. Re-pinning the locks alone
> would silence the gate while leaving the store genuinely missing the new
> dependency closure — do not do that. A real bump means
> `build/build-tool-crate-store.sh` (320 MB of payload churn) **and** a
> `crate-store` assurance re-pin, since that package has a record. `mlr` is Go
> and is not in the crate store, so it bumps freely.

**This note exists because both packages had none.** `ty` and `mlr` were each
bundled with no build script and no entry here, so nothing recorded where their
payload came from or how to refresh it — the same provenance gap
`lua-language-server`, `liberty-filter`, `tmux-path-store` and the five small C
tools each had. Multi-tool via `--tool`, following `build-simple-c.sh`.

Neither is a source build: upstream ships x86_64 binaries below EL8's glibc
2.28 floor (`ty` GLIBC_2.17; `mlr` is fully static). The script **asserts** that
rather than assuming it — a release built against a newer toolchain would
install cleanly here and be dead on a farm node, which is how `tree-sitter`,
`bottom` and `fresh` got rejected.

Three things worth not rediscovering:

- **Tag format differs per tool.** `ty` uses a bare version (`0.0.70`), miller
  uses a leading `v` (`v6.21.0`). The registry version is derived by stripping
  the `v`.
- **The binary name and the registry key are not the same for miller**: the
  binary is `mlr`, the `packages.json` key is `miller`. `loadout_package_bin`
  takes the binary name, `loadout_stamp_version` takes the registry key —
  passing the wrong one fails with a bare `KeyError`.
- **`loadout_package_bin` aborts on a static binary.** It always runs
  `patchelf --set-rpath`, which dies with `cannot find section '.dynamic'` on
  static Go binaries like `mlr`. Those take `strip` → `bzip2` with no patchelf
  and no RPATH — they load nothing. The script branches on an empty NEEDED set.

**Smoke is functional, not `--version`.** A type checker that silently passes
everything, or a data processor that emits nothing, both sail through a version
probe. `ty` is given a file with a genuine type error and must report it; `mlr`
must round-trip CSV to JSON. `ty` also publishes a sibling `.sha256` for its
release asset and the script verifies against it; miller publishes none, so the
script prints the hash it computed instead.


## spice-netlist-ls 0.3.0 -- SPICE netlist formatter + linter + LSP (upstream prebuilt, first-party)

**Build:** `build/build-prebuilt-bin.sh --tool spice-netlist-ls --tag v0.3.0`

First-party (smprather), MIT. `gofmt` for SPICE netlists: an opinionated
formatter, linter, and LSP server for the classic SPICE circuit-simulation
netlist format with pluggable dialects (HSPICE, NGSPICE, Spectre-SPICE, LTspice).
Member of `@eda`. Complements the bundled simulators (ngspice/iverilog/verilator)
by formatting+linting the decks they consume.

**Two binaries in one archive.** Upstream's `spice-netlist-ls-x86_64-unknown-linux-musl.tar.xz`
carries both `spicefmt` (the CLI formatter+linter) and `spice-netlist-ls` (the
LSP server). This is the first multi-binary prebuilt the import script handles:
the static-packaging branch was refactored to package each binary under its own
name (`_pkg_static_bin` helper) so a multi-binary tool does not clobber itself.
Both are static-pie musl — no NEEDED, no GLIBC symbols, no patchelf, no RPATH.
`strip` → `bzip2` only, same as `mlr`.

**`.tar.xz` not `.tar.gz`.** The extraction line now falls back to `tar xJf`
when `tar xzf` fails, so xz-compressed release archives work without a separate
code path per tool.

**Version probe is on the CLI binary, not the LSP.** `spicefmt --version`
prints `spicefmt 0.3.0`; `spice-netlist-ls` is an LSP server with no `--version`
or `--help` (bare invocation prints `Error: disconnected channel` and exits
nonzero). The script's version-assertion case branches on `spice-netlist-ls`
and probes `spicefmt`; the `tests/prebuilt-binaries` exec probe lists
`spice-netlist-ls` in `NO_EXEC`, so the generic `--version` loop does not flag
it as a failure. The dedicated LSP smoke drives initialize/initialized/shutdown/
exit over stdio and requires the server capabilities response. The CLI smoke
still covers formatter/linter behaviour.

**Functional smoke (in the import script and in `tests/prebuilt-binaries`).**
Four checks, each catching a distinct silent-failure class:
1. **Format:** a netlist with `R1 1 0   1k` (extra spaces) must come out as
   `R1 1 0 1k` — a formatter that passes input through unchanged sails a
   `--version` probe.
2. **Lint:** a deck with `X1 a b sub` (no matching `.subckt sub`) must report
   `undefined-subckt` — a linter that no-ops is the same hazard.
3. **Idempotency:** `spicefmt | spicefmt` is a fixed point — the formatter
   invariant. A non-idempotent formatter would destabilise every save.
4. **LSP startup:** `spice-netlist-ls` must answer a minimal stdio LSP session
   (`initialize` → `initialized` → `shutdown` → `exit`) with
   `definitionProvider` and `documentFormattingProvider` capabilities. This
   catches a corrupt/wrong-arch LSP binary that the sibling CLI cannot cover.

**Editor wiring.** `envs/nvim/lsp/spice_netlist_ls.lua` (added to
`vim.lsp.enable` in `init.lua`) — `cmd = {"spice-netlist-ls"}`, filetypes
`{spice, cir, scs, subckt}`. nvim's builtin `filetype.lua` maps `.sp`/`.scs`/
`.cir` → `spice` already; `.subckt` is not in its table, so the lsp config
calls `vim.filetype.add({ extension = { subckt = "spice" } })` (runs at config
time, before buffers load). Format-on-save is central: conform.nvim's
`BufWritePre` autocmd in `init.lua` falls back to the LSP server's
`textDocument/formatting` when no conform formatter is registered for the
filetype — no per-ft autocmd needed. Helix: `envs/helix/languages.toml`
registers a `[language-server.spice-netlist-ls]` + a `[[language]] name = "spice"`
block (helix has no built-in spice language, so this adds one rather than
replacing a default).

**`--dialect` / `spicefmt.toml` / `.scs` segmentation.** Dialect is
auto-detected per file (`.control`/`.csparam` → ngspice; `.alter`/`.protect`
→ hspice; `//` comments/paren nodes → spectre; etc), overridable with
`--dialect` or a `spicefmt.toml`. A `.scs` file with `simulator lang=spice` /
`simulator lang=spectre` directives gets per-section dialect routing — each
section is parsed under the dialect its directive selects. This is internal to
the tool; the loadout package does nothing special for it.


## yosys 0.68 -- RTL synthesis (EL8 SOURCE build)

**Build:** `build/build-yosys.sh --tag v0.68`
(ISC licence; upstream publishes **source only** -- no prebuilt binaries --
tarball at `https://github.com/YosysHQ/yosys/releases/download/v0.68/yosys.tar.gz`).

Yosys is the standard open-source RTL **synthesis** tool. It complements the
simulators already bundled: `iverilog` (event simulation) and `verilator`
(lint / C++ model generation). Member of the `@eda` group.

### What ships, and the one thing that does not

Shipped: `yosys`, `yosys-abc`, `yosys-config`, `yosys-filterlib`,
`yosys-smtbmc`, plus the `share/yosys/` techlib tree.

**`yosys-witness` is deliberately NOT shipped.** It is a Python script that does
`import click` at module scope, and click is not present on a stock EL8 system
python -- on an air-gapped farm node it cannot even print its help, it dies with
`ModuleNotFoundError`. Shipping a binary guaranteed to crash is worse than
omitting it (the same call this repo makes for `verilator_bin_dbg`). It was
caught by the Tier 3 clean-container gate, not on the dev box. `yosys-smtbmc`
IS shipped and works: it imports only stdlib plus its own siblings `smtio` and
`ywio`. If `yosys-witness` is ever wanted, the fix is to bundle click for the
system python or reroute the script at portable-python -- **not** to relax the
probe.

### Two binaries need probe metadata, and neither is a defect

- **`yosys-abc`** is ABC with its own CLI. It rejects `--version`/`--help` with
  `unknown option` and takes `-c <cmd>`/`-q <cmd>` instead, so its probe is
  `-c quit`, which exits 0.
- **`yosys-filterlib`** has NO zero-exit invocation at all, so it needs an
  `EXPECT_NONZERO` pin: every flag is read as a rules-file *path*, so `--help`
  fails to open it and prints the usage banner (exit 1) -- and that banner is
  what proves the binary ran. **Do not pin the bare invocation instead**: with
  no arguments it reads the liberty file from **stdin**, which yields a
  different message (`No entries found in liberty file.`) and would block on a
  tty.

### EL8 fit: nothing new to bundle

| check | value |
|---|---|
| max glibc symbol | **GLIBC_2.27** (EL8 provides 2.28) |
| max libstdc++ | **GLIBCXX_3.4.22** (EL8 provides 3.4.25) |
| NEEDED | `libdl.so.2`, `libffi.so.6`, `libz.so.1`, `libtcl8.6.so`, `libedit.so.0`, `libpthread.so.0`, `libstdc++.so.6`, `libm.so.6`, `libgcc_s.so.1`, `libc.so.6` -- `libz`/`libtcl8.6`/`libedit` already in `lib64/`, `libffi.so.6` is EL8 base, the rest are glibc/libstdc++/libgcc_s never bundled by policy |
| payload | 76 MB installed -> 69 MB stripped -> **~22.7 MB** bz2 |

C++20 did **not** push GLIBCXX over EL8's ceiling, so no `-static-libstdc++`
trick is needed (verilator needs one; this does not). **Nothing new is
bundled.** Everything else on EL8 already satisfies Yosys: cmake 4.3.2 (needs
3.28), flex 2.6.1 (needs 2.6), python 3.14 (needs 3.7), and gcc-toolset-14 for
the required **C++20**.

### bison is the only gap -- and it is a BUILD-time gap, not a runtime one

Yosys requires bison >= 3.6; EL8 ships **3.0.4**. The build script builds
**bison 3.8.2** into a temp prefix and prepends it to PATH. Stress that bison
is a **build-time tool only -- it generates the parser and is never packaged or
shipped.** Contrast this with OpenROAD, which was scoped and rejected for EL8
because EIGHT of its *runtime* dependencies are below floor (Boost 1.89 vs
EL8's 1.66, CMake 3.31, SWIG 4.3, spdlog 1.15, Eigen 3.4, OR-Tools 9.14, LEMON
1.3.1, CUDD 3.0). A build-time gap is cheap; a runtime dependency stack is a
project.

### Three traps not in any upstream doc

1. **The release tarball extracts FLAT** -- no top-level directory. Extract
   into an empty dir. A `cd $(find -maxdepth 1 -type d | head -1)` after
   extraction lands in a random subdirectory and fails.
2. **v0.68 moved to CMake.** There is no top-level Makefile and the old
   `make config-gcc` incantation is gone. Any older note or blog post saying
   otherwise is stale.
3. **`abc/` is vendored in the tarball** (47 MB). Older Yosys fetched ABC from
   git during the build, which would have made an offline/reproducible build
   much harder. Do not "clean up" by removing it.

### `yosys` relocates; `yosys-config` does not

**`yosys` itself relocates correctly** -- verified by copying the tree, hiding
the original, and synthesizing successfully from the copy. It resolves
`share/yosys` from its own location, so it needs **no wrapper**.

Installed artifacts: `yosys`, `yosys-abc`, `yosys-config`, `yosys-filterlib`,
`yosys-smtbmc`, `yosys-witness`, plus a `share/yosys/` data tree (techlibs).

**`bin/yosys-config` is the exception and needs a repo-owned replacement**
(`build/yosys/yosys-config`), for TWO reasons:

1. upstream generates it with the build prefix baked in at 5+ places, and
2. it reports `--cxx` as `/opt/rh/gcc-toolset-14/root/usr/bin/c++` -- a path
   that exists only on the build box. A user compiling a Yosys plugin on a
   farm node needs their own `g++`, so the replacement reports `${CXX:-g++}`.

This is the same idiom as `build/iverilog/iverilog-vpi` -- a shell script has
no `/proc/self/exe` trick, so it derives its prefix from `$0`.

### Smoke: `-V` is not enough -- SYNTHESIZE from a relocated copy

`yosys -V` prints a version banner from an install whose `share/yosys` techlib
tree is missing, so the packaging smoke actually **SYNTHESIZES**
`build/yosys/smoke.v` (a 4-bit adder) with `write_json` and requires a
non-empty `cells` object back. The build script runs that smoke against a
**RELOCATED copy with the original build prefix moved away** -- running a
copy while the original still exists proves nothing, because a binary that
silently fell back to the build prefix would pass. Note that this exact
false-green is what bit the `iverilog` packaging (see its section).


## iverilog 13.0 -- Icarus Verilog simulator (EL8 SOURCE build)

**Build:** `build/build-iverilog.sh --tag v13_0`
(upstream's tag format uses an underscore: `v13_0`, `v12_0`.)

Unlike verilator, which lints and emits a C++ model you then compile, iverilog
is an event simulator you run directly:
`iverilog -o sim.vvp design.v && ./sim.vvp`. It needs no host `g++` at runtime.

### EL8 fit: nothing new to bundle

| check | value |
|---|---|
| max glibc symbol | **GLIBC_2.14** (EL8 provides 2.28) |
| max libstdc++ | **GLIBCXX_3.4.21** (EL8 provides 3.4.25) |
| NEEDED | `libbz2`, `libz`, `libreadline.so.7`, `libtinfo.so.6` -- all already in `lib64/` -- plus glibc/libstdc++/libgcc_s, never bundled by policy |
| payload | 79 MB built -> 6.3 MB stripped -> **2.3 MB** (bins + 1.9 MB runtime archive) |

The script asserts both floors and the NEEDED allowlist rather than assuming
them.

### The compiled-in prefix WINS when it exists -- this is the whole story

The `iverilog` ELF has its code-generator tree (`<build-prefix>/lib/ivl`)
compiled in, and derives it from its own location **only when that path does
not exist**. So the build prefix wins whenever it is still on disk. That is
build-box masking *in reverse*: a clean farm node is fine, and the developer's
own machine is the one that silently breaks, because `/tmp/iverilog-inst-v13_0`
is still sitting there from the build.

It is not cosmetic. iverilog reads `lib/ivl/vvp.conf` for `VVP_EXECUTABLE` and
writes that into the **shebang** of the compiled `.vvp`. Resolving the wrong
`lib/ivl` means every `./sim.vvp` gets a dead interpreter path.

So `bin/iverilog` is a wrapper (`build/iverilog/iverilog`) that derives its
prefix from `$0` and passes **`-B <prefix>/lib/ivl`**, removing the ambiguity.
An explicit user `-B` still wins.

**`vvp` is deliberately NOT wrapped.** It is the interpreter named in that
shebang, and Linux does not honour a shebang pointing at another script, so
`bin/vvp` must stay a real ELF.

### Relocation: one token, one root

Three files embed the build prefix; the two ELFs do not count because of the
`-B` wrapper above. Handling:

- `bin/iverilog-vpi` -- upstream generates it with the prefix baked into
  `CFLAGS`/`LDFLAGS` and its `--install-dir` output. Replaced with
  `build/iverilog/iverilog-vpi`, a repo-owned wrapper deriving its prefix from
  `$0` (the ngspice / pdftotext idiom). This removes one relocation root.
- `lib/ivl/vvp.conf`, `lib/ivl/vvp-s.conf` -- rewritten at build time to the
  standard `/__LOADOUT_RELOC_ROOT__` token, substituted at install time via
  `relocate_token` + `relocate_root: lib/ivl`. Because those two files are now
  the *only* thing needing it, `relocate_root` stays a single path, which is
  all the installer accepts.

The ELFs keep the **real** build prefix as an unused fallback and must never
contain the token -- `relocate_runtime_token()` hard-errors on a token found in
an ELF, by design. The script asserts that separation explicitly.

### Smoke: three things `-V` cannot see

`build/iverilog/smoke.v` is compiled and run, and the check requires
`SMOKE_OK sum=42 acc=42` plus a non-empty VCD. Critically it runs the generated
file **both** ways:

1. `vvp smoke.vvp` -- explicit interpreter, and
2. `./smoke.vvp` -- **the only thing that exercises the shebang**, i.e. the
   relocated `VVP_EXECUTABLE`. A smoke that only does (1) cannot see the bug
   this package exists to avoid.

The build script runs that twice: once with the build prefix **present** (the
hostile case that catches a missing `-B`) and once with it moved away (what a
farm node looks like). `tests/prebuilt-binaries` runs the direct-execution form
against the installed tree.

Two shell traps hit while writing the script, both worth not repeating:
`sort` collates `vvp.conf` vs `vvp-s.conf` differently by locale, so the token
placement assertion needs `LC_ALL=C` on **both** sides; and a trailing
`[ test ] && { ...; }` as the last command in a `while` body makes the loop
return non-zero on the common case, which `set -e` then treats as a build
failure (and an `exit` inside a piped `while` runs in a subshell and would not
have stopped the script anyway).


## markdown-oxide 0.25.12 -- PKM language server (upstream x86_64 prebuilt)

**Build:** `build/build-markdown-oxide.sh --tag v0.25.12`
(leading `v` -- upstream's convention, unlike lua-language-server above).

### Why this package exists

`envs/nvim/lsp/markdown_oxide.lua` had shipped for some time with
`cmd = { 'markdown-oxide' }` and
`root_markers = { '.git', '.obsidian', '.moxide.toml' }`, but it was **dead for
two independent reasons**, and fixing only one changes nothing:

1. the binary was never in the payload, so `cmd` resolved to nothing; and
2. `envs/nvim/lsp/` is the **entire upstream nvim-lspconfig catalogue** (~300
   files, almost all inert). A file being present there does not enable it --
   only the explicit `vim.lsp.enable({...})` list in
   `envs/nvim/lua/global/init.lua` does, and `markdown_oxide` was not in it.

Both are fixed together: this package supplies the binary, and the enable list
now names `markdown_oxide`. Result: wikilinks, backlinks, daily notes and
unresolved-link creation over a plain directory of markdown, on an EL8 farm
node. User-facing docs are `docs/KNOWLEDGE-BASE.md`.

**`marksman` was removed from that enable list in the same change.** It is also
a markdown language server, and it was the mirror-image bug: *enabled but never
bundled*, so on an offline node nvim tried to spawn a binary that does not exist
and failed silently. Leaving both enabled would attach two servers to every
markdown buffer and double completions and go-to-definition results. Helix has
the same trap -- its built-in default for markdown is also `marksman` -- so
`envs/helix/languages.toml` names `markdown-oxide` explicitly, and listing
`language-servers` there replaces the default list rather than appending to it.

### Why Obsidian itself is NOT bundled, and cannot be

Obsidian's terms grant a **"non-sublicensable, non-transferable"** license to
install and execute it **"on machines operated by or for you"**, and separately
forbid the customer to **"distribute or share the Services or Software or make
any of them available for access by third parties"**. Bundling it into
`payload/` and publishing that as a GitHub release is exactly what those clauses
prohibit. Being free for commercial *use* is not permission to *redistribute*.

For the record, it would otherwise have fit: the main `obsidian` ELF floors at
**GLIBC_2.25** against EL8's 2.28, its bundled `.so`s at 2.17, and a plain
129 MB `tar.gz` exists in the GitHub release (it is not listed on the download
page). Only the `obsidian-cli` helper, at **GLIBC_2.34**, would have been dead on
EL8. So if an enterprise agreement ever permits internal redistribution, the
packaging path is a shanghai of that tarball -- not a research project.

Users install Obsidian themselves, under their own acceptance of its terms, and
point it at their own vault; markdown-oxide indexes that same vault from
nvim/helix. **The vault is org content and never belongs in this repo** -- that
is what the unbundled `corp/`/`site/`/`team/`/`project/`/`user/` layers and
`--post-install-hook` are for. The loadout ships tools and config, not content.

### Not a source build

Upstream ships an x86_64 binary that is already EL8-clean:

| check | value |
|---|---|
| max glibc symbol | **GLIBC_2.18** (EL8 provides 2.28) |
| NEEDED | `libgcc_s`, `librt`, `libpthread`, `libm`, `libdl`, `libc` |

Every NEEDED is glibc or `libgcc_s` -- all on the never-bundle list -- so
**nothing ships alongside it**: no `lib64/` additions, no wrapper, no runtime
archive. It is the cheapest package shape in the repo, a lone `kind: bin`.

The script **asserts** both properties rather than assuming them. A future
release built against a newer toolchain would install cleanly on the dev box and
be dead on a stock farm node -- how `tree-sitter` and `bottom` got rejected. If
the glibc assertion ever fires, this becomes an EL8 Rust source build and needs a
`build/rust-tool-locks.txt` pin so the offline crate store covers it (it has no
pin today, correctly, because nothing is built from source).

### Smoke: `--version` is not enough

`markdown-oxide --version` exits 0 from a binary that cannot resolve a single
wikilink -- the same false-green shape as gtkwave's converters (exit 255 printing
an error, scored OK) and ngspice with a dead datadir (silent). So
`build/markdown-oxide/lsp-smoke.py` drives the real protocol against a two-note
temp vault with an `.obsidian/` root:

```
initialize -> (skip window/logMessage) -> initialized -> didOpen -> textDocument/definition
```

and requires `[[note-b]]` to resolve to `note-b.md`. Two details that bit while
writing it, both fixed and worth not rediscovering: the server emits
`window/logMessage` **before** the initialize result, so the reader must match on
request **id** rather than taking the first message; and the server is spawned
with `cwd=<vault>`, so the binary path must be made **absolute** or a relative
path silently resolves against the temp vault and vanishes. The smoke was
negative-tested against `/bin/cat` (speaks no LSP) and `/bin/true` (exits
immediately); both fail it.


## tree-sitter 0.26.12 -- CLI (EL8 source build, Rust)

**This note exists because the package had none.** tree-sitter was source-built
for 0.26.11 during the 2026-08-04 sweep with no build script and no entry here,
so the procedure existed nowhere at all.

**Build:** `build/build-tree-sitter.sh --tag v0.26.12`
(add `--offline` to prove the shipped crate store can rebuild it with no network)

**Tag carries a leading `v`** -- upstream's convention. The script rejects a bare
version rather than failing obscurely on the clone.

**SOURCE BUILD, and not optional.** Upstream ships a `tree-sitter-linux-x64.gz`
prebuilt, but its glibc floor is far above EL8's 2.28 -- **GLIBC_2.39 at 0.26.11,
GLIBC_2.35 at 0.26.12**. Either would install cleanly on the dev box and be dead
on a stock farm node. That is the build-box masking the floor check exists to
catch, and it is why this must never be "simplified" into a download. The script
re-asserts the floor on every build rather than trusting the toolchain.

**Offline-rebuildable -- and it was NOT, until 2026-08-09.** `tree-sitter` was
absent from `build/rust-tool-locks.txt` entirely, so its Cargo.lock closure was
never folded into the shipped crate store: the tool was bundled but could not
have been rebuilt offline by anyone. It is now pinned there (295 crates in the
store). **If you bump the version here, re-pin it there and rebuild the store**
with `build/build-tool-crate-store.sh`, or `tests/run-all`'s crate-store policy
check fails on the drift -- which is exactly how the stale `uv`/`ty` pins from
v2026.08.07 were caught.

**Nothing bundled.** Rust static-links its own runtime, so the binary NEEDs only
glibc components plus `libgcc_s.so.1`. The script fails on anything else.

**Packaging:** `strip` -> `patchelf --set-rpath` -> `bzip2`, via
`loadout_package_bin`. That order is load-bearing -- never strip after patchelf.

---

## taplo 0.10.0 -- TOML linter + formatter + language server (upstream x86_64 prebuilt)

**Build:** `build/build-taplo.sh --tag 0.10.0`
(**bare version, no leading `v`** -- upstream's CLI-release convention. The
script rejects a `v`-prefixed tag rather than 404-ing obscurely on the download.)

**Refresh the schema cache separately:** `./build/update taplo-schemas`.
The binary and the schemas move on different clocks -- taplo itself is released
roughly yearly, SchemaStore changes weekly.

### What ships

Two payload artifacts, one registry entry (the `st` / `ngspice` shape: a `bin`
package that also carries a runtime archive):

| artifact | what it is |
|---|---|
| `bin/taplo.bin.bz2` | the upstream ELF, stripped |
| `bin/taplo.bz2` | POSIX-sh wrapper, `build/taplo/taplo` |
| `runtime/taplo-schemas.tar.bz2` | 49 JSON schemas + a catalog, ~388 KiB |

`taplo lint`, `taplo format` and `taplo lsp stdio` are one binary, which is why
this single package covers all three of "lint, format, language server".

### NOT a source build -- and the assertion matters

Upstream's `taplo-linux-x86_64.gz` is **static-pie (musl)**: no `NEEDED`
entries at all, no glibc floor to clear, the same shape as the bundled `biome`.
The script does not assume that -- it asserts it, and **fails if a future
release links dynamically**. A glibc build produced by a newer toolchain would
install cleanly on this box and be dead on a stock farm node (the tree-sitter
and bottom rejection, again), and it would also need an RPATH and a bundling
decision that the current packaging path does not make.

Packaging is therefore `strip` -> `bzip2` with **no patchelf** -- `patchelf
--set-rpath` aborts on a binary with no `.dynamic` section, the same reason the
static Go `mlr` is special-cased in `build-prebuilt-bin.sh`.

### The offline schema cache -- the whole point of the wrapper

taplo validates TOML at two independent levels:

* the **grammar**, compiled into the binary, always available; and
* **JSON Schema**, which knows that `[package] nmae = "x"` is a typo in a
  Cargo.toml. Schemas are resolved through a *catalog*, and upstream's default
  catalogs are `schemastore.org` and `taplo.tamasfe.dev`.

On an air-gapped farm node those are dead -- and **a dead catalog does not
error**. taplo quietly drops to grammar-only checking and exits 0 on a file full
of misspelled keys. That silent degrade is the failure class this repo keeps
getting bitten by (gtkwave's converters, ngspice's dead datadir), so the catalog
is vendored and the wrapper points `taplo lint` at it.

Three constraints shape how, and each was found the hard way:

1. **Catalog URLs must be ABSOLUTE `file://`.** A relative URL is rejected
   outright with `data did not match any variant of untagged enum SchemaCatalog`
   -- the catalog schema declares `format: uri`.
2. **Absolute cannot be baked at build time**, because the prefix varies
   (`$HOME/.local`, a `--dest-dir` staging tree, a shared read-only tree). So
   the shipped catalog carries `/__LOADOUT_RELOC_ROOT__` and the installer
   rewrites it, via the same `relocate_token` / `relocate_root` registry fields
   `modules` and `verilator` use.
3. **`taplo lsp stdio` accepts no catalog flag at all**, so the editors cannot
   use the wrapper's mechanism. They pass catalogs as LSP *client settings*
   instead -- see `envs/nvim/lsp/taplo.lua` and `envs/helix/languages.toml`.
   That is a genuinely separate code path, and it is smoke-tested separately.

The wrapper is deliberately narrow: it injects `--schema-catalog` for `lint`
(and its `check`/`validate` aliases) **only**. `taplo format` accepts no schema
options -- passing one is a hard argument error. Any user-supplied
`--schema` / `--schema-catalog` / `--no-schema` / `--default-schema-catalogs`
wins untouched, which is the escape hatch for a networked box that wants live
schemastore. A missing catalog is not an error; taplo then behaves exactly as
the unwrapped upstream binary.

### Which schemas, and why only those

`build/taplo/fetch-schemas.py` filters schemastore's catalog to entries claiming
a `*.toml` file (113 of them) and then keeps only what comes from **one trust
anchor**:

* `https://www.schemastore.org/...` and `https://json.schemastore.org/...`
* `https://raw.githubusercontent.com/SchemaStore/schemastore/...` -- the SAME
  upstream by repo path, and **not a loophole**: pyproject.toml, uv.toml and
  hatch.toml live only under that form and are three of the most valuable
  schemas in the set.
* plus a one-entry allowlist: `starship.rs`, for a tool this repo bundles and
  whose schema it already vendors at `envs/starship/config-schema.json`.

That drops 64 entries across ~20 third-party hosts, most of them
`raw.githubusercontent.com/<user>/<repo>/master` URLs that are mutable by
definition. Vendoring those would mean adopting 20 more upstreams whose bytes
can change under a fixed URL. The skipped hosts are **printed with counts** on
every run, so the exclusion is visible rather than silent. Net result is 49
schemas, 3.6 MiB raw, 388 KiB compressed.

The fetcher refuses to write a cache when fewer than 80% of the planned schemas
download, so a proxy hiccup or a rate limit cannot silently gut the catalog, and
it verifies after tarring that every catalog entry still carries the relocation
token.

### Smoke -- `--version` proves nothing here

`taplo --version` exits 0 from a binary that cannot lint anything, so the build
runs four functional checks, the last two inside a network namespace
(`unshare -Umrn`) where available, so an accidental dependence on schemastore.org
cannot pass on the build box:

1. `format` normalises `a=1` to `a = 1`
2. `lint` rejects a grammatically broken document
3. `lint` rejects an **unknown Cargo.toml key** through a fully staged install
   tree -- wrapper, extracted schema archive, token already rewritten. This is
   the check that catches a catalog shipped with relative URLs. It first asserts
   the fixture is grammatically *valid*, so the test cannot pass for the wrong
   reason.
4. the **LSP** (`build/taplo/lsp-smoke.py`) drives
   `initialize -> didOpen -> textDocument/formatting` plus diagnostics, and with
   a catalog argument also requires the schema diagnostic to arrive over the
   client-settings channel. The whole exchange is capped by `SIGALRM`, because a
   language server that never answers would otherwise wedge a release gate
   forever.

**Watch out when debugging this by hand:** relocating the catalog with
`open(p,"w").write(open(p).read().replace(...))` truncates the file *before*
reading it, leaving an empty catalog and a very confusing
`EOF while parsing a value at line 1 column 0` out of taplo. Read first, write
second.

### Editor wiring

`vim.lsp.enable({...})` in `envs/nvim/lua/global/init.lua` names `taplo`.
`envs/nvim/lsp/tombi.lua` also ships (it is part of the vendored lspconfig
catalogue) and is deliberately **not** enabled -- a second TOML server would
attach to every `.toml` buffer and double completions and diagnostics, exactly
the markdown_oxide/marksman problem. conform formats `toml` with `taplo`.

Helix gets the same server through `envs/helix/languages.toml`, whose catalog
path carries the relocation token and is rewritten by `_install_env_helix()` --
helix's languages.toml is static TOML with no `~` or `$VAR` expansion, so there
is no other way to express an absolute path portably.

## helix (hx) 25.07-984-g079a789e -- modal editor with tree-sitter + LSP (EL8 SOURCE build, Rust)

Build script: `build/build-helix.sh --rev <git-ref>` (or `--source <checkout>`).

### This is the one `--rev` build in the repo. Read this before "fixing" it.

Every other `build-*.sh` requires `--tag vX.Y.Z` and this repo's policy is
stable releases only. helix is a deliberate, documented exception:

* Upstream's newest **release** is `25.07.1`, published **2025-07-18**. Helix
  releases rarely; that tag has been the newest for over a year.
* The config surface `envs/helix/config.toml` depends on **does not exist in
  it**: `[editor.workspace-trust]`, `rainbow-brackets`,
  `[editor.word-completion]`, `auto-document-highlight` and
  `display-progress-messages` are all master-only.
* The binary this replaced was **also a master build** -- `25.07.1 (87d5c05c)`,
  committed 2026-05-03. It entered `payload/` through a bulk snapshot commit
  with no build script, no note here, and no recorded provenance, and
  `packages.json` recorded it as version `25.07.1` as though it were the
  release. This script exists to make that state explicit and reproducible, not
  to introduce it.

**`hx --version` prints the last release tag plus the commit** -- `helix 25.07.1
(079a789e)`. The tag half is not evidence of a release build; the sha is the
only part that identifies what you have. That is precisely how the previous
binary came to be mislabelled, so `build/farm-versions` now captures the whole
string, and `packages.json` carries `git describe` (`25.07-984-g079a789e` --
note master's nearest ancestor tag is `25.07`, not `25.07.1`, which is a patch
release off a side branch).

If upstream ever ships a release carrying the keys above, switch the script back
to `--tag` and delete the exception.

### Prerequisites

```sh
# system gcc (8.5) ONLY -- do NOT enable gcc-toolset-14 for this build.
# Grammars are compiled C/C++; a newer toolset raises the GLIBCXX floor above
# what stock EL8 provides and the .so files die on a farm node.
cargo --version   # 1.96.0 used for this build
```

### Build

```sh
./build/build-helix.sh --rev master
```

What it does, and the three things that are load-bearing:

1. **Fresh `CARGO_HOME`.** The loadout's own `~/.cargo/config.toml` (installed
   by `env-cargo`) replaces crates.io with the offline local-registry store,
   which cannot resolve helix's dependency graph. The script exports a private
   `CARGO_HOME` under its work dir, so the user's offline config is neither used
   nor modified. Same workaround as `build-surfer.sh`.
2. **Full clone, never `--depth 1`.** `git describe --tags` supplies the version
   string; a shallow clone has no tags and the script hard-fails rather than
   stamping something meaningless.
3. **`runtime/grammars/sources/` is excluded from the archive.** That directory
   is the fetched git checkout of every grammar: **2.2 GB** against ~200 MB of
   built `.so`. The script stages only `grammars/*.so`, `queries/`, `themes/`
   and `tutor`, and fails if `sources` leaks into the stage.

Grammars come from `hx --grammar fetch && hx --grammar build` with
`HELIX_RUNTIME` pointed at the source tree. 301 grammars built for this revision
(the previous payload had 291); the script fails below 200, because a partial
grammar set ships an editor with silently dead highlighting for whatever failed.

### Packaging

gvim-style wrapper split:

| artifact | what |
|---|---|
| `bin/hx.bz2` | POSIX-sh wrapper, source at `build/helix/hx` |
| `bin/hx.bin.bz2` | real ELF, stripped, RPATH `$ORIGIN/../lib64:$ORIGIN/../lib` |
| `runtime/helix.tar.bz2` | `./runtime/{grammars/*.so,queries,themes,tutor}` (~20 MB) |

The wrapper exists because helix resolves its runtime relative to the executable
and a compiled-in prefix, neither of which works for a relocatable `$HOME`
install. It derives the prefix from its own installed path and exports
`HELIX_RUNTIME`; an explicit caller value wins.

Nothing is bundled: the ELF floors at **GLIBC_2.28** (exactly EL8) and its
NEEDED set is glibc plus `libgcc_s` -- all on the never-bundle list. The script
asserts both, because a build that picked up a newer toolchain would run fine on
this box and be dead on a stock farm node.

### Smoke -- why `--version` is not enough

`hx --version` exits 0 from a binary that will discard the entire shipped config
and start as stock helix. The real check is **`hx --health` run against this
repo's `envs/helix/{config,languages}.toml`**:

* helix parses `config.toml` with `deny_unknown_fields`. **One** unrecognised
  key makes it throw away the **whole file** and fall back to defaults, printing
  a message that scrolls past at startup. Theme, keymaps, LSP display, workspace
  trust -- all silently gone, editor still starts, still looks fine.
* `--health` **exits 0 on a malformed config**, so the assertion has to be on
  its text (`Configuration file malformed` / `unknown field`), never the status.

This is not hypothetical. Upstream replaced `[editor] insecure` with the
`[editor.workspace-trust]` table between the old bundled build and this one, so
**binary and config must move together in both directions**: a new binary with
the old config, or the old binary with the new config, silently yields a
stock-default helix. `tests/env-helix-config` runs the same assertion against
the payload binary on every Tier 1 run, and carries a negative control that
injects the retired `insecure` key **inside** the existing `[editor]` table --
appending a second `[editor]` table instead would be a TOML *duplicate-table*
error, which helix also calls malformed, so a control written that way passes
while proving nothing about the rename.

The script also runs `hx --health <lang>` for rust/python/toml/markdown/bash and
requires highlight support, which fails if grammars or queries did not land
where the wrapper looks for them.

### Config posture

`envs/helix/config.toml` is deliberately set to **maximum functionality**,
including `[editor.workspace-trust] level = "insecure"`. The reasoning, the cost
on a shared farm filesystem, and the narrower `level = "servers"` alternative
are all recorded in the comment block at the top of that file -- read it there
rather than duplicating it here.

## OpenROAD 26Q3 -- RTL-to-GDS place & route (EL8 SOURCE build, C++20)

Build script: `build/build-openroad.sh --tag 26Q3` (add `--reuse-build` to
re-package an existing build tree without the ~60-90 min rebuild).

Ships `bin/openroad` + `bin/sta` (standalone OpenSTA) and 10 COIN-OR/SCIP
solver libs in `lib64/`. **No wrapper** -- see the Tcl section below for why
that is a deliberate, verified outcome rather than an oversight.

### Ten dependencies are built from source, and that is not gold-plating

Nothing OpenROAD 26Q3 needs exists on EL8 at a usable version: gcc 8.5 (needs
C++20), bison 3.0.4 (needs >= 3.2), swig 3.0.12 (needs >= 4.3), Boost 1.66 with
no CMake config at all, and no OR-Tools whatsoever. Upstream's own
`DependencyInstaller.sh` has a RHEL-8 branch, but its **x86_64 path 404s**: it
downloads a prebuilt or-tools named for the distro, and google/or-tools
publishes an AlmaLinux-8 asset for **aarch64 only**. The aarch64 branch
source-builds instead, and that is the recipe this script follows.

Version pins that are load-bearing, not arbitrary:

| dep | pin | why not the obvious choice |
|---|---|---|
| Boost | **1.87** | not upstream's 1.89 -- OR-Tools compiles its internals against 1.87, and one Boost in the link beats two ODR-conflicting ones |
| yaml-cpp | **0.6.3** | not 0.8.0 -- 0.8 exports only `yaml-cpp::yaml-cpp`, but OpenROAD links the **bare** `yaml-cpp` target, so 0.8 dies at link with `cannot find -lyaml-cpp`. 0.6.3 is what EL8's EPEL ships and what upstream tests |
| lemon | 1.3.1 **+ patch** | hardcodes `CMAKE_POLICY(SET CMP0048 OLD)`; CMake 4 **removed** that policy, so it is a hard error. Deleting the line is safe -- lemon's `project()` passes no VERSION |
| flex | **not needed** | upstream pins 2.6.4, but `find_package(FLEX)` has no `REQUIRED` and the version line is commented out. (flex 2.6.4 also fails to build under GCC 14 -- wasted effort to discover) |
| gtest | 1.17.0 | required even with `-DENABLE_TESTS=OFF` |

Every `cmake` call passes `-DCMAKE_POLICY_VERSION_MINIMUM=3.5`: this box has
CMake 4.x, which hard-refuses projects declaring `cmake_minimum_required < 3.5`,
and several deps still do.

### TRAP 1 -- OR-Tools must be built with STATIC deps

`cmake/dependencies/CMakeLists.txt` **hardcodes** `set(BUILD_SHARED_LIBS ON)`
for its FetchContent deps. It is not an option, and `-DBUILD_SHARED_LIBS=OFF` at
the top level reaches `libortools` but not them. Left alone, `openroad` needs
**111 shared libraries** -- about 100 of them abseil -- none present on EL8.
Patching that one line (plus `protobuf_BUILD_SHARED_LIBS`) drops the closure to
**26 NEEDED, 15 of which are EL8 base**.

`-DBUILD_ZLIB=OFF` does **not** work: it is a `CMAKE_DEPENDENT_OPTION` forced
back ON by `BUILD_DEPS`. It is harmless only because the static build emits
`libz.a` instead of the `libz.so` whose absence broke an earlier link.

The build script asserts the patch applied and that `libortools.a` exists,
because a silent revert here produces a binary that works perfectly on this box
and cannot start anywhere else.

### TRAP 2 -- the Tcl collision (this is the `expect` hazard, same shape)

`openroad` resolves **both** `libpython3.14.so.1.0` and `libtcl8.6.so` out of
portable-python's lib dir. portable-python owns `<prefix>/lib/tcl8.6` at Tcl
**8.6.17**, and its `init.tcl` does `package require -exact Tcl 8.6.17`. EL8's
system Tcl is **8.6.8**. The two therefore cannot be mixed in either direction:

* portable `libtcl8.6` with no matching script tree -> `Can't find a usable
  init.tcl`, having searched the dead compiled-in prefix
  `/opt/cpython3144-portablelib/lib/tcl8.6`;
* system `libtcl8.6` (8.6.8) with the 8.6.17 script tree -> rejected by the
  exact-version check once installed under `~/.local`.

**Resolution: lean INTO portable-python -- and note the RPATH ORDER.** A full
install holds THREE Tcl 8.6 patchlevels:

| path | version | owner |
|---|---|---|
| `lib64/libtcl8.6.so` | 8.6.16 | bundled for `expect` |
| `lib/libtcl8.6.so` | 8.6.17 | portable-python |
| `lib/tcl8.6/` (scripts) | 8.6.17 | portable-python -- the only script tree on the search path |
| `/usr/lib64/libtcl8.6.so` | 8.6.8 | EL8 system |

`init.tcl` does `package require -exact`, so library and script tree must match,
and only the `lib/` pair does. RPATH is therefore
**`$ORIGIN/../lib:$ORIGIN/../lib64` -- lib FIRST**, deliberately the reverse of
this repo's usual pair. With the usual order the 8.6.16 copy wins and openroad
dies with `Can't find a usable init.tcl`.

**This shipped past a green dev-box smoke and was caught only by the clean
container.** The build script had smoked the BUILD-TREE binary, whose RUNPATH
pointed straight at portable-python's lib dir, rather than the PACKAGED binary,
whose RPATH did not -- it passed for a reason unrelated to what ships. The smoke
now runs after packaging, on the decompressed payload `.bz2` artifacts in a
staged install tree, and fails specifically on `init.tcl` naming the RPATH
order. Verified with **no wrapper and no `TCL_LIBRARY` export**, so this repo's
standing rule against exporting it (see `expect`) survives intact. **Do not
"fix" a future Tcl failure by adding either** -- fix the portable-python depend
or the RPATH order.

### TRAP 3 -- `openroad -version` proves nothing

It prints `26Q3` from a binary that cannot load Tcl, cannot read a LEF, and
would fail on the first real command -- exactly the state trap 2 produces. Both
`build-openroad.sh` and `tests/prebuilt-binaries` instead read a real LEF + DEF
(`build/openroad/gscl45nm.lef`, `design.def`, BSD-3-Clause, from upstream's odb
test data) and require the resulting database to report **12 instances / 24
nets** through the Tcl API. The test also fails specifically on `init.tcl`
appearing in the output, so a Tcl regression is named rather than showing up as
a generic mismatch.

### Floors

`-static-libstdc++ -static-libgcc` is mandatory: gcc-toolset-14 is required for
C++20, and without them the binary requires `GLIBCXX` symbols newer than stock
EL8's 3.4.25 -- and would still run fine on this build box. The script asserts
**zero** `GLIBCXX` symbols and a glibc floor at or under 2.28 (currently
`GLIBC_2.27`). Same build-box-masking class as the firefox/NSS and octave
support-lib incidents.

### Not built

`-DBUILD_GUI=OFF` for now. The only blocker is Qt5Charts, and it is cheap: EPEL
ships `qt5-qtcharts 5.15.3-1.el8`, an exact match for the Qt5 already in
`gui_libs`. `find_package(Qt5 ... Charts)` in `src/gui` is QUIET, and
`BUILD_GUI` is a normal option, so enabling it later is additive.

OpenROAD-flow-scripts (ORFS) is a scripts + PDK layer **on top of** this binary;
it changes nothing here and only decides whether the PDK data also ships.

## sqlite 3.53.4 -- SQLite CLI + libsqlite3 (EL8 SOURCE build, C)

Date: 2026-08-22. Build: `./build/build-sqlite.sh --tag 3.53.4` (needs
`readline-devel` + `ncurses-devel` on the host for configure's auto-detect).
Payload:
`payload/el8.x86_64.glibc2p28/bin/sqlite3.bz2` (~928K) and
`payload/el8.x86_64.glibc2p28/lib64/libsqlite3.so.0.bz2` (~752K).

### Why

EL8 ships sqlite 3.26 from 2018. The CLI is the product; `libsqlite3.so.0`
ships with it because the shell links it dynamically, and future packages can
NEEDED against it for free.

### Readline: no NEW dependency, by design

`--enable-readline` is the upstream default and was kept ON. The NEEDED pair
`libreadline.so.7` + `libtinfo.so.6` (+ `libncurses.so.6`) is ALREADY shipped
in payload lib64/ as UNREGISTERED stems -- the installer's rule is "unclaimed
lib64 stem = installed with EVERY selection" (`_lib_selected` in
loadout_main.py), so the binary's RPATH `$ORIGIN/../lib64` resolves them on
any loadout host even though nothing declares an owner. gnuplot / ngspice /
octave / vvp already rely on exactly these libs. Do not read the missing
registry entry as a missing library.

### Extensions: `--all`

Upstream's own bundle (fts4 fts5 rtree geopoly session dbpage dbstat carray).
EL8's system build ships fts5+rtree; shipping a CLI that rejected
`USING fts5` would be a silent regression versus any distro from the last
decade.

### Version encoding trap

sqlite.org tarballs are named `sqlite-autoconf-<N>.tar.gz`, where N encodes
3.X.Y as `3XXYY00` (branch releases 3.X.Y.Z -> `3XXYYZZ`). The build script
derives N from --tag and cross-checks it against the download page's
machine-readable CSV comment (`PRODUCT,<version>,<relative-url>,<size>,<sha3>`),
which also supplies the year-scoped relative URL
(`https://www.sqlite.org/<year>/...`) and the SHA3-256 used for verification.
The CSV row is matched on `<name>.tar.gz,` -- never `,<name>.tar.gz`: the
leading character is the `/` of the year dir.

### Smoke tests that actually bite (house rule: --version proves nothing)

1. insert/select roundtrip on a temp db;
2. fts5 + rtree probes (catches `--all` silently not taking);
3. session changeset capture -- three separate traps, all hit during the first
   bring-up:
   - `.session open` takes an OPEN DATABASE ALIAS (`main`), NOT a filename;
     a filename silently opens a second connection whose writes are never
     recorded, yielding an EMPTY changeset with zero diagnostics;
   - tracked tables need a PRIMARY KEY -- rowid-only tables are silently
     skipped;
   - under `set -e`, an unguarded `printf | sqlite3` pipeline dies silently
     on nonzero exit before reaching the error handlers.
4. readline assertion: configure falls back SILENTLY to no-readline when the
   devel headers are absent; the script hard-fails unless `libreadline.so*`
   appears in NEEDED.

### Packaging notes

strip -> patchelf (`$ORIGIN/../lib64` for the binary, `$ORIGIN` for the lib)
-> bzip2, per repo invariant. The SONAME file ships under its soname
(`libsqlite3.so.0`), not the upstream real name (`libsqlite3.so.3.53.4`);
the linker-name `libsqlite3.so` is deliberately NOT shipped -- add it only if
an offline source build ever needs to compile against this copy.
Registry currency scrapes `SQLite version X.Y.Z` from the download page.

## pyright 1.1.411 -- Python LSP (upstream npm package, pure Node runtime archive)

Date: 2026-08-22. Build: `./build/build-pyright.sh --tag 1.1.411`.
Payload: `payload/el8.x86_64.glibc2p28/runtime/pyright.tar.bz2` (~3.0M).
Registry shape mirrors the nodejs entry: kind bin + `archive` +
`sentinel bin/pyright` + `install_to ~/.local`, hard `depends [nodejs]`.

### Why the PyPI wheel was retired (the offline bug, load-bearing)

The PyPI `pyright` wheel is a PYTHON WRAPPER around the same JS. It bundles
the npm dist (no pyright download at runtime) but resolves NODE at runtime:
(1) `nodejs-wheel-binaries` pkg (never shipped), (2) global `node` on PATH,
(3) fallback `_ensure_node_env()` -> **nodeenv downloads a Node tarball from
nodejs.org**. Air-gapped box + no `~/.local/bin/node` on PATH = dead, with a
confusing network error. Worse, the failure is masked on any box where the
bashrc put bundled node on PATH -- build-box masking in env-var form.

The new archive removes both Python and the resolution logic: sh wrappers
exec `$PREFIX/bin/node` by ABSOLUTE PATH derived from the wrapper location.
No PATH setup needed (GUI-launched nvim included), no network, no python.

### Packaging notes

- The archive tree must be PURE JS/data; the build script asserts no ELF
  bytes (`od -An -tx1` matching `7f 45 4c 46` -- grep does not interpret
  `\x7f` escapes, and `find -exec` exit status does not reflect per-file
  matches; both were bugs in the first draft of this guard).
- Integrity: verified against the registry metadata's
  `dist.integrity = sha512-<base64>` via `openssl dgst -sha512 -binary |
  openssl base64 -A`.
- Stage-verify needs a node at `$STAGE/bin/node` for the absolute-path
  wrapper to exec; the script symlinks one in and REMOVES it before tar so
  it never reaches the payload.
- typeshed-fallback rides along inside dist/ (asserted); without it pyright
  reports bogus stdlib errors.
- Upgraded installs keep stale uv shims `pyright-python` /
  `pyright-python-langserver`; `remove_stale_pyright_python_shims`
  (loadout_main.py, called from install_runtime_archives) deletes them,
  content-gated on referencing this install's `uv/tools/pyright` venv so an
  unrelated user file of the same name is never touched.
- Old wheels removed from the wheelhouse: pyright-1.1.40x, nodeenv-1.10.0.

## typescript-language-server 6.0.0 -- TypeScript/JavaScript LSP (upstream npm package, pure Node runtime archive)

Date: 2026-08-27. Build:
`./build/build-typescript-language-server.sh --tag 6.0.0 --typescript-tag 6.0.3`.
Payload:
`payload/el8.x86_64.glibc2p28/runtime/typescript-language-server.tar.bz2`.

Registry shape: `kind: bin`, `bins: [typescript-language-server]`,
`archive runtime/typescript-language-server.tar.bz2`, `sentinel
bin/typescript-language-server`, `install_to ~/.local`, hard `depends
[nodejs]`. It is also a member of `@dev-tools`; `@engineering-loadout` reaches
it through the normal `@shared` sweep.

Why a runtime archive: `typescript-language-server` is only the LSP shim. It
wraps `tsserver`, which comes from the separate `typescript` npm package.
Upstream's current install guidance is `npm install -g
typescript-language-server typescript@6`, so the loadout archive carries both
npm tarballs. The server wrapper execs `$PREFIX/bin/node` by absolute path and
therefore works from GUI-launched nvim and env-only shells without relying on
PATH or npm.

Build-script invariants:

- Fetch `typescript-language-server@$TAG` and `typescript@$TYPESCRIPT_TAG`
  from `registry.npmjs.org`.
- Verify npm `dist.integrity` SHA-512 before extracting either tarball.
- Reject any ELF file in the npm packages; pure JS/data only.
- Stage packages under `lib/node_modules/{typescript-language-server,typescript}`.
- Stage only the `typescript-language-server` user-visible wrapper. Do not
  expose `tsc`/`tsserver` unless a separate package decision is made; the
  bundled TypeScript exists to satisfy the language server offline.
- Smoke `typescript-language-server --version`, `typescript/lib/tsc.js
  --version`, and a minimal stdio LSP initialize/shutdown session before
  writing the archive.

Nvim integration: `envs/nvim/lua/global/init.lua` now enables `ts_ls` by
default, guarded by `vim.fn.executable("typescript-language-server")` through
the shared optional-LSP guard. This keeps env-only installs silent until the
package is installed, then enables JS/TS buffers without user config.

## valgrind 3.27.1 -- memcheck/cachegrind/callgrind bundle (EL8 SOURCE build, C)

Date: 2026-08-23. Build: `./build/build-valgrind.sh --tag 3.27.1`.
Payload: `payload/el8.x86_64.glibc2p28/runtime/valgrind.tar.bz2` (~70MB,
extracts to ~108MB).

Upstream ships signed tarballs at sourceware.org/pub/valgrind/. No per-file
sidecar hash; build script prints the sha256 it computed.

### Why from source (not a shanghai of EL8's 3.22.0)

EL8 ships 3.22.0 (2022). 3.27.1 is current stable and carries AVX-512
handling improvements that matter on modern Xeon/EPYC, plus six releases of
bug fixes. Valgrind is **pure userspace** (NEEDED = glibc only), so there is
no kernel-ABI coupling like `perf` has, and bundling is unambiguous.

### Layout after install (prefix ~/.local)

- `bin/valgrind` -- thin wrapper exporting `VALGRIND_LIB=<prefix>/libexec/valgrind`
  then exec'ing the real dispatcher.
- `libexec/valgrind/valgrind` -- upstream's real ELF dispatcher (3.27.x
  moved it from being a shell script to a compiled binary; it resolves
  tools via `VALGRIND_LIB`).
- `libexec/valgrind/{memcheck,cachegrind,callgrind,helgrind,...}-amd64-linux`
  -- tool binaries, stripped.
- `libexec/valgrind/*.xml` -- register descriptions (load-bearing; some code
  paths die at trace time without them, not startup).
- `libexec/valgrind/default.supp` -- default suppressions.
- `lib/valgrind/*.a` -- static libs, shipped for completeness.
- `share/valgrind/` -- docs.

### Traps (all hit during development)

1. **Layout changed in 3.27.x**: tools moved from `lib/valgrind/` to
   `libexec/valgrind/`. Configure's `pkglibdir` output is unreliable; the
   installed tree is the truth. Build script uses `libexec/` and asserts
   `memcheck-amd64-linux`, `default.supp`, and XMLs are all present.
2. **`--version` proves nothing** here either: valgrind can report its
   version and still fail to find memcheck. The stage-verify compiles a
   10-line C program with a deliberate `malloc(16)` leak, runs memcheck
   with `--error-exitcode=42`, and requires BOTH exit 42 AND the string
   "definitely lost: 16 bytes" in the log.
3. **NEEDED must be glibc only**. Valgrind's tool binaries are effectively
   self-contained; any NEEDED on libdw/libelf/libcap/etc. indicates the
   build box's devel headers leaked in, and the artifact is dead on a
   clean farm node. The check pattern-matches against el8's base set.
4. **glibc floor is 2.14** -- valgrind is extremely conservative; EL8's
   2.28 has ample headroom.

### perf is deliberately NOT bundled

The request that surfaced Valgrind also mentioned `perf`. `perf` is a
kernel-ABI-tied tool (matches the exact kernel, and its NEEDED
list includes libpython3.6m). This loadout cannot bundle a perf binary
that is correct on both EL8 farm nodes (kernel 4.18) and this dev box
(WSL2 kernel 6.18). Policy: use the system perf matching your kernel.
Documented in README.

---

## tclint 0.9.0 -- Tcl linter, formatter, and language server (pure-Python wheel)

**Tool:** tclint -- modern dev tools for Tcl
**Version:** 0.9.0 (latest stable; zero-ver project, https://0ver.org/)
**Source:** https://github.com/nmoroze/tclint (MIT)
**PyPI:** https://pypi.org/project/tclint/

tclint is a pure-Python package (`py3-none-any` wheel) installed via the
loadout's `uv tool` mechanism (the same path as visidata, ipython, etc.).
No source build, no ELF, no patchelf, no bundled libs. Three launchers are
produced in isolated venvs: `tclint` (linter), `tclfmt` (formatter), and
`tclsp` (language server for editor integration).

### Why a python-tool, not a bin

The wheel is pure Python and `requires-python >= 3.10`, so the loadout's
bundled Python 3.14 drives it. The `uv tool install` path gives isolated
venvs (one per tool), so tclint's deps cannot collide with another
python-tool's pins. The launcher shims resolve the interpreter by absolute
path, so `tclsp` starts under headless nvim and from GUI-launched editors
without PATH.

### Dependencies (the wheel closure)

Direct deps from `pyproject.toml` (pinned `==` / `~=`, so deterministic):

| package | version | note |
|---|---|---|
| ply | 3.11 | PEG parser engine |
| pathspec | 0.11.2 | gitignore-style file matching |
| importlib-metadata | 6.8.0 | entry-point discovery (backport) |
| pygls | 1.3.1 | the LSP framework tclsp is built on |
| voluptuous | 0.15.2 | config schema validation |

Transitive (pulled by pygls/lsprotocol/importlib-metadata):

| package | version |
|---|---|
| lsprotocol | 2023.0.1 |
| cattrs | 26.1.0 |
| zipp | 4.1.0 |

`attrs` and `typing-extensions` are already in the wheelhouse (shared by
many tools). `tomli` is conditional on `python_version < '3.11'` and is
therefore NOT needed for 3.14 (the stdlib `tomllib` covers it).

### Download (the manylinux tag matters)

```bash
PIP_REQUIRE_VIRTUALENV=0 ~/.local/bin/python3.14 -m pip download tclint==0.9.0 \
  --platform manylinux_2_28_x86_64 \
  --platform manylinux2010_x86_64 \
  --platform manylinux2014_x86_64 \
  --platform manylinux1_x86_64 \
  --platform any \
  --python-version 3.14 \
  --only-binary :all: \
  -d payload/el8.x86_64.glibc2p28/wheels/
```

All wheels are `py3-none-any` (pure Python), so the platform tags are
belt-and-suspenders; the `any` tag is what actually matches. Per the
ADDING_BINARIES wheel-download rule, pass EVERY acceptable platform tag --
pip matches tags EXACTLY with no downward implication, and a single-tag
mistake can misdiagnose a wheel as absent.

### Registry entry

`kind: python-tool`, `uv_tool: tclint`, `depends: [portable-python, uv]`.
The `wheels` list is the FULL closure (tclint + 8 deps); the installer
matches each by normalized name (hyphens -> underscores) so
`importlib-metadata` resolves `importlib_metadata-*.whl`. Member of
`@dev-tools` (next to ruff, ty, taplo, shellcheck, stylua). Version
discovery is automatic via `check-versions` (PyPI JSON keyed on
`uv_tool`); no `version_url`/`version_pattern` needed.

### Editor integration (tclsp)

`tclsp` is a stdio LSP server (no args beyond `-l <log-level>`). It covers
`.tcl` and the EDA constraint dialects `.sdc`/`.xdc`/`.upf`. Wired into both
bundled editors:

- **nvim:** `envs/nvim/lsp/tclsp.lua` (new) -- `cmd = { "tclsp" }`,
  `filetypes = { "tcl", "sdc" }` (nvim maps `.sdc` to its own filetype),
  `single_file_support = true`. Added to the `vim.lsp.enable({...})` list
  in `envs/nvim/lua/global/init.lua`.
- **helix:** `envs/helix/languages.toml` -- a `[language-server.tclsp]`
  block and a `[[language]] name = "tcl" language-servers = ["tclsp"]`
  entry. Helix has a built-in `tcl` language (tree-sitter grammar + queries)
  but no language server, so this ADDS one rather than replacing a default.

`tclsp` has no `--version` flag (it is an LSP server, not a CLI), so the
release smoke probes `tclint` itself (the linter) rather than `tclsp`.
`tests/prebuilt-binaries` drives `tclint` against a file with a known
violation and requires the violation to be reported -- a checker that
silently passes everything would sail through a version probe.

### Farm-versions

```python
("tclint", "tclint", "https://github.com/nmoroze/tclint",
 strategy_flag(["--version"], r"tclint ([0-9]+\.[0-9]+\.[0-9]+)")),
```

`tclint --version` prints `tclint 0.9.0`. `tclfmt --version` prints the
same; `tclsp` rejects `--version` (it is a server).

### Smoke (functional, not --version)

```bash
# Lint a file with a known violation -- a checker that silently passes
# everything would sail through a --version probe.
printf 'if { [expr {$x > 10}] } { puts $x is greater than 10! }\n' > /tmp/t.tcl
tclint /tmp/t.tcl                        # exits nonzero, prints violations
tclint /tmp/t.tcl; echo "rc=$?"          # rc=1 (violations found)
# Clean file exits 0:
printf 'puts "hello"\n' > /tmp/clean.tcl
tclint /tmp/clean.tcl; echo "rc=$?"      # rc=0
# Formatter round-trip:
tclfmt /tmp/t.tcl > /tmp/fmt.tcl
```

### Install

```bash
./loadout install tclint
```

Installs `tclint`, `tclfmt`, `tclsp` launchers to `~/.local/bin/` (via the
isolated venv at `~/.local/share/uv/tools/tclint/`). Also pulled by
`@dev-tools` and the full `@engineering-loadout` bundle.

### Updating

```bash
# Bump version in packages.json, re-download the wheel closure, run the
# post-payload chain (strip is a no-op for wheels -- pure Python -- but
# sizes + manifest must regenerate because the wheelhouse changed):
PIP_REQUIRE_VIRTUALENV=0 ~/.local/bin/python3.14 -m pip download tclint==<NEW> \
  --platform manylinux_2_28_x86_64 --platform manylinux2010_x86_64 \
  --platform manylinux2014_x86_64 --platform manylinux1_x86_64 --platform any \
  --python-version 3.14 --only-binary :all: \
  -d payload/el8.x86_64.glibc2p28/wheels/
# prune old tclint-*.whl + any stale dep wheels no longer in the closure
# stamp packages.json version -> run gen-installed-sizes -> gen-content-manifest
```

---

## OpenVAF 23.5.0 -- Verilog-A compiler (Rust + LLVM, EL8 SOURCE build)

**Tool:** OpenVAF -- Verilog-A compiler for circuit simulators
**Version:** 23.5.0 (latest stable; tag `OpenVAF-v23.5.0`)
**Source:** https://github.com/pascalkuthe/OpenVAF (GPL-3.0)
**Build script:** `build/build-openvaf.sh --tag OpenVAF-v23.5.0`

OpenVAF compiles Verilog-A compact model files to OSDI shared objects usable
by circuit simulators (ngspice with the OSDI prototype, Melange). It is a Rust
project that links LLVM statically at build time, producing a single
self-contained binary with only glibc + libstdc++ + libgcc_s NEEDED at runtime
-- no bundled libs, no runtime LLVM dep.

### The LLVM version constraint (why a prebuilt LLVM 15 is required)

OpenVAF 23.5.0 targets **LLVM 13-15**. LLVM 16 removed
`llvm/Transforms/IPO/PassManagerBuilder.h` and the corresponding legacy pass
manager C API (`LLVMPassManagerBuilder*`), which OpenVAF's `openvaf/llvm/`
FFI wrapper uses. The build box's `/usr/local` LLVM is version 23 (far too
new), and EL8's `llvm-compat-devel` only goes back to 17 (also too new).

The resolution is upstream's own **prebuilt LLVM 15.0.7** tarball
(`https://openva.fra1.cdn.digitaloceanspaces.com/llvm-15.0.7-x86_64-unknown-linux-gnu-FULL.tar.zst`),
which is built on CentOS 7 and runs on any Linux. The build script fetches it
once to `/tmp/llvm-15.0.7-openvaf/` and points `LLVM_CONFIG` + `LIBCLANG_PATH`
+ `PATH` at it. Static linking means the resulting binary has **zero LLVM
NEEDED** -- the prebuilt LLVM is a build-time-only tool, never shipped.

### Two patches required (both applied by the build script)

**Patch 1: `openvaf/llvm/build.rs` -- robust version parsing.**
The build script's version parser does `version.split('.')` and `parse()` on
each component. Our prebuilt LLVM reports `15.0.7` cleanly, but the build
box `/usr/local` LLVM reports `23.0.0git` and the `git` suffix fails
`u32::parse()`. The patch strips non-numeric characters from the patch
component before parsing:
```rust
// Before:
let patch: Result<u32, _> = patch.parse();
// After:
let patch: Result<u32, _> = patch.chars().take_while(|c| c.is_ascii_digit()).collect::<String>().parse();
```

**Patch 2: `openvaf/osdi/stdlib.c` -- NO_STD function declarations.**
This file compiles with `-DNO_STD` (no standard headers) but calls `strlen`,
`malloc`, `memcpy`, `strcmp`, `realloc`, `log`. Older clang tolerated
implicit declarations; clang 15 (from the prebuilt LLVM) in C99 mode rejects
them as errors. The patch adds `extern` declarations for the six functions
inside the `#ifdef NO_STD` block.

Both patches are applied idempotently (grep before apply) so `--reuse-build`
works. If upstream fixes either, the patch is silently skipped.

### Prerequisites

```bash
source /opt/rh/gcc-toolset-14/enable
# cargo 1.64+ (the loadout's 1.96 works), zstd to decompress the LLVM tarball
# The build script fetches the prebuilt LLVM 15 automatically on first run.
```

### Build

```bash
./build/build-openvaf.sh --tag OpenVAF-v23.5.0
./build/build-openvaf.sh --tag OpenVAF-v23.5.0 --reuse-build   # skip cargo build if tree exists
```

The build takes ~30s with warm deps, ~10 min cold. The release profile has
`debug = true` (for good backtraces), so the unstripped binary is ~230 MB;
after stripping it is ~58 MB.

### Runtime library requirements

| Library | Source | Notes |
|---------|--------|-------|
| `libstdc++.so.6` | EL8 system | Never bundle (per policy); GLIBCXX_3.4 floor |
| `libgcc_s.so.1` | EL8 system | Never bundle (per policy) |
| `libdl.so.2` | EL8 glibc | Always available |
| `libpthread.so.0` | EL8 glibc | Always available |
| `libm.so.6` | EL8 glibc | Always available |
| `libc.so.6` | EL8 glibc | Always available |

No bundled libs. Max glibc symbol: **GLIBC_2.28** (at the EL8 floor exactly).
Max C++ ABI: **GLIBCXX_3.4** (GCC 3.4 era -- no newer-than-EL8 concern).

### Packaging

`strip` -> `patchelf --set-rpath '$ORIGIN/../lib64:$ORIGIN/../lib'` ->
`bzip2` -> `payload/el8.x86_64.glibc2p28/bin/openvaf.bz2`.

RPATH is harmless (no bundled libs to find), set for consistency with the
repo convention. The `loadout_package_bin` helper in `build/lib.sh` handles
the strip -> patchelf -> bzip2 chain.

### Smoke test (functional, not --version)

`--version` prints `openvaf 23.5.0` but proves nothing about compilation. The
build script compiles `integration_tests/CURRENT_SOURCE/current_source.va`
(a simple ideal current source) and asserts a valid OSDI shared object is
produced:
```bash
openvaf integration_tests/CURRENT_SOURCE/current_source.va
# must produce integration_tests/CURRENT_SOURCE/current_source.osdi (ELF shared object)
```

### Install

```bash
./loadout install openvaf
```

Installs `openvaf` to `~/.local/bin/`. Member of `@eda` (alongside openroad,
iverilog, gtkwave, klayout, verilator, yosys). Also swept into the full
`@engineering-loadout` bundle via the `all` synthetic group.

### Updating

```bash
./build/build-openvaf.sh --tag OpenVAF-v<NEW>
# The script re-fetches the prebuilt LLVM 15 if /tmp/llvm-15.0.7-openvaf is gone.
# Run the post-payload chain after:
./build/strip-all-elf-binaries
python3.14 build/gen-installed-sizes
python3.14 build/gen-content-manifest
```

If a future OpenVAF release drops the legacy pass manager (migrating to the
new LLVM pass manager), the LLVM version constraint loosens and the prebuilt
LLVM 15 fetch can be dropped. Check `openvaf/llvm/wrapper/OpenVafWrapper.cpp`
for `PassManagerBuilder.h` -- if the include is gone, LLVM 16+ is fine.

## GUI wrapper env block (shared, for any bundled GUI launcher)

`build/gui-wrapper-env.sh` is the single source of truth for the
env-adaptation every GUI wrapper needs (host-GL probe + platform-gated
Mesa/GLVND fallback + host-fontconfig LD_PRELOAD + the
LOADOUT_GUI_HOST_GL / LOADOUT_GUI_HOST_FONTCONFIG / LOADOUT_GUI_LIB64
knobs). Consume it by INLINING at build time -- the installed wrapper
must stay a self-contained script with no repo dependency:

```sh
GUI_ENV_BLOCK="$(cd "$(dirname "$0")" && pwd)/gui-wrapper-env.sh"
cat > "$stage/yourtool" <<'HDR'
#!/bin/sh
# ... header comment ...
bin_dir=$(CDPATH= cd "$(dirname "$0")" && pwd -P) || exit 1
prefix=$(CDPATH= cd "$bin_dir/.." && pwd -P) || exit 1
HDR
cat "$GUI_ENV_BLOCK" >> "$stage/yourtool"
cat >> "$stage/yourtool" <<'FTR'

exec "$real_binary" "$@"
FTR
```

The block requires $prefix set beforehand and never tramples
caller-set values. Rationale + failure catalogue: see the block's own
header comment and the AGENTS.md GUI WRAPPER SHARED BLOCK paragraph.
Users of it today: build-wezterm.sh (3 wrappers), build-surfer.sh.
