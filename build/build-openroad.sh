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

DEPS_PREFIX="${OPENROAD_DEPS_PREFIX:-${LOADOUT_BUILD_CACHE:-/tmp}/openroad-deps}"
ORTOOLS_PREFIX="${OPENROAD_ORTOOLS_PREFIX:-${LOADOUT_BUILD_CACHE:-/tmp}/or-tools-install-9.14}"
INSTALL_PREFIX="${OPENROAD_INSTALL_PREFIX:-${LOADOUT_BUILD_CACHE:-/tmp}/openroad-install-26Q3}"
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

# Libraries openroad NEEDs that this script does NOT package because the payload
# ALREADY carries them (correctly stripped, RPATH $ORIGIN) from another
# package's files. openroad must still DECLARE them in the registry `libs` list,
# or a minimal openroad+portable-python install gets no ICU at all -- which is
# exactly what happened: the build container's /usr/lib64 satisfied them during
# the smoke while the deployed tree could not.
#
#   libicudata/libicui18n/libicuuc.so.60 -- the SWIG *_py modules link against
#   the ICU-using python prefix. gui_libs also ships these (Qt5 needs them), and
#   two owners for one payload path is already an accepted pattern in this repo
#   (libz.so.1, libffi.so.6, libpcre2-8.so.0, ...).
SHARED_WITH_PAYLOAD="libicudata.so.60 libicui18n.so.60 libicuuc.so.60"

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
loadout_require_cmds git cmake curl bzip2 strip readelf tar autoreconf nm objdump

[ -r /opt/rh/gcc-toolset-14/enable ] || {
    echo "ERROR: gcc-toolset-14 not found. OpenROAD needs C++20; EL8's gcc 8.5 cannot build it." >&2
    exit 1
}

WORK=$(mktemp -d "${TMPDIR:-/tmp}/build-openroad-XXXXXX")
trap 'rm -rf "$WORK"' EXIT INT TERM

# ---------------------------------------------------------------- dependencies

# Resume support. A 60-90 min build that dies in the LAST phase should not redo
# the first two on retry. Each phase drops a stamp naming its key artifacts; the
# stamp is only honoured when every named artifact still exists, so a wiped or
# half-written prefix re-runs that phase instead of linking against rubble.
# OPENROAD_NO_CACHE=1 forces a full rebuild.
cache_ok() {
    _ck_stamp=$1
    shift
    [ "${OPENROAD_NO_CACHE:-0}" = "1" ] && return 1
    [ -f "$_ck_stamp" ] || return 1
    for _ck_f in "$@"; do
        [ -e "$_ck_f" ] || return 1
    done
    return 0
}

cache_stamp() {
    _cs_stamp=$1
    shift
    mkdir -p "$(dirname "$_cs_stamp")"
    : > "$_cs_stamp"
    for _cs_f in "$@"; do
        printf '%s\n' "$_cs_f" >> "$_cs_stamp"
    done
}

build_deps() {
    # Probe paths that actually exist in an installed deps prefix -- a stamp
    # listing a path the build never creates can never match, silently turning
    # the resume into a full rebuild (which is what happened on the first try:
    # include/cudd/cudd.h and include/lemon/lemon/lemon.h are real headers but
    # not at those paths).
    if cache_ok "$DEPS_PREFIX/.loadout-deps-21" \
        "$DEPS_PREFIX/bin/bison" \
        "$DEPS_PREFIX/bin/swig" \
        "$DEPS_PREFIX/include/yaml-cpp/yaml.h" \
        "$DEPS_PREFIX/include/lemon/lemon.h" \
        "$DEPS_PREFIX/include/cudd.h" \
        "$DEPS_PREFIX/include/boost/version.hpp" \
        "$DEPS_PREFIX/lib64/libgtest.a" \
        "$DEPS_PREFIX/lib/libcudd.a" \
        "$DEPS_PREFIX/lib/libboost_system.a" \
        "$DEPS_PREFIX/include/eigen3/Eigen/Dense"; then
        echo "==> Dependencies already built in $DEPS_PREFIX -- skipping (OPENROAD_NO_CACHE=1 to force)"
        PATH="$DEPS_PREFIX/bin:$PATH"
        export PATH
        return
    fi
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
    cache_stamp "$DEPS_PREFIX/.loadout-deps-21" \
        "$DEPS_PREFIX/bin/bison" "$DEPS_PREFIX/bin/swig" \
        "$DEPS_PREFIX/include/yaml-cpp/yaml.h" "$DEPS_PREFIX/include/lemon/lemon.h" \
        "$DEPS_PREFIX/include/cudd.h" "$DEPS_PREFIX/include/boost/version.hpp" \
        "$DEPS_PREFIX/lib64/libgtest.a" "$DEPS_PREFIX/lib/libcudd.a" \
        "$DEPS_PREFIX/lib/libboost_system.a" "$DEPS_PREFIX/include/eigen3/Eigen/Dense"
}

