#!/bin/sh
# Shanghai-bundle WezTerm plus the Mesa 3D runtime from the on-system install
# for el8.x86_64.glibc2p28.
#
# This is intentionally a "sample app" bundle for the Mesa runtime:
#
#   pre_built/<platform>/runtime/wezterm.tar.bz2
#     ./bin/wezterm                 relocatable wrapper
#     ./lib/wezterm/wezterm.bin     copied from /usr/bin/wezterm
#     ./share/applications/...      desktop file, when installed
#     ./share/metainfo/...          appstream metadata, when installed
#     ./share/zsh/site-functions/_wezterm, when installed
#
#   pre_built/<platform>/runtime/mesa3d_libs.tar.bz2
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
#   ./pre_built/build_scripts/build-wezterm.sh --tag 20260618_095146_c10636f3

set -eu

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
PLATFORM="el8.x86_64.glibc2p28"
RUNTIME_DIR="$REPO/pre_built/$PLATFORM/runtime"
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
[ -x "$WEZTERM_BIN" ] || {
    echo "ERROR: $WEZTERM_BIN not found or not executable." >&2
    exit 1
}

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

STAGE=$(mktemp -d /tmp/wezterm-stage-XXXXXX)
MESA_STAGE=$(mktemp -d /tmp/mesa3d-stage-XXXXXX)
trap 'rm -rf "$STAGE" "$MESA_STAGE"' EXIT

mkdir -p "$RUNTIME_DIR"

echo "==> Staging WezTerm $TAG from $WEZTERM_BIN ..."
mkdir -p "$STAGE/bin" "$STAGE/lib/wezterm" "$STAGE/share/applications" \
    "$STAGE/share/metainfo" "$STAGE/share/zsh/site-functions"

cp "$WEZTERM_BIN" "$STAGE/lib/wezterm/wezterm.bin"
strip "$STAGE/lib/wezterm/wezterm.bin" 2>/dev/null || true
# shellcheck disable=SC2016
"$PATCHELF" --set-rpath '$ORIGIN/../../lib64:$ORIGIN' "$STAGE/lib/wezterm/wezterm.bin"

if [ -f /usr/share/applications/org.wezfurlong.wezterm.desktop ]; then
    cp /usr/share/applications/org.wezfurlong.wezterm.desktop "$STAGE/share/applications/"
fi
if [ -f /usr/share/metainfo/org.wezfurlong.wezterm.appdata.xml ]; then
    cp /usr/share/metainfo/org.wezfurlong.wezterm.appdata.xml "$STAGE/share/metainfo/"
fi
if [ -f /usr/share/zsh/site-functions/_wezterm ]; then
    cp /usr/share/zsh/site-functions/_wezterm "$STAGE/share/zsh/site-functions/"
fi

cat >"$STAGE/bin/wezterm" <<'EOF'
#!/bin/sh
# Wrapper for the engineering-loadout WezTerm shanghai bundle.
bin_dir=$(CDPATH= cd "$(dirname "$0")" && pwd -P) || exit 1
prefix=$(CDPATH= cd "$bin_dir/.." && pwd -P) || exit 1
real_wezterm="$prefix/lib/wezterm/wezterm.bin"

mesa_libdir="$prefix/lib64"
if [ -d "$mesa_libdir" ]; then
  export LD_LIBRARY_PATH="$mesa_libdir${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
  if [ -d "$mesa_libdir/dri" ]; then
    export LIBGL_DRIVERS_PATH="$mesa_libdir/dri${LIBGL_DRIVERS_PATH:+:$LIBGL_DRIVERS_PATH}"
  fi
fi
if [ -d "$prefix/share/glvnd/egl_vendor.d" ]; then
  export __EGL_VENDOR_LIBRARY_DIRS="$prefix/share/glvnd/egl_vendor.d${__EGL_VENDOR_LIBRARY_DIRS:+:$__EGL_VENDOR_LIBRARY_DIRS}"
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
    portal_setting_ok && return 0
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
echo "Run ./strip_all_elf_binaries before committing."
