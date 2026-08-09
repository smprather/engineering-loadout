# zsh environment

A loadout environment for zsh: PATH, the shared `LOADOUT_CFG_*` variables, the
full bash alias set, zsh-native completion, key bindings, history, prompt, and
OSC 133 shell integration — with the same six-layer override chain as bash.

## Installing it

`env-zsh` is not optional, but it is not in `@envs` (which is Bash-only). Get it
by name or with the full env sweep:

```
./loadout install env-zsh      # by name
./loadout install @envs-all    # every env bundle
```

It `depends` on `env-bash`, and that is load-bearing rather than incidental —
see below.

## Read this before "fixing" anything

**This environment tracks `envs/bash/`. A bash-env change is not finished until
the zsh form lands.** `tests/env-shell-parity` enforces it.

**It tracks by REUSE, not by reimplementation.** zsh has functions, arrays and
`local`, so unlike the tcsh port it does not rewrite the bash env — it sources
it:

| file | sourced from |
|---|---|
| `envs/bash/functions.sh` | the entry point, first |
| `envs/bash/global/config.sh` (+ the corp…user layers) | pass 1 |
| `envs/bash/global/aliases.sh` | `global/zshrc` |

That is why `env-zsh` depends on `env-bash`, and why the alias surface tracks
**automatically** instead of by discipline: there is one alias file, not two.

**The consequence is that those three files are SHARED CODE, and a bashism in
any of them is a zsh bug.** This is not theoretical — the following were all
found by running them under zsh, and all of them were also latent bugs for bash
users:

- `path_modify` / `path_trim` / `std_paths` used bash's `${!var}` indirect
  expansion and 0-based array indexing, so the documented two-arg form
  (`path_append LD_LIBRARY_PATH /opt/lib`) died with `bad substitution`. The
  one-arg PATH form worked, which made it look fine.
- `pl` lower-cased with `${var,,}` (bash 4 only) — a runtime parse error under
  zsh, so `pl` simply did not work.
- `a` dumped functions with `declare -f`; `typeset -f` means the same thing in
  bash and is the only spelling zsh knows.
- `check_extended_keys` probed the terminal and read the reply with
  `read -r -d 'c'`, which **ate the user's type-ahead** up to their first `c`
  when the terminal did not answer. Typing `echo MARK` during startup ran
  `ho MARK`. This one affected bash equally; `tests/shell-typeahead` now pins it.
- `loadout_detect_online` backgrounded its probes directly, and zsh reports
  jobs it owns — so every startup printed `[9] 2825450` / `[9] + done …`.

## The layer chain

`~/.zshenv`, `~/.zshrc` and `~/.zprofile` all link to `~/.config/zsh/zshrc`,
which sources, lowest first:

```
global -> corp -> site -> team -> project -> user
```

`config.zsh` for every layer first, then `zshrc` for every layer. Only `global/`
is loadout-owned; put your own settings in `~/.config/zsh/user/config.zsh` and
`~/.config/zsh/user/zshrc`.

**Why all three entry points.** zsh splits startup files by shell *type*:
`.zshenv` for every zsh including `zsh script.zsh`, `.zprofile` for login
shells, `.zshrc` for **interactive shells only**. Linking just `.zshrc` and
`.zprofile` — which this package used to do — meant a script got no PATH and
none of the exported environment. Linking `.zshenv` fixes that at the cost of an
interactive shell sourcing the file twice, so the entry point carries a
re-entry guard (`_LOADOUT_ZSH_SOURCED`, deliberately not exported).

## What zsh does natively, and better

Three places where zsh's own mechanism beats porting bash's, and is used:

| | |
|---|---|
| **`chpwd` hook** | "every directory change lists" needs no `cd` wrapper. The bash env has to put the `ls` inside `cd()` and then route `zoxide` and `latest` back through it; here `builtin cd`, `pushd`, `popd` and `AUTO_CD` all fire the hook, so no call site can forget. |
| **`AUTO_CD`** | a bare directory name changes to it — replaces the `trap … ERR` hack the bash env uses for the same thing, which cannot misfire on an unrelated failed command. |
| **native `precmd`/`preexec`** | full OSC 133 semantic zones. The vendored `wezterm.sh` is the bash-preexec variant with no zsh path at all, so `global/wezterm-integration.zsh` implements the protocol directly — smaller and more robust than sourcing it. |

Hooks are registered by appending to the `${hook}_functions` arrays directly,
**not** via `add-zsh-hook`. `add-zsh-hook` is an autoloaded function from the
zsh function library, which an env-only HOME (config installed, runtime not)
does not have — so every hook registered through it silently never fired.

## What you do not get, and why

| | why |
|---|---|
| IceCream-Bash (`ic`/`icp`/…) | relies on `${!var}` indirection and `export -f`. |
| bash-format completions, by default | `bashcompinit` bridges them, but it is a shim and a completion that reaches into `COMP_WORDS` can misbehave. Opt in with `LOADOUT_CFG_ZSH_ENABLE_BASHCOMPINIT=1`. The native ones (`uv`, `ruff`, `ty`) and zsh's own `_*` functions always load. |

Starship, fzf and zoxide **do** all work — unlike tcsh, upstream ships real zsh
support for each.

## zsh-only configuration

The shared defaults are not duplicated here; `global/config.zsh` holds only what
exists *because* the shell is zsh:

| variable | default | purpose |
|---|---|---|
| `LOADOUT_CFG_PREFERRED_ZSH` | `""` | re-exec into this zsh at startup (analogue of `LOADOUT_CFG_PREFERRED_BASH`) |
| `LOADOUT_CFG_ZSH_ENABLE_COMPLETION` | `1` | run `compinit` — the most expensive part of startup on a networked filesystem |
| `LOADOUT_CFG_ZSH_ENABLE_BASHCOMPINIT` | `0` | load the bash-format loadout completions through the compatibility shim |

## Testing

`tests/install-env-zsh` (Tier 2) and `tests/shell-typeahead` (Tier 1). Both skip
cleanly where zsh or `script` is unavailable.

The headline assertion is a clean start on an env-only HOME. **Three harness
traps** are documented in the test, each of which produces a green run that
proves nothing:

1. `zsh -i -c CMD` does not drive the interactive line editor; commands must be
   fed on stdin.
2. A pipe is not a terminal — `script -qec` is required, or the `[[ -t 0 ]]`
   guards short-circuit the code under test.
3. **`script` gives the child a PTY, so zsh's own diagnostics arrive on stdout
   while stderr stays empty.** A stderr-only assertion cannot see a shell
   complaining on every startup, and the zsh env shipped three such complaints
   (`no matches found: …zsh_history.*`, a failed `zsh/mathfunc` load, and
   background-job notices). `assert_no_zsh_noise` scans the output too.

`env -i` in the test harness is also load-bearing: without it the surrounding
loadout bash session's exported `LOADOUT_CFG_*` and PATH leak in, and the test
measures the developer's shell instead of a fresh farm HOME.
