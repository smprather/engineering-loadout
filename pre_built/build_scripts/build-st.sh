#!/bin/sh
# Build suckless st terminal from source for el8.x86_64.glibc2p28,
# patched with the undercurl patch from https://st.suckless.org/patches/undercurl/
# so editor diagnostics (LSP/spell-check/lint underlines) render as smooth
# undercurls rather than plain underlines.
#
# Runtime deps (bundled in this repo's lib64/):
#   libX11, libXft, libfontconfig, libfreetype, libxcb, libpng16,
#   libICE, libSM (transitive via gui_libs)
# Runtime deps (system on EL8):
#   libm, librt, libutil, libc
#
# Build-time deps (system, EL8):
#   gcc, make, libX11-devel, libXft-devel, fontconfig-devel,
#   freetype-devel
#
# Policy: always build from a stable tagged release.
# Upstream tarballs:    https://dl.suckless.org/st/
# Upstream undercurl:   https://st.suckless.org/patches/undercurl/
#
# UNDERCURL_STYLE is fixed at UNDERCURL_CURLY (smooth sine wave, the classic
# undercurl look). Available styles in the patch: CURLY, SPIKY, CAPPED.
#
# Two patch hunks fail to apply automatically against st 0.9.3 because
# upstream st 0.9.3 added its own colon-subparam SGR handling and its own
# stub for SGR 58 (set underline color). This script applies the patch then
# manually edits st.c to:
#   1. add the readcolonargs() call after p = np in csiparse, and
#   2. drop st 0.9.3's no-op SGR 58 case in favour of the patch's
#      ucolor-applying version.
# If you bump the st tag, re-verify these two fixups still apply cleanly.
#
# Usage (run from any directory):
#   /path/to/build-st.sh --tag 0.9.3

set -eu

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
BIN_DIR="$REPO/pre_built/el8.x86_64.glibc2p28/bin"
PATCHELF="${HOME}/.local/bin/patchelf"
DIST_URL_BASE="https://dl.suckless.org/st"
UNDERCURL_PATCH_URL="https://st.suckless.org/patches/undercurl/st-undercurl-0.9-20240103.diff"

clean=0
tag=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --clean) clean=1 ;;
        --tag)
            shift
            [ "$#" -gt 0 ] || { echo "missing value for --tag" >&2; exit 2; }
            tag="$1"
            ;;
        -h|--help)
            sed -n '2,/^$/p' "$0"
            exit 0
            ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done

if [ -z "$tag" ]; then
    echo "ERROR: --tag is required. Specify a stable release tag, e.g.:" >&2
    echo "  $0 --tag 0.9.3" >&2
    echo "" >&2
    echo "Stable releases: https://dl.suckless.org/st/" >&2
    echo "" >&2
    echo "Policy: this project ships stable releases only." >&2
    echo "Nightly/dev builds are not accepted." >&2
    exit 1
fi

if [ -r /opt/rh/gcc-toolset-14/enable ]; then
    # shellcheck disable=SC1091
    . /opt/rh/gcc-toolset-14/enable
fi

need() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "missing required command: $1 — install the prerequisite packages listed in this script's header" >&2
        exit 1
    }
}

need gcc
need make
need pkg-config
need patch
need curl
need bzip2

SRCDIR="/tmp/st-${tag}"
PATCHFILE="/tmp/st-undercurl-${tag}.diff"
TARBALL="/tmp/st-${tag}.tar.gz"

if [ ! -d "$SRCDIR" ]; then
    if [ ! -f "$TARBALL" ]; then
        echo "Downloading st-${tag}..."
        curl -fsSL "${DIST_URL_BASE}/st-${tag}.tar.gz" -o "$TARBALL"
    fi
    tar -xzf "$TARBALL" -C /tmp

    if [ ! -f "$PATCHFILE" ]; then
        echo "Downloading undercurl patch..."
        curl -fsSL "$UNDERCURL_PATCH_URL" -o "$PATCHFILE"
    fi

    cd "$SRCDIR"
    echo "Applying undercurl patch (1 hunk expected to reject; will fix manually)..."
    patch -p1 < "$PATCHFILE" || true
    rm -f st.c.rej

    # Fixup 1: add readcolonargs() call after p = np in csiparse loop.
    # The patch hunk failed because st 0.9.3 has additional sep-handling lines.
    python3 - <<'PYEDIT'
import re, pathlib
p = pathlib.Path("st.c")
src = p.read_text()
target = "\t\tcsiescseq.arg[csiescseq.narg++] = v;\n\t\tp = np;\n\t\tif (sep == ';' && *p == ':')"
insert = "\t\tcsiescseq.arg[csiescseq.narg++] = v;\n\t\tp = np;\n\t\treadcolonargs(&p, csiescseq.narg-1, csiescseq.carg);\n\t\tif (sep == ';' && *p == ':')"
if target in src and "readcolonargs(&p, csiescseq.narg-1" not in src:
    src = src.replace(target, insert, 1)
    p.write_text(src)
    print("fixup 1: inserted readcolonargs() call")
else:
    print("fixup 1: skipped (already applied or pattern not found)")
PYEDIT

    # Fixup 2: drop st 0.9.3's no-op SGR 58 case; keep the patch's ucolor case.
    python3 - <<'PYEDIT'
