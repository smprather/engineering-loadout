#!/bin/sh
# Build strace from source for el8.x86_64.glibc2p28.
#
# Produces:
#   payload/el8.x86_64.glibc2p28/bin/strace.bz2
#
# WHY THIS EXISTS. EL8 ships strace 5.18 (2022) with stale syscall decode
# tables; farm nodes run much newer kernels (6.x), where old strace prints
# bare syscall numbers. Bundling current upstream gives every user modern
# decodes offline without root. Also the runtime half of strace-ui, which
# shells out to strace with a modern flag set (see stage-verify below).
#
# --without-libunwind --without-libselinux, load-bearing:
#   libunwind is EPEL-only (not BaseOS), and it serves only strace -k which
#   strace-ui never passes. libselinux.so.1 is worse: present on EL8 but
#   ABSENT on newer distros (caught on CachyOS: loader hard-fails, no
#   graceful fallback) -- and it serves only -Z context decoding, also
#   unused by strace-ui. Drop both features instead of bundling.
#   libtinfo stays: it is already an unclaimed lib64 stem (sqlite precedent)
#   resolved via RPATH.
#
# Prerequisites on the build machine (EL8):
#   source /opt/rh/gcc-toolset-14/enable
#   dnf install -y gcc make   # + image base (see build/Dockerfile)
#   # patchelf at ~/.local/bin/patchelf (bundled in this repo)
#
# Usage (run from any directory):
#   ./build/build-strace.sh --tag 7.2
#
# Then, as for every payload change:
#   ./build/strip-all-elf-binaries && python3.14 build/gen-installed-sizes \
#     && python3.14 build/gen-content-manifest

set -eu

REPO="$(cd "$(dirname "$0")/.." && pwd)"
BIN_DIR="$REPO/payload/el8.x86_64.glibc2p28/bin"
LIB_DIR="$REPO/payload/el8.x86_64.glibc2p28/lib64"
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
    echo "ERROR: --tag is required. Specify a stable release, e.g.:" >&2
    echo "  $0 --tag 7.2" >&2
    echo "" >&2
    echo "Stable releases: https://github.com/strace/strace/releases" >&2
    echo "" >&2
    echo "Policy: this project ships stable releases only." >&2
    exit 1
fi

case "$TAG" in
    [0-9]*.[0-9]*) ;;
    *) echo "ERROR: --tag must look like 7.2 (got '$TAG')" >&2; exit 1 ;;
esac

TARBALL="strace-${TAG}.tar.xz"
TARBALL_URL="https://github.com/strace/strace/releases/download/v${TAG}/${TARBALL}"

# shellcheck disable=SC1091
[ -r /opt/rh/gcc-toolset-14/enable ] && . /opt/rh/gcc-toolset-14/enable

need() {
    command -v "$1" >/dev/null 2>&1 || {
        printf 'missing required command: %s\n' "$1" >&2
        exit 1
    }
}
need gcc
need make
need curl
need readelf
need strip

PATCHELF="$HOME/.local/bin/patchelf"
[ -x "$PATCHELF" ] || PATCHELF="$(command -v patchelf || true)"
[ -n "$PATCHELF" ] || { echo "ERROR: patchelf not found" >&2; exit 1; }

BZIP2="$(command -v bzip2 || true)"
[ -x "$HOME/.local/bin/bzip2" ] && BZIP2="$HOME/.local/bin/bzip2"
[ -n "$BZIP2" ] || { echo "ERROR: bzip2 not found" >&2; exit 1; }

WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/build-strace-XXXXXX")
INST_DIR="/tmp/loadout-strace-instdir-${TAG}"
trap 'rm -rf "$WORK_DIR" "$INST_DIR"' EXIT INT TERM

echo "==> Downloading $TARBALL_URL ..."
curl -fL -o "$WORK_DIR/$TARBALL" "$TARBALL_URL" --retry 3 --retry-delay 2

echo "==> Extracting ..."
tar xf "$WORK_DIR/$TARBALL" -C "$WORK_DIR"
SRC_DIR="$WORK_DIR/strace-${TAG}"
[ -d "$SRC_DIR" ] || { echo "ERROR: expected $SRC_DIR after extract" >&2; exit 1; }

echo "==> Configuring (no libunwind/libselinux: see header) ..."
rm -rf "$INST_DIR"
cd "$SRC_DIR"
./configure \
    --prefix="$INST_DIR" \
    --without-libunwind \
    --without-libselinux \
    >"$WORK_DIR/configure.log" 2>&1 || {
        echo "ERROR: configure failed; tail of log:" >&2
        tail -30 "$WORK_DIR/configure.log" >&2
        exit 1
    }

echo "==> Building ..."
make -j"$(nproc 2>/dev/null || echo 2)" >"$WORK_DIR/make.log" 2>&1 || {
    echo "ERROR: make failed; tail of log:" >&2
    tail -30 "$WORK_DIR/make.log" >&2
    exit 1
}
make install >"$WORK_DIR/install.log" 2>&1

STRACE_BIN="$INST_DIR/bin/strace"
[ -f "$STRACE_BIN" ] || { echo "ERROR: bin/strace not produced in $INST_DIR" >&2; exit 1; }

