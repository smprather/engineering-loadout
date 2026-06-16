#!/bin/sh
# Build xterm from source for el8.x86_64.glibc2p28.
#
# Produces:
#   - xterm   -- X11 terminal emulator with Unicode, color, and Xft font support
#   - resize  -- terminal resize utility (shipped with xterm source tree)
#
# Runtime deps (bundled in this repo's lib64/, pulled when xterm is selected):
#   libXft, libXaw, libXmu, libXt, libX11, libXpm, libXrender, libICE,
#   libSM, libfontconfig, libfreetype, libutempter, libtinfo
# Runtime deps (system on EL8):
#   libXext, libxcb, libXau, libexpat, libuuid, libm, libpthread, libc
#
# Build-time deps (system, EL8):
#   gcc, make, pkg-config, libX11-devel, libXft-devel, libXaw-devel,
#   libXt-devel, libXmu-devel, libXpm-devel, fontconfig-devel, freetype-devel,
#   libutempter-devel, ncurses-devel
#
# Policy: always build from a stable tagged release.
# Stable tarballs: https://invisible-island.net/archives/xterm/
#
# Usage (run from any directory):
#   /path/to/build-xterm.sh --tag 410

set -eu

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
BIN_DIR="$REPO/pre_built/el8.x86_64.glibc2p28/bin"
PATCHELF="${HOME}/.local/bin/patchelf"
DIST_URL_BASE="https://invisible-island.net/archives/xterm"

tag=""
clean=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --tag)
            shift
            [ "$#" -gt 0 ] || { echo "missing value for --tag" >&2; exit 2; }
            tag="$1"
            ;;
        --clean) clean=1 ;;
        -h|--help)
            sed -n '2,/^$/p' "$0"
            exit 0
            ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done

[ -n "$tag" ] || {
    echo "ERROR: --tag <version> required (e.g. --tag 410)" >&2
    echo "Stable tarballs: ${DIST_URL_BASE}/" >&2
    echo "Policy: stable releases only -- no git HEAD or dev builds." >&2
    exit 2
}

if [ -r /opt/rh/gcc-toolset-14/enable ]; then
    # shellcheck disable=SC1091
    . /opt/rh/gcc-toolset-14/enable
fi

need() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "missing required command: $1 -- install prerequisite packages listed in this script's header" >&2
        exit 1
    }
}

need gcc
need make
need pkg-config
need curl
need bzip2

SRCDIR="/tmp/xterm-src-${tag}"
INSTALL_PREFIX="/tmp/xterm-install-${tag}"

if [ ! -d "$SRCDIR" ]; then
    TARBALL="/tmp/xterm-${tag}.tgz"
    if [ ! -f "$TARBALL" ]; then
        echo "Downloading xterm-${tag}..."
        curl -fsSL "${DIST_URL_BASE}/xterm-${tag}.tgz" -o "$TARBALL"
    fi
    mkdir -p "$SRCDIR"
    tar -xzf "$TARBALL" -C "$SRCDIR" --strip-components=1
fi

cd "$SRCDIR"

if [ "$clean" -eq 1 ]; then
    [ -f Makefile ] && make distclean || true
fi

rm -rf "$INSTALL_PREFIX"

./configure \
    --prefix="$INSTALL_PREFIX" \
    --enable-256-color \
    --enable-wide-chars \
    --with-xft \
    --with-utempter \
    --enable-logging \
    CFLAGS="-O2 -fstack-protector-strong" \
    CPPFLAGS="-I/usr/include/X11"

make -j"$(nproc 2>/dev/null || echo 8)"
make install

echo ""
echo "Build complete: $("$INSTALL_PREFIX/bin/xterm" -v 2>&1 | head -1)"
echo ""

# Strip, patchelf RUNPATH, bzip2, install.
for bin in xterm resize; do
    SRC="$INSTALL_PREFIX/bin/$bin"
    [ -f "$SRC" ] || { echo "missing $SRC; skipping"; continue; }
    WORK="/tmp/xterm_work_${tag}_${bin}"
    cp "$SRC" "$WORK"
    strip "$WORK"
    "$PATCHELF" --set-rpath '$ORIGIN/../lib64:$ORIGIN/../lib' "$WORK"
    bzip2 -kf "$WORK"
    cp "${WORK}.bz2" "$BIN_DIR/${bin}.bz2"
    rm -f "$WORK" "${WORK}.bz2"
    echo "Installed: $BIN_DIR/${bin}.bz2"
done

# Update packages.json version
ver="${tag}"
TOOLS_JSON="$REPO/pre_built/packages.json"
python3 -c "
import re, sys
path = sys.argv[1]; ver = sys.argv[2]
txt = open(path).read()
new = re.sub(
    r'(\"xterm\".*?\"version\":\s*\")([^\"]+)(\")',
    r'\g<1>' + ver + r'\3',
    txt,
    flags=re.DOTALL,
)
open(path, 'w').write(new)
print('packages.json: xterm version -> ' + ver)
" "$TOOLS_JSON" "$ver"

# Update strip manifest
echo "Running strip_all_elf_binaries..."
"$REPO/strip_all_elf_binaries"

# glibc check
MAX_GLIBC="$(readelf -V "$INSTALL_PREFIX/bin/xterm" 2>/dev/null \
    | grep -oE 'GLIBC_[0-9]+\.[0-9]+' | sort -V | tail -1)"
echo "Max glibc symbol: $MAX_GLIBC (target: GLIBC_2.28)"
case "$MAX_GLIBC" in
    GLIBC_2.2[0-8]|GLIBC_2.1[0-9]|GLIBC_2.[0-9])
        echo "OK -- binary compatible with EL8 glibc 2.28" ;;
    *)
        echo "WARNING: requires newer glibc than EL8 baseline" >&2 ;;
esac

echo ""
echo "Next steps:"
echo "  $REPO/pre_built/build_scripts/verify-binaries xterm"
echo "  git add $BIN_DIR/xterm.bz2 $BIN_DIR/resize.bz2 $TOOLS_JSON $REPO/.strip-manifest"
echo "  git commit -m 'feat(xterm): bump xterm to ${tag} stable EL8 source build'"
