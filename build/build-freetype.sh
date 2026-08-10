#!/bin/sh
# Build FreeType from source for el8.x86_64.glibc2p28.
#
# Produces:
#   payload/el8.x86_64.glibc2p28/lib64/libfreetype.so.6.bz2
#
# WHY THIS EXISTS. Until 2026-08-10 this file was the EL8 system freetype
# 2.9.1, shanghai'd into gui_libs like the other 90 GUI libs. That is a 2018
# rasterizer carrying six years of unpatched upstream CVEs, and it is the
# shared font engine for EVERY GUI and terminal tool in the bundle: xterm, st,
# urxvt, gvim, Qt5, GTK3, cairo, pango, libxul (firefox), Xephyr, the octave
# fltk plugins. It also pinned `pdftotext` at poppler 22.12.0 -- poppler 23.01+
# requires freetype >= 2.10, so three years of poppler were unreachable.
#
# THE BLAST RADIUS IS THE RISK, NOT THE ABI. freetype keeps SONAME
# libfreetype.so.6 and is backwards-compatible across this span, but 2.9.1 ->
# 2.14.x is six years of rasterizer change, so the failure mode to expect is
# cosmetic (glyph rendering shifts), not link errors. Verify GUI apps by eye
# after a bump; `ldd` clean proves nothing about pixels.
#
# 2.14.3 removes exactly two exported symbols relative to 2.9.1:
#   FT_Outline_New_Internal, FT_Outline_Done_Internal
# Both were deprecated internals no consumer should have called. The
# --check-payload guard below proves that stays true for the whole payload
# rather than trusting the claim; see also --deep-check for runtime archives.
#
# CONFIGURE CHOICES, all load-bearing:
#   --with-harfbuzz=no  freetype>=2.10 wants harfbuzz>=2.0 for the autohinter,
#                       EL8 ships harfbuzz 1.7.5, and harfbuzz links freetype
#                       back -- a circular bundled dep. EL8's own freetype is
#                       built the same way (the 2.9.1 payload copy has no
#                       libharfbuzz NEEDED), so this changes nothing versus
#                       what shipped before. Cost: autohinter loses harfbuzz
#                       script coverage for complex scripts.
#   --with-brotli=no    WOFF2 support only, and it would add libbrotlidec.so.1
#                       to NEEDED -- a lib this repo does not bundle. Leaving
#                       it on is classic build-box masking: brotli-devel is
#                       installed here, absent on a stock farm node.
#   --with-png/zlib/bzip2=yes  matches the NEEDED set of the 2.9.1 payload copy
#                       exactly, and all three are already bundled in lib64/.
#
# Prerequisites on the build machine (EL8):
#   source /opt/rh/gcc-toolset-14/enable
#   dnf install -y gcc make pkg-config bzip2-devel zlib-devel libpng-devel
#   # patchelf at ~/.local/bin/patchelf (bundled in this repo)
#
# Usage (run from any directory):
#   ./build/build-freetype.sh --tag 2.14.3
#
# The install tree is LEFT BEHIND at /tmp/loadout-freetype-instdir-<TAG>
# (headers + lib + pkgconfig), because anything built against the loadout's
# freetype needs it: EL8's own freetype-devel is 2.9.1, so a poppler that
# requires >= 2.11 cannot configure against the system headers. Feed it in the
# same way build-modules.sh takes Tcl:
#   ./build/build-pdftotext.sh --tag 26.04.0 \
#       --with-freetype /tmp/loadout-freetype-instdir-2.14.3
# The path is version-scoped so successive builds cannot contaminate each other
# (the trap build-octave.sh hit with a fixed /tmp/octave-install).
#
# Then, as for every payload change:
#   ./build/strip-all-elf-binaries && python3.14 build/gen-content-manifest

set -eu

