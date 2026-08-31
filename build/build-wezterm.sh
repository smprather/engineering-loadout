#!/bin/sh
# Shanghai-bundle WezTerm plus the Mesa 3D runtime from the on-system install
# for el8.x86_64.glibc2p28.
#
# This is intentionally a "sample app" bundle for the Mesa runtime:
#
#   payload/<platform>/runtime/wezterm.tar.bz2
#     ./bin/wezterm                 relocatable wrapper
#     ./bin/wezterm-gui             relocatable wrapper
#     ./bin/wezterm-mux-server      relocatable wrapper
#     ./bin/open-wezterm-here       helper script
#     ./bin/strip-ansi-escapes      copied from /usr/bin/strip-ansi-escapes
#     ./lib/wezterm/wezterm         copied from /usr/bin/wezterm
#     ./lib/wezterm/wezterm-gui     copied from /usr/bin/wezterm-gui
#     ./lib/wezterm/wezterm-mux-server copied from /usr/bin/wezterm-mux-server
#     ./share/applications/...      desktop file, when installed
#     ./share/metainfo/...          appstream metadata, when installed
#     ./share/icons/...             application icon, when installed
#     ./share/nautilus-python/...   Nautilus extension, when installed
#
#   payload/<platform>/runtime/mesa3d_libs.tar.bz2
#     ./lib64/libEGL_mesa.so.0
#     ./lib64/libgbm.so.1
#     ./lib64/libglapi.so.0
#     ./lib64/libLLVM-17.so
#     ./lib64/libdrm*.so.*
#     ./lib64/dri/*_dri.so
#     ./share/glvnd/egl_vendor.d/50_mesa.json
#
# Do NOT bundle libGL.so.1, libGLX.so.0, or libGLdispatch.so.0. Those are
# GLVND/display-driver dispatchers and must come from the host. The bundled
# Mesa vendor library is found through the GLVND JSON and LD_LIBRARY_PATH.
#
# Usage:
#   ./build/build-wezterm.sh --tag 20260618_095146_c10636f3

set -eu

REPO="$(cd "$(dirname "$0")/.." && pwd)"
PLATFORM="el8.x86_64.glibc2p28"
RUNTIME_DIR="$REPO/payload/$PLATFORM/runtime"
TAG=""
PATCHELF="${HOME}/.local/bin/patchelf"

while [ "$#" -gt 0 ]; do
    case "$1" in
        --tag)
            shift
            [ "$#" -gt 0 ] || { echo "missing value for --tag" >&2; exit 2; }
            TAG="$1"
            ;;
        -h|--help)
            sed -n '2,/^$/p' "$0"
            exit 0
            ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done

need() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "missing required command: $1" >&2
        exit 1
    }
}

need bzip2
need readelf
need strip
need tar
command -v "$PATCHELF" >/dev/null 2>&1 || PATCHELF="$(command -v patchelf || true)"
[ -n "$PATCHELF" ] || { echo "missing required command: patchelf" >&2; exit 1; }

WEZTERM_BIN=/usr/bin/wezterm
WEZTERM_GUI=/usr/bin/wezterm-gui
WEZTERM_MUX_SERVER=/usr/bin/wezterm-mux-server
STRIP_ANSI_ESCAPES=/usr/bin/strip-ansi-escapes
for wezterm_bin in "$WEZTERM_BIN" "$WEZTERM_GUI" "$WEZTERM_MUX_SERVER" "$STRIP_ANSI_ESCAPES"; do
    [ -x "$wezterm_bin" ] || {
        echo "ERROR: $wezterm_bin not found or not executable." >&2
        exit 1
    }
done

detected_tag=$("$WEZTERM_BIN" --version | awk '{print $2}')
if [ -z "$TAG" ]; then
    echo "ERROR: --tag is required. Current system WezTerm reports:" >&2
    echo "  $WEZTERM_BIN --version => $("$WEZTERM_BIN" --version)" >&2
    exit 1
