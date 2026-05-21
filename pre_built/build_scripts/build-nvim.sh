#!/bin/sh
# Build Neovim from source for el8.x86_64.glibc2p28.
#
# Targets a Release build with bundled deps (luajit, luv, libuv,
# tree-sitter, etc.) so the resulting binary links only against
# system glibc ≤ 2.28 — no bundled libs needed.
#
# Note: official Neovim prebuilts require GLIBC_2.34+. EL8 provides
# glibc 2.28, so source builds from stable tags are required permanently.
#
# Note: system luajit (if installed) may have an incompatible bytecode
# format with the bundled luajit. This script always builds and uses the
# bundled luajit to avoid "E970: Failed to initialize builtin Lua modules".
#
# Policy: always build from a stable tagged release. See stable tags at:
#   https://github.com/neovim/neovim/releases
#
# Prerequisites on the build machine:
#   sudo dnf install cmake ninja-build gcc gcc-c++ make \
#                    gettext gettext-devel
#   # gcc-toolset-14 optional but recommended for consistent ABI
#
# Usage (run from any directory — script clones neovim automatically):
#   /path/to/build-nvim.sh --tag v0.12.2
#   /path/to/build-nvim.sh --tag v0.12.2 --clean   # wipe build dirs first

set -eu

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
BIN_DIR="$REPO/pre_built/el8.x86_64.glibc2p28/bin"
RUNTIME_DIR="$REPO/pre_built/el8.x86_64.glibc2p28/runtime"
PATCHELF="${HOME}/.local/bin/patchelf"
CLONE_URL="https://github.com/neovim/neovim.git"
CMAKE="${CMAKE:-cmake}"

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
    echo "  $0 --tag v0.12.2" >&2
    echo "" >&2
    echo "Stable releases: https://github.com/neovim/neovim/releases" >&2
    echo "" >&2
    echo "Policy: this project ships stable releases only." >&2
    echo "Nightly/dev builds are not accepted." >&2
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

need "$CMAKE"
need ninja
need gcc
need g++

# ── source checkout ───────────────────────────────────────────────────────────

SRCDIR="/tmp/neovim-src-${tag}"

if [ ! -d "$SRCDIR/.git" ]; then
    echo "Cloning $CLONE_URL ..."
    git clone --filter=blob:none "$CLONE_URL" "$SRCDIR"
fi

cd "$SRCDIR"
git fetch --tags
git checkout "$tag"

# ── clean ─────────────────────────────────────────────────────────────────────

if [ "$clean" -eq 1 ]; then
    rm -rf .deps build
fi

# ── build bundled deps ────────────────────────────────────────────────────────
# Must build deps before main build so bundled luajit is used as both
# compiler and runtime — system luajit may have incompatible bytecode format.

echo "Building bundled deps..."
"$CMAKE" -S cmake.deps -B .deps -DCMAKE_BUILD_TYPE=Release
"$CMAKE" --build .deps -j"$(nproc 2>/dev/null || echo 8)"

BUNDLED_LUAJIT="$(pwd)/.deps/usr/bin/luajit"

# ── build nvim ────────────────────────────────────────────────────────────────

# Install into /tmp prefix — no sudo needed, runtime lands in a predictable path.
INSTALL_PREFIX="/tmp/nvim-install-${tag}"
rm -rf "$INSTALL_PREFIX"

echo "Configuring nvim..."
DEPS_BUILD_DIR="$(pwd)/.deps" "$CMAKE" -B build \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$INSTALL_PREFIX" \
    -DENABLE_TRANSLATIONS=OFF \
    -DLUA_PRG="$BUNDLED_LUAJIT" \
    -G Ninja

echo "Building nvim..."
ninja -C build -j"$(nproc 2>/dev/null || echo 8)"
ninja -C build install

echo ""
echo "Build complete: $(./build/bin/nvim --version | head -1)"
echo ""

# ── package ───────────────────────────────────────────────────────────────────

echo "Packaging binary..."
WORK="/tmp/nvim_work_${tag}"
cp "$INSTALL_PREFIX/bin/nvim" "$WORK"
strip "$WORK"
"$PATCHELF" --set-rpath '$ORIGIN/../lib64:$ORIGIN/../lib' "$WORK"
bzip2 -kf "$WORK"
cp "${WORK}.bz2" "$BIN_DIR/nvim.bz2"
rm -f "$WORK" "${WORK}.bz2"

echo "Packaging runtime..."
RUNTIME_SRC="$INSTALL_PREFIX/share/nvim"
[ -f "$RUNTIME_SRC/runtime/filetype.lua" ] || {
    echo "ERROR: runtime/filetype.lua not found in $RUNTIME_SRC" >&2
    exit 1
}
tar -cjf /tmp/nvim_runtime_"${tag}".tar.bz2 -C "$RUNTIME_SRC" ./runtime
cp /tmp/nvim_runtime_"${tag}".tar.bz2 "$RUNTIME_DIR/nvim.tar.bz2"
rm -f /tmp/nvim_runtime_"${tag}".tar.bz2

echo ""
echo "Installed: $BIN_DIR/nvim.bz2"
echo "Runtime:   $RUNTIME_DIR/nvim.tar.bz2"
echo ""

# ── glibc check ──────────────────────────────────────────────────────────────

MAX_GLIBC="$(readelf -V "$INSTALL_PREFIX/bin/nvim" 2>/dev/null \
    | grep -oE 'GLIBC_[0-9]+\.[0-9]+' | sort -V | tail -1)"
echo "Max glibc symbol: $MAX_GLIBC (target: GLIBC_2.28)"
case "$MAX_GLIBC" in
    GLIBC_2.2[0-8]|GLIBC_2.1[0-9]|GLIBC_2.[0-9])
        echo "OK — binary compatible with EL8 glibc 2.28" ;;
    *)
        echo "WARNING: $MAX_GLIBC > GLIBC_2.28 — binary may not run on EL8" >&2 ;;
esac

# ── update packages.json ─────────────────────────────────────────────────────────

ver="${tag#v}"
TOOLS_JSON="$REPO/pre_built/packages.json"
# Use Python (guaranteed available — it's in pre_built) for reliable JSON field update
python3 -c "
import re, sys
path = sys.argv[1]; ver = sys.argv[2]
txt = open(path).read()
txt = re.sub(
    r'(\"nvim\".*?\"version\":\s*\")([^\"]+)(\")',
    r'\g<1>' + ver + r'\3',
    txt
)
open(path, 'w').write(txt)
print('packages.json: nvim version -> ' + ver)
" "$TOOLS_JSON" "$ver"

# ── strip manifest ────────────────────────────────────────────────────────────

echo "Running strip_all_elf_binaries..."
"$REPO/strip_all_elf_binaries"

echo ""
echo "Done. Commit with:"
echo "  git add pre_built/el8.x86_64.glibc2p28/bin/nvim.bz2 \\"
echo "          pre_built/el8.x86_64.glibc2p28/runtime/nvim.tar.bz2 \\"
echo "          .strip-manifest pre_built/packages.json"
echo "  git commit -m 'feat(pre_built): nvim ${ver} stable EL8 source build'"
