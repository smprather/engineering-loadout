#!/bin/sh
# Build neovide (GPU-accelerated Neovim GUI) from source for el8.x86_64.glibc2p28.
#
# The upstream binary requires GLIBC_2.29 and GLIBCXX_3.4.29 — both exceed
# EL8's glibc 2.28 / GLIBCXX_3.4.25.  Source build on EL8 produces a binary
# that satisfies EL8 symbol versions.
#
# Three build-time requirements that EL8 system packages cannot satisfy:
#   1. GLIBCXX_3.4.26+ (Skia C++ objects): fixed by -static-libstdc++ from
#      gcc-toolset-14 — embeds GCC 14 C++ runtime, no runtime dep.
#   2. FT_Palette_Data_Get / FT_Palette_Select / FT_Get_Color_Glyph_Layer
#      (Skia color emoji): EL8 ships FreeType 2.9.1; these APIs added in 2.10.
#      Fixed by building FreeType 2.13 from source.  libfreetype.so.6 is also
#      bundled alongside neovide in lib64/ so target EL8 machines pick it up
#      via RPATH $ORIGIN/../lib64 instead of the system 2.9.1.
#   3. SKIA_BUILD_FROM_SOURCE=1: rebuilds Skia on EL8 so glibc symbols ≤2.28.
#
# X11, Wayland, GL, and Vulkan are all dlopen'd at runtime — gui_libs covers them.
#
# Policy: always build from a stable tagged release. Never build from
# an untagged HEAD or dev branch. See stable tags at:
#   https://github.com/neovide/neovide/releases
#
# Prerequisites on the build machine (EL8 / AlmaLinux 8):
#   sudo dnf install epel-release
#   sudo dnf config-manager --set-enabled powertools
#   sudo dnf install cmake fontconfig-devel libxkbcommon-devel wayland-devel \
#                    pkg-config git openssl-devel patchelf bzip2 curl python3 make \
#                    ninja-build libpng-devel bzip2-devel zlib-devel \
#                    gcc-toolset-14 gcc-toolset-14-gcc gcc-toolset-14-gcc-c++
#   # FreeType 2.13 from source (EL8 has 2.9.1 — too old for Skia color emoji):
#   #   curl -fsSL https://download.savannah.gnu.org/releases/freetype/freetype-2.13.3.tar.xz | tar xJ
#   #   cd freetype-2.13.3 && source /opt/rh/gcc-toolset-14/enable
#   #   ./configure --prefix=/usr/local --enable-shared --disable-static \
#   #       --with-bzip2 --with-png --without-harfbuzz
#   #   make -j$(nproc) && sudo make install && sudo ldconfig /usr/local/lib
#   # Rust via rustup (system Rust on EL8 too old for neovide):
#   curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
#
# Usage (run from any directory — script clones neovide automatically):
#   /path/to/build-neovide.sh --tag 0.16.2
#   /path/to/build-neovide.sh --tag 0.16.2 --clean   # wipe target/ first
#
# After a successful build the script strips, patchelfs, bzip2s, and installs:
#   pre_built/el8.x86_64.glibc2p28/bin/neovide.bz2
#   pre_built/el8.x86_64.glibc2p28/lib64/libfreetype.so.6.bz2

set -eu

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
BIN_DIR="$REPO/pre_built/el8.x86_64.glibc2p28/bin"
LIB_DIR="$REPO/pre_built/el8.x86_64.glibc2p28/lib64"
PATCHELF="${PATCHELF:-$HOME/.local/bin/patchelf}"
JOBS="${JOBS:-$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 8)}"
CLONE_URL="https://github.com/neovide/neovide.git"

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
    echo "  $0 --tag 0.16.2" >&2
    echo "" >&2
    echo "Stable releases: https://github.com/neovide/neovide/releases" >&2
    echo "" >&2
    echo "Policy: this project ships stable releases only." >&2
    exit 1
fi

# ── toolchain setup ───────────────────────────────────────────────────────────

if [ -r /opt/rh/gcc-toolset-14/enable ]; then
    # shellcheck disable=SC1091
    . /opt/rh/gcc-toolset-14/enable
fi

# Ensure rustup Rust is on PATH (system Rust on EL8 is too old for neovide).
if [ -f "$HOME/.cargo/env" ]; then
    # shellcheck disable=SC1091
    . "$HOME/.cargo/env"
fi

need() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "missing required command: $1 — install the prerequisite packages listed in this script's header" >&2
        exit 1
    }
}

need cargo
need cmake
need pkg-config
need git
need strip
need patchelf 2>/dev/null || need "$PATCHELF"
PATCHELF_BIN="$(command -v patchelf 2>/dev/null || echo "$PATCHELF")"

pkg-config --exists fontconfig 2>/dev/null || {
    echo "fontconfig not found via pkg-config — install fontconfig-devel" >&2
    exit 1
}