fi
if [ "$TAG" != "$detected_tag" ]; then
    echo "ERROR: --tag $TAG does not match $WEZTERM_BIN --version ($detected_tag)" >&2
    exit 1
fi

STAGE=$(mktemp -d "${TMPDIR:-/tmp}/wezterm-stage-XXXXXX")
MESA_STAGE=$(mktemp -d "${TMPDIR:-/tmp}/mesa3d-stage-XXXXXX")
trap 'rm -rf "$STAGE" "$MESA_STAGE"' EXIT

mkdir -p "$RUNTIME_DIR"
rm -f "$RUNTIME_DIR/wezterm.tar.bz2" "$RUNTIME_DIR"/wezterm.tar.bz2.part-* \
    "$RUNTIME_DIR/mesa3d_libs.tar.bz2" "$RUNTIME_DIR"/mesa3d_libs.tar.bz2.part-*

echo "==> Staging WezTerm $TAG from $WEZTERM_BIN ..."
mkdir -p "$STAGE/bin" "$STAGE/lib/wezterm" "$STAGE/share/applications" \
    "$STAGE/share/metainfo" "$STAGE/share/icons/hicolor/128x128/apps" \
    "$STAGE/share/nautilus-python/extensions"

for wezterm_bin in "$WEZTERM_BIN" "$WEZTERM_GUI" "$WEZTERM_MUX_SERVER"; do
    name=$(basename "$wezterm_bin")
    cp "$wezterm_bin" "$STAGE/lib/wezterm/$name"
    strip "$STAGE/lib/wezterm/$name" 2>/dev/null || true
    # shellcheck disable=SC2016
    "$PATCHELF" --set-rpath '$ORIGIN/../../lib64:$ORIGIN' "$STAGE/lib/wezterm/$name"
done

cp "$STRIP_ANSI_ESCAPES" "$STAGE/bin/strip-ansi-escapes"
strip "$STAGE/bin/strip-ansi-escapes" 2>/dev/null || true
# shellcheck disable=SC2016
"$PATCHELF" --set-rpath '$ORIGIN/../lib64:$ORIGIN' "$STAGE/bin/strip-ansi-escapes"

if [ -f /usr/bin/open-wezterm-here ]; then
    cp /usr/bin/open-wezterm-here "$STAGE/bin/"
fi

if [ -f /usr/share/applications/org.wezfurlong.wezterm.desktop ]; then
    cp /usr/share/applications/org.wezfurlong.wezterm.desktop "$STAGE/share/applications/"
fi
if [ -f /usr/share/metainfo/org.wezfurlong.wezterm.appdata.xml ]; then
    cp /usr/share/metainfo/org.wezfurlong.wezterm.appdata.xml "$STAGE/share/metainfo/"
fi
if [ -f /usr/share/icons/hicolor/128x128/apps/org.wezfurlong.wezterm.png ]; then
    cp /usr/share/icons/hicolor/128x128/apps/org.wezfurlong.wezterm.png \
        "$STAGE/share/icons/hicolor/128x128/apps/"
fi
if [ -f /usr/share/nautilus-python/extensions/wezterm-nautilus.py ]; then
    cp /usr/share/nautilus-python/extensions/wezterm-nautilus.py \
        "$STAGE/share/nautilus-python/extensions/"
fi

cat >"$STAGE/bin/wezterm" <<'EOF'
#!/bin/sh
# Wrapper for the engineering-loadout WezTerm shanghai bundle.
bin_dir=$(CDPATH= cd "$(dirname "$0")" && pwd -P) || exit 1
prefix=$(CDPATH= cd "$bin_dir/.." && pwd -P) || exit 1
real_wezterm="$prefix/lib/wezterm/wezterm"

