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
# Step 12b: yosys-pyosys -- the `yosys -y` bridge.
#
# `yosys` becomes a WRAPPER (like wezterm/expect/octave in this repo):
#   bin/yosys          the wrapper: passes through unless `-y` is used, in
#                      which case it runs the script under portable-python with
#                      the pyosys package on sys.path
#   bin/yosys.bin      the real Yosys binary (this build)
#   lib/yosys-pyosys/  the upstream `pyosys` wheel: libyosys.so + data tree
#
# WHY: LibreLane runs every synthesis step as `yosys -y <script.py>`, and `-y`
# only exists when Yosys was compiled with YOSYS_ENABLE_PYTHON. That needs a
# Python development prefix and a pybind11/cxxheaderparser build env in the EL8
# container; the upstream wheel already ships a libyosys built from this same
# release, so the wrapper is smaller and closer to what upstream ships for
# non-python builds. Full rationale in build/yosys/yosys-wrapper's header.
# ---------------------------------------------------------------------------
PYOSYS_VERSION="${YOSYS_PYOSYS_VERSION:-$version}"
# Pinned sha256 of the cp314 manylinux wheel, per version. The check below
# applies to a vendored wheel and to a freshly fetched one alike: if PyPI ever
# serves different bytes for a pinned version the build stops rather than
# shipping them. A version with no pin here is fetched and accepted without
# verification -- add the pin when adding the version.
case "$PYOSYS_VERSION" in
    0.69) PYOSYS_SHA256="c357596079333319795925dcd76babd257f306b4a9cfbb598335c4cc7f680147" ;;
    *)    PYOSYS_SHA256="" ;;
esac
PYOSYS_WHEEL="$REPO/payload/$(basename "$PLATFORM_DIR")/wheels/pyosys-${PYOSYS_VERSION}-cp314-cp314-manylinux_2_27_x86_64.manylinux_2_28_x86_64.whl"
echo "==> Packaging yosys-pyosys $PYOSYS_VERSION ..."
if [ ! -f "$PYOSYS_WHEEL" ]; then
    WHEELS_DIR="$(dirname "$PYOSYS_WHEEL")"
    echo "  wheel not present -- fetching pyosys $PYOSYS_VERSION from PyPI ..."
    mkdir -p "$WHEELS_DIR"
    python3 - "$WHEELS_DIR" "$PYOSYS_VERSION" << 'PYEOF'
import json, os, sys, urllib.request

out, ver = sys.argv[1], sys.argv[2]
with urllib.request.urlopen(f"https://pypi.org/pypi/pyosys/{ver}/json") as fh:
    data = json.load(fh)
# Pick the cp314 manylinux artefact explicitly: the wheel also exists for other
# interpreters and for musl, and pip's tag matching is exact (no downward
# implication), so a loose "latest" choice would hand a future bump the wrong
# ABI.
want = [
    u for u in data["urls"]
    if u["filename"].endswith("cp314-cp314-manylinux_2_27_x86_64.manylinux_2_28_x86_64.whl")
]
if len(want) != 1:
    sys.exit(f"expected exactly 1 cp314 manylinux wheel for pyosys {ver}, found {len(want)}")
u = want[0]
urllib.request.urlretrieve(u["url"], os.path.join(out, u["filename"]))
print(f"  fetched {u['filename']}")
print(f"  sha256 {u['digests']['sha256']}")
PYEOF
fi
[ -f "$PYOSYS_WHEEL" ] || { echo "ERROR: no pyosys wheel at $PYOSYS_WHEEL" >&2; exit 1; }

# Verify the wheel against the pin. Applies to a vendored wheel and to a
# freshly fetched one alike.
if [ -n "$PYOSYS_SHA256" ]; then
    have=$(sha256sum "$PYOSYS_WHEEL" | cut -d' ' -f1)
    if [ "$have" != "$PYOSYS_SHA256" ]; then
        echo "ERROR: pyosys wheel sha256 mismatch" >&2
        echo "  expected $PYOSYS_SHA256" >&2
        echo "  actual   $have" >&2
        exit 1
    fi
    echo "  sha256 verified against pin"
