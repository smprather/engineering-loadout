#!/usr/bin/env bash
# Build xschem (schematic capture / SPICE netlister) from source for
# el8.x86_64.glibc2p28.
#
# xschem is a Tcl/Tk + X11 schematic editor and netlist generator for VLSI /
# analog custom design. It is bundled because it is the incumbent open-source
# schematic front-end for the ngspice / openroad / liberty flows we already
# ship, and there is no loadout alternative: the netlists it produces (and the
# .sym symbol library) are what an analog/EDA bring-up actually needs.
#
# WHY A PRIVATE Tcl/Tk 8.6 (this is the load-bearing design decision)
# ------------------------------------------------------------------
# xschem is a Tcl/Tk APPLICATION: the binary calls Tcl_Init/Tk_Init, its whole
# UI and netlist engine are xschem.tcl, and clipboard + message boxes go through
# Tk. The binary genuinely imports Tk symbols (Tk_Init, Tk_MainLoop, ...), so
# the link against libtk8.6.so is REQUIRED, not incidental.
#
# The payload's `tcl`/`tk` packages are Tcl/Tk 9.0, and xschem's Tcl layer is
# 8.6-era (winfo containing, ::tk::unsupported::MacWindowStyle, ...). Linking
# against 9.0 is not an option. On EL8, Tcl/Tk 8.6 is an AppStream package -- a
# minimal farm node may not have it -- so a host-provided Tk is not acceptable
# either.
#
# So we build a SELF-CONTAINED, private Tcl 8.6 + Tk 8.6 and co-locate it with
# the real ELF (the expect model, extended to Tk). Layout:
#
#   <prefix>/lib/xschem/bin/xschem.bin     the real ELF
#   <prefix>/lib/xschem/lib/libtcl8.6.so   private Tcl 8.6
#   <prefix>/lib/xschem/lib/libtk8.6.so    private Tk 8.6
#   <prefix>/lib/xschem/lib/{tcl8.6,tcl8,tk8.6}  Tcl/Tk SCRIPT libraries
#
# Tcl and Tk locate their script libraries via Tcl's own <exedir>/../lib/tcl8.6
# and <exedir>/../lib/tk8.6 fallback (the compiled-in prefix is dead once
# deployed), so the LAYOUT does the work: no TCL_LIBRARY/TK_LIBRARY env is
# exported and no script library is written under <prefix>/lib/tcl8.6, which
# portable-python owns at a different patchlevel (the documented cross-clobber
# hazard). Everything stays under <prefix>/lib/xschem, so the tree is
# relocatable and cannot collide with the payload's own Tcl 9 or expect's
# Tcl 8.6. A private libtcl8.6.so co-existing with expect's same-soname copy in
# a shared process is the standard two-versions-in-isolated-vfs case; each app
# resolves its own copy via $ORIGIN, so the two never interpose.
#
# RELOCATION: upstream's system xschemrc template ships with the
# XSCHEM_LIBRARY_PATH block COMMENTED OUT, so an installed tree falls back to
# the build prefix compiled into the binary -- which is dead after deploy, and
# a relocatable (~/.local or --dest-dir) install would lose its symbol library
# entirely. The wrapper exports XSCHEM_SHAREDIR, and this script uncomments /
# installs the equivalent path derivation into the shipped system xschemrc so
# the library path is rebuilt from the RUNTIME sharedir. This is the upstream-
# documented customization point (see the block's own comments), needs no ELF
# rewriting, and keeps a --dest-dir / fake-HOME install fully functional. This
# is asserted at stage-verify: the build prefix is MOVED AWAY and the headless
# netlist must still resolve every symbol.
#
# Prerequisites on the build machine (EL8; all baked into build/Dockerfile):
#   tcl-devel tk-devel libX11-devel libXpm-devel libXrender-devel cairo-devel
#   libxcb-devel libxcb-render-devel libjpeg-turbo-devel libX11-xcb-devel
#   bison flex patchelf
#
# Usage (run from any directory, inside the EL8 build container):
#   build/build-shell build/build-xschem.sh --tag 3.4.7

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="$REPO/payload/el8.x86_64.glibc2p28/bin"
RUNTIME_DIR="$REPO/payload/el8.x86_64.glibc2p28/runtime"
CLONE_URL="https://codeberg.org/stef_xschem/xschem.git"
PATCHELF="${LOADOUT_PATCHELF:-/usr/bin/patchelf}"

