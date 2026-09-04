#!/bin/sh
# Build gvim (GTK3 GUI Vim) from source for el8.x86_64.glibc2p28.
#
# Targets RHEL 8 base + GUI environment (gtk3 present system-wide).
# Links only against system libs (gtk3, X11, glib, tinfo, selinux, etc.);
# no bundled libs needed. Added to payload as optional tool.
#
# Prerequisites on the build machine:
#   sudo dnf install gcc make ncurses-devel gtk3-devel libX11-devel \
#                    libXt-devel libSM-devel libICE-devel
#   # gcc-toolset-14 optional but recommended for consistent ABI
#
# Usage:
#   cd ~/vim            # any vim 9.x source checkout
#   /path/to/build-gvim.sh [--clean]
#
# After a successful build:
#   - The vim binary with GTK3 GUI support is at  src/vim
#   - A gvim wrapper script is printed to stdout  (pipe to gvim or save)
#   - Packaging instructions are printed at the end.

set -eu

REPO="$(cd "$(dirname "$0")/.." && pwd)"
BIN_DIR="$REPO/payload/el8.x86_64.glibc2p28/bin"
PATCHELF="$HOME/.local/bin/patchelf"
JOBS="${JOBS:-$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 8)}"

clean=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --clean) clean=1 ;;
        -h|--help)
            sed -n '2,/^$/p' "$0"
            exit 0
            ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done

# Source gcc-toolset-14 if available (matches the existing vim.bin build).
if [ -r /opt/rh/gcc-toolset-14/enable ]; then
    # shellcheck disable=SC1091
    . /opt/rh/gcc-toolset-14/enable
fi

need() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "missing required command: $1 -- install the prerequisite packages listed in this script's header" >&2
        exit 1
    }
}

need gcc
need make
need pkg-config
pkg-config --exists gtk+-3.0 || {
    echo "gtk+-3.0 not found via pkg-config -- install gtk3-devel" >&2
    exit 1
}

if [ "$clean" -eq 1 ] && [ -f src/Makefile ]; then
    make -C src clean
fi

# Configure: huge feature set + GTK3 GUI + X11 + clipboard.
# Disable lua/python/ruby/perl to avoid bundling their runtimes.
# Match the CFLAGS from the existing vim.bin build.
./configure \
    --with-features=huge \
    --enable-gui=gtk3 \
    --with-x \
    --enable-multibyte \
    --disable-luainterp \
    --disable-python3interp \
    --disable-rubyinterp \
    --disable-perlinterp \
    CFLAGS="-O2 -fno-strength-reduce -Wall -Wno-deprecated-declarations -D_REENTRANT -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=1"

make -j"$JOBS"

echo ""
echo "Build complete: $(src/vim --version | head -1)"
echo ""
src/vim --version | grep "^Compilation:"
src/vim --version | grep "^Linking:"
echo ""
echo "Sanity check -- must show +gui_gtk3 and +X11:"
src/vim --version | grep -E "gui_gtk|X11|clipboard"
echo ""
echo "Binary size: $(ls -lh src/vim | awk '{print $5}') unstripped"
echo ""

echo "=== Packaging (run from the vim source directory) ===>"
echo ""
echo "  # Binary: strip -> bzip2  (no patchelf needed -- all system libs)"
echo "  cp src/vim /tmp/gvim.bin_tmp"
echo "  strip /tmp/gvim.bin_tmp"
echo "  ls -lh /tmp/gvim.bin_tmp"
echo "  bzip2 -k /tmp/gvim.bin_tmp"
echo "  cp /tmp/gvim.bin_tmp.bz2 $BIN_DIR/gvim.bin.bz2"
echo ""
echo "  # gvim wrapper: compose from build/gvim-launcher.sh (VIM header +"
echo "  # shared gui/gtk3 env blocks), then bzip2 alongside the binary:"
echo "  cp $REPO/build/gvim-launcher.sh /tmp/gvim_tmp"
echo "  bzip2 -k /tmp/gvim_tmp"
echo "  cp /tmp/gvim_tmp.bz2 $BIN_DIR/gvim.bz2"
echo ""
echo "  # Strip manifest + commit"
echo "  cd $REPO && ./build/strip-all-elf-binaries"
echo "  git add payload/el8.x86_64.glibc2p28/bin/gvim.bin.bz2 .strip-manifest"
echo "  git commit"
