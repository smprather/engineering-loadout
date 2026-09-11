#!/bin/sh
# Build SymbiYosys (sby) + Z3 solver for el8.x86_64.glibc2p28.
#
# sby is the Yosys front-end for formal hardware verification (bmc/prove/cover
# via yosys-smtbmc + an SMT solver). It is pure Python (sbysrc/sby*.py, no
# compiled extensions on Linux -- the extern/launcher.c is Windows-only), so
# the "build" is stage + relocatable-prefix rewrite + package, not compile.
#
# No stable release exists upstream -- no GitHub releases, no PyPI, only
# yosys-compat tags (latest yosys-0.47; we ship Yosys 0.68) -- so --tag takes
# the pinned COMMIT HASH (strace-ui precedent), not a version. The smoke test
# below proves the pinned commit works with our Yosys; if it does not, pick a
# different commit, do not ship a broken formal tool.
#
# Z3 comes from the official z3-solver PyPI wheel (manylinux_2_27, so it runs
# on EL8 glibc 2.28; max GLIBC_2.26, max GLIBCXX_3.4.22 <= EL8's 3.4.25 --
# verified by readelf, no C++ runtime to bundle). The wheel's data/bin/z3 is
# a self-contained 25 MB ELF (NEEDED is system libs only, no libz3.so), so we
# extract just the binary: no EL8 C++ solver build needed. Pinned by version +
# sha256 (like OX_REPO_COMMIT in build-strace-ui.sh).
#
# Layout (relocatable, no absolute paths):
#   bin/sby              sh wrapper -> <prefix>/bin/python3.14 <prefix>/share/sby/sby.py
#   share/sby/sby*.py    sby sources (runtime/sby.tar.bz2)
#   bin/z3               SMT solver ELF (bin/z3.bz2)
# sby finds yosys + z3 on PATH (both are loadout bins). The upstream Makefile
# seds (##yosys-sys-path##, ##yosys-release-version##) are replicated below
# with our relocatable layout; all sby files live in one dir so sys.path[0]
# already covers the imports.
#
# Prerequisites on the build machine (EL8):
#   gcc make patchelf bzip2 curl python3 (for the prove smoke: yosys from the
#   repo payload, staged to a temp prefix -- the build image has no yosys)
#   # gcc-toolset-14 optional (z3 is prebuilt, sby is Python)
#
# Usage (run from any directory, but payload work happens in the container):
#   build/build-shell ./build/build-sby.sh --tag b1a1e98cba941ec8433f8dc27f416cd7bb7f14be

set -eu

REPO="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib.sh
. "$REPO/build/lib.sh"
BIN_DIR="$LOADOUT_BIN_DIR"
LIB64_DIR="$REPO/payload/$LOADOUT_PLATFORM/lib64"
RUNTIME_DIR="$REPO/payload/$LOADOUT_PLATFORM/runtime"
PATCHELF="$LOADOUT_PATCHELF"
CLONE_URL="https://github.com/YosysHQ/sby.git"

# Pinned inputs. SBY_TAG comes from --tag; Z3 is pinned here (wheel filename +
# sha256 from PyPI). Bump both together and re-verify the prove smoke.
Z3_VERSION="5.1.0.0"
Z3_WHEEL="z3_solver-${Z3_VERSION}-py3-none-manylinux_2_27_x86_64.whl"
Z3_SHA256="dfad9e309d7010b1ff6bdb33f21570a1603ef4727373221c7117a74448f0cfef"
Z3_URL="https://files.pythonhosted.org/packages/34/de/30329041d9a2dda11308576a80b5db17060e4b03a7ba7f550437fb38dd6b/${Z3_WHEEL}"

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

if [ -z "$tag" ]; then
    echo "ERROR: --tag is required. Specify the pinned sby commit hash, e.g.:" >&2
    echo "  $0 --tag b1a1e98cba941ec8433f8dc27f416cd7bb7f14be" >&2
    echo "Policy note: upstream has no tags or releases; the commit hash IS the pin." >&2
    exit 2
fi
case "$tag" in
    *[!0-9a-f]*)
        echo "ERROR: --tag must be a commit hash (got '$tag')" >&2; exit 1 ;;
esac
if [ "${#tag}" -lt 7 ] || [ "${#tag}" -gt 40 ]; then
    echo "ERROR: --tag must be a commit hash (got '$tag')" >&2; exit 1
fi

loadout_require_cmds git curl python3 bzip2
[ -x "$PATCHELF" ] || { echo "missing patchelf at $PATCHELF" >&2; exit 1; }

SRCDIR="/tmp/sby-src"
STAGE="/tmp/sby-stage"
rm -rf "$SRCDIR" "$STAGE"
mkdir -p "$SRCDIR" "$STAGE/bin" "$STAGE/share/sby"