# Mesa/GLVND fallback -- PLATFORM-CONDITIONED, not unconditional. The binaries
# carry RPATH $ORIGIN/../../lib64:$ORIGIN, which already resolves every NEEDED
# lib (incl. the bundled libssl/libcrypto.so.1.1 stems). The env exports below
# exist ONLY for the GL dlopens (libEGL_mesa/DRI drivers) on farm nodes with no
# host GL. Exporting them on a host that HAS its own GL stack is poison: the
# loadout lib64 area also carries gui_libs' EL8-era glib/pcre2/etc, which would
# shadow the host copies for wezterm AND EVERY CHILD it spawns (flatpak died
# with "libaccountsservice: undefined symbol g_once_init_leave_pointer"; host
# grep broke against the old bundled libpcre2). Same universal-host rule as
# firefox: host copy wins wherever the host can supply the soname; loadout
# libs step in only when the host cannot.
mesa_libdir="$prefix/lib64"
host_gl_missing=0
if command -v ldconfig >/dev/null 2>&1 \
   && ! ldconfig -p 2>/dev/null | grep -q 'libEGL\.so\.1'; then
  host_gl_missing=1
fi
if [ "$host_gl_missing" -eq 1 ] && [ -d "$mesa_libdir" ]; then
  export LD_LIBRARY_PATH="$mesa_libdir${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
  if [ -d "$mesa_libdir/dri" ]; then
    export LIBGL_DRIVERS_PATH="$mesa_libdir/dri${LIBGL_DRIVERS_PATH:+:$LIBGL_DRIVERS_PATH}"
  fi
  if [ -d "$prefix/share/glvnd/egl_vendor.d" ]; then
    export __EGL_VENDOR_LIBRARY_DIRS="$prefix/share/glvnd/egl_vendor.d${__EGL_VENDOR_LIBRARY_DIRS:+:$__EGL_VENDOR_LIBRARY_DIRS}"
  fi
fi

portal_setting_ok() {
  [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ] || return 0
  command -v gdbus >/dev/null 2>&1 || return 0
  command -v timeout >/dev/null 2>&1 || return 0

  timeout 2s gdbus call \
    --session \
    --dest org.freedesktop.portal.Desktop \
    --object-path /org/freedesktop/portal/desktop \
    --method org.freedesktop.portal.Settings.Read \
    org.freedesktop.appearance \
    color-scheme >/dev/null 2>&1
}

restart_portal() {
  command -v systemctl >/dev/null 2>&1 || return 1

  timeout 10s systemctl --user restart xdg-desktop-portal.service >/dev/null 2>&1 || return 1

  for _ in 1 2 3 4 5 6 7 8 9 10; do
    portal_setting_ok || return 0
    sleep 0.25
  done

  return 1
}

if [ -n "${WAYLAND_DISPLAY:-}" ] || [ -n "${DISPLAY:-}" ]; then
  portal_setting_ok || restart_portal || true
fi

exec "$real_wezterm" "$@"
EOF
chmod 755 "$STAGE/bin/wezterm"

for wezterm_cmd in wezterm-gui wezterm-mux-server; do
    cat >"$STAGE/bin/$wezterm_cmd" <<EOF
#!/bin/sh
bin_dir=\$(CDPATH= cd "\$(dirname "\$0")" && pwd -P) || exit 1
prefix=\$(CDPATH= cd "\$bin_dir/.." && pwd -P) || exit 1

# See the bin/wezterm wrapper for why the Mesa/GLVND exports are
# platform-conditioned: unconditional exports shadow the host's glib/pcre2
# (EL8-era gui_libs copies) in every child process on hosts with their own GL.
mesa_libdir="\$prefix/lib64"
host_gl_missing=0
if command -v ldconfig >/dev/null 2>&1 \\
   && ! ldconfig -p 2>/dev/null | grep -q 'libEGL\.so\.1'; then
  host_gl_missing=1
fi
if [ "\$host_gl_missing" -eq 1 ] && [ -d "\$mesa_libdir" ]; then
  export LD_LIBRARY_PATH="\$mesa_libdir\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"
  if [ -d "\$mesa_libdir/dri" ]; then
    export LIBGL_DRIVERS_PATH="\$mesa_libdir/dri\${LIBGL_DRIVERS_PATH:+:\$LIBGL_DRIVERS_PATH}"
  fi
  if [ -d "\$prefix/share/glvnd/egl_vendor.d" ]; then
    export __EGL_VENDOR_LIBRARY_DIRS="\$prefix/share/glvnd/egl_vendor.d\${__EGL_VENDOR_LIBRARY_DIRS:+:\$__EGL_VENDOR_LIBRARY_DIRS}"
  fi
