# Interactive shell selection (`LOADOUT_CFG_INTERACTIVE_SHELL`)

Date: 2026-11-05
Status: draft for review (rev 2: design review folded in, see *Revision notes*)
Scope: per-user interactive shell choice, without root, without per-terminal config.
Release class: **C**. The `loadout doctor` findings (D7, csh section) touch
`loadout_main.py`, and `docs/RELEASE.md` puts anything touching it in class C
regardless of diff size, so the Tier 3 container gate is required. No payload,
registry or schema change.

## Problem

Users cannot change the shell their terminals, `ssh` sessions and consoles give
them. `chsh` needs a shell listed in `/etc/shells`; the loadout's own binaries
live under `$HOME/.local/share/loadout/bin` and are not in it, and corporate
builds often restrict `chsh` outright. The passwd shell space in the target
environment today is `csh`, `bash`, `zsh`.

EL already has a partial answer: `LOADOUT_CFG_PREFERRED_BASH`, honest name,
bash-only, same-family only. `envs/zsh` and `envs/tcsh` copied it
(`PREFERRED_ZSH`, `PREFERRED_TCSH`). Three variables, three implementations,
none cross-shell — a tcsh-login user, which is the majority of this audience,
cannot use any of them to get zsh.

## What exists today (evidence)

| Shell | Entry file | Exec block | Gate |
|---|---|---|---|
| bash | `~/.bash_profile` → `~/.bashrc` → `envs/bash/bashrc` | `envs/bash/bashrc:189-199` | interactive + `PREFERRED_BASH` set; compares `realpath(/proc/$$/exe)` to the target |
| zsh | `~/.zshenv`/`.zprofile`/`.zshrc` → `envs/zsh/zshrc` → `envs/zsh/global/zshrc` | `envs/zsh/global/zshrc:12-20` | `-o interactive`, compared against `$SHELL` |
| tcsh | `~/.tcshrc` → `envs/tcsh/tcshrc` → `envs/tcsh/global/tcshrc` | `envs/tcsh/global/tcshrc:24-38` | `$?prompt`, compared against `$shell` |

Defects that would be inherited by a fourth variable:

1. `envs/zsh/global/zshrc:17-19` and `envs/tcsh/global/tcshrc:33-35` clear the
   preference (`export ...=""`) before `exec`. The replacement shell and every
   child lose the setting; subprocesses that spawn a shell (tmux, `$SHELL -c`)
   then get the old one.
2. `envs/bash/global/config.sh:2` assigns unconditionally
   (`export LOADOUT_CFG_PREFERRED_BASH=""`), destroying an inherited value. zsh
   uses `: "${VAR:=}"`, tcsh uses `if ( ! $?VAR )` — bash is the odd one out.
3. Only bash compares the running executable (`/proc/$$/exe`); zsh compares the
   target to `$SHELL` and tcsh to `$shell`, neither of which identifies the
   running binary. All three only ever exec into their own shell family, so
   `tcsh → zsh` — the majority audience — is unsupported today.

Terminal-side capability, for the record (`payload/packages.json` ships
`xterm`, `wezterm`, `st`, `xfce4-terminal`, `mate-terminal`, `tmux`):

| Terminal | Shell knob | Usable as the mechanism? |
|---|---|---|
| xfce4-terminal | `run-custom-command` / `custom-command` exist in the shipped 1.0.4 (`terminal-preferences.c:588-620`), so a shell path *can* be set. Independently, 1.0.4 prefers `$SHELL` over the passwd shell when it is executable (`terminal-screen.c:734-755`) | possible, deliberately unused: static value, second source of truth, and it would override `$SHELL` |
| xterm | `-e` / `loginShell` resource only | no |
| wezterm | `config.default_prog` | possible, static |
| st | `st.shell` (our patched build) | possible, static |
| mate-terminal | profile `custom-command` via gsettings | possible, user UI state |
| tmux | `default-shell` | works; `envs/tmux/tmux-global.conf:51` deliberately does not pin it |

Per-terminal config is *possible* for four of six, but it freezes the choice in
each terminal as a separate static value, so a user switching shell edits four
places or runs a regeneration step, and the choice stops following a
`--dest-dir` move. It also reaches none of `ssh`, the console, IDE terminals or
a terminal a user installs themselves. The shell rc reaches all of them, because
EL already owns the rc of every shell in the passwd space — and it is the only
mechanism that can express "whatever this user chose, now" without duplicating
it.

## Decisions

### D1 (user) — one variable, `LOADOUT_CFG_INTERACTIVE_SHELL`

Name fixed by the request. Empty (the default) means "do nothing"; behaviour is
byte-identical to today for every user who does not set it.

Value semantics:

- absolute path → used verbatim when executable;
- bare name → `<shared prefix>/bin/<name>` when executable, else the first match
  on the inherited `PATH`;
- anything else — a relative path (`bin/zsh`), a value with whitespace
  (`zsh -l`, `/usr/bin/env zsh`) — is rejected: no exec and no output (see
  Anti-goals), and `loadout doctor` reports it (D7).

The exec runs before the rc sets PATH, so the second clause searches the PATH
the session handed us, not the one the finished shell will have. A target that
lives only on a loadout-added PATH row must be given as an absolute path; that
is documented rather than solved, because moving the exec after PATH setup would
run the expensive half of the startup in a shell that is about to be replaced.

