#!/bin/sh
# Build Verilator (Verilog/SystemVerilog -> C++ simulator) from source for
# el8.x86_64.glibc2p28.
#
# Verilator compiles synthesizable Verilog/SystemVerilog into a C++ model that
# is then compiled by the user's own g++. It is a lint/coverage/regression tool
# here, not a replacement for a commercial simulator: the target users have paid
# simulators, and Verilator does not do event-driven simulation of
# non-synthesizable testbench code.
#
# NO WRAPPER NEEDED -- verified. `bin/verilator` is upstream's Perl driver and it
# derives VERILATOR_ROOT itself:
#     my $verilator_pkgdatadir_relpath = "../share/verilator";
#     my $verilator_root = realpath("$RealBin/$verilator_pkgdatadir_relpath");
# so it resolves relative to wherever the tree is installed. The shims in
# `share/verilator/bin/` likewise exec through a relative `../../../bin`. The one
# artifact that is NOT self-relocating is `share/pkgconfig/verilator.pc`, whose
# `prefix=` is an absolute build path; this script rewrites it to the
# relocation token and the registry's relocate_token/relocate_root fields make
# the installer substitute the real deployment root (same mechanism as modules).
# The script PROVES relocatability by copying the staged tree to a second path
# and running a full RTL->C++->binary->execute smoke there.
#
# NOTHING TO BUNDLE. `verilator_bin` links only libpthread/libm/libc: Verilator's
# build uses -static-libstdc++/-static-libgcc, so there is no libstdc++.so.6
# dependency and no GLIBCXX_* version requirement at all. Max glibc symbol is
# GLIBC_2.17, well under EL8's 2.28. No patchelf, no RPATH -- same as espresso.
#
# HOST REQUIREMENT -- perl. `bin/verilator` and `bin/verilator_coverage` are Perl
# (`#!/usr/bin/env perl`); `verilator_gantt`, `verilator_profcfunc` and
# `verilator_includer` are Python 3. Perl is NOT bundled, exactly as for `cloc`,
# so the clean-container Tier 3 gate must list verilator as a host-contract skip.
# A farm node running an EDA flow has perl. Users also need their own `g++` to
# compile the generated model -- EL8's system g++ 8.5 is sufficient (verified).
#
# DELIBERATELY NOT SHIPPED -- `verilator_bin_dbg` (104 MB unstripped, ~25 MB
# compressed). It is the assertion-enabled build used only by `verilator --debug`
# for debugging Verilator ITSELF, not user RTL. Dropping it removes `--debug`,
# which fails loudly ("Exec failed"), and saves more payload than every other
# tool in this package combined. `verilator_coverage_bin_dbg` IS shipped: there
# is no release build of it, so `verilator_coverage` needs it, and it is 320 KB.
#
# Prerequisites on the build machine (EL8):
#   dnf install autoconf flex bison help2man gcc-c++ make perl python3
#   help2man is required: `make` builds man pages and dies with exit 127 without it.
#
# Policy: always build from a stable tagged release.
#
# Usage (run from any directory):
#   ./build/build-verilator.sh --tag v5.050

set -eu

REPO="$(cd "$(dirname "$0")/.." && pwd)"
PLATFORM_DIR="$REPO/payload/el8.x86_64.glibc2p28"
BIN_DIR="$PLATFORM_DIR/bin"
RUNTIME_DIR="$PLATFORM_DIR/runtime"
RELOC_TOKEN="/__LOADOUT_RELOC_ROOT__"
TAG=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        --tag)
            shift
            [ "$#" -gt 0 ] || { echo "missing value for --tag" >&2; exit 2; }
            TAG="$1"
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
    echo "  $0 --tag v5.050" >&2
    echo "" >&2
    echo "Stable releases: https://github.com/verilator/verilator/tags" >&2
    echo "" >&2
    echo "Policy: this project ships stable releases only." >&2
    exit 1
fi

