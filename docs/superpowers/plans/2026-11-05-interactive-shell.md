# Interactive Shell Selection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A user picks their interactive shell with one line, `LOADOUT_CFG_INTERACTIVE_SHELL`. It replaces the three `LOADOUT_CFG_PREFERRED_{BASH,ZSH,TCSH}` variables, and this change also lands the settings clean-up, the zsh shared-root fix, the doctor findings, the xfce4-terminal login default and the Settings table that the spec decided.

**Architecture:** Each shell's rc does a one-shot `exec` near its top. bash and zsh share two functions in `envs/bash/functions.sh`; tcsh has a hand-written block backed by a POSIX helper. The exec keeps login-ness (`-l` for known shells) and exports `LOADOUT_SHELL_EXEC` and `SHELL`. It is gated so that command strings, typed shells and non-interactive shells never switch. `loadout doctor` gains an "Interactive shell" audit, and `tests/docs-sync` gains a "every setting is documented" gate backed by one Settings table.

**Tech Stack:** bash and zsh (shared `functions.sh`, which must parse in both), tcsh plus POSIX-sh helpers, Python 3.15 (`loadout_main.py`, tests), `script(1)` PTYs, tmux on a private `-L` socket, Docker (`loadout-smoke:almalinux8.10`, `--network=none`).

**Spec:** `docs/superpowers/specs/2026-11-05-interactive-shell-design.md` (rev 2). D1–D11 and "Verification" below refer to its sections. Line numbers are as of `ed6d045`.

## Global Constraints

- Indent with spaces, never tabs: 4 in code, 2 in Markdown/YAML. Makefile recipes are the only exception.
- Release class **C**. `tests/run-all --container` (Tier 3) is required before release.
- Shared-prefix expression, verbatim, in every resolver: `${LOADOUT_CFG_SHARED_PREFIX:-$HOME/.local/share/loadout}`. Do not add `XDG_DATA_HOME` handling.
- `envs/bash/functions.sh` is shared bash+zsh code. Outside a `$ZSH_VERSION`/`$BASH_VERSION` branch it must not use `${!var}`, `${var,,}`, `declare -f`, `compgen` or `shopt`. Both `bash -n` and `zsh -n` must pass on it.
- tcsh rules:
  - never `exit` from an rc file;
  - gate interactive work with `$?prompt`;
  - nest `if`s so that no line substitutes an undefined variable;
  - never use an unquoted `!` followed by a non-space;
  - helpers under `envs/tcsh/global/helpers/` are POSIX sh and pass `dash -n`.
- Startup silence: no shell prints anything new at startup in any case. That includes a target that is missing, not executable, relative, or carrying arguments.
- Hot path when the variable is unset or empty: exactly one string test at each call site, and no fork.
- The marker is `LOADOUT_SHELL_EXEC`. On exec, export it together with `SHELL=<resolved absolute path>`. Never clear it or `LOADOUT_CFG_INTERACTIVE_SHELL`.
- `-l` is passed as the only argument, only when the origin is a login shell, and only to a target whose basename is one of `bash zsh tcsh csh fish ksh`.
- Nothing is written outside `$HOME` and the install root (D10): no `/etc/shells`, no `chsh`, no sudo, and no terminal shell knobs (`default_prog`, `st.shell`, tmux `default-shell`). Tests may write `/etc` only inside the Tier 3 container.
- Retired and renamed settings are cut over, never aliased. `loadout doctor` findings are informational and never change its exit status.
- tmux in tests uses private sockets only (`tmux -L el-ishell-$$`). Never run `kill-server` or `kill-session` against the default server.
- Every new `tests/*` executable is registered in `tests/run-all` and named in the AGENTS.md test list (`tests/docs-sync` → `test_tests_listed`).
- Commit Rule: each commit carries the doc updates for what it changes (README.md, AGENTS.md, the env READMEs, and `.github/copilot-instructions.md` only if the gates change). Commit directly to `main`. Never push.
- Another agent can run `tests/run-all` in this tree, and concurrent runs abort each other. Check `pgrep -fa tests/run-all` before a full run.
- If `docker run` fails with `failed to create endpoint ... operation not supported`, STOP and tell the user "can't run tests until you reboot". Never use `--network host`.
- `tests/run-all` appends timings to `assurance/release-timings.tsv` (tracked) and `~/.cache/engineering-loadout/ci-runtimes.tsv`. Commit the tracked rows after full runs.
- Python is ruff-formatted (`target-version = "py314"`). Never "fix" a bare `except A, B:`. Never run a pre-3.14 interpreter on `loadout_main.py`.

## Review Focus

- **Whole-word doctor matching.** A layer line that sets only `LOADOUT_CFG_ATTACH_TO_TMUX_WITH_DETACH_OTHERS` reports that name once and never `LOADOUT_CFG_ATTACH_TO_TMUX`. `LOADOUT_CFG_ENABLE_WEZTERM_SHELL_INTEGRATION=1` is never reported. Tested in Task 5.
- **An alias or function named like the target cannot hijack resolution:** a bash `zsh() { ...; }` in `user/config.sh`, or a tcsh `alias zsh ...` in `user/config.csh`. Tested in Tasks 3 and 4.
- **`SHELL` unset, or naming a file that does not exist,** in a non-login interactive origin: no exec and no output. Tested in Task 3.
- **Bare-name fallback.** A bare name missing from the shared prefix falls back to the inherited PATH; missing from both, nothing happens and nothing is printed. Tested in Task 3 (shell) and Task 5 (Python mirror).
- **A preference naming the running shell directly** (no symlink) means no exec and *no marker*, so a later change of preference still applies in that session tree. Tested in Task 3.

---

### Task 1: Settings clean-up (D11)

**Files:**
- Modify: `loadout_main.py` (new constant next to `BASH_ENTRYPOINTS`, ~line 205)
- Modify: `tests/env-shell-parity` (new check; drop the `LOADOUT_CFG_WEZTERM_SHELL_INTEGRATION` row from `EXPECTED_MISSING_CONFIG`, ~line 108)
- Modify: `envs/bash/global/config.sh:19-20,29,51-63`, `envs/tcsh/global/config.csh:66-67,89-90,111-122`
- Modify: `envs/bash/functions.sh`:
  - `:40-48`: cache TTL name;
  - `:88-110`: delete `auto_attach_to_tmux`;
  - `:112-`: drop the zsh branch of `unset_bashrc_local_vars`;
  - `:219-238`: wezterm explicit-path step.
- Modify: `envs/bash/global/bashrc:149-163`, `envs/zsh/global/zshrc:192-200,519-522`, `envs/tcsh/global/tcshrc:310-312,640-650`, `envs/tcsh/global/helpers/detect-online:23`, `envs/bash/global/wezterm/PROVENANCE`
- Test: `tests/env-shell-parity`, `tests/install-env-bash`, `tests/install-env-zsh`, `tests/install-env-tcsh`
- Docs: README.md (new "Retired and renamed settings" subsection), AGENTS.md (the "Config vars" line, ~263), `docs/BASH.md`, `envs/bash/global/README.md`

