#!/bin/sh
# Build KLayout (GDSII/OASIS layout viewer & editor) from source for
# el8.x86_64.glibc2p28.
#
# KLayout is the standard open-source mask-layout viewer/editor: GDS2, OASIS,
# DXF, CIF, MAG, LEF/DEF; a scriptable DRC and LVS engine; and a Ruby/Python
# API. It is what the existing `ruby` package was added for -- see
# ADDING_BINARIES.md "ruby 3.3.10", which describes it as "the interpreter
# KLayout embeds for DRC/LVS scripting". That intent had never been carried out.
#
# LAYOUT: KLayout installs FLAT -- one directory holding the `klayout` binary,
# 12 strm* batch tools, ~35 libklayout_*.so (plus their .so/.so.0/.so.0.30
# symlink chains), db_plugins/, lay_plugins/, and pymod/ (the standalone
# `import klayout` Python package). We ship that tree verbatim under
# <prefix>/lib/klayout/ and put 13 copies of build/klayout/klayout in bin/,
# which dispatch on basename -- the wezterm/vcd-toggle-profiler shape.
#
# EMBEDDED INTERPRETERS -- both, deliberately:
#   Ruby   from the loadout `ruby` package (libruby.so.3.3, RPATH $ORIGIN).
#          Required, not optional: KLayout's DRC and LVS runsets ARE Ruby, so
#          -noruby would remove the main reason to ship KLayout in an EDA flow.
#   Python from `portable-python` (libpython3.14.so.1.0 in <prefix>/lib).
#
# HOW THE RUBY HEADERS ARE OBTAINED -- do NOT switch the build box's dnf module
# stream. EL8's default ruby stream is 2.5 and the loadout ships 3.3, so
# `dnf module reset ruby && dnf module enable ruby:3.3` would replace the
# system interpreter as a side effect. Instead this script fetches the
# ruby-devel/ruby/ruby-libs RPMs from the ruby:3.3 stream BY DIRECT URL and
# extracts them to a temp tree -- exactly the technique build/build-ruby.sh
# already uses. Nothing on the build machine changes.
#
# Note the extracted ruby 3.3 interpreter cannot simply be run: `-rrbconfig`
# loads the SYSTEM /usr/share/rubygems (2.5's), which dies with
# "undefined method `=~' for an instance of Integer". Pass --disable-gems when
# probing it, or pass -rbvers explicitly as this script does.
#
# THE LINK TRAP -- LD_LIBRARY_PATH is load-bearing at BUILD time. libpython
# lives in ~/.local/lib, which is not on ld's search path. libklayout_pya.so
# itself links fine (shared objects tolerate undefined symbols), but when the
# strm* "buddy" executables link -lklayout_pya, ld must resolve its DT_NEEDED
# libpython3.14.so.1.0 transitively, cannot find it, and the build dies with
# ~200 "undefined reference to `PyList_GetItem'" errors after ~20 minutes of
# compiling. Exporting LD_LIBRARY_PATH=<portable-python lib> fixes it. This is
# NOT a runtime path -- the deployed RPATHs below are what resolve libpython on
# a user's machine.
#
# QT MODULES: built against the Qt5 5.15.3 already in gui_libs. Disabled
# because their libs are NOT bundled: uitools (no lib at all on EL8), designer,
# multimedia, sql. Kept: core/gui/widgets/network/svg/printsupport/xml. The
# consequence of -without-qt-uitools/-without-qt-designer is that KLayout macros
# cannot load .ui files at run time; everything else, including the macro IDE,
# works. HAVE_QT_XML pulls in Qt5XmlPatterns, which was NOT previously bundled
# -- this build adds libQt5XmlPatterns.so.5 to gui_libs. Do not "solve" that
# with -without-qt-xml: KLayout reads .lyp layer-property files and .lym macros
# as XML, and with neither QtXml nor expat there is no XML parser at all.
#
# -nolibgit2: HAVE_GIT2 defaults ON and drives KLayout's Salt package manager,
# which downloads packages over the network. Useless in an offline deployment
# and libgit2 is EPEL-only on EL8, so it is off.
#
# Prerequisites on the build machine (EL8):
#   dnf install qt5-qtbase-devel qt5-qtsvg-devel qt5-qtxmlpatterns-devel \
#               gcc-c++ make which curl rpm-build cpio
#   plus `loadout install portable-python` (headers + libpython3.14.so).
#   NOTE: qt5-qtxmlpatterns-devel is easy to miss -- without it qmake stops with
#   "Project ERROR: Unknown module(s) in QT: xmlpatterns".
#
# Policy: always build from a stable tagged release.
#
# Usage (run from any directory):
#   ./build/build-klayout.sh --tag v0.30.10

