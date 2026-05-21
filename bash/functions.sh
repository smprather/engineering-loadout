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
# LOADOUT_CFG_* vars are exported scalars — they survive into child processes intentionally.
unset_bashrc_local_vars() {
    # Unset all local variables that start with '_'.
    for var in $(compgen -v _); do
        # Check if the variable is NOT exported
        if [[ $(declare -p "$var" 2>/dev/null) != "declare -x"* ]]; then
            unset "$var"
        fi
    done
}

# Prepend a directory to PATH only if it exists and is not already present.
path_prepend_if_dir() {
    local dir="$1"
    [[ -d "$dir" ]] || return 0
    case ":$PATH:" in
    *":$dir:"*) ;;
    *) PATH="$dir:$PATH" ;;
    esac
}

# Append a directory to PATH only if it exists and is not already present.
path_append_if_dir() {
    local dir="$1"
    [[ -d "$dir" ]] || return 0
    case ":$PATH:" in
    *":$dir:"*) ;;
    *) PATH="$PATH:$dir" ;;
    esac
}

is_in() {
    echo -n "$2" | /bin/grep -w -q "$1"
}

# Path type variable manipulation. Copied from https://www.runscripts.com/support/guides/scripting/bash/path-functions
path_modify() {
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
    origdirs=(${!var})

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
                unset newdirs[n]
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
                    vardirs=("${vardirs[@]}" "${origdirs[o]}" "${newdirs[@]}")
                    ;;
                before)
                    vardirs=("${vardirs[@]}" "${newdirs[@]}" "${origdirs[o]}")
                    ;;
                replace)
                    vardirs=("${vardirs[@]}" "${newdirs[@]}")
                    ;;
                remove)
                    ;;
                esac

                if [[ "${opt_once}" ]]; then
                    todo=
                fi
            else
                vardirs=("${vardirs[@]}" "${origdirs[o]}")
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
    typeset var=$1
    typeset sep="${2:-:}"

    typeset OIFS
    OIFS="${IFS}"

    IFS="${sep}"
    typeset origdirs
    origdirs=(${!var})

    IFS="${OIFS}"

    typeset o
    typeset maxo=${#origdirs[*]}
    typeset seen=
    for ((o = 0; o < ${maxo}; o++)); do
        case "${sep}${seen}${sep}" in
        *"${sep}${origdirs[o]:-.}${sep}"*)
            unset origdirs[o]
            ;;
        *)
            seen="${seen+${seen}${sep}}${origdirs[o]:-.}"
            ;;
        esac
    done

    IFS="${sep}"
    read ${var} <<<"${origdirs[*]}"

    IFS="${OIFS}"
}

std_paths() {
    typeset act="$1"
    typeset val="$2"
    typeset sep="${3:-:}"

    typeset OIFS
    OIFS="${IFS}"

    IFS="${sep}"
    typeset origdirs
    origdirs=(${!var})

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
    if [[ $1 == $2 ]]; then
        return 0
    fi
    local IFS=.
    local i ver1=($1) ver2=($2)
    # fill empty fields in ver1 with zeros
    for ((i = ${#ver1[@]}; i < ${#ver2[@]}; i++)); do
        ver1[i]=0
    done
    for ((i = 0; i < ${#ver1[@]}; i++)); do
        if [[ -z ${ver2[i]} ]]; then
            # fill empty fields in ver2 with zeros
            ver2[i]=0
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

verlte() { [ "$1" = "$(echo -e "$1\n$2" | sort -V | head -n1)" ]; }
verlt() { [ "$1" = "$2" ] && return 1 || verlte $1 $2; }
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
    [[ -r "$1" ]] && source "$1"
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
        if [[ -n "$value" ]]; then
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

# vim: ft=bash
