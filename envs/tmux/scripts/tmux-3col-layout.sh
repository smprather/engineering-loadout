#!/bin/bash
# 3-column layout: left panes | active pane (full height) | right panes
# If total panes is even, bottom-right pane gets 2x height.

W=$(tmux display-message -p '#{window_width}')
H=$(tmux display-message -p '#{window_height}')
active=$(tmux display-message -p '#{pane_id}')
mapfile -t panes < <(tmux list-panes -F '#{pane_id}')
n=${#panes[@]}

if (( n < 3 )); then
    tmux display-message "Need at least 3 panes for 3-column layout"
    exit 0
fi

# Find active pane position and swap it to the center of the pane list.
# tmux select-layout assigns panes to layout cells positionally (pane list
# order maps to depth-first cell order), so we need the active pane at
# position n_left in the list for it to land in the center column.
for (( i=0; i<n; i++ )); do
    [[ "${panes[$i]}" == "$active" ]] && active_pos=$i && break
done

n_right=$(( (n - 1) / 2 ))
n_left=$(( n - 1 - n_right ))

if (( active_pos != n_left )); then
    tmux swap-pane -d -s "$active" -t "${panes[$n_left]}"
fi

# Column widths: center 40%, sides split the rest
usable_w=$(( W - 2 ))  # 2 column separators
center_w=$(( usable_w * 40 / 100 ))
side_w=$(( usable_w - center_w ))
left_w=$(( side_w / 2 ))
right_w=$(( side_w - left_w ))

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