REPO="$(cd "$(dirname "$0")/.." && pwd)"
LIB_DIR="$REPO/payload/el8.x86_64.glibc2p28/lib64"
BIN_DIR="$REPO/payload/el8.x86_64.glibc2p28/bin"
RUNTIME_DIR="$REPO/payload/el8.x86_64.glibc2p28/runtime"
SONAME="libfreetype.so.6"
TAG=""
DEEP_CHECK=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        --tag)
            shift
            [ "$#" -gt 0 ] || { echo "missing value for --tag" >&2; exit 2; }
            TAG="$1"
            ;;
        --deep-check)
            # Also scan the runtime archives (firefox, klayout, octave, ...).
            # Costs ~4 min and ~1.5 GB of /tmp; the fast check covers bin/ and
            # lib64/, which is where all but three freetype consumers live.
            DEEP_CHECK=1
            ;;
        -h|--help) sed -n '2,/^$/p' "$0"; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done

if [ -z "$TAG" ]; then
    echo "ERROR: --tag is required. Specify a stable release, e.g.:" >&2
    echo "  $0 --tag 2.14.3" >&2
    echo "" >&2
    echo "Stable releases: https://download.savannah.gnu.org/releases/freetype/" >&2
    echo "" >&2
    echo "Policy: this project ships stable releases only." >&2
    exit 1
fi

# shellcheck disable=SC1091
[ -r /opt/rh/gcc-toolset-14/enable ] && . /opt/rh/gcc-toolset-14/enable

need() {
    command -v "$1" >/dev/null 2>&1 || {
        printf 'missing required command: %s\n' "$1" >&2
        exit 1
    }
}
need gcc
need make
need pkg-config
need curl
need bzip2
need nm
need readelf

PATCHELF="$HOME/.local/bin/patchelf"
[ -x "$PATCHELF" ] || PATCHELF="$(command -v patchelf || true)"
[ -n "$PATCHELF" ] || { echo "ERROR: patchelf not found" >&2; exit 1; }

WORK_DIR=$(mktemp -d /tmp/build-freetype-XXXXXX)
trap 'rm -rf "$WORK_DIR"' EXIT INT TERM

echo "==> Downloading freetype-${TAG}.tar.xz ..."
curl -fL -o "$WORK_DIR/ft.tar.xz" \
    "https://download.savannah.gnu.org/releases/freetype/freetype-${TAG}.tar.xz" \
    --retry 3 --retry-delay 2

echo "==> Extracting ..."
tar xJf "$WORK_DIR/ft.tar.xz" -C "$WORK_DIR"
SRC_DIR="$WORK_DIR/freetype-${TAG}"
[ -d "$SRC_DIR" ] || { echo "ERROR: expected $SRC_DIR after extract" >&2; exit 1; }

