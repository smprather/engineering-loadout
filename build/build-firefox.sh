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
# masking trap as the octave support libs).  We therefore carry the NSS
# runtime closure inside the bundle -- EXCEPT the trust module
# (libnssckbi/libnsssysinit): those must stay system-provided, or the
# bundle breaks TLS on every non-EL8 distro (see the NSS_LIBS comment).
#
# libffi.so.6 + libjpeg.so.62 are BUNDLED too (co-located, RPATH=$ORIGIN).
# libxul.so NEEDEDs both EL8 sonames; hosts with newer userlands (Arch etc.)
# have no .so.6 (libffi 3.4 bumped to .so.8) and no .so.62 (libjpeg-turbo 3
# bumped to .so.8).  Bundle them next to libxul so the wrapper can keep its
# loader path INSIDE the bundle ($libdir only): prepending $prefix/lib64
# (gui_libs) instead would shadow the host's GTK3/dbus/etc with the EL8-era
# gui_libs copies on newer hosts and break theme engines / spawned helpers --
# firefox must run against the HOST desktop stack wherever it provides the
# sonames, carrying only what the host cannot supply.  Both are copied from
# /usr/lib64 on the EL8 build box, same as the NSS set.
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
#   On the EL8 build box (default path -- system dnf install):
#     sudo dnf upgrade -y firefox
#     rpm -q firefox                    # capture e.g. firefox-140.11.0-1.el8_10.alma.1.x86_64
#     ./build/build-firefox.sh --tag 140.11.0
#
#   Offline / non-EL8 host (rpm staging path -- used for the 140.14.0 bump,
#   which was built from Alma repo rpms on a CachyOS box because the EL8
#   build box was unavailable):
#     ./build/build-firefox.sh --tag 140.14.0 \
#         --from-rpms <dir with firefox-*.rpm + nss/nspr/nss-util/nss-softokn/
#                      nss-softokn-freebl rpms from the same Alma 8 repo>
#
#   --from-rpms stages from the extracted rpm trees instead of /usr/lib64:
#   firefox tree from the firefox rpm; NSS/NSPR closure from the nss rpms;
#   libffi.so.6 + libjpeg.so.62 from the loadout payload copies (EL8 bytes,
#   repo-proven).  The rpm NVR must match --tag, same as the dnf path.

set -eu

REPO="$(cd "$(dirname "$0")/.." && pwd)"
RUNTIME_DIR="$REPO/payload/el8.x86_64.glibc2p28/runtime"
TAG=""
FROM_RPMS=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        --tag)
            shift
            [ "$#" -gt 0 ] || { echo "missing value for --tag" >&2; exit 2; }
            TAG="$1"
            ;;
        --from-rpms)
            shift
            [ "$#" -gt 0 ] || { echo "missing value for --from-rpms" >&2; exit 2; }
            FROM_RPMS="$1"
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

need tar
need bzip2
PATCHELF="$HOME/.local/bin/patchelf"
command -v "$PATCHELF" >/dev/null 2>&1 || PATCHELF="$(command -v patchelf || true)"
[ -n "$PATCHELF" ] || { echo "ERROR: patchelf not found" >&2; exit 1; }

STAGE=$(mktemp -d "${TMPDIR:-/tmp}/firefox-stage-XXXXXX")
trap 'rm -rf "$STAGE" ${_RPMS_EXTRACT:-}' EXIT

if [ -n "$FROM_RPMS" ]; then
    # ---- Offline rpm-staging path (--from-rpms) --------------------------
    # Stage from Alma 8 repo rpms instead of the build box's installed tree.
    # The firefox NVR embedded in the rpm filenames must match --tag.
    need bsdtar
    [ -d "$FROM_RPMS" ] || { echo "ERROR: --from-rpms dir not found: $FROM_RPMS" >&2; exit 1; }
    FF_RPM=$(ls "$FROM_RPMS"/firefox-"${TAG}"-*.x86_64.rpm 2>/dev/null | head -1)
    [ -n "$FF_RPM" ] || {
        echo "ERROR: no firefox-${TAG}-*.x86_64.rpm in $FROM_RPMS" >&2
        echo "  Download from https://repo.almalinux.org/almalinux/8/AppStream/x86_64/os/Packages/" >&2
        exit 1
    }
    NSS_RPMS=""
    for n in "nspr-" "nss-3" "nss-util-" "nss-softokn-3" "nss-softokn-freebl-"; do
        r=$(ls "$FROM_RPMS"/"$n"*.x86_64.rpm 2>/dev/null | sort -V | tail -1)
        [ -n "$r" ] || { echo "ERROR: no ${n}* rpm in $FROM_RPMS" >&2; exit 1; }
        NSS_RPMS="$NSS_RPMS $r"
    done
    R=$(mktemp -d "${TMPDIR:-/tmp}/firefox-rpms-XXXXXX")
    # keep the extraction dir alive past this block's scope alongside $STAGE
    _RPMS_EXTRACT="$R"
    for r in "$FF_RPM" $NSS_RPMS; do
        bsdtar -xf "$r" -C "$R" 2>/dev/null
    done
    SRC_DIR="$R/usr/lib64/firefox"
    SRC_NSS_DIR="$R/usr/lib64"
