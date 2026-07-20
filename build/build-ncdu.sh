#!/usr/bin/env bash
# Build ncdu (Zig v2) from source for el8.x86_64.glibc2p28.
#
# ncdu v2 is a full rewrite in Zig; v1 (C) is unmaintained.
# Binary is fully self-contained -- no bundled libs needed.
#
# Policy: always build from a stable tagged release. See tags at:
#   https://code.blicky.net/yorhel/ncdu/tags
#
# Source repo:
#   https://code.blicky.net/yorhel/ncdu.git
#
# Zig toolchain is downloaded automatically (ziglang.org).
#
# Usage (run from any directory):
#   /path/to/build-ncdu.sh --tag v2.9.2

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="$REPO/payload/el8.x86_64.glibc2p28/bin"
CLONE_URL="https://code.blicky.net/yorhel/ncdu.git"

zig_version="${ZIG_VERSION:-0.15.2}"
zig_dir="${ZIG_DIR:-/tmp/zig-x86_64-linux-${zig_version}}"
zig_tar="${ZIG_TAR:-/tmp/zig-x86_64-linux-${zig_version}.tar.xz}"
zig_url="${ZIG_URL:-https://ziglang.org/download/${zig_version}/zig-x86_64-linux-${zig_version}.tar.xz}"
zig_cache="${ZIG_GLOBAL_CACHE_DIR:-/tmp/zig-global-cache-ncdu-${zig_version//./}}"

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

[ -n "$tag" ] || { echo "ERROR: --tag vX.Y.Z required (see https://code.blicky.net/yorhel/ncdu/tags)" >&2; exit 2; }

# Ensure Zig toolchain
if [[ ! -x "${zig_dir}/zig" ]]; then
    if [[ ! -f "${zig_tar}" ]]; then
        echo "Downloading Zig ${zig_version}..."
        curl -L "${zig_url}" -o "${zig_tar}"
    fi
    tar -xf "${zig_tar}" -C "$(dirname "${zig_dir}")"
fi

# Clone and checkout tag
workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT
echo "Cloning ${CLONE_URL} @ ${tag}..."
git clone --depth 1 --branch "${tag}" "${CLONE_URL}" "${workdir}/ncdu"
cd "${workdir}/ncdu"

# Build
ZIG_GLOBAL_CACHE_DIR="${zig_cache}" "${zig_dir}/zig" build --release=fast -Dstrip
echo "Zig version: $("${zig_dir}/zig" version)"
echo "ncdu version: $(zig-out/bin/ncdu --version)"

# Install
cp zig-out/bin/ncdu "${BIN_DIR}/ncdu"
bzip2 -kf "${BIN_DIR}/ncdu"
rm "${BIN_DIR}/ncdu"
echo "Installed: ${BIN_DIR}/ncdu.bz2"