set -eu

REPO="$(cd "$(dirname "$0")/.." && pwd)"
PLATFORM_DIR="$REPO/payload/el8.x86_64.glibc2p28"
LIB64_DIR="$PLATFORM_DIR/lib64"
RUNTIME_DIR="$PLATFORM_DIR/runtime"
PATCHELF="${HOME}/.local/bin/patchelf"
DOWNLOADS_LOG="$REPO/assurance/downloads.log"
MIRROR="https://repo.almalinux.org/almalinux/8/AppStream/x86_64/os/Packages"
TAG=""
# Ruby RPM NVR + module context, kept in step with build/build-ruby.sh. Find the
# current values with: dnf module info ruby:3.3
RUBY_TAG="3.3.10-7"
RUBY_CONTEXT="module_el8.10.0+4210+b037b1ec"
RUBYGEMS_VER="3.5.22"

while [ "$#" -gt 0 ]; do
    case "$1" in
        --tag)
            shift
            [ "$#" -gt 0 ] || { echo "missing value for --tag" >&2; exit 2; }
            TAG="$1"
            ;;
        --ruby-tag)
            shift
            [ "$#" -gt 0 ] || { echo "missing value for --ruby-tag" >&2; exit 2; }
            RUBY_TAG="$1"
            ;;
        --ruby-context)
            shift
            [ "$#" -gt 0 ] || { echo "missing value for --ruby-context" >&2; exit 2; }
            RUBY_CONTEXT="$1"
            ;;
        -h|--help)
            sed -n '2,/^$/p' "$0"
            exit 0
            ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done

if [ -z "$TAG" ]; then
    echo "ERROR: --tag is required. Specify a stable release tag, e.g.:" >&2
    echo "  $0 --tag v0.30.10" >&2
    echo "" >&2
    echo "Stable releases: https://github.com/KLayout/klayout/tags" >&2
    echo "" >&2
    echo "Policy: this project ships stable releases only." >&2
    exit 1
fi

case "$TAG" in
    v[0-9]*) ;;
    *) echo "ERROR: expected a vX.Y.Z tag, got: $TAG" >&2; exit 1 ;;
esac

VERSION="${TAG#v}"

# The names installed into bin/ as launchers. Enumerated so an upstream change
# to the tool set is a build failure, not a silent payload diff.
LAUNCHERS="klayout strm2cif strm2dxf strm2gds strm2gdstxt strm2lstr strm2mag strm2oas strm2txt strmclip strmcmp strmrun strmxor"
NUM_LAUNCHERS=13

if [ -r /opt/rh/gcc-toolset-14/enable ]; then
    # shellcheck disable=SC1091
    . /opt/rh/gcc-toolset-14/enable
fi

need() {
    command -v "$1" >/dev/null 2>&1 || {
        printf 'missing required command: %s\n' "$1" >&2
        exit 1
    }
}

need gcc
need g++
need make
need git
need curl
need rpm2cpio
need cpio
need pkg-config
need readelf
need strip
need "$PATCHELF"

QMAKE=/usr/bin/qmake-qt5
[ -x "$QMAKE" ] || { echo "ERROR: $QMAKE not found -- dnf install qt5-qtbase-devel" >&2; exit 1; }
pkg-config --exists Qt5XmlPatterns || {
    echo "ERROR: Qt5XmlPatterns not found by pkg-config." >&2
    echo "  dnf install qt5-qtxmlpatterns-devel" >&2
    echo "  (without it qmake stops with: Unknown module(s) in QT: xmlpatterns)" >&2
    exit 1
}

PY_PREFIX="$HOME/.local"
PY_INC="$PY_PREFIX/include/python3.14"
PY_LIB="$PY_PREFIX/lib/libpython3.14.so"
[ -f "$PY_INC/Python.h" ] || {
    echo "ERROR: $PY_INC/Python.h not found." >&2
    echo "  Run: ./loadout install portable-python" >&2
    exit 1
}
[ -f "$PY_LIB" ] || { echo "ERROR: $PY_LIB not found" >&2; exit 1; }

