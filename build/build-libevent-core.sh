#!/bin/sh
# Build libevent_core from source for el8.x86_64.glibc2p28, with OpenSSL
# support disabled.
#
# Produces:
#   payload/el8.x86_64.glibc2p28/lib64/libevent_core-2.1.so.6.bz2
#
# WHY THIS SCRIPT EXISTS. The bundled libevent_core-2.1.so.6 was never built
# by a script in this repo -- it was lifted straight from EL8's system
# libevent-2.1.8-5.el8 RPM (build/lib.sh's comment on build-tmux.sh calls it
# "system libevent-devel", but the actual shared object in lib64/ is the RPM's
# own libevent_core-2.1.so.6.0.2, byte-for-byte). Red Hat's libevent spec
# builds with --enable-openssl for the WHOLE package, and that bleeds into
# libevent_core (used for its arc4random fallback via RAND_bytes) even though
# "core" has no business needing crypto -- confirmed by rebuilding the same
# RPM in a clean AlmaLinux 8.10 container: libevent_core-2.1.so.6.0.2 there
# also carries NEEDED libcrypto.so.1.1.
#
# EL8 always has libcrypto.so.1.1 (openssl-libs-1.1.1), so this was invisible
# on the build machine and on any EL8 target. It breaks tmux everywhere else:
# Arch/CachyOS ships only OpenSSL 3 (libcrypto.so.3, no 1.1 compat by
# default), so a fresh loadout install fails at exec with:
#   tmux: error while loading shared libraries: libcrypto.so.1.1: cannot open
#   shared object file: No such file or directory
#
# THE FIX: build libevent 2.1.8-stable (the exact upstream version the RPM
# packages -- see EXPECTED_TAG below) from source with --disable-openssl.
# tmux only calls the core event/bufferevent API (event_*, bufferevent_*),
# none of which touches libevent's OpenSSL bufferevent backend, so dropping
# it costs nothing functionally and removes the NEEDED entry entirely:
#   NEEDED  libpthread.so.0   (always present -- glibc component, never
#                               bundled; see ADDING_BINARIES.md)
#   NEEDED  libc.so.6
# Verified by rebuilding tmux's own undefined dynsym set against this
# library's exports (see the check below) and by an actual smoke run:
#   tmux new-session -d ... / capture-pane  on a host with NO libcrypto.so.1.1
#   anywhere on the system.
#
# Pinned to release-2.1.8-stable, matching the version already in use --
# this is a targeted dependency fix, not a version bump. Bump separately if
# tmux ever needs newer libevent (2.1.12-stable changes the SONAME to
# libevent_core-2.1.so.7, which would also require rebuilding tmux itself).
#
# Build-time deps (system): gcc, make, autoconf, automake, libtool,
#   pkgconf-pkg-config, git. No openssl-devel needed -- --disable-openssl
#   means it is never probed for.
# Runtime deps (system on EL8 and everywhere else): libpthread.so.0, libc.so.6
#
# Usage (run from any directory):
#   /path/to/build-libevent-core.sh --tag release-2.1.8-stable

set -eu

REPO="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib.sh
. "$REPO/build/lib.sh"
CLONE_URL="https://github.com/libevent/libevent.git"
RELEASES_URL="https://github.com/libevent/libevent/releases"
LIB_DIR="$REPO/payload/$LOADOUT_PLATFORM/lib64"
SONAME="libevent_core-2.1.so.6"
EXPECTED_TAG="release-2.1.8-stable"

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

loadout_require_tag "$tag" "$0" "$RELEASES_URL" "$EXPECTED_TAG"
if [ "$tag" != "$EXPECTED_TAG" ]; then
    echo "WARNING: tag $tag != $EXPECTED_TAG -- check the SONAME libevent" >&2
    echo "         produces still matches $SONAME before shipping. 2.1.12-stable" >&2
    echo "         and later cut a new SONAME (.so.7) that tmux is not linked" >&2
    echo "         against." >&2
fi
loadout_enable_gcc_toolset
loadout_require_cmds autoconf automake libtool gcc make pkg-config git bzip2 strip readelf

SRCDIR="/tmp/libevent-src-${tag}"
INSTALL_PREFIX="/tmp/libevent-install-${tag}"

if [ ! -d "$SRCDIR/.git" ]; then
    echo "Cloning $CLONE_URL ..."
    git clone --filter=blob:none "$CLONE_URL" "$SRCDIR"
fi

cd "$SRCDIR"
if ! git rev-parse "$tag" >/dev/null 2>&1; then
    git fetch --tags
fi
git checkout "$tag"

rm -rf "$INSTALL_PREFIX"
[ -f configure ] || sh autogen.sh

