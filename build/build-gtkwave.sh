#!/bin/sh
# Build GTKWave (electronic waveform viewer) from source for el8.x86_64.glibc2p28.
#
# GTKWave is the incumbent open-source VCD/FST/LXT2/VZT waveform viewer. It is
# bundled alongside surfer (modern Rust/egui viewer) because essentially every
# existing regression script, Makefile and flow wrapper in industry invokes
# `gtkwave` by name, and because the format-converter suite (fst2vcd, vcd2fst,
# vcd2vzt, ...) is used headless in batch flows independent of the GUI.
#
# WHICH TREE: the repo has two build trees. `gtkwave3/` is the GTK2 build and
# `gtkwave3-gtk3/` is the GTK3 build -- we build the latter, against the GTK3
# 3.22 stack already bundled in gui_libs. The repo's `master` branch is the
# GTK4 rewrite (gtkwave 4.x): it has NO stable tag (nightly only), and GTK4 is
# not in gui_libs, so it is out of scope under the stable-release policy.
#
# GUI LAUNCHERS (env adaptation only): the three interactive frontends
# (gtkwave, twinwave, rtlbrowse) ship as sh launchers over sibling .bin
# ELFs. The launchers embed NO paths (everything derives from $0) -- the
# no-prefix invariant below still holds and is still enforced; what changed
# is that newer hosts need env adaptation the ELFs cannot do themselves.
# Each launcher inlines two shared blocks (installed wrappers stay
# self-contained): build/gui-wrapper-env.sh (host-GL probe + host-fontconfig
# preload) and build/gtk3-launcher-env.sh (Wayland-session GDK_BACKEND=x11 +
# GIO module suppression -- EL8-era gdk aborts on newer GNOME otherwise).
# EL8/X11 sessions take neither branch. The 13 converters stay bare ELFs.
#
# KNOWN LIMITATION -- Tcl scripting is disabled (--disable-tcl). GTKWave's Tcl
# layer (`gtkwave -S script.tcl`, the `gtkwave::` command set) would link
# system Tcl 8.6 and then need a Tcl script library (init.tcl) at run time.
# The loadout already owns <prefix>/lib/tcl8.6 for portable-python at a
# different Tcl patchlevel, and Tcl's init.tcl does `package require -exact`,
# so a second tcl8.6 script library in that tree breaks one side or the other
# (this is the same hazard documented for `expect` in ADDING_BINARIES.md).
# Enabling it later means giving GTKWave a private script-library prefix, the
# way build/build-expect.sh does. Without it, `gtkwave -S` fails loudly with an
# unrecognized-option error -- it does not silently ignore the script.
#
# Runtime library requirements:
#   GTK3 / cairo / pango / glib / X11 / Wayland  -- bundled (gui_libs)
#   libbz2.so.1, libz.so.1, libpcre.so.1         -- bundled (payload lib64)
#   liblzma.so.5                                 -- EL8 system (xz-libs). NOT
#     bundled: rpm's own librpmio links it, so it is present on every EL8 node,
#     including a minimal install. Same class as libsqlite3 / libgnutls.
#   libstdc++.so.6, libgcc_s.so.1, glibc         -- system, never bundled
# Everything else in the ldd closure (systemd, selinux, gnutls, blkid, mount,
# lz4, gcrypt, ...) arrives transitively through the glib/gio already shipped
# by gui_libs, so gtkwave adds no new system assumption beyond liblzma.
#
# Prerequisites on the build machine (EL8):
#   dnf install gtk3-devel glib2-devel bzip2-devel xz-devel zlib-devel \
#               gperf flex bison make gcc
#   NOTE: gperf is a hard configure error even though configure.ac says it is
#   "only needed if the user updates the gperf data".
#
# Policy: always build from a stable tagged release.
#
# Usage (run from any directory):
#   ./build/build-gtkwave.sh --tag v3.3.116

set -eu

REPO="$(cd "$(dirname "$0")/.." && pwd)"
PLATFORM_DIR="$REPO/payload/el8.x86_64.glibc2p28"
BIN_DIR="$PLATFORM_DIR/bin"
RUNTIME_DIR="$PLATFORM_DIR/runtime"
PATCHELF="${HOME}/.local/bin/patchelf"
TAG=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        --tag)
            shift
            [ "$#" -gt 0 ] || { echo "missing value for --tag" >&2; exit 2; }
            TAG="$1"
            ;;
        -h|--help)
            sed -n '2,/^$/p' "$0"
            exit 0
            ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done

