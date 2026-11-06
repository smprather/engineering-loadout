# Persistent Package Exclusion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Honor a persistent `exclude` list from `~/.config/engineering-loadout/config.toml` (and `LOADOUT_CFG_EXCLUDE`) on every install and resolve, with the same semantics as `--skip`, and report it in `loadout doctor`.

**Architecture:** The policy is read at the CLI edge by a new `_exclusion_policy()` and passed into `resolve_tool_selection(args, registry, exclude=None)`, which expands each source's tokens (names, `@groups`, globs) and unions them into the existing `skip_set`. Everything downstream -- subtraction, `forbidden=` on the dependency walk, recommendation drop -- is unchanged. `loadout doctor` gains one informational section.

**Tech Stack:** Python 3.15 (bundled interpreter; PEP 758 multi-except syntax), stdlib `tomllib`, click. Tests are standalone Python scripts under `tests/`.

**Spec:** `docs/superpowers/specs/2026-11-06-persistent-package-exclusion-design.md`

## Global Constraints

- Interpreter: bundled Python 3.15 only. `loadout_main.py` uses PEP 758 (`except A, B:`); never add parentheses back, never run a pre-3.14 interpreter or analyzer over it.
- `ruff format --check --force-exclude` and `ruff check --force-exclude` must pass; line length 120, target py314.
- Standard library only; no new dependency.
- Tests are hermetic: every case sets its own `HOME` (and `XDG_DATA_HOME` where relevant) to a `tempfile.TemporaryDirectory()`. No test may read the developer's real `config.toml`.
- The new test file MUST be registered in `tests/run-all` Tier 1; an unregistered test is not a gate.
- Docs sync before commit: `docs/INSTALLATION.md`, `README.md`, `AGENTS.md`, `docs/HANDOFF.md`.
- Release class C (any `loadout_main.py` change): Tier 3 container gate before release, not before commit.
- Every non-trivial run is timed; `tests/run-all` appends its own rows to `assurance/release-timings.tsv`.

## Review Focus

1. A typo or stale name in `exclude` -- must warn naming the source and install the rest, never abort a sweep.
2. `exclude` naming a retired group (`@engineering-loadout`) -- `loadout install` must raise that group's loud ResolverError; `loadout doctor` must not crash and must still exit 0.
3. `loadout install <pkg>` where `<pkg>` is policy-excluded -- exit 1 naming the source and the remedy, never a silent 0-package success.
4. Env-var-only policy (`LOADOUT_CFG_EXCLUDE` set, no config file) -- applies identically to the file list.
5. A copy left by a previous install -- doctor says "still installed"; a package with no `bins` gets no presence claim at all.

## File Structure

- Modify `loadout_main.py`: `_exclusion_policy()` + `resolve_tool_selection()` (policy union and messages), `cmd_install_v2()` + `cmd_resolve()` (wiring), `cmd_doctor()` + new `_doctor_exclusions()` (report).
- Create `tests/config-toml-exclude`: all cases, in-process resolver cases plus `./loadout` subprocess cases for wiring and doctor.
- Modify `tests/run-all`: one `run_test` line in the Tier 1 block.
- Modify `docs/INSTALLATION.md`, `README.md`, `AGENTS.md`, `docs/HANDOFF.md`.

---

### Task 1: Policy reader, resolver union, and the gate

**Files:**
- Modify: `loadout_main.py` (new `_exclusion_policy()` immediately above `resolve_tool_selection()` at `loadout_main.py:680`; `resolve_tool_selection()` signature and body)
- Create: `tests/config-toml-exclude`
- Modify: `tests/run-all` (Tier 1 block, after the `unit-resolver` line)

**Interfaces:**
- Produces: `_exclusion_policy() -> list[tuple[str, list[str]]]` -- one `(source_label, tokens)` pair per non-empty source, labels exactly `"config.toml exclude"` and `"LOADOUT_CFG_EXCLUDE"`.
- Produces: `resolve_tool_selection(args, registry, exclude=None)` -- `exclude=None` means no policy (resolver stays pure); `exclude=[(source, tokens), ...]` unions the expanded tokens into `skip_set`.

