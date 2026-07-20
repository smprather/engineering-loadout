#!/bin/sh
# Build expect from source for el8.x86_64.glibc2p28.
#
# expect is a Tcl-based tool for automating interactive CLI programs.
# This script builds Tcl 8.6 from source first (into a staging prefix)
# so we can bundle libtcl8.6.so alongside the expect binary, removing any
# dependency on the system Tcl installation.
#
# Produces:
#   payload/el8.x86_64.glibc2p28/bin/expect.bz2  (POSIX-sh wrapper)
#   payload/el8.x86_64.glibc2p28/lib64/libtcl8.6.so.bz2
#   payload/el8.x86_64.glibc2p28/runtime/expect.tar.bz2
#     lib/expect/bin/expect.bin        (real ELF)
#     lib/expect/lib/{tcl8.6,tcl8}     (Tcl 8.6 script library; init.tcl found
#       via Tcl's <exedir>/../lib/tcl8.6 fallback -- the compiled path is this
#       build's temp prefix and is dead once deployed. Private prefix because
#       portable-python owns <prefix>/lib/tcl8.6 at a different patchlevel.)
#
# Runtime deps (bundled in this repo's lib64/):
#   libtcl8.6.so
# Runtime deps (system on EL8):
#   libm, libpthread, libdl, libc
#
# Build-time deps (system, EL8):
#   gcc, make
#
# Policy: always build from a stable tagged release.
# expect tarballs: https://sourceforge.net/projects/expect/files/Expect/
# Tcl tarballs:    https://sourceforge.net/projects/tcl/files/Tcl/
#
# Usage (run from any directory):
#   /path/to/build-expect.sh --tag 5.45.4
#   /path/to/build-expect.sh --tag 5.45.4 --tcl-version 8.6.16

set -eu

REPO="$(cd "$(dirname "$0")/.." && pwd)"
BIN_DIR="$REPO/payload/el8.x86_64.glibc2p28/bin"
LIB_DIR="$REPO/payload/el8.x86_64.glibc2p28/lib64"
PATCHELF="${HOME}/.local/bin/patchelf"

tag=""
tcl_version="8.6.16"
clean=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --tag)
            shift
            [ "$#" -gt 0 ] || { echo "missing value for --tag" >&2; exit 2; }
            tag="$1"
            ;;
        --tcl-version)
            shift
            [ "$#" -gt 0 ] || { echo "missing value for --tcl-version" >&2; exit 2; }
            tcl_version="$1"
            ;;
        --clean) clean=1 ;;
        -h|--help)
            sed -n '2,/^$/p' "$0"
            exit 0
            ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done

[ -n "$tag" ] || {
    echo "ERROR: --tag <version> required (e.g. --tag 5.45.4)" >&2
    echo "Stable tarballs: https://sourceforge.net/projects/expect/files/Expect/" >&2
    echo "Policy: stable releases only -- no git HEAD or dev builds." >&2
    exit 2
}

if [ -r /opt/rh/gcc-toolset-14/enable ]; then
    # shellcheck disable=SC1091
    . /opt/rh/gcc-toolset-14/enable
fi

need() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "missing required command: $1 -- install prerequisite packages listed in this script's header" >&2
        exit 1
    }
}

need gcc
need make
need curl
need bzip2

# -- Tcl 8.6 ------------------------------------------------------------------

TCL_INSTALL="/tmp/tcl-install-${tcl_version}"
TCL_SRCDIR="/tmp/tcl-src-${tcl_version}"
TCL_TARBALL="/tmp/tcl${tcl_version}-src.tar.gz"
TCL_URL="https://prdownloads.sourceforge.net/tcl/tcl${tcl_version}-src.tar.gz"

