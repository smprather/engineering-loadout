#!/usr/bin/env bash
# Build the cicwave wheel + bundle its PyQt6 dependency wheels for EL8 / Python 3.14.
#
# cicwave (github.com/wulffern/cicwave) is a pure-Python PyQtGraph waveform
# viewer that imports PySide6. PySide6 has NO wheel that is both EL8-compatible
# (glibc 2.28) AND Python-3.14-capable: 6.9.x is manylinux_2_28 but caps at
# python<3.14; 6.10+ added 3.14 but jumped to manylinux_2_34 (glibc 2.34,
# RHEL9+). PyQt6, by contrast, ships an abi3 cp39 binding + a manylinux_2_28
# Qt6 (libQt6Core floor GLIBC_2.28) + a cp314 sip -- all EL8 + 3.14.
#
# So we carry a small fork: 0001-port-pyside6-to-pyqt6.patch rewrites the
# PySide6 imports to PyQt6, aliases pyqtSignal->Signal, scopes every enum to
# PyQt6's strict form (Qt.AlignCenter -> Qt.AlignmentFlag.AlignCenter, ...),
# fixes the one dynamic getattr(QPalette, role) -> getattr(QPalette.ColorRole,
# role), and swaps the pyproject dependency PySide6 -> PyQt6.
#
# This script clones the stable tag, applies the patch, `uv build`s the wheel,
# downloads the PyQt6 + matplotlib dependency closure as EL8/3.14 wheels, and
# chunks any wheel over the GitHub-safe size. numpy/pandas/click/pyyaml and
# other already-bundled shared wheels are reused from payload/<platform>/wheels.
#
# Usage:
#   build/build-cicwave.sh --tag 0.5.2
#   build/build-cicwave.sh --tag 0.5.2 --source /path/to/checkout

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLATFORM="el8.x86_64.glibc2p28"
WHEELS_DIR="$REPO/payload/$PLATFORM/wheels"
PATCH="$REPO/build/cicwave/0001-port-pyside6-to-pyqt6.patch"
CLONE_URL="https://github.com/wulffern/cicwave.git"
PYVER="3.14"
PLAT_TAG="manylinux_2_28_x86_64"
CHUNK_BYTES=$((40 * 1024 * 1024))   # 40 MiB -> stays under GitHub's 50 MB warn

# cicwave's own PyQt6 closure NOT already bundled as shared wheels. numpy,
# pandas, click, pyyaml, packaging, python_dateutil, six are reused from the
# existing bundle (added by other python-tools) and intentionally NOT re-fetched.
DEP_SPECS=(
  "PyQt6==6.9.1" "PyQt6-Qt6==6.9.2" "PyQt6-sip" pyqtgraph PyOpenGL
  matplotlib contourpy cycler fonttools kiwisolver pillow pyparsing colorama
)

tag=""
source_dir=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --tag) shift; [ "$#" -gt 0 ] || { echo "missing value for --tag" >&2; exit 2; }; tag="$1" ;;
        --source) shift; [ "$#" -gt 0 ] || { echo "missing value for --source" >&2; exit 2; }; source_dir="$1" ;;
        -h|--help) sed -n '2,/^$/p' "$0"; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done
[ -n "$tag" ] || { echo "ERROR: --tag X.Y.Z is required (stable release tag)" >&2; exit 2; }

need() { command -v "$1" >/dev/null 2>&1 || { echo "missing required command: $1" >&2; exit 1; }; }
need git; need uv; need pip3.14; need split
[ -r "$PATCH" ] || { echo "ERROR: patch not found: $PATCH" >&2; exit 1; }

workdir="$(mktemp -d "${TMPDIR:-/tmp}/cicwave-build.XXXXXX")"
trap 'rm -rf "$workdir"' EXIT

if [ -n "$source_dir" ]; then
    src="$(cd "$source_dir" && pwd)"
else
    src="$workdir/src"
    git clone --depth 1 --branch "$tag" "$CLONE_URL" "$src"
    echo "Applying PyQt6 port patch..."
    git -C "$src" apply "$PATCH"
fi

echo "Building cicwave $tag wheel via uv..."
mkdir -p "$WHEELS_DIR"
# Drop any prior cicwave wheel so a version bump does not leave a stale one.
rm -f "$WHEELS_DIR"/cicwave-*.whl
( cd "$src" && uv build --wheel --out-dir "$workdir/dist" )
cp "$workdir/dist"/cicwave-*.whl "$WHEELS_DIR"/
echo "  -> $(basename "$(ls "$WHEELS_DIR"/cicwave-*.whl)")"

echo "Downloading PyQt6 dependency closure (EL8 / cp$PYVER wheels)..."
# sip is a cp314-specific (non-abi3) wheel published only for older manylinux;
# allow the broader platform set so pip finds it alongside the 2_28 Qt wheels.
PIP_REQUIRE_VIRTUALENV=0 pip3.14 download "${DEP_SPECS[@]}" \
    --platform "$PLAT_TAG" --platform manylinux2014_x86_64 --platform manylinux_2_5_x86_64 --platform any \
    --python-version "$PYVER" --only-binary :all: --no-deps -d "$workdir/deps"
cp "$workdir/deps"/*.whl "$WHEELS_DIR"/

echo "Chunking wheels over $((CHUNK_BYTES / 1024 / 1024)) MiB (installer rejoins .whl.part-NNN)..."
for w in "$WHEELS_DIR"/*.whl; do
    sz=$(stat -c %s "$w")
    if [ "$sz" -gt "$CHUNK_BYTES" ]; then
        echo "  splitting $(basename "$w") ($((sz / 1024 / 1024)) MiB)"
        rm -f "$w".part-*
        split -d -a 3 -b "$CHUNK_BYTES" "$w" "$w".part-
        rm -f "$w"
    fi
done

echo
echo "Done. Next:"
echo "  python3 -m json.tool payload/packages.json >/dev/null   # if you edited the registry"
echo "  ./loadout completion bash > envs/bash/global/completions/loadout.bash"
echo "  ./loadout install cicwave --dest-dir /tmp/t --no-backup   # offline end-to-end smoke"
echo "  git add payload/$PLATFORM/wheels build/cicwave build/build-cicwave.sh"