Bare names are resolved through the loadout tree so a `--dest-dir` install or a
relocated shared tree keeps working; a hardcoded absolute path breaks on the
next move. Any executable name is accepted — bash, zsh, tcsh, csh, fish, an
unpatched distro shell. No allowlist: EL must not rule out a shell it does not
ship a config for.

Prefix-first is a deliberate exception to the PATH contract, under which system
copies keep priority and `prefer/` is the per-tool opt-in. The bare name is
resolved before the rc builds PATH, so there is no finished PATH to follow, and
on most hosts the inherited PATH does not contain the loadout tree at all.
Checking the prefix first is what makes `zsh` mean the same binary on every
host, instead of whichever distro zsh happens to be installed (EL8's 5.5, or
none). A user who wants the system shell gives its absolute path.

Shared prefix resolution matches `envs/bash/global/bashrc:28` and
`envs/tcsh/global/tcshrc:41`: `${LOADOUT_CFG_SHARED_PREFIX:-$HOME/.local/share/loadout}`
(the installer bakes `LOADOUT_CFG_SHARED_PREFIX` for non-default roots,
`loadout_main.py:6037`). Neither rc honours `XDG_DATA_HOME`; the helper must use
the same expression as the rc it lives in, not introduce a third rule.

### D2 (mine) — the mechanism is a one-shot `exec` at the top of the rc, not terminal config

The rc runs before the expensive half of the startup (bash: before
`global/bashrc`; zsh: `global/zshrc` is the first file of pass 2; tcsh: before
PATH/aliases). Exec conditions, all of which must hold. They are listed in
evaluation order: the first is the only work done when the variable is unset
(see Anti-goals), and the forks (`realpath`, PATH lookup) come last.

1. `LOADOUT_CFG_INTERACTIVE_SHELL` is non-empty;
2. the marker `LOADOUT_SHELL_EXEC` is unset (D3);
3. the shell is interactive **and was not given a command string**: bash
   `[[ $- == *i* && -z ${BASH_EXECUTION_STRING:-} ]]`, zsh
   `[[ -o interactive && -o shinstdin ]]`, tcsh `$?prompt` (`tcsh -i -c` does
   not set it, `tests/install-env-tcsh:12-13`);
4. this is a top-level spawn: the shell is a login shell **or**
   `realpath(running shell) == realpath("$SHELL")` with `${SHELL##*/}` ≠ `sh`;
5. the value resolves to an executable (D1);
6. `realpath(running shell) != realpath(target)` (`/proc/$$/exe`, Linux-only is
   fine — EL is Linux-only).

Condition 4 is the one that matters. Without it, `bash` typed inside a loadout
zsh would `exec` straight back to zsh, because the preference is still exported.
Login-ness alone is not enough either: `command-login-shell` defaults to `FALSE`
in the shipped 1.0.4, and the terminal prefers `$SHELL` over the passwd shell
(`terminal-screen.c:734-755`), so a window may be spawned non-login from a
session whose `$SHELL` equals the passwd shell — the `$SHELL` comparison covers
that case. The `sh` exclusion exists because cron and systemd set
`SHELL=/bin/sh`, which resolves to bash on EL (`/bin/sh -> bash`). Without it,
an interactive bash that cron-driven expect spawns under a PTY would match.

The command-string half of condition 3 is not optional. `$SHELL -i -l -c CMD` is
interactive and login, so it passes every other condition, and an exec would
replace it with an interactive shell that never runs CMD. VS Code and JetBrains
IDEs read the user's environment exactly this way, and then time out. Both
guards were checked on the dev host on 2026-11-05: `BASH_EXECUTION_STRING` is
set under `bash -ic`, and `shinstdin` is off under `zsh -lic`.

Non-interactive shells never exec (`bash -c`, scripts, `ssh host cmd`), and
neither do interactive shells given a command. What remains is a PTY-driven
interactive shell with no command (expect `spawn bash`, pexpect) started from
a context that has no marker. The marker covers every such shell spawned from a
switched session, and the `sh` exclusion covers cron and systemd. Anything
beyond that is accepted and documented, not claimed impossible.

Residual gap, accepted: a terminal that spawns a *non-login* shell, ignores
`$SHELL`, and was launched from a shell that exported a different `SHELL` keeps
the passwd shell. The shipped X11 terminal honours `$SHELL`, so it is not
affected. The alternative guard — inspecting the parent
process and exec'ing unless the parent is a known shell — needs a fork on every
start and a shell-name list that would silently rule out shells the list does
not know, which is the exact property the request requires we keep.

### D3 (mine) — the marker is exported, never cleared, and the preference is not cleared

On exec: set `LOADOUT_SHELL_EXEC=<resolved target>` (exported) and
`SHELL=<resolved target>` (exported; always the absolute path D1 resolved, never
the bare name), and leave `LOADOUT_CFG_INTERACTIVE_SHELL` exported with its
value. The new shell sees `LOADOUT_SHELL_EXEC` already set and stops, so the
loop terminates even for a shell whose rc re-sources itself.

