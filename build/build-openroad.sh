#!/bin/sh
# OpenROAD -- RTL-to-GDS place & route engine, EL8 source build.
#   https://github.com/The-OpenROAD-Project/OpenROAD   (BSD-3-Clause)
#
# Ships `openroad` (the engine, Tcl + Python scriptable) and `sta` (standalone
# OpenSTA timing), plus the 10 COIN-OR/SCIP solver libs they need.
#
# ── WHY THIS IS A LONG SCRIPT ────────────────────────────────────────────────
# Nothing OpenROAD 26Q3 needs exists on EL8 at a usable version. Ten
# dependencies are built from source here before OpenROAD itself. That is not
# gold-plating: EL8 ships gcc 8.5 (OpenROAD needs C++20), bison 3.0.4 (needs
# >=3.2), swig 3.0.12 (needs >=4.3), Boost 1.66 with no CMake config at all, and
# no OR-Tools whatsoever. Upstream's own DependencyInstaller.sh has a RHEL-8
# branch but its x86_64 path 404s: it downloads a prebuilt or-tools named for
# the distro, and google/or-tools publishes AlmaLinux-8 only for **aarch64**.
#
# ── THE THREE THINGS THAT WILL BITE YOU ──────────────────────────────────────
#
# 1. OR-TOOLS MUST BE BUILT WITH STATIC DEPS.
#    cmake/dependencies/CMakeLists.txt HARDCODES `set(BUILD_SHARED_LIBS ON)` for
#    its FetchContent deps. It is not an option; -DBUILD_SHARED_LIBS=OFF at the
#    top level reaches libortools but not them. Left alone, openroad needs 111
#    shared libraries, ~100 of them abseil, none present on EL8. Patching that
#    one line drops the closure to 26 NEEDED, 15 of which are EL8 base.
#    -DBUILD_ZLIB=OFF does NOT help -- it is a CMAKE_DEPENDENT_OPTION forced
#    back ON by BUILD_DEPS.
#
# 2. THE TCL TRAP -- this is the `expect` hazard in this repo, same shape, and
#    a full install contains THREE different Tcl 8.6 patchlevels:
#
#      lib64/libtcl8.6.so       8.6.16   bundled for expect
#      lib/libtcl8.6.so         8.6.17   portable-python
#      lib/tcl8.6/  (scripts)   8.6.17   portable-python -- the ONLY script tree
#                                        on openroad's search path
#      /usr/lib64/libtcl8.6.so  8.6.8    EL8 system
#
#    init.tcl does `package require -exact`, so the library and the script tree
#    must be the SAME patchlevel. Only the lib/ pair matches. Hence the RPATH
#    below is `$ORIGIN/../lib:$ORIGIN/../lib64` -- **lib FIRST**, the reverse of
#    this repo's usual pair. With the usual order the 8.6.16 copy in lib64 wins
#    and openroad dies with "Can't find a usable init.tcl" on the first real
#    command while `-version` keeps printing 26Q3.
#
#    That is not hypothetical: it is exactly what shipped past a build-box smoke
#    and was caught only by the clean-container gate, because the build-tree
#    binary's RUNPATH pointed straight at portable-python's lib dir while the
#    PACKAGED binary's did not. The smoke below now runs on the packaged
#    artifacts for that reason.
#
#    So: `depends: [portable-python]` (it supplies libpython3.14, libtcl8.6 AND
#    the matching script tree) + lib-first RPATH. Verified with no wrapper and
#    no TCL_LIBRARY export, so the repo's standing rule against exporting it
#    survives. DO NOT "fix" a future Tcl failure by adding either -- fix the
#    depend or the RPATH order.
#
# 3. `openroad -version` PROVES NOTHING. It prints `26Q3` from a binary that
#    cannot load Tcl, cannot read a LEF, and would fail on the first real
#    command. The smoke below reads a real LEF+DEF and queries the resulting
#    database through the Tcl API.
#
# Other version pins that are NOT arbitrary:
#   Boost 1.87   not upstream's 1.89 -- OR-Tools compiles its internals against
#                1.87, and one Boost in the link beats two ODR-conflicting ones.
#   yaml-cpp 0.6.3  not 0.8.0 -- 0.8 exports only `yaml-cpp::yaml-cpp`, while
#                OpenROAD links the bare `yaml-cpp` target, so 0.8 fails with
#                `cannot find -lyaml-cpp`. 0.6.3 is what EL8's EPEL ships and
#                what upstream actually tests against.
#   lemon 1.3.1  needs a patch: it hardcodes `CMAKE_POLICY(SET CMP0048 OLD)` and
#                CMake 4 REMOVED that policy, so it is a hard error. Deleting the
#                line is safe -- lemon's project() passes no VERSION.
#   flex         NOT required, despite upstream pinning 2.6.4.
#                `find_package(FLEX)` carries no REQUIRED and the version line is
#                commented out. (flex 2.6.4 also fails to build under GCC 14.)
#
# Every cmake invocation passes -DCMAKE_POLICY_VERSION_MINIMUM=3.5: this build
# box has CMake 4.x, which hard-refuses projects declaring
# cmake_minimum_required < 3.5, and several deps still do.
#
# Usage:
#   ./build/build-openroad.sh --tag 26Q3
#   ./build/build-openroad.sh --tag 26Q3 --reuse-build   # package an existing
#                                                        # build tree, no rebuild
#
# Expect ~60-90 min from cold on 20 cores, almost all of it OR-Tools.

