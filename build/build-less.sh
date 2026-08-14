#!/bin/sh
# Build less (the pager) from source for el8.x86_64.glibc2p28.
#
# Produces:
#   payload/el8.x86_64.glibc2p28/bin/less.bz2
#   payload/el8.x86_64.glibc2p28/bin/lessecho.bz2
#   payload/el8.x86_64.glibc2p28/bin/lesskey.bz2
#
# WHY THIS EXISTS. EL8 ships less 530 from 2017 -- six years of upstream
# development (search, filtering, key-binding improvements) never reached the
# farm nodes. Bundling the upstream RECOMMENDED release gives every user a
# current pager without root.
#
# VERSION CHOICE, load-bearing:
#   704  upstream's own download page says "Download RECOMMENDED version 704".
#        gwsw/less publishes ZERO GitHub releases, so the v705-v708 git tags
#        are DEVELOPMENT tags. This repo's stable-release policy forbids dev
#        builds, so 704 is the only acceptable version until a new tarball
#        appears on www.greenwoodsoftware.com.
#
# REGEX BACKEND CHOICE, load-bearing:
#   --with-regex=posix  PCRE2 would add libpcre2-8.so.0 to NEEDED, and that
#                       lib is owned by the gui_libs package. Coupling a core
#                       CLI pager to the GUI bundle is wrong -- a headless
#                       compute node with no gui_libs would lose its pager.
#                       The POSIX regex backend needs only libc, so minimal
#                       closure wins.
#
# Prerequisites on the build machine (EL8):
#   source /opt/rh/gcc-toolset-14/enable
#   dnf install -y gcc make ncurses-devel
#   # patchelf at ~/.local/bin/patchelf (bundled in this repo)
#
# Usage (run from any directory):
#   ./build/build-less.sh --tag 704
#
# The install tree is removed after packaging (less has no runtime data files
# and no downstream build needs its headers), unlike freetype whose devel tree
# is kept for poppler. The temp prefix is version-scoped
# (/tmp/loadout-less-instdir-<TAG>) so successive builds cannot contaminate
# each other -- the same convention build-octave.sh / build-freetype.sh use.
#
# Then, as for every payload change:
#   ./build/strip-all-elf-binaries && python3.14 build/gen-content-manifest

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
    echo "  $0 --tag 704" >&2
    echo "" >&2
    echo "Stable releases: http://www.greenwoodsoftware.com/less/download.html" >&2
    echo "" >&2
    echo "Policy: this project ships stable releases only." >&2
    echo "The gwsw/less GitHub tags v705+ are dev tags with no release tarball." >&2
    exit 1
fi

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
need bzip2
need readelf
need strip

PATCHELF="$HOME/.local/bin/patchelf"
[ -x "$PATCHELF" ] || PATCHELF="$(command -v patchelf || true)"
[ -n "$PATCHELF" ] || { echo "ERROR: patchelf not found" >&2; exit 1; }

WORK_DIR=$(mktemp -d /tmp/build-less-XXXXXX)
INST_DIR="/tmp/loadout-less-instdir-${TAG}"
trap 'rm -rf "$WORK_DIR" "$INST_DIR"' EXIT INT TERM

echo "==> Downloading less-${TAG}.tar.gz ..."
curl -fL -o "$WORK_DIR/less.tar.gz" \
    "http://www.greenwoodsoftware.com/less/less-${TAG}.tar.gz" \
    --retry 3 --retry-delay 2

echo "==> Extracting ..."
tar xzf "$WORK_DIR/less.tar.gz" -C "$WORK_DIR"
SRC_DIR="$WORK_DIR/less-${TAG}"
[ -d "$SRC_DIR" ] || { echo "ERROR: expected $SRC_DIR after extract" >&2; exit 1; }

# Pin the source version against --tag so a mislabelled tarball cannot ship
# silently. less does NOT use autoconf's PACKAGE_VERSION for its own version
# number (configure sets PACKAGE_VERSION='1'). The real version is a C string
# in version.c: `char version[] = "704";`
echo "==> Verifying source version matches --tag ..."
SRC_VER=$(sed -n 's/^char version\[\] = "\([0-9]*\)";/\1/p' "$SRC_DIR/version.c")
[ "$SRC_VER" = "$TAG" ] || {
    echo "ERROR: source declares version '$SRC_VER' but --tag says $TAG" >&2
    echo "       Check $SRC_DIR/version.c" >&2
    exit 1
}
echo "  version.c declares $SRC_VER"