SYS_XMLPATTERNS=/usr/lib64/libQt5XmlPatterns.so.5
[ -f "$SYS_XMLPATTERNS" ] || {
    echo "ERROR: $SYS_XMLPATTERNS not found (qt5-qtxmlpatterns)" >&2
    exit 1
}

WORK_DIR=$(mktemp -d /tmp/build-klayout-XXXXXX)
INST_DIR="/tmp/klayout-install-${VERSION}"
rm -rf "$INST_DIR"
mkdir -p "$INST_DIR"
# Keep the build + staged trees on ANY failure. This is a ~25 minute build and
# most of the steps that can fail (closure check, RPATHs, smokes, packaging) come
# AFTER it; deleting the tree on the way out turns a one-line fix into another
# full rebuild. Only a fully successful run cleans up.
SUCCESS=0
cleanup() {
    if [ "$SUCCESS" = 1 ]; then
        rm -rf "$WORK_DIR" "$INST_DIR"
    else
        echo "" >&2
        echo "NOTE: artefacts kept for inspection (rm them yourself when done):" >&2
        echo "  $WORK_DIR      logs + staged tree" >&2
        echo "  $INST_DIR      raw install" >&2
    fi
}
trap cleanup EXIT

# ---------------------------------------------------------------- ruby headers
echo "==> Fetching ruby $RUBY_TAG RPMs (ruby:3.3 stream, by URL -- no module switch) ..."
RB_TREE="$WORK_DIR/ruby-tree"
mkdir -p "$RB_TREE"
# ruby-devel: headers. ruby-libs: libruby + stdlib. ruby: the interpreter, used
# only to derive the ABI version code (so a ruby bump cannot silently leave
# KLayout built against a stale number). rubygems: needed because ruby's
# gem_prelude requires rubygems at startup, and without a 3.3 copy on RUBYLIB it
# reaches /usr/share/rubygems (EL8's 2.5) and dies with
# "undefined method `=~' for an instance of Integer".
for nvr in "ruby-devel-${RUBY_TAG}" "ruby-libs-${RUBY_TAG}" "ruby-${RUBY_TAG}" \
           "rubygems-${RUBYGEMS_VER}-${RUBY_TAG##*-}"; do
    case "$nvr" in
        rubygems-*) arch=noarch ;;
        *) arch=x86_64 ;;
    esac
    url="$MIRROR/${nvr}.${RUBY_CONTEXT}.${arch}.rpm"
    out="$WORK_DIR/${nvr}.rpm"
    code=$(curl -sSL -w '%{http_code}' -o "$out" "$url")
    if [ "$code" != 200 ]; then
        echo "ERROR: HTTP $code fetching $url" >&2
        echo "  (check --ruby-tag/--ruby-context against: dnf module info ruby:3.3)" >&2
        exit 1
    fi
    # TOFU provenance, same as build/build-ruby.sh and ./build/update.
    if [ -d "$(dirname "$DOWNLOADS_LOG")" ]; then
        printf '%s\t%s\t%s\n' \
            "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$url" \
            "$(sha256sum "$out" | cut -d' ' -f1)" >> "$DOWNLOADS_LOG"
    fi
    ( cd "$RB_TREE" && rpm2cpio "$out" | cpio -idm 2>/dev/null )
    echo "  fetched ${nvr}"
done
RB_INC="$RB_TREE/usr/include"
RB_LIB="$RB_TREE/usr/lib64/libruby.so.3.3.10"
[ -f "$RB_INC/ruby.h" ] || { echo "ERROR: $RB_INC/ruby.h missing" >&2; exit 1; }
[ -f "$RB_INC/ruby/config.h" ] || { echo "ERROR: $RB_INC/ruby/config.h missing" >&2; exit 1; }
[ -f "$RB_LIB" ] || { echo "ERROR: $RB_LIB missing" >&2; exit 1; }

# The SONAME must match the libruby the loadout actually ships, or KLayout will
# record a DT_NEEDED nothing satisfies at run time.
RB_SONAME=$(readelf -d "$RB_LIB" | sed -n 's/.*SONAME.*\[\(.*\)\].*/\1/p')
[ -f "$LIB64_DIR/${RB_SONAME}.bz2" ] || {
    echo "ERROR: linking against SONAME $RB_SONAME but $LIB64_DIR/${RB_SONAME}.bz2" >&2
    echo "is not in the payload. Rebuild the ruby package first (build/build-ruby.sh)." >&2
    exit 1
}
echo "  ruby SONAME $RB_SONAME matches the bundled payload lib"

