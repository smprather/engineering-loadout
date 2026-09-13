#!/bin/sh
# Bitwuzla -- SMT solver for bit-vectors, floating-point, arrays and UF
# (EL8 source build).   https://github.com/bitwuzla/bitwuzla   (MIT)
#
# One ELF, no wrapper: `bitwuzla` is a plain SMT2/BTOR2 solver CLI (unlike yosys
# or sby there is no runtime tree and no data dir to relocate). Upstream's
# official Linux release zip ("Bitwuzla-Linux-x86_64-static") is built on
# modern Ubuntu and needs GLIBC_2.38 / GLIBCXX_3.4.32, so it cannot ship here
# -- this script builds from the release tarball on EL8 instead.
#
# Upstream 0.9.0 made GMP >= 6.3 and MPFR >= 4.2.1 hard requirements (EL8 has
# gmp 6.1.2 / mpfr 3.1.6 and no newer packages anywhere), so this script builds
# both from the official GNU tarballs as STATIC archives into a private prefix
# and links them into the executable. That keeps the shipped NEEDED closure at
# libstdc++/libgcc_s/libm/libpthread/libc -- the same system-only set as z3 and
# yosys, no bundled .so to install or RPATH to get wrong.
#
# One upstream patch (applied below, asserted): when default_library=static the
# build forces `-static` onto the executable link, i.e. a fully static binary
# against static libc/libstdc++. EL8 never bundles or links those statically
# (repo policy: the host always supplies glibc/libstdc++), so the script drops
# that one link arg. Everything else stays exactly as upstream ships it.
#
# Prerequisites on the build machine (EL8):
#   gcc gcc-c++ make ninja-build meson(>= 0.64) python3 pkg-config \
#   curl tar bzip2 patchelf  (all present in the loadout-build image)
#   Base gcc 8.5.0 is SUFFICIENT -- no gcc-toolset needed (verified 2026-09-12:
#   C++17 codebase, GLIBC_2.14 / GLIBCXX_3.4.22 out).
#
# Usage (run from any directory):
#   ./build/build-bitwuzla.sh --tag 0.9.1

set -eu

REPO="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib.sh
. "$REPO/build/lib.sh"

PKG="bitwuzla"
RELEASES_URL="https://github.com/bitwuzla/bitwuzla/releases"

tag=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --tag)
            shift
            [ "$#" -gt 0 ] || { echo "missing value for --tag" >&2; exit 2; }
            tag=$1
            ;;
        -h | --help)
            sed -n '2,/^$/p' "$0"
            exit 0
            ;;
        *)
            echo "unknown argument: $1" >&2
            exit 2
            ;;
    esac
    shift
done

loadout_require_tag "$tag" "$0" "$RELEASES_URL" "0.9.1"
# Base gcc (8.5) is enough; gcc-toolset-14 would raise the GLIBCXX floor for no
# benefit. Do NOT source the toolset here.
loadout_require_cmds curl tar make pkg-config python3 bzip2 strip readelf patchelf
command -v ninja > /dev/null 2>&1 || { echo "missing required command: ninja" >&2; exit 1; }
command -v meson > /dev/null 2>&1 || { echo "missing required command: meson (>= 0.64)" >&2; exit 1; }

version=$tag  # upstream tags are bare versions (0.9.1), no v prefix

# Pinned source-build dependency versions (official GNU ftp tarballs). Bump
# together with the bitwuzla tag and re-verify; --tag never covers these.
GMP_VERSION="6.3.0"
MPFR_VERSION="4.2.2"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/build-bitwuzla-XXXXXX")
DEPS="/tmp/bitwuzla-deps-${version}"
INST="/tmp/bitwuzla-inst-${version}"
trap 'rm -rf "$WORK"' EXIT INT TERM
rm -rf "$DEPS" "$INST"

