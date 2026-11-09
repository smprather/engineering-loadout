# Probe network reachability against key hosts in parallel.
# Usage: loadout_detect_online [timeout_secs]
# Hosts: space-separated "host:port" pairs from LOADOUT_CFG_ONLINE_DETECT_HOSTS.
# Returns 0 (online) or 1 (offline/blocked); safe to call from non-interactive context.
loadout_detect_online() {
    local _t="${1:-${LOADOUT_CFG_ONLINE_DETECT_TIMEOUT:-0.15}}"
    local _hosts="${LOADOUT_CFG_ONLINE_DETECT_HOSTS:-github.com:443 raw.githubusercontent.com:443 pypi.org:443}"
    local _tmp _result
    _tmp=$(mktemp 2>/dev/null) || return 1

    # The whole parallel fan-out runs inside ONE subshell, so the background
    # jobs are that subshell's, not the interactive shell's.
    #
    # This is not stylistic. zsh reports background jobs as they start and as
    # they are reaped -- "[9] 2825450", "[9] + done (timeout ...)" -- so
    # backgrounding directly from the interactive shell printed job-control
    # noise into every zsh startup, and startup silence is a hard requirement.
    # Setting NO_NOTIFY/NO_MONITOR around it is NOT enough: LOCAL_OPTIONS
    # restores them when this function returns, and the reap notice then lands
    # afterwards anyway (observed at shell exit). Keeping the jobs out of the
    # interactive shell's job table is the only version with nothing to leak.
    # bash is quieter about this, which is why it went unnoticed until the zsh
    # env started using the shared function.
    (
        for _hp in $_hosts; do
            (timeout "$_t" bash -c "echo >/dev/tcp/${_hp%%:*}/${_hp##*:}" 2>/dev/null &&
                echo 1 >"$_tmp") &
        done
        wait
    ) >/dev/null 2>&1

    _result=$(cat "$_tmp" 2>/dev/null)
    rm -f "$_tmp"
    [[ "$_result" == "1" ]]
}

# loadout_detect_online behind a once-per-day disk cache.
#
# Shell startup must stay fast even on flaky networks: the first login of a
# day pays the parallel TCP probe once, every later shell reads the verdict
# from disk without touching the network. Keyed on an md5 of the host list so
# a user override of LOADOUT_CFG_ONLINE_DETECT_HOSTS gets its own entry.
# Usage: loadout_detect_online_cached [timeout_secs]   (TTL:
# LOADOUT_CFG_ONLINE_CACHE_TTL, default 86400; 0 disables caching)
loadout_detect_online_cached() {
    [ -n "${ZSH_VERSION:-}" ] && setopt LOCAL_OPTIONS KSH_ARRAYS SH_WORD_SPLIT 2>/dev/null
    local _ttl="${LOADOUT_CFG_ONLINE_CACHE_TTL:-86400}"
    local _hosts="${LOADOUT_CFG_ONLINE_DETECT_HOSTS:-github.com:443 raw.githubusercontent.com:443 pypi.org:443}"
    local _dir="${XDG_RUNTIME_DIR:-}/.loadout-net"
    local _key _file _verdict _now _age _result

    # No runtime dir, no cache. The old /tmp fallback was a predictable shared
    # dir that whoever creates it first owns: a co-tenant could plant the
    # verdict, or a symlink at the temp name. The shells set a private
    # XDG_RUNTIME_DIR before they get here.
    if [[ -z "${XDG_RUNTIME_DIR:-}" ]]; then
        loadout_detect_online "$@"
        return
    fi

    _key=$(printf '%s' "$_hosts" | md5sum | awk '{print $1}')
    _file="$_dir/detect-$_key"

    if ((_ttl > 0)) && [[ -f "$_file" ]]; then
        _verdict=$(cat "$_file" 2>/dev/null)
        case "$_verdict" in
        0 | 1)
            _now=$(date +%s)
            _age=$((_now - $(stat -c %Y "$_file" 2>/dev/null || echo 0)))
            if ((_age < _ttl)); then
                [[ "$_verdict" == "1" ]]
                return
            fi
            ;;
        esac
    fi

    loadout_detect_online "$@"
    _result=$?
    mkdir -p "$_dir" 2>/dev/null
    {
        printf '%s\n' "$((_result == 0 ? 1 : 0))" >"$_dir/.detect-$_key.$$" &&
            mv -f "$_dir/.detect-$_key.$$" "$_file"
    } 2>/dev/null
    return $_result
}

# Use a leading _ char for bashrc local vars that should go away at the end of env setup.
# LOADOUT_CFG_* vars are exported scalars -- they survive into child processes intentionally.
unset_bashrc_local_vars() {
    # Unset all local variables that start with '_'.
    # bash only: `compgen` has no zsh equivalent, and the zsh env never calls this.
    local var
    local -a _lo_names
    _lo_names=($(compgen -v _))
    for var in "${_lo_names[@]}"; do
        # Skip exported variables -- LOADOUT_CFG_* and friends are meant to
        # survive into child processes.
        _lo_exported=0
        case $(declare -p "$var" 2>/dev/null) in "declare -x"*) _lo_exported=1 ;; esac
        [ "$_lo_exported" = 1 ] && continue
        unset "$var"
    done
}

