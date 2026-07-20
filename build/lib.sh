# shellcheck shell=sh
# Shared helpers for build/build-*.sh (POSIX sh; source, do not execute).
#
# Usage at the top of a build script:
#   REPO="$(cd "$(dirname "$0")/.." && pwd)"
#   . "$REPO/build/lib.sh"
#
# Provides:
#   loadout_require_tag TAG SCRIPT RELEASES_URL [EXAMPLE]
#       Exit 2 with the standard stable-release-policy message when TAG is
#       empty. Every third-party build script must require --tag.
#   loadout_enable_gcc_toolset
#       Source /opt/rh/gcc-toolset-14/enable when present (no-op otherwise).
#   loadout_require_cmds CMD...
#       Exit 1 naming the first missing command.
#   loadout_package_bin SRC_BIN DEST_STEM [RPATH]
#       strip -> patchelf --set-rpath (default '$ORIGIN/../lib64:$ORIGIN/../lib')
#       -> bzip2 -> $REPO/payload/<platform>/bin/DEST_STEM.bz2 (mode 644).
#       Order is load-bearing: NEVER strip after patchelf (see AGENTS.md).
#   loadout_stamp_version PKG VERSION
#       Surgically update the package's "version" in payload/packages.json.
#   loadout_report_max_glibc BIN
#       Print the highest GLIBC_x.y version symbol the binary references.
#
# Scripts still own their own arg parsing and build steps -- only the
# boilerplate that was copy-pasted across ~30 scripts lives here.

LOADOUT_PLATFORM="${LOADOUT_PLATFORM:-el8.x86_64.glibc2p28}"
LOADOUT_BIN_DIR="${LOADOUT_BIN_DIR:-$REPO/payload/$LOADOUT_PLATFORM/bin}"
LOADOUT_PATCHELF="${LOADOUT_PATCHELF:-$HOME/.local/bin/patchelf}"

loadout_require_tag() {
    _lt_tag=$1
    _lt_script=$2
    _lt_url=$3
    _lt_example=${4:-vX.Y.Z}
    if [ -z "$_lt_tag" ]; then
        {
            echo "ERROR: --tag is required. Specify a stable release tag, e.g.:"
            echo "  $_lt_script --tag $_lt_example"
            echo ""
            echo "Stable releases: $_lt_url"
            echo ""
            echo "Policy: this project ships stable releases only."
            echo "Nightly/dev builds are not accepted."
        } >&2
        exit 2
    fi
}

loadout_enable_gcc_toolset() {
    if [ -r /opt/rh/gcc-toolset-14/enable ]; then
        # shellcheck disable=SC1091
        . /opt/rh/gcc-toolset-14/enable
    fi
}

loadout_require_cmds() {
    for _lc_cmd in "$@"; do
        command -v "$_lc_cmd" > /dev/null 2>&1 || {
            echo "missing required command: $_lc_cmd" >&2
            exit 1
        }
    done
}

loadout_package_bin() {
    _lp_src=$1
    _lp_stem=$2
    # shellcheck disable=SC2016  # $ORIGIN is an ld.so token, not a shell var
    _lp_rpath=${3:-'$ORIGIN/../lib64:$ORIGIN/../lib'}
    [ -f "$_lp_src" ] || { echo "loadout_package_bin: no such binary: $_lp_src" >&2; exit 1; }
    [ -x "$LOADOUT_PATCHELF" ] || { echo "missing patchelf at $LOADOUT_PATCHELF" >&2; exit 1; }
    _lp_work=$(mktemp "${TMPDIR:-/tmp}/loadout-pkg-${_lp_stem}.XXXXXX")
    cp "$_lp_src" "$_lp_work"
    strip "$_lp_work"
    "$LOADOUT_PATCHELF" --set-rpath "$_lp_rpath" "$_lp_work"
    bzip2 -f "$_lp_work"
    mkdir -p "$LOADOUT_BIN_DIR"
    cp "${_lp_work}.bz2" "$LOADOUT_BIN_DIR/${_lp_stem}.bz2"
    chmod 644 "$LOADOUT_BIN_DIR/${_lp_stem}.bz2"
    rm -f "${_lp_work}.bz2"
    echo "Packaged: $LOADOUT_BIN_DIR/${_lp_stem}.bz2"
}

loadout_stamp_version() {
    _lv_pkg=$1
    _lv_ver=$2
    python3 - "$REPO/payload/packages.json" "$_lv_pkg" "$_lv_ver" << 'PYEOF'
import re
import sys

path, pkg, ver = sys.argv[1:4]
txt = open(path).read()
pat = r'("%s": \{[^{}]*?"version":\s*")([^"]*)(")' % re.escape(pkg)
new, n = re.subn(pat, lambda m: m.group(1) + ver + m.group(3), txt, count=1, flags=re.S)
if n != 1:
    sys.exit(f"could not stamp version for package {pkg!r} in {path}")
open(path, "w").write(new)
print(f"packages.json: {pkg} version -> {ver}")
PYEOF
}

loadout_report_max_glibc() {
    _lg_max=$(readelf -V "$1" 2> /dev/null | grep -oE 'GLIBC_[0-9]+\.[0-9]+' | sort -V | tail -1)
    echo "Max glibc symbol: ${_lg_max:-none} (target: GLIBC_2.28)"
}
