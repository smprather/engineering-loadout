#!/bin/sh
# Rebuild Xephyr from AlmaLinux 8's own source RPM (same upstream tarball +
# every Red Hat CVE backport already applied), with its SHA1 backend switched
# from OpenSSL to libgcrypt, so the bundled binary drops libcrypto.so.1.1
# entirely.
#
# Produces: payload/el8.x86_64.glibc2p28/bin/Xephyr.bin.bz2
#
# WHY THIS SCRIPT EXISTS. build/build-xephyr.sh shanghais the upstream EL8
# AppStream RPM binary verbatim -- fast, faithful, and exactly right for a
# binary with no upstream config problem. But that RPM's Xephyr links
# libcrypto.so.1.1 for one thing only: SHA1_Init/Update/Final, used to hash
# X11 auth cookies (xorg-server's classic --with-sha1=libcrypto). EL8 always
# has libcrypto.so.1.1 (openssl-libs-1.1.1), so this was invisible on the
# original build/target machine. It breaks on any target without OpenSSL 1.1
# -- Arch/CachyOS ships only OpenSSL 3, no 1.1 compat by default:
#   Xephyr.bin: error while loading shared libraries: libcrypto.so.1.1
#
# THE FIX: --with-sha1=libgcrypt instead of the default libcrypto
# autodetection. libgcrypt.so.20 is a GnuPG dependency present by default on
# EL8 AND Arch/CachyOS (and virtually everywhere -- package managers
# themselves depend on it for signature verification), unlike libcrypto.so.1.1
# which Arch does not ship at all. Verified: NEEDED no longer includes any
# libcrypto/libssl entry (confirmed via readelf -d), and a live smoke test
# actually starts the server and completes a real X11 protocol handshake
# (connection-setup reply byte 1 = Success) against a raw AF_UNIX socket, on
# a host with zero libcrypto.so.1.1 anywhere on the system.
#
# TWO BUGS DISCOVERED AND FIXED ALONG THE WAY (both load-bearing, neither
# related to the SHA1 switch -- they surface on ANY from-source build of this
# exact patch stack, RHEL's own included, but RHEL's mock/koji environment
# must inject the missing pieces some other way since the shipped RPM works):
#   1. 0001-link-with-z-now.patch's hw/kdrive/ephyr hunk has a genuine typo:
#      "-W,-z,now" instead of "-Wl,-z,now". Every OTHER hunk in that same
#      patch (hw/dmx, hw/xfree86, ...) gets it right; only the ephyr one is
#      wrong. Invalid gcc flag -> hard failure at link time. Fixed with sed
#      on hw/kdrive/ephyr/Makefile.am before autoreconf.
#   2. The RPM spec's %build exports CFLAGS via
#      "-specs=/usr/lib/rpm/redhat/redhat-hardened-cc1", which implicitly
#      injects -fPIC/-fPIE for every compile. A plain ./configure without
#      that specs file (or --with-pic, which only covers libtool-driven
#      objects, not this directly-compiled PROGRAM) does not get -fPIC, and
#      -pie linking then fails: "relocation R_X86_64_32 ... can not be used
#      when making a PIE object". Fixed by adding -fPIC to CFLAGS/CXXFLAGS
#      explicitly.
#   3. (Not a bug, a missing flag) --prefix defaults to /usr/local, which
#      bakes XKB_BIN_DIRECTORY="/usr/local/bin" into the binary -- xkbcomp
#      actually lives at /usr/bin on every real target, so keymap compilation
#      fails at runtime ("Keyboard initialization failed") even though the
#      binary itself is fine. Fixed with --prefix=/usr, matching what the RPM
#      spec's %configure macro sets for free.
#
# SCOPE: only hw/kdrive (kdrive core + Xephyr DDX) is configured/built --
# --disable-xvfb --disable-xnest --disable-xorg --disable-dmx
# --disable-xwayland -- not the full xorg-server the RPM spec builds (Xorg,
# Xvfb, Xnest, dmx). This repo only bundles Xephyr; building the rest would
# be pure waste. Functionally equivalent kdrive/ephyr output either way,
# since those DDXs don't share build products with kdrive.
#
# NEEDED closure after the fix (verified with readelf -d against the built
# binary): same 6 bundled libs build/build-xephyr.sh already documents
# (libXdmcp, libXfont2, libfontenc, libxcb-glx, libxcb-xf86dri, libxcb-xv),
# the same gui_libs/mesa3d_libs/EL8-base set it already assumes present, PLUS
# two libs that were not previously direct NEEDED entries of this binary:
#   libgcrypt.so.20  -- the new SHA1 backend. EL8-base AND Arch-base (GnuPG
#                       dependency everywhere). Not bundled -- assumed
#                       present, same tier as libselinux/libaudit/libsystemd.
#   libunwind.so.8   -- present on EL8 (libunwind-devel is already a
#                       BuildRequires) and on Arch/CachyOS by default. Not
#                       bundled -- assumed present.
# libcrypto.so.1.1 is gone from the NEEDED list entirely.
#
# Build-time deps (system, headers) -- the full xorg-x11-server.spec
# BuildRequires list minus what --disable-{xvfb,xnest,xorg,dmx,xwayland}
# makes moot:
#   dnf install -y dnf-plugins-core rpm-build \
#     make systemtap-sdt-devel git automake autoconf libtool pkgconfig \
#     xorg-x11-util-macros xorg-x11-proto-devel xorg-x11-font-utils \
#     dbus-devel libepoxy-devel systemd-devel xorg-x11-xtrans-devel \
#     libXfont2-devel libXau-devel libxkbfile-devel libXres-devel \
#     libfontenc-devel libXtst-devel libXdmcp-devel \
#     libX11-devel libXext-devel libXinerama-devel libXi-devel \
#     libXt-devel libdmx-devel libXmu-devel libXrender-devel \
#     libXpm-devel libXaw-devel libXfixes-devel libXv-devel pixman-devel \
#     libpciaccess-devel bison flex flex-devel \
#     mesa-libGL-devel mesa-libEGL-devel mesa-libgbm-devel \
#     libdrm-devel kernel-headers pam-devel \
#     audit-libs-devel libselinux-devel libudev-devel libunwind-devel \
#     libgcrypt-devel \
#     xcb-util-devel xcb-util-image-devel xcb-util-wm-devel \
#     xcb-util-keysyms-devel xcb-util-renderutil-devel libxshmfence-devel
#   dnf config-manager --set-enabled appstream-source baseos-source \
#     powertools-source ha-source resilientstorage-source   # for dnf download --source
#
# Usage (run from any directory, inside the AlmaLinux 8.10 build container --
# see build/build-shell):
#   /path/to/build-xephyr-openssl-free.sh --tag 1.20.11-28.el8_10.3

