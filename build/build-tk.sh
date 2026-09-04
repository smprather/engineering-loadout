#!/bin/sh
# Build Tk from source for el8.x86_64.glibc2p28.
#
# Produces:
#   payload/el8.x86_64.glibc2p28/bin/wish.bz2
#   payload/el8.x86_64.glibc2p28/lib64/libtcl9tk9.0.so.bz2
#   payload/el8.x86_64.glibc2p28/runtime/tk.tar.bz2 (lib/tk9.0 script tree)
#
# Tcl must already be built by build-tcl.sh so tclConfig.sh, tcl.h, and
# libtcl9.0.so exist under /tmp/loadout-tcl-instdir-<version>.
#
# NOTE: Tk 9.x embeds its script library in libtcl9tk9.0.so via zipfs, but
# the embedded copy does NOT survive post-link patchelf (the zip
# central-directory offset goes stale, zipfs fails to mount, and wish dies
# with "Can't find a usable tk.tcl" -- broken on every host, EL8 included).
# So the .so ships un-patchelf'd AND the script tree ships explicitly as
# lib/tk9.0 (untarred from the intact embedded zip if needed, normally just
# `make install`'s lib/tk9.0). Do not strip the shared library either.
#
# Usage (run from any directory):
#   ./build/build-tk.sh --tag core-9-0-3

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
    exit 1
fi

VERSION="$(echo "$TAG" | sed 's/^core-//; s/-/./g')"
TARBALL="tk${VERSION}-src.tar.gz"
DOWNLOAD_URL="https://downloads.sourceforge.net/project/tcl/Tcl/${VERSION}/${TARBALL}"
TCL_INST_DIR="/tmp/loadout-tcl-instdir-${VERSION}"
TK_INST_DIR="/tmp/loadout-tk-instdir-${VERSION}"
TCL_CONFIG_DIR="${TCL_INST_DIR}/lib"
TCL_INCLUDE_DIR="${TCL_INST_DIR}/include"

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

[ -f "${TCL_CONFIG_DIR}/tclConfig.sh" ] || {
    echo "ERROR: missing ${TCL_CONFIG_DIR}/tclConfig.sh; run build-tcl.sh first" >&2
    exit 1
}
[ -f "${TCL_INCLUDE_DIR}/tcl.h" ] || {
    echo "ERROR: missing ${TCL_INCLUDE_DIR}/tcl.h; run build-tcl.sh first" >&2
    exit 1
}

WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/build-tk-XXXXXX")
trap 'rm -rf "$WORK_DIR"' EXIT

echo "==> Downloading ${TARBALL} ..."
curl -fL -o "$WORK_DIR/tk.tar.gz" "$DOWNLOAD_URL"

echo "==> Extracting ..."
tar xzf "$WORK_DIR/tk.tar.gz" -C "$WORK_DIR"
cd "$WORK_DIR/tk${VERSION}/unix"

echo "==> Configuring (prefix: ${TK_INST_DIR}) ..."
rm -rf "$TK_INST_DIR"
./configure \
    --prefix="$TK_INST_DIR" \
    --libdir="$TK_INST_DIR/lib" \
    --with-tcl="$TCL_CONFIG_DIR" \
    --enable-shared \
    --enable-64bit

echo "==> Building ..."
make -j"$(nproc 2>/dev/null || echo 2)"

echo "==> Installing ..."
make install

WISH_BIN=$(find "$TK_INST_DIR/bin" -name "wish[0-9]*" | sort -V | tail -1)
if [ -z "$WISH_BIN" ]; then
    echo "ERROR: wish binary not found in $TK_INST_DIR/bin" >&2
    exit 1
fi

TKLIB=$(find "$TK_INST_DIR/lib" -maxdepth 1 -name "lib*tcl*tk*.so" | sort -V | tail -1)
if [ -z "$TKLIB" ]; then
    echo "ERROR: Tk shared library not found in $TK_INST_DIR/lib" >&2
    exit 1
