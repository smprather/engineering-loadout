#!/bin/sh
# Build rxvt-unicode (urxvt) from source for el8.x86_64.glibc2p28.
#
# Produces:
#   - urxvt        — main terminal binary
#   - urxvtc       — client for the urxvt daemon
#   - urxvtd       — terminal daemon (one process for many windows)
#
# Runtime deps (bundled in this repo's lib64/, pulled when urxvt is selected):
#   libX11, libXft, libXt, libXmu, libXrender, libxcb, libfontconfig,
#   libfreetype, libpng16, libncurses, libtinfo, libICE, libSM
# Runtime deps (system on EL8):
#   libstdc++, libutil, libm, libpthread, libc
#
# Perl extension support is disabled (--disable-perl) so we don't need to
# bundle libperl.so.5.x and pull in the entire Perl runtime. The standard
# terminal works fine; only urxvt's perl-driven plugins (matcher, tabbed,
# etc.) are unavailable.
#
# Build-time deps (system, EL8):
#   gcc-c++, ncurses-devel, libX11-devel, libXft-devel, libXt-devel,
#   libXmu-devel, libXrender-devel, fontconfig-devel
#
# Policy: always build from a stable tagged release.
# Upstream tarballs: http://dist.schmorp.de/rxvt-unicode/
#
# Usage (run from any directory):
#   /path/to/build-urxvt.sh --tag 9.31

set -eu

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
BIN_DIR="$REPO/pre_built/el8.x86_64.glibc2p28/bin"
LIB_DIR="$REPO/pre_built/el8.x86_64.glibc2p28/lib64"
PATCHELF="${HOME}/.local/bin/patchelf"
DIST_URL_BASE="http://dist.schmorp.de/rxvt-unicode"
LIBPTYTTY_VERSION="2.0"
LIBPTYTTY_URL="http://dist.schmorp.de/libptytty/libptytty-${LIBPTYTTY_VERSION}.tar.gz"
LIBPTYTTY_PREFIX="/tmp/libptytty-install-${LIBPTYTTY_VERSION}"

clean=0
tag=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --clean) clean=1 ;;
        --tag)
            shift
            [ "$#" -gt 0 ] || { echo "missing value for --tag" >&2; exit 2; }
            tag="$1"
            ;;
        -h|--help)
            sed -n '2,/^$/p' "$0"
            exit 0
            ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done

if [ -z "$tag" ]; then
    echo "ERROR: --tag is required. Specify a stable release tag, e.g.:" >&2
    echo "  $0 --tag 9.31" >&2
    echo "" >&2
    echo "Stable releases: http://dist.schmorp.de/rxvt-unicode/" >&2
    echo "" >&2
    echo "Policy: this project ships stable releases only." >&2
    echo "Nightly/dev builds are not accepted." >&2
    exit 1
fi

if [ -r /opt/rh/gcc-toolset-14/enable ]; then
    # shellcheck disable=SC1091
    . /opt/rh/gcc-toolset-14/enable
fi

need() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "missing required command: $1 — install the prerequisite packages listed in this script's header" >&2
        exit 1
    }
}

need gcc
need make
need cmake
need pkg-config
need curl
need bzip2

# --- libptytty: small required dep, not in EL8 repos. Build first into a
# staging prefix; copy libptytty.so.0 into the repo as a bundled lib so the
# installer ships it alongside urxvt at runtime via the patchelf'd RUNPATH.
LIBPTYTTY_SRC="/tmp/libptytty-${LIBPTYTTY_VERSION}"
if [ ! -f "$LIBPTYTTY_PREFIX/lib64/pkgconfig/libptytty.pc" ]; then
    if [ ! -d "$LIBPTYTTY_SRC" ]; then
        echo "Downloading libptytty-${LIBPTYTTY_VERSION}..."
        curl -fsSL "$LIBPTYTTY_URL" -o "/tmp/libptytty-${LIBPTYTTY_VERSION}.tar.gz"
        tar -xzf "/tmp/libptytty-${LIBPTYTTY_VERSION}.tar.gz" -C /tmp
    fi
    cd "$LIBPTYTTY_SRC"
    cmake -B build -DCMAKE_INSTALL_PREFIX="$LIBPTYTTY_PREFIX" -DCMAKE_BUILD_TYPE=Release
    cmake --build build --target install -j"$(nproc 2>/dev/null || echo 8)"
fi

SRCDIR="/tmp/urxvt-src-${tag}"
INSTALL_PREFIX="/tmp/urxvt-install-${tag}"

# Download upstream tarball if not already present
if [ ! -d "$SRCDIR" ]; then
    TARBALL="/tmp/rxvt-unicode-${tag}.tar.bz2"
    if [ ! -f "$TARBALL" ]; then
        echo "Downloading rxvt-unicode-${tag}..."
        curl -fsSL "${DIST_URL_BASE}/rxvt-unicode-${tag}.tar.bz2" -o "$TARBALL"
    fi
    mkdir -p "$SRCDIR"
    tar -xjf "$TARBALL" -C "$SRCDIR" --strip-components=1
