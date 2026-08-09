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

auto_attach_to_tmux() {
    if is_truthy "${LOADOUT_CFG_ATTACH_TO_TMUX}"; then
        # Make sure terminal is in a known-good state
        reset

        if tmux has-session 2>/dev/null; then
            if is_truthy "${LOADOUT_CFG_ATTACH_TO_TMUX_WITH_DETACH_OTHERS}"; then
                # Attach this bash, -d -> detach all others
                unset_bashrc_local_vars
                tmux attach -d
            else
                unset_bashrc_local_vars
                tmux attach
            fi
        else
            # Create a new tmux session
            unset_bashrc_local_vars
            tmux
        fi
    fi
}

# Use a leading _ char for bashrc local vars that should go away at the end of env setup.
# LOADOUT_CFG_* vars are exported scalars -- they survive into child processes intentionally.
unset_bashrc_local_vars() {
    # Unset all local variables that start with '_'.
    #
    # `compgen` is a BASH builtin with no zsh equivalent, and this function is
    # reached from auto_attach_to_tmux, which the zsh env calls -- so a zsh user
    # with LOADOUT_CFG_ATTACH_TO_TMUX enabled got
    # "unset_bashrc_local_vars:2: command not found: compgen" on every login.
    # zsh lists parameter names through the `parameters` association instead.
    # The zsh-only expansions below go through `eval` so that this file, which
    # is bash-shaped and gets read by bash tooling, stays free of syntax bash
    # and shellcheck do not recognise (SC2296). Both shells parse it either way;
    # this is about not handing a reviewer a spurious error.
    local var
    local -a _lo_names
    if [ -n "${ZSH_VERSION:-}" ]; then
        eval '_lo_names=(${(Mk)parameters:#_*})'
    else
        _lo_names=($(compgen -v _))
    fi
    for var in "${_lo_names[@]}"; do
        # Skip exported variables -- LOADOUT_CFG_* and friends are meant to
        # survive into child processes.
        #
        # The two shells report "is exported" differently and there is no shared
        # spelling: bash's `declare -p` prints `declare -x NAME=...`, while
        # zsh's `typeset -p` prints `export NAME=...` with no -x anywhere. A
        # single `*" -x"*` test therefore matched nothing under zsh and unset
        # every exported variable it looked at. zsh's ${(t)} type string is the
        # reliable test there.
        _lo_exported=0
        if [ -n "${ZSH_VERSION:-}" ]; then
            eval '[[ ${(tP)var} == *export* ]] && _lo_exported=1'
        else
            case $(declare -p "$var" 2>/dev/null) in "declare -x"*) _lo_exported=1 ;; esac
        fi
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
#   1. LOADOUT_CFG_WEZTERM_SHELL_INTEGRATION  (explicit path; e.g. set by the
#      engineering-loadout --dest-dir installer)
#   2. copy vendored with the loadout (config root, plus home-dir override)
#   3. paths relative to the installed `wezterm` binary (dest-dir installs)
#   4. the configured shared prefix (${LOADOUT_CFG_SHARED_PREFIX:-$HOME/.local})
# Echoes the first readable match; returns 1 with no output if none found.
loadout_find_wezterm_shell_integration() {
    local _c _bin _real _bindir _prefix
    local _subs=(share/wezterm/shell-integration/wezterm.sh share/wezterm/wezterm.sh etc/profile.d/wezterm.sh)

    # 1. explicit override
    if [[ -n "${LOADOUT_CFG_WEZTERM_SHELL_INTEGRATION:-}" && -r "${LOADOUT_CFG_WEZTERM_SHELL_INTEGRATION}" ]]; then
        echo "${LOADOUT_CFG_WEZTERM_SHELL_INTEGRATION}"
        return 0
    fi

    # 2. vendored copy (canonical config root, then home-dir override)
    for _c in "$BASH_CONFIG_ROOT_DIR/global/wezterm/wezterm.sh" \
        "$HOME/.config/bash/global/wezterm/wezterm.sh"; do
        [[ -r "$_c" ]] && {
            echo "$_c"
            return 0
        }
    done

    # 3. relative to the installed wezterm binary
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

    # 4. configured shared prefix
    _prefix="${LOADOUT_CFG_SHARED_PREFIX:-$HOME/.local}"
    for _c in "${_subs[@]}"; do
        [[ -r "$_prefix/$_c" ]] && {
            echo "$_prefix/$_c"
            return 0
        }
    done

    return 1
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
