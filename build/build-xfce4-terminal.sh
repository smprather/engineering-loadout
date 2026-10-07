#!/bin/sh
# Shanghai-bundle xfce4-terminal (GTK3/VTE terminal emulator) from the EL8
# EPEL RPM for el8.x86_64.glibc2p28.
#
# Why an RPM repack: upstream publishes source tarballs only (no Linux binary
# release), and building it from source would mean building the whole Xfce
# stack (libxfce4util, libxfce4ui, xfconf) as well. EPEL8 already carries the
# 1.0.4 build against EL8's GTK3/VTE, so the repack is both smaller and closer
# to what an EL8 host expects. Same technique as mate-terminal / Xephyr /
# firefox: strip -> patchelf -> bzip2, RPATH pre-baked in the repo, installer
# stays pure decompress + chmod.
#
# Build process:
#
#   1. dnf download the exact pinned RPM NVR plus every consumed lib provider
#      RPM into a temp dir (no root, no system install). The lib RPMs are
#      downloaded rather than copied from /usr/lib64 so the bundled sonames
#      are pinned to the repo and not to whatever the build box happens to
#      have -- the build-box-masking class the NEEDED-closure guard below
#      exists to catch.
#   2. rpm2cpio | cpio each tree out; take usr/bin/xfce4-terminal and each
#      usr/lib64/<soname> (resolving symlinks *within the extracted tree*,
#      never against the host root).
#   3. strip -> patchelf (binary: '$ORIGIN/../lib64:$ORIGIN/../lib'; libs:
#      '$ORIGIN' so they find each other flat in lib64/) -> bzip2.
#   4. Ship bin/xfce4-terminal (prefix-deriving POSIX-sh wrapper) +
#      bin/xfce4-terminal.bin (the real ELF).
#
# Library split (verified with objdump -p against payload/packages.json):
#   - gui_libs owns the GTK3/X11/pango/cairo closure -> declared as a depends.
#   - mate-terminal owns libvte-2.91.so.0 at the same lib64/ path we install
#     to -> declared in BOTH entries' "libs" (two owners of one payload path is
#     the accepted pattern, cf. libz.so.1), so selecting either terminal
#     installs it and nothing is duplicated.
#   - BUNDLED here: libxfce4ui-2, libxfce4util.so.7, libxfconf-0.so.3 and
#     libstartup-notification-1.so.0.
#
# Why libstartup-notification-1.so.0 is bundled although it is not a direct
# NEEDED of the binary: it is a NEEDED of our OWN bundled libxfce4ui-2.so.0, it
# is owned by no other loadout package, and a stock almalinux:8.10 does not
# have it (verified: `ls /usr/lib64/libstartup-notification-1.so.0` is absent
# and the package is not installed; it lives in EL8 AppStream/EPEL). This is
# the same class as Xephyr's libfontenc, which shipped broken through a green
# smoke because the closure check walked only the binary.
#
# Still assumed present on the target (NOT bundled):
#   - a GLVND libGL (gui-wrapper-env.sh gates its Mesa exports on the host);
#     nothing here needs GL directly.
#   - /usr/share/xfce4/terminal/colorschemes: the app starts and runs without
#     it (measured under Xvfb with the directory absent). Only the extra colour
#     schemes are unavailable; the built-in defaults remain. The absent
#     xfce4-terminal.desktop costs a one-line libxfce4ui warning on GUI start.
#
# Session bus / xfconf (measured, not assumed): the terminal starts and shows
# its window with NO D-Bus session bus at all and with no xfconfd, and the
# Preferences dialog opens too. Persistence of preferences needs a host
# session bus with xfconf (EL8 `xfconf` package, i.e. xfconfd); without it the
# app silently uses built-in defaults and writes nothing under
# ~/.config/xfce4. xfconfd is therefore NOT bundled -- there is no hard
# failure to fix, and bundling a D-Bus-activatable service for one optional
# app would be the wrong trade.
#
# --tag is the upstream version (e.g. 1.0.4); the EPEL release field is pinned
# in this script (EPEL_RELEASE) so the downloaded RPM NVR is exact and the
# build is reproducible. The guard below matches the downloaded RPM NVR
# exactly, and payload/packages.json must record the same version. On success
# the script writes build/xfce4-terminal/PROVENANCE recording every source RPM
# NVR it actually consumed.
#
# Usage (run from any directory, inside the EL8 build container):
#   ./build/build-xfce4-terminal.sh --tag 1.0.4
#
# Then, as for every payload change:
#   ./build/strip-all-elf-binaries
#   python3.14 build/gen-installed-sizes
#   python3.14 build/gen-content-manifest

