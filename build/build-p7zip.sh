#!/bin/sh
# Build p7zip (Unix port of 7-Zip) from source for el8.x86_64.glibc2p28.
#
# Produces the standalone `7za` binary -- no shared-lib plugin (.so) needed.
# 7za includes LZMA/LZMA2, Deflate, BZip2, PPMD, 7z, zip, gzip, bzip2, tar,
# cab, arj, etc. It links only against system libs (libc, libm, libstdc++,
# libgcc_s, libpthread) that are always present on EL8.
#
# p7zip releases are distributed via SourceForge (project stalled at 16.02):
#   https://sourceforge.net/projects/p7zip/files/p7zip/
# Version is a plain dotted number: 16.02
#
# GCC compatibility patches applied for 16.02 + GCC 14:
#   1. makefile.machine: add -Wno-narrowing to OPTFLAGS (HRESULT enum narrowing)
#   2. CPP/7zip/Archive/7z/7zUpdate.cpp: us2fs(ui.Name) for CInFile::Open arg
#   3. CPP/7zip/Common/FileStreams.h: add SetTime/SetMTime stubs for !USE_WIN_FILE
#
# Note: do NOT pass LOCAL_FLAGS on the make command line -- it overrides the
# makefile.list definition that includes -DUNIX_USE_WIN_FILE and other required
# defines. All flags belong in makefile.machine's OPTFLAGS instead.
#
# Policy: always build from a stable tagged release.
#
# Prerequisites on the build machine (EL8):
#   dnf install gcc gcc-c++ make
#
# Usage (run from any directory):
#   ./build/build-p7zip.sh --tag 16.02

set -eu

REPO="$(cd "$(dirname "$0")/.." && pwd)"
BIN_DIR="$REPO/payload/el8.x86_64.glibc2p28/bin"
TAG=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        --tag)
            shift
            [ "$#" -gt 0 ] || { echo "missing value for --tag" >&2; exit 2; }
            TAG="$1"
            ;;
        -h|--help)
            sed -n '2,/^$/p' "$0"
            exit 0
            ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done

if [ -z "$TAG" ]; then
    echo "ERROR: --tag is required. Specify a stable release tag, e.g.:" >&2
    echo "  $0 --tag 16.02" >&2
    echo "" >&2
    echo "Stable releases: https://sourceforge.net/projects/p7zip/files/p7zip/" >&2
    echo "" >&2
    echo "Policy: this project ships stable releases only." >&2
    exit 1
fi

VERSION="$TAG"

if [ -r /opt/rh/gcc-toolset-14/enable ]; then
    # shellcheck disable=SC1091
    . /opt/rh/gcc-toolset-14/enable
fi

need() {
    command -v "$1" >/dev/null 2>&1 || {
        printf 'missing required command: %s\n' "$1" >&2
        exit 1
    }
}

need gcc
need g++
need make

WORK_DIR=$(mktemp -d /tmp/build-p7zip-XXXXXX)
trap 'rm -rf "$WORK_DIR"' EXIT

echo "==> Downloading p7zip_${VERSION}_src_all.tar.bz2 ..."
curl -fL -o "$WORK_DIR/p7zip.tar.bz2" \
    "https://sourceforge.net/projects/p7zip/files/p7zip/${VERSION}/p7zip_${VERSION}_src_all.tar.bz2/download" \
    --retry 3 --retry-delay 2

echo "==> Extracting ..."
tar xjf "$WORK_DIR/p7zip.tar.bz2" -C "$WORK_DIR"
cd "$WORK_DIR/p7zip_${VERSION}"

echo "==> Selecting platform config (linux_amd64, no yasm required) ..."
# makefile.machine is included by makefile.common; platform-specific settings go here.
# Use linux_amd64 (non-ASM) -- yasm not in base EL8 and ASM gives no significant benefit.
# Add -Wno-narrowing: HRESULT enum constants produce narrowing warnings with GCC >= 7.
cp makefile.linux_amd64 makefile.machine
sed -i 's/^OPTFLAGS=-O -s$/OPTFLAGS=-O -s -Wno-narrowing/' makefile.machine

echo "==> Applying GCC 14 compatibility patches ..."

# Patch 1: 7zUpdate.cpp -- CInFile::Open() takes CFSTR (const char*) but ui.Name
# is UString (wchar_t-based). Was implicit-convertible in older GCC, rejected in GCC14.
sed -i 's/if (file\.Open(ui\.Name))/if (file.Open(us2fs(ui.Name)))/' \
    CPP/7zip/Archive/7z/7zUpdate.cpp