case "$TAG" in
    v[0-9]*) ;;
    *) echo "ERROR: expected a vX.YYY tag, got: $TAG" >&2; exit 1 ;;
esac

VERSION="${TAG#v}"

# Shipped binaries. verilator_bin_dbg is deliberately absent (see header).
EXPECTED_BINS="verilator verilator_bin verilator_coverage verilator_coverage_bin_dbg verilator_gantt verilator_profcfunc"
NUM_BINS=6
# Of those, the ELFs that get stripped. The rest are perl/python scripts.
ELF_BINS="verilator_bin verilator_coverage_bin_dbg"

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
need autoconf
need flex
need bison
need help2man
need perl
need python3

WORK_DIR=$(mktemp -d /tmp/build-verilator-XXXXXX)
INST_DIR="/tmp/verilator-install-${VERSION}"
rm -rf "$INST_DIR"
mkdir -p "$INST_DIR"
trap 'rm -rf "$WORK_DIR" "$INST_DIR"' EXIT

echo "==> Cloning verilator ${TAG} ..."
git clone --depth 1 --branch "$TAG" https://github.com/verilator/verilator.git \
    "$WORK_DIR/verilator" >/dev/null 2>&1
cd "$WORK_DIR/verilator"

CONF_VERSION=$(sed -n 's/^AC_INIT(\[Verilator\],\[\([0-9.]*\) .*/\1/p' configure.ac)
if [ "$CONF_VERSION" != "$VERSION" ]; then
    echo "ERROR: tag $TAG carries AC_INIT version $CONF_VERSION, expected $VERSION" >&2
    exit 1
fi

echo "==> autoconf ..."
autoconf >"$WORK_DIR/autoconf.log" 2>&1 || {
    echo "ERROR: autoconf failed:" >&2; tail -20 "$WORK_DIR/autoconf.log" >&2; exit 1
}

echo "==> Configuring ..."
./configure --prefix="$INST_DIR" >"$WORK_DIR/configure.log" 2>&1 || {
    echo "ERROR: configure failed:" >&2; tail -30 "$WORK_DIR/configure.log" >&2; exit 1
}

echo "==> Building ..."
make -j"$(nproc 2>/dev/null || echo 2)" >"$WORK_DIR/build.log" 2>&1 || {
    echo "ERROR: build failed; errors:" >&2
    grep -iE '\berror\b|Error [0-9]' "$WORK_DIR/build.log" | head -20 >&2
    exit 1
}

echo "==> Installing ..."
make install >"$WORK_DIR/install.log" 2>&1 || {
    echo "ERROR: make install failed:" >&2; tail -20 "$WORK_DIR/install.log" >&2; exit 1
}

echo "==> Checking the installed tool set ..."
for b in $EXPECTED_BINS; do
    [ -x "$INST_DIR/bin/$b" ] || {
        echo "ERROR: expected binary missing after install: bin/$b" >&2
        exit 1
    }
done
[ -f "$INST_DIR/share/verilator/include/verilated.mk" ] || {
    echo "ERROR: share/verilator/include/verilated.mk missing -- the C++ model" >&2
    echo "cannot be built without it." >&2
    exit 1
}
echo "  OK: $NUM_BINS binaries + verilated.mk present"

