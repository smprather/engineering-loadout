#!/usr/bin/env bash
# shell-state-export.sh
#
# Source this in ~/.bashrc to get the `shell_state_export` function:
#     source ~/.config/tmux/shell-state-export.sh
#
# WHY: capturing a shell's functions, aliases, and non-exported vars is
# impossible from outside the process (/proc exposes only exported env + cwd).
# So this runs INSIDE the shell you want to clone and writes a snapshot rcfile.
# Starting a clone from it is far faster than sourcing ~/.bashrc and reflects
# the LIVE runtime state -- interactively-defined aliases/functions/exports
# included, not just what the static rc would rebuild.
#
# USAGE:
#     shell_state_export [outfile]      # prints the path it wrote
#     bash --rcfile "$(shell_state_export)"   # spawn a clone of this shell
#
# The pop-out helper normally calls this through a hidden tmux send-keys command
# when the source pane is bash. If that snapshot fails, pop-out falls back to
# env+cwd cloning with `bash --norc`.

shell_state_export() {
    local out
    if [[ $# -gt 0 ]]; then
        out="$1"
    else
        local snap_dir
        snap_dir=$(mktemp -d "${TMPDIR:-/tmp}/shell-snap.XXXXXX")
        out="$snap_dir/snapshot.rc"
    fi
    # Remember the real expand_aliases setting; restored at the very end.
    local _ea; _ea=$(shopt -p expand_aliases 2>/dev/null || echo 'shopt -s expand_aliases')

    {
        printf '# shell snapshot: pid %s  %s\n' "$$" "$(date -Is 2>/dev/null)"
        printf 'if [[ $- != *i* ]]; then return 2>/dev/null; fi  # interactive clones only\n'
        # Disable history expansion while sourcing: dumped function/alias bodies
        # can contain `!'\''` (e.g. starship's ${PS1//[!...]}) which an interactive
        # shell would otherwise mangle into "event not found" + broken quoting.
        printf 'set +H 2>/dev/null || true\n'
        # Disable alias expansion while sourcing. In an interactive shell it is ON,
        # so once the aliases below are defined, a matching word in a later function
        # body would be alias-expanded mid-parse and corrupt the quoting. We turn it
        # off for the whole file and restore the real value at the end.
        printf 'shopt -u expand_aliases\n\n'

        # --- working directory ------------------------------------------------
        printf 'cd %q 2>/dev/null || true\n\n' "$PWD"

        # --- set -o / shopt options ------------------------------------------
        # `set +o` prints reusable `set +o NAME` / `set -o NAME` lines. Drop
        # expand_aliases from the shopt dump -- we manage it explicitly above.
        printf '# set options\n'
        set +o
        printf '\n# shopt options\n'
        shopt -p | grep -v 'expand_aliases'

        # --- exported environment --------------------------------------------
        # `export -p` emits `declare -x NAME="VAL"`. Drop the vars tmux/bash
        # own on startup, so sourcing this AFTER the clone starts inside tmux
        # does not clobber the real TMUX / TMUX_PANE / SHLVL / PWD / _.
        printf '\n# exported environment\n'
        export -p | grep -vE '^declare -x (TMUX|TMUX_PANE|SHLVL|PWD|OLDPWD|_)=' || true

        # --- prompt-related shell vars (not exported, but define the "feel") --
        printf '\n# prompt\n'
        declare -p PS1 PS2 PS4 PROMPT_COMMAND PROMPT_DIRTRIM 2>/dev/null || true

        # --- traps -----------------------------------------------------------
        # NOTE: bash cannot show a DEBUG/RETURN/ERR trap via `trap -p` from
        # inside a normally-called function -- functrace must have been ON when
        # this function was *entered*, and once masked it stays masked for all
        # nested calls. So `trap -p` here reliably captures only EXIT and signal
        # traps. Starship's preexec hook (a DEBUG trap) is instead reproduced by
        # re-running its init below, which is exact and cheap. To also catch a
        # DEBUG trap generically, call: `set -T; shell_state_export ...; set +T`.
        printf '\n# traps\n'
        trap -p 2>/dev/null || true

        # --- bash-preexec hook arrays ----------------------------------------
        # When bash-preexec is in play (starship-via-preexec, direnv, atuin),
        # the hooks register in these arrays instead of clobbering PROMPT_COMMAND.
        printf '\n# preexec/precmd hook arrays\n'
        # shellcheck disable=SC2154
        declare -p precmd_functions preexec_functions 2>/dev/null || true

        # --- aliases ----------------------------------------------------------
        printf '\n# aliases\n'
        alias -p 2>/dev/null || true

        # --- functions --------------------------------------------------------
        # Includes this exporter itself; harmless. Non-exported shell variables
        # beyond the prompt set are deliberately skipped -- `declare -p` of the
        # full set drags in read-only/special vars (BASHOPTS, UID, FUNCNAME, ...)
        # that error or misbehave on source, for little interactive value.
        printf '\n# functions\n'
        # Dump every function EXCEPT starship's -- its declare -f form contains a
        # `${PS1//[!$'\''\n'\'']}` (literal newline inside a pattern) that bash
        # will not reliably re-source in an interactive shell. Starship's own
        # re-init below redefines them cleanly, so excluding them loses nothing.
        local -a _fns
        mapfile -t _fns < <(declare -F | awk '{print $NF}' | grep -Ev '^(starship_|__starship)' || true)
        ((${#_fns[@]})) && declare -f "${_fns[@]}"

        # --- prompt framework re-init ----------------------------------------
        # The one piece that can't be introspected from a function is the DEBUG
        # trap driving Starship's preexec (timing / transient prompt). Starship
        # is stateless (re-reads its config each prompt), so re-running its init
        # in the clone reproduces PROMPT_COMMAND + the DEBUG trap + functions
        # exactly, in ~10ms, and regenerates STARSHIP_SESSION_KEY so sibling
        # panes don't share one. This runs last, overriding the dumps above.
        if [[ $(type -t starship_precmd) == function ]]; then
            printf '\n# starship (re-init: restores the DEBUG-trap preexec hook)\n'
            # shellcheck disable=SC2016
            printf 'command -v starship >/dev/null && eval "$(starship init bash)"\n'
        fi

        # --- restore alias expansion -----------------------------------------
        # All definitions are parsed; safe to re-enable so the user gets aliases.
        printf '\n# restore alias expansion\n%s\n' "$_ea"
    } > "$out"

    printf '%s\n' "$out"
}
