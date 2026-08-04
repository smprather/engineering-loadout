#!/bin/sh
# Build terminal vim, the vim runtime archive, and GTK3 gvim from ONE vim
# source checkout, for el8.x86_64.glibc2p28.
#
# Replaces the old build-gvim.sh, which took no --tag, expected you to `cd` into
# a checkout you had prepared yourself, and only PRINTED the packaging commands.
# CLAUDE.md claims every build/build-*.sh enforces --tag; this makes that true
# for vim, and produces all three artifacts in one run so terminal vim, gvim and
# the runtime can never drift to different patch levels.
#
# Prerequisites on the build machine (EL8):
#   sudo dnf install -y gcc make ncurses-devel gtk3-devel libX11-devel \
#                       libXt-devel libSM-devel libICE-devel
#   gcc-toolset-14 is sourced automatically when present.
#
# Usage (run from any directory):
#   ./build/build-vim.sh --tag v9.2.0901
#   ./build/build-vim.sh --tag v9.2.0901 --src /path/to/vim-9.2.0901.tar.gz
#
# Then, as for every payload change:
#   ./build/strip-all-elf-binaries
#   python3.14 build/gen-content-manifest

set -eu

REPO="$(cd "$(dirname "$0")/.." && pwd)"
PLATFORM=el8.x86_64.glibc2p28
BIN_DIR="$REPO/payload/$PLATFORM/bin"
RT_DIR="$REPO/payload/$PLATFORM/runtime"
TAG=""
SRC_TARBALL=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        --tag) shift; [ "$#" -gt 0 ] || { echo "missing value for --tag" >&2; exit 2; }; TAG="$1" ;;
        --src) shift; [ "$#" -gt 0 ] || { echo "missing value for --src" >&2; exit 2; }; SRC_TARBALL="$1" ;;
        -h|--help) sed -n '2,/^$/p' "$0"; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done

if [ -z "$TAG" ]; then
    echo "ERROR: --tag is required, e.g. --tag v9.2.0901" >&2
    echo "  Use a stable vim patch tag from https://github.com/vim/vim/tags" >&2
    exit 1
fi
VERSION="${TAG#v}"

need() { command -v "$1" >/dev/null 2>&1 || { echo "missing required command: $1" >&2; exit 1; }; }
need make
need bzip2
need tar

PATCHELF="$HOME/.local/bin/patchelf"
[ -x "$PATCHELF" ] || PATCHELF="$(command -v patchelf || true)"
[ -n "$PATCHELF" ] || { echo "ERROR: patchelf not found" >&2; exit 1; }

# gcc-toolset-14 for a consistent ABI with the rest of the payload.
# shellcheck disable=SC1091
[ -f /opt/rh/gcc-toolset-14/enable ] && . /opt/rh/gcc-toolset-14/enable

STAGE=$(mktemp -d /tmp/vim-build-XXXXXX)
trap 'rm -rf "$STAGE"' EXIT INT TERM

echo "==> Obtaining vim $TAG ..."
if [ -n "$SRC_TARBALL" ]; then
    [ -f "$SRC_TARBALL" ] || { echo "ERROR: --src $SRC_TARBALL not found" >&2; exit 1; }
    tar xzf "$SRC_TARBALL" -C "$STAGE"
else
    need git
    git clone --depth 1 --branch "$TAG" https://github.com/vim/vim "$STAGE/vim" >/dev/null 2>&1 \
        || { echo "ERROR: git clone of $TAG failed" >&2; exit 1; }
fi
SRC=$(find "$STAGE" -maxdepth 1 -mindepth 1 -type d | head -1)
[ -f "$SRC/src/main.c" ] || { echo "ERROR: $SRC is not a vim source tree" >&2; exit 1; }

