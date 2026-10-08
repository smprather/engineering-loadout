#!/bin/sh
# tree-sitter CLI -- EL8 source build (Rust).
#
# WHY THIS SCRIPT EXISTS: tree-sitter was source-built for 0.26.11 during the
# 2026-08-04 sweep with no build script and no ADDING_BINARIES.md note, so the
# procedure existed nowhere. Same provenance gap as liberty-filter,
# tmux-path-store, lua-language-server and the five small C tools.
#
# SOURCE BUILD, and NOT optional. Upstream ships a linux-x64 prebuilt, but its
# glibc floor is far above EL8's 2.28 -- GLIBC_2.39 at 0.26.11 and GLIBC_2.35 at
# 0.26.12. Either would install cleanly on this box and be DEAD on a stock farm
# node, which is exactly the build-box masking the floor check exists to catch.
# Do not "simplify" this into a download.
#
# BUILD FROM SOURCE. Upstream publishes no EL8-safe prebuilt (the floor check
# above explains why a download is not an option), so this needs a Rust
# toolchain on the build host. That is a release-time prerequisite only: the
# shipped binary is a normal payload bin and users never need cargo.
#
# Usage (run from any directory):
#   /path/to/build-tree-sitter.sh --tag v0.26.12
#   /path/to/build-tree-sitter.sh --tag v0.26.12 --offline   # prove the store works
#
# Tag format carries a leading v -- upstream's convention.

set -eu

REPO="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO/build/lib.sh"

PKG="tree-sitter"
CLONE_URL="https://github.com/tree-sitter/tree-sitter"
RELEASES_URL="$CLONE_URL/releases"
GLIBC_FLOOR="2.28"

tag=""
offline=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --tag)
            shift
            [ "$#" -gt 0 ] || { echo "missing value for --tag" >&2; exit 2; }
            tag=$1
            ;;
        --offline) offline=1 ;;
        -h | --help)
            sed -n '2,26p' "$0"
            exit 0
            ;;
        *)
            echo "unknown argument: $1" >&2
            exit 2
            ;;
    esac
    shift
done

loadout_require_tag "$tag" "$0" "$RELEASES_URL" "v0.26.12"
loadout_require_cmds git cargo patchelf readelf strip bzip2

case "$tag" in
    v*) ;;
    *)
        echo "ERROR: upstream tags this project WITH a leading v (e.g. v0.26.12)." >&2
        echo "  Re-run with --tag v$tag" >&2
        exit 2
        ;;
esac

workdir=$(mktemp -d "${TMPDIR:-/tmp}/loadout-tree-sitter.XXXXXX")
trap 'rm -rf "$workdir"' EXIT INT TERM

src="$workdir/src"
echo "Cloning $PKG $tag ..."
git clone --quiet --depth 1 --branch "$tag" "$CLONE_URL" "$src" 2>/dev/null || {
    echo "ERROR: could not clone tag $tag -- does it exist?" >&2
    echo "  $RELEASES_URL" >&2
    exit 1
}

cargo_args="--release --locked"
if [ "$offline" -eq 1 ]; then
    # Generic cargo --offline: build against whatever the caller's own cargo
    # cache/config provides (a vendored tree, a local mirror, a warm cache).
    cargo_args="$cargo_args --offline"
    echo "  building OFFLINE (cargo --offline; caller's cargo cache/config)"
else
    # ISOLATE CARGO_HOME for the online build: a caller's ~/.cargo/config.toml
    # may point crates-io at a private mirror or a stale replace-with target, so
    # the release build resolves against real crates.io in its own home. The
    # same bypass is recorded for surfer in ADDING_BINARIES.
    CARGO_HOME="$workdir/cargo"
    export CARGO_HOME
    echo "  building ONLINE with an isolated CARGO_HOME (ignores the caller's cargo config)"
fi

echo "Building (cargo $cargo_args) ..."
( cd "$src" && cargo build $cargo_args --bin tree-sitter > "$workdir/build.log" 2>&1 ) || {
    echo "ERROR: cargo build failed; see $workdir/build.log" >&2
    tail -25 "$workdir/build.log" >&2
    exit 1
}

bin="$src/target/release/tree-sitter"
[ -x "$bin" ] || { echo "ERROR: no binary at $bin" >&2; exit 1; }

# Assert the artifact reports the tag we asked for -- the repo file says what
# upstream intends, the built binary says what actually ships.
built=$("$bin" --version 2>&1 | head -1)
echo "  built: $built"
case "$built" in
    *"${tag#v}"*) ;;
    *)
        echo "ERROR: built binary reports '$built', which does not match --tag $tag" >&2
        exit 1
        ;;
esac

# --- EL8 floor check -------------------------------------------------------
# This is the whole reason the package is a source build; assert it every time
# rather than trusting that the toolchain has not moved.
mg=$(readelf -V "$bin" 2>/dev/null | grep -oE 'GLIBC_[0-9]+\.[0-9]+' | sed 's/GLIBC_//' | sort -V | tail -1)
echo "  max glibc symbol: ${mg:-none} (floor $GLIBC_FLOOR)"
if [ -n "$mg" ]; then
    highest=$(printf '%s\n%s\n' "$mg" "$GLIBC_FLOOR" | sort -V | tail -1)
    [ "$highest" = "$GLIBC_FLOOR" ] || {
        echo "ERROR: needs GLIBC_$mg but EL8 ships $GLIBC_FLOOR." >&2
        echo "  The build toolchain is too new -- do not ship this binary." >&2
        exit 1
    }
fi

# Rust static-links its own runtime, so only glibc components should appear.
unexpected=""
for lib in $(patchelf --print-needed "$bin"); do
    case "$lib" in
        libc.so.6 | libm.so.6 | libdl.so.2 | libpthread.so.0 | librt.so.1 | ld-linux-x86-64.so.2) ;;
        libgcc_s.so.1) ;;
        *) unexpected="$unexpected $lib" ;;
    esac
done
[ -z "$unexpected" ] || {
    echo "ERROR: new shared-library dependencies:$unexpected" >&2
    exit 1
}
echo "  dependency closure: glibc only, nothing new to bundle"

echo "Packaging ..."
# strip BEFORE patchelf -- never the other way round (AGENTS.md).
loadout_package_bin "$bin" "$PKG"

loadout_stamp_version "$PKG" "${tag#v}"

echo ""
echo "Next:"
echo "  ./build/strip-all-elf-binaries"
echo "  python3.14 build/gen-content-manifest"
echo "  python3.14 build/gen-readme-table"
echo "  tests/prebuilt-binaries"
