#!/bin/sh
# Yosys -- open-source Verilog synthesis suite (EL8 source build).
#   https://github.com/YosysHQ/yosys   (ISC license)
#
# Builds Yosys from a stable release tarball, asserts ELF floors and an
# NEEDED allowlist, runs a relocation + synthesis smoke, and packages the
# result into payload/el8.x86_64.glibc2p28/{bin,runtime}.
#
# Prerequisites on the build machine (EL8):
#   source /opt/rh/gcc-toolset-14/enable
#   dnf install -y gcc-toolset-14-gcc-c++ cmake flex bzip2 readline-devel \
#                  tcl-devel libffi-devel zlib-devel
#   # bison >= 3.6 is REQUIRED at build time (EL8 ships 3.0.4); this script
#   # builds bison 3.8.2 itself -- see step 5.
#
# Usage (run from any directory):
#   ./build/build-yosys.sh --tag v0.68

set -eu

REPO="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO/build/lib.sh"

PKG="yosys"
RELEASES_URL="https://github.com/YosysHQ/yosys/releases"
PLATFORM_DIR="$REPO/payload/el8.x86_64.glibc2p28"
RUNTIME_DIR="$PLATFORM_DIR/runtime"

tag=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --tag)
            shift
            [ "$#" -gt 0 ] || { echo "missing value for --tag" >&2; exit 2; }
            tag=$1
            ;;
        -h | --help) sed -n '2,30p' "$0"; exit 0 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
    shift
done

loadout_require_tag "$tag" "$0" "$RELEASES_URL" "v0.68"
loadout_enable_gcc_toolset
loadout_require_cmds curl tar cmake make gcc g++ flex bzip2 strip readelf python3

version=${tag#v}  # v0.68 -> 0.68

WORK=$(mktemp -d "${TMPDIR:-/tmp}/build-yosys-XXXXXX")
# Version-scoped install prefix so successive builds cannot contaminate each
# other -- the trap build-octave.sh hit with a fixed /tmp/<pkg>-install.
INST="/tmp/yosys-inst-${tag}"
trap 'rm -rf "$WORK"' EXIT INT TERM
rm -rf "$INST"

# ---------------------------------------------------------------------------
# Step 5: build bison 3.8.2.
#
# EL8 ships bison 3.0.4 and Yosys needs >= 3.6. bison is a BUILD-TIME tool
# only and is never packaged or shipped -- it just has to exist on PATH
# during the Yosys build below.
# ---------------------------------------------------------------------------
echo "==> Building bison 3.8.2 (build-time only, not packaged) ..."
curl -fL --retry 3 --retry-delay 2 -o "$WORK/bison.tar.xz" \
    "https://ftp.gnu.org/gnu/bison/bison-3.8.2.tar.xz"
tar xf "$WORK/bison.tar.xz" -C "$WORK"
BISON_SRC=$(find "$WORK" -maxdepth 1 -mindepth 1 -type d -name 'bison-3.8.2' | head -1)
(
    cd "$BISON_SRC"
    ./configure --prefix="$WORK/bison-inst"
    make -j"$(nproc 2>/dev/null || echo 2)"
    make install
) > "$WORK/bison.log" 2>&1 || {
    echo "ERROR: bison build failed; tail of log:" >&2
    tail -30 "$WORK/bison.log" >&2
    exit 1
}
PATH="$WORK/bison-inst/bin:$PATH"
export PATH

# ---------------------------------------------------------------------------
# Step 6: download and extract Yosys.
#
# The GitHub release tarball extracts FLAT -- there is no top-level
# directory. A `cd $(find -maxdepth 1 -type d | head -1)` lands in a random
# subdirectory and fails. Extract into an empty dir and use that dir
# directly as the source root.
# ---------------------------------------------------------------------------
echo "==> Downloading Yosys $tag ..."
SRC="$WORK/yosys-src"
mkdir -p "$SRC"
curl -fL --retry 3 --retry-delay 2 -o "$WORK/yosys.tar.gz" \
    "https://github.com/YosysHQ/yosys/releases/download/${tag}/yosys.tar.gz"
tar xzf "$WORK/yosys.tar.gz" -C "$SRC"

# ---------------------------------------------------------------------------
# Step 7: build with CMake.
#
# v0.68 uses CMake; there is no top-level Makefile and `make config-gcc`
# no longer exists. Do not try either.
# ---------------------------------------------------------------------------
echo "==> Building Yosys (this takes several minutes) ..."
(
    cmake -S "$SRC" -B "$SRC/build" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$INST"
    cmake --build "$SRC/build" -j"$(nproc 2>/dev/null || echo 2)"
    cmake --install "$SRC/build"
) > "$WORK/build.log" 2>&1 || {
    echo "ERROR: build failed; tail of log:" >&2
    tail -30 "$WORK/build.log" >&2
    exit 1
}

# Step 8: version banner.
reported=$("$INST/bin/yosys" -V 2>&1 | head -1)
echo "  $reported"
case "$reported" in
    *"Yosys $version"*) ;;
    *) echo "ERROR: built binary reports '$reported', expected Yosys $version" >&2; exit 1 ;;
