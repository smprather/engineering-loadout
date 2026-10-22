# Starship: measured behavior

Everything here was **measured against the shipped binary** (starship 1.27.0,
on a host where `/bin/sh -> bash`), not taken from the docs. Re-verify with the
commands in each section — they take seconds. Recorded 2026-10-22 because the
first pass at this cost an hour of exploration.

Shipped config: `envs/starship/starship.toml` (installed as
`~/.config/starship/starship.toml`). The tcsh twin is
`envs/tcsh/global/starship-tcsh.toml`, pinned identical apart from the
`[directory]` style by `tests/env-tcsh-starship`.

---

## 1. `STARSHIP_SHELL` controls TWO things

It is not just "which shell runs the module commands". It also selects the
**zero-width marker syntax** starship emits. That is why no single value is
right for every shell, and why this is per-env:

| `STARSHIP_SHELL` | markers emitted | shell `when`/`command` run under |
|---|---|---|
| `bash` | readline `\[ \]` | bash |
| `zsh` | `%{ %}` | zsh |
| `tcsh` | `%{ %}` | **tcsh** |
| `sh` | **none** | POSIX sh |
| unset | none | `sh` |

```sh
for s in bash zsh tcsh sh; do
  printf '%-5s -> ' "$s"
  STARSHIP_SHELL=$s STARSHIP_CONFIG=envs/starship/starship.toml \
    TERM=xterm-256color starship prompt | cat -v | head -1 | cut -c1-50
done
```

Note `TERM=xterm-256color` (or any real TERM) — under `TERM=dumb` starship
prints nothing and says so.

## 1b. A per-module `shell = [...]` OVERRIDES `STARSHIP_SHELL` — for `when` too

This is the load-bearing mechanism that keeps a prompt render from ever
invoking a shell rc. Measured: with `STARSHIP_SHELL=/bin/zsh` and
`shell = ["/bin/bash"]` on the module, BOTH the `when` expression and the
`command` ran under `/usr/bin/bash` (control, no per-module `shell`: both ran
under `/usr/bin/zsh`).

Every `[custom.*]` in both configs therefore carries `shell = ["/bin/bash"]`.
That is what makes the prompt cost independent of `STARSHIP_SHELL` — see §1c.

## 1c. The 4-second prompt: shelling out to tcsh/zsh re-enters that shell's rc

**Symptom (reported from a deployment system):** the tcsh prompt took ~4 s to
render — "the tcsh rc sequence was 2 s × run twice".

**Mechanism:** starship runs each module's `when` AND `command` as a
subprocess of `STARSHIP_SHELL`. If that is `tcsh`, each spawn is a `tcsh -c`
that **sources `~/.tcshrc`** (tcsh sources it for non-interactive shells too),
i.e. the whole loadout rc, per module, per prompt. Same class for `zsh`:
`zsh -c` **sources `~/.zshenv`** even non-interactively (`starship init zsh`
sets `STARSHIP_SHELL=zsh` itself, so this was latent in the zsh env).

**Measured** with a `sleep 1` injected at the tcshrc's interactive guard to
simulate the slow box (delete it afterwards — it is only for this test):

| config | prompt render |
|---|---|
| `pin=tcsh`, no per-module `shell` — **the old bug** | **3.84 s** |
| `pin=tcsh` + `shell = ["/bin/bash"]` | 1.52 s |
| `pin=sh` + `shell = ["/bin/bash"]` | 1.52 s |
| `pin=sh`, no per-module `shell` | 1.52 s |

So the per-module `shell` is the structural fix: it removes the dependence on
`STARSHIP_SHELL` entirely. **A prompt render must never invoke a shell that
sources an rc** — and with `shell = ["/bin/bash"]` plus a non-rc shell for
`STARSHIP_SHELL` (`sh`), none can.

Reproduce the slow case:

```sh
# copy envs/tcsh, inject `sleep 1` before the line-anchored `if ( $?prompt ) then`
# (NOT the one in the header comment -- anchoring matters), then time `tcsh -i`.
```


## 2. Each env must pin its own value

| env | pin | why |
|---|---|---|
| bash | `STARSHIP_SHELL=bash` | PS1 needs readline's `\[ \]` to compute the prompt width; unset emits no markers |
| zsh | `STARSHIP_SHELL=sh` | `zsh` re-enters `~/.zshenv` per module (§1c). `sh` is POSIX and marker-free |
| tcsh | `STARSHIP_SHELL=sh` | `tcsh` re-enters `~/.tcshrc` per module (§1c); `bash` emits readline markers that tcsh prints literally |

And **every `[custom.*]` carries `shell = ["/bin/bash"]`**, so the shell-out is
pinned to bash no matter what `STARSHIP_SHELL` says (§1b). `tests/env-shell-parity`
gates the three pins; `tests/env-tcsh-starship` gates that each custom module in
both configs has the explicit shell.