# Prepend a directory to a colon-list variable only if it exists and is not
# already present. With one argument the target is PATH; with two, the first
# argument names the variable to change:
#   path_prepend_if_dir /opt/bin                  # -> PATH
#   path_prepend_if_dir LD_LIBRARY_PATH /opt/lib  # -> LD_LIBRARY_PATH
path_prepend_if_dir() {
    # eval-based indirection (not ${!var} / printf -v): this file is sourced
    # by zsh too (envs/zsh/zshrc), where both of those are bashisms.
    local _var _dir _cur
    if [[ $# -ge 2 ]]; then
        _var=$1
        _dir=$2
    else
        _var=PATH
        _dir=$1
    fi
    case $_var in *[!A-Za-z0-9_]* | "") return 1 ;; esac
    [[ -d "$_dir" ]] || return 0
    eval "_cur=\${$_var-}"
    case ":${_cur}:" in
    *":${_dir}:"*) ;;
    *) eval "$_var=\"\${_dir}\${_cur:+:}\${_cur}\"" ;;
    esac
}

# Append a directory to a colon-list variable only if it exists and is not
# already present. One argument targets PATH; two targets the named variable
# (see path_prepend_if_dir).
path_append_if_dir() {
    # See path_prepend_if_dir for why this uses eval (zsh compatibility).
    local _var _dir _cur
    if [[ $# -ge 2 ]]; then
        _var=$1
        _dir=$2
    else
        _var=PATH
        _dir=$1
    fi
    case $_var in *[!A-Za-z0-9_]* | "") return 1 ;; esac
    [[ -d "$_dir" ]] || return 0
    eval "_cur=\${$_var-}"
    case ":${_cur}:" in
    *":${_dir}:"*) ;;
    *) eval "$_var=\"\${_cur}\${_cur:+:}\${_dir}\"" ;;
    esac
}

# Register a function to run before each prompt, portably across prompt
# frameworks. If a precmd_functions array is active (bash-preexec, ble.sh,
# wezterm/vte shell integration) the callback is appended to it so the
# framework's own prompt driver keeps working; otherwise it is prepended to
# PROMPT_COMMAND. Never unsets or clobbers an existing driver, and dedups so a
# re-source can't register the same callback twice.
loadout_add_precmd() {
    local _fn="$1" _f
    if [[ $(declare -p precmd_functions 2>/dev/null) == 'declare -a'* ]]; then
        for _f in "${precmd_functions[@]}"; do
            [[ "$_f" == "$_fn" ]] && return 0
        done
        precmd_functions+=("$_fn")
    else
        case ";${PROMPT_COMMAND-};" in
        *";$_fn;"*) ;;
        *) PROMPT_COMMAND="$_fn${PROMPT_COMMAND:+;$PROMPT_COMMAND}" ;;
        esac
    fi
}

# Locate the wezterm shell-integration script (semantic zones / OSC 7 cwd / user
# vars) from user-writable space only -- never /etc. Search order:
#   1. copy vendored with the loadout (config root, plus home-dir override)
#   2. paths relative to the installed `wezterm` binary (dest-dir installs)
#   3. the configured shared prefix (${LOADOUT_CFG_SHARED_PREFIX:-$HOME/.local})
# Echoes the first readable match; returns 1 with no output if none found.
loadout_find_wezterm_shell_integration() {
    local _c _bin _real _bindir _prefix
    local _subs=(share/wezterm/shell-integration/wezterm.sh share/wezterm/wezterm.sh etc/profile.d/wezterm.sh)

    # 1. vendored copy (canonical config root, then home-dir override)
    for _c in "$BASH_CONFIG_DIR/global/wezterm/wezterm.sh" \
        "$HOME/.config/bash/global/wezterm/wezterm.sh"; do
        [[ -r "$_c" ]] && {
            echo "$_c"
            return 0
        }
    done

    # 2. relative to the installed wezterm binary
    if _bin=$(command -v wezterm 2>/dev/null); then
        _real=$(realpath "$_bin" 2>/dev/null || readlink -f "$_bin" 2>/dev/null || echo "$_bin")
        _bindir=$(dirname "$_real")
        _prefix=$(dirname "$_bindir")
        for _c in "${_subs[@]}"; do
            [[ -r "$_prefix/$_c" ]] && {
                echo "$_prefix/$_c"
                return 0
            }
        done
        [[ -r "$_bindir/wezterm.sh" ]] && {
            echo "$_bindir/wezterm.sh"
            return 0
        }
    fi

    # 3. configured shared prefix
    _prefix="${LOADOUT_CFG_SHARED_PREFIX:-$HOME/.local}"
    for _c in "${_subs[@]}"; do
        [[ -r "$_prefix/$_c" ]] && {
            echo "$_prefix/$_c"
            return 0
        }
    done

    return 1
}

