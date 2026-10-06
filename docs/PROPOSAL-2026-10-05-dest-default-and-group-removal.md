# Proposal: XDG-compliant default `--dest-dir`, and retire `@engineering-loadout`

> **Status: superseded for implementation** by
> [`docs/superpowers/specs/2026-10-05-dest-default-and-group-removal-design.md`](superpowers/specs/2026-10-05-dest-default-and-group-removal-design.md),
> which carries the full ask set plus the `prefer/` mechanism, resolves two internal
> inconsistencies (§5.2 vs §7 on the `local/` level; §3 vs §5.4 on config routing),
> and supersedes the stale "pending upstream merge" note in §6 (config.toml is merged
> on `main`, `8f16d52`). Retained as the evidence base.

**Author:** machine-state review, 2026-10-05
**Status:** proposal for discussion — no code changed beyond the already-merged
`config.toml` support (see "Already landed")
**Evidence:** all measurements below were taken on the live machine during the
session that prompted this document, not recalled.

---

## 1. The problem in one paragraph

Engineering Loadout installs its curated set into `$HOME/.local`, which places
EL's copies of `coreutils`, `bash`, `node`, `python3` and ~170 other binaries in
`~/.local/bin`. That directory sits **ahead of `/usr/bin`** on `PATH`, so the
loadout silently wins every lookup — and its builds are frequently **older** than
the distribution's. On the reviewed machine this produced `cat` 9.7 instead of
9.12, `bash` 5.3.15 instead of 5.3.20, and `node` v26.7.0 instead of v26.10.0,
with **176 shadowed binaries including 22 coreutils/shell entries**. The cause is
not hardware or PATH ordering in the abstract; it is that EL's default install
root is a *system-precedence* location. `--dest-dir` already solves it, but
nothing made it the default, and the one group advertised as the friendly
one-liner actively defeats it (below).

---

## 2. What the default destination should be

### Recommendation

```
~/.local/share/loadout
```

producing:

```
~/.local/share/loadout/
├── bin/          user-specific executables
├── lib/ lib64/ libexec/ include/    ELF payload (RPATH-relative; travels together)
├── share/        applications, fonts, man, doc, mime, metainfo, …
└── state/        mutable state (nvim)
```

### Why this and not the alternatives

| candidate | verdict |
|---|---|
| `$HOME/.local` (**current default**) | Rejected. This is the bug: `~/.local/bin` outranks `/usr/bin` on PATH. |
| `~/loadout` | Works, and is what the reviewer used, but it is non-canonical and clutters `$HOME` with a second tool root. Acceptable as a stopgap, not as the default. |
| `~/.local/loadout` | Acceptable. Short and predictable, but sits outside every XDG category, so tooling that enumerates XDG dirs will not see it. |
| **`~/.local/share/loadout`** | **Recommended.** |

`~/.local/share` is `XDG_DATA_HOME`, the spec's home for "data files" — installed
files that are not user configuration and not transient state. A multi-gigabyte
installed tool tree is exactly that. It is also the pattern the closest
analogues already use on this machine, measured directly:

```
$ uv tool dir
/home/mylesp/.local/share/uv/tools      # installed python tools
$ uv cache dir
/home/mylesp/.cache/uv                  # and cache under XDG_CACHE_HOME
```

`uv` splits *installed tools* (data home) from *cache* (cache home). EL should do
the same, and it already does for its own `state/` — EL putting `nvim` under
`state/` is correct XDG usage and is worth keeping as-is.

### Executables

The XDG Base Directory spec names `$HOME/bin` and `$HOME/.local/bin` as suitable
places for user-specific executables; there is no `XDG_BIN_HOME` in the spec.
Two consequences for the design:

1. `~/.local/share/loadout/bin` is **not** on `PATH` by default, and should not
   be. Adding it is an explicit, documented step (see §5).
2. Because it is not `~/.local/bin`, adding it **cannot** shadow a
   distribution binary the way the current default does.

---

## 3. `~/.config` must never receive a `--dest-dir` tree

This is the second half of the bug and it is currently violated.

