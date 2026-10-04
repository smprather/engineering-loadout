#!/bin/bash
# tmux-popin.sh  (helper; bind manually if wanted, e.g. prefix + C-i)
#
# Reverse of tmux-popout.sh. Run from inside the pop-out window: close the
# whole window (all its shells) and return focus to the source pane, which
# never moved.
#
# NOTE: prefix+C-i may arrive as prefix+Tab on terminals without extended-keys
# support, since Ctrl-i and Tab share byte 0x09.
set -euo pipefail

cur_win=$(tmux display-message -p '#{window_id}')
src_pane=$(tmux show -w -v -t "$cur_win" @popout_src_pane 2>/dev/null || true)
snap=$(tmux show -w -v -t "$cur_win" @popout_snap 2>/dev/null || true)

if [[ -z "$src_pane" ]]; then
    tmux display-message "pop-in: no pop-out state on this window"
    exit 0
fi

# Remove the temp state-snapshot rcfile, if pop-out made one. The containing
# dir is private mktemp state; rmdir fails harmlessly if the user changed it.
if [[ -n "$snap" ]]; then
    rm -f "$snap" "${snap}.part"
    rmdir "$(dirname -- "$snap")" 2>/dev/null || true
fi

# Resolve the source pane's window BEFORE we kill anything, if it still exists.
src_win=""
if tmux list-panes -a -F '#{pane_id}' | grep -qx "$src_pane"; then
    src_win=$(tmux display-message -p -t "$src_pane" '#{window_id}')
fi

# Close the pop-out window and everything in it.
tmux kill-window -t "$cur_win"

# Return to the source pane if it is still around.
if [[ -n "$src_win" ]]; then
    tmux select-window -t "$src_win"
    tmux select-pane   -t "$src_pane"
fi
