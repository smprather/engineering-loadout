#!/bin/sh
# Build an offline Cargo local-registry from a seed crate list.
#
# What it does (all ONLINE, run on the EL8 build machine):
#   1. Reads build/rust-crate-list.txt (top-level seed crates).
#   2. Generates a throwaway Cargo manifest with every seed as a dependency.
#   3. `cargo generate-lockfile` -> resolves the FULL transitive dep closure.
#      (250 seeds typically explode to 1000+ locked crates -- that's correct;
#       an offline `cargo build` needs the whole tree, not just the top level.)
#   4. `cargo local-registry --sync Cargo.lock <store>` -> downloads every
#      .crate into a local registry (index/ + *.crate files), no build.
#   5. Packs the store to rust/crate-store.tar.bz2 and reports the weight.
#
# The resulting registry is consumed offline by loadout's shell cargo wrapper
# (envs/bash/functions.sh cargo() / tcsh helpers/cargo-wrap): while crates.io
# is unreachable it injects, for that command only,
#
#     --config 'source.crates-io.replace-with="loadout-local"'
#     --config source.loadout-local.local-registry="<localroot>/share/cargo/registry-store"
#
# so any project whose deps are in the store resolves and builds with
# `cargo build --offline` -- no crates.io, no index fetch. ~/.cargo/config.toml
# itself stays stock (online-first).
#
# Prerequisites on the build machine (EL8):
#   - rustc + cargo on PATH (rustup, dnf, or the bundled rust runtime once it exists)
#   - network access to crates.io + static.crates.io
#   - cargo-local-registry (auto-installed via `cargo install` if missing)
#
# Usage (run from any directory):
#   /path/to/build-crate-store.sh                 # full seed list
#   /path/to/build-crate-store.sh --list other.txt  # alternate seed file
#   /path/to/build-crate-store.sh --keep          # keep the temp workdir
#   /path/to/build-crate-store.sh --no-pack       # sync only, skip tar (just weigh it)

set -eu

REPO="$(cd "$(dirname "$0")/.." && pwd)"
LIST="$REPO/build/rust-crate-list.txt"
OUT_DIR="$REPO/payload/crate-store"
OUT_ARCHIVE="$OUT_DIR/crate-store.tar.bz2"

# Crates forbidden in the store. If a banned crate turns up in the resolved
# closure the build fails loudly with the dependency path, so you can drop or
# steer the offending seed.
#
# This is the LEAN user-only store, so the ban stands: the seed list drops the
# online/TLS stack these come from. The SHIPPED store is built by
# build-tool-crate-store.sh, which unions in every bundled tool's Cargo.lock and
# downgrades this ban to a warning, because a tool's lock may legitimately pin
# aws-lc (numr's does, via reqwest -> rustls).
BANNED="aws-lc-sys aws-lc-rs"
# Match strip-all-elf-binaries' CHUNK_THRESHOLD so no committed file trips
# GitHub's 50 MB warning. rust/ is top-level (not under payload/), so the
# strip script will not chunk it -- this script does the split itself.
CHUNK_BYTES=$((40 * 1024 * 1024))

keep=0
pack=1
while [ "$#" -gt 0 ]; do
    case "$1" in
        --list)
            shift
            [ "$#" -gt 0 ] || { echo "missing value for --list" >&2; exit 2; }
            LIST="$1"
            ;;
        --keep) keep=1 ;;
        --no-pack) pack=0 ;;
        -h|--help)
            sed -n '2,/^$/p' "$0"
            exit 0
            ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done

need() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "missing required command: $1 -- see this script's header for prerequisites" >&2
        exit 1
    }
}

need cargo
need tar
need bzip2

[ -r "$LIST" ] || { echo "seed list not found: $LIST" >&2; exit 1; }

# Ensure cargo-local-registry is available (builds offline store indexes).
# Deliberately BEFORE the CARGO_HOME isolation below: `cargo install` writes to
# $CARGO_HOME/bin, so installing it into the throwaway home would discard it on
# every run. Once installed it is found through PATH, which the isolation does
# not touch.
if ! cargo local-registry --help >/dev/null 2>&1; then
    echo "cargo-local-registry not found -- installing via 'cargo install'..."
    cargo install cargo-local-registry
fi

# Isolate the resolve/sync from any loadout-influenced cargo resolution.
#
# Historically env-cargo wrote ~/.cargo/config.toml with an unconditional
# `replace-with` pointing at the installed store, so a plain `cargo build` on a
# build box that had run `loadout install env-cargo` resolved against the
# PREVIOUS store and new seeds died with "no matching package named `<seed>`
# found". That bootstrap trap is why the store went stale enough to break the
# fish 4.8.1 build. Since 2026-08-22 the config is stock and the offline
# fallback lives in the shell wrapper instead -- but the wrapper injects the
# same replacement whenever crates.io is unreachable, so on an air-gapped box
# the trap returns through a different door. A private CARGO_HOME with no
# config.toml keeps this script talking to real crates.io either way -- which
# is what its header has always claimed ("all ONLINE").
CARGO_HOME_ISOLATED="$(mktemp -d "${TMPDIR:-/tmp}/crate-store-cargo-home.XXXXXX")"
CARGO_HOME="$CARGO_HOME_ISOLATED"
export CARGO_HOME
echo "Isolated CARGO_HOME: $CARGO_HOME (bypasses the offline source replacement)"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/crate-store.XXXXXX")"
cleanup() {
    rm -rf "$CARGO_HOME_ISOLATED"
    [ "$keep" -eq 1 ] || rm -rf "$WORK"
}
trap cleanup EXIT INT TERM

