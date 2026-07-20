# tcsh environment — design

Date: 2026-07-13
Status: approved (design)

## Problem

Most of the >10,000 electrical engineers this project serves run **tcsh**, not
because they chose it but because it is their site's default shell. They are not
shell people; they will not switch. Today the loadout gives them nothing: `envs/`
has bash, zsh, and fish, and a tcsh login sees none of the loadout's PATH, config
variables, or tools.

The goal is a "sorta loadout" experience for those users.

## Goals

- A tcsh login gets the loadout's PATH (honoring `LOADOUT_CFG_SHARED_PREFIX`),
  terminfo, `LOADOUT_CFG_*` variables, a useful alias set, a git-aware prompt, and
  the same six-layer override chain as bash.
- **Silence is the acceptance criterion.** No crashes, no warnings, no stderr, no
  "command not found" noise on startup — on a machine with none of the loadout's
  tools installed, and on one with all of them. A usability turn-off is a bug; a
  missing feature is not.

## Non-goals — read these before adding anything

- **This is a one-time, best-effort port. It does NOT track `envs/bash/`.** When the
  bash env gains a feature, tcsh does not automatically need it. There is
  deliberately **no drift test** between the two: a sync gate would fail CI on every
  future bash change and impose exactly the maintenance cost this project does not
  want to pay for a shell with an expected user count near zero.
- **No Starship.** Upstream has no tcsh support. The prompt is hand-rolled and will
  not match bash. Accepted, not a defect.
- **No function library.** csh has no functions (see below).
- No shell integration (OSC 133), no fzf/zoxide keybindings, no bash-preexec.

## The wall: csh has no functions

`envs/bash/functions.sh` has 28 functions. csh has **no function construct at all**.
An alias can carry a one-liner with `\!*` argument substitution, but cannot do loops,
locals, or return values. A standalone script cannot modify the calling shell's PATH
or cwd, which is the entire point of most of them.

So:

| bash function | tcsh |
|---|---|
| `path_prepend` / `path_append` / `path_remove` / `path_trim` | ported as aliases — they only manipulate `$path`, which csh has natively |
| `source_if_exists` | ported as an alias (`if (-r X) source X`) |
| `is_truthy`, `vercomp`, `verlte`, `ver_between`, `fpcmp`, `array_slice`, `join_by`, `loadout_detect_online`, `loadout_add_precmd`, `loadout_restore_echo`, the custom `cd` | **absent.** Loops/locals/return values. Documented as absent, not faked. |

Aliases that *call* a dropped function (the `ls` wrapper, the custom `cd`) are
re-expressed directly in csh where the intent is simple (e.g. `alias ll 'eza -l'`) and
dropped where it is not.

## Design

### Layout

Mirrors `envs/bash/` so it is familiar to anyone who has read that:

```
envs/tcsh/
  tcshrc                  entry point -> ~/.config/tcsh/tcshrc; ~/.tcshrc + ~/.cshrc symlink here
  global/
    config.csh            LOADOUT_CFG_* as setenv -- a SNAPSHOT of bash's config.sh
    tcshrc                PATH, env, aliases, prompt, completions
    aliases.csh           the ported alias set
  corp/ site/ team/ project/ user/   user-created, sourced in that order
```

Loading order, each guarded by `if (-r ...)`: `global -> corp -> site -> team ->
project -> user`, `config.csh` for every layer first, then `tcshrc` for every layer —
the same two-pass shape bash uses.

### Config: a snapshot, deliberately

`envs/tcsh/global/config.csh` hand-writes the `LOADOUT_CFG_*` variables that mean
something in tcsh (`SHARED_PREFIX`, `PREFERRED_LS/VI/CAT`, `ENABLE_GRC`,
`PROMPT_INCLUDE_HOST`, the prompt colors) as `setenv`. It is **not** generated from
`envs/bash/global/config.sh` and there is **no** drift test. The file says so in a
header comment, so the next reader does not "fix" it.

### PATH and environment

Same resolution as bash: prepend `${LOADOUT_CFG_SHARED_PREFIX:-$HOME/.local}/bin` when
it exists, prepend `$HOME/.local/share/terminfo` to `TERMINFO_DIRS`, export
`GI_TYPELIB_PATH` / `QT_QPA_PLATFORM_PLUGIN_PATH` when their dirs exist. Every one is
guarded by a `-d` test, so a machine with no loadout install sets nothing and says
nothing.

### Prompt

A `precmd` alias sets `prompt` with cwd and, inside a git work tree, the branch. It
must be cheap: `precmd` runs before every prompt, and a naive implementation forks
`git` twice per keystroke-return. Guard on `where git` once at startup; use a single
`git symbolic-ref --short HEAD` with stderr redirected. No network, ever.

### Aliases

Port the subset that carries the daily-driver feel: `b`/`bb`/… (cd up N), `ll`/`la`/`lh`
(eza/ls with fallback), `g` (rg with grep fallback), `f` (fd with find fallback), `vi`
(`$LOADOUT_CFG_PREFERRED_VI`), `cat` (bat when present), git shortcuts (`gs`, `gc`,
`gp`, `gd`, `ga`), `h` (history | grep), `x` (chmod +x), `rp` (realpath). Each tool
alias is defined **only if the tool exists** (`where`), so an alias never resolves to a
missing binary.

### Packaging

`env-tcsh`, `kind: env`, `source: envs/tcsh/`, `install_to: ~/.config/tcsh`, in `@envs`.
A custom `_install_env_tcsh` handler (the generic one's `sync_dir(delete=True)` would
wipe user layers, same trap as `env-st`): sync `global/` with delete semantics, create
the empty layer dirs, and link `~/.tcshrc` and `~/.cshrc` to the installed entry point,
removing any prior loadout-owned copies first.

tcsh itself is **not bundled** — it is the site's shell, already present on every
machine that needs this.

## Testing

`tests/install-env-tcsh`. Skips cleanly with a printed SKIP when no `tcsh` is on PATH
(the dev box has none); the Tier 3 `almalinux:8.10` container installs tcsh, so it runs
there for real. Asserts:

1. **Startup produces empty stderr** — both `tcsh -l` (login) and `tcsh -i` (interactive
   non-login), in a fresh HOME. This is the headline requirement, so it is the headline
   test.
2. Same, on a HOME with **no loadout tools installed at all** (env-only install): still
   empty stderr, still exit 0. This is the farm-node case that would otherwise spew.
3. PATH contains the loadout bin dir; `LOADOUT_CFG_*` are set.
4. A representative alias resolves (`alias b` is defined; `where ll` succeeds).
5. Reinstall does not clobber a user-created `user/` layer (the `env-st` lesson).

## Risks

- **csh quoting is a minefield** (`!` in aliases needs escaping; `"` vs `'` differ from
  sh). Mitigation: every alias goes through the real tcsh in the test, not review.
- **`precmd` cost.** A slow prompt is a usability turn-off, which is the one thing we
  said we would not ship. Keep it to at most one `git` fork, guarded.
- **Drift.** Accepted and documented; see Non-goals.
