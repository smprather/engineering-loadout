#!/bin/sh
# Icarus Verilog -- Verilog/SystemVerilog compiler and simulator (EL8 SOURCE build).
#   https://github.com/steveicarus/iverilog   (GPL-2.0)
#
# Unlike verilator (which lints and generates C++ models), iverilog is an event
# simulator you actually run: `iverilog -o sim.vvp design.v && ./sim.vvp`.
#
# EL8 FIT. Builds clean against stock EL8 and needs nothing new bundled:
#   max glibc symbol  GLIBC_2.14    (EL8 provides 2.28)
#   max libstdc++     GLIBCXX_3.4.21 (EL8 provides 3.4.25)
#   NEEDED            libbz2, libz, libreadline.so.7, libtinfo.so.6 -- all
#                     already in lib64/ -- plus glibc/libstdc++/libgcc_s, which
#                     are never bundled by policy.
# The script asserts the two floors rather than assuming them.
#
# RELOCATION -- the part that is easy to get wrong.
#
# The two ELFs (iverilog, vvp) resolve their own root from /proc/self/exe, so
# they relocate for free. THREE text files do not, and one of them causes a
# user-visible failure that a naive smoke misses entirely:
#
#   lib/ivl/vvp.conf      VVP_EXECUTABLE=<prefix>/bin/vvp
#   lib/ivl/vvp-s.conf    same
#   bin/iverilog-vpi      -I<prefix>/include/iverilog, -L<prefix>/lib, and the
#                         --install-dir output
#
# VVP_EXECUTABLE is written into the SHEBANG of every compiled .vvp file, and
# `./sim.vvp` is the normal Icarus workflow. With the build prefix baked in,
# every user gets `bad interpreter: No such file or directory`. Running
# `vvp sim.vvp` explicitly hides this completely -- so the smoke below runs the
# generated file BOTH ways on purpose.
#
# Handling, and why it is shaped this way:
#   * bin/iverilog-vpi is replaced with build/iverilog/iverilog-vpi, a
#     repo-owned wrapper that derives its prefix from $0 (the ngspice /
#     pdftotext idiom). That removes one of the two relocation roots.
#   * lib/ivl/vvp*.conf get the build prefix rewritten to the standard
#     /__LOADOUT_RELOC_ROOT__ token, which the installer substitutes for the
#     deployed local root (registry: relocate_token + relocate_root: lib/ivl).
#     Because that is now the ONLY subtree needing it, relocate_root can stay a
#     single path as the installer requires.
#   * The ELFs keep the REAL build prefix as a harmless unused fallback. They
#     must NOT contain the token: the installer hard-errors on a token found in
#     an ELF, by design. The script asserts that separation.
#
# Prerequisites on the build machine (EL8):
#   source /opt/rh/gcc-toolset-14/enable
#   dnf install -y gcc-c++ make autoconf gperf bison flex zlib-devel \
#                  bzip2-devel readline-devel ncurses-devel
#
# Usage (run from any directory):
#   ./build/build-iverilog.sh --tag v13_0
#
# Tag format is upstream's: v13_0, v12_0 (underscore, not a dot).

set -eu

REPO="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO/build/lib.sh"

PKG="iverilog"
RELEASES_URL="https://github.com/steveicarus/iverilog/releases"
PLATFORM_DIR="$REPO/payload/el8.x86_64.glibc2p28"
RUNTIME_DIR="$PLATFORM_DIR/runtime"
RELOC_TOKEN="/__LOADOUT_RELOC_ROOT__"

tag=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --tag)
            shift
            [ "$#" -gt 0 ] || { echo "missing value for --tag" >&2; exit 2; }
            tag=$1
            ;;
        -h | --help) sed -n '2,55p' "$0"; exit 0 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
    shift
done

loadout_require_tag "$tag" "$0" "$RELEASES_URL" "v13_0"
loadout_enable_gcc_toolset
loadout_require_cmds curl tar make gcc g++ autoconf gperf bison flex bzip2 strip readelf

# v13_0 -> 13.0 for the registry version field.
version=$(printf '%s' "${tag#v}" | tr '_' '.')

WORK=$(mktemp -d "${TMPDIR:-/tmp}/build-iverilog-XXXXXX")
# Version-scoped install prefix so successive builds cannot contaminate each
# other -- the trap build-octave.sh hit with a fixed /tmp/octave-install.
INST="/tmp/iverilog-inst-${tag}"
trap 'rm -rf "$WORK"' EXIT INT TERM
rm -rf "$INST"