# Resolve a LOADOUT_CFG_INTERACTIVE_SHELL value to an executable. Prints the
# absolute path and returns 0, or prints nothing and returns 1:
#   empty, or any whitespace (`zsh -l`)  -> 1
#   /absolute/path                       -> itself, when a regular executable
#   any other slash (`bin/zsh`)          -> 1
#   bare name                            -> <shared prefix>/bin/NAME, else the
#                                           first absolute inherited PATH
#                                           entry with it
# Never `command -v`/`type`/`whence`: those answer with aliases and functions.
loadout_resolve_interactive_shell() {
    local _v="${1:-}" _rest _d
    case $_v in
    "" | *[[:space:]]*) return 1 ;;
    /*)
        [ -f "$_v" ] && [ -x "$_v" ] || return 1
        printf '%s\n' "$_v"
        return 0
        ;;
    */*) return 1 ;;
    esac
    _d="${LOADOUT_CFG_SHARED_PREFIX:-$HOME/.local/share/loadout}/bin/$_v"
    if [ -f "$_d" ] && [ -x "$_d" ]; then
        printf '%s\n' "$_d"
        return 0
    fi
    _rest=${PATH:-}
    while [ -n "$_rest" ]; do
        _d=${_rest%%:*}
        case $_rest in
        *:*) _rest=${_rest#*:} ;;
        *) _rest="" ;;
        esac
        # SHELL and the marker must be absolute: relative entries (and empty
        # ones, which mean the cwd) are skipped.
        case $_d in /*) ;; *) continue ;; esac
        if [ -f "$_d/$_v" ] && [ -x "$_d/$_v" ]; then
            printf '%s\n' "$_d/$_v"
            return 0
        fi
    done
    return 1
}

# bash only. Returns 0 when the bash argv in FILE (NUL-separated, the
# /proc/PID/cmdline shape) names a script operand, else 1; prints nothing and
# forks nothing. bash < 5.2 sets $0 to the script only AFTER the startup files,
# so the exec guard reads the operand off argv instead. The grammar is bash(1)
# INVOCATION: long options first (--init-file and --rcfile take an argument),
# then option clusters (each o/O in one takes the next argument) up to `-` or
# `--`; -c and -s mean no script; the first other argument is the script.
loadout_bash_argv_has_script() {
    [ -n "${BASH_VERSION:-}" ] && [ -r "${1:-}" ] || return 1
    local _a _r _skip=0 _long=1 _first=1
    while IFS= read -r -d '' _a; do
        if [ "$_first" = 1 ]; then
            _first=0 # argv[0]
            continue
        fi
        if [ "$_skip" -gt 0 ]; then
            _skip=$((_skip - 1))
            continue
        fi
        if [ "$_long" = 1 ]; then
            case $_a in
            --init-file | --rcfile)
                _skip=1
                continue
                ;;
            --) ;;
            --*) continue ;;
            esac
            _long=0
        fi
        case $_a in
        - | --)
            IFS= read -r -d '' _a
            return
            ;;
        [-+]?*)
            case $_a in [-+]*[cs]*) return 1 ;; esac
            _r=${_a#?}
            while [ -n "$_r" ]; do
                case $_r in [oO]*) _skip=$((_skip + 1)) ;; esac
                _r=${_r#?}
            done
            ;;
        *) return 0 ;;
        esac
    done <"$1"
    return 1
}

# One-shot exec into LOADOUT_CFG_INTERACTIVE_SHELL, called near the top of the
# bash and zsh rc only when that variable is non-empty. Returns 0 with no side
# effects unless ALL of these hold (cheap tests first, forks last):
#   - LOADOUT_SHELL_EXEC is unset: no earlier exec in this session tree;
#   - the shell is interactive and has no command string (`SHELL -ilc CMD`
#     must run CMD -- IDEs read the environment that way);
#   - it has no script operand: `bash -i FILE`, `zsh -i FILE` and a
#     `#!/bin/bash -i` script read the rc and then run FILE, which an exec
#     would drop. zsh says so in ZSH_SCRIPT. bash >= 5.2 sets $0 to FILE while
#     the rc runs (a login argv0 such as `-bash` is never one; $BASH itself
#     comes from passwd there); older bash still says `bash`, so its argv is
#     read (loadout_bash_argv_has_script);
#   - it is a top-level spawn: a login shell, or the INHERITED $SHELL (not
#     `sh`) resolves to the running shell. A shell typed at a prompt is
#     neither, so it never bounces back;
#   - the value resolves (loadout_resolve_interactive_shell);
#   - the target is not the running shell (symlinks resolved);
#   - the target actually runs here: one `-c :` probe.
# Then exports LOADOUT_SHELL_EXEC and SHELL as the resolved path and execs:
# with `-l` for a login origin and a known login-capable shell, with
# --init-file BASH_INIT_FILE for bash -> bash, else with no arguments.
# Usage: loadout_exec_interactive_shell [BASH_INIT_FILE]
loadout_exec_interactive_shell() {
    local _t _self _login=0
    [ -z "${LOADOUT_SHELL_EXEC+set}" ] || return 0
    if [ -n "${ZSH_VERSION:-}" ]; then
        # Not `-o shinstdin`: zsh turns that on only AFTER its startup files,
        # so it is off here even for a plain interactive zsh.
        [[ -o interactive && -z ${ZSH_EXECUTION_STRING:-} && -z ${ZSH_SCRIPT-} ]] || return 0
        [[ -o login ]] && _login=1
    elif [ -n "${BASH_VERSION:-}" ]; then
        [[ $- == *i* && -z ${BASH_EXECUTION_STRING:-} ]] || return 0
        case $0 in
        -*) ;;
        *) [ "${0##*/}" = "${BASH##*/}" ] || return 0 ;;
        esac
        if [ "${BASH_VERSINFO[0]}" -lt 5 ] || { [ "${BASH_VERSINFO[0]}" = 5 ] && [ "${BASH_VERSINFO[1]}" -lt 2 ]; }; then
            ! loadout_bash_argv_has_script "/proc/$$/cmdline" || return 0
        fi
        shopt -q login_shell && _login=1
    else
        return 0
    fi
    if [ "$_login" = 0 ]; then
        [ -n "${SHELL:-}" ] && [ "${SHELL##*/}" != sh ] || return 0
        # bash sets an unset SHELL to the passwd shell, unexported. Only an
        # inherited (exported) SHELL says anything about how we were spawned.
        if [ -n "${BASH_VERSION:-}" ]; then
            case $(declare -p SHELL 2>/dev/null) in "declare -x"*) ;; *) return 0 ;; esac
        fi
    fi
    _self=$(readlink -f /proc/$$/exe 2>/dev/null) && [ -n "$_self" ] || return 0
    if [ "$_login" = 0 ]; then
        [ "$(readlink -f "$SHELL" 2>/dev/null)" = "$_self" ] || return 0
    fi
    _t=$(loadout_resolve_interactive_shell "${LOADOUT_CFG_INTERACTIVE_SHELL:-}") || return 0
    [ "$(readlink -f "$_t" 2>/dev/null)" != "$_self" ] || return 0
    # Probe first: it catches bad interpreter, exec format and loader failures,
    # which `execfail` cannot catch after exec (the shell is already gone).
    case ${_t##*/} in
    zsh | tcsh | csh) "$_t" -f -c : </dev/null >/dev/null 2>&1 || return 0 ;;
    fish) "$_t" --no-config -c : </dev/null >/dev/null 2>&1 || return 0 ;;
    *) "$_t" -c : </dev/null >/dev/null 2>&1 || return 0 ;;
    esac

    export LOADOUT_SHELL_EXEC="$_t" SHELL="$_t"
    if [ "$_login" = 1 ]; then
        case ${_t##*/} in
        bash | zsh | tcsh | csh | fish | ksh) exec "$_t" -l ;;
        esac
    fi
    if [ -n "${BASH_VERSION:-}" ] && [ -n "${1:-}" ] && [ "${_t##*/}" = bash ]; then
        LOADOUT_BASHRC_SOURCED=0 exec "$_t" --init-file "$1"
    fi
    exec "$_t"
}