set -eu

REPO="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib.sh
. "$REPO/build/lib.sh"

PLATFORM=el8.x86_64.glibc2p28
ARCH=x86_64
BIN_DIR="$REPO/payload/$PLATFORM/bin"
LIB_DIR="$REPO/payload/$PLATFORM/lib64"
PROV_DIR="$REPO/build/xfce4-terminal"
PKG_JSON="$REPO/payload/packages.json"
PKG_NAME=xfce4-terminal
RPM_NAME="xfce4-terminal"

# EPEL release field for the pinned version. xfce4-terminal 1.0.4 has exactly
# one EL8 build; keeping the release here (instead of accepting it in --tag)
# makes the download reproducible. Bump alongside --tag if EPEL rebuilds.
EPEL_RELEASE="1.el8"

# Sonames no other loadout package owns. Keep in sync with the "libs" array of
# the xfce4-terminal entry in payload/packages.json. libvte-2.91.so.0 is
# deliberately NOT here: it is an existing payload stem shared with
# mate-terminal, so it is declared (below) rather than repackaged.
BUNDLE_LIBS="libxfce4ui-2.so.0 libxfce4util.so.7 libxfconf-0.so.3 libstartup-notification-1.so.0"

# soname -> providing EL8 package. Every BUNDLE_LIBS entry must map to exactly
# one package so the extraction loop knows which RPM tree to pull it from.
LIB_PKGS="libxfce4ui libxfce4util xfconf startup-notification"
lib_pkg_for() {
    case "$1" in
        libxfce4ui-2.so.0)            echo libxfce4ui ;;
        libxfce4util.so.7)           echo libxfce4util ;;
        libxfconf-0.so.3)            echo xfconf ;;
        libstartup-notification-1.so.0) echo startup-notification ;;
        *) return 1 ;;
    esac
}

# Payload stems our packages.json entry declares: installed with this package,
# but produced by someone else (so they are not repackaged here).
shared_libs="libvte-2.91.so.0"

# gui_libs-provided sonames our closure needs (declared in gui_libs' "libs").
dep_libs="libX11.so.6 libX11-xcb.so.1 libxcb.so.1 libxcb-util.so.1 \
libgtk-3.so.0 libgdk-3.so.0 libgdk_pixbuf-2.0.so.0 libpango-1.0.so.0 \
libpangocairo-1.0.so.0 libcairo.so.2 libcairo-gobject.so.2 libatk-1.0.so.0 \
libgio-2.0.so.0 libglib-2.0.so.0 libgobject-2.0.so.0 libgthread-2.0.so.0 \
libSM.so.6 libICE.so.6"

# Never bundled -- must match the host's ld-linux exactly (see AGENTS.md).
base_libs="libc.so.6 libm.so.6 libpthread.so.0 libdl.so.2 librt.so.1 libgcc_s.so.1"

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
    echo "ERROR: --tag is required. Specify the EPEL xfce4-terminal version, e.g.:" >&2
    echo "  $0 --tag 1.0.4" >&2
    echo "" >&2
    echo "The EPEL release field is pinned in this script (EPEL_RELEASE=$EPEL_RELEASE)," >&2
    echo "so the version alone is enough. See what is available with:" >&2
    echo "  dnf list --available $RPM_NAME" >&2
    exit 1
fi

