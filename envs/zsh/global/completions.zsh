# zsh completion setup. Sourced from global/zshrc (interactive only).
#
# TRACKS the ### Completions ### block in envs/bash/global/bashrc.
#
# zsh has the easier job of the three shells: it has a real completion system,
# and every modern bundled tool can generate a native zsh script. The only
# awkward part is the loadout's own completions under
# envs/bash/global/completions/*.bash, which are bash-format.

# --- fpath: the zsh function library ------------------------------------------
# Dynamic modules (zsh/regex, zsh/pcre, ...) ship via runtime/zsh.tar.bz2 to
# <root>/lib/zsh; the shell functions (compinit, add-zsh-hook, the _* completion
# functions) via the same archive to <root>/share/zsh. The BINARY's built-in
# fpath and module_path both point at the build prefix, which is gone -- so both
# have to be repointed at the installed tree, honouring the shared prefix.
_zsh_root="${LOADOUT_CFG_SHARED_PREFIX:-$HOME/.local}"
_zsh_share="${LOADOUT_CFG_SHARED_PREFIX:+$LOADOUT_CFG_SHARED_PREFIX/share/zsh}"
_zsh_share="${_zsh_share:-$HOME/.local/share/zsh}"
_zsh_module_dir="$_zsh_root/lib/zsh/$ZSH_VERSION"
if [[ -d "$_zsh_module_dir" ]]; then
    module_path=("$_zsh_module_dir" $module_path)
fi

_zsh_fns_ok=0
_zsh_extra_fpath=()
# env-owned completions (the loadout ships _wezterm here).
if [[ -d "$ZSH_CONFIG_ROOT_DIR/site-functions" ]]; then
    _zsh_extra_fpath+=("$ZSH_CONFIG_ROOT_DIR/site-functions")
fi
if [[ -d "$_zsh_share/$ZSH_VERSION/functions" ]]; then
    _zsh_extra_fpath+=("$_zsh_share/site-functions" "$_zsh_share/$ZSH_VERSION/functions")
    _zsh_fns_ok=1
fi
if (( ${#_zsh_extra_fpath[@]} )); then
    fpath=("${_zsh_extra_fpath[@]}" $fpath)
fi

# --- the completion system ----------------------------------------------------
# The dump is cached per zsh VERSION, because its format is version-specific and
# a stale dump from another version fails in confusing ways. -u skips the
# insecure-directory check: the bundled function tree is group-writable on a
# shared install, which is expected, not a compromise.
if is_truthy "${LOADOUT_CFG_ZSH_ENABLE_COMPLETION:-1}"; then
    _zsh_cache="${XDG_CACHE_HOME:-$HOME/.cache}/zsh"
    [[ -d "$_zsh_cache" ]] || mkdir -p "$_zsh_cache" 2>/dev/null
    if autoload -Uz +X compinit 2>/dev/null; then
        compinit -u -d "$_zsh_cache/zcompdump-$ZSH_VERSION"

        # Native zsh completions from the tools that can generate them. The bash
        # env does the same with `generate-shell-completion bash`.
        for _cmd in uv ruff ty; do
            if command -v $_cmd >/dev/null 2>&1; then
                eval "$($_cmd generate-shell-completion zsh 2>/dev/null)" 2>/dev/null
            fi
        done

        # The loadout's own completions are BASH-format (they live in
        # envs/bash/global/completions/*.bash and are shared with the bash env).
        # bashcompinit bridges them, but it is a compatibility shim and a
        # completion that reaches into COMP_WORDS internals can misbehave under
        # it -- so this is opt-in, unlike everything above.
        if is_truthy "${LOADOUT_CFG_ZSH_ENABLE_BASHCOMPINIT:-0}"; then
            if autoload -Uz +X bashcompinit 2>/dev/null; then
                bashcompinit
                for _layer in global corp site team project user; do
                    for _comp_file in "$BASH_CONFIG_ROOT_DIR/$_layer"/completions/*.bash(N); do
                        source_if_exists "$_comp_file"
                    done
                done
            fi
        fi
    fi
fi

# --- tool integrations that need add-zsh-hook ---------------------------------
# starship/zoxide/fzf zsh init all register precmd/preexec hooks, which need
# add-zsh-hook from the function library -- hence the _zsh_fns_ok gate. Unlike
# tcsh, ALL THREE have real zsh support upstream, so zsh gets the full set.
if (( _zsh_fns_ok )); then
    is_truthy "${LOADOUT_CFG_ENABLE_ZOXIDE:-0}" && command -v zoxide >/dev/null 2>&1 && {
        eval "$(zoxide init zsh)"
        # Every zoxide jump funnels through __zoxide_cd, whose generated body is
        # `builtin cd -- "$@"`. In bash that skips the listing, so the bash env
        # overrides it. Here the listing is on the chpwd HOOK, which builtin cd
        # still fires -- so no override is needed and none is added.
    }
    if is_truthy "${LOADOUT_CFG_ENABLE_FZF:-0}" && command -v fzf >/dev/null 2>&1; then
        # Same preview configuration as the bash env, so Ctrl-T looks identical
        # in both shells. _bat_exec is set by global/zshrc before this runs.
        if [[ -n ${_bat_exec:-} ]]; then
            export FZF_CTRL_T_OPTS="--walker-skip .git,.snapshot --preview 'bat -n --color=always {}' --bind 'ctrl-/:change-preview-window(down|hidden|)'"
        else
            export FZF_CTRL_T_OPTS="--walker-skip .git,.snapshot --preview 'cat {}' --bind 'ctrl-/:change-preview-window(down|hidden|)'"
        fi
        eval "$(fzf --zsh)"
    fi
fi

unset _zsh_root _zsh_share _zsh_module_dir _zsh_cache _cmd _layer _comp_file
unset _zsh_extra_fpath
