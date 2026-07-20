#!/bin/sh
# Build fish shell from source for el8.x86_64.glibc2p28.
#
# fish 4.x is written in Rust; this script handles both the cmake+cargo
# build (4.x) and the older cmake+C++ build (3.x) transparently.
#
# WHERE THE STANDARD LIBRARY LIVES (changed in fish 4.8):
#   fish <= 4.7 installed its standard library (functions/, completions/,
#   prompts/, themes/, tools/) into <prefix>/share/fish, and this script packaged
#   that tree into fish.tar.bz2.
#
#   fish 4.8 EMBEDS the standard library in the binary. Upstream deleted the
#   install(DIRECTORY share/...) rules from cmake/Install.cmake, so `ninja install`
#   now populates share/fish with nothing but the empty vendor_*.d drop-in dirs.
#   That is correct, not a build failure: the shipped binary defines fish_prompt,
#   carries the full function set, and completes -- with no share/fish data at all.
#
#   The runtime archive is therefore now just the vendor_*.d drop-in dirs (where
#   third-party packages leave completions). The guard below asserts the thing that
#   actually matters -- that the built fish has a working standard library -- rather
#   than asserting a file layout that upstream is free to move again. The 4.8.0 bump
#   shipped a 342-byte archive with no stdlib and nothing noticed, because the only
#   check was a registry sentinel pointing at a file that no longer exists.
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

REPO="$(cd "$(dirname "$0")/.." && pwd)"
BIN_DIR="$REPO/payload/el8.x86_64.glibc2p28/bin"
RUNTIME_DIR="$REPO/payload/el8.x86_64.glibc2p28/runtime"
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
        echo "missing required command: $1 -- install the prerequisite packages listed in this script's header" >&2
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
if ! git rev-parse "$tag" >/dev/null 2>&1; then
    git fetch --tags
fi
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
    -DWITH_DOCS=OFF \
    -G Ninja

echo "Building fish..."
ninja -C build -j"$(nproc 2>/dev/null || echo 8)"
ninja -C build install

echo ""
echo "Build complete: $("$INSTALL_PREFIX/bin/fish" --version 2>&1 | head -1)"
echo ""

# Assert the built fish actually has a usable standard library, wherever upstream
# keeps it this release (embedded in the binary since 4.8, on disk before that).
# Without this, a build that installs no stdlib still "succeeds" and ships a shell
# with no prompt and no completions -- which is exactly what the 4.8.0 bump did.
echo "Verifying the standard library is present..."
if ! "$INSTALL_PREFIX/bin/fish" -c 'type -q fish_prompt; and test (functions | count) -gt 20' 2>/dev/null; then
    echo "ERROR: the built fish has no usable standard library." >&2
    echo "  fish_prompt is undefined, or it defines fewer than 20 functions." >&2
    echo "  Either the stdlib install rules moved again upstream, or the build is broken." >&2
    echo "  Do NOT ship this: a fish with no stdlib has no prompt and no completions." >&2
    exit 1
fi
echo "  OK: fish_prompt defined, $("$INSTALL_PREFIX/bin/fish" -c 'functions | count') functions available"
echo ""

# Package the binary
WORK="/tmp/fish_work_${tag}"
cp "$INSTALL_PREFIX/bin/fish" "$WORK"
strip "$WORK"
"$PATCHELF" --set-rpath '$ORIGIN/../lib64:$ORIGIN/../lib' "$WORK"
bzip2 -kf "$WORK"
cp "${WORK}.bz2" "$BIN_DIR/fish.bz2"
rm -f "$WORK" "${WORK}.bz2"

# Package the runtime. Since 4.8 this is only the vendor_*.d drop-in dirs (the
# stdlib is inside the binary); on older tags it also carries functions/,
# completions/, prompts/ and themes/. Report what actually went in, so a tag bump
# that changes the layout is visible in the build log instead of silent.
echo "Packaging runtime..."
echo "  share/fish contents: $(find "$INSTALL_PREFIX/share/fish" -mindepth 1 -maxdepth 1 -printf '%f ' 2>/dev/null)"
echo "  ($(find "$INSTALL_PREFIX/share/fish" -type f 2>/dev/null | wc -l) files; 0 is expected on fish >= 4.8 -- see the header)"
tar -cjf /tmp/fish_runtime_"${tag}".tar.bz2 \
    -C "$INSTALL_PREFIX" \
    --exclude='./share/fish/man' \
    --exclude='./share/doc' \
    --exclude='./share/locale' \
    ./share/fish
cp /tmp/fish_runtime_"${tag}".tar.bz2 "$RUNTIME_DIR/fish.tar.bz2"
rm -f /tmp/fish_runtime_"${tag}".tar.bz2

# Update packages.json version
ver="${tag}"
TOOLS_JSON="$REPO/payload/packages.json"
python3 -c "
import json, sys
path, ver = sys.argv[1], sys.argv[2]
with open(path) as f:
    data = json.load(f)
data['packages']['fish']['version'] = ver
with open(path, 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
print('packages.json: fish version -> ' + ver)
" "$TOOLS_JSON" "$ver"

# Update strip manifest
echo "Running strip-all-elf-binaries..."
"$REPO/strip-all-elf-binaries"

# glibc check
MAX_GLIBC="$(readelf -V "$INSTALL_PREFIX/bin/fish" 2>/dev/null \
    | grep -oE 'GLIBC_[0-9]+\.[0-9]+' | sort -V | tail -1)"
echo "Max glibc symbol: $MAX_GLIBC (target: GLIBC_2.28)"
case "$MAX_GLIBC" in
    GLIBC_2.2[0-8]|GLIBC_2.1[0-9]|GLIBC_2.[0-9])
        echo "OK -- binary compatible with EL8 glibc 2.28" ;;
    *)
        echo "WARNING: $MAX_GLIBC > GLIBC_2.28 -- binary may not run on EL8" >&2 ;;
esac

echo ""
echo "Installed: $BIN_DIR/fish.bz2"
echo "Runtime:   $RUNTIME_DIR/fish.tar.bz2"
echo ""
echo "Then add installer logic in install (search for 'fish_runtime' or 'meld_runtime' for pattern)."
echo ""
echo "Commit with:"
echo "  git add payload/el8.x86_64.glibc2p28/bin/fish.bz2 \\"
echo "          payload/el8.x86_64.glibc2p28/runtime/fish.tar.bz2 \\"
echo "          .strip-manifest payload/packages.json"
echo "  git commit -m 'feat(payload): fish ${ver} stable EL8 source build'"
