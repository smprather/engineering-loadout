#!/bin/sh
# taplo -- the TOML toolkit: linter, formatter and language server in one binary.
#   https://github.com/tamasfe/taplo   (MIT)
#
# WHAT IT IS FOR. `taplo lint`, `taplo format` and `taplo lsp stdio` cover all
# three of the things an engineer wants for TOML, and it is the de-facto
# standard implementation (it is what VS Code's "Even Better TOML" runs).
# envs/nvim/lsp/taplo.lua and envs/helix/languages.toml both drive it.
#
# NOT a source build. Upstream ships an x86_64 Linux binary that is
# STATIC-PIE (musl) -- no NEEDED entries at all, no glibc floor to clear, the
# same shape as the bundled biome. The script ASSERTS that rather than assuming
# it: a future release built against glibc would install cleanly on this box and
# be dead on a stock farm node, which is how tree-sitter and bottom got rejected.
#
# WRAPPER SPLIT (bin/taplo + bin/taplo.bin). The installed `taplo` is a POSIX-sh
# wrapper from build/taplo/taplo. Its whole job is to point `taplo lint` at the
# offline schema catalog shipped by the `taplo-schemas` package, because taplo's
# built-in catalogs are remote URLs that are dead on an air-gapped node -- and a
# dead catalog does not fail, it silently downgrades to grammar-only checking.
# Refresh the catalog with `./build/update taplo-schemas`.
#
# SMOKE. `taplo --version` exits 0 from a binary that cannot lint anything, so
# the packaging check drives all three real jobs:
#   1. format normalises `a=1` to `a = 1`
#   2. lint rejects a grammatically broken document
#   3. lint rejects an UNKNOWN CARGO KEY through the offline catalog, from a
#      staged install tree with the relocation token already rewritten -- i.e.
#      the wrapper, the catalog and the relocation contract end to end
#   4. the LSP serves formatting + diagnostics (build/taplo/lsp-smoke.py)
# Steps 3 and 4 run inside a network namespace when `unshare` allows it, so an
# accidental dependence on schemastore.org cannot pass on the build box.
#
# Usage (run from any directory):
#   /path/to/build-taplo.sh --tag 0.10.0
#
# Tag format is a BARE version -- that is upstream's convention for the CLI
# releases (0.9.3, 0.10.0), with no leading v.

set -eu

REPO="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO/build/lib.sh"

PKG="taplo"
RELEASES_URL="https://github.com/tamasfe/taplo/releases"
ASSET="taplo-linux-x86_64.gz"

tag=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --tag)
            shift
            [ "$#" -gt 0 ] || { echo "missing value for --tag" >&2; exit 2; }
            tag=$1
            ;;
        -h | --help)
            sed -n '2,40p' "$0"
            exit 0
            ;;
        *)
            echo "unknown argument: $1" >&2
            exit 2
            ;;
    esac
    shift
done

loadout_require_tag "$tag" "$0" "$RELEASES_URL" "0.10.0"
loadout_require_cmds curl gzip bzip2 strip readelf sha256sum tar python3

WORK=$(mktemp -d "${TMPDIR:-/tmp}/build-taplo-XXXXXX")
trap 'rm -rf "$WORK"' EXIT INT TERM

BIN="$WORK/taplo"
URL="https://github.com/tamasfe/taplo/releases/download/${tag}/${ASSET}"

echo "==> Downloading $PKG $tag ..."
curl -fL --retry 3 --retry-delay 2 -o "$WORK/$ASSET" "$URL"
echo "==> No upstream sha256 published for taplo; recording ours:"
sha256sum "$WORK/$ASSET" | awk '{print "  "$1}'
gzip -dc "$WORK/$ASSET" > "$BIN"
chmod +x "$BIN"

echo "==> Verifying the binary reports $tag ..."
reported=$("$BIN" --version 2>&1 | head -1)
echo "  $reported"
case "$reported" in
    *"$tag"*) ;;
    *) echo "ERROR: reports '$reported', expected version $tag" >&2; exit 1 ;;
