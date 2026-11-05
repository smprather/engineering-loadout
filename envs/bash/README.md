# Bash Configuration

## File Layout

```
bash/
  bashrc          - Entry point (-> ~/.bashrc, ~/.bash_profile). Loads
                    functions.sh, then sources config.sh and bashrc per layer.
                    ~/.bash_login is retired (pruned on install).
  profile         - POSIX shim installed as ~/.profile: sources the bash env
                    only under bash. RHEL X sessions source ~/.profile (via
                    xinitrc-common); dash login shells read it too and must not
                    see bash-only syntax. Never link ~/.profile at bashrc.
  functions.sh    - Shared utilities loaded before any layer config
                    (path_*, is_truthy, fpcmp, array_slice, source_if_exists,
                    loadout_add_precmd, loadout_find_wezterm_shell_integration,
                    loadout_exec_interactive_shell, etc.)
  global/         - Canonical upstream config. Don't edit locally -- changes here
                    should be upstreamed to the repo.
    config.sh     - LOADOUT_CFG_* preference defaults
    bashrc        - PATH, colors, history, aliases, prompt, completions
    completions/  - Bundled bash completions (bat, rg, zoxide, hyperfine, watchexec)
    github.scop.bash-completion/  - Bundled bash-completion library (offline)
    wezterm/      - Vendored WezTerm shell integration (wezterm.sh + PROVENANCE);
                    sourced from user-writable space, never /etc. See
                    global/README.md "Prompt & shell integration".
  corp/           - Corp-level overrides (user-created, not committed here)
  site/           - Site-level overrides (user-created)
  team/           - Team-level overrides (user-created)
  project/        - Project-level overrides (user-created)
  user/           - Personal overrides (user-created)
```

## Loading Order

Files are sourced lowest-to-highest precedence: `global -> corp -> site -> team -> project -> user`.
Each later layer overrides the previous.

```
bashrc
  `-- functions.sh                     # shared utils (all layers can use these)
  `-- global/config.sh                 # LOADOUT_CFG_* defaults
  `-- corp/config.sh                   # (if exists) LOADOUT_CFG_* overrides
  `-- site/config.sh                   # ...
  `-- team/config.sh                   # ...
  `-- project/config.sh
  `-- user/config.sh
  `-- [exec into LOADOUT_CFG_INTERACTIVE_SHELL]  # once, top-level interactive shells only
  `-- global/bashrc                    # PATH, aliases, completions (exits if non-interactive)
  `-- corp/bashrc                      # (if exists)
  `-- site/bashrc
  `-- team/bashrc                      # (if exists)
  `-- project/bashrc
  `-- user/bashrc
  `-- unset_bashrc_local_vars          # clears all _* locals
  `-- path_trim PATH                   # deduplicates PATH entries
```

## Adding Layer Overrides

Create files that will be picked up automatically -- no edits to `global/` needed:

```bash
bash/user/config.sh      # override LOADOUT_CFG_* variables
bash/user/bashrc         # add aliases, functions, PATH entries
bash/corp/completions/mytool.bash  # add a completion (auto-sourced)
```

To switch to another interactive shell, put the line in your own user layer,
`~/.config/bash/user/config.sh`:

```bash
export LOADOUT_CFG_INTERACTIVE_SHELL=zsh
```

It applies to bash and zsh logins (zsh reads these layers); a csh/tcsh login
reads `~/.config/tcsh/user/config.csh` instead. The rules are in the top-level
README, "Choosing your interactive shell".

## Hook Injection Points

Each layer can inject code at specific points inside `global/bashrc` via numbered
files in `<layer>/global_hooks/`:

| File   | Injection point              |
|--------|------------------------------|
| `1.sh` | After functions loaded       |
| `2.sh` | After GLIBC detection        |
| `3.sh` | After PATH setup             |
| `4.sh` | After prompt configuration   |
| `5.sh` | Before bash completions      |
| `6.sh` | After bash completions loaded |
| `7.sh` | Late / final                  |

Example: `bash/team/global_hooks/3.sh` -- inject shared team PATH entries after global PATH is set.

## Settings

Every `LOADOUT_CFG_*` setting the shell configs define, with its default. Set
one in a layer's config file (`~/.config/bash/user/config.sh`, the zsh and tcsh
equivalents, or the shared bash layer for zsh), never in `global/`. The
`tests/docs-sync` gate fails when a setting is defined but missing from this
table. "Shells" lists the shells that read the setting: `all` is bash, zsh and
tcsh.

