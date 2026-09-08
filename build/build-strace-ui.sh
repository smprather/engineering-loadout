#!/bin/sh
# Build strace-ui (Jane Street OxCaml TUI for strace) for el8.x86_64.glibc2p28.
#
# Produces:
#   payload/el8.x86_64.glibc2p28/bin/strace-ui.bz2
#
# WHY THIS EXISTS. strace-ui turns raw strace output into a navigable
# syscall/FD browser (FD provenance tracking, struct hexdumps, dynamic
# filters). No stable release exists upstream -- 7 commits, no tags -- so
# --tag takes the pinned COMMIT HASH (nedit-ng precedent), not a version.
#
# TOOLCHAIN, load-bearing (all build-time only, nothing ships but the one
# native binary):
#   - OxCaml switch 5.2.0+ox from the oxcaml/opam-repository, pinned by
#     OX_REPO_COMMIT below. opam resolves ~260 packages (~10G switch);
#     OPAMROOT lives in a temp dir and is trap-deleted afterwards.
#   - Image prerequisites (see build/Dockerfile, absorbed 2026-09-05):
#     opam static binary, autoconf 2.72 (distro 2.69 is too old for
#     oxcaml-compiler's configure.ac which needs >= 2.71), rsync
#     (oxcaml-compiler `make install` copies with rsync, dies 127 without).
#   - `dune build --profile release`: the default dev profile fails this
#     compiler on warning 69 (unused-field) in src/virtual_list.ml.
#   - The dune file declares `(modes byte exe)`: release build emits BOTH
#     main.bc (351M bytecode, needs ocamlrun -- NOT shipped) and main.exe
#     (native, shipped). Bytecode is never packaged.
#
# LINKAGE NOTES (verified 2026-09-05 probe):
#   - NEEDED is glibc + libstdc++ + libgcc_s only. re2 links STATICALLY
#     (no libre2.so NEEDED). libunwind absent.
#   - GLIBCXX tops at 3.4.21, inside EL8 gcc-8's 3.4.25 -- host libstdc++
#     satisfies it, so NO static-link hackery (unlike verilator). The script
#     hard-fails if a rebuild ever exceeds EL8's symbols.
#
# Prerequisites on the build machine (EL8, all baked in the image):
#   source /opt/rh/gcc-toolset-14/enable
#   opam git curl gcc make patch rsync
#   # patchelf at ~/.local/bin/patchelf (bundled in this repo)
#
# Usage (run from any directory, takes ~35 min: compiler ~10 + ~260 pkgs):
#   ./build/build-strace-ui.sh --tag b48e51a2b98806049693a3dd5d10edf5fc3b719a
#
# Then, as for every payload change:
#   ./build/strip-all-elf-binaries && python3.14 build/gen-installed-sizes \
#     && python3.14 build/gen-content-manifest

set -eu

REPO="$(cd "$(dirname "$0")/.." && pwd)"
BIN_DIR="$REPO/payload/el8.x86_64.glibc2p28/bin"
LIB_DIR="$REPO/payload/el8.x86_64.glibc2p28/lib64"
TAG=""

# Pins (bump together, re-verify the guards below on every bump):
#   OX_REPO_COMMIT -- oxcaml/opam-repository commit (pins the compiler +
#     the whole Jane Street set: v0.18~preview.130.106+341 era).
OX_REPO_COMMIT="bb4555262936283daf5cbc82423509d4e7069b15"
OX_SWITCH="5.2.0+ox"
# EL8 gcc 8.5.0 ceilings (libstdc++.so.6.0.25 / libgcc): the binary must
# not reference anything newer, else stock farm nodes fail to start it.
GLIBCXX_MAX="3.4.25"
CXXABI_MAX="1.3.11"

while [ "$#" -gt 0 ]; do
    case "$1" in
        --tag)
            shift
            [ "$#" -gt 0 ] || { echo "missing value for --tag" >&2; exit 2; }
            TAG="$1"
            ;;
        -h|--help) sed -n '2,/^$/p' "$0"; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done

if [ -z "$TAG" ]; then
    echo "ERROR: --tag is required. Specify the pinned commit hash, e.g.:" >&2
    echo "  $0 --tag b48e51a2b98806049693a3dd5d10edf5fc3b719a" >&2
    echo "" >&2
    echo "Upstream: https://github.com/janestreet/strace_ui (branch oxcaml)" >&2
    echo "" >&2
    echo "Policy note: upstream has no tags; the commit hash IS the pin." >&2
    exit 1
