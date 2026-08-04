#!/bin/sh
# Build zsh from source for el8.x86_64.glibc2p28.
#
# Produces a dynamically-linked zsh binary (links system glibc + bundled
# ncurses/readline) PLUS the full set of dynamically-loaded zsh modules
# (zsh/regex, zsh/pcre, zsh/mathfunc, zsh/stat, zsh/mapfile, zsh/parameter,
# zsh/complist, zsh/zprof, zsh/zpty, zsh/socket, zsh/tcp, zsh/zftp,
# zsh/system, zsh/cap, zsh/clone, zsh/datetime, zsh/langinfo, zsh/terminfo,
# zsh/termcap, zsh/zutil, zsh/files, zsh/watch, zsh/newuser, zsh/attr,
# zsh/nearcolor, zsh/zselect). Modules install to lib/zsh/<ver>/zsh/*.so
# and are patchelf'd with an RPATH that reaches the bundled lib64/ (four
# parent hops for the flat modules, five for the nested net/ and param/
# ones -- see the patchelf loop below) so zsh/pcre finds libpcre.so.1 on
# its own, not merely because bin/zsh happens to preload it.
#
# PCRE1 (libpcre.so.1) is bundled (bzip2'd into lib64/, like every other
# bundled lib) for zsh/pcre; it is an EL8 BaseOS package but not guaranteed
# on every locked-down target. bin/zsh itself NEEDs it, so a target without
# system pcre1 cannot even start zsh unless we ship it.
#
# Module set: the build ships every module `configure` + `make` produce,
# including zsh/curses, zsh/example, zsh/deltochar, zsh/rlimits and
# zsh/sched. Only zsh/db/gdbm is dropped -- configure auto-disables it when
# libgdbm-devel is absent, which it is on the EL8 build base.
#
# Note: official zsh prebuilts are source tarballs only; this script builds
# from the GitHub mirror at a stable tagged release.
#
# Policy: always build from a stable tagged release. See stable tags at:
#   https://github.com/zsh-users/zsh/releases
#   https://sourceforge.net/projects/zsh/files/zsh/
#
# Prerequisites on the build machine (EL8):
#   sudo dnf install gcc make autoconf autoconf-archive ncurses-devel \
#                    readline-devel texinfo yodl gettext pcre-devel
#   # gcc-toolset-14 optional but recommended for consistent ABI
#
# Usage (run from any directory):
#   /path/to/build-zsh.sh --tag 5.9

set -eu

REPO="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib.sh
. "$REPO/build/lib.sh"
BIN_DIR="$LOADOUT_BIN_DIR"
PATCHELF="$LOADOUT_PATCHELF"
CLONE_URL="https://github.com/zsh-users/zsh.git"

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

loadout_require_tag "$tag" "$0" "https://github.com/zsh-users/zsh/releases" "5.9"
loadout_enable_gcc_toolset
loadout_require_cmds autoconf gcc make

SRCDIR="/tmp/zsh-src-${tag}"
INSTALL_PREFIX="/tmp/zsh-install-${tag}"

if [ ! -d "$SRCDIR/.git" ]; then
    echo "Cloning $CLONE_URL ..."
    git clone --filter=blob:none "$CLONE_URL" "$SRCDIR"
fi

cd "$SRCDIR"
git fetch --tags
# zsh release tags are prefixed: the 5.9 release is the tag "zsh-5.9" (a bare
# "5.9" is NOT a ref -- an earlier version of this script checked out "5.9",
# silently stayed on a dev commit, and shipped 5.8.0.1-dev). Accept the bare
# version as --tag and map to the real tag here.
git checkout "zsh-$tag"

if [ "$clean" -eq 1 ]; then
    [ -f Makefile ] && make distclean || true
fi

if [ ! -f configure ]; then
    echo "Generating configure script..."
    autoreconf -fi || autoconf
fi