is_in() {
    echo -n "$2" | /bin/grep -w -q "$1"
}

# zsh compatibility shim for the path_* family below.
#
# This file is sourced by BOTH envs/bash and envs/zsh -- it is the shared
# library, not a bash-private one. Three things in the path functions are
# bash-shaped and silently wrong under zsh:
#
#   * arrays are 1-based in zsh, and these functions index from 0;
#   * unquoted `${val}` does NOT word-split in zsh, so `newdirs=(${val})`
#     yields one element instead of the split list;
#   * `${!var}` is bash's indirect expansion; zsh has no equivalent, and ksh
#     emulation gives ksh93's meaning (the variable NAME) instead of its value.
#
# The first two are fixed by zsh's own local options; the third by the eval
# indirection this file already prefers elsewhere (see source_if_exists). The
# result is byte-identical behaviour in both shells -- verified by
# tests/env-shell-parity.
#
# Before this, `path_append LD_LIBRARY_PATH /opt/lib` -- the documented two-arg
# form -- died with "bad substitution" under zsh, which is why envs/zsh/zshrc
# used to hand-roll its TERMINFO_DIRS handling instead of calling path_prepend.
#
# The setopt line is REPEATED in each function rather than factored into a
# helper: LOCAL_OPTIONS restores the options when the function that set them
# returns, so a helper would undo them before its caller ever ran a line.

