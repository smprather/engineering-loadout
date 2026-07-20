#!/bin/sh
# Build the OpenSSH client suite from source for el8.x86_64.glibc2p28.
#
# Produces ssh10/ssh10.bin plus signer/agent tools -- ssh-keygen, ssh-add,
# ssh-agent, ssh-keyscan -- that link only against system libraries present on
# every EL8 host (glibc 2.28, libcrypto.so.1.1 from openssl-libs, libz.so.1).
# No loadout-bundled libs are required, so the package declares no depends.
#
# Why bundle a newer OpenSSH at all: git commit/tag signing shells out to
# `ssh-keygen -Y sign`, which was added in OpenSSH 8.2. Stock EL8 ships 8.0p1,
# whose ssh-keygen has no `-Y` subcommand, so `git tag -s` fails there. A
# modern ssh-keygen on PATH (this package installs into ~/.local/bin) makes SSH
# git signing work on any EL8 node. See docs/SECURITY.md section 6.
#
# Note: sshd is intentionally NOT built or shipped -- this is a client suite.
# Bare ssh/scp/sftp are intentionally NOT shipped. Mainline OpenSSH does not
# understand Red Hat's GSSAPIKexAlgorithms crypto-policy directive, so exposing
# a bare ssh on PATH breaks host-integrated SSH on RHEL. ssh10 is an explicit
# wrapper that runs ssh10.bin with -F ~/.ssh/config (or /dev/null) so it skips
# host /etc/ssh/ssh_config while normal ssh falls through to /usr/bin/ssh.
#
# Policy: always build from a stable tagged release. Tags use the form
# V_<major>_<minor>_P<n> and map to release <major>.<minor>p<n>. See:
#   https://github.com/openssh/openssh-portable/tags
#
# Prerequisites on the build machine (EL8):
#   sudo dnf install gcc make autoconf automake openssl-devel zlib-devel
#   # gcc-toolset-14 optional but recommended for a consistent ABI
#
# Usage (run from any directory):
#   /path/to/build-openssh.sh --tag V_10_4_P1

set -eu

REPO="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091  # sourced through runtime-computed repo root
. "$REPO/build/lib.sh"
CLONE_URL="https://github.com/openssh/openssh-portable.git"

BUILD_BINS="ssh ssh-keygen ssh-add ssh-agent ssh-keyscan"
INSTALL_BINS="ssh-keygen ssh-add ssh-agent ssh-keyscan"

clean=0
tag=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --clean) clean=1 ;;
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

loadout_require_tag "$tag" "$0" "https://github.com/openssh/openssh-portable/tags" "V_10_4_P1"
loadout_enable_gcc_toolset
loadout_require_cmds autoreconf gcc make

# Map the git tag (V_10_4_P1) to the human release string (10.4p1) for the
# registry version and the dev-build sanity check below.
ver=$(printf '%s\n' "$tag" | sed -E 's/^V_([0-9]+)_([0-9]+)_P([0-9]+)$/\1.\2p\3/')
case "$ver" in
    *_*) echo "ERROR: --tag must look like V_10_4_P1 (got '$tag')" >&2; exit 2 ;;
esac

SRCDIR="/tmp/openssh-src-${tag}"
INSTALL_PREFIX="/tmp/openssh-install-${tag}"

if [ ! -d "$SRCDIR/.git" ]; then
    echo "Cloning $CLONE_URL ..."
    git clone --filter=blob:none "$CLONE_URL" "$SRCDIR"
fi

cd "$SRCDIR"
git fetch --tags
git checkout "$tag"

if [ "$clean" -eq 1 ]; then
    [ -f Makefile ] && make distclean || true
fi

# The GitHub source tree has no generated ./configure (unlike the openbsd.org
# release tarball), so regenerate it.
if [ ! -f configure ]; then
    echo "Generating configure script..."
    autoreconf
fi

rm -rf "$INSTALL_PREFIX"

# Client-only build. --sysconfdir=/etc/ssh so the bundled ssh reads the host's
# global ssh_config; links system openssl (1.1.1 on EL8) and zlib.
./configure \
    --prefix="$INSTALL_PREFIX" \
    --sysconfdir=/etc/ssh \
    --with-ssl-dir=/usr \
    --without-zlib-version-check \
    CFLAGS="-O2 -fstack-protector-strong"

