#!/bin/sh
# Build Valgrind from source for el8.x86_64.glibc2p28 as a per-user, no-root
# memcheck/cachegrind/callgrind bundle.
#
# Produces:
#   payload/el8.x86_64.glibc2p28/runtime/valgrind.tar.bz2   extracting to:
#     bin/valgrind                      thin wrapper exporting VALGRIND_LIB
#     lib/valgrind/memcheck-amd64-linux (etc; real tool binaries)
#     lib/valgrind/*.xml                register description files
#     lib/valgrind/default.supp         default suppression file
#     share/valgrind/                   docs and examples
#
# WHY THIS SHAPE. Valgrind is pure userspace (no kernel ABI coupling the way
# perf has) and needs no root. The "dispatcher" at bin/valgrind relies on
# VALGRIND_LIB to find the tool binaries under lib/valgrind/ -- so a wrapper
# is load-bearing here, and the dispatcher binary itself is NOT shipped on
# PATH (it lives at lib/valgrind/valgrind and only the wrapper execs it).
#
# NEEDED closure is *only* glibc. Valgrind builds its tool binaries with
# -static-like flags and links no external library besides libc. Anything
# else on a NEEDED line (libdw, libelf, libcap, ...) is a red flag --
# the build-box's devel headers leaked in and the artifact is DEAD on a
# clean farm node.
#
# Build prereqs on this box (EL8 build machine, gcc-toolset-14 at
# /opt/rh/gcc-toolset-14/enable):
#   gcc make curl bzip2 awk
#
# Usage (from repo root):
#   ./build/build-valgrind.sh --tag 3.27.1
#
# After this script:
#   ./build/strip-all-elf-binaries && python3.14 build/gen-installed-sizes \
#     && python3.14 build/gen-content-manifest

set -eu

REPO="$(cd "$(dirname "$0")/.." && pwd)"
PLATFORM_DIR="$REPO/payload/el8.x86_64.glibc2p28"
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

[ -n "$TAG" ] || {
    echo "ERROR: --tag is required, e.g.: $0 --tag 3.27.1" >&2
    echo "Stable releases: https://valgrind.org/downloads/current.html" >&2
    exit 1
}

case "$TAG" in
    [0-9]*.[0-9]*.[0-9]*) ;;
    *) echo "ERROR: --tag must look like 3.27.1 (got '$TAG')" >&2; exit 1 ;;
esac

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
need openssl
need readelf
need strip
need tar
need awk

WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/build-valgrind-XXXXXX")
INST_DIR="/tmp/loadout-valgrind-instdir-${TAG}"
trap 'rm -rf "$WORK_DIR" "$INST_DIR"' EXIT INT TERM

TARBALL="valgrind-${TAG}.tar.bz2"
URL="https://sourceware.org/pub/valgrind/${TARBALL}"

echo "==> Downloading $URL ..."
curl -fsSL -o "$WORK_DIR/$TARBALL" "$URL" --retry 3 --retry-delay 2

SHA=$(openssl dgst -sha256 "$WORK_DIR/$TARBALL" | awk '{print $NF}')
echo "  sha256: $SHA"
echo "  (valgrind does not publish a per-file sidecar hash; recorded here)"

echo "==> Extracting ..."
tar xjf "$WORK_DIR/$TARBALL" -C "$WORK_DIR"
SRC_DIR="$WORK_DIR/valgrind-${TAG}"
[ -d "$SRC_DIR" ] || { echo "ERROR: expected $SRC_DIR after extract" >&2; exit 1; }

echo "==> Configuring ..."
# Keep the configure flag list minimal: --prefix is enough. Valgrind's
# configure is well-behaved and detects absence of the optional deps (MPI,
# gdbserver integration, 32-bit) without needing explicit --without-*
# flags. Explicitly disabling things upstream turns on opportunistically
# would silently drift from upstream's defaults if their flags change.
rm -rf "$INST_DIR"
mkdir -p "$INST_DIR"
cd "$SRC_DIR"
./configure \
    --prefix="$INST_DIR" \
    >"$WORK_DIR/configure.log" 2>&1 || {
        echo "ERROR: configure failed; tail of log:" >&2
        tail -30 "$WORK_DIR/configure.log" >&2
        exit 1
    }

echo "==> Building ..."
JOBS=$(nproc 2>/dev/null || echo 2)
echo "  (using -j$JOBS; log at $WORK_DIR/make.log)"
if ! make -j"$JOBS" >"$WORK_DIR/make.log" 2>&1; then
    echo "ERROR: make failed; tail of log:" >&2
    tail -60 "$WORK_DIR/make.log" >&2
    exit 1
fi
make install >"$WORK_DIR/install.log" 2>&1

