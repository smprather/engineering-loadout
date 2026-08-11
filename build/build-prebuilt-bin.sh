#!/bin/sh
# Import an upstream single-binary Linux prebuilt (no source build).
#
# WHY THIS SCRIPT EXISTS: `ty` and `mlr` were both bundled with NO build script
# and NO ADDING_BINARIES.md note, so nothing recorded where their payload came
# from or how to refresh it -- the same provenance gap lua-language-server,
# liberty-filter, tmux-path-store and the five small C tools each had. Whoever
# bumped them last did it by hand and left nothing behind.
#
# Multi-tool via --tool, following build/build-simple-c.sh's precedent, because
# the procedure is genuinely identical: fetch the upstream x86_64 tarball,
# verify it, assert it can run on EL8, smoke it, package it. Only the asset
# name, the binary path inside the archive and the smoke differ.
#
# These are NOT source builds. Upstream ships x86_64 binaries whose glibc floor
# is below EL8's 2.28. The script ASSERTS that rather than assuming it: a future
# release built against a newer toolchain would install cleanly on this box and
# be dead on a stock farm node, which is exactly how tree-sitter, bottom and
# fresh got rejected.
#
# Prerequisites: curl, tar, bzip2, strip, readelf, sha256sum, patchelf.
#
# Usage (run from any directory):
#   ./build/build-prebuilt-bin.sh --tool ty  --tag 0.0.70
#   ./build/build-prebuilt-bin.sh --tool mlr --tag v6.21.0
#
# Tag format is upstream's own and differs per tool: ty uses a BARE version,
# miller uses a leading v. The script derives the registry version from it.

set -eu

REPO="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO/build/lib.sh"

tool=""; tag=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --tool) shift; [ "$#" -gt 0 ] || { echo "missing value for --tool" >&2; exit 2; }; tool=$1 ;;
        --tag) shift; [ "$#" -gt 0 ] || { echo "missing value for --tag" >&2; exit 2; }; tag=$1 ;;
        -h | --help) sed -n '2,28p' "$0"; exit 0 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
    shift
done

# NOTE: the installed BINARY name and the packages.json REGISTRY KEY are not
# always the same -- miller ships a binary called `mlr`. loadout_stamp_version
# takes the registry key; loadout_package_bin takes the binary name.
case "$tool" in
    ty)
        RELEASES_URL="https://github.com/astral-sh/ty/releases"
        EXAMPLE_TAG="0.0.70"
        pkg="ty"
        ;;
    mlr)
        RELEASES_URL="https://github.com/johnkerl/miller/releases"
        EXAMPLE_TAG="v6.21.0"
        pkg="miller"
        ;;
    *)
        echo "ERROR: --tool must be one of: ty, mlr" >&2
        exit 2
        ;;
esac

loadout_require_tag "$tag" "$0 --tool $tool" "$RELEASES_URL" "$EXAMPLE_TAG"
loadout_require_cmds curl tar bzip2 strip readelf sha256sum

version=${tag#v}
WORK=$(mktemp -d "${TMPDIR:-/tmp}/build-prebuilt-${tool}-XXXXXX")
trap 'rm -rf "$WORK"' EXIT INT TERM

case "$tool" in
    ty)
        asset="ty-x86_64-unknown-linux-gnu.tar.gz"
        url="https://github.com/astral-sh/ty/releases/download/${tag}/${asset}"
        # Upstream publishes a sibling .sha256 -- use it. This is the only tool
        # here that does; miller publishes none.
        sums_url="${url}.sha256"
        binpath="ty-x86_64-unknown-linux-gnu/ty"
        ;;
    mlr)
        asset="miller-${version}-linux-amd64.tar.gz"
        url="https://github.com/johnkerl/miller/releases/download/${tag}/${asset}"
        sums_url=""
        binpath="miller-${version}-linux-amd64/mlr"
        ;;
esac

echo "==> Downloading $tool $tag ..."
curl -fL --retry 3 --retry-delay 2 -o "$WORK/$asset" "$url"

if [ -n "$sums_url" ]; then
    echo "==> Verifying upstream sha256 ..."
    curl -fL --retry 3 --retry-delay 2 -o "$WORK/$asset.sha256" "$sums_url"
    want=$(awk '{print $1; exit}' "$WORK/$asset.sha256")
    got=$(sha256sum "$WORK/$asset" | awk '{print $1}')
    [ "$want" = "$got" ] || {
        echo "ERROR: sha256 mismatch for $asset" >&2
        echo "  upstream: $want" >&2
        echo "  computed: $got" >&2
        exit 1
    }
    echo "  OK -- $got"
else
    echo "==> No upstream sha256 published for $tool; recording ours:"
    sha256sum "$WORK/$asset" | awk '{print "  "$1}'
fi

