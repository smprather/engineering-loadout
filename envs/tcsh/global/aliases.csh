# Loadout tcsh aliases.
#
# TRACKS envs/bash/global/aliases.sh. When an alias or function is added there,
# add its tcsh form here.
#
# Three csh rules this file lives by:
#
#   1. `!` MUST be escaped as `\!`. Unescaped it triggers history expansion at
#      alias-definition time, so `alias foo 'bar !:1'` expands the !:1 against
#      YOUR history right now and stores the result. `\!:1` is what gets stored.
#   2. An alias with NO `\!` reference gets its arguments appended automatically,
#      which is what you want for a plain wrapper (`alias gs 'git status'` then
#      `gs -s` runs `git status -s`). Use `\!:1` / `\!*` / `\!:2-` only when the
#      arguments must land somewhere other than the end.
#   3. An alias is defined ONLY when its binary exists. An alias pointing at a
#      missing command is exactly the startup noise this environment forbids.
#
# Anything needing loops, locals, `case` or arithmetic lives in global/helpers/
# and is aliased here. See helpers/README.md for the three helper shapes.

set _lo_helpers = "$HOME/.config/tcsh/global/helpers"

# ---- navigation --------------------------------------------------------------
# `cd` gets the same conveniences as the bash env's cd(): a FILE argument goes to
# its parent directory, and a missing path offers to mkdir -p it.
#
# The follow-up `ls` is NOT here -- cwdcmd in global/tcshrc does it, and covers
# pushd/popd/implicitcd too, so unlike bash there is no call site that can skip
# the listing by reaching the builtin directly.
#
# The empty-string guard is load-bearing: `cd ""` in csh goes to $HOME, so
# without it a typo'd path would silently move you home. `chdir` is csh's own
# builtin name for cd and is the escape hatch (aliased as bcd, matching bash's
# `bcd` for `builtin cd`).
alias cd        'set _lo_t = "`'"$_lo_helpers"'/cd-target \!*`" ; if ( "$_lo_t" != "" ) chdir "$_lo_t" ; unset _lo_t'
alias cd-       'chdir -'
alias bcd       'chdir'
alias b         'cd ..'
alias bb        'cd ../..'
alias bbb       'cd ../../..'
alias bbbb      'cd ../../../..'
alias bbbbb     'cd ../../../../..'
alias bbbbbb    'cd ../../../../../..'
alias bbbbbbb   'cd ../../../../../../..'
alias bbbbbbbb  'cd ../../../../../../../..'
alias bbbbbbbbb 'cd ../../../../../../../../..'
alias bbbbbbbbbb 'cd ../../../../../../../../../..'

# cd to the Nth most recently modified subdirectory. The helper prints the path;
# the `|| true` shape csh lacks is handled by the helper exiting non-zero and
# printing nothing, so `cd ""` -- which csh would turn into `cd $HOME` -- cannot
# happen: the outer test guards it.
alias cdd       'set _lo_d = "`'"$_lo_helpers"'/recent-dir 1`" ; if ( "$_lo_d" != "" ) cd "$_lo_d" ; unset _lo_d'
alias cddd      'set _lo_d = "`'"$_lo_helpers"'/recent-dir 2`" ; if ( "$_lo_d" != "" ) cd "$_lo_d" ; unset _lo_d'
alias cdddd     'set _lo_d = "`'"$_lo_helpers"'/recent-dir 3`" ; if ( "$_lo_d" != "" ) cd "$_lo_d" ; unset _lo_d'
alias cddddd    'set _lo_d = "`'"$_lo_helpers"'/recent-dir 4`" ; if ( "$_lo_d" != "" ) cd "$_lo_d" ; unset _lo_d'
alias cdddddd   'set _lo_d = "`'"$_lo_helpers"'/recent-dir 5`" ; if ( "$_lo_d" != "" ) cd "$_lo_d" ; unset _lo_d'

