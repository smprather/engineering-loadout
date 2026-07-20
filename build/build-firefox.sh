#!/bin/sh
# Shanghai-bundle Mozilla Firefox from the on-system EL8 RPM for
# el8.x86_64.glibc2p28.
#
# Firefox ships as a self-contained tree under /usr/lib64/firefox/ (libxul.so
# + a swarm of libmoz*.so, all linked with RPATH=$ORIGIN), so the only
# relocation work needed is to drop a thin POSIX-sh wrapper next to the
# binary tree.  Build process:
#
#   1. Update on-system Firefox to the freshest BaseOS RPM
#      (sudo dnf upgrade -y firefox).
#   2. Verify that rpm -q firefox matches the --tag argument so the
#      bundled tag and the actual binaries can't drift apart.
#   3. Stage:
#        STAGE/lib/firefox/   <- copy of /usr/lib64/firefox/
#        STAGE/bin/firefox    <- thin wrapper exec'ing firefox-bin
#   4. tar+bzip into payload/<plat>/runtime/firefox.tar.bz2 and let
#      strip-all-elf-binaries auto-chunk it into .part-NNN shards
#      (firefox is ~329 MB uncompressed / ~110 MB compressed -- well
#      above the 40 MiB chunking threshold).
#
# The Fedora-shipped /usr/bin/firefox launcher is intentionally NOT
# carried forward: it hardcodes /etc/gre.d/gre64.conf, /etc/fonts,
# /etc/firefox langpacks, and SELinux restorecon paths that don't apply
# to a relocatable $HOME install.  firefox-bin handles its own
# Wayland/X11 detection.
#
# NSS / NSPR are BUNDLED into lib/firefox/ (co-located, RPATH=$ORIGIN).
# Firefox 140's libxul.so requires NSS_3.107, newer than the NSS that
# AlmaLinux 8.10 shipped at GA (3.90).  An un-patched farm node aborts with
#   /lib64/libnss3.so: version `NSS_3.107' not found ... Couldn't load XPCOM
# The build box only has nss-3.112 because the firefox RPM pulled it in,
# which masked the gap until a dest node surfaced it (same build-box
# masking trap as the octave support libs).  We therefore carry the full
# NSS runtime closure (13 .so) inside the bundle; see the staging step.
#
# System libs still assumed present on the target (NOT bundled):
#   - glibc (libc/libm/libpthread/libdl/librt) -- policy
#   - libstdc++ / libgcc_s -- policy
#   - libsqlite3.so.0 -- softokn3 dep; EL8 base sqlite (3.26), identical on
#     build + dest, never security-bumped, so safe to leave external
#   - libtasn1.so.6   -- nssckbi dep; EL8 base, stable
#   - libasound2 -- alsa-lib, present on every EL8 desktop/farm node
#   - libfreetype / libfontconfig -- system; also in gui_libs
#
# gui_libs (declared as a depends in packages.json) covers the GTK3 /
# cairo / pango / X11 / Wayland stack libxul.so dlopens at runtime.
#
# Usage (run from any directory):
#   sudo dnf upgrade -y firefox
#   rpm -q firefox                      # capture e.g. firefox-140.11.0-1.el8_10.alma.1.x86_64
#   ./build/build-firefox.sh --tag 140.11.0

set -eu

REPO="$(cd "$(dirname "$0")/.." && pwd)"
RUNTIME_DIR="$REPO/payload/el8.x86_64.glibc2p28/runtime"
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
    echo "ERROR: --tag is required. Specify the exact Firefox version, e.g.:" >&2
    echo "  $0 --tag 140.11.0" >&2
    echo "" >&2
    echo "Capture with:  rpm -q firefox" >&2
    echo "" >&2
    echo "Policy: this project ships stable releases only." >&2
    exit 1
fi

need() {
    command -v "$1" >/dev/null 2>&1 || {
        printf 'missing required command: %s\n' "$1" >&2
        exit 1
    }
}

need rpm
need tar
need bzip2

SRC_DIR=/usr/lib64/firefox
SRC_BIN="$SRC_DIR/firefox-bin"

if [ ! -d "$SRC_DIR" ]; then
    echo "ERROR: $SRC_DIR not found -- install/upgrade firefox first:" >&2
    echo "  sudo dnf upgrade -y firefox" >&2
    exit 1
fi

