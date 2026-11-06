# Python-tool interpreter contract Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the CPython minor a python-tool entry is installable under a
declared, validated and asserted part of the registry, instead of a constant
plus a wheel tag.

**Architecture:** One new registry field, `requires_python` (PEP 440 specifier),
is enforced in the resolver against `_BUNDLED_PY` before any mutation; every
`uv tool install` is followed by an import assertion inside the tool's own venv,
so a wheel whose ABI does not match the interpreter fails at install instead of
at first run. Build tooling compares the declared specifier with what the wheels
actually say (ABI tag + `Requires-Python`), and `./build/update` refuses to copy
a rebuilt wheel that contradicts the declaration.

**Tech Stack:** Python 3.15 (stdlib only in the installer; `rich` is vendored),
bash test harness (`tests/run-all`), `uv tool install` for the wheel installs,
Maturin/rustup in the EL8 build container for the wheel rebuild.

**Spec:** `https://github.com/smprather/engineering-loadout/issues/16` (open) —
its body is the requirement, the 2026-11-06 comment records that upstream
`def-tools` v2026.11.4 ships the `def-dump-instances` console script.

## Global Constraints

- Installer stays stdlib-only: no `packaging` import; the specifier evaluator is
  ~40 lines in `loadout_main.py`. Never run a pre-3.14 interpreter over it
  (PEP 758 `except A, B:` is used).
- `_BUNDLED_PY` stays the single place the minor is spelled.
- `requires_python` describes the interpreter the ENTRY is installable under:
  `==3.15.*` when any wheel in its closure is ABI-locked (`cp3XY-cp3XY`), the
  upstream `Requires-Python` floor otherwise. It is not a copy of the upstream
  metadata; it is the install-time constraint.
- A mismatch is a `ResolverError` (named package, declared spec, bundled minor),
  raised during resolution so `--dry-run` fails too.
- Payload work happens in the EL8 build container (`build/build-shell`), and the
  post-payload manifest chain runs before committing.
- Every non-trivial action is timed into `assurance/release-timings.tsv`.

## Review Focus

- A registry edit that drops `requires_python` from a python-tool must fail the
  install with a name, not install under whatever `_BUNDLED_PY` is.
- A wheel built for another minor (or a `Requires-Python` the bundle cannot
  satisfy) must be reported by a gate, naming the wheel, not by a user's import
  error.
- `uv tool install` exiting 0 is not success: the venv interpreter must import
  the dist's console-script modules.
- `bins` may not claim a launcher the vendored wheel does not ship
  (`def-dump-instances` only exists from v2026.11.4).
- A PATH `python3` that is not the bundled minor must not change any of this.

---

### Task 1: Specifier evaluator + resolver enforcement

**Files:**
- Modify: `loadout_main.py` (constants near `_BUNDLED_PY`, helpers beside
  `walk_depends`, `resolve_tool_selection`)
- Test: `tests/unit-resolver`

**Interfaces:**
- Produces: `_python_spec_satisfied(spec: str, version: str) -> bool`,
  `_python_requires_error(name: str, entry: dict) -> str | None`
  (None = satisfied, else the human-readable reason).

- [ ] **Step 1:** Extend `tests/unit-resolver` REGISTRY with two python-tools
  (`py-tool` `requires_python: "==3.15.*"`, `py-tool-old` `">=3.16"`) and a
  `test_python_requires` case table: `">=3.14"`/`"==3.15.*"`/`"~=3.14.0"`/
  `"!=3.15.*"`/`"<3.15"` against `"3.15"`; then `resolve_tool_selection` must
  raise for the `>=3.16` entry and for an entry with no field, and must accept
  the exact-pin entry.
- [ ] **Step 2:** Run `tests/unit-resolver`; expect the new checks to FAIL.
- [ ] **Step 3:** Implement the evaluator and the resolver check (after
  `filter_by_platform`, over selected entries with `uv_tool`/`uv_tools`).
- [ ] **Step 4:** Run `tests/unit-resolver`; expect PASS.

### Task 2: Post-install import assertion

**Files:**
- Modify: `loadout_main.py` (`install_python_tools` and a new
  `_assert_uv_tool_imports`)
- Test: `tests/install-open-eda-file-tools` (T2, Task 5)

**Interfaces:**
- Produces: `_assert_uv_tool_imports(tool_name, tool_root, timeout=60) ->
  tuple[bool, str]`; on False the distribution joins `failed`, so the phase
  records `FAIL` naming the interpreter and the expected minor.

- [ ] **Step 1:** In `install_python_tools`, after a successful `uv tool
  install`, run `<tool_root>/bin/python -c '<program>' <dist>` where the program
  imports every console-script module the dist declares (`importlib.metadata`),
  and treat non-zero/`TimeoutExpired` as a failed distribution.
