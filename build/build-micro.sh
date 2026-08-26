#!/bin/sh
# Package micro (terminal text editor) from official GitHub release for
# el8.x86_64.glibc2p28.  Downloads the pre-built linux64 tarball -- no Go
# toolchain needed.
#
# Policy: always use a stable tagged release. See stable tags at:
#   https://github.com/zyedidia/micro/releases
#
# Usage:
#   /path/to/build-micro.sh --tag v2.0.14
#
# What this script does:
#   1. Downloads micro-VERSION-linux64.tar.gz from GitHub
#   2. Extracts the micro binary
#   3. Strips debug symbols
#   4. bzip2-compresses and installs to payload/el8.x86_64.glibc2p28/bin/

set -eu

REPO="$(cd "$(dirname "$0")/.." && pwd)"
BIN_DIR="$REPO/payload/el8.x86_64.glibc2p28/bin"

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
    echo "  $0 --tag v2.0.14" >&2
    echo "" >&2
    echo "Stable releases: https://github.com/zyedidia/micro/releases" >&2
    echo "" >&2
    echo "Policy: this project ships stable releases only." >&2
    exit 1
fi

# Strip leading 'v' for filenames
ver="${tag#v}"

URL="https://github.com/zyedidia/micro/releases/download/${tag}/micro-${ver}-linux64.tar.gz"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/build-micro.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

echo "Downloading $URL ..."
curl -fL "$URL" -o "$WORK_DIR/micro.tar.gz"

echo "Extracting ..."
tar -xzf "$WORK_DIR/micro.tar.gz" -C "$WORK_DIR"
# Archive layout changed: v2.0.14 used micro-VER-linux64/micro; v2.0.15+ uses micro-VER/micro
BIN="$WORK_DIR/micro-${ver}-linux64/micro"
if [ ! -f "$BIN" ]; then
    BIN="$WORK_DIR/micro-${ver}/micro"
fi
if [ ! -f "$BIN" ]; then
    echo "ERROR: could not find micro binary in archive" >&2
    ls "$WORK_DIR/" >&2
    exit 1
fi

echo "Stripping ..."
strip "$BIN"

echo "Compressing ..."
bzip2 -k "$BIN"
cp "${BIN}.bz2" "$BIN_DIR/micro.bz2"

echo ""
echo "Installed: $BIN_DIR/micro.bz2"
echo "Version:   $(file "$BIN" | head -1)"

# -- update packages.json ---------------------------------------------------------

TOOLS_JSON="$REPO/payload/packages.json"
python3 -c "
import json, sys
path, ver = sys.argv[1], sys.argv[2]
with open(path) as f:
    data = json.load(f)
data['packages']['micro']['version'] = ver
with open(path, 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
print('packages.json: micro version -> ' + ver)
" "$TOOLS_JSON" "$ver"

# -- strip manifest ------------------------------------------------------------

echo "Running strip-all-elf-binaries..."
"$REPO/build/strip-all-elf-binaries"

echo ""
echo "Done. Commit with:"
echo "  git add payload/el8.x86_64.glibc2p28/bin/micro.bz2 .strip-manifest payload/packages.json"
echo "  git commit -m 'feat(payload): micro ${ver} from stable release'"
