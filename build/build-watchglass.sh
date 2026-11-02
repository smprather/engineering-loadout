#!/bin/sh
# Build the watchglass wheel from a stable upstream tag and bundle it.
#
# First-party (github.com/smprather/watchglass): a user-space poller that runs
# watches (a config.toml + check + actions), observers and verified relay
# recipes, logging every poll as JSON lines and showing a read-only TUI.
#
# Pure Python (hatchling, `py3-none-any`) with runtime dependencies on
# rich, rich-click, textual and watchdog. The payload wheelhouse already had
# rich/rich-click and their shared deps; textual, watchdog, linkify-it-py and
# mdit-py-plugins were added with this package (see build/ADDING_BINARIES.md,
# "watchglass 2026.11.1"). No compiled artifact, no per-platform binary.
#
# NOT `rolling_git`. Upstream tags every release and publishes the same wheel
# to PyPI, so this is pinned like parity-plot/tmux-path-store: `--tag` only,
# no HEAD builds. Building from the tag (rather than downloading the PyPI
# wheel) keeps the script's version check honest and exercises the tag.
#
# Usage (run from any directory):
#   /path/to/build-watchglass.sh --tag v2026.11.1
#
# The build image has no `uv`; extract the payload's, as with tmux-path-store:
#   build/build-shell sh -c 'mkdir -p /tmp/uvbin \
#       && bzip2 -dc payload/el8.x86_64.glibc2p28/bin/uv.bin.bz2 >/tmp/uvbin/uv \
#       && chmod +x /tmp/uvbin/uv \
#       && PATH=/tmp/uvbin:$PATH build/build-watchglass.sh --tag v2026.11.1'

set -eu

REPO="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO/build/lib.sh"

PLATFORM="el8.x86_64.glibc2p28"
WHEELS_DIR="$REPO/payload/$PLATFORM/wheels"
CLONE_URL="https://github.com/smprather/watchglass.git"
RELEASES_URL="https://github.com/smprather/watchglass/releases"
PKG="watchglass"
DIST="watchglass"
EXPECT_SCRIPT="watchglass"
# The full runtime closure, for the registry's `wheels` list. Shared wheels are
# named because the manifest/size paths resolve per distribution, and because a
# refresh that changes the closure should have to say so here.
EXPECT_WHEELS="click linkify-it-py markdown-it-py mdit-py-plugins mdurl platformdirs pygments rich rich-click textual typing-extensions watchdog watchglass"

tag=""
while [ "$#" -gt 0 ]; do
    case "$1" in
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

loadout_require_tag "$tag" "$0" "$RELEASES_URL" "v2026.11.1"
loadout_require_cmds git uv python3.15

workdir=$(mktemp -d "${TMPDIR:-/tmp}/build-${PKG}.XXXXXX")
trap 'rm -rf "$workdir"' EXIT
src="$workdir/src"

echo "Cloning $PKG $tag ..."
git clone --quiet "$CLONE_URL" "$src"
git -C "$src" fetch --quiet --tags --force origin
git -C "$src" rev-parse "refs/tags/$tag" >/dev/null 2>&1 || {
    echo "ERROR: no such tag upstream: $tag" >&2
    echo "  Releases: $RELEASES_URL" >&2
    exit 1
}
git -C "$src" checkout --quiet --detach "refs/tags/$tag"

version=$(awk '/^\[project\]/{f=1;next} f&&/^version[[:space:]]*=/{gsub(/[",]/,"");print $3;exit}' "$src/pyproject.toml")
[ -n "$version" ] || { echo "ERROR: no [project] version in pyproject.toml" >&2; exit 1; }
case "$version" in
    *dev*|*rc*)
        echo "ERROR: refusing a pre-release version: $version" >&2
        exit 1
        ;;
esac
[ "${tag#v}" = "$version" ] || {
    echo "ERROR: tag $tag and pyproject version $version disagree" >&2
    exit 1
}
echo "  version: $version"

echo "Building wheel ..."
mkdir -p "$workdir/dist"
uv build --wheel --out-dir "$workdir/dist" "$src" >"$workdir/build.log" 2>&1 || {
    echo "ERROR: uv build failed:" >&2
    tail -20 "$workdir/build.log" >&2
    exit 1
}
wheel=$(find "$workdir/dist" -maxdepth 1 -name "${DIST}-*.whl" -print | sort | head -1)
[ -n "$wheel" ] || { echo "ERROR: no ${DIST}-*.whl produced" >&2; exit 1; }
echo "  $(basename "$wheel")"