alias p         'pwd | tee "/tmp/p_dir.$USER"'
alias cdp       'cd "`cat /tmp/p_dir.$USER`"'
alias latest    'eval "`'"$_lo_helpers"'/latest-link \!*`"'

# ---- listing -----------------------------------------------------------------
# The bash env drives every listing variant through ONE ls() function that reads
# per-call variables (`human_readable=1 ls`). csh has no functions and no
# per-command variable prefix, so each variant is its own alias built from the
# same arg sets that global/tcshrc exported. Same output, different mechanism.
# $EZA_ARGS / $LSD_ARGS are the SAME variables the bash ls() function uses, set
# to the same values by global/tcshrc -- so the two shells produce identical
# listings and a user who overrides one variable changes both.
if ( -X eza ) then
    alias ls    'eza --time-style "+%D %H:%M:%S" -B $EZA_ARGS'
    alias lh    'eza --time-style "+%D %H:%M:%S" $EZA_ARGS'
    alias la    'eza --time-style "+%D %H:%M:%S" -a -B $EZA_ARGS'
    alias lg    'eza --time-style "+%D %H:%M:%S" -g -B $EZA_ARGS'
    alias lah   'eza --time-style "+%D %H:%M:%S" -a $EZA_ARGS'
    alias tree  'eza -T'
else if ( -X lsd ) then
    alias ls    'lsd --size bytes --date "+%D %H:%M:%S" $LSD_ARGS'
    alias lh    'lsd --size short --date "+%D %H:%M:%S" $LSD_ARGS'
    alias la    'lsd --size bytes --date "+%D %H:%M:%S" -a $LSD_ARGS'
    alias lg    'lsd --size bytes --date "+%D %H:%M:%S" -g $LSD_ARGS'
    alias lah   'lsd --size short --date "+%D %H:%M:%S" -a $LSD_ARGS'
    alias tree  'lsd -T'
else
    alias ls    'ls --color -lrt --no-group --human-readable'
    alias lh    'ls --color -lrt --no-group'
    alias la    'ls --color -lrt --no-group --human-readable -a'
    alias lg    'ls --color -lrt --human-readable'
    alias lah   'ls --color -lrt --no-group -a'
    if ( -X tree ) then
        alias tree 'tree'
    else
        alias tree '/bin/ls -R'
    endif
endif
alias sl        'ls'
alias ll        'ls'
alias lr        'ls'
alias rl        'ls'
alias lha       'lah'
alias lsg       'lg'

# ---- editing -----------------------------------------------------------------
# $LOADOUT_CFG_PREFERRED_VI is resolved to something installed by global/tcshrc
# before this file is sourced, so these never point at a missing binary.
alias vi        '$LOADOUT_CFG_PREFERRED_VI'
alias vim       '$LOADOUT_CFG_PREFERRED_VI'
alias vic       '$LOADOUT_CFG_PREFERRED_VI --clean -u "$HOME/.vimrc"'
alias vid       '$LOADOUT_CFG_PREFERRED_VI -d'
alias vimdiff   '$LOADOUT_CFG_PREFERRED_VI -d -R'
alias vii       'set _lo_f = "`'"$_lo_helpers"'/recent-file`" ; if ( "$_lo_f" != "" ) $LOADOUT_CFG_PREFERRED_VI "$_lo_f" ; unset _lo_f'
alias ovi       '\vim'
alias v         'nvim -n -R -'
alias wip       '$LOADOUT_CFG_PREFERRED_VI $HOME/wip.txt'
alias new       'touch \!:1 && chmod +x \!:1 && $LOADOUT_CFG_PREFERRED_VI \!:1'
alias test_nvim 'env NVIM_APPNAME=test_nvim nvim'
if ( -X fzf ) then
    alias fvi   'set _lo_f = "`fzf`" ; if ( "$_lo_f" != "" ) $LOADOUT_CFG_PREFERRED_VI "$_lo_f" ; unset _lo_f'
    alias fls   'set _lo_f = "`fzf`" ; if ( "$_lo_f" != "" ) ls "$_lo_f" ; unset _lo_f'
    alias fcat  'set _lo_f = "`fzf`" ; if ( "$_lo_f" != "" ) cat "$_lo_f" ; unset _lo_f'
    alias fcd   'set _lo_d = "`fzf --walker=dir`" ; if ( "$_lo_d" != "" ) cd "$_lo_d" ; unset _lo_d'
