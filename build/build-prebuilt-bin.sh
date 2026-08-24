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
# Prerequisites: curl, tar, bzip2, strip, readelf, sha256sum, patchelf, timeout.
#
# Usage (run from any directory):
#   ./build/build-prebuilt-bin.sh --tool ty  --tag 0.0.70
#   ./build/build-prebuilt-bin.sh --tool mlr --tag v6.21.0
#   ./build/build-prebuilt-bin.sh --tool spice-netlist-ls --tag v0.3.0
#
# Tag format is upstream's own and differs per tool: ty uses a BARE version,
# miller and spice-netlist-ls use a leading v. The script derives the registry
# version from it. spice-netlist-ls is the first MULTI-binary prebuilt here:
# its tarball carries two static binaries (spicefmt CLI + spice-netlist-ls LSP).

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
    spice-netlist-ls)
        RELEASES_URL="https://github.com/smprather/spice-netlist-ls/releases"
        EXAMPLE_TAG="v0.3.0"
        pkg="spice-netlist-ls"
        ;;
    *)
        echo "ERROR: --tool must be one of: ty, mlr, spice-netlist-ls" >&2
        exit 2
        ;;
esac

loadout_require_tag "$tag" "$0 --tool $tool" "$RELEASES_URL" "$EXAMPLE_TAG"
loadout_require_cmds curl tar bzip2 strip readelf sha256sum timeout

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
    spice-netlist-ls)
        # .tar.xz (not .gz); two binaries inside one archive.
        asset="spice-netlist-ls-x86_64-unknown-linux-musl.tar.xz"
        url="https://github.com/smprather/spice-netlist-ls/releases/download/${tag}/${asset}"
        sums_url="${url}.sha256"
        binpath="spice-netlist-ls-x86_64-unknown-linux-musl/spicefmt"
        # Second binary lives next to the first; handled below.
        binpath2="spice-netlist-ls-x86_64-unknown-linux-musl/spice-netlist-ls"
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

tar xzf "$WORK/$asset" -C "$WORK" 2>/dev/null || tar xJf "$WORK/$asset" -C "$WORK"
BIN="$WORK/$binpath"
[ -f "$BIN" ] || {
    echo "ERROR: expected $binpath inside $asset; archive contains:" >&2
    tar tf "$WORK/$asset" 2>/dev/null | head -10 >&2 || tar tJf "$WORK/$asset" | head -10 >&2
    exit 1
}
chmod +x "$BIN"
# Optional second binary (spice-netlist-ls ships two in one archive).
BIN2=""
if [ -n "${binpath2:-}" ]; then
    BIN2="$WORK/$binpath2"
    [ -f "$BIN2" ] || { echo "ERROR: expected $binpath2 inside $asset" >&2; exit 1; }
    chmod +x "$BIN2"
fi

echo "==> Verifying the binary reports $version ..."
case "$tool" in
    spice-netlist-ls)
        # spicefmt reports the version; the LSP binary has no --version.
        out=$("$BIN" --version 2>&1 | head -1)
        case "$out" in
            *"$version"*) echo "  OK -- $out" ;;
            *) echo "ERROR: spicefmt reports '$out', expected $version" >&2; exit 1 ;;
        esac
        ;;
    *)
        reported=$("$BIN" --version 2>&1 | head -1)
        echo "  $reported"
        case "$reported" in
            *"$version"*) ;;
            *) echo "ERROR: reports '$reported', expected version $version" >&2; exit 1 ;;
        esac
        ;;
esac

_check_glibc_floor() {
    check_bin=$1
    check_label=$2
    loadout_report_max_glibc "$check_bin"
    max_glibc=$(readelf -V "$check_bin" 2> /dev/null | grep -oE 'GLIBC_[0-9]+\.[0-9]+' | sort -V | tail -1)
    case "${max_glibc:-GLIBC_2.0}" in
        GLIBC_2.2[0-8] | GLIBC_2.1[0-9] | GLIBC_2.[0-9]) ;;
        *)
            echo "ERROR: $check_label needs $max_glibc; EL8 has glibc 2.28." >&2
            echo "       The upstream prebuilt is no longer usable -- this tool would" >&2
            echo "       have to become an EL8 source build." >&2
            exit 1
            ;;
    esac
}

echo "==> Checking glibc floor ..."
_check_glibc_floor "$BIN" "$(basename "$BIN")"
[ -z "$BIN2" ] || _check_glibc_floor "$BIN2" "$(basename "$BIN2")"

echo "==> Checking NEEDED closure ..."
_check_needed_closure() {
    check_bin=$1
    check_label=$2
    needed_out=$(readelf -d "$check_bin" 2>/dev/null | sed -n 's/.*NEEDED.*\[\(.*\)\]/\1/p')
    if [ -z "$needed_out" ]; then
        echo "  $check_label: static / no dynamic deps"
    else
        echo "  $check_label NEEDED: $(echo "$needed_out" | tr '\n' ' ')"
        for so in $needed_out; do
            case "$so" in
                libc.so.6 | libm.so.6 | libdl.so.2 | libpthread.so.0 | librt.so.1) ;;
                libgcc_s.so.1 | libstdc++.so.6) ;;
                *)
                    echo "ERROR: $check_label has unexpected NEEDED '$so' -- not glibc and not bundled." >&2
                    exit 1
                    ;;
            esac
        done
    fi
}

