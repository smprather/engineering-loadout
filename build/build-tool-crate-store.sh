#!/bin/sh
# Build the SUPERSET offline crate store: the curated user seed closure
# (rust-crate-list.txt) UNION every loadout rust tool's Cargo.lock closure
# (rust-tool-locks.txt). The result lets a farm node both build the user's own
# offline projects AND rebuild the loadout's own rust binaries with
# `cargo build --offline`.
#
# Mechanism: `cargo local-registry --sync` regenerates the registry index from a
# SINGLE lockfile (it prunes anything not in that lock), so we cannot just run it
# per tool. Instead we harvest every lock, MERGE their registry [[package]]
# blocks into one synthetic Cargo.lock (dedup by name+version), then sync once.
#
# This re-introduces the online/TLS crates that build-crate-store.sh's lean
# user store deliberately drops -- here they are justified because a bundled
# tool's lock pins them. The aws-lc ban is therefore downgraded to a WARNING
# (a tool may legitimately pin it; we report but do not fail).
#
# Output: rust/crate-store.tar.bz2 (chunked) -- the SHIPPED store. Run
# build-crate-store.sh instead if you want the lean user-only store.
#
# Prerequisites (EL8 build machine): rustc+cargo, cargo-local-registry, git,
# network to crates.io + every tool repo, tar, bzip2, split, python3.
#
# Usage:
#   /path/to/build-tool-crate-store.sh                 # seeds + all tool locks
#   /path/to/build-tool-crate-store.sh --no-firstparty # skip smprather/* repos
#   /path/to/build-tool-crate-store.sh --no-seeds      # tool locks only
#   /path/to/build-tool-crate-store.sh --no-pack       # weigh only, no tar

set -eu

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SEED_LIST="$REPO/build/rust-crate-list.txt"
TOOL_LIST="$REPO/build/rust-tool-locks.txt"
OUT_DIR="$REPO/payload/crate-store"
OUT_ARCHIVE="$OUT_DIR/crate-store.tar.bz2"
BANNED="aws-lc-sys aws-lc-rs"
CHUNK_BYTES=$((40 * 1024 * 1024))

with_seeds=1
with_firstparty=1
pack=1
while [ "$#" -gt 0 ]; do
    case "$1" in
        --no-seeds) with_seeds=0 ;;
        --no-firstparty) with_firstparty=0 ;;
        --no-pack) pack=0 ;;
        -h|--help) sed -n '2,/^$/p' "$0"; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done

need() { command -v "$1" >/dev/null 2>&1 || { echo "missing required command: $1" >&2; exit 1; }; }
need cargo; need git; need tar; need bzip2; need split; need python3

if ! cargo local-registry --help >/dev/null 2>&1; then
    echo "installing cargo-local-registry..."; cargo install cargo-local-registry
fi

# Isolate the resolve/sync from any loadout-influenced cargo resolution,
# exactly as build-crate-store.sh does. Historically env-cargo wrote
# ~/.cargo/config.toml with `[source.crates-io] replace-with =
# "loadout-store"`, so on a build box that had run `loadout install env-cargo`,
# cargo resolved against the store this script is rebuilding -- and a crate not
# already in it died with "no matching package named `<name>` found ... index
# (which is replacing registry `crates-io`)". The store could then never gain a
# crate, which is how it went stale enough to break the fish 4.8.1 build. Since
# 2026-08-22 the config is stock, but the shell wrapper injects that same
# replacement whenever crates.io is unreachable -- so the isolation stays
# mandatory either way. Deliberately after the cargo-local-registry check
# above, since `cargo install` writes to $CARGO_HOME/bin.
CARGO_HOME_ISOLATED="$(mktemp -d "${TMPDIR:-/tmp}/tool-store-cargo-home.XXXXXX")"
CARGO_HOME="$CARGO_HOME_ISOLATED"
export CARGO_HOME
echo "Isolated CARGO_HOME: $CARGO_HOME (bypasses the offline source replacement)"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/tool-store.XXXXXX")"
trap 'rm -rf "$WORK" "$CARGO_HOME_ISOLATED"' EXIT INT TERM
STORES="$WORK/stores"; STORE="$WORK/store"; LOCKS_DIR="$WORK/locks"
mkdir -p "$STORES" "$STORE" "$LOCKS_DIR"
nsync=0

