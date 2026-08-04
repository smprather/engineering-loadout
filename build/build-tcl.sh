#!/bin/sh
# Build Tcl from source for el8.x86_64.glibc2p28.
#
# Produces:
#   payload/el8.x86_64.glibc2p28/bin/tclsh.bz2
#   payload/el8.x86_64.glibc2p28/lib64/libtcl9.0.so.bz2   (or libtcl8.X.so.bz2)
#
# NOTE: Tcl 9.x embeds its standard library (init.tcl etc.) inside libtcl9.0.so via
# zipfs -- there is NO separate runtime archive to deploy.  The binary + shared lib
# are self-sufficient.
#
# The install dir is intentionally left at /tmp/loadout-tcl-instdir-<version>
# so that downstream build scripts (build-modules.sh) can find tclConfig.sh:
#   build-modules.sh --tag v5.6.1 --with-tcl /tmp/loadout-tcl-instdir-9.0.3/lib
#
# Policy: always build from a stable tagged release. Tags use the form:
#   core-MAJOR-MINOR-PATCH  (e.g. core-9-0-3)
# Stable releases: https://github.com/tcltk/tcl/releases
#
# Prerequisites on the build machine (EL8):
#   dnf install gcc make  # already present on most EL8 systems
#
# Usage (run from any directory):
#   ./build/build-tcl.sh --tag core-9-0-3

set -eu

REPO="$(cd "$(dirname "$0")/.." && pwd)"
BIN_DIR="$REPO/payload/el8.x86_64.glibc2p28/bin"
LIB_DIR="$REPO/payload/el8.x86_64.glibc2p28/lib64"
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
    echo "  $0 --tag core-9-0-3" >&2
    echo "" >&2
    echo "Stable releases: https://github.com/tcltk/tcl/releases" >&2
    echo "" >&2
    echo "Policy: this project ships stable releases only." >&2
    exit 1
fi

# Derive version number from tag: core-9-0-3 -> 9.0.3
VERSION="$(echo "$TAG" | sed 's/^core-//; s/-/./g')"
TARBALL="tcl${VERSION}-src.tar.gz"
DOWNLOAD_URL="https://github.com/tcltk/tcl/releases/download/${TAG}/${TARBALL}"

# Install dir is LEFT IN PLACE after build (not cleaned up) so downstream
# build scripts can use tclConfig.sh and headers.
INST_DIR="/tmp/loadout-tcl-instdir-${VERSION}"

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
need "$PATCHELF"

WORK_DIR=$(mktemp -d /tmp/build-tcl-XXXXXX)
trap 'rm -rf "$WORK_DIR"' EXIT

echo "==> Downloading ${TARBALL} ..."
curl -fL -o "$WORK_DIR/tcl.tar.gz" "$DOWNLOAD_URL"

echo "==> Extracting ..."
tar xzf "$WORK_DIR/tcl.tar.gz" -C "$WORK_DIR"
cd "$WORK_DIR/tcl${VERSION}/unix"

echo "==> Configuring (prefix: ${INST_DIR}) ..."
rm -rf "$INST_DIR"
./configure \
    --prefix="$INST_DIR" \
    --libdir="$INST_DIR/lib" \
    --enable-shared \
    --enable-64bit \
    --disable-zipvfs

echo "==> Building ..."
make -j"$(nproc 2>/dev/null || echo 2)"

echo "==> Installing ..."
make install

# Discover binary name (tclsh9.0 for Tcl 9.x, tclsh8.6 for 8.x)
TCLSH_BIN=$(find "$INST_DIR/bin" -name "tclsh[0-9]*" | sort -V | tail -1)
if [ -z "$TCLSH_BIN" ]; then
    echo "ERROR: tclsh binary not found in $INST_DIR/bin" >&2
    exit 1
fi
echo "Found binary: $TCLSH_BIN"

# Discover shared library name
TCLLIB=$(find "$INST_DIR/lib" -maxdepth 1 -name "libtcl*.so" | sort -V | tail -1)
if [ -z "$TCLLIB" ]; then
    echo "ERROR: libtcl*.so not found in $INST_DIR/lib" >&2
    exit 1
fi
echo "Found library: $TCLLIB"
TCLLIB_NAME=$(basename "$TCLLIB")