if [ -z "$TAG" ]; then
    echo "ERROR: --tag is required. Specify a stable release tag, e.g.:" >&2
    echo "  $0 --tag v3.3.116" >&2
    echo "" >&2
    echo "Stable releases: https://github.com/gtkwave/gtkwave/tags" >&2
    echo "" >&2
    echo "Policy: this project ships stable releases only. Note that 'master'" >&2
    echo "is the unreleased GTK4 rewrite and has no stable tag." >&2
    exit 1
fi

case "$TAG" in
    v3.3.*) ;;
    *)
        echo "ERROR: expected a v3.3.x tag (the GTK3 line), got: $TAG" >&2
        echo "The 4.x GTK4 rewrite is unreleased and GTK4 is not in gui_libs." >&2
        exit 1
        ;;
esac

VERSION="${TAG#v}"

# The binaries this package owns. Enumerated rather than globbed so that an
# upstream change to the tool set is a build failure, not a silent payload diff.
EXPECTED_BINS="evcd2vcd fst2vcd fstminer gtkwave lxt2miner lxt2vcd rtlbrowse shmidcat twinwave vcd2fst vcd2lxt vcd2lxt2 vcd2vzt vzt2vcd vztminer xml2stems"
NUM_BINS=16

if [ -r /opt/rh/gcc-toolset-14/enable ]; then
    # shellcheck disable=SC1091
    . /opt/rh/gcc-toolset-14/enable
fi

need() {
    command -v "$1" >/dev/null 2>&1 || {
        printf 'missing required command: %s\n' "$1" >&2
        exit 1
    }
}

need gcc
need make
need git
need gperf
need flex
need bison
need pkg-config
need "$PATCHELF"

pkg-config --exists gtk+-3.0 || {
    echo "ERROR: gtk+-3.0 not found by pkg-config -- dnf install gtk3-devel" >&2
    exit 1
}

WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/build-gtkwave-XXXXXX")
# Version-scoped install prefix so successive builds cannot contaminate each
# other (same reasoning as build-octave.sh).
INST_DIR="/tmp/gtkwave-install-${VERSION}"
rm -rf "$INST_DIR"
mkdir -p "$INST_DIR"
trap 'rm -rf "$WORK_DIR" "$INST_DIR"' EXIT

echo "==> Cloning gtkwave ${TAG} ..."
git clone --depth 1 --branch "$TAG" https://github.com/gtkwave/gtkwave.git \
    "$WORK_DIR/gtkwave" >/dev/null 2>&1

SRC="$WORK_DIR/gtkwave/gtkwave3-gtk3"
[ -d "$SRC" ] || { echo "ERROR: $SRC not present in tag $TAG" >&2; exit 1; }
cd "$SRC"

# The tag ships a pre-generated configure; autoreconf only if that changes.
if [ ! -f configure ]; then
    echo "==> Running autogen.sh ..."
    need autoreconf
    ./autogen.sh
fi

CONF_VERSION=$(sed -n 's/^AC_INIT(gtkwave-gtk3, \([0-9.]*\).*/\1/p' configure.ac)
if [ "$CONF_VERSION" != "$VERSION" ]; then
    echo "ERROR: tag $TAG carries AC_INIT version $CONF_VERSION, expected $VERSION" >&2
    exit 1
fi

echo "==> Configuring ..."
# --enable-gtk3        build the GTK3 frontend (against bundled gui_libs GTK3)
# --disable-tcl        see KNOWN LIMITATION in the header
# --disable-mime-update / --disable-schemas-compile
#                      keep `make install` from touching system-wide
#                      /usr/share/mime and GSettings schema caches
# no --with-gsettings / --with-gconf: preferences then live in ~/.gtkwaverc,
#                      which needs neither a schema nor a settings daemon --
#                      the right default for headless farm nodes.
./configure \
    --prefix="$INST_DIR" \
    --enable-gtk3 \
    --disable-tcl \
    --disable-mime-update \
    --disable-schemas-compile \
    CFLAGS="-O2 -pipe" >"$WORK_DIR/configure.log" 2>&1 || {
        echo "ERROR: configure failed; tail of log:" >&2
        tail -30 "$WORK_DIR/configure.log" >&2
        exit 1
    }

grep -q '^  gtk3                  : yes' "$WORK_DIR/configure.log" || {
    echo "ERROR: configure did not select the gtk3 frontend" >&2
    grep -E '^  gtk' "$WORK_DIR/configure.log" >&2
    exit 1
}

