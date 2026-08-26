#!/bin/sh
# gnuplot -- EL8 source build, no Qt.
#
# WHY THIS SCRIPT EXISTS: gnuplot had a build NOTE in ADDING_BINARIES.md but no
# script, so the procedure existed only as prose and every bump meant re-deriving
# the configure line by hand. HANDOFF called this out for the 2026-08-03 sweep:
# bumping a script-less tool means authoring the procedure first, which the repo
# mandates anyway.
#
# SOURCE BUILD, not a prebuilt: upstream ships no Linux binary, and building it
# here is what lets us drop the Qt5 dependency chain.
#
# TWO artifacts, and the second is the one that gets forgotten:
#   bin/gnuplot.bz2                        the real ELF
#   runtime/gnuplot.tar.bz2                ./libexec/gnuplot/6.0/gnuplot_x11
#
# gnuplot 6's `x11` terminal is NOT in-process -- gnuplot forks a separate helper
# and pipes it a command stream, resolving it via $GNUPLOT_DRIVER_DIR, falling
# back to the COMPILED-IN <prefix>/libexec/gnuplot/6.0/gnuplot_x11. The original
# 6.0.2 build baked --prefix=/tmp/gnuplot-install and never bundled the helper,
# so on a destination machine every x11 plot died with
#   Couldn't exec expected X11 driver: /tmp/gnuplot-install/libexec/...
# and any tool defaulting to the x11 terminal failed on every plot. The helper is
# therefore bundled, and envs/*/global/* export GNUPLOT_DRIVER_DIR at the
# installed prefix. Do not drop either half.
#
# VERSION-BEARING PATH: the archive and the registry `sentinel` both contain the
# MAJOR.MINOR (`6.0`). A 6.1 bump must move the sentinel with it.
#
# Usage (run from any directory):
#   /path/to/build-gnuplot.sh --tag 6.0.5
#
# Tag format is a BARE version -- gnuplot releases on SourceForge, not GitHub.

set -eu

REPO="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO/build/lib.sh"

PKG="gnuplot"
RELEASES_URL="https://sourceforge.net/projects/gnuplot/files/gnuplot/"
PLATFORM_DIR="$REPO/payload/el8.x86_64.glibc2p28"
GLIBC_FLOOR="2.28"

tag=""
jobs=$(nproc 2>/dev/null || echo 4)
while [ "$#" -gt 0 ]; do
    case "$1" in
        --tag)
            shift
            [ "$#" -gt 0 ] || { echo "missing value for --tag" >&2; exit 2; }
            tag=$1
            ;;
        -j)
            shift
            jobs=$1
            ;;
        -h | --help)
            sed -n '2,32p' "$0"
            exit 0
            ;;
        *)
            echo "unknown argument: $1" >&2
            exit 2
            ;;
    esac
    shift
done

loadout_require_tag "$tag" "$0" "$RELEASES_URL" "6.0.5"
loadout_require_cmds curl tar bzip2 patchelf readelf make gcc

case "$tag" in
    v*) echo "ERROR: gnuplot versions have no leading v. Use --tag ${tag#v}" >&2; exit 2 ;;
esac

# MAJOR.MINOR drives the libexec path and the registry sentinel.
series=$(echo "$tag" | cut -d. -f1,2)

workdir=$(mktemp -d "${TMPDIR:-/tmp}/loadout-gnuplot.XXXXXX")
prefix="$workdir/install"
trap 'rm -rf "$workdir"' EXIT INT TERM

echo "Downloading gnuplot $tag ..."
curl -fsSL -o "$workdir/src.tar.gz" \
    "https://downloads.sourceforge.net/project/gnuplot/gnuplot/$tag/gnuplot-$tag.tar.gz" || {
    echo "ERROR: download failed for gnuplot $tag" >&2
    exit 1
}
tar xzf "$workdir/src.tar.gz" -C "$workdir"
src="$workdir/gnuplot-$tag"
[ -d "$src" ] || { echo "ERROR: expected $src in the tarball" >&2; exit 1; }

# Configure flags are load-bearing, not preferences:
#   --without-qt      drops the whole Qt5 build dependency chain
#   --without-cairo   likewise for cairo/pango
#   --without-lua     avoids a lua dev dependency for a terminal nobody uses here
#   --without-libcerf not packaged on EL8
#   --with-readline=gnu  gives the interactive line editing users expect
#   --with-x          keeps the x11 terminal (and thus the gnuplot_x11 helper)
echo "Configuring ..."
( cd "$src" && ./configure \
    --prefix="$prefix" \
    --without-qt \
    --without-lua \
    --without-cairo \
    --without-libcerf \
    --with-readline=gnu \
    --with-x > "$workdir/configure.log" 2>&1 ) || {
    echo "ERROR: configure failed; see $workdir/configure.log" >&2
    tail -20 "$workdir/configure.log" >&2
    exit 1
}

