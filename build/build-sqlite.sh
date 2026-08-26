#!/bin/sh
# Build sqlite (sqlite3 CLI + libsqlite3) from source for el8.x86_64.glibc2p28.
#
# Produces:
#   payload/el8.x86_64.glibc2p28/bin/sqlite3.bz2
#   payload/el8.x86_64.glibc2p28/lib64/libsqlite3.so.0.bz2
#
# WHY THIS EXISTS. EL8 ships sqlite 3.26 from 2018. Bundling the current
# upstream release gives every user a modern offline SQLite CLI without root.
#
# READLINE DECISION, load-bearing:
#   readline is left ON (upstream default). The shell links libreadline.so.7 +
#   libtinfo.so.6 -- BOTH already ship in payload lib64/ as unregistered stems,
#   which the installer lays into ~/.local/lib64 with EVERY selection
#   (loadout_main.py _lib_selected: unclaimed = always installed). The binary's
#   RPATH $ORIGIN/../lib64 resolves them there, so this is NOT a host
#   dependency even though we never declared an owner package. gnuplot /
#   ngspice / octave / vvp already rely on exactly these two libs.
#
# EXTENSION SET (--all):
#   Upstream's own blessed bundle: fts4 fts5 rtree geopoly session dbpage
#   dbstat carray. EL8's system build ships fts5+rtree; shipping a CLI that
#   rejects `CREATE VIRTUAL TABLE ... USING fts5` would be a silent regression
#   versus what users have on any distro from the last decade.
#
# Prerequisites on the build machine (EL8):
#   source /opt/rh/gcc-toolset-14/enable
#   dnf install -y gcc make readline-devel ncurses-devel   # headers for the auto-detect
#   # patchelf at ~/.local/bin/patchelf (bundled in this repo)
#
# Usage (run from any directory):
#   ./build/build-sqlite.sh --tag 3.53.4
#
# Version encoding: sqlite.org names tarballs sqlite-autoconf-<N>.tar.gz where
# N encodes 3.X.Y(Z) as 3XXYYZZ (e.g. 3.53.4 -> 3530400). This script derives N
# from --tag and cross-checks it against the download page's machine-readable
# CSV (PRODUCT,VERSION,RELATIVE-URL,SIZE-IN-BYTES,SHA3-HASH), which also gives
# us the year-scoped relative URL and the SHA3-256 for verification.
#
# Then, as for every payload change:
#   ./build/strip-all-elf-binaries && python3.14 build/gen-installed-sizes \
#     && python3.14 build/gen-content-manifest

set -eu

REPO="$(cd "$(dirname "$0")/.." && pwd)"
BIN_DIR="$REPO/payload/el8.x86_64.glibc2p28/bin"
LIB_DIR="$REPO/payload/el8.x86_64.glibc2p28/lib64"
TAG=""
DL_PAGE="https://www.sqlite.org/download.html"

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
    echo "  $0 --tag 3.53.4" >&2
    echo "" >&2
    echo "Stable releases: https://www.sqlite.org/download.html" >&2
    echo "" >&2
    echo "Policy: this project ships stable releases only." >&2
    exit 1
fi

case "$TAG" in
    3.*.*) ;;
    *) echo "ERROR: --tag must look like 3.53.4 (got '$TAG')" >&2; exit 1 ;;
esac

