#!/bin/sh
# Build ngspice (SPICE circuit simulator) from source for el8.x86_64.glibc2p28.
#
# ngspice is built without X11 (--without-x) so the binary works on headless
# farm nodes. Interactive text mode and batch mode (-b) work without a DISPLAY.
# For graphical plots use: ngspice -b -r rawfile.raw && gnuplot (or nutmeg).
#
# XSPICE code models (behavioral elements) and CIDER numerical device
# simulation are enabled -- both are standard for modern EE workflows.
#
# Runtime library requirements (all satisfied by system EL8 or existing bundles):
#   libreadline.so.7    — EL8 system package (readline-7.0, always installed)
#   libncurses.so.6     — EL8 system package (always installed)
#   libfftw3.so.3       — bundled (pre_built/lib64/libfftw3.so.3.bz2) from octave
#   libfftw3_threads    — bundled (same as above)
#   libc.so.6 / libm    — glibc, always present
#
# ngspice releases are distributed via SourceForge (not GitHub):
#   https://sourceforge.net/projects/ngspice/files/ng-spice-rework/
# Tags: numeric, e.g. ngspice-44 → version "44".
#
# Policy: always build from a stable tagged release.
#
# Prerequisites on the build machine (EL8):
#   dnf install readline-devel ncurses-devel fftw-devel gcc gcc-c++ make autoconf automake bison flex
#
# Usage (run from any directory):
#   ./pre_built/build_scripts/build-ngspice.sh --tag ngspice-44

set -eu

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
BIN_DIR="$REPO/pre_built/el8.x86_64.glibc2p28/bin"
RUNTIME_DIR="$REPO/pre_built/el8.x86_64.glibc2p28/runtime"
PATCHELF="${HOME}/.local/bin/patchelf"
TAG=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        --tag)
            shift
            [ "$#" -gt 0 ] || { echo "missing value for --tag" >&2; exit 2; }
            TAG="$1"
            ;;
        -h|--help)
            sed -n '2,/^$/p' "$0"
            exit 0
            ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done

if [ -z "$TAG" ]; then
    echo "ERROR: --tag is required. Specify a stable release tag, e.g.:" >&2
    echo "  $0 --tag ngspice-44" >&2
    echo "" >&2
    echo "Stable releases: https://sourceforge.net/projects/ngspice/files/ng-spice-rework/" >&2
    echo "" >&2
    echo "Policy: this project ships stable releases only." >&2
    exit 1
fi

# Derive version number: ngspice-44 -> 44
VERSION="${TAG#ngspice-}"

if [ -r /opt/rh/gcc-toolset-14/enable ]; then
    # shellcheck disable=SC1091
    . /opt/rh/gcc-toolset-14/enable
fi

need() {
    command -v "$1" >/dev/null 2>&1 || {
        printf 'missing required command: %s\n' "$1" >&2
        exit 1
    }
}

need gcc
need make
need bison
need flex
need "$PATCHELF"

WORK_DIR=$(mktemp -d /tmp/build-ngspice-XXXXXX)
INST_DIR=$(mktemp -d /tmp/inst-ngspice-XXXXXX)
trap 'rm -rf "$WORK_DIR" "$INST_DIR"' EXIT

echo "==> Downloading ngspice-${VERSION}.tar.gz ..."
# SourceForge download (requires -L to follow redirects through CDN)
curl -fL -o "$WORK_DIR/ngspice.tar.gz" \
    "https://sourceforge.net/projects/ngspice/files/ng-spice-rework/${VERSION}/ngspice-${VERSION}.tar.gz/download" \
    --retry 3 --retry-delay 2

echo "==> Extracting ..."
tar xzf "$WORK_DIR/ngspice.tar.gz" -C "$WORK_DIR"
cd "$WORK_DIR/ngspice-${VERSION}"

# ngspice distributed tarballs include configure; run autoreconf only if absent
if [ ! -f configure ]; then
    echo "==> Running autoreconf ..."
    need autoreconf
    autoreconf -fiv
fi

echo "==> Configuring ..."
./configure \
    --prefix="$INST_DIR" \
    --with-readline=yes \
    --without-x \
    --enable-xspice \
    --enable-cider \
    --enable-predictor \
    --disable-debug \
    CFLAGS="-O2 -pipe"