# The tag is the only version authority in this repo: gui_libs is a lib-bundle
# with an empty `version` field, and the bz2 payload is named for the SONAME so
# the full "6.20.6" minor is lost. Pin the header against --tag so a mislabelled
# tarball cannot ship silently.
echo "==> Verifying source version matches --tag ..."
HDR="$SRC_DIR/include/freetype/freetype.h"
SRC_VER=$(awk '
    /#define FREETYPE_MAJOR/ {maj=$3}
    /#define FREETYPE_MINOR/ {min=$3}
    /#define FREETYPE_PATCH/ {pat=$3}
    END {printf "%s.%s.%s", maj, min, pat}' "$HDR")
[ "$SRC_VER" = "$TAG" ] || {
    echo "ERROR: source declares $SRC_VER but --tag says $TAG" >&2
    exit 1
}
echo "  freetype.h declares $SRC_VER"

echo "==> Configuring ..."
INST_DIR="/tmp/loadout-freetype-instdir-${TAG}"
rm -rf "$INST_DIR"
cd "$SRC_DIR"
./configure \
    --prefix="$INST_DIR" \
    --enable-shared \
    --disable-static \
    --with-harfbuzz=no \
    --with-brotli=no \
    --with-png=yes \
    --with-zlib=yes \
    --with-bzip2=yes \
    >"$WORK_DIR/configure.log" 2>&1 || {
        echo "ERROR: configure failed; tail of log:" >&2
        tail -30 "$WORK_DIR/configure.log" >&2
        exit 1
    }

echo "==> Building ..."
make -j"$(nproc 2>/dev/null || echo 2)" >"$WORK_DIR/make.log" 2>&1 || {
    echo "ERROR: make failed; tail of log:" >&2
    tail -30 "$WORK_DIR/make.log" >&2
    exit 1
}
make install >"$WORK_DIR/install.log" 2>&1

BUILT=$(readlink -f "$INST_DIR/lib/$SONAME")
[ -f "$BUILT" ] || { echo "ERROR: $SONAME not produced" >&2; exit 1; }
echo "  built $(basename "$BUILT")"

WORK_SO="$WORK_DIR/$SONAME"
cp "$BUILT" "$WORK_SO"
/usr/bin/strip "$WORK_SO"
# lib64/ libs get RPATH '$ORIGIN' (NOT '$ORIGIN/../lib64', which is what a
# bin/ binary gets) -- they resolve their siblings in the same directory.
# shellcheck disable=SC2016  # $ORIGIN is a literal ld.so token
"$PATCHELF" --set-rpath '$ORIGIN' "$WORK_SO"

echo "==> Checking NEEDED closure ..."
# Anything outside this set is either a lib the repo does not bundle (brotli)
# or a circular bundled dep (harfbuzz). Both are silent on this box and fatal
# on a stock farm node, so fail rather than warn.
NEEDED=$(readelf -d "$WORK_SO" | sed -n 's/.*NEEDED.*\[\(.*\)\]/\1/p')
echo "  NEEDED: $(echo "$NEEDED" | tr '\n' ' ')"
for so in $NEEDED; do
    case "$so" in
        libbz2.so.1|libpng16.so.16|libz.so.1) ;;
        libpthread.so.0|libdl.so.2|libm.so.6|libc.so.6) ;;
        *)
            echo "ERROR: unexpected NEEDED '$so'." >&2
            echo "       Not bundled and not EL8-base-guaranteed. Check the" >&2
            echo "       --with-harfbuzz=no / --with-brotli=no flags." >&2
            exit 1
            ;;
    esac
done

echo "==> Checking glibc floor ..."
MAX_GLIBC=$(readelf -V "$WORK_SO" 2>/dev/null \
    | grep -oE 'GLIBC_[0-9]+\.[0-9]+' | sort -V | tail -1)
echo "  max glibc symbol: ${MAX_GLIBC:-none} (target: GLIBC_2.28)"
case "${MAX_GLIBC:-GLIBC_2.0}" in
    GLIBC_2.2[0-8]|GLIBC_2.1[0-9]|GLIBC_2.[0-9]) ;;
    *) echo "ERROR: needs $MAX_GLIBC; EL8 has glibc 2.28" >&2; exit 1 ;;
esac

# ---------------------------------------------------------------------------
# Symbol-closure guard.
#
# This is the check that matters for a shared rasterizer. freetype drops
# deprecated exports between releases (2.14.3 loses FT_Outline_New_Internal
# and FT_Outline_Done_Internal versus 2.9.1). A dropped symbol some bundled
# consumer imports is an undefined-symbol crash at first font load, on a stock
# farm node, long after the release -- exactly the build-box-masking class
# this repo keeps hitting. So: every FT_* symbol any payload ELF imports must
# be exported by the lib about to ship.
# ---------------------------------------------------------------------------
echo "==> Checking FT_* symbol closure against the payload ..."
SCAN="$WORK_DIR/scan"
mkdir -p "$SCAN"
nm -D --defined-only "$WORK_SO" | awk '{print $NF}' | sort -u > "$WORK_DIR/exports"

collect_undef() {
    # $1 = ELF path, $2 = label to report if it fails
    nm -D --undefined-only "$1" 2>/dev/null \
        | awk -v l="$2" '/ FT_/ {print $NF "\t" l}'
}