# Build only the client binaries we package -- skip sshd, scp, and sftp.
# shellcheck disable=SC2086  # word-split $BUILD_BINS into separate make targets
make -j"$(nproc 2>/dev/null || echo 8)" $BUILD_BINS

echo ""
echo "Build complete: $(./ssh -V 2>&1)"
echo ""

# Sanity: refuse a dev/portable snapshot (stable-release policy). A release tag
# yields a clean "OpenSSH_10.4p1" banner, never a git-describe string.
_banner="$(./ssh -V 2>&1)"
case "$_banner" in
    *"OpenSSH_${ver}"*) : ;;
    *) echo "ERROR: ssh banner '$_banner' does not match release ${ver} -- not a stable tag. Aborting." >&2; exit 1 ;;
esac

# Confirm the signing subcommand exists (the whole point of bundling this).
if ./ssh-keygen -Y 2>&1 | grep -qi 'unknown option'; then
    echo "ERROR: built ssh-keygen has no -Y subcommand (too old to sign). Aborting." >&2
    exit 1
fi
echo "ssh-keygen -Y sign: available"

# Package each binary (strip -> patchelf RPATH -> bzip2 -> payload bin dir) and
# report its glibc floor. The real ssh binary is namespaced as ssh10.bin; the
# public ssh10 entry point is a shell wrapper generated below.
loadout_package_bin "$SRCDIR/ssh" "ssh10.bin"
loadout_report_max_glibc "$SRCDIR/ssh"
for b in $INSTALL_BINS; do
    loadout_package_bin "$SRCDIR/$b" "$b"
    loadout_report_max_glibc "$SRCDIR/$b"
done

_ssh10_wrapper=$(mktemp "${TMPDIR:-/tmp}/loadout-ssh10.XXXXXX")
cat > "$_ssh10_wrapper" << 'EOF'
#!/bin/sh
#
# OpenSSH 10.x explicit client (loadout).
# Mainline OpenSSH cannot parse RHEL crypto-policy's GSSAPIKexAlgorithms
# directive. Skip host /etc/ssh/ssh_config by supplying -F unless the caller
# already supplied one. Normal `ssh` is deliberately left to /usr/bin/ssh.

bin_dir=$(unset CDPATH; cd "$(dirname "$0")" && pwd -P) || exit 1
real="$bin_dir/ssh10.bin"

if [ ! -x "$real" ]; then
  echo "ssh10: missing executable: $real" >&2
  exit 127
fi

has_config=0
for arg do
  case "$arg" in
    -F|-F*) has_config=1 ;;
  esac
done

if [ "$has_config" -eq 1 ]; then
  exec "$real" "$@"
fi

cfg=/dev/null
if [ -n "${HOME:-}" ] && [ -f "$HOME/.ssh/config" ]; then
  cfg=$HOME/.ssh/config
fi

exec "$real" -F "$cfg" "$@"
EOF
bzip2 -f "$_ssh10_wrapper"
mkdir -p "$LOADOUT_BIN_DIR"
cp "${_ssh10_wrapper}.bz2" "$LOADOUT_BIN_DIR/ssh10.bz2"
chmod 644 "$LOADOUT_BIN_DIR/ssh10.bz2"
rm -f "${_ssh10_wrapper}.bz2"
rm -f "$LOADOUT_BIN_DIR/ssh.bz2" "$LOADOUT_BIN_DIR/scp.bz2" "$LOADOUT_BIN_DIR/sftp.bz2"

loadout_stamp_version openssh "$ver"

echo ""
echo "Running strip-all-elf-binaries..."
"$REPO/strip-all-elf-binaries"

echo ""
echo "Installed OpenSSH ${ver} client suite into $LOADOUT_BIN_DIR:"
for b in ssh10 ssh10.bin $INSTALL_BINS; do echo "  $b.bz2"; done
echo ""
echo "Commit with:"
echo "  git add payload/$LOADOUT_PLATFORM/bin/{ssh10,ssh10.bin,$(echo "$INSTALL_BINS" | tr ' ' ',')}.bz2 \\"
echo "          .strip-manifest .content-manifest payload/packages.json \\"
echo "          envs/bash/global/completions/loadout.bash build/build-openssh.sh"
echo "  git commit -m 'feat(payload): OpenSSH ${ver} client suite (EL8 source build)'"
