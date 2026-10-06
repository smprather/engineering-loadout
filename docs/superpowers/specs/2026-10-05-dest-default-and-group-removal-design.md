# XDG default install root, retire `@engineering-loadout`, PATH preference

Date: 2026-10-05
Status: draft for review
Evidence base: `docs/PROPOSAL-2026-10-05-dest-default-and-group-removal.md`
Scope: proposal asks 1–8. Uninstall is explicitly out of scope (separate spec).
Release class: **C** (installer / registry / repo-layout change) per `docs/RELEASE.md`.

## Problem

EL installs into `$HOME/.local`, putting EL's copies of `coreutils`, `bash`, `node`,
`python3` and ~170 other binaries in `~/.local/bin` **ahead of `/usr/bin`**. On the
reviewed machine that shadowed 176 system binaries, including 22 coreutils/shell
entries, with EL builds that were often older (`cat` 9.7 vs 9.12, `bash` 5.3.15 vs
5.3.20, `node` v26.7.0 vs v26.10.0). The default install root is a *system-precedence*
location, so the installer silently wins every lookup. `--dest-dir` already solves it,
but nothing made it the default, and the one advertised one-liner —
`@engineering-loadout` — conflated the shared tree with per-user env configs, so a
relocated install dragged `~/.config` copies into the destination tree where nothing
reads them (inert, but a drift hazard: the `tmux` copy had already diverged).

## Decisions

### D1 — Built-in default root is `$XDG_DATA_HOME/loadout`

Resolution order (`_resolve_home`):

1. explicit `--dest-dir DIR` (command-line source),
2. `dest_dir` in `~/.config/engineering-loadout/config.toml`,
3. `$XDG_DATA_HOME/loadout` when `XDG_DATA_HOME` is set and absolute, else
   `~/.local/share/loadout`.

`~/.local/share` is the XDG spec's home for data files that are not configuration and
not transient state — exactly an installed tool tree. `uv` splits installed tools
(`~/.local/share/uv/tools`) from cache the same way.

Users who want the old layout set `dest_dir = "~"` in `config.toml`.

### D2 — The install root is a prefix; `.local` is dropped for non-HOME roots

`_local_root(root)`:

| root | tree |
|---|---|
| real `$HOME` | `<root>/.local/...` (legacy layout, unchanged) |
| anything else | `<root>/...` (direct) |

The `.local` component of registry `install_to` values is kept only in HOME mode and
dropped otherwise. Resulting layouts for the same path are identical whether reached
by default, config, or flag — no same-path-different-mode footgun.

| mode | install root | shared tree | layout example |
|---|---|---|---|
| default | `~/.local/share/loadout` | `<root>` | `…/loadout/bin`, `…/loadout/share/...` |
| config `dest_dir = "~"` | `$HOME` | `$HOME/.local` | `~/.local/bin` (legacy) |
| config `dest_dir = "/opt/lo"` | `/opt/lo` | `/opt/lo` | `/opt/lo/bin` |
| explicit `--dest-dir /opt/lo` | `/opt/lo` | `/opt/lo` | `/opt/lo/bin` |

**This resolves a contradiction inside the proposal.** §5.2 says "keep the `local/`
level for explicit `--dest-dir` prefixes", but §7's own migration command
(`install @shared-all --dest-dir ~/.local/share/loadout`) would then create
`…/loadout/local/bin`, contradicting §5.2's target of `…/loadout/bin`. Keeping the
level also makes the same path behave differently by source. Dropping it costs test
churn and nothing else; `--dest-dir ~/.local` now expresses the legacy layout exactly.

### D3 — Config and cache never enter the install root (one staging exception)

Two roots are threaded through the install:

- `user_home` — the real user's HOME.
- `install_root` — the shared/binary tree from D1.

Routing rule, applied to the **resolved** selection (groups already expanded):