# Derive the version code from the interpreter rather than hardcoding it, so a
# ruby bump does not silently build KLayout against a stale ABI number.
RB_BIN="$RB_TREE/usr/bin/ruby"
if [ -x "$RB_BIN" ]; then
    RB_VERS=$(LD_LIBRARY_PATH="$RB_TREE/usr/lib64" \
        RUBYLIB="$RB_TREE/usr/share/ruby:$RB_TREE/usr/lib64/ruby" \
        "$RB_BIN" --disable-gems -rrbconfig -e \
        "c=RbConfig::CONFIG; puts (c['MAJOR']||0).to_i*10000+(c['MINOR']||0).to_i*100+(c['TEENY']||0).to_i")
else
    RB_VERS=""
fi
case "$RB_VERS" in
    [0-9][0-9][0-9][0-9][0-9]) ;;
    *) echo "ERROR: could not derive ruby version code (got '$RB_VERS')" >&2; exit 1 ;;
esac
echo "  ruby version code: $RB_VERS"

# ------------------------------------------------------------------ klayout src
echo "==> Cloning klayout ${TAG} ..."
git clone --depth 1 --branch "$TAG" https://github.com/KLayout/klayout.git \
    "$WORK_DIR/klayout" >/dev/null 2>&1
SRC="$WORK_DIR/klayout"
cd "$SRC"

# shellcheck disable=SC1091
. ./version.sh
if [ "$KLAYOUT_VERSION" != "$VERSION" ]; then
    echo "ERROR: tag $TAG carries KLAYOUT_VERSION $KLAYOUT_VERSION, expected $VERSION" >&2
    exit 1
fi

echo "==> Building (this takes ~25 min) ..."
# See "THE LINK TRAP" in the header: build-time only, never a runtime path.
export LD_LIBRARY_PATH="$PY_PREFIX/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
./build.sh \
    -qmake "$QMAKE" \
    -prefix "$INST_DIR" \
    -release \
    -rbinc "$RB_INC" -rbinc2 "$RB_INC" -rblib "$RB_LIB" -rbvers "$RB_VERS" \
    -python "$PY_PREFIX/bin/python3.14" -pyinc "$PY_INC" -pylib "$PY_LIB" \
    -without-qt-uitools -without-qt-designer -without-qt-multimedia -without-qt-sql \
    -nolibgit2 \
    -j"$(nproc 2>/dev/null || echo 2)" >"$WORK_DIR/build.log" 2>&1 || {
        echo "ERROR: build failed. Errors:" >&2
        grep -E 'undefined reference|\berror:|Error [12]$' "$WORK_DIR/build.log" \
            | head -15 >&2
        echo "(full log: $WORK_DIR/build.log)" >&2
        exit 1
    }
grep -q 'Build successfully done' "$WORK_DIR/build.log" || {
    echo "ERROR: build.sh did not report success" >&2
    tail -20 "$WORK_DIR/build.log" >&2
    exit 1
}

echo "==> Checking the installed artefact set ..."
for l in $LAUNCHERS; do
    [ -x "$INST_DIR/$l" ] || {
        echo "ERROR: expected binary missing after install: $l" >&2
        exit 1
    }
done
for d in db_plugins lay_plugins pymod; do
    [ -d "$INST_DIR/$d" ] || { echo "ERROR: $d/ missing after install" >&2; exit 1; }
done
[ -f "$INST_DIR/libklayout_drc.so" ] || {
    echo "ERROR: libklayout_drc.so missing -- no DRC engine" >&2
    exit 1
}
[ -f "$INST_DIR/libklayout_lvs.so" ] || {
    echo "ERROR: libklayout_lvs.so missing -- no LVS engine" >&2
    exit 1
}
# Symlinks-to-DIRECTORIES do not survive strip-all-elf-binaries' re-tar
# (add_tree_to_tar walks with followlinks=False and never re-emits them -- the
# firefox lesson). File symlinks are fine and there are ~171 of them.
DIRLINKS=$(find "$INST_DIR" -type l -xtype d | wc -l)
[ "$DIRLINKS" -eq 0 ] || {
    echo "ERROR: $DIRLINKS symlink(s)-to-directory in the tree; they will be" >&2
    echo "silently dropped when strip-all-elf-binaries re-tars the archive." >&2
    find "$INST_DIR" -type l -xtype d >&2
    exit 1
}
ABSLINKS=$(find "$INST_DIR" -type l -lname '/*' | wc -l)
[ "$ABSLINKS" -eq 0 ] || {
    echo "ERROR: $ABSLINKS absolute symlink(s) -- they dangle once relocated" >&2
    exit 1
}
echo "  OK: $NUM_LAUNCHERS tools, DRC + LVS engines, plugins, pymod; link shapes safe"