build_ortools() {
    if cache_ok "$ORTOOLS_PREFIX/.loadout-ortools-21" "$ORTOOLS_PREFIX/lib64/libortools.a"; then
        echo "==> OR-Tools already built in $ORTOOLS_PREFIX -- skipping (OPENROAD_NO_CACHE=1 to force)"
        return
    fi
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
    cache_stamp "$ORTOOLS_PREFIX/.loadout-ortools-21" "$ORTOOLS_PREFIX/lib64/libortools.a"
}

build_openroad() {
    echo "==> Building OpenROAD $tag ..."
    cd "$WORK"
    # --recurse-submodules is LOAD-BEARING, not tidiness. At this tag OpenROAD
    # keeps its synthesis and timing backends in submodules (gitlinks, mode
    # 160000): third-party/abc (the technology mapper), third-party/slang-elab
    # (the SystemVerilog frontend, which itself nests MikePopoloski/slang and
    # fmtlib/fmt) and src/sta (OpenSTA). A plain clone leaves those directories
    # EMPTY and the configure below dies with
    #     add_subdirectory ... third-party/abc does not contain a CMakeLists.txt
    #     add_subdirectory given source "slang-elab/third_party/slang" ...
    #     Could not find a package configuration file provided by "fmt"
    # --shallow-submodules keeps it one commit deep, matching the parent clone.
    # Verified against the shipped binary: `strings` shows slang_frontend
    # symbols, so the released build did include these vendored backends.
    git clone -q --depth=1 -b "$tag" --recurse-submodules --shallow-submodules \
        "$CLONE_URL" openroad-src

    # Fail here, with names, instead of letting CMake report a missing
    # CMakeLists three screens later.
    for sub in third-party/abc third-party/slang-elab third-party/slang-elab/third_party/slang src/sta; do
        [ -e "openroad-src/$sub" ] && [ -n "$(ls -A "openroad-src/$sub" 2> /dev/null)" ] || {
            echo "ERROR: submodule openroad-src/$sub is empty after clone." >&2
            echo "       --recurse-submodules did not fetch it; check the relative" >&2
            echo "       submodule URLs in .gitmodules against the clone URL." >&2
            exit 1
        }
    done
    echo "    submodules present: abc, slang-elab (+slang), sta"

    # OpenROAD embeds CPython (src/CMakeLists.txt:138,
    # `find_package(Python3 COMPONENTS Development REQUIRED)`), so the build
    # needs a Python 3.14 development prefix -- headers AND libpython, matching
    # the runtime the binary will embed. The build image has no python3.14; the
    # interpreter is loadout's own portable-python, so extract it from the
    # payload exactly as the build smoke and the installer do. CMake finds it
    # through CMAKE_PREFIX_PATH (below), and because the tree is the SAME one
    # that ships, the embedded libpython3.14.so.1.0 is the one the deployed
    # binary links -- not the build box's system python.
    #
    # NOTE the archive layout: the tarball's root directory contains BUILD.md,
    # install.sh and a `local/` payload tree, and install.sh installs from
    # `$script_dir/local` into `--prefix` (install.sh:55). Do NOT use
    # `tar --strip-components=1`: that drops `local/`, and pointing --prefix at
    # `<dir>/local` then nests the payload again (headers land under
    # local/local/include and the Development check fails). Extract whole and
    # install out of the extracted tree.
    #
    # This is why the binary's NEEDED list carries libpython3.14.so.1.0 and
    # portable-python is a hard `depends` of this package.
    PP_TAR=$(ls "$REPO"/payload/*/portable-python-*.tar.bz2 2> /dev/null | head -1)
    [ -n "$PP_TAR" ] || { echo "ERROR: no portable-python archive in payload/." >&2; exit 1; }
    PY_SRC="$WORK/py-src"
    PY_PREFIX="$WORK/py-prefix"
    rm -rf "$PY_SRC" "$PY_PREFIX"
    mkdir -p "$PY_SRC" "$PY_PREFIX"
    tar xjf "$PP_TAR" -C "$PY_SRC"
    PP_ROOT=$(find "$PY_SRC" -maxdepth 1 -mindepth 1 -type d | head -1)
    [ -n "$PP_ROOT" ] || { echo "ERROR: portable-python archive has no top-level dir." >&2; exit 1; }
    ( cd "$PP_ROOT" && ./install.sh --prefix "$PY_PREFIX" --force --no-test ) > "$WORK/pp.log" 2>&1 || {
        echo "ERROR: portable-python install failed; tail:" >&2
        tail -20 "$WORK/pp.log" >&2
        exit 1
    }
    [ -f "$PY_PREFIX/include/python3.14/Python.h" ] || {
        echo "ERROR: no Python.h under $PY_PREFIX -- the Development component is missing." >&2
        exit 1
    }
    [ -f "$PY_PREFIX/lib/libpython3.14.so" ] || {
        echo "ERROR: no libpython3.14.so under $PY_PREFIX -- embed will fail." >&2
        exit 1
    }
    echo "    python dev prefix: $PY_PREFIX ($(python3 -c 'print("ok")' 2>/dev/null || echo ok))"

    # libpython's own SONAME is libpython3.14.so.1.0 and nothing in
    # PY_PREFIX/lib carries that name, so record the lib dir for the link.
    # -static-libstdc++/-static-libgcc: gcc-toolset-14 is mandatory for C++20,
    # and without these the binary floors above stock EL8's GLIBCXX_3.4.25 --
    # it would run here and die on a farm node.
    #
    # -fPIC/-pie: ALSO NOT OPTIONAL, but NOT SUFFICIENT -- read both parts.
    #
    # (a) gcc-toolset-14 defaults to NON-PIE (unlike newer distro gccs), and a
    #     non-PIE executable that references CPython's data objects --
    #     PyErr_SetString(PyExc_TypeError, ...) does -- gets COPY relocations for
    #     them. The linker allocates and exports zero-filled copies in the
    #     executable's .bss, and because the main executable is FIRST in the
    #     global symbol lookup scope, libpython's own internal references bind
    #     to those never-initialised copies. `openroad -python` then segfaults in
    #     Py_InitializeFromConfig -> pycore_interp_init -> type_ready ->
    #     PyErr_Format with si_addr=0x8, while Tcl mode works.
    #
    # (b) A PIE link removes the COPY relocations but NOT the exported symbols:
    #     the SWIG `*_py` static modules make the linker resolve those same
    #     libpython data objects and emit them as ABSOLUTE (`A`) in .dynsym
    #     (18 of them: PyExc_*, PyBool_Type, PyFloat_Type, PySlice_Type,
    #     PyType_Type, _Py_NoneStruct, ...). The reference openroad ships ZERO
    #     such symbols; an absolute definition cannot be rebound at runtime, so
    #     the crash simply MOVES -- to PySequence_Tuple inside type_ready, still
    #     in Py_InitializeFromConfig.
    #
    # The fix for (b) is the version script below: it keeps every other symbol
    # exported (openroad's ENABLE_EXPORTS/-rdynamic is there deliberately, for
    # stack traces) while localising the CPython data objects so the dynamic
    # loader resolves them from libpython. Both are asserted after the build.
    cat > openroad-src/hide-cpython-data.map <<'MAPEOF'
    {
      global: *;
      local:
        /* CPython data objects that must resolve to libpython, never to a
           definition inside this executable. */
        PyExc_*;
        Py*_Type;
        Py*_Struct;
        _Py_*;
        PyObject_Generic*;
        PyImport_*;
        Py_DecodeLocale;
        Py_Get*;
    };
MAPEOF
    cmake -S openroad-src -B openroad-src/build \
        -DCMAKE_BUILD_TYPE=Release -DBUILD_GUI=OFF -DENABLE_TESTS=OFF \
        -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
        -DCMAKE_PREFIX_PATH="$DEPS_PREFIX;$ORTOOLS_PREFIX;$PY_PREFIX" \
        -Dortools_ROOT="$ORTOOLS_PREFIX" -Dcudd_ROOT="$DEPS_PREFIX" \
        -DPython3_ROOT_DIR="$PY_PREFIX" \
        -DCMAKE_INSTALL_PREFIX="$INSTALL_PREFIX" \
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
        -DCMAKE_C_FLAGS="-fPIC" -DCMAKE_CXX_FLAGS="-fPIC" \
        -DCMAKE_EXE_LINKER_FLAGS="-pie -static-libstdc++ -static-libgcc -Wl,-rpath-link,$PY_PREFIX/lib -Wl,--version-script=$PWD/openroad-src/hide-cpython-data.map" > /dev/null
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

echo "==> Checking the binary is PIE and embeds CPython correctly ..."
# The embedding guard.
#
# WHY `openroad -python` CRASHES WHEN THIS IS WRONG
#   CPython's data objects (PyExc_*, Py*_Type, _Py_NoneStruct, ...) live in
#   libpython. A consumer that references them needs the loader to COPY them
#   into its own image, which the linker emits as an R_X86_64_COPY relocation
#   ONLY IF libpython's .dynsym entry for the symbol names a REAL section
#   (valid st_shndx). The portable-python 3.14.7 archive shipped a library whose
#   data-object entries pointed at RELOCATION sections instead, so the linker
#   silently emitted a PC-relative reference to a zero-filled .bss slot and
#   Py_InitializeFromConfig segfaulted in type_ready. Fixed by
#   build/repair-libpython-dynsym; this guard is what catches a regression.
#
# THE RULE (measured; symbol class alone is NOT sufficient)
#   `A` (absolute) on a Py data symbol is ALWAYS fatal -- the linker bound it to
#   a frozen link-time vaddr that no runtime relocation can fix.
#   `B`/`D`/`R`/`W` data symbols are CORRECT when a COPY relocation fills them
#   and FATAL when none does. A correct PIE consumer therefore shows
#   `B PyExc_TypeError` PLUS `COPY PyExc_TypeError`; the broken one shows the
#   same `B` symbol with NO copy relocation. Matching on class alone fails both
#   ways: it rejects the correct build and can miss the broken one.
nm -D --defined-only "$BIN" 2> /dev/null | grep -E ' [ABDRW] Py' | awk '{print $2, $3}' \
    > /tmp/or-pydefs.$$ || true
objdump -R "$BIN" 2> /dev/null | grep COPY | awk '{print $NF}' | sort -u > /tmp/or-copies.$$ || true

PY_ABS=$(awk '$1 == "A"' /tmp/or-pydefs.$$ | wc -l | tr -d ' ')
# Defined data symbols whose name has no COPY relocation to fill them.
PY_UNFILLED=$(awk '$1 ~ /^[BDRW]$/ {print $2}' /tmp/or-pydefs.$$ | sort -u \
    | comm -23 - /tmp/or-copies.$$ | wc -l | tr -d ' ')

if [ "$PY_ABS" != "0" ] || [ "$PY_UNFILLED" != "0" ]; then
    echo "ERROR: the embedded CPython is broken ($PY_ABS absolute, $PY_UNFILLED unrelocated):" >&2
    head -8 /tmp/or-pydefs.$$ >&2
    echo "       An 'A' entry means the linker treated a CPython symbol as defined" >&2
    echo "       by THIS executable, frozen at a link-time address -- libpython's" >&2
    echo "       internal references then bind to it and fault once relocated." >&2
    echo "       An unrelocated B/D/R/W entry means no COPY relocation was emitted." >&2
    echo "       Both happen when libpython's .dynsym has invalid section indices" >&2
    echo "       (the portable-python BOLT defect), which affects BOTH data objects" >&2
    echo "       and functions whose address is taken (tp_getattro etc.)." >&2
    echo "       Check the archive with: build/repair-libpython-dynsym --check <lib>" >&2
    echo "       Do NOT ship this binary." >&2
    rm -f /tmp/or-pydefs.$$ /tmp/or-copies.$$
    exit 1
fi
PY_FILLED=$(grep -c . /tmp/or-copies.$$ || true)
rm -f /tmp/or-pydefs.$$ /tmp/or-copies.$$
readelf -h "$BIN" | grep -q 'Type:.*DYN' || {
    echo "ERROR: not a PIE executable -- see the embedding note in build_openroad()." >&2
    exit 1
}
echo "  PIE; embedded CPython data objects all COPY-relocated ($PY_FILLED)"

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
# portable-python supplies BOTH libtcl8.6.so (with its 8.6.17 script tree) and
# libpython3.14.so.1.0; a real install has it as a hard depend. Extract it from
# the payload into the smoke tree rather than borrowing the build box's
# $HOME/.local: the container build has no $HOME/.local at all, and a smoke that
# depends on the box it runs on is exactly the masking class this script keeps
# getting bitten by.
PP_TAR=$(ls "$REPO"/payload/*/portable-python-*.tar.bz2 2> /dev/null | head -1)
[ -n "$PP_TAR" ] || {
    echo "ERROR: no portable-python payload archive to build the smoke tree from." >&2
    exit 1
}
mkdir -p "$WORK/pp"
tar xjf "$PP_TAR" -C "$WORK/pp" --strip-components=1
( cd "$WORK/pp" && ./install.sh --prefix "$SMOKE/pp" --force --no-test ) > "$WORK/pp-install.log" 2>&1 || {
    echo "ERROR: portable-python install into the smoke tree failed; tail:" >&2
    tail -20 "$WORK/pp-install.log" >&2
    exit 1
}
[ -x "$SMOKE/pp/bin/python3.14" ] || {
    echo "ERROR: smoke tree has no python3.14 after install." >&2
    exit 1
}
ln -s "$SMOKE/pp/lib" "$SMOKE/lib"

# ---- Bundled-closure check --------------------------------------------------
# The smoke tree holds ONLY what this package declares: the binary, its solver
# libs, and portable-python. Anything else the loader resolves comes from the
# CONTAINER's /usr/lib64 -- which a farm node does not have. That masking is how
# libicudata/libicui18n/libicuuc went missing: openroad NEEDs all three, the
# payload carried them only as gui_libs' files, and a minimal
# openroad+portable-python install had no ICU at all while this smoke stayed
# green because the container supplied them.
#
# Static check (readelf, not ldd -- ldd would search the CONTAINER's paths and
# re-introduce the masking): every DIRECT DT_NEEDED entry must be satisfiable
# from the staged tree, from portable-python, or be on the host-provided list.
echo "  checking the bundled closure ..."
closure_bad=""
for so in openroad $SOLVER_LIBS; do
    if [ "$so" = openroad ]; then
        target="$SMOKE/bin/openroad"
    else
        target="$SMOKE/lib64/$so"
    fi
    [ -e "$target" ] || continue
    for dep in $(readelf -dW "$target" 2> /dev/null \
            | awk '/\(NEEDED\)/ {gsub(/[\[\]]/, "", $NF); print $NF}'); do
        # Already staged (solver libs) or supplied by portable-python?
        if [ -e "$SMOKE/lib64/$dep" ] || [ -e "$SMOKE/pp/lib/$dep" ]; then
            continue
        fi
        case "$dep" in
            # Host-provided, deliberately never bundled: glibc components and
            # the C++ runtime (see the never-bundle list in AGENTS.md).
            libc.so.6|libm.so.6|libpthread.so.0|libdl.so.2|librt.so.1|\
            libresolv.so.2|libutil.so.1|libanl.so.1|libnsl.so.1|\
            libstdc++.so.6|libgcc_s.so.1|ld-linux-x86-64.so.2)
                continue ;;
            # EL8 BASEOS, present on every supported host (verified by rpm -qf
            # inside the build container): compression + the GNU OpenMP runtime.
            libbz2.so.1|liblzma.so.5|libzstd.so.1|libgomp.so.1)
                continue ;;
            # Supplied by portable-python, which is a hard `depends` of this
            # package (and is staged into $SMOKE/pp above, so it also shows up
            # in the tree on a real install: <prefix>/lib/).
            libpython3.14.so.1.0|libtcl8.6.so)
                continue ;;
        esac
        # Anything else must be a lib this package DECLARES -- either one it
        # packages itself or one it shares with another package's payload files.
        case " $SOLVER_LIBS $SHARED_WITH_PAYLOAD " in
            *" $dep "*) continue ;;
        esac
        closure_bad="$closure_bad $so->$dep"
    done
done
if [ -n "$closure_bad" ]; then
    echo "ERROR: unresolved DT_NEEDED entries (not bundled, not host-provided):" >&2
    for m in $closure_bad; do echo "         $m" >&2; done
    echo "       The build box satisfied these from its own /usr/lib64; a farm" >&2
    echo "       node will not. Add them to this package's registry \`libs\` list" >&2
    echo "       (payload/<platform>/lib64/<name>.bz2 must exist too)." >&2
    exit 1
fi
echo "  closure OK -- every non-host soname is bundled or declared"

# The SHARED_WITH_PAYLOAD libs are not packaged here, so verify their payload
# files actually exist -- declaring a lib whose .bz2 is absent would install a
# package that cannot load.
for so in $SHARED_WITH_PAYLOAD; do
    [ -f "$LIB_DIR/$so.bz2" ] || {
        echo "ERROR: $so is declared but $LIB_DIR/$so.bz2 does not exist." >&2
        echo "       openroad NEEDs it; the install would be unloadable." >&2
        exit 1
    }
done
echo "  shared-payload libs present: $SHARED_WITH_PAYLOAD"

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

# ---- Python embedding smoke ------------------------------------------------
# Tcl mode passing proves nothing about the embedded interpreter: the COPY-
# relocation bug (see build_openroad) leaves Tcl perfectly healthy. This runs
# the same packaged binary with -python and requires it to actually initialise
# CPython and evaluate code. portable-python's lib dir is already on the staged
# RPATH (../lib), which is where libpython3.14.so.1.0 lives.
pyout=$("$SMOKE/bin/openroad" -python -c 'print("SMOKE_PY_OK", 6*7)' 2>&1) || {
    echo "$pyout" >&2
    echo "ERROR: openroad -python failed -- the embedded interpreter is broken." >&2
    echo "       If this is a SIGSEGV in Py_InitializeFromConfig, the link went" >&2
    echo "       non-PIE again; check for exported Py* data symbols with:" >&2
    echo "         nm -D --defined-only <prefix>/bin/openroad | grep -E ' [TRDBW] Py'" >&2
    exit 1
}
echo "$pyout" | grep -q "SMOKE_PY_OK 42" || {
    echo "$pyout" >&2
    echo "ERROR: openroad -python ran but did not produce the expected output." >&2
    exit 1
}
echo "  packaged binary embedded CPython and evaluated a script"

loadout_stamp_version "$PKG" "$tag"

cat <<EOF

Done. OpenROAD $tag

Next, as for every payload change:
  ./build/strip-all-elf-binaries
  python3.14 build/gen-installed-sizes   # before the manifest: it hashes this file
  python3.14 build/gen-content-manifest
  python3.14 build/gen-readme-table
EOF