# FreeType 2.13 must be installed to /usr/local (see prerequisites in header).
ft_ver="$(pkg-config --modversion freetype2 2>/dev/null || echo 0)"
case "$ft_ver" in
    2.9*|2.10*|2.11*|2.12*|0)
        echo "ERROR: FreeType $ft_ver too old — Skia color emoji requires FT_Palette_Data_Get (2.10+)." >&2
        echo "Build FreeType 2.13 from source and install to /usr/local (see script header)." >&2
        exit 1
        ;;
esac
echo "FreeType $ft_ver OK"
export PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
export LIBRARY_PATH="/usr/local/lib:${LIBRARY_PATH:-}"

# Rust version check — neovide requires a reasonably recent stable.
rustc_ver="$(rustc --version | awk '{print $2}')"
echo "Using Rust $rustc_ver"

# ── source checkout ───────────────────────────────────────────────────────────

SRCDIR="/tmp/neovide-build-${tag}"

if [ ! -d "$SRCDIR/.git" ]; then
    echo "Cloning $CLONE_URL ..."
    git clone --filter=blob:none "$CLONE_URL" "$SRCDIR"
fi

cd "$SRCDIR"
git fetch --tags
git checkout "$tag"

# ── build ─────────────────────────────────────────────────────────────────────

if [ "$clean" -eq 1 ] && [ -d target ]; then
    rm -rf target
fi

GTS14_LIBDIR=""
if [ -r /opt/rh/gcc-toolset-14/enable ]; then
    GTS14_LIBDIR="$(gcc --print-file-name=libstdc++.a 2>/dev/null | xargs dirname 2>/dev/null || true)"
fi
RUSTFLAGS="-C link-arg=-static-libstdc++"
if [ -n "$GTS14_LIBDIR" ]; then
    RUSTFLAGS="$RUSTFLAGS -C link-arg=-L${GTS14_LIBDIR}"
fi
export RUSTFLAGS SKIA_BUILD_FROM_SOURCE=1
CARGO_JOBS="$JOBS" cargo build --release --locked

BIN="$SRCDIR/target/release/neovide"
echo ""
echo "Build complete: $("$BIN" --version 2>/dev/null || echo '(--version unsupported)')"
echo "Binary size:    $(ls -lh "$BIN" | awk '{print $5}') unstripped"
echo ""

# ── package ───────────────────────────────────────────────────────────────────

WORK="/tmp/neovide_tmp_${tag}"
cp "$BIN" "$WORK"

strip "$WORK"
echo "After strip: $(ls -lh "$WORK" | awk '{print $5}')"

"$PATCHELF_BIN" --set-rpath '$ORIGIN/../lib64:$ORIGIN/../lib' "$WORK"
echo "RPATH set."

bzip2_size() { bzip2 -k "$1" && ls -lh "${1}.bz2" | awk '{print $5}'; }
echo "Compressed:  $(bzip2_size "$WORK")"

cp "${WORK}.bz2" "$BIN_DIR/neovide.bz2"
echo "Installed: $BIN_DIR/neovide.bz2"

# ── bundle libfreetype.so.6 ───────────────────────────────────────────────────
# EL8 system has FreeType 2.9.1; we built 2.13 to /usr/local.  Bundle it so
# target EL8 machines pick it up via RPATH $ORIGIN/../lib64.

FT_SO="$(ls /usr/local/lib/libfreetype.so.6.* 2>/dev/null | head -1 || true)"
if [ -z "$FT_SO" ]; then
    echo "WARNING: /usr/local/lib/libfreetype.so.6.* not found — skipping libfreetype bundle." >&2
else
    FT_WORK="/tmp/libfreetype.so.6"
    cp "$FT_SO" "$FT_WORK"
    strip "$FT_WORK"
    "$PATCHELF_BIN" --set-rpath '$ORIGIN' "$FT_WORK"
    bzip2 -k "$FT_WORK"
    cp "${FT_WORK}.bz2" "$LIB_DIR/libfreetype.so.6.bz2"
    echo "Installed: $LIB_DIR/libfreetype.so.6.bz2"
fi
echo ""

# ── update packages.json version ─────────────────────────────────────────────

TOOLS_JSON="$REPO/pre_built/packages.json"
python3 - "$TOOLS_JSON" "$tag" <<'PYEOF'
import re, sys
path, ver = sys.argv[1], sys.argv[2]
txt = open(path).read()
txt = re.sub(
    r'("neovide".*?"version":\s*")([^"]+)(")',
    r'\g<1>' + ver + r'\3',
    txt,
)
open(path, "w").write(txt)
print("packages.json: neovide version ->", ver)
PYEOF

# ── strip manifest ────────────────────────────────────────────────────────────

echo "Running strip_all_elf_binaries..."
"$REPO/strip_all_elf_binaries"

echo "Done. Commit with:"
echo "  git add pre_built/el8.x86_64.glibc2p28/bin/neovide.bz2 \\"
echo "          pre_built/el8.x86_64.glibc2p28/lib64/libfreetype.so.6.bz2 \\"
echo "          .strip-manifest pre_built/packages.json"
echo "  git commit -m 'feat(pre_built): neovide ${tag} EL8 source build'"
