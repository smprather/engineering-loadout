# Loadout tcsh config -- LOADOUT_CFG_* preferences.
#
# This file TRACKS envs/bash/global/config.sh. When that file gains a variable,
# add it here too unless tcsh genuinely cannot act on it.
#
# Deliberately omitted, because upstream ships no tcsh target for the thing they
# control (see envs/tcsh/README.md): LOADOUT_CFG_ENABLE_STARSHIP,
# LOADOUT_CFG_ENABLE_FZF, LOADOUT_CFG_ENABLE_ZOXIDE, LOADOUT_CFG_ENABLE_ICECREAM,
# LOADOUT_CFG_ENABLE_WEZTERM_SHELL_INTEGRATION / _WEZTERM_SHELL_INTEGRATION,
# LOADOUT_CFG_PRESERVE_FUNCTIONS (csh has no functions to preserve),
# LOADOUT_CFG_PREFERRED_BASH (see LOADOUT_CFG_PREFERRED_TCSH below instead).
# Setting them here would be a variable nothing reads.
#
# Every value is an EXPORTED SCALAR (`setenv`, not `set`), exactly as in bash --
# they must survive into child processes and show up in `env | grep LOADOUT_CFG_`,
# and several are read by helper scripts under global/helpers/ which are separate
# processes and can only see the environment.
#
# Override any of these in ~/.config/tcsh/user/config.csh.

# ---- shell selection ---------------------------------------------------------
# Full path to a preferred tcsh binary; the rc re-execs into it at startup when
# it is set, differs from the running shell, and is executable. The bash analogue
# is LOADOUT_CFG_PREFERRED_BASH.
if ( ! $?LOADOUT_CFG_PREFERRED_TCSH )      setenv LOADOUT_CFG_PREFERRED_TCSH ""

# ---- deployment layout -------------------------------------------------------
# Local-root of a separately-installed shared/read-only tree (the dir holding
# bin/, share/, lib64/). Empty = use the user's own ~/.local.
if ( ! $?LOADOUT_CFG_SHARED_PREFIX )       setenv LOADOUT_CFG_SHARED_PREFIX ""

# ---- preferred tools ---------------------------------------------------------
# The aliases in aliases.csh fall back automatically when the preferred binary is
# not installed, so these are safe to leave as-is.
if ( ! $?LOADOUT_CFG_PREFERRED_LS )        setenv LOADOUT_CFG_PREFERRED_LS  eza
if ( ! $?LOADOUT_CFG_PREFERRED_VI )        setenv LOADOUT_CFG_PREFERRED_VI  nvim
if ( ! $?LOADOUT_CFG_PREFERRED_CAT )       setenv LOADOUT_CFG_PREFERRED_CAT bat

# ---- optional integrations ---------------------------------------------------
# Generic Colorizer.
if ( ! $?LOADOUT_CFG_ENABLE_GRC )          setenv LOADOUT_CFG_ENABLE_GRC 1
# Fast nvim mode (read by the nvim config, not by the shell).
if ( ! $?LOADOUT_CFG_ENABLE_FASTNVIM )     setenv LOADOUT_CFG_ENABLE_FASTNVIM 0
# Source modules-init.csh at startup to select the loadout-bundled Environment
# Modules install. Off by default -- opt in per user/site layer.
if ( ! $?LOADOUT_CFG_USE_LOADOUT_MODULES ) setenv LOADOUT_CFG_USE_LOADOUT_MODULES 0
# tmux-path-store alias injection (per-tmux-window path bookmarks). The variable
# name stays SCREAMING_SNAKE even though the command is kebab-case: a shell
# variable cannot take a dash.
if ( ! $?LOADOUT_CFG_ENABLE_TMUX_PATH_STORE ) setenv LOADOUT_CFG_ENABLE_TMUX_PATH_STORE 1

# ---- prompt ------------------------------------------------------------------
# Include the hostname in the prompt (1) or not (0).
if ( ! $?LOADOUT_CFG_PROMPT_INCLUDE_HOST ) setenv LOADOUT_CFG_PROMPT_INCLUDE_HOST 0
# Prompt colors, as tcsh %{...%} escape bodies. Normal sessions vs farm/LSF ones
# (the farm prompt turns red so an expensive job is never mistaken for a local
# shell). Names match the bash env; the VALUES are tcsh escapes, not bash ones.
if ( ! $?LOADOUT_CFG_PROMPT_COLOR_NORMAL ) setenv LOADOUT_CFG_PROMPT_COLOR_NORMAL "\033[38;2;255;255;0m"
if ( ! $?LOADOUT_CFG_PROMPT_COLOR_FARM )   setenv LOADOUT_CFG_PROMPT_COLOR_FARM   "\033[38;2;255;0;0m"
# Space-separated usernames; if `whoami` matches one, the username is shown in
# the prompt. Same variable the bash env passes to Starship.
if ( ! $?LOADOUT_CFG_STARSHIP_USERIDS_TO_HIGHLIGHT ) setenv LOADOUT_CFG_STARSHIP_USERIDS_TO_HIGHLIGHT ""

# ---- tmux --------------------------------------------------------------------
if ( ! $?LOADOUT_CFG_ATTACH_TO_TMUX )      setenv LOADOUT_CFG_ATTACH_TO_TMUX 0
if ( ! $?LOADOUT_CFG_ATTACH_TO_TMUX_WITH_DETACH_OTHERS ) setenv LOADOUT_CFG_ATTACH_TO_TMUX_WITH_DETACH_OTHERS 0

# ---- online connectivity detection -------------------------------------------
# auto (parallel TCP probe on startup) | 1 (force online) | 0 (force offline).
# Exports LOADOUT_ONLINE=1/0, inherited by child shells and tmux panes.
if ( ! $?LOADOUT_CFG_ENABLE_ONLINE_UPDATES ) setenv LOADOUT_CFG_ENABLE_ONLINE_UPDATES auto
# Per-host TCP connect timeout in seconds (GNU timeout; decimal OK).
if ( ! $?LOADOUT_CFG_ONLINE_DETECT_TIMEOUT ) setenv LOADOUT_CFG_ONLINE_DETECT_TIMEOUT 0.15
# Space-separated host:port pairs probed in parallel. Override in user/config.csh
# to use corporate mirror hosts.
if ( ! $?LOADOUT_CFG_ONLINE_DETECT_HOSTS ) setenv LOADOUT_CFG_ONLINE_DETECT_HOSTS "github.com:443 raw.githubusercontent.com:443 pypi.org:443"