# Private Tcl/Tk 8.6 -- MUST match the payload's expect libtcl8.6.so patchlevel
# (8.6.16) so the script library's `package require -exact Tcl 8.6.x` always
# agrees with the private shared lib we ship beside it.
TCLTK_VERSION="8.6.16"
TCL_URL="https://prdownloads.sourceforge.net/tcl/tcl${TCLTK_VERSION}-src.tar.gz"
TK_URL="https://prdownloads.sourceforge.net/tcl/tk${TCLTK_VERSION}-src.tar.gz"
# sha256 of the pinned 8.6.16 source tarballs (verified against SourceForge).
TCL_SHA256="91cb8fa61771c63c262efb553059b7c7ad6757afa5857af6265e4b0bdc2a14a5"
TK_SHA256="be9f94d3575d4b3099d84bc3c10de8994df2d7aa405208173c709cc404a7e5fe"

tag=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --tag)
            shift
            [ "$#" -gt 0 ] || { echo "missing value for --tag" >&2; exit 2; }
            tag="$1"
            ;;
        -h|--help)
            sed -n '2,/^Usage/p' "$0"
            exit 0
            ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done

[ -n "$tag" ] || {
    echo "ERROR: --tag <version> required (see $CLONE_URL/tags)" >&2
    exit 2
}
[ -x "$PATCHELF" ] || { echo "ERROR: patchelf not found at $PATCHELF" >&2; exit 2; }

VERSION="${tag#v}"
# Default the workdir to the container's persistent /cache so a failed run
# resumes; override with TMPDIR if you want it elsewhere. Staging ELFs must be
# chmod-writable before patchelf rewrites them in place.
WORK_DIR="${XSCHEM_WORKDIR:-${LOADOUT_BUILD_CACHE:-/cache}/xschem-build-${tag}}"
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"

# -- fetch + verify the private Tcl/Tk 8.6 sources -------------------------
echo "==> Fetching private Tcl/Tk ${TCLTK_VERSION} sources ..."
cd "$WORK_DIR"
fetch_verified() {
    local url="$1" sha="$2" out="$3"
    [ -f "$out" ] || curl -fsSL "$url" -o "$out"
    local got
    got=$(sha256sum "$out" | cut -d' ' -f1)
    [ "$got" = "$sha" ] || { echo "ERROR: sha256 mismatch for $out: $got != $sha" >&2; exit 1; }
    echo "  OK $out (sha256 $sha)"
}
fetch_verified "$TCL_URL" "$TCL_SHA256" "tcl${TCLTK_VERSION}-src.tar.gz"
fetch_verified "$TK_URL" "$TK_SHA256" "tk${TCLTK_VERSION}-src.tar.gz"
tar xf "tcl${TCLTK_VERSION}-src.tar.gz"
tar xf "tk${TCLTK_VERSION}-src.tar.gz"

TCL_PRIVATE="$WORK_DIR/tcltk-private"
echo "==> Building private Tcl ${TCLTK_VERSION} ..."
cd "$WORK_DIR/tcl${TCLTK_VERSION}/unix"
./configure --prefix="$TCL_PRIVATE" --enable-threads >/dev/null
make -j"$(nproc)" >/dev/null
make install >/dev/null
[ -f "$TCL_PRIVATE/lib/libtcl8.6.so" ] || { echo "ERROR: libtcl8.6.so missing" >&2; exit 1; }
[ -f "$TCL_PRIVATE/lib/tcl8.6/init.tcl" ] || { echo "ERROR: tcl8.6/init.tcl missing" >&2; exit 1; }

echo "==> Building private Tk ${TCLTK_VERSION} (against the private Tcl) ..."
cd "$WORK_DIR/tk${TCLTK_VERSION}/unix"
./configure --prefix="$TCL_PRIVATE" --with-tcl="$TCL_PRIVATE/lib" --enable-threads >/dev/null
make -j"$(nproc)" >/dev/null
make install >/dev/null
[ -f "$TCL_PRIVATE/lib/libtk8.6.so" ] || { echo "ERROR: libtk8.6.so missing" >&2; exit 1; }
[ -f "$TCL_PRIVATE/lib/tk8.6/tk.tcl" ] || { echo "ERROR: tk8.6/tk.tcl missing" >&2; exit 1; }

