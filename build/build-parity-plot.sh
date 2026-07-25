#!/usr/bin/env bash
# Build parity-plot + its locked Python 3.14/EL8 wheel closure.
#
# The upstream CLI is a Python package with a NiceGUI designer.  The loadout
# ships the full runtime dependency set because an offline install cannot fetch
# missing wheels later.
#
# There is NO loadout patch any more.  Through v0.6.0 we carried one that turned
# plotly's CDN reference into an inlined copy, so generated HTML renders
# air-gapped.  v0.7.0 adopted that natively and went further: `[output].plotlyjs`
# selects inline/cdn/directory/none, and a standalone document defaults to
# "inline" precisely so it opens with no network.  Upstream default == what we
# used to patch for, so the patch is gone rather than rewritten.  What guards the
# property now is behavioural, not textual: tests/install-parity-plot asserts the
# generated HTML embeds the plotly runtime and carries no CDN reference, so a
# future upstream default flip fails there instead of silently shipping.
#
# Usage:
#   build/build-parity-plot.sh --tag v0.7.0
#   build/build-parity-plot.sh --tag v0.7.0 --source /path/to/parity-plot

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLATFORM="el8.x86_64.glibc2p28"
WHEELS_DIR="$REPO/payload/$PLATFORM/wheels"
CLONE_URL="https://github.com/smprather/parity-plot.git"
PYVER="3.14"
CHUNK_BYTES=$((40 * 1024 * 1024))

tag=""
source_dir=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --tag)
            shift
            [ "$#" -gt 0 ] || { echo "missing value for --tag" >&2; exit 2; }
            tag="$1"
            ;;
        --source)
            shift
            [ "$#" -gt 0 ] || { echo "missing value for --source" >&2; exit 2; }
            source_dir="$1"
            ;;
        -h|--help)
            sed -n '2,/^$/p' "$0"
            exit 0
            ;;
        *)
            echo "unknown option: $1" >&2
            exit 2
            ;;
    esac
    shift
done
[ -n "$tag" ] || { echo "ERROR: --tag vX.Y.Z is required (stable upstream release)" >&2; exit 2; }

need() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "missing required command: $1" >&2
        exit 1
    }
}

need git
need uv
need pip3.14
need python3
need split

workdir="$(mktemp -d "${TMPDIR:-/tmp}/parity-plot-build.XXXXXX")"
trap 'rm -rf "$workdir"' EXIT

src="$workdir/src"
if [ -n "$source_dir" ]; then
    # Build from a disposable clone: the version stamp below rewrites
    # parity_plot/__init__.py, and that must never dirty the caller's checkout.
    source_dir="$(cd "$source_dir" && pwd)"
    git clone --no-checkout "$source_dir" "$src"
else
    git clone --depth 1 --branch "$tag" "$CLONE_URL" "$src"
fi
git -C "$src" checkout --detach "$tag"

version="$(git -C "$src" describe --exact-match --tags)"
version_number="${version#v}"
echo "Building parity-plot $version from $src"
python3 - "$src/parity_plot/__init__.py" "$version_number" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
version = sys.argv[2]
text = path.read_text(encoding="utf-8")
text, count = re.subn(r'__version__ = "[^"]+"', f'__version__ = "{version}"', text, count=1)
if count != 1:
    raise SystemExit(f"could not rewrite {path}")
path.write_text(text, encoding="utf-8")
PY

mkdir -p "$workdir/dist" "$workdir/deps" "$WHEELS_DIR"
uv build --wheel --out-dir "$workdir/dist" "$src"

# Use upstream's lockfile.  The project itself is built above; this export
# supplies runtime dependencies, but no test dependencies.  If a release tag has
# stale lock metadata, refresh it only in the disposable checkout.  Target tags
# ensure every binary wheel remains EL8-capable.
(
    cd "$src"
    if ! uv export --locked --no-dev --no-emit-project \
        --output-file "$workdir/requirements.txt" >/dev/null; then
        echo "Upstream lock is stale for $version; refreshing it in the disposable checkout." >&2
        uv lock
        uv export --locked --no-dev --no-emit-project \
            --output-file "$workdir/requirements.txt" >/dev/null
    fi
)
download_args=(
    --require-hashes --no-deps
    -r "$workdir/requirements.txt"
    --dest "$workdir/deps"
    --platform manylinux_2_28_x86_64
    --platform manylinux2014_x86_64
    --platform manylinux_2_17_x86_64
    --platform manylinux_2_5_x86_64
    --platform any
    --python-version "$PYVER"
    --implementation cp
    --abi cp314
    --only-binary :all:
)

# Rebuilding the project wheel must work completely offline when the lock's
# already-vendored closure is still current.  A changed lock falls back to the
# index, where hashes still make the refresh reproducible.
if ! PIP_REQUIRE_VIRTUALENV=0 pip3.14 download \
    "${download_args[@]}" --no-index --find-links "$WHEELS_DIR"; then
    echo "Vendored wheel closure is incomplete; refreshing locked dependencies from the index." >&2
    PIP_REQUIRE_VIRTUALENV=0 pip3.14 download "${download_args[@]}"
fi

# Only parity-plot's own wheel is safe to prune: dependency wheels are shared
# by other independently installable Python tools.
rm -f "$WHEELS_DIR"/parity_plot-*.whl "$WHEELS_DIR"/parity_plot-*.whl.part-*
shopt -s nullglob
incoming=("$workdir/dist"/*.whl "$workdir/deps"/*.whl)
[ "${#incoming[@]}" -gt 0 ] || { echo "no wheels built/downloaded" >&2; exit 1; }
printf '%s\n' "${incoming[@]##*/}" > "$workdir/wheel-names.txt"

for source_wheel in "${incoming[@]}"; do
    dest="$WHEELS_DIR/$(basename "$source_wheel")"
    cp "$source_wheel" "$dest"
    if [ "$(stat -c %s "$dest")" -gt "$CHUNK_BYTES" ]; then
        rm -f "$dest".part-*
        split -d -a 3 -b "$CHUNK_BYTES" "$dest" "$dest".part-
        rm -f "$dest"
    fi
done

# Keep registry metadata truthful after a rebuild.  Wheel filenames normalize
# distribution dashes to underscores, so turn them back into package names for
# human-facing `loadout info` output.
python3 - "$REPO/payload/packages.json" "$version" "$workdir/wheel-names.txt" <<'PY'
import json
import sys

path, version, names_path = sys.argv[1:]
with open(names_path, encoding="utf-8") as fh:
    wheels = sorted({line.strip().split("-", 1)[0].replace("_", "-") for line in fh if line.strip()})
with open(path, encoding="utf-8") as fh:
    data = json.load(fh)
entry = data["packages"]["parity-plot"]
entry["version"] = version
entry["wheels"] = wheels
with open(path, "w", encoding="utf-8") as fh:
    json.dump(data, fh, indent=2, ensure_ascii=True)
    fh.write("\n")
print(f"packages.json: parity-plot version -> {version}; {len(wheels)} wheel distributions")
PY

echo
echo "Built offline parity-plot wheel closure. Next:"
echo "  ./loadout completion bash > envs/bash/global/completions/loadout.bash"
echo "  ./build/gen-content-manifest"
echo "  ./tests/install-parity-plot"