esac

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
NEEDED=$(readelf -d "$BIN" 2> /dev/null | sed -n 's/.*NEEDED.*\[\(.*\)\]/\1/p')
if [ -n "$NEEDED" ]; then
    # Upstream has shipped a static-pie musl build since 0.9.x. A dynamic build
    # is not automatically wrong, but it is a different packaging decision
    # (RPATH, bundled sonames) and must not happen by accident.
    echo "ERROR: taplo is no longer statically linked; NEEDED: $(echo "$NEEDED" | tr '\n' ' ')" >&2
    echo "       Re-evaluate packaging (RPATH + bundled libs) before shipping this tag." >&2
    exit 1
fi
echo "  static / no dynamic deps"

# ---------------------------------------------------------------------------
# Functional smoke.
# ---------------------------------------------------------------------------
SM="$WORK/smoke"
mkdir -p "$SM"

echo "==> Smoke 1/4: format ..."
printf '[package]\nname="demo"\nversion   =    "1.0"\n' > "$SM/ugly.toml"
"$BIN" format "$SM/ugly.toml" > /dev/null 2>&1
grep -q '^name = "demo"$' "$SM/ugly.toml" || {
    echo "ERROR: format did not normalise 'name=\"demo\"'; file is now:" >&2
    cat "$SM/ugly.toml" >&2
    exit 1
}
echo "  OK -- normalised key spacing"

echo "==> Smoke 2/4: lint rejects broken grammar ..."
printf '[package\nname = "demo\n' > "$SM/broken.toml"
if "$BIN" lint --no-auto-config --no-schema "$SM/broken.toml" > "$SM/lint.out" 2>&1; then
    echo "ERROR: lint exited 0 on a syntactically broken document" >&2
    cat "$SM/lint.out" >&2
    exit 1
fi
echo "  OK -- rejected"