tar xzf "$WORK/$asset" -C "$WORK"
BIN="$WORK/$binpath"
[ -f "$BIN" ] || {
    echo "ERROR: expected $binpath inside $asset; archive contains:" >&2
    tar tzf "$WORK/$asset" | head -10 >&2
    exit 1
}
chmod +x "$BIN"

echo "==> Verifying the binary reports $version ..."
reported=$("$BIN" --version 2>&1 | head -1)
echo "  $reported"
case "$reported" in
    *"$version"*) ;;
    *) echo "ERROR: reports '$reported', expected version $version" >&2; exit 1 ;;
esac

echo "==> Checking glibc floor ..."
loadout_report_max_glibc "$BIN"
MAX_GLIBC=$(readelf -V "$BIN" 2> /dev/null | grep -oE 'GLIBC_[0-9]+\.[0-9]+' | sort -V | tail -1)
case "${MAX_GLIBC:-GLIBC_2.0}" in
    GLIBC_2.2[0-8] | GLIBC_2.1[0-9] | GLIBC_2.[0-9]) ;;
    *)
        echo "ERROR: needs $MAX_GLIBC; EL8 has glibc 2.28." >&2
        echo "       The upstream prebuilt is no longer usable -- this tool would" >&2
        echo "       have to become an EL8 source build." >&2
        exit 1
        ;;
esac

echo "==> Checking NEEDED closure ..."
NEEDED=$(readelf -d "$BIN" 2>/dev/null | sed -n 's/.*NEEDED.*\[\(.*\)\]/\1/p')
if [ -z "$NEEDED" ]; then
    echo "  static / no dynamic deps"
else
    echo "  NEEDED: $(echo "$NEEDED" | tr '\n' ' ')"
    for so in $NEEDED; do
        case "$so" in
            libc.so.6 | libm.so.6 | libdl.so.2 | libpthread.so.0 | librt.so.1) ;;
            libgcc_s.so.1 | libstdc++.so.6) ;;
            *)
                echo "ERROR: unexpected NEEDED '$so' -- not glibc and not bundled." >&2
                exit 1
                ;;
        esac
    done
fi

# ---------------------------------------------------------------------------
# Functional smoke. `--version` proves the ELF loads, nothing more -- the same
# false green that let three gtkwave tools ship. Make each tool actually do its
# job on real input.
# ---------------------------------------------------------------------------
echo "==> Functional smoke ..."
SM="$WORK/smoke"; mkdir -p "$SM"
case "$tool" in
    ty)
        # A file with a genuine type error must be REPORTED. A checker that
        # silently passes everything would sail through a --version probe.
        printf 'def f(x: int) -> str:\n    return x\n' > "$SM/bad.py"
        out=$("$BIN" check "$SM/bad.py" 2>&1 || true)
        case "$out" in
            *error*|*invalid-return-type*|*"1 diagnostic"*) echo "  OK -- reported the type error" ;;
            *) echo "ERROR: ty did not report an obvious type error:" >&2
               printf '%s\n' "$out" >&2; exit 1 ;;
        esac
        ;;
    mlr)
        printf 'a,b\n1,2\n3,4\n' > "$SM/in.csv"
        out=$("$BIN" --icsv --ojson cat "$SM/in.csv" 2>&1)
        case "$out" in
            *'"a": 1'*|*'"a": "1"'*) echo "  OK -- CSV -> JSON round-trip" ;;
            *) echo "ERROR: mlr did not convert CSV to JSON:" >&2
               printf '%s\n' "$out" >&2; exit 1 ;;
        esac
        ;;
esac

echo "==> Packaging ..."
# loadout_package_bin always runs patchelf --set-rpath, which ABORTS on a
# statically linked binary ("cannot find section '.dynamic'"). mlr is a static
# Go binary, so it needs strip -> bzip2 with no patchelf at all -- and it needs
# no RPATH either, since it loads nothing.
if [ -z "$NEEDED" ]; then
    work_bin="$WORK/pkg-$tool"
    cp "$BIN" "$work_bin"
    strip "$work_bin" 2>/dev/null || true
    bzip2 -kf "$work_bin"
    mkdir -p "$LOADOUT_BIN_DIR"
    cp "${work_bin}.bz2" "$LOADOUT_BIN_DIR/${tool}.bz2"
    chmod 644 "$LOADOUT_BIN_DIR/${tool}.bz2"
    echo "Packaged: $LOADOUT_BIN_DIR/${tool}.bz2 (static; no patchelf)"
else
    loadout_package_bin "$BIN" "$tool"
fi
loadout_stamp_version "$pkg" "$version"

cat <<EOF

Done.

Next, as for every payload change:
  ./build/strip-all-elf-binaries
  python3.14 build/gen-content-manifest
  python3.14 build/gen-readme-table
EOF
