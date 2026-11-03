#!/bin/sh
# Build one python-build-standalone (PBS) interpreter and bundle it as a
# loadout runtime archive.
#
# Source: astral-sh/python-build-standalone, `install_only_stripped`,
# x86_64-unknown-linux-gnu -- the same builds uv itself downloads. They are
# NOT built through the portable-python PGO/LTO/BOLT pipeline (hours per
# version, no benefit for a secondary interpreter). The archive ships as
#   payload/el8.x86_64.glibc2p28/runtime/python-<minor>.tar.bz2
# and the generic runtime-archive installer extracts it to
#   <prefix>/opt/python/<minor>
# (packages.json install_to), so patch updates land in place and every venv
# built from that path keeps working.
#
# Usage (run from any directory):
#   build/build-shell sh -c 'build/build-python-standalone.sh \
#       --tag 20261026 --version 3.12.16'
#
# The build is run inside build/build-shell even though it compiles nothing:
# repacking the archive is payload-mutating, and the EL8 bzip2 round-trip is
# part of the reproducibility contract (AGENTS.md, Build Machine Mandate).
#
# What it does:
#   1. Downloads the release SHA256SUMS and the pinned asset.
#   2. Verifies the asset against its exact SHA256SUMS line.
#   3. Extracts to a scratch dir; the PBS tarball's top level is `python/`.
#   4. Injects the CA sitecustomize hook (PBS compiles OpenSSL's default paths
#      against its build prefix, which does not exist after deployment; EL8's
#      /etc/ssl/cert.pem does not exist either). A hook the build already
#      ships is renamed to sitecustomize_pbs.py and still runs.
#   5. Writes LOADOUT_BUILD (source URL, tag, version, sha256).
#   6. Asserts the highest referenced GLIBC symbol is <= 2.28 and smoke-runs
#      the interpreter (ssl, sqlite3, zlib).
#   7. Repacks bin include lib share LOADOUT_BUILD and stamps the registry
#      entry python-<minor> to the exact patch version.

set -eu

REPO="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO/build/lib.sh"

PLATFORM="el8.x86_64.glibc2p28"
RUNTIME_DIR="$REPO/payload/$PLATFORM/runtime"
RELEASES_URL="https://github.com/astral-sh/python-build-standalone/releases"
SITECUSTOMIZE_SRC="$REPO/build/portable-python-sitecustomize.py"
GLIBC_FLOOR="2.28"

usage() {
    sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
}

die() {
    echo "build-python-standalone: $*" >&2
    exit 1
}

tag=""
version=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --tag)
            shift
            [ "$#" -gt 0 ] || { echo "missing value for --tag" >&2; exit 2; }
            tag="$1"
            ;;
        --version)
            shift
            [ "$#" -gt 0 ] || { echo "missing value for --version" >&2; exit 2; }
            version="$1"
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            echo "unknown option: $1" >&2
            exit 2
            ;;
    esac
    shift
done

loadout_require_tag "$tag" "build-python-standalone.sh" "$RELEASES_URL"
if ! printf '%s\n' "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    die "--version must be an exact X.Y.Z release, got '$version'"
fi
loadout_require_cmds curl sha256sum tar bzip2 readelf grep sort cut awk

minor=$(printf '%s\n' "$version" | cut -d. -f1-2)
pkg="python-$minor"
asset="cpython-$version+$tag-x86_64-unknown-linux-gnu-install_only_stripped.tar.gz"
asset_url="$RELEASES_URL/download/$tag/$asset"
sums_url="$RELEASES_URL/download/$tag/SHA256SUMS"
out="$RUNTIME_DIR/$pkg.tar.bz2"

work=$(mktemp -d "${TMPDIR:-/tmp}/loadout-pbs-$pkg.XXXXXX")
cleanup() {
    rm -rf "$work"
}
trap cleanup EXIT HUP INT TERM

echo "==> $pkg $version (tag $tag)"
curl -fsSL --retry 3 -o "$work/SHA256SUMS" "$sums_url" || die "cannot download $sums_url"
curl -fsSL --retry 3 -o "$work/$asset" "$asset_url" || die "cannot download $asset_url"

want_sha=$(awk -v a="$asset" '$2 == a || $2 == "*" a { print $1; exit }' "$work/SHA256SUMS")
[ -n "$want_sha" ] || die "$asset has no SHA256SUMS entry in tag $tag"
got_sha=$(sha256sum "$work/$asset" | cut -d' ' -f1)
[ "$got_sha" = "$want_sha" ] || die "sha256 mismatch for $asset: $got_sha != $want_sha"
echo "    sha256 $got_sha"

mkdir -p "$work/tree"
tar -xzf "$work/$asset" -C "$work/tree" || die "cannot extract $asset"
tree="$work/tree/python"
[ -x "$tree/bin/python$minor" ] || die "archive has no bin/python$minor"
[ -d "$tree/lib" ] || die "archive has no lib/"

# CA injection. PBS ships no startup hook of its own; if a future build adds
# one, keep it (the injected file imports it) and make the injected file run
# first, exactly as import-portable-python does for sitecustomize_portable.
hook="$tree/lib/python$minor/sitecustomize.py"
if [ -f "$hook" ]; then
    mv "$hook" "$tree/lib/python$minor/sitecustomize_pbs.py"
    echo "    existing sitecustomize preserved as sitecustomize_pbs.py"
fi
cp "$SITECUSTOMIZE_SRC" "$hook"

cat > "$tree/LOADOUT_BUILD" <<EOF
package: $pkg
version: $version
tag: $tag
source: $asset_url
sha256: $got_sha
layout: install_only_stripped, x86_64-unknown-linux-gnu, repacked for
  loadout with the CA sitecustomize hook (build/portable-python-sitecustomize.py)
  and installed at <prefix>/opt/python/$minor.
EOF

max_glibc=$(readelf -V "$tree/bin/python$minor" \
    | grep -oE 'GLIBC_[0-9]+\.[0-9]+' \
    | sed 's/^GLIBC_//' \
    | sort -V \
    | tail -1)
[ -n "$max_glibc" ] || die "cannot determine the GLIBC floor of bin/python$minor"
[ "$(printf '%s\n%s\n' "$max_glibc" "$GLIBC_FLOOR" | sort -V | tail -1)" = "$GLIBC_FLOOR" ] \
    || die "bin/python$minor references GLIBC_$max_glibc, above the EL8 floor $GLIBC_FLOOR"
echo "    max GLIBC $max_glibc"

"$tree/bin/python$minor" -c 'import sys, ssl, sqlite3, zlib; print("    smoke:", sys.version)'

mkdir -p "$RUNTIME_DIR"
rm -f "$out"
items="bin include lib share LOADOUT_BUILD"
[ -f "$tree/BUILD" ] && items="$items BUILD"
# shellcheck disable=SC2086  # items is a deliberate word list
tar -C "$tree" -cjf "$out" $items || die "cannot write $out"

loadout_stamp_version "$pkg" "$version"
echo "    archive $(stat -c%s "$out") bytes sha256 $(sha256sum "$out" | cut -d' ' -f1)"
