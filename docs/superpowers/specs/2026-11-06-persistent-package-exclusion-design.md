# Persistent per-consumer package exclusion (`exclude`)

Date: 2026-11-06
Status: design (not implemented). Issue: `smprather/engineering-loadout#13`.
Scope: a consumer records packages it never wants; every future sweep honors
it. Installer only (`loadout_main.py`) plus docs and one Tier 1 test.
Release class: **C** (`docs/RELEASE.md` puts any `loadout_main.py` change in
class C), so the Tier 3 container gate is required before release. No payload,
registry or schema change.

## Problem

A downstream distribution (PSG) ships its own build of two tools EL also
packages (`time-plot`, `watchglass`) as modulefile-managed, vendored copies.
Installing `@shared-all` therefore ships EL's copy too: duplicate payload,
two upstream versions on one machine, and PATH order alone decides which
binary wins.

EL has the mechanism -- `loadout install --skip NAME,...` -- but it is
per-invocation. Nothing records "this consumer never wants package X", so
every consumer that wants to own a package has to fork the installer wrapper
and remember a flag. The only persistent exclusion today is the registry's
`disabled: true`, which is global and removes the package for everyone.

## Goals

- A persistent list in `~/.config/engineering-loadout/config.toml` that every
  `install` / `reinstall` / `upgrade` / `resolve` / `--dry-run` honors without
  the caller repeating a flag.
- The same expansion rules as `--skip` (package names, `@groups`, glob
  patterns) and the same hard-dependency safety.
- `loadout doctor` names an excluded package so its absence is not read as a
  failed install.
- The key is documented next to `dest_dir` / `prefer` / `prefer_off`.

## Non-goals

- No global registry change (`disabled` stays "out of service for everyone").
- No marker file written into the destination tree (issue alternative 2): it
  makes the policy invisible from `$HOME`, and a read-only shared tree cannot
  take it.
- No override flag. Policy is policy; changing it means editing the config.
- No new column in `list` / `search` / `info`; `doctor` is the reporting
  surface.
- No pruning of files a previous install left in the tree. Excluding a
  package stops future installs; it does not uninstall.

## Anti-goals

- A silent partial install when an excluded package is a hard dependency of a
  selected one. Today's `--skip` raises and names the dependency; the
  persistent list must do the same.
- Any change to `--skip`'s own semantics.

## Decisions

**D1 -- key shape.** `exclude = ["watchglass", "time-plot"]` in
`~/.config/engineering-loadout/config.toml`. A list of strings; each string is
one token, and a token may be a package name, an `@group`, or a glob pattern
(`*?[`) matched against registry names. A key of the wrong type (or a non-string
entry) is ignored, exactly like `prefer` / `prefer_off` / `dest_dir`.

**D2 -- environment variable.** `LOADOUT_CFG_EXCLUDE` holds the same list as a
comma-separated string, so a distribution can set the policy without writing
into `$HOME`. The file list and the variable **union**; neither overrides the
other. Additive is the safe direction: a policy that silently replaced the
user's file list could install a package the user excluded.

**D3 -- where it is applied.** Inside `resolve_tool_selection()` the policy
tokens are expanded exactly like `--skip` tokens and unioned into the existing
`skip_set` *before* the subtraction. That reuses every existing property for
free: subtraction from the initial set, `forbidden=skip_set` on the
`walk_depends` walk (error naming the dependency, overridable with
`--force`/`--no-deps`), and silent drop of recommendations that hit the set.

Expansion errors are **not** swallowed: a policy token that makes
`expand_groups()` raise (bare `all`, a retired group, a cycle) fails the run
loudly. Ignoring it would install a package the consumer excluded, which is the
unsafe direction. `doctor` is the one surface that tolerates it (D6).

**D4 -- read at the edge, not in the resolver.** `resolve_tool_selection(args,
registry, exclude=None)` takes the policy as an argument. `exclude=None` means
"no policy" and keeps the resolver pure, so `tests/unit-resolver` stays
hermetic and a developer's real `config.toml` can never change a unit test.
The two CLI entry points (`cmd_install_v2`, and `cmd_resolve` -- which
`--dry-run` also calls) pass `_exclusion_policy()`, a new helper returning
`[(source_label, tokens), ...]` for the file list and the env var separately,
so warnings can name the source.

**D5 -- explicit naming.** A sweep and a demand are different things, so the
rule keys on how the name was requested, not on whether the result is empty:

