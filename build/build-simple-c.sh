#!/bin/sh
# Build one of the small autotools/make C tools the loadout ships as a single
# binary, for el8.x86_64.glibc2p28.
#
# These five (htop, rsync, xsel, yank, yara) had NO build script and NO entry in
# ADDING_BINARIES.md, despite the repo mandating a reproducible note per tool.
# Whoever added them built by hand and left nothing behind, so the next bump had
# to re-derive the procedure from scratch. This is that procedure, executable.
# xclip joined later (2026-09-22) and follows the same contract; nethogs
# (2026-09-22) is the first member that also ships a RUNTIME library.
#
# Each tool gets its own configure flags because they genuinely differ; what is
# shared is the packaging contract every loadout binary must satisfy:
#   strip -> patchelf RPATH '$ORIGIN/../lib64:$ORIGIN/../lib' -> bzip2
#   plus a hard check that the result needs nothing newer than EL8's glibc 2.28.
#
# Usage (run from any directory):
#   ./build/build-simple-c.sh --tool yara --tag 4.5.8 --src /path/to/yara.tar.gz
#
# Then, as for every payload change:
#   ./build/strip-all-elf-binaries && python3.14 build/gen-content-manifest

set -eu

REPO="$(cd "$(dirname "$0")/.." && pwd)"
BIN_DIR="$REPO/payload/el8.x86_64.glibc2p28/bin"
LIB_DIR="$REPO/payload/el8.x86_64.glibc2p28/lib64"
TOOL=""; TAG=""; SRC_TARBALL=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        --tool) shift; TOOL="${1:-}" ;;
        --tag) shift; TAG="${1:-}" ;;
        --src) shift; SRC_TARBALL="${1:-}" ;;
        -h|--help) sed -n '2,/^$/p' "$0"; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done
[ -n "$TOOL" ] || { echo "ERROR: --tool is required (htop|nethogs|rsync|xsel|xclip|yank|yara)" >&2; exit 1; }
[ -n "$TAG" ]  || { echo "ERROR: --tag is required" >&2; exit 1; }
[ -f "$SRC_TARBALL" ] || { echo "ERROR: --src tarball not found: $SRC_TARBALL" >&2; exit 1; }

PATCHELF="$HOME/.local/bin/patchelf"
[ -x "$PATCHELF" ] || PATCHELF="$(command -v patchelf || true)"
[ -n "$PATCHELF" ] || { echo "ERROR: patchelf not found" >&2; exit 1; }

# shellcheck disable=SC1091
[ -f /opt/rh/gcc-toolset-14/enable ] && . /opt/rh/gcc-toolset-14/enable

STAGE=$(mktemp -d "${TMPDIR:-/tmp}/build-$TOOL-XXXXXX")
trap 'rm -rf "$STAGE"' EXIT INT TERM
tar xzf "$SRC_TARBALL" -C "$STAGE"
SRC=$(find "$STAGE" -maxdepth 1 -mindepth 1 -type d | head -1)