echo "==> Checking glibc / C++ runtime requirements ..."
for b in $ELF_BINS; do
    f="$INST_DIR/bin/$b"
    MAX_GLIBC="$(readelf -V "$f" 2>/dev/null \
        | grep -oE 'GLIBC_[0-9]+\.[0-9]+' | sort -V | tail -1)"
    case "$MAX_GLIBC" in
        ''|GLIBC_2.2[0-8]|GLIBC_2.1[0-9]|GLIBC_2.[0-9]) ;;
        *) echo "ERROR: $b needs $MAX_GLIBC > GLIBC_2.28" >&2; exit 1 ;;
    esac
    # Verilator statically links libstdc++/libgcc. If a future release stops
    # doing that, the binary gains a libstdc++.so.6 dependency built by
    # gcc-toolset-14 -- newer than EL8's system libstdc++, which this repo
    # never bundles. Catch that here rather than on a user's farm node.
    if ldd "$f" 2>/dev/null | grep -q 'libstdc++\.so\.6'; then
        echo "ERROR: $b dynamically links libstdc++.so.6." >&2
        echo "Verilator is expected to link the C++ runtime statically; a" >&2
        echo "gcc-toolset-14 libstdc++ dependency will not resolve on EL8." >&2
        exit 1
    fi
    for so in $(ldd "$f" 2>/dev/null | awk '/=>/ {print $1}' | sort -u); do
        case "$so" in
            linux-vdso*|ld-linux*) continue ;;
            libc.so.6|libm.so.6|libdl.so.2|libpthread.so.0|librt.so.1) continue ;;
        esac
        echo "ERROR: $b needs an unexpected shared library: $so" >&2
        echo "Nothing is bundled for verilator; bundle it or explain it here." >&2
        exit 1
    done
done
echo "  OK: glibc floor fine, C++ runtime static, no libs to bundle"

echo "==> Dropping verilator_bin_dbg (104 MB, --debug only) ..."
rm -f "$INST_DIR/bin/verilator_bin_dbg"

echo "==> Tokenizing share/pkgconfig/verilator.pc ..."
PC="$INST_DIR/share/pkgconfig/verilator.pc"
[ -f "$PC" ] || { echo "ERROR: $PC not found after install" >&2; exit 1; }
sed -i "s|$INST_DIR|$RELOC_TOKEN|g" "$PC"
grep -q "^prefix=$RELOC_TOKEN\$" "$PC" || {
    echo "ERROR: verilator.pc prefix was not tokenized:" >&2
    grep '^prefix=' "$PC" >&2
    exit 1
}

echo "==> Verifying nothing else embeds the build prefix ..."
# bin/verilator resolves VERILATOR_ROOT from $RealBin, so the ONLY place the
# build prefix may survive is the tokenized .pc file. verilator_bin carries the
# prefix as a compiled-in *fallback* default root; the Perl driver always sets
# VERILATOR_ROOT before exec'ing it, and running verilator_bin directly without
# VERILATOR_ROOT fails loudly ("Misinstalled"), so that one is accepted.
BAD=$(find "$INST_DIR" -type f \
        ! -path "$PC" \
        ! -path "$INST_DIR/bin/verilator_bin" \
        -exec grep -lF "$INST_DIR" {} + 2>/dev/null || true)
if [ -n "$BAD" ]; then
    echo "ERROR: build prefix survives in:$BAD" >&2
    echo "Tokenize them (and widen relocate_root) or add a deriving wrapper." >&2
    exit 1
fi
echo "  OK: only the tokenized .pc and verilator_bin's fallback default"

echo "==> Proving relocatability: RTL -> C++ -> binary -> run from a MOVED tree ..."
# The whole no-wrapper claim rests on $RealBin-relative resolution. Copy the
# staged tree somewhere else entirely and drive a real elaboration+build+run
# there. `verilator --version` would pass even with a dead VERILATOR_ROOT.
MOVED="$WORK_DIR/moved-prefix/opt/somewhere/else"
mkdir -p "$MOVED"
cp -a "$INST_DIR/." "$MOVED/"
SMOKE="$WORK_DIR/smoke"
mkdir -p "$SMOKE"
cat > "$SMOKE/top.v" <<'EOF'
module top(input logic clk, output logic [7:0] cnt);
   always_ff @(posedge clk) cnt <= cnt + 8'd1;