- [ ] **Step 1: Register the test (so it gates from the first commit)**

In `tests/run-all`, directly after `run_test "unit-resolver" "$PY" tests/unit-resolver`, add:

```bash
run_test "config-toml-exclude" --deps payload+loader "$PY" tests/config-toml-exclude
```

- [ ] **Step 2: Write the failing test**

Create `tests/config-toml-exclude`, executable, starting `#!/usr/bin/env python3`. Shape (copy the `load_module`/`check` conventions from `tests/config-toml-dest-dir`):

```python
import contextlib, importlib.util, io, os, sys, tempfile, types

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VENDOR = os.path.join(REPO, "installer_vendor")

def load_module():
    for path in (REPO, VENDOR):
        if path not in sys.path:
            sys.path.insert(0, path)
    spec = importlib.util.spec_from_file_location("loadout_exclude_under_test", os.path.join(REPO, "loadout_main.py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

def write_config(home, body):
    cfg = os.path.join(home, ".config", "engineering-loadout")
    os.makedirs(cfg, exist_ok=True)
    with open(os.path.join(cfg, "config.toml"), "w", encoding="utf-8") as fh:
        fh.write(body)

def args(only=None, skip=None, no_deps=False, force=False):
    return types.SimpleNamespace(skip=skip, only=only, add=None, no_deps=no_deps, force=force)

REG = {
    "@fonts": {"kind": "group", "members": ["font-a", "font-b"]},
    "app": {"kind": "bin", "bins": ["app"], "depends": ["lib"]},
    "lib": {"kind": "bin", "bins": ["lib"]},
    "tool": {"kind": "bin", "bins": ["tool"]},
    "font-a": {"kind": "font"},
    "font-b": {"kind": "font"},
}
```

Cases in `main()` (each `check(label, got, want)` like the dest-dir test; `failures += ...`):

1. Reader: config `exclude = ["a", 42, " b "]` -> `[("config.toml exclude", ["a", "b"])]`; add `LOADOUT_CFG_EXCLUDE="c, d"` -> both pairs, env tokens `["c", "d"]`; `exclude = "a"` (wrong type) -> `[]`; absent file -> `[]`. Set `os.environ["HOME"]` per case and always `os.environ.pop("LOADOUT_CFG_EXCLUDE", None)` between cases.
2. `rts(args(only="@shared"), REG, exclude=[("config.toml exclude", ["tool"])])` -> `{"app", "lib", "font-a", "font-b"}`.
3. Union with `--skip`: same call plus `skip="font-a"` -> no `font-a` either.
4. Glob: `exclude=[(..., ["font-*"])]` -> no font.
5. Group token: `exclude=[(..., ["@fonts"])]` -> no font.
6. Hard dependency: `args(only="app")` with `exclude=[(..., ["lib"])]` raises `ResolverError`; with `force=True` -> `{"app"}`.
7. Direct demand excluded: `args(only="tool")` + `exclude=[(..., ["tool"])]` raises `ResolverError` whose text contains `excluded by the persistent policy` and `config.toml exclude`. Its sweep counterpart -- `args(only="@shared")` + `exclude=[(..., ["app", "lib", "tool", "font-a", "font-b"])]` -- returns `set()` and raises nothing.
8. Partial: `args(only="tool,app")` + exclude `tool` -> `{"app", "lib"}`, and stderr (captured with `contextlib.redirect_stderr(io.StringIO())`) contains `note: excluded by policy` and `tool`.
9. Unknown name: `exclude=[("config.toml exclude", ["nope"])]` with `only="@shared"` -> full set unchanged and stderr contains `config.toml exclude: unknown package 'nope'`.
10. Retired group: `exclude=[("config.toml exclude", ["@engineering-loadout"])]` with `only="@shared"` raises `ResolverError` containing `@engineering-loadout was retired`.

- [ ] **Step 3: Run it to verify it fails**