`--dest-dir` redirects a package's `install_to` by anchoring `~` at the install
root. A group that mixes **env config bundles** with shared binaries therefore
drags `~/.config` into the destination tree. Measured after one
`install @engineering-loadout --dest-dir ~/.loadout`:

```
~/.loadout/.config/   bash editorconfig helix nvim pip st starship tealdeer tmux vim zsh
~/.loadout/.cache/    nvim
~/.loadout/local/share/  nvim  zsh  helix
```

Nothing reads those copies — `BASH_CONFIG_ROOT_DIR` and `STARSHIP_CONFIG` both
resolve to `$HOME/.config` — so they were inert, but they were a live **drift
hazard**: the `tmux` copy had already diverged (321 files in `$HOME` vs 314 in
the dest tree), so any future code path that resolved against the dest tree
would read stale configuration.

The invariant to encode and test:

> **`--dest-dir` applies to the shared/binary tree only. `config` and `cache`
> always resolve under `$HOME`.**

`@engineering-loadout` violates it, which is the strongest argument for its
removal.

---

## 4. Retire `@engineering-loadout`

### Structure

Defined at `payload/packages.json:3994`, `kind: group`, 22 members:

```json
{ "kind": "group",
  "members": ["@shared", "env-bash", "env-editorconfig", "env-helix",
              "env-nvim", "env-pip", "env-st", "env-starship", "env-tmux",
              "env-vim", "env-zsh", "git-nvim", "@editor-gui", "@gui-suite",
              "@scientific", "@eda", "@python-tools-extra", "@fonts-all",
              "@shells-optional", "nodejs", "modules", "lua-language-server"],
  "description": "Curated loadout — shared packages, per-user config bundles, and selected package groups" }
```

**Good news: it is a leaf.** No other group lists it in `members` /
`includes` / `recommends` / `depends`, so deleting the entry cannot orphan a
resolution path.

### What breaks, precisely

| location | reference | consequence of removal |
|---|---|---|
| `payload/packages.json:3994` | the definition | delete (leaf, safe) |
| `payload/packages.json:19` | `optional` field doc string | stale prose; update |
| `loadout_main.py:324,348,4018,6272,6681,6731,6733` | 7 help/error strings present it as *the* recommended entry point | must be repointed, or the CLI recommends a name that no longer resolves |
| `tests/check-installer:89-106` | dry-runs `@engineering-loadout`, asserts ≥80 packages resolve | **fails** |
| `tests/install-linux-tmp-home:111` | installs `@engineering-loadout` as the broad fresh-HOME smoke | **fails** |
| `tests/unit-resolver:99` | asserts the bare-`all` error message mentions `@engineering-loadout` | **fails** |
| `envs/bash/global/completions/loadout.bash:24-25` | lists it among completable groups | offers a dead name |
| `envs/nvim/lua/global/paths.lua:4` | comment reference | stale prose |
| docs ×8 (`README`, `INSTALLATION`, `ARCHITECTURE`, `HANDOFF`, `MAINTENANCE`, `RELEASE`, `KNOWLEDGE-BASE`, `build/ADDING_BINARIES`) | prose + examples | update |

21 files total. This is a coordinated change, not a one-line delete — which is
worth stating plainly, because the group is *structurally* trivial to remove and
that is exactly the trap.

### Replacement

The two-step split is what users should be told to run, and it is the split that
makes `--dest-dir` safe:

```bash
loadout install @shared-all            # shared tools  -> dest tree
loadout install @envs                  # env configs   -> $HOME
LOADOUT_CFG_SHARED_PREFIX=~/.local/share/loadout loadout install @envs
```

Test repointing:

- `tests/check-installer` step 4 → dry-run `@shared-all` and assert the same
  `REQUIRED_FULL` set resolves. Keep the assertion, change the input.
- `tests/install-linux-tmp-home` → install `@shared-all` + `@envs-all` (it
  already appends `@envs-all`), preserving breadth. This is arguably a *better*
  smoke test, since it exercises the shared/env boundary explicitly instead of
  hiding it inside one curated name.
- `tests/unit-resolver` → the bare-`all` rejection message must still point at
  real replacements. Repoint to `@shared-all` / `@envs-all`, which are the names
  that will survive.

---

## 5. Other changes this session argues for

### 5.1 Make the new default the actual default

