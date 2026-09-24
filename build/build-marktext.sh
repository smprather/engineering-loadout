#!/bin/bash
# build-marktext.sh -- build the engineering-loadout MarkText shanghai bundle.
#
# MarkText is an Electron markdown editor (marktext/marktext).  We ship the
# official Linux release tarball with two native addons REBUILT against EL8,
# because the shipped ones are linked against newer toolchains than EL8 has.
#
# WHY A SHANGHAI REPACK AND NOT A SOURCE BUILD
#   Measured floors of the official v0.19.1 bundle:
#     * main binary `marktext` ...... GLIBC_2.25 max   (EL8 has 2.28)  OK
#     * NSS usage ................... NSS_3.30 max     (EL8 GA 3.90)   OK
#     * ced.node .................... GLIBCXX_3.4.29   (EL8 has 3.4.25) FAIL
#     * native-keymap.node .......... GLIBC_2.34       (EL8 has 2.28)   FAIL
#   Both broken addons are loaded with a TOP-LEVEL `require()` from the
#   bundled main process (out/main/index.js), so the app cannot start at all
#   on EL8 with the upstream bytes -- not a lazy/feature-gated failure.
#   Rebuilding only those two addons against EL8 (Electron 42 ABI =
#   NODE_MODULE_VERSION 146) brings both to GLIBC_2.14 / GLIBCXX_3.4.21.
#   Verified end-to-end inside almalinux:8.10: all three addons dlopen, and
#   MarkText creates a real 1200x800 window under Xvfb.
#
# WHY v0.19.1 AND NOT v0.20.0-rc.5
#   Repo policy is stable tagged releases only; v0.20.0-rc.5 is a prerelease.
#
# BUILD-MACHINE PREREQS (must already exist in the image; no mid-build dnf):
#   gcc-toolset-14 (/opt/rh/gcc-toolset-14/enable -- base gcc 8.5 rejects
#     -std=gnu++20, which both addons' binding.gyp requests)
#   rpm2cpio + cpio (unpack the EL8 rpm closure)
#   patchelf (stamp RPATH on the co-located libs)
#   bunzip2, tar, curl, python3
#
# PAYLOAD SHAPE
#   payload/<plat>/runtime/marktext.tar.bz2   (auto-chunked by
#   strip-all-elf-binaries into .part-NNN shards)
#     ./bin/marktext              wrapper (prefix-derived; gui-wrapper-env +
#                                 gtk3-launcher-env blocks inlined)
#     ./lib/marktext/             the official bundle, addons swapped
#     ./lib64/                    co-located closure (NSS/NSPR/libsecret/
#                                 libxkbfile -- see COLOCATE below)
#     ./share/applications/marktext.desktop
#     ./share/icons/hicolor/256x256/apps/marktext.png
#
# USAGE
#   ./build/build-marktext.sh --tag v0.19.1
#   ./build/build-marktext.sh --tag v0.19.1 --from-tarball /path/to.tar.gz
#
# Run it INSIDE the EL8 build container:  ./build/build-shell build/build-marktext.sh --tag v0.19.1
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
RUNTIME_DIR="$REPO/payload/el8.x86_64.glibc2p28/runtime"
PLATFORM_DIR="$REPO/payload/el8.x86_64.glibc2p28"
TAG=""
FROM_TARBALL=""
KEEP_STAGE=0

while [ $# -gt 0 ]; do
    case "$1" in
        --tag)          TAG="${2:-}"; shift 2 ;;
        --from-tarball) FROM_TARBALL="${2:-}"; shift 2 ;;
        --keep-stage)   KEEP_STAGE=1; shift ;;
        -h|--help)      sed -n '2,50p' "$0"; exit 0 ;;
        *) echo "ERROR: unknown arg: $1" >&2; exit 2 ;;
    esac
done

[ -n "$TAG" ] || { echo "ERROR: --tag is required (e.g. --tag v0.19.1)" >&2; exit 2; }
VERSION="${TAG#v}"

# --- pinned upstream facts -------------------------------------------------
# Release: https://github.com/marktext/marktext/releases/tag/v0.19.1
TARBALL_URL="https://github.com/marktext/marktext/releases/download/${TAG}/marktext-linux-${VERSION}.tar.gz"
# sha256 of marktext-linux-0.19.1.tar.gz as published in the release's
# SHA256SUMS.txt (verified against the live asset during recon).  Override with
# MARKTEXT_TARBALL_SHA256 only when deliberately re-pinning a new tag.
TARBALL_SHA256="${MARKTEXT_TARBALL_SHA256:-d1ecc7e47fe2cfdd6191330dd9360fdaae47508f458f179cc5f4948b7f3e6f1d}"
# Electron ABI: the bundle IS Electron 42.1.0 => NODE_MODULE_VERSION 146
ELECTRON_TARGET="42.1.0"
NODE_MODULE_VERSION="146"
# Addon sources, pinned by sha256 of the npm tarballs (verified below).
CED_VERSION="2.0.0"
CED_URL="https://registry.npmjs.org/ced/-/ced-${CED_VERSION}.tgz"
CED_SHA256="d6af33f18dd18ab1972b43c274d7b3c756371d48aca6514ad44cffe3d98252b9"
NK_VERSION="3.3.9"
NK_URL="https://registry.npmjs.org/native-keymap/-/native-keymap-${NK_VERSION}.tgz"
NK_SHA256="f6f3844be47e4cf8b6f8b9cc7d9b4b1d76922485d5897e77e0e1119168609935"
NODE_GYP_VERSION="10"