Run: `"$(command -v python3.15 || echo .loadout-bootstrap/bin/python3.15)" tests/config-toml-exclude`
Expected: FAIL -- `resolve_tool_selection() got an unexpected keyword argument 'exclude'` (or `_exclusion_policy` missing).

- [ ] **Step 4: Implement `_exclusion_policy()`**

Immediately above `resolve_tool_selection()`:

```python
def _exclusion_policy():
    """The persistent package exclusions: [(source, tokens), ...].

    Two sources, unioned (never overriding each other): config.toml `exclude`
    (a list of strings) and LOADOUT_CFG_EXCLUDE (comma-separated), so a
    distribution can set the policy without writing into $HOME. Wrong types are
    ignored like dest_dir/prefer; tokens may be names, @groups or globs.
    """
```

Body: read `_loadout_config().get("exclude")`; keep it only when `isinstance(value, list)`, tokens `v.strip()` for `isinstance(v, str)` non-empty; append `("config.toml exclude", tokens)` when non-empty. Then `_parse_namelist(os.environ.get("LOADOUT_CFG_EXCLUDE", ""))`; append `("LOADOUT_CFG_EXCLUDE", tokens)` when non-empty. Return the list.

- [ ] **Step 5: Implement the resolver union**

In `resolve_tool_selection()`, after the existing `skip_set = ...` block:

```python
policy_set = set()
policy_sources = []
for source, tokens in exclude or ():
    policy_sources.append(source)
    known = []
    for name in _expand_glob_names(tokens, registry):
        if name in registry or name.startswith("@"):
            known.append(name)
        else:
            warn(f"{source}: unknown package '{name}' (ignored)")
    policy_set |= expand_groups(known, registry, _stack=(source,))
skip_set |= policy_set
```

Capture `selected_before = set(selected)` immediately after `selected` is built and before `selected -= skip_set`, then after the subtraction:

```python
requested = _parse_namelist(getattr(args, "only", None) or getattr(args, "add", None) or "")
demanded = [n for n in requested if not n.startswith("@") and not any(ch in n for ch in "*?[")]
blocked = [n for n in demanded if n in policy_set]
if blocked:
    raise ResolverError(
        "package(s) excluded by the persistent policy:\n"
        f"  {', '.join(sorted(blocked))}\n"
        f"  source: {' + '.join(policy_sources)}\n"
        "  Remove the entry from ~/.config/engineering-loadout/config.toml\n"
        "  `exclude` (or LOADOUT_CFG_EXCLUDE) to install it."
    )
dropped = selected_before & policy_set
if dropped:
    eprint(f"  note: excluded by policy ({' + '.join(policy_sources)}): {', '.join(sorted(dropped))}")
```

A sweep (`@group`, a glob) that the policy empties is a no-op with the note, never this error.

- [ ] **Step 5b: Make the dependency error source-neutral (D8)**

In `walk_depends()`, change the raise to:

```python
f"package '{name}' hard-depends on '{d}', but '{d}' is excluded "
f"(--skip or the persistent `exclude` policy). Either stop excluding it, "
f"drop '{name}' from the selection, or pass --no-deps / --force."
```

and the `--force` warning to `... which is excluded (--force: continuing)`. No test pins this text; `tests/unit-resolver` only checks that it raises.

Update the `resolve_tool_selection()` docstring's numbered steps to say `--skip` plus the policy list.

- [ ] **Step 6: Run the test to verify it passes**

Run: `"$(command -v python3.15 || echo .loadout-bootstrap/bin/python3.15)" tests/config-toml-exclude`
Expected: `OK: config-toml-exclude`.

- [ ] **Step 7: Verify the existing resolver tests still pass**

Run: `"$(command -v python3.15 || echo .loadout-bootstrap/bin/python3.15)" tests/unit-resolver`
Expected: exit 0 (the default `exclude=None` keeps every existing case unchanged).

- [ ] **Step 8: Commit**

```bash
git add loadout_main.py tests/config-toml-exclude tests/run-all
git commit -m "feat(resolver): persistent package exclusions from config.toml"
```

---

