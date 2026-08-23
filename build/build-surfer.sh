#!/usr/bin/env bash
# Build Surfer (waveform viewer) for el8.x86_64.glibc2p28.
#
# Surfer is a Rust egui/glow (OpenGL) GUI. We build the latest STABLE tag from
# source on EL8 (glibc 2.28) -- upstream prebuilts target newer glibc. The
# release profile has no -march/target-cpu=native, so the artifact is portable
# across farm CPUs. Output is a bin-package pair (like gvim):
#
#   payload/<platform>/bin/surfer.bz2       POSIX-sh wrapper (Mesa/GLVND env)
#   payload/<platform>/bin/surfer.bin.bz2   real stripped ELF, RPATH $ORIGIN/../lib64
#
# Runtime libs come from gui_libs (X11/Wayland/xkbcommon) + mesa3d_libs (Mesa
# vendor EGL/GBM/DRI). GLVND dispatchers (libGL.so.1) stay host-provided.
#
# Usage:
#   build/build-surfer.sh --tag v0.7.0
#   build/build-surfer.sh --tag v0.7.0 --source /path/to/checkout
#
# After running: ./build/strip-all-elf-binaries && \
#   ./loadout completion bash > envs/bash/global/completions/loadout.bash

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLATFORM="el8.x86_64.glibc2p28"
BIN_DIR="$REPO/payload/$PLATFORM/bin"
CLONE_URL="https://gitlab.com/surfer-project/surfer.git"
GCC_ENABLE="/opt/rh/gcc-toolset-14/enable"

tag=""
source_dir=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --tag)
            shift; [ "$#" -gt 0 ] || { echo "missing value for --tag" >&2; exit 2; }
            tag="$1" ;;
        --source)
            shift; [ "$#" -gt 0 ] || { echo "missing value for --source" >&2; exit 2; }
            source_dir="$1" ;;
        -h|--help)
            sed -n '2,/^$/p' "$0"; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done

# Stable-release policy: a tag is mandatory and must look like a release tag.
[ -n "$tag" ] || { echo "ERROR: --tag vX.Y.Z is required (stable release tag)" >&2; exit 2; }
case "$tag" in
    v[0-9]*) : ;;
    *) echo "ERROR: --tag must be a stable release tag like v0.7.0 (got '$tag')" >&2; exit 2 ;;
esac

need() { command -v "$1" >/dev/null 2>&1 || { echo "missing required command: $1" >&2; exit 1; }; }
need git
need cargo
need patchelf
need strip
need bzip2

# Modern C toolchain: f128's __float128 shim wants quadmath; glibc floor stays
# at the system 2.28 regardless of gcc version.
[ -r "$GCC_ENABLE" ] && . "$GCC_ENABLE"

workdir="$(mktemp -d "${TMPDIR:-/tmp}/surfer-build.XXXXXX")"
trap 'rm -rf "$workdir"' EXIT

if [ -n "$source_dir" ]; then
    src="$(cd "$source_dir" && pwd)"
else
    src="$workdir/src"
    # v0.7.0 vendors f128 + instruction-decoder as git submodules (path deps);
    # they must be checked out or the workspace build fails to resolve f128.
    git clone --depth 1 --branch "$tag" --recurse-submodules --shallow-submodules \
        "$CLONE_URL" "$src"
fi

echo "Building surfer $tag from $src"

# Fresh CARGO_HOME: keep the build isolated from any loadout-influenced cargo
# resolution. Historically env-cargo's config redirected crates-io to the
# offline registry-store (curated subset only); since 2026-08-22 the config is
# stock but the shell wrapper injects that same replacement when crates.io is
# unreachable. Surfer's pinned deps need real crates.io, so isolate the
# registry/config here either way.
export CARGO_HOME="$workdir/cargo-home"
mkdir -p "$CARGO_HOME"

( cd "$src" && cargo build --release -p surfer )

real="$src/target/release/surfer"
[ -x "$real" ] || { echo "ERROR: build produced no $real" >&2; exit 1; }

# Portability gate: must run on EL8 glibc 2.28.
floor="$(readelf -V "$real" 2>/dev/null | grep -oE 'GLIBC_[0-9]+\.[0-9]+' | sort -V | tail -1)"
echo "glibc symbol floor: ${floor:-none}"
case "$floor" in
    GLIBC_2.2[0-9]|GLIBC_2.1*|GLIBC_2.[0-9]|"") : ;;
    *) echo "ERROR: $real needs $floor > GLIBC_2.28; not EL8-portable" >&2; exit 1 ;;
esac

stage="$workdir/stage"
mkdir -p "$stage"
cp "$real" "$stage/surfer.bin"
strip "$stage/surfer.bin"
# Mesa vendor libs live one level up from bin/ at <prefix>/lib64.
patchelf --set-rpath '$ORIGIN/../lib64' "$stage/surfer.bin"

# Wrapper (single source of truth; mirrors wezterm's Mesa/GLVND env block).
cat > "$stage/surfer" <<'WRAP'
#!/bin/sh
#
# Surfer launcher (loadout). egui/glow (OpenGL) GUI. On headless farm nodes the
# GL stack is served by bundled Mesa userspace (mesa3d_libs) + GUI client libs
# (gui_libs); the real ELF is the sibling surfer.bin. GLVND dispatchers
# (libGL.so.1 ...) stay host-provided -- only the Mesa vendor side is bundled.

bin_dir=$(CDPATH= cd "$(dirname "$0")" && pwd -P) || exit 1
prefix=$(CDPATH= cd "$bin_dir/.." && pwd -P) || exit 1

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

exec "$bin_dir/surfer.bin" "$@"
WRAP
chmod +x "$stage/surfer"

mkdir -p "$BIN_DIR"
bzip2 -kf "$stage/surfer.bin"
bzip2 -kf "$stage/surfer"
cp "$stage/surfer.bin.bz2" "$BIN_DIR/surfer.bin.bz2"
cp "$stage/surfer.bz2"     "$BIN_DIR/surfer.bz2"
chmod 644 "$BIN_DIR/surfer.bin.bz2" "$BIN_DIR/surfer.bz2"

echo "Staged:"
echo "  $BIN_DIR/surfer.bz2       (wrapper)"
echo "  $BIN_DIR/surfer.bin.bz2   (ELF $floor)"
echo
echo "Next:"
echo "  ./build/strip-all-elf-binaries"
echo "  ./loadout completion bash > envs/bash/global/completions/loadout.bash"
echo "  git add payload/$PLATFORM/bin/surfer.bz2 payload/$PLATFORM/bin/surfer.bin.bz2 .strip-manifest"