The marker name (confirmed by the user, 2026-11-05) has no leading underscore
and sits outside `LOADOUT_CFG_*`. In
the bashrc, a leading `_` marks scratch variables (`unset_bashrc_local_vars`
wipes `_*`), and an underscored marker would survive only because it is
exported. Outside `LOADOUT_CFG_*`, nobody mistakes it for a knob.

The marker, not condition 6, is the loop guard for a wrapper target. Loadout's
own `fish` is a sh wrapper around `fish.bin` (checked in the payload
2026-11-05), so `/proc/$$/exe` never equals the target's realpath. The marker is
load-bearing, not belt-and-braces.

The marker is deliberately session-wide, not one-shot-per-exec: nothing in the
target's rc unsets it, so every later spawn in that session tree (a `bash -l`
typed at the prompt, a tmux pane started as a login shell) is left alone.
That is the intent — a user who types `bash -l` asked for bash, and an
explicitly started shell must never bounce back. The cost is that changing the
preference mid-session takes effect in the next *fresh* session, not in
children of the current one. A fresh session is a new `ssh`, a new console
login, a new tmux server (D9), or a terminal process started after the change.
Single-instance terminals (xfce4-terminal and mate-terminal run one process per
desktop session by default) may open every window from the first instance's
environment. If that instance was started from a switched shell rather than
from the menu, its marker would then last until the terminal process exits.
Verify this in the manual X check and document the result.

Exporting `SHELL` is what makes everything downstream agree without extra
config: tmux's `default-shell` falls back to `$SHELL`
(`envs/tmux/tmux-global.conf:51` relies on this), xfce4-terminal runs `$SHELL`
instead of the passwd shell when it is executable (`terminal-screen.c:734-755`),
and `su`, `screen`, `$SHELL -c` and tools that re-spawn "the user's shell"
inherit the choice.

### D4 (mine, revised) — keep login-ness: a login shell execs a login shell

A login origin execs the target with `-l` as its only argument. A non-login
origin execs it with no arguments (`--init-file` for bash→bash, as today).
`-l` is passed only to targets whose basename is a known login-capable shell —
`bash`, `zsh`, `tcsh`, `csh`, `fish`, `ksh` — because an unknown shell that
rejected the flag would exit at once and close the window. An unknown shell
still works as the target, just non-login, so the list decides only *how* to
exec, never *whether* to, and rules no shell out. (tcsh accepts `-l` only as its
sole flag, which is why it is the only argument.)

Why: `exec` keeps environment variables and nothing else. Within one shell
family that was enough: `PREFERRED_BASH`'s child inherited the `export -f`
functions. Across families, functions, aliases and completions are lost, and
only the target's own system init brings them back. Without it:

- **tcsh → bash** has no Environment Modules `module`. EL8's `/etc/bashrc`
  sources `/etc/profile.d/*.sh` only for non-login shells, and the loadout
  bashrc never sources `/etc/bashrc`. tcsh's `module` is an alias, which no
  process inherits. (EL8 init files checked in `loadout-build` on 2026-11-05;
  `/etc/csh.cshrc` likewise sources `profile.d/*.csh` only for non-login tcsh.)
- **zsh → anything** never runs `/etc/profile` at all. `~/.zshenv` is an EL
  entrypoint, it runs before `/etc/zprofile` (which is what sources
  `/etc/profile` on EL; order checked 2026-11-05), and the exec happens during
  that first file.
- `logout`, `~/.bash_logout`/`~/.zlogout` and the target's login files stop
  working.

`chsh` would give a login shell of the target family with that family's system
init. The bar is "indistinguishable from chsh".