: > "$WORK_DIR/imports"
for f in "$LIB_DIR"/*.bz2 "$BIN_DIR"/*.bz2; do
    [ -f "$f" ] || continue
    b=$(basename "$f" .bz2)
    # The lib being replaced is not its own consumer.
    [ "$b" = "$SONAME" ] && continue
    bzip2 -dc "$f" > "$SCAN/$b" 2>/dev/null || continue
    collect_undef "$SCAN/$b" "$b" >> "$WORK_DIR/imports"
    rm -f "$SCAN/$b"
done

if [ "$DEEP_CHECK" = "1" ]; then
    echo "  --deep-check: also scanning runtime archives ..."
    for t in "$RUNTIME_DIR"/*.tar.bz2 "$RUNTIME_DIR"/*.tar.bz2.part-000; do
        [ -f "$t" ] || continue
        case "$t" in
            *.part-000) name=$(basename "$t" .tar.bz2.part-000)
                        cat "$RUNTIME_DIR/$name".tar.bz2.part-* > "$SCAN/$name.tar.bz2" ;;
            *)          name=$(basename "$t" .tar.bz2)
                        cp "$t" "$SCAN/$name.tar.bz2" ;;
        esac
        rm -rf "$SCAN/x"; mkdir -p "$SCAN/x"
        tar xjf "$SCAN/$name.tar.bz2" -C "$SCAN/x" 2>/dev/null || true
        find "$SCAN/x" -type f -print | while read -r f; do
            collect_undef "$f" "$name:$(basename "$f")"
        done >> "$WORK_DIR/imports"
        rm -rf "$SCAN/x" "$SCAN/$name.tar.bz2"
    done
fi

# A scan that collected nothing would pass this guard vacuously -- the exact
# "green test that never ran the code" shape this repo has been burned by. The
# payload has had freetype consumers since it had a GUI; zero means the scan
# broke (no nm, a payload layout change), not that the tree is clean.
N_IMPORTS=$(cut -f1 "$WORK_DIR/imports" | sort -u | wc -l)
if [ "$N_IMPORTS" -lt 20 ]; then
    echo "ERROR: only $N_IMPORTS distinct FT_* imports found across the payload." >&2
    echo "       Expected >= 20 (the 2026-08-10 baseline was 63 without" >&2
    echo "       --deep-check, 66 with it). The scan is broken -- this guard is" >&2
    echo "       not passing, it is failing to run." >&2
    exit 1
fi

MISSING=$(sort -u "$WORK_DIR/imports" | while IFS="$(printf '\t')" read -r sym owner; do
    grep -qx "$sym" "$WORK_DIR/exports" || printf '%s (imported by %s)\n' "$sym" "$owner"
done)
if [ -n "$MISSING" ]; then
    echo "ERROR: freetype $TAG does not export symbols the payload imports:" >&2
    echo "$MISSING" >&2
    exit 1
fi
echo "  OK -- $N_IMPORTS distinct FT_* imports, all exported"

echo "==> Staging ..."
bzip2 -kf "$WORK_SO"
cp "${WORK_SO}.bz2" "$LIB_DIR/${SONAME}.bz2"
chmod 644 "$LIB_DIR/${SONAME}.bz2"

echo ""
echo "Staged: payload/el8.x86_64.glibc2p28/lib64/${SONAME}.bz2  ($(du -h "$LIB_DIR/${SONAME}.bz2" | cut -f1))"
echo "Devel tree kept at: $INST_DIR"
echo "  (pass to anything that must build against it, e.g."
echo "   ./build/build-pdftotext.sh --tag 26.04.0 --with-freetype $INST_DIR)"
echo ""
echo "gui_libs owns this lib and carries no per-lib version field, so the"
echo "version of record is build/ADDING_BINARIES.md -- update the freetype"
echo "note there to $TAG."
echo ""
echo "Next:"
echo "  ./build/strip-all-elf-binaries"
echo "  python3.14 build/gen-content-manifest"
echo "  git add payload/el8.x86_64.glibc2p28/lib64/${SONAME}.bz2 .strip-manifest .content-manifest"