echo "==> Downloading iverilog $tag ..."
curl -fL --retry 3 --retry-delay 2 -o "$WORK/iv.tar.gz" \
    "https://github.com/steveicarus/iverilog/archive/refs/tags/${tag}.tar.gz"
tar xzf "$WORK/iv.tar.gz" -C "$WORK"
SRC=$(find "$WORK" -maxdepth 1 -mindepth 1 -type d | head -1)

echo "==> Building (this takes a few minutes) ..."
(
    cd "$SRC"
    sh autoconf.sh
    ./configure --prefix="$INST"
    make -j"$(nproc 2>/dev/null || echo 2)"
    make install
) > "$WORK/build.log" 2>&1 || {
    echo "ERROR: build failed; tail of log:" >&2
    tail -30 "$WORK/build.log" >&2
    exit 1
}

reported=$("$INST/bin/iverilog" -V 2>&1 | head -1)
echo "  $reported"
case "$reported" in
    *"version ${version}"*) ;;
    *) echo "ERROR: built binary reports '$reported', expected version $version" >&2; exit 1 ;;
esac

echo "==> Checking glibc / libstdc++ floors ..."
for b in "$INST/bin/iverilog" "$INST/bin/vvp"; do
    g=$(readelf -V "$b" 2>/dev/null | grep -oE 'GLIBC_[0-9]+\.[0-9]+' | sort -V | tail -1)
    x=$(readelf -V "$b" 2>/dev/null | grep -oE 'GLIBCXX_[0-9]+\.[0-9]+\.[0-9]+' | sort -V | tail -1)
    printf '  %-10s %s %s\n' "$(basename "$b")" "${g:-none}" "${x:-no-libstdc++}"
    case "${g:-GLIBC_2.0}" in
        GLIBC_2.2[0-8] | GLIBC_2.1[0-9] | GLIBC_2.[0-9]) ;;
        *) echo "ERROR: $(basename "$b") needs $g; EL8 has glibc 2.28" >&2; exit 1 ;;
    esac
    case "${x:-GLIBCXX_3.4.0}" in
        GLIBCXX_3.4.1? | GLIBCXX_3.4.2[0-5] | GLIBCXX_3.4.[0-9]) ;;
        *) echo "ERROR: $(basename "$b") needs $x; EL8 libstdc++ provides 3.4.25" >&2; exit 1 ;;
    esac
done

echo "==> Checking NEEDED closure ..."
for b in "$INST/bin/iverilog" "$INST/bin/vvp"; do
    for so in $(readelf -d "$b" | sed -n 's/.*NEEDED.*\[\(.*\)\]/\1/p'); do
        case "$so" in
            libc.so.6 | libm.so.6 | libdl.so.2 | libpthread.so.0 | librt.so.1) ;;
            libstdc++.so.6 | libgcc_s.so.1) ;;
            libbz2.so.1 | libz.so.1 | libreadline.so.7 | libtinfo.so.6) ;;
            *)
                echo "ERROR: $(basename "$b") NEEDs '$so', which is neither system-provided" >&2
                echo "       nor already in payload lib64/. Decide before shipping." >&2
                exit 1
                ;;
        esac
    done
done
echo "  OK -- nothing new to bundle"

echo "==> Stripping ..."
find "$INST" -type f | while read -r f; do
    [ "$(head -c4 "$f" 2>/dev/null)" = "$(printf '\177ELF')" ] && strip "$f" 2>/dev/null || true
done

echo "==> Installing the relocatable iverilog-vpi wrapper ..."
install -m 755 "$REPO/build/iverilog/iverilog-vpi" "$INST/bin/iverilog-vpi"

echo "==> Tokenising lib/ivl/*.conf ..."
for conf in "$INST"/lib/ivl/vvp.conf "$INST"/lib/ivl/vvp-s.conf; do
    [ -f "$conf" ] || { echo "ERROR: expected $conf" >&2; exit 1; }
    sed -i "s|$INST|$RELOC_TOKEN|g" "$conf"
    grep -q "VVP_EXECUTABLE=$RELOC_TOKEN/bin/vvp" "$conf" || {
        echo "ERROR: VVP_EXECUTABLE not tokenised in $conf" >&2
        exit 1
    }