# Per-tool coverage: "<name>\t<crates>", 0 for anything that was skipped.
# Every skip path below is a WARN on stderr and the build still exits 0, so a
# tool can silently contribute NOTHING to the shipped store. That is not
# hypothetical -- `ty` was absent from every store ever built (astral-sh/ty is a
# thin repo whose Rust source is a `ruff` git submodule, so it has no root
# Cargo.lock), and `verify-crate-store --check-policy` reported OK throughout
# because it compares REFS to packages.json, never store CONTENTS.
# This file is what makes coverage checkable; the gate reads it.
COVERAGE="$WORK/coverage.tsv"
: > "$COVERAGE"
COVERAGE_OUT="$REPO/assurance/crate-store-tools.tsv"

# cargo-local-registry --sync downloads exactly the crates a project's manifest
# + lock resolve to (an empty manifest syncs nothing), and it prunes anything
# outside that one lock. So we sync each tool's OWN clone (manifest + committed
# lock = the tool's EXACT pinned versions, which an offline tool build needs)
# into its own per-tool store, then union all the per-tool stores at the end.
sync_root() {  # label  dir-with-Cargo.toml-and-lock
    label="$1"; root="$2"
    out="$STORES/$label"; mkdir -p "$out"
    if cargo local-registry --sync "$root/Cargo.lock" "$out" >/dev/null 2>&1; then
        cp "$root/Cargo.lock" "$LOCKS_DIR/$label.lock"
        rc="$(find "$out" -name '*.crate' | wc -l | tr -d ' ')"
        echo "  $label: $rc crates"
        printf '%s\t%s\n' "$label" "$rc" >> "$COVERAGE"
        nsync=$((nsync + 1))
    else
        echo "  WARN: sync failed for $label -- skipping" >&2
        printf '%s\t0\n' "$label" >> "$COVERAGE"
        rm -rf "$out"
    fi
}

# 1. curated user seed closure (resolved to latest -> for users' own projects)
if [ "$with_seeds" -eq 1 ]; then
    echo "### resolving + syncing curated user seed closure"
    PROJ="$WORK/seed"; mkdir -p "$PROJ/src"; : > "$PROJ/src/lib.rs"
    {
        echo '[package]'; echo 'name="loadout-seed"'; echo 'version="0.0.0"'
        echo 'edition="2021"'; echo 'publish=false'; echo; echo '[dependencies]'
    } > "$PROJ/Cargo.toml"
    while IFS= read -r line || [ -n "$line" ]; do
        line="${line%%#*}"; line="$(printf '%s' "$line" | tr -d '[:space:]')"
        [ -n "$line" ] || continue
        name="${line%%=*}"; req='*'; [ "$name" != "$line" ] && req="${line#*=}"
        printf '%s = "%s"\n' "$name" "$req" >> "$PROJ/Cargo.toml"
    done < "$SEED_LIST"
    ( cd "$PROJ" && cargo generate-lockfile >/dev/null 2>&1 )
    sync_root "00-seeds" "$PROJ"
fi

# 2. each rust tool: clone at ref, sync its exact-pinned closure
clone_tool() {
    name="$1"; repo="$2"; ref="$3"; dir="$WORK/src/$name"
    rm -rf "$dir"
    for r in "$ref" "v$ref"; do
        [ "$ref" = "HEAD" ] && continue
        if git clone --depth 1 --branch "$r" "$repo" "$dir" >/dev/null 2>&1; then return 0; fi
    done
    git clone --depth 1 "$repo" "$dir" >/dev/null 2>&1 && return 0
    return 1
}

