#!/bin/sh
# Build `models` (TUI/CLI for browsing AI models, benchmarks, coding agents) from
# source for el8.x86_64.glibc2p28.
#
# models (crate `modelsdev`) is Rust. The ONLY official linux prebuilt is
# `*-linux-gnu` built on a modern host -- it needs GLIBC_2.39 and aborts on EL8
# (glibc 2.28):
#   models: /lib64/libc.so.6: version `GLIBC_2.29' not found
# Building here yields a native glibc-2.28 binary (max GLIBC symbol 2.28). The
# crate also defines a second `transform` bin (an internal data helper) -- we
# build and ship ONLY `models` via `--bin models`.
#
# Runtime libs: only glibc + libgcc_s (all EL8 base). The TUI fetches model data
# from models.dev over HTTPS at runtime (reqwest/rustls, no openssl NEEDED), so
# it needs network for live data but starts fine offline.
#
# Policy: always build from a stable tagged release. See tags at:
#   https://github.com/reyamira/models/releases
#
# Prerequisites: rustc + cargo (tested with 1.95), gcc-toolset-14 (optional),
# patchelf at ~/.local/bin/patchelf, network for crates.io (outside the sandbox).
#
# Usage (run from any directory):
#   /path/to/build-models.sh --tag v0.12.3

set -eu

REPO="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib.sh
. "$REPO/build/lib.sh"
BIN_DIR="$LOADOUT_BIN_DIR"
CLONE_URL="https://github.com/reyamira/models.git"

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

loadout_require_tag "$tag" "$0" "https://github.com/reyamira/models/releases" "v0.12.3"
loadout_enable_gcc_toolset
loadout_require_cmds cargo git

SRCDIR="/tmp/models-src-${tag}"
rm -rf "$SRCDIR"
git clone --depth 1 --branch "$tag" "$CLONE_URL" "$SRCDIR"
cd "$SRCDIR"

echo "Building models (release, --bin models) ..."
cargo build --release --bin models

BIN="$SRCDIR/target/release/models"
[ -f "$BIN" ] || { echo "build did not produce $BIN" >&2; exit 1; }
echo "Build complete: $("$BIN" --version 2>&1 | head -1)"

loadout_package_bin "$BIN" models
loadout_stamp_version models "${tag#v}"

echo "Running strip-all-elf-binaries ..."
"$REPO/build/strip-all-elf-binaries"

loadout_report_max_glibc "$BIN"

echo ""
echo "Installed: $BIN_DIR/models.bz2"