done

# The installer hard-errors on the token inside an ELF, so prove the token
# lives ONLY in the two conf files before packaging.
echo "==> Asserting token placement ..."
# LC_ALL=C on BOTH sides: the default locale collates punctuation loosely, so
# "vvp.conf" vs "vvp-s.conf" order flips between locales and the comparison
# fails on a perfectly good tree.
tokenised=$(grep -rl -- "$RELOC_TOKEN" "$INST" 2>/dev/null | sed "s|$INST/||" | LC_ALL=C sort)
expected=$(printf 'lib/ivl/vvp-s.conf\nlib/ivl/vvp.conf\n' | LC_ALL=C sort)
[ "$tokenised" = "$expected" ] || {
    echo "ERROR: relocation token is not confined to lib/ivl/*.conf." >&2
    echo "found:" >&2; printf '%s\n' "$tokenised" >&2
    exit 1
}
# Collect and test afterwards: `exit` inside a piped `while` runs in a subshell
# and would not stop this script, and a trailing `[ ] && {...}` makes the loop
# return non-zero on the common case, which `set -e` then treats as failure.
elf_hits=$(grep -rl -- "$RELOC_TOKEN" "$INST" | while read -r f; do
    if [ "$(head -c4 "$f" 2>/dev/null)" = "$(printf '\177ELF')" ]; then printf '%s\n' "$f"; fi
done)
[ -z "$elf_hits" ] || {
    echo "ERROR: relocation token found in ELF -- the installer rejects this:" >&2
    printf '%s\n' "$elf_hits" >&2
    exit 1
}
echo "  OK -- token only in lib/ivl/vvp.conf, lib/ivl/vvp-s.conf"

# ---------------------------------------------------------------------------
# Relocation + functional smoke.
#
# The first version of this check was WORTHLESS and it is worth saying why: it
# copied the tree elsewhere and ran the copy while the ORIGINAL PREFIX STILL
# EXISTED, so a binary that had silently fallen back to the build prefix passed.
# The original must be moved away first (the build-expect.sh trick). And the
# generated .vvp must be executed DIRECTLY, not via `vvp file.vvp`, or the
# shebang -- the thing most likely to be wrong -- is never exercised.
# ---------------------------------------------------------------------------
echo "==> Relocation + simulation smoke ..."
# Build a tree in the DEPLOYED shape: wrapper + .bin + vvp in bin/, and the
# relocation token already substituted, exactly as the installer leaves it.
STAGE="$WORK/relocated"
mkdir -p "$STAGE/bin"
cp -a "$INST/lib" "$INST/include" "$INST/share" "$STAGE/"
cp "$INST/bin/iverilog" "$STAGE/bin/iverilog.bin"
cp "$INST/bin/vvp" "$STAGE/bin/vvp"
install -m 755 "$REPO/build/iverilog/iverilog" "$STAGE/bin/iverilog"
install -m 755 "$REPO/build/iverilog/iverilog-vpi" "$STAGE/bin/iverilog-vpi"
sed -i "s|$RELOC_TOKEN|$STAGE|g" "$STAGE"/lib/ivl/vvp.conf "$STAGE"/lib/ivl/vvp-s.conf

run_smoke() {
    # $1 = label for the failure message
    _sd="$WORK/smoke-$1"
    rm -rf "$_sd"; mkdir -p "$_sd"
    cp "$REPO/build/iverilog/smoke.v" "$_sd/"
    (
        cd "$_sd"
        PATH="$STAGE/bin:/usr/bin:/bin"
        export PATH
        iverilog -o smoke.vvp smoke.v || exit 21
        # (a) explicit interpreter
        out=$(vvp smoke.vvp 2>&1) || exit 22
        case "$out" in *SMOKE_OK*) ;; *) printf '%s\n' "$out"; exit 23 ;; esac
        # (b) direct execution -- the ONLY thing that exercises the shebang,
        #     i.e. VVP_EXECUTABLE out of lib/ivl/vvp.conf
        chmod +x smoke.vvp
        out=$(./smoke.vvp 2>&1) || exit 24
        case "$out" in *SMOKE_OK*) ;; *) printf '%s\n' "$out"; exit 25 ;; esac
        [ -s smoke.vcd ] || exit 26
        [ "$(iverilog-vpi --install-dir)" = "$STAGE/lib/ivl" ] || exit 27
        # (c) the shebang must name the STAGED vvp, not the build tree and not
        #     an unsubstituted token
        head -1 smoke.vvp | grep -qxF "#! $STAGE/bin/vvp" || exit 28
    )
}

