# shellcheck shell=bash
# loadout extension to vendored IceCream-Bash (icecream-bash/ic.sh).
#
# Keeps the vendored ic.sh byte-for-byte (so it stays re-clone-updatable) and
# redefines ic/ict here to accept BOTH variables and arbitrary strings, mixed in
# one call (Python-icecream style). Each argument is auto-classified:
#   - a valid identifier that is currently set  -> printed as "name - value"
#     (the [@] indirect handles scalars and arrays, same as upstream).
#   - anything else (literals, quoted strings)   -> printed verbatim.
# Multiple args are joined with " | ".
#
# icp/ictp are left as the vendored force-literal variants: use them when you
# want a word that happens to be a set variable name printed literally (e.g.
# `icp PATH`), since auto-classify would otherwise expand it.
#
# Sourced by global/bashrc right after ic.sh. Must be sourced after, so these
# definitions win.

ic() {
    local _src=${BASH_SOURCE[1]} _fn=${FUNCNAME[1]} _ln=${BASH_LINENO[0]} _a _tmp _out=
    for _a in "$@"; do
        if [[ $_a =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] && [[ -v $_a ]]; then
            _tmp="${_a}[@]"
            _out+="$_a - ${!_tmp} | "
        else
            _out+="$_a | "
        fi
    done
    echo "(${_src},${_fn}) ${_ln}: ${_out% | }"
}

ict() {
    local _i _a _tmp _out=
    for ((_i = ${#BASH_SOURCE[@]} - 2; _i >= 0; _i--)); do
        echo -n "(${BASH_SOURCE[$_i + 1]},${FUNCNAME[$_i + 1]}) ${BASH_LINENO[$_i]}: "
    done
    for _a in "$@"; do
        if [[ $_a =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] && [[ -v $_a ]]; then
            _tmp="${_a}[@]"
            _out+="$_a - ${!_tmp} | "
        else
            _out+="$_a | "
        fi
    done
    echo "${_out% | }"
}