# Patch: zsh 5.9 Src/Modules/termcap.c declares local `boolcodes`/`numcodes`
# arrays that conflict with the `const char * const []` declarations in modern
# ncurses term.h (GCC: "conflicting types"). zsh already renamed strcodes ->
# zstrcodes for the same reason but missed these two. Rename them to match.
if grep -q 'static char \*boolcodes\[\]' Src/Modules/termcap.c 2>/dev/null; then
    echo "Patching termcap.c (boolcodes/numcodes ncurses const conflict)..."
    sed -i 's/\bboolcodes\b/zboolcodes/g; s/\bnumcodes\b/znumcodes/g' Src/Modules/termcap.c
fi

rm -rf "$INSTALL_PREFIX"

# Build WITH PCRE (zsh/pcre module) -- libpcre.so.1 is bundled for deployment.
# ncurses and readline are bundled from this repo ($ORIGIN/../lib64).
# --enable-cap: POSIX capabilities support (libcap is always on EL8).
# Dynamic modules are ON (default) -- they install as .so files under
# lib/zsh/<ver>/zsh/ and are loaded on demand by zmodload.
#
# Do NOT add --enable-zsh-secure-free: it is a DEBUG allocator that runs error
# checking on every free(), which makes allocation-heavy work pathologically
# slow. With it on, compinit's compdump (line 108 globs every fpath dir against
# a ~900-branch alternation of _* function names -- very alloc-heavy) takes
# >60s and looks like a startup hang. Plain release builds dump in well under a
# second.
#
# Do NOT add --without-tcsetpgrp: that disables terminal process-group handling
# (job control). Linux always has tcsetpgrp; let configure auto-detect it so an
# interactive zsh gets working Ctrl-Z / fg / bg.
#
# CRITICAL -- override three autoconf AC_TRY_RUN feature probes (cache vars
# below). These probes COMPILE AND RUN small programs that fork children and
# poke signals / process groups. When this build runs inside a restricted build
# environment (sandbox, no controlling tty, ptrace/seccomp), those probes
# misbehave and configure wrongly concludes the syscalls are "broken":
#   zsh_cv_sys_killesrch=no  -> #define BROKEN_KILL_ESRCH
#     and, nested under it, also runs and fails:
#   zsh_cv_sys_sigsuspend=no -> #define BROKEN_POSIX_SIGSUSPEND
#   zsh_cv_sys_tcsetpgrp=no  -> #define BROKEN_TCSETPGRP
# BROKEN_POSIX_SIGSUSPEND is the killer: it swaps zsh's race-free sigsuspend()
# child-wait for a pause() fallback that has a lost-wakeup race -- SIGCHLD is
# reaped in the handler, then zsh calls pause() waiting for a SIGCHLD that
# already fired, so EVERY command substitution and job-wait hangs forever.
# On real EL8 (glibc 2.28) all three syscalls work correctly; the probes only
# failed because of WHERE we built. Pre-seeding the cache vars (the ${var+:}
# guard in configure skips the run-test when the var is already set) bakes in
# the correct target-platform answer.
#
# Two MORE AC_TRY_RUN probes disable dynamic module loading in a sandbox:
#   zsh_cv_func_dlsym_needs_underscore=failed -> dynamic=no
#     The probe dlopen()s a compiled conftest .so and calls dlsym on it;
#     sandbox/ptrace restrictions make the dlopen fail, so configure kills
#     all dynamic modules. On Linux glibc the answer is always "no" (no
#     leading underscore needed).
#   zsh_cv_shared_environ=no -> dynamic=no
#     The probe checks whether shared libs can see the main binary's
#     environ. It forks a child that reads environ from a shared lib;
#     sandbox restrictions break the fork/exec. On Linux glibc the
#     answer is always "yes".
# Without pre-seeding both, every dynamic module (zsh/regex, zsh/pcre,
# zsh/mathfunc, zsh/stat, zsh/mapfile, zsh/zprof, zsh/zpty, zsh/socket,
# zsh/tcp, zsh/zftp, zsh/system, zsh/cap, zsh/clone, zsh/files,
# zsh/watch, zsh/newuser, zsh/nearcolor, zsh/zselect) silently gets
# link=no and is never compiled. The "either" modules (parameter,
# complist, datetime, langinfo, terminfo, zutil) fall back to static,
# which works but bloats the binary and prevents zmodload -u.
zsh_cv_sys_killesrch=yes \
zsh_cv_sys_sigsuspend=yes \
zsh_cv_sys_tcsetpgrp=yes \
zsh_cv_func_dlsym_needs_underscore=no \
zsh_cv_shared_environ=yes \
./configure \
    --prefix="$INSTALL_PREFIX" \
    --bindir="$INSTALL_PREFIX/bin" \
    --enable-cap \
    --enable-pcre \
    --enable-multibyte \
    CFLAGS="-O2 -fstack-protector-strong"

