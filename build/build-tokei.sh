#!/bin/sh
# Build `tokei` (code counter) from source for el8.x86_64.glibc2p28.
#
# tokei's tracked stable tags ship NO prebuilt binaries (v15.0.0's GitHub
# release has zero assets; only an older v12.1.2 had a musl static), so the
# stable-only policy means building from source on EL8 -- which also yields a
# native glibc-2.28 binary. Rust + cargo.
#
# Runtime libs: libgcc_s, libpthread, libdl, libm, libc -- all EL8 base, no
# bundling and no RPATH needed beyond the repo default every bin/ payload gets.
#
# Prerequisites: rustc + cargo (the bundled rust runtime works: the loadout
# rust package is a hard dependency of many tools and is staged read-only in
# the build container), git.
#
# Usage (run from any directory):
#   ./build/build-tokei.sh --tag v15.0.0

set -eu

REPO="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib.sh
. "$REPO/build/lib.sh"
CLONE_URL="https://github.com/XAMPPRocky/tokei.git"

tag=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --tag)
            shift
            [ "$#" -gt 0 ] || { echo "missing value for --tag" >&2; exit 2; }
            tag="$1"
            ;;
        -h | --help)
            sed -n '2,/^$/p' "$0"
            exit 0
            ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done

loadout_require_tag "$tag" "$0" "https://github.com/XAMPPRocky/tokei/releases" "v15.0.0"
loadout_enable_gcc_toolset
loadout_require_cmds cargo git strip readelf

SRCDIR="${TMPDIR:-/tmp}/tokei-src-${tag#v}"
rm -rf "$SRCDIR"
git clone --depth 1 --branch "$tag" "$CLONE_URL" "$SRCDIR"
cd "$SRCDIR"

echo "==> Building tokei (release) ..."
cargo build --release

BIN="$SRCDIR/target/release/tokei"
[ -f "$BIN" ] || { echo "ERROR: build did not produce $BIN" >&2; exit 1; }
reported=$("$BIN" --version 2>&1 | head -1)
echo "  $reported"
case "$reported" in
    *"${tag#v}"*) ;;
    *) echo "ERROR: tokei reports '$reported', expected ${tag#v}" >&2; exit 1 ;;
esac

# Floor check: this is a native EL8 build, so anything above 2.28 means the
# container's gcc-toolset leaked a newer glibc reference.
g=$(readelf -V "$BIN" 2>/dev/null | grep -oE 'GLIBC_[0-9]+\.[0-9]+' | sort -V | tail -1)
echo "  Max glibc symbol: ${g:-none} (target: <= GLIBC_2.28)"
case "${g:-GLIBC_2.0}" in
    GLIBC_2.2[0-8] | GLIBC_2.1[0-9] | GLIBC_2.[0-9]) ;;
    *) echo "ERROR: tokei needs $g; EL8 has glibc 2.28" >&2; exit 1 ;;
esac

loadout_package_bin "$BIN" tokei
loadout_stamp_version tokei "${tag#v}"

echo "==> Running strip-all-elf-binaries ..."
"$REPO/build/strip-all-elf-binaries"

cat << EOF

Done.

Next, as for every payload change:
  build/gen-installed-sizes
  build/gen-content-manifest
EOF