echo "==> Configuring ..."
rm -rf "$INST_DIR"
cd "$SRC_DIR"
# --libexecdir=$INST_DIR/bin: upstream installs `lessecho` to libexecdir and
# `less`/`lesskey` to bindir. Setting libexecdir=bindir puts all three in
# bin/ so we can package them uniformly. The compiled-in LIBEXECDIR macro
# (used by `less` to find `lessecho` for glob expansion and `less-osc8-open`
# for OSC8 hyperlink clicks) then points at this temp path, which is dead once
# deployed. That is acceptable:
#   - `lessecho` is installed to ~/.local/bin/ (on PATH), and the `LESSECHO`
#     env var can override the compiled-in path if glob expansion is needed.
#     When the dead path fails, filename.c falls back gracefully (returns the
#     original filename) -- it does not crash.
#   - `less-osc8-open` is a shell script not shipped (task scope: 3 binaries).
#     OSC8 hyperlink clicking is opt-in via LESS_OSC8_OPEN_ANY env var; without
#     it, links simply are not clickable -- not a crash, not a regression
#     versus EL8's less 530 which predates OSC8 support.
./configure \
    --prefix="$INST_DIR" \
    --libexecdir="$INST_DIR/bin" \
    --with-regex=posix \
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

BINS="less lessecho lesskey"
for b in $BINS; do
    [ -f "$INST_DIR/bin/$b" ] || {
        echo "ERROR: $b not produced in $INST_DIR/bin" >&2
        exit 1
    }
done
echo "  built: $BINS"

# ---------------------------------------------------------------------------
# Functional stage-verify BEFORE packaging.
#
# A `--version` probe proves nothing -- a mis-built less can print its banner
# and fail to page. Verify by actually paging: pipe multi-line input through
# the built `less` with -F (quit-if-one-screen, so it exits without a tty) and
# assert every input line comes back out. Also run `lesskey -V` and `lessecho`
# with real arguments. This is the repo's house rule: a version probe is not a
# smoke test.
# ---------------------------------------------------------------------------
echo "==> Functional stage-verify (paging, not --version) ..."
SMOKE_INPUT="line one
line two
line three
line four
line five"

PAGED=$(printf '%s\n' "$SMOKE_INPUT" | "$INST_DIR/bin/less" -F 2>/dev/null || true)
if [ "$PAGED" != "$SMOKE_INPUT" ]; then
    echo "ERROR: less -F did not reproduce its input verbatim:" >&2
    printf '%s\n' "$PAGED" | sed 's/^/  OUT: /' >&2
    exit 1
fi
echo "  less -F: paged 5 lines, content matched"

LESSECHO_OUT=$("$INST_DIR/bin/lessecho" "hello world" 2>&1)
case "$LESSECHO_OUT" in
    *hello*) echo "  lessecho: produced output containing 'hello'" ;;
    *) echo "ERROR: lessecho produced unexpected output: $LESSECHO_OUT" >&2; exit 1 ;;
esac

LESSKEY_OUT=$("$INST_DIR/bin/lesskey" -V 2>&1 || true)
case "$LESSKEY_OUT" in
    *lesskey*) echo "  lesskey -V: $LESSKEY_OUT" | head -1 ;;
    *) echo "ERROR: lesskey -V produced unexpected output: $LESSKEY_OUT" >&2; exit 1 ;;
esac

# ---------------------------------------------------------------------------
# NEEDED closure assertion.
#
# Collect readelf -d NEEDED for all three binaries and hard-fail on anything
# outside an explicit allowlist. Only libs already present in
# payload/el8.x86_64.glibc2p28/lib64/ or on the never-bundle list (glibc
# components, libstdc++/libgcc_s) are acceptable. A build-box-only library
# silently installs fine here and is DEAD on a stock farm node -- this guard
# exists because of that masking (see ADDING_BINARIES.md "build-box masking").
#
# With --with-regex=posix, less links only against ncurses/tinfo and glibc.
# If a future less gains a new NEEDED outside this set, FAIL and investigate
# rather than weakening the allowlist.
# ---------------------------------------------------------------------------
echo "==> Checking NEEDED closure ..."
# Build the allowlist from what is already bundled in lib64/ (strip the .bz2).
ALLOW_BUNDLED=$(cd "$LIB_DIR" && for f in *.bz2; do echo "${f%.bz2}"; done | sort -u)
# Never-bundle libs (always present on EL8, must match system ld-linux).
NEVER_BUNDLE="libc.so.6 libm.so.6 libpthread.so.0 libdl.so.2 librt.so.1 libstdc++.so.6 libgcc_s.so.1"