echo "==> Building $TOOL $TAG ..."
cd "$SRC"
case "$TOOL" in
    yara)
        # --disable-magic/--disable-cuckoo: those modules need libmagic and
        # jansson, which the loadout does not bundle and EL8 does not guarantee.
        # scan-for-malware only needs the core scanner.
        ./bootstrap.sh >/dev/null 2>&1
        ./configure --disable-magic --disable-cuckoo --without-crypto >/dev/null
        make -j"$(nproc)" >/dev/null
        BUILT="$SRC/yara"
        ;;
    rsync)
        # --disable-md2man avoids the doc toolchain; --disable-xxhash etc. are
        # NOT passed because packages.json ships libxxhash.so.0 for rsync.
        ./configure --disable-md2man >/dev/null
        make -j"$(nproc)" >/dev/null
        BUILT="$SRC/rsync"
        ;;
    htop)
        ./autogen.sh >/dev/null 2>&1
        ./configure --disable-unicode --enable-static=no >/dev/null
        make -j"$(nproc)" >/dev/null
        BUILT="$SRC/htop"
        ;;
    xsel)
        ./autogen.sh >/dev/null 2>&1 || autoreconf -fi >/dev/null 2>&1
        ./configure >/dev/null
        make -j"$(nproc)" >/dev/null
        BUILT="$SRC/xsel"
        ;;
    xclip)
        # GitHub tags carry configure.ac + bootstrap only -- no configure, so
        # bootstrap (autoreconf -i) runs first. NEEDED: libX11 + libXmu (Xmu's
        # XmuClientWindow); both come from gui_libs, so this package is a
        # member of @gui-suite like xsel.
        ./bootstrap >/dev/null 2>&1
        ./configure >/dev/null
        make -j"$(nproc)" >/dev/null
        BUILT="$SRC/xclip"
        ;;
    nethogs)
        # Plain make (its Makefile is hand-written, not autotools) and NO
        # configure step -- the whole build is `make -C src -f MakeApp.mk`.
        #
        # BASE gcc, deliberately: nethogs is C++14 and has no C++20 need, so
        # gcc-toolset-14 would raise its libstdc++ floor for nothing. Its
        # makefile defaults CXXFLAGS to `-Wall -Wextra -std=c++14`.
        #
        # VERSION must be passed explicitly: the Makefile gets it from
        # ./determineVersion.sh, which reads `git describe --tags` in a git
        # checkout and otherwise parses the DIRECTORY NAME (`nethogs-0.9.0` ->
        # "0.9.0"). GitHub's tag tarball is not a git repo, and the extracted
        # dir name happens to work -- but passing it makes the -V string
        # independent of how the tarball was unpacked.
        #
        # NCURSES_LIBS: its default is `-lncurses`. EL8's libncurses.so.6 and
        # libtinfo.so.6 ship as UNCLAIMED payload stems (installed with every
        # selection, RPATH $ORIGIN/../lib64 resolves them), same arrangement as
        # sqlite's readline. Nothing extra is bundled for ncurses.
        make -C src -f MakeApp.mk nethogs "VERSION=$TAG" -j"$(nproc)" >/dev/null
        BUILT="$SRC/src/nethogs"
        ;;
    yank)
        make -j"$(nproc)" >/dev/null
        BUILT="$SRC/yank"
        ;;
    *) echo "ERROR: no recipe for tool '$TOOL'" >&2; exit 1 ;;
esac

[ -x "$BUILT" ] || { echo "ERROR: $TOOL did not build ($BUILT missing)" >&2; exit 1; }

cp "$BUILT" "$STAGE/out"
/usr/bin/strip "$STAGE/out"
"$PATCHELF" --set-rpath '$ORIGIN/../lib64:$ORIGIN/../lib' "$STAGE/out" 2>/dev/null || true

# EL8 floor. A binary needing a newer glibc installs fine on this box and is
# dead on a stock farm node -- the build-box masking this repo keeps hitting.
MAXG=$(objdump -T "$STAGE/out" | grep -oE 'GLIBC_[0-9]+\.[0-9]+' | sort -V | tail -1)
case "${MAXG:-GLIBC_2.0}" in
    GLIBC_2.1[0-9]|GLIBC_2.2[0-8]|GLIBC_2.[0-9]) ;;
    GLIBC_2.0) ;;
    *) echo "ERROR: $TOOL needs $MAXG; EL8 has glibc 2.28" >&2; exit 1 ;;
esac
echo "    max glibc symbol: ${MAXG:-none}"
echo "    NEEDED: $(objdump -p "$STAGE/out" | awk '/NEEDED/ {printf "%s ", $2}')"

bzip2 -kf "$STAGE/out"
cp "$STAGE/out.bz2" "$BIN_DIR/$TOOL.bz2"
chmod 644 "$BIN_DIR/$TOOL.bz2"

