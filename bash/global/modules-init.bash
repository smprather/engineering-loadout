# Environment Modules shell integration (loadout-local install)
#
# Sourced from bash/global/bashrc when ~/.local/lib/modulecmd.tcl is present.
# Uses $HOME-relative paths — portable across usernames.
#
# module() and ml() are defined via `modulecmd.tcl bash autoinit`, which also
# sets MODULESHOME, MODULEPATH, and all other modules env vars.  The autoinit
# output is eval'd here so downstream shells inherit the correct environment.
#
# Prefers the loadout-bundled tclsh (~/.local/bin/tclsh) when available;
# falls back to /usr/bin/tclsh so modules works on machines with system Tcl only.

_mc="$HOME/.local/lib/modulecmd.tcl"
_tclsh="$HOME/.local/bin/tclsh"
[ -x "$_tclsh" ] || _tclsh="/usr/bin/tclsh"
if [ -f "$_mc" ] && [ -x "$_tclsh" ]; then
    eval "$("$_tclsh" "$_mc" bash autoinit 2>/dev/null)"
fi
unset _mc _tclsh