esac

# ---------------------------------------------------------------------------
# Step 9: glibc / libstdc++ floors.
#
# Measured on a clean EL8 build: GLIBC_2.27 and GLIBCXX_3.4.22. Both are
# below EL8's ceilings (glibc 2.28, libstdc++ 3.4.25). The case statements
# below accept anything <= those ceilings and reject higher.
# ---------------------------------------------------------------------------
echo "==> Checking glibc / libstdc++ floors ..."
for b in "$INST/bin/yosys" "$INST/bin/yosys-abc" "$INST/bin/yosys-filterlib"; do
    [ -f "$b" ] || { echo "ERROR: expected $b" >&2; exit 1; }
    g=$(readelf -V "$b" 2>/dev/null | grep -oE 'GLIBC_[0-9]+\.[0-9]+' | sort -V | tail -1)
    x=$(readelf -V "$b" 2>/dev/null | grep -oE 'GLIBCXX_[0-9]+\.[0-9]+\.[0-9]+' | sort -V | tail -1)
    printf '  %-18s %s %s\n' "$(basename "$b")" "${g:-none}" "${x:-no-libstdc++}"
    case "${g:-GLIBC_2.0}" in
        GLIBC_2.2[0-8] | GLIBC_2.1[0-9] | GLIBC_2.[0-9]) ;;
        *) echo "ERROR: $(basename "$b") needs $g; EL8 has glibc 2.28" >&2; exit 1 ;;
    esac
    case "${x:-GLIBCXX_3.4.0}" in
        GLIBCXX_3.4.1? | GLIBCXX_3.4.2[0-5] | GLIBCXX_3.4.[0-9]) ;;
        *) echo "ERROR: $(basename "$b") needs $x; EL8 libstdc++ provides 3.4.25" >&2; exit 1 ;;
    esac
done

# ---------------------------------------------------------------------------
# Step 10: NEEDED allowlist. Anything outside it is a hard error -- either
# bundle it or stop linking it. Do not silently widen the list.
# ---------------------------------------------------------------------------
echo "==> Checking NEEDED closure ..."
for b in "$INST/bin/yosys" "$INST/bin/yosys-abc" "$INST/bin/yosys-filterlib"; do
    for so in $(readelf -d "$b" | sed -n 's/.*NEEDED.*\[\(.*\)\]/\1/p'); do
        case "$so" in
            libdl.so.2|libffi.so.6|libz.so.1|libtcl8.6.so|libedit.so.0|libpthread.so.0|libstdc++.so.6|libm.so.6|libgcc_s.so.1|libc.so.6|ld-linux-x86-64.so.2) ;;
            *)
                echo "ERROR: $(basename "$b") NEEDs '$so', which is not on the allowlist." >&2
                echo "       Decide: bundle it into payload lib64/ or stop linking it." >&2
                exit 1
                ;;
        esac
    done
done
echo "  OK -- NEEDED closure within allowlist"

# Step 11: strip every ELF under $INST.
echo "==> Stripping ..."
find "$INST" -type f | while read -r f; do
    if [ "$(head -c4 "$f" 2>/dev/null)" = "$(printf '\177ELF')" ]; then
        strip "$f" 2>/dev/null || true
    fi
done

# Step 12: install the relocatable yosys-config wrapper.
echo "==> Installing yosys-config wrapper ..."
install -m 755 "$REPO/build/yosys/yosys-config" "$INST/bin/yosys-config"

# ---------------------------------------------------------------------------
# Step 13: relocation + synthesis smoke -- the most important step.
#
# Running a copy while the ORIGINAL prefix still exists proves NOTHING: a
# binary that silently fell back to the build prefix would pass. The
# original must be moved away first, then the copy is run, then the
# original is restored. This is the only way to catch a compiled-in
# build-prefix fallback.
# ---------------------------------------------------------------------------
echo "==> Relocation + synthesis smoke ..."
STAGE="$WORK/relocated"
rm -rf "$STAGE"
cp -a "$INST" "$STAGE"