# Confirm the checkout really is the requested patch level, so a mislabelled
# tarball cannot silently ship as another version.
PATCHLEVEL=$(awk '/^#define VIM_VERSION_SHORT/ {gsub(/"/,"",$3); print $3}' "$SRC/src/version.h" 2>/dev/null || true)
HIGHEST=$(awk '/^static int included_patches/,0' "$SRC/src/version.c" | grep -oE '^\s+[0-9]+,' | head -1 | tr -dc '0-9')
echo "    source reports ${PATCHLEVEL:-?} patch ${HIGHEST:-?} (requested $VERSION)"

CFLAGS_COMMON="-O2 -fno-strength-reduce -Wall -Wno-deprecated-declarations -D_REENTRANT -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=1"

# --- 1. terminal vim ---------------------------------------------------------
# --without-wayland is LOAD-BEARING. vim 9.2.07xx gained Wayland clipboard
# support, so without it terminal vim links libwayland-client.so.0 -- a lib that
# ships in gui_libs, which plain `vim` deliberately does not depend on.
echo "==> Building terminal vim ..."
( cd "$SRC" && ./configure --with-features=huge --enable-gui=no --without-x \
    --without-wayland --enable-multibyte CFLAGS="$CFLAGS_COMMON" >/dev/null )
( cd "$SRC" && make -j"$(nproc)" >/dev/null )
[ -x "$SRC/src/vim" ] || { echo "ERROR: terminal vim did not build" >&2; exit 1; }

cp "$SRC/src/vim" "$STAGE/vim.bin"
/usr/bin/strip "$STAGE/vim.bin"
"$PATCHELF" --set-rpath '$ORIGIN/../lib64:$ORIGIN/../lib' "$STAGE/vim.bin"

# Guard the --without-wayland trap: fail rather than ship a terminal vim that
# needs a gui_libs-only shared object.
if objdump -p "$STAGE/vim.bin" | awk '/NEEDED/ {print $2}' | grep -q '^libwayland-client'; then
    echo "ERROR: terminal vim NEEDs libwayland-client -- --without-wayland did not take." >&2
    echo "  plain vim must not depend on gui_libs; refusing to ship it." >&2
    exit 1
fi
echo "    terminal vim NEEDED: $(objdump -p "$STAGE/vim.bin" | awk '/NEEDED/ {printf "%s ", $2}')"

# --- 2. runtime archive ------------------------------------------------------
# Packed from the SOURCE TREE's runtime/, not `make install` output: install
# drops the spell binaries and other source-tree extras.
#
# Staged, NOT written into payload/ yet. Everything lands together at the end,
# so a failure in the gvim build below cannot leave a new runtime archive beside
# old binaries -- which is exactly what happened on the first 9.2.0901 run.
echo "==> Packing the vim runtime archive ..."
mkdir -p "$STAGE/rt"
cp -a "$SRC/runtime" "$STAGE/rt/runtime"
find "$STAGE/rt/runtime" -type d -name testdir -prune -exec rm -rf {} + 2>/dev/null || true
[ -f "$STAGE/rt/runtime/filetype.vim" ] || { echo "ERROR: runtime/filetype.vim missing" >&2; exit 1; }
[ -f "$STAGE/rt/runtime/spell/en.utf-8.spl" ] || { echo "ERROR: runtime/spell/en.utf-8.spl missing" >&2; exit 1; }
tar cjf "$STAGE/vim92.tar.bz2" -C "$STAGE/rt" ./runtime

