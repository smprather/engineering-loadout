#!/bin/sh
# Build spice-subckt-rc-reduce (SPICE .subckt parasitic RC reduction) from
# source for el8.x86_64.glibc2p28.
#
# First-party project (github.com/smprather). Pure Rust, and unusually clean to
# package: Cargo.lock resolves to exactly ONE package -- itself. There are no
# external crates at all, so the build needs no network and no offline
# crate-store, unlike surfer or the @rust trio. Do not add a rust-crate-store
# dependency for it.
#
# The binary NEEDs only glibc and libgcc_s, both of which are on every EL8
# target and both of which the loadout must NEVER bundle (see CLAUDE.md ->
# "Never bundle these libs"). So there are no lib64 artifacts either: this is a
# single self-contained binary with no runtime data files, hence no runtime
# tarball.
#
# Note the name asymmetry, which is upstream's and is deliberate here:
#   registry package / repo : spice-subckt-rc-reduce   (dashes)
#   installed binary        : spice_subckt_rc_reduce   (underscores, [[bin]] name)
# The registry entry's "bins" MUST use the underscore form -- it names the
# payload stem `bin/spice_subckt_rc_reduce.bz2`, not the package.
#
# edition = "2024" needs Rust >= 1.85; upstream's README asks for 1.96+.
#
# Policy: stable tagged releases only. `rolling_git` is NOT an option here even
# though this is a first-party project -- ./update's rolling path builds Python
# WHEELS (`uv build --wheel`), so it cannot produce a Rust binary.
#   https://github.com/smprather/spice-subckt-rc-reduce/releases
#
# Prerequisites on the build machine (EL8):
#   - rustc + cargo (rustup stable). Tested with 1.96.0.
#   - patchelf at ~/.local/bin/patchelf
#
# Usage (run from any directory):
#   /path/to/build-spice-subckt-rc-reduce.sh --tag v0.1.0

set -eu

REPO="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO/build/lib.sh"

CLONE_URL="https://github.com/smprather/spice-subckt-rc-reduce.git"
RELEASES_URL="https://github.com/smprather/spice-subckt-rc-reduce/releases"
PKG="spice-subckt-rc-reduce"
BIN_STEM="spice_subckt_rc_reduce"

clean=0
tag=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --clean) clean=1 ;;
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

loadout_require_tag "$tag" "$0" "$RELEASES_URL" "v0.1.0"
loadout_enable_gcc_toolset
loadout_require_cmds cargo rustc git

SRCDIR="/tmp/${PKG}-src-${tag}"

if [ ! -d "$SRCDIR/.git" ]; then
    echo "Cloning $CLONE_URL ..."
    git clone --filter=blob:none "$CLONE_URL" "$SRCDIR"
fi

cd "$SRCDIR"
if ! git rev-parse "$tag" > /dev/null 2>&1; then
    git fetch --tags
fi
git checkout --detach "$tag"

# Guard the no-dependency invariant this script's packaging relies on. If
# upstream ever takes a crate dependency, the offline build assumption breaks
# and this needs the crate-store treatment -- fail loudly rather than silently
# reaching for the network on some future build box.
dep_count=$(grep -c '^\[\[package\]\]' Cargo.lock || true)
if [ "$dep_count" -ne 1 ]; then
    echo "ERROR: Cargo.lock now resolves $dep_count packages (expected exactly 1: itself)." >&2
    echo "  Upstream took a crate dependency. This build is no longer dependency-free," >&2
    echo "  so it needs an offline crate-store path before it can be bundled." >&2
    exit 1
fi

if [ "$clean" -eq 1 ]; then
    cargo clean
fi

echo "Building $PKG (release) ..."
cargo build --release --locked

BIN="$SRCDIR/target/release/$BIN_STEM"
[ -f "$BIN" ] || { echo "build did not produce $BIN" >&2; exit 1; }

# Functional check before packaging. `--version`/exit-0 proves nothing about a
# reduction engine, so run a real reduction and assert the node count actually
# drops: large_mesh is 105 nodes and must reduce past 100 at tau=1e-9.
echo ""
echo "Verifying a real reduction ..."
out=$("$BIN" testdata/large_mesh.subckt -o "$SRCDIR/.smoke.subckt" --tau 1e-9 -v 2>&1)
echo "$out" | sed 's/^/  /'
reduced=$(echo "$out" | awk '/Nodes:/ {print $4}')
case "$reduced" in
    ''|*[!0-9]*)
        echo "ERROR: could not parse a reduced node count from the run above" >&2
        exit 1 ;;
esac
if [ "$reduced" -ge 105 ]; then
    echo "ERROR: large_mesh did not reduce (nodes ${reduced} >= 105); the engine is not working" >&2
    exit 1
fi
echo "  OK: 105 -> ${reduced} nodes"
rm -f "$SRCDIR/.smoke.subckt"

# Package: strip -> patchelf -> bzip2 (order is load-bearing; see AGENTS.md).
loadout_package_bin "$BIN" "$BIN_STEM"

ver="${tag#v}"
loadout_stamp_version "$PKG" "$ver"

echo "Running strip-all-elf-binaries ..."
"$REPO/strip-all-elf-binaries"

loadout_report_max_glibc "$BIN"

echo ""
echo "NEEDED shared libs (must be glibc/libgcc_s only -- never bundled):"
readelf -d "$BIN" 2>/dev/null | grep NEEDED || true

echo ""
echo "Next:"
echo "  python3.14 build/gen-content-manifest"
echo "  tests/prebuilt-binaries --keep    # or ./release --dry-run"
echo "  git add payload/ .strip-manifest build/build-${PKG}.sh \\"
echo "          build/farm-versions build/ADDING_BINARIES.md"
