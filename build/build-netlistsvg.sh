#!/bin/sh
# Build netlistsvg as a pure Node.js runtime archive for
# el8.x86_64.glibc2p28.
#
# Produces:
#   payload/el8.x86_64.glibc2p28/runtime/netlistsvg.tar.bz2
#     bin/netlistsvg
#       sh wrapper -> bundled node + lib/node_modules/netlistsvg/bin/netlistsvg.js
#     bin/netlistsvg-dumplayout
#       sh wrapper -> bundled node + lib/node_modules/netlistsvg/bin/exportLayout.js
#     lib/node_modules/netlistsvg/  (upstream npm package + production deps)
#
# Why the npm tarball is the source: upstream GitHub (nturley/netlistsvg, tag
# v1.0.2, 2020) ships no release assets; the npm tarball netlistsvg@1.0.2 is
# the published artifact and the Yosys-ecosystem standard render path.
#
# Why npm install at build time: the package ships no lockfile, so production
# deps (ajv, onml, clone, elkjs, json5, yargs, lodash, fs-extra, ajv-errors
# plus transitive closure) are resolved with the loadout node/npm at build
# time (network allowed at build time, container only) and vendored into the
# archive. The installed tree is fully offline.
#
# Usage:
#   ./build/build-netlistsvg.sh --tag 1.0.2

set -eu

REPO="$(cd "$(dirname "$0")/.." && pwd)"
RUNTIME_DIR="$REPO/payload/el8.x86_64.glibc2p28/runtime"
TAG=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        --tag)
            shift
            [ "$#" -gt 0 ] || { echo "missing value for --tag" >&2; exit 2; }
            TAG="$1"
            ;;
        -h|--help) sed -n '2,/^$/p' "$0"; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done

if [ -z "$TAG" ]; then
    echo "ERROR: --tag is required, e.g.: $0 --tag 1.0.2" >&2
    echo "Versions: https://www.npmjs.com/package/netlistsvg?activeTab=versions" >&2
    exit 1
fi

PY=
for cand in "$HOME/.local/bin/python3.14" "$(command -v python3.14 || true)" "$(command -v python3 || true)"; do
    if [ -n "$cand" ] && [ -x "$cand" ]; then PY="$cand"; break; fi
done
[ -n "$PY" ] || { echo "ERROR: no python3.14/python3 found" >&2; exit 1; }

need() {
    command -v "$1" >/dev/null 2>&1 || {
        printf 'missing required command: %s\n' "$1" >&2
        exit 1
    }
}
need curl
need tar
need openssl

BZIP2="$(command -v bzip2 || true)"
[ -x "$HOME/.local/bin/bzip2" ] && BZIP2="$HOME/.local/bin/bzip2"
[ -n "$BZIP2" ] || { echo "ERROR: bzip2 not found" >&2; exit 1; }

WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/build-netlistsvg-XXXXXX")
trap 'rm -rf "$WORK_DIR"' EXIT INT TERM

echo "==> Fetching npm registry metadata for netlistsvg@$TAG ..."
curl -fsSL -o "$WORK_DIR/meta.json" \
    "https://registry.npmjs.org/netlistsvg/$TAG" --retry 3 --retry-delay 2

eval "$($PY - "$WORK_DIR/meta.json" <<'PYEOF'
import json, sys
meta = json.load(open(sys.argv[1]))
print(f'TARBALL_URL={meta["dist"]["tarball"]!r}')
integrity = meta["dist"].get("integrity", "")
algo, _, b64 = integrity.partition("-")
print(f'INTEGRITY_ALGO={algo!r}')
print(f'INTEGRITY_B64={b64!r}')
PYEOF
)"
[ -n "${TARBALL_URL:-}" ] || { echo "ERROR: no tarball URL in registry metadata" >&2; exit 1; }
echo "==> Downloading $TARBALL_URL ..."
curl -fL -o "$WORK_DIR/netlistsvg.tgz" "$TARBALL_URL" --retry 3 --retry-delay 2