fi

cd "$SRCDIR"

if [ "$clean" -eq 1 ]; then
    [ -f Makefile ] && make distclean || true
fi

rm -rf "$INSTALL_PREFIX"

# Disable perl to avoid bundling libperl.so + the Perl runtime.
# Disable xim/250-color/etc. dependencies that pull in extra libs.
# Keep wide-char + xft (those are why people use urxvt).
PKG_CONFIG_PATH="$LIBPTYTTY_PREFIX/lib64/pkgconfig:${PKG_CONFIG_PATH:-}" \
./configure \
    --prefix="$INSTALL_PREFIX" \
    --enable-everything \
    --disable-perl \
    --disable-pixbuf \
    --disable-startup-notification \
    --enable-256-color \
    --enable-xft \
    --enable-wide-glyphs \
    CFLAGS="-O2 -fstack-protector-strong" \
    CXXFLAGS="-O2 -fstack-protector-strong"

make -j"$(nproc 2>/dev/null || echo 8)"
make install

echo ""
echo "Build complete: $("$INSTALL_PREFIX/bin/urxvt" -h 2>&1 | head -1)"
echo ""

# Package each binary: strip first, then patchelf RUNPATH so urxvt finds the
# bundled X11/Xft/libptytty/etc. libs in ~/.local/lib64/ alongside ~/.local/bin/.
for bin in urxvt urxvtc urxvtd; do
    SRC="$INSTALL_PREFIX/bin/$bin"
    [ -f "$SRC" ] || { echo "missing $SRC; skipping"; continue; }
    WORK="/tmp/urxvt_work_${tag}_${bin}"
    cp "$SRC" "$WORK"
    strip "$WORK"
    "$PATCHELF" --set-rpath '$ORIGIN/../lib64:$ORIGIN/../lib' "$WORK"
    bzip2 -kf "$WORK"
    cp "${WORK}.bz2" "$BIN_DIR/$bin.bz2"
    rm -f "$WORK" "${WORK}.bz2"
    echo "Installed: $BIN_DIR/$bin.bz2"
done

# libptytty.so.0 — patchelf RPATH $ORIGIN (finds siblings in ~/.local/lib64/),
# strip, bzip2, drop into the repo's lib64 dir.
LIBPTYTTY_WORK="/tmp/libptytty_work_${LIBPTYTTY_VERSION}"
cp "$LIBPTYTTY_PREFIX/lib64/libptytty.so.0" "$LIBPTYTTY_WORK"
strip "$LIBPTYTTY_WORK"
"$PATCHELF" --set-rpath '$ORIGIN' "$LIBPTYTTY_WORK"
bzip2 -kf "$LIBPTYTTY_WORK"
cp "${LIBPTYTTY_WORK}.bz2" "$LIB_DIR/libptytty.so.0.bz2"
rm -f "$LIBPTYTTY_WORK" "${LIBPTYTTY_WORK}.bz2"
echo "Installed: $LIB_DIR/libptytty.so.0.bz2"

# Update packages.json version (single regex matches all three urxvt* entries)
ver="${tag}"
TOOLS_JSON="$REPO/pre_built/packages.json"
python3 -c "
import re, sys
path = sys.argv[1]; ver = sys.argv[2]
txt = open(path).read()
# urxvt, urxvtc, urxvtd all share one version
new = re.sub(
    r'(\"urxvt[a-z]?\".*?\"version\":\s*\")([^\"]+)(\")',
    r'\g<1>' + ver + r'\3',
    txt,
    flags=re.DOTALL,
)
open(path, 'w').write(new)
print('packages.json: urxvt* version -> ' + ver)
" "$TOOLS_JSON" "$ver"

# Update strip manifest
echo "Running strip_all_elf_binaries..."
"$REPO/strip_all_elf_binaries"

# glibc check (use the largest binary, urxvt)
MAX_GLIBC="$(readelf -V "$INSTALL_PREFIX/bin/urxvt" 2>/dev/null \
    | grep -oE 'GLIBC_[0-9]+\.[0-9]+' | sort -V | tail -1)"
echo "Max glibc symbol: $MAX_GLIBC (target: GLIBC_2.28)"
case "$MAX_GLIBC" in
    GLIBC_2.2[0-8]|GLIBC_2.1[0-9]|GLIBC_2.[0-9])
        echo "OK — binary compatible with EL8 glibc 2.28" ;;
    *)
        echo "WARNING: requires newer glibc than EL8 baseline" >&2 ;;
esac

echo ""
echo "Next steps:"
echo "  $REPO/pre_built/build_scripts/verify-binaries urxvt"
echo "  git add $BIN_DIR/urxvt*.bz2 $TOOLS_JSON $REPO/.strip-manifest"
echo "  git commit -m 'feat(urxvt): bump urxvt to ${ver} stable EL8 source build'"