echo "==> Building ..."
make -j"$(nproc 2>/dev/null || echo 2)" >"$WORK_DIR/build.log" 2>&1 || {
    echo "ERROR: build failed; errors:" >&2
    grep -iE 'error' "$WORK_DIR/build.log" | head -20 >&2
    exit 1
}

echo "==> Installing ..."
make install >"$WORK_DIR/install.log" 2>&1 || {
    echo "ERROR: make install failed; tail of log:" >&2
    tail -20 "$WORK_DIR/install.log" >&2
    exit 1
}

echo "==> Checking the installed tool set ..."
for b in $EXPECTED_BINS; do
    [ -x "$INST_DIR/bin/$b" ] || {
        echo "ERROR: expected binary missing after install: bin/$b" >&2
        exit 1
    }
done
for f in "$INST_DIR"/bin/*; do
    n=$(basename "$f")
    case " $EXPECTED_BINS " in
        *" $n "*) ;;
        *)
            echo "ERROR: upstream installed an unexpected binary: bin/$n" >&2
            echo "Add it to EXPECTED_BINS here and to the gtkwave 'bins' list" >&2
            echo "in payload/packages.json, then re-run." >&2
            exit 1
            ;;
    esac
done
echo "  OK: $NUM_BINS binaries, no drift"

echo "==> Verifying no binary embeds the build prefix ..."
# The launchers below embed no paths (everything derives from $0), so this
# invariant still holds and is still enforced: if it fires, a binary (not a
# launcher) needs a prefix-deriving wrapper (see build/ngspice/ngspice).
PREFIX_HITS=0
for f in "$INST_DIR"/bin/*; do
    if strings -a "$f" | grep -qF "$INST_DIR"; then
        echo "  EMBEDS PREFIX: $(basename "$f")" >&2
        PREFIX_HITS=$((PREFIX_HITS + 1))
    fi
done
if grep -rlF "$INST_DIR" "$INST_DIR/share" >/dev/null 2>&1; then
    echo "  EMBEDS PREFIX: files under share/" >&2
    grep -rlF "$INST_DIR" "$INST_DIR/share" >&2
    PREFIX_HITS=$((PREFIX_HITS + 1))
fi
if [ "$PREFIX_HITS" -ne 0 ]; then
    echo "ERROR: $PREFIX_HITS artifact(s) embed the build prefix." >&2
    echo "Only the sh launchers may ship without embedded paths -- a binary" >&2
    echo "hitting this needs a prefix-deriving wrapper before shipping." >&2
    exit 1
fi
echo "  OK: nothing embeds $INST_DIR -- binaries are relocatable as-is"

echo "==> Checking glibc symbol requirements ..."
for f in "$INST_DIR"/bin/*; do
    MAX_GLIBC="$(readelf -V "$f" 2>/dev/null \
        | grep -oE 'GLIBC_[0-9]+\.[0-9]+' | sort -V | tail -1)"
    case "$MAX_GLIBC" in
        ''|GLIBC_2.2[0-8]|GLIBC_2.1[0-9]|GLIBC_2.[0-9]) ;;
        *)
            echo "ERROR: $(basename "$f") needs $MAX_GLIBC > GLIBC_2.28" >&2
            exit 1
            ;;
    esac
done
echo "  OK: all binaries within GLIBC_2.28"

echo "==> Checking shared library closure ..."
# Every NEEDED soname must be either bundled in the payload or a documented
# EL8 base assumption. A closure check that only looked at one binary is how
# libfontenc.so.1 shipped missing for xephyr -- walk them all.
MISSING=""
for f in "$INST_DIR"/bin/*; do
    for so in $(ldd "$f" 2>/dev/null | awk '/=>/ {print $1}' | sort -u); do
        case "$so" in
            linux-vdso*|ld-linux*) continue ;;
        esac
        if [ -f "$PLATFORM_DIR/lib64/${so}.bz2" ] || [ -f "$PLATFORM_DIR/lib64/${so}" ]; then
            continue
        fi
        case "$so" in
            # glibc, C++ runtime, and the GLVND dispatcher are never bundled.
            libc.so.6|libm.so.6|libdl.so.2|libpthread.so.0|librt.so.1|libresolv.so.2)
                continue ;;
            libstdc++.so.6|libgcc_s.so.1) continue ;;
            libGL.so.1|libGLX.so.0|libGLdispatch.so.0) continue ;;
            # EL8 base, transitively required by the glib/gio already in
            # gui_libs, plus liblzma via gtkwave's own -llzma.
            liblzma.so.5|liblz4.so.1|libsystemd.so.0|libselinux.so.1) continue ;;
            libblkid.so.1|libmount.so.1|libcap.so.2|libffi.so.6) continue ;;
            libgnutls.so.30|libgcrypt.so.20|libgpg-error.so.0) continue ;;
            libnettle.so.6|libhogweed.so.4|libtasn1.so.6|libp11-kit.so.0) continue ;;
            libidn2.so.0|libunistring.so.2) continue ;;
        esac
        MISSING="$MISSING $so($(basename "$f"))"
    done
done
if [ -n "$MISSING" ]; then
    echo "ERROR: unbundled, undocumented shared libraries:$MISSING" >&2
    echo "Bundle them in payload/*/lib64 or add them to the allow-list above" >&2
    echo "with a reason -- do not leave the decision implicit." >&2
    exit 1