set -eu

REPO="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
. "$REPO/build/lib.sh"

PKG="openroad"
RELEASES_URL="https://github.com/The-OpenROAD-Project/OpenROAD/tags"
CLONE_URL="https://github.com/The-OpenROAD-Project/OpenROAD.git"

DEPS_PREFIX="${OPENROAD_DEPS_PREFIX:-/tmp/openroad-deps}"
ORTOOLS_PREFIX="${OPENROAD_ORTOOLS_PREFIX:-/tmp/or-tools-install-9.14}"
INSTALL_PREFIX="${OPENROAD_INSTALL_PREFIX:-/tmp/openroad-install-26Q3}"
JOBS="${JOBS:-$(nproc)}"

BOOST_VERSION=1.87.0
ORTOOLS_TAG=v9.14
SWIG_TAG=v4.3.0
BISON_VERSION=3.8.2
SPDLOG_TAG=v1.15.0
EIGEN_TAG=3.4
LEMON_TAG=1.3.1
CUDD_TAG=3.0.0
YAMLCPP_TAG=yaml-cpp-0.6.3
GTEST_TAG=v1.17.0

# The solver libs OR-Tools leaves shared even in a static build. These are the
# only things this package has to bundle; everything else in the closure is EL8
# base or already a loadout package (portable-python supplies libpython3.14 and
# libtcl8.6).
SOLVER_LIBS="libCbcSolver.so.2 libOsiCbc.so.2 libCbc.so.2 libCgl.so.0 \
libClpSolver.so.1 libOsiClp.so.1 libClp.so.1 libOsi.so.0 libCoinUtils.so.2 \
libscip.so.9.2"

tag=""
reuse=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --tag)
            shift
            [ "$#" -gt 0 ] || { echo "missing value for --tag" >&2; exit 2; }
            tag=$1
            ;;
        --reuse-build) reuse=1 ;;
        -h | --help) sed -n '2,80p' "$0"; exit 0 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
    shift
done

loadout_require_tag "$tag" "$0" "$RELEASES_URL" "26Q3"
loadout_require_cmds git cmake curl bzip2 strip readelf tar autoreconf

[ -r /opt/rh/gcc-toolset-14/enable ] || {
    echo "ERROR: gcc-toolset-14 not found. OpenROAD needs C++20; EL8's gcc 8.5 cannot build it." >&2
    exit 1
}

WORK=$(mktemp -d "${TMPDIR:-/tmp}/build-openroad-XXXXXX")
trap 'rm -rf "$WORK"' EXIT INT TERM

# ---------------------------------------------------------------- dependencies

