#!/bin/sh
# Build nedit-ng (Qt5 NEdit rewrite) from source for el8.x86_64.glibc2p28.
#
# nedit-ng is a single binary linking only against system Qt5/X11 libs;
# no bundled libs needed. Added to pre_built as optional tool.
#
# Policy: always build from a stable tagged release. Never build from
# an untagged HEAD or dev branch. See stable tags at:
#   https://github.com/eteran/nedit-ng/releases
#
# Prerequisites on the build machine:
#   sudo dnf install cmake gcc-c++ \
#                    qt5-qtbase-devel qt5-qtsvg-devel \
#                    libXt-devel git
#   # gcc-toolset-14 optional but recommended for consistent ABI
#
# Usage (run from any directory — script clones nedit-ng automatically):
#   /path/to/build-nedit-ng.sh --tag 2025.1
#   /path/to/build-nedit-ng.sh --tag 2025.1 --clean   # wipe build/ first
#
# After a successful build the script packages and installs the binary.

set -eu

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
BIN_DIR="$REPO/pre_built/el8.x86_64.glibc2p28/bin"
JOBS="${JOBS:-$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 8)}"
CLONE_URL="https://github.com/eteran/nedit-ng.git"

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
    echo "  $0 --tag 2025.1" >&2
    echo "" >&2
    echo "Stable releases: https://github.com/eteran/nedit-ng/releases" >&2
    echo "" >&2
    echo "Policy: this project ships stable releases only." >&2
    exit 1
fi

# ── prerequisite checks ───────────────────────────────────────────────────────

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

need cmake
need g++
need git
pkg-config --exists Qt5Widgets 2>/dev/null || {
    echo "Qt5Widgets not found via pkg-config — install qt5-qtbase-devel" >&2
    exit 1
}

# ── source checkout ───────────────────────────────────────────────────────────

# Run inside a dedicated clone dir under /tmp so we never dirty the loadout repo
SRCDIR="/tmp/nedit-ng-build-${tag}"

if [ ! -d "$SRCDIR/.git" ]; then
    echo "Cloning $CLONE_URL ..."
    git clone --filter=blob:none "$CLONE_URL" "$SRCDIR"
fi

cd "$SRCDIR"
git fetch --tags
git checkout "$tag"

# ── build ─────────────────────────────────────────────────────────────────────

if [ "$clean" -eq 1 ] && [ -d build ]; then
    rm -rf build
fi

cmake -B build \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_CXX_FLAGS="-O2 -Wall" \
    -DBUILD_SHARED_LIBS=OFF

cmake --build build -j"$JOBS"

echo ""
echo "Build complete: $(./build/nedit-ng --version 2>/dev/null || echo '(--version not supported)')"
echo ""
echo "Binary size: $(ls -lh build/nedit-ng | awk '{print $5}') unstripped"
echo ""

# ── package ───────────────────────────────────────────────────────────────────

WORK="/tmp/nedit-ng_tmp_${tag}"
cp build/nedit-ng "$WORK"
strip "$WORK"
ls -lh "$WORK"
bzip2 -kf "$WORK"
cp "${WORK}.bz2" "$BIN_DIR/nedit-ng.bz2"

echo ""
echo "Installed: $BIN_DIR/nedit-ng.bz2"

# ── update packages.json ─────────────────────────────────────────────────────────

TOOLS_JSON="$REPO/pre_built/packages.json"
python3 -c "
import re, sys
path = sys.argv[1]; ver = sys.argv[2]
txt = open(path).read()
txt = re.sub(
    r'(\"nedit-ng\".*?\"version\":\s*\")([^\"]+)(\")',
    r'\g<1>' + ver + r'\3',
    txt
)
open(path, 'w').write(txt)
print('packages.json: nedit-ng version -> ' + ver)
" "$TOOLS_JSON" "$tag"

# ── strip manifest ────────────────────────────────────────────────────────────

echo "Running strip_all_elf_binaries..."
"$REPO/strip_all_elf_binaries"

echo ""
echo "Done. Commit with:"
echo "  git add pre_built/el8.x86_64.glibc2p28/bin/nedit-ng.bz2 .strip-manifest pre_built/packages.json"
echo "  git commit -m 'feat(pre_built): nedit-ng ${tag} stable EL8 source build'"
