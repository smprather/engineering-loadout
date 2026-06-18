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
alias cdd='cd $(find * -maxdepth 0 -type d | xargs /bin/ls -drt1 | tail -n 1)'
alias cddd='cd `find * -maxdepth 0 -type d | xargs /bin/ls -drt1 | tail -n 2 | head -n 1`'
alias cdddd='cd `find * -maxdepth 0 -type d | xargs /bin/ls -drt1 | tail -n 3 | head -n 1`'
alias cddddd='cd `find * -maxdepth 0 -type d | xargs /bin/ls -drt1 | tail -n 4 | head -n 1`'
alias cdddddd='cd `find * -maxdepth 0 -type d | xargs /bin/ls -drt1 | tail -n 5 | head -n 1`'
alias p='pwd | tee "/tmp/p_dir.$USER"'
alias cdp='cd "$(cat "/tmp/p_dir.$USER")"'
cds() {
    eval "$(cd-surfer "$@")"
}

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
alias tree='ls -T'

### Editing ###
_vi=${LOADOUT_CFG_PREFERRED_VI}
alias vi="$_vi"
alias vim="$_vi"
alias vic="$_vi --clean -u ~/.vimrc"
alias vii="$_vi \$(find * -maxdepth 0 -type f | xargs /bin/ls -drt1 | tail -n 1)"
alias vimdiff="NVIM_WRAPPER_OPTS='-d -R' $_vi"
alias vid="$_vi -d"
alias ovi='\vim'
alias fls="ls \$(fzf)"
alias fvi="$_vi \$(fzf)"
unset _vi
alias fcd="eval \$(__fzf_cd__) && ls"
alias fcat="cat \$(fzf)"
alias v="nvim -n -R -"
alias wip='vim $HOME/wip.txt'
alias test_nvim='NVIM_APPNAME=test_nvim nvim_wrapper'
new() {
    touch $1
    chmod +x $1
    vi $1
}

### Search ###
if command -v rg >&/dev/null; then
    g() {
        rg --smart-case --search-zip --hidden --no-ignore --glob='!*.snapshot*' "$@"
    }
    alias sg='rg --smart-case --search-zip --hidden --no-ignore --glob="!*.snapshot*" --max-filesize=100K'
    alias gv='g -v'
else
    g() {
        grep -r -i --color=auto --exclude-dir='.snapshot' "$@"
    }
    alias sg='g -l'
    alias gv='g -v'
fi
alias gf='g -F'
alias gpy='g --glob "*.py" --glob="!*.snapshot*"'
alias gtcl='g --glob "*.tcl" --glob="!*.snapshot*"'
# This makes grep run way faster. Though you should be using rg instead!
alias grep='LC_ALL=C grep'
if command -v fdfind >/dev/null; then
    alias fd="fdfind"
    alias f='fdfind --exclude .snapshot --unrestricted --full-path'
elif command -v fd >/dev/null && fd --help | /bin/grep -q sharkdp; then
    alias f='fd --exclude .snapshot --unrestricted --full-path'
else
    alias f='find .'
