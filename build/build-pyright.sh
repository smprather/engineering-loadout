#!/bin/sh
# Build pyright (Python LSP) as a pure Node.js runtime archive for
# el8.x86_64.glibc2p28.
#
# Produces:
#   payload/el8.x86_64.glibc2p28/runtime/pyright.tar.bz2
#     bin/pyright              sh wrapper -> bundled node + lib/node_modules/pyright/index.js
#     bin/pyright-langserver   sh wrapper -> .../langserver.index.js
#     lib/node_modules/pyright/  (upstream npm package, verbatim)
#
# WHY NOT THE PyPI WHEEL (history, load-bearing). pyright used to ship as a
# uv_tool python-tool from the PyPI `pyright` wheel. That wheel is a PYTHON
# WRAPPER around the same JS: at runtime it resolves node via
# (1) nodejs-wheel-binaries pkg (not shipped), (2) global `node` on PATH,
# (3) nodeenv -- which DOWNLOADS A NODE TARBALL FROM NODEJS.ORG. On an air-
# gapped box without ~/.local/bin/node on PATH it died trying to download.
# This archive removes Python and the wrapper entirely: the wrappers exec the
# loadout-bundled node by ABSOLUTE PATH ($PREFIX/bin/node), so pyright works
# with no PATH setup at all (GUI-launched nvim included) and zero network.
#
# Prerequisites on the build machine:
#   network access to registry.npmjs.org
#   python3.14 (repo bootstrap or ./loadout) for JSON metadata parsing
#
# Usage (run from any directory):
#   ./build/build-pyright.sh --tag 1.1.411
#
# The archive installs via the generic runtime-archive path exactly like
# nodejs itself: install_to ~/.local, sentinel bin/pyright.

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
    echo "ERROR: --tag is required, e.g.: $0 --tag 1.1.411" >&2
    echo "Releases: https://github.com/microsoft/pyright/releases (npm package 'pyright')" >&2
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

WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/build-pyright-XXXXXX")
trap 'rm -rf "$WORK_DIR"' EXIT INT TERM

echo "==> Fetching npm registry metadata for pyright@$TAG ..."
curl -fsSL -o "$WORK_DIR/meta.json" \
    "https://registry.npmjs.org/pyright/$TAG" --retry 3 --retry-delay 2

# dist.shasum = SHA1 of the tarball; dist.integrity = "sha512-<base64>".
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
curl -fL -o "$WORK_DIR/pyright.tgz" "$TARBALL_URL" --retry 3 --retry-delay 2

if [ -n "${INTEGRITY_B64:-}" ]; then
    echo "==> Verifying $INTEGRITY_ALGO integrity ..."
    case "$INTEGRITY_ALGO" in
        sha512)
            GOT=$(openssl dgst -sha512 -binary "$WORK_DIR/pyright.tgz" | openssl base64 -A)
            [ "$GOT" = "$INTEGRITY_B64" ] || {
                echo "ERROR: sha512 mismatch" >&2
                echo "       expected $INTEGRITY_B64" >&2
                echo "       got      $GOT" >&2
                exit 1
            }
            echo "  integrity OK"
            ;;
        *)
            echo "WARNING: unsupported integrity algo '$INTEGRITY_ALGO'; skipping verify" >&2
            ;;
    esac
fi

echo "==> Extracting ..."
mkdir -p "$WORK_DIR/pkg"
tar xzf "$WORK_DIR/pyright.tgz" -C "$WORK_DIR/pkg"