fi
echo "  OK: closure satisfied by bundled libs + documented EL8 base"

echo "==> Verifying staged tree functionally (FST -> VCD -> FST) ..."
# `gtkwave --version` alone is a worthless smoke: the converters are what runs
# in batch flows, and a broken FST reader is silent under --version.
EX="$INST_DIR/share/gtkwave-gtk3/examples"
[ -f "$EX/des.fst" ] || { echo "ERROR: $EX/des.fst missing" >&2; exit 1; }
"$INST_DIR/bin/fst2vcd" "$EX/des.fst" > "$WORK_DIR/des.vcd" 2>"$WORK_DIR/fst2vcd.err" || {
    echo "ERROR: fst2vcd failed:" >&2; cat "$WORK_DIR/fst2vcd.err" >&2; exit 1
}
VCD_LINES=$(wc -l < "$WORK_DIR/des.vcd")
[ "$VCD_LINES" -gt 1000 ] || {
    echo "ERROR: fst2vcd produced only $VCD_LINES lines of VCD" >&2
    exit 1
}
# shellcheck disable=SC2016  # literal VCD keyword, not a shell expansion
grep -q '\$enddefinitions' "$WORK_DIR/des.vcd" || {
    echo "ERROR: fst2vcd output has no \$enddefinitions section" >&2
    exit 1
}
"$INST_DIR/bin/vcd2fst" "$WORK_DIR/des.vcd" "$WORK_DIR/des2.fst" \
    >/dev/null 2>"$WORK_DIR/vcd2fst.err" || {
    echo "ERROR: vcd2fst failed:" >&2; cat "$WORK_DIR/vcd2fst.err" >&2; exit 1
}
[ -s "$WORK_DIR/des2.fst" ] || { echo "ERROR: vcd2fst produced an empty FST" >&2; exit 1; }
"$INST_DIR/bin/fst2vcd" "$WORK_DIR/des2.fst" >/dev/null 2>&1 || {
    echo "ERROR: round-tripped FST is not readable by fst2vcd" >&2
    exit 1
}
echo "  OK: des.fst -> ${VCD_LINES} lines VCD -> FST -> re-read"

echo "==> Verifying gtkwave starts headless ..."
GW_VER=$(env -u DISPLAY -u WAYLAND_DISPLAY "$INST_DIR/bin/gtkwave" --version 2>&1 | head -1)
echo "  $GW_VER"
echo "$GW_VER" | grep -qF "v$VERSION" || {
    echo "ERROR: --version does not report $VERSION" >&2
    exit 1
}

echo "==> Packaging binaries ..."
# Stage in a dedicated dir: $WORK_DIR itself holds the clone, whose top-level
# directory is also named "gtkwave" and would shadow the binary of that name.
# The three GUI frontends ship wrapper-split (launcher + .bin ELF); the
# converters stay bare ELFs.
GUI_WRAPPED="gtkwave twinwave rtlbrowse"
PKG_DIR="$WORK_DIR/pkg"
mkdir -p "$PKG_DIR"
# Launcher composition (single source of truth per block; installed wrappers
# stay self-contained sh): header derives the install prefix from $0, then
# the shared GUI env block, then the shared GTK3 block, then exec.
GUI_ENV_BLOCK="$REPO/build/gui-wrapper-env.sh"
GTK_ENV_BLOCK="$REPO/build/gtk3-launcher-env.sh"
[ -r "$GUI_ENV_BLOCK" ] || { echo "ERROR: missing $GUI_ENV_BLOCK" >&2; exit 1; }
[ -r "$GTK_ENV_BLOCK" ] || { echo "ERROR: missing $GTK_ENV_BLOCK" >&2; exit 1; }
for b in $GUI_WRAPPED; do
    {
        printf '#!/bin/sh\n# loadout %s launcher -- env adaptation ONLY (no prefix embedded;\n' "$b"
        printf '# the real binary is the sibling .bin and carries no build prefix).\n'
        printf '# Composed of: prefix header + build/gui-wrapper-env.sh +\n'
        printf '# build/gtk3-launcher-env.sh -- see those files for what each fixes.\n'
        printf 'here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)\n'
        printf 'prefix=$(CDPATH= cd -- "$here/.." && pwd -P)\n'
        cat "$GUI_ENV_BLOCK" "$GTK_ENV_BLOCK"
        printf 'exec "$here/%s.bin" "$@"\n' "$b"
    } > "$PKG_DIR/$b.launcher"
