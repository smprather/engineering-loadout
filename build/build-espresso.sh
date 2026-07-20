#!/bin/sh
# Build the Berkeley espresso two-level logic minimizer for el8.x86_64.
#
# espresso reduces a boolean function (PLA truth-table / cover) to a minimal
# sum-of-products -- the classic EDA logic-minimization tool. Source is the
# modernized, buildable re-host of the original UC Berkeley espresso:
#   https://github.com/classabbyamp/espresso-logic   (MIT + original Berkeley license)
#
# TAG CHOICE -- read before bumping: use v1.1.1. The `2.0.0` tag is NOT a real
# release -- it is a mid-history "node project" experiment that does not build as a
# CLI (`make` fails at a prepare step); the repo was "converted back to a plain CLI
# executable" in commits AFTER it. v1.1.1 is the last good CLI tag and builds clean
# on modern gcc. The repo is archived (read-only since 2021), so v1.1.1 is stable
# and will not move.
#
# Pure C, links libc ONLY (glibc floor GLIBC_2.7, far under EL8's 2.28), so there is
# nothing to bundle and no patchelf/RPATH -- just build -> strip -> bzip2.
#
# Usage (run from any directory):
#   /path/to/build-espresso.sh --tag v1.1.1

set -eu

REPO="$(cd "$(dirname "$0")/.." && pwd)"
BIN_DIR="$REPO/payload/el8.x86_64.glibc2p28/bin"
SRC_URL="https://github.com/classabbyamp/espresso-logic.git"

tag=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --tag) shift; [ "$#" -gt 0 ] || { echo "missing value for --tag" >&2; exit 2; }; tag="$1" ;;
        -h|--help) sed -n '2,/^$/p' "$0"; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done

if [ -z "$tag" ]; then
    echo "ERROR: --tag is required (stable release tag). Use:" >&2
    echo "  $0 --tag v1.1.1" >&2
    echo "  (the 2.0.0 tag is a broken node-project experiment -- see this script's header)" >&2
    exit 1
fi

need() { command -v "$1" >/dev/null 2>&1 || { echo "missing required command: $1" >&2; exit 1; }; }
need git; need make; need cc; need strip; need bzip2

SRCDIR="/tmp/espresso-${tag}"
rm -rf "$SRCDIR"
echo "Cloning espresso-logic @ ${tag}..."
git clone -q "$SRC_URL" "$SRCDIR"
git -C "$SRCDIR" checkout -q "$tag"

echo "Building..."
make -C "$SRCDIR/espresso-src" clean >/dev/null 2>&1 || true
make -C "$SRCDIR/espresso-src" >/dev/null

BIN="$SRCDIR/bin/espresso"
[ -x "$BIN" ] || { echo "ERROR: build produced no bin/espresso" >&2; exit 1; }

# Smoke the fresh binary before packaging: minimize 3-input majority, expect 3
# product terms (ab + ac + bc). A dead datadir-style silent failure has no meaning
# for espresso -- it is a pure function -- but a broken build could still mis-reduce,
# so assert the actual result.
printf '.i 3\n.o 1\n011 1\n101 1\n110 1\n111 1\n.e\n' > "$SRCDIR/maj.pla"
p=$("$BIN" "$SRCDIR/maj.pla" | sed -n 's/^\.p //p')
[ "$p" = "3" ] || { echo "ERROR: majority smoke expected 3 product terms, got '$p'" >&2; exit 1; }
echo "  smoke OK: majority -> 3 product terms"

echo "Max glibc symbol: $(readelf -V "$BIN" 2>/dev/null | grep -oE 'GLIBC_[0-9.]+' | sort -V | tail -1) (target <= GLIBC_2.28)"

WORK="/tmp/espresso_work_${tag}"
cp "$BIN" "$WORK"
strip "$WORK"
bzip2 -kf "$WORK"
cp "${WORK}.bz2" "$BIN_DIR/espresso.bz2"
rm -f "$WORK" "${WORK}.bz2"
echo "Installed: $BIN_DIR/espresso.bz2"

echo ""
echo "Next:"
echo "  $REPO/strip-all-elf-binaries && $REPO/build/gen-content-manifest"
echo "  $REPO/loadout completion bash > $REPO/envs/bash/global/completions/loadout.bash"
echo "  git add $BIN_DIR/espresso.bz2 $REPO/payload/packages.json"
