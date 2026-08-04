#!/bin/sh
# Build tmux from source for el8.x86_64.glibc2p28.
#
# Produces a tmux binary linked against system glibc 2.28, with RUNPATH
# $ORIGIN/../lib64:$ORIGIN/../lib so it picks up the bundled libevent_core
# alongside ~/.local/bin at runtime.
#
# Build-time deps (system, headers): libevent-devel, ncurses-devel
#   (build links against /usr/lib64/libevent_core.so -> SONAME
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

REPO="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib.sh
. "$REPO/build/lib.sh"
BIN_DIR="$LOADOUT_BIN_DIR"
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

loadout_require_tag "$tag" "$0" "https://github.com/tmux/tmux/releases" "3.6b"
loadout_enable_gcc_toolset
loadout_require_cmds autoconf automake gcc make pkg-config bison

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

# Package the binary + stamp the registry version (strip -> patchelf -> bzip2;
# order matters -- stripping after patchelf corrupts .dynstr placement).
loadout_package_bin "$INSTALL_PREFIX/bin/tmux" tmux
ver="$tag"
TOOLS_JSON="$REPO/payload/packages.json"
loadout_stamp_version tmux "$ver"

# Update strip manifest
echo "Running strip-all-elf-binaries..."
"$REPO/build/strip-all-elf-binaries"

# glibc check
loadout_report_max_glibc "$INSTALL_PREFIX/bin/tmux"

echo ""
echo "Installed: $BIN_DIR/tmux.bz2"
echo ""
echo "Next steps:"
echo "  $REPO/build/verify-binaries tmux"
echo "  git add $BIN_DIR/tmux.bz2 $TOOLS_JSON $REPO/.strip-manifest"
echo "  git commit -m 'feat(tmux): bump tmux to ${ver} stable EL8 source build'"