if [ ! -f "$TCL_INSTALL/lib/libtcl8.6.so" ]; then
    if [ ! -d "$TCL_SRCDIR" ]; then
        if [ ! -f "$TCL_TARBALL" ]; then
            echo "Downloading Tcl ${tcl_version}..."
            curl -fsSL "$TCL_URL" -o "$TCL_TARBALL"
        fi
        mkdir -p "$TCL_SRCDIR"
        tar -xzf "$TCL_TARBALL" -C "$TCL_SRCDIR" --strip-components=1
    fi
    cd "$TCL_SRCDIR/unix"
    if [ "$clean" -eq 1 ]; then
        [ -f Makefile ] && make distclean || true
    fi
    ./configure \
        --prefix="$TCL_INSTALL" \
        --enable-shared \
        --disable-static \
        CFLAGS="-O2 -fstack-protector-strong"
    make -j"$(nproc 2>/dev/null || echo 8)"
    make install
    echo "Tcl ${tcl_version} built: ${TCL_INSTALL}"
fi

# -- expect --------------------------------------------------------------------

EXPECT_SRCDIR="/tmp/expect-src-${tag}"
EXPECT_INSTALL="/tmp/expect-install-${tag}"
# expect tarball name differs from version string: expect5.45.4 -> expect5.45.4.tar.gz
EXPECT_NAME="expect${tag}"
EXPECT_TARBALL="/tmp/${EXPECT_NAME}.tar.gz"
EXPECT_URL="https://sourceforge.net/projects/expect/files/Expect/${tag}/${EXPECT_NAME}.tar.gz/download"

if [ ! -d "$EXPECT_SRCDIR" ]; then
    if [ ! -f "$EXPECT_TARBALL" ]; then
        echo "Downloading expect ${tag}..."
        curl -fsSL "$EXPECT_URL" -o "$EXPECT_TARBALL"
    fi
    mkdir -p "$EXPECT_SRCDIR"
    tar -xzf "$EXPECT_TARBALL" -C "$EXPECT_SRCDIR" --strip-components=1
fi

cd "$EXPECT_SRCDIR"
if [ "$clean" -eq 1 ]; then
    [ -f Makefile ] && make distclean || true
fi

rm -rf "$EXPECT_INSTALL"

# GCC 14 made -Wimplicit-int, -Wimplicit-function-declaration, and
# -Wincompatible-pointer-types errors. expect 5.45.4 configure generates
# C89-style test code that trips these, causing PTY detection to fail.
# Suppress them so autoconf tests pass and configure picks the right pty_ file.
#
# exp_chan.c uses the old Tcl_ChannelType field order where blockModeProc
# occupied the second slot (now reserved for TCL_CHANNEL_VERSION_*). Patch
# it to insert TCL_CHANNEL_VERSION_4 and move blockModeProc to position 12.
COMPAT_CFLAGS="-O2 -fstack-protector-strong -Wno-implicit-int -Wno-implicit-function-declaration -Wno-return-type -Wno-incompatible-pointer-types"

./configure \
    --prefix="$EXPECT_INSTALL" \
    --with-tcl="$TCL_INSTALL/lib" \
    --with-tclinclude="$TCL_INSTALL/include" \
    CFLAGS="$COMPAT_CFLAGS"

# Patch exp_chan.c: modern Tcl requires TCL_CHANNEL_VERSION_4 in the second
# field; old expect put blockModeProc there directly.
EXP_CHAN="$EXPECT_SRCDIR/exp_chan.c"
if grep -q 'ExpBlockModeProc.*\* Version' "$EXP_CHAN" 2>/dev/null || \
   grep -q '"exp".*ExpBlockModeProc' "$EXP_CHAN" 2>/dev/null || \
   ! grep -q 'TCL_CHANNEL_VERSION' "$EXP_CHAN" 2>/dev/null; then
    python3 - "$EXP_CHAN" <<'PYEOF'
import re, sys
path = sys.argv[1]
src = open(path).read()
# Replace the Tcl_ChannelType initializer block
old = re.search(
    r'(Tcl_ChannelType\s+expChannelType\s*=\s*\{[^}]+\})\s*;',
    src, re.DOTALL)