# ---------------------------------------------------------------------------
# Step 1: GMP 6.3.0 + MPFR 4.2.2, static + PIC, into a private prefix.
#
# Static archives so the shipped binary stays system-runtime-only; -fPIC so
# they can be linked into the PIE executable meson produces by default.
# `--with-pic` applies to the static archive too.
# ---------------------------------------------------------------------------
echo "==> Building GMP ${GMP_VERSION} (static, build-only) ..."
curl -fL --retry 3 --retry-delay 2 -o "$WORK/gmp.tar.xz" \
    "https://ftp.gnu.org/gnu/gmp/gmp-${GMP_VERSION}.tar.xz"
tar xf "$WORK/gmp.tar.xz" -C "$WORK"
(
    cd "$WORK/gmp-${GMP_VERSION}"
    ./configure --prefix="$DEPS" --disable-shared --enable-static --with-pic
    make -j"$(nproc 2>/dev/null || echo 2)"
    make install
) > "$WORK/gmp-build.log" 2>&1 || {
    echo "ERROR: GMP build failed; tail of log:" >&2
    tail -30 "$WORK/gmp-build.log" >&2
    exit 1
}
[ -f "$DEPS/lib/libgmp.a" ] || { echo "ERROR: libgmp.a not produced" >&2; exit 1; }
echo "  $DEPS/lib/libgmp.a"

echo "==> Building MPFR ${MPFR_VERSION} (static, build-only) ..."
curl -fL --retry 3 --retry-delay 2 -o "$WORK/mpfr.tar.xz" \
    "https://ftp.gnu.org/gnu/mpfr/mpfr-${MPFR_VERSION}.tar.xz"
tar xf "$WORK/mpfr.tar.xz" -C "$WORK"
(
    cd "$WORK/mpfr-${MPFR_VERSION}"
    ./configure --prefix="$DEPS" --disable-shared --enable-static --with-pic \
        --with-gmp="$DEPS"
    make -j"$(nproc 2>/dev/null || echo 2)"
    make install
) > "$WORK/mpfr-build.log" 2>&1 || {
    echo "ERROR: MPFR build failed; tail of log:" >&2
    tail -30 "$WORK/mpfr-build.log" >&2
    exit 1
}
[ -f "$DEPS/lib/libmpfr.a" ] || { echo "ERROR: libmpfr.a not produced" >&2; exit 1; }
echo "  $DEPS/lib/libmpfr.a"

# ---------------------------------------------------------------------------
# Step 2: Bitwuzla source tarball.
# ---------------------------------------------------------------------------
echo "==> Downloading Bitwuzla $version ..."
SRC="$WORK/bitwuzla-src"
mkdir -p "$SRC"
curl -fL --retry 3 --retry-delay 2 -o "$WORK/bitwuzla.tar.gz" \
    "https://github.com/bitwuzla/bitwuzla/archive/refs/tags/${tag}.tar.gz"