if [ ! -x "$SRC_BIN" ]; then
    echo "ERROR: $SRC_BIN not found or not executable." >&2
    echo "  EL8 firefox normally ships both /usr/lib64/firefox/firefox" >&2
    echo "  and /usr/lib64/firefox/firefox-bin.  If only firefox is" >&2
    echo "  present on this distro, edit the wrapper below to exec" >&2
    echo "  \$prefix/lib/firefox/firefox instead." >&2
    exit 1
fi

INSTALLED_NVR=$(rpm -q firefox 2>/dev/null || true)
case "$INSTALLED_NVR" in
    firefox-${TAG}-*)
        echo "==> Confirmed installed firefox: $INSTALLED_NVR"
        ;;
    *)
        echo "ERROR: --tag $TAG does not match installed package $INSTALLED_NVR" >&2
        echo "  Update --tag to match, or run:  sudo dnf upgrade -y firefox" >&2
        exit 1
        ;;
esac

STAGE=$(mktemp -d /tmp/firefox-stage-XXXXXX)
trap 'rm -rf "$STAGE"' EXIT

echo "==> Staging Firefox tree from $SRC_DIR ..."
mkdir -p "$STAGE/bin" "$STAGE/lib"
# -a preserves perms + symlinks.  The firefox tree contains a few absolute
# symlinks that won't survive relocation:
#
#   dictionaries                       -> /usr/share/myspell  (Hunspell)
#   browser/defaults/preferences       -> /usr/lib64/firefox/defaults/preferences
#
# Both are rewritten below so the bundled tree is fully self-contained.
cp -a "$SRC_DIR" "$STAGE/lib/firefox"

# The Hunspell dictionaries symlink points outside the bundle.  Drop it --
# firefox still ships its own built-in spell data; users who want extra
# Hunspell dictionaries can install hunspell-* on the host and re-create
# the symlink in their $HOME profile.
if [ -L "$STAGE/lib/firefox/dictionaries" ]; then
    rm "$STAGE/lib/firefox/dictionaries"
fi

# Replace the absolute symlink browser/defaults/preferences ->
# /usr/lib64/firefox/defaults/preferences with a real directory holding a
# copy of the prefs files.  A relative symlink would work logically, but
# strip-all-elf-binaries' tar-rewrite step uses os.walk(followlinks=False)
# and never re-emits symlinks-to-directories, so the symlink would silently
# vanish from the bundled archive.  Copying the directory contents (a
# single ~2 KB .js file in EL8) sidesteps that and keeps the bundled
# Firefox standalone.
if [ -L "$STAGE/lib/firefox/browser/defaults/preferences" ]; then
    rm "$STAGE/lib/firefox/browser/defaults/preferences"
    mkdir -p "$STAGE/lib/firefox/browser/defaults/preferences"
    cp -a "$STAGE/lib/firefox/defaults/preferences/." \
          "$STAGE/lib/firefox/browser/defaults/preferences/"
fi

# Sanity: make sure no other absolute symlinks slipped through.
absolute_links=$(find "$STAGE/lib/firefox" -type l -lname '/*' 2>/dev/null || true)
if [ -n "$absolute_links" ]; then
    echo "ERROR: bundle still contains absolute symlinks:" >&2
    printf '  %s\n' $absolute_links >&2
    echo "  Update build-firefox.sh to rewrite them." >&2
    exit 1
fi

# --- Bundle the NSS / NSPR runtime closure into lib/firefox/ -------------
# Firefox 140 needs NSS_3.107 (see header).  Co-locate the EL8 nss .so set
# next to libxul.so; firefox-bin already runs with RPATH=$ORIGIN, and NSS
# dlopen's its softoken/freebl/ckbi plugins from libnss3's own directory,
# so stamping each with RPATH=$ORIGIN makes the closure self-resolving
# regardless of the host's (possibly older) system NSS.  Strip-before-
# patchelf per the repo ELF rule (nss RPM libs are already stripped, so
# strip is a near no-op, but keep the order).
PATCHELF="$HOME/.local/bin/patchelf"
command -v "$PATCHELF" >/dev/null 2>&1 || PATCHELF="$(command -v patchelf || true)"
[ -n "$PATCHELF" ] || { echo "ERROR: patchelf not found (need it to stamp NSS RPATH)" >&2; exit 1; }