# 3.X.Y -> 3XXYY00 ; branch release 3.X.Y.Z -> 3XXYYZZ.
_rest=${TAG#3.}
_xx=${_rest%%.*}
_yz=${_rest#*.}
_yy=${_yz%%.*}
_zz=00
[ "$_yy" != "$_yz" ] && _zz=$(printf '%02d' "${_yz#*.}")
N=$(printf '3%s%02d%s' "$_xx" "$_yy" "$_zz")
echo "==> Tag $TAG encodes as tarball suffix $N"
TARBALL="sqlite-autoconf-${N}.tar.gz"

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

PATCHELF="$HOME/.local/bin/patchelf"
[ -x "$PATCHELF" ] || PATCHELF="$(command -v patchelf || true)"
[ -n "$PATCHELF" ] || { echo "ERROR: patchelf not found" >&2; exit 1; }

BZIP2="$(command -v bzip2 || true)"
[ -x "$HOME/.local/bin/bzip2" ] && BZIP2="$HOME/.local/bin/bzip2"
[ -n "$BZIP2" ] || { echo "ERROR: bzip2 not found" >&2; exit 1; }

WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/build-sqlite-XXXXXX")
INST_DIR="/tmp/loadout-sqlite-instdir-${TAG}"
trap 'rm -rf "$WORK_DIR" "$INST_DIR"' EXIT INT TERM

echo "==> Fetching download page to locate $TARBALL ..."
curl -fsSL -o "$WORK_DIR/dl.html" "$DL_PAGE" --retry 3 --retry-delay 2

# Machine-readable CSV row: PRODUCT,<version>,<relative-url>,<size>,<sha3>.
# Match on "<tarball>," -- the relative URL's year dir means the tarball name
# is preceded by '/', never ','.
CSV_ROW=$(grep '^PRODUCT,' "$WORK_DIR/dl.html" | grep "${TARBALL}," || true)
[ -n "$CSV_ROW" ] || { echo "ERROR: no CSV row for $TARBALL on $DL_PAGE" >&2; exit 1; }
REL_URL=$(printf '%s\n' "$CSV_ROW" | cut -d, -f3)
SHA3=$(printf '%s\n' "$CSV_ROW" | cut -d, -f5)

# Cross-check: the page's stated version for this tarball must equal --tag so a
# mislabelled request cannot ship silently (mirrors build-less.sh's guard).
PAGE_VER=$(printf '%s\n' "$CSV_ROW" | cut -d, -f2)
[ "$PAGE_VER" = "$TAG" ] || {
    echo "ERROR: download page says $TARBALL is version '$PAGE_VER' but --tag says $TAG" >&2
    exit 1
}

echo "==> Downloading $REL_URL ..."
curl -fL -o "$WORK_DIR/$TARBALL" "https://www.sqlite.org/$REL_URL" \
    --retry 3 --retry-delay 2

if [ -n "$SHA3" ]; then
    echo "==> Verifying SHA3-256 ..."
    GOT=$(openssl dgst -sha3-256 "$WORK_DIR/$TARBALL" | awk '{print $NF}')
    [ "$GOT" = "$SHA3" ] || {
        echo "ERROR: SHA3-256 mismatch" >&2
        echo "       expected $SHA3" >&2
        echo "       got      $GOT" >&2
        exit 1
    }
    echo "  sha3 OK"
fi

echo "==> Extracting ..."
tar xzf "$WORK_DIR/$TARBALL" -C "$WORK_DIR"
SRC_DIR="$WORK_DIR/sqlite-autoconf-${N}"
[ -d "$SRC_DIR" ] || { echo "ERROR: expected $SRC_DIR after extract" >&2; exit 1; }

echo "==> Configuring ..."
rm -rf "$INST_DIR"
cd "$SRC_DIR"
./configure \
    --prefix="$INST_DIR" \
    --all \
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

SQLITE3_BIN="$INST_DIR/bin/sqlite3"
[ -f "$SQLITE3_BIN" ] || { echo "ERROR: bin/sqlite3 not produced in $INST_DIR" >&2; exit 1; }

# Pin the built binary's self-reported version against --tag.
BIN_VER=$("$SQLITE3_BIN" --version | awk '{print $1}')
[ "$BIN_VER" = "$TAG" ] || {
    echo "ERROR: built sqlite3 reports version '$BIN_VER' but --tag says $TAG" >&2
    exit 1
}
echo "  built sqlite3 $BIN_VER"

SONAME_REAL=$(ls "$INST_DIR"/lib/libsqlite3.so.*.* 2>/dev/null | head -1)
[ -n "$SONAME_REAL" ] || { echo "ERROR: libsqlite3 shared library not produced" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Functional stage-verify BEFORE packaging (house rule: --version proves
# nothing). Exercise a real DB roundtrip plus every extension class that
# configure was asked to enable -- a flag that silently didn't take would
# otherwise only be discovered by a farm user mid-query.
# ---------------------------------------------------------------------------
echo "==> Functional stage-verify (DB roundtrip + extensions) ..."
SMOKE_DB="$WORK_DIR/smoke.db"
rm -f "$SMOKE_DB"
OUT=$(printf '%s\n' \
    "CREATE TABLE t(id INTEGER PRIMARY KEY, v TEXT);" \
    "INSERT INTO t(v) VALUES ('roundtrip');" \
    "SELECT v FROM t WHERE id = 1;" \
    | "$SQLITE3_BIN" "$SMOKE_DB")
[ "$OUT" = "roundtrip" ] || {
    echo "ERROR: basic insert/select roundtrip failed (got: '$OUT')" >&2
    exit 1
}
echo "  insert/select roundtrip: OK"

EXT_PROBE=$(printf '%s\n' \
    "CREATE VIRTUAL TABLE ft USING fts5(content);" \
    "INSERT INTO ft VALUES ('needle');" \
    "SELECT count(*) FROM ft WHERE ft MATCH 'needle';" \
    "CREATE VIRTUAL TABLE rt USING rtree(id, xmin, xmax);" \
    "INSERT INTO rt VALUES (1, 10, 20);" \
    "SELECT id FROM rt WHERE xmin <= 15 AND xmax >= 15;" \
    | "$SQLITE3_BIN" "$SMOKE_DB" 2>&1) || true
[ "$EXT_PROBE" = "$(printf '1\n1')" ] || {
    echo "ERROR: fts5/rtree probe failed -- --all did not take?" >&2
    echo "  output: $EXT_PROBE" >&2
    exit 1
}
echo "  fts5 + rtree: OK"

SESS_DB="$WORK_DIR/sess.db"
SESS_CS="$WORK_DIR/changeset.bin"
rm -f "$SESS_DB" "$SESS_CS"
# Real session flow. The db file is passed as ARGV so it is open as "main",
# and .session open takes that ALIAS (a filename would silently open a second
# connection whose writes are never recorded -> empty changeset). .session
# attach takes a TABLE name; tracked tables need a PRIMARY KEY.
printf '%s\n' \
    ".session open main s1" \
    "CREATE TABLE s(id INTEGER PRIMARY KEY, x);" \
    ".session attach s" \
    "INSERT INTO s(id, x) VALUES (1, 'change');" \
    ".session changeset $SESS_CS" \
    | "$SQLITE3_BIN" "$SESS_DB" >"$WORK_DIR/session.out" 2>&1 || true
if [ -s "$WORK_DIR/session.out" ]; then
    echo "ERROR: session extension probe produced diagnostics:" >&2
    sed 's/^/  /' "$WORK_DIR/session.out" >&2
    exit 1
fi
[ -s "$SESS_CS" ] || {
    echo "ERROR: session changeset file empty/missing -- session ext missing?" >&2
    exit 1
}
echo "  session: OK (changeset captured $(wc -c <"$SESS_CS") bytes)"

# ---------------------------------------------------------------------------
# Readline assertion. configure falls back SILENTLY to no-readline when the
# dev headers are missing -- the shell still builds and still passes every
# functional test above, just without line editing. Fail loudly here instead.
# ---------------------------------------------------------------------------
echo "==> Asserting readline linkage ..."
NEEDED_BIN=$(readelf -d "$SQLITE3_BIN" | sed -n 's/.*NEEDED.*\[\(.*\)\]/\1/p')
case "$NEEDED_BIN" in
    *libreadline.so*) echo "  readline: linked ($(echo "$NEEDED_BIN" | tr '\n' ' '))" ;;
    *)
        echo "ERROR: sqlite3 has NO libreadline NEEDED." >&2
        echo "       configure silently dropped readline (missing devel headers?)." >&2
        echo "       Install readline-devel + ncurses-devel and rebuild." >&2
        exit 1
        ;;
esac
case "$NEEDED_BIN" in
    *libtinfo.so*) : ;;
    *)
        echo "ERROR: expected libtinfo.so NEEDED alongside readline; got:" >&2
        printf '  %s\n' $NEEDED_BIN >&2
        exit 1
        ;;