# Pin the built binary's self-reported version against --tag.
BIN_VER=$("$STRACE_BIN" -V 2>&1 | head -1 | awk '{print $NF}')
[ "$BIN_VER" = "$TAG" ] || {
    echo "ERROR: built strace reports version '$BIN_VER' but --tag says $TAG" >&2
    exit 1
}
echo "  built strace $BIN_VER"

# ---------------------------------------------------------------------------
# Functional stage-verify BEFORE packaging (house rule: --version proves
# nothing). Exercise the exact flag set strace-ui shells out with, plus a
# real traced syscall and the -c summary path.
# ---------------------------------------------------------------------------
echo "==> Functional stage-verify (strace-ui flag set + trace smoke) ..."
"$STRACE_BIN" \
    --absolute-timestamps=format:unix,precision:us \
    --syscall-times \
    --follow-forks \
    --decode-fds=all \
    --no-abbrev \
    --strings-in-hex=non-ascii \
    --string-limit=1024 \
    -e trace=none -o "$WORK_DIR/flags.log" true || {
    echo "ERROR: strace-ui flag set rejected by this build" >&2
    exit 1
}
echo "  strace-ui flag set: OK"
TRACE_OUT=$("$STRACE_BIN" -e trace=openat -o "$WORK_DIR/trace.log" true 2>&1; cat "$WORK_DIR/trace.log")
case "$TRACE_OUT" in
    *openat*) echo "  openat trace: OK" ;;
    *) echo "ERROR: openat trace produced no output" >&2; exit 1 ;;
esac

# ---------------------------------------------------------------------------
# NEEDED closure assertion: hard-fail on anything outside the never-bundle
# list or already-bundled unclaimed stems. libunwind/libselinux must NOT
# appear (--without-* above); libtinfo resolves via RPATH to the bundled
# unclaimed stem.
# ---------------------------------------------------------------------------
echo "==> Checking NEEDED closure ..."
ALLOW_BUNDLED=$(cd "$LIB_DIR" && for f in *.bz2; do echo "${f%.bz2}"; done | sort -u)
NEVER_BUNDLE="libc.so.6 libm.so.6 libpthread.so.0 libdl.so.2 librt.so.1 libstdc++.so.6 libgcc_s.so.1"

NEEDED=$(readelf -d "$STRACE_BIN" | sed -n 's/.*NEEDED.*\[\(.*\)\]/\1/p')
echo "  strace NEEDED: $(echo "$NEEDED" | tr '\n' ' ')"
for so in $NEEDED; do
    ok=0
    for a in $ALLOW_BUNDLED $NEVER_BUNDLE; do
        [ "$a" = "$so" ] && ok=1
    done
    if [ "$ok" != 1 ]; then
        echo "ERROR: strace has unexpected NEEDED '$so'." >&2
        echo "       Not bundled in lib64/, not EL8-base-guaranteed." >&2
        exit 1
    fi
done
case " $NEEDED " in
    *" libunwind"*|*" libselinux"*)
        echo "ERROR: libunwind/libselinux linkage slipped back in." >&2
        exit 1
        ;;
esac
echo "  closure: OK (no libunwind, no libselinux)"

# ---------------------------------------------------------------------------
# glibc floor assertion: EL8's glibc is 2.28.
# ---------------------------------------------------------------------------
echo "==> Checking glibc floor ..."
MAX_GLIBC=$(readelf -V "$STRACE_BIN" 2>/dev/null | grep -oE 'GLIBC_[0-9]+\.[0-9]+' | sort -V | tail -1)
echo "  max glibc symbol: ${MAX_GLIBC:-none} (target: GLIBC_2.28)"
case "${MAX_GLIBC:-GLIBC_2.0}" in
    GLIBC_2.2[0-8]|GLIBC_2.1[0-9]|GLIBC_2.[0-9]) ;;
    *) echo "ERROR: needs $MAX_GLIBC; EL8 has glibc 2.28" >&2; exit 1 ;;
esac

# ---------------------------------------------------------------------------
# Package: strip -> patchelf RPATH -> bzip2. Order is load-bearing: NEVER
# strip after patchelf (see AGENTS.md).
# ---------------------------------------------------------------------------
echo "==> Packaging (strip -> patchelf -> bzip2) ..."
WORK_ART="$WORK_DIR/strace"
cp "$STRACE_BIN" "$WORK_ART"
strip "$WORK_ART"
# shellcheck disable=SC2016  # $ORIGIN is an ld.so token, not a shell var
"$PATCHELF" --set-rpath '$ORIGIN/../lib64' "$WORK_ART"
"$BZIP2" -kf "$WORK_ART"
cp "${WORK_ART}.bz2" "$BIN_DIR/strace.bz2"
chmod 644 "$BIN_DIR/strace.bz2"
echo "  staged: $BIN_DIR/strace.bz2 ($(du -h "$BIN_DIR/strace.bz2" | cut -f1))"

echo ""
echo "Done."
echo ""
echo "Produced:"
echo "  $BIN_DIR/strace.bz2"
echo ""
echo "Next:"
echo "  ./build/strip-all-elf-binaries"
echo "  python3.14 build/gen-installed-sizes"
echo "  python3.14 build/gen-content-manifest"