done
for b in $EXPECTED_BINS; do
    cp "$INST_DIR/bin/$b" "$PKG_DIR/$b.bin"
    strip "$PKG_DIR/$b.bin"
    # shellcheck disable=SC2016  # $ORIGIN is a literal ld.so token
    "$PATCHELF" --set-rpath '$ORIGIN/../lib64' "$PKG_DIR/$b.bin"
    case " $GUI_WRAPPED " in
        *" $b "*)
            cp "$PKG_DIR/$b.launcher" "$PKG_DIR/$b"
            chmod 755 "$PKG_DIR/$b"
            bzip2 -kf "$PKG_DIR/$b" "$PKG_DIR/$b.bin"
            cp "$PKG_DIR/$b.bz2" "$BIN_DIR/$b.bz2"
            cp "$PKG_DIR/$b.bin.bz2" "$BIN_DIR/$b.bin.bz2"
            ;;
        *)
            bzip2 -kf "$PKG_DIR/$b.bin"
            cp "$PKG_DIR/$b.bin.bz2" "$BIN_DIR/$b.bz2"
            ;;
    esac
done
echo "  Wrote $NUM_BINS tools to $BIN_DIR (3 GUI frontends wrapper-split)"

echo "==> Packaging gtkwave runtime (examples, man pages, desktop/mime/icons) ..."
# gtkwave.odt is the 1.7 MB ODT user manual -- excluded, like octave's doc
# tree. The man pages are the offline reference that is actually usable from a
# terminal, and man-db maps <prefix>/bin -> <prefix>/share/man automatically.
# The examples are kept because tests/prebuilt-binaries converts des.fst as
# its functional probe.
rm -f "$INST_DIR/share/gtkwave-gtk3/gtkwave.odt"
tar cjf "$RUNTIME_DIR/gtkwave.tar.bz2" \
    -C "$INST_DIR" \
    "./share/gtkwave-gtk3" \
    "./share/man" \
    "./share/mime" \
    "./share/icons" \
    "./share/applications"
echo "  Wrote: $RUNTIME_DIR/gtkwave.tar.bz2 ($(wc -c < "$RUNTIME_DIR/gtkwave.tar.bz2" | tr -d ' ') bytes)"

echo "==> Updating packages.json ..."
python3 -c "
import sys, json
path, ver = sys.argv[1], sys.argv[2]
with open(path) as f:
    data = json.load(f)
pkgs = data['packages']
if 'gtkwave' in pkgs:
    pkgs['gtkwave']['version'] = ver
    print(f'packages.json: gtkwave version -> {ver}')
else:
    print('WARNING: gtkwave not found in packages.json, skipping version update')
with open(path, 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
" "$REPO/payload/packages.json" "$VERSION"

echo "==> Running strip-all-elf-binaries ..."
"$REPO/build/strip-all-elf-binaries"

echo ""
echo "Done."
echo ""
echo "Produced:"
for b in $EXPECTED_BINS; do echo "  $BIN_DIR/$b.bz2"; done
for b in $GUI_WRAPPED; do echo "  $BIN_DIR/$b.bin.bz2"; done
echo "  $RUNTIME_DIR/gtkwave.tar.bz2"
echo ""
echo "Reminders:"
echo "  - ./loadout completion bash > envs/bash/global/completions/loadout.bash"
echo "  - build/ADDING_BINARIES.md note is MANDATORY"
echo ""
echo "Commit with:"
echo "  git add payload/el8.x86_64.glibc2p28/bin/ payload/el8.x86_64.glibc2p28/runtime/gtkwave.tar.bz2 \\"
echo "          .strip-manifest payload/packages.json build/build-gtkwave.sh"
echo "  git commit -m 'feat(payload): gtkwave ${VERSION} EL8 GTK3 source build'"
