#!/bin/sh
# Build liberty-filter (strip unneeded data from Liberty .lib timing files) from
# source for el8.x86_64.glibc2p28.
#
# First-party project: github.com/smprather/liberty-filter -- a SEPARATE repo from
# liberty-tools, which is easy to get wrong because the two ship related CLIs and
# share a version lineage. liberty-tools is a Python wheel with a PyO3 cdylib
# (rolling_git, built by ./build/update); this is a standalone Rust binary and
# cannot use that path, because ./build/update's rolling path builds WHEELS.
#
# WHY THIS SCRIPT EXISTS AT ALL: liberty-filter entered the payload in the
# `ad63c48` bootstrap snapshot with NO build script and NO note here, so its
# provenance was recorded nowhere in this repo. It had to be recovered from the
# shipped binary's own strings (which named /tmp/liberty-rebuild-*/liberty-filter).
# Do not let that happen again -- every tool needs a note, see ADDING_BINARIES.md.
#
# OFFLINE BUILD, no crate-store needed. Unlike spice-subckt-rc-reduce (which has
# zero dependencies) this crate depends on flate2 + regex, but upstream VENDORS
# the whole closure: `vendor/` is committed (466 files) together with a
# `.cargo/config.toml` that sets `replace-with = "vendored-sources"`. The build
# therefore runs with `--offline` and that is asserted below, so a future upstream
# change that drops the vendor tree fails loudly here instead of silently
# reaching for the network on some build box that happens to have it.
#
# VERSION SOURCE -- read this before bumping.
#   --tag vX.Y.Z   a stable upstream tag; version becomes X.Y.Z
#   --rev <ref>    any ref (e.g. HEAD or a sha); version becomes `git describe`
#
# `--rev` exists because the kebab-case executable rename landed on HEAD and was
# never tagged: tag v2026.06.01.1 still declares `[[bin]] name = "liberty_filter"`
# while HEAD declares `liberty-filter`. Building the tag would re-ship the
# underscore name. Shipping a describe-versioned HEAD build is consistent with
# how the other first-party tools already ship here -- liberty-tools is
# `v2026.06.01.1-35-g73af358`, text-serdes is a bare sha -- but prefer `--tag`
# whenever upstream has tagged the state you want.
#
# The binary NEEDs only glibc + libgcc_s, both present on every EL8 target and
# both on the never-bundle list in CLAUDE.md. No lib64 artifacts, no runtime data
# files, so no runtime tarball either.
#
# Prerequisites on the build machine (EL8):
#   - rustc + cargo (tested 1.96.0; edition = "2021")
#   - patchelf at ~/.local/bin/patchelf
#
# Usage (run from any directory):
#   /path/to/build-liberty-filter.sh --rev HEAD
#   /path/to/build-liberty-filter.sh --tag v2026.06.01.2

set -eu

REPO="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO/build/lib.sh"

CLONE_URL="https://github.com/smprather/liberty-filter.git"
PKG="liberty-filter"
# The executable name is upstream's ([[bin]] name), NOT this package name. It was
# `liberty_filter` up to and including tag v2026.06.01.1 and is `liberty-filter`
# from HEAD onward; the script reads it from Cargo.toml rather than assuming, and
# reports it so the registry `bins` entry can be kept honest.
EXPECT_BIN="liberty-filter"

clean=0
tag=""
rev=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --clean) clean=1 ;;
        --tag)
            shift
            [ "$#" -gt 0 ] || { echo "missing value for --tag" >&2; exit 2; }
            tag="$1"
            ;;
        --rev)
            shift
            [ "$#" -gt 0 ] || { echo "missing value for --rev" >&2; exit 2; }
            rev="$1"
            ;;
        -h|--help)
            sed -n '2,/^$/p' "$0"
            exit 0
            ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done

if [ -n "$tag" ] && [ -n "$rev" ]; then
    echo "ERROR: pass --tag OR --rev, not both" >&2
    exit 2
