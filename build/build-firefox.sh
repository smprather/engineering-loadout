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

# --- Bundle the decode-only FFmpeg codec set (H.264/AAC) ------------------
# WHY: Firefox ships its own ffvpx decoder for VP8/VP9/AV1/Opus/Vorbis/FLAC/
# MP3, but it does NOT ship an H.264 or AAC decoder.  For those it dlopens a
# SYSTEM FFmpeg from FFmpegRuntimeLinker's candidate list
# (libavcodec.so.61 first, down to .53) and drives it through
# FFmpegLibWrapper's function table.  EL8 ships no FFmpeg at all, so every
# H.264/AAC source -- Facebook Reels, YouTube (progressive/AVC), WebRTC H.264
# -- fails with NS_ERROR_DOM_MEDIA_METADATA_ERR while canPlayType('avc1...')
# answers "".  Debian/Ubuntu Firefox behaves the same way and solves it by
# depending on the distro ffmpeg; we solve it by carrying the two libs.
#
# We build FFmpeg 7.1.x decode-only ourselves (--enable-decoder=<list>,
# --disable-everything else) rather than shanghai an EL8 RPM: no EL8 ffmpeg
# rpm exists (no EPEL package either), and the full upstream build would drag
# in hundreds of encoders/muxers this bundle never calls.  Output is
# libavcodec.so.61 (macro 61 == the first entry in Firefox 140's dlopen
# ladder) + libavutil.so.59 + libswresample.so.5, ~5.7 MB stripped.
#
# ABI contract, asserted below so a future FFmpeg bump fails the build rather
# than silently losing H.264 at runtime:
#   * libavcodec major must stay <= 61 (FFmpegRuntimeLinker's newest
#     candidate; a .62 lib is not even attempted).  We pin 7.1.x == 61.
#   * avcodec_version()&0xffff >= 100 marks an FFmpeg (not LibAV) build;
#     FFmpegLibWrapper refuses LibAV and refuses FFmpeg < 54.35.1.
#   * Every symbol FFmpegLibWrapper's AV_FUNC table requires is checked by
#     loading the built lib and looking them up.
#
# Co-location mirrors the NSS set: files land IN $libdir (which the wrapper
# prepends to LD_LIBRARY_PATH) with RPATH=$ORIGIN, so libavcodec finds its
# libavutil/libswresample siblings without any host FFmpeg present -- and a
# host that DOES have a compatible FFmpeg still wins nothing, since the
# loader searches $libdir first.  Never put these in $prefix/lib64: on
# newer hosts that would shadow the host FFmpeg with our narrow
# decode-only build for every other application.
FFMPEG_VERSION="7.1.5"
FFMPEG_SHA256="de668509caf9e35e3cd162473441fdb29538c6d96ed080292b3cf9e6fc5d558f"
FFMPEG_URL="https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.xz"
FFMPEG_DECODERS="h264,hevc,aac,aac_latm,mp3,flac,opus,vorbis,av1,vp8,vp9"
FFMPEG_PARSERS="h264,hevc,aac,av1,vp9,vp8,opus,vorbis,flac,mpegaudio"

echo "==> Building decode-only FFmpeg ${FFMPEG_VERSION} for H.264/AAC ..."
need curl
need nasm
FF_WORK=$(mktemp -d "${TMPDIR:-/tmp}/firefox-ffmpeg-XXXXXX")
# shellcheck disable=SC2064  # expand FF_WORK now, not at trap time
trap 'rm -rf "$STAGE" ${_RPMS_EXTRACT:-} ${FF_WORK:-}' EXIT
curl -fL --retry 3 --retry-delay 2 -o "$FF_WORK/ffmpeg.tar.xz" "$FFMPEG_URL"
got=$(sha256sum "$FF_WORK/ffmpeg.tar.xz" | awk '{print $1}')
[ "$got" = "$FFMPEG_SHA256" ] || {
    echo "ERROR: ffmpeg tarball sha256 mismatch" >&2
    echo "  want $FFMPEG_SHA256" >&2
    echo "  got  $got" >&2
    exit 1
}
tar xf "$FF_WORK/ffmpeg.tar.xz" -C "$FF_WORK"
(
    cd "$FF_WORK/ffmpeg-${FFMPEG_VERSION}"
    ./configure \
        --prefix="$FF_WORK/inst" \
        --disable-everything \
        --disable-programs \
        --disable-doc \
        --disable-network \
        --disable-autodetect \
        --disable-static \
        --enable-shared \
        --enable-pic \
        --enable-decoder="$FFMPEG_DECODERS" \
        --enable-parser="$FFMPEG_PARSERS"
    make -j"$(nproc 2>/dev/null || echo 2)"
    make install
) > "$FF_WORK/build.log" 2>&1 || {
    echo "ERROR: FFmpeg build failed; tail of log:" >&2
    tail -30 "$FF_WORK/build.log" >&2
    exit 1
}

