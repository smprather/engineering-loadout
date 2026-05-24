#!/bin/sh
# Build neovide (GPU-accelerated Neovim GUI) from source for el8.x86_64.glibc2p28.
#
# The upstream binary requires GLIBC_2.29 and GLIBCXX_3.4.29 — both exceed
# EL8's glibc 2.28 / GLIBCXX_3.4.25.  Source build on EL8 produces a binary
# that satisfies EL8 symbol versions.
#
# neovide links only against system libs always present on EL8
# (fontconfig, freetype, libc).  X11, Wayland, GL, and Vulkan are
# all dlopen'd at runtime — no bundled libs needed.
#
# Policy: always build from a stable tagged release. Never build from
# an untagged HEAD or dev branch. See stable tags at:
#   https://github.com/neovide/neovide/releases
#
# Prerequisites on the build machine:
#   sudo dnf install cmake fontconfig-devel freetype-devel \
#                    libxkbcommon-devel wayland-devel \
#                    pkg-config git
#   # Rust via rustup (not system Rust — too old for neovide):
#   curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
#   # gcc-toolset-14 recommended for consistent C ABI:
#   sudo dnf install gcc-toolset-14
#
# Usage (run from any directory — script clones neovide automatically):
#   /path/to/build-neovide.sh --tag 0.16.2
#   /path/to/build-neovide.sh --tag 0.16.2 --clean   # wipe target/ first
#
# After a successful build the script strips, patchelfs, bzip2s, and
# installs the binary into pre_built/el8.x86_64.glibc2p28/bin/.

set -eu

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
BIN_DIR="$REPO/pre_built/el8.x86_64.glibc2p28/bin"
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

# gcc-toolset-14 for consistent C ABI when compiling C deps (fontconfig etc.).
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
echo ""
echo "Installed: $BIN_DIR/neovide.bz2"

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

echo ""
echo "Done. Commit with:"
echo "  git add pre_built/el8.x86_64.glibc2p28/bin/neovide.bz2 .strip-manifest pre_built/packages.json"
echo "  git commit -m 'feat(pre_built): neovide ${tag} EL8 source build'"