# ---------------------------------------------------------------------------
# Runtime libraries, for tools that need one the host cannot be assumed to have.
#
# nethogs is the first member that ships one: it links libpcap.so.1, which is on
# EL8 base but NOT guaranteed on a newer host (this repo's ceiling gate runs on
# a CachyOS box where libpcap is present only because it was installed by hand
# for unrelated reasons -- an air-gapped farm node without it would leave
# nethogs unable to open a single interface).
#
# WHY SOURCE AND NOT THE EL8 RPM. Straight from the rpm the library looks
# perfect -- soname libpcap.so.1, glibc floor 2.28 -- but it carries
# `NEEDED libibverbs.so.1`, because the EL8 spec calls `%configure --enable-rdma`
# (libpcap.spec:61). libibverbs is NOT on EL8 base (it is baseos-available but
# not installed), it is ABSENT from the CachyOS dev host, and it drags in a
# second closure of its own. Shipping the rpm as-is would produce a library that
# loads on neither a stock farm node nor the ceiling-gate host.
#
# So: libpcap 1.9.1 -- the same upstream version EL8 packages -- built with
# `--disable-rdma --disable-bluetooth --disable-dbus`. RDMA capture is irrelevant
# to nethogs (it monitors ordinary interfaces), and the other two keep the link
# closure at libc. Upstream's configure only probes for ibverbs when rdma is not
# "no" (configure:10920-10934) and only probes dbus inside the bluetooth block
# (configure:10846-10874), so the flags are jointly sufficient:
#   --disable-rdma        drops libibverbs.so.1
#   --disable-bluetooth   skips the BT sniffers (needs bluez headers)
#   --disable-dbus        skips the BT-monitor D-Bus probe, which otherwise
#                         links libdbus-1.so.3 -- a gui_libs library this
#                         package must not drag in (nethogs is not a GUI tool).
# Result: NEEDED = libc.so.6 alone.
#
# The tarball URL and sha256 are pinned; EL8's own source rpm carries the
# identical libpcap-1.9.1.tar.gz, so this is the same code the distro ships.
# ---------------------------------------------------------------------------
if [ "$TOOL" = "nethogs" ]; then
    echo "==> Bundling libpcap.so.1 (source build, no rdma/bluetooth/dbus) for $TOOL ..."
    PCAP_SO=$(objdump -p "$STAGE/out" | awk '/NEEDED/ && /libpcap/ {print $2}')
    [ -n "$PCAP_SO" ] || { echo "ERROR: $TOOL does not NEED libpcap -- recipe changed?" >&2; exit 1; }
    [ "$PCAP_SO" = "libpcap.so.1" ] || { echo "ERROR: unexpected soname $PCAP_SO" >&2; exit 1; }

    PCAP_VERSION=1.9.1
    # Verified two ways: this is the sha256 of tcpdump.org's tarball, AND it is
    # byte-identical to the libpcap-1.9.1.tar.gz inside EL8's own
    # libpcap-1.9.1-5.el8.src.rpm (`dnf download --source libpcap`). An upstream
    # GPG signature (libpcap-1.9.1.tar.gz.sig, RSA key
    # 1F166A5742ABB9E0249A8D30E089DEF1D9C15D0D) is published alongside it.
    PCAP_SHA256=635237637c5b619bcceba91900666b64d56ecb7be63f298f601ec786ce087094
    PCAP_TMP=$(mktemp -d "${TMPDIR:-/tmp}/build-pcap-XXXXXX")
    curl -fsSL -o "$PCAP_TMP/libpcap.tar.gz" \
        "https://www.tcpdump.org/release/libpcap-${PCAP_VERSION}.tar.gz"
    echo "$PCAP_SHA256  $PCAP_TMP/libpcap.tar.gz" | sha256sum -c - > /dev/null || {
        echo "ERROR: libpcap tarball sha256 mismatch -- refusing to build it." >&2
        echo "       Expected $PCAP_SHA256" >&2
        exit 1
    }
    tar xzf "$PCAP_TMP/libpcap.tar.gz" -C "$PCAP_TMP"
    (
        cd "$PCAP_TMP/libpcap-${PCAP_VERSION}"
        ./configure --prefix="$PCAP_TMP/inst" --disable-rdma --disable-bluetooth \
            --disable-dbus --with-pic > "$PCAP_TMP/configure.log" 2>&1
        make -j"$(nproc)" > "$PCAP_TMP/build.log" 2>&1
    ) || {
        echo "ERROR: libpcap build failed; tail of log:" >&2
        tail -20 "$PCAP_TMP/build.log" 2>&1 >&2
        tail -20 "$PCAP_TMP/configure.log" 2>&1 >&2
        exit 1
    }
    PCAP_LIB="$PCAP_TMP/libpcap-${PCAP_VERSION}/libpcap.so.1.9.1"
    [ -f "$PCAP_LIB" ] || { echo "ERROR: libpcap.so.1.9.1 not produced" >&2; exit 1; }

    # The guard that makes the three --disable flags meaningful. libpcap must
    # come out needing libc and nothing else; any extra soname is a configure
    # probe that found a build-box library (ibverbs, dbus, bluez) and would ship
    # a dependency no farm node has.
    PCAP_EXTRA=$(objdump -p "$PCAP_LIB" | awk '/NEEDED/ && $2 != "libc.so.6" {print $2}')
    if [ -n "$PCAP_EXTRA" ]; then
        echo "ERROR: libpcap NEEDs libraries beyond libc: $PCAP_EXTRA" >&2
        echo "       A configure probe picked up a build-box library. The" >&2
        echo "       --disable-rdma/--disable-bluetooth/--disable-dbus set is" >&2
        echo "       supposed to keep this at libc alone -- check which probe" >&2
        echo "       found it before relaxing this." >&2
        exit 1
    fi

    PMAXG=$(objdump -T "$PCAP_LIB" | grep -oE 'GLIBC_[0-9]+\.[0-9]+' | sort -V | tail -1)
    case "${PMAXG:-GLIBC_2.0}" in
        GLIBC_2.1[0-9]|GLIBC_2.2[0-8]|GLIBC_2.[0-9]|GLIBC_2.0) ;;
        *) echo "ERROR: libpcap needs $PMAXG; EL8 has glibc 2.28" >&2; exit 1 ;;
    esac
    echo "    libpcap max glibc symbol: ${PMAXG:-none}"
    echo "    libpcap NEEDED: $(objdump -p "$PCAP_LIB" | awk '/NEEDED/ {printf "%s ", $2}')"
    echo "    libpcap SONAME: $(readelf -d "$PCAP_LIB" | awk '/SONAME/ {print $NF}')"

    cp "$PCAP_LIB" "$PCAP_TMP/pcap-stripped"
    /usr/bin/strip "$PCAP_TMP/pcap-stripped"
    "$PATCHELF" --set-rpath '$ORIGIN' "$PCAP_TMP/pcap-stripped"
    bzip2 -kf "$PCAP_TMP/pcap-stripped"
    cp "$PCAP_TMP/pcap-stripped.bz2" "$LIB_DIR/$PCAP_SO.bz2"
    chmod 644 "$LIB_DIR/$PCAP_SO.bz2"
    rm -rf "$PCAP_TMP"
    echo "Staged: payload/el8.x86_64.glibc2p28/lib64/$PCAP_SO.bz2"
fi

python3 - "$REPO/payload/packages.json" "$TOOL" "$TAG" <<'PYEOF'
import re, sys
path, pkg, version = sys.argv[1], sys.argv[2], sys.argv[3]
raw = open(path).read()
pat = re.compile(r'("%s":\s*\{(?:[^{}]|\{[^{}]*\})*?"version":\s*")([^"]*)(")' % pkg)
raw, n = pat.subn(lambda m: m.group(1) + version + m.group(3), raw, count=1)
if n != 1:
    sys.exit("could not stamp %s version in packages.json" % pkg)
open(path, "w").write(raw)
print("    packages.json: %s -> %s" % (pkg, version))
PYEOF

echo "Staged: payload/el8.x86_64.glibc2p28/bin/$TOOL.bz2"