fi
fc() {
    fd --unrestricted --full-path $1 | wc -l
}
alias h='history | g'
alias hg='history | /bin/grep -i'
gah() {
    rg $* /run/user/*/bash_history.* 2>/dev/null
}

### Git ###
ga() {
    if [[ -z "$1" ]]; then
        git add --all .
    else
        git add $*
    fi
    git status
}
alias gc='git commit'
alias gs='git status'
alias gp='git push'
alias gd='git d'
alias gr='git review'
alias gsp='git stash; git pull; git stash pop'

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
alias df='colourify df --block-size=G'
pl() {
    if [[ $# -eq 0 ]]; then
        echo "$PATH" | tr ":" "\n" | nl
        return
    fi

    echo "$PATH" | tr ":" "\n" | while IFS= read -r path_entry; do
        for pattern in "$@"; do
            if [[ ${path_entry,,} == *${pattern,,}* ]]; then
                printf '%s\n' "$path_entry"
                break
            fi
        done
    done | nl
}
alias ncdu='ncdu --graph-style hash --color dark'
alias less='less --incsearch --use-color +X'
alias tx='tar -xvf'
alias tt='tar -tvf'
alias gunzip='unpigz'
alias gzip='pigz'
alias gz='pigz'
alias we='watchexec --clear --poll 500'
alias rlrt="find \$1 -type f -print0 | xargs -0 stat --format '%Y :%y %n' | sort -nr | cut -d: -f2- | head"
alias gpw='chmod -R g+w'
alias gmw='chmod -R g-w'
alias a="alias | sort > /tmp/alias.$$; declare -f >> /tmp/alias.$$; vi /tmp/alias.$$; rm /tmp/alias.$$"
alias clean_bash='echo "/usr/bin/env --ignore-environment PATH=/bin HOME=$HOME USER=$(/bin/whoami) /bin/bash --rcfile ~/.clean.bashrc"'
alias vman="MANPAGER='nvim +Man\!' man"
alias st="strace -o /tmp/strace.$USER -f -v -s 1000000"
alias sp1="set_prompt"
alias sp2="set_prompt include_host"
alias fsbm='fio --randrepeat=1 --ioengine=libaio --direct=0 --gtod_reduce=1 --name=test --bs=4k --iodepth=64 --readwrite=randrw --rwmixread=75 --size=4G --filename=./fio_test; rm ./fio_test'
# I was getting a weird completion failure for `x <tab>`. This is the work-around.
unalias x 2>/dev/null
complete -r x 2>/dev/null
x() { chmod +x -- "$@"; }
rp() { [[ -n "$1" ]] && realpath $1 || realpath .; }
if [[ -n $_bat_exec ]]; then
    alias cat='bat --paging=never'
    alias catp='bat'
fi
lns() {
    # Assume deletion of any existing sym-link
    if [[ -n $2 ]]; then
        if /bin/readlink $2 >/dev/null; then
            rm -f $2
        fi
    else
        local b=$(basename $1)
        if readlink $b >/dev/null; then
            rm -f $b
        fi
    fi
    ln -s "$@"
}
latest() {
    local latest
    rm -f latest
    if [[ -n $1 ]]; then
        mkdir -p $1
        ln -s $1 latest
        latest=$1
    else
        latest=$(command ls -1drt */ | tail -n 1)
        ln -s $latest latest
    fi
    cd $latest
}

### Tmux ###
alias tl='tmux list-sessions'
alias ta='resize; tmux attach -d || tmux'
alias btopu='btop -u $(/bin/whoami)'
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
alias my_total_cpu="while true; do top -b -n 1 -u \$(/bin/whoami) | awk 'NR>7 { sum += \$9; } END { print sum; }'; sleep 1; done"
alias pg='pgrep -u $(/bin/whoami) --full --list-full'
alias pk='pkill'
alias pgrep='pgrep -f'
alias pkill='pkill -f'
alias bkillall='bkill -u $(/bin/whoami) 0'
alias bjobsv='export LSB_BJOBS_FORMAT="jobid:7 stat:5 user:12 queue:15 slots:3 proj_name:15 sla:15 exec_host:13 max_mem:12 pend_time:12 max_req_proc:12 mem"'
bq() {
    [[ $1 == "-l" ]] && bqueues -l $* || bqueues -u $(whoami) -o 'queue_name: status: njobs: pend: run:'
}
alias bqs="bq"
alias sbqueues='echo "QUEUE_NAME      PRIO STATUS          MAX JL/U JL/P JL/H NJOBS  PEND   RUN  SUSP  RSV PJOBS "; bqueues | grep hw_ | egrep "interactive|reg_batch|reg_user|cot|batch|biggermem|spot|reg_ci"'
alias sbq='sbqueues'

### VNC / X ###
_xterm_cmd="xterm -bg black -fg white -fa HackNerdFontMono-Regular -fs 10 +sb"
alias xterm=$_xterm_cmd
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
    # max_display=$(
    #     ps -ef | awk '
    #         /Xtigervnc|Xvnc/ && $0 !~ /awk/ {
    #             for (i=1; i<=NF; i++) {
    #                 if ($i ~ /^:[0-9]+/) {
    #                     gsub(":", "", $i)
    #                     print $i
    #                 }
    #             }
    #         }
    #     ' | sort -n | tail -1
    # )
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
