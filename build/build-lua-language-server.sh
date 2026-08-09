#!/bin/sh
# lua-language-server -- LSP server for Lua, bundled from the upstream linux-x64
# release tarball.
#
# WHY THIS SCRIPT EXISTS: the package was bundled with no build script and no
# ADDING_BINARIES.md note, so nothing recorded where its payload came from or how
# to refresh it. Same gap liberty-filter and tmux-path-store had. Every tool needs
# a note and a script -- see the mandate at the top of ADDING_BINARIES.md.
#
# NOT a source build. Upstream ships an x86_64 tarball whose ELF floor is
# GLIBC_2.17, comfortably under EL8's 2.28, so the prebuilt is usable as-is. The
# script ASSERTS that rather than assuming it: a future release built against a
# newer toolchain would install cleanly on this box and be dead on a stock farm
# node, which is exactly how tree-sitter and bottom got rejected.
#
# PACKAGING SHAPE (two artifacts, and they must stay in sync):
#   bin/lua-language-server.bz2       POSIX-sh wrapper
#   runtime/lua-language-server.tar.bz2   ./share/lua-language-server/ tree
# The server is not a lone binary -- it needs main.lua, meta/, script/ and
# locale/ beside it and resolves them relative to its own path, so the real ELF
# lives inside the share tree and the wrapper execs it from there.
#
# Usage (run from any directory):
#   /path/to/build-lua-language-server.sh --tag 3.19.0
#
# Tag format is a BARE version, no leading v -- that is upstream's convention
# (github.com/LuaLS/lua-language-server/releases).

set -eu

REPO="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO/build/lib.sh"

PKG="lua-language-server"
RELEASES_URL="https://github.com/LuaLS/lua-language-server/releases"
PLATFORM_DIR="$REPO/payload/el8.x86_64.glibc2p28"
GLIBC_FLOOR="2.28"

tag=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --tag)
            shift
            [ "$#" -gt 0 ] || { echo "missing value for --tag" >&2; exit 2; }
            tag=$1
            ;;
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

loadout_require_tag "$tag" "$0" "$RELEASES_URL" "3.19.0"
loadout_require_cmds curl tar bzip2 patchelf readelf

case "$tag" in
    v*)
        echo "ERROR: upstream tags this project WITHOUT a leading v (e.g. 3.19.0)." >&2
        echo "  Re-run with --tag ${tag#v}" >&2
        exit 2
        ;;
esac

workdir=$(mktemp -d /tmp/loadout-lls.XXXXXX)
trap 'rm -rf "$workdir"' EXIT INT TERM

url="$RELEASES_URL/download/$tag/lua-language-server-$tag-linux-x64.tar.gz"
echo "Downloading $PKG $tag ..."
curl -fsSL -o "$workdir/lls.tar.gz" "$url" || {
    echo "ERROR: download failed: $url" >&2
    echo "  Check that the tag exists and ships a linux-x64 asset." >&2
    exit 1
}

src="$workdir/src"
mkdir -p "$src"
tar xzf "$workdir/lls.tar.gz" -C "$src"

elf="$src/bin/lua-language-server"
[ -f "$elf" ] || { echo "ERROR: no bin/lua-language-server in the tarball" >&2; exit 1; }

# --- EL8 floor check -------------------------------------------------------
# A prebuilt needing a newer glibc than the target runs fine on a dev box and
# dies on a stock farm node. Reject it here rather than at a user's shell.
max_glibc=$(readelf -V "$elf" 2>/dev/null | grep -oE 'GLIBC_[0-9]+\.[0-9]+' | sed 's/GLIBC_//' | sort -V | tail -1)
echo "  max glibc symbol: ${max_glibc:-none} (target floor: $GLIBC_FLOOR)"
if [ -n "$max_glibc" ]; then
    highest=$(printf '%s\n%s\n' "$max_glibc" "$GLIBC_FLOOR" | sort -V | tail -1)
    if [ "$highest" != "$GLIBC_FLOOR" ]; then
        echo "ERROR: this build needs GLIBC_$max_glibc but EL8 ships $GLIBC_FLOOR." >&2
        echo "  It would install cleanly here and be DEAD on a stock farm node." >&2
        echo "  Build from source on this EL8 box instead of using the prebuilt." >&2
        exit 1
    fi
fi

# --- dependency closure ----------------------------------------------------
# Only glibc components are acceptable: those are never bundled (they must match
# the host ld.so exactly). Anything else is a new library that has to be added to
# the payload deliberately, not discovered by a user at runtime.
unexpected=""
for lib in $(patchelf --print-needed "$elf"); do
    case "$lib" in
        libc.so.6 | libm.so.6 | libpthread.so.0 | libdl.so.2 | librt.so.1 | ld-linux-x86-64.so.2) ;;
        *) unexpected="$unexpected $lib" ;;
    esac
done
if [ -n "$unexpected" ]; then
    echo "ERROR: new shared-library dependencies:$unexpected" >&2
    echo "  Bundle them under payload/<platform>/lib64/ before shipping." >&2
    exit 1
fi
echo "  dependency closure: glibc only, nothing new to bundle"

# --- stage the share tree --------------------------------------------------
stage="$workdir/stage"
mkdir -p "$stage/share/lua-language-server"
cp -a "$src/." "$stage/share/lua-language-server/"
chmod 755 "$stage/share/lua-language-server/bin/lua-language-server"

# --- wrapper ---------------------------------------------------------------
# Derives its prefix from its own installed path, so a --dest-dir or shared-tree
# install resolves the share tree without any build-time prefix baked in.
cat > "$workdir/wrapper" << 'WRAPEOF'
#!/bin/sh
bindir=$(CDPATH= cd "$(dirname "$0")" 2>/dev/null && pwd) || exit 1
exec "$bindir/../share/lua-language-server/bin/lua-language-server" "$@"
WRAPEOF
chmod 755 "$workdir/wrapper"

echo "Packaging ..."
mkdir -p "$PLATFORM_DIR/bin" "$PLATFORM_DIR/runtime"
tar cjf "$PLATFORM_DIR/runtime/$PKG.tar.bz2" -C "$stage" ./share
echo "  runtime/$PKG.tar.bz2"
bzip2 -c "$workdir/wrapper" > "$PLATFORM_DIR/bin/$PKG.bz2"
chmod 644 "$PLATFORM_DIR/bin/$PKG.bz2"
echo "  bin/$PKG.bz2 (wrapper)"

loadout_stamp_version "$PKG" "$tag"

echo ""
echo "Next:"
echo "  ./build/strip-all-elf-binaries"
echo "  python3.14 build/gen-content-manifest"
echo "  python3.14 build/gen-readme-table"
echo "  tests/prebuilt-binaries"
echo "  git add payload/ .strip-manifest .content-manifest \\"
echo "          build/build-$PKG.sh build/ADDING_BINARIES.md payload/packages.json"