build_deps() {
    echo "==> Building dependencies into $DEPS_PREFIX ..."
    mkdir -p "$DEPS_PREFIX"
    cd "$WORK"

    echo "  -- bison $BISON_VERSION (EL8 has 3.0.4; OpenROAD needs >=3.2, swig needs >=3.5)"
    curl -fsSL "https://ftp.gnu.org/gnu/bison/bison-${BISON_VERSION}.tar.gz" | tar xz
    ( cd "bison-${BISON_VERSION}" && ./configure --prefix="$DEPS_PREFIX" -q && make -j"$JOBS" -s && make install -s )

    # From here on our bison must win over the system one.
    PATH="$DEPS_PREFIX/bin:$PATH"
    export PATH

    echo "  -- swig $SWIG_TAG (EL8 has 3.0.12; OpenROAD needs >=4.3)"
    git clone -q --depth=1 -b "$SWIG_TAG" https://github.com/swig/swig.git
    ( cd swig && ./autogen.sh > /dev/null && ./configure --prefix="$DEPS_PREFIX" --with-pcre2 -q \
        && make -j"$JOBS" -s && make install -s )

    echo "  -- spdlog $SPDLOG_TAG"
    git clone -q --depth=1 -b "$SPDLOG_TAG" https://github.com/gabime/spdlog.git
    cmake -S spdlog -B spdlog/build -DCMAKE_INSTALL_PREFIX="$DEPS_PREFIX" \
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON -DSPDLOG_BUILD_EXAMPLE=OFF \
        -DSPDLOG_BUILD_TESTS=OFF -DCMAKE_BUILD_TYPE=Release > /dev/null
    cmake --build spdlog/build --target install -j"$JOBS" > /dev/null

    echo "  -- eigen $EIGEN_TAG"
    git clone -q --depth=1 -b "$EIGEN_TAG" https://gitlab.com/libeigen/eigen.git
    cmake -S eigen -B eigen/build -DCMAKE_INSTALL_PREFIX="$DEPS_PREFIX" \
        -DCMAKE_POLICY_VERSION_MINIMUM=3.5 > /dev/null
    cmake --build eigen/build --target install -j"$JOBS" > /dev/null

    echo "  -- lemon $LEMON_TAG (patched: CMP0048 OLD was removed in CMake 4)"
    git clone -q --depth=1 -b "$LEMON_TAG" https://github.com/The-OpenROAD-Project/lemon-graph.git
    sed -i '/CMAKE_POLICY(SET CMP0048 OLD)/d' lemon-graph/CMakeLists.txt
    ! grep -q "CMP0048" lemon-graph/CMakeLists.txt || {
        echo "ERROR: lemon CMP0048 patch did not apply -- upstream layout changed." >&2
        exit 1
    }
    cmake -S lemon-graph -B lemon-graph/build -DCMAKE_INSTALL_PREFIX="$DEPS_PREFIX" \
        -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
        -DCMAKE_BUILD_TYPE=Release > /dev/null
    cmake --build lemon-graph/build --target install -j"$JOBS" > /dev/null

    echo "  -- cudd $CUDD_TAG"
    git clone -q --depth=1 -b "$CUDD_TAG" https://github.com/The-OpenROAD-Project/cudd.git
    ( cd cudd && autoreconf -i > /dev/null 2>&1 \
        && ./configure --prefix="$DEPS_PREFIX" --enable-shared=no --with-pic -q \
        && make -j"$JOBS" -s install )

    echo "  -- yaml-cpp $YAMLCPP_TAG (0.8 exports only yaml-cpp::yaml-cpp; OpenROAD links the bare target)"
    git clone -q --depth=1 -b "$YAMLCPP_TAG" https://github.com/jbeder/yaml-cpp.git
    cmake -S yaml-cpp -B yaml-cpp/build -DCMAKE_INSTALL_PREFIX="$DEPS_PREFIX" \
        -DYAML_CPP_BUILD_TESTS=OFF -DYAML_CPP_BUILD_TOOLS=OFF -DYAML_CPP_BUILD_CONTRIB=OFF \
        -DBUILD_SHARED_LIBS=OFF -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
        -DCMAKE_BUILD_TYPE=Release -DCMAKE_POLICY_VERSION_MINIMUM=3.5 > /dev/null 2>&1
    cmake --build yaml-cpp/build --target install -j"$JOBS" > /dev/null 2>&1
    grep -qE "add_library\(yaml-cpp[^:]" "$DEPS_PREFIX"/lib*/cmake/yaml-cpp/yaml-cpp-targets.cmake || {
        echo "ERROR: yaml-cpp did not export the un-namespaced 'yaml-cpp' target." >&2
        echo "       OpenROAD links it by bare name; a namespaced-only export fails" >&2
        echo "       at link with 'cannot find -lyaml-cpp'." >&2
        exit 1
    }

    echo "  -- gtest $GTEST_TAG (required even with -DENABLE_TESTS=OFF)"
    git clone -q --depth=1 -b "$GTEST_TAG" https://github.com/google/googletest.git
    cmake -S googletest -B googletest/build -DCMAKE_INSTALL_PREFIX="$DEPS_PREFIX" \
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_SHARED_LIBS=OFF -DCMAKE_POLICY_VERSION_MINIMUM=3.5 > /dev/null
    cmake --build googletest/build --target install -j"$JOBS" > /dev/null

    echo "  -- boost $BOOST_VERSION (matches what OR-Tools compiles against)"
    curl -fsSL "https://archives.boost.io/release/${BOOST_VERSION}/source/boost_$(echo "$BOOST_VERSION" | tr . _).tar.gz" -o b.tgz
    tar xzf b.tgz
    ( cd "boost_$(echo "$BOOST_VERSION" | tr . _)" \
        && ./bootstrap.sh --prefix="$DEPS_PREFIX" > /dev/null 2>&1 \
        && ./b2 install -q -j"$JOBS" --with-iostreams --with-serialization --with-system \
             --with-thread --with-test --with-filesystem --with-program_options \
             link=static runtime-link=shared cxxflags=-fPIC > /dev/null 2>&1 )
}