### Task 2: CLI wiring (install, reinstall, upgrade, resolve, --dry-run)

**Files:**
- Modify: `loadout_main.py:7457` (`cmd_resolve`) and `loadout_main.py:8627` (`cmd_install_v2`)
- Test: `tests/config-toml-exclude` (add subprocess cases)

**Interfaces:**
- Consumes: `_exclusion_policy()` and `resolve_tool_selection(..., exclude=...)` from Task 1.
- Produces: nothing new; both entry points pass the policy.

- [ ] **Step 1: Write the failing CLI cases**

Add to `tests/config-toml-exclude` a helper and cases:

```python
def run_loadout(home, *argv, extra_env=None):
    env = {"HOME": home, "PATH": "/usr/bin:/bin", "TERM": "xterm"}
    env.update(extra_env or {})
    return subprocess.run([os.path.join(REPO, "loadout"), *argv], env=env, capture_output=True, text=True, timeout=180)
```

Cases:

1. Config `exclude = ["gnuplot"]`; `run_loadout(home, "resolve", "@shared-all")` -> exit 0 and `"gnuplot"` not in stdout.
2. Same HOME; `run_loadout(home, "resolve", "gnuplot")` -> exit 1, and stdout+stderr contains `excluded by policy` and `config.toml exclude`.
3. Config `exclude = ["gnuplot"]`; `run_loadout(home, "resolve", "@shared-all", "--skip", "micro")` -> neither `gnuplot` nor `micro` in stdout.
4. No config file; `run_loadout(home, "resolve", "@shared-all", extra_env={"LOADOUT_CFG_EXCLUDE": "gnuplot"})` -> `gnuplot` absent.
5. `run_loadout(home, "resolve", "@shared-all")` with no policy -> `gnuplot` present (proves the absence above is the policy, not the registry).
6. Config `exclude = ["gnuplot"]`; `run_loadout(home, "install", "--dry-run", "micro", "gnuplot")` -> exit 0, `gnuplot` absent from the listing, and `note: excluded by policy` appears exactly once in stdout+stderr.

- [ ] **Step 2: Run to verify they fail**

Run: `"$(command -v python3.15 || echo .loadout-bootstrap/bin/python3.15)" tests/config-toml-exclude`
Expected: FAIL on case 1 (`gnuplot` still listed) -- the resolver supports `exclude=` but nothing passes it.

- [ ] **Step 3: Wire both entry points**

`cmd_resolve`: `selected = resolve_tool_selection(args, registry, exclude=_exclusion_policy())`.
`cmd_install_v2`: `selected_tools = resolve_tool_selection(args, registry, exclude=_exclusion_policy())`.

- [ ] **Step 3b: Print the dry-run listing from the resolved set (D9)**

Extract the listing body of `cmd_resolve` into `_print_resolved(selected, registry)` (the `None` sentinel line, the `Resolved N packages:` header, the by-kind grouping; `cmd_resolve` keeps its `ResolverError` handling and returns 0). In `cmd_install`, replace the `--dry-run` branch's `return cmd_resolve(args, registry)` with:

```python
        _print_resolved(selected_tools, registry)
        return 0
```

so the policy note and any expansion warning print once per run.

- [ ] **Step 4: Run to verify they pass**

Run: `"$(command -v python3.15 || echo .loadout-bootstrap/bin/python3.15)" tests/config-toml-exclude`
Expected: `OK: config-toml-exclude`.

- [ ] **Step 5: Commit**

```bash
git add loadout_main.py tests/config-toml-exclude
git commit -m "feat(cli): apply config exclusions on install and resolve"
```

---

### Task 3: Real install honors the policy (Tier 2)

**Files:**
- Create: `tests/install-exclude-policy`
- Modify: `tests/run-all` (Tier 2 block, next to the other `install-*` tests)

**Interfaces:**
- Consumes: the CLI behaviour from Task 2 (`install` resolves with the policy).

- [ ] **Step 1: Write the failing test**