[ -n "${INTEGRITY_B64:-}" ] || { echo "ERROR: no dist.integrity for netlistsvg@$TAG" >&2; exit 1; }
echo "==> Verifying $INTEGRITY_ALGO integrity ..."
case "$INTEGRITY_ALGO" in
    sha512)
        GOT=$(openssl dgst -sha512 -binary "$WORK_DIR/netlistsvg.tgz" | openssl base64 -A)
        [ "$GOT" = "$INTEGRITY_B64" ] || {
            echo "ERROR: sha512 mismatch" >&2
            echo "       expected $INTEGRITY_B64" >&2
            echo "       got      $GOT" >&2
            exit 1
        }
        echo "  integrity OK"
        ;;
    *)
        echo "ERROR: unsupported integrity algo '$INTEGRITY_ALGO'" >&2
        exit 1
        ;;
esac

echo "==> Extracting ..."
mkdir -p "$WORK_DIR/pkg"
tar xzf "$WORK_DIR/netlistsvg.tgz" -C "$WORK_DIR/pkg"

PKG_JSON="$WORK_DIR/pkg/package/package.json"
[ -f "$PKG_JSON" ] || { echo "ERROR: package/package.json missing after extract" >&2; exit 1; }
NPM_VER=$($PY -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$PKG_JSON")
[ "$NPM_VER" = "$TAG" ] || {
    echo "ERROR: npm package declares version '$NPM_VER' but --tag says $TAG" >&2
    exit 1
}
for f in bin/netlistsvg.js bin/exportLayout.js; do
    [ -f "$WORK_DIR/pkg/package/$f" ] || { echo "ERROR: $f missing in npm package" >&2; exit 1; }
done

echo "==> Staging archive tree ..."
STAGE="$WORK_DIR/stage"
mkdir -p "$STAGE/bin" "$STAGE/lib/node_modules"
mv "$WORK_DIR/pkg/package" "$STAGE/lib/node_modules/netlistsvg"

NODE_BIN="$HOME/.local/bin/node"
[ -x "$NODE_BIN" ] || NODE_BIN="$(command -v node || true)"
[ -n "$NODE_BIN" ] || { echo "ERROR: no node found (use loadout's node)" >&2; exit 1; }
NPM_BIN="$(dirname "$NODE_BIN")/npm"
[ -x "$NPM_BIN" ] || NPM_BIN="$(command -v npm || true)"
[ -n "$NPM_BIN" ] || { echo "ERROR: no npm found alongside loadout's node" >&2; exit 1; }
echo "==> Installing production deps with $("$NODE_BIN" --version) ..."
(cd "$STAGE/lib/node_modules/netlistsvg" && "$NPM_BIN" install --omit=dev --no-audit --no-fund)
echo "==> Resolved dep tree ..."
(cd "$STAGE/lib/node_modules/netlistsvg" && "$NPM_BIN" ls --omit=dev)

ELF_HITS=$(find "$STAGE/lib/node_modules/netlistsvg" -type f | while IFS= read -r f; do
    if head -c4 "$f" | od -An -tx1 | grep -q '7f 45 4c 46'; then
        echo "$f"
    fi
done)
[ -z "$ELF_HITS" ] || {
    echo "ERROR: ELF file(s) found in staged tree -- unexpected; investigate:" >&2
    printf '  %s\n' "$ELF_HITS" >&2
    exit 1
}

cat >"$STAGE/bin/netlistsvg" <<WRAPPER
#!/bin/sh
# loadout wrapper: netlistsvg CLI on loadout's bundled Node.js (absolute path --
# works without any PATH setup).
PREFIX=\$(CDPATH= cd -- "\$(dirname -- "\$0")/.." && pwd)
exec "\$PREFIX/bin/node" "\$PREFIX/lib/node_modules/netlistsvg/bin/netlistsvg.js" "\$@"
WRAPPER

cat >"$STAGE/bin/netlistsvg-dumplayout" <<WRAPPER
#!/bin/sh
# loadout wrapper: netlistsvg layout dumper on loadout's bundled Node.js.
PREFIX=\$(CDPATH= cd -- "\$(dirname -- "\$0")/.." && pwd)
exec "\$PREFIX/bin/node" "\$PREFIX/lib/node_modules/netlistsvg/bin/exportLayout.js" "\$@"
WRAPPER
chmod 755 "$STAGE/bin/netlistsvg" "$STAGE/bin/netlistsvg-dumplayout"

echo "==> Stage-verify with $($NODE_BIN --version) ..."
ln -s "$NODE_BIN" "$STAGE/bin/node"

HELP_OUT=$("$STAGE/bin/netlistsvg" --help 2>&1 || true)
case "$HELP_OUT" in
    *"usage:"*"input_json_file"*)
        echo "  netlistsvg --help prints usage (rc=1 by upstream yargs-6 demand design)" ;;
    *)
        echo "ERROR: netlistsvg --help output unexpected:" >&2
        printf '%s\n' "$HELP_OUT" >&2
        exit 1
        ;;
