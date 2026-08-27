# tcsh environment

A loadout environment for tcsh: PATH, `LOADOUT_CFG_*` variables, terminfo, the
bash alias surface reimplemented as tcsh aliases/helpers, a git-aware prompt,
and the same six-layer override chain as bash.

## Installing it

`env-tcsh` is still marked `optional: true` so it is skipped by tool-only groups
like `@shared`, but it is a first-class member of `@envs` because tcsh is the
majority interactive shell for the target EE users.

```
./loadout install env-tcsh     # by name
./loadout install @envs        # bash + tcsh majority-shell config
./loadout install @envs-all    # every env bundle, optionals included
```

## Read this before "fixing" anything

**This environment tracks `envs/bash/`. A bash-env change is not finished until the
tcsh form lands.**

This reverses the policy that stood from 2026-07-13 to 2026-08-08. That policy called
this a deliberate one-time port, refused a drift test, and justified both on an
expected user count "close to zero". **That premise was wrong.** The EE community this
project serves is roughly **90% tcsh** — it is the majority shell of the target
audience, not a courtesy port. Every argument for not tracking rested on the bad
premise, so all of them go with it.

If you are adding an alias, a `LOADOUT_CFG_*` variable, or an environment export to
the bash env, add the tcsh equivalent in the same change.

**"csh has no functions" is not an exemption.** It selects the implementation, not
whether the feature ships:

| what the bash version needs | the tcsh form |
|---|---|
| a one-line wrapper around a command | an alias — they take args (`\!:1`, `\!*`, `\!:2-`) |
| loops, locals, `case`, arithmetic | a POSIX-sh helper in `global/helpers/`, aliased |
| to change the caller's cwd/PATH/env | a helper that *prints* the command, run through `` eval `helper` `` |

`global/git-branch.sh` is the original precedent for the second row.

Startup silence is still a hard requirement — a warning on startup is a bug — but it
is now the floor rather than the goal.

## The layer chain

Same shape as bash. `~/.tcshrc` and `~/.cshrc` both link to
`~/.config/tcsh/tcshrc`, which sources, lowest first:

```
global -> corp -> site -> team -> project -> user
```

`config.csh` for every layer first (preferences), then `tcshrc` for every layer
(PATH, aliases, prompt). Every source is guarded — a layer you have not created is
normal, not an error.

`TCSH_CONFIG_ROOT_DIR` mirrors bash's `BASH_CONFIG_ROOT_DIR` and zsh's
`ZSH_CONFIG_ROOT_DIR`. It defaults to `~/.config/tcsh`, but can point at a shared
loadout-owned tcsh config root. When it differs from the user's home config root,
the entrypoint still sources the home-local `corp/site/team/project/user` layers
after the shared root, so personal overrides survive shared config deployments.

Only `global/` is loadout-owned. Put your own settings in
`~/.config/tcsh/user/config.csh` and `~/.config/tcsh/user/tcshrc`; a reinstall never
touches them.

For split installs, `loadout install @envs` bakes
`LOADOUT_CFG_SHARED_PREFIX=<shared>/local` into both bash and tcsh global config
defaults. A direct tcsh login then finds shared `bin/`, `TERMINFO_DIRS`, typelibs,
and GUI helper paths without relying on the parent process to export the prefix.

## What you get

Files, all under `global/`:

| file | what it does |
|---|---|
| `tcshrc` | PATH, environment, shell options, history, prompt, integrations |
| `config.csh` | the `LOADOUT_CFG_*` defaults |
| `aliases.csh` | the alias set |
| `completions.csh` | hand-written `complete` rules |
| `keybinds.csh` | `bindkey` bindings |
| `grc-aliases.csh` | Generic Colorizer aliases, csh form |
| `modules-init.csh` | Environment Modules selector |
| `git-branch.sh`, `helpers/` | the sh helpers behind the aliases |

Behaviour:

- **PATH** — the loadout's `bin` (honoring `LOADOUT_CFG_SHARED_PREFIX`), plus
  `/usr/local/bin`, `~/.cargo/bin`, `~/go/bin`, `~/.venv/bin`, `~/.opencode/bin`,
  `~/node_modules/.bin` and NVM's `$NVM_BIN`, each added only when it exists.
- **Environment** — `EDITOR`/`VISUAL`/`GIT_EDITOR`, `PAGER`, `MANPAGER`, the
  `LESS_TERMCAP_*` colours, `PIP_REQUIRE_VIRTUALENV`, `PYTHONPYCACHEPREFIX`,
  `COLORTERM`, `EGL_LOG_LEVEL`, `TERMINFO_DIRS`, `GI_TYPELIB_PATH`,
  `QT_QPA_PLATFORM_PLUGIN_PATH`, `NVIM_QT_RUNTIME_PATH`, `GNUPLOT_DRIVER_DIR` —
  the same values the bash env exports.
