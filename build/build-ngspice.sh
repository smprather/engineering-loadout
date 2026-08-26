#!/bin/sh
# Build ngspice (SPICE circuit simulator) from source for el8.x86_64.glibc2p28.
#
# ngspice is built without X11 (--without-x) so the binary works on headless
# farm nodes. Interactive text mode and batch mode (-b) work without a DISPLAY.
# For graphical plots use: ngspice -b -r rawfile.raw && gnuplot (or nutmeg).
#
# XSPICE code models (behavioral elements) and CIDER numerical device
# simulation are enabled -- both are standard for modern circuit-simulation workflows.
#
# Runtime library requirements (all satisfied by system EL8 or existing bundles):
#   libreadline.so.7    -- EL8 system package (readline-7.0, always installed)
#   libncurses.so.6     -- EL8 system package (always installed)
#   libfftw3.so.3       -- bundled (payload/lib64/libfftw3.so.3.bz2) from octave
#   libfftw3_threads    -- bundled (same as above)
#   libc.so.6 / libm    -- glibc, always present
#
# ngspice releases are distributed via SourceForge (not GitHub):
#   https://sourceforge.net/projects/ngspice/files/ng-spice-rework/
# Tags: numeric, e.g. ngspice-44 -> version "44".
#
# Policy: always build from a stable tagged release.
#
# Prerequisites on the build machine (EL8):
#   dnf install readline-devel ncurses-devel fftw-devel gcc gcc-c++ make autoconf automake bison flex
#
# Usage (run from any directory):
#   ./build/build-ngspice.sh --tag ngspice-44

set -eu

REPO="$(cd "$(dirname "$0")/.." && pwd)"
BIN_DIR="$REPO/payload/el8.x86_64.glibc2p28/bin"
RUNTIME_DIR="$REPO/payload/el8.x86_64.glibc2p28/runtime"
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

WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/build-ngspice-XXXXXX")
INST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/inst-ngspice-XXXXXX")
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
        echo "  OK -- binary compatible with EL8 glibc 2.28" ;;
    *)
        echo "  WARNING: $MAX_GLIBC > GLIBC_2.28 -- binary may not run on EL8" >&2 ;;
esac

echo "==> Making spinit relocatable ..."
# The binary embeds its configure prefix (NGSPICEDATADIR), and the generated
# spinit embeds absolute codemodel paths under the same temp prefix. The
# packaged bin/ngspice wrapper exports SPICE_LIB_DIR (spinit discovery) and
# passes -D loadout_cmdir=<prefix>/lib/ngspice; rewrite spinit to load
# codemodels through that variable, guarded so a direct ngspice.bin run
# skips codemodel loading silently instead of erroring on an unset variable.
SPINIT="$INST_DIR/share/ngspice/scripts/spinit"
[ -f "$SPINIT" ] || { echo "ERROR: $SPINIT not found after install" >&2; exit 1; }
sed -i \
    -e "s|$INST_DIR/lib/ngspice|\$loadout_cmdir|g" \
    -e 's/^if \$?xspice_enabled$/if $?xspice_enabled \& $?loadout_cmdir/' \
    -e 's/^if \$?osdi_enabled$/if $?osdi_enabled \& $?loadout_cmdir/' \
    "$SPINIT"
if grep -q "$INST_DIR" "$SPINIT"; then
    echo "ERROR: spinit still contains the temp install prefix" >&2
    exit 1
fi

CM_DIR="$INST_DIR/lib/ngspice"
if [ ! -f "$CM_DIR/analog.cm" ]; then
    echo "ERROR: XSPICE codemodels not found in $CM_DIR" >&2
    exit 1
fi

echo "==> Verifying relocated staged tree (XSPICE codemodel load) ..."
# Run the staged tree exactly the way an install runs it: wrapper at
# bin/ngspice deriving its prefix, real ELF at bin/ngspice.bin, cwd elsewhere,
# XSPICE gain codemodel from lib/ngspice/analog.cm. The tar step below only
# packs ./share/ngspice and ./lib/ngspice, so staging into bin/ is harmless.
install -m 755 "$REPO/build/ngspice/ngspice" "$INST_DIR/bin/ngspice-smoke"
cp "$NGSPICE_BIN" "$INST_DIR/bin/ngspice.bin"
cat > "$WORK_DIR/xspice-smoke.cir" <<'EOF'
* xspice gain smoke
v1 1 0 1
a1 1 2 amp
.model amp gain(gain=2.0)
r1 2 0 1k
.op
.end
EOF
SMOKE_OUT=$(cd /tmp && env -i PATH=/usr/bin:/bin HOME="$WORK_DIR" \
    "$INST_DIR/bin/ngspice-smoke" \
    -b "$WORK_DIR/xspice-smoke.cir" 2>&1) || {
    echo "ERROR: staged XSPICE smoke run failed:" >&2
    echo "$SMOKE_OUT" >&2
    exit 1
}
echo "$SMOKE_OUT" | grep -Eq 'V\(2\)[[:space:]]+2\.0*e?\+?0*' || {
    echo "ERROR: XSPICE gain codemodel did not produce V(2)=2:" >&2
    echo "$SMOKE_OUT" >&2
    exit 1
}
echo "  OK: XSPICE gain codemodel loaded and evaluated from staged tree"
rm -f "$INST_DIR/bin/ngspice-smoke" "$INST_DIR/bin/ngspice.bin"

echo "==> Packaging binaries (wrapper + real ELF) ..."
WORK_BIN="$WORK_DIR/ngspice.bin"
cp "$NGSPICE_BIN" "$WORK_BIN"
strip "$WORK_BIN"
"$PATCHELF" --set-rpath '$ORIGIN/../lib64' "$WORK_BIN"
bzip2 -kf "$WORK_BIN"
cp "${WORK_BIN}.bz2" "$BIN_DIR/ngspice.bin.bz2"
bzip2 -c "$REPO/build/ngspice/ngspice" > "$BIN_DIR/ngspice.bz2"

echo "==> Packaging ngspice runtime (scripts + codemodels) ..."
tar cjf "$RUNTIME_DIR/ngspice.tar.bz2" \
    -C "$INST_DIR" \
    "./share/ngspice" "./lib/ngspice"
echo "  Wrote: $RUNTIME_DIR/ngspice.tar.bz2 ($(wc -c < "$RUNTIME_DIR/ngspice.tar.bz2" | tr -d ' ') bytes)"

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
" "$REPO/payload/packages.json" "$VERSION"

echo "==> Running strip-all-elf-binaries ..."
"$REPO/build/strip-all-elf-binaries"

echo ""
echo "Done."
echo ""
echo "Produced:"
echo "  $BIN_DIR/ngspice.bz2 (wrapper)"
echo "  $BIN_DIR/ngspice.bin.bz2"
echo "  $RUNTIME_DIR/ngspice.tar.bz2"
echo ""
echo "Commit with:"
echo "  git add payload/el8.x86_64.glibc2p28/bin/ngspice.bz2 \\"
echo "          payload/el8.x86_64.glibc2p28/bin/ngspice.bin.bz2 \\"
echo "          payload/el8.x86_64.glibc2p28/runtime/ngspice.tar.bz2 \\"
echo "          .strip-manifest payload/packages.json build/ngspice/ngspice"
echo "  git commit -m 'feat(payload): ngspice ${VERSION} EL8 source build'"
