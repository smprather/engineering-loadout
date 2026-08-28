#!/bin/sh
# Build typescript-language-server as a pure Node.js runtime archive for
# el8.x86_64.glibc2p28.
#
# Produces:
#   payload/el8.x86_64.glibc2p28/runtime/typescript-language-server.tar.bz2
#     bin/typescript-language-server
#       sh wrapper -> bundled node + lib/node_modules/typescript-language-server/lib/cli.mjs
#     lib/node_modules/typescript-language-server/  (upstream npm package)
#     lib/node_modules/typescript/                  (tsserver/TypeScript package)
#
# Why bundle TypeScript too: upstream typescript-language-server is only the
# LSP shim. It wraps tsserver, which comes from the `typescript` npm package.
# The loadout archive must be self-contained and offline, so both npm tarballs
# are fetched, integrity-checked, staged, and smoked together.
#
# Usage:
#   ./build/build-typescript-language-server.sh --tag 6.0.0
#   ./build/build-typescript-language-server.sh --tag 6.0.0 --typescript-tag 6.0.3

set -eu

REPO="$(cd "$(dirname "$0")/.." && pwd)"
RUNTIME_DIR="$REPO/payload/el8.x86_64.glibc2p28/runtime"
TAG=""
TYPESCRIPT_TAG="6.0.3"

while [ "$#" -gt 0 ]; do
    case "$1" in
        --tag)
            shift
            [ "$#" -gt 0 ] || { echo "missing value for --tag" >&2; exit 2; }
            TAG="$1"
            ;;
        --typescript-tag)
            shift
            [ "$#" -gt 0 ] || { echo "missing value for --typescript-tag" >&2; exit 2; }
            TYPESCRIPT_TAG="$1"
            ;;
        -h|--help) sed -n '2,/^$/p' "$0"; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done

if [ -z "$TAG" ]; then
    echo "ERROR: --tag is required, e.g.: $0 --tag 6.0.0" >&2
    echo "Releases: https://www.npmjs.com/package/typescript-language-server?activeTab=versions" >&2
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

WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/build-typescript-language-server-XXXXXX")
trap 'rm -rf "$WORK_DIR"' EXIT INT TERM

fetch_npm() {
    pkg="$1"
    version="$2"
    out="$3"
    meta="$WORK_DIR/${pkg}-${version}.json"
    tgz="$WORK_DIR/${pkg}-${version}.tgz"

    echo "==> Fetching npm registry metadata for $pkg@$version ..."
    curl -fsSL -o "$meta" "https://registry.npmjs.org/$pkg/$version" --retry 3 --retry-delay 2

    eval "$($PY - "$meta" <<'PYEOF'
import json
import shlex
import sys

meta = json.load(open(sys.argv[1]))
dist = meta["dist"]
integrity = dist.get("integrity", "")
algo, _, b64 = integrity.partition("-")
print("TARBALL_URL=" + shlex.quote(dist["tarball"]))
print("INTEGRITY_ALGO=" + shlex.quote(algo))
print("INTEGRITY_B64=" + shlex.quote(b64))
PYEOF
)"
    [ -n "${TARBALL_URL:-}" ] || { echo "ERROR: no tarball URL in registry metadata" >&2; exit 1; }

    echo "==> Downloading $TARBALL_URL ..."
    curl -fL -o "$tgz" "$TARBALL_URL" --retry 3 --retry-delay 2

    [ -n "${INTEGRITY_B64:-}" ] || { echo "ERROR: no dist.integrity for $pkg@$version" >&2; exit 1; }
    echo "==> Verifying $pkg@$version $INTEGRITY_ALGO integrity ..."
    case "$INTEGRITY_ALGO" in
        sha512)
            GOT=$(openssl dgst -sha512 -binary "$tgz" | openssl base64 -A)
            [ "$GOT" = "$INTEGRITY_B64" ] || {
                echo "ERROR: sha512 mismatch for $pkg@$version" >&2
                echo "       expected $INTEGRITY_B64" >&2
                echo "       got      $GOT" >&2
                exit 1
            }
            echo "  integrity OK"
            ;;
        *)
            echo "ERROR: unsupported integrity algo '$INTEGRITY_ALGO' for $pkg@$version" >&2
            exit 1
            ;;
    esac

    mkdir -p "$out"
    tar xzf "$tgz" -C "$out"
    [ -f "$out/package/package.json" ] || { echo "ERROR: $pkg/package.json missing after extract" >&2; exit 1; }
    NPM_VER=$($PY -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$out/package/package.json")
    [ "$NPM_VER" = "$version" ] || {
        echo "ERROR: $pkg declares version '$NPM_VER' but requested $version" >&2
        exit 1
    }
}

