# WezTerm shell integration for zsh: OSC 133 semantic zones + OSC 7 cwd.
#
# TRACKS the wezterm block in envs/bash/global/bashrc, which sources the
# vendored envs/bash/global/wezterm/wezterm.sh. That script is the
# BASH-PREEXEC variant -- it contains no ZSH_VERSION path at all -- so sourcing
# it here would install a bash-preexec driver into zsh and achieve nothing.
#
# zsh needs no preexec framework: precmd and preexec are native hooks. So this
# implements the same protocol directly, which is both smaller and more robust
# than the bash path. zsh therefore gets the FULL integration (133 zones + 7
# cwd); the tcsh env can only manage OSC 7, because csh has no per-command hook.
#
# Never sourced from /etc -- same rule as the bash env. This file ships with the
# loadout in user-writable space.

# Off-WezTerm terminals: emitting OSC 133 is harmless (unknown OSC sequences are
# ignored), and several other terminals consume them -- but respect the same
# skip variables the vendored bash script honours, so a user who has turned a
# piece off for bash gets the same result here.
_loadout_wz_zones=1
_loadout_wz_cwd=1
[[ -n ${WEZTERM_SHELL_SKIP_SEMANTIC_ZONES:-} ]] && _loadout_wz_zones=0
[[ -n ${WEZTERM_SHELL_SKIP_CWD:-} ]] && _loadout_wz_cwd=0
# A dumb or linux console cannot render any of this; the vendored script
# self-skips on the same two TERM values.
case ${TERM:-} in
    dumb | linux) _loadout_wz_zones=0; _loadout_wz_cwd=0 ;;
esac

# OSC 7: report the cwd, so a new tab/pane opens in the same directory.
# Registered on chpwd (fires for cd/pushd/popd/AUTO_CD) AND precmd, because a
# shell that starts in a directory never fires chpwd for it.
loadout_wezterm_osc7() {
    (( _loadout_wz_cwd )) || return 0
    printf '\033]7;file://%s%s\033\\' "${HOST:-$(hostname)}" "$PWD"
}

# OSC 133: mark where the prompt starts (A), where the typed command starts (B),
# where output starts (C) and where it ends with its exit status (D). This is
# what lets the terminal jump between prompts and select a command's output.
loadout_wezterm_precmd() {
    local _rc=$?
    (( _loadout_wz_zones )) && printf '\033]133;D;%s\033\\\033]133;A\033\\' "$_rc"
    loadout_wezterm_osc7
    return $_rc
}

loadout_wezterm_preexec() {
    (( _loadout_wz_zones )) || return 0
    printf '\033]133;C\033\\'
}

loadout_add_zsh_hook precmd  loadout_wezterm_precmd
loadout_add_zsh_hook preexec loadout_wezterm_preexec
loadout_add_zsh_hook chpwd   loadout_wezterm_osc7

# The B marker (end of prompt / start of user input) belongs at the very end of
# the prompt string, so it is appended rather than hooked. Doing it here rather
# than inside the prompt block keeps every OSC 133 emitter in one file.
if (( _loadout_wz_zones )); then
    PROMPT="${PROMPT}%{$(printf '\033]133;B\033\\')%}"
fi