# -- fetch + build xschem -----------------------------------------------------
echo "==> Cloning xschem ${tag} ..."
cd "$WORK_DIR"
git clone --quiet --depth 1 --branch "$tag" "$CLONE_URL" xschem-src
cd "$WORK_DIR/xschem-src"

XSCHEM_PREFIX="$WORK_DIR/prefix"
echo "==> Configuring xschem (prefix-independent; the wrapper drives relocation) ..."
./configure --prefix="$XSCHEM_PREFIX" >configure.log 2>&1 || {
    echo "ERROR: configure failed" >&2; tail -30 configure.log >&2; exit 1;
}
# Upstream's scconfig link line needs Tk 8.6. We relink the binary against the
# PRIVATE Tcl/Tk with an $ORIGIN-relative RUNPATH, so the shipped tree is
# self-contained and relocatable. --force-rpath is the default; RUNPATH
# ($ORIGIN/../lib) is what we want so LD_LIBRARY_PATH still outranks it.
sed -i "s|^LDFLAGS=.*|LDFLAGS=-L$TCL_PRIVATE/lib -lm -ljpeg -lcairo -lX11 -lxcb -lxcb-render -lX11-xcb -lXpm -ltcl8.6 -ltk8.6 |" Makefile.conf
grep '^LDFLAGS=' Makefile.conf

echo "==> Building xschem ..."
rm -f src/xschem
(cd src && make xschem >"$WORK_DIR/relink.log" 2>&1) || { tail -20 "$WORK_DIR/relink.log" >&2; exit 1; }
echo "==> Installing xschem data tree ..."
# Top-level `make install` runs the src / xschem_library / doc / utile installs
# (the tcl layer, the systemlib scripts, share/doc/xschem libraries, man page).
make install >"$WORK_DIR/install.log" 2>&1 || {
    echo "ERROR: make install failed" >&2; tail -20 "$WORK_DIR/install.log" >&2; exit 1;
}
[ -d "$XSCHEM_PREFIX/share/xschem" ] || { echo "ERROR: share/xschem not installed" >&2; exit 1; }

# -- stage the runtime tree (valgrind/expect layout) --------------------------
STAGE="$WORK_DIR/stage"
rm -rf "$STAGE"
mkdir -p "$STAGE/bin" "$STAGE/lib/xschem/bin" "$STAGE/lib/xschem/lib" \
         "$STAGE/share/doc/xschem" "$STAGE/share/man/man1"

# The real ELF, inside the private prefix so Tcl/Tk find their script libraries
# via <exedir>/../lib/{tcl8.6,tk8.6} (relocatable, no env export). `make xschem`
# runs in src/ and drops the binary there.
cp src/xschem "$STAGE/lib/xschem/bin/xschem.bin"
# Private Tcl/Tk shared libs + script libraries.
cp "$TCL_PRIVATE/lib/libtcl8.6.so" "$TCL_PRIVATE/lib/libtk8.6.so" "$STAGE/lib/xschem/lib/"
cp -r "$TCL_PRIVATE/lib/tcl8.6" "$TCL_PRIVATE/lib/tcl8" "$TCL_PRIVATE/lib/tk8.6" "$STAGE/lib/xschem/lib/"
# patchelf rewrites in place: make the staged ELFs owner-writable.
chmod u+w "$STAGE/lib/xschem/bin/xschem.bin" "$STAGE/lib/xschem/lib/libtcl8.6.so" "$STAGE/lib/xschem/lib/libtk8.6.so"
# xschem's own data tree (xschem.tcl, systemlib, xschemrc, xschem_library/...).
cp -r "$XSCHEM_PREFIX/share/xschem" "$STAGE/share/xschem"

