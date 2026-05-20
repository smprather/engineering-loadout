#!/bin/sh
# Build fish shell from source for el8.x86_64.glibc2p28.
#
# fish 4.x is written in Rust; this script handles both the cmake+cargo
# build (4.x) and the older cmake+C++ build (3.x) transparently.
#
# Runtime data files (functions/, completions/, themes/) are packaged as
# fish-runtime.tar.bz2 and installed to ~/.local/share/fish/ so that the
# binary finds its standard library without any $SHARE_DIR patching.
#
# Bundled libs used at runtime: libncurses.so.6, libpcre2-8.so.0
#
# Policy: always build from a stable tagged release. See stable tags at:
#   https://github.com/fish-shell/fish-shell/releases
#
# Prerequisites on the build machine (EL8):
#   sudo dnf install cmake ninja-build gcc gcc-c++ gettext pcre2-devel \
#                    ncurses-devel
#   # For fish 4.x (Rust): also install rust cargo via rustup or dnf
#   # cargo install or dnf install rust cargo
#   # gcc-toolset-14 optional but recommended for consistent ABI
#
# Usage (run from any directory):
#   /path/to/build-fish.sh --tag 4.0.2

set -eu

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
BIN_DIR="$REPO/pre_built/el8.x86_64.glibc2p28/bin"
RUNTIME_DIR="$REPO/pre_built/el8.x86_64.glibc2p28/runtime"
PATCHELF="${HOME}/.local/bin/patchelf"
CLONE_URL="https://github.com/fish-shell/fish-shell.git"
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
    echo "  $0 --tag 4.0.2" >&2
    echo "" >&2
    echo "Stable releases: https://github.com/fish-shell/fish-shell/releases" >&2
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

need "$CMAKE"
need gcc

SRCDIR="/tmp/fish-src-${tag}"
INSTALL_PREFIX="/tmp/fish-install-${tag}"

if [ ! -d "$SRCDIR/.git" ]; then
    echo "Cloning $CLONE_URL ..."
    git clone --filter=blob:none "$CLONE_URL" "$SRCDIR"
fi

cd "$SRCDIR"
git fetch --tags
git checkout "$tag"

if [ "$clean" -eq 1 ]; then
    rm -rf build
fi

rm -rf "$INSTALL_PREFIX"

echo "Configuring fish..."
"$CMAKE" -S . -B build \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$INSTALL_PREFIX" \
    -DCMAKE_INSTALL_SYSCONFDIR="$INSTALL_PREFIX/etc" \
    -DBUILD_DOCS=OFF \
    -G Ninja

echo "Building fish..."
ninja -C build -j"$(nproc 2>/dev/null || echo 8)"
ninja -C build install

echo ""
echo "Build complete: $("$INSTALL_PREFIX/bin/fish" --version 2>&1 | head -1)"
echo ""

# Package the binary
WORK="/tmp/fish_work_${tag}"
cp "$INSTALL_PREFIX/bin/fish" "$WORK"
strip "$WORK"
"$PATCHELF" --set-rpath '$ORIGIN/../lib64:$ORIGIN/../lib' "$WORK"
bzip2 -kf "$WORK"
cp "${WORK}.bz2" "$BIN_DIR/fish.bz2"
rm -f "$WORK" "${WORK}.bz2"

# Package the runtime (share/fish: functions, completions, themes, etc.)
echo "Packaging runtime..."
tar -cjf /tmp/fish_runtime_"${tag}".tar.bz2 \
    -C "$INSTALL_PREFIX" \
    --exclude='./share/fish/man' \
    --exclude='./share/doc' \
    --exclude='./share/locale' \
    ./share/fish
cp /tmp/fish_runtime_"${tag}".tar.bz2 "$RUNTIME_DIR/fish.tar.bz2"
rm -f /tmp/fish_runtime_"${tag}".tar.bz2

# Update tools.json version
ver="${tag}"
TOOLS_JSON="$REPO/pre_built/tools.json"
python3 -c "
import re, sys
path = sys.argv[1]; ver = sys.argv[2]
txt = open(path).read()
txt = re.sub(
    r'(\"fish\".*?\"version\":\s*\")([^\"]+)(\")',
    r'\g<1>' + ver + r'\3',
    txt
)
open(path, 'w').write(txt)
print('tools.json: fish version -> ' + ver)
" "$TOOLS_JSON" "$ver"

# Update strip manifest
echo "Running strip_all_elf_binaries..."
"$REPO/strip_all_elf_binaries"

# glibc check
MAX_GLIBC="$(readelf -V "$INSTALL_PREFIX/bin/fish" 2>/dev/null \
    | grep -oE 'GLIBC_[0-9]+\.[0-9]+' | sort -V | tail -1)"
echo "Max glibc symbol: $MAX_GLIBC (target: GLIBC_2.28)"
case "$MAX_GLIBC" in
    GLIBC_2.2[0-8]|GLIBC_2.1[0-9]|GLIBC_2.[0-9])
        echo "OK — binary compatible with EL8 glibc 2.28" ;;
    *)
        echo "WARNING: $MAX_GLIBC > GLIBC_2.28 — binary may not run on EL8" >&2 ;;
esac

echo ""
echo "Installed: $BIN_DIR/fish.bz2"
echo "Runtime:   $RUNTIME_DIR/fish.tar.bz2"
echo ""
echo "Then add installer logic in install (search for 'fish_runtime' or 'meld_runtime' for pattern)."
echo ""
echo "Commit with:"
echo "  git add pre_built/el8.x86_64.glibc2p28/bin/fish.bz2 \\"
echo "          pre_built/el8.x86_64.glibc2p28/runtime/fish.tar.bz2 \\"
echo "          .strip-manifest pre_built/tools.json"
echo "  git commit -m 'feat(pre_built): fish ${ver} stable EL8 source build'"
