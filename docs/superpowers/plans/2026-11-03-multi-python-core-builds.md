# Multiple Python Core Builds Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship CPython 3.12 and 3.13 alongside the existing 3.15, selectable with Environment Modules, without per-version python-loaded.

**Architecture:** Bundle python-build-standalone `install_only_stripped` interpreters as runtime archives. The existing generic runtime-archive installer extracts each into a stable `<prefix>/opt/python/<minor>` path; a new installer phase writes modulefiles under `<prefix>/share/modulefiles/python/<minor>`. The uv launcher gains a `LOADOUT_PYTHON` default that modulefiles set, while project pins still win. `python-loaded` and EL's own python-tools stay on 3.15.

**Tech Stack:** POSIX-sh build script, Python 3.15 installer (`loadout_main.py`), Environment Modules 5.6.1, uv 0.13.5.

**Spec:** `docs/superpowers/specs/2026-11-03-multi-python-versions-parked-design.md` (parked design; this plan implements §6.1-§6.4, §6.7-§6.8 and excludes §6.5-§6.6).

## Global Constraints

- EL8 / glibc 2.28 is the floor. Every new interpreter must run on a stock AlmaLinux 8.10 container and pass `tests/needed-closure`.
- All payload-mutating work runs through `build/build-shell`; never build or repack payload on the host.
- Interpreters are pinned to python-build-standalone release tag `20261026` and versions `3.12.16` and `3.13.18`. Do not silently substitute a newer release.
- Install layout is stable per minor: `<prefix>/opt/python/<minor>`. Never install to a patch-named path.
- Modulefiles must not set `PYTHONPATH`, `PYTHONHOME`, or `LD_LIBRARY_PATH`, and must not export `UV_PYTHON`.
- `python-loaded` is unchanged and remains tied to 3.15. Extra interpreters are optional and excluded from `@shared`.
- Regenerate `payload/installed-sizes.json` BEFORE `.content-manifest`; the manifest hashes the sizes file.
- Every new `tests/*` executable must be named in `AGENTS.md`; `tests/docs-sync` enforces it.
- Commit only after the task's named tests pass; run the full T1/T2/T3 gates in the final task.

## Review Focus

- **Project pin vs module default.** With `python/3.12` loaded, a project pinned to 3.13 must not be silently rebuilt on 3.12. Tested in `tests/uv-launchers`.
- **Patch-update path stability.** A venv created from `opt/python/3.12/bin/python3` must keep that path and keep working after the interpreter is reinstalled in place. Tested in `tests/install-python-versions`.
- **Modulefile leakage.** Loading a Python module must not export `PYTHONPATH`, `PYTHONHOME`, or `LD_LIBRARY_PATH` into child processes, including EDA tools' bundled Pythons. Tested in `tests/install-python-versions`.
- **EL8 runtime closure.** Each interpreter must start on stock EL8 with every `DT_NEEDED` soname resolved by the payload or the EL8 floor. Tested by `tests/needed-closure` and the Tier 3 probe.
- **EL's own tools stay on 3.15.** Loading a module must not change `<prefix>/bin/python3` or the interpreter used by EL's python-tools. Tested in `tests/install-python-versions`, `tests/uv-launchers`, and the existing `tests/python-suite` / `tests/install-python-tool-upgrade` gates.

## File Structure

- `build/build-python-standalone.sh` (new) — fetch, verify, CA-inject, check, repack one PBS interpreter.
- `build/strip-all-elf-binaries` (modify) — add `python-3.` to `NOSTRIP_ARCHIVE_PREFIXES`.
- `payload/packages.json` (modify) — `python-3.12`, `python-3.13`, `@python-versions`, `_schema.python_version`.
- `payload/el8.x86_64.glibc2p28/runtime/python-3.12.tar.bz2` (new binary payload).
- `payload/el8.x86_64.glibc2p28/runtime/python-3.13.tar.bz2` (new binary payload).
- `loadout_main.py` (modify) — modulefile writer and install phase.
- `build/uv-launcher.sh` (modify) — `LOADOUT_PYTHON` and project-pin policy.
- `build/update-prebuilt` (modify) — `--launchers-only`.
- `payload/el8.x86_64.glibc2p28/bin/uv.bz2` (regenerated launcher payload).
- `tests/payload-interpreter-abi` (modify) — allow declared python-base minors.
- `tests/install-python-versions` (new T2) — install, module load, venv stability, no leakage.
- `tests/uv-launchers` (modify) — module default and project-pin precedence.
- `tests/prebuilt-binaries` (modify) — Tier 3 probe for each bundled interpreter.
- `tests/run-all` (modify) — register the new T2 test.
- `docs/PYTHON-VERSIONS.md` (new) — user-facing selection/uv/module behavior.
- `README.md`, `AGENTS.md`, `docs/INSTALLATION.md`, `build/ADDING_BINARIES.md`, `docs/HANDOFF.md` (modify).
- `.content-manifest`, `payload/installed-sizes.json` (regenerated).

