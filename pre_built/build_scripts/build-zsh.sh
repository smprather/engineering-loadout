#!/bin/sh
# Build zsh from source for el8.x86_64.glibc2p28.
#
# Produces a statically-linked ncurses zsh binary that links only against
# system glibc 2.28 — no bundled libs needed at runtime.
#
# Deps bundled from this repo: libncurses.so.6, libreadline.so.7
# PCRE support is disabled to avoid bundling libpcre.so.1; zsh regex
# features (is-at-least, pcre-match) will still work via the extended glob
# and regex module that uses POSIX ERE.
#
# Note: official zsh prebuilts are source tarballs only; this script builds
# from the GitHub mirror at a stable tagged release.
#
# Policy: always build from a stable tagged release. See stable tags at:
#   https://github.com/zsh-users/zsh/releases
#   https://sourceforge.net/projects/zsh/files/zsh/
#
# Prerequisites on the build machine (EL8):
#   sudo dnf install gcc make autoconf autoconf-archive ncurses-devel \
#                    readline-devel texinfo yodl gettext
#   # gcc-toolset-14 optional but recommended for consistent ABI
#
# Usage (run from any directory):
#   /path/to/build-zsh.sh --tag 5.9

set -eu

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
BIN_DIR="$REPO/pre_built/el8.x86_64.glibc2p28/bin"
PATCHELF="${HOME}/.local/bin/patchelf"
CLONE_URL="https://github.com/zsh-users/zsh.git"

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
    echo "  $0 --tag 5.9" >&2
    echo "" >&2
    echo "Stable releases: https://github.com/zsh-users/zsh/releases" >&2
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
need gcc
need make

SRCDIR="/tmp/zsh-src-${tag}"
INSTALL_PREFIX="/tmp/zsh-install-${tag}"

if [ ! -d "$SRCDIR/.git" ]; then
    echo "Cloning $CLONE_URL ..."
    git clone --filter=blob:none "$CLONE_URL" "$SRCDIR"
fi

cd "$SRCDIR"
git fetch --tags
# zsh tags are plain version numbers like "5.9" (no "v" prefix)
git checkout "$tag"

if [ "$clean" -eq 1 ]; then
    [ -f Makefile ] && make distclean || true
fi

if [ ! -f configure ]; then
    echo "Generating configure script..."
    autoreconf -fi || autoconf
fi

rm -rf "$INSTALL_PREFIX"

# Build without PCRE to avoid bundling libpcre.so.1.
# ncurses and readline are bundled from this repo ($ORIGIN/../lib64).
# --enable-cap: POSIX capabilities support (libcap is always on EL8).
./configure \
    --prefix="$INSTALL_PREFIX" \
    --bindir="$INSTALL_PREFIX/bin" \
    --enable-cap \
    --enable-multibyte \
    --enable-zsh-secure-free \
    --without-tcsetpgrp \
    --disable-pcre \
    CFLAGS="-O2 -fstack-protector-strong"

make -j"$(nproc 2>/dev/null || echo 8)"
make install

echo ""
echo "Build complete: $("$INSTALL_PREFIX/bin/zsh" --version)"
echo ""

# Package the binary
WORK="/tmp/zsh_work_${tag}"
cp "$INSTALL_PREFIX/bin/zsh" "$WORK"
strip "$WORK"
"$PATCHELF" --set-rpath '$ORIGIN/../lib64:$ORIGIN/../lib' "$WORK"
bzip2 -kf "$WORK"
cp "${WORK}.bz2" "$BIN_DIR/zsh.bz2"
rm -f "$WORK" "${WORK}.bz2"

# Update tools.json version
ver="${tag}"
TOOLS_JSON="$REPO/pre_built/tools.json"
python3 -c "
import re, sys
path = sys.argv[1]; ver = sys.argv[2]
txt = open(path).read()
txt = re.sub(
    r'(\"zsh\".*?\"version\":\s*\")([^\"]+)(\")',
    r'\g<1>' + ver + r'\3',
    txt
)
open(path, 'w').write(txt)
print('tools.json: zsh version -> ' + ver)
" "$TOOLS_JSON" "$ver"

# Update strip manifest
echo "Running strip_all_elf_binaries..."
"$REPO/strip_all_elf_binaries"

# glibc check
MAX_GLIBC="$(readelf -V "$INSTALL_PREFIX/bin/zsh" 2>/dev/null \
    | grep -oE 'GLIBC_[0-9]+\.[0-9]+' | sort -V | tail -1)"
echo "Max glibc symbol: $MAX_GLIBC (target: GLIBC_2.28)"
case "$MAX_GLIBC" in
    GLIBC_2.2[0-8]|GLIBC_2.1[0-9]|GLIBC_2.[0-9])
        echo "OK — binary compatible with EL8 glibc 2.28" ;;
    *)
        echo "WARNING: $MAX_GLIBC > GLIBC_2.28 — binary may not run on EL8" >&2 ;;
esac

echo ""
echo "Installed: $BIN_DIR/zsh.bz2"
echo ""
echo "Commit with:"
echo "  git add pre_built/el8.x86_64.glibc2p28/bin/zsh.bz2 \\"
echo "          .strip-manifest pre_built/tools.json"
echo "  git commit -m 'feat(pre_built): zsh ${ver} stable EL8 source build'"