# ---------------------------------------------------------------------------
# Smoke BEFORE packaging, on the staged install tree. A --version proves
# nothing here (valgrind could exit 0 and still be unable to find any of its
# tools). Require: dispatcher runs, finds memcheck, runs a real compiled
# binary with a known leak, reports it, and exits with --error-exitcode.
# ---------------------------------------------------------------------------
echo "==> Stage-verify (real memcheck against staged install) ..."

VALGRIND="$INST_DIR/bin/valgrind"
[ -x "$VALGRIND" ] || { echo "ERROR: $VALGRIND not produced" >&2; exit 1; }

cat > "$WORK_DIR/leak.c" <<'EOF'
#include <stdlib.h>
int main(void) { (void)malloc(16); return 0; }
EOF
cc -O0 -g "$WORK_DIR/leak.c" -o "$WORK_DIR/leak"

memcheck_log="$WORK_DIR/memcheck.log"
rc=0
"$VALGRIND" --tool=memcheck --leak-check=full --error-exitcode=42 \
    "$WORK_DIR/leak" >"$memcheck_log" 2>&1 || rc=$?

if [ "$rc" != 42 ]; then
    echo "ERROR: staged memcheck exit code $rc (expected 42 from --error-exitcode)" >&2
    echo "--- memcheck log ---" >&2
    cat "$memcheck_log" >&2
    exit 1
fi
if ! grep -q 'definitely lost: 16 bytes' "$memcheck_log"; then
    echo "ERROR: staged memcheck did not report the expected 16-byte leak" >&2
    echo "--- memcheck log ---" >&2
    cat "$memcheck_log" >&2
    exit 1
fi
echo "  memcheck found the 16-byte leak and exited 42"

# ---------------------------------------------------------------------------
# NEEDED closure. Valgrind should link ONLY glibc. Anything else fails loudly.
# ---------------------------------------------------------------------------
echo "==> Checking NEEDED closure ..."
NEVER_ALLOW_PATTERN='lib(dw|elf|cap|numa|selinux|z|lzma|zstd|bz2|readline|ncurses|tinfo|history|crypto|ssl)\.so'

find "$INST_DIR" -type f \( -perm -0100 -o -name '*.so*' \) | while read -r f; do
    if file "$f" 2>/dev/null | grep -q 'ELF 64-bit'; then
        needed=$(readelf -d "$f" 2>/dev/null | sed -n 's/.*NEEDED.*\[\(.*\)\]/\1/p')
        for so in $needed; do
            case "$so" in
                libc.so.6|libm.so.6|libpthread.so.0|libpthread.so.2|libdl.so.2|librt.so.1|ld-linux-x86-64.so.2|ld-linux-aarch64.so.1) ;;
                *)
                    if echo "$so" | grep -qE "$NEVER_ALLOW_PATTERN"; then
                        echo "ERROR: $f links unexpected external library: $so" >&2
                        echo "       Valgrind's tool binaries must depend only on glibc." >&2
                        exit 1
                    fi
                    # Anything else not on the glibc allowlist also fails.
                    echo "ERROR: $f has unexpected NEEDED: $so" >&2
                    exit 1
                    ;;
            esac
        done
    fi
done
echo "  NEEDED closure: glibc only"

# ---------------------------------------------------------------------------
# glibc floor: must not need newer than EL8's 2.28.
# ---------------------------------------------------------------------------
MAX_GLIBC=$(find "$INST_DIR" -type f \( -perm -0100 -o -name '*.so*' \) \
    | while read -r f; do
        if file "$f" 2>/dev/null | grep -q 'ELF 64-bit'; then
            readelf -V "$f" 2>/dev/null
        fi
    done \
    | grep -oE 'GLIBC_[0-9]+\.[0-9]+' | sort -V | tail -1)
echo "==> glibc floor: ${MAX_GLIBC:-none} (target <= GLIBC_2.28)"
case "${MAX_GLIBC:-GLIBC_2.0}" in
    GLIBC_2.2[0-8]|GLIBC_2.1[0-9]|GLIBC_2.[0-9]|GLIBC_2.0) ;;
    *) echo "ERROR: requires $MAX_GLIBC; EL8 has 2.28" >&2; exit 1 ;;
esac

# ---------------------------------------------------------------------------
# Package. The archive extracts directly under ~/.local/:
#   bin/valgrind                  thin wrapper exporting VALGRIND_LIB
#   libexec/valgrind/             full upstream libexec/valgrind/ tree
#                                 (memcheck-amd64-linux, XMLs, default.supp)
#   lib/valgrind/                 static libs (*.a) shipped for completeness
#   share/valgrind/               docs
#
# Upstream 3.27.x places its tool binaries under libexec/valgrind/ (not the
# historical lib/valgrind/) and ships bin/valgrind as a real ELF dispatcher
# that consults VALGRIND_LIB. We replace that dispatcher with a thin wrapper
# that resolves the relocated prefix at exec time, then exec's the REAL
# dispatcher binary from its new home.
# ---------------------------------------------------------------------------
echo "==> Packaging ..."
mkdir -p "$PLATFORM_DIR/runtime"
STAGE="$WORK_DIR/stage"
rm -rf "$STAGE"
mkdir -p "$STAGE/bin"