**Interfaces:**
- Produces `RETIRED_SHELL_SETTINGS: dict[str, str]` in `loadout_main.py`. It maps each retired name to its replacement: a setting name, or text starting `removed:`. Tasks 3 and 4 add entries; Task 5 reads it in doctor; `tests/env-shell-parity` reads it through `ast`. Initial content, exactly:

```python
RETIRED_SHELL_SETTINGS = {
    "LOADOUT_CFG_ATTACH_TO_TMUX": "removed: tmux auto-attach was retired",
    "LOADOUT_CFG_ATTACH_TO_TMUX_WITH_DETACH_OTHERS": "removed: tmux auto-attach was retired",
    "LOADOUT_CFG_ENABLE_FASTNVIM": "removed: nothing ever read it",
    "LOADOUT_CFG_WEZTERM_SHELL_INTEGRATION": "removed: the integration script is found automatically",
    "LOADOUT_CFG_ENABLE_ONLINE_UPDATES": "LOADOUT_CFG_ONLINE_DETECT",
    "LOADOUT_ONLINE_CACHE_TTL": "LOADOUT_CFG_ONLINE_CACHE_TTL",
}
```

- Produces the settings `LOADOUT_CFG_ONLINE_DETECT` (`auto | 1 | 0`, same accepted spellings as today) and `LOADOUT_CFG_ONLINE_CACHE_TTL` (seconds, default `86400`, `0` disables the cache).

- [ ] **Step 1: Add the constant and the failing parity check**

In `tests/env-shell-parity`, add the check `no env source uses a retired setting`:
- Load `RETIRED_SHELL_SETTINGS` from `loadout_main.py` with `ast`: find the module-level `Assign` with that target and `ast.literal_eval` its value. Then `check("retired-settings table found", len(table) >= 6, ...)`, which catches a broken extractor.
- Scan every regular file under `envs/bash`, `envs/zsh` and `envs/tcsh`. Skip `*.md` and the vendored trees `envs/bash/global/github.scop.bash-completion/` and `envs/bash/global/icecream-bash/`.
- Match each name with `(?<![A-Za-z0-9_])NAME(?![A-Za-z0-9_])`. On failure, list `path:line: NAME -> replacement`.

- [ ] **Step 2: Run it and watch it fail**

Run: `tests/env-shell-parity`
Expected: FAIL, naming at least `config.sh`, `config.csh`, `functions.sh`, `global/bashrc`, `global/zshrc`, `global/tcshrc`, `helpers/detect-online` and `wezterm/PROVENANCE`.

- [ ] **Step 3: Add failing runtime checks for `LOADOUT_CFG_ONLINE_DETECT`**

In each of `tests/install-env-bash`, `tests/install-env-zsh` and `tests/install-env-tcsh`, after the env is installed:
1. Write the user layer with `ONLINE_DETECT=1` plus `LOADOUT_CFG_ONLINE_DETECT_HOSTS="127.0.0.1:9"`, a closed port, so that an `auto` probe would say offline.
2. Start a clean interactive shell and assert `printenv LOADOUT_ONLINE` prints `1`.
3. Repeat with `ONLINE_DETECT=0`, expecting `0`.

The user layer is `~/.config/bash/user/config.sh` for bash and zsh, `~/.config/tcsh/user/config.csh` for tcsh.

