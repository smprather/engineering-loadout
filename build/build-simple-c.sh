#!/bin/sh
# Build one of the small autotools/make C tools the loadout ships as a single
# binary, for el8.x86_64.glibc2p28.
#
# These five (htop, rsync, xsel, yank, yara) had NO build script and NO entry in
# ADDING_BINARIES.md, despite the repo mandating a reproducible note per tool.
# Whoever added them built by hand and left nothing behind, so the next bump had
# to re-derive the procedure from scratch. This is that procedure, executable.
#
# Each tool gets its own configure flags because they genuinely differ; what is
# shared is the packaging contract every loadout binary must satisfy:
#   strip -> patchelf RPATH '$ORIGIN/../lib64:$ORIGIN/../lib' -> bzip2
#   plus a hard check that the result needs nothing newer than EL8's glibc 2.28.
#
# Usage (run from any directory):
#   ./build/build-simple-c.sh --tool yara --tag 4.5.8 --src /path/to/yara.tar.gz
#
# Then, as for every payload change:
#   ./strip-all-elf-binaries && python3.14 build/gen-content-manifest

set -eu

REPO="$(cd "$(dirname "$0")/.." && pwd)"
BIN_DIR="$REPO/payload/el8.x86_64.glibc2p28/bin"
TOOL=""; TAG=""; SRC_TARBALL=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        --tool) shift; TOOL="${1:-}" ;;
        --tag) shift; TAG="${1:-}" ;;
        --src) shift; SRC_TARBALL="${1:-}" ;;
        -h|--help) sed -n '2,/^$/p' "$0"; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done
[ -n "$TOOL" ] || { echo "ERROR: --tool is required (htop|rsync|xsel|yank|yara)" >&2; exit 1; }
[ -n "$TAG" ]  || { echo "ERROR: --tag is required" >&2; exit 1; }
[ -f "$SRC_TARBALL" ] || { echo "ERROR: --src tarball not found: $SRC_TARBALL" >&2; exit 1; }

PATCHELF="$HOME/.local/bin/patchelf"
[ -x "$PATCHELF" ] || PATCHELF="$(command -v patchelf || true)"
[ -n "$PATCHELF" ] || { echo "ERROR: patchelf not found" >&2; exit 1; }

# shellcheck disable=SC1091
[ -f /opt/rh/gcc-toolset-14/enable ] && . /opt/rh/gcc-toolset-14/enable

STAGE=$(mktemp -d "/tmp/build-$TOOL-XXXXXX")
trap 'rm -rf "$STAGE"' EXIT INT TERM
tar xzf "$SRC_TARBALL" -C "$STAGE"
SRC=$(find "$STAGE" -maxdepth 1 -mindepth 1 -type d | head -1)

echo "==> Building $TOOL $TAG ..."
cd "$SRC"
case "$TOOL" in
    yara)
        # --disable-magic/--disable-cuckoo: those modules need libmagic and
        # jansson, which the loadout does not bundle and EL8 does not guarantee.
        # scan-for-malware only needs the core scanner.
        ./bootstrap.sh >/dev/null 2>&1
        ./configure --disable-magic --disable-cuckoo --without-crypto >/dev/null
        make -j"$(nproc)" >/dev/null
        BUILT="$SRC/yara"
        ;;
    rsync)
        # --disable-md2man avoids the doc toolchain; --disable-xxhash etc. are
        # NOT passed because packages.json ships libxxhash.so.0 for rsync.
        ./configure --disable-md2man >/dev/null
        make -j"$(nproc)" >/dev/null
        BUILT="$SRC/rsync"
        ;;
    htop)
        ./autogen.sh >/dev/null 2>&1
        ./configure --disable-unicode --enable-static=no >/dev/null
        make -j"$(nproc)" >/dev/null
        BUILT="$SRC/htop"
        ;;
    xsel)
        ./autogen.sh >/dev/null 2>&1 || autoreconf -fi >/dev/null 2>&1
        ./configure >/dev/null
        make -j"$(nproc)" >/dev/null
        BUILT="$SRC/xsel"
        ;;
    yank)
        make -j"$(nproc)" >/dev/null
        BUILT="$SRC/yank"
        ;;
    *) echo "ERROR: no recipe for tool '$TOOL'" >&2; exit 1 ;;
esac

[ -x "$BUILT" ] || { echo "ERROR: $TOOL did not build ($BUILT missing)" >&2; exit 1; }

cp "$BUILT" "$STAGE/out"
/usr/bin/strip "$STAGE/out"
"$PATCHELF" --set-rpath '$ORIGIN/../lib64:$ORIGIN/../lib' "$STAGE/out" 2>/dev/null || true

# EL8 floor. A binary needing a newer glibc installs fine on this box and is
# dead on a stock farm node -- the build-box masking this repo keeps hitting.
MAXG=$(objdump -T "$STAGE/out" | grep -oE 'GLIBC_[0-9]+\.[0-9]+' | sort -V | tail -1)
case "${MAXG:-GLIBC_2.0}" in
    GLIBC_2.1[0-9]|GLIBC_2.2[0-8]|GLIBC_2.[0-9]) ;;
    GLIBC_2.0) ;;
    *) echo "ERROR: $TOOL needs $MAXG; EL8 has glibc 2.28" >&2; exit 1 ;;
esac
echo "    max glibc symbol: ${MAXG:-none}"
echo "    NEEDED: $(objdump -p "$STAGE/out" | awk '/NEEDED/ {printf "%s ", $2}')"

bzip2 -kf "$STAGE/out"
cp "$STAGE/out.bz2" "$BIN_DIR/$TOOL.bz2"
chmod 644 "$BIN_DIR/$TOOL.bz2"

python3.14 - "$REPO/payload/packages.json" "$TOOL" "$TAG" <<'PYEOF'
import re, sys
path, pkg, version = sys.argv[1], sys.argv[2], sys.argv[3]
raw = open(path).read()
pat = re.compile(r'("%s":\s*\{(?:[^{}]|\{[^{}]*\})*?"version":\s*")([^"]*)(")' % pkg)
raw, n = pat.subn(lambda m: m.group(1) + version + m.group(3), raw, count=1)
if n != 1:
    sys.exit("could not stamp %s version in packages.json" % pkg)
open(path, "w").write(raw)
print("    packages.json: %s -> %s" % (pkg, version))
PYEOF

echo "Staged: payload/el8.x86_64.glibc2p28/bin/$TOOL.bz2"