`tests/install-exclude-policy`, executable bash, following `tests/optional-packages` conventions (`set -euo pipefail`, `mktemp` home + dest under `${TMPDIR:-/tmp}`, `trap cleanup EXIT`, `fail()`):

```bash
repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
test_home=$(mktemp -d "${TMPDIR:-/tmp}/loadout-exclude-home.XXXXXX")
dest_dir=$(mktemp -d "${TMPDIR:-/tmp}/loadout-exclude-dest.XXXXXX")
mkdir -p "$test_home/.config/engineering-loadout"
printf 'exclude = ["gnuplot"]\n' > "$test_home/.config/engineering-loadout/config.toml"

env -i HOME="$test_home" PATH="/usr/bin:/bin:/usr/sbin:/sbin" LANG="${LANG:-C.UTF-8}" \
    "$repo_dir/loadout" install -y micro gnuplot --dest-dir "$dest_dir" --no-backup \
    > "$test_home/install.log" 2>&1 || fail "install failed (see log)"

[ -x "$dest_dir/bin/micro" ] || fail "selected package micro was not installed"
[ ! -e "$dest_dir/bin/gnuplot" ] || fail "excluded gnuplot was installed"
grep -q "excluded by policy" "$test_home/install.log" || fail "no policy note in the install output"
```

- [ ] **Step 2: Register it**

In the Tier 2 block of `tests/run-all` (beside `run_test "optional-packages" ...`):

```bash
run_test "install-exclude-policy" --deps auto tests/install-exclude-policy
```

- [ ] **Step 3: Run it to verify it fails**

