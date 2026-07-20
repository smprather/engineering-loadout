#!/bin/sh
# Build gocheat (interactive terminal cheatsheet TUI) from source for
# el8.x86_64.glibc2p28.
#
# gocheat is pure Go (no `import "C"`). Upstream's official linux_amd64 release
# is built by goreleaser with cgo on a newer host, so it is DYNAMICALLY linked
# and needs GLIBC_2.34 -- it does NOT run on EL8 (glibc 2.28):
#   gocheat: /lib64/libc.so.6: version `GLIBC_2.34' not found
# Building here with CGO_ENABLED=0 yields a fully static binary (no glibc dep),
# which is why we source-build instead of shipping the upstream prebuilt.
#
# gocheat has no --version flag (any arg drops straight into the TUI and opens
# /dev/tty), so it is intentionally NOT in farm-versions; its version is tracked
# only in packages.json.
#
# Policy: always build from a stable tagged release. See tags at:
#   https://github.com/Achno/gocheat/releases
#
# Prerequisites: a Go toolchain (tested with go1.26); network for the module
# proxy (run outside the command sandbox).
#
# Usage (run from any directory):
#   /path/to/build-gocheat.sh --tag v0.1.1

set -eu

REPO="$(cd "$(dirname "$0")/.." && pwd)"
BIN_DIR="$REPO/payload/el8.x86_64.glibc2p28/bin"
CLONE_URL="https://github.com/Achno/gocheat.git"

tag=""
while [ "$#" -gt 0 ]; do
    case "$1" in
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
    echo "  $0 --tag v0.1.1" >&2
    echo "" >&2
    echo "Stable releases: https://github.com/Achno/gocheat/releases" >&2
    exit 1
fi

command -v go >/dev/null 2>&1 || { echo "missing required command: go" >&2; exit 1; }

SRCDIR="/tmp/gocheat-src-${tag}"
rm -rf "$SRCDIR"
git clone --depth 1 --branch "$tag" "$CLONE_URL" "$SRCDIR"
cd "$SRCDIR"

echo "Building gocheat (CGO_ENABLED=0, static) ..."
CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /tmp/gocheat-build .

BIN=/tmp/gocheat-build
file "$BIN" | grep -q "statically linked" || { echo "ERROR: build is not static" >&2; exit 1; }
if readelf -V "$BIN" 2>/dev/null | grep -qoE 'GLIBC_[0-9.]+'; then
    echo "ERROR: build has glibc version symbols -- not a clean static binary" >&2
    exit 1
fi
echo "OK -- static, no glibc syms."

strip "$BIN"
bzip2 -kf "$BIN"
cp "${BIN}.bz2" "$BIN_DIR/gocheat.bz2"
chmod 644 "$BIN_DIR/gocheat.bz2"
rm -f "$BIN" "${BIN}.bz2"

# Update packages.json version (strip any leading v from the tag).
ver="${tag#v}"
python3 -c "
import json, sys
path, ver = sys.argv[1], sys.argv[2]
with open(path) as f:
    data = json.load(f)
data['packages']['gocheat']['version'] = ver
with open(path, 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
print('packages.json: gocheat version -> ' + ver)
" "$REPO/payload/packages.json" "$ver"

echo "Running strip-all-elf-binaries ..."
"$REPO/strip-all-elf-binaries"

echo ""
echo "Installed: $BIN_DIR/gocheat.bz2"
