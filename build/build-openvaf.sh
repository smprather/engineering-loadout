#!/bin/sh
# Build OpenVAF (Verilog-A compiler) from source for el8.x86_64.glibc2p28.
#
# OpenVAF is a Rust project that compiles Verilog-A files to OSDI shared
# objects for circuit simulators. It requires LLVM at build time (statically
# linked, no runtime LLVM dep) and produces a single self-contained binary
# with only glibc + libstdc++ + libgcc_s NEEDED.
#
# OpenVAF 23.5.0 targets LLVM 13-15. LLVM 16+ removed the legacy PassManagerBuilder
# C API that OpenVAF's wrapper code uses, so we build against upstream's own
# prebuilt LLVM 15.0.7 (built on CentOS 7, runs anywhere). The build machine's
# /usr/local LLVM is 23 -- too new.
#
# Two patches are required:
#   1. openvaf/llvm/build.rs: strip non-numeric suffix from the LLVM version
#      string (our prebuilt LLVM reports "15.0.7" cleanly, but the build box
#      /usr/local LLVM reports "23.0.0git" which fails the version parser).
#      This patch makes the parser robust so either LLVM works.
#   2. openvaf/osdi/stdlib.c: add explicit function declarations under NO_STD.
#      The file compiles with -DNO_STD (no standard headers) but calls strlen,
#      malloc, memcpy, strcmp, realloc, log. Older clang tolerated implicit
#      declarations; clang 15 (from the prebuilt LLVM) in C99 mode rejects them.
#
# Policy: always build from a stable tagged release.
# Prerequisites: cargo 1.64+, zstd (to decompress the prebuilt LLVM tarball).
#
# Usage (run from any directory):
#   ./build/build-openvaf.sh --tag OpenVAF-v23.5.0
#   ./build/build-openvaf.sh --tag OpenVAF-v23.5.0 --reuse-build   # skip cargo build if tree exists

set -eu

REPO="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO/build/lib.sh"

CLONE_URL="https://github.com/pascalkuthe/OpenVAF.git"
LLVM_TARBALL_URL="https://openva.fra1.cdn.digitaloceanspaces.com/llvm-15.0.7-x86_64-unknown-linux-gnu-FULL.tar.zst"
LLVM_DIR="/tmp/llvm-15.0.7-openvaf"

tag=""
reuse_build=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --tag)
            shift
            [ "$#" -gt 0 ] || { echo "missing value for --tag" >&2; exit 2; }
            tag="$1"
            ;;
        --reuse-build) reuse_build=1 ;;
        -h|--help)
            sed -n '2,/^$/p' "$0"
            exit 0
            ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done

loadout_require_tag "$tag" "$0" "https://github.com/pascalkuthe/OpenVAF/releases" "OpenVAF-v23.5.0"
loadout_enable_gcc_toolset
loadout_require_cmds cargo git curl zstd strip readelf file

version="${tag#OpenVAF-v}"

# ── 1. Fetch prebuilt LLVM 15.0.7 ──────────────────────────────────────────
# LLVM 16+ removed PassManagerBuilder.h; OpenVAF 23.5.0 needs LLVM <= 15.
# Upstream provides a CentOS-7-built LLVM 15 tarball that runs on any Linux.