Use the existing clean-environment helpers: `zsh_i` in `install-env-zsh`, and `tcsh_i_clean_home` in `install-env-tcsh` (not `tcsh_i`, which inherits the caller's `LOADOUT_ONLINE`). In `install-env-bash`, add `bash_i CMDS`, shaped exactly like `zsh_i` (`env -i HOME TERM=xterm PATH=/usr/bin:/bin`, `script -qec "$BASH_BIN -i"`, `tr -d '\r'`, and the same `strip_escapes` copied over).

- [ ] **Step 4: Run them and watch the `=1` case fail**

Run: `tests/install-env-bash; tests/install-env-zsh; tests/install-env-tcsh`
Expected: FAIL on the `ONLINE_DETECT=1` case in each, because the old name is still what the rc reads.

- [ ] **Step 5: Implement the clean-up**

- `config.sh`:
  - delete lines 19-20 (`ATTACH_TO_TMUX*`), 29 (`ENABLE_FASTNVIM`) and 51-54 (the `WEZTERM_SHELL_INTEGRATION` path and its comment);
  - lines 55-56 become `# LOADOUT_CFG_ONLINE_DETECT -> auto | 1 | 0` and `export LOADOUT_CFG_ONLINE_DETECT="auto"`;
  - replace the commented line 63 with `export LOADOUT_CFG_ONLINE_CACHE_TTL="86400"`.
- `config.csh`: the same deletions (66-67, 89-90) and the same two renames (114, 122). Keep the `if ( ! $?NAME )` form.
- `functions.sh`:
  - `_ttl="${LOADOUT_CFG_ONLINE_CACHE_TTL:-86400}"`, and fix the usage comment at :44;
  - delete `auto_attach_to_tmux` entirely;
  - check that `rg -n unset_bashrc_local_vars envs/zsh` returns nothing, then delete the `$ZSH_VERSION` branch of `unset_bashrc_local_vars` and its explanatory comment;
  - delete search step 1 of `loadout_find_wezterm_shell_integration` and renumber its header comment.
- The `global/bashrc`, `global/zshrc` and `global/tcshrc` readers move to `LOADOUT_CFG_ONLINE_DETECT`. Also update the comment at `bashrc:151`.
- Delete the zsh auto-attach block (`zshrc:519-522`) and the tcsh one (`tcshrc:640-650`, including its comment line).
- `helpers/detect-online:23`: `cache_ttl=${LOADOUT_CFG_ONLINE_CACHE_TTL:-86400}`.
- `wezterm/PROVENANCE`: drop the explicit-variable step from its resolution description.
- `tests/env-shell-parity`: drop the `LOADOUT_CFG_WEZTERM_SHELL_INTEGRATION` row.

- [ ] **Step 6: Run the gates**

Run: `bash -n envs/bash/global/bashrc && bash -n envs/bash/functions.sh && zsh -n envs/bash/functions.sh && dash -n envs/tcsh/global/helpers/detect-online && tests/env-shell-parity && tests/install-env-bash && tests/install-env-zsh && tests/install-env-tcsh && tests/env-bash-runtime`
Expected: all PASS.

- [ ] **Step 7: Sync the docs**

Run: `rg -n 'ATTACH_TO_TMUX|auto_attach_to_tmux|FASTNVIM|LOADOUT_CFG_WEZTERM_SHELL_INTEGRATION|ENABLE_ONLINE_UPDATES|ONLINE_UPDATES|LOADOUT_ONLINE_CACHE_TTL|CAT=bat' --glob '!docs/archive/**' --glob '!docs/superpowers/**' --glob '!docs/HANDOFF.md'`

Fix every hit:
- In AGENTS.md's "Config vars" line, remove `ATTACH_TO_TMUX(+WITH_DETACH_OTHERS)`, `FASTNVIM=0`, `WEZTERM_SHELL_INTEGRATION (explicit path)` and the nonexistent `CAT=bat`. Rename `ONLINE_UPDATES=auto(...)` to `ONLINE_DETECT=auto(...)`, and add `ONLINE_CACHE_TTL=86400`.
- Add a README subsection, "Retired and renamed settings": a table of old name → new name, or "removed" plus what to do. Task 3 and Task 4 append to it.
- Then run `tests/docs-sync`. Expected: PASS.

- [ ] **Step 8: Commit**

Stage tracked changes under `envs/` with `-u`, so that untracked user files there are never swept in, and name everything else.

```bash
git add -u envs/
git add loadout_main.py tests/env-shell-parity tests/install-env-bash tests/install-env-zsh tests/install-env-tcsh README.md AGENTS.md docs/BASH.md
git commit -m "refactor(envs): drop tmux auto-attach and dead settings; rename online-detect settings"
```

---

### Task 2: zsh reads home override layers under a shared config root (D6)

**Files:**
- Modify: `envs/zsh/zshrc:58-73`
- Test: `tests/install-env-zsh`
- Docs: `envs/zsh/README.md` (layer-chain description)

**Interfaces:** none new. Behaviour: in each of the three passes, after the root's layers, source the `corp site team project user` layers from the home dir:
- pass 1a: `~/.config/bash/<layer>/config.sh`, when `${BASH_CONFIG_ROOT_DIR:A}` ≠ `$HOME/.config/bash` resolved;
- pass 1b: `~/.config/zsh/<layer>/config.zsh`;
- pass 2: `~/.config/zsh/<layer>/zshrc`.

Passes 1b and 2 apply when `${ZSH_CONFIG_ROOT_DIR:A}` ≠ `$HOME/.config/zsh` resolved. Use zsh's `:A` (no fork) for the comparison, the same check as `envs/bash/bashrc:179-187`.

- [ ] **Step 1: Write the failing test**

In `tests/install-env-zsh`, add a `zsh_i_env CMDS VAR=value...` helper (`zsh_i` plus extra `env -i` assignments), then a section mirroring `tests/install-env-tcsh:263-280`:
1. Copy `~/.config/bash/global` to `$ALTB/global`, and `~/.config/zsh/global` to `$ALTZ/global`, with empty `corp..user` layer dirs in both.
2. In the home layers, set `export LOADOUT_TEST_OV_CFGSH=yes` (`bash/user/config.sh`), `export LOADOUT_TEST_OV_CFGZSH=yes` (`zsh/user/config.zsh`) and `export LOADOUT_TEST_OV_ZSHRC=yes` (`zsh/user/zshrc`).
3. With `BASH_CONFIG_ROOT_DIR=$ALTB ZSH_CONFIG_ROOT_DIR=$ALTZ`, assert that all three print `yes`.
4. Negative control, default roots: `zsh/user/zshrc` also does `export LOADOUT_TEST_ZSHRC_COUNT=$(( ${LOADOUT_TEST_ZSHRC_COUNT:-0} + 1 ))`, and the probe must print `1`.

- [ ] **Step 2: Run it and watch it fail**

Run: `tests/install-env-zsh`
Expected: FAIL. The three overlay variables are empty under the shared roots.

- [ ] **Step 3: Implement the three home-override blocks in `envs/zsh/zshrc`**

- [ ] **Step 4: Run it and watch it pass**

Run: `tests/install-env-zsh && tests/env-shell-parity`
Expected: PASS, with the count at `1`.

- [ ] **Step 5: Docs and commit**

Describe the shared-root plus home-overlay order in `envs/zsh/README.md`. Check that AGENTS.md's `TCSH_CONFIG_ROOT_DIR mirrors bash/zsh config-root vars` sentence is now true and leave it as is.

```bash
git add envs/zsh/zshrc envs/zsh/README.md tests/install-env-zsh
git commit -m "fix(zsh): read home override layers under a shared config root"
```

---

### Task 3: Interactive shell exec for bash and zsh (D1–D4, D6, D7)

**Files:**
- Modify: `envs/bash/functions.sh` (two new functions after `loadout_find_wezterm_shell_integration`)
- Modify: `envs/bash/bashrc:189-199`, which is replaced
- Modify: `envs/zsh/global/zshrc:12-20`, which is replaced, and the closing `unset` line (drop `_loadout_target_shell`)
- Modify: `envs/bash/global/config.sh:1-2`, `envs/zsh/global/config.zsh:13-17` (delete), `envs/tcsh/global/config.csh` (add the definition; the reader is Task 4)
- Modify: `tests/env-shell-parity` (drop the `LOADOUT_CFG_PREFERRED_BASH` row). The `PREFERRED_*` entries join `RETIRED_SHELL_SETTINGS` in Task 4, not here: until Task 4, tcsh comments still name `PREFERRED_BASH`, and adding the entries now would fail the parity check.
- Create: `tests/env-interactive-shell` (T2, POSIX sh). Register it in `tests/run-all` after `install-env-zsh` with `run_test "env-interactive-shell" --deps auto tests/env-interactive-shell`.
- Docs: README.md, AGENTS.md, `docs/BASH.md`, `envs/bash/README.md`, `envs/zsh/README.md`, `docs/TMUX.md`

**Interfaces:**
- Produces `loadout_resolve_interactive_shell VALUE` in `functions.sh`. It prints the resolved absolute path and returns 0, or prints nothing and returns 1. D1 rules, in order:
  - empty → 1;
  - any whitespace → 1;
  - a leading `/` → VALUE itself, if it is a regular executable file;
  - any other `/` → 1;
  - a bare name → `${LOADOUT_CFG_SHARED_PREFIX:-$HOME/.local/share/loadout}/bin/NAME` if that is a regular executable file, else the first `$PATH` entry (split on `:`, empty entries skipped) that holds one.
  - Never use `command -v`, `type` or `whence`: they return aliases and functions.
- Produces `loadout_exec_interactive_shell [BASH_INIT_FILE]`. It returns 0 with no side effects unless D2 conditions 2-6 all hold; the caller does condition 1. Then it exports and execs, and never returns. Task 4 mirrors it in tcsh.
  - **Condition 2:** `LOADOUT_SHELL_EXEC` is unset.
  - **Condition 3:** the shell is interactive and has no command string. bash: `[[ $- == *i* && -z ${BASH_EXECUTION_STRING:-} ]]`; zsh: `[[ -o interactive && -o shinstdin ]]`.
  - **Condition 4:** the origin is a login shell (bash `shopt -q login_shell`, zsh `[[ -o login ]]`), OR `${SHELL:-}` is non-empty, `${SHELL##*/}` ≠ `sh`, and `readlink -f "$SHELL"` equals the running shell.
  - **Condition 5:** `loadout_resolve_interactive_shell` succeeds.
  - **Condition 6:** `readlink -f` of the target ≠ the running shell (`readlink -f /proc/$$/exe`).
  - **Exec form:** `export LOADOUT_SHELL_EXEC="$t" SHELL="$t"`, then:
    - a login origin with a target basename in `bash zsh tcsh csh fish ksh` → `exec "$t" -l`;
    - else, a bash origin with `BASH_INIT_FILE` given and target basename `bash` → `LOADOUT_BASHRC_SOURCED=0 exec "$t" --init-file "$BASH_INIT_FILE"`, as today;
    - else → `exec "$t"`.
- Call sites, at the same position as the blocks they replace:
  - `envs/bash/bashrc`: `[[ -n ${LOADOUT_CFG_INTERACTIVE_SHELL:-} ]] && loadout_exec_interactive_shell "${BASH_SOURCE[0]}"`
  - `envs/zsh/global/zshrc`: the same line without the argument.
- Config definition, replacing `config.sh:1-2`: a 3-line comment (bare name or absolute path; empty keeps the login shell; see README "Choosing your interactive shell"), then `: "${LOADOUT_CFG_INTERACTIVE_SHELL:=}"` and `export LOADOUT_CFG_INTERACTIVE_SHELL`. Add to `config.csh`: `if ( ! $?LOADOUT_CFG_INTERACTIVE_SHELL ) setenv LOADOUT_CFG_INTERACTIVE_SHELL ""`.

- [ ] **Step 1: Write `tests/env-interactive-shell` (bash/zsh cases)**

Header and traps: copy the harness-trap comment and `strip_escapes` from `tests/install-env-zsh`. Skip (exit 0 with `SKIP:`) when there is no `zsh` or `script`. Resolve `BASH_BIN`, `ZSH_BIN`, `TCSH_BIN` and `TMUX_BIN` with `command -v` before any `env -i`. Install with `HOME="$H" "$REPO/loadout" install -y env-bash env-zsh env-tcsh --no-backup`.

Helpers:
- `pty ORIGIN_CMD CMDS [VAR=value ...]` runs `printf '%s\nexit\n' "$CMDS" | env -i HOME="$H" TERM=xterm PATH=/usr/bin:/bin "$@" timeout 20 script -qec "$ORIGIN_CMD" /dev/null`, then `| tr -d '\r' | strip_escapes`.
- `set_pref VALUE [EXTRA_BASH_LINE] [EXTRA_CSH_LINE]` rewrites both user layers: `~/.config/bash/user/config.sh` with `export LOADOUT_CFG_INTERACTIVE_SHELL="VALUE"`, and `~/.config/tcsh/user/config.csh` with `setenv LOADOUT_CFG_INTERACTIVE_SHELL "VALUE"`.
- `PROBE='echo PROBE_comm=`ps -o comm= -p $$` PROBE_marker=`printenv LOADOUT_SHELL_EXEC` PROBE_shell=`printenv SHELL`'`. Backticks and `$$` work in all three shells. The echoed input line never contains `PROBE_comm=<name>`.
- `LOGIN_BASH='shopt -q login_shell && echo PROBE_login=yes || echo PROBE_login=no'` and `LOGIN_ZSH='[[ -o login ]] && echo PROBE_login=yes || echo PROBE_login=no'`.
- `assert_quiet OUT LABEL` fails on any of `No such file`, `not found`, `Permission denied`, `command not found`, `bad substitution`.

Fixtures:
- `$T/bin/mybash` → a symlink to `$BASH_BIN`;
- `$T/bin/zshwrap` → `#!/bin/sh` + `exec "$ZSH_BIN" "$@"`;
- `$T/bin/oddsh` → `#!/bin/sh` + `echo "PROBE_oddsh_args=[$*]"; exec "$ZSH_BIN"`;
- `$T/prefix/bin/zsh` → a symlink to `$ZSH_BIN`;
- `$T/notexec`, mode 644;
- `$T/emptyprefix/bin/`, an empty dir.

Cases (spec Verification items in brackets). `SHELL=$BASH_BIN` unless stated:

| # | Pref | Origin | Expect |
|---|---|---|---|
| a [1] | `$ZSH_BIN` | `bash -l` | `PROBE_comm=zsh`, marker = shell = `$ZSH_BIN`, `PROBE_login=yes` |
| b [2] | `$BASH_BIN` | `zsh -l`, `SHELL=$ZSH_BIN` | `PROBE_comm=bash`, `PROBE_login=yes` |
| c [3,9] | `$ZSH_BIN` | `bash -l`; then typed `bash`, PROBE, `printenv LOADOUT_CFG_INTERACTIVE_SHELL`, `exit` | the child line shows `PROBE_comm=bash`; the preference is printed |
| d [4] | `$ZSH_BIN` | `bash -c 'echo PROBE_c=$BASH_VERSION'` (no PTY), and the zsh twin | prints and exits; no zsh |
| e [5] | empty, then no line at all | `bash -l` | `PROBE_comm=bash`, empty marker |
| f [6] | `/nonexistent/zsh`, `$T/notexec`, `zhs` | `bash -l` | `PROBE_comm=bash`, empty marker, `assert_quiet` |
| g [7] | `$T/bin/mybash` | `bash -l` | no exec, empty marker |
| h [7] | `$T/bin/zshwrap` | `bash -l` | `PROBE_comm=zsh`, marker `$T/bin/zshwrap`, finishes before the timeout |
| i [8] | `zsh` + `export LOADOUT_CFG_SHARED_PREFIX=$T/prefix` | `bash -l` | marker `$T/prefix/bin/zsh` |
| j | `zsh` + prefix `$T/emptyprefix` | `bash -l` | marker = the PATH zsh (`/usr/bin/zsh`) |
| k | `no-such-shell` | `bash -l` | no exec, `assert_quiet` |
| l [10] | `$ZSH_BIN` | `bash -i -l -c 'echo PROBE_cmd=ran'`; the twin `zsh -i -l -c ...` with `$BASH_BIN` | `PROBE_cmd=ran`, no switch, finishes before the timeout |
| m [11] | `$ZSH_BIN` | `bash -i` (non-login) | `PROBE_comm=zsh`, `PROBE_login=no` |
| n [11] | `$T/bin/oddsh` | `bash -l` | `PROBE_oddsh_args=[]` |
| o [12] | `bin/zsh`, then `zsh -l` | `bash -l` | no exec, `assert_quiet` |
| p [13] | `$ZSH_BIN` | `bash -i` with `SHELL=/bin/sh`, only when `readlink -f /bin/sh` ends in `/bash` (else print `SKIP: case p`) | no exec |
| q | `$ZSH_BIN` | `bash -i` with `SHELL` unset, then `SHELL=/nonexistent/bash` | no exec, `assert_quiet` |
| r | `$BASH_BIN` | `bash -l` | no exec, *empty* marker |
| s | `zsh` + prefix `$T/prefix` + `zsh() { echo PROBE_hijack; }` in `user/config.sh` | `bash -l` | marker `$T/prefix/bin/zsh`, no `PROBE_hijack` |

**Case t [14]**, tmux; skip when `TMUX_BIN` is empty:
1. Start `env -i HOME="$H" SHELL="$BASH_BIN" TERM=xterm-256color PATH=/usr/bin:/bin "$TMUX_BIN" -L "el-ishell-$$-a" -f /dev/null new-session -d -s t -x 200 -y 50`.
2. Send `echo PROBE_pane=$(ps -o comm= -p $$)` + Enter, and poll `capture-pane -p` for up to 10 s until `PROBE_pane=zsh` appears.
3. Do the same on socket `-b`, started with `LOADOUT_SHELL_EXEC=$ZSH_BIN` added; expect `PROBE_pane=bash`.

`trap` kills both private servers with `-L ... kill-server`, and only those.

- [ ] **Step 2: Run it and watch it fail**

Run: `tests/env-interactive-shell`
Expected: FAIL on case a (`PROBE_comm=bash`, because nothing reads the new variable yet).

- [ ] **Step 3: Implement both functions, the call sites and the config definitions; delete the `PREFERRED_BASH`/`PREFERRED_ZSH` blocks and definitions**

- [ ] **Step 4: Run it and watch it pass, plus the startup gates**

Run: `bash -n envs/bash/bashrc && bash -n envs/bash/functions.sh && zsh -n envs/bash/functions.sh && tests/env-interactive-shell && tests/env-shell-parity && tests/install-env-bash && tests/install-env-zsh && tests/env-bash-runtime && tests/shell-typeahead`
Expected: all PASS. Case p may print `SKIP: case p` on hosts where `/bin/sh` is not bash.

- [ ] **Step 5: Docs**

- **README.md:** a new "Choosing your interactive shell" section near the shell-env docs (around the tcsh text at :568). Cover:
  - the line for each login-shell family: `export LOADOUT_CFG_INTERACTIVE_SHELL=zsh` in `~/.config/bash/user/config.sh` for bash/zsh logins, and `setenv LOADOUT_CFG_INTERACTIVE_SHELL zsh` in `~/.config/tcsh/user/config.csh` for csh/tcsh logins;
  - the value rules (D1);
  - that a change takes effect in the next fresh session (D3);
  - that a typed shell never bounces back, and `exec zsh -l` for a one-off;
  - that a tcsh `~/.login` stops applying (D4);
  - the tmux migration one-liners (D9);
  - the `PREFERRED_BASH` behaviour change for a typed `bash`/`t` (D7).
  - Add `PREFERRED_BASH`/`PREFERRED_ZSH` rows to "Retired and renamed settings".
- **AGENTS.md:**
  - add `env-interactive-shell` to the test list;
  - in "Config vars", replace `PREFERRED_BASH (re-exec)` with `INTERACTIVE_SHELL (one-shot exec, see README)`;
  - add a short pitfalls paragraph: the exported marker; login-preserving `-l`; the command-string guard (`BASH_EXECUTION_STRING`, `shinstdin`); resolution never uses `command -v`; no `default-shell`.
- **`docs/BASH.md`:** replace the `PREFERRED_BASH` text.
- **`envs/bash/README.md`, `envs/zsh/README.md`:** where the line goes.
- **`docs/TMUX.md`:** the D9 paragraph, i.e. servers that predate the change still switch per pane, and migrate with `set -g default-shell` or `set-environment -gu LOADOUT_SHELL_EXEC`.
- Run `tests/docs-sync`. Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add -u envs/
git add tests/env-interactive-shell tests/env-shell-parity tests/run-all README.md AGENTS.md docs/BASH.md docs/TMUX.md
git commit -m "feat(envs): LOADOUT_CFG_INTERACTIVE_SHELL for bash and zsh; retire PREFERRED_BASH/ZSH"
```

---

### Task 4: Interactive shell exec for tcsh and csh (D5)

**Files:**
- Create: `envs/tcsh/global/helpers/resolve-shell` (POSIX sh, mode 0755)
- Modify: `envs/tcsh/global/tcshrc:24-38`, replaced
- Modify: `envs/tcsh/global/config.csh:11,29-33` (drop the `PREFERRED_*` comment mention and the `PREFERRED_TCSH` definition)
- Modify: `loadout_main.py`: `RETIRED_SHELL_SETTINGS` gains `LOADOUT_CFG_PREFERRED_BASH`, `LOADOUT_CFG_PREFERRED_ZSH` and `LOADOUT_CFG_PREFERRED_TCSH`, all mapping to `"LOADOUT_CFG_INTERACTIVE_SHELL"`. The parity check from Task 1 then guards all three.
- Test: `tests/env-interactive-shell` (tcsh cases)
- Docs: `envs/tcsh/README.md`, README.md (the retired row)

**Interfaces:**
- Produces `helpers/resolve-shell VALUE`: the same contract and rules as `loadout_resolve_interactive_shell` (Task 3). It prints the path and exits 0, or prints nothing and exits 1. It reads `LOADOUT_CFG_SHARED_PREFIX`, `HOME` and `PATH` from the environment and never uses `command -v`.
- The tcsh block applies the same conditions, in Task 3's order:
  - **Gate:** `$?LOADOUT_CFG_INTERACTIVE_SHELL` and non-empty → `! $?LOADOUT_SHELL_EXEC` → `$?prompt`.
  - **Top-level:** `$?loginsh`, OR `$?SHELL`, `"$SHELL:t" != sh`, and `` `readlink -f "$SHELL"` `` equals `` `readlink -f /proc/$$/exe` ``.
  - **Resolve and compare:** `` set _t = "`${_loadout_helpers}/resolve-shell "$LOADOUT_CFG_INTERACTIVE_SHELL"`" `` must be non-empty, and `` `readlink -f "$_t"` `` must differ from the running shell.
  - **Exec:** `setenv LOADOUT_SHELL_EXEC "$_t"` and `setenv SHELL "$_t"`. Then, for a login origin, `switch ( "$_t:t" )` over `bash zsh tcsh csh fish ksh` → `exec "$_t" -l`; otherwise `exec "$_t"`.
  - Unset the block's scratch variables, as the surrounding code does.

- [ ] **Step 1: Add the failing tcsh cases to `tests/env-interactive-shell`**

Skip these when there is no `TCSH_BIN`. `LOGIN_TCSH='echo PROBE_loginsh=$?loginsh'`.

| # | Pref | Origin | Expect |
|---|---|---|---|
| u | `$ZSH_BIN` | `tcsh -l`, `SHELL=$TCSH_BIN` | `PROBE_comm=zsh`, `PROBE_login=yes` |
| v | `$BASH_BIN` | `tcsh -l` | `PROBE_comm=bash`, `PROBE_login=yes` |
| w | `$ZSH_BIN` | `tcsh -i`, `SHELL=$TCSH_BIN` | `PROBE_comm=zsh`, `PROBE_login=no` |
| x | `$TCSH_BIN` | `zsh -l`, `SHELL=$ZSH_BIN` | `PROBE_comm=tcsh`, `PROBE_loginsh=1` |
| y | `$ZSH_BIN` | `tcsh -i -c 'echo PROBE_cmd=ran'` | `PROBE_cmd=ran`, no switch |
| z | `$ZSH_BIN` | `tcsh -l`, then typed `tcsh`, PROBE, `exit` | the child shows `PROBE_comm=tcsh` |
| aa | `zsh` + `setenv LOADOUT_CFG_SHARED_PREFIX $T/prefix` + `alias zsh 'echo PROBE_hijack'` in `user/config.csh` | `tcsh -l` | marker `$T/prefix/bin/zsh`, no `PROBE_hijack` |
| ab | `/nonexistent/zsh` | `tcsh -l` | `PROBE_comm=tcsh`, quiet |
| ac | `$ZSH_BIN` | `csh -l`, only when `readlink -f /bin/csh` ends in `/tcsh` (else `SKIP: case ac`) | `PROBE_comm=zsh` |

- [ ] **Step 2: Run it and watch it fail**

Run: `tests/env-interactive-shell`
Expected: FAIL on case u (`PROBE_comm=tcsh`).

- [ ] **Step 3: Implement the helper and the tcsh block; delete `PREFERRED_TCSH`**

- [ ] **Step 4: Run the tcsh gates**

Run: `dash -n envs/tcsh/global/helpers/resolve-shell && tests/env-interactive-shell && tests/install-env-tcsh && tests/env-tcsh-starship && tests/env-tcsh-prompt-resize && tests/env-shell-parity && tests/env-private-dirs`
Expected: all PASS. Case ac may SKIP.

- [ ] **Step 5: Docs and commit**

In `envs/tcsh/README.md`, document the `setenv` line, the `~/.login` caveat, and csh = tcsh. Add the `PREFERRED_TCSH` row to README's retired table. Run `tests/docs-sync`.

```bash
git add -u envs/tcsh
git add envs/tcsh/global/helpers/resolve-shell loadout_main.py tests/env-interactive-shell README.md
git commit -m "feat(tcsh): LOADOUT_CFG_INTERACTIVE_SHELL for tcsh/csh; retire PREFERRED_TCSH"
```

---

### Task 5: `loadout doctor` interactive-shell audit (D7, csh section)

**Files:**
- Modify: `loadout_main.py`. Add new functions above `_doctor_layout_audit` (~line 7626), and call the audit from it just before its final `print()`.
- Test: `tests/unit-install-steps` (new `test_*` functions, appended to `TESTS`), `tests/doctor-shadow-audit`
- Docs: AGENTS.md (the CLI Verbs `doctor` sentence: add "and an Interactive shell audit"), README.md (the doctor description)

**Interfaces:**
- Consumes `RETIRED_SHELL_SETTINGS` (Tasks 1, 3, 4).
- Produces `_resolve_interactive_shell(value: str, shared_prefix: str, path: str) -> str | None`, the Python mirror of D1 (same rules as Task 3). The caller passes `environ.get("LOADOUT_CFG_SHARED_PREFIX") or os.path.join(user_home, ".local/share/loadout")` and `environ.get("PATH", "")`.
- Produces `_shell_family(path: str) -> str | None`. It returns `"bash"`, `"zsh"` or `"tcsh"` from the basename or the realpath's basename; `"csh"` maps to `"tcsh"`; anything else is None.
- Produces `_doctor_shell_audit(user_home: str, environ: Mapping[str, str]) -> int`. It prints the section and returns the number of findings.
  - **Roots** for each family: `~/.config/<family>` plus `$<FAMILY>_CONFIG_ROOT_DIR` when set, deduped by realpath. Layers are `corp site team project user`; files are `config.sh` (bash), `config.zsh` (zsh), `config.csh` (tcsh).
  - **Retired names:** whole-word regex `(?<![A-Za-z0-9_])NAME(?![A-Za-z0-9_])` over every layer file of every family.
  - **"Set in the passwd family's layers":** a non-comment line containing `LOADOUT_CFG_INTERACTIVE_SHELL` as a whole word. A bash passwd shell checks the bash roots' `config.sh`; zsh checks those plus the zsh roots' `config.zsh`; tcsh checks the tcsh roots' `config.csh`.
  - **Env installed:** `<root>/global` is a directory for the family's first root. The packages are `env-bash`, `env-zsh` and `env-tcsh`.
  - **passwd shell:** `pwd.getpwuid(os.getuid()).pw_shell`; on `KeyError`, `"unknown"`.
- Pinned output substrings (the tests assert these; the wording around them is free):
  - `Interactive shell:` (section header)
  - `passwd shell: <path> (EL rc: yes)` or `(EL rc: no)`
  - `retired setting <NAME> in <path>:<line> -> <replacement>`
  - `LOADOUT_CFG_INTERACTIVE_SHELL=<value> does not resolve`
  - `LOADOUT_CFG_INTERACTIVE_SHELL is not set in the <family> layers`, only when the value is non-empty
  - `<env-package> is not installed`, when the target's family has no env

- [ ] **Step 1: Write the failing unit tests**

In `tests/unit-install-steps`, add `test_resolve_interactive_shell(m, tmp)`. Build `tmp/prefix/bin/zsh` and `tmp/pathdir/zsh` (executable), `tmp/pathdir/plain` (mode 644), and `tmp/bin/abs` (executable). Assert that `m._resolve_interactive_shell(value, f"{tmp}/prefix", f"{tmp}/pathdir")` returns:

| Input | Result |
|---|---|
| `""` | None |
| `"zsh -l"` | None |
| `"bin/zsh"` | None |
| `f"{tmp}/bin/abs"` | that path |
| `f"{tmp}/pathdir/plain"` | None |
| `"zsh"` | `f"{tmp}/prefix/bin/zsh"` (prefix wins) |
| `"zsh"` with prefix `f"{tmp}/none"` | `f"{tmp}/pathdir/zsh"` |
| `"nosuch"` | None |

Add `test_shell_family(m, tmp)`: `/bin/csh` → `"tcsh"`, `/usr/bin/zsh` → `"zsh"`, `/usr/bin/fish` → None, and a symlink named `mysh` pointing to a file named `bash` → `"bash"`. Append both to `TESTS`.

- [ ] **Step 2: Write the failing doctor test**

Add a section to `tests/doctor-shadow-audit`:
1. Create `$home/.config/bash/global/`, `$home/.config/tcsh/global/` and `$home/.config/bash/user/config.sh` containing `export LOADOUT_CFG_PREFERRED_BASH=/x`, `export LOADOUT_CFG_ATTACH_TO_TMUX_WITH_DETACH_OTHERS=1`, `export LOADOUT_CFG_ENABLE_WEZTERM_SHELL_INTEGRATION=1` and `export LOADOUT_ONLINE_CACHE_TTL=0`.
2. Run `env -i HOME="$home" PATH=/usr/bin:/bin TERM=xterm LOADOUT_CFG_INTERACTIVE_SHELL="zsh -l" "$repo/loadout" doctor` and assert:
   - exit 0;
   - `Interactive shell:` present;
   - `retired setting LOADOUT_CFG_PREFERRED_BASH in` with `-> LOADOUT_CFG_INTERACTIVE_SHELL`;
   - exactly one `retired setting LOADOUT_CFG_ATTACH_TO_TMUX_WITH_DETACH_OTHERS`;
   - no `retired setting LOADOUT_CFG_ATTACH_TO_TMUX in`;
   - no `ENABLE_WEZTERM` in any `retired setting` line;
   - `-> LOADOUT_CFG_ONLINE_CACHE_TTL`;
   - `does not resolve`.
3. **Second run:** if `/usr/bin/zsh` exists, `LOADOUT_CFG_INTERACTIVE_SHELL=/usr/bin/zsh` with no `.config/zsh/global` → `env-zsh is not installed`.
4. **Wrong layer:** `fam=$(basename "$(getent passwd "$(id -un)" | cut -d: -f7)")`. Run doctor with `LOADOUT_CFG_INTERACTIVE_SHELL=zsh` in its environment, and write the variable only into the *other* family's user layer (tcsh when the passwd shell is bash or zsh, bash when it is tcsh or csh) → `is not set in the <bash|tcsh> layers`. When the passwd family is something else, assert `(EL rc: no)` instead.
5. **Negative control:** the existing clean-HOME run must show no `retired setting` and no `does not resolve`.

- [ ] **Step 3: Run them and watch them fail**

Run: `tests/unit-install-steps; tests/doctor-shadow-audit`
Expected: FAIL (`AttributeError: ... _resolve_interactive_shell`; no `Interactive shell:` section).

- [ ] **Step 4: Implement the three functions and the call from `_doctor_layout_audit`**

- [ ] **Step 5: Run them and watch them pass**

Run: `tests/unit-install-steps && tests/doctor-shadow-audit && ruff check loadout_main.py && ruff format --check loadout_main.py && python3.15 -m py_compile loadout_main.py`
Expected: all PASS.

- [ ] **Step 6: Docs and commit**

Update the AGENTS.md and README doctor descriptions, then run `tests/docs-sync`.

```bash
git add loadout_main.py tests/unit-install-steps tests/doctor-shadow-audit AGENTS.md README.md
git commit -m "feat(doctor): interactive-shell audit and retired-setting report"
```

---

### Task 6: xfce4-terminal seeds login-shell windows (D8, its own commit)

**Files:**
- Modify: `envs/xfce4-terminal/xfce4-terminal.xml`: add `<property name="command-login-shell" type="bool" value="true"/>`
- Modify: `envs/xfce4-terminal/terminalrc`: add `CommandLoginShell=TRUE`, keeping the keys alphabetical
- Test: `tests/install-env-xfce4-terminal`: `trc_key_for` gains `command-login-shell) echo CommandLoginShell ;;`, and the shared-lines loop gains `'CommandLoginShell=TRUE'`
- Docs: `envs/xfce4-terminal/README.md`:
  - a new table row;
  - the counts become thirteen properties, twelve of them mapping exactly;
  - a paragraph saying it is seeded once, so existing users keep `FALSE` until they delete the file or tick the preference;
  - why: switched shells get their family's system init (spec D8).
- Docs: `docs/HANDOFF.md`, a one-line "next release notes" entry: new installs open xfce4-terminal windows as login shells.

- [ ] **Step 1: Add the test expectations**

- [ ] **Step 2: Run them and watch them fail**

Run: `tests/install-env-xfce4-terminal`
Expected: FAIL with `terminalrc missing: CommandLoginShell=TRUE`.

- [ ] **Step 3: Add the property to both seeded files**

- [ ] **Step 4: Run it and watch it pass**

Run: `tests/install-env-xfce4-terminal && tests/docs-sync`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -u envs/xfce4-terminal
git add tests/install-env-xfce4-terminal docs/HANDOFF.md
git commit -m "feat(env-xfce4-terminal): seed login-shell windows"
```

