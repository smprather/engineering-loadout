# shellcheck shell=bash
# Interactive aliases + small command-shortcut functions (bq/vnc/killvnc).
# Sourced from global/bashrc. Pure definitions -- order-independent.

### Navigation ###
alias cd-='cd -'
alias bcd="builtin cd"
alias b='cd ..'
alias bb='cd ../..'
alias bbb='cd ../../..'
alias bbbb='cd ../../../..'
alias bbbbb='cd ../../../../..'
alias bbbbbb='cd ../../../../../..'
alias bbbbbbb='cd ../../../../../../..'
alias bbbbbbbb='cd ../../../../../../../..'
alias bbbbbbbbb='cd ../../../../../../../../..'
alias bbbbbbbbbb='cd ../../../../../../../../../..'
loadout_cd_recent_dir() {
    local index=${1:-1}
    local target

    target=$(
        find . -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' 2>/dev/null |
            sort -n |
            tail -n "$index" |
            head -n 1 |
            cut -d' ' -f2-
    )
    [[ -n $target ]] || return 1
    # Deliberately the cd FUNCTION (global/bashrc), not `builtin cd`: every
    # directory change is expected to be followed by an ls, and the builtin
    # skips that. `find` always emits a ./-prefixed path, so no `--` is needed
    # (the wrapper does not take one).
    cd "$target" || return
}
cdd() { loadout_cd_recent_dir 1; }
cddd() { loadout_cd_recent_dir 2; }
cdddd() { loadout_cd_recent_dir 3; }
cddddd() { loadout_cd_recent_dir 4; }
cdddddd() { loadout_cd_recent_dir 5; }
alias p='pwd | tee "/tmp/p_dir.$USER"'
alias cdp='cd "$(cat "/tmp/p_dir.$USER")"'

### Listing ###
alias sl='ls'
alias ll='ls'
alias lr='ls'
alias rl='ls'
alias lh='human_readable=1 ls'
alias la='list_all=1 ls'
alias lg='show_group=1 ls'
alias lah='human_readable=1 list_all=1 ls'
alias lha='lah'
alias lsg='lg'
tree() {
    case ${LOADOUT_CFG_PREFERRED_LS:-} in
        eza | lsd)
            ls -T "$@"
            ;;
        *)
            if command -v tree >/dev/null 2>&1; then
                command tree "$@"
            else
                /bin/ls -R "$@"
            fi
            ;;
    esac
}

### Editing ###
vi() { "${LOADOUT_CFG_PREFERRED_VI:-nvim}" "$@"; }
vim() { vi "$@"; }
vic() { "${LOADOUT_CFG_PREFERRED_VI:-nvim}" --clean -u "$HOME/.vimrc" "$@"; }
vii() {
    local target
    target=$(
        find . -mindepth 1 -maxdepth 1 -type f -printf '%T@ %p\n' 2>/dev/null |
            sort -n |
            tail -n 1 |
            cut -d' ' -f2-
    )
    [[ -n $target ]] || return 1
    vi "$target"
}
vimdiff() { NVIM_WRAPPER_OPTS='-d -R' "${LOADOUT_CFG_PREFERRED_VI:-nvim}" "$@"; }
vid() { "${LOADOUT_CFG_PREFERRED_VI:-nvim}" -d "$@"; }
ovi() { command vim "$@"; }
fls() {
    local target
    target=$(fzf) || return
    ls "$target"
}
fvi() {
    local target
    target=$(fzf) || return
    vi "$target"
}
alias fcd="eval \$(__fzf_cd__) && ls"
fcat() {
    local target
    target=$(fzf) || return
    cat "$target"
}
alias v="nvim -n -R -"
alias wip='vim $HOME/wip.txt'
alias test_nvim='NVIM_APPNAME=test_nvim nvim_wrapper'
new() {
    [[ -n $1 ]] || return 1
    touch -- "$1"
    chmod +x -- "$1"
    vi "$1"
}