tar xzf "$WORK/bitwuzla.tar.gz" -C "$SRC" --strip-components=1
[ -f "$SRC/src/main/main.cpp" ] || { echo "ERROR: unexpected source layout" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Step 3: patch out upstream's fully-static executable link flag.
#
# src/main/meson.build adds `-static` to the executable when
# default_library=static and not macOS. We want static GMP/MPFR/CaDiCaL but
# dynamic libc/libstdc++ (never bundle or static-link either). The patch is a
# single-line removal; assert it applied so a future upstream refactor fails
# loudly instead of silently shipping a link error.
# ---------------------------------------------------------------------------
echo "==> Patching src/main/meson.build (drop forced -static executable link) ..."
python3 - "$SRC/src/main/meson.build" << 'PYEOF'
import sys

path = sys.argv[1]
txt = open(path).read()
needle = "  link_args += ['-static']\n"
if needle not in txt:
    sys.exit(f"patch target not found in {path}: {needle!r}")
txt = txt.replace(needle, "  # loadout: no fully-static link; host supplies libc/libstdc++\n")
open(path, "w").write(txt)
print("  patched")
PYEOF

# ---------------------------------------------------------------------------
# Step 4: configure + build.
#
# -Ddefault_library=static: GMP/MPFR/CaDiCaL/SymFPU statically linked.
# -Dtesting=disabled: no gtest, no regression tree.
# -Dcadical=true (default): the bundled SAT back end via the meson wrap --
#   no system cadical needed (EL8 has none).
# fpexp stays off (release default; only enables non-standard FP formats).
# PKG_CONFIG_PATH points at our private GMP/MPFR .pc files.
# ---------------------------------------------------------------------------
echo "==> Configuring Bitwuzla ..."
export PKG_CONFIG_PATH="$DEPS/lib/pkgconfig"
(
    cd "$SRC"
    meson setup build \
        --prefix="$INST" \
        --buildtype=release \
        -Ddefault_library=static \
        -Dtesting=disabled \
        -Dunit_testing=disabled \
        -Ddocs=false \
        -Dpython=false \
        -Dcadical=true
    ninja -C build -j"$(nproc 2>/dev/null || echo 2)"
    ninja -C build install
) > "$WORK/build.log" 2>&1 || {
    echo "ERROR: build failed; tail of log:" >&2
    tail -40 "$WORK/build.log" >&2
    exit 1
}
BUILT="$INST/bin/bitwuzla"
[ -x "$BUILT" ] || { echo "ERROR: $BUILT not produced" >&2; exit 1; }

# Version banner: `--version` prints the bare version (no program prefix).
reported=$("$BUILT" --version 2>&1 | head -1)
echo "  $reported"
[ "$reported" = "$version" ] || {
    echo "ERROR: built binary reports '$reported', expected '$version'" >&2
    exit 1
}

# ---------------------------------------------------------------------------
# Step 5: glibc / libstdc++ floors.
#
# Base GCC 8.5 EL8 build: measured GLIBC_2.14 and GLIBCXX_3.4.22. Both are
# below EL8's ceilings (glibc 2.28, libstdc++ 3.4.25); anything above the
# ceiling means the build linked something newer than EL8 ships.
# ---------------------------------------------------------------------------
echo "==> Checking glibc / libstdc++ floors ..."
g=$(readelf -V "$BUILT" 2>/dev/null | grep -oE 'GLIBC_[0-9]+\.[0-9]+' | sort -V | tail -1)
x=$(readelf -V "$BUILT" 2>/dev/null | grep -oE 'GLIBCXX_[0-9]+\.[0-9]+\.[0-9]+' | sort -V | tail -1)
printf '  %-12s %s %s\n' "bitwuzla" "${g:-none}" "${x:-no-libstdc++}"
case "${g:-GLIBC_2.0}" in
    GLIBC_2.2[0-8] | GLIBC_2.1[0-9] | GLIBC_2.[0-9]) ;;
    *) echo "ERROR: bitwuzla needs $g; EL8 has glibc 2.28" >&2; exit 1 ;;
esac
case "${x:-GLIBCXX_3.4.0}" in
    GLIBCXX_3.4.1? | GLIBCXX_3.4.2[0-5] | GLIBCXX_3.4.[0-9]) ;;
    *) echo "ERROR: bitwuzla needs $x; EL8 libstdc++ provides 3.4.25" >&2; exit 1 ;;
esac

# ---------------------------------------------------------------------------
# Step 6: NEEDED allowlist. GMP/MPFR/CaDiCaL/SymFPU are static; the executable
# must need nothing but the system runtime. Anything else is a hard error --
# bundle it or stop linking it. Do not silently widen the list.
# ---------------------------------------------------------------------------
echo "==> Checking NEEDED closure ..."
needed=$(objdump -p "$BUILT" | awk '$1 == "NEEDED" {print $2}' | sort)
echo "$needed" | sed 's/^/  /'
for lib in $needed; do
    case "$lib" in
        libstdc++.so.6 | libgcc_s.so.1 | libm.so.6 | libpthread.so.0 | libc.so.6 | ld-linux-x86-64.so.2) ;;
        *) echo "ERROR: unexpected NEEDED entry: $lib" >&2; exit 1 ;;
    esac
done

