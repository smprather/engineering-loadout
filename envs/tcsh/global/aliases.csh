# Loadout tcsh aliases.
#
# Snapshot of envs/bash/global/aliases.sh; NOT synced with it.
#
# The bash env drives `ls`/`cat`/`vi` through shell FUNCTIONS that read
# LOADOUT_CFG_* and per-call variables (`human_readable=1 ls`). csh has no
# functions, so those are re-expressed directly here: the best available tool is
# chosen once, at startup, and aliased directly. An alias is only defined when its
# binary exists -- an alias pointing at a missing command is exactly the kind of
# noise this environment must not produce.

# ---- navigation --------------------------------------------------------------
alias b         'cd ..'
alias bb        'cd ../..'
alias bbb       'cd ../../..'
alias bbbb      'cd ../../../..'
alias bbbbb     'cd ../../../../..'
alias bbbbbb    'cd ../../../../../..'
alias cd-       'cd -'

# ---- listing -----------------------------------------------------------------
if ( -X eza ) then
    alias ls    'eza'
    alias ll    'eza -l'
    alias la    'eza -la'
    alias lh    'eza -lh'
    alias lah   'eza -lah'
else if ( -X lsd ) then
    alias ls    'lsd'
    alias ll    'lsd -l'
    alias la    'lsd -la'
    alias lh    'lsd -lh'
    alias lah   'lsd -lah'
else
    alias ll    'ls -l'
    alias la    'ls -la'
    alias lh    'ls -lh'
    alias lah   'ls -lah'
endif

# ---- search ------------------------------------------------------------------
if ( -X rg ) then
    alias g     'rg --smart-case --search-zip --hidden --no-ignore'
else
    alias g     'grep -r'
endif

if ( -X fd ) then
    alias f     'fd --unrestricted --full-path'
else
    alias f     'find . -name'
endif

alias h         'history | grep'

# ---- editor / pager ----------------------------------------------------------
if ( -X nvim ) then
    alias vi    'nvim'
    alias vim   'nvim'
else if ( -X vim ) then
    alias vi    'vim'
endif

if ( -X bat ) then
    alias cat   'bat --paging=never'
    alias catp  'bat'
endif

# ---- git ---------------------------------------------------------------------
alias gs        'git status'
alias gc        'git commit'
alias gp        'git push'
alias gd        'git diff'
alias ga        'git add -A && git status'

# ---- misc --------------------------------------------------------------------
alias x         'chmod +x'
alias rp        'realpath'
alias t         'exec tcsh'
alias w         'where'
alias mkdir     'mkdir -p'

# ---- the only survivors of envs/bash/functions.sh ----------------------------
# These manipulate $path, which csh has natively. The other 26 functions need
# loops, locals or return values and have no csh equivalent -- they are absent by
# design, not missing by accident. See envs/tcsh/README.md.
alias path_prepend  'set path = ( \!:1 $path:q )'
alias path_append   'set path = ( $path:q \!:1 )'