# Path type variable manipulation. Copied from https://www.runscripts.com/support/guides/scripting/bash/path-functions
path_modify() {
    [ -n "${ZSH_VERSION:-}" ] && setopt LOCAL_OPTIONS KSH_ARRAYS SH_WORD_SPLIT 2>/dev/null
    typeset opt_op opt_once

    OPTIND=1
    while getopts "1def" opt; do
        case "${opt}" in
        1)
            opt_once=1
            ;;
        d | e | f)
            opt_op=${opt}
            ;;
        ?)
            error "Unexpected argument"
            ;;
        esac
    done

    shift $(($OPTIND - 1))

    typeset var=$1
    typeset val="$2"
    typeset act="$3"
    typeset wrt="$4"
    typeset sep="${5:-:}"

    typeset OIFS
    OIFS="${IFS}"

    IFS="${sep}"
    typeset origdirs
    eval "origdirs=(\${$var})"

    typeset newdirs
    newdirs=(${val})

    if [[ ${opt_op} ]]; then
        typeset n
        typeset maxn=${#newdirs[*]}

        for ((n = 0; n < ${maxn}; n++)); do

            if
                case "${opt_op}" in
                d) [[ ! -d "${newdirs[n]}" ]] ;;
                e) [[ ! -e "${newdirs[n]}" ]] ;;
                f) [[ ! -f "${newdirs[n]}" ]] ;;
                esac
            then
                unset "newdirs[n]"
            fi
        done
    fi

    if [[ ${#newdirs[*]} -eq 0 ]]; then
        case "${act}" in
        verify | replace | remove)
            ;;
        *)
            IFS="${OIFS}"
            return 0
            ;;
        esac
    fi

    typeset vardirs
    vardirs=()
    case "${act}" in
    first | start)
        vardirs=("${newdirs[@]}" "${origdirs[@]}")
        ;;
    last | end)
        vardirs=("${origdirs[@]}" "${newdirs[@]}")
        ;;
    verify)
        vardirs=("${newdirs[@]}")
        ;;
    after | before | replace | remove)
        typeset todo=1
        typeset o
        typeset maxo=${#origdirs[*]}

        for ((o = 0; o < ${maxo}; o++)); do
            if [[ "${todo}" && "${origdirs[o]}" = "${wrt}" ]]; then
                case "${act}" in
                after)
                    vardirs+=("${origdirs[o]}" "${newdirs[@]}")
                    ;;
                before)
                    vardirs+=("${newdirs[@]}" "${origdirs[o]}")
                    ;;
                replace)
                    vardirs+=("${newdirs[@]}")
                    ;;
                remove)
                    ;;
                esac

                if [[ "${opt_once}" ]]; then
                    todo=
                fi
            else
                vardirs+=("${origdirs[o]}")
            fi
        done
        ;;
    *)
        vardirs=("${origdirs[@]}")
        ;;
    esac

    read ${var} <<<"${vardirs[*]}"

    IFS="${OIFS}"
}

path_append() {
    typeset opt_flags

    OPTIND=1
    while getopts "def" opt; do
        case "${opt}" in
        d | e | f)
            opt_flags=-${opt}
            ;;
        ?)
            error "Unexpected argument"
            ;;
        esac
    done

    shift $(($OPTIND - 1))

    path_modify ${opt_flags} "$1" "$2" last '' "${3:-:}"
}

path_prepend() {
    typeset opt_flags

    OPTIND=1
    while getopts "def" opt; do
        case "${opt}" in
        d | e | f)
            opt_flags=-${opt}
            ;;
        ?)
            error "Unexpected argument"
            ;;
        esac
    done

    shift $(($OPTIND - 1))

    path_modify ${opt_flags} "$1" "$2" first '' "${3:-:}"
}

path_verify() {
    typeset opt_flags

    OPTIND=1
    while getopts "def" opt; do
        case "${opt}" in
        d | e | f)
            opt_flags=-${opt}
            ;;
        ?)
            error "Unexpected argument"
            ;;
        esac
    done

    shift $(($OPTIND - 1))

    # As path_modify checks the paths to be added we pass the expansion of NAME, ie
    # our own value

    path_modify ${opt_flags} "$1" "${!1}" verify '' "${2:-:}"
}

path_replace() {
    typeset opt_flags

    OPTIND=1
    while getopts "def" opt; do
        case "${opt}" in
        d | e | f)
            opt_flags=-${opt}
            ;;
        ?)
            error "Unexpected argument"
            ;;
        esac
    done

    shift $(($OPTIND - 1))

    # The expression is path_replace OLD NEW but path_modify takes the arguments
    # the other way round

    path_modify ${opt_flags} "$1" "$3" replace "$2" "${4:-:}"
}

path_remove() {
    typeset opt_flags

    OPTIND=1
    while getopts "def" opt; do
        case "${opt}" in
        d | e | f)
            opt_flags=-${opt}
            ;;
        ?)
            error "Unexpected argument"
            ;;
        esac
    done

    shift $(($OPTIND - 1))

    path_modify ${opt_flags} "$1" '' remove "$2" "${3:-:}"
}

