#!/bin/sh
# Build nvim-qt (official Qt5 GUI frontend for Neovim) from source for el8.x86_64.glibc2p28.
#
# nvim-qt is simpler than neovide: CMake + Qt5, no Rust, no GPU renderer.
# EL8 system Qt5 (5.12.x) is sufficient for the build; at runtime the binary
# resolves Qt5 libs from ~/.local/lib64 (gui_libs) via RPATH $ORIGIN/../lib64,
# so users get Qt5 5.15.3 without any system Qt5 install required.
#
# Policy: always build from a stable tagged release. Never build from
# an untagged HEAD or dev branch. See stable tags at:
#   https://github.com/equalsraf/neovim-qt/releases
#
# Prerequisites on the build machine (EL8 / AlmaLinux 8):
#   sudo dnf install epel-release
#   sudo dnf config-manager --set-enabled powertools
#   sudo dnf install cmake git gcc gcc-c++ patchelf bzip2 \
#                    qt5-qtbase-devel qt5-qtsvg-devel
#
# Usage (run from any directory -- script clones neovim-qt automatically):
#   /path/to/build-nvim-qt.sh --tag 0.2.19
#   /path/to/build-nvim-qt.sh --tag 0.2.19 --clean   # wipe build/ first
#
# After a successful build the script strips, patchelfs, bzip2s, and installs:
#   payload/el8.x86_64.glibc2p28/bin/nvim-qt.bz2

set -eu

REPO="$(cd "$(dirname "$0")/.." && pwd)"
BIN_DIR="$REPO/payload/el8.x86_64.glibc2p28/bin"
PATCHELF="${PATCHELF:-$HOME/.local/bin/patchelf}"
JOBS="${JOBS:-$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 8)}"
CLONE_URL="https://github.com/equalsraf/neovim-qt.git"

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
    echo "  $0 --tag 0.2.19" >&2
    echo "" >&2
    echo "Stable releases: https://github.com/equalsraf/neovim-qt/releases" >&2
    echo "" >&2
    echo "Policy: this project ships stable releases only." >&2
    exit 1
fi

# -- toolchain setup -----------------------------------------------------------

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

need cmake
need git
need strip
need patchelf 2>/dev/null || need "$PATCHELF"
PATCHELF_BIN="$(command -v patchelf 2>/dev/null || echo "$PATCHELF")"

pkg-config --exists Qt5Core 2>/dev/null || {
    echo "Qt5Core not found via pkg-config -- install qt5-qtbase-devel" >&2
    exit 1
}

# -- source checkout -----------------------------------------------------------

SRCDIR="/tmp/nvim-qt-build-${tag}"

if [ ! -d "$SRCDIR/.git" ]; then
    echo "Cloning $CLONE_URL ..."
    git clone --filter=blob:none "$CLONE_URL" "$SRCDIR"
fi

cd "$SRCDIR"
git fetch --tags
git checkout "v${tag}"

# -- build ---------------------------------------------------------------------

if [ "$clean" -eq 1 ] && [ -d build ]; then
    rm -rf build
fi

cmake -B build -S . \
    -DCMAKE_BUILD_TYPE=Release \
    -DENABLE_TESTS=OFF \
    -DCMAKE_SKIP_RPATH=ON
cmake --build build -j"$JOBS"

BIN="$SRCDIR/build/bin/nvim-qt"
echo ""
echo "Build complete: $BIN"
echo "Binary size:    $(ls -lh "$BIN" | awk '{print $5}') unstripped"
echo ""

# -- package -------------------------------------------------------------------

WORK="/tmp/nvim-qt_tmp_${tag}"
cp "$BIN" "$WORK"

strip "$WORK"
echo "After strip: $(ls -lh "$WORK" | awk '{print $5}')"

"$PATCHELF_BIN" --set-rpath '$ORIGIN/../lib64:$ORIGIN/../lib' "$WORK"
echo "RPATH set."

bzip2_size() { bzip2 -k "$1" && ls -lh "${1}.bz2" | awk '{print $5}'; }
echo "Compressed:  $(bzip2_size "$WORK")"

cp "${WORK}.bz2" "$BIN_DIR/nvim-qt.bz2"
echo ""
echo "Installed: $BIN_DIR/nvim-qt.bz2"

# -- update packages.json version ---------------------------------------------

TOOLS_JSON="$REPO/payload/packages.json"
python3 - "$TOOLS_JSON" "$tag" <<'PYEOF'
import json, sys
path, ver = sys.argv[1], sys.argv[2]
with open(path) as f:
    data = json.load(f)
data['packages']['nvim-qt']['version'] = ver
with open(path, 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
print('packages.json: nvim-qt version -> ' + ver)
PYEOF

# -- strip manifest ------------------------------------------------------------

echo "Running strip-all-elf-binaries..."
"$REPO/strip-all-elf-binaries"

echo ""
echo "Done. Commit with:"
echo "  git add payload/el8.x86_64.glibc2p28/bin/nvim-qt.bz2 .strip-manifest payload/packages.json"
echo "  git commit -m 'feat(payload): nvim-qt ${tag} EL8 build'"
