#!/bin/sh
# build-pyyaml.sh -- build the PURE-PYTHON PyYAML wheel this wheelhouse ships.
#
# WHY THIS SCRIPT EXISTS (issue #15). PyPI publishes no cp315 wheel for PyYAML
# and no universal `py3-none-any` one either (6.0.3 ships cp38..cp314 + sdists).
# `uvicorn[standard]` declares `pyyaml>=5.1`, so every FastAPI/uvicorn front end
# -- liberty-view (liberty-tools), ir-drop-viewer, ... -- pulls PyYAML, and
# under the shipped 3.15 interpreter the bundled wheel is the ONLY offline
# source. Without it the closure does not resolve and the tool cannot install.
# Until this script the wheel was load-bearing and unreproducible: nothing in
# build/ said where it came from or how to refresh it for a CVE.
#
# WHAT IT BUILDS: the no-libyaml, no-C variant. That is the trade-off the
# wheelhouse already made deliberately -- `yaml.__with_libyaml__ == False`, but
# the wheel is ABI-free and survives an interpreter minor bump, which a
# cp315-ABI-locked one would not.
#
# VERIFIED RECIPE (matches the shipped wheel file-for-file: same 23 entries,
# same `Generator: setuptools (84.2.1)`, same `Tag: py3-none-any`, same
# pure-Python `_yaml/__init__.py` shim, 45450 bytes on PyPI's sdist).
# Two dead ends, recorded so nobody re-derives them:
#   * `pip wheel --no-binary :all: PyYAML==<v>` FAILS: the sdist's
#     build-system.requires pins Cython>=3.0 for py3.13+, Cython has no 3.15
#     wheel, so pip tries to build Cython from source and dies.
#   * `pip wheel --no-build-isolation` FAILS with `BackendUnavailable: Cannot
#     import '_pyyaml_pep517'` -- that shim lives in `packaging/_pyyaml_pep517.py`
#     and is only importable through `backend-path`.
# `setup.py bdist_wheel` sidesteps both, which is why it is the recipe below.
#
# USAGE (inside the EL8 build container -- it owns the bzip2/wheelhouse rules):
#   build/build-shell build/build-pyyaml.sh --version 6.0.3
#   build/build-shell build/build-pyyaml.sh --version 6.0.3 --sdist /cache/PyYAML-6.0.3.tar.gz
#
# Needs network only to fetch the sdist (or `--sdist` a file you already have).
# The built wheel is copied into the shared wheelhouse; if a copy also exists in
# payload/python-loaded/wheels/, the python-loaded LOCK pins that file's sha256,
# so the script refuses to overwrite it and tells you to re-lock instead.

set -eu

REPO=$(cd "$(dirname "$0")/.." && pwd)
VERSION=""
SDIST=""
PY="${PY:-python3.15}"

usage() {
    echo "usage: build/build-pyyaml.sh --version <x.y.z> [--sdist FILE] [--python INTERP]" >&2
    exit 2
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --version) VERSION=${2:-}; shift 2 ;;
        --sdist) SDIST=${2:-}; shift 2 ;;
        --python) PY=${2:-}; shift 2 ;;
        -h | --help) usage ;;
        *) echo "unknown option: $1" >&2; usage ;;
    esac
done
[ -n "$VERSION" ] || usage
command -v "$PY" >/dev/null 2>&1 || {
    echo "ERROR: $PY not on PATH (it is the payload interpreter this wheel must install under)" >&2
    exit 1
}

PLATFORM_DIR=
for d in "$REPO"/payload/el8.*/; do
    [ -d "$d" ] || continue
    PLATFORM_DIR=${d%/}
    break
done
[ -n "$PLATFORM_DIR" ] || {
    echo "ERROR: no payload/el8.* platform dir" >&2
    exit 1
}
WHEELS="$PLATFORM_DIR/wheels"
[ -d "$WHEELS" ] || {
    echo "ERROR: $WHEELS is missing" >&2
    exit 1
}