---

### Task 7: The Settings table and the docs-sync gate

**Files:**
- Modify: `tests/docs-sync`: add `test_cfg_vars_documented` and put it in `main()`'s tuple after `test_kinds_documented`
- Modify: `envs/bash/README.md` (new `## Settings` section), `envs/zsh/README.md` and `envs/tcsh/README.md` (one line each, linking to it)

**Interfaces:**
- The gate's definition rules:
  - `^\s*export\s+(LOADOUT_CFG_[A-Z0-9_]+)` and `^\s*typeset\s+-g?x\s+(LOADOUT_CFG_[A-Z0-9_]+)` in `envs/bash/global/config.sh` and `envs/zsh/global/config.zsh`;
  - `\bsetenv\s+(LOADOUT_CFG_[A-Z0-9_]+)` in `envs/tcsh/global/config.csh`.
  - Name exactly those three files.
  - Each name must appear as a whole word in at least one `current_md()` path that starts with `docs/` or `envs/`.
  - Sanity check: at least 20 names found.
- The table has columns `Setting | Default | Shells | What it does`, one row per setting below. Take the descriptions from the comments in the three config files and the spec. The Shells column is decided:

| Shells | Settings |
|---|---|
| all | `INTERACTIVE_SHELL`, `SHARED_PREFIX`, `SHM_DIR`, `PREFERRED_LS`, `PREFERRED_VI`, `TMUX_TERM` (read by tmux), `ENABLE_TMUX_PATH_STORE`, `PROMPT_INCLUDE_HOST`, `PROMPT_COLOR_NORMAL`, `PROMPT_COLOR_FARM` (built-in prompt only; tcsh values are tcsh escapes), `ENABLE_LINELIGHT`, `ENABLE_SSH_AGENT`, `ENABLE_STARSHIP`, `STARSHIP_USERIDS_TO_HIGHLIGHT`, `ONLINE_DETECT`, `ONLINE_DETECT_TIMEOUT`, `ONLINE_DETECT_HOSTS`, `USE_LOADOUT_MODULES` |
| bash, zsh | `ENABLE_FZF`, `ENABLE_ZOXIDE`, `ENABLE_WEZTERM_SHELL_INTEGRATION` |
| bash, tcsh | `ONLINE_CACHE_TTL` (zsh probes on every login; noted as a follow-up in Task 9) |
| bash | `ENABLE_ICECREAM`, `PRESERVE_FUNCTIONS` |
| zsh | `ZSH_ENABLE_COMPLETION`, `ZSH_ENABLE_BASHCOMPINIT` |