else
    echo "  WARNING: no sha256 pin for pyosys $PYOSYS_VERSION -- wheel accepted unverified" >&2
fi

# Extract ONLY the import surface + the shared library, laid out as a package
# directory so `import pyosys` works:
#     lib/yosys-pyosys/pyosys/{__init__.py,libyosys.so}
#     lib/yosys-pyosys/click/           vendored, see below
# PYTHONPATH=<prefix>/lib/yosys-pyosys makes both importable in the -y process.
#
# The wheel's other ~32MB (a duplicate share/ tree and a second yosys-abc) is not
# needed:
#   - python3.14 in the same prefix is the interpreter, so libyosys resolves its
#     data tree through the readlink("/proc/self/exe") path this repo's yosys
#     already installs (share/yosys) and finds the sibling yosys-abc.
#     VERIFIED: `synth` (which reads the techlib tree and shells out to ABC)
#     succeeds with just __init__.py + libyosys.so on PYTHONPATH.
#   - share/python3 is a copy of the interpreter's own stubs that nothing in
#     the librelane scripts path imports.
# Dropping them keeps the package at ~49MB instead of ~81MB and leaves exactly
# ONE copy of every data file on disk.
PYOSYS_STAGE="$INST/lib/yosys-pyosys"
rm -rf "$PYOSYS_STAGE" "$WORK/pyosys-x"
mkdir -p "$PYOSYS_STAGE/pyosys"
python3 -c "
import sys, zipfile
zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])
" "$PYOSYS_WHEEL" "$WORK/pyosys-x"
cp "$WORK/pyosys-x/pyosys/__init__.py" "$WORK/pyosys-x/pyosys/libyosys.so" "$PYOSYS_STAGE/pyosys/"
rm -rf "$WORK/pyosys-x"
for f in __init__.py libyosys.so; do
    [ -s "$PYOSYS_STAGE/pyosys/$f" ] || {
        echo "ERROR: pyosys wheel has no pyosys/$f -- upstream layout changed." >&2
        exit 1
    }
done

# Vendor click. LibreLane's synthesis scripts (scripts/pyosys/json_header.py,
# synthesize.py) `import click`, and the -y process runs under portable-python,
# which has no site-packages click. LibreLane's own venv does have it, but a
# venv does not put its site-packages on a subprocess's sys.path -- only
# PYTHONPATH crosses that boundary, and librelane only adds its scripts dir.
# 8.2.1 is librelane's pin. Same pattern as sby's vendored click (see
# ADDING_BINARIES), and it keeps portable-python itself minimal.
CLICK_WHEEL=$(ls "$REPO"/payload/$(basename "$PLATFORM_DIR")/wheels/click-8.2.1-*.whl 2> /dev/null | head -1)
if [ -z "$CLICK_WHEEL" ]; then
    CLICK_WHEEL=$(ls "$REPO"/payload/$(basename "$PLATFORM_DIR")/wheels/click-*.whl 2> /dev/null | sort -V | tail -1)
fi
[ -n "$CLICK_WHEEL" ] || {
    echo "ERROR: no click wheel in the payload wheelhouse to vendor for yosys -y." >&2
    echo "       (librelane's synthesis scripts import it; portable-python has none)" >&2
    exit 1
}
rm -rf "$WORK/click-x"
python3 -c "
import sys, zipfile
zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])
" "$CLICK_WHEEL" "$WORK/click-x"
cp -a "$WORK/click-x/click" "$PYOSYS_STAGE/click"
rm -rf "$WORK/click-x"
[ -f "$PYOSYS_STAGE/click/__init__.py" ] || { echo "ERROR: vendored click is incomplete" >&2; exit 1; }
echo "  vendored click $(basename "$CLICK_WHEEL") into lib/yosys-pyosys/"