# Stage the three runtime libs + soname links.  RPATH=$ORIGIN is what lets
# libavcodec find libavutil/libswresample inside $libdir.
FF_LIBS=""
for pair in "libavcodec.so.61" "libavutil.so.59" "libswresample.so.5"; do
    real=$(ls "$FF_WORK/inst/lib/$pair".* 2>/dev/null | sort -V | tail -1)
    [ -n "$real" ] || { echo "ERROR: $pair not built" >&2; exit 1; }
    base=$(basename "$real")
    case "$base" in
        *.*.*) ;;
        *) echo "ERROR: unexpected ffmpeg lib name: $base" >&2; exit 1 ;;
    esac
    cp "$real" "$STAGE/lib/firefox/$base"
    strip --strip-debug "$STAGE/lib/firefox/$base"
    "$PATCHELF" --set-rpath '$ORIGIN' "$STAGE/lib/firefox/$base"
    chmod 755 "$STAGE/lib/firefox/$base"
    ln -sf "$base" "$STAGE/lib/firefox/$pair"
    FF_LIBS="$FF_LIBS $pair"
done

# ABI guard: avcodec macro must be within FFmpegRuntimeLinker's ladder, and
# every decoder Firefox asks this bundle for must be present.
FF_AC="$STAGE/lib/firefox/libavcodec.so.61"
# shellcheck disable=SC2016  # $ORIGIN is an ld.so token in the sibling libs
LD_LIBRARY_PATH="$STAGE/lib/firefox${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
python3 - "$FF_AC" "$FFMPEG_DECODERS" <<'PY' || exit 1
import ctypes
import os
import sys

lib_path, want = sys.argv[1], sys.argv[2].split(",")
lib = ctypes.CDLL(os.path.abspath(lib_path))
version = lib.avcodec_version()
macro = (version >> 16) & 0xFF
micro = version & 0xFF
print(f"  avcodec_version={version:#x} macro={macro} micro={micro}")
if macro > 61:
    sys.exit(f"ERROR: libavcodec macro {macro} > 61 -- Firefox will not load it")
if micro < 100:
    sys.exit(f"ERROR: libavcodec looks like LibAV (micro={micro}); Firefox refuses it")
lib.avcodec_find_decoder_by_name.restype = ctypes.c_void_p
lib.avcodec_find_decoder_by_name.argtypes = [ctypes.c_char_p]
missing = [d for d in want if not lib.avcodec_find_decoder_by_name(d.encode())]
if missing:
    sys.exit(f"ERROR: decoders missing from libavcodec: {', '.join(missing)}")
print(f"  decoders present: {', '.join(want)}")
PY
echo "  bundled:$FF_LIBS"

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

# ---------------------------------------------------------------------------
# Stage-verify: the FFmpeg pair must actually decode H.264 and AAC.
#
# The ABI guard above proves the decoder entries exist; this proves they run,
# by exercising the exact call sequence FFmpegLibWrapper uses (parser ->
# open decoder -> send_packet -> receive_frame).  Hand-rolled rather than
# calling ffmpeg(1): no ffmpeg CLI ships in the bundle, the EL8 build box has
# none, and the CLI would not test the dlopen path Firefox takes anyway.
#
# Media are tiny hand-built elementary streams committed under build/firefox/
# (dev-only, export-ignored, same precedent as build/iverilog/smoke.v):
#   h264.es - 160x120 testsrc, 2 s, x264 main profile, Annex-B
#   aac.es  - 440 Hz sine, 2 s, AAC-LC, ADTS
# Raw elementary streams, not MP4: the check drives libavcodec's own parser,
# which expects Annex-B / ADTS framing, not MP4 length prefixes.
# ---------------------------------------------------------------------------
echo "==> Stage-verify: decode H.264 + AAC with the bundled FFmpeg ..."
FF_VERIFY="$REPO/build/firefox"
[ -f "$FF_VERIFY/h264.es" ] || { echo "ERROR: missing $FF_VERIFY/h264.es" >&2; exit 1; }
[ -f "$FF_VERIFY/aac.es" ] || { echo "ERROR: missing $FF_VERIFY/aac.es" >&2; exit 1; }

LD_LIBRARY_PATH="$STAGE/lib/firefox${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
python3 "$REPO/build/firefox/check-decode.py" "$STAGE/lib/firefox" "$FF_VERIFY" || exit 1

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
# ensure_ascii=False: the registry carries UTF-8 (em dashes, arrows); the
# default escaping churned every description string in the file on each bump.
with open(path, 'w', encoding='utf-8') as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
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
