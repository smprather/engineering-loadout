#!/bin/sh
# Build pdftotext (from poppler) from source for el8.x86_64.glibc2p28.
#
# pdftotext is the standard CLI tool for extracting text from PDF files.
# Part of the poppler-utils suite; reads PDF structure and emits plain text.
# The '-layout' flag attempts to preserve multi-column layout.
#
# poppler releases: https://poppler.freedesktop.org/releases.html
# Version format: YY.MM.patch (e.g. 22.12.0)
#
# FREETYPE. This used to pin poppler at 22.12.0, because EL8 ships freetype
# 2.9.1 and poppler 23.01+ wants 2.10+. The loadout now source-builds freetype
# (build/build-freetype.sh) and bundles it in lib64/, so that pin is gone --
# but EL8's *headers* are still 2.9.1, so cmake configures against the system
# freetype and fails unless you point it at the loadout build:
#
#   ./build/build-freetype.sh --tag 2.14.3
#   ./build/build-pdftotext.sh --tag 26.04.0 \
#       --with-freetype /tmp/loadout-freetype-instdir-2.14.3
#
# THE CEILING IS NOW FONTCONFIG, NOT FREETYPE. poppler's own requirements by
# release (grep FREETYPE_VERSION / FONTCONFIG_VERSION in its CMakeLists.txt):
#
#   poppler        freetype   fontconfig   C++
#   23.12          2.10       2.13         17
#   24.08 .. 26.04 2.11       2.13         20 / 23
#   26.06+         2.13       2.15         23
#
# EL8 has fontconfig 2.13.1, so 26.04.0 is the last buildable release. Going
# past it means source-building and bundling fontconfig too -- a much bigger
# blast radius than freetype, since fontconfig 2.15 also moves the font-cache
# format and would force a cache rebuild for every user. Do not raise --tag
# past 26.04.0 without doing that work.
#
# libtiff is disabled (-DENABLE_LIBTIFF=OFF): poppler >= 25.x wants tiff 4.3
# and EL8 has 4.0.9. TIFF only feeds pdfimages/pdftoppm output formats, which
# this package does not ship, so turning it off costs nothing here.
#
# This script builds libpoppler as a STATIC library so that pdftotext
# is fully self-contained (no companion libpoppler.so to bundle).
# Runtime deps (all present on EL8 base or EL8 with powertools packages):
#   libfreetype.so.6, libfontconfig.so.1, libjpeg.so.62, libpng16.so.16,
#   liblcms2.so.2, libopenjp2.so.7, libtiff.so.5, libstdc++.so.6
# curl is disabled (-DENABLE_LIBCURL=OFF) to avoid pulling in libcurl and
# its transitive deps (openssl, krb5, etc.) on minimal nodes.
#
# lcms2 and openjpeg2 are NOT in the EL8 base install (they're in
# powertools/appstream) so their shared libs are bundled in lib64/.
#   liblcms2.so.2   -> payload/el8.x86_64.glibc2p28/lib64/liblcms2.so.2.bz2
#   libopenjp2.so.7 -> payload/el8.x86_64.glibc2p28/lib64/libopenjp2.so.7.bz2
#
# Prerequisites on the build machine (EL8):
#   source /opt/rh/gcc-toolset-14/enable
#   dnf install -y cmake gcc-c++ pkg-config \
#     fontconfig-devel freetype-devel libjpeg-turbo-devel libpng-devel \
#     libtiff-devel zlib-devel lcms2-devel openjpeg2-devel
#   # lcms2-devel and openjpeg2-devel are in the PowerTools repo:
#   # dnf config-manager --set-enabled powertools
#
# Usage (run from any directory):
#   ./build/build-pdftotext.sh --tag 26.04.0 \
#       --with-freetype /tmp/loadout-freetype-instdir-2.14.3

set -eu

REPO="$(cd "$(dirname "$0")/.." && pwd)"
BIN_DIR="$REPO/payload/el8.x86_64.glibc2p28/bin"
LIB_DIR="$REPO/payload/el8.x86_64.glibc2p28/lib64"
TAG=""
WITH_FREETYPE=""
DATA_VERSION="0.4.12"