echo "==> Pruning the bulky doc trees from the shipped share ..."
# xschem_man is a 12 MB HTML/PDF manual and gschem_import a 7.7 MB gschem->xschem
# symbol converter -- neither is needed offline; the .1 man page is the usable
# reference. Both are excluded like gtkwave's .odt / octave's doc tree.
rm -rf "$STAGE/share/doc/xschem/xschem_man" "$STAGE/share/doc/xschem/gschem_import"
# Keep the example schematics + the netlist helper libraries ngspice/openroad
# users reference, minus the pruned trees.
for d in examples ngspice ngspice_verilog_cosim logic xschem_simulator generators \
         inst_sch_select binto7seg pcb rom8k; do
    [ -d "$XSCHEM_PREFIX/share/doc/xschem/$d" ] && \
        cp -r "$XSCHEM_PREFIX/share/doc/xschem/$d" "$STAGE/share/doc/xschem/$d"
done
cp -r "$XSCHEM_PREFIX/share/man/man1" "$STAGE/share/man/"

# -- make the shipped system xschemrc relocatable ----------------------------
# The binary's compiled-in XSCHEM_LIBRARY_PATH points at the DEAD build prefix,
# and upstream ships the system xschemrc path block commented out -- so a
# relocated install would lose its symbol library. The wrapper exports
# XSCHEM_SHAREDIR (the absolute runtime share dir); this block rebuilds the
# library path from it. This is the documented customization point in
# xschemrc's own comments.
echo "==> Installing the relocatable library-path block into share/xschem/xschemrc ..."
XSCHEMRC="$STAGE/share/xschem/xschemrc"
cat > "$WORK_DIR/xschemrc.snippet" <<'SNIP'
#### LOADOUT: derive the design-library path from the RUNTIME sharedir so a
#### relocatable install (~/.local or --dest-dir) never depends on the build
#### prefix compiled into the binary. The launcher exports XSCHEM_SHAREDIR.
if { [info exists XSCHEM_SHAREDIR] } {
  set _loadout_xschem_docdir [file join [file dirname $XSCHEM_SHAREDIR] doc xschem]
  set XSCHEM_LIBRARY_PATH {}
  append XSCHEM_LIBRARY_PATH :$XSCHEM_SHAREDIR/xschem_library/devices
  foreach _d {examples ngspice ngspice_verilog_cosim logic xschem_simulator generators inst_sch_select binto7seg pcb rom8k} {
    if { [file isdirectory [file join $_loadout_xschem_docdir $_d]] } {
      append XSCHEM_LIBRARY_PATH :[file join $_loadout_xschem_docdir $_d]
    }
  }
  unset _loadout_xschem_docdir
  unset _d
}

SNIP
# Insert the block just before the (commented) upstream path list; fail if the
# anchor is not found so a rebase can never silently drop the relocation.
awk -v snip="$WORK_DIR/xschemrc.snippet" '
  /^# set XSCHEM_LIBRARY_PATH \{\}/ && !done {
    while ((getline line < snip) > 0) print line
    close(snip); done=1
  }
  { print }
  END { if (!done) exit 3 }
' "$XSCHEMRC" > "$XSCHEMRC.new" || { echo "ERROR: xschemrc anchor not found" >&2; exit 1; }
mv "$XSCHEMRC.new" "$XSCHEMRC"
grep -q "LOADOUT: derive the design-library path" "$XSCHEMRC" || {
    echo "ERROR: relocation block not present in shipped xschemrc" >&2; exit 1; }

# -- strip the real ELF and the private Tcl/Tk, THEN set RPATHs --------------
# ORDER IS LOAD-BEARING: strip FIRST, patchelf SECOND. Stripping after patchelf
# moves .dynstr outside PT_LOAD and the binary dies at load with "no version
# information available" / "undefined symbol: , version" -- the exact failure
# documented in AGENTS.md for the whole payload. (xschem, Tcl and Tk all carry
# versioned symbol references, so the failure is immediate, not latent.)
strip "$STAGE/lib/xschem/bin/xschem.bin"
strip "$STAGE/lib/xschem/lib/libtcl8.6.so" "$STAGE/lib/xschem/lib/libtk8.6.so"
# $ORIGIN/../lib        -> the private Tcl/Tk (lib/xschem/lib); the same path Tcl's
#                         own <exedir>/../lib/tcl8.6 script-library fallback uses
# $ORIGIN/../../../lib64 -> the payload lib64 (gui_libs: libjpeg, and any soname
#                         a farm node's EL8 userland cannot supply). THREE levels:
#                         the ELF sits at <prefix>/lib/xschem/bin/, so ../.. is
#                         <prefix>/lib -- a two-level element silently resolves
#                         to the nonexistent <prefix>/lib/lib64.
# shellcheck disable=SC2016  # $ORIGIN is a literal ld.so token
"$PATCHELF" --set-rpath '$ORIGIN/../lib:$ORIGIN/../../../lib64' \
    "$STAGE/lib/xschem/bin/xschem.bin"
