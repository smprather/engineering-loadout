#!/bin/sh
# Shanghai-bundle Xephyr (nested X server) from the EL8 AppStream RPM for
# el8.x86_64.glibc2p28.
#
# Why Xephyr: on a locked-down host the desktop environment is picked by the
# display manager or by the remote-desktop server's root-owned config
# (NoMachine's /usr/NX/etc/node.cfg, GDM's session list). A nested X server
# needs none of that -- it is an ordinary window inside the session the user
# already has, so any WM or desktop they can execute runs inside it with no
# root, no config change, and (unlike Xvnc) no listening TCP port.
#
# Build process:
#
#   1. dnf download every consumed RPM into a temp dir (no root, no system
#      install), so the bundled bits are pinned to --tag rather than to
#      whatever happens to be installed on the build box. This covers BOTH
#      the Xephyr RPM and the six support-lib RPMs -- copying support libs
#      straight from /usr/lib64 would re-introduce the build-box-masking
#      class of bug the NEEDED-closure guard below was written to catch.
#   2. rpm2cpio | cpio each tree out. Take usr/bin/Xephyr; take each
#      usr/lib64/<soname> from its providing RPM (resolving symlinks *within
#      the extracted tree*, never against the host root -- readlink -f on an
#      absolute symlink would silently fall back to /usr/lib64 and ship the
#      build-box copy again).
#   3. strip -> patchelf RPATH '$ORIGIN/../lib64' -> bzip2, per the repo ELF
#      rule, and ship it as Xephyr.bin behind a POSIX-sh wrapper.
#   4. Bundle the six NEEDED sonames that no existing loadout package owns.
#
# Library split (verified with objdump -p against payload/packages.json):
#   - gui_libs owns libX11, libX11-xcb, libXau, libdbus-1, libepoxy,
#     libpixman-1 and 9 of the libxcb-* extensions -> declared as a depends.
#   - mesa3d_libs owns libdrm.so.2 and libxshmfence.so.1 at the same lib64/
#     path we would install to -> declared as a depends rather than
#     duplicated, which also gives Xephyr a real Mesa vendor side for GLX.
#   - EL8 base is assumed for libsystemd, libudev, libaudit, libcap-ng,
#     libselinux, libcrypto, libgcrypt and friends: all base RPMs, present on
#     every supported node.
#   - libGL.so.1 / libGLX.so.0 / libGLdispatch.so.0 stay HOST-provided. Never
#     bundle the GLVND dispatcher -- see AGENTS.md, "Never bundle these libs".
#   - BUNDLED here: libXdmcp, libXfont2, libfontenc, libxcb-glx,
#     libxcb-xf86dri, libxcb-xv.
#
# Still assumed present on the target (NOT bundled):
#   - /usr/share/X11/xkb  (xkeyboard-config) and /usr/bin/xkbcomp: the server
#     compiles its keymap through these at startup. Present on any host with
#     an X server or GUI stack installed; without them Xephyr falls back to a
#     pre-XKB keymap instead of failing.
#   - a GLVND libGL, as above.
#
# --tag is the FULL version-release, e.g. 1.20.11-28.el8_10.3. The release
# field is where Red Hat's CVE backports live; pinning only the upstream
# version (1.20.11) would hide which security fixes shipped. The guard below
# matches the downloaded RPM NVR exactly, and payload/packages.json must
# record the same full NVR as the xephyr entry's "version" field. On success
# the script writes build/xephyr/PROVENANCE recording every source RPM NVR
# it actually consumed.
#
# Usage (run from any directory):
#   ./build/build-xephyr.sh --tag 1.20.11-28.el8_10.3
#   ./build/build-xephyr.sh --tag 1.20.11-28.el8_10.3 --rpm /path/to/Xephyr.rpm
#   ./build/build-xephyr.sh --tag 1.20.11-28.el8_10.3 --rpm-dir /path/to/all-rpms
#
# --rpm <file>      Xephyr RPM only (lib RPMs still fetched via dnf).
# --rpm-dir <dir>   Directory already containing every RPM this script needs
#                   (the Xephyr RPM + the four lib provider RPMs, x86_64).
#                   Use this on a build box with no dnf; filenames must be
#                   <pkg>-<nvr>.x86_64.rpm so 32-bit (.i686) RPMs are ignored.
#
# Then, as for every payload change:
#   ./build/strip-all-elf-binaries
#   ./loadout completion bash > envs/bash/global/completions/loadout.bash