fi
TKLIB_NAME=$(basename "$TKLIB")

echo "==> Verifying wish ..."
if "$WISH_BIN" <<'EOF'
puts "Tk version: [package require Tk]"
puts "Tk library: $tk_library"
exit
EOF
then
    echo "  OK: wish works and can find Tk"
else
    echo "  ERROR: wish verification failed" >&2
    exit 1
fi

echo "==> Packaging binary ..."
WORK_BIN="$WORK_DIR/wish"
cp "$WISH_BIN" "$WORK_BIN"
strip "$WORK_BIN"
"$PATCHELF" --set-rpath '$ORIGIN/../lib64' "$WORK_BIN"
bzip2 -kf "$WORK_BIN"
cp "${WORK_BIN}.bz2" "$BIN_DIR/wish.bz2"

echo "==> Packaging shared library ..."
# NEVER patchelf/strip this library: Tk 9.x appends its script library as a
# zipfs zip whose central-directory offset is absolute from file start -- ANY
# post-link rewrite (even an RPATH-only patchelf) shifts bytes and the offset
# goes stale, so zipfs silently fails to mount and wish dies with "Can't find
# a usable tk.tcl" on hosts without a system tk9. No RPATH is needed: wish
# links this lib directly, so wish's own $ORIGIN/../lib64 RUNPATH resolves
# whatever it needs. Guard below fails the build if an RPATH ever reappears.
WORK_LIB="$WORK_DIR/${TKLIB_NAME}"
cp "$TKLIB" "$WORK_LIB"
if readelf -d "$WORK_LIB" | grep -qE 'RPATH|RUNPATH'; then
    echo "ERROR: ${TKLIB_NAME} carries RPATH/RUNPATH -- zipfs offset would break" >&2
    exit 1
fi
bzip2 -kf "$WORK_LIB"
cp "${WORK_LIB}.bz2" "$LIB_DIR/${TKLIB_NAME}.bz2"

echo "==> Updating packages.json ..."
python3 -c "
import json, sys
path, ver, libname = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path) as f:
    data = json.load(f)
pkgs = data['packages']
pkgs.setdefault('tk', {})
pkgs['tk'].update({
    'kind': 'bin',
    'bins': ['wish'],
    'libs': [libname],
    'depends': ['tcl', 'gui_libs'],
    'version': ver,
    'version_url': 'https://github.com/tcltk/tk',
    'platforms': ['linux'],
    'tags': ['lang', 'gui'],
    'description': 'Tk GUI toolkit \u2014 wish interpreter and embedded Tk runtime',
})
if 'tkdiff' in pkgs:
    deps = pkgs['tkdiff'].setdefault('depends', [])
    if 'tk' not in deps:
        deps.append('tk')
with open(path, 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
" "$REPO/payload/packages.json" "$VERSION" "$TKLIB_NAME"

echo "==> Packaging Tk script tree (lib/tk9.0 file tree, not zipfs) ..."
# make install already materialized $TK_INST_DIR/lib/tk9.0 -- tar it as the
# package runtime so wish finds tk.tcl without depending on the embedded
# zipfs copy (see NOTE at the top of this script).
[ -f "$TK_INST_DIR/lib/tk9.0/tk.tcl" ] || {
    echo "ERROR: $TK_INST_DIR/lib/tk9.0/tk.tcl missing" >&2; exit 1; }
tar cjf "$RUNTIME_DIR/tk.tar.bz2" -C "$TK_INST_DIR" ./lib/tk9.0
echo "  runtime/tk.tar.bz2 ($(du -h "$RUNTIME_DIR/tk.tar.bz2" | cut -f1))"

echo "==> Running strip-all-elf-binaries ..."
"$REPO/build/strip-all-elf-binaries"

echo ""
echo "Done."
echo ""
echo "Produced:"
echo "  $BIN_DIR/wish.bz2"
echo "  $LIB_DIR/${TKLIB_NAME}.bz2"
echo "  $RUNTIME_DIR/tk.tar.bz2"