# The console script, the declared runtime dependencies and the registry's
# wheel list all come from ARTIFACTS, not from pyproject.toml assumptions.
python3.15 - "$wheel" "$EXPECT_SCRIPT" "$WHEELS_DIR" "$REPO/payload/packages.json" "$EXPECT_WHEELS" <<'PYEOF'
import json
import os
import re
import sys
import zipfile

wheel, expect_script, wheels_dir, packages_json, expect_wheels = sys.argv[1:6]


def read(name):
    with zipfile.ZipFile(wheel) as z:
        hits = [n for n in z.namelist() if n.endswith(name)]
        return z.read(hits[0]).decode() if hits else ""


scripts, section = [], None
for line in read("entry_points.txt").splitlines():
    line = line.strip()
    if line.startswith("["):
        section = line
    elif line and section == "[console_scripts]":
        scripts.append(line.split("=", 1)[0].strip())
if scripts != [expect_script]:
    sys.exit(
        f"ERROR: wheel declares console_scripts {scripts}, expected ['{expect_script}'].\n"
        "  Update EXPECT_SCRIPT here AND the 'bins' entry for watchglass in\n"
        "  payload/packages.json -- the registry names the launcher the installer\n"
        "  expects, so a mismatch ships a tool the user cannot run."
    )
print(f"  console_scripts: {scripts[0]}")

# An offline install cannot fetch a wheel later, so every declared runtime
# dependency must already be in the payload wheelhouse. Environment markers
# that cannot apply to the Linux/cp315 target are skipped; an unreadable new
# marker form is treated as applying (fail closed).
have = set()
for path in os.listdir(wheels_dir):
    if path.endswith(".whl") or path.endswith(".whl.part-000"):
        have.add(path.split("-")[0].lower().replace("_", "-"))
missing = []
for line in read("METADATA").splitlines():
    if not line.startswith("Requires-Dist:"):
        continue
    req = line[len("Requires-Dist:"):].strip()
    marker = ""
    if ";" in req:
        req, marker = req.split(";", 1)
        marker = marker.strip()
    if "extra" in marker:
        continue
    if "win32" in marker or "Windows" in marker:
        continue
    name = re.split(r"[<>=!~\[\s]", req.strip(), maxsplit=1)[0].lower().replace("_", "-")
    if name and name not in have:
        missing.append(name)
if missing:
    sys.exit(
        f"ERROR: runtime dependencies not in the payload wheelhouse: {sorted(set(missing))}\n"
        "  Bundle them before shipping -- an offline install cannot fetch them."
    )
print("  runtime dependency closure already bundled")

registry = json.load(open(packages_json))["packages"].get("watchglass")
if registry is None:
    sys.exit("ERROR: payload/packages.json has no watchglass entry yet")
declared = sorted(registry.get("wheels", []))
expected = sorted(expect_wheels.split())
if declared != expected:
    sys.exit(
        "ERROR: registry watchglass wheels do not match this script's closure.\n"
        f"  registry: {declared}\n"
        f"  expected: {expected}\n"
        "  Update 'wheels' for watchglass in payload/packages.json (and this list)\n"
        "  in the same change, so the manifest/size paths cover the new wheels."
    )
print("  registry wheel list matches the declared closure")
PYEOF

echo "Replacing the bundled wheel ..."
mkdir -p "$WHEELS_DIR"
# Prune the previous build first: a stale sibling would leave two versions of the
# same dist in --find-links and let uv resolve the wrong one.
find "$WHEELS_DIR" -maxdepth 1 \( -name "${DIST}-*.whl" -o -name "${DIST}-*.whl.part-*" \) -print -delete | sed 's/^/  removed /'
cp "$wheel" "$WHEELS_DIR/"
echo "  installed $(basename "$wheel")"

loadout_stamp_version "$PKG" "$version"

echo ""
echo "Next:"
echo "  python3.15 build/gen-installed-sizes"
echo "  python3.15 build/gen-content-manifest   # AFTER sizes: it hashes installed-sizes.json"
echo "  python3.15 build/gen-readme-table"
echo "  ./loadout completion bash > envs/bash/global/completions/loadout.bash"
echo "  tests/install-watchglass"
echo "  git add payload/ .content-manifest payload/installed-sizes.json README.md \\"
echo "          build/build-watchglass.sh build/ADDING_BINARIES.md payload/packages.json"