while [ "$#" -gt 0 ]; do
    case "$1" in
        --tag)
            shift
            [ "$#" -gt 0 ] || { echo "missing value for --tag" >&2; exit 2; }
            TAG="$1"
            ;;
        --data-tag)
            shift
            [ "$#" -gt 0 ] || { echo "missing value for --data-tag" >&2; exit 2; }
            DATA_VERSION="$1"
            ;;
        --with-freetype)
            shift
            [ "$#" -gt 0 ] || { echo "missing value for --with-freetype" >&2; exit 2; }
            WITH_FREETYPE="$1"
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
    echo "  $0 --tag 26.04.0 --with-freetype /tmp/loadout-freetype-instdir-2.14.3" >&2
    echo "" >&2
    echo "Stable releases: https://poppler.freedesktop.org/releases.html" >&2
    echo "" >&2
    echo "Policy: this project ships stable releases only." >&2
    echo "NOTE: 26.04.0 is the EL8 ceiling -- 26.06+ needs fontconfig 2.15." >&2
    exit 1
fi

# EL8's freetype-devel is 2.9.1. Without an explicit prefix cmake finds those
# headers and either fails the version check (poppler >= 23.01) or -- worse, if
# a future EL8 point release nudges the system version -- silently builds
# against a freetype that is NOT the one shipped in lib64/.
if [ -z "$WITH_FREETYPE" ]; then
    echo "ERROR: --with-freetype is required." >&2
    echo "       EL8's system freetype-devel is 2.9.1; poppler needs >= 2.11." >&2
    echo "       Build the loadout's freetype first, then pass its install dir:" >&2
    echo "         ./build/build-freetype.sh --tag 2.14.3" >&2
    echo "         $0 --tag $TAG --with-freetype /tmp/loadout-freetype-instdir-2.14.3" >&2
    exit 1
fi
[ -f "$WITH_FREETYPE/include/freetype2/freetype/freetype.h" ] || {
    echo "ERROR: no freetype headers under $WITH_FREETYPE" >&2
    echo "       expected $WITH_FREETYPE/include/freetype2/freetype/freetype.h" >&2
    exit 1
}

VERSION="$TAG"

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
need g++
need cmake
need pkg-config
need patchelf

WORK_DIR=$(mktemp -d /tmp/build-pdftotext-XXXXXX)
trap 'rm -rf "$WORK_DIR"' EXIT

echo "==> Downloading poppler-${VERSION}.tar.xz ..."
curl -fL -o "$WORK_DIR/poppler.tar.xz" \
    "https://poppler.freedesktop.org/poppler-${VERSION}.tar.xz" \
    --retry 3 --retry-delay 2

echo "==> Extracting ..."
tar xJf "$WORK_DIR/poppler.tar.xz" -C "$WORK_DIR"
SRC_DIR="$WORK_DIR/poppler-${VERSION}"

echo "==> Patching GlobalParams for a POPPLER_DATADIR runtime override ..."
# Upstream Unix poppler resolves poppler-data only from the compile-time
# POPPLER_DATADIR macro, which here is the temp build prefix -- dead once
# deployed. The single use site already prefers the constructor-supplied
# popplerDataDir, so seeding that member from the environment when the caller
# passed nothing covers CMap/cidToUnicode/nameToUnicode/unicodeMap lookups
# uniformly. The bin/pdftotext wrapper exports POPPLER_DATADIR from the
# install prefix.
#
# The constructor signature is version-sensitive: it took `const char *` up to
# poppler 22.x and takes `std::string` from (at least) 26.04. The grep below is
# what turns a silent no-op patch into a hard failure -- a pdftotext built
# without it extracts CJK as garbage rather than crashing, so nothing
# downstream would notice. If a bump lands here, re-read GlobalParams.cc and
# update the expression; do not relax the check.
GP="$SRC_DIR/poppler/GlobalParams.cc"
sed -i \
    -e 's|^#include <config.h>$|#include <config.h>\n#include <cstdlib>|' \
    -e 's|GlobalParams::GlobalParams(std::string customPopplerDataDir) : popplerDataDir(std::move(customPopplerDataDir))|GlobalParams::GlobalParams(std::string customPopplerDataDir) : popplerDataDir(customPopplerDataDir.empty() \&\& getenv("POPPLER_DATADIR") ? std::string(getenv("POPPLER_DATADIR")) : std::move(customPopplerDataDir))|' \
    "$GP"