# --- co-located closure ----------------------------------------------------
# The bundle NEEDs 9 sonames the payload does not supply.  What we do with
# each, and why (verified against stock almalinux:8.10 + the payload):
#
#   libnss3/libnssutil3/libsmime3/libnspr4 ... EL8 BaseOS `nss`/`nspr`, but a
#       farm node may lack them and newer hosts version-skew; the firefox
#       bundle co-locates the same family, so follow that precedent.
#   libsecret-1.so.0 ......................... needed by keytar.node (secret
#       storage).  EL8 AppStream, often absent on minimal nodes.
#   libxkbfile.so.1 .......................... needed by native-keymap.node.
#       NEW runtime need introduced by our own rebuild (the upstream .node
#       needed GLIBC_2.34 and no libxkbfile dependency path at all).
#   libcups.so.2 ............................. direct NEEDED of the main
#       binary.  EL8 AppStream `cups-libs`, but a STOCK almalinux:8.10 image
#       does not install it -- Tier 3 failed marktext with "libcups.so.2:
#       cannot open shared object file" after the first "assume host" cut.
#       Co-locate it plus the two avahi libs it NEEDs (also absent from the
#       stock image); the rest of its closure (krb5/gnutls/selinux/audit/
#       com_err/keyutils/crypt/z) IS in the EL8 base image and on newer
#       hosts, and the payload's unclaimed libcrypt/libcrypto stems cover
#       non-EL8 hosts.
#   libudev.so.1 ............................. EL8 BaseOS `systemd-libs`,
#       PRESENT in a stock image; assume host.
#   libgbm.so.1 .............................. shipped by mesa3d_libs
#       (declared dep, AGENTS.md two-owners pattern).
#
# Co-located libs go to <prefix>/lib64 (NOT the app dir) so the gui_libs copy
# can be shared, and each is stamped RPATH=$ORIGIN.  libsecret's own needs
# (libgcrypt.so.20, libgpg-error.so.0, libgio/gobject/glib) are all EL8
# BASeOS/base-provided and are assumed, matching gui_libs' existing
# assumptions (it already assumes libgnutls.so.30, libsystemd.so.0,
# libmount.so.1 without bundling them).
#
# NSS softoken/freebl are dlopen'd by libnss3 from ITS OWN directory, so the
# whole NSS family must land in the same place.  libnssckbi.so (the trust
# module) is DELIBERATELY EXCLUDED -- same hard rule as the firefox bundle:
# on EL8 it is a p11-kit proxy reading distro-specific trust paths, and
# bundling it broke TLS on every non-EL8 host (see docs/SHARED_LIBS.md).
COLOCATE="libnss3.so libnssutil3.so libsmime3.so libssl3.so libnspr4.so \
libplc4.so libplds4.so libsoftokn3.so libfreebl3.so libfreeblpriv3.so \
libnssdbm3.so libsecret-1.so.0 libxkbfile.so.1 \
libcups.so.2 libavahi-client.so.3 libavahi-common.so.3"
# rpms providing the above (EL8 BaseOS/AppStream)
COLOCATE_RPMS="nss nspr libsecret libxkbfile cups-libs avahi-libs"

echo "==> MarkText ${VERSION} shanghai bundle"
echo "    repo:     $REPO"
echo "    runtime:  $RUNTIME_DIR"

need() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing tool: $1" >&2; exit 1; }; }
need tar; need bunzip2; need curl; need python3
need rpm2cpio; need cpio

# --- 0. work area ----------------------------------------------------------
# Under ${TMPDIR:-/tmp}, matching every other build script (mktemp -d).  It is
# load-bearing that this is NOT inside $REPO: strip-all-elf-binaries walks the
# whole repository at the end of this script, so a work tree in-repo would get
# scanned, stripped, and recorded into .strip-manifest as if it were payload.
# (That exact mistake was made and caught: 706 scratch entries landed in the
# manifest.)  Anything worth keeping is echoed to stdout, and the archive is
# written straight into payload/.
WORK=$(mktemp -d "${TMPDIR:-/tmp}/marktext-XXXXXX")
STAGE="$WORK/stage"
mkdir -p "$STAGE/bin" "$STAGE/lib/marktext" "$STAGE/lib64" \
         "$STAGE/share/applications" "$STAGE/share/icons/hicolor/256x256/apps"
if [ "$KEEP_STAGE" = 0 ]; then
    # shellcheck disable=SC2064  # expand WORK now
    trap 'rm -rf "$WORK"' EXIT
fi
# node-gyp downloads Electron's headers into $HOME/.cache (HOME=/tmp in the
# build container).  Point it inside WORK so the headers are not silently
# reused across targets and are cleaned up with everything else.
export npm_config_devdir="$WORK/node-gyp-devdir"
mkdir -p "$npm_config_devdir"