if [ ! -d "$SRCDIR/.git" ]; then
    echo "Cloning $CLONE_URL ..."
    git clone --filter=blob:none "$CLONE_URL" "$SRCDIR"
fi
cd "$SRCDIR"
git fetch --tags origin >/dev/null 2>&1 || true
git checkout -q "$tag"
GOT="$(git rev-parse HEAD)"
case "$GOT" in
    "$tag"*)
        ;;
    *)
        echo "ERROR: checkout resolved to $GOT, wanted $tag" >&2
        exit 1
        ;;
esac
SHORT="$(git rev-parse --short=7 HEAD)"
echo "sby commit: $GOT ($SHORT)"

# --- stage sby Python sources -----------------------------------------------
# Replicates `make install` seds with our relocatable layout. All files land
# in share/sby/ so the script's own directory is already on sys.path; the
# sys-path placeholder becomes a no-op and the version records the pin.
echo "Staging sby sources ..."
for f in "$SRCDIR"/sbysrc/sby_*.py; do
    cp "$f" "$STAGE/share/sby/"
done
sed -e 's|##yosys-sys-path##|pass|' \
    -e "s|##yosys-release-version##|release_version = 'SBY $GOT'|" \
    "$SRCDIR/sbysrc/sby.py" > "$STAGE/share/sby/sby.py"
sed -e 's|##yosys-program-prefix##||' \
    "$SRCDIR/sbysrc/sby_core.py" > "$STAGE/share/sby/sby_core.py.tmp"