path_trim() {
    [ -n "${ZSH_VERSION:-}" ] && setopt LOCAL_OPTIONS KSH_ARRAYS SH_WORD_SPLIT 2>/dev/null
    typeset var=$1
    typeset sep="${2:-:}"

    typeset OIFS
    OIFS="${IFS}"

    IFS="${sep}"
    typeset origdirs
    eval "origdirs=(\${$var})"

    IFS="${OIFS}"

    typeset o
    typeset maxo=${#origdirs[*]}
    typeset seen=
    # Build the kept list rather than `unset`-ing duplicates in place. bash's
    # `unset arr[i]` REMOVES the element, so "${arr[*]}" skips it; zsh's blanks
    # the slot but keeps it, so the same code trimmed "/a:/tmp:/a:/tmp" to
    # "/a:/tmp::" -- correct entries plus two empty fields. Appending to a second
    # array means the same thing in both shells.
    typeset keptdirs
    keptdirs=()
    for ((o = 0; o < ${maxo}; o++)); do
        case "${sep}${seen}${sep}" in
        *"${sep}${origdirs[o]:-.}${sep}"*)
            ;;
        *)
            seen="${seen+${seen}${sep}}${origdirs[o]:-.}"
            keptdirs+=("${origdirs[o]}")
            ;;
        esac
    done

    IFS="${sep}"
    read ${var} <<<"${keptdirs[*]}"

    IFS="${OIFS}"
}

std_paths() {
    [ -n "${ZSH_VERSION:-}" ] && setopt LOCAL_OPTIONS KSH_ARRAYS SH_WORD_SPLIT 2>/dev/null
    typeset act="$1"
    typeset val="$2"
    typeset sep="${3:-:}"

    typeset OIFS
    OIFS="${IFS}"

    IFS="${sep}"
    typeset origdirs
    eval "origdirs=(\${$var})"

    IFS="${OIFS}"

    typeset dir
    for dir in "${origdirs[@]}"; do
        path_${act} PATH "${dir}/bin"
        typeset md
        for md in man share/man; do
            if [[ -d "${dir}/${md}" ]]; then
                path_${act} MANPATH "${dir}/${md}"
            fi
        done
    done
}