grep -q 'getenv("POPPLER_DATADIR")' "$GP" || {
    echo "ERROR: POPPLER_DATADIR patch did not apply to $GP" >&2
    echo "       The GlobalParams constructor signature likely changed;" >&2
    echo "       inspect it and update the sed expression above." >&2
    exit 1
}
grep -q '^#include <cstdlib>$' "$GP" || {
    echo "ERROR: <cstdlib> include not added to $GP (getenv would not declare)" >&2
    exit 1
}

mkdir "$SRC_DIR/build"
cd "$SRC_DIR/build"

echo "==> Configuring (static libpoppler, utils only, no Qt/GLib) ..."
cmake \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$WORK_DIR/install" \
    -DCMAKE_PREFIX_PATH="$WITH_FREETYPE" \
    -DFreetype_ROOT="$WITH_FREETYPE" \
    -DENABLE_LIBTIFF=OFF \
    -DBUILD_SHARED_LIBS=OFF \
    -DENABLE_UTILS=ON \
    -DENABLE_GLIB=OFF \
    -DENABLE_GOBJECT_INTROSPECTION=OFF \
    -DENABLE_QT5=OFF \
    -DENABLE_QT6=OFF \
    -DENABLE_GTK_DOC=OFF \
    -DBUILD_GTK_TESTS=OFF \
    -DENABLE_NSS3=OFF \
    -DENABLE_GPGME=OFF \
    -DENABLE_LIBOPENJPEG=openjpeg2 \
    -DENABLE_LIBCURL=OFF \
    -DENABLE_BOOST=OFF \
    -DENABLE_CPP=OFF \
    ..

echo "==> Building pdftotext ..."
# Build only pdftotext target (skips pdfimages, pdftoppm, etc.)
make -j"$(nproc 2>/dev/null || echo 2)" pdftotext

PDFTOTEXT_BIN="$SRC_DIR/build/utils/pdftotext"
if [ ! -f "$PDFTOTEXT_BIN" ]; then
    echo "ERROR: pdftotext binary not found at $PDFTOTEXT_BIN after build" >&2
    exit 1
fi

echo "==> Verifying binary ..."
# The freshly linked binary needs the loadout freetype, not EL8's 2.9.1:
# newer-linked against older is the direction that is NOT compatible.
VER_OUT=$(LD_LIBRARY_PATH="$WITH_FREETYPE/lib" "$PDFTOTEXT_BIN" -v 2>&1 | head -2)
echo "$VER_OUT"
echo "$VER_OUT" | grep -qi "pdftotext\|poppler" || {
    echo "WARNING: unexpected output from 'pdftotext -v'" >&2
}

echo "==> Checking runtime library requirements ..."
LD_LIBRARY_PATH="$WITH_FREETYPE/lib" ldd "$PDFTOTEXT_BIN" \
    | grep -v "linux-vdso\|ld-linux" | awk '{print "  " $0}'

echo "==> Checking glibc symbol requirements ..."
MAX_GLIBC="$(readelf -V "$PDFTOTEXT_BIN" 2>/dev/null \
    | grep -oE 'GLIBC_[0-9]+\.[0-9]+' | sort -V | tail -1)"
echo "  Max glibc symbol: $MAX_GLIBC (target: GLIBC_2.28)"
case "$MAX_GLIBC" in
    GLIBC_2.2[0-8]|GLIBC_2.1[0-9]|GLIBC_2.[0-9])
        echo "  OK -- binary compatible with EL8 glibc 2.28" ;;
    *)
        echo "  WARNING: $MAX_GLIBC > GLIBC_2.28 -- binary may not run on EL8" >&2 ;;
