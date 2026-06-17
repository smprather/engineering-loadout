#!/bin/sh
# Build `models` (TUI/CLI for browsing AI models, benchmarks, coding agents) from
# source for el8.x86_64.glibc2p28.
#
# models (crate `modelsdev`) is Rust. The ONLY official linux prebuilt is
# `*-linux-gnu` built on a modern host -- it needs GLIBC_2.39 and aborts on EL8
# (glibc 2.28):
#   models: /lib64/libc.so.6: version `GLIBC_2.29' not found
# Building here yields a native glibc-2.28 binary (max GLIBC symbol 2.28). The
# crate also defines a second `transform` bin (an internal data helper) -- we
# build and ship ONLY `models` via `--bin models`.
#
# Runtime libs: only glibc + libgcc_s (all EL8 base). The TUI fetches model data
# from models.dev over HTTPS at runtime (reqwest/rustls, no openssl NEEDED), so
# it needs network for live data but starts fine offline.
#
# Policy: always build from a stable tagged release. See tags at:
#   https://github.com/reyamira/models/releases
#
# Prerequisites: rustc + cargo (tested with 1.95), gcc-toolset-14 (optional),
# patchelf at ~/.local/bin/patchelf, network for crates.io (outside the sandbox).
#
# Usage (run from any directory):
#   /path/to/build-models.sh --tag v0.12.3

set -eu

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
BIN_DIR="$REPO/pre_built/el8.x86_64.glibc2p28/bin"
PATCHELF="${HOME}/.local/bin/patchelf"
CLONE_URL="https://github.com/reyamira/models.git"

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
    echo "  $0 --tag v0.12.3" >&2
    echo "" >&2
    echo "Stable releases: https://github.com/reyamira/models/releases" >&2
    exit 1
fi

if [ -r /opt/rh/gcc-toolset-14/enable ]; then
    # shellcheck disable=SC1091
    . /opt/rh/gcc-toolset-14/enable
fi

command -v cargo >/dev/null 2>&1 || { echo "missing required command: cargo" >&2; exit 1; }
[ -x "$PATCHELF" ] || { echo "missing patchelf at $PATCHELF" >&2; exit 1; }

SRCDIR="/tmp/models-src-${tag}"
rm -rf "$SRCDIR"
git clone --depth 1 --branch "$tag" "$CLONE_URL" "$SRCDIR"
cd "$SRCDIR"

echo "Building models (release, --bin models) ..."
cargo build --release --bin models

BIN="$SRCDIR/target/release/models"
[ -f "$BIN" ] || { echo "build did not produce $BIN" >&2; exit 1; }
echo "Build complete: $("$BIN" --version 2>&1 | head -1)"

WORK="/tmp/models_work_${tag}"
cp "$BIN" "$WORK"
strip "$WORK"
"$PATCHELF" --set-rpath '$ORIGIN/../lib64:$ORIGIN/../lib' "$WORK"
bzip2 -kf "$WORK"
cp "${WORK}.bz2" "$BIN_DIR/models.bz2"
chmod 644 "$BIN_DIR/models.bz2"
rm -f "$WORK" "${WORK}.bz2"

# Update packages.json version (strip any leading v from the tag).
ver="${tag#v}"
python3 -c "
import re, sys
path = sys.argv[1]; ver = sys.argv[2]
txt = open(path).read()
txt = re.sub(r'(\"models\".*?\"version\":\s*\")([^\"]+)(\")', r'\g<1>' + ver + r'\3', txt)
open(path, 'w').write(txt)
print('packages.json: models version -> ' + ver)
" "$REPO/pre_built/packages.json" "$ver"

echo "Running strip_all_elf_binaries ..."
"$REPO/strip_all_elf_binaries"

MAX_GLIBC="$(readelf -V "$BIN" 2>/dev/null | grep -oE 'GLIBC_[0-9]+\.[0-9]+' | sort -V | tail -1)"
echo "Max glibc symbol: $MAX_GLIBC (target: GLIBC_2.28)"

echo ""
echo "Installed: $BIN_DIR/models.bz2"
