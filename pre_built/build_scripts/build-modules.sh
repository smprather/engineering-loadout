#!/bin/sh
# Build Environment Modules (envmodules/modules) from source for el8.x86_64.glibc2p28.
#
# Produces a runtime archive containing modulecmd.tcl and a default modulefiles
# directory.  No ELF binaries — the archive is pure Tcl and is effectively
# platform-independent, but lives alongside other EL8 runtimes by convention.
#
# modules requires Tcl 8.5+; EL8 ships tcl-8.6 via the base repos.
# All shell integration (module/ml functions) is handled by the loadout's
# bash/global/modules-init.bash which uses $HOME-relative paths, so the
# archive is re-usable across usernames.
#
# modulecmd.tcl derives its MODULESHOME at runtime from [info script] — the
# directory containing modulecmd.tcl.  Building with any temp prefix therefore
# produces a fully portable script once deployed to ~/.local/lib/.
#
# Policy: always build from a stable tagged release. See stable tags at:
#   https://github.com/envmodules/modules/releases
# Tags are prefixed with "v", e.g. v5.6.1.
#
# Prerequisites on the build machine (EL8):
#   sudo dnf install tcl-devel autoconf make
#   # gcc-toolset-14 optional (not strictly needed; modules is pure Tcl)
#
# Usage (run from any directory):
#   ./pre_built/build_scripts/build-modules.sh --tag v5.6.1

set -eu

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
RUNTIME_DIR="$REPO/pre_built/el8.x86_64.glibc2p28/runtime"
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

need tclsh
need make

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
    --without-x \
    --without-tclx \
    --without-docs \
    --disable-versioning \
    --with-tclsh=/usr/bin/tclsh

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
if /usr/bin/tclsh "$MODULECMD" --version 2>&1 | grep -qi "modules"; then
    echo "  OK: modulecmd.tcl responds to --version"
else
    echo "  WARNING: unexpected --version output (continuing)"
fi

echo "==> Packaging ..."
mkdir -p "$REPO/pre_built/el8.x86_64.glibc2p28/runtime"

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

echo ""
echo "Done.  Next steps:"
echo "  cd $REPO"
echo "  ./strip_all_elf_binaries    # no-op for pure Tcl but updates manifest"
echo "  # Update packages.json version to ${VERSION}"
echo "  git add pre_built/el8.x86_64.glibc2p28/runtime/modules.tar.bz2 .strip-manifest packages.json"
echo "  git commit -m 'feat(modules): add Environment Modules ${VERSION}'"