vercomp() {
    if [[ $1 == "$2" ]]; then
        return 0
    fi
    local IFS=.
    local i
    local -a ver1 ver2
    read -r -a ver1 <<<"$1"
    read -r -a ver2 <<<"$2"
    # fill empty fields in ver1 with zeros
    for ((i = ${#ver1[@]}; i < ${#ver2[@]}; i++)); do
        ver1[i]=0
    done
    for ((i = 0; i < ${#ver1[@]}; i++)); do
        if [[ -z ${ver2[i]} ]]; then
            # fill empty fields in ver2 with zeros
            ver2[i]=0
        fi
        if [[ ! ${ver1[i]} =~ ^[0-9]+$ || ! ${ver2[i]} =~ ^[0-9]+$ ]]; then
            if [[ ${ver1[i]} > "${ver2[i]}" ]]; then
                return 1
            fi
            if [[ ${ver1[i]} < "${ver2[i]}" ]]; then
                return 2
            fi
            continue
        fi
        if ((10#${ver1[i]} > 10#${ver2[i]})); then
            return 1
        fi
        if ((10#${ver1[i]} < 10#${ver2[i]})); then
            return 2
        fi
    done
    return 0
}

join_by() {
    local d=${1-} f=${2-}
    if shift 2; then
        printf %s "$f" "${@/#/$d}"
    fi
}

verlte() { [ "$1" = "$(printf '%s\n' "$1" "$2" | sort -V | head -n1)" ]; }
verlt() { [ "$1" = "$2" ] && return 1 || verlte "$1" "$2"; }
ver_between() {
    # args: min, actual, max
    printf '%s\n' "$@" | sort -C -V
}
ver() {
    printf "%03d%03d%03d%03d" $(echo "$1" | tr '.' ' ')
}

array_slice() {
    local __doc__='
    Returns a slice of an array (similar to Python).

    From the Python documentation:
    One way to remember how slices work is to think of the indices as pointing
    between elements, with the left edge of the first character numbered 0.
    Then the right edge of the last element of an array of length n has
    index n, for example:
    ```
    +---+---+---+---+---+---+
    | 0 | 1 | 2 | 3 | 4 | 5 |
    +---+---+---+---+---+---+
    0   1   2   3   4   5   6
    -6  -5  -4  -3  -2  -1
    ```

    >>> local a=(0 1 2 3 4 5)
    >>> echo $(array.slice 1:-2 "${a[@]}")
    1 2 3
    >>> local a=(0 1 2 3 4 5)
    >>> echo $(array.slice 0:1 "${a[@]}")
    0
    >>> local a=(0 1 2 3 4 5)
    >>> [ -z "$(array.slice 1:1 "${a[@]}")" ] && echo empty
    empty
    >>> local a=(0 1 2 3 4 5)
    >>> [ -z "$(array.slice 2:1 "${a[@]}")" ] && echo empty
    empty
    >>> local a=(0 1 2 3 4 5)
    >>> [ -z "$(array.slice -2:-3 "${a[@]}")" ] && echo empty
    empty
    >>> [ -z "$(array.slice -2:-2 "${a[@]}")" ] && echo empty
    empty

    Slice indices have useful defaults; an omitted first index defaults to
    zero, an omitted second index defaults to the size of the string being
    sliced.
    >>> local a=(0 1 2 3 4 5)
    >>> # from the beginning to position 2 (excluded)
    >>> echo $(array.slice 0:2 "${a[@]}")
    >>> echo $(array.slice :2 "${a[@]}")
    0 1
    0 1

    >>> local a=(0 1 2 3 4 5)
    >>> # from position 3 (included) to the end
    >>> echo $(array.slice 3:"${#a[@]}" "${a[@]}")
    >>> echo $(array.slice 3: "${a[@]}")
    3 4 5
    3 4 5

    >>> local a=(0 1 2 3 4 5)
    >>> # from the second-last (included) to the end
    >>> echo $(array.slice -2:"${#a[@]}" "${a[@]}")
    >>> echo $(array.slice -2: "${a[@]}")
    4 5
    4 5

    >>> local a=(0 1 2 3 4 5)
    >>> echo $(array.slice -4:-2 "${a[@]}")
    2 3

    If no range is given, it works like normal array indices.
    >>> local a=(0 1 2 3 4 5)
    >>> echo $(array.slice -1 "${a[@]}")
    5
    >>> local a=(0 1 2 3 4 5)
    >>> echo $(array.slice -2 "${a[@]}")
    4
    >>> local a=(0 1 2 3 4 5)
    >>> echo $(array.slice 0 "${a[@]}")
    0
    >>> local a=(0 1 2 3 4 5)
    >>> echo $(array.slice 1 "${a[@]}")
    1
    >>> local a=(0 1 2 3 4 5)
    >>> array.slice 6 "${a[@]}"; echo $?
    1
    >>> local a=(0 1 2 3 4 5)
    >>> array.slice -7 "${a[@]}"; echo $?
    1
    '
    local start end array_length length
    if [[ $1 == *:* ]]; then
        IFS=":"
        read -r start end <<<"$1"
        shift
        array_length="$#"
        # defaults
        [ -z "$end" ] && end=$array_length
        [ -z "$start" ] && start=0
        ((start < 0)) && let "start=(( array_length + start ))"
        ((end < 0)) && let "end=(( array_length + end ))"
    else
        start="$1"
        shift
        array_length="$#"
        ((start < 0)) && let "start=(( array_length + start ))"
        let "end=(( start + 1 ))"
    fi
    let "length=(( end - start ))"
    ((start < 0)) && return 1
    # check bounds
    ((length < 0)) && return 1
    ((start < 0)) && return 1
    ((start >= array_length)) && return 1
    # parameters start with $1, so add 1 to $start
    let "start=(( start + 1 ))"
    echo "${@:$start:$length}"
}
alias array.slice="array_slice"

# Succeed only when DIR is a directory only this user can write: created 0700
# when absent, never a symlink, owned by us, no one else could have written it,
# tightened to 0700. RHEL's UPG umask 002 leaves our own dirs 0775 with our
# PRIVATE group, so that group write bit is ours to remove. Other write, or
# group write with a shared group, is refused and left alone: tightening would
# trust what a co-tenant may already have planted inside. Prints nothing.
#
# /dev/shm and the temp root are world-writable and the per-user names under
# them are predictable, so a co-tenant can create them first -- and whoever
# owns the directory can swap what we keep there (the eza copy every `ls`
# runs, .pyc files every Python imports, shell history). Callers fall back to
# a HOME path when this fails. Shared with zsh; envs/tcsh/global/helpers/
# private-dir is the same rule for tcsh, and global.paths.private_dir for nvim.
# Usage: loadout_private_dir DIR
loadout_private_dir() {
    local _d=$1 _st _mode _group
    [ -n "$_d" ] || return 1
    if [ ! -e "$_d" ] && [ ! -L "$_d" ]; then
        (umask 077 && mkdir -p "$_d") 2>/dev/null
    fi
    [ -d "$_d" ] && [ ! -L "$_d" ] && [ -O "$_d" ] || return 1
    _st=$(stat -c '%a %G' "$_d" 2>/dev/null) || return 1
    _mode=${_st%% *}
    _group=${_st#* }
    case $_mode in
    700) return 0 ;;
    # Other write bit (last octal digit): refuse, leave it alone.
    *[2367]) return 1 ;;
    # Group write bit: ours to remove only with our private (UPG) group.
    *[2367]?) [ "$_group" = "$(id -un)" ] || return 1 ;;
    esac
    chmod 700 "$_d" 2>/dev/null || return 1
    return 0
}

source_if_exists() {
    [[ -r "$1" ]] || return 0
    source "$1"
}

# https://stackoverflow.com/questions/59895/how-do-i-get-the-directory-where-a-bash-script-is-located-from-within-the-script
get_script_dir() {
    local source_path="${BASH_SOURCE[0]}"
    local symlink_dir
    local script_dir
    # Resolve symlinks recursively
    while [ -L "$source_path" ]; do
        # Get symlink directory
        symlink_dir="$(cd -P "$(/usr/bin/dirname "$source_path")" >/dev/null 2>&1 && pwd)"
        # Resolve symlink target (relative or absolute)
        source_path="$(/usr/bin/readlink "$source_path")"
        # Check if candidate path is relative or absolute
        if [[ $source_path != /* ]]; then
            # Candidate path is relative, resolve to full path
            source_path=$symlink_dir/$source_path
        fi
    done
    # Get final script directory path from fully resolved source path
    script_dir="$(cd -P "$(/usr/bin/dirname "$source_path")" >/dev/null 2>&1 && pwd)"
    echo "$script_dir"
}

is_truthy() {
    case "$1" in
    "true" | "1" | "yes" | "on" | "enabled")
        return 0 # True
        ;;
    "false" | "0" | "no" | "off" | "disabled" | "")
        return 1 # False
        ;;
    *)
        # For other non-empty strings, consider them truthy
        if [[ -n "$1" ]]; then
            # True
            return 0
        else
            # False
            return 1 # False (empty string)
        fi
        ;;
    esac
}

fpcmp() {
    if [ $# -ne 3 ]; then
        echo "Usage: fpcmp n1 (-eq|-gt|-ge|-lt|-le) n2" >&2
        return 2
    fi

    local n1="$1"
    local op="$2"
    local n2="$3"

    # Extract integer and decimal parts
    local n1_int="${n1%.*}"
    local n1_dec="${n1#*.}"
    local n2_int="${n2%.*}"
    local n2_dec="${n2#*.}"

    # Handle whole numbers (no decimal point)
    [ "$n1_int" = "$n1" ] && n1_dec="0"
    [ "$n2_int" = "$n2" ] && n2_dec="0"

    # Pad decimal parts to same length
    local max_len=${#n1_dec}
    [ ${#n2_dec} -gt $max_len ] && max_len=${#n2_dec}

    while [ ${#n1_dec} -lt $max_len ]; do n1_dec="${n1_dec}0"; done
    while [ ${#n2_dec} -lt $max_len ]; do n2_dec="${n2_dec}0"; done

    # Combine into integers for comparison
    local cmp1="${n1_int}${n1_dec}"
    local cmp2="${n2_int}${n2_dec}"

    # Remove leading zeros (but keep single 0)
    cmp1=$((10#$cmp1))
    cmp2=$((10#$cmp2))

    case "$op" in
    "-eq")
        [ $cmp1 -eq $cmp2 ]
        ;;
    "-gt")
        [ $cmp1 -gt $cmp2 ]
        ;;
    "-lt")
        [ $cmp1 -lt $cmp2 ]
        ;;
    "-ge")
        [ $cmp1 -ge $cmp2 ]
        ;;
    "-le")
        [ $cmp1 -le $cmp2 ]
        ;;
    *)
        echo "Invalid operator: $op" >&2
        return 2
        ;;
    esac
}

# Function to check terminal keyboard capabilities.
#
# THE SECONDARY-DA PROBE CONSUMES STDIN, so it is the last thing tried, not the
# first. `read -r -d 'c' -t 0.1` reads until the letter `c`; if the terminal
# never answers the query -- no real terminal, or one that ignores Secondary DA
# -- that read swallows whatever the USER typed ahead, up to their first `c`.
# Typing `echo MARK` during shell startup ran `ho MARK` (the `ec` eaten, and
# `ho` is the hostname alias). Reproduced in BOTH bash and zsh.
#
# So: answer from TERM and tmux FIRST, since neither touches stdin, and only
# fall through to the probe when it can be run safely.
check_extended_keys() {
    # Cheap, side-effect-free answers first.
    case "$TERM" in
    *kitty* | *alacritty*) return 0 ;;
    esac
    if [[ -n "$TMUX" ]]; then
        if tmux show-options -s extended-keys 2>/dev/null | grep -q "on"; then
            return 0
        fi
    fi

    # Ensure we are attached to a real TTY before querying
    if [[ ! -t 0 || ! -t 1 ]]; then
        return 1
    fi

    # Refuse the probe when input is ALREADY pending -- that input is the user's
    # and must not be eaten. The readability test has to be non-consuming, and
    # the two shells differ:
    #   bash: `read -t 0` reports readability and consumes nothing.
    #   zsh:  `read -t 0` CONSUMES the pending line, so it cannot be used here;
    #         zsh/zselect is the non-consuming test, and when that module is
    #         unavailable (an env-only install has no module_path) the probe is
    #         skipped rather than risking the user's keystrokes.
    if [ -n "${ZSH_VERSION:-}" ]; then
        zmodload zsh/zselect 2>/dev/null || return 1
        zselect -t 0 -r 0 >/dev/null 2>&1 && return 1
    else
        read -t 0 2>/dev/null && return 1
    fi

    local response
    # Save TTY state and turn off echo so the response isn't printed to the screen
    local old_stty=$(stty -g)
    stty -echo

    # Send the Device Attributes query (\e[>c)
    # Read the response with a tight 0.1-second timeout (-t 0.1)
    printf '\e[>c'
    read -r -d 'c' -t 0.1 response

    # Restore original TTY settings immediately
    stty "$old_stty"

    # Inside Tmux with extended keys enabled, the response starts with >84 (tmux id).
    # Kitty, Alacritty, iTerm2, and Ghostty return distinct vendor IDs here.
    [[ "$response" == *">84;"* ]]
}

# vim: ft=bash