set -eu

REPO="$(cd "$(dirname "$0")/.." && pwd)"
PLATFORM=el8.x86_64.glibc2p28
ARCH=x86_64
BIN_DIR="$REPO/payload/$PLATFORM/bin"
LIB_DIR="$REPO/payload/$PLATFORM/lib64"
WRAP_DIR="$REPO/build/xephyr"
RPM_NAME=xorg-x11-server-Xephyr
TAG=""
RPM_FILE=""
RPM_DIR=""

# Sonames no other loadout package owns. Keep in sync with the "libs" array of
# the xephyr entry in payload/packages.json.
BUNDLE_LIBS="libXdmcp.so.6 libXfont2.so.2 libfontenc.so.1 libxcb-glx.so.0 libxcb-xf86dri.so.0 libxcb-xv.so.0"

# Distinct EL8 RPM packages that provide the bundled sonames. Used to download
# (or locate in --rpm-dir) the provider RPMs so the libs are pinned to the RPM
# rather than copied from /usr/lib64 on the build box.
LIB_PKGS="libXdmcp libXfont2 libfontenc libxcb"

# soname -> providing package. Each bundled soname must map to exactly one of
# LIB_PKGS so the extraction loop knows which RPM tree to pull it from.
lib_pkg_for() {
    case "$1" in
        libXdmcp.so.6)        echo libXdmcp ;;
        libXfont2.so.2)       echo libXfont2 ;;
        libfontenc.so.1)      echo libfontenc ;;
        libxcb-glx.so.0|libxcb-xf86dri.so.0|libxcb-xv.so.0) echo libxcb ;;
        *) return 1 ;;
    esac
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --tag)
            shift
            [ "$#" -gt 0 ] || { echo "missing value for --tag" >&2; exit 2; }
            TAG="$1"
            ;;
        --rpm)
            shift
            [ "$#" -gt 0 ] || { echo "missing value for --rpm" >&2; exit 2; }
            RPM_FILE="$1"
            ;;
        --rpm-dir)
            shift
            [ "$#" -gt 0 ] || { echo "missing value for --rpm-dir" >&2; exit 2; }
            RPM_DIR="$1"
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
    echo "ERROR: --tag is required. Specify the full version-release, e.g.:" >&2
    echo "  $0 --tag 1.20.11-28.el8_10.3" >&2
    echo "" >&2
    echo "The release field (-28.el8_10.3) is where Red Hat's CVE backports" >&2
    echo "live; pinning only the upstream version would hide which security" >&2
    echo "fixes shipped." >&2
    echo "" >&2
    echo "See what is available with:" >&2
    echo "  dnf list --available $RPM_NAME" >&2
    exit 1
fi

# --tag must carry a release field (must contain a '-'). Without it the NVR
# exact-match guard below cannot work and the shipped X server is not
# reproducible. Fail here, before any download, so the run is side-effect free.
case "$TAG" in
    *-*) ;;
    *)
        echo "ERROR: --tag must be the full version-release, not just the" >&2
        echo "upstream version. You passed '$TAG'." >&2
        echo "" >&2
        echo "The release field (the part after the first '-') is where Red" >&2
        echo "Hat's CVE backports live and must be pinned, e.g." >&2
        echo "  --tag 1.20.11-28.el8_10.3" >&2
        echo "" >&2
        echo "Discover the available release with:" >&2
        echo "  dnf list --available $RPM_NAME" >&2
        exit 1
        ;;
esac

need() {
    command -v "$1" >/dev/null 2>&1 || {
        printf 'missing required command: %s\n' "$1" >&2
        exit 1
    }
}

need rpm2cpio
need cpio
need bzip2
need objdump

PATCHELF="$HOME/.local/bin/patchelf"
[ -x "$PATCHELF" ] || PATCHELF="$(command -v patchelf || true)"
[ -n "$PATCHELF" ] || { echo "ERROR: patchelf not found" >&2; exit 1; }