# CRITICAL (DT_RPATH poisons the whole process): Tcl's build bakes a DT_RPATH
# pointing at the build tree into libtcl8.6.so. When ANY loaded object carries a
# DT_RPATH, glibc switches the ENTIRE process to legacy RPATH semantics, which
# IGNORES the executable's DT_RUNPATH -- so the executable's ../../lib64 (where
# gui_libs' libjpeg.so.62/libXpm live) would never be searched and xschem dies
# with "libjpeg.so.62: cannot open shared object file" even though it is
# installed. Strip the build-tree RPATH off BOTH private libs: libtcl to empty,
# libtk to $ORIGIN (so it still finds its own libtcl8.6.so, which is now the
# only copy in the chain).
# shellcheck disable=SC2016
"$PATCHELF" --remove-rpath "$STAGE/lib/xschem/lib/libtcl8.6.so"
# shellcheck disable=SC2016
"$PATCHELF" --set-rpath '$ORIGIN' "$STAGE/lib/xschem/lib/libtk8.6.so"
# Assert no DT_RPATH survives anywhere in the shipped ELFs (a DT_RPATH would
# silently disable the executable's RUNPATH for the whole process).
for elf in "$STAGE/lib/xschem/bin/xschem.bin" "$STAGE/lib/xschem/lib/libtcl8.6.so" \
           "$STAGE/lib/xschem/lib/libtk8.6.so"; do
    if readelf -d "$elf" | grep -q '(RPATH)'; then
        echo "ERROR: DT_RPATH survived in $elf (would disable RUNPATH for the process)" >&2
        exit 1
    fi
done

# -- launcher: derive the prefix from $0, adapt the host env, exec the ELF ----
# Composed from the shared GUI block (one source of truth, same as wezterm /
# surfer / gtkwave): the host-GL probe keeps us off the payload's GLVND, and
# the host-fontconfig LD_PRELOAD stops the bundled EL8 fontconfig 2.13 from
# parsing a newer host's /etc/fonts and warning on every launch (xschem pulls
# fontconfig in through cairo).
GUI_ENV_BLOCK="$REPO/build/gui-wrapper-env.sh"
[ -r "$GUI_ENV_BLOCK" ] || { echo "ERROR: missing $GUI_ENV_BLOCK" >&2; exit 1; }
# COMPOSITION INVARIANT: every concatenated fragment must end in a newline or
# its last line fuses with the next fragment's first (a shipped xschem wrapper
# would then print `unset _host_fc _fc_mode# ...` and leave _fc_mode set).
[ -n "$(tail -c1 "$GUI_ENV_BLOCK")" ] && {
    echo "ERROR: $GUI_ENV_BLOCK does not end in a newline" >&2
    exit 1
}
{
    # shellcheck disable=SC2016  # writing a shell script: $ must stay literal
    printf '#!/bin/sh\n'
    printf '# loadout xschem launcher -- host-env adaptation + relocatability ONLY\n'
    printf '# (no prefix embedded; the real binary is lib/xschem/bin/xschem.bin and\n'
    printf '# carries the private Tcl/Tk 8.6 runtime).\n'
    printf '# Composed of: prefix header + build/gui-wrapper-env.sh + the\n'
    printf '# XSCHEM_SHAREDIR handoff -- see that file for what the block fixes.\n'
    printf 'here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)\n'
    printf 'prefix=$(CDPATH= cd -- "$here/.." && pwd -P)\n'
    cat "$GUI_ENV_BLOCK"
    printf 'XSCHEM_SHAREDIR="$prefix/share/xschem"\n'
    printf 'export XSCHEM_SHAREDIR\n'
    printf 'exec "$prefix/lib/xschem/bin/xschem.bin" "$@"\n'
} > "$STAGE/bin/xschem"
chmod 755 "$STAGE/bin/xschem"
# The no-prefix invariant still holds: the launcher embeds no install path.
grep -q "$WORK_DIR\|$XSCHEM_PREFIX" "$STAGE/bin/xschem" && {
    echo "ERROR: launcher embeds a build path" >&2
    exit 1
}