- A package named **directly** on the command line (`loadout install
  time-plot`) that the policy excludes -> `ResolverError` naming the package,
  the source and the remedy ("remove it from `exclude`"). This holds even when
  other packages are named in the same command: a name the user typed is a
  demand, and a demand the policy forbids fails. Exit 1, not a silent empty
  install. "Directly" means a literal registry name in `--only`/`--add`: not a
  `@group`, not a glob, and not a package pulled in as a dependency.
- A sweep (`@shared-all`, `@group`, a glob) -> plain subtraction, exactly like
  `--skip`. If the policy removes the whole sweep the selection is empty and
  the run is a no-op, not an error: the consumer asked for "everything except
  what I exclude".
- A partial drop from any selection -> one stderr note naming the dropped
  packages and the source; the rest installs.

`--skip` alone keeps today's behaviour (subtract, and an empty set is an empty
set). Only policy-excluded names produce the error or the note.

**D6 -- doctor.** A new informational section, printed only when a policy
exists:

```
Exclusions (config.toml exclude, LOADOUT_CFG_EXCLUDE):
  time-plot: excluded by policy
  watchglass: excluded by policy; still installed: <prefix>/bin/watchglass
```

Each token is expanded (globs, groups) against the registry; a token that does
not resolve, or a group name that raises, is reported as invalid instead of
crashing doctor (doctor must never fail on a bad config). "Still installed"
means any `bins` entry the package declares exists in `<prefix>/bin`; a
package with no `bins` (libs, fonts, env bundles) gets the policy line only,
never a presence claim. Informational: doctor's exit status is unchanged.

The probe root is the config-resolved install root (`_resolve_home(None)` ->
`_local_root`), the same root the layout audit reports. A tree installed with a
one-off `--dest-dir` that is not in `config.toml` is not probed -- the same
limitation the layout audit already has, and the reason a pinned root belongs in
`config.toml`.

**D7 -- no un-exclude switch.** Removing the entry is the way out. An override
flag would recreate the per-invocation forgetting the issue exists to remove,
and would let a wrapper silently reinstall the duplicate.

**D8 -- dependency error wording.** `walk_depends()`'s message currently says
the dependency "was passed to --skip", which is false for a consumer who never
typed the flag. The message becomes source-neutral ("excluded (--skip or the
persistent `exclude` policy)") rather than carrying a per-name source map into
the walk. Same error, same `--force`/`--no-deps` escape.

**D9 -- one note per run.** `loadout install --dry-run` resolves twice today:
`cmd_install_v2` resolves, then the `--dry-run` branch re-enters `cmd_resolve`,
which resolves again. The listing printer is extracted so the dry-run branch
prints the already-resolved set instead. That removes the duplicate note (and a
duplicate `expand_groups` warning) and drops a redundant resolution; the
`resolve` verb's output is unchanged.

## Acceptance criteria (issue #13) -> design

| Criterion | Where it lands |
|---|---|
| `@shared-all` with `exclude = ["time-plot"]` omits it | D1, D3 (resolver subtraction) |
| Exclusion persists across runs | D1 (config file read on every run) |
| `--skip` still works and unions | D3 (same set) |
| Hard-dependency safety unchanged | D3 (`forbidden=skip_set`) |
| doctor distinguishes policy from failure | D6 |
| Documented with `dest_dir` | docs task (`docs/INSTALLATION.md` keys block) |

## Constraints

- Standard library only (`tomllib` is already imported); no new dependency.
- `loadout_main.py` uses PEP 758 multi-except syntax: Python 3.15 only, and
  `ruff format` must pass.
- New tests use a throwaway `HOME`; they must not read the developer's config.
- The new Tier 1 test is registered in `tests/run-all`; an unregistered test
  does not exist as a gate.
- Docs sync before commit: `docs/INSTALLATION.md` (config keys + a semantics
  paragraph), `README.md`, `AGENTS.md` (config keys line, resolver order),
  `docs/HANDOFF.md`.

## What is left to the builder

Exact wording of the messages and the doctor header; test file name and case
list; whether `_exclusion_policy()` belongs beside `_prefer_config()`.

## Revision notes

- rev 2 (2026-11-06): a builder check asked five questions; all five are ruled
  on above. D5 now keys the error on a *directly named* package rather than on
  an empty result (a sweep emptied by policy stays a no-op); D3 says expansion
  errors propagate; D6 names the single probe root; D8 fixes the dependency
  error's `--skip`-only wording; D9 removes the double resolution behind
  `--dry-run` so the note prints once.