esac

echo "==> Bundling companion shared libs not present in EL8 base ..."
# liblcms2 and libopenjp2 are in powertools/appstream, not EL8 base.
# Bundle them so pdftotext works on minimal farm nodes.
LCMS2_SO="$(ldconfig -p 2>/dev/null | grep 'liblcms2\.so\.2' | awk '{print $NF}' | head -1)"
OPENJP2_SO="$(ldconfig -p 2>/dev/null | grep 'libopenjp2\.so\.7' | awk '{print $NF}' | head -1)"

for SOFILE in "$LCMS2_SO" "$OPENJP2_SO"; do
    if [ -z "$SOFILE" ] || [ ! -f "$SOFILE" ]; then
        echo "  WARNING: could not locate $SOFILE -- skipping bundle" >&2
        continue
    fi
    SONAME="$(basename "$SOFILE")"
    echo "  Bundling $SONAME from $SOFILE"
    WORK_SO="$WORK_DIR/$SONAME"
    cp "$SOFILE" "$WORK_SO"
    strip "$WORK_SO"
    bzip2 -kf "$WORK_SO"
    cp "${WORK_SO}.bz2" "$LIB_DIR/${SONAME}.bz2"
    echo "  -> $LIB_DIR/${SONAME}.bz2"
done

echo "==> Downloading poppler-data-${DATA_VERSION} ..."
curl -fL -o "$WORK_DIR/poppler-data.tar.gz" \
    "https://poppler.freedesktop.org/poppler-data-${DATA_VERSION}.tar.gz" \
    --retry 3 --retry-delay 2
tar xzf "$WORK_DIR/poppler-data.tar.gz" -C "$WORK_DIR"
DATA_SRC="$WORK_DIR/poppler-data-${DATA_VERSION}"

echo "==> Packaging poppler-data runtime archive ..."
RUNTIME_DIR="$REPO/payload/el8.x86_64.glibc2p28/runtime"
mkdir -p "$RUNTIME_DIR"
STAGE="$WORK_DIR/stage"
mkdir -p "$STAGE/share/poppler"
for d in cMap cidToUnicode nameToUnicode unicodeMap; do
    cp -a "$DATA_SRC/$d" "$STAGE/share/poppler/$d"
done
cp "$DATA_SRC/COPYING" "$STAGE/share/poppler/COPYING" 2>/dev/null || true
cp "$DATA_SRC/COPYING.adobe" "$STAGE/share/poppler/COPYING.adobe" 2>/dev/null || true
tar cjf "$RUNTIME_DIR/pdftotext.tar.bz2" -C "$STAGE" ./share
echo "  -> $RUNTIME_DIR/pdftotext.tar.bz2"

echo "==> Packaging pdftotext binaries (wrapper + real ELF) ..."
WORK_BIN="$WORK_DIR/pdftotext.bin"
cp "$PDFTOTEXT_BIN" "$WORK_BIN"
strip "$WORK_BIN"
# Set RPATH so bundled liblcms2.so.2 and libopenjp2.so.7 are found at runtime
# when installed to ~/.local/bin/ (looks in ~/.local/lib64/).
patchelf --set-rpath '$ORIGIN/../lib64' "$WORK_BIN"
bzip2 -kf "$WORK_BIN"
cp "${WORK_BIN}.bz2" "$BIN_DIR/pdftotext.bin.bz2"
bzip2 -c "$REPO/build/pdftotext/pdftotext" > "$BIN_DIR/pdftotext.bz2"
echo "  -> $BIN_DIR/pdftotext.bz2 (wrapper)"
echo "  -> $BIN_DIR/pdftotext.bin.bz2"

