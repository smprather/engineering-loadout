# bash/global

Canonical upstream bash config. Changes here should be upstreamed to the repo,
not made locally -- use a layer override instead (`bash/user/`, `bash/corp/`, etc.).

## GRC (Generic Colorizer)

The `grc/` directory contains a patched GRC binary with hardcoded config paths
baked in so it works without system installation:

- `grc/bin/grc` -- hardcoded: `conffilenames = [home + '/.config/bash/global/grc/etc/grc.conf']`
- `grc/bin/grcat` -- hardcoded: `conffilepath += [home + '/.config/bash/global/grc/share/grc/']`

If you rebuild GRC from source, patch these paths accordingly.
Enabled via `LOADOUT_CFG_ENABLE_GRC=1` in `config.sh`.

## Alias-Safe Function Definitions

Interactive bash expands aliases while parsing sourced files. If `aliases.sh`
defines a function whose name may already be an alias (`df`, `grep`, `cat`,
etc.), clear the alias first:

```bash
unalias df 2>/dev/null || true
df() { command df --block-size=G "$@"; }
```

This is load-bearing. A plain `df() { ... }` can parse as invalid text after
alias expansion in `exec bash`, while `bash -n aliases.sh` still passes.

## Bash Completions (`completions/`)

Bundled completions for offline environments. Sourced automatically by `global/bashrc`.
All `*.bash` files in any layer's `completions/` directory are sourced automatically.

To regenerate a completion from the tool's own generator:
```bash
rg --generate complete-bash > completions/rg.bash
bat --generate-shell-completion bash > completions/bat.bash
```

## github.scop.bash-completion

Vendored [scop/bash-completion](https://github.com/scop/bash-completion) library,
used as the base completion framework loaded before all other completions.
Required for most completion scripts to work correctly in offline environments
where the system bash-completion package may be absent or outdated.

## wezterm/ (vendored shell integration)

`wezterm/wezterm.sh` is a vendored copy of WezTerm's shell integration (OSC 133
semantic zones, OSC 7 cwd reporting, OSC 1337 user vars). It bundles
`bash-preexec` verbatim and self-guards (bash/zsh only, interactive only, skips
`TERM=dumb`/`linux`). See `wezterm/PROVENANCE` for source and update steps.

We **own** this file rather than relying on the system copy because:

- The bundled wezterm runtime archive ships only the binaries + `wezterm
  shell-completion` (tab-completion), not the integration script.
- The only system copy is `/etc/profile.d/wezterm.sh` -- a non-user-writable
  path that also requires a distro wezterm package, both against this loadout's
  no-`/etc`, user-writable, quota-friendly design.

Loaded by `global/bashrc` (when `LOADOUT_CFG_ENABLE_WEZTERM_SHELL_INTEGRATION` is
truthy) through `loadout_find_wezterm_shell_integration` (`bash/functions.sh`).
Resolver order: explicit `LOADOUT_CFG_WEZTERM_SHELL_INTEGRATION` -> this vendored
copy -> paths relative to the installed `wezterm` binary -> shared prefix. Never
`/etc`.

Outside a real WezTerm session (`TERM_PROGRAM != WezTerm` and no
`WEZTERM_PANE`), `global/bashrc` keeps the vendored bash-preexec hooks but
overrides `__wezterm_osc7` to the integration script's fast printf fallback.
This prevents every prompt from blocking in `wezterm set-working-directory` on
plain SSH/tmux sessions where the loadout's `wezterm` wrapper is visible on
`PATH` but no mux/GUI is reachable.

## Prompt & shell integration

> **Read this before touching the prompt block in `global/bashrc`.** It is
> order- and clobber-sensitive, and an "obvious simplification" silently breaks
> the Starship prompt on login shells. This cost real debugging to get right.

### The invariants

1. **The loadout does not own `PROMPT_COMMAND`.** Never `unset` it or overwrite
   it with a fresh value. A preexec framework may be driving the prompt through
   it. Add prompt callbacks with `loadout_add_precmd`, which appends to
   `precmd_functions` when a framework is live and otherwise prepends to
   `PROMPT_COMMAND` -- without clobbering either.
2. **Starship does not always hook via `PROMPT_COMMAND`.** `starship init bash`
   auto-detects an active framework: with `precmd_functions`/`ble.sh` it
   registers `starship_precmd` into the **array** and leaves `PROMPT_COMMAND`
   alone; only with no framework does it use `PROMPT_COMMAND`. So wrapping the
   `eval "$(starship init bash)"` line with `unset`/`export PROMPT_COMMAND` wipes
   the framework's driver and `starship_precmd` never runs.
3. **Echo-restore is `loadout_restore_echo`**, registered via
   `loadout_add_precmd` -- the no-fork, type-ahead-safe replacement for the old
   `stty '$(stty -g)'` snapshot (that snapshot ran an unconditional `tcsetattr`
   every prompt and swallowed the Enter of any type-ahead).

### Why the reset + re-source dance exists

Login shells read `/etc/profile` -> `/etc/profile.d/wezterm.sh` (and `vte.sh`)
**before** our `bashrc`. Those load `bash-preexec`, register `precmd_functions`,
and set `PROMPT_COMMAND` to bash-preexec's install stub. Then our clean-slate
`unset -f $(declare -F ...)` ("clear all functions") **deletes those framework
functions**, leaving dangling references: `PROMPT_COMMAND` calls a now-missing
`__bp_install` ("command not found" every prompt) and `precmd_functions` points
at missing `__wezterm_*`. Non-login shells (`exec bash`) never source
`/etc/profile`, so they have no framework -- which is exactly why the old bug
showed **no Starship prompt at login but a correct one after `exec bash`**.

So the prompt block, in this exact order:

```
1. reset framework state   unset precmd_functions preexec_functions \
                                 __bp_imported bash_preexec_imported PROMPT_COMMAND
2. source loadout wezterm.sh   (re-installs a *working* bash-preexec + wezterm
                                hooks from user-writable space; gives wezterm
                                users semantic zones / OSC7 even without tmux;
                                off-WezTerm shells use printf OSC7 fallback)
3. eval "$(starship init bash)"   (self-hooks onto precmd_functions if present,
                                   else PROMPT_COMMAND -- do NOT touch
                                   PROMPT_COMMAND around it)
4. loadout_add_precmd loadout_restore_echo
```

This converges login and `exec bash` to identical behavior and serves the whole
terminal matrix: raw wezterm, tmux-in-wezterm, tmux-in-st, st/xterm, and
`dumb`/`linux` (where `wezterm.sh` self-skips and Starship uses `PROMPT_COMMAND`).

### How to verify

Use a **real PTY**. `bash -lic '...'` runs a command list with no prompt cycle,
so `precmd_functions` never fire and the bug is invisible:

```bash
tmux new-session -d -s t "env -i HOME=$HOME TERM=xterm bash -li"
sleep 2; tmux send-keys -t t 'echo hi' Enter; sleep 1
tmux capture-pane -p -t t      # expect the Starship prompt, no __bp_install error
tmux kill-session -t t
```

Always test **both** a login shell and `exec bash`.