### Search ###
if command -v rg >&/dev/null; then
    g() {
        rg --smart-case --search-zip --hidden --no-ignore --glob='!*.snapshot*' "$@"
    }
    sg() {
        rg --smart-case --search-zip --hidden --no-ignore --glob='!*.snapshot*' --max-filesize=100K "$@"
    }
else
    g() {
        if [[ -t 0 ]]; then
            grep -r -i --color=auto --exclude-dir='.snapshot' "$@" .
        else
            grep -i --color=auto "$@"
        fi
    }
    sg() {
        if [[ -t 0 ]]; then
            grep -r -i -l --color=auto --exclude-dir='.snapshot' "$@" .
        else
            grep -i -l --color=auto "$@"
        fi
    }
fi
gv() { g -v "$@"; }
gf() { g -F "$@"; }
gpy() {
    if command -v rg >/dev/null 2>&1; then
        g --glob '*.py' --glob='!*.snapshot*' "$@"
    elif [[ -t 0 ]]; then
        grep -r -i --color=auto --include='*.py' --exclude-dir='.snapshot' "$@" .
    else
        grep -i --color=auto "$@"
    fi
}
gtcl() {
    if command -v rg >/dev/null 2>&1; then
        g --glob '*.tcl' --glob='!*.snapshot*' "$@"
    elif [[ -t 0 ]]; then
        grep -r -i --color=auto --include='*.tcl' --exclude-dir='.snapshot' "$@" .
    else
        grep -i --color=auto "$@"
    fi
}
# This makes grep run way faster. Though you should be using rg instead!
alias grep='LC_ALL=C grep'
if command -v fdfind >/dev/null; then
    loadout_find_uses_fd=1
    fd() { fdfind "$@"; }
    f() { fdfind --exclude .snapshot --unrestricted --full-path "$@"; }
elif command -v fd >/dev/null && fd --help | /bin/grep -q sharkdp; then
    loadout_find_uses_fd=1
    f() { fd --exclude .snapshot --unrestricted --full-path "$@"; }
else
    loadout_find_uses_fd=0
    f() { find . "$@"; }
