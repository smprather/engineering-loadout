#!/bin/sh
# Bundle git for EL8 as a PRIVATE git for nvim/lazy -- never on the user's PATH.
#
# WHY PRIVATE (do not "simplify" this into bin/git):
#   A loadout `git` on the user's PATH would shadow the corp-provided git. Corp
#   git-lfs, credential helpers and custom git-* subcommands resolve against THEIR
#   git's exec-path and config; a different git in front breaks them silently. This is
#   the same failure the openssh package documents (it ships `ssh10` and deliberately
#   never a bare `ssh`, so /usr/bin/ssh keeps winning). See AGENTS.md ->
#   "OpenSSH package behavior".
#
#   So this installs to  lib/loadout-git/{bin,libexec}  and NOTHING is linked into
#   bin/. The only consumer is nvim: envs/nvim/lua/global/paths.lua `ensure_git()`
#   prepends lib/loadout-git/bin to *nvim's* vim.env.PATH, and only when the system has
#   no git at all. The user's shell never sees it.
#
# WHY A WRAPPER:
#   RHEL/AlmaLinux do NOT build git with RUNTIME_PREFIX, so the binary hard-codes
#   /usr/libexec/git-core as its exec-path. Relocated, it cannot find its own helpers
#   (git-remote-https, git-fetch-pack...) and even `git clone` fails. bin/git is a
#   POSIX-sh wrapper that derives its prefix from its own path and exports
#   GIT_EXEC_PATH / GIT_TEMPLATE_DIR before exec'ing the real ELF.
#
# Shanghai: extracted from the EL8 system packages (git-core), like meld /
# mate-terminal / firefox. Deps are all EL8 BaseOS (libpcre2-8, libz, libcrypto,
# glibc) -- nothing is bundled, per AGENTS.md's never-bundle list.
#
# Usage:
#   build/build-git.sh                 # bundle the system git
#   build/build-git.sh --check         # report what would be bundled

set -eu

REPO="$(cd "$(dirname "$0")/.." && pwd)"
RUNTIME_DIR="$REPO/payload/el8.x86_64.glibc2p28/runtime"

check_only=0
[ "${1:-}" = "--check" ] && check_only=1

command -v git >/dev/null 2>&1 || { echo "no system git to bundle" >&2; exit 1; }

GIT_BIN=$(command -v git)
GIT_EXEC=$(git --exec-path)
VERSION=$(git --version | awk '{print $3}')

echo "Bundling git $VERSION"
echo "  binary : $GIT_BIN"
echo "  libexec: $GIT_EXEC ($(find "$GIT_EXEC" -maxdepth 1 | wc -l) entries)"
echo "  NEEDED : $(ldd "$GIT_BIN" | awk '{print $1}' | grep -v 'linux-vdso\|ld-linux' | tr '\n' ' ')"
echo "  (all EL8 BaseOS: pcre2, zlib, openssl, glibc -- nothing bundled)"

if [ "$check_only" -eq 1 ]; then
    exit 0
fi

STAGING="/tmp/git-nvim-staging.$$"
rm -rf "$STAGING"
mkdir -p "$STAGING/lib/loadout-git/bin" "$STAGING/lib/loadout-git/libexec"

# -a preserves the hardlinks inside git-core (164 entries share a few inodes; a naive
# copy would balloon 14 MB into ~500 MB).
cp -a "$GIT_EXEC" "$STAGING/lib/loadout-git/libexec/git-core"
cp -a "$GIT_BIN" "$STAGING/lib/loadout-git/bin/git.bin"

# scalar / git-shell are the targets of two libexec symlinks; without them those links
# dangle.
for extra in scalar git-shell; do
    if [ -x "/usr/bin/$extra" ]; then
        cp -a "/usr/bin/$extra" "$STAGING/lib/loadout-git/bin/$extra"
    fi
done

# CRITICAL: 137 of the libexec entries are symlinks to ../../bin/git -- which, in this
# layout, is the WRAPPER. Two things break if they are left alone:
#   1. the wrapper would re-derive its prefix from the symlink's own path
#      (libexec/git-core/..) and look for libexec/bin/git.bin, which does not exist;
#   2. exec'ing through the wrapper destroys argv[0], and argv[0] is exactly how git
#      knows that `git-upload-pack` means upload-pack. Every helper would run as plain
#      `git` and `git clone` would fail.
# Point them at the real ELF instead. Invoking a symlink preserves argv[0] = the link
# name, which is the whole mechanism.
find "$STAGING/lib/loadout-git/libexec/git-core" -maxdepth 1 -type l | while read -r link; do
    target=$(readlink "$link")
    case "$target" in
        ../../bin/git) ln -sf ../../bin/git.bin "$link" ;;
    esac
done

# Templates: `git init`/`clone` want them; without, git warns on every init.
if [ -d /usr/share/git-core/templates ]; then
    mkdir -p "$STAGING/lib/loadout-git/share/git-core"
    cp -a /usr/share/git-core/templates "$STAGING/lib/loadout-git/share/git-core/templates"
fi

cat > "$STAGING/lib/loadout-git/bin/git" <<'WRAPPER'
#!/bin/sh
# Private git for nvim/lazy. NOT on the user's PATH -- see build/build-git.sh.
#
# RHEL git is built without RUNTIME_PREFIX, so the binary hard-codes
# /usr/libexec/git-core. Relocated, it cannot find git-remote-https and friends, and
# `git clone` fails. Point it at our own exec-path; explicit user values still win.

case "$0" in
    /*) script=$0 ;;
    *) script=$(command -v "$0") || exit 127 ;;
esac
prefix=$(CDPATH= cd -- "$(dirname -- "$script")/.." && pwd) || exit 1

[ -n "${GIT_EXEC_PATH:-}" ] || export GIT_EXEC_PATH="$prefix/libexec/git-core"
if [ -z "${GIT_TEMPLATE_DIR:-}" ] && [ -d "$prefix/share/git-core/templates" ]; then
    export GIT_TEMPLATE_DIR="$prefix/share/git-core/templates"
fi

exec "$prefix/bin/git.bin" "$@"
WRAPPER
chmod 755 "$STAGING/lib/loadout-git/bin/git"

mkdir -p "$RUNTIME_DIR"
( cd "$STAGING" && tar -cjf "$RUNTIME_DIR/git.tar.bz2" ./lib )
rm -rf "$STAGING"

echo "Installed: $RUNTIME_DIR/git.tar.bz2 ($(du -h "$RUNTIME_DIR/git.tar.bz2" | cut -f1))"
echo ""
echo "Next: ./build/strip-all-elf-binaries && build/gen-content-manifest, then commit."