# Bring over libexec/valgrind/ (the real tree) and lib/valgrind/ (static
# libs). Upstream names both; both go to identical paths under ~/.local.
mkdir -p "$STAGE/libexec"
cp -a "$INST_DIR/libexec/valgrind" "$STAGE/libexec/valgrind"
[ -d "$INST_DIR/lib/valgrind" ] && {
    mkdir -p "$STAGE/lib"
    cp -a "$INST_DIR/lib/valgrind" "$STAGE/lib/"
}
[ -d "$INST_DIR/share/valgrind" ] && {
    mkdir -p "$STAGE/share"
    cp -a "$INST_DIR/share/valgrind" "$STAGE/share/"
}

# Move the real dispatcher out of bin/ and into libexec/valgrind/ where the
# wrapper execs it from. The bin/ slot then receives our wrapper.
[ -f "$INST_DIR/bin/valgrind" ] || { echo "ERROR: $INST_DIR/bin/valgrind missing" >&2; exit 1; }
cp "$INST_DIR/bin/valgrind" "$STAGE/libexec/valgrind/valgrind"
chmod 755 "$STAGE/libexec/valgrind/valgrind"

# Strip every ELF inside the staged tree BEFORE writing the wrapper (the
# wrapper is NOT an ELF and stripping a shell script would be a no-op we do
# not want).
find "$STAGE" -type f -print0 \
    | xargs -0 -r file \
    | grep ': ELF 64-bit' \
    | cut -d: -f1 \
    | xargs -r strip 2>/dev/null || true

# Assert sentinel + load-bearing files.
[ -x "$STAGE/libexec/valgrind/valgrind" ] \
    || { echo "ERROR: dispatcher missing at libexec/valgrind/valgrind" >&2; exit 1; }
[ -x "$STAGE/libexec/valgrind/memcheck-amd64-linux" ] \
    || { echo "ERROR: memcheck-amd64-linux missing" >&2; exit 1; }
[ -r "$STAGE/libexec/valgrind/default.supp" ] \
    || { echo "ERROR: default.supp missing" >&2; exit 1; }
ls "$STAGE/libexec/valgrind/"*-amd64-linux >/dev/null 2>&1 \
    || { echo "ERROR: no *-amd64-linux tool binaries staged" >&2; exit 1; }
ls "$STAGE/libexec/valgrind/"*.xml >/dev/null 2>&1 \
    || { echo "ERROR: no XML register description files staged" >&2; exit 1; }

# Write the wrapper at bin/valgrind. It exports VALGRIND_LIB so the
# dispatcher finds its tools, then execs the dispatcher ELF (which we
# relocated into libexec/valgrind/). VALGRIND_LIB is the *only* env var the
# dispatcher needs -- everything else is derived from it.
cat > "$STAGE/bin/valgrind" <<'EOF'
#!/bin/sh
# Loadout valgrind wrapper. Exports VALGRIND_LIB pointing at the relocated
# libexec/valgrind tree, then execs the real dispatcher (also under that
# tree, renamed from upstream bin/valgrind).
prefix=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
VALGRIND_LIB="${VALGRIND_LIB:-$prefix/libexec/valgrind}"
export VALGRIND_LIB
exec "$VALGRIND_LIB/valgrind" "$@"
EOF
chmod 755 "$STAGE/bin/valgrind"

# Tar it up.
VALGRIND_TAR="$PLATFORM_DIR/runtime/valgrind.tar.bz2"
rm -f "$VALGRIND_TAR"
tar -C "$STAGE" -cjf "$VALGRIND_TAR" .
chmod 644 "$VALGRIND_TAR"
echo "  staged: $VALGRIND_TAR ($(du -h "$VALGRIND_TAR" | cut -f1))"

echo ""
echo "Produced: $VALGRIND_TAR"
echo ""
echo "Next:"
echo "  ./build/strip-all-elf-binaries"
echo "  python3.14 build/gen-installed-sizes"
echo "  python3.14 build/gen-content-manifest"
echo "  git add payload/el8.x86_64.glibc2p28/runtime/valgrind.tar.bz2 \\"
echo "          payload/packages.json .strip-manifest .content-manifest \\"
echo "          payload/installed-sizes.json build/ADDING_BINARIES.md \\"
echo "          README.md AGENTS.md"