echo "Building (-j$jobs) ..."
( cd "$src" && make -j"$jobs" > "$workdir/make.log" 2>&1 && make install > "$workdir/install.log" 2>&1 ) || {
    echo "ERROR: build failed; see $workdir/make.log" >&2
    tail -20 "$workdir/make.log" >&2
    exit 1
}

bin="$prefix/bin/gnuplot"
helper="$prefix/libexec/gnuplot/$series/gnuplot_x11"
[ -x "$bin" ] || { echo "ERROR: no gnuplot binary at $bin" >&2; exit 1; }
[ -x "$helper" ] || {
    echo "ERROR: no gnuplot_x11 helper at $helper" >&2
    echo "  Without it every x11 plot fails at run time. Did --with-x survive configure?" >&2
    exit 1
}

built=$("$bin" --version 2>&1 | head -1)
echo "  built: $built"
case $built in
    *"$series patchlevel ${tag##*.}"*) ;;
    *)
        echo "ERROR: built binary reports '$built', which does not match --tag $tag" >&2
        exit 1
        ;;
esac

# --- EL8 floor + dependency closure ---------------------------------------
# A newer-glibc build installs fine here and is dead on a stock farm node.
for f in "$bin" "$helper"; do
    mg=$(readelf -V "$f" 2>/dev/null | grep -oE 'GLIBC_[0-9]+\.[0-9]+' | sed 's/GLIBC_//' | sort -V | tail -1)
    echo "  $(basename "$f"): max glibc ${mg:-none} (floor $GLIBC_FLOOR)"
    if [ -n "$mg" ]; then
        highest=$(printf '%s\n%s\n' "$mg" "$GLIBC_FLOOR" | sort -V | tail -1)
        [ "$highest" = "$GLIBC_FLOOR" ] || {
            echo "ERROR: $(basename "$f") needs GLIBC_$mg, EL8 ships $GLIBC_FLOOR" >&2
            exit 1
        }
    fi
done

# Everything here is either already bundled under lib64/ or is a system library
# the loadout must never bundle (glibc components, the C++ runtime, EL8-base zlib
# and the host X11 client libs). A NEEDED entry outside this set is a new payload
# dependency and has to be added deliberately.
unexpected=""
for lib in $(patchelf --print-needed "$bin" "$helper" 2>/dev/null | sort -u); do
    case "$lib" in
        libreadline.so.7 | libncurses.so.6 | libtinfo.so.6) ;;                 # bundled
        libc.so.6 | libm.so.6 | libdl.so.2 | libpthread.so.0 | librt.so.1) ;;   # glibc
        libstdc++.so.6 | libgcc_s.so.1) ;;                                     # C++ runtime
        libz.so.1 | libX11.so.6 | libXt.so.6) ;;                                # EL8 base / X11
        *) unexpected="$unexpected $lib" ;;
    esac
done
[ -z "$unexpected" ] || {
    echo "ERROR: new shared-library dependencies:$unexpected" >&2
    echo "  Bundle them under payload/<platform>/lib64/ before shipping." >&2
    exit 1
}
echo "  dependency closure: nothing new to bundle"

# --- package ---------------------------------------------------------------
echo "Packaging ..."
loadout_package_bin "$bin" "$PKG"

stage="$workdir/stage"
mkdir -p "$stage/libexec/gnuplot/$series"
cp "$helper" "$stage/libexec/gnuplot/$series/gnuplot_x11"
strip "$stage/libexec/gnuplot/$series/gnuplot_x11" 2>/dev/null || true
chmod 755 "$stage/libexec/gnuplot/$series/gnuplot_x11"
mkdir -p "$PLATFORM_DIR/runtime"
tar cjf "$PLATFORM_DIR/runtime/$PKG.tar.bz2" -C "$stage" ./libexec
echo "  runtime/$PKG.tar.bz2 (libexec/gnuplot/$series/gnuplot_x11)"

loadout_stamp_version "$PKG" "$tag"

echo ""
echo "Check the registry sentinel still matches the series:"
echo "  gnuplot.sentinel should be libexec/gnuplot/$series/gnuplot_x11"
echo ""
echo "Next:"
echo "  ./build/strip-all-elf-binaries"
echo "  python3.14 build/gen-content-manifest"
echo "  python3.14 build/gen-readme-table"
echo "  tests/prebuilt-binaries"