Run: `tests/install-exclude-policy`
Expected: FAIL on `excluded gnuplot was installed` (before Task 2's wiring the excluded package installs).

- [ ] **Step 4: Run it to verify it passes**

Run: `tests/install-exclude-policy`
Expected: exit 0, no output beyond the install log being clean.

- [ ] **Step 5: Commit**

```bash
git add tests/install-exclude-policy tests/run-all
git commit -m "test(t2): an excluded package never reaches the installed tree"
```

---

### Task 4: `loadout doctor` reports policy exclusions

**Files:**
- Modify: `loadout_main.py` (new `_doctor_exclusions()` above `_doctor_layout_audit()`; call it from `cmd_doctor()` just before `_doctor_layout_audit(...)`)
- Test: `tests/config-toml-exclude` (add doctor cases)

**Interfaces:**
- Consumes: `_exclusion_policy()` (Task 1), `_local_root()`, `_load_tool_registry()` shape (`entry["bins"]`).
- Produces: `_doctor_exclusions(registry, install_root) -> None`; prints the section only when a policy exists, never raises.

- [ ] **Step 1: Write the failing doctor cases**

Add to `tests/config-toml-exclude`:

1. HOME with `exclude = ["watchglass", "time-plot"]`; create `<home>/.local/share/loadout/bin/watchglass` (empty file); `run_loadout(home, "doctor")` -> exit 0; output contains `Exclusions (config.toml exclude):`, `watchglass: excluded by policy; still installed:`, and a `time-plot: excluded by policy` line with no `still installed` on it.
2. Same HOME but `exclude = ["@engineering-loadout"]` -> exit 0, output contains the retired-group text (`@engineering-loadout was retired`) and the rest of doctor still printed (`Install layout:`).
3. No policy -> output contains no `Exclusions (` line.

- [ ] **Step 2: Run to verify they fail**

Run: `"$(command -v python3.15 || echo .loadout-bootstrap/bin/python3.15)" tests/config-toml-exclude`
Expected: FAIL -- no `Exclusions (` line.

- [ ] **Step 3: Implement `_doctor_exclusions()`**

Signature `def _doctor_exclusions(registry, install_root):`. Behaviour:

- `policy = _exclusion_policy()`; return immediately when empty.
- Print `Exclusions ({', '.join(source for source, _ in policy)}):`.
- For each `(source, tokens)`: expand `_expand_glob_names(tokens, registry)` then `expand_groups(known, registry, _stack=(source,))` inside `try/except ResolverError as exc`, printing `  {token}: invalid ({exc})` for a token that raises, and continuing (doctor never fails on a bad config). Guard expansion per token, not per source, so one bad group does not hide the rest.
- For each expanded name, sorted: `bins = registry.get(name, {}).get("bins") or []`; `leftover = [p for p in (os.path.join(_local_root(install_root), "bin", b) for b in bins) if os.path.isfile(p)]`. Print `  {name}: excluded by policy` plus `; still installed: {', '.join(leftover)}` when `leftover`; packages with no `bins` get the plain line only.
- No return value; never touches doctor's exit status.

Call it from `cmd_doctor()` immediately before `_doctor_layout_audit(repo_dir, registry, _resolve_home(None), os.path.expanduser("~"))`, with `_doctor_exclusions(registry, _resolve_home(None))`.

- [ ] **Step 4: Run to verify they pass**

Run: `"$(command -v python3.15 || echo .loadout-bootstrap/bin/python3.15)" tests/config-toml-exclude`
Expected: `OK: config-toml-exclude`.

- [ ] **Step 5: Commit**

```bash
git add loadout_main.py tests/config-toml-exclude
git commit -m "feat(doctor): report config exclusions and leftovers"
```

---

### Task 5: Docs, gate, and timing rows

**Files:**
- Modify: `docs/INSTALLATION.md` (config keys block at `docs/INSTALLATION.md:166-174` + one paragraph)
- Modify: `README.md` (the `--skip` examples around `README.md:116` and the `config.toml` sentence around `README.md:52-61`)
- Modify: `AGENTS.md` (cold-start `config.toml` key list; "Resolver order" line)
- Modify: `docs/HANDOFF.md` (new entry at the top of the dated entries)

- [ ] **Step 1: Document the key**

`docs/INSTALLATION.md` keys block gains `exclude = ["watchglass", "time-plot"]  # never install these, on every run`, and a paragraph stating: tokens may be package names, `@groups` or globs; the list is subtracted exactly like `--skip` and unions with it; `LOADOUT_CFG_EXCLUDE` (comma-separated) unions with the file list; excluding a hard dependency of a selected package keeps today's error (override with `--force`/`--no-deps`); naming a fully-excluded package on the command line is an error naming this key; `doctor` lists exclusions and any copy a previous install left behind; removing the entry is the only override.

`README.md`: one sentence in the `--skip` examples block ("record a permanent exclusion in `config.toml` instead of repeating the flag") and add `exclude` to the config key sentence.

`AGENTS.md`: add `exclude` to the cold-start `config.toml` key list (`dest_dir`, `prefer`, `prefer_off`), and extend "Resolver order" so step 1 reads: parse `--skip`, union the persistent policy (`config.toml exclude` / `LOADOUT_CFG_EXCLUDE`), expand globs and groups.

- [ ] **Step 2: Run the doc gates**

Run: `"$(command -v python3.15 || echo .loadout-bootstrap/bin/python3.15)" tests/docs-sync` -> exit 0.
Run: `rg -n "exclude" README.md docs/INSTALLATION.md AGENTS.md` -> the three files name the key.

- [ ] **Step 3: Run the Tier 1 gate, timed**

Run: `tests/run-all --fast` (this appends its rows to `assurance/release-timings.tsv`).
Expected: `Tier 1 passed.`

- [ ] **Step 4: Smoke the real surface**

Run, with a throwaway HOME and a config that excludes `gnuplot`:
`./loadout resolve @shared-all` (gnuplot absent), `./loadout resolve gnuplot` (exit 1, message), `./loadout doctor` (Exclusions section).
Expected: as described; no traceback.

- [ ] **Step 5: Handoff entry**

Add a `## 2026-11-06 (5): persistent package exclusions` entry at the top of the dated entries in `docs/HANDOFF.md`: what changed, class C, the gates actually run (with durations), and what was not run.

- [ ] **Step 6: Commit**

```bash
git add docs/INSTALLATION.md README.md AGENTS.md docs/HANDOFF.md assurance/release-timings.tsv
git commit -m "docs: persistent package exclusions"
```