echo "==> Verifying nothing but RUNPATH embeds the build prefix ..."
# patchelf rewrites RUNPATH below, so a hit there is expected. A hit in a data
# file or a compiled-in data path is not, and would mean klayout needs more
# than a prefix-deriving launcher.
BAD_FILE="$WORK_DIR/prefix-hits"
: > "$BAD_FILE"
find "$INST_DIR" -type f ! -type l | while IFS= read -r f; do
    strings -a "$f" 2>/dev/null | grep -qF "$INST_DIR" || continue
    rp=$(readelf -d "$f" 2>/dev/null | grep -cF "$INST_DIR" || true)
    hits=$(strings -a "$f" | grep -cF "$INST_DIR")
    # One hit that is the RUNPATH string is fine.
    if [ "$rp" -ge 1 ] && [ "$hits" -le 1 ]; then
        continue
    fi
    printf ' %s(%s)' "$f" "$hits" >> "$BAD_FILE"
done
BAD=$(cat "$BAD_FILE")
if [ -n "$BAD" ]; then
    echo "ERROR: build prefix embedded beyond RUNPATH in:$BAD" >&2
    exit 1
fi
echo "  OK: only RUNPATH, which patchelf replaces"

# --------------------------------------------------------------------- staging
echo "==> Staging relocatable tree ..."
STAGE="$WORK_DIR/stage"
mkdir -p "$STAGE/bin" "$STAGE/lib"
cp -a "$INST_DIR" "$STAGE/lib/klayout"

echo "==> Stripping + setting RPATHs ..."
# KLayout's tree is flat at <prefix>/lib/klayout, so each depth needs its own
# hop count back to <prefix>/lib64 (bundled Qt5/ruby/X11) and <prefix>/lib
# (portable-python's libpython3.14.so.1.0).
set_rpaths() {
    _dir=$1
    _rpath=$2
    find "$_dir" -maxdepth 1 -type f ! -type l \
        \( -name '*.so' -o -name '*.so.*' -o -perm -u+x \) | while IFS= read -r f
    do
        readelf -h "$f" >/dev/null 2>&1 || continue
        strip --strip-unneeded "$f" 2>/dev/null || true
        "$PATCHELF" --set-rpath "$_rpath" "$f" 2>/dev/null || {
            echo "ERROR: patchelf failed on $f" >&2
            exit 1
        }
    done
}
# shellcheck disable=SC2016  # $ORIGIN is a literal ld.so token
set_rpaths "$STAGE/lib/klayout" '$ORIGIN:$ORIGIN/../../lib64:$ORIGIN/../../lib'
for sub in db_plugins lay_plugins; do
    # shellcheck disable=SC2016
    set_rpaths "$STAGE/lib/klayout/$sub" \
        '$ORIGIN:$ORIGIN/..:$ORIGIN/../../../lib64:$ORIGIN/../../../lib'
done
# shellcheck disable=SC2016
set_rpaths "$STAGE/lib/klayout/pymod/klayout" \
    '$ORIGIN:$ORIGIN/../..:$ORIGIN/../../../../lib64:$ORIGIN/../../../../lib'
# shellcheck disable=SC2016
set_rpaths "$STAGE/lib/klayout/pymod/pya" \
    '$ORIGIN:$ORIGIN/../..:$ORIGIN/../../../../lib64:$ORIGIN/../../../../lib'

if find "$STAGE" -type f ! -type l -exec readelf -d {} + 2>/dev/null \
        | grep -qF "$INST_DIR"; then
    echo "ERROR: a RUNPATH still points at the build prefix after patchelf" >&2
    exit 1
fi
echo "  OK: no RUNPATH references the build prefix"

echo "==> Installing launchers ..."
for l in $LAUNCHERS; do
    cp "$REPO/build/klayout/klayout" "$STAGE/bin/$l"
    chmod 755 "$STAGE/bin/$l"
done

