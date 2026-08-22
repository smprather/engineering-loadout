#!/bin/sh
# helix (hx) -- modal editor with tree-sitter and built-in LSP, built from
# source on the EL8 build machine.
#   https://github.com/helix-editor/helix   (MPL-2.0)
#
# ── WHY THIS IS A --rev BUILD AND NOT A --tag BUILD ───────────────────────────
# This repo's policy is stable tagged releases only (see AGENTS.md, "Stable-
# release policy for bundled binaries"). helix is a deliberate, documented
# exception, and every other build script should keep requiring --tag.
#
# Upstream's newest RELEASE is 25.07.1, published 2025-07-18. Helix releases
# infrequently and that tag has been the newest for over a year. The config
# surface this repo depends on does not exist in it:
#
#   [editor.workspace-trust]     master only -- the ONLY way to stop helix
#                                gating every language server behind a modal
#   rainbow-brackets             master only -- already set in envs/helix/config.toml
#   [editor.word-completion]     master only
#   auto-document-highlight,     master only
#   display-progress-messages
#
# The binary this replaced was ALSO a master build (25.07.1 (87d5c05c),
# 2026-05-03) -- it entered the payload through a bulk snapshot commit with no
# build script, no ADDING_BINARIES.md note and no recorded provenance, and
# packages.json described it as "25.07.1" as though it were the release. This
# script exists to make that state explicit and reproducible rather than to
# introduce it. If upstream ever cuts a release carrying the keys above, switch
# this script back to --tag and delete this block.
#
# Note that `hx --version` reports "25.07.1 (<sha>)" for a master build -- the
# last release tag plus the commit. The tag half of that string is NOT evidence
# you are on a release; the sha is the only part that identifies the build. That
# is exactly how the previous binary came to be mislabelled.
#
# ── WHAT GETS PACKAGED ───────────────────────────────────────────────────────
#   bin/hx.bz2            POSIX-sh wrapper (build/helix/hx) that exports
#                         HELIX_RUNTIME derived from its own installed path
#   bin/hx.bin.bz2        the real ELF, RPATH $ORIGIN/../lib64:$ORIGIN/../lib
#   runtime/helix.tar.bz2 ./runtime/{grammars/*.so,queries,themes,tutor}
#
# `runtime/grammars/sources/` is EXCLUDED and must stay excluded: it is the
# fetched git checkout of every grammar, 2.2 GB against ~200 MB of built .so.
#
# ── SMOKES ───────────────────────────────────────────────────────────────────
# `hx --version` proves nothing about the shipped config. The load-bearing check
# here is `hx --health` run against THIS REPO's envs/helix/{config,languages}.toml,
# because an unknown [editor] field makes helix discard the ENTIRE config file
# and silently fall back to stock defaults -- the exact silent-degrade this repo
# keeps designing against. That is how `[editor] insecure` -> workspace-trust
# would have shipped a config-less editor. The check greps for helix's own
# "Configuration file malformed" text; --health exits 0 either way, so an exit
# code alone does not catch it. tests/env-helix-config runs the same assertion
# against the payload binary on every Tier 1 run.
#
# Usage (run from any directory):
#   /path/to/build-helix.sh --rev master
#   /path/to/build-helix.sh --rev 079a789e          # pin an exact commit
#   /path/to/build-helix.sh --source /path/to/helix # reuse an existing checkout

set -eu

REPO="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
. "$REPO/build/lib.sh"

PKG="hx"
CLONE_URL="https://github.com/helix-editor/helix"

rev=""
source_dir=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --rev)
            shift
            [ "$#" -gt 0 ] || { echo "missing value for --rev" >&2; exit 2; }
            rev=$1
            ;;
        --source)
            shift
            [ "$#" -gt 0 ] || { echo "missing value for --source" >&2; exit 2; }
            source_dir=$1
            ;;
        --tag)
            shift
            echo "ERROR: helix is a --rev build, not a --tag build." >&2
            echo "       See the header of this script for why. Use --rev." >&2
            exit 2
            ;;
        -h | --help)
            sed -n '2,60p' "$0"
            exit 0
            ;;
        *)
            echo "unknown argument: $1" >&2
            exit 2
            ;;
    esac
    shift
done

if [ -z "$source_dir" ] && [ -z "$rev" ]; then
    {
        echo "ERROR: --rev is required (or --source for an existing checkout)."
        echo "  $0 --rev master"
        echo ""
        echo "helix is a documented exception to the stable-release policy;"
        echo "see the header of this script."
    } >&2
    exit 2