# Move the original away so a build-prefix fallback cannot masquerade as success.
mv "$INST" "${INST}.hidden"
rc=0
(
    cd "$STAGE"
    PATH="$STAGE/bin:/usr/bin:/bin"
    export PATH
    cp "$REPO/build/yosys/smoke.v" .
    yosys -q -p "read_verilog smoke.v; synth; write_json smoke.json" || exit 21
    [ -s smoke.json ] || exit 22
    python3 -c 'import json,sys; d=json.load(open("smoke.json")); n=sum(len(m.get("cells") or {}) for m in d["modules"].values()); sys.exit(0 if n>=1 else 1)' || exit 23
    dd=$(yosys-config --datdir) || exit 24
    [ "$dd" = "$STAGE/share/yosys" ] || exit 25
) || rc=$?

# Restore the original install tree before reporting.
mv "${INST}.hidden" "$INST"

case "$rc" in
    0) echo "  OK -- synthesised and wrote smoke.json with >=1 cell; yosys-config relocates" ;;
    21) echo "ERROR: yosys synth failed in relocated tree" >&2; exit 1 ;;
    22) echo "ERROR: smoke.json was not written / is empty in relocated tree" >&2; exit 1 ;;
    23) echo "ERROR: smoke.json has no cells -- synthesis produced an empty netlist" >&2; exit 1 ;;
    24) echo "ERROR: yosys-config --datdir failed in relocated tree" >&2; exit 1 ;;
    25) echo "ERROR: yosys-config --datdir did not equal \$STAGE/share/yosys -- prefix not relocatable" >&2; exit 1 ;;
    *) echo "ERROR: relocation smoke failed (rc=$rc)" >&2; exit 1 ;;
esac

# ---------------------------------------------------------------------------
# Step 14: package.
#
# ELF binaries go through loadout_package_bin (strip -> patchelf -> bzip2).
# Shell scripts (yosys-config, and any of yosys-smtbmc/yosys-witness that are
# scripts) must NOT go through loadout_package_bin -- it strips and
# patchelfs, which corrupts a script. bzip2 them straight through.
# ---------------------------------------------------------------------------
echo "==> Packaging ..."
mkdir -p "$LOADOUT_BIN_DIR"
for b in yosys yosys-abc yosys-filterlib; do
    loadout_package_bin "$INST/bin/$b" "$b"
done

# yosys-config is a script -- bzip2 directly.
bzip2 -c "$INST/bin/yosys-config" > "$LOADOUT_BIN_DIR/yosys-config.bz2"
chmod 644 "$LOADOUT_BIN_DIR/yosys-config.bz2"
echo "Packaged: $LOADOUT_BIN_DIR/yosys-config.bz2 (script)"

# yosys-witness is deliberately NOT packaged. It is a Python script that does
# `import click` at module scope, and click is not on a stock EL8 system
# python -- so on an air-gapped farm node it cannot even print its help; it
# dies with ModuleNotFoundError. Shipping a binary that is guaranteed to crash
# is worse than not shipping it (same call as verilator_bin_dbg, which this
# repo also declines to ship). yosys-smtbmc IS shipped: it imports only stdlib
# plus its own siblings (smtio, ywio) and works.
#
# If yosys-witness is ever wanted, the fix is to bundle click for the system
# python or reroute the script at portable-python -- not to relax the probe.
for s in yosys-smtbmc; do
    f="$INST/bin/$s"
    [ -f "$f" ] || continue
    if [ "$(head -c2 "$f" 2>/dev/null)" = "#!" ]; then
        bzip2 -c "$f" > "$LOADOUT_BIN_DIR/${s}.bz2"
        chmod 644 "$LOADOUT_BIN_DIR/${s}.bz2"
        echo "Packaged: $LOADOUT_BIN_DIR/${s}.bz2 (script)"
    else
        loadout_package_bin "$f" "$s"
    fi
done

# Step 15: runtime archive (share/yosys techlib tree).
mkdir -p "$RUNTIME_DIR"
tar cjf "$RUNTIME_DIR/yosys.tar.bz2" -C "$INST" ./share
echo "Packaged: $RUNTIME_DIR/yosys.tar.bz2 ($(du -h "$RUNTIME_DIR/yosys.tar.bz2" | cut -f1))"

# Step 16: stamp version in packages.json.
loadout_stamp_version "$PKG" "$version"

# Step 17: next steps.
cat <<EOF

Done.

Next, as for every payload change:
  ./build/strip-all-elf-binaries
  python3.14 build/gen-content-manifest
  ./loadout completion bash > envs/bash/global/completions/loadout.bash
  python3.14 build/gen-readme-table
EOF