make -j"$(nproc 2>/dev/null || echo 8)"
# Install binary + modules + shell functions. Skip install.man / install.info
# -- zsh's man pages need `yodl` (absent on EL8) and we bundle only the
# self-contained binary + modules anyway.
make install.bin install.modules install.fns

echo ""
echo "Build complete: $("$INSTALL_PREFIX/bin/zsh" --version)"
echo ""

# Sanity: refuse a dev build (stable-release policy). The release tag must yield
# a clean X.Y version, not an X.Y.Z-dev string.
_zver="$("$INSTALL_PREFIX/bin/zsh" -c 'print -r -- $ZSH_VERSION')"
case "$_zver" in
    *-dev|*dev*)
        echo "ERROR: built zsh reports dev version '$_zver' -- not a stable release. Aborting." >&2
        exit 1 ;;
esac
echo "ZSH_VERSION: $_zver"

# Set RPATH on every dynamic module .so so they resolve bundled lib64 deps
# (libpcre.so.1, libncursesw.so.6, etc.) at runtime WITHOUT relying on
# bin/zsh having preloaded them. Modules live at lib/zsh/<ver>/zsh/*.so, so
# the install prefix -- whose lib64/ holds the bundled libs -- is four parent
# hops up ($ORIGIN/../../../../lib64). The nested net/ and param/ modules sit
# one directory deeper and need five hops. An earlier revision used a single
# $ORIGIN/../../.. for all of them, which resolves to <prefix>/lib (no libs)
# and only worked because bin/zsh preloads the shared deps.
# patchelf failure is fatal: a module shipping with a dead RPATH is a bug.
MODULE_DIR="$INSTALL_PREFIX/lib/zsh/$_zver/zsh"
if [ -d "$MODULE_DIR" ]; then
    echo "Setting RPATH on zsh modules..."
    for mod in "$MODULE_DIR"/*.so; do
        [ -f "$mod" ] || continue
        "$PATCHELF" --set-rpath '$ORIGIN/../../../../lib64' "$mod" || {
            echo "ERROR: patchelf failed for $mod" >&2; exit 1
        }
    done
    for mod in "$MODULE_DIR"/net/*.so "$MODULE_DIR"/param/*.so; do
        [ -f "$mod" ] || continue
        "$PATCHELF" --set-rpath '$ORIGIN/../../../../../lib64' "$mod" || {
            echo "ERROR: patchelf failed for $mod" >&2; exit 1
        }
    done
    echo "  Module count: $(find "$MODULE_DIR" -name '*.so' | wc -l)"
else
    echo "ERROR: no module directory found at $MODULE_DIR" >&2
    exit 1
fi

# libzsh-<ver>.so lives at lib/zsh/ (two hops below the prefix) and NEEDs the
# bundled lib64/ deps directly, so its RPATH is $ORIGIN/../../lib64.
if [ -f "$INSTALL_PREFIX/lib/zsh/libzsh-$_zver.so" ]; then
    echo "Setting RPATH on libzsh-$_zver.so..."
    "$PATCHELF" --set-rpath '$ORIGIN/../../lib64' "$INSTALL_PREFIX/lib/zsh/libzsh-$_zver.so"
fi

# Bundle libpcre.so.1 (PCRE1) for zsh/pcre. It is an EL8 BaseOS package but
# not guaranteed on every locked-down target, and bin/zsh NEEDs it directly.
# It MUST be bzip2-compressed like every other bundled lib64/ file: the
# installer only decompresses lib64/*.bz2, so a raw ELF here is silently
# never installed (a `loadout doctor` "Missing bin/lib artifacts" gap that
# only surfaces on a host lacking system pcre1 -- classic build-box masking).
LIB64_DIR="$REPO/payload/$LOADOUT_PLATFORM/lib64"
mkdir -p "$LIB64_DIR"
if [ -f /lib64/libpcre.so.1 ]; then
    echo "Bundling libpcre.so.1 for zsh/pcre module..."
    _pcre_tmp="/tmp/libpcre.so.1.$$"
    cp /lib64/libpcre.so.1 "$_pcre_tmp"
    "$PATCHELF" --set-rpath '$ORIGIN' "$_pcre_tmp" || {
        echo "ERROR: patchelf failed for libpcre.so.1" >&2; exit 1
    }
    rm -f "$LIB64_DIR/libpcre.so.1" "$LIB64_DIR/libpcre.so.1.bz2"
    bzip2 -c "$_pcre_tmp" > "$LIB64_DIR/libpcre.so.1.bz2"
    rm -f "$_pcre_tmp"
else
    echo "ERROR: /lib64/libpcre.so.1 not found; cannot bundle zsh/pcre dep" >&2
    exit 1
fi

# Package the zsh function library (fpath) + dynamic modules as a runtime
# archive. The binary is built with dynamic modules -- the .so files live at
# lib/zsh/<ver>/zsh/ and MUST ship alongside the functions so zmodload works.
# The shell functions (compinit, add-zsh-hook, the _* completions, etc.) live
# in share/zsh/<ver>/functions and share/zsh/site-functions and MUST ship --
# without them fpath points at this gone /tmp build prefix and
# compinit/add-zsh-hook fail (starship's zsh init hangs). zsh/zshrc points
# fpath at the installed copy.
RUNTIME_DIR="$REPO/payload/el8.x86_64.glibc2p28/runtime"
mkdir -p "$RUNTIME_DIR"
echo "Packaging zsh function library + modules -> runtime/zsh.tar.bz2 ..."
tar -cjf "/tmp/zsh_runtime_${tag}.tar.bz2" -C "$INSTALL_PREFIX" \
    --exclude='./share/zsh/*/help' \
    ./share/zsh \
    ./lib/zsh
