#!/bin/sh
# Build prettier as a pure Node.js runtime archive for el8.x86_64.glibc2p28.
#
# prettier is the JavaScript/TypeScript/JSON/YAML/CSS formatter conform.nvim
# calls for the `javascript` filetype. It ships as a plain npm package with ZERO
# runtime dependencies (single entry point bin/prettier.cjs, engines.node >= 14),
# so unlike netlistsvg / typescript-language-server there is nothing to vendor
# alongside it: the tarball IS the whole thing.
#
# We run it directly on loadout's bundled Node.js (the nodejs package) through a
# tiny sh launcher -- no npm install, no node_modules, no runtime downloads.
# That is what makes the `javascript` formatter in envs/nvim work offline. Before
# this package existed the mapping named `prettier`/`prettierd` but neither was
# ever installed, so conform.nvim found no binary and silently fell through to
# lsp_format = "fallback" (see tests/nvim-formatters-resolve).
#
# conform's invocation matters: its built-in `prettier` formatter feeds the
# buffer on STDIN and passes `--stdin-filepath $FILENAME` -- it does NOT use
# `-`, which prettier rejects ("No files matching the pattern were found: -").
# The launcher must therefore exec the cjs entry point and let node read stdin.
# prettier infers the parser (js/ts/json/yaml/css) from that filename's
# extension, so nothing filetype-specific is needed here.
#
# Integrity: the tarball is verified against the sha512 dist.integrity the npm
# registry publishes for the exact version, pinned below.
#
# Usage (run from any directory, inside the EL8 build container):
#   ./build/build-prettier.sh --tag 3.8.1

set -eu

REPO="$(cd "$(dirname "$0")/.." && pwd)"
RUNTIME_DIR="$REPO/payload/el8.x86_64.glibc2p28/runtime"
PY=".loadout-bootstrap/bin/python3.14"
[ -x "$REPO/$PY" ] || PY="$(command -v python3.14 || command -v python3)"

# Pinned sha512 dist.integrity per version, as published by the npm registry.
case "$1" in
    --tag) version="${2:-}" ;;
    -h|--help) sed -n '2,/^Usage/p' "$0"; exit 0 ;;
    *) echo "usage: $0 --tag <version>" >&2; exit 2 ;;
esac
[ -n "$version" ] || { echo "ERROR: --tag <version> required" >&2; exit 2; }

case "$version" in
    3.8.1)
        INTEGRITY="sha512-UOnG6LftzbdaHZcKoPFtOcCKztrQ57WkHDeRD9t/PTQtmT0NHSeWWepj6pS0z/N7+08BHFDQVUrfmfMRcZwbMg=="
        ;;
    *)
        echo "ERROR: no pinned integrity for prettier $version" >&2
        echo "       look it up: curl -s https://registry.npmjs.org/prettier/$version | python3 -m json.tool | grep integrity" >&2
        exit 2
        ;;
esac

WORK_DIR=$(mktemp -d "${TMPDIR:-/var/tmp}/build-prettier-XXXXXX")
trap 'rm -rf "$WORK_DIR"' EXIT INT TERM

TARBALL_URL="https://registry.npmjs.org/prettier/-/prettier-${version}.tgz"

echo "==> Fetching prettier ${version} ..."
curl -fL -o "$WORK_DIR/prettier.tgz" "$TARBALL_URL" --retry 3 --retry-delay 2

# Recompute sha512 and compare against the registry's dist.integrity.
GOT="$("$PY" - "$WORK_DIR/prettier.tgz" <<'PYEOF'
import base64, hashlib, sys
print("sha512-" + base64.b64encode(hashlib.sha512(open(sys.argv[1], "rb").read()).digest()).decode())
PYEOF
)"
if [ "$GOT" != "$INTEGRITY" ]; then
    echo "ERROR: prettier tarball integrity mismatch" >&2
    echo "  expected $INTEGRITY" >&2
    echo "  got      $GOT" >&2
    exit 1
fi
echo "  integrity OK"

STAGE="$WORK_DIR/stage"
mkdir -p "$STAGE/lib/node_modules/prettier" "$STAGE/bin"

# npm tarballs are rooted at package/; netlistsvg's builder moves that level into
# node_modules/<pkg>, so do the same.
tar xzf "$WORK_DIR/prettier.tgz" -C "$WORK_DIR"
for f in bin/prettier.cjs package.json; do
    [ -f "$WORK_DIR/package/$f" ] || { echo "ERROR: $f missing in npm package" >&2; exit 1; }
