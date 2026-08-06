#!/bin/sh
# Build the tmux-path-store wheel from a stable upstream tag and bundle it.
#
# First-party (github.com/smprather/tmux-path-store): a tmux window-name-keyed
# directory/file path store, driven by the shell aliases in
# envs/bash/global/bashrc (`p` / `cdp`). Pure Python, single runtime dependency
# (`rich`), so there is no compiled artifact and no per-platform wheel -- the
# wheel is `py3-none-any`.
#
# WHY THIS SCRIPT EXISTS: like liberty-filter, this package was bundled with no
# build script and no ADDING_BINARIES.md note, so nothing recorded where its wheel
# came from or how to refresh it. Every tool needs a note -- see the mandate at the
# top of ADDING_BINARIES.md.
#
# NOT `rolling_git`. ./build/update's rolling path builds from source HEAD and
# stamps a `git describe` version, which is right for tools upstream does not tag
# (text-serdes, time-plot). This project tags releases, so it is pinned like
# parity-plot: `--tag` only, no HEAD builds.
#
# DEPENDENCY CLOSURE: the only runtime dependency is `rich`, which the payload
# already ships for several other tools. The script ASSERTS that rather than
# assuming it, and refuses to bundle a wheel whose declared dependencies are not
# already present -- an offline install cannot fetch a missing wheel later, so a
# new upstream dependency has to be bundled deliberately, not discovered by a user.
#
# Usage (run from any directory):
#   /path/to/build-tmux-path-store.sh --tag v1.0.1

set -eu

REPO="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO/build/lib.sh"

PLATFORM="el8.x86_64.glibc2p28"
WHEELS_DIR="$REPO/payload/$PLATFORM/wheels"
CLONE_URL="https://github.com/smprather/tmux-path-store.git"
RELEASES_URL="https://github.com/smprather/tmux-path-store/releases"
PKG="tmux-path-store"
DIST="tmux_path_store"
# The console script is upstream's; it was `tmux_path_store` through v1.0.0 and is
# `tmux-path-store` from v1.0.1. Read from the built wheel, never assumed.
EXPECT_SCRIPT="tmux-path-store"

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

loadout_require_tag "$tag" "$0" "$RELEASES_URL" "v1.0.1"
loadout_require_cmds git uv python3.14

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
        echo "ERROR: tag $tag carries a pre-release version ($version)." >&2
        echo "  Tag a release commit instead; this repo ships stable versions." >&2
        exit 1 ;;
esac
echo "  version: $version"

echo "Building wheel ..."
mkdir -p "$workdir/dist"
uv build --wheel --out-dir "$workdir/dist" "$src" >"$workdir/build.log" 2>&1 || {
    echo "ERROR: uv build failed:" >&2; tail -20 "$workdir/build.log" >&2; exit 1; }
wheel=$(find "$workdir/dist" -maxdepth 1 -name "${DIST}-*.whl" -print | sort | head -1)
[ -n "$wheel" ] || { echo "ERROR: no ${DIST}-*.whl produced" >&2; exit 1; }
echo "  $(basename "$wheel")"

# The console-script name and the dependency closure both come from the wheel
# itself, so check the artifact rather than the repo files.
python3.14 - "$wheel" "$EXPECT_SCRIPT" "$WHEELS_DIR" <<'PYEOF'
import sys, zipfile, glob, os, re

wheel, expect_script, wheels_dir = sys.argv[1], sys.argv[2], sys.argv[3]
z = zipfile.ZipFile(wheel)

def read(suffix):
    hits = [n for n in z.namelist() if n.endswith(suffix)]
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
        "  Update EXPECT_SCRIPT here AND the 'bins' entry for tmux-path-store in\n"
        "  payload/packages.json -- the registry names the launcher the installer\n"
        "  expects, so a mismatch ships a tool the user cannot run."
    )
print(f"  console_scripts: {scripts[0]}")

# An offline install cannot fetch a wheel later, so every declared runtime
# dependency must already be in the payload wheelhouse.
have = set()
for path in glob.glob(os.path.join(wheels_dir, "*.whl")) + glob.glob(
    os.path.join(wheels_dir, "*.whl.part-000")
):
    have.add(os.path.basename(path).split("-")[0].lower().replace("_", "-"))
missing = []
for line in read("METADATA").splitlines():
    if not line.startswith("Requires-Dist:"):
        continue
    req = line[len("Requires-Dist:"):].strip()
    if ";" in req:            # environment marker / extra
        req, marker = req.split(";", 1)
        if "extra" in marker:
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
PYEOF

echo "Replacing the bundled wheel ..."
mkdir -p "$WHEELS_DIR"
# Prune the previous build first: a stale sibling would leave two versions of the
# same dist in --find-links and let uv resolve the wrong one.
find "$WHEELS_DIR" -maxdepth 1 -name "${DIST}-*.whl" -print -delete | sed 's/^/  removed /'
cp "$wheel" "$WHEELS_DIR/"
echo "  installed $(basename "$wheel")"

loadout_stamp_version "$PKG" "$version"

echo ""
echo "Next:"
echo "  python3.14 build/gen-content-manifest"
echo "  python3.14 build/gen-readme-table"
echo "  ./loadout completion bash > envs/bash/global/completions/loadout.bash"
echo "  tests/prebuilt-binaries"
echo "  git add payload/ .content-manifest build/build-${PKG}.sh \\"
echo "          build/ADDING_BINARIES.md payload/packages.json"
