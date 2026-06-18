# shellcheck shell=bash
# GNU readline key bindings. Sourced from global/bashrc (interactive only).

bind 'set colored-completion-prefix on'
bind 'set colored-stats off'
bind 'set bell-style none'
# Disable check for too many completions, and paging the results.
# This is so that I can use a 2nd TAB to cycle through the possible results.
bind 'set completion-query-items 0'
bind 'set page-completions off'
# Prevent pasted text from being highlighted in reverse text
bind 'set enable-bracketed-paste off'
# If there are multiple matches for completion, Tab should cycle through them
bind 'TAB:menu-complete'
# Display a list of the matching files
bind "set show-all-if-ambiguous on"
# Perform partial (common) completion on the first Tab press, only start
# cycling full results on the second Tab press (from bash version 5)
bind "set menu-complete-display-prefix on"
# Make dot-files not tab-complete visible. I was getting .snapshot hits.
bind 'set match-hidden-files off'
# Cycle through history based on characters already typed on the line
bind '"\e[A":history-search-backward'
bind '"\e[B":history-search-forward'
bind "set colored-completion-prefix on"
# Cycle completions: Tab forward (above), Shift-Tab backward. Do NOT bind
# \C-j/\C-k here: \C-j IS newline (\n), so binding it to menu-complete makes
# typed-ahead Enter (buffered as \n in cooked mode while a long command runs)
# trigger completion instead of accept-line -- the Enter looks "not accepted".
bind '"\e[Z":menu-complete-backward'