NSS_LIBS="libnss3.so libnssutil3.so libsmime3.so libssl3.so libnspr4.so \
libplc4.so libplds4.so libsoftokn3.so libfreebl3.so libfreeblpriv3.so \
libnssdbm3.so libnssckbi.so libnsssysinit.so"
echo "==> Bundling NSS/NSPR closure into lib/firefox/ ..."
for nsslib in $NSS_LIBS; do
    src=$(readlink -f "/usr/lib64/$nsslib" 2>/dev/null || true)
    [ -n "$src" ] && [ -f "$src" ] || {
        echo "ERROR: /usr/lib64/$nsslib missing -- install nss/nspr first" >&2
        exit 1
    }
    dst="$STAGE/lib/firefox/$nsslib"
    cp "$src" "$dst"
    /usr/bin/strip "$dst" 2>/dev/null || true
    "$PATCHELF" --set-rpath '$ORIGIN' "$dst"
    chmod 755 "$dst"
done

# Firefox auto-mounts plugins from MOZ_PLUGIN_PATH; not needed for the
# default browser experience.  The optional system langpacks under
# /usr/lib64/firefox/langpacks are already included by the cp -a above.

echo "==> Writing wrapper $STAGE/bin/firefox ..."
cat > "$STAGE/bin/firefox" <<'EOF'
#!/bin/sh
# Wrapper for the engineering-loadout Firefox shanghai bundle.
# Derives the install prefix from this script's location so the same
# wrapper works from $HOME, --dest-dir staging trees, or shared
# release trees.
bin_dir=$(CDPATH= cd "$(dirname "$0")" && pwd -P) || exit 1
prefix=$(CDPATH= cd "$bin_dir/.." && pwd -P) || exit 1
libdir="$prefix/lib/firefox"
# Firefox 140's libxul.so needs NSS_3.107; the matching NSS/NSPR .so set is
# bundled in $libdir. firefox-bin loads libxul by absolute path but does NOT
# add its own directory to the loader search path for libxul's NEEDED libs,
# so without this libxul's libnss3 would resolve to the host's /lib64 copy
# (older on un-patched EL8 nodes) and abort with
#   "/lib64/libnss3.so: version `NSS_3.107' not found ... Couldn't load XPCOM".
# Prepend $libdir so the bundled NSS (and every other bundled .so) wins; this
# mirrors what the stock /usr/bin/firefox launcher does with LD_LIBRARY_PATH.
LD_LIBRARY_PATH="$libdir${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export LD_LIBRARY_PATH
exec "$libdir/firefox-bin" "$@"
EOF
chmod 755 "$STAGE/bin/firefox"

# Optional XDG desktop entry -- copied unmodified.  Users with a desktop
# session pick it up via XDG_DATA_DIRS=$HOME/.local/share:...; the .desktop
# file's Exec= line points at /usr/bin/firefox, which still works on EL8
# workstations as a fallback but the bundled wrapper is the intended path.
if [ -r /usr/share/applications/firefox.desktop ]; then
    mkdir -p "$STAGE/share/applications"
    cp /usr/share/applications/firefox.desktop "$STAGE/share/applications/"
fi

echo "==> Packaging ..."
mkdir -p "$RUNTIME_DIR"
ARCHIVE="$RUNTIME_DIR/firefox.tar.bz2"
# Wipe any stale chunked output from a prior build so strip-all-elf-binaries
# does not mistake yesterday's chunks for the current archive (manifest-hit
# is keyed by chunk0's sha -- stale chunks block reprocessing).
rm -f "$ARCHIVE" "$ARCHIVE".part-*
tar cjf "$ARCHIVE" -C "$STAGE" .
echo "  Wrote: $ARCHIVE ($(wc -c < "$ARCHIVE" | tr -d ' ') bytes)"

# Update packages.json version
python3 -c "
import sys, json
path, ver = sys.argv[1], sys.argv[2]
with open(path) as f:
    data = json.load(f)
pkgs = data['packages']
if 'firefox' in pkgs:
    pkgs['firefox']['version'] = ver
    print(f'packages.json: firefox version -> {ver}')
else:
    print('WARNING: firefox not in packages.json -- add the entry manually')
with open(path, 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
" "$REPO/payload/packages.json" "$TAG"

echo "==> Running strip-all-elf-binaries (this also auto-chunks the archive) ..."
"$REPO/strip-all-elf-binaries"

echo ""
echo "Done."
echo ""
echo "Commit with:"
echo "  git add payload/el8.x86_64.glibc2p28/runtime/firefox.tar.bz2* \\"
echo "          .strip-manifest payload/packages.json"
echo "  git commit -m 'feat(payload): firefox ${TAG} shanghai bundle'"