fi

exec "\$prefix/lib/wezterm/$wezterm_cmd" "\$@"
EOF
    chmod 755 "$STAGE/bin/$wezterm_cmd"
done

echo "==> Writing WezTerm runtime archive ..."
tar -cjf "$RUNTIME_DIR/wezterm.tar.bz2" -C "$STAGE" \
    --owner=0 --group=0 --numeric-owner \
    ./bin ./lib ./share

echo "==> Staging Mesa 3D runtime ..."
mkdir -p "$MESA_STAGE/lib64/dri" "$MESA_STAGE/share/glvnd/egl_vendor.d"

copy_one() {
    src=$1
    dst_dir=$2
    [ -e "$src" ] || {
        echo "ERROR: missing Mesa runtime file: $src" >&2
        exit 1
    }
    cp -a "$src" "$dst_dir/"
}

for lib in \
    /usr/lib64/libEGL_mesa.so.0 /usr/lib64/libEGL_mesa.so.0.0.0 \
    /usr/lib64/libgbm.so.1 /usr/lib64/libgbm.so.1.0.0 \
    /usr/lib64/libglapi.so.0 /usr/lib64/libglapi.so.0.0.0 \
    /usr/lib64/libdrm.so.2 /usr/lib64/libdrm.so.2.4.0 \
    /usr/lib64/libdrm_amdgpu.so.1 /usr/lib64/libdrm_amdgpu.so.1.0.0 \
    /usr/lib64/libdrm_nouveau.so.2 /usr/lib64/libdrm_nouveau.so.2.0.0 \
    /usr/lib64/libdrm_radeon.so.1 /usr/lib64/libdrm_radeon.so.1.0.1 \
    /usr/lib64/libwayland-server.so.0 /usr/lib64/libwayland-server.so.0.21.0 \
    /usr/lib64/libxcb-dri2.so.0 /usr/lib64/libxcb-dri2.so.0.0.0 \
    /usr/lib64/libxcb-dri3.so.0 /usr/lib64/libxcb-dri3.so.0.0.0 \
    /usr/lib64/libxcb-present.so.0 /usr/lib64/libxcb-present.so.0.0.0 \
    /usr/lib64/libxshmfence.so.1 /usr/lib64/libxshmfence.so.1.0.0 \
    /usr/lib64/llvm17/lib/libLLVM-17.so
do
    copy_one "$lib" "$MESA_STAGE/lib64"
done

for drv in /usr/lib64/dri/*_dri.so; do
    copy_one "$drv" "$MESA_STAGE/lib64/dri"
done

copy_one /usr/share/glvnd/egl_vendor.d/50_mesa.json "$MESA_STAGE/share/glvnd/egl_vendor.d"

find "$MESA_STAGE" -type f -name '*.so*' | while IFS= read -r elf; do
    if readelf -h "$elf" >/dev/null 2>&1; then
        strip "$elf" 2>/dev/null || true
        # shellcheck disable=SC2016
        "$PATCHELF" --set-rpath '$ORIGIN:$ORIGIN/..' "$elf" 2>/dev/null || true
    fi
done

echo "==> Writing Mesa 3D runtime archive ..."
tar -cjf "$RUNTIME_DIR/mesa3d_libs.tar.bz2" -C "$MESA_STAGE" \
    --owner=0 --group=0 --numeric-owner \
    ./lib64 ./share

echo "==> Done:"
echo "  $RUNTIME_DIR/wezterm.tar.bz2"
echo "  $RUNTIME_DIR/mesa3d_libs.tar.bz2"
echo ""
echo "Run ./build/strip-all-elf-binaries before committing."
