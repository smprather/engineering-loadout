#!/bin/sh
# Repack a minimal offline Rust toolchain (rustc + cargo + std) into
# payload/<platform>/runtime/rust.tar.bz2 for the el8.x86_64.glibc2p28 target.
#
# Source: the rustup-installed stable toolchain on the build machine. rustup
# fetches the official static.rust-lang.org binaries, so the repacked bytes are
# the upstream stable release -- this script just trims docs/clippy/rustfmt/src
# and keeps the load-bearing subset:
#
#   bin/rustc, bin/cargo
#   lib/librustc_driver-*.so, lib/libLLVM-*.so
#   lib/rustlib/<triple>/            (std .rlibs + libstd dylib + rust-lld)
#
# rustc/cargo already carry RPATH $ORIGIN/../lib, and rustc derives its sysroot
# from its own path (bin/.. -> install prefix), so the archive is relocatable:
# it extracts straight into ~/.local (or a --dest-dir local/) and runs with no
# patchelf. A system C toolchain (gcc/cc + ld) is still required at compile time
# -- rustc shells out to `cc` for the final link, exactly like any rust install.
#
# The archive is large (~360 MB extracted); this script pre-splits it into
# rust.tar.bz2.part-NNN so no committed file trips GitHub's 50 MB warning. The
# installer's runtime loop rejoins the chunks via _bz2.resolve(). Because the
# chunks live under payload/, "rust.tar.bz2" is added to
# strip-all-elf-binaries' NOSTRIP list so the strip pass never re-tars and
# strips the rustc/LLVM shared objects (which would corrupt the compiler).
#
# Prerequisites on the build machine (EL8):
#   - rustup with a stable toolchain installed (rustup toolchain install stable)
#   - patchelf, tar, bzip2, split
#
# Usage (run from any directory):
#   /path/to/build-rust.sh --tag 1.96.0          # must match installed stable

set -eu

REPO="$(cd "$(dirname "$0")/.." && pwd)"
RUNTIME_DIR="$REPO/payload/el8.x86_64.glibc2p28/runtime"
OUT_ARCHIVE="$RUNTIME_DIR/rust.tar.bz2"
TRIPLE="x86_64-unknown-linux-gnu"
CHUNK_BYTES=$((40 * 1024 * 1024))

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
    echo "ERROR: --tag is required, e.g. --tag 1.96.0 (must match installed stable)." >&2
    echo "Policy: ship stable releases only. https://github.com/rust-lang/rust/releases" >&2
    exit 1
fi

need() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "missing required command: $1 -- see this script's header" >&2
        exit 1
    }
}
need rustc
need cargo
need patchelf
need tar
need bzip2
need split

SYS="$(rustc --print sysroot)"
have_ver="$(rustc --version | awk '{print $2}')"
if [ "$have_ver" != "$tag" ]; then
    echo "ERROR: active rustc is $have_ver but --tag is $tag." >&2
    echo "Run 'rustup default $tag' (or 'rustup toolchain install $tag') first." >&2
    exit 1
fi

echo "Toolchain: $SYS (rustc $have_ver)"

STAGE="$(mktemp -d "${TMPDIR:-/tmp}/rust-stage.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT INT TERM
mkdir -p "$STAGE/bin" "$STAGE/lib/rustlib"

cp -p "$SYS/bin/rustc" "$SYS/bin/cargo" "$STAGE/bin/"
# rustc driver + LLVM live in lib/ and are found via RPATH $ORIGIN/../lib.
# NOTE: the real LLVM object is named libLLVM.so.22.1-rust-<ver> (no trailing
# .so) plus a tiny libLLVM-NN-rust-<ver>.so ld stub -- copy every libLLVM*.
cp -p "$SYS"/lib/librustc_driver-*.so "$STAGE/lib/"
cp -p "$SYS"/lib/libLLVM* "$STAGE/lib/"
# Full per-target rustlib (std rlibs + libstd dylib + rust-lld + crt objects).
cp -a "$SYS/lib/rustlib/$TRIPLE" "$STAGE/lib/rustlib/"
# rustup bookkeeping / std source are not needed for compiling.
rm -rf "$STAGE/lib/rustlib/$TRIPLE/lib/.cargo-ok" 2>/dev/null || true

stage_size="$(du -sh "$STAGE" | cut -f1)"
echo "Staged subset: $stage_size"

# Smoke the staged tree in isolation before packing: a relocated prefix must
# compile a trivial crate with no reference back to $SYS.
echo "Smoke-testing staged toolchain..."
SMOKE="$(mktemp -d "${TMPDIR:-/tmp}/rust-smoke.XXXXXX")"
(
    PATH="$STAGE/bin:/usr/bin:/bin"
    export PATH
    cd "$SMOKE"
    "$STAGE/bin/rustc" --version
    printf 'fn main(){println!("ok");}\n' > m.rs
    "$STAGE/bin/rustc" m.rs -o m
    ./m | grep -q ok
)
rm -rf "$SMOKE"
echo "  staged rustc compiles + runs a binary."

mkdir -p "$RUNTIME_DIR"
rm -f "$OUT_ARCHIVE" "$OUT_ARCHIVE".part-*
echo "Packing -> $OUT_ARCHIVE ..."
tar -cjf "$OUT_ARCHIVE" -C "$STAGE" ./bin ./lib
packed_bytes="$(wc -c < "$OUT_ARCHIVE" | tr -d ' ')"
echo "  packed: $(du -sh "$OUT_ARCHIVE" | cut -f1)"

if [ "$packed_bytes" -gt "$CHUNK_BYTES" ]; then
    echo "  splitting into .part-NNN chunks (> $((CHUNK_BYTES / 1024 / 1024)) MiB)..."
    split -d -a 3 -b "$CHUNK_BYTES" "$OUT_ARCHIVE" "$OUT_ARCHIVE".part-
    rm -f "$OUT_ARCHIVE"
    nparts="$(ls "$OUT_ARCHIVE".part-* | wc -l | tr -d ' ')"
    echo "  -> $nparts chunks"
fi

echo ""
echo "Done. 'rust.tar.bz2' is in strip-all-elf-binaries' NOSTRIP list, so do NOT"
echo "expect ./build/strip-all-elf-binaries to touch it. packages.json carries the"
echo "'rust' runtime package (sentinel bin/cargo, install_to ~/.local)."
echo "Install with:  ./loadout install rust   (or @rust for the crate store too)"