---

### Task 1: Build and register the PBS interpreters

**Files:**
- Create: `build/build-python-standalone.sh`
- Modify: `build/strip-all-elf-binaries:42`
- Modify: `payload/packages.json` (`_schema`, `python-3.12`, `python-3.13`, `@python-versions`)
- Create: `payload/el8.x86_64.glibc2p28/runtime/python-3.12.tar.bz2`, `payload/el8.x86_64.glibc2p28/runtime/python-3.13.tar.bz2`
- Modify: `tests/payload-interpreter-abi`
- Modify: `README.md` (add two rows)
- Modify: `build/ADDING_BINARIES.md` (new section)
- Regenerate: `payload/installed-sizes.json`, `.content-manifest`

**Interfaces:**
- `build/build-python-standalone.sh --tag 20261026 --version 3.12.16` writes `payload/el8.x86_64.glibc2p28/runtime/python-3.12.tar.bz2` and stamps `payload/packages.json` entry `python-3.12` to `3.12.16`.
- Registry entry shape:
  ```json
  "python-3.12": {
    "kind": "python-base",
    "archive": "payload/PLATFORM/runtime/python-3.12.tar.bz2",
    "archive_name": "python-3.12.tar.bz2",
    "sentinel": "bin/python3.12",
    "install_to": "~/.local/opt/python/3.12",
    "version": "3.12.16",
    "python_version": "3.12",
    "platforms": ["linux"],
    "optional": true,
    "tags": ["python", "runtime"],
    "description": "CPython 3.12 (python-build-standalone) for version-pinned scripts; module load python/3.12"
  }
  ```
  Add `"depends": ["gui_libs"]` only if `tests/needed-closure` reports an X11 soname for the archive.
- Group: `@python-versions` members `["python-3.12", "python-3.13"]`, description `"Optional CPython 3.12 + 3.13 interpreters (module load python/3.12)"`.
- `_schema` gains: `"python_version": "For kind='python-base': the CPython minor this archive provides (e.g. '3.12'). Distinct from 'version' (the exact patch, e.g. '3.12.16'); used by modulefile generation and the ABI gate."`

- [ ] **Step 1: Write the build script**

Create `build/build-python-standalone.sh` (POSIX sh, `set -eu`). It must:

1. Require `--tag` and `--version`; reject a non-`X.Y.Z` version.
2. Derive `MINOR` from the first two components.
3. Download `https://github.com/astral-sh/python-build-standalone/releases/download/<tag>/SHA256SUMS` and the asset `cpython-<version>+<tag>-x86_64-unknown-linux-gnu-install_only_stripped.tar.gz` with `curl -fsSL`.
4. Verify the asset's sha256 against the exact `SHA256SUMS` line; abort on mismatch.
5. Extract to a temp dir; require the tree to contain `bin/python<MINOR>`, `lib/`, and `BUILD`.
6. If `lib/python<MINOR>/sitecustomize.py` already exists, rename it to `sitecustomize_pbs.py` and make the injected file import it first (the portable-python hook does the same for `sitecustomize_portable`); otherwise copy `build/portable-python-sitecustomize.py` to that path.
7. Write `LOADOUT_BUILD` in the tree with the source URL, tag, version, and sha256.
8. Assert the highest `GLIBC_x.y` in `bin/python<MINOR>` is <= 2.28 (use `readelf -V`, `sort -V`).
9. Smoke-run `bin/python<MINOR> -c 'import sys, ssl, sqlite3, zlib; print(sys.version)'`.
10. Repack `bin include lib share BUILD LOADOUT_BUILD` with `tar -C <tree> -cjf` to `payload/el8.x86_64.glibc2p28/runtime/python-<MINOR>.tar.bz2` (delete the old file first).
11. Call `loadout_stamp_version python-<MINOR> <version>` from `build/lib.sh`.

