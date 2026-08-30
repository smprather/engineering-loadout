#!/bin/sh
# Rebuild libQt5Network.so.5 from AlmaLinux 8's own qt5-qtbase source RPM
# (same upstream 5.15.3 tarball + every Red Hat CVE backport already
# applied), linked against OpenSSL 3 instead of OpenSSL 1.1.
#
# Produces:
#   payload/el8.x86_64.glibc2p28/lib64/libQt5Network.so.5.bz2
#   payload/el8.x86_64.glibc2p28/lib64/libssl.so.3.bz2   (if not already bundled)
#   payload/el8.x86_64.glibc2p28/lib64/libcrypto.so.3.bz2 (if not already bundled)
#
# WHY THIS SCRIPT EXISTS. gui_libs (Qt5, GTK3, and friends) is shanghai'd
# whole from EL8 AppStream RPMs -- see build/ADDING_BINARIES.md's "gui_libs
# bundle notes". EL8's qt5-qtbase spec builds with `-openssl-linked` against
# system OpenSSL 1.1 (`%global openssl -openssl-linked`, line 5 of
# qt5-qtbase.spec), which is a REAL, live TLS backend for QSslSocket /
# QNetworkAccessManager -- not a narrow single-function usage like Xephyr's
# SHA1 cookie hashing (see build-xephyr-openssl-free.sh). EL8 always has
# libssl.so.1.1/libcrypto.so.1.1 (openssl-libs-1.1.1); Arch/CachyOS never
# does, so every Qt5-based tool that touches the network (flameshot's imgur
# upload, and any other gui_libs consumer that opens an HTTPS connection)
# fails to load at all on such targets.
#
# THE FIX: rebuild ONLY libQt5Network.so.5 (not the whole qtbase RPM output)
# from the exact same source+patches, linked against OpenSSL 3.5.5 --
# `openssl3-devel`/`openssl3-libs` from EPEL, a currently-maintained release
# (OpenSSL 1.1 has been EOL and unpatched since 2023-09). libssl.so.3 /
# libcrypto.so.3 are bundled alongside it (NEEDED closure: libz.so.1
# [already bundled], libdl/libpthread/libc [glibc, never bundled] -- nothing
# else). All the OTHER gui_libs Qt5 libs (QtCore, QtGui, QtWidgets, QtDBus,
# QtSvg, ...) are left exactly as the RPM shipped them; only QtNetwork is
# rebuilt. This is safe because Qt 5.15.x is one LTS branch that maintains
# strict binary compatibility for its entire life -- a QtNetwork built from
# the identical version+patch level links and runs against the untouched
# QtCore already in lib64/ with no ABI concerns.
#
# openssl3's headers/libs are NAMESPACED to coexist with the system's
# default 1.1 install (headers under /usr/include/openssl3/, libs under
# /usr/lib64/openssl3/ with dev symlinks, runtime .so.3 files directly in
# /usr/lib64/). Qt's configure looks for a pkg-config module literally named
# "openssl" for MOST pkgConfig-type feature checks (journald, dbus, xcb, ...)
# -- but NOT for OpenSSL itself. Its own config test is a hardcoded "type
# openssl" probe (config.tests/openssl) that does a bare `g++ -o openssl
# main.o -lssl -lcrypto` with no pkg-config involved at all, so a
# PKG_CONFIG_PATH shim is silently ignored for this one library -- confirmed
# by watching the actual compile line in the configure log; it never
# consulted pkg-config for openssl. The real override point, printed by
# configure's own hint text, is the OPENSSL_LIBS environment variable
# (`OPENSSL_LIBS='-L/opt/ssl/lib -lssl -lcrypto' ./configure -openssl-linked`)
# for the link step, plus CPATH for the compiler's header search (openssl3's
# headers live under the non-default /usr/include/openssl3/, so plain
# -I/usr/include still finds the system 1.1 headers first without this).
# Both are exported before configure runs, below.
#
# WHY THE FULL QTBASE BUILDS FIRST. Qt5's build needs its own freshly-built
# host tools (moc, in particular) before ANY module -- including
# corelib -- will compile; there is no shortcut that skips straight to
# `make -C src/network`. This script therefore runs the RPM's own full
# top-level `make` (same as build/ADDING_BINARIES.md's gui_libs notes
# describe), then extracts ONLY lib/libQt5Network.so.5.15.3 from the result.
# Building the whole tree costs real wall-clock time (tens of minutes even
# on many cores) but no extra engineering risk -- it is exactly what the RPM
# itself does, verified byte-for-byte identical wherever it does not touch
# OpenSSL.
#
# Build-time deps (system, headers) -- the qt5-qtbase.spec BuildRequires,
# plus openssl3-devel from EPEL:
#   dnf install -y dnf-plugins-core rpm-build openssl3-devel \
#     automake autoconf libtool pkgconfig bison flex gperf git \
#     libxcb-devel xcb-util-devel xcb-util-image-devel xcb-util-wm-devel \
#     xcb-util-keysyms-devel xcb-util-renderutil-devel \
#     libX11-devel libXext-devel libXrender-devel libSM-devel libICE-devel \
#     fontconfig-devel freetype-devel glib2-devel dbus-devel cups-devel \
#     libxkbcommon-devel libxkbcommon-x11-devel mesa-libGL-devel \
#     mesa-libEGL-devel sqlite-devel pcre2-devel gtk3-devel harfbuzz-devel \
#     krb5-devel cyrus-sasl-devel libdrm-devel libudev-devel libpng-devel \
#     libjpeg-turbo-devel icu-devel
#   dnf config-manager --set-enabled appstream-source baseos-source \
#     powertools-source ha-source resilientstorage-source   # for dnf download --source
#
# Usage (run from any directory, inside the AlmaLinux 8.10 build container --
# see build/build-shell):
#   /path/to/build-qt5network-openssl3.sh --tag 5.15.3-8.el8_10

