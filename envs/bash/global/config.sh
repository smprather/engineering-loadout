# Full path to preferred bash binary; re-execs at startup if set
export LOADOUT_CFG_PREFERRED_BASH=""
# Local-root directory for a separately-installed shared/read-only loadout tree.
# It directly contains bin/, share/, and lib64/; for `loadout install @shared
# --dest-dir /foo/bar`, set this to /foo/bar/local. Empty means the user's own
# ~/.local. PATH, TERMINFO_DIRS, and the tealdeer cache resolve against
# ${LOADOUT_CFG_SHARED_PREFIX:-$HOME/.local}.
export LOADOUT_CFG_SHARED_PREFIX=""
# Valid values for LOADOUT_CFG_PREFERRED_LS: eza, lsd, ls
export LOADOUT_CFG_PREFERRED_LS="eza"
export LOADOUT_CFG_PREFERRED_VI="nvim"
export LOADOUT_CFG_PREFERRED_CAT="bat"
export LOADOUT_CFG_ATTACH_TO_TMUX="0"
export LOADOUT_CFG_ATTACH_TO_TMUX_WITH_DETACH_OTHERS="0"
export LOADOUT_CFG_ENABLE_TMUX_PATH_STORE="1"
export LOADOUT_CFG_PROMPT_INCLUDE_HOST="0"
export LOADOUT_CFG_PROMPT_COLOR_NORMAL="$PROMPT_YELLOW"
export LOADOUT_CFG_PROMPT_COLOR_FARM="$PROMPT_RED"
export LOADOUT_CFG_ENABLE_FASTNVIM="0"
export LOADOUT_CFG_ENABLE_FZF="0"
export LOADOUT_CFG_ENABLE_ZOXIDE="0"
export LOADOUT_CFG_ENABLE_GRC="1"
# Fixed-socket ssh-agent (~/.ssh/loadout-agent.sock) started on demand if not
# already running, instead of `eval "$(ssh-agent -s)"`'s random per-shell
# socket that nothing outside that one shell can find. Does NOT auto-run
# ssh-add -- a passphrase-protected key would prompt on every new shell; load
# it once per agent lifetime yourself. See docs/RELEASE.md for why the fixed
# socket matters for release signing specifically.
export LOADOUT_CFG_ENABLE_SSH_AGENT="0"
# IceCream-Bash ic/icp/ict/ictp debug-print helpers
export LOADOUT_CFG_ENABLE_ICECREAM="1"
export LOADOUT_CFG_ENABLE_STARSHIP="1"
export LOADOUT_CFG_STARSHIP_USERIDS_TO_HIGHLIGHT=""
# wezterm shell integration: semantic zones, OSC 7 cwd reporting, and user
# vars. Safe everywhere -- the script self-skips non-interactive and dumb/linux
# terminals, and its OSC sequences are ignored by terminals that don't grok
# them. Benefits wezterm users (including tmux-in-wezterm with passthrough).
export LOADOUT_CFG_ENABLE_WEZTERM_SHELL_INTEGRATION="1"
# Explicit path to wezterm.sh. Empty -> auto-resolve (vendored copy, then paths
# relative to the installed `wezterm` binary / shared prefix). Set this from the
# engineering-loadout --dest-dir installer to pin an exact location. Never /etc.
export LOADOUT_CFG_WEZTERM_SHELL_INTEGRATION=""
# LOADOUT_CFG_ENABLE_ONLINE_UPDATES -> auto | 1 | 0
export LOADOUT_CFG_ENABLE_ONLINE_UPDATES="auto"
# LOADOUT_CFG_ONLINE_DETECT_TIMEOUT -> seconds per host (GNU timeout; decimal ok)
export LOADOUT_CFG_ONLINE_DETECT_TIMEOUT="0.15"
# LOADOUT_CFG_ONLINE_DETECT_HOSTS -> space-separated host:port
export LOADOUT_CFG_ONLINE_DETECT_HOSTS="github.com:443 raw.githubusercontent.com:443 pypi.org:443"
# Startup online verdict is cached on disk for this many seconds (default one
# day) so only the first login pays for probes. 0 disables the cache.
# export LOADOUT_ONLINE_CACHE_TTL="86400"
# cargo wrapper (online-first, offline fallback to rust-crate-store):
# hosts probed per invocation, TTL of their cached verdicts, and manual
# tri-state override (1 = always offline mode, 0 = never wrap).
export LOADOUT_CFG_CARGO_PROBE_HOSTS="index.crates.io:443 static.crates.io:443"
export LOADOUT_NET_PROBE_TTL="300"
# export LOADOUT_CARGO_OFFLINE=""
# LOADOUT_CFG_USE_LOADOUT_MODULES -> 0 | 1  (source modules-init.bash; opt-in)
export LOADOUT_CFG_USE_LOADOUT_MODULES="0"
# LOADOUT_CFG_PRESERVE_FUNCTIONS -> space-separated function names.
# At startup bash/bashrc clears every function with `unset -f` so a re-source or
# `exec bash` starts from a clean slate. Names listed here survive that reset --
# e.g. the Environment Modules functions (module/_module_raw/ml) inherited via
# `export -f` from a parent shell, which would otherwise be wiped. Empty = clear all.
export LOADOUT_CFG_PRESERVE_FUNCTIONS="module _module_raw ml"