# ---------------------------------------------------------------------------
# Smoke 3: the offline schema path, end to end.
#
# Stage a real install tree -- wrapper at bin/taplo, ELF at bin/taplo.bin,
# the taplo-schemas archive extracted and its relocation token rewritten
# exactly as the installer does -- then lint a Cargo.toml with a bogus key.
# Grammar-only checking accepts that file; only schema validation catches it.
# This is the check that would have caught a catalog shipped with relative
# URLs, which taplo rejects outright.
# ---------------------------------------------------------------------------
SCHEMA_ARCHIVE=""
for d in "$REPO"/payload/*/runtime/taplo-schemas.tar.bz2; do
    [ -f "$d" ] && SCHEMA_ARCHIVE=$d
done

if [ -z "$SCHEMA_ARCHIVE" ]; then
    echo "==> Smoke 3/4: SKIPPED -- no taplo-schemas archive in payload/" >&2
    echo "    Build it with ./build/update taplo-schemas, then re-run this script" >&2
    echo "    to exercise the offline schema path." >&2
else
    echo "==> Smoke 3/4: offline schema validation through the wrapper ..."
    PREFIX="$WORK/prefix"
    mkdir -p "$PREFIX/bin"
    cp "$BIN" "$PREFIX/bin/taplo.bin"
    cp "$REPO/build/taplo/taplo" "$PREFIX/bin/taplo"
    chmod +x "$PREFIX/bin/taplo" "$PREFIX/bin/taplo.bin"
    tar xjf "$SCHEMA_ARCHIVE" -C "$PREFIX"
    CATALOG="$PREFIX/share/taplo/schemas/catalog.json"
    [ -f "$CATALOG" ] || { echo "ERROR: $SCHEMA_ARCHIVE did not yield $CATALOG" >&2; exit 1; }
    python3 - "$CATALOG" "$PREFIX" <<'PYEOF'
import sys

path, prefix = sys.argv[1:3]
token = "/__LOADOUT_RELOC_ROOT__"
with open(path) as fh:
    text = fh.read()
if token not in text:
    sys.exit(f"ERROR: relocation token absent from {path}")
with open(path, "w") as fh:
    fh.write(text.replace(token, prefix))
PYEOF

    mkdir -p "$SM/crate"
    printf '[package]\nname = "demo"\nversion = "0.1.0"\nnot_a_real_cargo_key = 3\n' > "$SM/crate/Cargo.toml"

    # Grammar-only must ACCEPT it -- that is the silent degrade being guarded.
    (cd "$SM/crate" && "$PREFIX/bin/taplo" lint --no-auto-config --no-schema Cargo.toml) > /dev/null 2>&1 || {
        echo "ERROR: the bogus-key Cargo.toml is not grammatically valid; fix the fixture" >&2
        exit 1
    }

    NETNS=""
    if unshare -Umrn true > /dev/null 2>&1; then
        NETNS="unshare -Umrn"
        echo "  (running with the network namespaced away)"
    else
        echo "  (unshare unavailable; running with host networking -- offline path unproven)" >&2
    fi

    if (cd "$SM/crate" && $NETNS "$PREFIX/bin/taplo" lint --no-auto-config Cargo.toml) > "$SM/schema.out" 2>&1; then
        echo "ERROR: schema lint exited 0 on an unknown Cargo.toml key -- the offline" >&2
        echo "       catalog is not reaching taplo. Output:" >&2
        cat "$SM/schema.out" >&2
        exit 1
    fi
    grep -q "not_a_real_cargo_key" "$SM/schema.out" || {
        echo "ERROR: lint failed but never mentioned the bogus key; it is failing for" >&2
        echo "       some other reason. Output:" >&2
        cat "$SM/schema.out" >&2
        exit 1
    }
    echo "  OK -- offline catalog caught an unknown Cargo.toml key"
fi

# Smoke 4: the LSP. `taplo lsp stdio` accepts NO catalog flag, so the editors
# pass catalogs as LSP client settings instead -- a different code path from
# smoke 3's CLI flag, and the one nvim and helix actually use. When the staged
# catalog exists, drive that path too and require the schema diagnostic.
echo "==> Smoke 4/4: LSP (initialize -> formatting -> diagnostics) ..."
set -- "$REPO/build/taplo/lsp-smoke.py" "$BIN"
if [ -n "$SCHEMA_ARCHIVE" ]; then
    set -- "$@" "$CATALOG"
fi
if unshare -Umrn true > /dev/null 2>&1; then
    unshare -Umrn python3 "$@"
else
    python3 "$@"
fi

# ---------------------------------------------------------------------------
# Packaging. Static binary: strip + bzip2, no patchelf (it aborts on a binary
# with no .dynamic section) and no RPATH to set, since it loads nothing.
# ---------------------------------------------------------------------------
echo "==> Packaging ..."
cp "$BIN" "$WORK/pkg-taplo"
strip "$WORK/pkg-taplo" 2> /dev/null || true
bzip2 -kf "$WORK/pkg-taplo"
mkdir -p "$LOADOUT_BIN_DIR"
cp "$WORK/pkg-taplo.bz2" "$LOADOUT_BIN_DIR/taplo.bin.bz2"
chmod 644 "$LOADOUT_BIN_DIR/taplo.bin.bz2"
echo "Packaged: $LOADOUT_BIN_DIR/taplo.bin.bz2 (static; no patchelf)"

bzip2 -c "$REPO/build/taplo/taplo" > "$LOADOUT_BIN_DIR/taplo.bz2"
chmod 644 "$LOADOUT_BIN_DIR/taplo.bz2"
echo "Packaged: $LOADOUT_BIN_DIR/taplo.bz2 (POSIX-sh wrapper)"

echo "==> Regenerating shell completions ..."
"$BIN" completions bash > "$REPO/envs/bash/global/completions/taplo.bash"
mkdir -p "$REPO/envs/zsh/site-functions"
"$BIN" completions zsh > "$REPO/envs/zsh/site-functions/_taplo"
echo "  envs/bash/global/completions/taplo.bash"
echo "  envs/zsh/site-functions/_taplo"

loadout_stamp_version "$PKG" "$tag"

cat <<EOF

Done.

Next, as for every payload change:
  ./build/strip-all-elf-binaries
  python3.14 build/gen-content-manifest
  python3.14 build/gen-readme-table
EOF
