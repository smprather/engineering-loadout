#!/bin/sh
# Build GNU coreutils from source for el8.x86_64.glibc2p28.
#
# Produces individual binaries (ls, cp, mv, rm, ...) in:
#   pre_built/el8.x86_64.glibc2p28/bin/<name>.bz2
#
# Runtime deps (system on all EL8, never bundled):
#   libc.so.6, libpthread.so.0 (glibc — always present)
#
# Configure skips acl, selinux, gmp to keep deps at glibc-only.
# libacl/libselinux are NOT guaranteed on all compute fleet nodes.
#
# Build-time deps (system, EL8):
#   gcc (toolset-14 preferred), make, autoconf, automake
#
# Tarballs: https://ftp.gnu.org/gnu/coreutils/
#
# Usage (run from repo root or any directory):
#   pre_built/build_scripts/build-gnu-coreutils.sh --tag 9.6

set -eu

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BIN_DIR="$REPO_ROOT/pre_built/el8.x86_64.glibc2p28/bin"

TAG=""

while [ $# -gt 0 ]; do
    case "$1" in
        --tag) TAG="$2"; shift 2 ;;
        *) echo "Usage: $0 --tag <version>"; exit 1 ;;
    esac
done

if [ -z "$TAG" ]; then
    echo "Error: --tag <version> is required (e.g. --tag 9.6)" >&2
    exit 1
fi

# Source GCC 14 if available
if [ -f /opt/rh/gcc-toolset-14/enable ]; then
    . /opt/rh/gcc-toolset-14/enable
fi

WORK_DIR="/tmp/gnu-coreutils-build-$$"
INSTALL_DIR="/tmp/gnu-coreutils-install-$$"
mkdir -p "$WORK_DIR" "$INSTALL_DIR"
trap 'rm -rf "$WORK_DIR" "$INSTALL_DIR"' EXIT

cd "$WORK_DIR"

echo "==> Downloading coreutils-${TAG}.tar.xz ..."
curl -L -o coreutils.tar.xz \
    "https://ftp.gnu.org/gnu/coreutils/coreutils-${TAG}.tar.xz"

echo "==> Extracting ..."
tar xJf coreutils.tar.xz
cd "coreutils-${TAG}"

echo "==> Configuring (no acl, no selinux, no gmp) ..."
./configure \
    --prefix="$INSTALL_DIR" \
    --disable-acl \
    --without-selinux \
    --without-gmp \
    --enable-single-binary=no

echo "==> Building ..."
make -j"$(nproc)"

echo "==> Installing ..."
make install

echo "==> Packaging binaries ..."
# The registry is the single source of truth for which coreutils programs we ship.
# coreutils builds ~106 programs; we curate a subset (e.g. excluding builtin-shadowing
# kill/pwd/[/printenv and rarely-wanted chroot/pinky/...). Read packages.json
# gnu-coreutils.bins and copy ONLY those — so the build output always equals the
# registry, with no hand-maintained skip list to drift.
WANTED_BINS="$(python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))['packages']['gnu-coreutils']
print(' '.join(d.get('bins', [])))
" "$REPO_ROOT/pre_built/packages.json")"
if [ -z "$WANTED_BINS" ]; then
    echo "ERROR: gnu-coreutils.bins empty in packages.json — refusing to ship the full set" >&2
    exit 1
fi

for bin in "$INSTALL_DIR/bin/"*; do
    name="$(basename "$bin")"
    # Ship only registry-listed programs.
    case " $WANTED_BINS " in
        *" $name "*) : ;;
        *) echo "  skip (not in registry): $name"; continue ;;
    esac
    # Skip non-ELF (scripts).
    file_type="$(file "$bin" | grep -o 'ELF\|shell script\|Python')"
    if [ "$file_type" != "ELF" ]; then
        echo "  skip (not ELF): $name"
        continue
    fi

    # Check glibc max symbol — must be ≤ 2.28
    max_glibc="$(readelf -V "$bin" 2>/dev/null | grep -oE 'GLIBC_[0-9]+\.[0-9]+' | sort -V | tail -1)"
    echo "  $name: max glibc=$max_glibc"

    # Strip → compress (no patchelf needed — links only against libc which is system)
    /usr/bin/strip "$bin"
    bzip2 -k "$bin"
    cp "${bin}.bz2" "$BIN_DIR/${name}.bz2"
    chmod 644 "$BIN_DIR/${name}.bz2"
done

echo ""
echo "Done. Binaries written to $BIN_DIR/"
echo "Next steps:"
echo "  cd $REPO_ROOT"
echo "  ./strip_all_elf_binaries"
echo "  # Update packages.json version to ${TAG}"
echo "  git add pre_built/el8.x86_64.glibc2p28/bin/ .strip-manifest"
echo "  git commit -m 'feat(gnu-coreutils): add GNU coreutils ${TAG}'"
