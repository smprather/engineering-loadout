#!/bin/sh
# Build GNU Bash from source for el8.x86_64.glibc2p28.
#
# GNU ships only `bash-X.Y.tar.gz`; patchlevels live in `bash-X.Y-patches/` as
# `bashXY-NNN` files. The bundled version is base+patchlevel (e.g. 5.3.15 = 5.3
# release + patches 001..015). This script downloads the base tarball, applies
# every available patch in order, builds, and stamps packages.json to X.Y.<N>.
#
# Build characteristics matched to the existing bundle (verify after building):
#   - NEEDED: libtinfo.so.6, libdl.so.2, libc.so.6 (readline is built in -- bash's
#     default --with-installed-readline=no; no libreadline NEEDED).
#   - RUNPATH: $ORIGIN/../lib64:$ORIGIN/../lib (set via patchelf, post-strip).
#   - Plain `./configure` (no special flags) reproduces the above on EL8.
#
# Policy: build from the latest stable base release + all published patches.
#   https://ftp.gnu.org/gnu/bash/
#
# Prerequisites (EL8): gcc + make (gcc-toolset-14 recommended), patchelf at
# ~/.local/bin/patchelf, network to ftp.gnu.org (run outside the command sandbox).
#
# Usage (run from any directory):
#   /path/to/build-bash.sh --tag 5.3        # base release; applies all patches

set -eu

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
BIN_DIR="$REPO/pre_built/el8.x86_64.glibc2p28/bin"
PATCHELF="${HOME}/.local/bin/patchelf"
BASE_URL="https://ftp.gnu.org/gnu/bash"

base=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --tag)
            shift
            [ "$#" -gt 0 ] || { echo "missing value for --tag" >&2; exit 2; }
            base="$1"
            ;;
        -h|--help)
            sed -n '2,/^$/p' "$0"
            exit 0
            ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done

if [ -z "$base" ]; then
    echo "ERROR: --tag is required, e.g.: $0 --tag 5.3" >&2
    echo "  (the base X.Y release; all published patches are applied automatically)" >&2
    exit 1
fi

if [ -r /opt/rh/gcc-toolset-14/enable ]; then
    # shellcheck disable=SC1091
    . /opt/rh/gcc-toolset-14/enable
fi
command -v gcc >/dev/null 2>&1 || { echo "missing gcc" >&2; exit 1; }
[ -x "$PATCHELF" ] || { echo "missing patchelf at $PATCHELF" >&2; exit 1; }

WORK="/tmp/bash-build-${base}"
rm -rf "$WORK"
mkdir -p "$WORK"
cd "$WORK"

echo "Downloading bash-${base}.tar.gz ..."
curl -fsSL -o "bash-${base}.tar.gz" "${BASE_URL}/bash-${base}.tar.gz"
tar xzf "bash-${base}.tar.gz"
cd "bash-${base}"

# Apply every published patch in numeric order. patch files are bashXY-NNN,
# applied with `patch -p0` from the source root. Stop at the first gap.
compact="$(printf '%s' "$base" | tr -d '.')"
patch_dir_url="${BASE_URL}/bash-${base}-patches"
echo "Fetching + applying patches from ${patch_dir_url} ..."
maxpatch=0
i=1
while :; do
    nnn="$(printf '%03d' "$i")"
    pf="bash${compact}-${nnn}"
    if ! curl -fsSL -o "/tmp/${pf}" "${patch_dir_url}/${pf}" 2>/dev/null; then
        break
    fi
    patch -p0 < "/tmp/${pf}"
    rm -f "/tmp/${pf}"
    maxpatch="$i"
    i=$((i + 1))
done
echo "Applied patches 001..$(printf '%03d' "$maxpatch")"
ver="${base}.${maxpatch}"

echo "Configuring + building bash ${ver} ..."
./configure >/tmp/bash-configure.log 2>&1
make -j"$(nproc 2>/dev/null || echo 8)" >/tmp/bash-make.log 2>&1

[ -f bash ] || { echo "build did not produce ./bash" >&2; exit 1; }
echo "Built: $(./bash --version | head -1)"

strip bash
"$PATCHELF" --set-rpath '$ORIGIN/../lib64:$ORIGIN/../lib' bash
echo "NEEDED:"; readelf -d bash | grep NEEDED
bzip2 -kf bash
cp bash.bz2 "$BIN_DIR/bash.bz2"
chmod 644 "$BIN_DIR/bash.bz2"

# Stamp packages.json (key-anchored to the bash package, NOT a bare "bash" which
# also appears in depends/recommends lists).
python3 -c "
import re, sys
path, ver = sys.argv[1], sys.argv[2]
txt = open(path).read()
pat = r'(\"bash\":\s*\{.*?\"version\":\s*\")([^\"]+)(\")'
txt, n = re.subn(pat, r'\g<1>' + ver + r'\3', txt, count=1, flags=re.S)
assert n == 1, 'bash version stamp matched %d times' % n
open(path, 'w').write(txt)
print('packages.json: bash version -> ' + ver)
" "$REPO/pre_built/packages.json" "$ver"

echo "Running strip_all_elf_binaries ..."
"$REPO/strip_all_elf_binaries"

MAXG="$(readelf -V bash 2>/dev/null | grep -oE 'GLIBC_[0-9]+\.[0-9]+' | sort -V | tail -1)"
echo "Max glibc symbol: $MAXG (target <= GLIBC_2.28)"
echo "Installed: $BIN_DIR/bash.bz2  (bash ${ver})"