_check_needed_closure "$BIN" "$(basename "$BIN")"
NEEDED=$needed_out
NEEDED2=""
if [ -n "$BIN2" ]; then
    _check_needed_closure "$BIN2" "$(basename "$BIN2")"
    NEEDED2=$needed_out
fi
if [ -z "$NEEDED" ] && [ -n "$NEEDED2" ]; then
    echo "ERROR: first binary is static but second binary is dynamic; package paths would diverge." >&2
    exit 1
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
    spice-netlist-ls)
        # (1) format a real netlist, (2) lint catches undefined subckt,
        # (3) idempotency: format(format(x)) == format(x). A formatter that
        # silently passes through would sail a --version probe; the lint
        # check catches a linter that no-ops.
        printf '* title\nR1 1 0   1k\nC1 1 0  1p\n.tran 1n 10n\n' > "$SM/deck.sp"
        out=$("$BIN" "$SM/deck.sp" 2>&1)
        case "$out" in
            *'R1 1 0 1k'*) echo "  OK -- formatted netlist" ;;
            *) echo "ERROR: spicefmt did not normalize spacing:" >&2
               printf '%s\n' "$out" >&2; exit 1 ;;
        esac
        printf 'X1 a b sub\ntitle line\n' | "$BIN" --lint > "$SM/lint.out" 2>&1 || true
        case "$(cat "$SM/lint.out")" in
            *undefined-subckt*) echo "  OK -- lint reported undefined-subckt" ;;
            *) echo "ERROR: spicefmt --lint missed an undefined subckt" >&2
               cat "$SM/lint.out" >&2; exit 1 ;;
        esac
        "$BIN" "$SM/deck.sp" > "$SM/o1.sp" 2>/dev/null
        "$BIN" "$SM/o1.sp" > "$SM/o2.sp" 2>/dev/null
        cmp -s "$SM/o1.sp" "$SM/o2.sp" \
            && echo "  OK -- idempotent (format | format = fixed point)" \
            || { echo "ERROR: spicefmt is not idempotent" >&2; exit 1; }
        lsp_out=$(
            {
                printf 'Content-Length: 107\r\n\r\n{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":null,"rootUri":null,"capabilities":{}}}'
                printf 'Content-Length: 52\r\n\r\n{"jsonrpc":"2.0","method":"initialized","params":{}}'
                printf 'Content-Length: 58\r\n\r\n{"jsonrpc":"2.0","id":2,"method":"shutdown","params":null}'
                printf 'Content-Length: 47\r\n\r\n{"jsonrpc":"2.0","method":"exit","params":null}'
            } | timeout 10 "$BIN2" 2>&1 || true
        )
        case "$lsp_out" in
            *\"id\":1*definitionProvider*documentFormattingProvider*\"id\":2*\"result\":null*)
                echo "  OK -- LSP initialize/shutdown over stdio"
                ;;
            *)
                echo "ERROR: spice-netlist-ls did not answer a minimal LSP session:" >&2
                printf '%s\n' "$lsp_out" >&2
                exit 1
                ;;
        esac
        ;;
esac

echo "==> Packaging ..."
# loadout_package_bin always runs patchelf --set-rpath, which ABORTS on a
# statically linked binary ("cannot find section '.dynamic'"). mlr is a static
# Go binary, so it needs strip -> bzip2 with no patchelf at all -- and it needs
# no RPATH either, since it loads nothing.
#
# spice-netlist-ls is static-pie musl AND ships TWO binaries in one archive
# (spicefmt CLI + spice-netlist-ls LSP). The static branch below packages every
# binary under its own name so a multi-binary tool does not clobber itself.
if [ -z "$NEEDED" ]; then
    _pkg_static_bin() {
        src_bin=$1
        out_stem=$2
        work_bin="$WORK/.pkg-${out_stem}"
        rm -f "$work_bin" "${work_bin}.bz2"
        cp "$src_bin" "$work_bin"
        strip "$work_bin" 2>/dev/null || true
        bzip2 -kf "$work_bin"
        mkdir -p "$LOADOUT_BIN_DIR"
        cp "${work_bin}.bz2" "$LOADOUT_BIN_DIR/${out_stem}.bz2"
        chmod 644 "$LOADOUT_BIN_DIR/${out_stem}.bz2"
        rm -f "$work_bin" "${work_bin}.bz2"
        echo "Packaged: $LOADOUT_BIN_DIR/${out_stem}.bz2 (static; no patchelf)"
    }
    _pkg_static_bin "$BIN" "$(basename "$BIN")"
    [ -z "$BIN2" ] || _pkg_static_bin "$BIN2" "$(basename "$BIN2")"
else
    loadout_package_bin "$BIN" "$tool"
    [ -z "$BIN2" ] || loadout_package_bin "$BIN2" "$(basename "$BIN2")"
fi
loadout_stamp_version "$pkg" "$version"

cat <<EOF

Done.

Next, as for every payload change:
  ./build/strip-all-elf-binaries
  python3.14 build/gen-installed-sizes
  python3.14 build/gen-content-manifest
  python3.14 build/gen-readme-table
EOF