echo "==> Bundling libQt5XmlPatterns.so.5 (new gui_libs member) ..."
XP="$WORK_DIR/libQt5XmlPatterns.so.5"
cp "$(readlink -f "$SYS_XMLPATTERNS")" "$XP"
strip "$XP" 2>/dev/null || true
# shellcheck disable=SC2016
"$PATCHELF" --set-rpath '$ORIGIN' "$XP"
bzip2 -kf "$XP"
cp "$XP.bz2" "$LIB64_DIR/libQt5XmlPatterns.so.5.bz2"
echo "  Wrote: $LIB64_DIR/libQt5XmlPatterns.so.5.bz2"

echo "==> Checking shared library closure of the staged tree ..."
# Walk EVERY ELF, not just bin/klayout: a closure check that looked at one
# binary is how libfontenc.so.1 shipped missing for Xephyr.
MISSING=""
for f in $(find "$STAGE/lib/klayout" -type f ! -type l -name '*.so*'; \
           for l in $LAUNCHERS; do echo "$STAGE/lib/klayout/$l"; done); do
    readelf -h "$f" >/dev/null 2>&1 || continue
    for so in $(readelf -d "$f" 2>/dev/null \
            | sed -n 's/.*NEEDED.*\[\(.*\)\].*/\1/p' | sort -u); do
        case "$so" in
            ld-linux*) continue ;;
        esac
        # Satisfied from inside KLayout's own tree. This must be a real lookup,
        # not a name pattern: besides libklayout_*/libbd_*, the format readers
        # in db_plugins/ and lay_plugins/ are plainly named (libgds2.so.0,
        # liboasis.so.0, liblefdef.so.0, libmag.so.0, libdxf.so.0, libcif.so.0,
        # libpcb.so.0, libmaly.so.0, liblstream.so.0, libnet_tracer.so.0) and
        # each *_ui plugin NEEDs its non-UI half. RPATH $ORIGIN/$ORIGIN/.. is
        # what resolves them at run time.
        if [ -n "$(find "$STAGE/lib/klayout" -name "$so" -print -quit)" ]; then
            continue
        fi
        if [ -f "$LIB64_DIR/${so}.bz2" ] || [ -f "$LIB64_DIR/${so}" ]; then
            continue
        fi
        case "$so" in
            # glibc + C++ runtime: never bundled.
            libc.so.6|libm.so.6|libdl.so.2|libpthread.so.0|librt.so.1|libresolv.so.2) continue ;;
            libstdc++.so.6|libgcc_s.so.1) continue ;;
            # GLVND dispatchers: must come from the host display stack.
            libGL.so.1|libGLX.so.0|libGLdispatch.so.0) continue ;;
            # portable-python (installed to <prefix>/lib, reached by RPATH).
            libpython3.14.so.1.0) continue ;;
            # EL8 base, transitively required by the bundled glib/Qt stack.
            liblzma.so.5|liblz4.so.1|libsystemd.so.0|libselinux.so.1) continue ;;
            libblkid.so.1|libmount.so.1|libcap.so.2|libffi.so.6) continue ;;
            libgnutls.so.30|libgcrypt.so.20|libgpg-error.so.0) continue ;;
            libnettle.so.6|libhogweed.so.4|libtasn1.so.6|libp11-kit.so.0) continue ;;
            libidn2.so.0|libunistring.so.2) continue ;;
            # EL8 base openssl + krb5 (pulled by openssl/curl on every node).
            libssl.so.1.1|libcrypto.so.1.1) continue ;;
            libgssapi_krb5.so.2|libkrb5.so.3|libkrb5support.so.0) continue ;;
            libk5crypto.so.3|libcom_err.so.2|libkeyutils.so.1) continue ;;
        esac
        MISSING="$MISSING ${so}($(basename "$f"))"
    done
done
if [ -n "$MISSING" ]; then
    echo "ERROR: unbundled, undocumented shared libraries:$MISSING" >&2
    echo "Bundle them in payload/*/lib64 or add them to the allow-list above" >&2
    echo "with a reason -- do not leave the decision implicit." >&2
    exit 1
fi
echo "  OK: closure satisfied by bundled libs + documented EL8 base"

echo "==> Checking glibc symbol floor ..."
GLIBC_BAD="$WORK_DIR/glibc-too-new"
: > "$GLIBC_BAD"
find "$STAGE/lib/klayout" -maxdepth 1 -type f ! -type l | while IFS= read -r f; do
    readelf -h "$f" >/dev/null 2>&1 || continue
    MAX_GLIBC="$(readelf -V "$f" 2>/dev/null \
        | grep -oE 'GLIBC_[0-9]+\.[0-9]+' | sort -V | tail -1)"
    case "$MAX_GLIBC" in
        ''|GLIBC_2.2[0-8]|GLIBC_2.1[0-9]|GLIBC_2.[0-9]) ;;
        *) printf ' %s(%s)' "$(basename "$f")" "$MAX_GLIBC" >> "$GLIBC_BAD" ;;
    esac