# --disable-openssl is the load-bearing flag: it is why libevent_core no
# longer links libcrypto. --disable-libevent-regress/--disable-samples just
# skip building things this repo never ships.
./configure \
    --prefix="$INSTALL_PREFIX" \
    --disable-openssl \
    --disable-libevent-regress \
    --disable-samples \
    CFLAGS="-O2 -fstack-protector-strong"

make -j"$(nproc 2>/dev/null || echo 8)"
make install

BUILT_SO="$INSTALL_PREFIX/lib/${SONAME}.0.2"
if [ ! -f "$BUILT_SO" ]; then
    # Point-release suffix drifts across libevent tags; fall back to whatever
    # matches the SONAME stem.
    BUILT_SO=$(find "$INSTALL_PREFIX/lib" -maxdepth 1 -name "${SONAME}.*" -type f | head -1)
fi
[ -n "$BUILT_SO" ] && [ -f "$BUILT_SO" ] || {
    echo "ERROR: no ${SONAME}.* produced in $INSTALL_PREFIX/lib" >&2
    exit 1
}

echo "==> Checking NEEDED ..."
NEEDED=$(readelf -d "$BUILT_SO" | sed -n 's/.*NEEDED.*\[\(.*\)\]/\1/p')
echo "$NEEDED" | sed 's/^/  /'
case "$NEEDED" in
    *crypto*|*ssl*)
        echo "ERROR: build still links OpenSSL -- --disable-openssl did not take." >&2
        exit 1
        ;;
esac
for so in $NEEDED; do
    case "$so" in
        libpthread.so.0 | libc.so.6) ;;
        *) echo "ERROR: unexpected NEEDED '$so' -- not glibc, not accounted for." >&2; exit 1 ;;
    esac
done
echo "  OK -- no OpenSSL, only glibc components"

WORK_SO="$INSTALL_PREFIX/${SONAME}"
cp "$BUILT_SO" "$WORK_SO"
strip "$WORK_SO"

loadout_report_max_glibc "$WORK_SO"

# Prove the payload's tmux binary is still fully satisfied: every non-GLIBC
# function symbol tmux imports must be exported here (mirrors build-freetype.sh's
# import/export closure check, scoped to the one consumer that matters).
TMUX_BIN="$LOADOUT_BIN_DIR/tmux"
TMUX_TMP=""
if [ ! -f "$TMUX_BIN" ]; then
    TMUX_TMP="$TMUX_BIN.tmp"
    bzip2 -dk -c "${TMUX_BIN}.bz2" > "$TMUX_TMP" 2>/dev/null && TMUX_BIN="$TMUX_TMP"
fi
if [ -f "$TMUX_BIN" ]; then
    echo "==> Checking tmux's undefined symbols against this build's exports ..."
    UNDEF=$(readelf --dyn-syms -W "$TMUX_BIN" 2>/dev/null | awk '$4=="FUNC" && $7=="UND"{print $NF}' | sort -u)
    EXPORTED=$(readelf --dyn-syms -W "$WORK_SO" 2>/dev/null | awk '$4=="FUNC"{print $NF}' | sort -u)
    MISSING=""
    for sym in $UNDEF; do
        case "$sym" in
            event_*|bufferevent_*|evutil_*|evbuffer_*|evconnlistener_*|evdns_*|evrpc_*|evhttp_*|evtimer_*|evsignal_*)
                echo "$EXPORTED" | grep -qx "$sym" || MISSING="$MISSING $sym"
                ;;
        esac
    done
    [ -z "$TMUX_TMP" ] || rm -f "$TMUX_TMP"
    if [ -n "$MISSING" ]; then
        echo "ERROR: tmux needs libevent symbols this build does not export:$MISSING" >&2
        exit 1
    fi
    echo "  OK -- all libevent symbols tmux imports are exported"
else
    echo "WARNING: no tmux binary found to check symbol closure against -- skipped." >&2
fi

echo "==> Staging ..."
bzip2 -kf "$WORK_SO"
mkdir -p "$LIB_DIR"
cp "${WORK_SO}.bz2" "$LIB_DIR/${SONAME}.bz2"
chmod 644 "$LIB_DIR/${SONAME}.bz2"

echo ""
echo "Staged: payload/$LOADOUT_PLATFORM/lib64/${SONAME}.bz2  ($(du -h "$LIB_DIR/${SONAME}.bz2" | cut -f1))"
echo ""
echo "Next:"
echo "  $REPO/build/verify-binaries tmux"
echo "  ./build/strip-all-elf-binaries"
echo "  python3.14 build/gen-content-manifest"
echo "  git add $LIB_DIR/${SONAME}.bz2 .strip-manifest .content-manifest \\"
echo "          $REPO/build/build-libevent-core.sh"
echo "  git commit -m 'fix(tmux): rebuild bundled libevent_core without OpenSSL'"