if [ ! -x "$LLVM_DIR/bin/llvm-config" ]; then
    echo "==> Fetching prebuilt LLVM 15.0.7 ..."
    WORK=$(mktemp -d "${TMPDIR:-/tmp}/openvaf-llvm-XXXXXX")
    trap 'rm -rf "$WORK"' EXIT INT TERM
    curl -fL --retry 3 -o "$WORK/llvm.tar.zst" "$LLVM_TARBALL_URL"
    mkdir -p "$LLVM_DIR"
    zstd -d -c --long=31 "$WORK/llvm.tar.zst" | tar xf - -C "$LLVM_DIR"
    # The tarball extracts to ./LLVM/...
    if [ -d "$LLVM_DIR/LLVM" ]; then
        mv "$LLVM_DIR/LLVM"/* "$LLVM_DIR/" && rmdir "$LLVM_DIR/LLVM"
    fi
    rm -rf "$WORK"
    trap - EXIT INT TERM
fi

echo "LLVM: $("$LLVM_DIR/bin/llvm-config" --version)"

# ── 2. Clone OpenVAF ────────────────────────────────────────────────────────

SRCDIR="/tmp/openvaf-src-${tag}"

if [ ! -d "$SRCDIR/.git" ]; then
    echo "==> Cloning $CLONE_URL ..."
    git clone --filter=blob:none "$CLONE_URL" "$SRCDIR"
fi

cd "$SRCDIR"
git fetch --tags
git checkout "$tag"

# ── 3. Apply patches ─────────────────────────────────────────────────────────

# Patch 1: make the LLVM version parser robust to "X.Y.Zgit" suffixes.
# The build box /usr/local LLVM reports "23.0.0git"; the prebuilt LLVM 15
# reports "15.0.7" cleanly, but the patch is belt-and-suspenders.
BUILD_RS="$SRCDIR/openvaf/llvm/build.rs"
if ! grep -q 'take_while.*is_ascii_digit' "$BUILD_RS" 2>/dev/null; then
    echo "==> Patching llvm/build.rs (version parser) ..."
    python3 -c "
import re
with open('$BUILD_RS') as f:
    src = f.read()
old = 'let patch: Result<u32, _> = patch.parse();'
new = \"\"\"let patch: Result<u32, _> = patch.chars().take_while(|c| c.is_ascii_digit()).collect::<String>().parse();\"\"\"
if old not in src:
    raise SystemExit('target string not found in build.rs -- patch may already be applied or upstream changed')
with open('$BUILD_RS', 'w') as f:
    f.write(src.replace(old, new))
print('  patched: version parser now strips non-numeric suffix')
"
fi

# Patch 2: add function declarations under NO_STD in stdlib.c.
STDLIB_C="$SRCDIR/openvaf/osdi/stdlib.c"
if ! grep -q 'extern size_t strlen' "$STDLIB_C" 2>/dev/null; then
    echo "==> Patching osdi/stdlib.c (NO_STD declarations) ..."
    python3 -c "
with open('$STDLIB_C') as f:
    src = f.read()
old = '''#define NULL ((void*)0)
#else'''
new = '''#define NULL ((void*)0)
/* Declarations for functions used below; normally provided by the excluded headers. */
extern size_t strlen(const char *s);
extern void *malloc(size_t size);
extern void *memcpy(void *dst, const void *src, size_t n);
extern int strcmp(const char *s1, const char *s2);
extern void *realloc(void *ptr, size_t size);
extern double log(double x);
#else'''
if old not in src:
    raise SystemExit('target string not found in stdlib.c -- patch may already be applied or upstream changed')
with open('$STDLIB_C', 'w') as f:
    f.write(src.replace(old, new, 1))
print('  patched: NO_STD block now declares strlen/malloc/memcpy/strcmp/realloc/log')
"
fi

# ── 4. Build ─────────────────────────────────────────────────────────────────

export LLVM_CONFIG="$LLVM_DIR/bin/llvm-config"
export LIBCLANG_PATH="$LLVM_DIR/lib"
export PATH="$LLVM_DIR/bin:$PATH"

BIN="$SRCDIR/target/release/openvaf"

if [ "$reuse_build" -eq 0 ] || [ ! -f "$BIN" ]; then
    echo "==> Building openvaf $tag ..."
    cargo build --release --bin openvaf
fi

echo ""
echo "Build complete: $(./target/release/openvaf --version)"
echo ""

# ── 5. Smoke test ────────────────────────────────────────────────────────────

echo "==> Smoke test: compile a Verilog-A file ..."
SMOKE_DIR="$SRCDIR/integration_tests/CURRENT_SOURCE"
if "$BIN" "$SMOKE_DIR/current_source.va" 2>&1; then
    if [ -f "$SMOKE_DIR/current_source.osdi" ]; then
        echo "  OK: compiled current_source.va -> current_source.osdi"
        file "$SMOKE_DIR/current_source.osdi"
    else
        echo "ERROR: smoke test produced no .osdi output" >&2
        exit 1
    fi
else
    echo "ERROR: smoke test failed to compile current_source.va" >&2
    exit 1
fi

# ── 6. Package ───────────────────────────────────────────────────────────────

echo "==> Packaging ..."
loadout_package_bin "$BIN" openvaf
loadout_stamp_version openvaf "$version"
loadout_report_max_glibc "$BIN"

echo ""
echo "Done. Commit with:"
echo "  git add payload/el8.x86_64.glibc2p28/bin/openvaf.bz2 \\"
echo "          .strip-manifest payload/packages.json \\"
echo "          build/build-openvaf.sh build/ADDING_BINARIES.md"
echo "  git commit -m 'feat(payload): openvaf ${version} Verilog-A compiler'"