- [ ] **Step 2:** Verify on a real install:
  `./loadout install -y tmux-path-store --dest-dir /var/tmp/x --no-backup`
  prints the tool as installed; then break one launcher module's import in the
  venv and re-run `upgrade` to see the FAIL row.

### Task 3: Declare the field in the registry

**Files:**
- Modify: `payload/packages.json` (14 python-tool entries + `_schema`)
- Test: `tests/registry-integrity`

- [ ] **Step 1:** Add `tests/registry-integrity` checks: every `python-tool`
  declares a non-empty string `requires_python` that parses and that
  `_BUNDLED_PY` satisfies; `open-eda-file-tools.bins` contains
  `def-dump-instances`.
- [ ] **Step 2:** Run it; expect FAIL on the missing field.
- [ ] **Step 3:** Add `requires_python` per entry — `==3.15.*` where the closure
  holds an ABI-locked `cp315-cp315` wheel (open-eda-file-tools, librelane,
  jupyterlab, time-plot, text-serdes, cicwave, parity-plot, pygwalker), else the
  upstream floor (`>=3.8` … `>=3.12`). Document the field in `_schema`.
- [ ] **Step 4:** Run it; expect PASS.

### Task 4: Vendor the wheel and gate it in the build tooling

**Files:**
- Modify: `payload/el8.x86_64.glibc2p28/wheels/` (new `def_tools`, `lef_tools`,
  `liberty_tools` wheels), `payload/installed-sizes.json`, `.content-manifest`
- Modify: `build/update`
- Test: `tests/wheelhouse-closure`

- [ ] **Step 1:** `tests/wheelhouse-closure`: parse `Requires-Python` from each
  wheel's METADATA, fail when the shipped interpreter does not satisfy it, and
  fail when a declared `requires_python` is not satisfied by the shipped minor
  or contradicts the ABI tags in its closure.
- [ ] **Step 2:** `build/update`: after building rolling wheels, read the built
  wheel's tag + `Requires-Python` and refuse to copy it when the entry's
  declared `requires_python` disagrees.
- [ ] **Step 3:** `build/build-shell sh -c 'build/container-rust && . /cache/env
  && ./build/update open-eda-file-tools --rebuild'`.
- [ ] **Step 4:** Run `tests/wheelhouse-closure` and `build/gen-installed-sizes`
  + `build/gen-content-manifest` in the container; expect PASS and a manifest
  that covers the new wheels.

### Task 5: End-to-end proofs

**Files:**
- Create: `tests/python-requires`
- Modify: `tests/install-open-eda-file-tools`

- [ ] **Step 1:** `tests/python-requires` (T1): a temp repo (symlinked
  `loadout_main.py` + `installer_vendor`, `payload/packages.json` copy) where
  `open-eda-file-tools.requires_python` is `>=3.16`, `mdformat` has the field
  deleted, and nothing is changed; `resolve` must exit 1 with the package named
  in the first two cases and 0 in the third.
- [ ] **Step 2:** `tests/install-open-eda-file-tools`: require
  `def-dump-instances` on PATH and run its `--help`; run both CLIs with a
  `python3` that exits 99 first on PATH.
- [ ] **Step 3:** Run both (T2 with `TMPDIR=/var/tmp`); expect PASS.

## Outcome (2026-11-06)

All five tasks landed on `main` in one change. Two facts the plan did not
anticipate:

- The rebuilt upstream wheels (`v2026.11.4-1-gef72bb6`) require
  `polars>=2.1.0`; the wheelhouse carried 2.0.0, so
  `uv tool install liberty-tools` failed with an unsatisfiable requirement and
  the T2 gate caught it. The closure was refreshed with `polars==2.1.0` plus
  `polars-runtime-{32,64,compat}` and the superseded 1.41.2/2.0.0 wheels pruned.
  `tests/wheelhouse-closure` did NOT catch the version mismatch: it checks
  presence, ABI tags and (now) `Requires-Python`, not `Requires-Dist` version
  constraints. Left as a known gap rather than guessed at.
- `build/update` needed no CLI change: the container provisioning script
  (`build/container-rust`) already existed, so the rebuild was one command.
- Task 2's "import every console-script module" probe was wrong and was replaced
  (`f0967b6`) before the release gates: jupyterlab's `labhubapp` needs unbundled
  JupyterHub and a GUI package's module import needs libGL, so
  `tests/install-linux-tmp-home` failed on a correct install. The probe now
  checks what the ABI lock actually claims: every compiled extension the
  distribution itself ships must be tagged for the venv interpreter's ABI and
  must import (dependency extensions are skipped).
