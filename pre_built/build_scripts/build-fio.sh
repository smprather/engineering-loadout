#!/usr/bin/env bash
# Build fio (Flexible I/O tester) from source for el8.x86_64.glibc2p28.
#
# fio is a storage/filesystem performance benchmark. We build it with the
# libaio ioengine and zlib (iolog compression) but DISABLE the http ioengine,
# which would otherwise drag in libcurl's whole krb5/ldap/brotli/nghttp2
# closure -- heavy deps not guaranteed on a minimal farm node and useless for a
# filesystem performance checker.
#
# Resulting non-glibc NEEDED libs (both bundled):
#   libaio.so.1   -> lib64/libaio.so.1.bz2  (copied from EL8 libaio RPM, RPATH $ORIGIN)
#   libz.so.1     -> already bundled in lib64/
# Everything else (librt/libpthread/libm/libmvec/libdl/libc) is glibc 2.28 --
# present on every EL8 target, never bundled.
#
# Policy: always build from a stable tagged release.
#   Tags: https://github.com/axboe/fio/releases
#
# Prereqs (build box): gcc-toolset-14, libaio-devel, zlib-devel.
#   sudo dnf install -y libaio-devel zlib-devel
#
# Usage (run from any directory):
#   /path/to/build-fio.sh --tag fio-3.42

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BIN_DIR="$REPO/pre_built/el8.x86_64.glibc2p28/bin"
LIB_DIR="$REPO/pre_built/el8.x86_64.glibc2p28/lib64"
CLONE_URL="https://github.com/axboe/fio.git"
RPATH_BIN='$ORIGIN/../lib64:$ORIGIN/../lib'

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

[ -n "$tag" ] || { echo "ERROR: --tag fio-X.Y required (see https://github.com/axboe/fio/releases)" >&2; exit 2; }

# Toolchain
. /opt/rh/gcc-toolset-14/enable 2>/dev/null || true

PATCHELF="$HOME/.local/bin/patchelf"
command -v "$PATCHELF" >/dev/null 2>&1 || PATCHELF="$(command -v patchelf)"
[ -n "$PATCHELF" ] || { echo "ERROR: patchelf not found" >&2; exit 1; }

workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT

echo "Cloning ${CLONE_URL} @ ${tag}..."
git clone --depth 1 --branch "${tag}" "${CLONE_URL}" "${workdir}/fio"
cd "${workdir}/fio"

# --disable-native: no -march=native (portability across farm CPUs)
# --disable-http:   drop libcurl/krb5/ldap closure
./configure --disable-native --disable-http
make -j"$(nproc)"
echo "Built: $(./fio --version)"

# --- Package fio binary: strip -> patchelf -> bzip2 ---
cp fio "${workdir}/fio_tmp"
/usr/bin/strip "${workdir}/fio_tmp"
"$PATCHELF" --set-rpath "$RPATH_BIN" "${workdir}/fio_tmp"
rm -f "${workdir}/fio_tmp.bz2"; bzip2 -kf "${workdir}/fio_tmp"
cp "${workdir}/fio_tmp.bz2" "${BIN_DIR}/fio.bz2"; chmod 644 "${BIN_DIR}/fio.bz2"
echo "Installed: ${BIN_DIR}/fio.bz2"

# --- Bundle libaio.so.1 (from EL8 libaio RPM) ---
src_libaio=$(readlink -f /usr/lib64/libaio.so.1)
[ -f "$src_libaio" ] || { echo "ERROR: /usr/lib64/libaio.so.1 missing (dnf install libaio)" >&2; exit 1; }
cp "$src_libaio" "${workdir}/libaio_tmp"
/usr/bin/strip "${workdir}/libaio_tmp"
"$PATCHELF" --set-soname libaio.so.1 "${workdir}/libaio_tmp"
"$PATCHELF" --set-rpath '$ORIGIN' "${workdir}/libaio_tmp"
rm -f "${workdir}/libaio_tmp.bz2"; bzip2 -kf "${workdir}/libaio_tmp"
cp "${workdir}/libaio_tmp.bz2" "${LIB_DIR}/libaio.so.1.bz2"; chmod 644 "${LIB_DIR}/libaio.so.1.bz2"
echo "Installed: ${LIB_DIR}/libaio.so.1.bz2"

echo
echo "Done. Now run: ./strip_all_elf_binaries  (skips both via RPATH guard)"