mv "$STAGE/share/sby/sby_core.py.tmp" "$STAGE/share/sby/sby_core.py"
chmod 644 "$STAGE"/share/sby/*.py
echo "  sby files: $(ls "$STAGE"/share/sby/*.py | wc -l)"

# Vendor click (sby_core imports it; portable-python is minimal and must stay
# that way). click is pure Python, no deps; copy the package out of the
# already-vendored wheelhouse wheel so sby is self-contained under share/sby/.
# Pinned here; bump with the wheelhouse (./build/update) and re-verify.
CLICK_WHEEL="click-8.4.2-py3-none-any.whl"
CLICK_SRC="$REPO/payload/$LOADOUT_PLATFORM/wheels/$CLICK_WHEEL"
[ -f "$CLICK_SRC" ] || { echo "ERROR: click wheel not found: $CLICK_SRC" >&2; exit 1; }
python3 -c "import zipfile,sys; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])" \
    "$CLICK_SRC" "/tmp/sby-click-$$"
cp -r "/tmp/sby-click-$$/click" "$STAGE/share/sby/click"
cp -r "/tmp/sby-click-$$"/click-*.dist-info "$STAGE/share/sby/"
chmod -R a+rX "$STAGE/share/sby/click" "$STAGE"/share/sby/click-*.dist-info
rm -rf "/tmp/sby-click-$$"
python3.14 -c "import sys; sys.path.insert(0, '$STAGE/share/sby'); import click; from importlib.metadata import version; print('  vendored click OK:', version('click'))"

# --- bin/sby wrapper ----------------------------------------------------------
# Derives prefix from its own path (never $HOME -- dest-dir installs must work),
# runs the prefix python3.14 (portable-python, a hard dep), falls back to PATH.
cat > "$STAGE/bin/sby" <<'WRAPPER'
#!/bin/sh
# sby launcher -- SymbiYosys formal verification front-end.
# Prefix-derived (relocatable); needs yosys + z3 on PATH (both loadout bins).
case "$0" in
    /*) script=$0 ;;
    *) script=$(command -v "$0") || exit 127 ;;
esac
prefix=$(CDPATH= cd -- "$(dirname -- "$script")/.." && pwd) || exit 1
py="$prefix/bin/python3.14"
if [ ! -x "$py" ]; then
    py=$(command -v python3.14) || py=$(command -v python3) || {
        echo "sby: no python3 found (need portable-python or system python3)" >&2
        exit 127
    }
fi
exec "$py" "$prefix/share/sby/sby.py" "$@"
WRAPPER
chmod 755 "$STAGE/bin/sby"

# --- z3 from the pinned wheel ---------------------------------------------------
echo "Fetching z3-solver $Z3_VERSION wheel ..."
Z3_DL="/tmp/z3-wheel-${Z3_VERSION}.whl"
rm -f "$Z3_DL"
curl -fsSL -o "$Z3_DL" "$Z3_URL" || { echo "ERROR: z3 wheel download failed" >&2; exit 1; }
echo "$Z3_SHA256  $Z3_DL" | sha256sum -c - || { echo "ERROR: z3 wheel sha256 mismatch" >&2; exit 1; }
echo "  z3 wheel verified"
Z3_EXTRACT="/tmp/z3-extract"
rm -rf "$Z3_EXTRACT"
mkdir -p "$Z3_EXTRACT"
cd "$Z3_EXTRACT"
python3 -c "import zipfile; zipfile.ZipFile('$Z3_DL').extract('z3_solver-${Z3_VERSION}.data/data/bin/z3', '.')"
cp "z3_solver-${Z3_VERSION}.data/data/bin/z3" "$STAGE/bin/z3"
chmod 755 "$STAGE/bin/z3"
cd /
rm -f "$Z3_DL"
rm -rf "$Z3_EXTRACT"
echo "  z3 binary staged"

# glibc floor: z3 must not exceed EL8's 2.28 (wheel says 2.27, verify anyway).
MAX_GLIBC="$(readelf -V "$STAGE/bin/z3" 2>/dev/null \
    | grep -oE 'GLIBC_[0-9]+\.[0-9]+' | sort -V | tail -1)"
echo "z3 max glibc symbol: $MAX_GLIBC (target: <= GLIBC_2.28)"
case "$MAX_GLIBC" in
    GLIBC_2.2[0-8]|GLIBC_2.1[0-9]|GLIBC_2.[0-9])
        echo "OK -- z3 compatible with EL8 glibc 2.28" ;;
    *)
        echo "ERROR: $MAX_GLIBC > GLIBC_2.28 -- z3 wheel no longer runs on EL8" >&2
        exit 1 ;;
esac
# C++ runtime floor: EL8 libstdc++ tops at GLIBCXX_3.4.25.
MAX_CXX="$(readelf -V "$STAGE/bin/z3" 2>/dev/null \
    | grep -oE 'GLIBCXX_[0-9.]+' | sort -V | tail -1)"
echo "z3 max GLIBCXX symbol: $MAX_CXX (target: <= GLIBCXX_3.4.25)"
case "$MAX_CXX" in
    GLIBCXX_3.4.2[0-5]|GLIBCXX_3.4.1[0-9]|GLIBCXX_3.4.[0-9])
        echo "OK -- z3 compatible with EL8 libstdc++" ;;
    *)
        echo "ERROR: $MAX_CXX > GLIBCXX_3.4.25 -- z3 wheel needs newer libstdc++ than EL8" >&2
        exit 1 ;;
esac

# --- package --------------------------------------------------------------------
# z3 is an ELF: strip -> patchelf -> bzip2 (same order as loadout_package_bin;
# inlined here because that helper also stamps/commits assumptions we handle
# explicitly below for the two-artifact sby+z3 build).
# shellcheck disable=SC2016  # $ORIGIN is an ld.so token, not a shell var
echo "Packaging z3 binary ..."
_Z3_WORK=$(mktemp "${TMPDIR:-/tmp}/loadout-pkg-z3.XXXXXX")
cp "$STAGE/bin/z3" "$_Z3_WORK"
strip "$_Z3_WORK"
"$PATCHELF" --set-rpath '$ORIGIN/../lib64' "$_Z3_WORK" || {
    echo "ERROR: patchelf failed for z3" >&2; exit 1
}
bzip2 -f "$_Z3_WORK"
mkdir -p "$BIN_DIR"
cp "${_Z3_WORK}.bz2" "$BIN_DIR/z3.bz2"
chmod 644 "$BIN_DIR/z3.bz2"
rm -f "${_Z3_WORK}.bz2"
echo "Packaged: $BIN_DIR/z3.bz2"

# sby wrapper is sh (not ELF): bzip2 directly, no strip/patchelf.
echo "Packaging sby wrapper ..."
bzip2 -kf "$STAGE/bin/sby"
cp "$STAGE/bin/sby.bz2" "$BIN_DIR/sby.bz2"
chmod 644 "$BIN_DIR/sby.bz2"
echo "Packaged: $BIN_DIR/sby.bz2"

# sby Python sources as a runtime archive.
echo "Packaging sby runtime (share/sby) ..."
mkdir -p "$RUNTIME_DIR"
tar -cjf "/tmp/sby_runtime_${SHORT}.tar.bz2" -C "$STAGE" ./share/sby
cp "/tmp/sby_runtime_${SHORT}.tar.bz2" "$RUNTIME_DIR/sby.tar.bz2"
rm -f "/tmp/sby_runtime_${SHORT}.tar.bz2"
echo "Packaged: $RUNTIME_DIR/sby.tar.bz2"

loadout_stamp_version z3 "$Z3_VERSION"
# sby has no version; stamp the 7-char commit (strace-ui precedent).
python3 - "$REPO/payload/packages.json" sby "$SHORT" << 'PYEOF'
import re
import sys

path, pkg, ver = sys.argv[1:4]
txt = open(path).read()
pat = r'("%s": \{[^{}]*?"version":\s*")([^"]*)(")' % re.escape(pkg)
new, n = re.subn(pat, lambda m: m.group(1) + ver + m.group(3), txt, count=1, flags=re.S)
if n != 1:
    sys.exit(f"could not stamp version for package {pkg!r} in {path}")
open(path, "w").write(new)
print(f"packages.json: {pkg} version -> {ver}")
PYEOF

# --- stage-verify: prove a design with OUR yosys + staged z3/sby ---------------
# House rule: flags prove nothing. sby must drive yosys-smtbmc (from the repo
# payload, temp prefix -- the build image has no yosys) and discharge a real
# assertion with z3. This is also the Yosys-0.68 compatibility proof for the
# pinned commit: sby tracks Yosys main, and a mismatch fails here, not on a
# user's box.
echo ""
echo "Stage-verify: sby prove with repo Yosys 0.68 + staged z3 ..."
YOSYS_TMP="/tmp/sby-verify-yosys"
rm -rf "$YOSYS_TMP"
mkdir -p "$YOSYS_TMP/bin" "$YOSYS_TMP/share"
for b in yosys yosys-abc yosys-config yosys-filterlib yosys-smtbmc; do
    bzip2 -dc "$REPO/payload/$LOADOUT_PLATFORM/bin/$b.bz2" > "$YOSYS_TMP/bin/$b" \
        || { echo "ERROR: cannot stage repo yosys binary $b" >&2; exit 1; }
    chmod 755 "$YOSYS_TMP/bin/$b"
done
tar -xjf "$REPO/payload/$LOADOUT_PLATFORM/runtime/yosys.tar.bz2" -C "$YOSYS_TMP" \
    || { echo "ERROR: cannot stage repo yosys runtime" >&2; exit 1; }
"$YOSYS_TMP/bin/yosys" -V || { echo "ERROR: staged yosys does not run" >&2; exit 1; }

VERIFY_DIR="/tmp/sby-verify-$$"
rm -rf "$VERIFY_DIR"
mkdir -p "$VERIFY_DIR"
cat > "$VERIFY_DIR/demo.v" <<'EOF'
// 2-bit counter: cnt is always <= 3 from ANY start state (arbitrary initial
// values included), so both basecase and induction must PASS. A FAIL here
// means the tool flow is broken, not the design.
module demo(input clk, rst, output reg [1:0] cnt);
always @(posedge clk) begin
    if (rst)
        cnt <= 0;
    else
        cnt <= cnt + 1;
end
`ifdef FORMAL
always @(posedge clk)
    assert(cnt <= 3);
`endif
endmodule
EOF
cat > "$VERIFY_DIR/demo.sby" <<'EOF'
[options]
mode prove
depth 5

[engines]
smtbmc z3

[script]
read -formal -D FORMAL demo.v
prep -top demo

[files]
demo.v
EOF
export PATH="$STAGE/bin:$YOSYS_TMP/bin:$PATH"
export PYTHONPATH="$STAGE/share/sby"
if ! "$STAGE/bin/sby" --help > /tmp/sby-help.log 2>&1; then
    echo "ERROR: staged sby --help failed:" >&2
    head -20 /tmp/sby-help.log >&2
    exit 1
fi
echo "  sby --help OK"
cd "$VERIFY_DIR"
if "$STAGE/bin/sby" -f demo.sby > prove.log 2>&1; then
    if grep -q "DONE (PASS" prove.log; then
        echo "  sby prove PASS with Yosys 0.68 + z3 (pinned commit compatible)"
    else
        echo "ERROR: sby prove did not report PASS:" >&2
        tail -20 prove.log >&2
        exit 1
    fi
else
    echo "ERROR: sby prove failed:" >&2
    tail -20 prove.log >&2
    exit 1
fi
cd /
rm -rf "$VERIFY_DIR" "$YOSYS_TMP"

# --- manifests ---------------------------------------------------------------------
echo "Running strip-all-elf-binaries..."
"$REPO/build/strip-all-elf-binaries"

echo ""
echo "Staged:"
echo "  payload/$LOADOUT_PLATFORM/bin/sby.bz2 (wrapper)"
echo "  payload/$LOADOUT_PLATFORM/runtime/sby.tar.bz2 (share/sby/*.py)"
echo "  payload/$LOADOUT_PLATFORM/bin/z3.bz2 (solver ELF)"
echo ""
echo "Commit with:"
echo "  git add payload/$LOADOUT_PLATFORM/bin/sby.bz2 \\"
echo "          payload/$LOADOUT_PLATFORM/runtime/sby.tar.bz2 \\"
echo "          payload/$LOADOUT_PLATFORM/bin/z3.bz2 \\"
echo "          .strip-manifest .content-manifest payload/packages.json"
echo "  git commit -m 'feat(payload): sby <commit> + z3 ${Z3_VERSION}'"