endif

# ---- search ------------------------------------------------------------------
if ( -X rg ) then
    alias g     "rg --smart-case --search-zip --hidden --no-ignore --glob='\!*.snapshot*'"
    alias sg    "rg --smart-case --search-zip --hidden --no-ignore --glob='\!*.snapshot*' --max-filesize=100K"
    alias gpy   "rg --smart-case --search-zip --hidden --no-ignore --glob='*.py' --glob='\!*.snapshot*'"
    alias gtcl  "rg --smart-case --search-zip --hidden --no-ignore --glob='*.tcl' --glob='\!*.snapshot*'"
else
    alias g     "grep -r -i --color=auto --exclude-dir='.snapshot'"
    alias sg    "grep -r -i -l --color=auto --exclude-dir='.snapshot'"
    alias gpy   "grep -r -i --color=auto --include='*.py' --exclude-dir='.snapshot'"
    alias gtcl  "grep -r -i --color=auto --include='*.tcl' --exclude-dir='.snapshot'"
endif
alias gv        'g -v'
alias gf        'g -F'
# Makes grep noticeably faster. You should be using rg instead.
alias grep      'env LC_ALL=C grep'

if ( -X fdfind ) then
    alias fd    'fdfind'
    alias f     'fdfind --exclude .snapshot --unrestricted --full-path'
else if ( -X fd ) then
    alias f     'fd --exclude .snapshot --unrestricted --full-path'
else
    alias f     'find . -name'
endif
alias fc        "$_lo_helpers/find-count"

alias h         'history | g'
alias hg        'history | /bin/grep -i'
alias gah       "$_lo_helpers/grep-all-history"

# ---- git ---------------------------------------------------------------------
# `ga` with no argument stages everything; with arguments it stages those. csh
# cannot branch on $#argv inside an alias, so this uses git's own semantics:
# `git add --all` with no pathspec is repo-wide, and with pathspecs is scoped.
alias ga        'git add --all \!* ; git status'
alias gc        'git commit'
alias gs        'git status'
alias gp        'git push'
alias gd        'git d'
alias gr        'git review'
alias gsp       "$_lo_helpers/git-stash-pull"

# ---- system / utils ----------------------------------------------------------
alias t         'exec tcsh'
alias c         'clear'
alias w         'where'
alias ho        'hostname -s'
alias d         'date'
alias rm        'rm -f'
alias mkdir     'mkdir -p'
alias mdkir     'mkdir -p'
alias rs        'rsync --archive --info=progress2 --info=name0 --no-inc-recursive --exclude="*/.snapshot/"'
alias du        'du --block-size=G -s * | sort -r -n -k 1'
alias dum       '/bin/du --block-size=M -s * | sort -r -n -k 1'
alias pl        "$_lo_helpers/path-list"
alias tx        'tar -xvf'
alias tt        'tar -tvf'
alias we        'watchexec --clear --poll 500'
alias rlrt      "$_lo_helpers/recent-files"
alias gpw       'chmod -R g+w'
alias gmw       'chmod -R g-w'
alias x         'chmod +x'
alias rp        'realpath'
alias lns       "$_lo_helpers/safe-symlink"
alias extract_rpm 'rpm2cpio \!:1 | cpio -idmv'
alias zhead     "$_lo_helpers/zhead"
alias vman      'env MANPAGER="nvim +Man\!" man'
alias clean_bash 'echo "/usr/bin/env --ignore-environment PATH=/bin HOME=$HOME USER=`/bin/whoami` /bin/bash --rcfile ~/.clean.bashrc"'
alias agrep     'alias | g'
# `a`: dump the alias table to a temp file and edit it. The bash version also
# dumps `declare -f`; csh has no functions, so the alias table is the whole set.
alias a         'alias | sort > "/tmp/alias.$$" ; $LOADOUT_CFG_PREFERRED_VI "/tmp/alias.$$" ; rm -f "/tmp/alias.$$"'
# NOTE: shadows the bundled `st` terminal, exactly as the bash env's st() does.
# Kept for parity -- run the terminal as `\st` or by full path.
alias st        'strace -o "/tmp/strace.$USER" -f -v -s 1000000'
# sp1 / sp2: prompt without / with the hostname. The bash env re-runs its
# set_prompt function; csh has no functions, so these reassign the prompt lead
# that global/tcshrc left in place for exactly this purpose (and that precmd
# re-reads on the next prompt).
alias sp1       'set loadout_prompt_lead = "$loadout_prompt_lead_nohost" ; set prompt = "${loadout_prompt_lead}%B%~%b %#${loadout_prompt_tail}"'
alias sp2       'set loadout_prompt_lead = "$loadout_prompt_lead_host" ; set prompt = "${loadout_prompt_lead}%B%~%b %#${loadout_prompt_tail}"'
alias fsbm      'fio --randrepeat=1 --ioengine=libaio --direct=0 --gtod_reduce=1 --name=test --bs=4k --iodepth=64 --readwrite=randrw --rwmixread=75 --size=4G --filename=./fio_test ; rm ./fio_test'