esac

# ---------------------------------------------------------------------------
# NEEDED closure assertion (same guard as build-less.sh): hard-fail on any
# NEEDED outside bundled lib64/ stems or the never-bundle list. A
# build-box-only library installs fine here and is DEAD on a stock farm node.
# libsqlite3.so.0 is shipped by THIS script, hence pre-seeded into the list.
# ---------------------------------------------------------------------------
echo "==> Checking NEEDED closure ..."
ALLOW_BUNDLED=$(cd "$LIB_DIR" && for f in *.bz2; do echo "${f%.bz2}"; done | sort -u)
ALLOW_BUNDLED="$ALLOW_BUNDLED libsqlite3.so.0"
NEVER_BUNDLE="libc.so.6 libm.so.6 libpthread.so.0 libdl.so.2 librt.so.1 libstdc++.so.6 libgcc_s.so.1"

allow() {
    so=$1
    for a in $ALLOW_BUNDLED; do [ "$a" = "$so" ] && return 0; done
    for a in $NEVER_BUNDLE;  do [ "$a" = "$so" ] && return 0; done
    return 1
}

for artifact in "$SQLITE3_BIN" "$SONAME_REAL"; do
    NEEDED=$(readelf -d "$artifact" | sed -n 's/.*NEEDED.*\[\(.*\)\]/\1/p')
    echo "  $(basename "$artifact") NEEDED: $(echo "$NEEDED" | tr '\n' ' ')"
    for so in $NEEDED; do
        if ! allow "$so"; then
            echo "ERROR: $(basename "$artifact") has unexpected NEEDED '$so'." >&2
            echo "       Not bundled in lib64/ and not EL8-base-guaranteed." >&2
            exit 1
        fi
    done
