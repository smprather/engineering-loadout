# Loadout tcsh config -- LOADOUT_CFG_* preferences.
#
# SNAPSHOT, NOT A MIRROR. These are hand-maintained and deliberately NOT generated
# from envs/bash/global/config.sh. There is no drift test between them: the tcsh
# environment is a one-time best-effort port and does not track the bash env. If the
# bash env gains a config variable, tcsh does not automatically need it.
#
# Only the variables that mean something in tcsh are here. The bash env has 25; the
# ones governing Starship, fzf/zoxide integration, bash-preexec, tmux auto-attach and
# the online-detection probe have no tcsh implementation and are omitted rather than
# set to a value nothing reads.
#
# Override any of these in ~/.config/tcsh/user/config.csh.

# Local-root of a separately-installed shared/read-only tree (dir holding bin/,
# share/, lib64/). Empty = use the user's own ~/.local.
if ( ! $?LOADOUT_CFG_SHARED_PREFIX )       setenv LOADOUT_CFG_SHARED_PREFIX ""

# Preferred tools. The aliases in aliases.csh fall back automatically when the
# preferred binary is not installed, so these are safe to leave as-is.
if ( ! $?LOADOUT_CFG_PREFERRED_LS )        setenv LOADOUT_CFG_PREFERRED_LS  eza
if ( ! $?LOADOUT_CFG_PREFERRED_VI )        setenv LOADOUT_CFG_PREFERRED_VI  nvim
if ( ! $?LOADOUT_CFG_PREFERRED_CAT )       setenv LOADOUT_CFG_PREFERRED_CAT bat

# Include the hostname in the prompt (1) or not (0).
if ( ! $?LOADOUT_CFG_PROMPT_INCLUDE_HOST ) setenv LOADOUT_CFG_PROMPT_INCLUDE_HOST 0