echo "==> Verifying binary ..."
if "$TCLSH_BIN" - <<'EOF'
puts "Tcl version: [info patchlevel]"
puts "Library: $tcl_library"
if {[file exists [file join $tcl_library init.tcl]]} {
    puts "init.tcl: OK"
} else {
    puts "init.tcl: NOT FOUND"
    exit 1
}
EOF
then
    echo "  OK: tclsh works and can find its library"
else
    echo "  ERROR: tclsh verification failed" >&2
    exit 1
fi

echo "==> Packaging binary ..."
WORK_BIN="$WORK_DIR/tclsh"
cp "$TCLSH_BIN" "$WORK_BIN"
strip "$WORK_BIN"
"$PATCHELF" --set-rpath '$ORIGIN/../lib64' "$WORK_BIN"
bzip2 -kf "$WORK_BIN"
cp "${WORK_BIN}.bz2" "$BIN_DIR/tclsh.bz2"

echo "==> Packaging shared library ..."
WORK_LIB="$WORK_DIR/${TCLLIB_NAME}"
cp "$TCLLIB" "$WORK_LIB"
# CRITICAL: do NOT strip libtcl9.0.so. Tcl 9.x appends its standard
# library as a zipfs archive to the .so file's tail; strip truncates
# trailing data and silently destroys the embedded zipfs, leaving
# tclsh unable to find init.tcl at runtime ("Cannot find a usable
# init.tcl in the following directories: ..."). patchelf alone
# preserves the trailing zip data, so just patchelf for RPATH and
# bzip2. strip-all-elf-binaries already skips patchelf'd payloads
# (RPATH set), so the bundled .bz2 will not be re-stripped on
# subsequent repo-wide strip passes.
"$PATCHELF" --set-rpath '$ORIGIN' "$WORK_LIB"
bzip2 -kf "$WORK_LIB"
cp "${WORK_LIB}.bz2" "$LIB_DIR/${TCLLIB_NAME}.bz2"

echo "==> Updating packages.json ..."
python3 -c "
import re, sys, json
path, ver, libname = sys.argv[1], sys.argv[2], sys.argv[3]

with open(path) as f:
    data = json.load(f)
pkgs = data['packages']

# Update tcl version
if 'tcl' in pkgs:
    pkgs['tcl']['version'] = ver
    pkgs['tcl']['libs'] = [libname]
    print(f'packages.json: tcl version -> {ver}, libs -> [{libname}]')
else:
    print('WARNING: tcl not found in packages.json, skipping version update')

with open(path, 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
" "$REPO/payload/packages.json" "$VERSION" "$TCLLIB_NAME"

echo "==> Running strip-all-elf-binaries ..."
"$REPO/build/strip-all-elf-binaries"

echo "==> Checking glibc symbol requirements ..."
MAX_GLIBC="$(readelf -V "$TCLSH_BIN" 2>/dev/null \
    | grep -oE 'GLIBC_[0-9]+\.[0-9]+' | sort -V | tail -1)"
echo "  Max glibc symbol: $MAX_GLIBC (target: GLIBC_2.28)"
case "$MAX_GLIBC" in
    GLIBC_2.2[0-8]|GLIBC_2.1[0-9]|GLIBC_2.[0-9])
        echo "  OK -- binary compatible with EL8 glibc 2.28" ;;
    *)
        echo "  WARNING: $MAX_GLIBC > GLIBC_2.28 -- binary may not run on EL8" >&2 ;;
esac

echo ""
echo "Done."
echo ""
echo "Produced:"
echo "  $BIN_DIR/tclsh.bz2"
echo "  $LIB_DIR/${TCLLIB_NAME}.bz2"
echo "  (No runtime archive -- Tcl 9.x stdlib is embedded in ${TCLLIB_NAME} via zipfs)"
echo ""
echo "Install dir left at: $INST_DIR"
echo "  tclConfig.sh: $INST_DIR/lib/tclConfig.sh"
echo "  Use with: build-modules.sh --tag vX.Y.Z --with-tcl $INST_DIR/lib"
echo ""
echo "Commit with:"
echo "  git add payload/el8.x86_64.glibc2p28/bin/tclsh.bz2 \\"
echo "          payload/el8.x86_64.glibc2p28/lib64/${TCLLIB_NAME}.bz2 \\"
echo "          .strip-manifest payload/packages.json"
echo "  git commit -m 'feat(payload): tcl ${VERSION} EL8 source build'"