else
    # ---- Default path: build box's dnf-managed system tree ----------------
    need rpm
    SRC_DIR=/usr/lib64/firefox
    SRC_NSS_DIR=/usr/lib64
fi

SRC_BIN="$SRC_DIR/firefox-bin"

if [ ! -d "$SRC_DIR" ]; then
    if [ -n "$FROM_RPMS" ]; then
        echo "ERROR: firefox rpm did not unpack a /usr/lib64/firefox tree" >&2
    else
        echo "ERROR: $SRC_DIR not found -- install/upgrade firefox first:" >&2
        echo "  sudo dnf upgrade -y firefox" >&2
    fi
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

if [ -z "$FROM_RPMS" ]; then
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
fi

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

# --- Bundle the NSS / NSPR + libffi runtime closure into lib/firefox/ -----
# Firefox 140 needs NSS_3.107 (see header); libxul NEEDEDs libffi.so.6 (see
# header).  Co-locate the EL8 .so set next to libxul.so; firefox-bin already
# runs with RPATH=$ORIGIN, and NSS dlopen's its softoken/freebl/ckbi plugins
# from libnss3's own directory, so stamping each with RPATH=$ORIGIN makes the
# closure self-resolving regardless of the host's system NSS/libffi.  Strip-
# before-patchelf per the repo ELF rule (nss RPM libs are already stripped, so
# strip is a near no-op, but keep the order).
PATCHELF="$HOME/.local/bin/patchelf"
command -v "$PATCHELF" >/dev/null 2>&1 || PATCHELF="$(command -v patchelf || true)"
[ -n "$PATCHELF" ] || { echo "ERROR: patchelf not found (need it to stamp NSS RPATH)" >&2; exit 1; }

# NSS_LIBS deliberately EXCLUDES libnssckbi.so -- the trust module must stay
# system-provided (this is also what Mozilla's official Linux tarballs do: they
# ship no ckbi either).  On EL8/Fedora /usr/lib64/libnssckbi.so is an
# alternatives symlink to p11-kit-trust.so, a PROXY that reads the trust store
# from hardcoded distro paths (/etc/pki/ca-trust/...).  Bundling that proxy
# made firefox show SEC_ERROR_UNKNOWN_ISSUER for every HTTPS site on any other
# distro (Arch-family trust lives in /etc/ssl/certs) -- classic build-box
# masking, same shape as the NSS_3.107 gap.  Without a bundled ckbi, NSS
# dlopens the HOST's trust module: works on every mainstream distro.  The
# staging loop below hard-fails if /usr/lib64 lacks the remaining libs.
# Also excluded: libnsssysinit.so (EL8's system-init shim; same distro-coupling
# argument -- without it NSS uses the upstream default init path).
NSS_LIBS="libnss3.so libnssutil3.so libsmime3.so libssl3.so libnspr4.so \
libplc4.so libplds4.so libsoftokn3.so libfreebl3.so libfreeblpriv3.so \
libnssdbm3.so libffi.so.6 libjpeg.so.62"
echo "==> Bundling NSS/NSPR + host-gap sonames (libffi, libjpeg) into lib/firefox/ ..."
for nsslib in $NSS_LIBS; do
    src=$(readlink -f "$SRC_NSS_DIR/$nsslib" 2>/dev/null || true)
    # Offline/non-EL8 path: libffi.so.6 + libjpeg.so.62 do not exist on the
    # host -- fall back to the loadout payload copies (EL8 bytes, repo-proven).
    if { [ -z "$src" ] || [ ! -f "$src" ]; } \
       && [ -f "$REPO/payload/el8.x86_64.glibc2p28/lib64/$nsslib.bz2" ]; then
        src=""
        echo "  $nsslib: staging from payload copy (host lacks the EL8 soname)"
        bunzip2 -c "$REPO/payload/el8.x86_64.glibc2p28/lib64/$nsslib.bz2" \
            > "$STAGE/lib/firefox/$nsslib"
    else
        [ -n "$src" ] && [ -f "$src" ] || {
            echo "ERROR: $SRC_NSS_DIR/$nsslib missing -- install nss/nspr first" >&2
            exit 1
        }
        cp "$src" "$STAGE/lib/firefox/$nsslib"
    fi
    dst="$STAGE/lib/firefox/$nsslib"
    strip "$dst" 2>/dev/null || true
    "$PATCHELF" --set-rpath '$ORIGIN' "$dst"
    chmod 755 "$dst"