fetch_npm "typescript-language-server" "$TAG" "$WORK_DIR/tls"
fetch_npm "typescript" "$TYPESCRIPT_TAG" "$WORK_DIR/typescript"

TLS_PKG="$WORK_DIR/tls/package"
TS_PKG="$WORK_DIR/typescript/package"
CLI_PATH=$($PY - "$TLS_PKG/package.json" <<'PYEOF'
import json
import sys

pkg = json.load(open(sys.argv[1]))
bin_map = pkg.get("bin", {})
if isinstance(bin_map, dict):
    cli = bin_map.get("typescript-language-server", "")
else:
    cli = str(bin_map)
if not cli:
    raise SystemExit("no typescript-language-server bin in package.json")
print(cli)
PYEOF
)
CLI_PATH=${CLI_PATH#./}
[ -f "$TLS_PKG/$CLI_PATH" ] || { echo "ERROR: CLI path missing: $CLI_PATH" >&2; exit 1; }
[ -f "$TS_PKG/lib/tsserver.js" ] || { echo "ERROR: TypeScript tsserver.js missing" >&2; exit 1; }
[ -f "$TS_PKG/lib/tsc.js" ] || { echo "ERROR: TypeScript tsc.js missing" >&2; exit 1; }

# Guard: both packages must be pure JS/data. Any ELF here would bypass the
# strip/patchelf path and needs a different packaging plan.
ELF_HITS=$(find "$TLS_PKG" "$TS_PKG" -type f | while IFS= read -r f; do
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
mv "$TLS_PKG" "$STAGE/lib/node_modules/typescript-language-server"
mv "$TS_PKG" "$STAGE/lib/node_modules/typescript"

cat >"$STAGE/bin/typescript-language-server" <<WRAPPER
#!/bin/sh
# loadout wrapper: typescript-language-server on loadout's bundled Node.js.
# Executes node by absolute path, so GUI-launched nvim and env-only shells do
# not need PATH setup beyond this wrapper.
PREFIX=\$(CDPATH= cd -- "\$(dirname -- "\$0")/.." && pwd)
exec "\$PREFIX/bin/node" "\$PREFIX/lib/node_modules/typescript-language-server/$CLI_PATH" "\$@"
WRAPPER
chmod 755 "$STAGE/bin/typescript-language-server"

NODE_BIN="$HOME/.local/bin/node"
[ -x "$NODE_BIN" ] || NODE_BIN="$(command -v node || true)"
[ -n "$NODE_BIN" ] || { echo "ERROR: no node found to stage-verify against" >&2; exit 1; }
echo "==> Stage-verify with $($NODE_BIN --version) ..."
ln -s "$NODE_BIN" "$STAGE/bin/node"

VER_OUT=$("$STAGE/bin/typescript-language-server" --version)
[ "$VER_OUT" = "$TAG" ] || {
    echo "ERROR: wrapper reports '$VER_OUT', expected '$TAG'" >&2
    exit 1
}
echo "  typescript-language-server --version: $VER_OUT"

TS_OUT=$("$NODE_BIN" "$STAGE/lib/node_modules/typescript/lib/tsc.js" --version)
[ "$TS_OUT" = "Version $TYPESCRIPT_TAG" ] || {
    echo "ERROR: TypeScript reports '$TS_OUT', expected 'Version $TYPESCRIPT_TAG'" >&2
    exit 1
}
echo "  bundled TypeScript: $TS_OUT"

"$PY" - "$STAGE/bin/typescript-language-server" "$WORK_DIR/lsp-out.txt" <<'PYEOF'
import os
import select
import time
import json
import subprocess
import sys

cmd = sys.argv[1]
out_path = sys.argv[2]
captured = bytearray()

def frame(payload):
    body = json.dumps(payload, separators=(",", ":")).encode("utf-8")
    return b"Content-Length: %d\r\n\r\n" % len(body) + body

proc = subprocess.Popen(
    [cmd, "--stdio"],
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
)

def write(payload):
    assert proc.stdin is not None
    proc.stdin.write(frame(payload))
    proc.stdin.flush()

def saw_id(req_id):
    compact = b'"id":%d' % req_id
    spaced = b'"id": %d' % req_id
    return compact in captured or spaced in captured

def drain_until(req_id, timeout):
    assert proc.stdout is not None
    deadline = time.monotonic() + timeout
    fd = proc.stdout.fileno()
    while time.monotonic() < deadline:
        if saw_id(req_id):
            return True
        if proc.poll() is not None:
            break
        ready, _, _ = select.select([fd], [], [], 0.1)
        if ready:
            chunk = os.read(fd, 65536)
            if not chunk:
                break
            captured.extend(chunk)
    return saw_id(req_id)

write(
    {
        "jsonrpc": "2.0",
        "id": 1,
        "method": "initialize",
        "params": {
            "processId": None,
            "rootUri": None,
            "capabilities": {},
            "clientInfo": {"name": "loadout-smoke"},
        },
    }
)
ok1 = drain_until(1, 15)
write({"jsonrpc": "2.0", "method": "initialized", "params": {}})
write({"jsonrpc": "2.0", "id": 2, "method": "shutdown", "params": None})
ok2 = drain_until(2, 15)
write({"jsonrpc": "2.0", "method": "exit", "params": None})
if proc.stdin is not None:
    proc.stdin.close()
try:
    rc = proc.wait(timeout=5)
except subprocess.TimeoutExpired:
    proc.kill()
    rc = proc.wait(timeout=5)
stderr = proc.stderr.read() if proc.stderr is not None else b""
open(out_path, "wb").write(bytes(captured) + b"\n--- stderr ---\n" + stderr)
if not ok1 or not ok2 or rc not in (0, None):
    sys.stderr.buffer.write(bytes(captured) + b"\n--- stderr ---\n" + stderr + b"\n")
    raise SystemExit(proc.returncode or 1)
PYEOF
echo "  LSP initialize/shutdown: OK"

rm -f "$STAGE/bin/node"
[ -L "$STAGE/bin/node" ] && { echo "ERROR: failed to remove stage node symlink" >&2; exit 1; }

echo "==> Packaging (tar.bz2) ..."
rm -f "$RUNTIME_DIR/typescript-language-server.tar.bz2"
tar cjf "$RUNTIME_DIR/typescript-language-server.tar.bz2" -C "$STAGE" bin lib 2>/dev/null \
    || tar -cf - -C "$STAGE" bin lib | "$BZIP2" >"$RUNTIME_DIR/typescript-language-server.tar.bz2"
chmod 644 "$RUNTIME_DIR/typescript-language-server.tar.bz2"
echo "  staged: $RUNTIME_DIR/typescript-language-server.tar.bz2 ($(du -h "$RUNTIME_DIR/typescript-language-server.tar.bz2" | cut -f1))"

echo ""
echo "Done."
echo ""
echo "Next:"
echo "  ./build/strip-all-elf-binaries"
echo "  python3.14 build/gen-installed-sizes"
echo "  python3.14 build/gen-content-manifest"