# RPATH: upstream bakes <build-prefix>/lib64 into the executable (meson
# install_rpath). Nothing resolves through it (static GMP/MPFR/CaDiCaL, system
# runtime only), and loadout_package_bin overwrites it with the repo default
# after strip; only the build prefix is acceptable here, so a future upstream
# change that RPATHs a real runtime dependency fails loudly.
rpath=$(readelf -d "$BUILT" | grep -E 'RPATH|RUNPATH' || true)
case "$rpath" in
    *"$DEPS"* | *"$INST"* | "") ;;
    *)
        echo "ERROR: bitwuzla carries an unexpected RPATH: $rpath" >&2
        exit 1
        ;;
esac

# ---------------------------------------------------------------------------
# Step 7: functional smoke -- real satisfiability, not --version.
#
# --version proves the ELF loads; a solver that loads and cannot solve is
# worthless. Assert one SAT model and one UNSAT on a hand-checkable pair, plus
# the incremental/push-pop path sby uses (smtio drives bitwuzla in single-shot
# mode, but interactive use is the normal CLI mode).
# ---------------------------------------------------------------------------
echo "==> Running functional smoke ..."
SMOKE="$WORK/smoke"
mkdir -p "$SMOKE"

cat > "$SMOKE/sat.smt2" << 'EOF'
(set-logic QF_BV)
(declare-fun x () (_ BitVec 32))
(assert (distinct (bvadd x #x00000001) #x00000001))
(check-sat)
(get-model)
EOF
sat_out=$("$BUILT" -m "$SMOKE/sat.smt2" 2>&1) || {
    echo "ERROR: SAT smoke exited non-zero:" >&2; echo "$sat_out" >&2; exit 1
}
case "$sat_out" in
    *sat*) ;;
    *) echo "ERROR: SAT smoke did not report sat:" >&2; echo "$sat_out" >&2; exit 1 ;;
esac
case "$sat_out" in
    *"#b11111111111111111111111111111111"*) ;;
    *) echo "ERROR: SAT smoke model wrong (x should be all-ones):" >&2; echo "$sat_out" >&2; exit 1 ;;
esac
echo "  sat: distinct(x+1,1) -> sat, model x=0xffffffff"

cat > "$SMOKE/unsat.smt2" << 'EOF'
(set-logic QF_BV)
(declare-fun x () (_ BitVec 8))
(assert (= (bvand x #xff) #x00))
(assert (= x #xff))
(check-sat)
EOF
unsat_out=$("$BUILT" "$SMOKE/unsat.smt2" 2>&1) || {
    echo "ERROR: UNSAT smoke exited non-zero:" >&2; echo "$unsat_out" >&2; exit 1
}
[ "$unsat_out" = "unsat" ] || {
    echo "ERROR: UNSAT smoke returned '$unsat_out', expected 'unsat'" >&2
    exit 1
}
echo "  unsat: (x & 0xff)=0 and x=0xff -> unsat"

# sby's smtio detects engine support via `bitwuzla --help` containing --lang.
"$BUILT" --help 2>&1 | grep -q -- '--lang' || {
    echo "ERROR: --lang missing from --help; sby's smtbmc bitwuzla engine would fall back to pre-0.3 flags" >&2
    exit 1
}
echo "  --lang present (sby smtbmc bitwuzla engine flags match)"

# ---------------------------------------------------------------------------
# Step 8: package. Plain ELF -> strip -> patchelf -> bzip2. RPATH stays the
# repo default even though nothing bundled resolves through it: the same
# system-only closure also means the RPATH is harmless, and consistency with
# every other bin/ payload keeps strip-all-elf-binaries' patched-skip logic
# uniform. (No $ORIGIN targets exist, so no resolution changes.)
# ---------------------------------------------------------------------------
loadout_package_bin "$BUILT" "$PKG"

loadout_stamp_version "$PKG" "$version"

# ---------------------------------------------------------------------------
# Step 9: next steps.
# ---------------------------------------------------------------------------
cat << EOF

Done.

Next, as for every payload change:
  ./build/strip-all-elf-binaries
  python3.14 build/gen-installed-sizes
  python3.14 build/gen-content-manifest
  ./loadout completion bash > envs/bash/global/completions/loadout.bash
  python3.14 build/gen-readme-table
EOF