esac
DUMP_OUT=$("$STAGE/bin/netlistsvg-dumplayout" --help 2>&1 || true)
case "$DUMP_OUT" in
    *"usage:"*"input_json_file"*)
        echo "  netlistsvg-dumplayout --help prints usage (rc=1, same design)" ;;
    *)
        echo "ERROR: netlistsvg-dumplayout --help output unexpected:" >&2
        printf '%s\n' "$DUMP_OUT" >&2
        exit 1
        ;;
esac

cat >"$WORK_DIR/fixture.json" <<FIXTURE
{"creator": "loadout-smoke", "modules": {"top": {"ports": {"a": {"direction": "input", "bits": [2]}, "b": {"direction": "input", "bits": [3]}, "y": {"direction": "output", "bits": [4]}}, "cells": {"\$and\$top\$1": {"hide_name": 1, "type": "\$and", "parameters": {}, "attributes": {}, "port_directions": {"A": "input", "B": "input", "Y": "output"}, "connections": {"A": [2], "B": [3], "Y": [4]}}}, "netnames": {"a": {"hide_name": 0, "bits": [2], "attributes": {}}, "b": {"hide_name": 0, "bits": [3], "attributes": {}}, "y": {"hide_name": 0, "bits": [4], "attributes": {}}}}}}
FIXTURE
"$STAGE/bin/netlistsvg" "$WORK_DIR/fixture.json" -o "$WORK_DIR/out.svg"
grep -q '<svg' "$WORK_DIR/out.svg" || {
    echo "ERROR: rendered output has no <svg element" >&2
    exit 1
}
echo "  AND-gate fixture renders SVG: OK"

rm -f "$STAGE/bin/node"
[ -L "$STAGE/bin/node" ] && { echo "ERROR: failed to remove stage node symlink" >&2; exit 1; }

echo "==> Packaging (tar.bz2) ..."
rm -f "$RUNTIME_DIR/netlistsvg.tar.bz2"
tar cjf "$RUNTIME_DIR/netlistsvg.tar.bz2" -C "$STAGE" bin lib 2>/dev/null \
    || tar -cf - -C "$STAGE" bin lib | "$BZIP2" >"$RUNTIME_DIR/netlistsvg.tar.bz2"
chmod 644 "$RUNTIME_DIR/netlistsvg.tar.bz2"
echo "  staged: $RUNTIME_DIR/netlistsvg.tar.bz2 ($(du -h "$RUNTIME_DIR/netlistsvg.tar.bz2" | cut -f1))"

echo ""
echo "Done."
echo ""
echo "Next:"
echo "  ./build/strip-all-elf-binaries"
echo "  python3.14 build/gen-installed-sizes"
echo "  python3.14 build/gen-content-manifest"
