#!/bin/sh
# Build numr (text calculator with vim-style TUI) from source for
# el8.x86_64.glibc2p28.
#
# numr is written in Rust (cargo workspace). The headline command is the TUI
# binary `numr` from crates/numr-tui. It is a single self-contained binary --
# no runtime data files, so there is no runtime tarball (unlike fish).
#
# numr-tui pulls numr-core with the "fetch" feature for live currency rates.
# That feature uses reqwest with `rustls-tls` (default-features = false in the
# workspace manifest), NOT openssl -- so the binary has NO libssl/libcrypto
# NEEDED entry and stays offline-clean. Live rates simply no-op when offline;
# all other math (units, variables, static conversions) works with no network.
#
# Runtime libs: only glibc 2.28 (already on every EL8 target). Confirmed by the
# ldd report this script prints at the end.
#
# Policy: always build from a stable tagged release. See stable tags at:
#   https://github.com/nasedkinpv/numr/releases
#
# Prerequisites on the build machine (EL8):
#   - rustc + cargo (rustup stable, or dnf). Tested with 1.95.0.
#   - gcc-toolset-14 (optional but recommended for consistent ABI)
#   - patchelf at ~/.local/bin/patchelf
#
# Usage (run from any directory):
#   /path/to/build-numr.sh --tag v0.5.5

set -eu

REPO="$(cd "$(dirname "$0")/.." && pwd)"
BIN_DIR="$REPO/payload/el8.x86_64.glibc2p28/bin"
PATCHELF="${HOME}/.local/bin/patchelf"
CLONE_URL="https://github.com/nasedkinpv/numr.git"

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
    echo "  $0 --tag v0.5.5" >&2
    echo "" >&2
    echo "Stable releases: https://github.com/nasedkinpv/numr/releases" >&2
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
        echo "missing required command: $1 -- install the prerequisites listed in this script's header" >&2
        exit 1
    }
}

need cargo
need rustc
[ -x "$PATCHELF" ] || { echo "missing patchelf at $PATCHELF" >&2; exit 1; }

SRCDIR="/tmp/numr-src-${tag}"

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
    cargo clean
fi

echo "Building numr (release) ..."
cargo build --release -p numr-tui

BIN="$SRCDIR/target/release/numr"
[ -f "$BIN" ] || { echo "build did not produce $BIN" >&2; exit 1; }

echo ""
echo "Build complete: $("$BIN" --version 2>&1 | head -1)"
echo ""

# Package the binary: strip -> patchelf RPATH -> bzip2
WORK="/tmp/numr_work_${tag}"
cp "$BIN" "$WORK"
strip "$WORK"
"$PATCHELF" --set-rpath '$ORIGIN/../lib64:$ORIGIN/../lib' "$WORK"
bzip2 -kf "$WORK"
cp "${WORK}.bz2" "$BIN_DIR/numr.bz2"
chmod 644 "$BIN_DIR/numr.bz2"
rm -f "$WORK" "${WORK}.bz2"

# Update packages.json version (strip any leading v from the tag)
ver="${tag#v}"
TOOLS_JSON="$REPO/payload/packages.json"
python3 -c "
import json, sys
path, ver = sys.argv[1], sys.argv[2]
with open(path) as f:
    data = json.load(f)
data['packages']['numr']['version'] = ver
with open(path, 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
print('packages.json: numr version -> ' + ver)
" "$TOOLS_JSON" "$ver"

# Update strip manifest
echo "Running strip-all-elf-binaries ..."
"$REPO/strip-all-elf-binaries"

# glibc check
MAX_GLIBC="$(readelf -V "$BIN" 2>/dev/null \
    | grep -oE 'GLIBC_[0-9]+\.[0-9]+' | sort -V | tail -1)"
echo "Max glibc symbol: $MAX_GLIBC (target: GLIBC_2.28)"
case "$MAX_GLIBC" in
    GLIBC_2.2[0-8]|GLIBC_2.1[0-9]|GLIBC_2.[0-9])
        echo "OK -- binary compatible with EL8 glibc 2.28" ;;
    *)
        echo "WARNING: $MAX_GLIBC > GLIBC_2.28 -- binary may not run on EL8" >&2 ;;
esac

echo ""
echo "NEEDED shared libs (must all be glibc / already-bundled):"
readelf -d "$BIN" 2>/dev/null | grep NEEDED || true

echo ""
echo "Installed: $BIN_DIR/numr.bz2"
echo ""
echo "Commit with:"
echo "  git add payload/el8.x86_64.glibc2p28/bin/numr.bz2 \\"
echo "          .strip-manifest payload/packages.json \\"
echo "          build/build-numr.sh \\"
echo "          build/farm-versions build/ADDING_BINARIES.md"
echo "  git commit -m 'feat(payload): numr ${ver} stable EL8 source build'"