# --- 1. toolchain ----------------------------------------------------------
if [ -r /opt/rh/gcc-toolset-14/enable ]; then
    # shellcheck disable=SC1091
    . /opt/rh/gcc-toolset-14/enable
    echo "==> gcc-toolset-14 enabled: $(g++ --version | head -1)"
else
    echo "ERROR: /opt/rh/gcc-toolset-14/enable not found." >&2
    echo "       Both addons' binding.gyp request -std=gnu++20; base gcc 8.5 cannot." >&2
    exit 1
fi

# --- 2. fetch + verify the upstream bundle ---------------------------------
echo "==> Fetching marktext-linux-${VERSION}.tar.gz ..."
SRC_TAR="$WORK/marktext-linux-${VERSION}.tar.gz"
if [ -n "$FROM_TARBALL" ]; then
    cp "$FROM_TARBALL" "$SRC_TAR"
else
    curl -fsSL --retry 3 -o "$SRC_TAR" "$TARBALL_URL"
fi
got=$(sha256sum "$SRC_TAR" | awk '{print $1}')
if [ -n "$TARBALL_SHA256" ]; then
    [ "$got" = "$TARBALL_SHA256" ] || {
        echo "ERROR: tarball sha256 mismatch" >&2
        echo "  expected $TARBALL_SHA256" >&2
        echo "  got      $got" >&2
        exit 1
    }
    echo "    sha256 OK: $got"
else
    echo "    sha256: $got"
    echo "    (not pinned -- export MARKTEXT_TARBALL_SHA256 to enforce)"
fi

echo "==> Staging the upstream bundle ..."
tar xzf "$SRC_TAR" -C "$STAGE/lib/marktext" --strip-components=1
APPDIR="$STAGE/lib/marktext"

# Remove the setuid sandbox helper (see the wrapper comment): unusable without
# root, and its presence-but-misconfiguration is a FATAL abort on hosts where
# the namespace sandbox would otherwise be used.  Deleting it makes Chromium
# fall through to the namespace path deterministically.
if [ -e "$APPDIR/chrome-sandbox" ]; then
    rm -f "$APPDIR/chrome-sandbox"
    echo "    removed chrome-sandbox (setuid helper; unusable in a no-root install)"
fi

