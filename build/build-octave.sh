#!/bin/sh
# Build GNU Octave from source for el8.x86_64.glibc2p28. Version via --tag.
#
# Builds without Qt, Java, OpenGL, FLTK, or X11. Uses gnuplot as the
# graphics backend (already bundled in the repo). Disables RapidJSON to
# avoid a GCC 14 compile error (assignment to read-only member).
#
# Prerequisites (install with sudo dnf):
#   gcc-toolset-14  openblas-devel  fftw-devel  hdf5-devel  libaec-devel
#   arpack-devel    suitesparse-devel  tbb-devel  glpk-devel  qhull-devel
#   portaudio-devel  libsndfile-devel  alsa-lib-devel  flac-devel
#   libgsm-devel  libogg-devel  libvorbis-devel  readline-devel
#   pcre2-devel  curl-devel  hdf5-devel  bzip2-devel
#
# Usage:
#   cd /path/to/octave-<VERSION>       # extracted source tarball
#   /path/to/build-octave.sh --tag <VERSION>
#   /path/to/build-octave.sh
#
# The script builds into /tmp/octave-install and then runs the bundling
# steps automatically.
#
# Source tarball: https://gnu.mirror.constant.com/octave/
# First packaged at 11.1.0 (2026-05-13); pass the version you are building via --tag.

set -eu

REPO="$(cd "$(dirname "$0")/.." && pwd)"
BIN_DIR="$REPO/payload/el8.x86_64.glibc2p28/bin"
LIB_DIR="$REPO/payload/el8.x86_64.glibc2p28/lib64"
RUNTIME_DIR="$REPO/payload/el8.x86_64.glibc2p28/runtime"
PATCHELF="$HOME/.local/bin/patchelf"
VERSION=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --tag) shift; [ "$#" -gt 0 ] || { echo "missing value for --tag" >&2; exit 2; }; VERSION="$1" ;;
        -h|--help) sed -n '2,/^$/p' "$0"; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done
if [ -z "$VERSION" ]; then
    echo "ERROR: --tag is required, e.g. --tag 11.3.0" >&2
    echo "  It must match the extracted source tree you are running this in," >&2
    echo "  and the octave version recorded in payload/packages.json." >&2
    exit 1
fi

# Version-scoped so successive builds cannot contaminate each other. The old
# fixed /tmp/octave-install ended up holding both 11.1.0 and 11.3.0 trees.
INSTALL_PREFIX=/tmp/octave-install-$VERSION

if [ -r /opt/rh/gcc-toolset-14/enable ]; then
    # shellcheck disable=SC1091
    . /opt/rh/gcc-toolset-14/enable
    echo "Using gcc-toolset-14: $(gcc --version | head -1)"
fi

echo "=== Configuring ==="
./configure \
    --prefix="$INSTALL_PREFIX" \
    --without-qt \
    --without-java \
    --without-opengl \
    --without-fltk \
    --without-x \
    --disable-rapidjson \
    CFLAGS="-O2" CXXFLAGS="-O2" FFLAGS="-O2"

echo "=== Building ==="
make -j"$(nproc)"

echo "=== Installing ==="
make install

echo "=== Bundling binary ==="
BIN="$INSTALL_PREFIX/bin/octave-cli-$VERSION"
TMP=/tmp/octave_bin_tmp
cp "$BIN" "$TMP"
strip "$TMP"
"$PATCHELF" --set-rpath '$ORIGIN/../lib64' "$TMP"
bzip2 -f -k "$TMP"
cp "${TMP}.bz2" "$BIN_DIR/octave.bz2"
chmod 644 "$BIN_DIR/octave.bz2"
rm -f "$TMP" "${TMP}.bz2"
echo "  binary: $(ls -lh "$BIN_DIR/octave.bz2" | awk '{print $5}')"

echo '=== Bundling octave core libs (strip + RPATH=$ORIGIN) ==='
OCTLIB="$INSTALL_PREFIX/lib/octave/$VERSION"
for lib in liboctave.so.13 liboctinterp.so.15 liboctmex.so.1; do
    tmp="/tmp/oct_${lib}_tmp"
    cp "$OCTLIB/$lib" "$tmp"
    strip "$tmp"
    "$PATCHELF" --set-rpath '$ORIGIN' "$tmp"
    bzip2 -f -k "$tmp"
    cp "${tmp}.bz2" "$LIB_DIR/${lib}.bz2"
    chmod 644 "$LIB_DIR/${lib}.bz2"
    rm -f "$tmp" "${tmp}.bz2"
    echo "  $lib: $(ls -lh "$LIB_DIR/${lib}.bz2" | awk '{print $5}')"
done

