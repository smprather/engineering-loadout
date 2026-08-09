# Environment Modules native shell selector, zsh form.
#
# TRACKS envs/bash/global/modules-init.bash.
#
# The `modules` package ships upstream's full installation at <local>/lib/modules,
# including init/zsh. Source the native init rather than owning a wrapper-shaped
# `module` function here. Shared deployments resolve through
# LOADOUT_CFG_SHARED_PREFIX exactly as in bash.

_loadout_modules_prefix="${LOADOUT_CFG_SHARED_PREFIX:-$HOME/.local}/lib/modules"
_loadout_modules_init="$_loadout_modules_prefix/init/zsh"

if [[ -r "$_loadout_modules_init" ]]; then
    # Aliases expand while a sourced file is parsed. Clear names upstream init
    # may turn into functions before sourcing it (AGENTS.md rule).
    unalias module _module_raw ml 2>/dev/null

    # An inherited Environment Modules state can be INCONSISTENT -- a loaded
    # modulefile deleted on disk, or LOADEDMODULES and _LMFILES_ not 1:1 (e.g.
    # LOADEDMODULES=foo with an EMPTY _LMFILES_, after a partial env
    # inheritance). Re-sourcing init over that leaves EM to fail the next
    # `module load` with "Loaded environment state is inconsistent". Detect it
    # and clear the stale state; a HEALTHY inherited state is left alone -- no
    # purge, so this is a no-op for the common case.
    #
    # Fork-free, same reasoning as the bash version: this runs in every
    # interactive shell that opts in and the common case is "do nothing", so it
    # uses zsh parameter splitting rather than tr|grep pipelines.
    _lo_em_broken=0
    _lo_lm=(${(s.:.)${LOADEDMODULES:-}})
    _lo_lf=(${(s.:.)${_LMFILES_:-}})
    for _lo_e in "${_lo_lf[@]}"; do
        [[ -z $_lo_e ]] && continue
        # A loaded modulefile that no longer exists on disk.
        [[ -e $_lo_e ]] || _lo_em_broken=1
    done
    # LOADEDMODULES and _LMFILES_ must stay 1:1.
    (( ${#_lo_lm[@]} != ${#_lo_lf[@]} )) && _lo_em_broken=1

    if (( _lo_em_broken )); then
        if typeset -f module >/dev/null 2>&1; then
            module purge    >/dev/null 2>&1
            module reset -f >/dev/null 2>&1
        fi
        unset -f module _module_raw ml 2>/dev/null
        # MODULEPATH must SURVIVE the flush. It matches a naive ^MODULE sweep,
        # but it is the caller/site-selected modulefile search path -- clearing
        # it turns "inconsistent state" into "module avail is empty and nothing
        # can be loaded", a worse and SILENT failure (upstream init substitutes
        # its own default), at exactly the moment the user is already in a bad
        # state. Hence the explicit list rather than a prefix sweep.
        unset LOADEDMODULES _LMFILES_ \
              MODULES_LMALTNAME MODULES_LMCONFLICT MODULES_LMPREREQ MODULES_LMNOTUASKED
    fi
    unset _lo_em_broken _lo_lm _lo_lf _lo_e

    # Select this native install rather than a host Modules initialization that
    # might already have set identity variables. Preserve MODULEPATH: upstream
    # init intentionally respects a caller/site-selected search path.
    unset MODULESHOME MODULES_CMD
    source "$_loadout_modules_init"
fi

unset _loadout_modules_prefix _loadout_modules_init