build_ortools() {
    echo "==> Building OR-Tools $ORTOOLS_TAG (static deps) into $ORTOOLS_PREFIX ..."
    cd "$WORK"
    git clone -q --depth=1 -b "$ORTOOLS_TAG" https://github.com/google/or-tools.git
    D=or-tools/cmake/dependencies/CMakeLists.txt
    # THE load-bearing patch. See header note 1.
    sed -i 's/^set(BUILD_SHARED_LIBS ON)$/set(BUILD_SHARED_LIBS OFF)/' "$D"
    sed -i 's/^  set(protobuf_BUILD_SHARED_LIBS ON)$/  set(protobuf_BUILD_SHARED_LIBS OFF)/' "$D"
    grep -q "^set(BUILD_SHARED_LIBS OFF)$" "$D" || {
        echo "ERROR: the OR-Tools static-deps patch did not apply." >&2
        echo "       Without it openroad needs 111 shared libs that EL8 lacks." >&2
        exit 1
    }
    cmake -S or-tools -B or-tools/build -DBUILD_DEPS:BOOL=ON \
        -DBUILD_EXAMPLES:BOOL=OFF -DBUILD_SAMPLES:BOOL=OFF -DBUILD_TESTING:BOOL=OFF \
        -DBUILD_SHARED_LIBS:BOOL=OFF -DCMAKE_POSITION_INDEPENDENT_CODE:BOOL=ON \
        -DCMAKE_BUILD_TYPE=Release -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
        -DCMAKE_INSTALL_PREFIX="$ORTOOLS_PREFIX" \
        -DCMAKE_CXX_FLAGS="-w" -DCMAKE_C_FLAGS="-w" > /dev/null
    cmake --build or-tools/build --config Release --target install -j"$JOBS" > /dev/null
    [ -f "$ORTOOLS_PREFIX/lib64/libortools.a" ] || {
        echo "ERROR: no static libortools.a -- the patch silently did not take." >&2
        exit 1
    }
}

build_openroad() {
    echo "==> Building OpenROAD $tag ..."
    cd "$WORK"
    git clone -q --depth=1 -b "$tag" "$CLONE_URL" openroad-src
    # -static-libstdc++/-static-libgcc: gcc-toolset-14 is mandatory for C++20,
    # and without these the binary floors above stock EL8's GLIBCXX_3.4.25 --
    # it would run here and die on a farm node.
    cmake -S openroad-src -B openroad-src/build \
        -DCMAKE_BUILD_TYPE=Release -DBUILD_GUI=OFF -DENABLE_TESTS=OFF \
        -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
        -DCMAKE_PREFIX_PATH="$DEPS_PREFIX;$ORTOOLS_PREFIX" \
        -Dortools_ROOT="$ORTOOLS_PREFIX" -Dcudd_ROOT="$DEPS_PREFIX" \
        -DCMAKE_INSTALL_PREFIX="$INSTALL_PREFIX" \
        -DCMAKE_EXE_LINKER_FLAGS="-static-libstdc++ -static-libgcc" > /dev/null
    cmake --build openroad-src/build -j"$JOBS" > /dev/null
    rm -rf "$INSTALL_PREFIX"
    cmake --install openroad-src/build > /dev/null
}