# --- 3. gvim (GTK3) ----------------------------------------------------------
# EL8 back-port: vim 9.2.0901's PostScript printing path calls
# pango_font_metrics_get_height(), which Pango added in 1.44. EL8 ships Pango
# 1.42.3, so the GTK3 build fails with "implicit declaration of function
# 'pango_font_metrics_get_height'". The value is only used to derive extra line
# leading beyond ascent+descent; before vim adopted the call there was none, so
# a 0 fallback reproduces the older behaviour on old Pango. Guarded by version
# so a newer build host still gets upstream's code.
echo "==> Applying the EL8 Pango back-port ..."
python3.14 - "$SRC" <<'PYEOF'
import sys, os
src = sys.argv[1]
path = os.path.join(src, "src", "hardcopy_pango.c")
old = """	pctx.line_spacing = (double)
	    (pango_font_metrics_get_height(metrics) - (ascent + descent))
	    / PANGO_SCALE;
"""
new = """#if PANGO_VERSION_CHECK(1, 44, 0)
	pctx.line_spacing = (double)
	    (pango_font_metrics_get_height(metrics) - (ascent + descent))
	    / PANGO_SCALE;
#else
	/* pango_font_metrics_get_height() is Pango >= 1.44; EL8 has 1.42.
	 * No extra leading, which is what vim did before it adopted the call. */
	pctx.line_spacing = 0.0;
#endif
"""
s = open(path).read()
if new in s:
    print("    already patched")
elif old in s:
    open(path, "w").write(s.replace(old, new, 1))
    print("    patched src/hardcopy_pango.c")
else:
    sys.exit("PATCH TARGET MISSING in src/hardcopy_pango.c -- upstream changed; re-derive the EL8 Pango back-port.")
PYEOF

echo "==> Building gvim (GTK3) ..."
( cd "$SRC" && make distclean >/dev/null 2>&1 || true )
( cd "$SRC" && ./configure --with-features=huge --enable-gui=gtk3 --with-x \
    --enable-multibyte CFLAGS="$CFLAGS_COMMON" >/dev/null )
( cd "$SRC" && make -j"$(nproc)" >/dev/null )
[ -x "$SRC/src/vim" ] || { echo "ERROR: gvim did not build" >&2; exit 1; }

cp "$SRC/src/vim" "$STAGE/gvim.bin"
/usr/bin/strip "$STAGE/gvim.bin"
"$PATCHELF" --set-rpath '$ORIGIN/../lib64:$ORIGIN/../lib' "$STAGE/gvim.bin"

# gvim must be the GUI build; if GTK3 was not picked up it is just another
# terminal vim under a different name.
if ! objdump -p "$STAGE/gvim.bin" | awk '/NEEDED/ {print $2}' | grep -q '^libgtk-3'; then
    echo "ERROR: gvim does not NEED libgtk-3 -- the GTK3 GUI was not built." >&2
    exit 1
fi

# --- install into payload (all three together, only once everything built) ---
mkdir -p "$BIN_DIR" "$RT_DIR"
for f in vim.bin gvim.bin; do
    bzip2 -kf "$STAGE/$f"
    cp "$STAGE/$f.bz2" "$BIN_DIR/$f.bz2"
    chmod 644 "$BIN_DIR/$f.bz2"
done
cp "$STAGE/vim92.tar.bz2" "$RT_DIR/vim92.tar.bz2"
chmod 644 "$RT_DIR/vim92.tar.bz2"

# --- stamp the registry ------------------------------------------------------
python3.14 - "$REPO/payload/packages.json" "$VERSION" <<'PYEOF'
import json, re, sys
path, version = sys.argv[1], sys.argv[2]
raw = open(path).read()
for pkg in ("vim", "gvim"):
    pat = re.compile(r'("%s":\s*\{(?:[^{}]|\{[^{}]*\})*?"version":\s*")([^"]*)(")' % pkg)
    raw, n = pat.subn(lambda m: m.group(1) + version + m.group(3), raw, count=1)
    if n != 1:
        sys.exit("could not stamp %s version in packages.json" % pkg)
open(path, "w").write(raw)
print("    packages.json: vim + gvim -> %s" % version)
PYEOF

echo ""
echo "Staged:"
echo "  payload/$PLATFORM/bin/vim.bin.bz2"
echo "  payload/$PLATFORM/bin/gvim.bin.bz2"
echo "  payload/$PLATFORM/runtime/vim92.tar.bz2"
echo ""
echo "Next:"
echo "  ./build/strip-all-elf-binaries"
echo "  python3.14 build/gen-content-manifest"