explain_smoke() {
    case "$1" in
        21) echo "ERROR [$2]: iverilog failed to compile smoke.v" >&2 ;;
        22 | 23) echo "ERROR [$2]: 'vvp smoke.vvp' did not print SMOKE_OK" >&2 ;;
        24 | 25)
            echo "ERROR [$2]: './smoke.vvp' failed -- the shebang (VVP_EXECUTABLE from" >&2
            echo "            lib/ivl/vvp.conf) is wrong. A 'vvp file.vvp' smoke cannot see this." >&2
            ;;
        26) echo "ERROR [$2]: no VCD -- the vvp runtime's VPI system tasks are broken" >&2 ;;
        27) echo "ERROR [$2]: iverilog-vpi --install-dir did not derive its own prefix" >&2 ;;
        28)
            echo "ERROR [$2]: the compiled .vvp shebang does not name $STAGE/bin/vvp." >&2
            echo "            iverilog resolved the WRONG lib/ivl -- most likely the" >&2
            echo "            compiled-in build prefix, which wins whenever it exists." >&2
            ;;
        *) echo "ERROR [$2]: smoke failed (rc=$1)" >&2 ;;
    esac
}

# PASS 1, the hostile one: build prefix still on disk. The iverilog ELF prefers
# its compiled-in <build-prefix>/lib/ivl whenever that path exists, so without
# the -B wrapper this pass picks up the build tree, writes a shebang pointing
# into /tmp, and ships a package that is broken on the developer's own box.
rc=0; run_smoke present || rc=$?
[ "$rc" -eq 0 ] || { explain_smoke "$rc" "build prefix PRESENT"; exit 1; }
echo "  OK (build prefix present)  -- wrapper's -B pinned the staged lib/ivl"

# PASS 2: build prefix gone, i.e. what a farm node looks like.
mv "$INST" "${INST}.hidden"
rc=0; run_smoke absent || rc=$?
mv "${INST}.hidden" "$INST"
[ "$rc" -eq 0 ] || { explain_smoke "$rc" "build prefix ABSENT"; exit 1; }
echo "  OK (build prefix absent)   -- compiled, ran via vvp AND ./smoke.vvp, VCD written"

echo "==> Packaging ..."
# iverilog ships as wrapper + real ELF (gvim/ngspice shape) so -B always names
# the installed lib/ivl; see build/iverilog/iverilog for why that matters.
# vvp stays a bare ELF: it is the interpreter in the generated .vvp shebang and
# Linux does not honour a shebang pointing at another script.
loadout_package_bin "$INST/bin/iverilog" "iverilog.bin"
loadout_package_bin "$INST/bin/vvp" "vvp"
bzip2 -c "$REPO/build/iverilog/iverilog" > "$LOADOUT_BIN_DIR/iverilog.bz2"
chmod 644 "$LOADOUT_BIN_DIR/iverilog.bz2"
echo "Packaged: $LOADOUT_BIN_DIR/iverilog.bz2 (wrapper)"
# iverilog-vpi is a script, not an ELF: bzip2 it directly rather than going
# through loadout_package_bin (which strips and patchelfs).
bzip2 -c "$INST/bin/iverilog-vpi" > "$LOADOUT_BIN_DIR/iverilog-vpi.bz2"
chmod 644 "$LOADOUT_BIN_DIR/iverilog-vpi.bz2"
echo "Packaged: $LOADOUT_BIN_DIR/iverilog-vpi.bz2"

mkdir -p "$RUNTIME_DIR"
tar cjf "$RUNTIME_DIR/iverilog.tar.bz2" -C "$INST" ./lib/ivl ./include ./share
echo "Packaged: $RUNTIME_DIR/iverilog.tar.bz2 ($(du -h "$RUNTIME_DIR/iverilog.tar.bz2" | cut -f1))"

loadout_stamp_version "$PKG" "$version"

cat <<EOF

Done.

Next, as for every payload change:
  ./build/strip-all-elf-binaries
  python3.14 build/gen-content-manifest
  ./loadout completion bash > envs/bash/global/completions/loadout.bash
  python3.14 build/gen-readme-table
EOF