fi
fc() {
    if [[ $loadout_find_uses_fd == 1 || $# -eq 0 ]]; then
        f "$@" | wc -l
    else
        find . -iname "*$1*" | wc -l
    fi
}
alias h='history | g'
alias hg='history | /bin/grep -i'
gah() {
    local history_files=(/run/user/*/bash_history.*)
    [[ -e ${history_files[0]} ]] || return 1
    if command -v rg >/dev/null 2>&1; then
        rg "$@" "${history_files[@]}" 2>/dev/null
    else
        grep -i --color=auto "$@" "${history_files[@]}" 2>/dev/null
    fi
}

### Git ###
ga() {
    if [[ -z "$1" ]]; then
        git add --all .
    else
        git add "$@"
    fi
    git status
}
alias gc='git commit'
alias gs='git status'
alias gp='git push'
alias gd='git d'
alias gr='git review'
gsp() {
    local stashed=0

    if ! git diff --quiet || ! git diff --cached --quiet; then
        git stash push || return
        stashed=1
    fi

    git pull || return
    if [[ $stashed == 1 ]]; then
        git stash pop
    fi
}

### System / utils ###
alias t='exec bash'
alias c='clear'
alias w='type -a'
alias ho='hostname -s'
alias d='date'
alias rm='rm -f'
alias mkdir='mkdir -p'
alias mdkir='mkdir'
alias rs='rsync --archive --info=progress2 --info=name0 --no-inc-recursive --exclude="*/.snapshot/"'
alias du='du --block-size=G -s * | sort -r -n -k 1'
alias dum='/bin/du --block-size=M -s * | sort -r -n -k 1'
unalias df 2>/dev/null || true
df() {
    if command -v colourify >/dev/null 2>&1; then
        colourify df --block-size=G "$@"
    else
        command df --block-size=G "$@"
    fi
}
pl() {
    if [[ $# -eq 0 ]]; then
        echo "$PATH" | tr ":" "\n" | nl
        return
    fi

    # Lower-case via tr, NOT ${var,,}: this file is sourced by envs/zsh too, and
    # ${var,,} is bash-4-only -- under zsh it is a parse error at call time
    # ("pl:8: bad substitution"), so pl was simply broken for every zsh user.
    local lower_entry lower_pattern
    echo "$PATH" | tr ":" "\n" | while IFS= read -r path_entry; do
        lower_entry=$(printf '%s' "$path_entry" | tr '[:upper:]' '[:lower:]')
        for pattern in "$@"; do
            lower_pattern=$(printf '%s' "$pattern" | tr '[:upper:]' '[:lower:]')
            case $lower_entry in
            *"$lower_pattern"*)
                printf '%s\n' "$path_entry"
                break
                ;;
            esac
        done
    done | nl
}
alias ncdu='ncdu --graph-style hash --color dark'
alias less='less --incsearch --use-color +X'
alias tx='tar -xvf'
alias tt='tar -tvf'
if command -v unpigz >/dev/null 2>&1; then
    alias gunzip='unpigz'
fi
if command -v pigz >/dev/null 2>&1; then
    alias gzip='pigz'
    alias gz='pigz'
fi
alias we='watchexec --clear --poll 500'
rlrt() {
    local root=${1:-.}
    find "$root" -type f -print0 |
        xargs -0 stat --format '%Y :%y %n' |
        sort -nr |
        cut -d: -f2- |
        head
}
alias gpw='chmod -R g+w'
alias gmw='chmod -R g-w'
a() {
    local alias_file="/tmp/alias.$$"
    alias | sort >"$alias_file"
    # `typeset -f`, not `declare -f`: identical in bash, and the only spelling
    # zsh understands (this file is sourced by envs/zsh too).
    typeset -f >>"$alias_file"
    vi "$alias_file"
    rm -f -- "$alias_file"
}
alias clean_bash='echo "/usr/bin/env --ignore-environment PATH=/bin HOME=$HOME USER=$(/bin/whoami) /bin/bash --rcfile ~/.clean.bashrc"'
alias vman="MANPAGER='nvim +Man\!' man"
st() { strace -o "/tmp/strace.$USER" -f -v -s 1000000 "$@"; }
alias sp1="set_prompt"
alias sp2="set_prompt include_host"
alias fsbm='fio --randrepeat=1 --ioengine=libaio --direct=0 --gtod_reduce=1 --name=test --bs=4k --iodepth=64 --readwrite=randrw --rwmixread=75 --size=4G --filename=./fio_test; rm ./fio_test'
# I was getting a weird completion failure for `x <tab>`. This is the work-around.
# `complete` is a bash builtin with no zsh equivalent, and this file is sourced
# by envs/zsh too -- gate it so zsh does not report an unknown command.
unalias x 2>/dev/null
[[ -n ${BASH_VERSION:-} ]] && complete -r x 2>/dev/null
x() { chmod +x -- "$@"; }
rp() {
    if [[ -n $1 ]]; then
        realpath "$1"
    else
        realpath .
    fi
}
if [[ -n $_bat_exec ]]; then
    loadout_bat_exec=$_bat_exec
    if [[ ${LOADOUT_CFG_PREFERRED_CAT:-bat} == "bat" ]]; then
        cat() { "$loadout_bat_exec" --paging=never "$@"; }
    fi
    catp() { "$loadout_bat_exec" "$@"; }
fi
lns() {
    # Assume deletion of any existing sym-link
    if [[ -n $2 ]]; then
        if [[ -L $2 ]]; then
            rm -f -- "$2"
        fi
    else
        local b
        b=$(basename -- "$1")
        if [[ -L $b ]]; then
            rm -f -- "$b"
        fi
    fi
    ln -s "$@"
}
latest() {
    local latest
    if [[ -e latest && ! -L latest ]]; then
        printf 'latest exists and is not a symlink\n' >&2
        return 1
    fi
    rm -f -- latest
    if [[ -n $1 ]]; then
        mkdir -p -- "$1"
        ln -s -- "$1" latest
        latest=$1
    else
        latest=$(
            find . -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' 2>/dev/null |
                sort -n |
                tail -n 1 |
                cut -d' ' -f2-
        )
        [[ -n $latest ]] || return 1
        ln -s -- "$latest" latest
    fi
    # cd function, not `builtin cd` -- see loadout_cd_recent_dir above.
    cd "$latest" || return
}

### Tmux ###
alias tl='tmux list-sessions'
alias ta='resize; tmux attach -d || tmux'
alias btopu='btop -u $(/bin/whoami)'
# shellcheck disable=SC2016
_tmux_get_window_cmd='TMUX_WINDOW=$(tmux display-message -p "#W")'

### EDA / LSF ###
alias invs='innovus -stylus'
alias vlts='voltus -stylus'
alias itcl="\$HOME/.local/lib/tcl/tclsh-wrapper/TclReadLine/TclReadLine.tcl"
alias ipy='ipython3'
alias pyprofile='python3 -m cProfile -s cumtime'
alias agrep="alias | g"
alias fdon="echo 'export FLEXLM_DIAGNOSTICS=3'; export FLEXLM_DIAGNOSTICS=3"
alias fdoff="echo 'unset FLEXLM_DIAGNOSTICS'; unset FLEXLM_DIAGNOSTICS"
alias mli='module list'
alias ms='module show'
alias ma='module avail'
my_total_cpu() {
    while true; do
        top -b -n 1 -u "$(/bin/whoami)" | awk 'NR>7 { sum += $9; } END { print sum; }'
        sleep 1
    done
}
pg() { command pgrep -u "$(/bin/whoami)" --full --list-full "$@"; }
pk() { pkill "$@"; }
pgrep() { command pgrep -f "$@"; }
pkill() { command pkill -f "$@"; }
alias bkillall='bkill -u $(/bin/whoami) 0'
alias bjobsv='export LSB_BJOBS_FORMAT="jobid:7 stat:5 user:12 queue:15 slots:3 proj_name:15 sla:15 exec_host:13 max_mem:12 pend_time:12 max_req_proc:12 mem"'
bq() {
    if [[ $1 == "-l" ]]; then
        bqueues -l "$@"
    else
        bqueues -u "$(/bin/whoami)" -o 'queue_name: status: njobs: pend: run:'
    fi
}
alias bqs="bq"
alias sbqueues='echo "QUEUE_NAME      PRIO STATUS          MAX JL/U JL/P JL/H NJOBS  PEND   RUN  SUSP  RSV PJOBS "; bqueues | grep hw_ | egrep "interactive|reg_batch|reg_user|cot|batch|biggermem|spot|reg_ci"'
alias sbq='sbqueues'

### VNC / X ###
xterm() {
    command xterm -bg black -fg white -fa HackNerdFontMono-Regular -fs 10 +sb "$@"
}
# Without args, start a VNC server. With args, be an alias for vncserver.
vnc() {
    if [[ -z $1 ]]; then
        vncserver -SecurityTypes None
    else
        vncserver "$@"
    fi
}
alias startvnc="vncserver -SecurityTypes None"
alias runvnc="startvnc"
alias stopvnc="vncserver -kill"
killvnc() {
    local max_display
    max_display=$(
        ps -ef | awk '
            /Xtigervnc|Xvnc/ && $0 !~ /awk/ {
                for (i=1; i<=NF; i++) {
                    if ($i ~ /^:[0-9]+/) {
                        gsub(":", "", $i)
                        print $i
                    }
                }
            }
        ' | sort -n | tail -1
    )
    if [[ -z "$max_display" ]]; then
        echo "No VNC sessions found."
        return 1
    fi
    echo "Killing VNC session :$max_display"
    if command -v vncserver >/dev/null 2>&1; then
        vncserver -kill :"$max_display"
    else
        pkill -f "X.*:$max_display"
    fi
}
