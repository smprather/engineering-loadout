#!/bin/sh
# Build Environment Modules (envmodules/modules) from source for el8.x86_64.glibc2p28.
#
# Produces a runtime archive containing modulecmd.tcl and a default modulefiles
# directory.  No ELF binaries — the archive is pure Tcl and is effectively
# platform-independent, but lives alongside other EL8 runtimes by convention.
#
# modules requires Tcl 8.5+.  Build against the loadout-bundled Tcl when available
# (pass --with-tcl to the tclConfig.sh dir from a prior build-tcl.sh run), or fall
# back to system tclsh for the pure-Tcl build (--disable-libtclenvmodules).
#
# modulecmd.tcl derives its MODULESHOME at runtime from [info script] — the
# directory containing modulecmd.tcl.  Building with any temp prefix therefore
# produces a fully portable script once deployed to ~/.local/lib/.
#
# Policy: always build from a stable tagged release. See stable tags at:
#   https://github.com/envmodules/modules/releases
# Tags are prefixed with "v", e.g. v5.6.1.
#
# Usage (run from any directory):
#   ./pre_built/build_scripts/build-modules.sh --tag v5.6.1
#   ./pre_built/build_scripts/build-modules.sh --tag v5.6.1 \
#       --with-tcl /tmp/loadout-tcl-instdir-9.0.3/lib

set -eu

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
RUNTIME_DIR="$REPO/pre_built/el8.x86_64.glibc2p28/runtime"
TAG=""
WITH_TCL=""

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
    echo "  $0 --tag v5.6.1" >&2
    echo "" >&2
    echo "Stable releases: https://github.com/envmodules/modules/releases" >&2
    echo "" >&2
    echo "Policy: this project ships stable releases only." >&2
    exit 1
fi

# Strip leading 'v' for the tarball filename
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

# Determine tclsh and configure flags for libtclenvmodules C extension
if [ -n "$WITH_TCL" ]; then
    if [ ! -f "$WITH_TCL/tclConfig.sh" ]; then
        echo "ERROR: tclConfig.sh not found in $WITH_TCL" >&2
        exit 1
    fi
    TCLSH="$(grep '^TCL_EXEC_PREFIX=' "$WITH_TCL/tclConfig.sh" | cut -d= -f2 | tr -d "'")/bin/tclsh"
    # Try versioned name too
    [ -x "$TCLSH" ] || TCLSH="$(find "$(dirname "$TCLSH")" -name 'tclsh[0-9]*' | sort -V | tail -1)"
    CONFIGURE_TCL="--with-tcl=$WITH_TCL"
    echo "==> Using provided Tcl: tclConfig.sh from $WITH_TCL"
else
    # Auto-detect: prefer loadout-bundled, fall back to system
    TCLSH=""
    for candidate in \
        "$HOME/.local/bin/tclsh" \
        /usr/bin/tclsh \
        /usr/local/bin/tclsh; do
        if [ -x "$candidate" ]; then
            TCLSH="$candidate"
            break
        fi
    done
    if [ -z "$TCLSH" ]; then
        echo "ERROR: tclsh not found; provide --with-tcl or ensure tclsh is on PATH" >&2
        exit 1
    fi
    echo "==> Using tclsh: $TCLSH (no --with-tcl provided; building pure-Tcl)"
    CONFIGURE_TCL="--disable-libtclenvmodules"
fi

echo "    tclsh: $TCLSH"

WORK_DIR=$(mktemp -d /tmp/build-modules-XXXXXX)
INST_DIR=$(mktemp -d /tmp/inst-modules-XXXXXX)
trap 'rm -rf "$WORK_DIR" "$INST_DIR"' EXIT

echo "==> Downloading modules-${VERSION}.tar.bz2 ..."
curl -fL -o "$WORK_DIR/modules.tar.bz2" \
    "https://github.com/envmodules/modules/releases/download/${TAG}/modules-${VERSION}.tar.bz2"

echo "==> Extracting ..."
tar xjf "$WORK_DIR/modules.tar.bz2" -C "$WORK_DIR"
cd "$WORK_DIR/modules-${VERSION}"

echo "==> Configuring ..."
# Use a temp prefix; modulecmd.tcl is self-locating via [info script] so the
# built-in prefix path is irrelevant once deployed.
./configure \
    --prefix="$INST_DIR" \
    --libexecdir="$INST_DIR/lib" \
    --disable-versioning \
    --with-tclsh="$TCLSH" \
    $CONFIGURE_TCL

echo "==> Building ..."
make -j"$(nproc 2>/dev/null || echo 2)"

echo "==> Installing ..."
make install

MODULECMD="$INST_DIR/lib/modulecmd.tcl"
if [ ! -f "$MODULECMD" ]; then
    echo "ERROR: modulecmd.tcl not found at $MODULECMD after install" >&2
    exit 1
fi

echo "==> Verifying modulecmd.tcl ..."
if "$TCLSH" "$MODULECMD" --version 2>&1 | grep -qi "modules"; then
    echo "  OK: modulecmd.tcl responds to --version"
else
    echo "  WARNING: unexpected --version output (continuing)"
fi

echo "==> Packaging ..."
mkdir -p "$RUNTIME_DIR"

STAGE=$(mktemp -d /tmp/modules-stage-XXXXXX)
trap 'rm -rf "$WORK_DIR" "$INST_DIR" "$STAGE"' EXIT

mkdir -p "$STAGE/lib" "$STAGE/share/modulefiles"
cp "$MODULECMD" "$STAGE/lib/modulecmd.tcl"

# Default modulespath: tells modules to look in ~/modulefiles and ~/privatemodules.
# modules 5.x reads MODULESHOME/../etc/modulespath if present.
mkdir -p "$STAGE/etc"
printf '~/modulefiles\n~/privatemodules\n' > "$STAGE/etc/modulespath"

ARCHIVE="$RUNTIME_DIR/modules.tar.bz2"
tar cjf "$ARCHIVE" -C "$STAGE" .
echo "  Wrote: $ARCHIVE ($(wc -c < "$ARCHIVE" | tr -d ' ') bytes)"

# Update packages.json version
python3 -c "
import re, sys, json
path, ver = sys.argv[1], sys.argv[2]
with open(path) as f:
    data = json.load(f)
pkgs = data['packages']
if 'modules' in pkgs:
    pkgs['modules']['version'] = ver
    print(f'packages.json: modules version -> {ver}')
with open(path, 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
" "$REPO/pre_built/packages.json" "$VERSION"

echo "==> Running strip_all_elf_binaries ..."
"$REPO/strip_all_elf_binaries"

echo ""
echo "Done."
echo ""
echo "Commit with:"
echo "  git add pre_built/el8.x86_64.glibc2p28/runtime/modules.tar.bz2 \\"
echo "          .strip-manifest pre_built/packages.json"
echo "  git commit -m 'feat(pre_built): environment modules ${VERSION} EL8 build'"