PROJ="$WORK/seed"
STORE="$WORK/store"
mkdir -p "$PROJ/src" "$STORE"
: > "$PROJ/src/lib.rs"

# Build the seed manifest. Each non-comment line is `name` or `name=req`.
{
    printf '%s\n' '[package]'
    printf '%s\n' 'name = "loadout-crate-store-seed"'
    printf '%s\n' 'version = "0.0.0"'
    printf '%s\n' 'edition = "2021"'
    printf '%s\n' 'publish = false'
    printf '\n'
    printf '%s\n' '[dependencies]'
} > "$PROJ/Cargo.toml"

seed_count=0
while IFS= read -r line || [ -n "$line" ]; do
    # strip comments + surrounding whitespace
    line="${line%%#*}"
    line="$(printf '%s' "$line" | tr -d '[:space:]')"
    [ -n "$line" ] || continue
    name="${line%%=*}"
    if [ "$name" != "$line" ]; then
        req="${line#*=}"
    else
        req="*"
    fi
    # default-features stay on; that maximizes the .crate set we capture offline.
    printf '%s = { version = "%s" }\n' "$name" "$req" >> "$PROJ/Cargo.toml"
    seed_count=$((seed_count + 1))
done < "$LIST"

echo "Seed crates: $seed_count"
echo "Workdir:     $WORK"
echo ""
echo "Resolving full dependency closure (cargo generate-lockfile)..."
( cd "$PROJ" && cargo generate-lockfile )

locked="$(grep -c '^name = ' "$PROJ/Cargo.lock" 2>/dev/null || echo '?')"
# the seed package itself is one of those names; subtract it
[ "$locked" != "?" ] && locked=$((locked - 1))
echo "Locked crates (transitive closure): $locked"
echo ""

# Ban guardrail: refuse to build a store containing forbidden crates.
ban_hit=0
for b in $BANNED; do
    if grep -q "^name = \"$b\"\$" "$PROJ/Cargo.lock"; then
        ban_hit=1
        echo "ERROR: banned crate '$b' is in the resolved closure." >&2
        echo "       dependency path(s) pulling it in:" >&2
        ( cd "$PROJ" && cargo tree -i "$b" --edges normal 2>/dev/null ) | sed 's/^/         /' >&2
    fi
done
if [ "$ban_hit" -ne 0 ]; then
    echo "" >&2
    echo "Drop or steer the offending seed in $LIST, then re-run." >&2
    exit 1
fi

echo "Downloading crates into local registry (cargo local-registry --sync)..."
cargo local-registry --sync "$PROJ/Cargo.lock" "$STORE"

ncrate="$(find "$STORE" -name '*.crate' | wc -l | tr -d ' ')"
raw_size="$(du -sh "$STORE" | cut -f1)"
echo ""
echo "=== STORE WEIGH-IN ==="
echo "  .crate files:   $ncrate"
echo "  raw store size: $raw_size"

if [ "$pack" -eq 0 ]; then
    echo ""
    echo "--no-pack: skipping tar. Store left at: $STORE"
    echo "(pass --keep to retain it; otherwise it is removed on exit)"
    keep=1
    exit 0
fi

mkdir -p "$OUT_DIR"
# Clear any prior artifact (whole file or chunk set) so a shrunk store does not
# leave stale .part-NNN behind.
rm -f "$OUT_ARCHIVE" "$OUT_ARCHIVE".part-*
echo ""
echo "Packing -> $OUT_ARCHIVE ..."
tar -cjf "$OUT_ARCHIVE" -C "$STORE" .
packed_bytes="$(wc -c < "$OUT_ARCHIVE" | tr -d ' ')"
packed_size="$(du -sh "$OUT_ARCHIVE" | cut -f1)"
echo "  packed archive: $packed_size  ($OUT_ARCHIVE)"

# Chunk if over the GitHub-safe threshold. The installer rejoins .part-NNN via
# _bz2.resolve(); naming must be <archive>.part-000, .part-001, ... (zero-based,
# 3-digit), matching strip-all-elf-binaries' split.
if [ "$packed_bytes" -gt "$CHUNK_BYTES" ]; then
    echo "  archive > $((CHUNK_BYTES / 1024 / 1024)) MiB -- splitting into .part-NNN chunks..."
    split -d -a 3 -b "$CHUNK_BYTES" "$OUT_ARCHIVE" "$OUT_ARCHIVE".part-
    rm -f "$OUT_ARCHIVE"
    nparts="$(ls "$OUT_ARCHIVE".part-* | wc -l | tr -d ' ')"
    echo "  -> $nparts chunks: $(basename "$OUT_ARCHIVE").part-000 .. .part-$(printf '%03d' $((nparts - 1)))"
fi

echo ""
echo "=== NEXT STEPS ==="
echo "1. packages.json already carries the 'rust-crate-store' data package"
echo "   (archive payload/crate-store/crate-store.tar.bz2, installed by install_crate_store)."
echo "2. The env-cargo package writes ~/.cargo/config.toml pointing cargo at the"
echo "   installed store -- no manual config edits needed."
echo "3. Install offline with:  ./loadout install @rust"
echo ""
echo "If the weigh-in above is too fat: drop seeds from rust-crate-list.txt and re-run."