PKG_JSON="$WORK_DIR/pkg/package/package.json"
[ -f "$PKG_JSON" ] || { echo "ERROR: package/package.json missing after extract" >&2; exit 1; }
NPM_VER=$($PY -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$PKG_JSON")
[ "$NPM_VER" = "$TAG" ] || {
    echo "ERROR: npm package declares version '$NPM_VER' but --tag says $TAG" >&2
    exit 1
}
for f in index.js langserver.index.js dist/pyright.js dist/pyright-langserver.js; do
    [ -f "$WORK_DIR/pkg/package/$f" ] || { echo "ERROR: $f missing in npm package" >&2; exit 1; }
done

# Guard: the tree must be pure JS/data. An ELF sneaking in here would bypass
# the strip/patchelf pipeline entirely.
ELF_HITS=$(find "$WORK_DIR/pkg/package" -type f | while IFS= read -r f; do
    if head -c4 "$f" | od -An -tx1 | grep -q '7f 45 4c 46'; then
        echo "$f"
    fi
done)
[ -z "$ELF_HITS" ] || {
    echo "ERROR: ELF file(s) found in npm package -- unexpected; investigate:" >&2
    printf '  %s\n' "$ELF_HITS" >&2
    exit 1
}

echo "==> Staging archive tree ..."
STAGE="$WORK_DIR/stage"
mkdir -p "$STAGE/bin" "$STAGE/lib/node_modules"
mv "$WORK_DIR/pkg/package" "$STAGE/lib/node_modules/pyright"

cat >"$STAGE/bin/pyright" <<WRAPPER
#!/bin/sh
# loadout wrapper: pyright CLI on loadout's bundled Node.js (absolute path --
# works without any PATH setup).
PREFIX=\$(CDPATH= cd -- "\$(dirname -- "\$0")/.." && pwd)
exec "\$PREFIX/bin/node" "\$PREFIX/lib/node_modules/pyright/index.js" "\$@"
WRAPPER

cat >"$STAGE/bin/pyright-langserver" <<WRAPPER
#!/bin/sh
# loadout wrapper: pyright language server on loadout's bundled Node.js.
PREFIX=\$(CDPATH= cd -- "\$(dirname -- "\$0")/.." && pwd)
exec "\$PREFIX/bin/node" "\$PREFIX/lib/node_modules/pyright/langserver.index.js" "\$@"
WRAPPER
chmod 755 "$STAGE/bin/pyright" "$STAGE/bin/pyright-langserver"

# ---------------------------------------------------------------------------
# Functional stage-verify. Prefer a bundled node (~/.local/bin/node); fall back
# to PATH only as a dev convenience -- CI/container verification runs the real
# thing offline.
# ---------------------------------------------------------------------------
NODE_BIN="$HOME/.local/bin/node"
[ -x "$NODE_BIN" ] || NODE_BIN="$(command -v node || true)"
[ -n "$NODE_BIN" ] || { echo "ERROR: no node found to stage-verify against" >&2; exit 1; }
echo "==> Stage-verify with $($NODE_BIN --version) ..."
# The wrapper execs $PREFIX/bin/node by design; that file only exists after
# install (nodejs pkg owns it). Symlink it in for the probe and remove it so
# it never reaches the archive.
ln -s "$NODE_BIN" "$STAGE/bin/node"

VER_OUT=$("$STAGE/bin/pyright" --version)
[ "$VER_OUT" = "pyright $TAG" ] || {
    echo "ERROR: wrapper reports '$VER_OUT', expected 'pyright $TAG'" >&2
    exit 1
}
echo "  pyright --version: $VER_OUT"

TMPD=$(mktemp -d "${TMPDIR:-/tmp}/pyright-smoke-XXXXXX")
printf 'def f(x: int) -> str:\n    return x\n' >"$TMPD/bad.py"
ERR_OUT=$("$STAGE/bin/pyright" "$TMPD/bad.py" 2>&1) || true
case "$ERR_OUT" in
    *reportReturnType*)
        echo "  type-check diagnostic produced: OK" ;;
    *)
        echo "ERROR: expected reportReturnType diagnostic, got:" >&2
        printf '%s\n' "$ERR_OUT" | sed 's/^/  /' >&2
        rm -rf "$TMPD"
        exit 1
        ;;
esac
rm -rf "$TMPD"

LS_OUT=$("$STAGE/bin/pyright-langserver" 2>&1 || true)
case "$LS_OUT" in
    *"Connection input stream is not set"*)
        echo "  langserver reaches vscode-languageserver: OK" ;;
    *)
        echo "ERROR: langserver probe output unexpected:" >&2
        printf '%s\n' "$LS_OUT" | sed 's/^/  /' >&2
        exit 1
        ;;
esac

# typeshed-fallback must ride along: without it pyright degrades to partial
# stubs and reports bogus errors on stdlib usage.
[ -f "$STAGE/lib/node_modules/pyright/dist/typeshed-fallback/stdlib/builtins.pyi" ] || {
    echo "ERROR: typeshed-fallback missing from staged tree" >&2
    exit 1
}
echo "  typeshed-fallback present"

rm -f "$STAGE/bin/node"
[ -L "$STAGE/bin/node" ] && { echo "ERROR: failed to remove stage node symlink" >&2; exit 1; }

echo "==> Packaging (tar.bz2) ..."
rm -f "$RUNTIME_DIR/pyright.tar.bz2"
tar cjf "$RUNTIME_DIR/pyright.tar.bz2" -C "$STAGE" bin lib 2>/dev/null \
    || tar -cf - -C "$STAGE" bin lib | "$BZIP2" >"$RUNTIME_DIR/pyright.tar.bz2"
chmod 644 "$RUNTIME_DIR/pyright.tar.bz2"
echo "  staged: $RUNTIME_DIR/pyright.tar.bz2 ($(du -h "$RUNTIME_DIR/pyright.tar.bz2" | cut -f1))"

echo ""
echo "Done."
echo ""
echo "Next:"
echo "  edit payload/packages.json: replace the pyright entry (kind bin + archive,"
echo "    depends [nodejs], sentinel bin/pyright, install_to ~/.local) -- see nodejs"
echo "    entry as the shape reference"
echo "  remove wheels/pyright-*.whl and wheels/nodeenv-*.whl from the wheelhouse"
echo "  ./build/strip-all-elf-binaries"
echo "  python3.14 build/gen-installed-sizes && python3.14 build/gen-content-manifest"