done

# ---------------------------------------------------------------------------
# glibc floor assertion: EL8's glibc is 2.28. Anything above fails on stock
# nodes with "version `GLIBC_2.29' not found".
# ---------------------------------------------------------------------------
echo "==> Checking glibc floor ..."
MAX_GLIBC=$(
{
    readelf -V "$SQLITE3_BIN" 2>/dev/null
    readelf -V "$SONAME_REAL" 2>/dev/null
} | grep -oE 'GLIBC_[0-9]+\.[0-9]+' | sort -V | tail -1)
echo "  max glibc symbol: ${MAX_GLIBC:-none} (target: GLIBC_2.28)"
case "${MAX_GLIBC:-GLIBC_2.0}" in
    GLIBC_2.2[0-8]|GLIBC_2.1[0-9]|GLIBC_2.[0-9]) ;;
    *) echo "ERROR: needs $MAX_GLIBC; EL8 has glibc 2.28" >&2; exit 1 ;;
esac

# ---------------------------------------------------------------------------
# Package: strip -> patchelf RPATH -> bzip2. Order is load-bearing: NEVER
# strip after patchelf (see AGENTS.md).
#   bin/sqlite3            RPATH $ORIGIN/../lib64  (repo standard for bin/)
#   lib64/libsqlite3.so.0  RPATH $ORIGIN           (repo standard for libs)
# The SONAME file is staged under its SONAME (libsqlite3.so.0), not the real
# name -- the installer preserves filenames, and consumers reference the
# soname. The linker-name libsqlite3.so is deliberately NOT shipped: nothing
# compiles against this copy today; add it if an offline source build ever
# needs it.
# ---------------------------------------------------------------------------
echo "==> Packaging (strip -> patchelf -> bzip2) ..."

WORK_ART="$WORK_DIR/sqlite3"
cp "$SQLITE3_BIN" "$WORK_ART"
strip "$WORK_ART"
# shellcheck disable=SC2016  # $ORIGIN is an ld.so token, not a shell var
"$PATCHELF" --set-rpath '$ORIGIN/../lib64' "$WORK_ART"
"$BZIP2" -kf "$WORK_ART"
cp "${WORK_ART}.bz2" "$BIN_DIR/sqlite3.bz2"
chmod 644 "$BIN_DIR/sqlite3.bz2"
echo "  staged: $BIN_DIR/sqlite3.bz2 ($(du -h "$BIN_DIR/sqlite3.bz2" | cut -f1))"

WORK_LIB="$WORK_DIR/libsqlite3.so.0"
cp "$SONAME_REAL" "$WORK_LIB"
strip "$WORK_LIB"
"$PATCHELF" --set-rpath '$ORIGIN' "$WORK_LIB"
"$BZIP2" -kf "$WORK_LIB"
cp "${WORK_LIB}.bz2" "$LIB_DIR/libsqlite3.so.0.bz2"
chmod 644 "$LIB_DIR/libsqlite3.so.0.bz2"
echo "  staged: $LIB_DIR/libsqlite3.so.0.bz2 ($(du -h "$LIB_DIR/libsqlite3.so.0.bz2" | cut -f1))"

echo ""
echo "Done."
echo ""
echo "Produced:"
echo "  $BIN_DIR/sqlite3.bz2"
echo "  $LIB_DIR/libsqlite3.so.0.bz2"
echo ""
echo "Next:"
echo "  ./build/strip-all-elf-binaries"
echo "  python3.14 build/gen-installed-sizes"
echo "  python3.14 build/gen-content-manifest"
echo "  git add payload/el8.x86_64.glibc2p28/bin/sqlite3.bz2 \\"
echo "          payload/el8.x86_64.glibc2p28/lib64/libsqlite3.so.0.bz2 \\"
echo "          .strip-manifest .content-manifest payload/packages.json \\"
echo "          payload/installed-sizes.json build/build-sqlite.sh \\"
echo "          build/farm-versions envs/bash/global/completions/loadout.bash \\"
echo "          build/ADDING_BINARIES.md"