Use the existing build scripts' header/usage conventions and `build/lib.sh` helpers.

- [ ] **Step 2: Build both interpreters in the container**

Run:
```sh
build/build-shell sh -c 'build/build-python-standalone.sh --tag 20261026 --version 3.12.16 && build/build-python-standalone.sh --tag 20261026 --version 3.13.18'
```
Expected: two archives, each ~30–34 MiB, and two `packages.json` stamps.

- [ ] **Step 3: Verify the archives outside the installer**

```sh
tmp=$(mktemp -d); tar -C "$tmp" -xjf payload/el8.x86_64.glibc2p28/runtime/python-3.12.tar.bz2
"$tmp/bin/python3.12" -c 'import sys, ssl, sqlite3, zlib; print(sys.version)'
readelf -V "$tmp/bin/python3.12" | grep -oE 'GLIBC_[0-9]+\.[0-9]+' | sort -V | tail -1
```
Repeat for 3.13. Expected: versions print; max GLIBC <= 2.28.

- [ ] **Step 4: Register the packages and group**

Add the two entries and `@python-versions` to `payload/packages.json`; add `python_version` to `_schema`. Add the two README rows by hand:
```markdown
| python-3.12 | python-base | 3.12.16 | CPython 3.12 (python-build-standalone) for version-pinned scripts; `module load python/3.12` |
| python-3.13 | python-base | 3.13.18 | CPython 3.13 (python-build-standalone) for version-pinned scripts; `module load python/3.13` |
```

- [ ] **Step 5: Add the strip exclusion**

Add `"python-3."` to `NOSTRIP_ARCHIVE_PREFIXES` in `build/strip-all-elf-binaries` so the already-stripped PBS archives are never repacked.

- [ ] **Step 6: Teach the ABI gate about declared minors**

Modify `tests/payload-interpreter-abi`:

1. Add `python_base_minors()`: read `packages.json`, return `{entry["python_version"] for entry in packages.values() if entry.get("kind") == "python-base" and entry.get("python_version")}`.
2. Map each `runtime/python-<minor>.tar.bz2:<member>` file to its owning minor. For every other file, the allowed minor is the portable-python minor (3.15).
3. Rule 1 (libpython NEEDED), Rule 2 (interpreter-picking scripts), and Rule 3 (extension-module ABI) must accept the owning archive's minor and reject any other minor.
4. Extend `disabled_artifacts()` to map `archive_name` as well as `archive`.
5. Keep the existing failure messages; name the owning archive in them.

Run:
```sh
python3.15 tests/payload-interpreter-abi
```
Expected: PASS, with a line naming each declared minor.

- [ ] **Step 7: Run the closure and registry gates**

```sh
python3.15 tests/registry-integrity
python3.15 tests/needed-closure
./loadout doctor
```
If `needed-closure` reports an X11 soname for either archive, add `"depends": ["gui_libs"]` to both entries and rerun.

- [ ] **Step 8: Regenerate sizes, manifest, README**

In `build/build-shell`:
```sh
python3.15 build/gen-installed-sizes
python3.15 build/gen-content-manifest
python3.15 build/gen-readme-table
```
Expected: sizes and manifest include the two new archives; README rows remain.

- [ ] **Step 9: Write the build notes**

Add a `## python-3.12 / python-3.13 ...` section to `build/ADDING_BINARIES.md` with the PBS tag, asset names, verified sha256s, compressed/uncompressed sizes, CA injection, glibc result, closure result, layout, and the exact build command.

- [ ] **Step 10: Commit**

```bash
git add build/build-python-standalone.sh build/strip-all-elf-binaries payload/packages.json \
    payload/el8.x86_64.glibc2p28/runtime/python-3.12.tar.bz2 \
    payload/el8.x86_64.glibc2p28/runtime/python-3.13.tar.bz2 \
    tests/payload-interpreter-abi README.md build/ADDING_BINARIES.md \
    payload/installed-sizes.json .content-manifest
git commit -m "feat(python): bundle CPython 3.12 and 3.13 interpreters"
```

---

### Task 2: Generate modulefiles and prove module selection