Measured A/B on prompt width: `STARSHIP_SHELL=sh` (no markers at all) and
`bash` + the `prompt-markers` helper (which rewrites `\[ \]` → `%{ %}`) put the
cursor at the **same column** (104) after 100 typed characters in an 80-column
PTY. So the marker-free prompt does not regress width in practice; the
`%{ %}`-wrapping the repo's hand-rolled prompts do is still the belt — see
`envs/tcsh/global/helpers/prompt-markers`.

## 3. The tcsh trap: `starship init tcsh` exports `STARSHIP_SHELL=tcsh` itself

```sh
starship init tcsh --print-full-init | head -1     # -> setenv STARSHIP_SHELL tcsh;
```

So "leave it unset" is NOT the same as "set it to `sh`". Unpinned, the shared
config's `when` expressions run under **tcsh**, where
`custom.username`'s `for u in $VAR; do ... done` cannot parse — that module
**silently never appears**, with no error and no missing-username hint.

The tcsh env therefore sets `STARSHIP_SHELL=sh` **after** the `eval` of the
init, so it overrides starship's own export. Order is load-bearing: before the
init, starship overwrites it back to `tcsh`.

Consequences measured in a real PTY tcsh session:

| value | literal `\[` in prompt | literal `%{` in prompt | `custom.username` |
|---|---|---|---|
| `tcsh` (what the init sets) | 0 | 0 (tcsh parses `%{ %}` natively) | **missing** |
| `bash` (the old pin) | **present — garbage** | 0 | renders |
| `sh` (current) | 0 | 0 | renders |

`bash` was the old pin and is the one value that visibly breaks the prompt.
It is also what made `envs/tcsh/global/helpers/prompt-markers` necessary —
that helper exists to strip the markers the pin produced. With `sh` the prompt
carries none, so the helper is a no-op passthrough; it is kept as the belt.

## 4. There is NO config-time environment-variable substitution

`style = "$MY_STYLE"` is emitted verbatim by `print-config` and rendered as a
literal style string. Verified: setting `MY_STYLE` changes nothing.

```sh
printf 'format = "$custom.d"\n[custom.d]\ncommand = "hostname -s"\nstyle = "$MY_STYLE"\n' > /tmp/t.toml
MY_STYLE="bold green" STARSHIP_CONFIG=/tmp/t.toml starship print-config custom.d | grep style
# -> style = "$MY_STYLE"     (unchanged)
```

So a config **value** cannot follow a `LOADOUT_CFG_*` switch. Only these can:

- `when` — whether the module appears at all (this is how `custom.host`
  honors `LOADOUT_CFG_PROMPT_INCLUDE_HOST` and `custom.lsf` honors `$LSB_JOBID`)
- `command` — what it prints, evaluated at run time in a shell
- a built-in module's `detect_env_vars` — but that tests variable **PRESENCE**,
  not value. Useless for our switches, which are always exported even when `0`.

If a user-tunable color is ever wanted, the only routes are a custom module
whose `command` emits ANSI bytes itself, or generating the config at startup
(the latter breaks the sealed-config invariant — don't).

## 5. `--norc --noprofile` do not do what they look like

A non-interactive bash reads **no** startup files already:

```sh
bash -c 'echo ran'          # sources neither ~/.bashrc nor ~/.bash_profile
```

The one file it does read is `$BASH_ENV`, and **neither flag suppresses it**:

```sh
printf 'echo LEAKED\n' > /tmp/leak.sh
BASH_ENV=/tmp/leak.sh bash -c 'echo ran'                    # -> LEAKED / ran
BASH_ENV=/tmp/leak.sh bash --norc --noprofile -c 'echo ran' # -> LEAKED / ran
```

So a per-module `shell = ["/bin/bash", "--norc", "--noprofile"]` buys nothing,
and `STARSHIP_SHELL` cannot carry flags anyway (it is a shell name). The only
thing that closes the `BASH_ENV` hole is `unset BASH_ENV`. Nothing in this
repo or on the dev host sets `BASH_ENV`, so that is not done — it would be
defending against an unobserved variable.

## 6. Other measured details worth keeping

- **`starship init <shell>` does not export `STARSHIP_SHELL` for bash or zsh**
  (`grep -c` -> 0 and 1 respectively; zsh's own line 89 does
  `export STARSHIP_SHELL="zsh"`). Only tcsh's init does, and only with
  `--print-full-init`.
- **A custom module with no `when` key renders NOTHING.** The schema default
  is `when = false`, so every `[custom.*]` in our configs carries an explicit
  `when`. This looks exactly like "the module is broken" and cost real time.
- **`shell = [...]` on a custom module does work** (`VecOr_string`: a string or
  a list). It just cannot be set globally.
- **`starship module <name>`** prints one module in isolation — the fastest way
  to debug a single module without a shell session.
- **`STARSHIP_LOG=trace starship prompt`** shows config parsing and per-module
  timing.
