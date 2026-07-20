# tcsh environment

A loadout environment for tcsh: PATH, `LOADOUT_CFG_*` variables, terminfo, ~30
aliases, a git-aware prompt, and the same six-layer override chain as bash.

## Installing it

`env-tcsh` is **opt-in** (`optional: true`): it is not in `@envs`, and not in the
`@engineering-loadout` full-bundle sweep. Nobody gets a tcsh config they did not ask for.

```
./loadout install env-tcsh     # by name
./loadout install @envs-all    # every env bundle, optionals included
```

## Read this before "fixing" anything

**This is a deliberate one-time port. It does not track `envs/bash/`.**

There is no generator and no drift test between the two. That is on purpose: a sync
gate would fail CI on every future bash-env change and impose ongoing maintenance
cost on a shell whose expected user count is close to zero. If the bash env gains a
feature, tcsh does not automatically need it.

It exists because most of the engineers this project serves are on tcsh only because
it is their site's default — not by choice, and not by interest. The bar is: **it
works, it is quiet, and it never gets in their way.** A warning on startup is a bug.
A missing feature is not.

## The layer chain

Same shape as bash. `~/.tcshrc` and `~/.cshrc` both link to `~/.config/tcsh/tcshrc`,
which sources, lowest first:

```
global -> corp -> site -> team -> project -> user
```

`config.csh` for every layer first (preferences), then `tcshrc` for every layer
(PATH, aliases, prompt). Every source is guarded — a layer you have not created is
normal, not an error.

Only `global/` is loadout-owned. Put your own settings in
`~/.config/tcsh/user/config.csh` and `~/.config/tcsh/user/tcshrc`; a reinstall never
touches them.

## What you get

- **PATH** — the loadout's `bin` (honoring `LOADOUT_CFG_SHARED_PREFIX` for shared
  installs), plus `~/.cargo/bin`, `~/go/bin`, added only when they exist.
- **terminfo** — `~/.local/share/terminfo` on `TERMINFO_DIRS`, so `st-256color` and
  friends resolve.
- **Aliases** — `b`/`bb`/`bbb`… (cd up), `ll`/`la`/`lh` (eza, falling back to ls),
  `g` (rg, falling back to grep), `f` (fd, falling back to find), `vi`, `cat` (bat),
  `gs`/`gc`/`gp`/`gd`/`ga`, `h`, `x`, `rp`, `t`, `w`. Each tool alias is defined
  **only if the tool is installed**, so an alias never points at a missing binary.
- **Prompt** — cwd plus the git branch when you are in a repo.

## What you do not get, and why

| | why |
|---|---|
| The `functions.sh` library (26 of 28) | **csh has no functions.** Not a gap in the port — the language has no function construct. Aliases cannot do loops, locals, or return values, and a standalone script cannot change the calling shell's PATH or cwd. `path_prepend` / `path_append` survive as aliases because they only touch `$path`, which csh has natively. `is_truthy`, `vercomp`, `array_slice`, `join_by`, `loadout_detect_online`, the custom `cd`, and the rest are **absent by design**. |
| Starship | No upstream tcsh support. The prompt here is hand-rolled and does not match the bash one. |
| Shell integration (OSC 133), fzf/zoxide keybindings, tmux auto-attach | No csh equivalent worth the maintenance. |

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

Two harness traps are documented in that file and are worth knowing before you touch
it: `tcsh -i -c CMD` does **not** set `$prompt`, so it silently skips the entire
interactive block (a silence test written that way passes without running the code
under test); and a piped tcsh with no controlling terminal prints
`Warning: no access to tty` to stderr, which looks exactly like the noise you are
testing for. The test uses a real PTY (`script -qec`) for that reason.