fi

case "$TAG" in
    [0-9a-f]*)
        case "$TAG" in
            ???????*) ;;
            *) echo "ERROR: --tag must be a commit hash (got '$TAG')" >&2; exit 1 ;;
        esac
        ;;
    *) echo "ERROR: --tag must be a commit hash (got '$TAG')" >&2; exit 1 ;;
esac

# shellcheck disable=SC1091
[ -r /opt/rh/gcc-toolset-14/enable ] && . /opt/rh/gcc-toolset-14/enable

need() {
    command -v "$1" >/dev/null 2>&1 || {
        printf 'missing required command: %s\n' "$1" >&2
        exit 1
    }
}
need opam
need git
need curl
need gcc
need make
need readelf
need strip
need python3

PATCHELF="$HOME/.local/bin/patchelf"
[ -x "$PATCHELF" ] || PATCHELF="$(command -v patchelf || true)"
[ -n "$PATCHELF" ] || { echo "ERROR: patchelf not found" >&2; exit 1; }

BZIP2="$(command -v bzip2 || true)"
[ -x "$HOME/.local/bin/bzip2" ] && BZIP2="$HOME/.local/bin/bzip2"
[ -n "$BZIP2" ] || { echo "ERROR: bzip2 not found" >&2; exit 1; }

WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/build-strace-ui-XXXXXX")
export OPAMROOT="$WORK_DIR/opamroot"
export OPAMYES=1
trap 'rm -rf "$WORK_DIR"' EXIT INT TERM

echo "==> opam init (bare, no sandboxing: container has no user namespaces) ..."
opam init --disable-sandboxing --bare -y --no-setup >"$WORK_DIR/init.log" 2>&1

echo "==> Adding pinned ox repo @ $OX_REPO_COMMIT ..."
# NOTE: `opam repo add` exits nonzero with "No switch is currently set"
# even on success ([ox] Initialised) when no switch exists yet -- do NOT
# let set -e kill the script; verify via repo list instead.
opam repo add ox "git+https://github.com/oxcaml/opam-repository.git#$OX_REPO_COMMIT" \
    >"$WORK_DIR/repo.log" 2>&1 || true
# (`opam repo list` needs a switch to print anything -- check the repo dir.)
[ -d "$OPAMROOT/repo/ox" ] || {
    echo "ERROR: ox repo not registered; tail of log:" >&2
    tail -30 "$WORK_DIR/repo.log" >&2
    exit 1
}

echo "==> Creating OxCaml switch $OX_SWITCH (compiler build, ~10 min) ..."
opam switch create "$OX_SWITCH" --repos ox,default >"$WORK_DIR/switch.log" 2>&1 || {
    echo "ERROR: switch create failed; tail of log:" >&2
    tail -30 "$WORK_DIR/switch.log" >&2
    exit 1
}
eval "$(opam env --switch="$OX_SWITCH")"
echo "  $(ocaml -version)"

echo "==> Cloning strace_ui @ $TAG ..."
git clone -q https://github.com/janestreet/strace_ui "$WORK_DIR/strace_ui" \
    >>"$WORK_DIR/clone.log" 2>&1
cd "$WORK_DIR/strace_ui"
git checkout -q "$TAG"
GOT=$(git rev-parse HEAD)
case "$GOT" in
    "$TAG"*) ;;
    *)
        echo "ERROR: checkout resolved to $GOT, wanted $TAG" >&2
        exit 1
        ;;
esac
echo "  HEAD: $(git log --oneline -1)"

echo "==> Installing opam dep closure (~260 pkgs, ~15 min) ..."
opam install ./strace_ui.opam --deps-only >"$WORK_DIR/deps.log" 2>&1 || {
    echo "ERROR: dep install failed; tail of log:" >&2
    tail -30 "$WORK_DIR/deps.log" >&2
    exit 1
}
echo "  installed: $(opam list --installed --short 2>/dev/null | wc -l) packages"

echo "==> dune build --profile release (dev profile fails warning 69) ..."
dune build --profile release >"$WORK_DIR/dune.log" 2>&1 || {
    echo "ERROR: dune build failed; tail of log:" >&2
    tail -30 "$WORK_DIR/dune.log" >&2
    exit 1
}

