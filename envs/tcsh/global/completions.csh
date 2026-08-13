# tcsh completions. Sourced from global/tcshrc (interactive only).
#
# TRACKS the ### Completions ### block in envs/bash/global/bashrc.
#
# The bash env has it easy: it sources the bash-completion library and then the
# per-tool scripts under global/completions/*.bash, and modern tools generate
# their own with `<tool> generate-shell-completion bash`. NONE of that works
# here -- bash-completion is bash-only, and no bundled tool emits csh.
#
# So these are hand-written `complete` rules for the tools that ship with the
# loadout. tcsh's completion language is small but covers the common shapes:
#   p/N/(words)/   -- position N completes from this word list
#   c/-/(words)/   -- a word starting with `-` completes from this list
#   n/-x/f/        -- the word AFTER -x completes as a filename
#   p@N@`cmd`@     -- position N completes from a command's output
# `--` at the end means "otherwise complete filenames".

# ---- loadout itself ----------------------------------------------------------
# Verbs come from `loadout completion bash`'s subcommand list; package and group
# names are resolved live so they never go stale against packages.json.
complete loadout \
    'p@1@(install reinstall upgrade update list search info describe resolve doctor snapshot clean completion)@' \
    'n/snapshot/(create restore list)/' \
    'n/completion/(bash)/' \
    'c/--/(help version dry-run no-deps force skip dest-dir no-backup no-verify groups tag installed verify logs pending all allow-online-plugin-sync post-install-hook install-follows-symlinks)/' \
    'n/*/`loadout list 2>/dev/null | awk "NR>2 {print \$1}"`/'

# ---- git ---------------------------------------------------------------------
complete git \
    'p@1@(add branch checkout cherry-pick clone commit diff fetch grep init log merge mv pull push rebase remote reset restore revert rm show stash status switch tag worktree)@' \
    'n/checkout/`git branch --format="%(refname:short)" 2>/dev/null`/' \
    'n/switch/`git branch --format="%(refname:short)" 2>/dev/null`/' \
    'n/merge/`git branch --format="%(refname:short)" 2>/dev/null`/' \
    'n/rebase/`git branch --format="%(refname:short)" 2>/dev/null`/' \
    'n/branch/`git branch --format="%(refname:short)" 2>/dev/null`/'

# ---- bundled CLI tools -------------------------------------------------------
complete bat      'c/--/(paging style theme language list-themes plain number color decorations)/' 'n/*/f/'
complete rg       'c/--/(smart-case ignore-case case-sensitive hidden no-ignore glob type files-with-matches max-filesize search-zip fixed-strings invert-match)/' 'n/*/f/'
complete fd       'c/--/(hidden no-ignore unrestricted full-path type extension exec exec-batch max-depth exclude)/' 'n/*/f/'
complete eza      'c/--/(long tree all git icons header sort time time-style classify color group)/' 'n/*/d/'
complete hx       'n/*/f/'
complete nvim     'c/--/(clean version headless noplugin cmd startuptime)/' 'n/*/f/'
complete tmux     'p@1@(attach detach new-session new-window kill-session kill-server list-sessions list-windows list-panes rename-session source-file split-window)@'
complete zoxide   'p@1@(add query remove init import edit)@'
complete uv       'p@1@(run add remove sync lock export tree venv build publish pip tool python init cache version)@'
complete ruff     'p@1@(check format rule config linter clean version server analyze)@'
complete taplo    'p@1@(lint check validate format fmt lsp config get toml-test completions)@' 'n/{lsp}/(tcp stdio)/' 'n/{config}/(default schema)/' 'n/*/f/'
complete just     'p@1@()@' 'n/*/`just --summary 2>/dev/null`/'
complete lazygit  'c/--/(version path filter work-tree git-dir)/'
complete tldr     'c/--/(update list clear-cache pager quiet language platform)/'

# ---- module (Environment Modules) -------------------------------------------
# Only when the loadout modules install is actually in use; `module` is otherwise
# whatever the site provides and its own tcsh_completion may already be loaded.
complete module \
    'p@1@(add load unload swap switch list avail show display help use unuse purge reload whatis apropos)@' \
    'n/{load,add,show,display,whatis,help}/`module -t avail 2>&1 | grep -v ":$" | grep -v "^$"`/' \
    'n/{unload,rm}/`echo $LOADEDMODULES | tr ":" " "`/'
complete ml 'p@*@`module -t avail 2>&1 | grep -v ":$" | grep -v "^$"`@'

# ---- shell builtins that take specific things -------------------------------
complete cd     'p@1@d@'
complete pushd  'p@1@d@'
complete rmdir  'p@1@d@'
complete which  'p@1@c@'
complete where  'p@1@c@'
complete man    'p@1@c@'
complete kill   'c/-/S/' 'p@*@`ps -u $USER -o pid= | tr -d " "`@'
complete unsetenv 'n/*/e/'
complete setenv   'p@1@e@'
complete unalias  'p@1@a@'
complete alias    'p@1@a@'
