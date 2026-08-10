#!/bin/sh
# markdown-oxide -- PKM (personal knowledge management) language server, bundled
# from the upstream x86_64-unknown-linux-gnu release binary.
#   https://github.com/Feel-ix-343/markdown-oxide   (Apache-2.0)
#
# WHAT IT IS FOR. envs/nvim/lsp/markdown_oxide.lua has shipped in this repo for
# some time with `cmd = { 'markdown-oxide' }` and
# `root_markers = { '.git', '.obsidian', '.moxide.toml' }` -- but the binary was
# never in the payload, so that config resolved to nothing and was dead. This
# package makes it live: wikilinks, backlinks, daily notes and unresolved-link
# creation over a plain directory of markdown, on an EL8 farm node.
#
# WHY NOT OBSIDIAN ITSELF. Obsidian's terms grant a "non-sublicensable,
# non-transferable" license to install and execute it "on machines operated by
# or for you", and separately forbid the customer to "distribute or share the
# Services or Software or make any of them available for access by third
# parties". Bundling it into payload/ and publishing that as a GitHub release
# is exactly what those clauses prohibit, so Obsidian is NOT and cannot be
# bundled here regardless of technical fit (for the record, it would have fit:
# its main ELF floors at GLIBC_2.25 against EL8's 2.28 -- only its `obsidian-cli`
# helper, at GLIBC_2.34, would have been dead). Users install Obsidian
# themselves under their own acceptance of its terms and point it at their own
# vault; markdown-oxide then indexes that same vault from nvim/helix. The vault
# itself is org content and never belongs in this repo -- that is what the
# unbundled corp/site/team/project/user layers are for.
#
# NOT a source build. Upstream ships an x86_64 binary whose ELF floor is
# GLIBC_2.18, comfortably under EL8's 2.28, and whose NEEDED set is glibc plus
# libgcc_s -- all on this repo's never-bundle list, so nothing has to ship
# alongside it. The script ASSERTS both rather than assuming: a future release
# built against a newer toolchain would install cleanly on this box and be dead
# on a stock farm node, which is how tree-sitter and bottom got rejected.
#
# SMOKE. `markdown-oxide --version` exits 0 from a binary that cannot resolve a
# single wikilink, so the packaging check drives the real protocol
# (initialize -> didOpen -> textDocument/definition) against a two-note vault
# and requires [[note-b]] to resolve. See build/markdown-oxide/lsp-smoke.py.
#
# Usage (run from any directory):
#   /path/to/build-markdown-oxide.sh --tag v0.25.12
#
# Tag format carries the leading v -- that is upstream's convention.

set -eu

REPO="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO/build/lib.sh"

PKG="markdown-oxide"
RELEASES_URL="https://github.com/Feel-ix-343/markdown-oxide/releases"
ASSET_ARCH="x86_64-unknown-linux-gnu"

tag=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --tag)
            shift
            [ "$#" -gt 0 ] || { echo "missing value for --tag" >&2; exit 2; }
            tag=$1
            ;;
        -h | --help)
            sed -n '2,42p' "$0"
            exit 0
            ;;
        *)
            echo "unknown argument: $1" >&2
            exit 2
            ;;
    esac
    shift
done

loadout_require_tag "$tag" "$0" "$RELEASES_URL" "v0.25.12"
loadout_require_cmds curl bzip2 strip readelf python3

WORK=$(mktemp -d "${TMPDIR:-/tmp}/build-markdown-oxide-XXXXXX")
trap 'rm -rf "$WORK"' EXIT INT TERM

BIN="$WORK/$PKG"
URL="https://github.com/Feel-ix-343/markdown-oxide/releases/download/${tag}/markdown-oxide-${tag}-${ASSET_ARCH}"

echo "==> Downloading $PKG $tag ($ASSET_ARCH) ..."
curl -fL --retry 3 --retry-delay 2 -o "$BIN" "$URL"
chmod +x "$BIN"

echo "==> Verifying the binary reports $tag ..."
# Upstream tags carry a leading v; the binary prints a bare version.
expected=${tag#v}
reported=$("$BIN" --version 2>&1 | head -1 | awk '{print $NF}')
[ "$reported" = "$expected" ] || {
    echo "ERROR: asset for $tag reports version '$reported', expected '$expected'" >&2
    exit 1
}
echo "  reports $reported"

echo "==> Checking glibc floor ..."
loadout_report_max_glibc "$BIN"
MAX_GLIBC=$(readelf -V "$BIN" 2> /dev/null | grep -oE 'GLIBC_[0-9]+\.[0-9]+' | sort -V | tail -1)
case "${MAX_GLIBC:-GLIBC_2.0}" in
    GLIBC_2.2[0-8] | GLIBC_2.1[0-9] | GLIBC_2.[0-9]) ;;
    *)
        echo "ERROR: needs $MAX_GLIBC; EL8 has glibc 2.28." >&2
        echo "       The upstream prebuilt is no longer usable -- this tool would" >&2
        echo "       have to become an EL8 source build (Rust, see the crate store)." >&2
        exit 1
        ;;
esac

echo "==> Checking NEEDED closure ..."
# Everything here must be either glibc (never bundled, present on every EL8) or
# already in lib64/. A new NEEDED means this stopped being a drop-in binary and
# needs a bundling decision before it can ship.
NEEDED=$(readelf -d "$BIN" | sed -n 's/.*NEEDED.*\[\(.*\)\]/\1/p')
echo "  NEEDED: $(echo "$NEEDED" | tr '\n' ' ')"
for so in $NEEDED; do
    case "$so" in
        libc.so.6 | libm.so.6 | libdl.so.2 | libpthread.so.0 | librt.so.1) ;;
        libgcc_s.so.1) ;;
        *)
            echo "ERROR: unexpected NEEDED '$so' -- not glibc and not bundled." >&2
            echo "       Decide whether to bundle it before shipping this tag." >&2
            exit 1
            ;;
    esac
done

echo "==> LSP smoke (initialize -> didOpen -> definition on a real vault) ..."
python3 "$REPO/build/markdown-oxide/lsp-smoke.py" "$BIN"

echo "==> Packaging ..."
loadout_package_bin "$BIN" "$PKG"
loadout_stamp_version "$PKG" "$expected"

cat <<EOF

Done.

Next, as for every payload change:
  ./build/strip-all-elf-binaries
  python3.14 build/gen-content-manifest
  ./loadout completion bash > envs/bash/global/completions/loadout.bash
  python3.14 build/gen-readme-table
EOF