set -eu

REPO="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib.sh
. "$REPO/build/lib.sh"
RELEASES_URL="https://download.qt.io/official_releases/qt/5.15/5.15.3/"
EXPECTED_TAG="5.15.3-8.el8_10"
LIB_DIR="$REPO/payload/$LOADOUT_PLATFORM/lib64"

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

loadout_require_tag "$tag" "$0" "$RELEASES_URL" "$EXPECTED_TAG"
loadout_require_cmds dnf rpmbuild pkg-config readelf strip bzip2

WORKROOT="/tmp/qt5network-openssl3-${tag}"
rm -rf "$WORKROOT"
mkdir -p "$WORKROOT"
export HOME="$WORKROOT/home"
mkdir -p "$HOME"

echo "==> Fetching qt5-qtbase source RPM ..."
dnf config-manager --set-enabled appstream-source baseos-source powertools-source ha-source resilientstorage-source >/dev/null 2>&1 || true
cd "$WORKROOT"
dnf download --source qt5-qtbase >/tmp/qt5-dl.log 2>&1
srpm=$(find "$WORKROOT" -maxdepth 1 -name "qt5-qtbase-*.src.rpm" | head -1)
[ -n "$srpm" ] || { echo "ERROR: no source RPM downloaded" >&2; cat /tmp/qt5-dl.log >&2; exit 1; }
rpm -i "$srpm"

echo "==> Applying every Red Hat patch (rpmbuild -bp) ..."
rpmbuild -bp --nodeps "$HOME/rpmbuild/SPECS/qt5-qtbase.spec" >/tmp/qt5-prep.log 2>&1 \
    || { echo "ERROR: rpmbuild -bp failed" >&2; tail -40 /tmp/qt5-prep.log >&2; exit 1; }

SRCDIR=$(find "$HOME/rpmbuild/BUILD" -maxdepth 1 -type d -name "qtbase-everywhere-src-*" | head -1)
[ -n "$SRCDIR" ] || { echo "ERROR: no prepped source tree found" >&2; exit 1; }
cd "$SRCDIR"

echo "==> Pointing OpenSSL detection at openssl3 (OPENSSL_LIBS + CPATH) ..."
[ -f /usr/lib64/openssl3/libssl.so ] || {
    echo "ERROR: openssl3-devel not installed (see script header)" >&2
    exit 1
}

echo "==> configure (full qtbase; only libQt5Network.so.5 gets bundled) ..."
export RPM_OPT_FLAGS="-O2 -g -fstack-protector-strong -fPIC"
export CFLAGS="$RPM_OPT_FLAGS"
export CXXFLAGS="$RPM_OPT_FLAGS"
export OPENSSL_LIBS="-L/usr/lib64/openssl3 -lssl -lcrypto"
export CPATH="/usr/include/openssl3"
./configure \
    -verbose -confirm-license -opensource \
    -prefix /usr -archdatadir /usr/lib64/qt5 -bindir /usr/lib64/qt5/bin \
    -libdir /usr/lib64 -libexecdir /usr/lib64/qt5/libexec \
    -datadir /usr/share/qt5 -docdir /usr/share/doc/qt5 \
    -examplesdir /usr/share/doc/qt5/examples -headerdir /usr/include/qt5 \
    -importdir /usr/lib64/qt5/imports -plugindir /usr/lib64/qt5/plugins \
    -sysconfdir /etc/xdg -translationdir /usr/share/qt5/translations \
    -platform linux-g++ \
    -release -shared -accessibility -dbus-linked -egl -eglfs \
    -fontconfig -glib -gtk -no-sql-ibase -no-sql-tds -icu -optimized-qmake \
    -openssl-linked \
    -nomake examples -nomake tests \
    -no-pch -no-reduce-relocations -no-rpath -no-separate-debug-info -no-strip \
    -system-libjpeg -system-libpng -system-harfbuzz -system-pcre \
    -system-sqlite -system-zlib -no-use-gold-linker -no-directfb \
    -no-feature-relocatable -no-feature-renameat2 -no-feature-statx \
    -no-feature-getentropy \
    QMAKE_CFLAGS_RELEASE="$CFLAGS" QMAKE_CXXFLAGS_RELEASE="$CXXFLAGS" \
    QMAKE_LFLAGS_RELEASE="" \
    >/tmp/qt5-configure.log 2>&1 \
    || { echo "ERROR: configure failed" >&2; tail -60 /tmp/qt5-configure.log >&2; exit 1; }