fi
if [ -z "$tag" ] && [ -z "$rev" ]; then
    {
        echo "ERROR: one of --tag or --rev is required."
        echo "  $0 --tag v2026.06.01.2      # a stable upstream tag (preferred)"
        echo "  $0 --rev HEAD               # describe-versioned build, for"
        echo "                              # upstream state that is not tagged"
        echo ""
        echo "Tags: https://github.com/smprather/liberty-filter/tags"
        echo ""
        echo "NOTE: tag v2026.06.01.1 still names the binary liberty_filter."
        echo "The kebab-case rename is only on HEAD, so use --rev until it is tagged."
    } >&2
    exit 1
fi

loadout_enable_gcc_toolset
loadout_require_cmds cargo rustc git readelf strip bzip2

SRCDIR="/tmp/${PKG}-src"

if [ ! -d "$SRCDIR/.git" ]; then
    echo "Cloning $CLONE_URL ..."
    git clone "$CLONE_URL" "$SRCDIR"
fi

cd "$SRCDIR"
git fetch --tags --force origin
if [ -n "$tag" ]; then
    git rev-parse "refs/tags/$tag" >/dev/null 2>&1 || {
        echo "ERROR: no such tag upstream: $tag" >&2; exit 1; }
    git checkout --quiet --detach "refs/tags/$tag"
    # Upstream's tags are date-based (v2026.08.06.1) while Cargo carries the
    # semantic version (1.0.1), and `--version` prints the Cargo one -- so stamp
    # THAT, or the registry and the binary disagree and check-versions is noise.
    version=$(awk '/^\[package\]/{f=1;next} f&&/^version[[:space:]]*=/{gsub(/[",]/,"");print $3;exit}' Cargo.toml)
    case "$version" in
        ''|*-dev)
            echo "ERROR: tag $tag carries Cargo version '${version:-<none>}'." >&2
            echo "  A -dev version is a post-release bump, not a release; tag the" >&2
            echo "  release commit instead, or use --rev to ship a describe build." >&2
            exit 1 ;;
    esac
else
    if [ "$rev" = HEAD ]; then
        git checkout --quiet --detach origin/HEAD
    else
        git checkout --quiet --detach "$rev"
    fi
    version=$(git describe --tags --always)
fi
echo "Building $PKG at $(git rev-parse --short HEAD) (version: $version)"

# The executable name comes from upstream. Read it instead of assuming, so a
# rename is a loud build failure with the actual name in hand rather than a
# silently mismatched payload stem.
bin_stem=$(awk '/^\[\[bin\]\]/{f=1;next} f&&/^name[[:space:]]*=/{gsub(/[",]/,"");print $3;exit}' Cargo.toml)
[ -n "$bin_stem" ] || bin_stem=$(awk '/^\[package\]/{f=1;next} f&&/^name[[:space:]]*=/{gsub(/[",]/,"");print $3;exit}' Cargo.toml)
[ -n "$bin_stem" ] || { echo "ERROR: could not read the binary name from Cargo.toml" >&2; exit 1; }
if [ "$bin_stem" != "$EXPECT_BIN" ]; then
    echo "ERROR: upstream declares the executable as '$bin_stem', expected '$EXPECT_BIN'." >&2
    echo "  If upstream renamed it deliberately, update EXPECT_BIN here AND the" >&2
    echo "  'bins' entry for $PKG in payload/packages.json AND the binary-name key" >&2
    echo "  and match regex in build/farm-versions -- the registry names the payload" >&2
    echo "  stem bin/<name>.bz2, so a mismatch ships a package nothing can run." >&2
    exit 1
fi
echo "  executable: $bin_stem"

# Assert the offline build inputs are really present, so --offline below is a
# genuine guarantee rather than a lucky cache hit.
[ -d vendor ] || { echo "ERROR: no vendor/ tree; upstream stopped vendoring its crates." >&2; exit 1; }
grep -q 'replace-with[[:space:]]*=[[:space:]]*"vendored-sources"' .cargo/config.toml 2>/dev/null || {
    echo "ERROR: .cargo/config.toml does not redirect crates-io to vendored-sources." >&2
    echo "  The offline build assumption is broken; this needs a crate-store path." >&2
    exit 1
}

if [ "$clean" -eq 1 ]; then
    cargo clean
fi

echo "Building (release, offline, locked) ..."
cargo build --release --locked --offline

