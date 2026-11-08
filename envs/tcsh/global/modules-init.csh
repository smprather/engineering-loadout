# Environment Modules native shell selector, csh form.
#
# TRACKS envs/bash/global/modules-init.bash.
#
# The `modules` package ships upstream's full installation at <local>/lib/modules,
# including init/tcsh and init/csh. Source the native init rather than owning a
# wrapper-shaped `module` alias here. Shared deployments resolve through
# LOADOUT_CFG_SHARED_PREFIX exactly as in bash.
#
# tcsh gets init/tcsh (it defines `module` with tcsh's `alias` and adds the
# tcsh_completion hooks); a plain csh would get init/csh. $?tcsh distinguishes
# them -- tcsh sets it, csh does not.

set _lo_mod_prefix = "$HOME/.local"
if ( $?LOADOUT_CFG_SHARED_PREFIX ) then
    if ( "$LOADOUT_CFG_SHARED_PREFIX" != "" ) set _lo_mod_prefix = "$LOADOUT_CFG_SHARED_PREFIX"
endif
set _lo_mod_prefix = "${_lo_mod_prefix}/lib/modules"

if ( $?tcsh ) then
    set _lo_mod_init = "${_lo_mod_prefix}/init/tcsh"
else
    set _lo_mod_init = "${_lo_mod_prefix}/init/csh"
endif

if ( -r "$_lo_mod_init" ) then
    # An inherited Environment Modules state can be INCONSISTENT: a loaded
    # modulefile deleted on disk, or LOADEDMODULES and _LMFILES_ not 1:1 (e.g.
    # LOADEDMODULES=foo with an EMPTY _LMFILES_, seen after a partial env
    # inheritance). Re-sourcing init over that leaves EM to fail the next
    # `module load` with "Loaded environment state is inconsistent". Detect it
    # and clear the stale state; a HEALTHY inherited state is left alone -- no
    # purge, so this is a no-op for the common case.
    #
    # ORDER IS LOAD-BEARING: the detection and the purge come BEFORE the
    # unaliases below. `module` exists only as an ALIAS in tcsh, so unaliasing
    # first destroys the only thing that can undo the old modules' PATH /
    # LD_LIBRARY_PATH mutations -- which is exactly how the flush used to leave
    # stale foreign PATH entries behind (issue #18).
    set _lo_em_broken = 0
    set _lo_lm = 0
    set _lo_lf = 0
    if ( $?LOADEDMODULES ) then
        foreach _lo_e ( `printf '%s' "$LOADEDMODULES" | tr ':' ' '` )
            @ _lo_lm++
        end
    endif
    if ( $?_LMFILES_ ) then
        foreach _lo_e ( `printf '%s' "$_LMFILES_" | tr ':' ' '` )
            @ _lo_lf++
            # A loaded modulefile that no longer exists on disk.
            if ( ! -e "$_lo_e" ) set _lo_em_broken = 1
        end
    endif
    if ( $_lo_lm != $_lo_lf ) set _lo_em_broken = 1

    if ( $_lo_em_broken == 1 ) then
        # Ask the CURRENTLY loaded EM to undo its own environment mutations
        # before the state variables are cleared (bash's modules-init.bash does
        # the same with `module purge` / `module reset -f`).
        #
        # NEVER write `module purge >& /dev/null` here: `module` is an alias
        # built on `!*`, so a trailing redirect is substituted INSIDE the
        # backticks (`modulecmd.tcl csh purge >& /dev/null`) and the eval runs
        # an empty string -- a silent no-op. `--silent` is EM's own switch
        # (4.2+) and is the only correct way to quiet it.
        #
        # MODULEPATH must SURVIVE the flush. It matches a naive ^MODULE sweep but
        # it is the caller/site-selected modulefile search path -- clearing it
        # turns "inconsistent state" into "module avail is empty and nothing can
        # be loaded", a worse and SILENT failure (upstream init substitutes its
        # own default), at exactly the moment the user is already in a bad state.
        # `reset -f` restores MODULEPATH to its INITIAL value, so save/restore
        # around it; hence the explicit unsetenv list rather than a prefix sweep.
        where module >& /dev/null
        if ( ! $status ) then
            set _lo_saved_mp = ""
            if ( $?MODULEPATH ) set _lo_saved_mp = "$MODULEPATH"
            module --silent purge
            module --silent reset -f
            if ( "$_lo_saved_mp" != "" ) setenv MODULEPATH "$_lo_saved_mp"
            unset _lo_saved_mp
        endif
        unsetenv LOADEDMODULES
        unsetenv _LMFILES_
        unsetenv MODULES_LMALTNAME
        unsetenv MODULES_LMCONFLICT
        unsetenv MODULES_LMPREREQ
        unsetenv MODULES_LMNOTUASKED
    endif
    unset _lo_em_broken _lo_lm _lo_lf _lo_e

    # Aliases expand while a sourced file is PARSED, so a pre-existing `module`
    # alias would corrupt upstream init's own definition of it. Clear the three
    # names AFTER the flush (AGENTS.md rule; the bash file does the same with
    # unalias).
    unalias module
    unalias _module_raw
    unalias ml

    # Select this native install rather than a host Modules initialization that
    # may already have set the identity variables. MODULEPATH is preserved on
    # purpose -- upstream init respects a caller/site-selected search path.
    unsetenv MODULESHOME
    unsetenv MODULES_CMD
    source "$_lo_mod_init"
endif

unset _lo_mod_prefix
unset _lo_mod_init
