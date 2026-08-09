# zsh key bindings. Sourced from global/zshrc (interactive only).
#
# TRACKS envs/bash/global/keybinds.sh. bash configures GNU readline with
# `bind 'set ...'`; zsh has its own line editor (zle), so the mechanism differs
# while the resulting behaviour is meant to match.

# Emacs keymap, matching bash's readline default. Without this, zsh picks the
# keymap from $EDITOR -- so a user with EDITOR=vim silently gets vi bindings in
# zsh and emacs bindings in bash, on the same machine.
bindkey -e

# --- history search on the arrow keys ----------------------------------------
# bash: history-search-backward / -forward, which search on what is already
# typed. zsh's history-beginning-search-* is the same behaviour.
bindkey '^[[A' history-beginning-search-backward
bindkey '^[[B' history-beginning-search-forward
# Application-mode variants, which tmux and most modern terminals send.
bindkey '^[OA' history-beginning-search-backward
bindkey '^[OB' history-beginning-search-forward

# --- completion cycling -------------------------------------------------------
# bash binds TAB to menu-complete and Shift-Tab to menu-complete-backward.
bindkey '^I'   complete-word
bindkey '^[[Z' reverse-menu-complete

# --- word-wise movement -------------------------------------------------------
bindkey '^[[1;5D' backward-word
bindkey '^[[1;5C' forward-word
bindkey '^[[5D'   backward-word
bindkey '^[[5C'   forward-word

# --- Home / End / Delete ------------------------------------------------------
# zsh's defaults depend on terminfo being right, which it frequently is not on
# a farm node with an unusual TERM. Bind the sequences directly.
bindkey '^[[H'  beginning-of-line
bindkey '^[[F'  end-of-line
bindkey '^[[1~' beginning-of-line
bindkey '^[[4~' end-of-line
bindkey '^[[3~' delete-char

# --- completion behaviour (bash's readline `set` options) ---------------------
# bash: `set show-all-if-ambiguous on` + `menu-complete-display-prefix on` --
# complete the common prefix on the first TAB, list/cycle on the second.
setopt AUTO_LIST AUTO_MENU NO_LIST_BEEP
# bash: `set match-hidden-files off` -- do not offer dotfiles unless asked.
# (This was added there because .snapshot dirs kept showing up.)
unsetopt GLOB_DOTS
# bash: `set completion-query-items 0` + `page-completions off` -- never ask
# "display all N possibilities?", never page the list.
LISTMAX=0
unsetopt ALWAYS_LAST_PROMPT
# Case-insensitive and partial-word completion, closest to bash-completion's
# behaviour with the loadout's settings.
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}' 'r:|[._-]=* r:|=*'
zstyle ':completion:*' menu select
zstyle ':completion:*' list-colors ''

# Do NOT bind ^J or ^K to a completion widget. ^J IS newline: binding it makes
# typed-ahead Enter (buffered while a long command runs) trigger completion
# instead of accepting the line, so the Enter looks swallowed. The bash keybinds
# file carries the same warning for the same reason.
