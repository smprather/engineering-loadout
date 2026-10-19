#!/bin/bash
# 3-column layout: left panes | active pane (full height) | right panes
# If total panes is even, bottom-right pane gets 2x height.
#
# Modes:
#   (default)        layout 6 -- active pane centered; the other panes split
#                    across the full-height left and right columns.
#                    Column widths 30/40/30.
#   --left-last, 7   layout 7 -- active pane centered, the previously active
#                    pane (the 2nd most recently used, tmux's pane_last)
#                    alone in the full-height left column, and ALL remaining
#                    panes stacked down the right column. Widths 35/35/30.

MODE=classic
case "${1:-}" in
    "")            MODE=classic   ;;
    --left-last|7) MODE=left-last ;;
    *)
        tmux display-message "3col layout: unknown mode '$1'"
        exit 0
        ;;
esac

W=$(tmux display-message -p '#{window_width}')
H=$(tmux display-message -p '#{window_height}')
active=$(tmux display-message -p '#{pane_id}')

# Snapshot the pane list once: pane ids in window pane-list order, plus
# whichever pane carries pane_last. tmux remembers exactly ONE previous pane
# per window and marks it with pane_last, so the active pane is the most
# recently used and pane_last is the 2nd most recently used -- which is what
# layout 7 wants on the left. pane_last is 0 on every pane in a window built
# from `split-window -d` splits, where the active pane never changed.
panes=()
last_pane=""
while read -r id is_last; do
    panes+=("$id")
    [[ "$is_last" == 1 ]] && last_pane="$id"
done < <(tmux list-panes -F '#{pane_id} #{pane_last}')
n=${#panes[@]}

if (( n < 3 )); then
    tmux display-message "Need at least 3 panes for 3-column layout"
    exit 0
fi

# Move a pane to a given index in the window's pane list. tmux select-layout
# assigns panes to layout cells positionally (pane list order maps to
# depth-first cell order), and swap-pane trades the two panes' positions in
# that list, so swap and mirror the same exchange in "panes".
move_to_index() {
    local want=$1 idx=$2 i
    [[ -z "$want" ]] && return
    [[ "${panes[$idx]}" == "$want" ]] && return
    for (( i=0; i<n; i++ )); do
        [[ "${panes[$i]}" == "$want" ]] && break
    done
    tmux swap-pane -d -s "$want" -t "${panes[$idx]}"
    panes[$i]="${panes[$idx]}"
    panes[$idx]="$want"
}

if [[ "$MODE" == left-last ]]; then
    # Left column: the 2nd most recently used pane, alone and full height.
    # Fall back to the first non-active pane when no pane_last is recorded.
    left_pane="$last_pane"
    [[ "$left_pane" == "$active" ]] && left_pane=""
    if [[ -z "$left_pane" ]]; then
        for (( i=0; i<n; i++ )); do
            [[ "${panes[$i]}" != "$active" ]] && left_pane="${panes[$i]}" && break
        done
    fi
    move_to_index "$left_pane" 0
    move_to_index "$active"    1

    n_left=1
    n_right=$(( n - 2 ))
else
    n_right=$(( (n - 1) / 2 ))
    n_left=$(( n - 1 - n_right ))

    move_to_index "$active" "$n_left"
fi

# Column widths.
usable_w=$(( W - 2 ))  # 2 column separators
if [[ "$MODE" == left-last ]]; then
    # 35/35/30: the two single panes take the first two slices, the stack the rest.
    left_w=$(( usable_w * 35 / 100 ))
    center_w=$(( usable_w * 35 / 100 ))
    right_w=$(( usable_w - left_w - center_w ))
else
    # 30/40/30: center 40%, sides split the rest.
    center_w=$(( usable_w * 40 / 100 ))
    side_w=$(( usable_w - center_w ))
    left_w=$(( side_w / 2 ))
    right_w=$(( side_w - left_w ))
fi

left_x=0
center_x=$(( left_w + 1 ))
right_x=$(( center_x + center_w + 1 ))

# Even total? Bottom-right pane gets 2x height
double_last=$(( n % 2 == 0 ? 1 : 0 ))

# Build a vertical column layout spec.
# Args: col_width col_x n_panes double_last start_pane_num
build_col() {
    local cw=$1 cx=$2 np=$3 dbl=$4 sp=$5

    if (( np == 1 )); then
        echo "${cw}x${H},${cx},0,${sp}"
        return
    fi

    local seps=$(( np - 1 ))
    local uh=$(( H - seps ))
    local slots=$np
    (( dbl )) && slots=$(( np + 1 ))
    local unit=$(( uh / slots ))
    local leftover=$(( uh - unit * slots ))

    local result="${cw}x${H},${cx},0["
    local y=0
    for (( i=0; i<np; i++ )); do
        (( i > 0 )) && result+=","
        local ph=$unit
        if (( i == np - 1 )); then
            (( dbl )) && ph=$(( unit * 2 + leftover )) || ph=$(( unit + leftover ))
        fi
        result+="${cw}x${ph},${cx},${y},$(( sp + i ))"
        y=$(( y + ph + 1 ))
    done
    result+="]"
    echo "$result"
}

left_spec=$(build_col $left_w $left_x $n_left 0 0)
center_spec="${center_w}x${H},${center_x},0,${n_left}"
right_spec=$(build_col $right_w $right_x $n_right $double_last $(( n_left + 1 )))

layout="${W}x${H},0,0{${left_spec},${center_spec},${right_spec}}"

# Compute tmux layout checksum (required for select-layout)
csum=0
for (( i=0; i<${#layout}; i++ )); do
    ch=$(printf '%d' "'${layout:$i:1}")
    csum=$(( (csum >> 1) + ((csum & 1) << 15) + ch ))
    csum=$(( csum & 0xFFFF ))
done

tmux select-layout "$(printf '%04x' $csum),${layout}"
tmux select-pane -t "$active"