if ( -X rp ) then
    alias rp    'realpath'
endif
if ( -X ncdu ) then
    alias ncdu  'ncdu --graph-style hash --color dark'
endif
if ( -X less ) then
    alias less  'less --incsearch --use-color +X'
endif
if ( -X unpigz ) then
    alias gunzip 'unpigz'
endif
if ( -X pigz ) then
    alias gzip  'pigz'
    alias gz    'pigz'
endif
if ( -X colourify ) then
    alias df    'colourify df --block-size=G'
else
    alias df    'df --block-size=G'
endif
if ( -X bat ) then
    if ( "$LOADOUT_CFG_PREFERRED_CAT" == "bat" ) alias cat 'bat --paging=never'
    alias catp  'bat'
else if ( -X batcat ) then
    # Debian and derivatives ship bat as `batcat`. The bash env aliases `bat` to
    # whichever name exists so scripts and muscle memory keep working; same here.
    alias bat   'batcat'
    if ( "$LOADOUT_CFG_PREFERRED_CAT" == "bat" ) alias cat 'batcat --paging=never'
    alias catp  'batcat'
endif

# ---- tmux --------------------------------------------------------------------
alias tl        'tmux list-sessions'
alias ta        'resize ; tmux attach -d || tmux'
alias btopu     'btop -u `/bin/whoami`'

# ---- EDA / LSF ---------------------------------------------------------------
alias invs      'innovus -stylus'
alias vlts      'voltus -stylus'
alias itcl      '$HOME/.local/lib/tcl/tclsh-wrapper/TclReadLine/TclReadLine.tcl'
alias ipy       'ipython3'
alias pyprofile 'python3 -m cProfile -s cumtime'
alias fdon      'echo "setenv FLEXLM_DIAGNOSTICS 3" ; setenv FLEXLM_DIAGNOSTICS 3'
alias fdoff     'echo "unsetenv FLEXLM_DIAGNOSTICS" ; unsetenv FLEXLM_DIAGNOSTICS'
alias mli       'module list'
alias ms        'module show'
alias ma        'module avail'
alias my_total_cpu "$_lo_helpers/total-cpu"
alias pg        'pgrep -u `/bin/whoami` --full --list-full'
alias pk        'pkill -f'
# The bash env overrides pgrep/pkill themselves to add -f, so a bare `pgrep foo`
# matches the full command line in both shells. Same here -- otherwise muscle
# memory built in bash silently matches fewer processes in tcsh.
alias pgrep     'pgrep -f'
alias pkill     'pkill -f'
alias bkillall  'bkill -u `/bin/whoami` 0'
alias bjobsv    'setenv LSB_BJOBS_FORMAT "jobid:7 stat:5 user:12 queue:15 slots:3 proj_name:15 sla:15 exec_host:13 max_mem:12 pend_time:12 max_req_proc:12 mem"'
alias bq        "$_lo_helpers/lsf-queues"
alias bqs       "$_lo_helpers/lsf-queues"
alias sbqueues  'echo "QUEUE_NAME      PRIO STATUS          MAX JL/U JL/P JL/H NJOBS  PEND   RUN  SUSP  RSV PJOBS " ; bqueues | grep hw_ | egrep "interactive|reg_batch|reg_user|cot|batch|biggermem|spot|reg_ci"'
alias sbq       'sbqueues'