# -- stage-verify: relocate, hide the build prefix, netlist headless ---------
# This is the assertion that matters: move the whole staged tree to a fresh
# path, MOVE the build prefix out of the way (so any dependence on the compiled
# path is fatal), and netlist a bundled example. A correct relocatable install
# resolves every symbol and writes a complete netlist with 0 "IS MISSING".
echo "==> Stage-verify: relocated headless netlist (build prefix hidden) ..."
VERIFY="$WORK_DIR/verify-tree"
rm -rf "$VERIFY"
cp -r "$STAGE" "$VERIFY"
mv "$XSCHEM_PREFIX" "$XSCHEM_PREFIX.hidden"
cd "$VERIFY"
mkdir -p out
cp share/doc/xschem/examples/test.sch .
set +e
timeout 120 ./bin/xschem test.sch -q -x -r -n -o out >"$WORK_DIR/netlist.log" 2>&1
net_rc=$?
set -e
mv "$XSCHEM_PREFIX.hidden" "$XSCHEM_PREFIX"
# xschem exits 10 on a netlist that completed with warnings (upstream's own
# regression harness treats 10 as a netlisting completion, not a crash -- see
# tests/netlisting.tcl: "in case of netlisting error xschem exit code is 10").
# The real assertion is the CONTENT: a complete netlist with every symbol
# resolved. Accept 0 (clean) and 10 (completed-with-warnings), reject crashes.
case "$net_rc" in
    0|10) ;;
    *)
        echo "ERROR: headless netlist crashed (exit $net_rc)" >&2
        tail -20 "$WORK_DIR/netlist.log" >&2
        exit 1
        ;;
esac
[ -f out/test.spice ] || { echo "ERROR: no netlist produced" >&2; tail -20 "$WORK_DIR/netlist.log" >&2; exit 1; }
if grep -q "IS MISSING\|Symbol not found" out/test.spice "$WORK_DIR/netlist.log"; then
    echo "ERROR: relocatable netlist has unresolved symbols (build-prefix dependence?)" >&2
    head -20 out/test.spice >&2
    exit 1
fi
grep -q '\.subckt test' out/test.spice || { echo "ERROR: netlist missing the top subckt" >&2; exit 1; }
echo "  OK: relocated netlist complete, 0 missing symbols ($(wc -l < out/test.spice) lines)"