echo "  staged lib/yosys-pyosys: $(du -sh "$PYOSYS_STAGE" | cut -f1) (libyosys.so + __init__.py + click)"

# Install the wrapper as `yosys` and keep the real binary beside it as
# `yosys.bin`. This is the deployed layout the smoke below exercises.
mv "$INST/bin/yosys" "$INST/bin/yosys.bin"
install -m 755 "$REPO/build/yosys/yosys-wrapper" "$INST/bin/yosys"

bzip2 -c "$REPO/build/yosys/yosys-wrapper" > "$LOADOUT_BIN_DIR/yosys.bz2"
chmod 644 "$LOADOUT_BIN_DIR/yosys.bz2"
echo "  packaged bin/yosys.bz2 (wrapper script)"

# The real binary ships as yosys.bin. loadout_package_bin does strip -> patchelf
# -> bzip2; strip is a no-op here (step 11 already stripped it).
loadout_package_bin "$INST/bin/yosys.bin" "yosys.bin"

# ---------------------------------------------------------------------------
# Step 13: relocation + synthesis smoke -- the most important step.
#
# Running a copy while the ORIGINAL prefix still exists proves NOTHING: a
# binary that silently fell back to the build prefix would pass. The
# original must be moved away first, then the copy is run, then the
# original is restored. This is the only way to catch a compiled-in
# build-prefix fallback.
#
# Three things are proven here, all on the RELOCATED tree:
#   1. plain `yosys` still synthesises (the wrapper's passthrough path)
#   2. `yosys -y` runs a Python script -- the LibreLane path, which is the
#      entire reason the wrapper exists
#   3. yosys-config still reports the relocated prefix
# For (2) the stage needs an interpreter, so portable-python is installed INTO
# the stage tree: that is exactly the deployed shape (both live in one prefix),
# and it keeps the smoke independent of whatever the build box has in
# $HOME/.local.
# ---------------------------------------------------------------------------
echo "==> Relocation + synthesis smoke ..."
STAGE="$WORK/relocated"
rm -rf "$STAGE"
cp -a "$INST" "$STAGE"

