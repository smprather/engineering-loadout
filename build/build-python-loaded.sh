#!/bin/sh
# build-python-loaded.sh -- regenerate the python-loaded lock + private wheelhouse.
#
# Runs entirely in AlmaLinux 8: resolution must see glibc 2.28 and cp315 only,
# and auditwheel must repair against EL8's libraries. There is no host fallback
# (spec D3): a machine without Docker cannot refresh the suite.
#
# Usage:
#   ./build/build-python-loaded.sh              # full build (network + Docker)
#   ./build/build-python-loaded.sh --print-plan # print the container plan only
#
# Outputs:
#   payload/python-loaded/requirements.lock.txt
#   payload/python-loaded/wheels/*.whl          (private, repaired)
#   payload/packages.json                       ("python-loaded".version = lock date)

set -eu

REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
PLATFORM_DIR="$REPO/payload/el8.x86_64.glibc2p28"
SUITE_DIR="$REPO/payload/python-loaded"
REQ_IN="$SUITE_DIR/requirements.in"
SDIST_ALLOW="$REPO/build/python-loaded-sdist-allowlist.txt"
CLI_ALLOW="$REPO/build/python-loaded-cli-allowlist.txt"
CONSTRAINTS="$REPO/build/python-loaded-constraints.txt"
OUT_WHEELS="$SUITE_DIR/wheels"
IMAGE="${LOADOUT_EL8_IMAGE:-almalinux:8.10}"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/engineering-loadout/python-loaded-build-v1"

PRINT_PLAN=0
case "${1:-}" in
    --print-plan) PRINT_PLAN=1 ;;
    "") ;;
    *) echo "usage: $0 [--print-plan]" >&2; exit 2 ;;
esac

PORTABLE_PYTHON=$(ls "$PLATFORM_DIR"/portable-python-*.tar.bz2 2>/dev/null | head -1 || true)
UV_BZ2="$PLATFORM_DIR/bin/uv.bz2"
UV_BIN_BZ2="$PLATFORM_DIR/bin/uv.bin.bz2"
for f in "$PORTABLE_PYTHON" "$UV_BZ2" "$UV_BIN_BZ2" "$REQ_IN" "$SDIST_ALLOW" "$CLI_ALLOW" "$CONSTRAINTS"; do
    [ -f "$f" ] || { echo "ERROR: missing required input: $f" >&2; exit 1; }
done

mkdir -p "$CACHE"
cat > "$CACHE/run.sh" <<'CONTAINER'
set -euo pipefail
trap 'echo "python-loaded build FAILED at line $LINENO" >&2' ERR

echo "== toolchain"
dnf -y -q install epel-release >/dev/null 2>&1 || true
dnf -y -q install bzip2 tar gzip which file make \
    gcc-toolset-14 gcc-toolset-14-gcc-c++ \
    openldap-devel cyrus-sasl-devel openssl-devel zlib-devel libffi-devel \
    patchelf >/dev/null
# shellcheck disable=SC1091
. /opt/rh/gcc-toolset-14/enable
# The portable build's sysconfig bakes /hostllvm/bin/clang-23 (absent here);
# sdist builds must use the EL8 toolchain, not the build-host compiler path.
export CC=gcc CXX=g++ LDSHARED="gcc -shared"
# GCC 14 promotes pre-C99 pointer mismatches to errors; pyeda's vendored
# espresso is old C that only needs a warning-level diagnostic.
export CFLAGS="-Wno-incompatible-pointer-types -Wno-implicit-function-declaration -Wno-int-conversion"

echo "== portable python"
mkdir -p /work/ppy /work/prefix /work/bin /work/prebuilt /work/dl /work/final /work/be
tar -xjf /work/portable-python.tar.bz2 -C /work/ppy
PPY_ROOT=$(find /work/ppy -maxdepth 1 -mindepth 1 -type d | head -1)
sh "$PPY_ROOT/install.sh" --prefix /work/prefix --force --no-test >/dev/null
/work/prefix/bin/python3 -V

