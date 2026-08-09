# Loadout zsh config -- zsh-ONLY LOADOUT_CFG_* preferences.
#
# The shared defaults are NOT duplicated here. envs/zsh/zshrc sources
# envs/bash/global/config.sh directly, so every LOADOUT_CFG_* the bash env
# defines already applies to zsh with the same value, and a user who overrides
# one in envs/bash/user/config.sh changes both shells at once. Adding a copy
# here would create a second source of truth that silently drifts.
#
# Only variables that exist BECAUSE the shell is zsh belong in this file.
#
# Override any of these in ~/.config/zsh/user/config.zsh.

# Full path to a preferred zsh binary; global/zshrc re-execs into it at startup
# when set, executable, and different from the running shell. The bash analogue
# is LOADOUT_CFG_PREFERRED_BASH.
: "${LOADOUT_CFG_PREFERRED_ZSH:=}"
export LOADOUT_CFG_PREFERRED_ZSH

# Run compinit (zsh's completion system) at startup. It is the single most
# expensive part of zsh startup on a slow/networked filesystem, so it gets its
# own switch; the bash env has no equivalent because bash-completion is sourced
# unconditionally there.
: "${LOADOUT_CFG_ZSH_ENABLE_COMPLETION:=1}"
export LOADOUT_CFG_ZSH_ENABLE_COMPLETION

# Load the BASH-format completion scripts under envs/bash/global/completions/
# via zsh's bashcompinit bridge. Off by default: bashcompinit is a compatibility
# shim, and a bash completion function that reaches for COMP_WORDS internals can
# misbehave under it. The natively-generated completions (uv, ruff, ty) and
# zsh's own _* functions are loaded regardless of this setting.
: "${LOADOUT_CFG_ZSH_ENABLE_BASHCOMPINIT:=0}"
export LOADOUT_CFG_ZSH_ENABLE_BASHCOMPINIT