allow() {
    so=$1
    for a in $ALLOW_BUNDLED; do [ "$a" = "$so" ] && return 0; done
    for a in $NEVER_BUNDLE;  do [ "$a" = "$so" ] && return 0; done
    return 1
}

ALL_NEEDED=""
for b in $BINS; do
    NEEDED=$(readelf -d "$INST_DIR/bin/$b" | sed -n 's/.*NEEDED.*\[\(.*\)\]/\1/p')
    echo "  $b NEEDED: $(echo "$NEEDED" | tr '\n' ' ')"
    ALL_NEEDED="$ALL_NEEDED$NEEDED"
    for so in $NEEDED; do
        if ! allow "$so"; then
            echo "ERROR: $b has unexpected NEEDED '$so'." >&2
            echo "       Not bundled in lib64/ and not EL8-base-guaranteed." >&2
            echo "       Check the --with-regex=posix flag or configure options." >&2
            exit 1
        fi
    done
done

# ---------------------------------------------------------------------------
# glibc floor assertion.
#
# EL8's glibc is 2.28. Any binary referencing a GLIBC symbol > 2.28 will fail
# with "version `GLIBC_2.29' not found" on a stock farm node. Fail loudly.
# ---------------------------------------------------------------------------
echo "==> Checking glibc floor ..."
MAX_GLIBC=$(
for b in $BINS; do
    readelf -V "$INST_DIR/bin/$b" 2>/dev/null \
        | grep -oE 'GLIBC_[0-9]+\.[0-9]+' || true
done | sort -V | tail -1)
echo "  max glibc symbol: ${MAX_GLIBC:-none} (target: GLIBC_2.28)"
case "${MAX_GLIBC:-GLIBC_2.0}" in
    GLIBC_2.2[0-8]|GLIBC_2.1[0-9]|GLIBC_2.[0-9]) ;;
    *) echo "ERROR: needs $MAX_GLIBC; EL8 has glibc 2.28" >&2; exit 1 ;;
esac

# ---------------------------------------------------------------------------
# Package: strip -> patchelf --set-rpath '$ORIGIN/../lib64' -> bzip2.
# Order is load-bearing: NEVER strip after patchelf (see AGENTS.md).
# RPATH $ORIGIN/../lib64 is the repo standard for bin/ binaries.
# ---------------------------------------------------------------------------
echo "==> Packaging (strip -> patchelf -> bzip2) ..."
for b in $BINS; do
    WORK_BIN="$WORK_DIR/$b"
    cp "$INST_DIR/bin/$b" "$WORK_BIN"
    strip "$WORK_BIN"
    # shellcheck disable=SC2016  # $ORIGIN is an ld.so token, not a shell var
    "$PATCHELF" --set-rpath '$ORIGIN/../lib64' "$WORK_BIN"
    bzip2 -kf "$WORK_BIN"
    cp "${WORK_BIN}.bz2" "$BIN_DIR/${b}.bz2"
    chmod 644 "$BIN_DIR/${b}.bz2"
    echo "  staged: $BIN_DIR/${b}.bz2 ($(du -h "$BIN_DIR/${b}.bz2" | cut -f1))"
done

echo ""
echo "Done."
echo ""
echo "Produced:"
for b in $BINS; do echo "  $BIN_DIR/${b}.bz2"; done
echo ""
echo "Next:"
echo "  ./build/strip-all-elf-binaries"
echo "  python3.14 build/gen-content-manifest"
echo "  git add payload/el8.x86_64.glibc2p28/bin/{less,lessecho,lesskey}.bz2 \\"
echo "          .strip-manifest .content-manifest payload/packages.json \\"
echo "          build/build-less.sh build/farm-versions tests/prebuilt-binaries"