done
if [ -s "$GLIBC_BAD" ]; then
    echo "ERROR: binaries needing symbols newer than GLIBC_2.28:$(cat "$GLIBC_BAD")" >&2
    exit 1
fi
echo "  OK: all binaries within GLIBC_2.28"

echo "==> Verifying staged tree functionally (GDS write -> read -> XOR) ..."
# `klayout -v` proves nothing: it prints a compiled-in string and never touches
# the db plugins, the Ruby interpreter, or the stream writers. Drive a real
# batch Ruby script through the staged launcher instead. -zz is batch mode with
# no GUI and no window, so this works headless.
SMOKE="$WORK_DIR/smoke"
mkdir -p "$SMOKE"
cat > "$SMOKE/gen.rb" <<'RBEOF'
# Build a two-layer layout, save as GDS2 and OASIS, read both back, and confirm
# geometry survives the round trip. Exercises db_plugins (stream writers), the
# embedded Ruby, and the core db library.
ly = RBA::Layout.new
top = ly.create_cell("TOP")
l1 = ly.layer(1, 0)
l2 = ly.layer(2, 0)
top.shapes(l1).insert(RBA::Box.new(0, 0, 1000, 2000))
top.shapes(l2).insert(RBA::Polygon.new([RBA::Point.new(0,0), RBA::Point.new(500,0), RBA::Point.new(0,500)]))
ly.write("out.gds")
ly.write("out.oas")

%w(out.gds out.oas).each do |f|
  r = RBA::Layout.new
  r.read(f)
  cell = r.cell("TOP")
  raise "#{f}: no TOP cell" unless cell
  area = cell.shapes(r.layer(1, 0)).each.map { |s| s.polygon.area }.inject(0) { |a, b| a + b }
  raise "#{f}: layer 1/0 area #{area}, expected 2000000" unless area == 2_000_000
  n = 0
  cell.shapes(r.layer(2, 0)).each { |s| n += 1 }
  raise "#{f}: layer 2/0 has #{n} shapes, expected 1" unless n == 1
  puts "#{f}: OK"
end
puts "RUBY_OK"
RBEOF
# The staged tree carries no ruby stdlib and no python stdlib -- at deploy time
# those come from the `ruby` and `portable-python` packages in the same prefix,
# and the launcher derives them from its own location. Here we hand the launcher
# the extracted ruby tree and the build box's portable-python explicitly; the
# launcher honours caller-set values. tests/prebuilt-binaries is what proves the
# launcher's own derivation, against a real installed tree.
SMOKE_ENV="RUBYLIB=$RB_TREE/usr/lib64/ruby:$RB_TREE/usr/share/ruby:$RB_TREE/usr/share/rubygems"
SMOKE_ENV="$SMOKE_ENV GEM_HOME=$RB_TREE/usr/share/gems GEM_PATH=$RB_TREE/usr/share/gems"
SMOKE_ENV="$SMOKE_ENV KLAYOUT_PYTHONHOME=$PY_PREFIX"
SMOKE_ENV="$SMOKE_ENV LD_LIBRARY_PATH=$PY_PREFIX/lib:$RB_TREE/usr/lib64"
# shellcheck disable=SC2086
SMOKE_OUT=$( cd "$SMOKE" && env -u DISPLAY -u WAYLAND_DISPLAY $SMOKE_ENV \
    HOME="$SMOKE" "$STAGE/bin/klayout" -zz -r gen.rb 2>&1 ) || {
    echo "ERROR: batch Ruby smoke failed:" >&2
    echo "$SMOKE_OUT" >&2
    exit 1
}
echo "$SMOKE_OUT" | grep -q 'RUBY_OK' || {
    echo "ERROR: batch Ruby smoke did not reach RUBY_OK:" >&2
    echo "$SMOKE_OUT" >&2
    exit 1
}
[ -s "$SMOKE/out.gds" ] && [ -s "$SMOKE/out.oas" ] || {
    echo "ERROR: GDS/OASIS output missing or empty" >&2
    exit 1
}
echo "  OK: GDS2 + OASIS written and read back with correct geometry"

