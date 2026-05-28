# Environment Modules shell integration (loadout-local install)
#
# Sourced from bash/global/bashrc when ~/.local/lib/modulecmd.tcl is present.
# Uses $HOME-relative paths — portable across usernames.
#
# module() and ml() are defined via `modulecmd.tcl bash autoinit`, which also
# sets MODULESHOME, MODULEPATH, and all other modules env vars.  The autoinit
# output is eval'd here so downstream shells inherit the correct environment.

_mc="$HOME/.local/lib/modulecmd.tcl"
if [ -f "$_mc" ]; then
    eval "$(/usr/bin/tclsh "$_mc" bash autoinit 2>/dev/null)"
fi
unset _mc
