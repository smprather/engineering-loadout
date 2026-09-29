#!/bin/sh
# Build yamlfmt (YAML formatter) as a static bin for el8.x86_64.glibc2p28.
#
# yamlfmt is the `yaml` filetype formatter in envs/nvim. It is a pure-Go program
# published as a STATIC linux/amd64 binary (zero NEEDED entries, no glibc
# involvement at all), so the download is the whole build: extract, verify
# upstream's own sha256, strip, bzip2, done. Nothing to compile, which is why it
# is a straight `bin` package rather than a source build.
#
# Before this package existed conform.nvim's `yaml = { "yamlfmt" }` mapping named
# a binary that was never installed, so YAML silently fell through to
# lsp_format = "fallback" (see tests/nvim-formatters-resolve).
#
# Integrity: the release ships a checksums.txt covering every platform archive;
# the linux/x86_64 entry is verified with sha256sum -c before the binary is used.
#
# Usage (run from any directory):
#   ./build/build-yamlfmt.sh --tag 0.21.0

set -eu

REPO="$(cd "$(dirname "$0")/.." && pwd)"
BIN_DIR="$REPO/payload/el8.x86_64.glibc2p28/bin"
PATCHELF="${LOADOUT_PATCHELF:-/usr/bin/patchelf}"

while [ "$#" -gt 0 ]; do
    case "$1" in
        --tag)
            shift
            [ "$#" -gt 0 ] || { echo "missing value for --tag" >&2; exit 2; }
            VERSION="$1"
            ;;
        -h|--help)
            sed -n '2,/^Usage/p' "$0"
            exit 0
            ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done

[ -n "${VERSION:-}" ] || { echo "ERROR: --tag <version> required" >&2; exit 2; }
V="${VERSION#v}"

# The release publishes one archive per platform plus a checksums.txt. Stable
# releases only (yamlfmt has no rolling channel); see
# https://github.com/google/yamlfmt/releases.
ARCHIVE="yamlfmt_${V}_Linux_x86_64.tar.gz"
BASE_URL="https://github.com/google/yamlfmt/releases/download/v${V}"

WORK_DIR=$(mktemp -d "${TMPDIR:-/var/tmp}/build-yamlfmt-XXXXXX")
trap 'rm -rf "$WORK_DIR"' EXIT INT TERM

echo "==> Fetching yamlfmt ${V} (${ARCHIVE}) ..."
curl -fL -o "$WORK_DIR/$ARCHIVE" "$BASE_URL/$ARCHIVE" --retry 3 --retry-delay 2
curl -fL -o "$WORK_DIR/checksums.txt" "$BASE_URL/checksums.txt" --retry 3 --retry-delay 2

echo "==> Verifying against the release checksums.txt ..."
( cd "$WORK_DIR" && grep " ${ARCHIVE}\$" checksums.txt | sha256sum -c - ) || {
    echo "ERROR: yamlfmt tarball failed its upstream sha256 check" >&2
    exit 1
}

echo "==> Extracting ..."
tar xzf "$WORK_DIR/$ARCHIVE" -C "$WORK_DIR"
[ -f "$WORK_DIR/yamlfmt" ] || { echo "ERROR: yamlfmt binary not in the archive" >&2; exit 1; }
chmod 755 "$WORK_DIR/yamlfmt"

# Sanity: the binary must be a static ELF for this arch. A dynamic build here
# would mean the upstream release layout changed and the "no glibc floor"
# argument in the header no longer holds.
if readelf -d "$WORK_DIR/yamlfmt" 2>/dev/null | grep -q NEEDED; then
    echo "ERROR: yamlfmt is dynamically linked; expected the static release build" >&2
    readelf -d "$WORK_DIR/yamlfmt" | grep NEEDED >&2
    exit 1
fi

echo "==> Stage-verify ..."
"$WORK_DIR/yamlfmt" --version
# conform feeds YAML on stdin with `-` (yamlfmt's own convention, unlike
# prettier), so prove that exact path.
printf 'a:   1\nb:\n  -  x\n  -   y\n' | "$WORK_DIR/yamlfmt" - > "$WORK_DIR/out.yaml"
grep -q '^a: 1$' "$WORK_DIR/out.yaml" || {
    echo "ERROR: yamlfmt did not reformat the fixture" >&2
    cat "$WORK_DIR/out.yaml" >&2
    exit 1
}
echo "  OK: stdin -> stdout, reformats"

echo "==> Packaging ..."
# Upstream ships it already stripped; strip is a no-op then, but keep the call so
# a future dynamic build gets stripped before the RPATH step (order matters).
strip "$WORK_DIR/yamlfmt"
# No NEEDED, so there is nothing to point an RPATH at; the static binary needs
# no $ORIGIN entries and must not be given any.
"$PATCHELF" --print-rpath "$WORK_DIR/yamlfmt" >/dev/null 2>&1 || true
bzip2 -kf "$WORK_DIR/yamlfmt"
cp "$WORK_DIR/yamlfmt.bz2" "$BIN_DIR/yamlfmt.bz2"
echo "  Wrote: $BIN_DIR/yamlfmt.bz2"

echo ""
echo "Done. Produced:"
echo "  $BIN_DIR/yamlfmt.bz2"
echo ""
echo "Reminders:"
echo "  - ./loadout completion bash > envs/bash/global/completions/loadout.bash"
echo "  - build/ADDING_BINARIES.md note is MANDATORY"
echo ""
echo "Commit with:"
echo "  git add payload/el8.x86_64.glibc2p28/bin/yamlfmt.bz2 .strip-manifest packages.json build/build-yamlfmt.sh"