import re, pathlib
p = pathlib.Path("st.c")
src = p.read_text()
stub = (
    "\t\tcase 58:\n"
    "\t\t\t/* This starts a sequence to change the color of\n"
    "\t\t\t * \"underline\" pixels. We don't support that and\n"
    "\t\t\t * instead eat up a following \"5;n\" or \"2;r;g;b\". */\n"
    "\t\t\ttdefcolor(attr, &i, l);\n"
    "\t\t\tbreak;\n"
)
if stub in src:
    src = src.replace(stub, "", 1)
    p.write_text(src)
    print("fixup 2: removed duplicate SGR 58 stub")
else:
    print("fixup 2: skipped (stub not found — patch layout may have changed)")
PYEDIT

    # UNDERCURL_STYLE = CURLY (project default; edit if you want SPIKY/CAPPED).
    sed -i 's/^#define UNDERCURL_STYLE UNDERCURL_SPIKY/#define UNDERCURL_STYLE UNDERCURL_CURLY/' config.def.h

    # Silence "erresc: unknown csi / set/reset mode" warnings on stderr.
    # Modern apps probe st for features it doesn't have (synchronized output
    # mode 2026, DECLRMM mode 69, etc.); logging every probe spams stderr.
    python3 - <<'PYEDIT'
import pathlib
p = pathlib.Path("st.c")
src = p.read_text()
patches = [
    (
        '\t\tfprintf(stderr, "erresc: unknown csi ");\n'
        '\t\tcsidump();\n'
        '\t\t/* die(""); */\n'
        '\t\tbreak;',
        '\t\t/* silently ignore unknown CSI escapes (feature probes from modern apps) */\n'
        '\t\tbreak;',
    ),
    (
        '\t\t\t\tfprintf(stderr,\n'
        '\t\t\t\t\t"erresc: unknown private set/reset mode %d\\n",\n'
        '\t\t\t\t\t*args);\n'
        '\t\t\t\tbreak;',
        '\t\t\t\t/* silently ignore unknown private set/reset modes */\n'
        '\t\t\t\tbreak;',
    ),
    (
        '\t\t\t\tfprintf(stderr,\n'
        '\t\t\t\t\t"erresc: unknown set/reset mode %d\\n",\n'
        '\t\t\t\t\t*args);\n'
        '\t\t\t\tbreak;',
        '\t\t\t\t/* silently ignore unknown set/reset modes */\n'
        '\t\t\t\tbreak;',
    ),
]
changed = 0
for old, new in patches:
    if old in src:
        src = src.replace(old, new, 1)
        changed += 1
p.write_text(src)
print("silence-warnings fixup: applied {} of 3 patches".format(changed))
PYEDIT
fi

cd "$SRCDIR"

if [ "$clean" -eq 1 ]; then
    make clean
fi

make -j"$(nproc 2>/dev/null || echo 8)"

echo ""
echo "Build complete: $(./st -v 2>&1 | head -1 || echo "st $tag built ($(stat -c%s st) bytes)")"
echo ""

# Strip → patchelf → bzip2 (order critical: stripping after patchelf corrupts
# .dynstr placement; see project_elf_bundling memory).
WORK="/tmp/st_work_${tag}"
cp st "$WORK"
strip "$WORK"
"$PATCHELF" --set-rpath '$ORIGIN/../lib64:$ORIGIN/../lib' "$WORK"
bzip2 -kf "$WORK"
cp "${WORK}.bz2" "$BIN_DIR/st.bz2"
rm -f "$WORK" "${WORK}.bz2"
echo "Installed: $BIN_DIR/st.bz2"

# packages.json version bump
ver="${tag}"
TOOLS_JSON="$REPO/pre_built/packages.json"
python3 -c "
import re, sys
path = sys.argv[1]; ver = sys.argv[2]
txt = open(path).read()
txt = re.sub(
    r'(\"st\"\s*:.*?\"version\":\s*\")([^\"]+)(\")',
    r'\g<1>' + ver + r'\3',
    txt,
    count=1,
    flags=re.DOTALL,
)
open(path, 'w').write(txt)
print('packages.json: st version -> ' + ver)
" "$TOOLS_JSON" "$ver"

# Update strip manifest
echo "Running strip_all_elf_binaries..."
"$REPO/strip_all_elf_binaries"

# glibc check
MAX_GLIBC="$(readelf -V "$SRCDIR/st" 2>/dev/null \
    | grep -oE 'GLIBC_[0-9]+\.[0-9]+' | sort -V | tail -1)"
echo "Max glibc symbol: $MAX_GLIBC (target: GLIBC_2.28)"
case "$MAX_GLIBC" in
    GLIBC_2.2[0-8]|GLIBC_2.1[0-9]|GLIBC_2.[0-9])
        echo "OK — binary compatible with EL8 glibc 2.28" ;;
    *)
        echo "WARNING: requires newer glibc than EL8 baseline" >&2 ;;
esac

echo ""
echo "Next steps:"
echo "  $REPO/pre_built/build_scripts/verify-binaries st"
echo "  git add $BIN_DIR/st.bz2 $TOOLS_JSON $REPO/.strip-manifest"
echo "  git commit -m 'feat(st): bump suckless st to ${ver} stable EL8 source build (undercurl + UNDERCURL_CURLY)'"