STRIP=/usr/bin/strip
[ -x "$STRIP" ] || { echo "ERROR: $STRIP not found" >&2; exit 1; }

STAGE=$(mktemp -d "${TMPDIR:-/tmp}/xephyr-stage-XXXXXX")
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/bin" "$STAGE/lib64" "$STAGE/rpm" "$STAGE/rpm-libs"

# --- acquire the Xephyr RPM -------------------------------------------------
if [ -n "$RPM_FILE" ]; then
    [ -f "$RPM_FILE" ] || { echo "ERROR: --rpm $RPM_FILE not found" >&2; exit 1; }
    cp "$RPM_FILE" "$STAGE/rpm/"
elif [ -n "$RPM_DIR" ]; then
    [ -d "$RPM_DIR" ] || { echo "ERROR: --rpm-dir $RPM_DIR not a directory" >&2; exit 1; }
    found=$(ls "$RPM_DIR"/${RPM_NAME}-*.${ARCH}.rpm 2>/dev/null | head -1)
    [ -n "$found" ] || {
        echo "ERROR: no $RPM_NAME *.${ARCH}.rpm in --rpm-dir $RPM_DIR" >&2
        exit 1
    }
    cp "$found" "$STAGE/rpm/"
else
    need dnf
    # Ask for the exact NVR, not the bare name: `dnf download xorg-x11-...`
    # fetches whatever is newest, so a build would start failing the guard
    # below the moment the repo moves, instead of reproducing --tag.
    echo "==> Downloading $RPM_NAME-$TAG ..."
    ( cd "$STAGE/rpm" && dnf download "$RPM_NAME-$TAG" >/dev/null 2>&1 ) || {
        echo "ERROR: dnf download $RPM_NAME-$TAG failed (no such build in the repos?)." >&2
        echo "  Offline build box? Fetch the RPM elsewhere and pass" >&2
        echo "  --rpm <file> or --rpm-dir <dir>." >&2
        exit 1
    }
fi