if old:
    replacement = '''Tcl_ChannelType expChannelType = {
    "exp",                      /* Type name. */
    TCL_CHANNEL_VERSION_4,      /* Version. */
    ExpCloseProc,               /* Close proc. */
    ExpInputProc,               /* Input proc. */
    ExpOutputProc,              /* Output proc. */
    NULL,                       /* Seek proc. */
    NULL,                       /* Set option proc. */
    NULL,                       /* Get option proc. */
    ExpWatchProc,               /* Initialize notifier. */
    ExpGetHandleProc,           /* Get OS handles out of channel. */
    NULL,                       /* Close2 proc */
    ExpBlockModeProc,           /* Set blocking/nonblocking mode.*/
}'''
    src = src[:old.start()] + replacement + src[old.end()-1:]
    open(path, 'w').write(src)
    print("exp_chan.c: patched Tcl_ChannelType initializer for modern Tcl")
else:
    print("exp_chan.c: pattern not found -- may already be patched or different version")
PYEOF
fi

make -j"$(nproc 2>/dev/null || echo 8)"
make install

# expect's Makefile installs the binary into the Tcl prefix dir, not --prefix.
EXPECT_BIN="$TCL_INSTALL/bin/expect"
[ -f "$EXPECT_BIN" ] || EXPECT_BIN="$EXPECT_INSTALL/bin/expect"

echo ""
echo "Build complete: $("$EXPECT_BIN" -v 2>&1 | head -1)"
echo ""

# -- package expect wrapper ----------------------------------------------------

# bin/expect is a POSIX-sh shim that execs lib/expect/bin/expect.bin. The real
# ELF must live inside the private lib/expect prefix so Tcl's own
# <exedir>/../lib/tcl8.6 fallback finds the bundled script library (see the
# runtime archive step below). No TCL_LIBRARY export -- expect spawns child
# processes for a living and portable-python bundles a different Tcl
# patchlevel, so environment leakage would break other Tcl programs.
bzip2 -c "$REPO/build/expect/expect" > "$BIN_DIR/expect.bz2"
echo "Installed: $BIN_DIR/expect.bz2 (wrapper)"

# -- package libtcl8.6.so -----------------------------------------------------

TCL_LIB="$TCL_INSTALL/lib/libtcl8.6.so"
LIBWORK="/tmp/libtcl8.6_work_${tcl_version}"
rm -f "$LIBWORK"
cp "$TCL_LIB" "$LIBWORK"
chmod u+w "$LIBWORK"
strip "$LIBWORK"
"$PATCHELF" --set-rpath '$ORIGIN' "$LIBWORK"
bzip2 -kf "$LIBWORK"
cp "${LIBWORK}.bz2" "$LIB_DIR/libtcl8.6.so.bz2"
rm -f "$LIBWORK" "${LIBWORK}.bz2"
echo "Installed: $LIB_DIR/libtcl8.6.so.bz2"

# -- package the private expect runtime (ELF + Tcl 8.6 script library) ---------

# libtcl8.6's compiled tcl_library is this build's temp prefix, which vanishes
# once deployed; without the script library on disk every expect start dies
# with "Tcl_Init failed: Can't find a usable init.tcl" (shipped that way for a
# while -- the build box masked it because the temp prefix still existed).
#
# The script library must NOT install to <prefix>/lib/tcl8.6: portable-python
# owns that path with a different Tcl patchlevel, and init.tcl does
# `package require -exact`, so cross-clobbering breaks one side or the other.
# Instead the real ELF lives at lib/expect/bin/expect.bin with its own trees at
# lib/expect/lib/{tcl8.6,tcl8}; Tcl's <exedir>/../lib/tcl8.6 fallback resolves
# inside that private prefix. lib/tcl8 carries the stdlib .tm modules (http,
# msgcat, ...). Extension dirs (itcl, sqlite3, tdbc*, thread) are deliberately
# not shipped.
RUNTIME_DIR="$REPO/payload/el8.x86_64.glibc2p28/runtime"
mkdir -p "$RUNTIME_DIR"
STAGE="/tmp/expect-stage-${tag}"
rm -rf "$STAGE"
mkdir -p "$STAGE/lib/expect/bin" "$STAGE/lib/expect/lib"
cp "$EXPECT_BIN" "$STAGE/lib/expect/bin/expect.bin"
chmod 755 "$STAGE/lib/expect/bin/expect.bin"
strip "$STAGE/lib/expect/bin/expect.bin"
# lib/expect/bin -> up three levels to the install prefix for lib64/lib
"$PATCHELF" --set-rpath '$ORIGIN/../../../lib64:$ORIGIN/../../../lib' \
    "$STAGE/lib/expect/bin/expect.bin"