echo "=== Patchelf .oct plugin files ==="
OCTDIR="$OCTLIB/oct/x86_64-pc-linux-gnu"
for f in "$OCTDIR"/*.oct; do
    if file "$f" | grep -q ELF; then
        "$PATCHELF" --set-rpath '$ORIGIN/../../../../../lib64' "$f"
    fi
done

echo "=== Bundling dependency libs ==="
bundle_lib() {
    soname="$1"
    srcpath="$2"
    tmp="/tmp/oct_lib_${soname}_tmp"
    cp "$srcpath" "$tmp"
    strip "$tmp" 2>/dev/null || true
    # RPATH '$ORIGIN' so these resolve each other inside the installed lib64/.
    # This step was missing: the shipped libhdf5/libsz/libsatlas had $ORIGIN
    # from some earlier hand-patch, and rebuilding produced them with an EMPTY
    # rpath. Nothing on this box noticed, because a build host with system szip
    # installed silently satisfies libhdf5 -> libsz from /lib64; the clean
    # AlmaLinux container, which has no szip, failed with
    # "libsz.so.2 => not found". Textbook build-box masking -- the container is
    # the only gate that can see it.
    "$PATCHELF" --set-rpath '$ORIGIN' "$tmp"
    bzip2 -f -k "$tmp"
    cp "${tmp}.bz2" "$LIB_DIR/${soname}.bz2"
    chmod 644 "$LIB_DIR/${soname}.bz2"
    rm -f "$tmp" "${tmp}.bz2"
    echo "  $soname: $(ls -lh "$LIB_DIR/${soname}.bz2" | awk '{print $5}')"
}

# FFTW
bundle_lib libfftw3.so.3       /lib64/libfftw3.so.3
bundle_lib libfftw3_threads.so.3 /lib64/libfftw3_threads.so.3
bundle_lib libfftw3f.so.3      /lib64/libfftw3f.so.3
bundle_lib libfftw3f_threads.so.3 /lib64/libfftw3f_threads.so.3

# HDF5
bundle_lib libhdf5.so.103      /lib64/libhdf5.so.103
bundle_lib libsz.so.2          /lib64/libsz.so.2
bundle_lib libaec.so.0         /lib64/libaec.so.0

# ARPACK
bundle_lib libarpack.so.2      /lib64/libarpack.so.2

# BLAS / ATLAS
bundle_lib libopenblas.so.0    /lib64/libopenblas.so.0
bundle_lib libopenblasp.so.0   /lib64/libopenblasp.so.0
bundle_lib libsatlas.so.3      /usr/lib64/atlas/libsatlas.so.3

# TBB
bundle_lib libtbb.so.2         /lib64/libtbb.so.2

# SuiteSparse
bundle_lib libcholmod.so.3     /lib64/libcholmod.so.3
bundle_lib libumfpack.so.5     /lib64/libumfpack.so.5
bundle_lib libamd.so.2         /lib64/libamd.so.2
bundle_lib libcamd.so.2        /lib64/libcamd.so.2
bundle_lib libcolamd.so.2      /lib64/libcolamd.so.2
bundle_lib libccolamd.so.2     /lib64/libccolamd.so.2
bundle_lib libcxsparse.so.3    /lib64/libcxsparse.so.3
bundle_lib libsuitesparseconfig.so.4 /lib64/libsuitesparseconfig.so.4
bundle_lib libspqr.so.2        /lib64/libspqr.so.2

# GCC Fortran/OpenMP/QuadMath runtimes (from gcc-toolset-14 or system GCC)
bundle_lib libgfortran.so.5    /lib64/libgfortran.so.5
bundle_lib libgomp.so.1        /lib64/libgomp.so.1
bundle_lib libquadmath.so.0    /lib64/libquadmath.so.0

# GLPK / GMP / Qhull (loaded by .oct plugins)
bundle_lib libglpk.so.40       /lib64/libglpk.so.40
bundle_lib libgmp.so.10        /lib64/libgmp.so.10
bundle_lib libqhull_r.so.7     /lib64/libqhull_r.so.7

# Audio (loaded by audioread.oct, audiodevinfo.oct)
bundle_lib libasound.so.2      /lib64/libasound.so.2
bundle_lib libFLAC.so.8        /lib64/libFLAC.so.8
bundle_lib libgsm.so.1         /lib64/libgsm.so.1
bundle_lib libogg.so.0         /lib64/libogg.so.0
bundle_lib libportaudio.so.2   /lib64/libportaudio.so.2
bundle_lib libsndfile.so.1     /lib64/libsndfile.so.1
bundle_lib libvorbis.so.0      /lib64/libvorbis.so.0
bundle_lib libvorbisenc.so.2   /lib64/libvorbisenc.so.2

echo "=== Creating runtime tarball ==="
mkdir -p "$RUNTIME_DIR"
cd "$INSTALL_PREFIX"
tar -cjf /tmp/octave-runtime.tar.bz2 \
    --exclude="./share/octave/$VERSION/doc" \
    ./share/octave/$VERSION/ \
    ./lib/octave/$VERSION/oct/ \
    ./libexec/octave/$VERSION/
cp /tmp/octave-runtime.tar.bz2 "$RUNTIME_DIR/octave.tar.bz2"
chmod 644 "$RUNTIME_DIR/octave.tar.bz2"
echo "  runtime: $(ls -lh "$RUNTIME_DIR/octave.tar.bz2" | awk '{print $5}')"

echo ""
echo "=== Done. Run next steps: ==="
echo "  cd $REPO && ./build/strip-all-elf-binaries"
echo "  git add payload/el8.x86_64.glibc2p28/ .strip-manifest"
echo "  git commit"