# ---- VNC / X -----------------------------------------------------------------
alias xterm     'xterm -bg black -fg white -fa HackNerdFontMono-Regular -fs 10 +sb'
alias vnc       "$_lo_helpers/vnc-start"
alias startvnc  'vncserver -SecurityTypes None'
alias runvnc    'vncserver -SecurityTypes None'
alias stopvnc   'vncserver -kill'
alias killvnc   "$_lo_helpers/vnc-kill-newest"

# ---- history -----------------------------------------------------------------
# The csh form of the bash env's loadout_save_history precmd hook: flush the
# in-memory history list to $histfile without waiting for the shell to exit, so
# a `kill -9`, a crashed tmux server or a dropped connection does not take the
# session's history with it, and so `gah` can see commands from shells that are
# still running.
#
# tcsh has NO incremental append. `history -S` rewrites the WHOLE file (10k
# lines), where bash's `history -a` writes only what is new -- which is why
# tcshrc drives this from `periodic`/$tperiod rather than from precmd. Per
# prompt it would rewrite the file on every keystroke-to-enter cycle, and on an
# NFS farm home that cost is real. Every few minutes buys nearly all of the
# crash-survival benefit for a bounded fraction of the writes.
#
# Safe against clobber: seed-history gives each shell its own per-PID $histfile,
# so this shell is the only writer of that file.
alias loadout_save_history 'history -S'

# ---- the csh forms of envs/bash/functions.sh ---------------------------------
# path_prepend / path_append only touch $path, which csh has natively.
# path_remove / path_trim need a filtering loop, which an alias can express.
alias path_prepend 'set path = ( \!:1 $path:q )'
alias path_append  'set path = ( $path:q \!:1 )'
alias path_prepend_if_dir 'if ( -d \!:1 ) set path = ( \!:1 $path:q )'
alias path_append_if_dir  'if ( -d \!:1 ) set path = ( $path:q \!:1 )'
alias path_remove  'set _lo_np = ( ) ; foreach _lo_pe ( $path:q ) ; if ( "$_lo_pe" != "\!:1" ) set _lo_np = ( $_lo_np:q "$_lo_pe" ) ; end ; set path = ( $_lo_np:q ) ; unset _lo_np _lo_pe'
alias path_trim    'set _lo_np = ( ) ; foreach _lo_pe ( $path:q ) ; set _lo_dup = 0 ; foreach _lo_pk ( $_lo_np:q ) ; if ( "$_lo_pk" == "$_lo_pe" ) set _lo_dup = 1 ; end ; if ( $_lo_dup == 0 && -d "$_lo_pe" ) set _lo_np = ( $_lo_np:q "$_lo_pe" ) ; end ; set path = ( $_lo_np:q ) ; unset _lo_np _lo_pe _lo_pk _lo_dup'
alias source_if_exists 'if ( -r \!:1 ) source \!:1'
# Exit-status helpers: use them as `if ( { is_truthy "$VAR" } ) then ... endif`.
alias is_truthy    "$_lo_helpers/is-truthy"
alias vercmp       "$_lo_helpers/vercmp"
alias fpcmp        "$_lo_helpers/vercmp"

unset _lo_helpers