echo "### cloning + syncing each rust tool"
while read -r name repo ref _rest; do
    case "$name" in ''|\#*) continue ;; esac
    [ -n "${repo:-}" ] && [ -n "${ref:-}" ] || continue
    case "$repo" in *smprather*) [ "$with_firstparty" -eq 1 ] || { echo "  skip $name (--no-firstparty)"; continue; } ;; esac
    if ! clone_tool "$name" "$repo" "$ref"; then
        echo "  WARN: clone failed for $name ($repo @ $ref) -- skipping" >&2
        printf '%s\t0\n' "$name" >> "$COVERAGE"; continue
    fi
    dir="$WORK/src/$name"
    lockroot="$dir"

    # Initialise submodules ALWAYS, not only when a root Cargo.lock is missing.
    # Two different tools need this for two different reasons, and each was
    # silently skipped from every store ever built:
    #
    #   ty     -- a thin DISTRIBUTION repo (pyproject.toml, uv.lock, docs) whose
    #             Rust source is a `ruff` submodule. No root Cargo.lock and no
    #             workspace, so `cargo generate-lockfile` fails outright.
    #   surfer -- HAS a root Cargo.lock, but `f128` and `instruction-decoder` are
    #             submodules referenced as PATH dependencies, so
    #             `cargo local-registry --sync` cannot resolve the lock without
    #             them and fails.
    #
    # Gating this on "no root lock" therefore fixes ty and leaves surfer broken.
    # --filter=blob:none keeps it cheap against a large monorepo and works on a
    # --depth 1 parent clone; the unfiltered retry covers servers with no
    # partial-clone support.
    ( cd "$dir" && git submodule update --init --recursive --filter=blob:none >/dev/null 2>&1 ) \
        || ( cd "$dir" && git submodule update --init --recursive >/dev/null 2>&1 ) || true

    if [ ! -f "$dir/Cargo.lock" ]; then
        for sub in $( cd "$dir" && git submodule status 2>/dev/null | awk '{print $2}' ); do
            if [ -f "$dir/$sub/Cargo.lock" ]; then
                lockroot="$dir/$sub"
                echo "  $name: no root lock; using submodule $sub/Cargo.lock"
                break
            fi
        done
    fi
    if [ ! -f "$lockroot/Cargo.lock" ]; then
        ( cd "$lockroot" && cargo generate-lockfile >/dev/null 2>&1 ) || {
            echo "  WARN: no lock and generate-lockfile failed for $name -- skipping" >&2
            printf '%s\t0\n' "$name" >> "$COVERAGE"; continue; }
    fi
    sync_root "$name" "$lockroot"
done < "$TOOL_LIST"

[ "$nsync" -gt 0 ] || { echo "no stores synced" >&2; exit 1; }

# 3. ban guardrail -> WARN only (a tool may legitimately pin it)
for b in $BANNED; do
    if grep -rqs "^name = \"$b\"\$" "$LOCKS_DIR"; then
        who="$(grep -rls "^name = \"$b\"\$" "$LOCKS_DIR" | xargs -n1 basename | sed 's/\.lock$//' | paste -sd, )"
        echo "  WARNING: banned crate '$b' pinned by: $who (kept -- tool needs it)" >&2
    fi
done

# 4. union all per-tool stores into one consistent local-registry. The
# local-registry index is per-crate-name (one JSON line per version), so the
# merge is: copy every .crate once, and union the index lines per crate file.
echo "### merging $nsync per-tool stores -> one registry"
python3 - "$STORES" "$STORE" <<'PY'
import os, sys, shutil
stores, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)
index_lines = {}   # rel index path -> dict(version-line-key -> line)
import json
for label in sorted(os.listdir(stores)):
    sdir = os.path.join(stores, label)
    if not os.path.isdir(sdir):
        continue
    for root, _dirs, files in os.walk(sdir):
        rel = os.path.relpath(root, sdir)
        for fn in files:
            src = os.path.join(root, fn)
            rpath = fn if rel == "." else os.path.join(rel, fn)
            in_index = rpath.split(os.sep)[0] == "index"
            if fn.endswith(".crate") or not in_index or fn == "config.json":
                dst = os.path.join(out, rpath)
                os.makedirs(os.path.dirname(dst), exist_ok=True)
                if not os.path.exists(dst):
                    shutil.copy2(src, dst)
            else:
                bucket = index_lines.setdefault(rpath, {})
                for line in open(src, encoding="utf-8", errors="replace"):
                    line = line.rstrip("\n")
                    if not line.strip():
                        continue
                    try:
                        key = json.loads(line)["vers"]
                    except Exception:
                        key = line
                    bucket.setdefault(key, line)