fi

loadout_require_cmds git cargo readelf strip bzip2 tar python3 cc

WORK=$(mktemp -d "${TMPDIR:-/tmp}/build-helix-XXXXXX")
trap 'rm -rf "$WORK"' EXIT INT TERM

if [ -n "$source_dir" ]; then
    SRC=$(cd "$source_dir" && pwd -P)
    echo "==> Using existing checkout: $SRC"
else
    SRC="$WORK/helix"
    echo "==> Cloning $CLONE_URL ..."
    # Full clone, not --depth 1: `git describe` needs tags to produce the
    # version string that goes into packages.json.
    git clone "$CLONE_URL" "$SRC"
    git -C "$SRC" checkout "$rev"
fi

SHA=$(git -C "$SRC" rev-parse HEAD)
DESCRIBE=$(git -C "$SRC" describe --tags 2> /dev/null || echo "")
[ -n "$DESCRIBE" ] || {
    echo "ERROR: 'git describe --tags' produced nothing in $SRC." >&2
    echo "       A shallow clone has no tags; re-clone without --depth." >&2
    exit 1
}
echo "  commit:   $SHA"
echo "  describe: $DESCRIBE"

# The loadout's own ~/.cargo/config.toml (installed by env-cargo) replaces
# crates.io with the offline local-registry store, which cannot resolve helix's
# dependency graph. Build under a private CARGO_HOME so the user's offline
# config is neither used nor modified. Same workaround as build-surfer.sh.
export CARGO_HOME="$WORK/cargo-home"

echo "==> Building release binary ..."
( cd "$SRC" && cargo build --release --locked )
BIN="$SRC/target/release/hx"
[ -x "$BIN" ] || { echo "ERROR: no binary at $BIN" >&2; exit 1; }

echo "==> Verifying reported version ..."
reported=$("$BIN" --version | head -1)
echo "  $reported"
case "$reported" in
    *"$(echo "$SHA" | cut -c1-8)"*) ;;
    *)
        echo "ERROR: '$reported' does not carry the built commit $(echo "$SHA" | cut -c1-8)." >&2
        echo "       The binary is not the tree that was just built." >&2
        exit 1
        ;;
esac

echo "==> Checking glibc floor ..."
loadout_report_max_glibc "$BIN"
MAX_GLIBC=$(readelf -V "$BIN" 2> /dev/null | grep -oE 'GLIBC_[0-9]+\.[0-9]+' | sort -V | tail -1)
case "${MAX_GLIBC:-GLIBC_2.0}" in
    GLIBC_2.2[0-8] | GLIBC_2.1[0-9] | GLIBC_2.[0-9]) ;;
    *)
        echo "ERROR: needs $MAX_GLIBC; EL8 has glibc 2.28." >&2
        echo "       Something in the build picked up a newer toolchain -- check" >&2
        echo "       that gcc-toolset is NOT enabled for this build." >&2
        exit 1
        ;;
esac

echo "==> Checking NEEDED closure ..."
# Everything must be glibc or libgcc_s, both on this repo's never-bundle list.
# A new NEEDED means helix stopped being self-contained and needs a bundling
# decision before it can ship.
NEEDED=$(readelf -d "$BIN" | sed -n 's/.*NEEDED.*\[\(.*\)\]/\1/p')
echo "  NEEDED: $(echo "$NEEDED" | tr '\n' ' ')"
for so in $NEEDED; do
    case "$so" in
        libc.so.6 | libm.so.6 | libdl.so.2 | libpthread.so.0 | librt.so.1) ;;
        libgcc_s.so.1 | ld-linux-x86-64.so.2) ;;
        *)
            echo "ERROR: unexpected NEEDED '$so' -- not glibc and not bundled." >&2
            exit 1
            ;;
    esac
done

echo "==> Fetching and building tree-sitter grammars ..."
HELIX_RUNTIME="$SRC/runtime"
export HELIX_RUNTIME
( cd "$SRC" && "$BIN" --grammar fetch )
( cd "$SRC" && "$BIN" --grammar build )
GRAMMARS=$(find "$SRC/runtime/grammars" -maxdepth 1 -name '*.so' | wc -l)
echo "  built $GRAMMARS grammars"
[ "$GRAMMARS" -gt 200 ] || {
    echo "ERROR: only $GRAMMARS grammars built; expected 200+." >&2
    echo "       A partial grammar set ships an editor with silently dead" >&2
    echo "       highlighting for whatever failed. Read the build output." >&2
    exit 1
}