work=$(mktemp -d "${TMPDIR:-/tmp}/pyyaml-build.XXXXXX")
trap 'rm -rf "$work"' EXIT

if [ -z "$SDIST" ]; then
    url="https://files.pythonhosted.org/packages/source/P/PyYAML/PyYAML-${VERSION}.tar.gz"
    echo "Fetching $url"
    SDIST="$work/PyYAML-${VERSION}.tar.gz"
    "$PY" - "$url" "$SDIST" <<'EOF'
import sys
import urllib.request

url, dest = sys.argv[1], sys.argv[2]
with urllib.request.urlopen(url, timeout=120) as r, open(dest, "wb") as fh:
    while True:
        chunk = r.read(1 << 20)
        if not chunk:
            break
        fh.write(chunk)
print("  downloaded", dest)
EOF
fi
[ -f "$SDIST" ] || {
    echo "ERROR: sdist not found: $SDIST" >&2
    exit 1
}

tar -xzf "$SDIST" -C "$work"
src=$(find "$work" -maxdepth 1 -type d -name 'PyYAML-*' | head -1)
[ -n "$src" ] || {
    echo "ERROR: the sdist did not unpack a PyYAML-* directory" >&2
    exit 1
}

echo "Building the pure-Python wheel (no libyaml, no C extension)"
(
    cd "$src"
    PYYAML_FORCE_LIBYAML=0 PYYAML_FORCE_YAML=0 "$PY" setup.py -q bdist_wheel --dist-dir "$work/dist"
)

wheel="$work/dist/pyyaml-${VERSION}-py3-none-any.whl"
[ -f "$wheel" ] || {
    echo "ERROR: expected $wheel -- build produced:" >&2
    ls -1 "$work/dist" >&2
    exit 1
}

# The three properties this wheel is relied on for: pure python, correct tag,
# and a working `yaml` import without libyaml.
"$PY" - "$wheel" <<'EOF'
import sys
import zipfile

wheel = sys.argv[1]
with zipfile.ZipFile(wheel) as zf:
    names = zf.namelist()
    if any(n.endswith(".so") for n in names):
        raise SystemExit("ERROR: wheel contains a compiled extension -- not the pure-Python variant")
    if "_yaml/__init__.py" not in names:
        raise SystemExit("ERROR: wheel lacks the pure-Python _yaml shim")
    print(f"  {len(names)} files, no .so, _yaml shim present")
EOF
"$PY" - "$wheel" <<'EOF'
import sys
import zipfile

wheel = sys.argv[1]
sys.path.insert(0, wheel)  # zipimport: import straight from the wheel
import yaml  # noqa: E402

print(f"  yaml {yaml.__version__} (libyaml={yaml.__with_libyaml__}), safe_load ok: {yaml.safe_load('a: [1, 2]')}")
if yaml.__with_libyaml__:
    raise SystemExit("ERROR: the build picked up libyaml -- it must stay pure python")
EOF

name=$(basename "$wheel")
dest="$WHEELS/$name"
cp2_loaded="$REPO/payload/python-loaded/wheels/$name"

if [ -f "$cp2_loaded" ]; then
    # The python-loaded suite's lock pins that file by sha256; replacing it
    # without re-locking would make `tests/python-suite` fail (by design).
    want=$(sha256sum "$cp2_loaded" | cut -d' ' -f1)
    got=$(sha256sum "$wheel" | cut -d' ' -f1)
    if [ "$want" != "$got" ]; then
        echo "WARNING: payload/python-loaded/wheels/$name is pinned by" >&2
        echo "         payload/python-loaded/requirements.lock.txt (sha256 $want)." >&2
        echo "         The new wheel hashes $got -- re-lock the suite" >&2
        echo "         (build/build-python-loaded.sh) or keep the pinned copy." >&2
        echo "         The shared wheelhouse copy IS updated." >&2
    fi
fi

cp "$wheel" "$dest"
echo "Installed $dest"
echo "Next: python3.15 build/gen-installed-sizes && python3.15 build/gen-content-manifest"