for rpath, bucket in index_lines.items():
    dst = os.path.join(out, rpath)
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    with open(dst, "w", encoding="utf-8") as f:
        for key in sorted(bucket):
            f.write(bucket[key] + "\n")
ncrate = sum(1 for r, _d, fs in os.walk(out) for x in fs if x.endswith(".crate"))
print("  unioned .crate files:", ncrate)
PY

ncrate="$(find "$STORE" -name '*.crate' | wc -l | tr -d ' ')"
echo ""
echo "=== SUPERSET STORE WEIGH-IN ==="
echo "  stores merged:  $nsync"
echo "  .crate files:   $ncrate"
echo "  raw store size: $(du -sh "$STORE" | cut -f1)"

if [ "$pack" -eq 0 ]; then
    echo ""; echo "--no-pack: store left at $STORE (removed on exit; nothing kept)"; exit 0
fi

mkdir -p "$OUT_DIR"
rm -f "$OUT_ARCHIVE" "$OUT_ARCHIVE".part-*
echo ""; echo "Packing -> $OUT_ARCHIVE ..."
tar -cjf "$OUT_ARCHIVE" -C "$STORE" .

# Assert the archive is actually there before measuring it. `wc -c < missing`
# fails in the redirect, so the command substitution yields an empty string and
# the `[ "$packed_bytes" -gt ... ]` below dies with "integer expression
# expected" -- which this script previously survived, exiting 0 while leaving a
# TRUNCATED two-chunk store in payload/. That happened for real: a concurrent
# ./build/strip-all-elf-binaries saw the freshly written 314 MB archive, chunked it
# mid-write, and this step never noticed. Never run two payload-mutating builds
# at once, and fail loudly when the output is missing.
[ -s "$OUT_ARCHIVE" ] || {
    echo "ERROR: $OUT_ARCHIVE was not created (or is empty) by tar." >&2
    echo "  Is another payload-mutating job running (strip-all-elf-binaries)?" >&2
    exit 1
}
packed_bytes="$(wc -c < "$OUT_ARCHIVE" | tr -d ' ')"
case "$packed_bytes" in
    ''|*[!0-9]*) echo "ERROR: could not size $OUT_ARCHIVE" >&2; exit 1 ;;
esac
echo "  packed: $(du -sh "$OUT_ARCHIVE" | cut -f1)"
if [ "$packed_bytes" -gt "$CHUNK_BYTES" ]; then
    echo "  splitting into .part-NNN chunks..."
    split -d -a 3 -b "$CHUNK_BYTES" "$OUT_ARCHIVE" "$OUT_ARCHIVE".part-
    rm -f "$OUT_ARCHIVE"
    nchunks="$(ls "$OUT_ARCHIVE".part-* 2>/dev/null | wc -l | tr -d ' ')"
    [ "$nchunks" -ge 1 ] || { echo "ERROR: split produced no chunks" >&2; exit 1; }
    echo "  -> $nchunks chunks"
fi
# Record per-tool coverage so `verify-crate-store --check-coverage` can prove
# every pinned tool actually contributed crates. Written LAST, only on an
# otherwise successful build, so a failed run cannot leave a record claiming
# coverage the store does not have.
sort -o "$COVERAGE" "$COVERAGE"
{
    echo "# Per-tool crate counts in the shipped store, written by build-tool-crate-store.sh."
    echo "# 0 means the tool contributed NOTHING -- it was skipped (no lock, clone or sync"
    echo "# failure). The build still exits 0 in that case, so this file is the record that"
    echo "# makes it visible. Gated by: build/verify-crate-store --check-coverage"
    echo "# Format: <name>\t<crates>.  00-seeds is the curated user closure, not a tool."
    cat "$COVERAGE"
} > "$COVERAGE_OUT"
echo ""
echo "Wrote coverage record -> $COVERAGE_OUT"
awk -F'\t' '$2 == 0 && $1 !~ /^#/ { print "  ZERO COVERAGE: " $1 }' "$COVERAGE"

echo ""
echo "Shipped store now covers user projects + offline rebuilds of loadout rust tools."
echo "Install:  ./loadout install @rust"