| selection | shared tree | env config / per-user data |
|---|---|---|
| contains any non-env package (mixed) | `install_root` | `user_home`, **even when `--dest-dir` was explicit** |
| only env packages, no explicit flag | n/a (nothing shared selected) | `user_home`; config `dest_dir` ignored with a note |
| only env packages, explicit `--dest-dir D` | n/a | `D` (staging/testing escape hatch, today's behavior) |

Explicit-flag detection uses click's parameter source
(`ctx.get_parameter_source("dest_dir") == ParameterSource.COMMANDLINE`); the click
default (which carries the config value) does not count.

When the config `dest_dir` is ignored for an env-only install, print exactly once:

```text
note: env bundles always install under $HOME; ignoring dest_dir=… for this install
```

The mixed-set rule is what the proposal measured as the bug: `install
@engineering-loadout --dest-dir ~/.loadout` dragged `~/.config` into the dest tree.
After the group is retired (D6) mixed sets are explicit, and they still must not drag
config. The env-only explicit-flag case remains because staging a HOME for tests is a
real workflow; tests that stage everything set `HOME` instead.

### D4 — PATH: append the shared `bin`, prepend the `prefer` dir

- `<prefix>/bin` is **appended** (system wins where a copy exists).
- `<prefix>/prefer` is **prepended** (see D5); it goes after the existing prepends so
  it outranks `~/.local/bin` and stale legacy copies.
- Fallback prefix when `LOADOUT_CFG_SHARED_PREFIX` is empty:
  `$HOME/.local/share/loadout` (was `$HOME/.local`).
- `~/.local/bin` stays prepended: it is the conventional user bin dir, and after
  migration it holds no EL files.
- TERMINFO_DIRS, Qt plugin path, `GI_TYPELIB_PATH`, `NVIM_QT_RUNTIME_PATH`, and
  gnuplot's driver dir all derive from the same fallback prefix and must be updated
  together in bash, zsh and tcsh.

Preference of an EL tool over a system one is never implicit from PATH order; the
`LOADOUT_CFG_PREFERRED_{LS,VI,CAT}` aliases keep their interactive-only meaning and
are unchanged.

### D5 — Managed `prefer/` shims for explicit per-tool preference

`<install_root>/prefer/<tool>` is a small shim:

```sh
#!/bin/sh
# loadout prefer shim
exec "<install_root>/bin/<tool>" "$@"
```

- Absolute exec target, so the shim works even when `<prefix>/bin` is not on PATH,
  and wrapper scripts that derive their prefix from `$0` still see a `<root>/bin/...`
  path.
- Active set = registry-declared defaults **+** `prefer` from `config.toml` **−**
  `prefer_off`. `env-tmux` declares `"prefer": ["tmux"]`, so EL tmux is preferred
  whenever the env-tmux config is installed (opt out with `prefer_off = ["tmux"]`).
  tmux is coupled to its config and to server/client protocol version; firefox
  (ESR, cannot self-update, corp expects the system build) is system-by-default and
  opt-in only, as an example of the general mechanism.
- Reconcile happens in an install phase (shared tree present and either a shared
  selection was made or a selected env package declares defaults). Shims for
  inactive tools are pruned **only** when their content matches the EL template;
  foreign files are left alone with a warning. Missing `<root>/bin/<tool>` targets
  warn and do not create a dangling shim. The dir is removed when empty.
- `config.toml` keys: `prefer = ["firefox"]`, `prefer_off = ["tmux"]`. Wrong types
  degrade to "no preference" exactly like `dest_dir`; a hand-edited config must never
  abort an install.
- Registry `prefer` declarations are validated (names exist; targets are non-env,
  non-group).

### D6 — Retire `@engineering-loadout`

- Delete the registry entry (a leaf: nothing lists it) and fix the `optional` field's
  doc string.
- Add a retired-name resolver error naming the replacements:
  `@shared-all` (tools) then `@envs-all` (shell configs). The resolver replaces the
  old one-liner; `@shared-all + @envs-all` is a **strict superset** of the old group
  (177 vs 167 resolved names, verified), so nothing is lost.
- Repoint the 7 help/error strings in `loadout_main.py`, the CLI docstring, completions
  (regenerated), and active docs. Historical specs, `docs/HANDOFF.md` history, and the
  proposal keep their historical names (records, not guidance).

### D7 — Starship staleness is documentation, not self-healing

`starship init bash` bakes an absolute binary path into `starship_precmd`; shells
started before a relocation keep invoking a missing path until re-initialized. There
is no code fix that reaches an already-running shell: a new shell re-runs
`starship init` anyway, so any "self-heal" in the rc would only ever run when nothing
is stale. The migration doc records the recovery one-liner and the fact that `hash -r`
alone does not help (the path is in the function body):

```bash
eval "$(starship init bash)"; hash -r
```

### D8 — `doctor` audits layout, shadowing and preference

Read-only, never fails the check:

- reports the install root, the layout mode (XDG default / legacy HOME / configured /
  explicit), and the prefer dir when present;
- lists EL-managed bin names found in `~/.local/bin` while the install root is not
  HOME-mode (legacy copies) with a migration pointer;
- counts EL-managed names that also exist in system dirs and would win from any EL
  dir that precedes the system dirs on PATH;
- lists prefer shims and flags missing/non-executable targets.

Implementation is set intersections over one listing per directory, not per-name
stats, so `doctor` stays fast.

### D9 — Migration is docs + doctor detection (no migration script)

Documented in `docs/INSTALLATION.md` (new "Migrating an existing install" section),
following the proposal §7 order, corrected to this spec's model: install the shared
tree at the new root, re-point envs, prune legacy copies from `~/.local/bin` **by
name** (EL rebuilds differ from previous builds by hash, with an absolute `/usr/bin/rm`
because a loop deleting `rm` itself fails), remove the legacy `~/.local` payload
subdirectories, open new terminals, run the starship recovery line. Also documents the
GUI-session PATH gap (login-chain PATH does not include the install root; session-wide
changes need `/etc/environment` via `pam_env`, and systemd `DefaultEnvironment` cannot
override an already-populated environment block).

### D10 — Release

Class C: Tier 3 container gate required, assurance re-pin required, full currency
sweep required. Payload chain: `packages.json` changed → regenerate
`.content-manifest`; `gen-installed-sizes --check`; regenerate completions. Follow
`docs/RELEASE.md` end to end (auth at kickoff, gates, tag/publish, post-publish
verification) and the AGENTS.md commit doc-sync rule.

## Installer pipeline routing

| phase | root |
|---|---|
| backup, config files (env handlers), tealdeer/cargo config, fonts | `env_home` |
| pre-built binaries, tldr cache, crate store, portable Python, typelibs, Python tools, runtime archives, vim runtime, mate-terminal, nvim-qt, treesitter vendor, plugin stash, tree-sitter parsers | `install_root` |
| nvim plugin bundle, Lazy sync, nvim state/cache | `env_home` |
| post-install hooks / layer scripts | `env_home` context; `LOADOUT_DEST_DIR` = `install_root` |

`env_home` follows D3: `user_home`, except env-only + explicit flag where it is the
staged root. Fonts are per-user XDG data (`$XDG_DATA_HOME/fonts` equivalent) so
fontconfig keeps discovering them; the proposal's schematic tree listed fonts under
the root, and this deviates deliberately.

Snapshot is a per-user config operation: `snapshot create|list|restore` target
`user_home` unless `--dest-dir` is explicit on the command line (staging). Config
`dest_dir` does **not** move snapshots — a shared-tree setting must not relocate the
backup of `$HOME` config. `loadout_backups/` therefore stays under the snapshot
target as today.

`LOADOUT_CFG_SHARED_PREFIX` baking becomes unconditional: env installs stamp the
shared prefix — `_local_root(install_root)`, so legacy HOME mode bakes `$HOME/.local`
and prefix modes bake the root — unless the environment variable is set explicitly
(then it wins). The empty value keeps its legacy meaning ("fall back to the XDG default") but
new installs do not rely on it.

## Shell environment changes

- bash (`envs/bash/global/bashrc`): shared bin leaves the prepend list and is appended;
  prefer dir prepended last; fallback prefix `$HOME/.local/share/loadout`; terminfo/Qt/
  GI/nvim-qt/gnuplot fallbacks updated.
- zsh (`envs/zsh/global/zshrc`): mirrors the same list and order (its own loop).
- tcsh (`envs/tcsh/global/tcshrc`): mirrors the same list and order; prefer dir
  prepended last; shared bin appended.
- All three keep the existing "prepend only if the dir exists" behavior. The bash block
  stays before the non-interactive guard so scripts see the same PATH; tcsh sources for
  non-interactive shells too and stays silent.

## Registry changes

- Remove `@engineering-loadout`; fix the `optional` doc string.
- `env-tmux` gains `"prefer": ["tmux"]`.
- Registry validation (and `tests/registry-integrity`) covers `prefer` entries:
  known names, non-env/non-group targets.

## Tests

Updated:

- `tests/config-toml-dest-dir` — XDG default, `XDG_DATA_HOME` honored, config override,
  explicit flag, `dest_dir = "~"` legacy mode.
- `tests/check-installer` — step 4 dry-runs `@shared-all` (same `REQUIRED_FULL` set,
  count ≥ 80).
- `tests/install-linux-tmp-home` — `@shared-all @envs-all`, `HOME` set for isolation,
  layout assertions at the new paths.
- `tests/unit-resolver` — bare-`all` message points at surviving replacements; retired
  `@engineering-loadout` rejected with the pointer.
- `tests/registry-integrity` — `prefer` validation.
- `tests/env-shell-parity` — append/prepend ordering and fallback prefix in all three
  shells.
- `tests/install-split-shared-envs` — layout paths without `local/`, baking rules.
- `tests/install-nvim-deployments` — shared stash vs per-user lazy/state with the new
  routing.

New:

- `tests/dest-layout-and-env-routing` (unit-level, T1) — `_resolve_home`,
  `_local_root`, `_resolve_install_to`, and the D3 selection rules across all modes.
- `tests/prefer-shims` (T1) — active set from registry defaults + config +
  `prefer_off`, pruning, foreign-file protection, missing-target warning, shim exec
  behavior, doctor audit output.
- Doctor shadow/layout audit assertions (extend `check-installer` or the new test).

Gates: Tier 1 + Tier 2 via `tests/run-all`; Tier 3
`tests/prebuilt-binaries-almalinux8 --full --network=none` (install behavior change);
release gates via `./build/release`.

## Docs sync

`README.md`, `docs/INSTALLATION.md` (default root, config keys, migration),
`docs/ARCHITECTURE.md`, `AGENTS.md`, `.github/copilot-instructions.md`,
`docs/HANDOFF.md` (new current entry), `envs/bash/global/README.md`, `docs/BASH.md` if
PATH rationale changes, `envs/nvim/lua/global/paths.lua` comment, completions
(regenerated). The proposal gets a "superseded for implementation" banner and is
committed as the evidence record.

## Out of scope

- **Uninstall** — next spec; this change lands the preconditions (dedicated root,
  config separation, doctor footprint reporting).
- Per-package preference management CLI (`loadout prefer`) — `config.toml` is the
  interface for now.
- Shared-tree fontconfig registration and shared-prefix font discovery.
- Module-based toolchain switching (`module load`) — unchanged, opt-in.

## Review flags (intentional deviations from the proposal)

1. **D2** drops `local/` for all non-HOME roots instead of keeping it for explicit
   flags, resolving the proposal's §5.2 vs §7 contradiction.
2. **D3** applies the no-config-in-dest invariant to mixed explicit-flag installs
   (proposal §3's measured bug); env-only + explicit flag remains the staging escape
   hatch (proposal §5.4).
3. Fonts and nvim state route to per-user XDG dirs rather than the install root,
   despite the proposal's schematic tree listing them under the root.
4. **D7** is docs-only; self-healing cannot reach already-running shells.
5. `LOADOUT_CFG_SHARED_PREFIX` is baked unconditionally rather than relying on the
   empty-value fallback.

## Success criteria

- Fresh default install lands in `~/.local/share/loadout` with no `local/` level; no
  config or cache file appears under it.
- No EL-managed name is ahead of `/usr/bin` unless the user opted into a prefer shim;
  `env-tmux` prefers EL tmux automatically.
- `@engineering-loadout` resolves nowhere, and every remaining mention in the CLI
  points at real replacements.
- Existing machines can migrate using the documented steps; `doctor` reports what it
  finds without failing.
- All gates green; class C release published and verified per `docs/RELEASE.md`.