- [ ] **Step 1: Add the gate**

- [ ] **Step 2: Run it and watch it fail**

Run: `tests/docs-sync`
Expected: FAIL. It lists the knobs that are still undocumented (about 10, among them `ENABLE_ICECREAM`, `PROMPT_COLOR_FARM` and `STARSHIP_USERIDS_TO_HIGHLIGHT`).

- [ ] **Step 3: Write the Settings table and the two links**

- [ ] **Step 4: Run it and watch it pass**

Run: `tests/docs-sync`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add tests/docs-sync envs/bash/README.md envs/zsh/README.md envs/tcsh/README.md
git commit -m "docs(envs): one Settings table; docs-sync requires every setting documented"
```

---

### Task 8: Tier 3 container test (EL8 system init across a switch)

**Files:**
- Create: `tests/interactive-shell-almalinux8`, shaped like `tests/private-state-two-users`:
  - **Host mode:** skip with `SKIP` when docker or the image is missing. Otherwise `exec docker run --rm --network=none --user root --entrypoint /bin/sh -v "$REPO:/src:ro" loadout-smoke:almalinux8.10 /src/tests/interactive-shell-almalinux8 --inside`.
- Modify: `tests/run-all`: in the `--container` block, add `run_test "interactive-shell-almalinux8" --deps container tests/interactive-shell-almalinux8`
- Docs: AGENTS.md (test list; one Testing-tiers clause naming it as a Tier 3 gate)

**Interfaces:**
- **Root setup inside the container:**
  - `/etc/profile.d/zz-el-t3.sh` holds `el_t3_sh_profile() { :; }`, and `/etc/profile.d/zz-el-t3.csh` holds `alias el_t3_csh_profile true`. These are the stand-ins for Environment Modules' `module`, which the image lacks: a function or alias defined only by a family's system init.
  - `/etc/zprofile` holds EL's zsh-rpm content, `emulate sh -c 'source /etc/profile'`. The image has no zsh rpm, but the payload's libzsh reads `/etc/zprofile`.
  - `useradd --create-home carol`.
- **As carol** (`runuser -u carol -- env -i HOME=/home/carol USER=carol PATH=/usr/bin:/bin LANG=en_US.UTF-8 ...`): run `/src/loadout install -y zsh env-bash env-zsh env-tcsh --no-backup`. The default root provides `bin/zsh` for the bare name. Use the `pty`/`PROBE` shapes from Task 3, with preferences written to carol's user layers.

- [ ] **Step 1: Write the test**

| # | Pref | Origin | Expect |
|---|---|---|---|
| T3-a | `bash` | `tcsh -l` | `PROBE_comm=bash`, `PROBE_login=yes`, `type el_t3_sh_profile` succeeds |
| T3-b | `zsh` | `tcsh -l` | `PROBE_comm=zsh`, `PROBE_login=yes`, `whence -w el_t3_sh_profile` prints `function` |
| T3-c | `bash` | `$HOME/.local/share/loadout/bin/zsh -l` | bash login; `el_t3_sh_profile` defined (the zsh origin never ran `/etc/profile`, so the target must have) |
| T3-d | `tcsh` | `bash -l` | `PROBE_loginsh=1`; `alias el_t3_csh_profile` prints `true` |
| T3-e | `zsh` | `csh -l` | `readlink -f /bin/csh` ends in `/tcsh`; `PROBE_comm=zsh` |

- [ ] **Step 2: Run it**

Run: `tests/interactive-shell-almalinux8`
Expected: PASS. A failure on T3-a to T3-d means login-ness was not preserved (D4). If docker fails with the bridge error, STOP (see Global Constraints).

- [ ] **Step 3: Commit**

```bash
git add tests/interactive-shell-almalinux8 tests/run-all AGENTS.md
git commit -m "test(tier3): interactive shell switch keeps each family's system init on EL8"
```

---

### Task 9: Full gates, manual X check, handoff

**Files:**
- Modify: `docs/HANDOFF.md`, `assurance/release-timings.tsv` (rows appended by `run-all`)

- [ ] **Step 1: Confirm no other suite is running**

Run: `pgrep -fa tests/run-all`
Expected: no output. Otherwise wait for it to finish.

- [ ] **Step 2: Run T1 + T2**

Run: `tests/run-all`
Expected: every test PASS. The run's own total is recorded as `test:total` in `assurance/release-timings.tsv`.

- [ ] **Step 3: Run Tier 3**

Run: `tests/run-all --container`
Expected: every test PASS, including `interactive-shell-almalinux8`.

- [ ] **Step 4: Run the final drift check**

Run: `rg -n 'PREFERRED_(BASH|ZSH|TCSH)|ATTACH_TO_TMUX|FASTNVIM|ENABLE_ONLINE_UPDATES|LOADOUT_ONLINE_CACHE_TTL|LOADOUT_CFG_WEZTERM_SHELL_INTEGRATION' --glob '!docs/archive/**' --glob '!docs/superpowers/**' --glob '!docs/HANDOFF.md'`
Expected: hits only in README's "Retired and renamed settings" table, in `loadout_main.py`'s `RETIRED_SHELL_SETTINGS`, and in the `tests/doctor-shadow-audit` fixtures.

- [ ] **Step 5: Do the manual X-session check (no automated gate exists)**

In a real X session with `LOADOUT_CFG_INTERACTIVE_SHELL=zsh` set in the passwd shell's layer, check that:
1. an xfce4-terminal window opened from the launcher starts as the passwd shell and switches to zsh as a login shell;
2. `xfce4-terminal` typed in a switched shell opens zsh directly;
3. with xfce4-terminal already running (it is single-instance), changing the preference and opening a window from the launcher shows whether the first instance's marker carries over (D3).

Record each result.

- [ ] **Step 6: Write the HANDOFF entry and commit**

In `docs/HANDOFF.md`, add a dated entry covering:
- what landed (Tasks 1-8, with commit hashes);
- the gate results and durations (from `build/bottlenecks`);
- the manual X results from Step 5;
- the follow-ups:
  - zsh does not cache the online verdict (`loadout_detect_online` vs bash's `_cached`);
  - the non-login bash target residual (D4);
  - the single-instance terminal behaviour, if Step 5 showed the marker carrying over.

```bash
git add docs/HANDOFF.md
git commit -m "docs(handoff): interactive shell selection landed"
git add assurance/release-timings.tsv
git commit -m "chore(assurance): record T1/T2/T3 timings for interactive shell selection"
```