Cost: the system login init runs twice where both shells read the sh-family
files, which is bash→zsh (EL's `/etc/zprofile` sources `/etc/profile`) and
bash→bash. EL's `/etc/profile` is idempotent: `pathmunge` checks before adding,
and the profile.d snippets re-initialize. Across the csh/sh boundary the files
are disjoint, so nothing is duplicated, and a zsh origin has not yet run its
own.

The exec still runs before the shipped rc files touch PATH (`bashrc:189` vs
`global/bashrc:28-30`; `zsh/global/zshrc:12` vs `:45-64`; `tcsh/global/tcshrc:24`
vs `:40-48`), so the replaced shell has done only config work and the target's
loadout rc runs once. User config layers may do PATH work (`envs/bash/bashrc:165-167`
directs it there), and whatever they export reaches the target along with
everything else exported.

Not recoverable: a tcsh origin's `~/.login` runs *after* `~/.tcshrc`, so a
tcsh→X exec skips the user's own `~/.login`. It is csh syntax, so the target
could not run it anyway. This is documented: move what you need into the
target's config layer.

Residual: a non-login origin (a terminal that does not start login shells, see
D8) gives a non-login target, and a non-login bash target gets no profile.d.
That is the same inherited-environment behaviour every non-login loadout bash
has today. Sourcing `/etc/bashrc` from the loadout bashrc would change it for
everyone and is out of scope.

### D5 (mine) — the predicate is written twice, not three times

bash and zsh can share: put `loadout_exec_interactive_shell()` in
`envs/bash/functions.sh` (already sourced by both; it is the repo's shared-code
home and must stay bashism-free for zsh reuse) and call it from
`envs/bash/bashrc` and `envs/zsh/global/zshrc`. tcsh is csh and cannot call a
shell function, so `envs/tcsh/global/tcshrc` keeps a hand-written block with the
same predicate, in the `if ( ... )` style already used there. The tcsh block must
not resolve a bare name with tcsh's `which` builtin, which checks aliases first:
an alias named `zsh` would win. It needs a POSIX `command -v` helper or an
explicit loop over `$path`, and `readlink -f` for the realpath comparisons (tcsh
has no `:A`).

### D6 (mine) — one default definition, inherited by zsh

`envs/zsh/zshrc:59` sources the **bash** config layer first, by design ("the
defaults live in exactly one place so a value a user sets for bash also applies
to zsh"). So `LOADOUT_CFG_INTERACTIVE_SHELL` is defined only in
`envs/bash/global/config.sh` (`: "${LOADOUT_CFG_INTERACTIVE_SHELL:=}"` followed by
`export LOADOUT_CFG_INTERACTIVE_SHELL`) and in `envs/tcsh/global/config.csh`
(`if ( ! $?LOADOUT_CFG_INTERACTIVE_SHELL ) ...`). No default in `config.zsh`.

`tests/env-shell-parity` needs no zsh-side change: it asserts the *sourcing* of
`global/config.sh` via `ZSH_REQUIRED_SOURCES`, and its read-implies-defined rule
covers only bash and tcsh. The tcsh half is load-bearing: `global/tcshrc` reads
the variable and `config.csh` must `setenv` it, or the "every LOADOUT_CFG_* is
defined in tcsh or excused" check fails — and a read without a definition is
exactly the dead-switch class that check exists to catch
(`LOADOUT_CFG_ENABLE_SSH_AGENT`'s history).

**Where the user's line goes.** The variable must be set in the layers of the
shell that sessions *start* in, which is the passwd shell:
`~/.config/tcsh/user/config.csh` for csh/tcsh, and `~/.config/bash/user/config.sh`
for bash and zsh (zsh reads the bash layers). A line only in the other family's
layer never fires; setting it in both is harmless. `loadout doctor` checks this
(D7). The "one documented line" in Goals means one line in the login shell's
layer.

**Gap brought into scope (user, 2026-11-05: all three passes).** In all three
passes, zsh reads only the configured roots (`envs/zsh/zshrc:58-73`):

- pass 1a reads `$BASH_CONFIG_ROOT_DIR/<layer>/config.sh`;
- passes 1b and 2 read `$ZSH_CONFIG_ROOT_DIR/<layer>/{config.zsh,zshrc}`.

When a root is a shared tree, bash and tcsh *also* read the user's home override
layers afterwards (`envs/bash/bashrc:179-187`, `envs/tcsh/tcshrc:60-80`, tested
by `tests/install-env-tcsh:263`). zsh does not. In a shared-config-root
deployment, a line in `~/.config/bash/user/config.sh` therefore reaches bash but
not zsh, which breaks the paragraph above. Every other personal zsh setting is
silently dropped the same way today.

In this change, each of the three passes gains bash's home-override block. After
the root's layers, it sources the `corp..user` layers under `~/.config/bash`
(pass 1a) or `~/.config/zsh` (passes 1b and 2). It is guarded by bash's realpath
comparison, so the default setup, where the root *is* the home dir, never
sources a file twice. AGENTS.md already describes zsh as behaving this way;
after this change that is true.

### D7 (user) — the retired variables are cut over, not aliased

`LOADOUT_CFG_PREFERRED_{BASH,ZSH,TCSH}` are deleted: definitions, exec blocks,
docs. Outside this spec there are 26 matching lines across 11 files
(`AGENTS.md`, `docs/BASH.md`, `envs/bash/README.md`, `envs/zsh/README.md`,
`envs/bash/bashrc`, `envs/bash/global/config.sh`, `envs/zsh/global/config.zsh`,
`envs/zsh/global/zshrc`, `envs/tcsh/global/config.csh`, `envs/tcsh/global/tcshrc`,
`tests/env-shell-parity`; counted 2026-11-05). `README.md` and
`envs/tcsh/README.md` mention none of them. The count includes the
`LOADOUT_CFG_PREFERRED_BASH` row in `tests/env-shell-parity`
(`EXPECTED_MISSING_CONFIG`, line 102), whose reason text would otherwise
document a gap that no longer exists.

A setting that is silently ignored is worse than a loud one, so `loadout doctor`
gains these findings. Like the precedent, `_doctor_layout_audit` (which already
scans user files for stale tmux autosave references), they are informational
and never change the exit status:

1. any retired name (the three `PREFERRED_*`, the D11 removals, and the old
   names of the D11 renames) found in the user layers:
   `$HOME/.config/{bash,zsh,tcsh}/*/config.*`, plus any
   `{BASH,TCSH,ZSH}_CONFIG_ROOT_DIR` present in the environment (relocatable
   roots are real), deduped by realpath;
2. a `LOADOUT_CFG_INTERACTIVE_SHELL` value that does not resolve per D1:
   missing, not executable, relative, or carrying arguments. The variable is
   exported, so doctor sees the value the invoking shell ended up with. The
   runtime stays silent (Anti-goals), so doctor is where a typo surfaces;
3. the passwd shell (`getent passwd`), whether an EL rc exists for it (csh
   section), and whether that family's layers set the variable (D6);
4. a target that is a shell EL configures (bash, zsh, tcsh/csh) whose env
   package is not installed, i.e. no EL entry link such as `~/.zshrc`. A zsh
   target without env-zsh starts zsh's new-user wizard with no loadout PATH.
   `@envs` is env-bash + env-tcsh; env-zsh comes only by name or via
   `@envs-all`.

**Behaviour change for `PREFERRED_BASH` users, accepted.** Under the old
variable every interactive bash re-exec'd, so typing `bash`, or `t`
(`alias t='exec bash'`, `envs/bash/global/aliases.sh:229`), landed in the
preferred bash. Under conditions 2 and 4 both now stay on whichever bash PATH
finds. That follows the rule that an explicitly started shell never bounces
back. The migration note in `README.md`/`docs/BASH.md` says so, and `t` is
unchanged.

### D8 (user, reconfirmed 2026-11-05: keep, as its own commit) — xfce4-terminal is seeded to run a login shell

Add `command-login-shell=true` to `envs/xfce4-terminal/xfce4-terminal.xml` and
`CommandLoginShell=TRUE` to `envs/xfce4-terminal/terminalrc` (the 1.0.4 key is
the property's blurb — the same mapping the README table documents).

To be plain about scope: this is a separate change to a default, not part of the
exec mechanism. The exec fires in xfce4-terminal windows without it, because the
terminal runs `$SHELL` and condition 4's `$SHELL` check matches every window it
opens. What D8 adds, together with D4, is that the window's target is a *login*
shell. A tcsh→bash window then gets `/etc/profile` and `module`, instead of the
non-login residual described in D4. The upstream default is `FALSE`; with it on,
terminals give the login-shell semantics (`/etc/profile`, `profile.d`, modules)
that this audience expects. It does not fight the terminal's own `$SHELL`
preference.

D8 also changes every newly seeded user's windows to login shells, whether or
not they set the variable; the zero-behaviour-change bullet in Goals carves this
out. It therefore lands as its own commit with its own release-note entry. The
two files are seeded once and then user-owned (README: "delete a seeded file to
have the next install recreate it"), so existing users keep their old
`FALSE` value until they delete the file or tick the preference — documented,
not worked around. `tests/install-env-xfce4-terminal` must gain the
`command-login-shell → CommandLoginShell` mapping entry.

### D9 (mine) — tmux keeps not pinning `default-shell`

No `default-shell` in the tmux config. tmux's `default-shell` defaults to the
`$SHELL` the server was started with, and panes are login shells. Two cases
follow:

- A server started *before* the change still switches. Each new pane is the
  passwd shell as a login shell, so the exec fires once per pane.
- A server started from a switched shell runs the target directly, and its
  global environment carries the marker. After a later preference change, its
  new panes stay on the old target. The migration does not need `kill-server`
  (which destroys every session): use `tmux set -g default-shell <new path>`, or
  `tmux set-environment -gu LOADOUT_SHELL_EXEC` so that new panes start the old
  target, which then execs onward.

Both are documented one-liners, not new config.

### D10 (mine) — nothing outside `$HOME` and the install root

No `/etc/shells`, no `chsh`, no sudo, no session-environment manipulation, no
`default_prog`/`st.shell`/`default-shell` in this change. Every write is the
user's own config layer, so the choice is reversible by deleting one line.

### D11 (user) — settings clean-up

Decided one setting at a time while scoping the Settings table (see the
docs-sync section under Verification).

Removed:

- `LOADOUT_CFG_ATTACH_TO_TMUX` and `LOADOUT_CFG_ATTACH_TO_TMUX_WITH_DETACH_OTHERS`,
  together with everything that serves them: `auto_attach_to_tmux()`
  (`envs/bash/functions.sh:88`), its call in `envs/zsh/global/zshrc:522`, the
  tcsh block (`envs/tcsh/global/tcshrc:641` onwards), both definitions in
  `config.sh`/`config.csh`, and their docs. In bash the feature was already
  dead: a search on 2026-11-05 found that nothing in the bash env calls
  `auto_attach_to_tmux`; only zsh does. If `unset_bashrc_local_vars` then no
  longer runs under zsh, its zsh branch (`functions.sh:116` onwards, which exists
  for that call) goes too. `loadout doctor` lists both names as retired (D7
  item 1).
- `LOADOUT_CFG_ENABLE_FASTNVIM`, a dead switch. It is defined in `config.sh` and
  `config.csh` and read by nothing. The tcsh comment says the nvim config
  reads it, but it does not. Only those two definitions and the mention in
  AGENTS.md go.
- `LOADOUT_CFG_WEZTERM_SHELL_INTEGRATION`, the explicit path to `wezterm.sh`.
  Its comment says the `--dest-dir` installer sets it; the installer never does,
  and automatic resolution already covers the vendored copy, the path relative
  to the installed binary, and the shared prefix. Remove the explicit-variable
  step from `loadout_find_wezterm_shell_integration` (`envs/bash/functions.sh`),
  the definition in `config.sh`, its row in `tests/env-shell-parity`
  `EXPECTED_MISSING_CONFIG`, and the mentions in `docs/BASH.md`,
  `envs/bash/global/README.md`, `envs/bash/global/wezterm/PROVENANCE` and
  AGENTS.md. `LOADOUT_CFG_ENABLE_WEZTERM_SHELL_INTEGRATION`, the on/off switch,
  stays.

Renamed. These are cut over like D7, not aliased; `loadout doctor` reports the
old names (D7 item 1):

- `LOADOUT_CFG_ENABLE_ONLINE_UPDATES` → `LOADOUT_CFG_ONLINE_DETECT`
  (`auto | 1 | 0`). The old name suggested it turns updates on; it actually
  decides whether the machine counts as online, and exports `LOADOUT_ONLINE`.
  The new name groups it with `ONLINE_DETECT_TIMEOUT` and
  `ONLINE_DETECT_HOSTS`. Readers: `envs/bash/global/bashrc`,
  `envs/zsh/global/zshrc`, `envs/tcsh/global/tcshrc`, both config files.
  `LOADOUT_ONLINE`, the exported result, keeps its name, so nvim is untouched.
  Until a user renames their line, a forced `1`/`0` reverts to `auto`; for an
  air-gapped host that costs one fast-failing probe per day (cached), and doctor
  flags it.
- `LOADOUT_ONLINE_CACHE_TTL` → `LOADOUT_CFG_ONLINE_CACHE_TTL` (seconds, default
  86400, `0` disables the cache). It is the only setting outside the
  `LOADOUT_CFG_` namespace, so the docs-sync gate and the Settings table would
  miss it. bash had it only as a comment in `config.sh`; bash now defines it
  (`export LOADOUT_CFG_ONLINE_CACHE_TTL="86400"`), alongside tcsh's existing
  `setenv`. Readers: `envs/bash/functions.sh`
  (`loadout_detect_online_cached`) and `envs/tcsh/global/helpers/detect-online`.

Kept as they are: every other setting. The full list was reviewed one by one
on 2026-11-05 and goes into the Settings table.

## csh (passwd shell `csh`)

`/bin/csh` on EL8/EL9 is tcsh (symlink or the same binary), and tcsh reads
`~/.tcshrc` even when invoked as `csh`; `~/.cshrc` was retired 2026-10-08
(`loadout_main.py:214-218` records "plain csh ... is not a supported shell
here"). So the csh entries in the passwd space are covered without restoring
`~/.cshrc`. The builder must not assume it: verify inside the EL8 container.
`loadout-smoke:almalinux8.10` has tcsh, with `/usr/bin/csh -> tcsh` (checked
2026-11-05); stock `almalinux:8.10` has neither tcsh nor zsh. Check
`readlink -f /bin/csh`, then that `csh` reads `~/.tcshrc` — under a **real
PTY**, because `tcsh -i -c CMD` does not set `$prompt` and the whole interactive
block, this one included, is skipped; `tests/install-env-tcsh:12-13` documents
that trap), and have `loadout doctor` print the passwd shell with whether an EL
rc exists for it. If
a host really has BSD csh, the feature is inert there and nothing breaks — which
is the required "don't rule out other shells" property.

## Goals

- A user changes their interactive shell by editing one documented line in the
  config layer of their login shell (D6), with no root, no `chsh`, no
  terminal-specific file. (A one-command override of a *typed* shell —
  `VAR=zsh bash` — is deliberately inert; condition 4 cannot tell it from an
  explicitly requested shell. Use `exec zsh`.)
- The result is what `chsh` would have given: a login origin yields a login
  target with its own family's system init (D4).
- The choice applies to any terminal emulator (shipped or not), `ssh`, the text
  console and tmux panes.
- The choice follows the loadout tree across `--dest-dir` and shared-prefix
  moves when given as a bare name.
- Zero behaviour change when the variable is unset or empty. The one exception
  is D8's seeded terminal default, a separate change that lands in its own
  commit.
- One variable replaces three.

## Non-goals

- Selecting the shell for non-interactive execution, system accounts, `su` to
  another user, or `cron`.
- Editing `/etc/shells`, `/etc/passwd`, PAM, or any display-manager/session
  environment.
- Setting any terminal's own shell knob — including xfce4-terminal's
  `run-custom-command`/`custom-command`, wezterm's `default_prog`, st's
  `st.shell`, mate-terminal's profile command, tmux's `default-shell`. All are
  possible; none is used, because each is a static second source of truth that
  would have to be edited on every change and cannot follow a `--dest-dir` move.
- A per-spawn override through the environment (`VAR=zsh ssh host`,
  `VAR=zsh xfce4-terminal`). ssh forwards only what sshd's `AcceptEnv` allows
  (on EL, `LANG` and `LC_*`), and the user-layer assignment overrides an
  inherited value anyway. For one spawn, start the shell explicitly:
  `exec zsh -l`, `ssh -t host zsh -l`.
- Sourcing `/etc/bashrc` from the loadout bashrc (the D4 residual for non-login
  bash targets).
- Making EL's rc apply to shells EL does not configure (fish, dash, xonsh): the
  mechanism simply does not fire there. Such a shell still works as the
  *target*.
- `XDG_DATA_HOME` support in the rc prefix resolution (pre-existing gap,
  unrelated).

## Anti-goals (what would make this a failure even if it works)

- A user's explicit `chsh` choice or their terminal's own command setting being
  overridden without `LOADOUT_CFG_INTERACTIVE_SHELL` being set.
- A second source of truth: the shell choice must not be expressible in two
  places that can disagree.
- Any extra work on the hot path when the variable is unset beyond one
  string test.
- A re-exec loop under any configuration, including a preference that names a
  symlink to the running shell or a wrapper script around it.
- `$SHELL -ic CMD` or `$SHELL -ilc CMD` not running CMD.
- An error message, a delay, or a start-up failure when the target is missing,
  not executable, or a typo.

## Costs

- One extra shell init per top-level window while the login shell differs from
  the target (tcsh config + zsh rc instead of zsh rc). The replaced shell does
  config only — no PATH, aliases, prompt or plugins (D4) — so this is tens of
  milliseconds, and it is the only reason a terminal-side accelerator could ever
  be worth revisiting.
- The system login init runs twice for bash→zsh and bash→bash login switches
  (D4). It is idempotent on EL.
- The shipped layers do no PATH work before the exec, and the target's loadout
  rc runs once (D4). User config layers may do PATH work, and what they export
  reaches the target. `path_modify`'s lack of dedupe
  (`envs/bash/functions.sh:306`) predates this change and is out of scope.
- A changed preference takes effect in the next fresh session, not in children
  of the current one (D3 marker).

## Verification

New `tests/env-interactive-shell` (PTY-driven, precedent: `tests/install-env-tcsh`
drives a real PTY), registered in `tests/run-all`:

1. bash entry + `LOADOUT_CFG_INTERACTIVE_SHELL=<prefix>/bin/zsh` → session is
   zsh (`$ZSH_VERSION`), `SHELL` is the target, marker set.
2. same from a tcsh entry and from a zsh entry.
3. `bash` typed inside the resulting zsh stays bash (condition 4).
4. `bash -c 'echo $BASH_VERSION'` and `zsh -c ...` do not exec.
5. unset/empty variable → identical process to today.
6. target missing / not executable / typo → no exec, no output, no delay.
7. target is a symlink to the running shell → no exec; target is a wrapper
   script (loadout's `fish`) → exactly one exec, no loop (marker).
8. bare name resolves through `LOADOUT_CFG_SHARED_PREFIX` (split-install case).
9. inherited value survives: `bash` child of the re-exec'd zsh sees the
   preference and does not re-exec.
10. `$SHELL -i -c 'echo ok'` and `$SHELL -i -l -c 'echo ok'` from each origin
    print `ok` and do not exec (condition 3).
11. login origin → login target (`shopt -q login_shell`, `[[ -o login ]]`,
    `$?loginsh`); non-login origin → non-login target; an unknown target
    basename gets no `-l`.
12. relative path and value-with-arguments → no exec, no output.
13. `SHELL=/bin/sh`, no marker, interactive bash under a PTY → no exec.
14. tmux: a pane from a server started without the marker switches; a pane
    from a server whose environment carries the marker does not.
15. zsh home-override layers (in `tests/install-env-zsh`, mirroring
    `tests/install-env-tcsh:263`): with `BASH_CONFIG_ROOT_DIR` and
    `ZSH_CONFIG_ROOT_DIR` pointing at shared trees, a value set in each of
    `~/.config/bash/user/config.sh`, `~/.config/zsh/user/config.zsh` and
    `~/.config/zsh/user/zshrc` reaches zsh. With both roots at their defaults,
    no file is sourced twice (D6).

Doctor findings (D7 items 1-4) get cases next to the existing
`_doctor_layout_audit` coverage (`tests/doctor-shadow-audit`, T1).

Tier 3 (EL8 container, `--network=none`), in `loadout-smoke:almalinux8.10`, which
has tcsh and Environment Modules' `profile.d/modules.{sh,csh}`:

- `csh` verification (csh section);
- tcsh login → bash target and tcsh login → zsh target both have `module`
  defined (D4);
- zsh-origin login → the target sees `/etc/profile`'s effects. No EL8 image has
  a system zsh, so either stage the zsh rpm or make the test user's passwd shell
  the payload's zsh.

Updated gates: `tests/install-env-xfce4-terminal` (new mapping row),
`tests/env-shell-parity` (new variable defined for tcsh; retired names gone),
`tests/run-all --fast` (T1), `tests/run-all` (T1+T2 installs into temp roots),
and `tests/run-all --container` (Tier 3, required for class C). The `csh` entry
can only be exercised under a real PTY (`tests/install-env-tcsh:12-13`).

`tests/docs-sync` requires every `tests/*` executable to be named in
`AGENTS.md` (`test_tests_listed`), so the new test file lands with its entry
there or T1 fails.

`tests/docs-sync` does not currently know about `LOADOUT_CFG_*`: nothing lists
them, so a new knob can ship undocumented. Add `test_cfg_vars_documented` (one
of the `main()` checks, same shape as `test_kinds_documented`): every
`LOADOUT_CFG_*` *defined* in the three shell configs appears in at least one
tracked Markdown file under `docs/` or `envs/` (excluding `docs/archive/`).
"Defined" uses the rules of `tests/env-shell-parity`, not a mention:
`export`/`typeset -gx` in `envs/bash/global/config.sh` and
`envs/zsh/global/config.zsh`, and `setenv` in `envs/tcsh/global/config.csh`. Name
the three files explicitly; `envs/**/config.*` also matches
`envs/helix/config.toml`. That is the mechanical half of the Commit Rule for
this feature's interface; the prose half stays a manual review.

Today 13 defined knobs would fail the check (counted 2026-11-05):
`ATTACH_TO_TMUX`, `ATTACH_TO_TMUX_WITH_DETACH_OTHERS`, `ENABLE_FASTNVIM`,
`ENABLE_ICECREAM`, `ENABLE_ONLINE_UPDATES`, `ENABLE_TMUX_PATH_STORE`,
`ENABLE_ZOXIDE`, `ONLINE_DETECT_TIMEOUT`, `PREFERRED_TCSH`, `PRESERVE_FUNCTIONS`,
`PROMPT_COLOR_FARM`, `PROMPT_COLOR_NORMAL`, `STARSHIP_USERIDS_TO_HIGHLIGHT` (all
`LOADOUT_CFG_`-prefixed). `PREFERRED_TCSH` is removed by D7. D11 removes the
two `ATTACH_TO_TMUX` settings and `ENABLE_FASTNVIM`, and renames
`ENABLE_ONLINE_UPDATES`.

Neither README has a settings table today, so this change adds one (user
decision, 2026-11-05). It is a **Settings** table in `envs/bash/README.md`
covering *every* setting, not just the missing ones: the default, a one-line
description, and which shells honour it. `envs/zsh/README.md` and
`envs/tcsh/README.md` link to it. The descriptions come from the comments in the
three config files. The gate then keeps the table complete, and it lands green
without an allowlist; an allowlist of permanent exceptions would make the gate
decorative.

Not covered by any automated gate: the terminal-side behaviour that depends on
`$SHELL` (xfce4-terminal window from a switched shell runs the preferred shell;
launcher window runs passwd shell then re-execs). Verify by hand in a real X
session and record the result in `docs/HANDOFF.md`; there is no display in CI.

## Docs to sync before commit

`README.md` (user-facing behaviour, which layer the line goes in, the
`PREFERRED_*` migration note including the typed-`bash`/`t` change),
`AGENTS.md` (env-var list: drop the removed settings and the nonexistent
`PREFERRED_CAT`; pitfalls: exported marker, login-preserving `-l`,
command-string guard, no `default-shell`; the zsh home-override claim becomes
true), `docs/BASH.md` (the variable and its value semantics),
`envs/bash/README.md` (the new Settings table), `envs/zsh/README.md` and
`envs/tcsh/README.md` (link to it), `docs/TMUX.md` (server environment, migration via
`set -g default-shell`), `docs/HANDOFF.md` (state + follow-ups),
`envs/xfce4-terminal/README.md` (login-shell property + seeded-once caveat).
`.github/copilot-instructions.md` is a pointer and needs no edit unless the
gates change.

## Left to the builder

- The exact list of shells that get `-l` (D4), as long as an unknown basename
  falls back to a non-login exec.
- Exact helper name and file split between `functions.sh`, `bashrc`,
  `global/zshrc`, `global/tcshrc`.
- Whether the tcsh block clears its scratch variables (`unset _loadout_target_shell`)
  the way the surrounding code does.
- PTY test mechanics (expect/socat/stdin script), matching `tests/install-env-tcsh`.
- Doctor output formatting.

## Revision notes

rev 2 (2026-11-05), from a design review:

- D4 reversed. A login origin now gives a login target (previously: never
  `-l`), after confirming that a cross-family exec loses the system init: no
  `module` in tcsh→bash, and a zsh origin never runs `/etc/profile`.
- D2: command-string guard added (`$SHELL -ilc` from IDEs); `SHELL=/bin/sh`
  excluded from the `$SHELL` check; conditions reordered by cost and renumbered
  (the top-level-spawn condition is now 4).
- Per-spawn environment override moved from Goals to Non-goals: ssh does not
  forward it, and the user layer overrides it.
- Release class B → C: doctor changes `loadout_main.py`.
- D8 reframed as a separate default change; Goals carve it out.
- D7: inventory corrected; doctor also reports an unresolvable value, the layer
  the line must live in, and a target whose env is not installed; the
  `PREFERRED_BASH` behaviour change is recorded.
- D1: rejected value shapes defined; prefix-first stated as a deliberate
  PATH-contract exception.
- D3: marker named `LOADOUT_SHELL_EXEC` (user decision); the marker is the loop guard for
  wrapper targets; single-instance terminal caveat added.
- D5: tcsh must not resolve bare names with the alias-aware `which` builtin.
- D6: which layer the line goes in; the zsh home-override layer gap is fixed in
  all three zsh passes (user decision).
- D9: migration corrected. Servers that predate the change still switch per
  pane, and `set -g default-shell` replaces `kill-server`.
- Verification: cases 10-15, doctor cases, and a Tier 3 plan naming the image.
- docs-sync gate: definition rules and explicit files; it lands with a complete
  Settings table in `envs/bash/README.md` (user decision).
- D11 added: settings clean-up (user decisions). Tmux auto-attach,
  `ENABLE_FASTNVIM` and the explicit `WEZTERM_SHELL_INTEGRATION` path are
  removed; `ENABLE_ONLINE_UPDATES` is renamed to `ONLINE_DETECT`, and
  `LOADOUT_ONLINE_CACHE_TTL` to `LOADOUT_CFG_ONLINE_CACHE_TTL`.