**Files:**
- Modify: `loadout_main.py` (modulefile writer; install phase)
- Create: `tests/install-python-versions`
- Modify: `tests/run-all`
- Modify: `AGENTS.md` (name the new test)

**Interfaces:**
- `_python_modulefile_text(prefix: str, minor: str) -> str` returns the exact modulefile text.
- `install_python_modulefiles(repo_dir, home, selected_tools, registry) -> None` iterates `kind == "python-base"` entries with `python_version`, skips unselected entries, skips missing interpreters with a `SKIP` row, and writes `<prefix>/share/modulefiles/python/<minor>` atomically only when the content changed.
- The phase is wired after `runtime archives`:
  ```python
  run_install_step("Python modulefiles", install_python_modulefiles, repo_dir, home, selected_tools, registry)
  ```

Modulefile text (exact):
```tcl
#%Module1.0
##
## python/<minor> -- loadout-managed CPython <minor>
##
proc ModulesHelp { } {
    puts stderr "CPython <minor> from loadout ({prefix}/opt/python/<minor>)"
}
module-whatis "CPython <minor> (loadout)"
family python
prepend-path PATH {<prefix>/opt/python/<minor>/bin}
setenv LOADOUT_PYTHON {<prefix>/opt/python/<minor>/bin/python3}
setenv UV_PYTHON_DOWNLOADS never
```

- [ ] **Step 1: Write the failing T2 test**