echo "==> Smoke: --health against this repo's shipped helix config ..."
# See the header. --health exits 0 on a malformed config, so the text is the
# assertion, not the exit code.
HEALTH_HOME="$WORK/health"
mkdir -p "$HEALTH_HOME/helix"
cp "$REPO/envs/helix/config.toml" "$HEALTH_HOME/helix/config.toml"
cp "$REPO/envs/helix/languages.toml" "$HEALTH_HOME/helix/languages.toml"
health=$(XDG_CONFIG_HOME="$HEALTH_HOME" "$BIN" --health 2>&1) || {
    echo "$health" >&2
    echo "ERROR: hx --health exited non-zero." >&2
    exit 1
}
case "$health" in
    *"malformed"* | *"Bad config"*)
        echo "$health" >&2
        echo "" >&2
        echo "ERROR: this helix REJECTS envs/helix/config.toml or languages.toml." >&2
        echo "       helix discards the WHOLE file on an unknown field and falls" >&2
        echo "       back to stock defaults silently -- fix the config to match" >&2
        echo "       this build before packaging it." >&2
        exit 1
        ;;
esac
echo "$health" | grep -q "Config file:" || {
    echo "ERROR: --health did not report a config file; probe is not testing what it thinks." >&2
    exit 1
}
echo "  config accepted"

echo "==> Smoke: tree-sitter highlighting on a real buffer ..."
# `hx --health <language>` reports per-language highlight/LSP status from the
# runtime that HELIX_RUNTIME points at, so this fails if grammars or queries did
# not land where the wrapper will look for them.
for lang in rust python toml markdown bash; do
    line=$(XDG_CONFIG_HOME="$HEALTH_HOME" "$BIN" --health "$lang" 2>&1) || {
        echo "$line" >&2
        echo "ERROR: --health $lang failed." >&2
        exit 1
    }
    echo "$line" | grep -qi "highlight.*✓" || {
        echo "$line" >&2
        echo "ERROR: no highlight support reported for $lang." >&2
        exit 1
    }
done
echo "  highlighting present for rust python toml markdown bash"

echo "==> Staging runtime archive ..."
STAGE="$WORK/stage"
mkdir -p "$STAGE/runtime/grammars"
cp "$SRC/runtime/tutor" "$STAGE/runtime/tutor"
cp -a "$SRC/runtime/queries" "$STAGE/runtime/queries"
cp -a "$SRC/runtime/themes" "$STAGE/runtime/themes"
# Built grammars ONLY -- grammars/sources is the fetched git checkout of every
# grammar (2.2 GB) and must never enter the payload.
find "$SRC/runtime/grammars" -maxdepth 1 -name '*.so' -exec cp {} "$STAGE/runtime/grammars/" \;
strip "$STAGE"/runtime/grammars/*.so 2> /dev/null || true
[ ! -e "$STAGE/runtime/grammars/sources" ] || {
    echo "ERROR: grammars/sources leaked into the stage." >&2
    exit 1
}

RUNTIME_DIR="$REPO/payload/$LOADOUT_PLATFORM/runtime"
mkdir -p "$RUNTIME_DIR"
( cd "$STAGE" && tar -cf - ./runtime ) | bzip2 -9 > "$RUNTIME_DIR/helix.tar.bz2"
echo "Packaged: $RUNTIME_DIR/helix.tar.bz2 ($(du -h "$RUNTIME_DIR/helix.tar.bz2" | cut -f1))"

echo "==> Packaging binary and wrapper ..."
loadout_package_bin "$BIN" "$PKG.bin"
bzip2 -c "$REPO/build/helix/hx" > "$LOADOUT_BIN_DIR/hx.bz2"
chmod 644 "$LOADOUT_BIN_DIR/hx.bz2"
echo "Packaged: $LOADOUT_BIN_DIR/hx.bz2"

loadout_stamp_version "$PKG" "$DESCRIBE"

cat <<EOF

Done. helix $DESCRIBE ($SHA)

Next, as for every payload change:
  ./build/strip-all-elf-binaries
  python3.14 build/gen-installed-sizes   # before the manifest: it hashes this file
  python3.14 build/gen-content-manifest
  python3.14 build/gen-readme-table
EOF