BUILT_EXE="$WORK_DIR/strace_ui/_build/default/bin/main.exe"
[ -f "$BUILT_EXE" ] || { echo "ERROR: main.exe not produced" >&2; exit 1; }
echo "  built: $(du -h "$BUILT_EXE" | cut -f1) native (bytecode main.bc ignored)"

# ---------------------------------------------------------------------------
# NEEDED closure assertion: glibc + libstdc++ + libgcc_s ONLY. Anything else
# (libre2 dynamic, libunwind, libtinfo, ...) means the closure drifted and
# must be bundled or configured away -- never shipped silently.
# ---------------------------------------------------------------------------
echo "==> Checking NEEDED closure ..."
NEEDED=$(readelf -d "$BUILT_EXE" | sed -n 's/.*NEEDED.*\[\(.*\)\]/\1/p')
echo "  strace-ui NEEDED: $(echo "$NEEDED" | tr '\n' ' ')"
NEVER_BUNDLE="libc.so.6 libm.so.6 libpthread.so.0 libdl.so.2 librt.so.1 libstdc++.so.6 libgcc_s.so.1 ld-linux-x86-64.so.2"
for so in $NEEDED; do
    ok=0
    for a in $NEVER_BUNDLE; do [ "$a" = "$so" ] && ok=1; done
    if [ "$ok" != 1 ]; then
        echo "ERROR: strace-ui has unexpected NEEDED '$so'." >&2
        echo "       Not EL8-base-guaranteed; bundle it or configure it away." >&2
        exit 1
    fi
done
echo "  closure: OK"

# ---------------------------------------------------------------------------
# C++ symbol ceiling: host libstdc++ is gcc 8 (GLIBCXX_3.4.25). A rebuild
# against newer symbols would install fine here and die on stock nodes.
# ---------------------------------------------------------------------------
echo "==> Checking C++ symbol ceiling (host max GLIBCXX_$GLIBCXX_MAX) ..."
SYMS=$(readelf -V "$BUILT_EXE" 2>/dev/null | grep -oE 'GLIBCXX_[0-9.]+|CXXABI_[0-9.]+' | sort -Vu || true)
echo "  referenced: $(echo "$SYMS" | tr '\n' ' ')"
for s in $SYMS; do
    name=${s%%_*} ver=${s##*_}
    case "$name" in
        GLIBCXX) ceiling=$GLIBCXX_MAX ;;
        CXXABI) ceiling=$CXXABI_MAX ;;
        *) continue ;;
    esac
    if [ "$ver" != "$ceiling" ] \
        && [ "$(printf '%s\n%s\n' "$ver" "$ceiling" | sort -V | tail -1)" = "$ver" ]; then
        echo "ERROR: references $s, newer than host $name""_$ceiling" >&2
        exit 1
    fi
done
echo "  ceiling: OK"

# ---------------------------------------------------------------------------
# glibc floor assertion: EL8's glibc is 2.28.
# ---------------------------------------------------------------------------
echo "==> Checking glibc floor ..."
MAX_GLIBC=$(readelf -V "$BUILT_EXE" 2>/dev/null | grep -oE 'GLIBC_[0-9]+\.[0-9]+' | sort -V | tail -1 || true)
echo "  max glibc symbol: ${MAX_GLIBC:-none} (target: GLIBC_2.28)"
case "${MAX_GLIBC:-GLIBC_2.0}" in
    GLIBC_2.2[0-8]|GLIBC_2.1[0-9]|GLIBC_2.[0-9]) ;;
    *) echo "ERROR: needs $MAX_GLIBC; EL8 has glibc 2.28" >&2; exit 1 ;;
esac

# ---------------------------------------------------------------------------
# Functional stage-verify BEFORE packaging (house rule: flags prove nothing
# alone). 1) -version exits 0 (what the smoke probe runs). 2) Full TUI
# render under a winsize-set pty against an extracted strace: the frame must
# contain the Syscalls/Details panes and a traced execve. (A 0x0 pty renders
# nothing -- set 40x120 first; learned the hard way.)
# ---------------------------------------------------------------------------
echo "==> Functional stage-verify (-version + pty render) ..."
VER_OUT=$("$BUILT_EXE" -version 2>&1)
[ "$VER_OUT" = "NO_VERSION_UTIL" ] || {
    echo "ERROR: -version printed '$VER_OUT', expected NO_VERSION_UTIL" >&2
    exit 1
}
echo "  -version: OK"

