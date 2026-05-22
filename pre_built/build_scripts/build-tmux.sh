#!/bin/sh
# Build tmux from source for el8.x86_64.glibc2p28.
#
# Produces a tmux binary linked against system glibc 2.28, with RUNPATH
# $ORIGIN/../lib64:$ORIGIN/../lib so it picks up the bundled libevent_core
# alongside ~/.local/bin at runtime.
#
# Build-time deps (system, headers): libevent-devel, ncurses-devel
#   (build links against /usr/lib64/libevent_core.so → SONAME
#    libevent_core-2.1.so.6, which is ABI-compatible with the bundled
#    libevent_core-2.1.so.6 the installer drops into ~/.local/lib64).
# Runtime deps (bundled in this repo's lib64/): libevent_core-2.1.so.6
# Runtime deps (system on EL8): libutil, libtinfo, libm, libresolv, libc
#
# Policy: always build from a stable tagged release. See stable tags at:
#   https://github.com/tmux/tmux/releases
# tmux uses bare-string tags like "3.6b" (no "v" prefix).
#
# Prerequisites on the build machine (EL8):
#   sudo dnf install gcc make autoconf automake pkgconf-pkg-config \
#                    libevent-devel ncurses-devel bison byacc
#   # gcc-toolset-14 optional but recommended for consistent ABI
#
# Usage (run from any directory):
#   /path/to/build-tmux.sh --tag 3.6b

set -eu

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
BIN_DIR="$REPO/pre_built/el8.x86_64.glibc2p28/bin"
PATCHELF="${HOME}/.local/bin/patchelf"
CLONE_URL="https://github.com/tmux/tmux.git"

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
    echo "  $0 --tag 3.6b" >&2
    echo "" >&2
    echo "Stable releases: https://github.com/tmux/tmux/releases" >&2
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

need autoconf
need automake
need gcc
need make
need pkg-config
need bison

SRCDIR="/tmp/tmux-src-${tag}"
INSTALL_PREFIX="/tmp/tmux-install-${tag}"

if [ ! -d "$SRCDIR/.git" ]; then
    echo "Cloning $CLONE_URL ..."
    git clone --filter=blob:none "$CLONE_URL" "$SRCDIR"
fi

cd "$SRCDIR"
if ! git rev-parse "$tag" >/dev/null 2>&1; then
    git fetch --tags
fi
git checkout "$tag"

if [ "$clean" -eq 1 ]; then
    [ -f Makefile ] && make distclean || true
fi

if [ ! -f configure ]; then
    echo "Generating configure script..."
    sh autogen.sh
fi

rm -rf "$INSTALL_PREFIX"

# libevent and ncurses come from system headers at build time; the bundled
# libevent_core-2.1.so.6 in this repo's lib64/ satisfies tmux at runtime via
# the patchelf'd $ORIGIN/../lib64 RUNPATH.
./configure \
    --prefix="$INSTALL_PREFIX" \
    --bindir="$INSTALL_PREFIX/bin" \
    CFLAGS="-O2 -fstack-protector-strong"

make -j"$(nproc 2>/dev/null || echo 8)"
make install

echo ""
echo "Build complete: $("$INSTALL_PREFIX/bin/tmux" -V)"
echo ""

# Package the binary: strip first, then patchelf (order matters — stripping
# after patchelf corrupts .dynstr placement and crashes the binary at runtime).
WORK="/tmp/tmux_work_${tag}"
cp "$INSTALL_PREFIX/bin/tmux" "$WORK"
strip "$WORK"
"$PATCHELF" --set-rpath '$ORIGIN/../lib64:$ORIGIN/../lib' "$WORK"
bzip2 -kf "$WORK"
cp "${WORK}.bz2" "$BIN_DIR/tmux.bz2"
rm -f "$WORK" "${WORK}.bz2"

# Update packages.json version
ver="${tag}"
TOOLS_JSON="$REPO/pre_built/packages.json"
python3 -c "
import re, sys
path = sys.argv[1]; ver = sys.argv[2]
txt = open(path).read()
txt = re.sub(
    r'(\"tmux\".*?\"version\":\s*\")([^\"]+)(\")',
    r'\g<1>' + ver + r'\3',
    txt,
    count=1,
    flags=re.DOTALL,
)
open(path, 'w').write(txt)
print('packages.json: tmux version -> ' + ver)
" "$TOOLS_JSON" "$ver"

# Update strip manifest
echo "Running strip_all_elf_binaries..."
"$REPO/strip_all_elf_binaries"

# glibc check
MAX_GLIBC="$(readelf -V "$INSTALL_PREFIX/bin/tmux" 2>/dev/null \
    | grep -oE 'GLIBC_[0-9]+\.[0-9]+' | sort -V | tail -1)"
echo "Max glibc symbol: $MAX_GLIBC (target: GLIBC_2.28)"
case "$MAX_GLIBC" in
    GLIBC_2.2[0-8]|GLIBC_2.1[0-9]|GLIBC_2.[0-9])
        echo "OK — binary compatible with EL8 glibc 2.28" ;;
    *)
        echo "WARNING: requires newer glibc than EL8 baseline" >&2 ;;
esac

echo ""
echo "Installed: $BIN_DIR/tmux.bz2"
echo ""
echo "Next steps:"
echo "  $REPO/pre_built/build_scripts/verify-binaries tmux"
echo "  git add $BIN_DIR/tmux.bz2 $TOOLS_JSON $REPO/.strip-manifest"
echo "  git commit -m 'feat(tmux): bump tmux to ${ver} stable EL8 source build'"