- **Aliases** — the bash alias set: navigation (`b`…`bbbbbbbbbb`, `cdd`…`cdddddd`,
  `p`/`cdp`, `latest`), listing (`ls`/`ll`/`la`/`lh`/`lg`/`lah`/`tree`), editing
  (`vi`/`vim`/`vic`/`vid`/`vii`/`v`/`new`), search (`g`/`sg`/`gv`/`gf`/`gpy`/`gtcl`/
  `f`/`fc`/`h`/`hg`/`gah`), git (`gs`/`gc`/`gp`/`gd`/`ga`/`gr`/`gsp`), LSF/EDA
  (`bq`/`bjobsv`/`bkillall`/`mli`/`ms`/`ma`/`pg`/`pk`/`ipy`…), VNC (`vnc`/`killvnc`…)
  and the utility set. Each tool alias is defined **only if the tool is installed**.
- **Prompt** — cwd, git branch, optional hostname, the username when it is
  highlighted or differs from `$USER`, and the red farm colour under `$LSB_JOBID`.
- **Every directory change lists**, via csh's native `cwdcmd`. It also carries
  OSC 7 (cwd reporting) to the terminal.
- **`set implicitcd`** — typing a bare directory name changes to it.
- **History** — per-PID, inherited from the parent shell, 10000 entries, dedup'd.
- **`LOADOUT_ONLINE`** — the same parallel TCP probe the bash env runs.

### The helper scripts

`global/helpers/` is what lets "csh has no functions" stop being a reason to drop
a feature. Each is POSIX sh, shellcheck-clean, and silent on the boring path;
`helpers/README.md` explains the three calling shapes. A helper that must change
the shell's own cwd or environment *prints* the csh command and the alias
`eval`s it — that is how `latest` and `cdd` work.

Two of them are worth knowing about specifically:

- **`prompt-color`** — `LOADOUT_CFG_PROMPT_COLOR_*` is shared with the bash env
  and **exported** there, so a tcsh launched from a loadout bash shell inherits a
  *bash* prompt string wrapped in readline's `\[` / `\]` zero-width markers. tcsh
  prints those literally. This strips them and turns a literal `\033`/`\e` into a
  real ESC byte; `%{…%}` in the prompt is tcsh's own zero-width wrapper.
- **`seed-history`** — derives the parent pid from `/proc` because **tcsh has no
  `$PPID`**. Naming `$PPID` in the rc file makes every interactive shell print
  `PPID: Undefined variable.` on startup.

## What you do not get, and why

These are absent because **upstream provides no tcsh support at all** — not because
the port stopped early. Each is a dependency on a generated shell snippet that only
exists for bash/zsh/fish.

| | why |
|---|---|
| Starship | `starship init` has no tcsh target. The prompt here is hand-rolled and does not match the bash one. |
| fzf keybindings (`Ctrl+T`, `Ctrl+R`, `Alt+C`) | `fzf --bash` / `--zsh` / `--fish` only. fzf itself works fine as a command. |
| zoxide (`z` / `zi`) | `zoxide init` has no tcsh target. |
| OSC 133 semantic zones / OSC 7 cwd | Needs a preexec framework (bash-preexec). tcsh's `precmd`/`postcmd` can carry OSC 7, which the prompt block does; full 133 zoning needs per-command hooks csh does not expose. |
| IceCream-Bash (`ic`/`icp`/`ict`/`ictp`) | A bash function library that relies on `${!var}` indirect expansion and `export -f`. |

Everything else in the bash env has a tcsh form and should have one here. If you find
a gap that is not in this table, it is a bug, not a design decision.

## The prompt, and why there is a shell script next to it

`global/git-branch.sh` exists because **csh cannot redirect stderr separately from
stdout** — there is no `2>/dev/null`. An inline branch lookup has to use `|&`, which
merges git's *error text* into the captured value. In a repo with no commits yet
(unborn HEAD), that renders git's multi-line "Use `--` to separate paths from
revisions" hint directly into your prompt. The helper script does the redirect in sh,
where it is possible, and prints nothing when you are not in a repo.

It uses `git symbolic-ref` rather than `git rev-parse --abbrev-ref`, because
`symbolic-ref` resolves correctly on an unborn HEAD; a detached HEAD falls back to a
short sha.

## Testing

`tests/install-env-tcsh`. It skips cleanly where there is no tcsh (the dev box) and
runs for real in the Tier 3 `almalinux:8.10` container.

The headline assertion is **empty stderr** on startup — interactive and login, on a
HOME with no loadout tools installed at all.

**Three** harness traps are documented in that file, and every one of them produces
a green run that proves nothing:

1. `tcsh -i -c CMD` does **not** set `$prompt`, so it silently skips the entire
   interactive block — a silence test written that way passes without running the
   code under test.
2. A piped tcsh with no controlling terminal prints `Warning: no access to tty` to
   stderr, which looks exactly like the noise you are testing for. Hence the real
   PTY (`script -qec`).
3. **`script` gives the child a PTY, so tcsh's own diagnostics come back on
   stdout and `$ERRFILE` stays empty.** The headline "empty stderr" assertion
   cannot see a shell that complains on every startup. Two real bugs shipped
   through that hole during the 2026-08-08 parity work — `PPID: Undefined
   variable.` and `0: Event not found.` — both printing on every interactive
   start while the test was green. `assert_no_csh_noise` now scans the output for
   tcsh's error vocabulary, and both bugs were re-introduced deliberately to
   confirm it fails.