echo "==> Verifying staged CJK extraction (predefined CMap, no ToUnicode) ..."
# A Type0 font using the predefined UniJIS-UCS2-H CMap with no embedded
# ToUnicode needs poppler-data for both CMap and CID->Unicode resolution;
# without it extraction is silent garbage. Build the layout an install
# produces, then require the reference text back.
mkdir -p "$STAGE/bin" "$STAGE/lib64"
install -m 755 "$REPO/build/pdftotext/pdftotext" "$STAGE/bin/pdftotext"
# Stage the PATCHELF'd binary and a lib64/ beside it, so this exercises the
# deployed resolution path ('$ORIGIN/../lib64') rather than whatever the build
# box happens to have in /usr/lib64. That matters most for freetype: EL8's
# 2.9.1 is OLDER than what this binary was linked against, and the env -i
# below strips LD_LIBRARY_PATH, so an unpatched copy would silently be tested
# against the wrong lib -- or pass here and die on a farm node.
cp "$WORK_BIN" "$STAGE/bin/pdftotext.bin"
for so in "$LIB_DIR"/libfreetype.so.6.bz2 "$LIB_DIR"/liblcms2.so.2.bz2 \
          "$LIB_DIR"/libopenjp2.so.7.bz2; do
    [ -f "$so" ] || continue
    bzip2 -dc "$so" > "$STAGE/lib64/$(basename "$so" .bz2)"
done
[ -f "$STAGE/lib64/libfreetype.so.6" ] || {
    echo "ERROR: no bundled libfreetype.so.6 in $LIB_DIR --" >&2
    echo "       run ./build/build-freetype.sh first" >&2
    exit 1
}
python3 "$REPO/build/pdftotext/make-cjk-smoke-pdf.py" "$WORK_DIR/cjk-smoke.pdf"
SMOKE_OUT=$(cd /tmp && env -i PATH=/usr/bin:/bin HOME="$WORK_DIR" \
    "$STAGE/bin/pdftotext" "$WORK_DIR/cjk-smoke.pdf" - 2>&1) || {
    echo "ERROR: staged CJK pdftotext run failed:" >&2
    printf '%s\n' "$SMOKE_OUT" >&2
    exit 1
}
case "$SMOKE_OUT" in
    *$(printf '\343\201\202\343\201\204')*) echo "  OK: CJK text extracted via bundled poppler-data" ;;
    *)
        echo "ERROR: CJK extraction did not produce the reference text:" >&2
        printf '%s\n' "$SMOKE_OUT" >&2
        exit 1
        ;;
esac

echo "==> Updating packages.json ..."
python3 -c "
import re, sys, json
path, ver = sys.argv[1], sys.argv[2]
with open(path) as f:
    data = json.load(f)
pkgs = data['packages']
if 'pdftotext' in pkgs:
    pkgs['pdftotext']['version'] = ver
    print(f'packages.json: pdftotext version -> {ver}')
else:
    print('WARNING: pdftotext not found in packages.json, skipping version update')
with open(path, 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
" "$REPO/payload/packages.json" "$VERSION"

echo "==> Running strip-all-elf-binaries ..."
"$REPO/build/strip-all-elf-binaries"

echo ""
echo "Done."
echo ""
echo "Produced:"
echo "  $BIN_DIR/pdftotext.bz2 (wrapper)"
echo "  $BIN_DIR/pdftotext.bin.bz2"
echo "  $RUNTIME_DIR/pdftotext.tar.bz2 (poppler-data ${DATA_VERSION})"
echo "  $LIB_DIR/liblcms2.so.2.bz2  (if bundled)"
echo "  $LIB_DIR/libopenjp2.so.7.bz2  (if bundled)"
echo ""
echo "Commit with:"
echo "  git add payload/el8.x86_64.glibc2p28/bin/pdftotext.bz2 \\"
echo "          payload/el8.x86_64.glibc2p28/bin/pdftotext.bin.bz2 \\"
echo "          payload/el8.x86_64.glibc2p28/runtime/pdftotext.tar.bz2 \\"
echo "          payload/el8.x86_64.glibc2p28/lib64/ build/pdftotext/ \\"
echo "          .strip-manifest payload/packages.json"
echo "  git commit -m 'feat(payload): pdftotext ${VERSION} EL8 source build (poppler, static)'"