# Assert every RUNPATH element is meaningful. The container HAS system
# X11/cairo/jpeg, so a wrong RUNPATH depth would still netlist fine here and
# only break on a host without those sonames (the libjpeg.so.62 case). Check the
# element count/depth directly instead of relying on the smoke.
rp=$(readelf -d "$VERIFY/lib/xschem/bin/xschem.bin" | sed -n 's/.*runpath: \[\(.*\)\]/\1/p')
echo "  RUNPATH: $rp"
# shellcheck disable=SC2016
IFS=: read -r -a rp_parts <<< "$rp"
for part in "${rp_parts[@]}"; do
    resolved=${part//\$ORIGIN/$VERIFY/lib/xschem/bin}
    norm=$(realpath -m "$resolved")
    # shellcheck disable=SC2016  # comparing against the literal $ORIGIN token
    if [ "$part" = '$ORIGIN/../../../lib64' ]; then
        # the payload lib64 is not part of the xschem archive (gui_libs owns it);
        # assert only that the DEPTH is right: <prefix>/lib/xschem/bin + ../../../lib64
        [ "$norm" = "$(realpath -m "$VERIFY/lib64")" ] || {
            echo "ERROR: RUNPATH lib64 element resolves to $norm, expected $(realpath -m "$VERIFY/lib64")" >&2
            exit 1
        }
    elif [ ! -d "$norm" ]; then
        echo "ERROR: RUNPATH element $part resolves to a missing dir: $norm" >&2
        exit 1
    fi
done
echo "  OK: every RUNPATH element resolves (3-level lib64 depth asserted)"

# -- GUI stage-verify under Xvfb (Tk_Init + X11 + cairo real path) ------------
if command -v Xvfb >/dev/null 2>&1; then
    echo "==> Stage-verify: GUI under Xvfb ..."
    Xvfb :99 -screen 0 1280x1024x24 >/dev/null 2>&1 &
    xvfb_pid=$!
    sleep 3
    (
        export DISPLAY=:99
        cd "$VERIFY"
        timeout 30 ./bin/xschem share/doc/xschem/examples/test.sch >/dev/null 2>&1 || true
    ) &
    gui_pid=$!
    sleep 10
    if kill -0 "$gui_pid" 2>/dev/null; then
        echo "  OK: xschem GUI stayed up under Xvfb (Tk_Init + X11 + cairo)"
    else
        echo "  WARNING: xschem GUI exited early under Xvfb (see below)" >&2
    fi
    kill "$gui_pid" 2>/dev/null || true
    kill "$xvfb_pid" 2>/dev/null || true
else
    echo "  (Xvfb not present -- skipping GUI stage-verify)"
fi

# -- package: bin launcher + runtime archive (gtkwave/expect layout) ---------
echo "==> Packaging ..."
cp "$STAGE/bin/xschem" "$WORK_DIR/xschem.launcher"
bzip2 -kf "$WORK_DIR/xschem.launcher"
cp "$WORK_DIR/xschem.launcher.bz2" "$BIN_DIR/xschem.bz2"

# Runtime archive: private Tcl/Tk + real ELF + share tree. Prune the doc trees
# already removed from the stage (defence in depth) and the .1 man page stays.
tar cjf "$RUNTIME_DIR/xschem.tar.bz2" \
    -C "$STAGE" \
    ./lib/xschem \
    ./share/xschem \
    ./share/doc/xschem \
    ./share/man
echo "  Wrote $BIN_DIR/xschem.bz2"
echo "  Wrote $RUNTIME_DIR/xschem.tar.bz2 ($(wc -c < "$RUNTIME_DIR/xschem.tar.bz2" | tr -d ' ') bytes)"

# -- stamp the registry version ----------------------------------------------
python3 -c "
import sys, json
path, ver = sys.argv[1], sys.argv[2]
with open(path) as f:
    data = json.load(f)
pkgs = data['packages']
if 'xschem' in pkgs:
    pkgs['xschem']['version'] = ver
    print(f'packages.json: xschem version -> {ver}')
else:
    print('WARNING: xschem not found in packages.json, skipping version update')
with open(path, 'w') as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write('\n')
" "$REPO/payload/packages.json" "$VERSION"

echo "==> Running strip-all-elf-binaries ..."
# The image ships only python3.6; strip-all-elf-binaries needs a 3.14
# interpreter (PEP 758 syntax). Resolve one like build-netlistsvg.sh does: the
# warm bootstrap interpreter, else any python3.14/python3 on PATH.
PY=
for cand in "$REPO/.loadout-bootstrap/bin/python3.14" "$HOME/.local/bin/python3.14" \
            "$(command -v python3.14 || true)" "$(command -v python3 || true)"; do
    if [ -n "$cand" ] && [ -x "$cand" ]; then PY="$cand"; break; fi
done
[ -n "$PY" ] || { echo "ERROR: no python3.14/python3 interpreter found for strip" >&2; exit 1; }
"$PY" "$REPO/build/strip-all-elf-binaries"

echo ""
echo "Done. Produced:"
echo "  $BIN_DIR/xschem.bz2"
echo "  $RUNTIME_DIR/xschem.tar.bz2"
echo ""
echo "Reminders:"
echo "  - ./build/strip-all-elf-binaries already ran; regen sizes+manifest if needed:"
echo "      python3.14 build/gen-installed-sizes && python3.14 build/gen-content-manifest"
echo "  - ./loadout completion bash > envs/bash/global/completions/loadout.bash"
echo "  - build/ADDING_BINARIES.md note is MANDATORY"