cp "/tmp/zsh_runtime_${tag}.tar.bz2" "$RUNTIME_DIR/zsh.tar.bz2"
rm -f "/tmp/zsh_runtime_${tag}.tar.bz2"

# Package the binary + stamp the registry version. The binary needs
# libzsh-5.9.so (in lib/zsh/) as well as the usual lib64/ deps, so the
# RPATH adds $ORIGIN/../lib/zsh to the standard search path.
# shellcheck disable=SC2016  # $ORIGIN is an ld.so token, not a shell var
loadout_package_bin "$INSTALL_PREFIX/bin/zsh" zsh '$ORIGIN/../lib/zsh:$ORIGIN/../lib64:$ORIGIN/../lib'
loadout_stamp_version zsh "$tag"

# Update strip manifest
echo "Running strip-all-elf-binaries..."
"$REPO/build/strip-all-elf-binaries"

# glibc check
MAX_GLIBC="$(readelf -V "$INSTALL_PREFIX/bin/zsh" 2>/dev/null \
    | grep -oE 'GLIBC_[0-9]+\.[0-9]+' | sort -V | tail -1)"
echo "Max glibc symbol: $MAX_GLIBC (target: GLIBC_2.28)"
case "$MAX_GLIBC" in
    GLIBC_2.2[0-8]|GLIBC_2.1[0-9]|GLIBC_2.[0-9])
        echo "OK -- binary compatible with EL8 glibc 2.28" ;;
    *)
        echo "WARNING: $MAX_GLIBC > GLIBC_2.28 -- binary may not run on EL8" >&2 ;;
esac

echo ""
echo "Installed: $BIN_DIR/zsh.bz2"
echo ""
echo "Commit with:"
echo "  git add payload/el8.x86_64.glibc2p28/bin/zsh.bz2 \\"
echo "          payload/el8.x86_64.glibc2p28/runtime/zsh.tar.bz2 \\"
echo "          payload/el8.x86_64.glibc2p28/lib64/libpcre.so.1.bz2 \\"
echo "          .strip-manifest .content-manifest payload/packages.json"
echo "  git commit -m 'feat(payload): zsh ${tag} with dynamic modules'"