cp -a "$TCL_INSTALL/lib/tcl8.6" "$STAGE/lib/expect/lib/tcl8.6"
cp -a "$TCL_INSTALL/lib/tcl8" "$STAGE/lib/expect/lib/tcl8"
tar cjf "$RUNTIME_DIR/expect.tar.bz2" -C "$STAGE" ./lib
echo "Installed: $RUNTIME_DIR/expect.tar.bz2"

# -- verify the staged layout without build-box masking ------------------------

# The compiled-in library path ($TCL_INSTALL) still exists on the build box and
# would satisfy Tcl_Init even if the archive were broken. Hide it during the
# staged run so the <exedir>/../lib/tcl8.6 fallback is what gets exercised.
mkdir -p "$STAGE/bin" "$STAGE/lib64"
bunzip2 -c "$BIN_DIR/expect.bz2" > "$STAGE/bin/expect"
chmod 755 "$STAGE/bin/expect"
bunzip2 -c "$LIB_DIR/libtcl8.6.so.bz2" > "$STAGE/lib64/libtcl8.6.so"
bunzip2 -c "$LIB_DIR/libexpect5.45.4.so.bz2" > "$STAGE/lib64/libexpect5.45.4.so"
mv "$TCL_INSTALL" "${TCL_INSTALL}.verify-hidden"
VERIFY_STATUS=0
VERIFY_OUT=$(cd /tmp && env -i PATH=/usr/bin:/bin HOME=/tmp \
    "$STAGE/bin/expect" -c 'spawn /bin/echo loadout-expect-smoke; expect eof; puts verified-ok' 2>&1) \
    || VERIFY_STATUS=$?
mv "${TCL_INSTALL}.verify-hidden" "$TCL_INSTALL"
if [ "$VERIFY_STATUS" -ne 0 ] || ! printf '%s' "$VERIFY_OUT" | grep -q 'verified-ok'; then
    echo "ERROR: staged expect verify failed (Tcl script library not relocatable?):" >&2
    printf '%s\n' "$VERIFY_OUT" >&2
    exit 1
fi
echo "Staged verify OK"
rm -rf "$STAGE"

# -- update packages.json version ---------------------------------------------

TOOLS_JSON="$REPO/payload/packages.json"
python3 -c "
import re, sys
path = sys.argv[1]; ver = sys.argv[2]
txt = open(path).read()
new = re.sub(
    r'(\"expect\".*?\"version\":\s*\")([^\"]*)(\")',
    r'\g<1>' + ver + r'\3',
    txt,
    flags=re.DOTALL,
)
open(path, 'w').write(new)
print('packages.json: expect version -> ' + ver)
" "$TOOLS_JSON" "$tag"

# -- strip manifest + glibc check ---------------------------------------------

echo "Running strip-all-elf-binaries..."
"$REPO/strip-all-elf-binaries"

MAX_GLIBC="$(readelf -V "$EXPECT_BIN" 2>/dev/null \
    | grep -oE 'GLIBC_[0-9]+\.[0-9]+' | sort -V | tail -1)"
echo "Max glibc symbol: $MAX_GLIBC (target: GLIBC_2.28)"
case "$MAX_GLIBC" in
    GLIBC_2.2[0-8]|GLIBC_2.1[0-9]|GLIBC_2.[0-9])
        echo "OK -- binary compatible with EL8 glibc 2.28" ;;
    *)
        echo "WARNING: requires newer glibc than EL8 baseline" >&2 ;;
esac

echo ""
echo "Next steps:"
echo "  $REPO/build/verify-binaries expect"
echo "  git add $BIN_DIR/expect.bz2 $LIB_DIR/libtcl8.6.so.bz2 \\"
echo "          $RUNTIME_DIR/expect.tar.bz2 $REPO/build/expect/expect \\"
echo "          $TOOLS_JSON $REPO/.strip-manifest"
echo "  git commit -m 'feat(expect): add expect ${tag} + libtcl8.6.so EL8 source build'"