Create `tests/install-python-versions` modeled on `tests/install-modules` and `tests/install-watchglass`. It must install offline into a temp root:
```bash
env -i HOME="$test_home" PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
    "$repo_dir/loadout" install -y python-3.12 python-3.13 modules uv --dest-dir "$dest_dir" --no-backup
```
Then assert:
1. `$dest_dir/opt/python/3.12/bin/python3.12` and `.../3.13/bin/python3.13` are executable and report the right versions.
2. `$dest_dir/share/modulefiles/python/3.12` and `.../3.13` exist; each contains `family python`, `LOADOUT_PYTHON`, and `UV_PYTHON_DOWNLOADS never`, and does not contain `PYTHONPATH`, `PYTHONHOME`, `LD_LIBRARY_PATH`, or `setenv UV_PYTHON `.
3. In bash: source `$dest_dir/lib/modules/init/bash`; `module use $dest_dir/share/modulefiles`; `module load python/3.12`; `python3 -c 'import sys; assert sys.version_info[:2] == (3, 12)'`; `$LOADOUT_PYTHON` equals `$dest_dir/opt/python/3.12/bin/python3`; `$UV_PYTHON_DOWNLOADS` equals `never`; `PYTHONPATH`/`PYTHONHOME`/`LD_LIBRARY_PATH` are unset; `UV_PYTHON` is unset.
4. `module switch python/3.13` (or unload/load if `family` conflicts) makes `python3` report 3.13.
5. In tcsh: source `$dest_dir/lib/modules/init/csh`, `module use ...`, `module load python/3.12`, and assert `python3 --version` reports 3.12 and `$LOADOUT_PYTHON` is set.
6. Create a venv from the loaded 3.12 with `$dest_dir/bin/uv venv` (install `uv` in the selection for this step); assert `venv/bin/python -c 'import sys; print(sys.executable)'` is under `$dest_dir/opt/python/3.12/`, and `pyvenv.cfg` names the stable path. Re-run the install command; assert the venv still runs (path stability).
7. `"$dest_dir/bin/python3" --version` still reports 3.15 after the module load (EL's default is unchanged).

Add `run_test "install-python-versions" --deps auto tests/install-python-versions` to `tests/run-all` near `install-modules`, and add the name to the T2 list in `AGENTS.md`.

Run the test before implementing: it must fail because the modulefiles are absent.

- [ ] **Step 2: Implement the modulefile writer and phase**

Add the two functions and the `run_install_step` wiring to `loadout_main.py`. Use `_write_stream_atomic` and compare the existing content first. Use `record_result` with names `"python-3.12 modulefile"` / `"python-3.13 modulefile"`.

- [ ] **Step 3: Run the T2 test**

```sh
tests/install-python-versions
```
Expected: PASS. If `module switch` is unsupported by the bundled Environment Modules, change the test to `module unload python/3.12 && module load python/3.13` and record why in the test comment.

- [ ] **Step 4: Run docs-sync**

```sh
python3.15 tests/docs-sync
```
Expected: PASS (the new test is named in `AGENTS.md`).

- [ ] **Step 5: Commit**

```bash
git add loadout_main.py tests/install-python-versions tests/run-all AGENTS.md
git commit -m "feat(python): install modulefiles for bundled interpreters"
```

---

### Task 3: Make uv honor the loaded interpreter without overriding project pins

**Files:**
- Modify: `build/uv-launcher.sh`
- Modify: `build/update-prebuilt` (`--launchers-only`)
- Regenerate: `payload/el8.x86_64.glibc2p28/bin/uv.bz2` (and `uvx.bz2`)
- Modify: `tests/uv-launchers`
- Regenerate: `payload/installed-sizes.json`, `.content-manifest`

**Interfaces:**
- Launcher pin source: `${LOADOUT_PYTHON}` when executable, else `<prefix>/bin/python3`.
- `project_pins_python()` returns success when a `.python-version` file or a `pyproject.toml` containing a `requires-python =` assignment exists in `$PWD` or any ancestor.
- Project-scoped commands that must defer to a project pin: `run`, `sync`, `lock`, `venv`, `add`, `remove`, `build`, `export`.
- `build/update-prebuilt --launchers-only` rewrites the launcher bz2s from `build/*-launcher.sh` without downloading the upstream binary.

- [ ] **Step 1: Extend the failing uv test**

Add to `tests/uv-launchers` an install of `python-3.12 python-3.13` (alongside the existing `portable-python uv`). Add cases:
1. `LOADOUT_PYTHON=$tree/opt/python/3.12/bin/python3` + `uv run --no-project python -c 'import sys; print(sys.executable)'` -> the 3.12 path.
2. `LOADOUT_PYTHON=...3.12...` + `uv init` in an empty dir -> `.python-version` is `3.12`.
3. A project with `.python-version` `3.13` + `LOADOUT_PYTHON=...3.12...` + `uv venv` -> the venv's Python reports 3.13.
4. A project with `pyproject.toml` `requires-python = ">=3.13"` + `LOADOUT_PYTHON=...3.12...` + `uv venv` -> the venv's Python is not 3.12 (expect 3.13 or a loud uv refusal; assert the 3.12 path was not used).
5. Existing cases still pass: caller `UV_PYTHON` wins, active venv wins for `uv run`, `uv pip` remains unpinned.

Run the test before implementing; the new cases must fail.

- [ ] **Step 2: Implement the launcher policy**

Add `project_pins_python()` and the command gate to `build/uv-launcher.sh`. Keep the existing `uv pip` and active-venv carve-outs. Do not export `LOADOUT_PYTHON`; only read it. Preserve the existing `UV_PYTHON` caller precedence.

- [ ] **Step 3: Add `--launchers-only` and recompose**

Add the flag to `build/update-prebuilt`; when set, skip the download/stamp path and write each `LAUNCHERS` entry from `build/<launcher>` into `payload/<platform>/bin/<name>.bz2`. Run:
```sh
./build/update-prebuilt --launchers-only
bunzip2 -c payload/el8.x86_64.glibc2p28/bin/uv.bz2 | grep -q LOADOUT_PYTHON
```
Expected: exit 0 and the marker is present.

- [ ] **Step 4: Run the uv tests**

```sh
tests/uv-launchers
```
Expected: PASS.

- [ ] **Step 5: Regenerate sizes and manifest**

In `build/build-shell`:
```sh
python3.15 build/gen-installed-sizes
python3.15 build/gen-content-manifest
```

- [ ] **Step 6: Commit**

```bash
git add build/uv-launcher.sh build/update-prebuilt tests/uv-launchers \
    payload/el8.x86_64.glibc2p28/bin/uv.bz2 payload/el8.x86_64.glibc2p28/bin/uvx.bz2 \
    payload/installed-sizes.json .content-manifest
git commit -m "feat(uv): honor LOADOUT_PYTHON without overriding project pins"
```

---

### Task 4: Tier 3 coverage, docs, and generated-file sync

**Files:**
- Modify: `tests/prebuilt-binaries` (install `@python-versions`; probe each interpreter)
- Create: `docs/PYTHON-VERSIONS.md`
- Modify: `README.md`, `AGENTS.md`, `docs/INSTALLATION.md`, `build/ADDING_BINARIES.md`
- Modify: `docs/HANDOFF.md`
- Regenerate: `payload/installed-sizes.json`, `.content-manifest`, `README.md`

**Interfaces:**
- Tier 3 install command becomes `./loadout install -y @shared @python-versions --dest-dir ... --no-backup`.
- The probe iterates registry entries with `kind == "python-base"` and `python_version`, runs `<dest>/opt/python/<minor>/bin/python<minor> -c 'import sys, ssl, sqlite3; print(sys.version_info[:2])'`, and asserts the modulefile exists.

- [ ] **Step 1: Add the Tier 3 probe**

Modify `tests/prebuilt-binaries` at the install call and add a `probe_python_versions(install_root, env)` function. It must fail when an interpreter is missing, does not start, or has no modulefile. Keep the existing `@shared` probes unchanged.

- [ ] **Step 2: Write the user docs**

Create `docs/PYTHON-VERSIONS.md` covering:
- `./loadout install @python-versions` (optional; not in `@shared`).
- `module use <prefix>/share/modulefiles`, `module load python/3.12`, `module switch python/3.13`.
- The module prepends `opt/python/<minor>/bin` and sets `LOADOUT_PYTHON` + `UV_PYTHON_DOWNLOADS=never`; it sets no `PYTHON*` or `LD_LIBRARY_PATH`.
- `uv init`/`uv venv` use the loaded interpreter by default; a project `.python-version` or `requires-python` wins; `uv pip` and active venvs keep their existing behavior.
- `python-loaded` and EL's python-tools remain on 3.15.
- Patch updates replace the interpreter in place; venvs keep the stable path.
- Offline: no downloads; interpreters and wheels come from the payload.

Add a short "Multiple Python versions" subsection to the README's Python section and a pointer in `docs/INSTALLATION.md`. Update the `AGENTS.md` architecture paragraph: new python-base entries, `opt/python/<minor>`, modulefiles, `LOADOUT_PYTHON`, and the new test name.

- [ ] **Step 3: Update the build notes**

Add the interpreter layout, modulefile contract, and the uv policy to `build/ADDING_BINARIES.md` (extend the Task 1 section).

- [ ] **Step 4: Regenerate the generated files**

In `build/build-shell`:
```sh
python3.15 build/gen-installed-sizes
python3.15 build/gen-content-manifest
python3.15 build/gen-readme-table
```

- [ ] **Step 5: Run the focused gates**

```sh
python3.15 tests/docs-sync
python3.15 tests/registry-integrity
python3.15 tests/payload-interpreter-abi
python3.15 tests/needed-closure
python3.15 build/gen-content-manifest --check
python3.15 build/gen-installed-sizes --check
python3.15 build/gen-readme-table --check
```
Expected: all PASS.

- [ ] **Step 6: Commit**

```bash
git add tests/prebuilt-binaries docs/PYTHON-VERSIONS.md README.md AGENTS.md \
    docs/INSTALLATION.md build/ADDING_BINARIES.md payload/installed-sizes.json \
    .content-manifest
git commit -m "docs(python): document multiple interpreter selection and uv behavior"
```

---

### Task 5: Final verification and handoff

**Files:**
- Modify: `docs/HANDOFF.md`
- Modify: `assurance/release-timings.tsv` (generated by gate runs)

- [ ] **Step 1: Run Tier 1**

```sh
tests/run-all --fast
```
Expected: PASS.

- [ ] **Step 2: Run the targeted Tier 2 tests**

```sh
tests/install-python-versions
tests/uv-launchers
tests/install-modules
tests/install-watchglass
tests/install-python-tool-upgrade
```
Expected: all PASS.

- [ ] **Step 3: Run Tier 3**

```sh
tests/prebuilt-binaries-almalinux8 --full
```
Expected: PASS, including the new `opt/python/3.12` and `opt/python/3.13` probes.

- [ ] **Step 4: Record the handoff**

Add a `docs/HANDOFF.md` entry with: the exact PBS tag/versions and sha256s, payload sizes, modulefile path, uv policy, test results and timings, and the remaining open decisions (EOL versions, exact-patch modulefiles, site Environment Modules version, whether `@python-versions` should join `@python-stack`).

- [ ] **Step 5: Commit and push**

```bash
git add docs/HANDOFF.md assurance/release-timings.tsv
git commit -m "docs(handoff): record multi-Python core builds verification"
git push origin main
```
