#!/usr/bin/env bash
# Build vcd-toggle-profiler (C++ implementation) for el8.x86_64.glibc2p28.
#
# The upstream CMake Release profile enables -march=native/-mtune=native. Do
# not use that for the loadout artifact. Build with EL8 system GCC 8 instead so
# the resulting libstdc++ symbol floor stays at GLIBCXX_3.4.21, then package a
# relocatable runtime archive:
#
#   bin/vcd-toggle-profiler                         wrapper
#   lib/vcd-toggle-profiler/vcd-toggle-profiler.bin real C++ binary
#   share/vcd-toggle-profiler/uplot/*               runtime HTML assets
#
# Usage:
#   build/build-vcd-toggle-profiler.sh --rev main
#   build/build-vcd-toggle-profiler.sh --source /tmp/vcd-toggle-profiler

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLATFORM="el8.x86_64.glibc2p28"
RUNTIME_DIR="$REPO/payload/$PLATFORM/runtime"
CLONE_URL="https://github.com/smprather/vcd-toggle-profiler.git"

rev="main"
source_dir=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --rev)
            shift
            [ "$#" -gt 0 ] || { echo "missing value for --rev" >&2; exit 2; }
            rev="$1"
            ;;
        --source)
            shift
            [ "$#" -gt 0 ] || { echo "missing value for --source" >&2; exit 2; }
            source_dir="$1"
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

need git
need /usr/bin/g++
need tar
need bzip2

workdir="$(mktemp -d "${TMPDIR:-/tmp}/vcd-toggle-profiler-build.XXXXXX")"
trap 'rm -rf "$workdir"' EXIT

if [ -n "$source_dir" ]; then
    src="$(cd "$source_dir" && pwd)"
else
    src="$workdir/src"
    git clone --filter=blob:none "$CLONE_URL" "$src"
    git -C "$src" checkout "$rev"
fi

version="$(git -C "$src" describe --tags --always --dirty)"
echo "Building vcd-toggle-profiler $version from $src"

bin="$workdir/vcd-toggle-profiler.bin"
/usr/bin/g++ \
    -std=c++17 -O2 -DNDEBUG -Wall -Wextra \
    -I"$src/third_party/CLI11/include" \
    "$src/src/main.cpp" \
    -lstdc++fs \
    -o "$bin"

"$bin" --help >/dev/null

stage="$workdir/stage"
mkdir -p \
    "$stage/bin" \
    "$stage/lib/vcd-toggle-profiler" \
    "$stage/share/vcd-toggle-profiler/uplot" \
    "$stage/share/licenses/vcd-toggle-profiler"

cp "$bin" "$stage/lib/vcd-toggle-profiler/vcd-toggle-profiler.bin"
cp "$src/third_party/uplot/uPlot.iife.js" "$stage/share/vcd-toggle-profiler/uplot/"
cp "$src/third_party/uplot/uPlot.min.css" "$stage/share/vcd-toggle-profiler/uplot/"
cp "$src/LICENSE" "$stage/share/licenses/vcd-toggle-profiler/LICENSE"
cp "$src/third_party/uplot/LICENSE-uPlot.txt" "$stage/share/licenses/vcd-toggle-profiler/"
cp "$src/third_party/CLI11/LICENSE-CLI11.txt" "$stage/share/licenses/vcd-toggle-profiler/"

cat >"$stage/bin/vcd-toggle-profiler" <<'EOF'
#!/bin/sh
set -eu

_bin_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
_prefix=$(CDPATH= cd -- "$_bin_dir/.." && pwd -P)
_real="$_prefix/lib/vcd-toggle-profiler/vcd-toggle-profiler.bin"
_js="$_prefix/share/vcd-toggle-profiler/uplot/uPlot.iife.js"
_css="$_prefix/share/vcd-toggle-profiler/uplot/uPlot.min.css"

_has_js=0
_has_css=0
for _arg do
    case $_arg in
        --uplot-js|--uplot-js=*) _has_js=1 ;;
        --uplot-css|--uplot-css=*) _has_css=1 ;;
    esac
done

if [ "$_has_js" -eq 0 ]; then
    set -- --uplot-js "$_js" "$@"
fi
if [ "$_has_css" -eq 0 ]; then
    set -- --uplot-css "$_css" "$@"
fi

exec "$_real" "$@"
EOF
chmod 755 "$stage/bin/vcd-toggle-profiler" "$stage/lib/vcd-toggle-profiler/vcd-toggle-profiler.bin"

mkdir -p "$RUNTIME_DIR"
tar -C "$stage" -cjf "$RUNTIME_DIR/vcd-toggle-profiler.tar.bz2" .
echo "Wrote $RUNTIME_DIR/vcd-toggle-profiler.tar.bz2"

python3 - "$REPO/payload/packages.json" "$version" <<'PY'
import json
import sys

path, version = sys.argv[1], sys.argv[2]
with open(path, encoding="utf-8") as fh:
    data = json.load(fh)
data["packages"]["vcd-toggle-profiler"]["version"] = version
with open(path, "w", encoding="utf-8") as fh:
    json.dump(data, fh, indent=2, ensure_ascii=True)
    fh.write("\n")
print(f"packages.json: vcd-toggle-profiler version -> {version}")
PY

"$REPO/build/strip-all-elf-binaries"
ldd "$bin"