endmodule
EOF
cat > "$SMOKE/sim.cpp" <<'EOF'
#include "Vtop.h"
#include "verilated.h"
#include <cstdio>
int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    Vtop* t = new Vtop;
    t->cnt = 0;
    for (int i = 0; i < 10; i++) { t->clk = 0; t->eval(); t->clk = 1; t->eval(); }
    printf("CNT=%d\n", (int)t->cnt);
    delete t;
    return 0;
}
EOF
# Use the SYSTEM g++, not gcc-toolset-14: that is what a farm node has, and the
# generated model must compile there.
( cd "$SMOKE" && env -u VERILATOR_ROOT PATH="/usr/bin:/bin" \
    "$MOVED/bin/verilator" -cc top.v --exe sim.cpp --build -j 4 -o simtop \
    >"$WORK_DIR/smoke.log" 2>&1 ) || {
    echo "ERROR: verilation/build failed from the moved tree:" >&2
    tail -25 "$WORK_DIR/smoke.log" >&2
    exit 1
}
SMOKE_OUT=$("$SMOKE/obj_dir/simtop" 2>&1) || {
    echo "ERROR: verilated simulation did not run: $SMOKE_OUT" >&2
    exit 1
}
[ "$SMOKE_OUT" = "CNT=10" ] || {
    echo "ERROR: verilated model produced '$SMOKE_OUT', expected 'CNT=10'" >&2
    exit 1
}
echo "  OK: moved tree elaborated, compiled with system g++, and ran (CNT=10)"

echo "==> Verifying version output ..."
VL_VER=$(env -u VERILATOR_ROOT "$MOVED/bin/verilator" --version 2>&1 | head -1)
echo "  $VL_VER"
echo "$VL_VER" | grep -qF "$VERSION" || {
    echo "ERROR: --version does not report $VERSION" >&2
    exit 1
}

echo "==> Packaging binaries ..."
PKG_DIR="$WORK_DIR/pkg"
mkdir -p "$PKG_DIR"
for b in $EXPECTED_BINS; do
    cp "$INST_DIR/bin/$b" "$PKG_DIR/$b"
    case " $ELF_BINS " in
        *" $b "*) strip "$PKG_DIR/$b" ;;
    esac
    bzip2 -kf "$PKG_DIR/$b"
    cp "$PKG_DIR/$b.bz2" "$BIN_DIR/$b.bz2"
done
echo "  Wrote $NUM_BINS *.bz2 to $BIN_DIR"

echo "==> Packaging verilator runtime (include tree, shims, examples, man, .pc) ..."
tar cjf "$RUNTIME_DIR/verilator.tar.bz2" \
    -C "$INST_DIR" \
    "./share/verilator" \
    "./share/man" \
    "./share/pkgconfig"
echo "  Wrote: $RUNTIME_DIR/verilator.tar.bz2 ($(wc -c < "$RUNTIME_DIR/verilator.tar.bz2" | tr -d ' ') bytes)"

echo "==> Updating packages.json ..."
python3 -c "
import sys, json
path, ver = sys.argv[1], sys.argv[2]
with open(path) as f:
    data = json.load(f)
pkgs = data['packages']
if 'verilator' in pkgs:
    pkgs['verilator']['version'] = ver
    print(f'packages.json: verilator version -> {ver}')
else:
    print('WARNING: verilator not found in packages.json, skipping version update')
with open(path, 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
" "$REPO/payload/packages.json" "$VERSION"

echo "==> Running strip-all-elf-binaries ..."
"$REPO/build/strip-all-elf-binaries"

echo ""
echo "Done."
echo ""
echo "Produced:"
for b in $EXPECTED_BINS; do echo "  $BIN_DIR/$b.bz2"; done
echo "  $RUNTIME_DIR/verilator.tar.bz2"
echo ""
echo "Reminders:"
echo "  - ./loadout completion bash > envs/bash/global/completions/loadout.bash"
echo "  - build/gen-content-manifest"
echo "  - build/ADDING_BINARIES.md note is MANDATORY"
echo ""
echo "Commit with:"
echo "  git add payload/el8.x86_64.glibc2p28/bin/ payload/el8.x86_64.glibc2p28/runtime/verilator.tar.bz2 \\"
echo "          .strip-manifest .content-manifest payload/packages.json build/build-verilator.sh"
echo "  git commit -m 'feat(payload): verilator ${VERSION} EL8 source build'"