# shellcheck disable=SC1091
. /opt/rh/gcc-toolset-14/enable

if [ "$reuse" -eq 1 ]; then
    echo "==> --reuse-build: skipping dependency, OR-Tools and OpenROAD builds"
    [ -x "$INSTALL_PREFIX/bin/openroad" ] || {
        echo "ERROR: --reuse-build but no binary at $INSTALL_PREFIX/bin/openroad" >&2
        exit 1
    }
else
    build_deps
    build_ortools
    build_openroad
fi

BIN="$INSTALL_PREFIX/bin/openroad"
[ -x "$BIN" ] || { echo "ERROR: no openroad at $BIN" >&2; exit 1; }

echo "==> Verifying reported version ..."
reported=$("$BIN" -version 2>&1 | head -1 | tr -d '[:space:]')
[ "$reported" = "$tag" ] || {
    echo "ERROR: binary reports '$reported', expected '$tag'" >&2
    exit 1
}
echo "  reports $reported"

echo "==> Checking glibc floor ..."
loadout_report_max_glibc "$BIN"
MAX_GLIBC=$(readelf -V "$BIN" 2> /dev/null | grep -oE 'GLIBC_[0-9]+\.[0-9]+' | sort -V | tail -1)
case "${MAX_GLIBC:-GLIBC_2.0}" in
    GLIBC_2.2[0-8] | GLIBC_2.1[0-9] | GLIBC_2.[0-9]) ;;
    *) echo "ERROR: needs $MAX_GLIBC; EL8 has glibc 2.28." >&2; exit 1 ;;
esac

echo "==> Checking there is NO libstdc++ requirement ..."
# gcc-toolset-14 is newer than stock EL8's libstdc++. If -static-libstdc++ ever
# stops taking effect, this binary starts requiring GLIBCXX symbols EL8 lacks --
# and it will still work perfectly on this build box. Same masking class as the
# firefox/NSS and octave support-lib incidents.
if readelf -V "$BIN" 2> /dev/null | grep -qoE 'GLIBCXX_[0-9.]+'; then
    echo "ERROR: binary requires GLIBCXX symbols:" >&2
    readelf -V "$BIN" | grep -oE 'GLIBCXX_[0-9.]+' | sort -V | tail -3 >&2
    echo "       -static-libstdc++ did not take. It would run here and die on a farm node." >&2
    exit 1
fi
echo "  none (static libstdc++)"

echo "==> Checking NEEDED closure ..."
UNEXPECTED=""
for so in $(readelf -d "$BIN" | sed -n 's/.*NEEDED.*\[\(.*\)\]/\1/p'); do
    case "$so" in
        libc.so.6 | libm.so.6 | libdl.so.2 | libpthread.so.0 | librt.so.1 | ld-linux-x86-64.so.2) ;;
        libgomp.so.1 | libz.so.1 | libbz2.so.1 | liblzma.so.5 | libzstd.so.1) ;;
        libicudata.so.60 | libicui18n.so.60 | libicuuc.so.60) ;;
        libtcl8.6.so | libpython3.14.so.1.0) ;;  # portable-python (a hard depend)
        *)
            found=0
            for want in $SOLVER_LIBS; do [ "$so" = "$want" ] && found=1; done
            [ "$found" -eq 1 ] || UNEXPECTED="$UNEXPECTED $so"
            ;;
    esac
done
[ -z "$UNEXPECTED" ] || {
    echo "ERROR: unexpected NEEDED:$UNEXPECTED" >&2
    echo "       Not EL8 base, not portable-python, not a bundled solver lib." >&2
    echo "       Decide whether to bundle before shipping." >&2
    exit 1
}
echo "  OK ($(readelf -d "$BIN" | grep -c NEEDED) entries, all EL8 base / portable-python / bundled)"

echo "==> Packaging ..."
# RPATH puts ../lib BEFORE ../lib64, which is the reverse of this repo's usual
# pair and is load-bearing. A full install has TWO libtcl8.6.so: the one bundled
# in lib64 for expect (Tcl **8.6.16**) and portable-python's in lib (**8.6.17**).
# The only Tcl SCRIPT library on openroad's search path is portable-python's
# lib/tcl8.6, at 8.6.17, and its init.tcl does `package require -exact`. With the
# usual lib64-first order the 8.6.16 library wins and openroad dies with
# "Can't find a usable init.tcl". Ordering lib first pairs the 8.6.17 library
# with its own 8.6.17 script tree. The solver libs live only in lib64, so they
# still resolve.
# shellcheck disable=SC2016  # $ORIGIN is an ld.so token, not a shell var
OPENROAD_RPATH='$ORIGIN/../lib:$ORIGIN/../lib64'
loadout_package_bin "$BIN" "openroad" "$OPENROAD_RPATH"
loadout_package_bin "$INSTALL_PREFIX/bin/sta" "sta" "$OPENROAD_RPATH"

