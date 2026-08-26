#!/bin/sh
# Build Environment Modules (envmodules/modules) from source for el8.x86_64.glibc2p28.
#
# Produces a native Environment Modules runtime archive rooted at lib/modules/:
# bin/, etc/, init/, lib/, libexec/, modulefiles/, and share/. It includes
# libtclenvmodules.so built against loadout Tcl 9.
#
# Modules 5.6.1 has no Unix relocatable configure mode. Configure under a
# distinctive local-root token, then make generated text use that token for
# tclsh. The installer replaces the token only within this package's runtime.
#
# Prerequisite: build Tcl first, then pass its tclConfig.sh directory:
#   ./build/build-tcl.sh --tag core-9-0-3
#   ./build/build-modules.sh --tag v5.6.1 \
#       --with-tcl /tmp/loadout-tcl-instdir-9.0.3/lib
#
# Policy: always build from a stable tagged release. See:
#   https://github.com/envmodules/modules/releases

set -eu

REPO="$(cd "$(dirname "$0")/.." && pwd)"
RUNTIME_DIR="$REPO/payload/el8.x86_64.glibc2p28/runtime"
TAG=""
WITH_TCL=""
RELOC_ROOT_TOKEN="/__LOADOUT_RELOC_ROOT__"
MODULES_PREFIX="$RELOC_ROOT_TOKEN/lib/modules"

while [ "$#" -gt 0 ]; do
    case "$1" in
        --tag)
            shift
            [ "$#" -gt 0 ] || { echo "missing value for --tag" >&2; exit 2; }
            TAG="$1"
            ;;
        --with-tcl)
            shift
            [ "$#" -gt 0 ] || { echo "missing value for --with-tcl" >&2; exit 2; }
            WITH_TCL="$1"
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
    echo "  $0 --tag v5.6.1 --with-tcl /tmp/loadout-tcl-instdir-9.0.3/lib" >&2
    exit 1
fi

[ -n "$WITH_TCL" ] || {
    echo "ERROR: --with-tcl is required; build loadout Tcl 9 first" >&2
    exit 1
}
[ -f "$WITH_TCL/tclConfig.sh" ] || {
    echo "ERROR: tclConfig.sh not found in $WITH_TCL" >&2
    exit 1
}

# Strip leading 'v' for the tarball filename.
VERSION="${TAG#v}"

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

need make
need readelf

TCL_EXEC_PREFIX="$(grep '^TCL_EXEC_PREFIX=' "$WITH_TCL/tclConfig.sh" | cut -d= -f2- | tr -d "'")"
[ -n "$TCL_EXEC_PREFIX" ] || {
    echo "ERROR: could not read TCL_EXEC_PREFIX from $WITH_TCL/tclConfig.sh" >&2
    exit 1
}
BUILD_TCLSH="$(find "$TCL_EXEC_PREFIX/bin" -maxdepth 1 -type f -name 'tclsh[0-9]*' | sort -V | tail -1)"
[ -x "$BUILD_TCLSH" ] || {
    echo "ERROR: Tcl executable not found below $TCL_EXEC_PREFIX/bin" >&2
    exit 1
}
echo "==> Using bundled Tcl: $BUILD_TCLSH ($WITH_TCL/tclConfig.sh)"

WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/build-modules-XXXXXX")
STAGE_PARENT=$(mktemp -d "${TMPDIR:-/tmp}/modules-stage-XXXXXX")
trap 'rm -rf "$WORK_DIR" "$STAGE_PARENT"' EXIT

echo "==> Downloading modules-${VERSION}.tar.bz2 ..."
curl -fL -o "$WORK_DIR/modules.tar.bz2" \
    "https://github.com/envmodules/modules/releases/download/${TAG}/modules-${VERSION}.tar.bz2"

echo "==> Extracting ..."
tar xjf "$WORK_DIR/modules.tar.bz2" -C "$WORK_DIR"
cd "$WORK_DIR/modules-${VERSION}"

echo "==> Configuring ..."
# DESTDIR below confines this absolute token prefix to STAGE_PARENT.
./configure \
    --prefix="$MODULES_PREFIX" \
    --disable-versioning \
    --disable-set-binpath \
    --disable-set-manpath \
    --disable-doc-install \
    --disable-vim-addons \
    --disable-emacs-addons \
    --disable-nagelfar-addons \
    --disable-example-modulefiles \
    --with-tclsh="$BUILD_TCLSH" \
    --with-tcl="$WITH_TCL"

echo "==> Building ..."
# Configure validates BUILD_TCLSH. Override only generated-file substitutions:
# runtime text must call the deployed loadout tclsh after token relocation.
make -j"$(nproc 2>/dev/null || echo 2)" TCLSH="$RELOC_ROOT_TOKEN/bin/tclsh"

echo "==> Installing ..."
make install DESTDIR="$STAGE_PARENT" TCLSH="$RELOC_ROOT_TOKEN/bin/tclsh"

