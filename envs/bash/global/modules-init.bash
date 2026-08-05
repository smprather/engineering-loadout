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

    # Robustness: an inherited Environment Modules state can be INCONSISTENT --
    # a loaded modulefile deleted on disk, or LOADEDMODULES and _LMFILES_ not
    # 1:1 (e.g. LOADEDMODULES=foo with an EMPTY _LMFILES_, seen after a partial
    # env inheritance). Re-sourcing init over such a state leaves EM to error
    # "Loaded environment state is inconsistent" on the next `module load`.
    # Detect it and clear the stale state first. A HEALTHY inherited state is
    # left untouched (no purge) -- this is a no-op for the common case, so it is
    # safe for non-Modules-heavy users.
    _lo_em_broken=0
    for _lo_lmf in $(printf '%s' "${_LMFILES_:-}" | tr ':' '\n'); do
        [[ -n $_lo_lmf && ! -e $_lo_lmf ]] && { _lo_em_broken=1; break; }
    done
    _lo_lm=$(printf '%s' "${LOADEDMODULES:-}" | tr ':' '\n' | grep -c . || true)
    _lo_lf=$(printf '%s' "${_LMFILES_:-}"    | tr ':' '\n' | grep -c . || true)
    [[ $_lo_lm != $_lo_lf ]] && _lo_em_broken=1
    if [[ $_lo_em_broken == 1 ]]; then
        if type module >/dev/null 2>&1; then
            module purge   >/dev/null 2>&1
            module reset -f >/dev/null 2>&1
        fi
        unset -f module _module_raw ml 2>/dev/null || true
        for _lo_mv in $(printenv | grep -E '^MODULE|^__MODULE|^LOADEDMODULES|^_LMFILES_' | cut -f1 -d=); do
            unset "$_lo_mv"
        done
    fi
    unset _lo_em_broken _lo_lmf _lo_lm _lo_lf _lo_mv

    # Select this native install rather than a host Modules initialization that
    # might already have set identity variables. Preserve MODULEPATH: upstream
    # init intentionally respects a caller/site-selected modulefile search path.
    unset MODULESHOME MODULES_CMD
    source "$_loadout_modules_init"
fi

unset _loadout_modules_prefix _loadout_modules_init