echo "== uv"
bunzip2 -c /work/uv.bz2 > /work/bin/uv
bunzip2 -c /work/uv.bin.bz2 > /work/bin/uv.bin
chmod +x /work/bin/uv /work/bin/uv.bin
/work/bin/uv --version

echo "== build environment"
/work/bin/uv venv --seed --python /work/prefix/bin/python3 /work/be >/dev/null
BE=/work/be/bin
export PATH="$BE:$PATH"
"$BE/python" -m pip install -q --upgrade pip setuptools wheel
# EPEL8's patchelf (0.12) is too old for auditwheel; the PyPI `patchelf`
# package ships a current prebuilt binary into the venv, and auditwheel
# discovers it on PATH.
"$BE/python" -m pip install -q Cython auditwheel patchelf
"$BE/patchelf" --version

echo "== sdist allowlist"
while IFS= read -r name; do
    case "$name" in ''|'#'*) continue ;; esac
    echo "   building $name"
    "$BE/python" -m pip wheel --no-deps --no-build-isolation -w /work/prebuilt "$name"
done < /work/sdist-allowlist.txt

# Resolve with pip ON the real 3.15 interpreter: uv 0.13.1 mis-evaluates
# `python_version` markers for 3.15 (it pulls dataclasses and drops
# Requires-Python<3.15 packages as though the interpreter were 3.1.5).
# pip's resolver reads the running interpreter's markers, and the wheels it
# picks are exactly the cp315/EL8 ones the suite installs.
echo "== resolve + acquire (cp315 / glibc 2.28)"
"$BE/python" -m pip download --only-binary=:all: \
    --find-links /work/prebuilt -c /work/constraints.txt \
    -r /work/requirements.in -d /work/dl
echo "   downloaded $(ls /work/dl/*.whl 2>/dev/null | wc -l) wheels"

# A local sdist build can be pure Python yet carry a platform tag (pip's
# backend decides the tag before it knows there is no extension). auditwheel
# refuses those with "does not look like a platform wheel"; retag them instead
# of shipping an x86_64 tag that has no ELF to justify it.
cat > /work/retag_pure.py <<'PY'
import base64
import hashlib
import os
import sys
import zipfile

src, outdir = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(src) as zin:
    names = zin.namelist()
    if any(name.endswith((".so", ".pyd", ".dll")) for name in names):
        raise SystemExit(f"{src}: contains an ELF/extension; not a pure wheel")
    payload = {name: zin.read(name) for name in names}

wheel_info = [name for name in names if name.endswith(".dist-info/WHEEL")]
if len(wheel_info) != 1:
    raise SystemExit(f"{src}: no unique WHEEL metadata")
wheel_path = wheel_info[0]
lines = payload[wheel_path].decode("utf-8").splitlines()
kept = [line for line in lines if not line.startswith(("Tag:", "Root-Is-Purelib:"))]
kept.insert(1, "Root-Is-Purelib: true")
kept.append("Tag: py3-none-any")
payload[wheel_path] = ("\n".join(kept) + "\n").encode("utf-8")

fields = os.path.basename(src)[: -len(".whl")].split("-")
dist, version = fields[0], fields[1]

record_path = [name for name in names if name.endswith(".dist-info/RECORD")][0]
rows = []
for name in sorted(payload):
    if name == record_path:
        continue
    data = payload[name]
    digest = base64.urlsafe_b64encode(hashlib.sha256(data).digest()).rstrip(b"=").decode()
    rows.append(f"{name},sha256={digest},{len(data)}")
rows.append(f"{record_path},,")
payload[record_path] = ("\n".join(rows) + "\n").encode("utf-8")

dest = os.path.join(outdir, f"{dist}-{version}-py3-none-any.whl")
with zipfile.ZipFile(dest, "w", zipfile.ZIP_DEFLATED) as zout:
    for name in sorted(payload):
        zout.writestr(name, payload[name])