BIN="$SRCDIR/target/release/$bin_stem"
[ -f "$BIN" ] || { echo "build did not produce $BIN" >&2; exit 1; }

# Functional check. `--version` proves nothing about a filter engine, and this
# tool's whole job is to make a Liberty file smaller while keeping it parseable,
# so run a real filter over the real 1308-cell / 96 MB library upstream ships and
# assert the output actually shrank, kept what was asked for, and dropped the
# rest. A pass-through bug would sail past a version check.
LIB=$(find "$SRCDIR" -maxdepth 1 -name '*.lib.gz' -print | sort | head -1)
[ -n "$LIB" ] || { echo "ERROR: no *.lib.gz test library in the checkout" >&2; exit 1; }
echo ""
echo "Verifying a real filter run against $(basename "$LIB") ..."
OUT="$SRCDIR/.smoke-out.lib"
rm -f "$OUT"
# NOTE the flag semantics, which are easy to get wrong: --filter-in-cells is an
# EXCEPTION LIST to --filter-out-cells, not a standalone allowlist. The drop rule
# is `match_filter_out_cell && !match_filter_in_cell`, so --filter-in-cells alone
# drops nothing (upstream's own unit test pairs ^KEEP$ with filter_out_cells=".").
# "Keep only nand" therefore needs BOTH flags.
"$BIN" --in-file "$LIB" --out-file "$OUT" \
    --filter-out-cells '.' --filter-in-cells '^nand' >/dev/null 2>&1 || {
    echo "ERROR: filter run failed" >&2; exit 1; }
[ -s "$OUT" ] || { echo "ERROR: filter produced no output" >&2; exit 1; }

in_cells=$(zcat "$LIB" | grep -cE '^[[:space:]]*cell[[:space:]]*\(' || true)
out_cells=$(grep -cE '^[[:space:]]*cell[[:space:]]*\(' "$OUT" || true)
kept_nand=$(grep -cE '^[[:space:]]*cell[[:space:]]*\([[:space:]]*nand' "$OUT" || true)
echo "  cells: $in_cells in -> $out_cells out (nand kept: $kept_nand)"
[ "$out_cells" -gt 0 ] || { echo "ERROR: output has no cells at all" >&2; exit 1; }
[ "$kept_nand" -gt 0 ] || { echo "ERROR: --filter-in-cells '^nand' kept no nand cells" >&2; exit 1; }
if [ "$out_cells" -ge "$in_cells" ]; then
    echo "ERROR: no reduction ($out_cells >= $in_cells); the filter is a pass-through" >&2
    exit 1
fi
if [ "$out_cells" -ne "$kept_nand" ]; then
    echo "ERROR: output holds $out_cells cells but only $kept_nand are nand -- " >&2
    echo "  --filter-in-cells let non-matching cells through" >&2
    exit 1
fi
# Still a well-formed Liberty file: the library group must survive intact.
grep -qE '^[[:space:]]*library[[:space:]]*\(' "$OUT" || {
    echo "ERROR: output lost its library() group; result is not valid Liberty" >&2
    exit 1
}
echo "  OK: filtered, shrank, kept only the requested cells, library group intact"
rm -f "$OUT"

# Package: strip -> patchelf -> bzip2 (order is load-bearing; see AGENTS.md).
loadout_package_bin "$BIN" "$bin_stem"
loadout_stamp_version "$PKG" "$version"

echo "Running strip-all-elf-binaries ..."
"$REPO/build/strip-all-elf-binaries"

loadout_report_max_glibc "$BIN"

echo ""
echo "NEEDED shared libs (must be glibc/libgcc_s only -- never bundled):"
readelf -d "$BIN" 2>/dev/null | grep NEEDED || true

echo ""
echo "Next:"
echo "  python3.14 build/gen-content-manifest"
echo "  python3.14 build/gen-readme-table"
echo "  ./loadout completion bash > envs/bash/global/completions/loadout.bash"
echo "  tests/prebuilt-binaries --keep"
echo "  git add payload/ .strip-manifest .content-manifest build/build-${PKG}.sh \\"
echo "          build/farm-versions build/ADDING_BINARIES.md payload/packages.json"
