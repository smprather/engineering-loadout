#!/bin/bash
# tmux-popout.sh  (helper; bind manually if wanted, e.g. prefix + C-o)
#
# Open a NEW window of shells that inherit the active pane's launch-time state
# (cwd + exported environment), then apply the 3-column layout (prefix+6).
# The active pane STAYS PUT -- nothing is broken out or moved.
#
# State copy always reads cwd from tmux and exported env from
# /proc/<pane_pid>/environ. By default it also tries to snapshot full bash state
# by sending a hidden command to the source pane; if that fails, the new shells
# fall back to `bash --norc` with cwd + env only. The source pane is never moved.
set -euo pipefail

NPANES=5           # total shells in the pop-out window
CAPTURE_STATE=1    # 1: clone the source shell's FULL state (Starship prompt,
                   #    aliases, functions) by running shell_state_export inside
                   #    it via a hidden send-keys; 0: plain fast `bash --norc`.

# --- source pane (left untouched) --------------------------------------------
src_pane=$(tmux display-message -p '#{pane_id}')
src_pid=$(tmux display-message -p '#{pane_pid}')
src_cwd=$(tmux display-message -p '#{pane_current_path}')
src_win_name=$(tmux display-message -p '#{window_name}')

# --- copy the source shell's exported environment ----------------------------
# Skip tmux's own vars (the new panes must get correct ones from the server)
# and the ones bash manages itself on startup.
eargs=()
if [[ -r "/proc/$src_pid/environ" ]]; then
    while IFS= read -r -d '' kv; do
        case "$kv" in
            TMUX=*|TMUX_PANE=*|SHLVL=*|_=*) continue ;;
            *=*) eargs+=(-e "$kv") ;;
        esac
    done < "/proc/$src_pid/environ"
fi

# --- optionally snapshot the source shell's full interactive state -----------
# shell_state_export must run INSIDE the source pane -- its aliases/functions/
# DEBUG-trap live in that shell's memory, unreadable from /proc. We inject it
# with send-keys, hidden behind the alternate screen buffer (1049h/1049l) so the
# pane shows nothing, with a leading space to keep it out of history. An atomic
# rename signals "snapshot ready". If the pane isn't at a bash prompt, or
# shell_state_export isn't defined there, no file lands and we fall back.
snap=""
if (( CAPTURE_STATE )) && \
   [[ "$(tmux display-message -p -t "$src_pane" '#{pane_current_command}')" == bash ]]; then
    snap_dir=$(mktemp -d "${TMPDIR:-/tmp}/tmux-popout.XXXXXX")
    snap="$snap_dir/snapshot.rc"
    printf -v snap_part_q '%q' "${snap}.part"
    printf -v snap_q '%q' "$snap"
    inj=" printf '\\033[?1049h'; shell_state_export $snap_part_q >/dev/null 2>&1 && mv -f $snap_part_q $snap_q; printf '\\033[?1049l'"
    tmux send-keys -t "$src_pane" -l "$inj"
    tmux send-keys -t "$src_pane" Enter
    # Wait up to ~2s for the atomic rename; otherwise fall back to --norc.
    for _ in $(seq 1 40); do [[ -f "$snap" ]] && break; sleep 0.05; done
    if [[ ! -f "$snap" ]]; then
        rm -f "${snap}.part"
        rmdir "$snap_dir" 2>/dev/null || true
        snap=""
    fi
fi

if [[ -n "$snap" ]]; then
    shell_cmd=(bash --rcfile "$snap")   # full-state clone
else
    shell_cmd=(bash --norc)             # fast, env+cwd only
fi

# --- build the pop-out window ------------------------------------------------
# First shell = new window (no -d: switch to it). Rest are splits (-d: keep the
# first pane active so the layout formatter centers it).
first=$(tmux new-window -P -F '#{pane_id}' -n "$src_win_name" -c "$src_cwd" "${eargs[@]}" "${shell_cmd[@]}")
new_win=$(tmux display-message -p -t "$first" '#{window_id}')
# Keep the launcher's name: without this, automatic-rename resets it to "bash".
tmux set -w -t "$new_win" automatic-rename off
new_panes=("$first")
for (( i=1; i<NPANES; i++ )); do
    p=$(tmux split-window -d -P -F '#{pane_id}' -t "$first" -c "$src_cwd" "${eargs[@]}" "${shell_cmd[@]}")
    new_panes+=("$p")
done

# --- 3-column layout, centered on the first pane -----------------------------
# The formatter keys off $TMUX_PANE; ours still points at the (untouched)
# source pane, so override it to a pane in the new window.
tmux select-pane -t "$first"
TMUX_PANE="$first" bash ~/.config/tmux/tmux-3col-layout.sh

# --- persist reverse-state (window-scoped; dies with the window) -------------
tmux set -w -t "$new_win" @popout_src_pane  "$src_pane"
tmux set -w -t "$new_win" @popout_new_panes "${new_panes[*]}"
tmux set -w -t "$new_win" @popout_snap      "$snap"   # temp rcfile to clean up on pop-in