# portable-python, for the -y path. Optional in the sense that it is skipped
# only if no payload archive exists at all -- but then the -y check would be
# vacuous, so treat a missing archive as an error.
PP_TAR=$(ls "$REPO"/payload/*/portable-python-*.tar.bz2 2> /dev/null | head -1)
[ -n "$PP_TAR" ] || { echo "ERROR: no portable-python archive for the -y smoke." >&2; exit 1; }
mkdir -p "$WORK/pp"
tar xjf "$PP_TAR" -C "$WORK/pp" --strip-components=1
( cd "$WORK/pp" && ./install.sh --prefix "$STAGE" --force --no-test ) > "$WORK/pp-install.log" 2>&1 || {
    echo "ERROR: portable-python install into the smoke stage failed; tail:" >&2
    tail -20 "$WORK/pp-install.log" >&2
    exit 1
}
[ -x "$STAGE/bin/python3.14" ] || { echo "ERROR: stage has no python3.14 -- -y cannot be tested." >&2; exit 1; }

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

    # The LibreLane path. A script that exercises the API the real synthesis
    # scripts use -- Design(), run_pass with a command string, and the data
    # tree (read_verilog of a techlib file it must find through /proc/self/exe).
    #
    # The script also asserts the ARGV CONTRACT, which is what broke before:
    # kernel/driver.cc:530-553 sets sys.argv = [scriptfile] + (everything after
    # `--`). LibreLane's PyosysStep.get_command() emits
    #   yosys -y <script.py> [-Q] [-q|-qq] -- --config-in <config.json>
    # and its scripts are click commands that read --config-in from sys.argv.
    # A wrapper that forwards the ORIGINAL argv hands the script a leading `-y`
    # and click dies -- every stage-5 script fails while a bare `-y script` run
    # still looks fine. So the smoke passes a flag that the script must see.
    cat > py_smoke.py <<'PYEOF'
import os
import sys
from pyosys import libyosys as ys

if not getattr(sys, "_pyosys_dir", None):
    sys.exit("pyosys did not initialise sys._pyosys_dir")

# --- argv contract (driver.cc:530-553) -------------------------------------
# Only what follows `--` may reach the script. `--config-in <path>` is the
# exact shape librelane uses; `--probe-arg` is a marker with no meaning.
argv = sys.argv[1:]
if "-y" in argv or "-q" in argv or "-Q" in argv:
    sys.exit(f"argv leak: yosys flags reached the script: {argv!r}")
if "--config-in" not in argv:
    sys.exit(f"--config-in did not reach the script: {argv!r}")
probe = argv[argv.index("--config-in") + 1]
if not probe.endswith("config.json"):
    sys.exit(f"--config-in value wrong: {probe!r}")
if sys.argv[0] != "py_smoke.py":
    sys.exit(f"sys.argv[0] should be the script path, got {sys.argv[0]!r}")
# driver.cc inserts the script's PARENT DIRECTORY at sys.path[0]; running the
# file directly gives the cwd instead. Both are fine -- the directory must just
# be the one the script actually lives in. Assert it resolves to the script's
# own directory rather than some yosys install tree.
_here = os.path.dirname(os.path.abspath(__file__))
_p0 = os.path.abspath(sys.path[0]) if sys.path[0] else os.getcwd()
if _p0 != _here:
    sys.exit(f"sys.path[0] should be the script's dir ({_here!r}), got {_p0!r}")

d = ys.Design()
d.run_pass("read_verilog smoke.v")
d.run_pass("synth")
d.run_pass("stat")
print("PYOSYS_SMOKE_OK", ys.Globals.yosys_version_str.split()[1])
PYEOF
    : > config.json
    out=$(yosys -y py_smoke.py -Q -q -- --config-in config.json --probe-arg) || exit 26
    echo "$out" | grep -q "PYOSYS_SMOKE_OK" || { echo "$out" >&2; exit 27; }
) || rc=$?

# Restore the original install tree before reporting.
mv "${INST}.hidden" "$INST"

case "$rc" in
    0) echo "  OK -- synthesised (plain), ran a Python script via -y, and yosys-config relocates" ;;
    21) echo "ERROR: yosys synth failed in relocated tree" >&2; exit 1 ;;
    22) echo "ERROR: smoke.json was not written / is empty in relocated tree" >&2; exit 1 ;;
    23) echo "ERROR: smoke.json has no cells -- synthesis produced an empty netlist" >&2; exit 1 ;;
    24) echo "ERROR: yosys-config --datdir failed in relocated tree" >&2; exit 1 ;;
    25) echo "ERROR: yosys-config --datdir did not equal \$STAGE/share/yosys -- prefix not relocatable" >&2; exit 1 ;;
    26) echo "ERROR: 'yosys -y' failed in the relocated tree -- the LibreLane path is broken" >&2; exit 1 ;;
    27) echo "ERROR: 'yosys -y' ran but its script did not complete" >&2; exit 1 ;;
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
# `yosys` is the wrapper (already packaged above, straight bzip2). Only the real
# ELF binaries go through loadout_package_bin -- it strips and patchelfs, which
# would destroy the wrapper.
for b in yosys-abc yosys-filterlib; do
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

# Step 15: runtime archive. Two trees:
#   share/yosys       the techlib data tree (simlib.v, techmap, cells_sim...)
#   lib/yosys-pyosys  the `yosys -y` bridge staged in Step 12b: the pyosys
#                     package (__init__.py + libyosys.so) plus vendored click.
# Both are part of the RELOCATABLE install tree, so they ride in the one
# runtime archive the registry already declares (`archive:` is a single field;
# a second archive would have nowhere to be listed). One `remove_before_extract`
# entry per top-level tree keeps reinstalls clean.
mkdir -p "$RUNTIME_DIR"
tar cjf "$RUNTIME_DIR/yosys.tar.bz2" -C "$INST" ./share ./lib
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
