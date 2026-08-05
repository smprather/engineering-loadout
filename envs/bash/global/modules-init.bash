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
    # Fork-free on purpose: this runs in every interactive shell that opts in,
    # and the common case is "state is fine, do nothing". The earlier form spent
    # two tr|grep pipelines plus printenv|grep|cut per shell; bash array
    # splitting and ${!prefix@} do the same work with no subprocesses at all
    # (same reasoning as loadout_restore_echo replacing its stty snapshot).
    _lo_em_broken=0
    _lo_lm=0
    _lo_lf=0
    IFS=: read -ra _lo_arr <<< "${LOADEDMODULES:-}" || true
    for _lo_e in "${_lo_arr[@]}"; do
        [[ -n $_lo_e ]] && _lo_lm=$((_lo_lm + 1))
    done
    IFS=: read -ra _lo_arr <<< "${_LMFILES_:-}" || true
    for _lo_e in "${_lo_arr[@]}"; do
        [[ -z $_lo_e ]] && continue
        _lo_lf=$((_lo_lf + 1))
        # A loaded modulefile that no longer exists on disk.
        [[ -e $_lo_e ]] || _lo_em_broken=1
    done
    # LOADEDMODULES and _LMFILES_ must stay 1:1.
    ((_lo_lm != _lo_lf)) && _lo_em_broken=1
    if ((_lo_em_broken)); then
        if type module >/dev/null 2>&1; then
            module purge   >/dev/null 2>&1
            module reset -f >/dev/null 2>&1
        fi
        unset -f module _module_raw ml 2>/dev/null || true
        # MODULEPATH must SURVIVE the flush. It matches a naive ^MODULE sweep,
        # but it is the caller/site-selected modulefile search path -- clearing
        # it turns "inconsistent state" into "module avail is empty and nothing
        # can be loaded", a worse failure, at exactly the moment the user is
        # already in a bad state. Same invariant as the narrow
        # `unset MODULESHOME MODULES_CMD` below.
        for _lo_mv in ${!MODULE@} ${!__MODULE@} ${!LOADEDMODULES@} ${!_LMFILES_@}; do
            [[ $_lo_mv == MODULEPATH ]] && continue
            unset "$_lo_mv"
        done
    fi
    unset _lo_em_broken _lo_arr _lo_e _lo_lm _lo_lf _lo_mv

    # Select this native install rather than a host Modules initialization that
    # might already have set identity variables. Preserve MODULEPATH: upstream
    # init intentionally respects a caller/site-selected modulefile search path.
    unset MODULESHOME MODULES_CMD
    source "$_loadout_modules_init"
fi

unset _loadout_modules_prefix _loadout_modules_init