case "$tag" in
    *-*)
        echo "ERROR: --tag must be the bare version, not a version-release." >&2
        echo "  You passed '$tag'; the release field ($EPEL_RELEASE) is pinned in this script." >&2
        echo "  Use: $0 --tag ${tag%%-*}" >&2
        exit 1
        ;;
esac

loadout_require_cmds dnf rpm2cpio cpio bzip2 objdump readelf strip

PATCHELF="${LOADOUT_PATCHELF:-$HOME/.local/bin/patchelf}"
[ -x "$PATCHELF" ] || PATCHELF="$(command -v patchelf || true)"
[ -n "$PATCHELF" ] || { echo "ERROR: patchelf not found" >&2; exit 1; }
STRIP=/usr/bin/strip
[ -x "$STRIP" ] || { echo "ERROR: $STRIP not found" >&2; exit 1; }

EXPECTED_NVR="$RPM_NAME-$tag-$EPEL_RELEASE.$ARCH"
EXPECTED_BASENAME="$EXPECTED_NVR.rpm"

# --- guard: packages.json must record the same version ----------------------
# Read-only check (this script never writes packages.json). Scope the search to
# the xfce4-terminal block so another package's "version" line cannot match:
# enter on `    "xfce4-terminal": {` (4-space indent), leave at the first `    }`.
[ -f "$PKG_JSON" ] || { echo "ERROR: $PKG_JSON not found" >&2; exit 1; }
json_version=$(awk '
    /^    "xfce4-terminal": \{/ { in_block=1; next }
    in_block && /^    \}/ { in_block=0; next }
    in_block && /"version":/ {
        line = $0
        sub(/^.*"version":[[:space:]]*"/, "", line)
        sub(/".*$/, "", line)
        print line
        exit
    }
' "$PKG_JSON")
if [ -z "$json_version" ]; then
    echo "ERROR: could not locate the xfce4-terminal \"version\" field in $PKG_JSON." >&2
    echo "  Check that the xfce4-terminal entry exists and has a \"version\" key." >&2
    exit 1
fi
if [ "$json_version" != "$tag" ]; then
    echo "ERROR: payload/packages.json xfce4-terminal version mismatch." >&2
    echo "  --tag:                                $tag" >&2
    echo "  packages.json xfce4-terminal.version: $json_version" >&2
    echo "  They must be identical. Update packages.json to match --tag; this" >&2
    echo "  script does not write it." >&2
    exit 1
fi

STAGE=$(mktemp -d "${TMPDIR:-/tmp}/xfce4-terminal-stage-XXXXXX")
XVFB_PID=""
APP_PID=""
cleanup() {
    [ -n "$APP_PID" ] && kill "$APP_PID" 2>/dev/null || true
    [ -n "$XVFB_PID" ] && kill "$XVFB_PID" 2>/dev/null || true
    rm -rf "$STAGE"
}
trap cleanup EXIT INT TERM

mkdir -p "$STAGE/bin" "$STAGE/lib64" "$STAGE/rpm" "$STAGE/rpm-libs"

# --- acquire the pinned xfce4-terminal RPM ----------------------------------
echo "==> Downloading $EXPECTED_NVR ..."
( cd "$STAGE/rpm" && dnf download "$EXPECTED_NVR" >/dev/null 2>&1 ) || {
    echo "ERROR: dnf download $EXPECTED_NVR failed (no such build in the repos?)." >&2
    echo "  Check: dnf list --available $RPM_NAME" >&2
    exit 1
}
RPM_PATH="$STAGE/rpm/$EXPECTED_BASENAME"
[ -f "$RPM_PATH" ] || {
    # dnf may have chosen a different release than EPEL_RELEASE. Never guess:
    # a different release is a different build and must be pinned deliberately.
    echo "ERROR: expected $EXPECTED_BASENAME, got:" >&2
    ls "$STAGE/rpm" >&2
    echo "  EPEL moved or added a release. Bump EPEL_RELEASE in this script (and" >&2
    echo "  re-verify) rather than shipping an unpinned build." >&2
    exit 1
}
RPM_NVR=$(basename "$RPM_PATH" .rpm)
echo "==> Confirmed RPM: $RPM_NVR"

# --- acquire the lib provider RPMs -----------------------------------------
# --arch x86_64 keeps dnf from dragging the 32-bit build down; a plain
# `dnf download <lib>` on EL8 fetches both. The globs below ignore any .i686.
CONSUMED_LIB_NVRS=""
echo "==> Downloading support-lib RPMs: $LIB_PKGS ..."
( cd "$STAGE/rpm-libs" && dnf download --arch "$ARCH" $LIB_PKGS >/dev/null 2>&1 ) || {
    echo "ERROR: dnf download of support-lib RPMs failed." >&2
    exit 1
}
for pkg in $LIB_PKGS; do
    p=$(ls "$STAGE"/rpm-libs/${pkg}-*.${ARCH}.rpm 2>/dev/null | head -1)
    [ -n "$p" ] || {
        echo "ERROR: $pkg ${ARCH} RPM missing from $STAGE/rpm-libs" >&2
        exit 1
    }
    CONSUMED_LIB_NVRS="$CONSUMED_LIB_NVRS $(basename "$p" .rpm)"
done

# --- extract xfce4-terminal -------------------------------------------------
echo "==> Extracting $RPM_NVR ..."
( cd "$STAGE" && rpm2cpio "$RPM_PATH" | cpio -idm --quiet )

SRC_BIN="$STAGE/usr/bin/$PKG_NAME"
[ -f "$SRC_BIN" ] || { echo "ERROR: usr/bin/$PKG_NAME not in $RPM_NVR" >&2; exit 1; }

cp "$SRC_BIN" "$STAGE/bin/$PKG_NAME.bin"
chmod 755 "$STAGE/bin/$PKG_NAME.bin"
"$STRIP" "$STAGE/bin/$PKG_NAME.bin"
# shellcheck disable=SC2016  # $ORIGIN is a literal ld.so token
"$PATCHELF" --set-rpath '$ORIGIN/../lib64:$ORIGIN/../lib' "$STAGE/bin/$PKG_NAME.bin"

# --- bundled libs (from the provider RPMs, never from /usr/lib64) ----------
echo "==> Bundling support libs from RPMs ..."
for soname in $BUNDLE_LIBS; do
    pkg=$(lib_pkg_for "$soname") || { echo "ERROR: no provider mapping for $soname" >&2; exit 1; }
    rpm_path=$(ls "$STAGE"/rpm-libs/${pkg}-*.${ARCH}.rpm 2>/dev/null | head -1)
    [ -n "$rpm_path" ] || { echo "ERROR: $pkg ${ARCH} RPM missing" >&2; exit 1; }

    # One tree per provider RPM: overlapping paths from different RPMs must not
    # clobber, and re-running cpio over an existing tree emits "not created:
    # newer or same age version exists" warnings that read like a failure.
    ext="$STAGE/extract-$pkg"
    if [ ! -d "$ext" ]; then
        mkdir -p "$ext"
        ( cd "$ext" && rpm2cpio "$rpm_path" | cpio -idm --quiet )
    fi

    link="$ext/usr/lib64/$soname"
    [ -e "$link" ] || {
        echo "ERROR: $soname not found in $pkg RPM ($(basename "$rpm_path"))" >&2
        exit 1
    }

    # Resolve to a regular file *within the extracted tree*. Never `readlink -f`:
    # on an absolute symlink it would resolve against the HOST root and silently
    # ship the build box's copy again. Map absolute targets back into $ext.
    src="$link"
    while [ -L "$src" ]; do
        target=$(readlink "$src")
        case "$target" in
            /*) src="$ext$target" ;;
            *)  src="$(dirname "$src")/$target" ;;
        esac
    done
    [ -f "$src" ] || {
        echo "ERROR: $soname resolved to '$src', not a regular file, in the $pkg RPM tree" >&2
        exit 1
    }

    cp "$src" "$STAGE/lib64/$soname"
    chmod 755 "$STAGE/lib64/$soname"
    "$STRIP" "$STAGE/lib64/$soname"
    # shellcheck disable=SC2016  # $ORIGIN is a literal ld.so token
    "$PATCHELF" --set-rpath '$ORIGIN' "$STAGE/lib64/$soname"
done

# --- verify the split is still true -----------------------------------------
# Build-box masking guard: every NEEDED soname of the binary AND of every lib we
# bundle must be accounted for by our bundle, by a payload stem this package
# declares, by a declared dependency (gui_libs), or by the EL8 base allowlist. A
# new upstream dep would otherwise ship broken to a node that lacks it. Walking
# the binary only is not enough -- see libstartup-notification-1.so.0 above and
# Xephyr's libfontenc in AGENTS.md.
echo "==> Checking NEEDED closure ..."
scan_targets="$STAGE/bin/$PKG_NAME.bin"
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
        for known in $BUNDLE_LIBS $shared_libs $dep_libs $base_libs; do
            [ "$soname" = "$known" ] && { found=1; break; }
        done
        [ "$found" -eq 1 ] || unaccounted="$unaccounted $soname"
    done
done
if [ -n "$unaccounted" ]; then
    echo "ERROR: NEEDED sonames not covered by bundle, declared libs, depends, or base:" >&2
    printf '  %s\n' $unaccounted >&2
    echo "  Bundle them (BUNDLE_LIBS + LIB_PKGS + packages.json libs), declare a" >&2
    echo "  depends, or extend the allowlist above if they are genuinely EL8 base." >&2
    exit 1
fi
echo "    closure covered by $BUNDLE_LIBS $shared_libs + gui_libs"

# --- wrapper (header + shared env blocks + exec) -----------------------------
# The installed wrapper must stay self-contained (no repo runtime dependency),
# so the shared blocks are inlined here. Single source of truth per block:
# build/gui-wrapper-env.sh owns the host-GL gate + host-fontconfig LD_PRELOAD,
# build/gtk3-launcher-env.sh owns the Wayland-session GTK3 adaptation. Both must
# END IN A NEWLINE or `cat` fuses their last line with the next fragment's first
# (tests/prebuilt-binaries asserts this and scans every installed wrapper).
GUI_ENV_BLOCK="$REPO/build/gui-wrapper-env.sh"
GTK3_ENV_BLOCK="$REPO/build/gtk3-launcher-env.sh"
[ -r "$GUI_ENV_BLOCK" ] || { echo "ERROR: missing $GUI_ENV_BLOCK" >&2; exit 1; }
[ -r "$GTK3_ENV_BLOCK" ] || { echo "ERROR: missing $GTK3_ENV_BLOCK" >&2; exit 1; }
for block in "$GUI_ENV_BLOCK" "$GTK3_ENV_BLOCK"; do
    [ "$(tail -c 1 "$block" | wc -l)" -eq 1 ] || {
        echo "ERROR: $block does not end in a newline; inlining would fuse its" >&2
        echo "  last line with the next fragment's first. Fix the fragment." >&2
        exit 1
    }
done

{
    printf '#!/bin/sh\n'
    printf '# xfce4-terminal launcher -- loadout shanghai bundle.\n'
    printf '# Composed of: prefix header + build/gui-wrapper-env.sh +\n'
    printf '# build/gtk3-launcher-env.sh -- see those files for what each fixes.\n'
    printf '# Regenerate by re-running build/build-xfce4-terminal.sh.\n'
    printf '#\n'
    printf '# Resolves the install prefix from the installed path (never $HOME, so a\n'
    printf '# --dest-dir install works) and execs the sibling .bin.\n\n'
    # shellcheck disable=SC2016  # $0/$prefix must stay literal here
    printf 'prefix=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)\n\n'
    cat "$GUI_ENV_BLOCK" "$GTK3_ENV_BLOCK"
    # shellcheck disable=SC2016  # $prefix/$@ must stay literal here
    printf 'exec "$prefix/bin/%s.bin" "$@"\n' "$PKG_NAME"
} > "$STAGE/bin/$PKG_NAME"
chmod 755 "$STAGE/bin/$PKG_NAME"

# --- stage-verify: run the shipped wrapper under Xvfb -----------------------
# This is the check a --version probe cannot do. It exercises the composed
# wrapper, the pre-baked RPATHs and the real GTK3/VTE window path, with a fake
# HOME and from / so nothing can resolve through the build tree or $HOME.
echo "==> Stage-verify under Xvfb ..."
STAGE_PREFIX="$STAGE/prefix"
mkdir -p "$STAGE_PREFIX/bin" "$STAGE_PREFIX/lib64" "$STAGE/home"
cp "$STAGE/bin/$PKG_NAME" "$STAGE/bin/$PKG_NAME.bin" "$STAGE_PREFIX/bin/"
# Simulate the installed tree: our libs first, then the whole payload lib64 so
# the run resolves the GTK3/VTE closure from loadout payload -- never from the
# container's /usr/lib64 (that is the build-box-masking trap).
cp "$STAGE"/lib64/* "$STAGE_PREFIX/lib64/"
for f in "$LIB_DIR"/*.bz2; do
    s=$(basename "$f" .bz2)
    [ -e "$STAGE_PREFIX/lib64/$s" ] || bunzip2 -c "$f" > "$STAGE_PREFIX/lib64/$s"
done

# No shipped byte may carry the build-tree path. The wrapper derives its prefix
# from $0 and the ELFs carry $ORIGIN, so any hit here is a packaging defect.
prefix_hits=$(grep -rla -- "$STAGE" "$STAGE_PREFIX/bin" "$STAGE_PREFIX/lib64" 2>/dev/null || true)
repo_hits=$(grep -la -- "$REPO" "$STAGE_PREFIX/bin/$PKG_NAME" 2>/dev/null || true)
if [ -n "$prefix_hits$repo_hits" ]; then
    echo "ERROR: shipped tree embeds the build prefix:" >&2
    printf '%s\n' $prefix_hits $repo_hits >&2
    exit 1
fi
echo "    no build prefix in the staged tree"

ver_out=$(cd / && HOME="$STAGE/home" XDG_CONFIG_HOME="$STAGE/home/.config" \
    "$STAGE_PREFIX/bin/$PKG_NAME" --version 2>/dev/null || true)
case "$ver_out" in
    "$PKG_NAME $tag"*) echo "    --version: $(echo "$ver_out" | head -1)" ;;
    *)
        echo "ERROR: --version did not report $PKG_NAME $tag. Got:" >&2
        printf '  %s\n' "$ver_out" >&2
        exit 1
        ;;
esac

DISP=:93
rm -f "/tmp/.X11-unix/X93"
Xvfb "$DISP" -screen 0 800x600x24 >"$STAGE/xvfb.log" 2>&1 &
XVFB_PID=$!
i=0
while [ "$i" -lt 40 ] && [ ! -e "/tmp/.X11-unix/X93" ]; do
    sleep 0.25
    i=$((i + 1))
done
[ -e "/tmp/.X11-unix/X93" ] || {
    echo "ERROR: Xvfb $DISP did not come up:" >&2
    cat "$STAGE/xvfb.log" >&2
    exit 1
}

# No DBUS_SESSION_BUS_ADDRESS on purpose: starting must not depend on one (see
# the header). LOADOUT_GUI_HOST_FONTCONFIG=0 keeps the bundled fontconfig in
# play, which is what a GL-less farm node gets.
( cd / && exec env HOME="$STAGE/home" XDG_CONFIG_HOME="$STAGE/home/.config" DISPLAY="$DISP" \
    LOADOUT_GUI_HOST_FONTCONFIG=0 "$STAGE_PREFIX/bin/$PKG_NAME" ) >"$STAGE/app.log" 2>&1 &
APP_PID=$!
found=0
i=0
while [ "$i" -lt 40 ]; do
    if xwininfo -display "$DISP" -root -tree 2>/dev/null | grep -qi 'Xfce4-terminal'; then
        found=1
        break
    fi
    sleep 0.5
    i=$((i + 1))
done
if [ "$found" -ne 1 ]; then
    echo "ERROR: no xfce4-terminal window on $DISP after 20s. Tree:" >&2
    xwininfo -display "$DISP" -root -tree 2>&1 | head -20 >&2
    echo "  app output:" >&2
    cat "$STAGE/app.log" >&2
    exit 1
fi
kill -0 "$APP_PID" 2>/dev/null || {
    echo "ERROR: xfce4-terminal exited after mapping its window:" >&2
    cat "$STAGE/app.log" >&2
    exit 1
}
# A startup that merely mapped a window but could not resolve a lib would have
# died above; assert the log holds no loader/fatal noise either.
if grep -Eq 'cannot open shared object file|GLib-GIO-ERROR|Segmentation fault' "$STAGE/app.log"; then
    echo "ERROR: fatal runtime noise in the staged tree:" >&2
    cat "$STAGE/app.log" >&2
    exit 1
fi
echo "    window mapped: $(xwininfo -display "$DISP" -root -tree 2>/dev/null | grep -i 'Xfce4-terminal' | head -1 | sed 's/^ *//')"
echo "    app log ($(wc -l <"$STAGE/app.log" | tr -d ' ') lines):"
sed 's/^/      /' "$STAGE/app.log"
kill "$APP_PID" 2>/dev/null || true
APP_PID=""
kill "$XVFB_PID" 2>/dev/null || true
XVFB_PID=""

# --- install into payload ---------------------------------------------------
mkdir -p "$BIN_DIR" "$LIB_DIR"
for f in "$PKG_NAME" "$PKG_NAME.bin"; do
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
# auditable. Overwrites the committed file on each successful build.
mkdir -p "$PROV_DIR"
PROV="$PROV_DIR/PROVENANCE"
{
    echo "# Written by build/build-xfce4-terminal.sh on $(date -u +%Y-%m-%dT%H:%M:%SZ)."
    echo "# Do not edit by hand; the script overwrites this on each build."
    echo ""
    echo "Source:       EL8 EPEL RPMs (${ARCH} only), pinned by --tag + EPEL_RELEASE"
    echo "Platform:     ${PLATFORM}"
    echo "Version:      ${tag}"
    echo "Built:        $(date -u +%Y-%m-%d)"
    echo ""
    echo "Consumed RPM NVRs:"
    echo "  ${RPM_NVR}"
    for nvr in $CONSUMED_LIB_NVRS; do
        echo "  ${nvr}"
    done
    echo ""
    echo "Bundled libs (taken from the RPMs above, never from /usr/lib64 on the"
    echo "build box):"
    printf '  %s\n' $BUNDLE_LIBS
    echo ""
    echo "libstartup-notification-1.so.0 is a NEEDED of the bundled"
    echo "libxfce4ui-2.so.0, is owned by no other loadout package, and is absent"
    echo "from a stock EL8 install -- hence bundled rather than assumed."
    echo ""
    echo "libvte-2.91.so.0 is NOT repackaged here: it is an existing payload stem"
    echo "declared by both this package and mate-terminal in packages.json."
    echo ""
    echo "payload/packages.json records \"version\": \"${tag}\" for xfce4-terminal."
} > "$PROV"

echo ""
echo "Staged:"
for f in "$PKG_NAME" "$PKG_NAME.bin"; do
    echo "  payload/$PLATFORM/bin/$f.bz2"
done
for soname in $BUNDLE_LIBS; do
    echo "  payload/$PLATFORM/lib64/$soname.bz2"
done
echo ""
echo "Provenance: $PROV"
echo ""
echo "Next (order matters -- sizes must be regenerated before the manifest):"
echo "  ./build/strip-all-elf-binaries"
echo "  python3.14 build/gen-installed-sizes"
echo "  python3.14 build/gen-content-manifest"