set -eu

REPO="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib.sh
. "$REPO/build/lib.sh"
RELEASES_URL="https://gitlab.freedesktop.org/xorg/xserver/-/tags"
EXPECTED_TAG="1.20.11-28.el8_10.3"

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
loadout_require_cmds dnf rpmbuild rpm2cpio sed autoreconf readelf strip

WORKROOT="/tmp/xephyr-openssl-free-${tag}"
rm -rf "$WORKROOT"
mkdir -p "$WORKROOT"
export HOME="$WORKROOT/home"
mkdir -p "$HOME"

echo "==> Fetching source RPM for xorg-x11-server-${tag} ..."
dnf config-manager --set-enabled appstream-source baseos-source powertools-source ha-source resilientstorage-source >/dev/null 2>&1 || true
cd "$WORKROOT"
dnf download --source xorg-x11-server-Xephyr >/tmp/xephyr-dl.log 2>&1
srpm=$(find "$WORKROOT" -maxdepth 1 -name "xorg-x11-server-*.src.rpm" | head -1)
[ -n "$srpm" ] || { echo "ERROR: no source RPM downloaded" >&2; cat /tmp/xephyr-dl.log >&2; exit 1; }
case "$(basename "$srpm")" in
    *"$tag"*) ;;
    *) echo "ERROR: downloaded $(basename "$srpm") does not match --tag $tag" >&2; exit 1 ;;
esac
rpm -i "$srpm"

echo "==> Applying every Red Hat patch (rpmbuild -bp) ..."
rpmbuild -bp --nodeps "$HOME/rpmbuild/SPECS/xorg-x11-server.spec" >/tmp/xephyr-prep.log 2>&1 \
    || { echo "ERROR: rpmbuild -bp failed" >&2; tail -40 /tmp/xephyr-prep.log >&2; exit 1; }