print(f"   retagged pure wheel: {os.path.basename(dest)}")
PY

echo "== repair (auditwheel)"
for wheel in /work/dl/*.whl; do
    base=$(basename "$wheel")
    case "$base" in
        *-py3-none-any.whl|*-py2.py3-none-any.whl)
            cp "$wheel" /work/final/
            ;;
        *-linux_x86_64.whl)
            # Locally built (sdist allowlist): must be retagged to manylinux,
            # or to py3-none-any when the build produced no extension.
            echo "   repairing $base"
            "$BE/auditwheel" repair --plat manylinux_2_28_x86_64 -w /work/final "$wheel" ||
                "$BE/python" /work/retag_pure.py "$wheel" /work/final
            ;;
        *)
            if "$BE/auditwheel" show "$wheel" | grep -q "external dependencies"; then
                echo "   repairing $base"
                "$BE/auditwheel" repair --plat manylinux_2_28_x86_64 -w /work/final "$wheel"
            else
                cp "$wheel" /work/final/
            fi
            ;;
    esac
done

echo "== platform + ABI policy"
"$BE/python" - <<'PY'
import glob
import os
import re
import sys

MAX_GLIBC = (2, 28)


def legal_platform(plat):
    for tag in plat.split("."):
        if tag == "any":
            return True
        match = re.fullmatch(r"manylinux_(\d+)_(\d+)_x86_64", tag)
        if match and (int(match.group(1)), int(match.group(2))) <= MAX_GLIBC:
            return True
        if re.fullmatch(r"manylinux(1|2010|2014)_x86_64", tag):
            return True
    return False


bad = []
for path in sorted(glob.glob("/work/final/*")):
    name = os.path.basename(path)
    if not name.endswith(".whl"):
        bad.append(f"{name}: source distribution")
        continue
    fields = name[: -len(".whl")].split("-")
    py, abi, plat = fields[-3], fields[-2], fields[-1]
    if not legal_platform(plat):
        bad.append(f"{name}: no EL8-legal platform tag ({plat})")
        continue
    abi_tags = abi.split(".")
    if abi == "none" and plat == "any":
        continue
    # Compressed tags such as `abi3.abi3t` include abi3; the free-threaded
    # variant simply also supports a build we never run.
    if "abi3" in abi_tags:
        continue
    if abi == "none" and "py3" in py.split("."):
        continue
    if py == "cp315" and "cp315" in abi_tags:
        continue
    bad.append(f"{name}: ABI tag {py}/{abi} is not cp315/abi3/py3")
if bad:
    print("\n".join(bad), file=sys.stderr)
    sys.exit(1)
print(f"   {len(glob.glob('/work/final/*.whl'))} wheels pass the EL8 platform+ABI policy")
PY

echo "== emit lock"
PY_ABI=$("$BE/python" -c 'import sys; print(sys.implementation.cache_tag)')
PY_VER=$("$BE/python" -c 'import platform; print(platform.python_version())')
"$BE/python" - "$LOADOUT_LOCK_DATE" "$PY_ABI" "$PY_VER" <<'PY'
import hashlib
import os
import sys

lock_date, py_abi, py_ver = sys.argv[1:4]
rows = []
for name in sorted(os.listdir("/work/final")):
    if not name.endswith(".whl"):
        continue
    parts = name[: -len(".whl")].split("-")
    dist = parts[0].replace("_", "-")
    version = parts[1]
    with open(os.path.join("/work/final", name), "rb") as fh:
        digest = hashlib.file_digest(fh, "sha256").hexdigest()
    rows.append((dist, version, digest))
rows.sort(key=lambda row: (row[0].lower(), row[1]))
with open("/work/requirements.lock.txt", "w", encoding="utf-8") as fh:
    fh.write(f"# python-loaded lock {lock_date}\n")
    fh.write(f"# abi: {py_abi}\n")
    fh.write(f"# python: {py_ver}\n")
    for dist, version, digest in rows:
        fh.write(f"{dist}=={version} --hash=sha256:{digest}\n")
print(f"   {len(rows)} pinned distributions")
PY

echo "== verify offline"
rm -rf /work/verify
/work/bin/uv venv --python /work/prefix/bin/python3 /work/verify >/dev/null
env -i HOME=/work PATH=/usr/bin:/bin \
    /work/bin/uv pip install --python /work/verify/bin/python \
    --offline --no-index --find-links /work/final --require-hashes --no-cache \
    -r /work/requirements.lock.txt >/dev/null
echo "   installed offline"

env -i HOME=/work PATH=/usr/bin:/bin /work/verify/bin/python - <<'PY'
import importlib
import sys

MAP = {
    "django": "django", "django-auth-ldap": "django_auth_ldap", "django-filter": "django_filters",
    "flask": "flask", "dash": "dash", "litestar": "litestar", "litestar-htmx": "litestar_htmx",
    "uvicorn": "uvicorn", "boto3": "boto3", "numpy": "numpy", "pandas": "pandas", "scipy": "scipy",
    "matplotlib": "matplotlib", "scikit-learn": "sklearn", "statsmodels": "statsmodels",
    "xgboost-cpu": "xgboost", "shapely": "shapely", "pyarrow": "pyarrow", "openpyxl": "openpyxl",
    "pikepdf": "pikepdf", "img2pdf": "img2pdf", "pillow": "PIL", "nltk": "nltk", "graphviz": "graphviz",
    "evidently": "evidently", "pylint": "pylint", "pylintfileheader": "pylintfileheader",
    "pydantic": "pydantic", "rich": "rich", "typer": "typer", "httpx": "httpx", "requests": "requests",
    "jsonschema": "jsonschema", "sqlobject": "sqlobject", "pymysql": "pymysql", "pyeda": "pyeda",
    "ruamel.yaml": "ruamel.yaml", "python-dotenv": "dotenv", "psutil": "psutil", "pexpect": "pexpect",
    "prettytable": "prettytable", "more-itertools": "more_itertools", "tenacity": "tenacity",
    "setproctitle": "setproctitle", "websockets": "websockets", "uvloop": "uvloop",
    "httptools": "httptools", "watchfiles": "watchfiles", "watchdog": "watchdog",
    "pyyaml": "yaml", "python-ldap": "ldap",
}
names = []
with open("/work/requirements.in", encoding="utf-8") as fh:
    for line in fh:
        line = line.strip()
        if line and not line.startswith("#"):
            names.append(line.lower())
missing = []
for name in names:
    module = MAP.get(name)
    if module is None:
        print(f"no module mapping for top {name}", file=sys.stderr)
        sys.exit(1)
    try:
        importlib.import_module(module)
    except Exception as exc:
        missing.append(f"{name} ({module}): {exc}")
if missing:
    print("\n".join(missing), file=sys.stderr)
    sys.exit(1)
print(f"   imported {len(names)} tops")
PY

echo "== shared objects"
find /work/verify -type f \( -name '*.so' -o -name '*.so.*' \) -print0 |
while IFS= read -r -d '' so; do
    if file "$so" | grep -q 'ELF'; then
        if ldd "$so" 2>/dev/null | grep -q 'not found'; then
            echo "UNRESOLVED: $so" >&2
            ldd "$so" | grep 'not found' >&2
            exit 1
        fi
    fi
done
echo "   every extension resolves"

echo "== console scripts"
# Some wheels ship `scripts/` files with a literal `#!/usr/bin/env python`
# (SQLObject does); uv copies those verbatim, so they would run the HOST
# interpreter on a deployed box. Point them at the venv.
"$BE/python" - <<'PY'
import os
import re

bin_dir = "/work/verify/bin"
pattern = re.compile(r"#!\s*(/usr/bin/env\s+python3?|/usr/bin/python3?|/usr/local/bin/python3?)")
for name in sorted(os.listdir(bin_dir)):
    path = os.path.join(bin_dir, name)
    if not os.path.isfile(path):
        continue
    with open(path, "rb") as fh:
        if fh.read(2) != b"#!":
            continue
    with open(path, encoding="utf-8", errors="replace") as fh:
        text = fh.read()
    first, sep, rest = text.partition("\n")
    if pattern.fullmatch(first.strip()):
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(f"#!{bin_dir}/python\n{rest}")
        os.chmod(path, 0o755)
        print(f"   rewrote shebang: {name}")
PY
for script in /work/verify/bin/*; do
    [ -f "$script" ] || continue
    head -c 2 "$script" | grep -q '#!' || continue
    [ -x "$script" ] || { echo "not executable: $script" >&2; exit 1; }
    head -1 "$script" | grep -q '/work/verify/bin/python' ||
        { echo "shebang does not name the venv: $script" >&2; exit 1; }
done
while IFS= read -r cli; do
    case "$cli" in ''|'#'*) continue ;; esac
    /work/verify/bin/"$cli" --help >/dev/null
done < /work/cli-allowlist.txt
echo "   console scripts and CLI allowlist OK"

echo "== publish"
rm -f /out/wheels/*.whl /out/wheels/*.whl.part-*
cp /work/final/*.whl /out/wheels/
cp /work/requirements.lock.txt /out/suite/requirements.lock.txt
echo "   $(ls /out/wheels | wc -l) wheels, $(du -sh /out/wheels | cut -f1)"
CONTAINER

if [ "$PRINT_PLAN" = 1 ]; then
    echo "docker run --rm -e LOADOUT_LOCK_DATE=<UTC date> $IMAGE bash /work/run.sh"
    sed -n '1,400p' "$CACHE/run.sh"
    exit 0
fi

command -v docker >/dev/null 2>&1 || {
    echo "ERROR: Docker is required to build python-loaded (EL8 resolution); no host fallback." >&2
    exit 1
}

mkdir -p "$OUT_WHEELS"
LOCK_DATE=$(date -u +%Y.%m.%d)
START=$(date +%s)

docker run --rm \
    -e LOADOUT_LOCK_DATE="$LOCK_DATE" \
    -v "$PORTABLE_PYTHON:/work/portable-python.tar.bz2:ro" \
    -v "$UV_BZ2:/work/uv.bz2:ro" \
    -v "$UV_BIN_BZ2:/work/uv.bin.bz2:ro" \
    -v "$REQ_IN:/work/requirements.in:ro" \
    -v "$SDIST_ALLOW:/work/sdist-allowlist.txt:ro" \
    -v "$CLI_ALLOW:/work/cli-allowlist.txt:ro" \
    -v "$CONSTRAINTS:/work/constraints.txt:ro" \
    -v "$CACHE/run.sh:/work/run.sh:ro" \
    -v "$SUITE_DIR:/out/suite" \
    -v "$OUT_WHEELS:/out/wheels" \
    -v "$CACHE:/cache" \
    "$IMAGE" bash /work/run.sh

ELAPSED=$(( $(date +%s) - START ))

python3 - "$REPO/payload/packages.json" "$LOCK_DATE" <<'PY'
import re
import sys

path, lock_date = sys.argv[1], sys.argv[2]
with open(path, encoding="utf-8") as fh:
    text = fh.read()
pattern = re.compile(r'("python-loaded":\s*\{.*?"version":\s*")[^"]*(")', re.S)
updated, count = pattern.subn(rf"\g<1>{lock_date}\g<2>", text, count=1)
if count != 1:
    raise SystemExit("could not update python-loaded version in packages.json")
with open(path, "w", encoding="utf-8") as fh:
    fh.write(updated)
print(f"python-loaded version -> {lock_date}")
PY

echo "python-loaded build completed in ${ELAPSED}s ($(ls "$OUT_WHEELS" | wc -l) wheels, $(du -sh "$OUT_WHEELS" | cut -f1))"