echo "==> Verifying a strm* batch tool from the staged tree ..."
# shellcheck disable=SC2086
( cd "$SMOKE" && env -u DISPLAY $SMOKE_ENV HOME="$SMOKE" \
    "$STAGE/bin/strm2oas" out.gds converted.oas >"$WORK_DIR/strm.log" 2>&1 ) || {
    echo "ERROR: strm2oas failed:" >&2; cat "$WORK_DIR/strm.log" >&2; exit 1
}
[ -s "$SMOKE/converted.oas" ] || { echo "ERROR: strm2oas wrote nothing" >&2; exit 1; }
echo "  OK: strm2oas converted GDS -> OASIS"

echo "==> Verifying the embedded Python interpreter ..."
cat > "$SMOKE/gen.py" <<'PYEOF'
import pya
ly = pya.Layout()
top = ly.create_cell("TOP")
top.shapes(ly.layer(3, 0)).insert(pya.Box(0, 0, 100, 100))
ly.write("py.gds")
print("PYTHON_OK")
PYEOF
# shellcheck disable=SC2086
PY_OUT=$( cd "$SMOKE" && env -u DISPLAY -u WAYLAND_DISPLAY $SMOKE_ENV \
    HOME="$SMOKE" "$STAGE/bin/klayout" -zz -rm gen.py 2>&1 ) || {
    echo "ERROR: embedded Python smoke failed:" >&2; echo "$PY_OUT" >&2; exit 1
}
echo "$PY_OUT" | grep -q 'PYTHON_OK' || {
    echo "ERROR: embedded Python smoke did not print PYTHON_OK:" >&2
    echo "$PY_OUT" >&2
    exit 1
}
echo "  OK: embedded Python 3.14 ran and wrote a layout"

echo "==> Verifying version output ..."
# shellcheck disable=SC2086
KL_VER=$(env -u DISPLAY $SMOKE_ENV HOME="$SMOKE" "$STAGE/bin/klayout" -v 2>&1 | head -2 | tr '\n' ' ')
echo "  $KL_VER"
echo "$KL_VER" | grep -qF "$VERSION" || {
    echo "ERROR: -v does not report $VERSION" >&2
    exit 1
}

echo "==> Packaging klayout runtime ..."
rm -f "$RUNTIME_DIR/klayout.tar.bz2" "$RUNTIME_DIR"/klayout.tar.bz2.part-*
tar cjf "$RUNTIME_DIR/klayout.tar.bz2" -C "$STAGE" \
    --owner=0 --group=0 --numeric-owner \
    ./bin ./lib
echo "  Wrote: $RUNTIME_DIR/klayout.tar.bz2 ($(wc -c < "$RUNTIME_DIR/klayout.tar.bz2" | tr -d ' ') bytes)"
echo "  (strip-all-elf-binaries will chunk it into .part-NNN shards)"

echo "==> Updating packages.json ..."
python3 -c "
import sys, json
path, ver = sys.argv[1], sys.argv[2]
with open(path) as f:
    data = json.load(f)
pkgs = data['packages']
if 'klayout' in pkgs:
    pkgs['klayout']['version'] = ver
    print(f'packages.json: klayout version -> {ver}')
else:
    print('WARNING: klayout not found in packages.json, skipping version update')
with open(path, 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
" "$REPO/payload/packages.json" "$VERSION"

echo "==> Running strip-all-elf-binaries ..."
"$REPO/build/strip-all-elf-binaries"

SUCCESS=1
echo ""
echo "Done."
echo ""
echo "Produced:"
echo "  $RUNTIME_DIR/klayout.tar.bz2 (chunked)"
echo "  $LIB64_DIR/libQt5XmlPatterns.so.5.bz2"
echo ""
echo "Reminders:"
echo "  - ./loadout completion bash > envs/bash/global/completions/loadout.bash"
echo "  - build/gen-content-manifest"
echo "  - build/ADDING_BINARIES.md note is MANDATORY"
echo ""
echo "Commit with:"
echo "  git add payload/el8.x86_64.glibc2p28/runtime/klayout.tar.bz2* \\"
echo "          payload/el8.x86_64.glibc2p28/lib64/libQt5XmlPatterns.so.5.bz2 \\"
echo "          .strip-manifest .content-manifest payload/packages.json \\"
echo "          build/build-klayout.sh build/klayout/klayout assurance/downloads.log"
echo "  git commit -m 'feat(payload): klayout ${VERSION} EL8 source build'"