SRCDIR=$(find "$HOME/rpmbuild/BUILD" -maxdepth 1 -type d -name "xorg-server-*" | head -1)
[ -n "$SRCDIR" ] || { echo "ERROR: no prepped source tree found" >&2; exit 1; }
cd "$SRCDIR"

echo "==> Fixing the -W,-z,now typo in 0001-link-with-z-now.patch's ephyr hunk ..."
grep -q '\-W,-z,now' hw/kdrive/ephyr/Makefile.am || {
    echo "ERROR: expected typo not found -- upstream/RH may have fixed it; drop this sed" >&2
    exit 1
}
sed -i 's/-W,-z,now/-Wl,-z,now/' hw/kdrive/ephyr/Makefile.am

echo "==> autoreconf ..."
autoreconf -f -v --install >/tmp/xephyr-autoreconf.log 2>&1

echo "==> configure (kdrive/Xephyr only, --with-sha1=libgcrypt) ..."
export CFLAGS="-O2 -fstack-protector-strong -fPIC"
export CXXFLAGS="-O2 -fstack-protector-strong -fPIC"
./configure \
    --prefix=/usr \
    --enable-kdrive --enable-xephyr --disable-xfake --disable-xfbdev \
    --disable-xvfb --disable-xnest --disable-xorg --disable-dmx --disable-xwayland \
    --enable-dependency-tracking --disable-static --with-pic \
    --with-int10=x86emu \
    --with-default-font-path="catalogue:/etc/X11/fontpath.d,built-ins" \
    --with-module-dir=/usr/lib64/xorg/modules \
    --with-xkb-output=/var/lib/xkb \
    --without-dtrace \
    --disable-linux-acpi --disable-linux-apm \
    --enable-xselinux --enable-record --enable-present \
    --enable-xcsecurity \
    --enable-config-udev \
    --disable-unit-tests \
    --enable-dri --enable-dri2 --enable-dri3 --enable-suid-wrapper --enable-glamor \
    --with-sha1=libgcrypt \
    >/tmp/xephyr-configure.log 2>&1 \
    || { echo "ERROR: configure failed" >&2; tail -60 /tmp/xephyr-configure.log >&2; exit 1; }

grep -q 'SHA1 implementation... libgcrypt' /tmp/xephyr-configure.log \
    || grep -q 'for SHA1 implementation.*libgcrypt' /tmp/xephyr-configure.log \
    || { echo "ERROR: configure did not select libgcrypt for SHA1" >&2; exit 1; }

echo "==> make (kdrive/ephyr; -j8 to avoid resource pressure) ..."
make -j8 >/tmp/xephyr-make.log 2>&1 \
    || { echo "ERROR: make failed" >&2; tail -60 /tmp/xephyr-make.log >&2; exit 1; }

BUILT="$SRCDIR/hw/kdrive/ephyr/Xephyr"
[ -f "$BUILT" ] || { echo "ERROR: $BUILT not produced" >&2; exit 1; }

echo "==> Checking NEEDED (no libcrypto/libssl) ..."
NEEDED=$(readelf -d "$BUILT" | sed -n 's/.*NEEDED.*\[\(.*\)\]/\1/p')
case "$NEEDED" in
    *libcrypto*|*libssl*)
        echo "ERROR: rebuilt Xephyr still links OpenSSL:" >&2
        echo "$NEEDED" >&2
        exit 1
        ;;
esac
echo "$NEEDED" | grep -q libgcrypt || { echo "ERROR: expected libgcrypt.so NEEDED, not found" >&2; exit 1; }
echo "  OK -- no libcrypto/libssl; libgcrypt present for SHA1"

loadout_report_max_glibc "$BUILT"
loadout_package_bin "$BUILT" Xephyr.bin

echo ""
echo "Next:"
echo "  $REPO/build/verify-binaries xephyr"
echo "  ./build/strip-all-elf-binaries"
echo "  python3.14 build/gen-content-manifest"
echo "  python3.14 build/gen-installed-sizes"
echo "  git add $REPO/payload/el8.x86_64.glibc2p28/bin/Xephyr.bin.bz2 \\"
echo "          .strip-manifest .content-manifest payload/installed-sizes.json \\"
echo "          $REPO/build/build-xephyr-openssl-free.sh"
echo "  git commit -m 'fix(xephyr): rebuild from source with libgcrypt SHA1, drop OpenSSL 1.1'"