done

# Guard: the trust module must NEVER ship in the bundle (see the NSS_LIBS
# comment).  If a future edit re-adds it, fail the build here.
if [ -e "$STAGE/lib/firefox/libnssckbi.so" ] || [ -e "$STAGE/lib/firefox/libnsssysinit.so" ]; then
    echo "ERROR: trust-module libs (libnssckbi/libnsssysinit) must not ship in the bundle" >&2
    echo "       (they are distro-specific trust proxies; see NSS_LIBS comment)" >&2
    exit 1
fi

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
# Keep the path INSIDE the bundle: do NOT add $prefix/lib64 (gui_libs) here --
# on hosts newer than EL8 that would shadow the host GTK3/dbus stack with the
# EL8-era gui_libs copies and break theme engines / spawned helpers.  The
# host-gap sonames (libffi.so.6, libjpeg.so.62) are bundled in $libdir
# instead, so $libdir alone closes the NEEDED set on any host.
LD_LIBRARY_PATH="$libdir${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export LD_LIBRARY_PATH

# Platform condition (the ONE spot firefox needs one): the bundle ships no
# libnssckbi.so -- the trust module must come from the host (bundling EL8's
# p11-kit proxy broke TLS on every non-EL8 distro; see the NSS_LIBS comment
# in the staging section).  NSS dlopens it by soname from the loader path, so
# probe WITHOUT the bundle dir on the path: if the host provides no
# libnssckbi.so at all (minimal containers, stripped farm nodes), fall back
# to the loadout-owned copy under <prefix>/lib64 (gui_libs), if present.
# gui_libs' ckbi has the same distro-proxy problem, so only use it as a
# better-than-nothing fallback -- a working EL8 node always resolves its own
# /usr/lib64 ckbi first, and hosts with no NSS at all likely lack the trust
# paths the proxy wants, so this stays a pragmatic best-effort, not a fix.
if ! command -v ldconfig >/dev/null 2>&1 \
   || ! ldconfig -p 2>/dev/null | grep -q 'libnssckbi.so'; then
    if [ -e "$prefix/lib64/libnssckbi.so" ]; then
        LD_LIBRARY_PATH="$LD_LIBRARY_PATH:$prefix/lib64"
        export LD_LIBRARY_PATH
        printf 'firefox wrapper: host has no libnssckbi.so; using loadout copy\n' >&2
    fi
fi

exec "$libdir/firefox-bin" "$@"
EOF
chmod 755 "$STAGE/bin/firefox"

# Optional XDG desktop entry -- copied unmodified.  Users with a desktop
# session pick it up via XDG_DATA_DIRS=$HOME/.local/share:...; the .desktop
# file's Exec= line points at /usr/bin/firefox, which still works on EL8
# workstations as a fallback but the bundled wrapper is the intended path.
# Offline path: the rpm carries the .desktop in /usr/share/applications, so
# prefer the unpacked copy when --from-rpms; keep the currently-deployed one
# from the payload tar as the last-resort (a .desktop never goes stale in a
# way that matters).
if [ -n "${_RPMS_EXTRACT:-}" ] && [ -r "$_RPMS_EXTRACT/usr/share/applications/firefox.desktop" ]; then
    mkdir -p "$STAGE/share/applications"
    cp "$_RPMS_EXTRACT/usr/share/applications/firefox.desktop" "$STAGE/share/applications/"
elif [ -r /usr/share/applications/firefox.desktop ]; then
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
"$REPO/build/strip-all-elf-binaries"

echo ""
echo "Done."
echo ""
echo "Commit with:"
echo "  git add payload/el8.x86_64.glibc2p28/runtime/firefox.tar.bz2* \\"
echo "          .strip-manifest payload/packages.json"
echo "  git commit -m 'feat(payload): firefox ${TAG} shanghai bundle'"
