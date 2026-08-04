#!/bin/sh
# Build restic -- fast, secure, user-space backup with deduplication, compression,
# incremental snapshots, and authenticated encryption -- to a repo on any filesystem.
# No root, no FUSE/cron/dbus required (unlike backintime); a single static Go binary.
#   https://github.com/restic/restic   (BSD-2-Clause)
#
# Go static build (CGO_ENABLED=0): the result links NO shared libraries, so it runs on
# any EL8 regardless of glibc -- nothing to bundle, no patchelf, no RPATH.
#
# Usage (run from any directory):
#   /path/to/build-restic.sh --tag v0.19.1

set -eu

REPO="$(cd "$(dirname "$0")/.." && pwd)"
BIN_DIR="$REPO/payload/el8.x86_64.glibc2p28/bin"
SRC_URL="https://github.com/restic/restic.git"

tag=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --tag) shift; [ "$#" -gt 0 ] || { echo "missing value for --tag" >&2; exit 2; }; tag="$1" ;;
        -h|--help) sed -n '2,/^$/p' "$0"; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done
[ -n "$tag" ] || { echo "ERROR: --tag is required (e.g. --tag v0.19.1)" >&2; exit 1; }

need() { command -v "$1" >/dev/null 2>&1 || { echo "missing required command: $1" >&2; exit 1; }; }
need git; need go; need strip; need bzip2

SRCDIR="/tmp/restic-${tag}"
rm -rf "$SRCDIR"
echo "Cloning restic @ ${tag}..."
git clone -q --depth 1 --branch "$tag" "$SRC_URL" "$SRCDIR"

echo "Building (static, CGO disabled)..."
BIN="/tmp/restic-${tag}.bin"
( cd "$SRCDIR" && CGO_ENABLED=0 go build -mod=mod -trimpath -ldflags "-s -w" -o "$BIN" ./cmd/restic )
[ -x "$BIN" ] || { echo "ERROR: build produced no binary" >&2; exit 1; }

case "$(file -b "$BIN")" in
    *statically*) : ;;
    *) echo "ERROR: restic is not statically linked -- CGO leaked in" >&2; exit 1 ;;
esac

# Roundtrip smoke: a backup tool that runs but can't restore is worthless, and
# --version cannot detect that. Prove init -> backup -> restore -> content-match.
echo "Smoke: init/backup/restore roundtrip..."
W="/tmp/restic-smoke-${tag}"; rm -rf "$W"; mkdir -p "$W/src" "$W/rec"
echo "restic-roundtrip-canary" > "$W/src/canary.txt"
RESTIC_PASSWORD=smoke RESTIC_REPOSITORY="$W/repo" "$BIN" init >/dev/null
RESTIC_PASSWORD=smoke RESTIC_REPOSITORY="$W/repo" "$BIN" backup "$W/src" >/dev/null
RESTIC_PASSWORD=smoke RESTIC_REPOSITORY="$W/repo" "$BIN" restore latest --target "$W/rec" >/dev/null
grep -qr "restic-roundtrip-canary" "$W/rec" || { echo "ERROR: restore roundtrip failed" >&2; exit 1; }
rm -rf "$W"
echo "  roundtrip OK ($("$BIN" version | awk '{print $1, $2}'))"

WORK="/tmp/restic_work_${tag}"
cp "$BIN" "$WORK"; strip "$WORK"; bzip2 -kf "$WORK"
cp "${WORK}.bz2" "$BIN_DIR/restic.bz2"
rm -f "$WORK" "${WORK}.bz2" "$BIN"
echo "Installed: $BIN_DIR/restic.bz2 ($(du -h "$BIN_DIR/restic.bz2" | cut -f1))"
echo ""
echo "Next: $REPO/build/strip-all-elf-binaries && $REPO/build/gen-content-manifest && update packages.json"