# Patch 2: FileStreams.h -- SetTime/SetMTime are #ifdef USE_WIN_FILE but called
# unconditionally. When UNIX_USE_WIN_FILE is defined (makefile.list sets it for 7za)
# USE_WIN_FILE is active and these are already defined; the stubs handle the !WIN case
# (e.g. if building without UNIX_USE_WIN_FILE).
python3 - <<'PYEOF'
import sys
path = 'CPP/7zip/Common/FileStreams.h'
with open(path) as f:
    content = f.read()
old = (
    '  #ifdef USE_WIN_FILE\n'
    '  bool SetTime(const FILETIME *cTime, const FILETIME *aTime, const FILETIME *mTime)\n'
    '  {\n'
    '    return File.SetTime(cTime, aTime, mTime);\n'
    '  }\n'
    '  bool SetMTime(const FILETIME *mTime) {  return File.SetMTime(mTime); }\n'
    '  #endif'
)
new = (
    '  #ifdef USE_WIN_FILE\n'
    '  bool SetTime(const FILETIME *cTime, const FILETIME *aTime, const FILETIME *mTime)\n'
    '  {\n'
    '    return File.SetTime(cTime, aTime, mTime);\n'
    '  }\n'
    '  bool SetMTime(const FILETIME *mTime) {  return File.SetMTime(mTime); }\n'
    '  #else\n'
    '  bool SetTime(const FILETIME *, const FILETIME *, const FILETIME *) { return true; }\n'
    '  bool SetMTime(const FILETIME *) { return true; }\n'
    '  #endif'
)
if old not in content:
    print('WARNING: FileStreams.h patch target not found -- may already be patched or source changed')
    sys.exit(0)
content = content.replace(old, new)
with open(path, 'w') as f:
    f.write(content)
print('FileStreams.h patched')
PYEOF

echo "==> Building 7za (standalone binary) ..."
# Do NOT pass LOCAL_FLAGS= here -- doing so overrides makefile.list's LOCAL_FLAGS
# which contains -DUNIX_USE_WIN_FILE and other required defines for the 7za bundle.
make -j"$(nproc 2>/dev/null || echo 2)" 7za

P7ZA_BIN="$WORK_DIR/p7zip_${VERSION}/bin/7za"
if [ ! -f "$P7ZA_BIN" ]; then
    echo "ERROR: 7za binary not found at $P7ZA_BIN after build" >&2
    exit 1
fi

echo "==> Verifying binary ..."
VER_OUT=$("$P7ZA_BIN" i 2>&1 | head -3)
echo "$VER_OUT"
echo "$VER_OUT" | grep -qi "7-zip\|version\|p7zip" || {
    echo "WARNING: unexpected output from '7za i'" >&2
}

echo "==> Checking runtime library requirements ..."
ldd "$P7ZA_BIN" | grep -v "linux-vdso\|ld-linux" | awk '{print "  " $0}'

echo "==> Checking glibc symbol requirements ..."
MAX_GLIBC="$(readelf -V "$P7ZA_BIN" 2>/dev/null \
    | grep -oE 'GLIBC_[0-9]+\.[0-9]+' | sort -V | tail -1)"
echo "  Max glibc symbol: $MAX_GLIBC (target: GLIBC_2.28)"
case "$MAX_GLIBC" in
    GLIBC_2.2[0-8]|GLIBC_2.1[0-9]|GLIBC_2.[0-9])
        echo "  OK -- binary compatible with EL8 glibc 2.28" ;;
    *)
        echo "  WARNING: $MAX_GLIBC > GLIBC_2.28 -- binary may not run on EL8" >&2 ;;
esac

echo "==> Packaging binary ..."
WORK_BIN="$WORK_DIR/7za"
cp "$P7ZA_BIN" "$WORK_BIN"
strip "$WORK_BIN"
# 7za links only against system libs; no RPATH needed
bzip2 -kf "$WORK_BIN"
cp "${WORK_BIN}.bz2" "$BIN_DIR/7za.bz2"

echo "==> Updating packages.json ..."
python3 -c "
import re, sys, json
path, ver = sys.argv[1], sys.argv[2]
with open(path) as f:
    data = json.load(f)
pkgs = data['packages']
if 'p7zip' in pkgs:
    pkgs['p7zip']['version'] = ver
    print(f'packages.json: p7zip version -> {ver}')
else:
    print('WARNING: p7zip not found in packages.json, skipping version update')
with open(path, 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
" "$REPO/payload/packages.json" "$VERSION"

echo "==> Running strip-all-elf-binaries ..."
"$REPO/build/strip-all-elf-binaries"

echo ""
echo "Done."
echo ""
echo "Produced:"
echo "  $BIN_DIR/7za.bz2"
echo ""
echo "Commit with:"
echo "  git add payload/el8.x86_64.glibc2p28/bin/7za.bz2 \\"
echo "          .strip-manifest payload/packages.json"
echo "  git commit -m 'feat(payload): p7zip ${VERSION} EL8 source build'"