LIB_DIR="$REPO/payload/$LOADOUT_PLATFORM/lib64"
mkdir -p "$LIB_DIR"
for so in $SOLVER_LIBS; do
    src="$ORTOOLS_PREFIX/lib64/$so"
    [ -f "$src" ] || { echo "ERROR: missing solver lib $src" >&2; exit 1; }
    cp "$src" "$WORK/$so"
    strip "$WORK/$so" 2> /dev/null || true
    # shellcheck disable=SC2016  # $ORIGIN is an ld.so token, not a shell var
    "$LOADOUT_PATCHELF" --set-rpath '$ORIGIN' "$WORK/$so"
    bzip2 -f "$WORK/$so"
    cp "$WORK/$so.bz2" "$LIB_DIR/$so.bz2"
    chmod 644 "$LIB_DIR/$so.bz2"
    echo "  packaged $so"
done

echo "==> Functional smoke against the PACKAGED artifacts ..."
# Deliberately runs AFTER packaging, on the payload .bz2 files, in a staged tree
# shaped like a real install. An earlier version of this script smoked the
# build-tree binary instead and passed -- while the packaged one died in the
# clean container, because the build tree's RUNPATH pointed straight at
# portable-python's lib dir and the packaged RPATH did not. Testing the artifact
# you ship is the whole point; see header note 3.
SMOKE="$WORK/smoke"
mkdir -p "$SMOKE/bin" "$SMOKE/lib64"
bzip2 -dc "$LOADOUT_BIN_DIR/openroad.bz2" > "$SMOKE/bin/openroad"
chmod +x "$SMOKE/bin/openroad"
for so in $SOLVER_LIBS; do
    bzip2 -dc "$LIB_DIR/$so.bz2" > "$SMOKE/lib64/$so"
done
# portable-python supplies BOTH libtcl8.6.so and the matching lib/tcl8.6 tree;
# a real install has it as a hard depend.
[ -d "$HOME/.local/lib/tcl8.6" ] || {
    echo "ERROR: no $HOME/.local/lib/tcl8.6 -- install portable-python first;" >&2
    echo "       the smoke needs the same Tcl the deployed tree resolves." >&2
    exit 1
}
ln -s "$HOME/.local/lib" "$SMOKE/lib"
cp "$REPO/build/openroad/gscl45nm.lef" "$REPO/build/openroad/design.def" \
   "$REPO/build/openroad/smoke.tcl" "$SMOKE/"
out=$("$SMOKE/bin/openroad" -no_init -exit "$SMOKE/smoke.tcl" 2>&1) || {
    echo "$out" >&2; echo "ERROR: smoke failed" >&2; exit 1
}
case "$out" in
    *init.tcl*)
        echo "$out" >&2
        echo "ERROR: Tcl script library unresolved. Check the RPATH order -- ../lib" >&2
        echo "       must come BEFORE ../lib64 so portable-python's 8.6.17 libtcl" >&2
        echo "       wins over the 8.6.16 copy bundled in lib64 for expect." >&2
        exit 1
        ;;
esac
echo "$out" | grep -q "SMOKE_INSTANCES=12" || {
    echo "$out" >&2
    echo "ERROR: smoke did not report 12 instances -- the DEF was not really read." >&2
    exit 1
}
echo "$out" | grep -q "SMOKE_NETS=24" || {
    echo "$out" >&2; echo "ERROR: smoke did not report 24 nets." >&2; exit 1
}
echo "  packaged binary read LEF+DEF: 12 instances / 24 nets via the Tcl API"

loadout_stamp_version "$PKG" "$tag"

cat <<EOF

Done. OpenROAD $tag

Next, as for every payload change:
  ./build/strip-all-elf-binaries
  python3.14 build/gen-installed-sizes   # before the manifest: it hashes this file
  python3.14 build/gen-content-manifest
  python3.14 build/gen-readme-table
EOF