RPM_PATH=$(ls "$STAGE"/rpm/*.rpm 2>/dev/null | head -1)
[ -n "$RPM_PATH" ] || { echo "ERROR: no RPM in $STAGE/rpm" >&2; exit 1; }
RPM_NVR=$(basename "$RPM_PATH" .rpm)

# Exact NVR match. The downloaded filename is <name>-<version-release>.<arch>
# so RPM_NVR must equal $RPM_NAME-$TAG.$ARCH exactly. A prefix match would
# accept any release and hide which CVE backports shipped.
EXPECTED_NVR="$RPM_NAME-$TAG.$ARCH"
if [ "$RPM_NVR" = "$EXPECTED_NVR" ]; then
    echo "==> Confirmed RPM: $RPM_NVR"
else
    echo "ERROR: --tag $TAG does not exactly match downloaded package." >&2
    echo "  expected NVR: $EXPECTED_NVR" >&2
    echo "  got NVR:      $RPM_NVR" >&2
    echo "  --tag must be the full version-release. See: dnf list --available $RPM_NAME" >&2
    exit 1
fi

# --- guard: packages.json must record the same full NVR ---------------------
# Read-only check (this script never writes packages.json). We extract the
# "version" value from the xephyr block only, so a different package's
# version line cannot match. Scoping: enter the block on the top-level key
# `    "xephyr": {` (4-space indent) and leave at the first line that is
# `    }` at that same indent. The first "version": "..." line inside that
# span is the xephyr version. No JSON parser dependency (POSIX sh + awk).
PKG_JSON="$REPO/payload/packages.json"
[ -f "$PKG_JSON" ] || { echo "ERROR: $PKG_JSON not found" >&2; exit 1; }
xephyr_version=$(awk '
    /^    "xephyr": \{/ { in_block=1; next }
    in_block && /^    \}/ { in_block=0; next }
    in_block && /"version":/ {
        line = $0
        sub(/^.*"version":[[:space:]]*"/, "", line)
        sub(/".*$/, "", line)
        print line
        exit
    }
' "$PKG_JSON")
if [ -z "$xephyr_version" ]; then
    echo "ERROR: could not locate the xephyr \"version\" field in $PKG_JSON." >&2
    echo "  Check that the xephyr entry exists and has a \"version\" key." >&2
    exit 1
fi
if [ "$xephyr_version" != "$TAG" ]; then
    echo "ERROR: payload/packages.json xephyr version mismatch." >&2
    echo "  --tag:                           $TAG" >&2
    echo "  packages.json xephyr.version:    $xephyr_version" >&2
    echo "  They must be identical (full version-release). Update packages.json" >&2
    echo "  to match --tag; this script does not write it." >&2
    exit 1
fi

# --- acquire the lib provider RPMs -----------------------------------------
# Download (or copy from --rpm-dir) the four provider RPMs, x86_64 only. A
# plain `dnf download libfontenc` on EL8 pulls BOTH the .i686 and .x86_64
# builds; --arch x86_64 avoids dragging the 32-bit one down, and the glob
# *.${ARCH}.rpm below ignores any .i686.rpm that slipped through anyway.
CONSUMED_LIB_NVRS=""
if [ -n "$RPM_DIR" ]; then
    [ -d "$RPM_DIR" ] || { echo "ERROR: --rpm-dir $RPM_DIR not a directory" >&2; exit 1; }
    for pkg in $LIB_PKGS; do
        found=$(ls "$RPM_DIR"/${pkg}-*.${ARCH}.rpm 2>/dev/null | head -1)
        [ -n "$found" ] || {
            echo "ERROR: no $pkg *.${ARCH}.rpm in --rpm-dir $RPM_DIR" >&2
            exit 1
        }
        cp "$found" "$STAGE/rpm-libs/"
    done
else
    need dnf
    echo "==> Downloading support-lib RPMs: $LIB_PKGS ..."
    ( cd "$STAGE/rpm-libs" && dnf download --arch "$ARCH" $LIB_PKGS >/dev/null 2>&1 ) || {
        echo "ERROR: dnf download of support-lib RPMs failed." >&2
        echo "  Offline build box? Fetch the provider RPMs and pass --rpm-dir <dir>." >&2
        exit 1
    }
fi

# Verify each provider RPM is present (x86_64 only) and record its NVR.
for pkg in $LIB_PKGS; do
    p=$(ls "$STAGE"/rpm-libs/${pkg}-*.${ARCH}.rpm 2>/dev/null | head -1)
    [ -n "$p" ] || {
        echo "ERROR: $pkg ${ARCH} RPM missing from $STAGE/rpm-libs" >&2
        echo "  If you used dnf, the package may not be available; fetch it" >&2
        echo "  and pass --rpm-dir <dir>." >&2
        exit 1
    }
    CONSUMED_LIB_NVRS="$CONSUMED_LIB_NVRS $(basename "$p" .rpm)"
done

# --- extract Xephyr ---------------------------------------------------------
echo "==> Extracting $RPM_NVR ..."
( cd "$STAGE" && rpm2cpio "$RPM_PATH" | cpio -idm --quiet )

SRC_BIN="$STAGE/usr/bin/Xephyr"
[ -f "$SRC_BIN" ] || { echo "ERROR: usr/bin/Xephyr not in $RPM_NVR" >&2; exit 1; }

cp "$SRC_BIN" "$STAGE/bin/Xephyr.bin"
chmod 755 "$STAGE/bin/Xephyr.bin"
"$STRIP" "$STAGE/bin/Xephyr.bin" 2>/dev/null || true
"$PATCHELF" --set-rpath '$ORIGIN/../lib64' "$STAGE/bin/Xephyr.bin"

# --- wrappers ---------------------------------------------------------------
for w in Xephyr xdesk; do
    [ -f "$WRAP_DIR/$w" ] || { echo "ERROR: missing wrapper $WRAP_DIR/$w" >&2; exit 1; }
    cp "$WRAP_DIR/$w" "$STAGE/bin/$w"
    chmod 755 "$STAGE/bin/$w"
done

# --- bundled libs (from the provider RPMs, never from /usr/lib64) ----------
echo "==> Bundling support libs from RPMs ..."
for soname in $BUNDLE_LIBS; do
    pkg=$(lib_pkg_for "$soname") || {
        echo "ERROR: no provider mapping for $soname" >&2
        exit 1
    }
    rpm_path=$(ls "$STAGE"/rpm-libs/${pkg}-*.${ARCH}.rpm 2>/dev/null | head -1)
    [ -n "$rpm_path" ] || { echo "ERROR: $pkg ${ARCH} RPM missing" >&2; exit 1; }

    # Extract this provider RPM into its own tree so overlapping paths from
    # different RPMs cannot clobber. Extract each package at most once:
    # libxcb provides three of the six sonames, and re-running cpio over an
    # existing tree emits a screenful of "not created: newer or same age
    # version exists" warnings that look like a build failure.
    ext="$STAGE/extract-$pkg"
    if [ ! -d "$ext" ]; then
        mkdir -p "$ext"
        ( cd "$ext" && rpm2cpio "$rpm_path" | cpio -idm --quiet )
    fi

    link="$ext/usr/lib64/$soname"
    [ -e "$link" ] || [ -L "$link" ] || {
        echo "ERROR: $soname not found in $pkg RPM ($(basename "$rpm_path"))" >&2
        echo "  Expected it at usr/lib64/$soname inside the RPM tree." >&2
        exit 1
    }

    # Resolve the soname to a regular file *within the extracted tree*. We
    # must not use `readlink -f` here: on an absolute symlink (e.g. the RPM
    # points /usr/lib64/libXdmcp.so.6 -> /usr/lib64/libXdmcp.so.6.0.0) a bare
    # readlink -f would resolve against the HOST root, silently falling back
    # to /usr/lib64 and reintroducing the build-box-masking bug. Map any
    # absolute target back into the extracted tree root ($ext) instead.
    src="$link"
    while [ -L "$src" ]; do
        target=$(readlink "$src")
        case "$target" in
            /*) src="$ext$target" ;;
            *)  src="$(dirname "$src")/$target" ;;
        esac
    done
    [ -f "$src" ] || {
        echo "ERROR: $soname resolved to '$src' which is not a regular file" >&2
        echo "  in the $pkg RPM tree." >&2
        exit 1
    }

    dst="$STAGE/lib64/$soname"
    cp "$src" "$dst"
    chmod 755 "$dst"
    "$STRIP" "$dst" 2>/dev/null || true
    "$PATCHELF" --set-rpath '$ORIGIN' "$dst"
done

# --- verify the split is still true -----------------------------------------
# Build-box masking guard: every NEEDED soname must be accounted for by the
# bundle, by a declared dependency, or by the EL8 base/GLVND allowlist. A new
# upstream dep would otherwise ship broken to a node that lacks it.
#
# This walks the binary AND every bundled lib. Checking only the binary is not
# enough and shipped a broken package once: libXfont2 pulls libfontenc, which
# nothing else in the loadout owns, so the clean-container gate caught
# "libfontenc.so.1 => not found" on a build box where the X libs were installed.
echo "==> Checking NEEDED closure ..."
ALLOW_BASE="libc.so.6 libm.so.6 libpthread.so.0 libdl.so.2 librt.so.1 \
libgcc_s.so.1 libsystemd.so.0 libudev.so.1 libaudit.so.1 libcap.so.2 \
libcap-ng.so.0 libselinux.so.1 libcrypto.so.1.1 libgcrypt.so.20 \
libgpg-error.so.0 libz.so.1 liblzma.so.5 liblz4.so.1 libblkid.so.1 \
libmount.so.1 libuuid.so.1 libbz2.so.1 libpcre2-8.so.0 \
libGL.so.1 libGLX.so.0 libGLdispatch.so.0"
ALLOW_DEP="libX11.so.6 libX11-xcb.so.1 libXau.so.6 libdbus-1.so.3 \
libepoxy.so.0 libpixman-1.so.0 libfreetype.so.6 libxcb.so.1 libxcb-icccm.so.4 \
libxcb-image.so.0 libxcb-keysyms.so.1 libxcb-randr.so.0 libxcb-render.so.0 \
libxcb-render-util.so.0 libxcb-shape.so.0 libxcb-shm.so.0 libxcb-util.so.1 \
libxcb-xkb.so.1 libdrm.so.2 libxshmfence.so.1"

scan_targets="$STAGE/bin/Xephyr.bin"
for soname in $BUNDLE_LIBS; do
    scan_targets="$scan_targets $STAGE/lib64/$soname"
done

unaccounted=""
seen=""
for target in $scan_targets; do
    for soname in $(objdump -p "$target" | awk '/NEEDED/ {print $2}'); do
        case " $seen " in
            *" $soname "*) continue ;;
        esac
        seen="$seen $soname"
        found=0
        for known in $BUNDLE_LIBS $ALLOW_BASE $ALLOW_DEP; do
            [ "$soname" = "$known" ] && { found=1; break; }
        done
        [ "$found" -eq 1 ] || unaccounted="$unaccounted $soname"
    done
done
if [ -n "$unaccounted" ]; then
    echo "ERROR: NEEDED sonames not covered by bundle, depends, or base allowlist:" >&2
    printf '  %s\n' $unaccounted >&2
    echo "  Bundle them (BUNDLE_LIBS + packages.json libs), add a depends, or" >&2
    echo "  extend the allowlist above if they are genuinely EL8 base." >&2
    exit 1
fi

# --- install into payload ---------------------------------------------------
mkdir -p "$BIN_DIR" "$LIB_DIR"
for f in Xephyr Xephyr.bin xdesk; do
    bzip2 -kf "$STAGE/bin/$f"
    cp "$STAGE/bin/$f.bz2" "$BIN_DIR/$f.bz2"
    chmod 644 "$BIN_DIR/$f.bz2"
done
for soname in $BUNDLE_LIBS; do
    bzip2 -kf "$STAGE/lib64/$soname"
    cp "$STAGE/lib64/$soname.bz2" "$LIB_DIR/$soname.bz2"
    chmod 644 "$LIB_DIR/$soname.bz2"
done

# --- provenance -------------------------------------------------------------
# Record every source RPM NVR actually consumed so the shipped build is
# auditable. Overwrites the committed placeholder on each successful build.
PROV="$WRAP_DIR/PROVENANCE"
{
    echo "# Written by build/build-xephyr.sh on $(date -u +%Y-%m-%dT%H:%M:%SZ)."
    echo "# Do not edit by hand; the script overwrites this on each build."
    echo ""
    echo "Source:       EL8 AppStream RPMs (${ARCH} only), pinned by --tag"
    echo "Platform:     ${PLATFORM}"
    echo "Tag:          ${TAG}"
    echo "Built:        $(date -u +%Y-%m-%d)"
    echo ""
    echo "Bundled RPM NVRs (every source RPM actually consumed):"
    echo "  ${RPM_NVR}"
    for nvr in $CONSUMED_LIB_NVRS; do
        echo "  ${nvr}"
    done
    echo ""
    echo "The --tag is the full version-release (e.g. ${TAG}). The release"
    echo "field is where Red Hat's CVE backports live, so pinning it is what"
    echo "makes the shipped X server reproducible and auditable."
    echo "payload/packages.json records the same full NVR as the xephyr"
    echo "entry's \"version\" field."
    echo ""
    echo "Bundled support libs (taken from the RPMs above, never from"
    echo "/usr/lib64 on the build box):"
    echo "  libXdmcp.so.6, libXfont2.so.2, libfontenc.so.1,"
    echo "  libxcb-glx.so.0, libxcb-xf86dri.so.0, libxcb-xv.so.0"
} > "$PROV"

echo "Staged:"
for f in Xephyr Xephyr.bin xdesk; do
    echo "  payload/$PLATFORM/bin/$f.bz2"
done
for soname in $BUNDLE_LIBS; do
    echo "  payload/$PLATFORM/lib64/$soname.bz2"
done
echo ""
echo "Provenance: $PROV"
echo ""
echo "Next:"
echo "  ./build/strip-all-elf-binaries"
echo "  ./loadout completion bash > envs/bash/global/completions/loadout.bash"