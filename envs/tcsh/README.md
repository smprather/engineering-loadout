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

Same shape as bash. `~/.tcshrc` links to `~/.config/tcsh/tcshrc`. The retired
`~/.cshrc` is pruned **only when it is a loadout link** — a regular user file is
left alone (tcsh ignores it while `~/.tcshrc` exists, and `--no-backup` must not
make its deletion permanent). The entrypoint sources, lowest first:

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

Only `global/` and the top-level `tcshrc` entrypoint are loadout-owned. Put your
own settings in `~/.config/tcsh/user/config.csh` and
`~/.config/tcsh/user/tcshrc`; a reinstall never touches them. If
`~/.config/tcsh` is a symlink into a shared tree, the installer materializes it
and moves every existing `corp/site/team/project/user` layer across first — the
same preservation the bash env has (zsh shares it).

Site/system aliases loaded by `/etc/csh.cshrc` before this file (Environment
Modules' `module`/`_module_raw`/`ml`, gawk path helpers, site tooling) are
preserved. The loadout only overrides aliases it defines itself.

For split installs, `loadout install @envs` bakes
`LOADOUT_CFG_SHARED_PREFIX=<shared>/local` into both bash and tcsh global config
defaults. A direct tcsh login then finds shared `bin/`, `TERMINFO_DIRS`, typelibs,
GUI helper paths, and any shared fonts (`FONTCONFIG_FILE`) without relying on the
parent process to export the prefix.

## What you get

Files under `global/` (plus the top-level `tcshrc` entrypoint):

| file | what it does |
|---|---|
| `tcshrc` | PATH, environment, shell options, history, prompt, integrations |
| `config.csh` | the `LOADOUT_CFG_*` defaults |
| `aliases.csh` | the alias set |
| `completions.csh` | hand-written `complete` rules |
| `keybinds.csh` | `bindkey` bindings |
| `modules-init.csh` | Environment Modules selector |
| `git-branch.sh`, `helpers/` | the sh helpers behind the aliases |

Behaviour:

- **PATH** — the loadout's `bin` (honoring `LOADOUT_CFG_SHARED_PREFIX`), plus
  `/usr/local/bin`, `~/.cargo/bin`, `~/.venv/bin`, `~/.opencode/bin`,
  `~/node_modules/.bin`, `~/go/bin` and `~/.local/bin`, each added only when it
  exists. The final order matches bash's: `~/.local/bin`, `~/go/bin`,
  `~/node_modules/.bin`, `~/.opencode/bin`, `~/.venv/bin`, `~/.cargo/bin`, then
  `/usr/local/bin`. NVM comes after those user dirs (bash's `nvm.sh`-then-prepend
  order). A parent bash's exported `NVM_BIN` wins; a direct tcsh login resolves
  `~/.nvm/alias/default`, or the newest installed version, via
  `helpers/nvm-bin` — `nvm.sh` itself is bash-only.
- **Environment** — `EDITOR`/`VISUAL`/`GIT_EDITOR` (interactive only, like bash;
  `ssh host cmd` gets the same environment in both shells), `PAGER`, `MANPAGER`,
  the `LESS_TERMCAP_*` colours (real ESC bytes, like bash),
  `PIP_REQUIRE_VIRTUALENV`, `PYTHONPYCACHEPREFIX`, `COLORTERM`, `EGL_LOG_LEVEL`,
  `TERMINFO_DIRS` (loadout prefix first, then `~/.local/share/terminfo`, matching
  bash), `GI_TYPELIB_PATH`, `QT_QPA_PLATFORM_PLUGIN_PATH`,
  `NVIM_QT_RUNTIME_PATH`, `FONTCONFIG_FILE` (only when the tree carries
  `etc/fonts/loadout-fonts.conf`), `GNUPLOT_DRIVER_DIR` — the shared values the
  bash env exports. With `HOME` unset, the entrypoint recovers it from the passwd
  entry instead of aborting on `HOME: Undefined variable.`
- **Aliases** — the bash alias set: navigation (`b`…`bbbbbbbbbb`, `cdd`…`cdddddd`,
  `p`/`cdp`, `latest`), listing (`ls`/`ll`/`la`/`lh`/`lg`/`lah`/`tree`), editing
  (`vi`/`vim`/`vic`/`vid`/`vii`/`v`/`new`), search (`g`/`sg`/`gv`/`gf`/`gpy`/`gtcl`/
  `f`/`fc`/`h`/`hg`/`gah`), git (`gs`/`gc`/`gp`/`gd`/`ga`/`gr`/`gsp`), LSF/EDA
  (`bq`/`bjobsv`/`bkillall`/`mli`/`ms`/`ma`/`pg`/`pk`/`ipy`…), VNC (`vnc`/`killvnc`…)
  and the utility set. `ls -1` always runs `/bin/ls -1` (eza has no `-1`), and
  `du`/`dum` keep their operands on du's side of the pipe, both via helpers — a
  csh alias cannot branch on its arguments. `new`/`extract_rpm` report a usage
  error when called with no argument instead of failing alias expansion. There is
  no `rm -f` alias: it suppressed `set rmstar`, so `rm *` deleted without asking.
  Aliases for optional tools are defined only when the tool is installed;
  site-specific EDA/LSF aliases are defined unconditionally because they are
  expected on the target farm.
- **Extended keys** — `EXTENDED_KEYS_SUPPORTED` comes from the same
  `helpers/check-extended-keys` logic as bash: kitty/alacritty and an existing
  tmux server with `extended-keys on` are answered cheaply, otherwise a
  Secondary-DA probe. Pending type-ahead is never consumed; a probe that cannot
  run exports `0`, exactly what bash does. The helper is a POSIX wrapper; only
  the timed readiness/read pair runs in an explicit `bash -c` child (see
  `global/helpers/README.md`).
- **Prompt** — cwd, git branch, optional hostname, the username when it is
  highlighted or differs from `$USER`, and the red farm colour under `$LSB_JOBID`.
- **Every directory change lists**, via csh's native `cwdcmd`. It also carries
  OSC 7 (cwd reporting) to the terminal.
- **`set implicitcd`** — typing a bare directory name changes to it.
- **History** — per-PID, inherited from the parent shell, 10000 entries, dedup'd.
- **`LOADOUT_ONLINE`** — the same parallel TCP probe the bash env runs.
- **Fixed-socket ssh-agent** — `LOADOUT_CFG_ENABLE_SSH_AGENT=1` exports
  `SSH_AUTH_SOCK=$HOME/.ssh/loadout-agent.sock` and starts an agent there when
  none is listening. The path is fixed, so anything outside this one shell can
  find the agent. `ssh-add` is NOT run for you: a passphrase-protected key
  would prompt on every new shell. Off by default, exactly like the bash env.
  The switch is defined by **this** env's `config.csh` — `env-tcsh` does not
  depend on `env-bash`, so it carries its own copy of every switch it reads
  (`tests/env-shell-parity` fails on a switch the env reads but never
  defines).

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
- **`prompt-markers` / `prompt-redraw`** — the starship prompt's tcsh adapter
  (markers, path colour, python label, the line split) and the Ctrl-L redraw
  that reprints the upper prompt lines. See the prompt section below.
- **`seed-history`** — derives the parent pid from `/proc` because **tcsh has no
  `$PPID`**. Naming `$PPID` in the rc file makes every interactive shell print
  `PPID: Undefined variable.` on startup.
- **`private-dir`** — the tcsh twin of bash's `loadout_private_dir`: succeeds only
  for a directory private to you (created 0700; never a symlink; your uid;
  tightened to 0700 — an own 0775 from UPG umask 002, whose group is your
  private group, is fixed; other write, or group write with a shared group, is
  refused and left alone). `PYTHONPYCACHEPREFIX` and the `XDG_RUNTIME_DIR` fallback
  under `$LOADOUT_CFG_SHM_DIR` (default `/dev/shm`) are used only when it passes;
  otherwise the pycache prefix stays unset and the runtime dir falls back to
  `~/.cache/loadout/runtime`. `seed-history` applies the same chain. See the
  "Private runtime dirs" section of `envs/bash/global/README.md`.

## What you do not get, and why

These are absent because **upstream ships no tcsh target for them** — not
because the port stopped early. Each is a dependency on a generated shell snippet
that only exists for bash/zsh/fish.

| | why |
|---|---|
| fzf keybindings (`Ctrl+T`, `Ctrl+R`, `Alt+C`) | `fzf --bash` / `--zsh` / `--fish` only. fzf itself works fine as a command. |
| zoxide (`z` / `zi`) | `zoxide init` has no tcsh target. |
| OSC 133 semantic zones | Needs a preexec framework (bash-preexec), which csh does not expose. OSC 7 cwd reporting IS carried, by `cwdcmd` (see above). |
| IceCream-Bash (`ic`/`icp`/`ict`/`ictp`) | A bash function library that relies on `${!var}` indirect expansion and `export -f`. |

**Starship IS supported.** The tcsh prompt used to be hand-rolled because
`starship init` had no tcsh target — that stopped being true when the payload
moved to starship 1.26.0, which ships one (`starship init tcsh`). The prompt is
now starship-driven, exactly like the bash env: the same modules, the same
glyphs, the same git branch and LSF/user handling.

**The hostname follows the switch.** `LOADOUT_CFG_PROMPT_INCLUDE_HOST=1` adds
the short hostname to the prompt. It is honored by the starship prompt (the
`custom.host` module in the shared config) *and* by the hand-rolled fallback
prompt, so the switch means the same thing in every shell. On an LSF node the
hostname is already carried by the `LSF:` tag, so it is not repeated.

**No python snake, and a label instead.** tcsh drops astral (4-byte)
characters when rendering a prompt in a UTF-8 locale, so `$python`'s `🐍`
cannot be shown. Left alone the module reads as a bare `v3.14.8`, which says
nothing; the helper substitutes `python `, so the prompt shows
`python v3.14.8`. bash and zsh keep the real emoji.

**One starship config, shared with bash and zsh; only the path colour differs.**
All three envs read `~/.config/starship/starship.toml`. Starship has **no
config-time environment-variable substitution** (measured: `style = "$VAR"` is
emitted verbatim by `print-config`), so the per-shell path colour cannot be a
config parameter — there is no `STARSHIP_SHELL`-style switch for a *value*.
Instead the colour is applied after starship renders: starship's output already
passes through `global/helpers/prompt-markers` for the zero-width markers, and
that helper also rewrites the directory's SGR from `bold cyan` to `bold
yellow`. So a glance at the prompt still says which shell you are in.

The mapping is not hidden magic: `tests/env-tcsh-starship` parses
`[directory] style` out of the shared config, maps it to the SGR sequence, and
requires the helper to carry exactly that rewrite — change the style without
updating the helper and the gate fails instead of the path silently going cyan.

**STARSHIP_SHELL=sh, on purpose — and it must be set AFTER the init.**
`starship init tcsh --print-full-init` exports `STARSHIP_SHELL=tcsh` itself,
so leaving it unset is not the same as setting it to `sh`. The variable
controls two things, and `sh` is the only value that is right for both:

1. **The shell each module's `when` runs under.** `sh` is POSIX, and every
   expression in the shared config is (`for u in $VAR; do ... done`, `test`,
   `[ ]`). Under `tcsh` — which is what the init sets — `custom.username`'s
   `for` loop cannot parse at all, so that module silently never appears: no
   error, no username in the prompt.
2. **The zero-width marker syntax starship emits.** `sh` emits none.
   `bash` emits readline's `\[ ... \]`, which tcsh prints literally because
   it has no readline; `tcsh` emits zsh's `%{ ... %}`.

**The performance trap, which is the reason this matters at all.** Starship
runs each module's `when` AND `command` as a subprocess. If that subprocess
is `tcsh`, it **sources `~/.tcshrc`** — tcsh does that for non-interactive
shells too — so every module, on every prompt, pays the whole loadout rc.
On one deployment that was 2 s per module, twice, i.e. a 4 s prompt.

Both configs therefore give **every `[custom.*]` an explicit
`shell = ["/bin/bash"]`**, which overrides `STARSHIP_SHELL` for both `when`
and `command`. Measured with a 1 s delay injected into the rc: 3.84 s without
the explicit shell, 1.52 s with it — and 1.52 s even with
`STARSHIP_SHELL=tcsh`, which is the proof the module shell is what decides.
`tests/env-tcsh-starship` fails if any custom module lacks it, and if the
`STARSHIP_SHELL=sh` pin is missing, changed, or placed above the init.

`global/helpers/prompt-markers` still exists: with `sh` the prompt carries no
markers of its own, so the helper wraps the colour sequences in `%{ %}` itself.
It also SPLITS the prompt: tcsh draws a `\n` inside `$prompt` as padding up to a
soft wrap, which tmux zoom/resize (and any terminal that reflows on resize)
re-wraps into one merged row. So every line but the last is printed as real
output above the prompt, and only the last line (`❯`) is `$prompt`. tcsh
redraws only `$prompt`, so Ctrl-L is bound to `global/helpers/prompt-redraw`,
which clears and reprints the upper lines from a per-tty cache before tcsh
redraws the prompt and your typed input. Details: `docs/STARSHIP.md` §5c.

The full measurements — the marker table for every value, the `init`-exports-
`tcsh` trap, why there is no config-time env-var substitution, and the
commands that reproduce all of it — are in **`docs/STARSHIP.md`**.

Two caveats on the starship prompt in tcsh:

- **Some starship modules have no tcsh equivalent.** A module that reads the
  SHELL's own state (the `jobs` module is the classic one) cannot work here,
  because tcsh exposes no such hook to starship. The shared config's `format`
  does not include `$jobs`, so nothing is lost here; if you add a
  shell-state module to the config, expect it to be blank under tcsh.
- **The hand-rolled prompt is still there, as the fallback.** With
  `LOADOUT_CFG_ENABLE_STARSHIP=0`, or on a host with no starship binary, the
  original tcsh prompt is used — it needs no external binary. The two paths
  never fight: the hand-rolled one is skipped when starship owns `prompt` and
  the `precmd` alias.

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

### `>&2` does not mean stderr in tcsh

When instrumenting this env, never write `echo ... >&2`. In tcsh `>&` means
"redirect stdout **and** stderr to a *file*", so `>&2` silently creates a file
named **`2`** in the current directory. Verified:

```sh
tcsh -f -c 'echo HELLO >&2'   # -> creates ./2 containing HELLO; nothing on stderr
```

This has bitten this repo twice: a stray tracked file named `2` was committed
from exactly this mistake. To reach stderr, `echo ... > /dev/stderr`; to
discard, `>& /dev/null`.

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