| Setting | Default | Shells | What it does |
|---|---|---|---|
| `LOADOUT_CFG_INTERACTIVE_SHELL` | empty | all | Interactive shell to switch to at startup: a bare name (`zsh`) or an absolute path. Empty keeps the login shell. See [Choosing your interactive shell](../../README.md#choosing-your-interactive-shell). csh and tcsh accept only `[-A-Za-z0-9_./+@%,:=]` in the value and in the target path. |
| `LOADOUT_CFG_SHARED_PREFIX` | empty | all | Root of a separately installed shared tree (the directory that directly holds `bin/`, `share/` and `lib64/`). Empty means `$HOME/.local/share/loadout`. PATH, TERMINFO_DIRS and the other prefix-derived paths resolve against it. |
| `LOADOUT_CFG_SHM_DIR` | `/dev/shm` | all | Fast scratch root for per-user runtime state (the `XDG_RUNTIME_DIR` fallback, the Python bytecode cache, the eza copy, nvim's swap dir). A per-user dir under it is used only when it is private to you. Mainly a test seam. |
| `LOADOUT_CFG_PREFERRED_LS` | `eza` | all | `eza` or `ls`; any other value means `eza`. eza falls back to plain `ls` when it is not installed. |
| `LOADOUT_CFG_PREFERRED_VI` | `nvim` | all | Editor behind the `vi`/`vim` aliases. Falls back when the binary is not installed. |
| `LOADOUT_CFG_TMUX_TERM` | `xterm-256color` | all (read by tmux) | Pane `TERM` inside tmux, read by the tmux config through the server environment. Only newly created panes are affected. |
| `LOADOUT_CFG_ENABLE_TMUX_PATH_STORE` | `1` | all | Inject the tmux-path-store aliases (per-tmux-window path bookmarks). |
| `LOADOUT_CFG_PROMPT_INCLUDE_HOST` | `0` | all | `1` shows the hostname in the prompt. |
| `LOADOUT_CFG_PROMPT_COLOR_NORMAL` | yellow | all | Colour of the built-in prompt in normal sessions. The built-in prompt only; tcsh values are tcsh escapes, not bash ones. |
| `LOADOUT_CFG_PROMPT_COLOR_FARM` | red | all | Colour of the built-in prompt in farm/LSF sessions, so an expensive job is never mistaken for a local shell. The built-in prompt only; tcsh values are tcsh escapes. |
| `LOADOUT_CFG_ENABLE_LINELIGHT` | `1` | all | linelight colour for `df`, `diff`, `dig`, `free`, `lsblk`, `ping`, `ps`, `sensors` and `ss`. Needs the linelight package; per-command opt-out in `~/.config/linelight/adapters.toml`. |
| `LOADOUT_CFG_ENABLE_SSH_AGENT` | `0` | all | Start a fixed-socket ssh-agent (`~/.ssh/loadout-agent.sock`) on demand. Does not run `ssh-add`. |
| `LOADOUT_CFG_ENABLE_STARSHIP` | `1` | all | Starship prompt. `0` uses the built-in fallback prompt. |
| `LOADOUT_CFG_STARSHIP_USERIDS_TO_HIGHLIGHT` | empty | all | Space-separated usernames; when `whoami` matches one, the username is shown in the prompt. |
| `LOADOUT_CFG_ONLINE_DETECT` | `auto` | all | `auto` (parallel TCP probe at startup), `1` (force online) or `0` (force offline). Exports `LOADOUT_ONLINE`. |
| `LOADOUT_CFG_ONLINE_DETECT_TIMEOUT` | `0.15` | all | Seconds per host for the probe (GNU timeout; decimals are fine). |
| `LOADOUT_CFG_ONLINE_DETECT_HOSTS` | `github.com:443 raw.githubusercontent.com:443 pypi.org:443` | all | Space-separated `host:port` pairs probed in parallel. Point it at corporate mirrors if needed. |
| `LOADOUT_CFG_USE_LOADOUT_MODULES` | `0` | all | `1` sources the loadout-bundled Environment Modules init. Opt-in. |
| `LOADOUT_CFG_ENABLE_FZF` | `0` | bash, zsh | fzf key bindings and completion. |
| `LOADOUT_CFG_ENABLE_ZOXIDE` | `0` | bash, zsh | zoxide `z` integration. |
| `LOADOUT_CFG_ENABLE_WEZTERM_SHELL_INTEGRATION` | `1` | bash, zsh | WezTerm semantic zones, OSC 7 cwd reporting and user vars. The script self-skips non-interactive and dumb terminals. |
| `LOADOUT_CFG_ONLINE_CACHE_TTL` | `86400` | bash, tcsh | Seconds the startup online verdict is cached on disk, so only the first login pays for probes. `0` disables the cache. zsh does not read it yet and probes on every login. |
| `LOADOUT_CFG_ENABLE_ICECREAM` | `1` | bash | IceCream-Bash `ic`/`icp`/`ict`/`ictp` debug-print helpers. |
| `LOADOUT_CFG_PRESERVE_FUNCTIONS` | `module _module_raw ml` | bash | Space-separated function names that survive bashrc's start-of-source `unset -f` reset (for example the Environment Modules functions inherited via `export -f`). Empty clears all. |
| `LOADOUT_CFG_ZSH_ENABLE_COMPLETION` | `1` | zsh | Run `compinit` at startup. The most expensive part of zsh startup on a slow filesystem. |
| `LOADOUT_CFG_ZSH_ENABLE_BASHCOMPINIT` | `0` | zsh | Load the bash-format completions under `bash/global/completions/` through zsh's bashcompinit bridge. |
