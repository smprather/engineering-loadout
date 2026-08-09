# tcsh key bindings. Sourced from global/tcshrc (interactive only).
#
# TRACKS envs/bash/global/keybinds.sh. tcsh uses its own editor (not GNU
# readline), so the mechanism differs -- `bindkey` and shell variables here,
# `bind 'set ...'` there -- but the resulting behaviour is meant to match.
#
# The bash file's readline-only settings have no tcsh analogue and are not
# faked: colored-completion-prefix, colored-stats, page-completions,
# completion-query-items and enable-bracketed-paste are readline internals.
# tcsh's equivalents live in global/tcshrc as `set color`, `set autolist`,
# `set complete = enhance` and `set nobeep`.

# History search on Up/Down using what has already been typed, matching
# bash's history-search-backward / history-search-forward. tcsh's
# history-search-backward is prefix-based, which is the same behaviour.
bindkey -k up   history-search-backward
bindkey -k down history-search-forward
# The same, for terminals that send the application-mode sequences instead
# (tmux and most modern emulators do, depending on the mode).
bindkey "\033[A" history-search-backward
bindkey "\033[B" history-search-forward
bindkey "\033OA" history-search-backward
bindkey "\033OB" history-search-forward

# Tab cycles forward through completions, Shift-Tab backward -- the same pairing
# the bash env binds to menu-complete / menu-complete-backward.
bindkey "^I"    complete-word-fwd
bindkey "\033[Z" complete-word-back

# Word-wise movement with Ctrl+Left / Ctrl+Right, which tcsh does not bind by
# default. Both the CSI and the xterm-modifier forms, since terminals disagree.
bindkey "\033[1;5D" backward-word
bindkey "\033[1;5C" forward-word
bindkey "\033[5D"   backward-word
bindkey "\033[5C"   forward-word

# Home / End / Delete. tcsh gets these wrong on several terminfo entries; bind
# the sequences directly so they work the same everywhere.
bindkey "\033[H"  beginning-of-line
bindkey "\033[F"  end-of-line
bindkey "\033[1~" beginning-of-line
bindkey "\033[4~" end-of-line
bindkey "\033[3~" delete-char

# Do NOT bind ^J or ^K here. ^J IS newline: binding it to a completion verb makes
# typed-ahead Enter (buffered while a long command runs) trigger completion
# instead of accepting the line, so the Enter looks like it was swallowed. The
# bash keybinds file carries the same warning for the same reason.