grep -q "succeeded" /tmp/qt5-configure.log && grep -B1 "config.qtbase_network.libraries.openssl" /tmp/qt5-configure.log | head -2

echo "==> make (full qtbase -- moc/host tools have no shortcut) ..."
make -j"$(nproc 2>/dev/null || echo 8)" >/tmp/qt5-make.log 2>&1 \
    || { echo "ERROR: make failed" >&2; tail -80 /tmp/qt5-make.log >&2; exit 1; }

BUILT=$(find "$SRCDIR/lib" -maxdepth 1 -name "libQt5Network.so.5.*.*" -type f | head -1)
[ -n "$BUILT" ] || { echo "ERROR: libQt5Network.so.5.* not produced" >&2; exit 1; }

echo "==> Checking NEEDED (openssl 3, not 1.1) ..."
NEEDED=$(readelf -d "$BUILT" | sed -n 's/.*NEEDED.*\[\(.*\)\]/\1/p')
case "$NEEDED" in
    *libssl.so.1.1*|*libcrypto.so.1.1*)
        echo "ERROR: still linked against OpenSSL 1.1:" >&2
        echo "$NEEDED" >&2
        exit 1
        ;;
esac
echo "$NEEDED" | grep -q 'libssl.so.3' || { echo "ERROR: expected libssl.so.3 NEEDED, not found" >&2; exit 1; }
echo "  OK -- linked against libssl.so.3 / libcrypto.so.3"
echo "$NEEDED" | sed 's/^/  /'

loadout_report_max_glibc "$BUILT"

echo "==> Staging libQt5Network.so.5 ..."
WORK_SO="$WORKROOT/libQt5Network.so.5"
cp "$BUILT" "$WORK_SO"
strip "$WORK_SO"
# gui_libs libs use RPATH $ORIGIN (flat lib64/), not $ORIGIN/../lib64 -- see
# "gui_libs bundle notes" in ADDING_BINARIES.md.
"$LOADOUT_PATCHELF" --set-rpath '$ORIGIN' "$WORK_SO"
bzip2 -kf "$WORK_SO"
mkdir -p "$LIB_DIR"
cp "${WORK_SO}.bz2" "$LIB_DIR/libQt5Network.so.5.bz2"
chmod 644 "$LIB_DIR/libQt5Network.so.5.bz2"

echo "==> Staging libssl.so.3 / libcrypto.so.3 (if not already bundled) ..."
for pair in "libssl.so.3:/usr/lib64/openssl3/libssl.so" "libcrypto.so.3:/usr/lib64/openssl3/libcrypto.so"; do
    name=${pair%%:*}
    src=${pair##*:}
    dest="$LIB_DIR/${name}.bz2"
    if [ -f "$dest" ]; then
        echo "  $name already bundled, leaving as-is"
        continue
    fi
    real=$(readlink -f "$src")
    tmp="$WORKROOT/$name"
    cp "$real" "$tmp"
    strip "$tmp"
    bzip2 -f "$tmp"
    cp "${tmp}.bz2" "$dest"
    chmod 644 "$dest"
    echo "  staged $name"
done

echo ""
echo "Staged: payload/$LOADOUT_PLATFORM/lib64/libQt5Network.so.5.bz2"
echo ""
echo "Next:"
echo "  $REPO/build/verify-binaries flameshot"
echo "  ./build/strip-all-elf-binaries"
echo "  python3.14 build/gen-content-manifest"
echo "  python3.14 build/gen-installed-sizes"
echo "  Add libssl.so.3 / libcrypto.so.3 to gui_libs's \"libs\" array in"
echo "  payload/packages.json if this is their first bundling."
echo "  git add $LIB_DIR/libQt5Network.so.5.bz2 $LIB_DIR/libssl.so.3.bz2 \\"
echo "          $LIB_DIR/libcrypto.so.3.bz2 .strip-manifest .content-manifest \\"
echo "          payload/installed-sizes.json payload/packages.json \\"
echo "          $REPO/build/build-qt5network-openssl3.sh"
echo "  git commit -m 'fix(qt5): rebuild libQt5Network against OpenSSL 3, drop OpenSSL 1.1'"