echo "==> Pty render smoke (frame must show Syscalls + traced execve) ..."
SMOKE_DIR="$WORK_DIR/render-smoke"
mkdir -p "$SMOKE_DIR"
"$BZIP2" -dc "$BIN_DIR/strace.bz2" > "$SMOKE_DIR/strace"
chmod +x "$SMOKE_DIR/strace"
"$SMOKE_DIR/strace" -V >/dev/null 2>&1 || {
    echo "ERROR: extracted payload strace.bz2 does not run" >&2
    exit 1
}
cat > "$SMOKE_DIR/drive.py" << PYEOF
import fcntl, os, pty, select, struct, sys, termios, time
exe, sdir = sys.argv[1], sys.argv[2]
env = dict(os.environ, TERM="xterm-256color", PATH=sdir + ":" + os.environ.get("PATH", ""))
pid, fd = pty.fork()
if pid == 0:
    os.execve(exe, [exe, "sleep", "0.5"], env)
fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 120, 0, 0))
out = b""
end = time.time() + 12
sent_int = False
while time.time() < end:
    r, _, _ = select.select([fd], [], [], 0.5)
    if r:
        try:
            chunk = os.read(fd, 65536)
        except OSError:
            break
        if not chunk:
            break
        out += chunk
    if time.time() > end - 3 and not sent_int:
        try:
            os.write(fd, b"\x03")
        except OSError:
            pass
        sent_int = True
ok = all(p in out for p in (b"Syscalls", b"Details", b"execve"))
print("bytes=%d syscalls=%d details=%d execve=%d" % (
    len(out), out.count(b"Syscalls"), out.count(b"Details"), out.count(b"execve")))
sys.exit(0 if ok else 1)
PYEOF
python3 "$SMOKE_DIR/drive.py" "$BUILT_EXE" "$SMOKE_DIR" || {
    echo "ERROR: pty render smoke failed (no Syscalls/Details/execve frame)" >&2
    exit 1
}
echo "  render: OK"

# ---------------------------------------------------------------------------
# Package: strip -> patchelf RPATH -> bzip2. Order is load-bearing: NEVER
# strip after patchelf (see AGENTS.md). _build outputs are read-only, so
# chmod u+w the copy first (strip dies Permission denied otherwise).
# ---------------------------------------------------------------------------
echo "==> Packaging (strip -> patchelf -> bzip2) ..."
WORK_ART="$WORK_DIR/strace-ui"
cp "$BUILT_EXE" "$WORK_ART"
chmod u+w "$WORK_ART"
strip "$WORK_ART"
# shellcheck disable=SC2016  # $ORIGIN is an ld.so token, not a shell var
"$PATCHELF" --set-rpath '$ORIGIN/../lib64' "$WORK_ART"
"$BZIP2" -kf "$WORK_ART"
cp "${WORK_ART}.bz2" "$BIN_DIR/strace-ui.bz2"
chmod 644 "$BIN_DIR/strace-ui.bz2"
echo "  staged: $BIN_DIR/strace-ui.bz2 ($(du -h "$BIN_DIR/strace-ui.bz2" | cut -f1))"

SHORT=$(printf '%s' "$TAG" | cut -c1-7)
python3 - "$REPO/payload/packages.json" "strace-ui" "$SHORT" << 'PYEOF'
import re
import sys
path, pkg, ver = sys.argv[1:4]
txt = open(path).read()
pat = r'("%s": \{[^{}]*?"version":\s*")([^"]*)(")' % re.escape(pkg)
new, n = re.subn(pat, lambda m: m.group(1) + ver + m.group(3), txt, count=1, flags=re.S)
if n != 1:
    print(f"NOTE: no existing packages.json entry for {pkg!r}; skipping version stamp")
else:
    open(path, "w").write(new)
    print(f"packages.json: {pkg} version -> {ver}")
PYEOF

echo ""
echo "Done."
echo ""
echo "Produced:"
echo "  $BIN_DIR/strace-ui.bz2"
echo ""
echo "Next:"
echo "  ./build/strip-all-elf-binaries"
echo "  python3.14 build/gen-installed-sizes"
echo "  python3.14 build/gen-content-manifest"