done
cp -r "$WORK_DIR/package/." "$STAGE/lib/node_modules/prettier/"

# The launcher: prefix-derived node + the vendored cjs entry point, stdin/stdout
# passed straight through (conform feeds the buffer on stdin). No build step, no
# npm, no network. Same shape as the netlistsvg / ts_ls launchers.
cat > "$STAGE/bin/prettier" <<'LAUNCHER'
#!/bin/sh
# loadout prettier launcher -- prefix-derived, no embedded path.
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
prefix=$(CDPATH= cd -- "$here/.." && pwd -P)
exec "$prefix/bin/node" "$prefix/lib/node_modules/prettier/bin/prettier.cjs" "$@"
LAUNCHER
chmod 755 "$STAGE/bin/prettier"

# --- stage-verify: version, then the REAL stdin form conform uses -------------
# Node comes from the loadout `nodejs` package at INSTALL time, not from this
# archive, so the stage-verify resolves node from PATH (the bundled node when run
# on a loadout box or in the container) and exercises the launcher inside a
# throwaway prefix that has the same <prefix>/bin/node layout the installer
# produces. The archive itself only ships the launcher + vendored prettier.
NODE="$(command -v node || true)"
[ -n "$NODE" ] || { echo "ERROR: node not found on PATH; cannot stage-verify prettier" >&2; exit 1; }
echo "==> Stage-verify: --version"
echo "  using node: $NODE ($("$NODE" --version))"

# Fake install prefix with the layout the installer produces, so the launcher is
# exercised for real (it resolves <prefix>/bin/node + the vendored cjs).
FAKE="$WORK_DIR/fakeprefix"
mkdir -p "$FAKE/bin" "$FAKE/lib/node_modules"
cp -r "$STAGE/lib/node_modules/prettier" "$FAKE/lib/node_modules/prettier"
cp "$STAGE/bin/prettier" "$FAKE/bin/prettier"
ln -s "$NODE" "$FAKE/bin/node"
"$FAKE/bin/prettier" --version

echo "==> Stage-verify: stdin format (conform's --stdin-filepath form) ..."
cat > "$WORK_DIR/fixture.js" <<'FIXTURE'
const  x   =  {a:1,b:2}
function  f( ) {return   1}
FIXTURE
# Run it the way conform does: a real $FILENAME on argv (prettier infers the
# parser from its extension) with the buffer fed on stdin. The fixture is piped
# rather than redirected so the same path is not both an argument and an input
# redirect.
OUT=$(cat "$WORK_DIR/fixture.js" | "$FAKE/bin/prettier" --stdin-filepath "$WORK_DIR/fixture.js")
printf '%s\n' "$OUT"
case "$OUT" in
    *"const x = { a: 1, b: 2 };"*) : ;;
    *) echo "ERROR: prettier did not format the fixture as expected" >&2; exit 1 ;;
esac
# NEGATIVE: prettier must reject `-` (that is WHY conform uses --stdin-filepath).
# If a future version accepted it, the launcher's reasoning still holds (conform
# sends --stdin-filepath either way) but this note needs a look.
if cat "$WORK_DIR/fixture.js" | "$FAKE/bin/prettier" - >/dev/null 2>&1; then
    echo "NOTE: this prettier accepted a bare '-' argument; conform still sends" >&2
    echo "      --stdin-filepath, so the launcher is unaffected." >&2
fi
echo "  OK: launcher resolves its prefix and formats via stdin like conform"

echo "==> Packaging runtime archive ..."
tar cjf "$RUNTIME_DIR/prettier.tar.bz2" -C "$STAGE" ./bin ./lib
echo "  Wrote: $RUNTIME_DIR/prettier.tar.bz2 ($(wc -c < "$RUNTIME_DIR/prettier.tar.bz2" | tr -d ' ') bytes)"

echo ""
echo "Done. Produced:"
echo "  $RUNTIME_DIR/prettier.tar.bz2"
echo ""
echo "Registry entry (kind bin, depends nodejs, archive runtime/prettier.tar.bz2,"
echo "sentinel bin/prettier, install_to ~/.local, version $version)."
echo ""
echo "Reminders:"
echo "  - ./loadout completion bash > envs/bash/global/completions/loadout.bash"
echo "  - build/ADDING_BINARIES.md note is MANDATORY"