echo "==> Building ..."
make -j"$(nproc 2>/dev/null || echo 2)"

echo "==> Installing ..."
make install

NGSPICE_BIN="$INST_DIR/bin/ngspice"
if [ ! -f "$NGSPICE_BIN" ]; then
    echo "ERROR: ngspice binary not found at $NGSPICE_BIN after install" >&2
    exit 1
fi

echo "==> Verifying binary ..."
VER_OUT=$("$NGSPICE_BIN" --version 2>&1 | head -3)
echo "$VER_OUT"
echo "$VER_OUT" | grep -qi "ngspice\|version" || {
    echo "WARNING: unexpected --version output" >&2
}

echo "==> Checking runtime library requirements ..."
ldd "$NGSPICE_BIN" | grep -v "linux-vdso\|ld-linux" | awk '{print "  " $0}'

echo "==> Checking glibc symbol requirements ..."
MAX_GLIBC="$(readelf -V "$NGSPICE_BIN" 2>/dev/null \
    | grep -oE 'GLIBC_[0-9]+\.[0-9]+' | sort -V | tail -1)"
echo "  Max glibc symbol: $MAX_GLIBC (target: GLIBC_2.28)"
case "$MAX_GLIBC" in
    GLIBC_2.2[0-8]|GLIBC_2.1[0-9]|GLIBC_2.[0-9])
        echo "  OK — binary compatible with EL8 glibc 2.28" ;;
    *)
        echo "  WARNING: $MAX_GLIBC > GLIBC_2.28 — binary may not run on EL8" >&2 ;;
esac

echo "==> Packaging binary ..."
WORK_BIN="$WORK_DIR/ngspice"
cp "$NGSPICE_BIN" "$WORK_BIN"
strip "$WORK_BIN"
"$PATCHELF" --set-rpath '$ORIGIN/../lib64' "$WORK_BIN"
bzip2 -kf "$WORK_BIN"
cp "${WORK_BIN}.bz2" "$BIN_DIR/ngspice.bz2"

echo "==> Packaging ngspice scripts/spinit runtime ..."
# ngspice looks for spinit and code models relative to $NGSPICE_HOME (binary dir
# or share/ngspice).  Package the share/ngspice tree so headless farm use works.
SHARE_DIR="$INST_DIR/share/ngspice"
if [ -d "$SHARE_DIR" ]; then
    tar cjf "$RUNTIME_DIR/ngspice.tar.bz2" \
        -C "$INST_DIR" \
        "./share/ngspice"
    echo "  Wrote: $RUNTIME_DIR/ngspice.tar.bz2 ($(wc -c < "$RUNTIME_DIR/ngspice.tar.bz2" | tr -d ' ') bytes)"
else
    echo "  WARNING: $SHARE_DIR not found — ngspice may not find spinit at runtime"
fi

echo "==> Updating packages.json ..."
python3 -c "
import re, sys, json
path, ver = sys.argv[1], sys.argv[2]
with open(path) as f:
    data = json.load(f)
pkgs = data['packages']
if 'ngspice' in pkgs:
    pkgs['ngspice']['version'] = ver
    print(f'packages.json: ngspice version -> {ver}')
else:
    print('WARNING: ngspice not found in packages.json, skipping version update')
with open(path, 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
" "$REPO/pre_built/packages.json" "$VERSION"

echo "==> Running strip_all_elf_binaries ..."
"$REPO/strip_all_elf_binaries"

echo ""
echo "Done."
echo ""
echo "Produced:"
echo "  $BIN_DIR/ngspice.bz2"
[ -f "$RUNTIME_DIR/ngspice.tar.bz2" ] && echo "  $RUNTIME_DIR/ngspice.tar.bz2"
echo ""
echo "Commit with:"
echo "  git add pre_built/el8.x86_64.glibc2p28/bin/ngspice.bz2 \\"
if [ -f "$RUNTIME_DIR/ngspice.tar.bz2" ]; then
echo "          pre_built/el8.x86_64.glibc2p28/runtime/ngspice.tar.bz2 \\"
fi
echo "          .strip-manifest pre_built/packages.json"
echo "  git commit -m 'feat(pre_built): ngspice ${VERSION} EL8 source build'"
