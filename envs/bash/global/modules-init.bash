# Environment Modules native shell selector.
#
# The package ships upstream's full installation at
# <local>/lib/modules. Source its standard init/bash file rather than owning a
# wrapper-shaped module function here. Shared deployments use the same local
# root through LOADOUT_CFG_SHARED_PREFIX.

_loadout_modules_prefix="${LOADOUT_CFG_SHARED_PREFIX:-"$HOME/.local"}/lib/modules"
_loadout_modules_init="$_loadout_modules_prefix/init/bash"

if [[ -r "$_loadout_modules_init" ]]; then
    # Aliases expand while a sourced file is parsed. Clear names upstream init
    # may turn into functions before sourcing it (AGENTS.md rule).
    unalias module _module_raw ml 2>/dev/null || true

    # Select this native install rather than a host Modules initialization that
    # might already have set identity variables. Preserve MODULEPATH: upstream
    # init intentionally respects a caller/site-selected modulefile search path.
    unset MODULESHOME MODULES_CMD
    source "$_loadout_modules_init"
fi

unset _loadout_modules_prefix _loadout_modules_init