STAGE_ROOT="$STAGE_PARENT$RELOC_ROOT_TOKEN"
MODULES_STAGE="$STAGE_ROOT/lib/modules"
MODULECMD="$MODULES_STAGE/libexec/modulecmd.tcl"
EXTENSION="$MODULES_STAGE/lib/libtclenvmodules.so"

[ -f "$MODULECMD" ] || {
    echo "ERROR: modulecmd.tcl not found at $MODULECMD after install" >&2
    exit 1
}
[ -f "$EXTENSION" ] || {
    echo "ERROR: libtclenvmodules.so not found at $EXTENSION after install" >&2
    exit 1
}

echo "==> Verifying modulecmd.tcl ..."
if "$BUILD_TCLSH" "$MODULECMD" bash --version 2>&1 | grep -qi "modules"; then
    echo "  OK: modulecmd.tcl responds to --version"
else
    echo "  ERROR: unexpected modulecmd.tcl --version output" >&2
    exit 1
fi

echo "==> Verifying native Tcl extension ..."
readelf -h "$EXTENSION" >/dev/null || {
    echo "ERROR: $EXTENSION is not ELF" >&2
    exit 1
}
if readelf -d "$EXTENSION" | grep -Eq '(RPATH|RUNPATH)'; then
    echo "ERROR: $EXTENSION has an unexpected RPATH/RUNPATH" >&2
    exit 1
fi
if grep -aqF "$RELOC_ROOT_TOKEN" "$EXTENSION" || grep -aqF "$BUILD_TCLSH" "$EXTENSION"; then
    echo "ERROR: token or build Tcl path leaked into $EXTENSION" >&2
    exit 1
fi
if EXTENSION="$EXTENSION" "$BUILD_TCLSH" <<'EOF'
load $::env(EXTENSION) Envmodules
if {[llength [info commands readFile]] != 1} {
    puts stderr "Envmodules Tcl extension did not provide readFile"
    exit 1
}
EOF
then
    echo "  OK: libtclenvmodules.so loads with bundled Tcl"
else
    echo "  ERROR: libtclenvmodules.so did not load with bundled Tcl" >&2
    exit 1
fi

echo "==> Verifying relocation token ..."
# Feed `find` through a temp file rather than `for file in $(find ...)`: the
# latter word-splits on IFS (breaks paths with spaces/globs), and a pipe into
# `while read` would run the loop in a subshell where token_files can't persist.
token_files=0
_token_list="$(mktemp)"
find "$MODULES_STAGE" -type f -print > "$_token_list"
while IFS= read -r file; do
    if grep -aqF "$RELOC_ROOT_TOKEN" "$file"; then
        if readelf -h "$file" >/dev/null 2>&1; then
            echo "ERROR: relocation token found in ELF: $file" >&2
            exit 1
        fi
        if ! grep -IqF "$RELOC_ROOT_TOKEN" "$file"; then
            echo "ERROR: relocation token found in non-text file: $file" >&2
            exit 1
        fi
        token_files=$((token_files + 1))
    fi
done < "$_token_list"
rm -f "$_token_list"
if [ "$token_files" -lt 20 ]; then
    echo "ERROR: expected token in at least 20 text files, found $token_files" >&2
    exit 1
fi
for file in bin/modulecmd etc/initrc init/bash libexec/modulecmd.tcl; do
    grep -Fq "$RELOC_ROOT_TOKEN" "$MODULES_STAGE/$file" || {
        echo "ERROR: expected relocation token missing from $file" >&2
        exit 1
    }
done
echo "  OK: token appears in $token_files text files and zero ELF files"

echo "==> Packaging ..."
mkdir -p "$MODULES_STAGE/share/licenses/modules" "$RUNTIME_DIR"
install -m 644 COPYING.GPLv2 "$MODULES_STAGE/share/licenses/modules/COPYING.GPLv2"

ARCHIVE="$RUNTIME_DIR/modules.tar.bz2"
tar cjf "$ARCHIVE" -C "$STAGE_ROOT" lib/modules
echo "  Wrote: $ARCHIVE ($(wc -c < "$ARCHIVE" | tr -d ' ') bytes)"

# Update packages.json version.
python3 -c "
import json, sys
path, ver = sys.argv[1], sys.argv[2]
with open(path) as f:
    data = json.load(f)
data['packages']['modules']['version'] = ver
with open(path, 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\\n')
print(f'packages.json: modules version -> {ver}')
" "$REPO/payload/packages.json" "$VERSION"

echo "==> Running strip-all-elf-binaries ..."
"$REPO/build/strip-all-elf-binaries"

echo ""
echo "Done."
echo ""
echo "Commit with:"
echo "  git add payload/el8.x86_64.glibc2p28/runtime/modules.tar.bz2 \\
          .strip-manifest payload/packages.json build/build-modules.sh"
echo "  git commit -m 'feat(payload): native Environment Modules ${VERSION} runtime'"