# --- 3. node-gyp toolchain (rebuild the two EL8-incompatible addons) -------
# node-gyp 10's bundled gyp uses PEP 572 (walrus) syntax that EL8's Python 3.6
# cannot even PARSE -- so drive it with the loadout payload's Python 3.14.
echo "==> Staging the payload node + python for node-gyp ..."
PLIBS="$WORK/plibs"
mkdir -p "$PLIBS" "$WORK/node"
for f in "$PLATFORM_DIR"/lib64/*.bz2; do
    case "$f" in *.part-*) continue ;; esac
    bunzip2 -c "$f" > "$PLIBS/$(basename "$f" .bz2)" 2>/dev/null || true
done
tar xjf "$PLATFORM_DIR"/runtime/node.tar.bz2 -C "$WORK/node" --strip-components=1 2>/dev/null \
  || tar xjf "$PLATFORM_DIR"/runtime/node.tar.bz2 -C "$WORK/node" 2>/dev/null
NODE_BIN=$(find "$WORK/node" -maxdepth 3 -name node -type f | head -1)
[ -n "$NODE_BIN" ] || { echo "ERROR: node not found in the payload archive" >&2; exit 1; }
NPM_CLI=$(find "$WORK/node" -maxdepth 6 -path '*npm/bin/npm-cli.js' | head -1)
[ -n "$NPM_CLI" ] || { echo "ERROR: npm-cli.js not found in the payload archive" >&2; exit 1; }
export LD_LIBRARY_PATH="$PLIBS"
echo "    node: $("$NODE_BIN" --version)"

PY314="$REPO/.loadout-bootstrap/bin/python3.14"
if [ ! -x "$PY314" ]; then
    mkdir -p "$REPO/.loadout-bootstrap"
    tar xjf "$PLATFORM_DIR"/portable-python-*.tar.bz2 -C "$REPO/.loadout-bootstrap" 2>/dev/null || true
    PY314=$(find "$REPO/.loadout-bootstrap" -maxdepth 4 -name 'python3.14' -type f | head -1)
fi
if [ ! -x "$PY314" ]; then
    echo "ERROR: python3.14 not available (node-gyp cannot run under EL8's 3.6)" >&2
    exit 1
fi
export npm_config_python="$PY314"
echo "    python for gyp: $("$PY314" --version)"

echo "==> Installing node-gyp@${NODE_GYP_VERSION} ..."
"$NODE_BIN" "$NPM_CLI" install --prefix "$WORK/gyp" "node-gyp@${NODE_GYP_VERSION}" \
    >"$WORK/npm-gyp.log" 2>&1
GYP="$WORK/gyp/node_modules/.bin/node-gyp"
[ -f "$GYP" ] || { echo "ERROR: node-gyp install failed"; tail -20 "$WORK/npm-gyp.log" >&2; exit 1; }

# --- 4. rebuild ced --------------------------------------------------------
# ced = Chrome's Compact Encoding Detector.  Upstream prebuilt: GLIBCXX_3.4.29.
build_addon() {
    # $1 name, $2 url, $3 expected sha256, $4 extra patch file (optional)
    # Diagnostics go to STDERR: stdout is the command substitution's return
    # channel (the built artifact path), so it must carry nothing else.
    name=$1; url=$2; want=$3; patch_file="${4:-}"
    echo "==> Building $name (Electron $ELECTRON_TARGET ABI) ..." >&2
    dir="$WORK/src-$name"
    mkdir -p "$dir"
    tgz="$WORK/$name.tgz"
    curl -fsSL --retry 3 -o "$tgz" "$url"
    got=$(sha256sum "$tgz" | awk '{print $1}')
    [ "$got" = "$want" ] || {
        echo "ERROR: $name tarball sha256 mismatch" >&2
        echo "  expected $want" >&2
        echo "  got      $got" >&2
        exit 1
    }
    tar xzf "$tgz" -C "$dir"
    ( cd "$dir/package"
      if [ -n "$patch_file" ] && [ -s "$patch_file" ]; then
          echo "    applying $(basename "$patch_file")" >&2
          patch -p1 --forward < "$patch_file" >&2 || true
      fi
      "$NODE_BIN" "$GYP" configure --target="$ELECTRON_TARGET" \
          --dist-url=https://electronjs.org/headers --arch=x64 >&2
      "$NODE_BIN" "$GYP" build >&2
    )
    # locate the linked artifact (gyp puts it at build/Release/<name>.node or
    # a differently-named target such as keymapping.node)
    node_file=$(find "$dir/package/build/Release" -maxdepth 1 -name '*.node' -type f | head -1)
    [ -n "$node_file" ] || { echo "ERROR: no .node built for $name" >&2; exit 1; }
    echo "    built: $node_file" >&2
    printf '%s' "$node_file"
}

CED_NODE=$(build_addon "ced" "$CED_URL" "$CED_SHA256")

# --- 5. rebuild native-keymap ---------------------------------------------
# native-keymap's upstream prebuilt is GLIBC_2.34.  MarkText patches it (see
# the app's own patches/native-keymap+3.3.9.patch, shipped inside its asar);
# we extract that patch from the staged app so our rebuild matches what the
# app expects, rather than guessing.
echo "==> Extracting MarkText's own native-keymap patch from the asar ..."
NK_PATCH="$WORK/native-keymap+${NK_VERSION}.patch"
python3 - "$APPDIR/resources/app.asar" "$NK_PATCH" <<'PY' || true
import json, struct, sys
asar, out = sys.argv[1], sys.argv[2]
with open(asar, "rb") as f:
    _, hs, _, js = struct.unpack("<IIII", f.read(16))
    hdr = json.loads(f.read(js).decode("utf-8", "replace"))
node = hdr["files"]["patches"]["files"]["native-keymap+3.3.9.patch"]
with open(asar, "rb") as f:
    f.seek(8 + hs + int(node["offset"]))
    data = f.read(int(node["size"]))
open(out, "wb").write(data)
print(f"    extracted {len(data)} bytes")
PY
[ -s "$NK_PATCH" ] || echo "    (patch not extractable; building pristine)"

NK_NODE=$(build_addon "native-keymap" "$NK_URL" "$NK_SHA256" "$NK_PATCH")

# --- 6. swap the rebuilt addons into the bundle ---------------------------
echo "==> Swapping rebuilt addons into the bundle ..."
swap_into() {
    # $1 built artifact, $2 node_modules dir name, $3 destination basename
    src=$1; dir=$2; base=$3
    n=0
    for dest in "$APPDIR/resources/app.asar.unpacked/node_modules/$dir/bin/linux-x64-$NODE_MODULE_VERSION/$base.node" \
                "$APPDIR/resources/app.asar.unpacked/node_modules/$dir/build/Release/$base.node"; do
        if [ -f "$dest" ]; then
            cp "$src" "$dest"
            chmod 755 "$dest"
            echo "    swapped ${dest#$APPDIR/}"
            n=$((n+1))
        fi
    done
    [ "$n" -gt 0 ] || { echo "ERROR: no destination found for $dir/$base.node" >&2; exit 1; }
}
swap_into "$CED_NODE" "ced" "ced"
swap_into "$NK_NODE" "native-keymap" "native-keymap"
# the built target is named keymapping.node; the bundle keeps that name too
swap_into "$NK_NODE" "native-keymap" "keymapping"

# guard: no addon may need GLIBC above the EL8 floor
echo "==> Verifying addon floors (EL8: GLIBC<=2.28, GLIBCXX<=3.4.25) ..."
for f in "$APPDIR"/resources/app.asar.unpacked/node_modules/*/bin/linux-x64-$NODE_MODULE_VERSION/*.node \
         $(find "$APPDIR/resources/app.asar.unpacked" -name '*.node' 2>/dev/null); do
    [ -f "$f" ] || continue
    g=$(readelf -V "$f" 2>/dev/null | grep -oE 'GLIBC_[0-9]+\.[0-9]+' | sed 's/GLIBC_//' | sort -uV | tail -1)
    x=$(readelf -V "$f" 2>/dev/null | grep -oE 'GLIBCXX_[0-9.]+' | sed 's/GLIBCXX_//' | sort -uV | tail -1)
    ok=1
    [ -n "$g" ] && [ "$(printf '%s\n2.28\n' "$g" | sort -V | tail -1)" != "2.28" ] && ok=0
    [ -n "$x" ] && [ "$(printf '%s\n3.4.25\n' "$x" | sort -V | tail -1)" != "3.4.25" ] && ok=0
    printf '    %-22s GLIBC=%-5s GLIBCXX=%-8s %s\n' "$(basename "$f")" "${g:-none}" "${x:-none}" \
        "$([ "$ok" = 1 ] && echo OK || echo '*** TOO NEW ***')"
    [ "$ok" = 1 ] || { echo "ERROR: $(basename "$f") exceeds the EL8 floor" >&2; exit 1; }
done

# --- 7. co-locate the closure --------------------------------------------
echo "==> Co-locating the NSS/NSPR/libsecret/libxkbfile/cups/avahi closure ..."
PATCHELF="$(command -v patchelf || true)"
[ -n "$PATCHELF" ] || { echo "ERROR: patchelf required to stamp RPATH" >&2; exit 1; }
# Source the libs from the build container's own userland.  The image must
# carry the EL8 rpms (see the prereq list in the header): this script never
# shells out to dnf, so a missing rpm is a build failure with a clear message
# rather than a mid-build install.
for lib in $COLOCATE; do
    src=$(ldconfig -p 2>/dev/null | grep -F "$lib (" | head -1 | sed 's/.*=> //')
    if [ -z "$src" ] && [ -L "/usr/lib64/$lib" ]; then
        src="/usr/lib64/$lib"
    fi
    [ -n "$src" ] || {
        echo "ERROR: $lib not resolvable in the build container." >&2
        echo "       Bake the EL8 rpms into build/Dockerfile: $COLOCATE_RPMS" >&2
        exit 1
    }
    # -L follows the soname symlink so we ship real bytes named by soname.
    cp -L "$src" "$STAGE/lib64/$lib"
    strip "$STAGE/lib64/$lib" 2>/dev/null || true
    "$PATCHELF" --set-rpath '$ORIGIN' "$STAGE/lib64/$lib"
    chmod 755 "$STAGE/lib64/$lib"
    echo "    $lib  <- $src"
done

# Guard: the trust module must NEVER ship (see the COLOCATE comment).
if [ -e "$STAGE/lib64/libnssckbi.so" ] || [ -e "$STAGE/lib64/libnsssysinit.so" ]; then
    echo "ERROR: trust-module libs must not ship in the bundle" >&2
    exit 1
fi

# --- 8. wrapper -----------------------------------------------------------
echo "==> Writing the wrapper ..."
cat > "$STAGE/bin/marktext" <<'WRAPPER'
#!/bin/sh
# Wrapper for the engineering-loadout MarkText bundle.
# Derives the install prefix from this script's location so the same wrapper
# works from $HOME, --dest-dir staging trees, or shared release trees.
bin_dir=$(CDPATH= cd "$(dirname "$0")" && pwd -P) || exit 1
prefix=$(CDPATH= cd "$bin_dir/.." && pwd -P) || exit 1
appdir="$prefix/lib/marktext"

# The bundle NEEDs sonames the payload does not supply on every host:
#   libnss3/libnssutil3/libsmime3/libnspr4/libsecret-1/libxkbfile
#   libcups (plus the avahi libs it NEEDs)
# are co-located in $prefix/lib64 (each RPATH=$ORIGIN); libudev is assumed
# host-provided (EL8 BaseOS); libgbm comes from mesa3d_libs (declared
# dependency).
#
# Ordering is load-bearing.  $appdir FIRST so the bundle's own libffmpeg.so
# (NEEDED by the main binary, RPATH=$ORIGIN covers it too) can never be
# shadowed; then $prefix/lib64 for the co-located closure.  $appdir is a
# path INSIDE the bundle, never $prefix/lib64-as-gui_libs: pointing the whole
# search path at the EL8-era gui_libs copies would shadow a newer host's
# GTK3/dbus stack and break theme engines and spawned helpers (the shipped
# firefox regression of the same shape).
LD_LIBRARY_PATH="$appdir:$prefix/lib64${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export LD_LIBRARY_PATH

# Chromium's setuid sandbox helper is unusable in a no-root, per-user install:
# it only works when owned root:root with mode 4755, and when Chromium finds it
# present-but-misconfigured it FATAL-aborts instead of degrading.  Verified
# behavior (probe, almalinux:8.10 + native CachyOS):
#   * user namespaces available  -> Chromium takes the namespace sandbox and a
#     PLAIN run works (a real 1200x800 window appears under Xvfb);
#   * user namespaces blocked    -> Chromium wants the setuid helper, finds it
#     misconfigured, and aborts with a confusing "not configured correctly".
# The helper is therefore removed at BUILD time (not at wrapper runtime), so
# the behavior is identical on read-only mount trees and the failure mode on a
# userns-less host is a clear "No usable sandbox" plus the documented
# --no-sandbox escape hatch, rather than a bogus configuration complaint.
# loadout is a no-root installer by design, so the setuid path was never
# available to us.

# ---- shared GUI adaptation (build/gui-wrapper-env.sh, inlined) ----
WRAPPER
# Inline the shared GUI blocks wholesale (comments included -- the repo does
# the same in build-wezterm.sh), so the installed wrapper is self-contained
# with no repo runtime dependency.
[ -r "$REPO/build/gui-wrapper-env.sh" ] || { echo "ERROR: missing gui-wrapper-env.sh" >&2; exit 1; }
[ -r "$REPO/build/gtk3-launcher-env.sh" ] || { echo "ERROR: missing gtk3-launcher-env.sh" >&2; exit 1; }
cat "$REPO/build/gui-wrapper-env.sh" >> "$STAGE/bin/marktext"
cat "$REPO/build/gtk3-launcher-env.sh" >> "$STAGE/bin/marktext"
cat >> "$STAGE/bin/marktext" <<'WRAPPER2'

exec "$appdir/marktext" "$@"
WRAPPER2
chmod 755 "$STAGE/bin/marktext"
# Guard: the inlined blocks must actually be present and syntactically valid.
sh -n "$STAGE/bin/marktext" || { echo "ERROR: generated wrapper fails sh -n" >&2; exit 1; }
grep -q 'LOADOUT_GUI_HOST_GL' "$STAGE/bin/marktext" \
    || { echo "ERROR: gui-wrapper-env block did not inline" >&2; exit 1; }
grep -q 'LOADOUT_GTK_X11' "$STAGE/bin/marktext" \
    || { echo "ERROR: gtk3-launcher-env block did not inline" >&2; exit 1; }

# --- 9. desktop entry + icon ---------------------------------------------
echo "==> Writing the .desktop entry and icon ..."
# The bundle ships only .ico icons (resources/icons/{icon,md}.ico); the
# 256x256 frame is a PNG, so lift it directly rather than shipping an ICO
# (most Linux icon themes ignore .ico).
python3 - "$APPDIR/resources/icons/md.ico" \
          "$STAGE/share/icons/hicolor/256x256/apps/marktext.png" <<'PY'
import struct, sys
src, dst = sys.argv[1], sys.argv[2]
data = open(src, "rb").read()
_, _, count = struct.unpack("<HHH", data[:6])
best = None
for i in range(count):
    off = 6 + i * 16
    w, _h, _c, _r, _p, bpp, size, offset = struct.unpack("<BBBBHHII", data[off:off+16])
    w = w or 256
    if data[offset:offset+8] == b"\x89PNG\r\n\x1a\n" and (best is None or w > best[0]):
        best = (w, offset, size)
if best is None:
    raise SystemExit("no PNG frame in the .ico")
_w, offset, size = best
open(dst, "wb").write(data[offset:offset+size])
print(f"    lifted {best[0]}x{best[0]} PNG ({size} bytes) from md.ico")
PY

cat > "$STAGE/share/applications/marktext.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Version=1.0
Name=MarkText
GenericName=Markdown Editor
Comment=Simple and elegant markdown editor
Exec=marktext %U
Icon=marktext
Terminal=false
StartupNotify=true
MimeType=text/markdown;
Categories=Office;TextEditor;Utility;
Keywords=markdown;editor;md;
DESKTOP

# --- 10. stage verify ----------------------------------------------------
echo "==> Stage-verify: launch MarkText headlessly and check it starts"
# Two checks, because they prove different things:
#   (a) the rebuilt addons dlopen -- `marktext --version` does NOT load
#       native-keymap (verified by poisoning its soname and watching the run
#       stay green), so --version alone is a weak gate.
#   (b) the app's main process boots and reports its version.
export LD_LIBRARY_PATH="$STAGE/lib64:${LD_LIBRARY_PATH:-}"
VERIFY_HOME="$WORK/verify-home"
mkdir -p "$VERIFY_HOME"

# Mirror the INSTALLED library shape.  In a real tree, gui_libs lands in
# <prefix>/lib64 together with our co-located closure, and mesa3d_libs supplies
# the Mesa vendor side -- so stage both from the payload into a verify-only dir
# (under $WORK, never packaged) and search it exactly as the installer will.
# Without this the verify fails on libasound/libgtk and tells us nothing about
# the artifact we are shipping.
VERIFY_LIB64="$WORK/verify-lib64"
mkdir -p "$VERIFY_LIB64"
for f in "$PLATFORM_DIR"/lib64/*.bz2; do
    case "$f" in *.part-*) continue ;; esac
    bunzip2 -c "$f" > "$VERIFY_LIB64/$(basename "$f" .bz2)" 2>/dev/null || true
done
cat "$PLATFORM_DIR"/runtime/mesa3d_libs.tar.bz2.part-* 2>/dev/null \
    | tar xjf - -C "$WORK/mesa-verify" 2>/dev/null || {
        mkdir -p "$WORK/mesa-verify"
        cat "$PLATFORM_DIR"/runtime/mesa3d_libs.tar.bz2.part-* 2>/dev/null \
            | tar xjf - -C "$WORK/mesa-verify" 2>/dev/null || true
    }
if [ -d "$WORK/mesa-verify/lib64" ]; then
    for f in "$WORK/mesa-verify/lib64"/*.so*; do
        [ -e "$f" ] || continue
        [ -e "$VERIFY_LIB64/$(basename "$f")" ] || cp -P "$f" "$VERIFY_LIB64/" 2>/dev/null || true
    done
fi
# $appdir first (its own libffmpeg/libEGL), then the merged prefix lib64 --
# byte-identical ordering to what the installed wrapper produces.
VLP="$APPDIR:$STAGE/lib64:$VERIFY_LIB64"
echo "    verify libdirs: $VLP"

cat > "$WORK/load-addons.js" <<'JS'
const path = require("path");
const appdir = process.argv[2];
const mods = [
  ["ced", "node_modules/ced/bin/linux-x64-146/ced.node"],
  ["native-keymap", "node_modules/native-keymap/bin/linux-x64-146/native-keymap.node"],
  ["keytar", "node_modules/keytar/build/Release/keytar.node"],
];
let bad = 0;
for (const [name, rel] of mods) {
  const p = path.join(appdir, "resources/app.asar.unpacked", rel);
  try { require(p); console.log("  LOADED " + name); }
  catch (e) { bad++; console.log("  FAILED " + name + ": " + e.message.split("\n")[0]); }
}
process.exit(bad ? 1 : 0);
JS
echo "  (a) dlopen every native addon via ELECTRON_RUN_AS_NODE"
set +e
addon_out=$(env -i HOME="$VERIFY_HOME" PATH=/usr/bin:/bin ELECTRON_RUN_AS_NODE=1 \
        LD_LIBRARY_PATH="$VLP" \
        "$APPDIR/marktext" "$WORK/load-addons.js" "$APPDIR" 2>&1)
addon_rc=$?
set -e
echo "$addon_out" | sed 's/^/    /'
[ "$addon_rc" = 0 ] || { echo "ERROR: a native addon failed to load (rc=$addon_rc)" >&2; exit 1; }

# (a2) NEGATIVE CONTROL -- the whole point of this gate.
# The build container may carry these sonames in /usr/lib64 itself (it does for
# libxkbfile), which would let a broken co-located copy pass unnoticed: the
# loader would silently fall back to the container's.  Poison the two sonames
# the MAIN binary does NOT link directly but the addons NEED (libsecret for
# keytar, libxkbfile for native-keymap): poisoning libnss3 would kill the
# process before the addons load and prove nothing, so it is deliberately NOT
# poisoned here.  Prepending the poison dir must make the addon load FAIL; if
# it still succeeds, our copy is not the one being loaded and the gate above
# was meaningless.  (AGENTS.md: a smoke that resolves libs from the build box's
# own paths is environment-masked.)
POISON="$WORK/poison"
mkdir -p "$POISON"
for so in libsecret-1.so.0 libxkbfile.so.1; do
    head -c 512 /dev/urandom > "$POISON/$so"
done
set +e
neg_out=$(env -i HOME="$VERIFY_HOME" PATH=/usr/bin:/bin ELECTRON_RUN_AS_NODE=1 \
        LD_LIBRARY_PATH="$POISON:$VLP" \
        "$APPDIR/marktext" "$WORK/load-addons.js" "$APPDIR" 2>&1)
neg_rc=$?
set -e
if [ "$neg_rc" = 0 ]; then
    echo "ERROR: negative control PASSED -- the addons resolved their closure" >&2
    echo "       from the build container, not from \$STAGE/lib64." >&2
    echo "       The co-located set is incomplete or unused; do not trust the gate." >&2
    exit 1
fi
echo "  (a2) negative control OK: poisoning the co-located sonames breaks the load"
echo "       (so the addons really do resolve through \$STAGE/lib64)"

# (b2) NEGATIVE CONTROL for the MAIN process's co-located closure.
# The build container HAS libcups/avahi in /usr/lib64, and that is exactly how
# a missing co-located copy passed the green (b) check until the stock-EL8
# Tier 3 gate caught it.  Use a FRESH poison dir (the (a2) dir also poisons
# libsecret/libxkbfile, which would mask the specific failure), poison only
# cups/avahi, and require the main process to fail.
POISON_MAIN="$WORK/poison-main"
mkdir -p "$POISON_MAIN"
for so in libcups.so.2 libavahi-client.so.3 libavahi-common.so.3; do
    head -c 512 /dev/urandom > "$POISON_MAIN/$so"
done
set +e
neg2_out=$(env -i HOME="$VERIFY_HOME" PATH=/usr/bin:/bin \
        LD_LIBRARY_PATH="$POISON_MAIN:$VLP" \
        timeout 90 "$APPDIR/marktext" --version --no-sandbox 2>&1)
neg2_rc=$?
set -e
if [ "$neg2_rc" = 0 ]; then
    echo "ERROR: main-process negative control PASSED -- libcups/avahi resolved" >&2
    echo "       from the build container, not from \$STAGE/lib64." >&2
    echo "       The co-located set is incomplete or unused; do not trust the gate." >&2
    exit 1
fi
echo "$neg2_out" | head -3 | sed 's/^/    /'
echo "  (b2) negative control OK: poisoning libcups/avahi breaks the main process"
echo "       (so the main binary really resolves them through \$STAGE/lib64)"

echo "  (b) main process boots and prints its version"
set +e
out=$(env -i HOME="$VERIFY_HOME" PATH=/usr/bin:/bin \
        LD_LIBRARY_PATH="$VLP" \
        timeout 90 "$APPDIR/marktext" --version --no-sandbox 2>&1)
rc=$?
set -e
echo "$out" | sed 's/^/    /'
[ "$rc" = 0 ] || { echo "ERROR: marktext --version exited $rc" >&2; exit 1; }
echo "$out" | grep -q "MarkText: v${VERSION}" \
    || { echo "ERROR: version banner did not report v${VERSION}" >&2; exit 1; }

# (c) REAL WINDOW smoke under Xvfb.
# This is the strongest available gate and the one that matches how the app is
# actually used: it exercises the GTK3 stack, the bundled GUI libs, and window
# creation, none of which --version touches.  A window titled "Untitled-1"
# appearing on the root window is the pass condition.  (The image bakes Xvfb +
# xdpyinfo; see build/Dockerfile.)
if command -v Xvfb >/dev/null 2>&1 && command -v xdpyinfo >/dev/null 2>&1; then
    echo "  (c) real window under Xvfb"
    _disp=":${MARKTEXT_VERIFY_DISPLAY:-88}"
    Xvfb "$_disp" -screen 0 1280x800x24 -nolisten tcp >"$WORK/xvfb.log" 2>&1 &
    _xvfb_pid=$!
    sleep 3
    env -i HOME="$VERIFY_HOME" PATH=/usr/bin:/bin DISPLAY="$_disp" \
        LD_LIBRARY_PATH="$VLP" \
        "$STAGE/bin/marktext" --no-sandbox >"$WORK/window.log" 2>&1 &
    _app_pid=$!
    _found=""
    for _i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
        sleep 2
        if DISPLAY="$_disp" xdpyinfo >/dev/null 2>&1; then
            if DISPLAY="$_disp" xwininfo -root -children 2>/dev/null | grep -qi 'marktext'; then
                _found=yes
                break
            fi
        fi
        kill -0 "$_app_pid" 2>/dev/null || break
    done
    if [ -n "$_found" ]; then
        echo "    window found:"
        DISPLAY="$_disp" xwininfo -root -children 2>/dev/null | grep -i marktext | sed 's/^/      /'
    else
        echo "    no window detected; app log:" >&2
        head -20 "$WORK/window.log" | sed 's/^/      /' >&2
    fi
    kill "$_app_pid" 2>/dev/null || true
    kill "$_xvfb_pid" 2>/dev/null || true
    wait "$_app_pid" 2>/dev/null || true
    wait "$_xvfb_pid" 2>/dev/null || true
    [ -n "$_found" ] || { echo "ERROR: MarkText did not create a window under Xvfb" >&2; exit 1; }
else
    echo "  (c) SKIPPED: Xvfb/xdpyinfo absent from the image (bake them per build/Dockerfile)"
    echo "      -- without this check the smoke does not exercise window creation." >&2
fi

# --- 11. package ---------------------------------------------------------
echo "==> Packaging ..."
ARCHIVE="$RUNTIME_DIR/marktext.tar.bz2"
# Wipe stale shards first so strip-all-elf-binaries' chunker cannot leave a
# mixed-generation set behind.
rm -f "$ARCHIVE" "$ARCHIVE".part-*
tar cjf "$ARCHIVE" -C "$STAGE" .
echo "  Wrote: $ARCHIVE ($(wc -c < "$ARCHIVE" | tr -d ' ') bytes)"

# --- 12. registry --------------------------------------------------------
echo "==> Updating packages.json ..."
python3 - "$REPO/payload/packages.json" "$VERSION" <<'PY'
import json, sys
path, ver = sys.argv[1], sys.argv[2]
with open(path) as f:
    data = json.load(f)
pkg = data["packages"].get("marktext")
if pkg is None:
    print("WARNING: marktext not in packages.json; skipping version update")
else:
    pkg["version"] = ver
    print(f"packages.json: marktext version -> {ver}")
with open(path, "w") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write("\n")
PY

echo "==> Running strip-all-elf-binaries (auto-chunks the archive) ..."
# strip-all-elf-binaries carries a `#!/usr/bin/env python3.14` shebang, and the
# build image deliberately does NOT bake python3.14 (see build/Dockerfile's
# "What's NOT baked in" note -- loadout self-hosts it).  So put the
# cold-bootstrapped interpreter on PATH for the call.  $PY314 is the real file
# under $REPO/.loadout-bootstrap/..., so its bin dir is the PATH entry.
PATH="$(dirname "$PY314"):$PATH" "$REPO/build/strip-all-elf-binaries"

echo
echo "==> Done."
echo "    Next: ./build/build-shell 'PATH=\$(dirname $PY314):\$PATH python3.14 build/gen-installed-sizes'"
echo "    then: ... build/gen-content-manifest, git add payload/ ... && commit"