Not just `config.toml`-configurable — **built-in**. Change `_resolve_home` so
that with no flag and no config, the install root is
`$XDG_DATA_HOME/loadout` (i.e. `~/.local/share/loadout`), rather than `$HOME`.

This is the single change that prevents the class of bug. Users who want the
old layout set `dest_dir = "~"` in `config.toml`; users on an air-gapped
corporate prefix keep passing `--dest-dir /opt/...`.

### 5.2 Drop the extra `local/` level for the new default

Today `_local_name(home)` returns `.local` when the root is `$HOME` and `local`
otherwise, so `--dest-dir /foo` yields `/foo/local/bin`. With a default root of
`~/.local/share/loadout`, naively reusing that gives the ugly
`~/.local/share/loadout/local/bin`.

Suggest: when the resolved root is the built-in XDG default (or the config
value), install **directly** at `<root>/`, and keep the `local/` level only for
explicit `--dest-dir` prefixes, which genuinely model `/usr/local`. The shared
prefix for `LOADOUT_CFG_SHARED_PREFIX` then becomes `~/.local/share/loadout`,
matching the documented "`LOADOUT_CFG_SHARED_PREFIX` is baked into your
`config.sh` so PATH, TERMINFO_DIRS, and the tealdeer cache resolve against it".

### 5.3 EL's bash env should APPEND to PATH, never PREPEND

Measured after `loadout install @envs`:

```
$ bash -lc 'echo $PATH | tr : "\n" | head -4'
/home/mylesp/.cargo/bin
/home/mylesp/.opencode/bin
/home/mylesp/.loadout/local/bin     <-- EL's bin, ahead of /usr/bin
/home/mylesp/.pi/agent/bin
```

EL prepends its `bin` directory, which means a user who relocates EL but does
nothing else still shadows the distribution. Recommend:

- Append `$LOADOUT_CFG_SHARED_PREFIX/bin` to `PATH`, not prepend.
- Where a tool must be *preferred* over a distribution one, offer it as an
  explicit opt-in rather than a default — EL already has `LOADOUT_CFG_PREFERRED_LS`,
  `LOADOUT_CFG_PREFERRED_VI`, `LOADOUT_CFG_PREFERRED_CAT` for exactly this, which
  is the right mechanism and should be the only one.
- Document the PATH line to add, and note that adding it is safe precisely
  because it is not `~/.local/bin`.

### 5.4 `dest_dir` must never apply to an env-only install

Even with the default changed, a user can still run
`loadout install @envs` while `dest_dir` is set, and redirect their configs.
Suggest: when the resolved install set contains **only** `env`/`group` packages,
ignore `dest_dir` unless the flag was passed explicitly on the command line, and
say so once:

```
note: env bundles always install under $HOME; ignoring dest_dir=… for this install
```

This makes §3's invariant a property of the tool rather than a property of which
group a user happened to type.

### 5.5 Fix the `starship init` staleness trap

Not strictly a destination issue, but it surfaced directly from the relocation
and will recur on **every** future move.

`starship init bash` bakes the **absolute path** of the resolved `starship`
binary into the `starship_precmd` function:

```
PS1="$(/home/mylesp/.local/bin/starship prompt "${ARGS[@]}")";
```

So any shell started before a relocation keeps invoking a path that no longer
exists, and every prompt draw prints:

```
bash: /home/mylesp/.local/bin/starship: No such file or directory
```

Note this is **not** fixed by `hash -r` — the path is inside the function body,
not the hash table. The fix is to re-run the init:

```bash
eval "$(starship init bash)"; hash -r
```

Two consequences worth handling in EL:

- Document the recovery command in the relocation notes.
- Consider having the env detect a `starship_precmd` pointing at a missing
  binary and self-heal, since a broken prompt after any toolchain move is a
  guaranteed support question.

### 5.6 Consider a doctor check for shadowing

`loadout doctor` already validates registry integrity and archive presence. A
check that reports "N EL-managed names also exist in a system directory and
would win on PATH" would have caught all of this before it was noticed. The
reviewer never saw it because nothing surfaced it.

---

## 6. Already landed

`config.toml` support is implemented and committed on this machine
(`feat(config): persistent install root via ~/.config/engineering-loadout/config.toml`),
pending upstream merge:

```toml
# ~/.config/engineering-loadout/config.toml
dest_dir = "~/.loadout"
```

- Precedence: **explicit flag > config file > `$HOME`**.
- `dest_dir` mirrors the flag name.
- Missing / unreadable / malformed / wrong-typed config degrades to "no default"
  rather than aborting an install — a hand-edited file must not block a
  multi-gigabyte install.
- `tests/config-toml-dest-dir` pins this (10 cases).
- Note the default here is still `$HOME`; §5.1 proposes changing that to
  `~/.local/share/loadout`.

---

## 7. Migration path for an existing machine

Ordered, with the safe stop after each step.

1. **Stop the bleeding (reversible, no reinstall).** Move the loadout directory
   to the new location and prune the duplicates:

   ```bash
   ./loadout install @shared-all --dest-dir ~/.local/share/loadout -y
   # prune: remove from ~/.local/bin every name also present in the dest bin
   # use an ABSOLUTE /usr/bin/rm — a loop that deletes `rm` while it resolves
   # through ~/.local/bin fails on every later iteration
   ```

   Back up `~/.local/bin` first. Ownership must be decided **by name**
   (present in both trees), not by content hash: EL rebuilds several packages
   with different options than the previous build, so `bash`, `broot`, `btm`,
   `fd`, `fzf`, `klayout` and `lazygit` all hashed differently while still being
   EL's.

2. **Repoint the env**, without touching `$HOME` configs:

   ```bash
   LOADOUT_CFG_SHARED_PREFIX=~/.local/share/loadout ./loadout install @envs -y
   ```

   This rewrites `export LOADOUT_CFG_SHARED_PREFIX=` in
   `~/.config/bash/global/config.sh` only.

3. **Add the PATH line** to `~/.bashrc` / `~/.zshrc`, **appended**:

   ```bash
   _loadout_bin="${LOADOUT_CFG_SHARED_PREFIX:-$HOME/.local/share/loadout}/bin"
   case ":$PATH:" in *":$_loadout_bin:"*) ;; *)
     PATH="$PATH:$_loadout_bin"; export PATH ;; esac
   unset _loadout_bin
   ```

4. **Open new terminals.** Existing shells keep their old PATH *and* their baked
   `starship_precmd`; fix each with the §5.5 one-liner.

5. **Prune leftovers**: the old `~/.local/lib` payload and any
   `<dest>/.config` or `<dest>/.cache` copies (§3).

**Known gap:** the GUI session's PATH is set by the login chain and does **not**
include the loadout directory. A `~/.config/systemd/user.conf.d/` drop-in with
`[Manager] DefaultEnvironment=PATH=…` does **not** work for this — the user
manager inherits PATH from the login session, and `DefaultEnvironment` cannot
override an already-populated environment block (verified: `systemctl --user
daemon-reexec` left `show-environment` unchanged). A session-wide change needs
`/etc/environment` via `pam_env`, which is system-wide and requires root.
Nothing is broken today because no `.desktop` `Exec` invokes a loadout-only tool
by bare name, but it should be documented rather than discovered.

---

## 8. Summary of asks

| # | change | why |
|---|---|---|
| 1 | default `--dest-dir` = `$XDG_DATA_HOME/loadout` | removes the shadowing class of bug at the source |
| 2 | drop the extra `local/` level for that default | `~/.local/share/loadout/bin`, not `…/loadout/local/bin` |
| 3 | delete `@engineering-loadout` | it is the one-liner that defeats `--dest-dir` by dragging env configs along |
| 4 | repoint the 3 tests + 7 help strings + completions | removing the group otherwise leaves the CLI recommending a dead name |
| 5 | EL's env APPENDS to PATH; preference via `LOADOUT_CFG_PREFERRED_*` | prepending is what let EL outrank `/usr/bin` |
| 6 | `dest_dir` ignored for env-only installs, with a note | makes "config never goes to dest" a tool invariant |
| 7 | document + self-heal the `starship init` absolute-path trap | a broken prompt after any move is a guaranteed support question |
| 8 | `doctor` check for names that would shadow a system binary | would have caught this before anyone noticed |