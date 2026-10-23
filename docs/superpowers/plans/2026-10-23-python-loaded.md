# python-loaded Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a `python-loaded` package that installs one curated, offline, cp315/EL8 Python 3.15 venv with its own `bin/` and no links into the shared bin.

**Architecture:** A new `python-suite` registry kind drives a new installer phase. The payload carries a maintained `requirements.in`, a pinned+hashed lock, and a suite-private repaired wheelhouse built in AlmaLinux 8. At install time `uv` creates a versioned venv behind a stable symlink; nothing is resolved or patched on the host.

**Tech Stack:** Python 3.15 (EL portable build), `uv`, `pip`, `auditwheel`, AlmaLinux 8.10 container, POSIX sh build script, existing loadout registry/installer/test harness.

**Spec:** `docs/superpowers/specs/2026-10-23-python-loaded-design.md`

## Global Constraints

- Interpreter is the payload's portable Python; suite ABI is exactly `cpython-315`.
- Wheel tags must be installable on EL8: `abi3`, pure `py3-none-*` at glibc ≤ 2.28, or `cp315` at glibc ≤ 2.28.
- No suite file is linked or copied into `<prefix>/bin`.
- Install is fully offline: `--no-index --find-links payload/python-loaded/wheels --require-hashes`.
- No `patchelf`/repair at install time; repair happens only in the EL8 build.
- Patch-level interpreter change never rebuilds; minor-level change hard-fails.
- Docker/EL8 absence is a hard failure for a refresh, never a host fallback.
- `python-loaded` is `standalone`: excluded from `@shared`, `@shared-all`, `@all`.
- Source must remain valid under the repo's Python 3.14+ PEP 758 syntax rules.
- Time the suite build and the integration install; record the numbers.

## Review Focus

- `--dest-dir` install: the venv, shebangs, and stable `venv/bin` symlink must work under a non-HOME prefix with no write to the real HOME. Owned by Task 5.
- Minor-ABI mismatch: a `cpython-316` interpreter with a `cpython-315` lock must fail before touching the working venv. Owned by Task 5.
- Lock integrity: a wheel whose hash does not match the lock, or a missing wheel, must fail before a venv is created. Owned by Tasks 2 and 5.
- Upgrade swap: console scripts must keep working after the `venv` symlink moves, and a failed rebuild must leave the previous version usable. Owned by Task 5.
- Sweep isolation: `install @shared-all` must not create `share/python-loaded`. Owned by Tasks 1 and 6.

---

### Task 1: Registry kind and standalone sweeps

**Files:**
- Modify: `payload/packages.json` (`_schema`, new `python-loaded` entry)
- Modify: `loadout_main.py:434-452` (`@shared`, `@shared-all` filters) and a helper near `disabled_packages`
- Modify: `tests/registry-integrity:38` (`KNOWN_KINDS`)
- Modify: `tests/unit-resolver` (fixtures + assertions)
- Modify: `docs/ARCHITECTURE.md:14-33` (kind list and artifact fields)

**Interfaces:**
- Produces: `standalone_packages(registry: dict) -> set[str]` — names whose entry has `standalone is True`.
- Produces: registry fields `standalone: bool`, `requirements: str`, `lock: str`, `wheels_dir: str`.
- Consumes: nothing.

- [ ] **Step 1: Add failing resolver assertions**

In `tests/unit-resolver`, add to `REGISTRY`:
```python
"suite": {"kind": "python-suite", "standalone": True, "platforms": ["linux"],
          "depends": ["portable-python", "uv"]},
"portable-python": {"kind": "python-base", "platforms": ["linux"]},
"uv": {"kind": "bin", "bins": ["uv"], "platforms": ["linux"]},
```
and assert in `test_expand_groups`:
```python
check("standalone excluded from @shared", "suite" not in eg(["@shared"], REGISTRY))
check("standalone excluded from @shared-all", "suite" not in eg(["@shared-all"], REGISTRY))
check("standalone excluded from @all", "suite" not in eg(["@all"], REGISTRY))
check("standalone named explicitly", eg(["suite"], REGISTRY) == {"suite"})
```

- [ ] **Step 2: Run it and watch it fail**

Run: `python3.15 tests/unit-resolver`
Expected: FAIL on the first three new checks.

- [ ] **Step 3: Implement the filter and registry entry**

`standalone_packages` returns `{n for n, e in registry.items() if e.get("standalone")}`; compute it beside `_disabled` and add `and n not in _standalone` to the `@shared` and `@shared-all` comprehensions. `@all` is their union and inherits.

Add the entry from spec D1 (version `2026.10.23`, `standalone: true`, `depends: ["portable-python", "uv"]`, `requirements`/`lock`/`wheels_dir` paths). Add those four fields to `_schema` with one-line descriptions, and state in `optional`'s description that `standalone` is a second gating field. Add `python-suite` to `KNOWN_KINDS` and to the `kind` schema string.

- [ ] **Step 4: Run both registry tests**

Run: `python3.15 tests/unit-resolver && python3.15 tests/registry-integrity`
Expected: both exit 0.

- [ ] **Step 5: Commit**

```bash
git add payload/packages.json loadout_main.py tests/unit-resolver tests/registry-integrity docs/ARCHITECTURE.md
git commit -m "feat(registry): add python-suite kind and standalone sweep flag"
```

---

### Task 2: EL8 build pipeline and payload artifacts

**Files:**
- Create: `payload/python-loaded/requirements.in`
- Create: `payload/python-loaded/requirements.lock.txt` (generated)
- Create: `payload/python-loaded/wheels/*.whl` (generated)
- Create: `build/python-loaded-sdist-allowlist.txt`
- Create: `build/python-loaded-cli-allowlist.txt`
- Create: `build/build-python-loaded.sh`
- Create: `tests/python-suite`

**Interfaces:**
- Produces: lock header lines `# python-loaded lock <YYYY.MM.DD>`, `# abi: cpython-315`, `# python: 3.15.0`, then pinned `name==version --hash=sha256:<digest>` lines.
- Produces: `build/build-python-loaded.sh [--print-plan]`, exit 0 on success, non-zero without Docker.
- Produces: `tests/python-suite` (Tier 1, no args), exit 0/1.
- Consumes: registry entry from Task 1.

- [ ] **Step 1: Write the contract test**

`tests/python-suite` loads `loadout_main.py` with the same
`importlib.machinery.SourceFileLoader` pattern as `tests/unit-resolver`, and
asserts, with `check()` like `tests/wheelhouse-closure`:

```python
tops = parse_requirements_in()                 # names only, '#' comments skipped
lock = parse_lock()                            # (name, version, hash) per line + header
assert lock["abi"] == "cpython-315"
assert lock["python"].startswith("3.15.")
assert "kaleido" not in tops and "uWSGI" not in tops
for name in tops: assert name in {d for d,_,_ in lock}
for name, ver, sha in lock:
    path = wheel_path(WHEELS, name, ver)       # rejoins .part-NNN
    assert path, f"{name}=={ver} has no wheel"
    assert sha256_file(path) == sha
assert not (REPO / "payload/python-loaded/wheels").glob("*.tar.gz")
assert (REPO / "build/python-loaded-sdist-allowlist.txt").read_text().split() == ["PyYAML", "python-ldap", "pyeda"]
# D8: the suite must not write into the shared wheelhouse.
status = subprocess.run(["git", "status", "--porcelain", "--",
                         "payload/el8.x86_64.glibc2p28/wheels"],
                        capture_output=True, text=True).stdout
assert status == ""
```

- [ ] **Step 2: Run it and watch it fail**

Run: `python3.15 tests/python-suite`
Expected: FAIL, `payload/python-loaded/requirements.in` missing.

- [ ] **Step 3: Write the inputs**

`requirements.in`: Appendix A tops, one per line, no versions:
`Django django-auth-ldap django-filter Flask dash litestar litestar-htmx uvicorn boto3 numpy pandas scipy matplotlib scikit-learn statsmodels xgboost-cpu shapely pyarrow openpyxl pikepdf img2pdf pillow nltk graphviz evidently pylint pylintfileheader pydantic rich typer httpx requests jsonschema SQLObject PyMySQL pyeda ruamel.yaml python-dotenv psutil pexpect prettytable more-itertools tenacity setproctitle websockets uvloop httptools watchfiles watchdog`.

`build/python-loaded-sdist-allowlist.txt`: `PyYAML`, `python-ldap`, `pyeda` — one per line, with a comment stating that any addition needs a build recipe.

`build/python-loaded-cli-allowlist.txt`: start with `pylint`, `pygmentize`, `django-admin`, `uvicorn`, `watchmedo`, `sqlformat`.

- [ ] **Step 4: Write the build script**

`build/build-python-loaded.sh`:
- `set -eu`; resolve `REPO`; require `docker`; `--print-plan` prints every container command and exits 0 without network.
- Container: `almalinux:8.10`, repo copied read-only into `/work/repo`, `/cache` bind mount, `dnf install -y gcc-toolset-14 openldap-devel cyrus-sasl-devel openssl-devel zlib-devel libffi-devel patchelf` (enable EPEL first if `patchelf` is not in AppStream).
- Extract portable Python; `uv venv --seed /work/buildenv`; install `auditwheel` into it.
- For each name in the sdist allowlist: `python -m pip wheel --no-deps --no-binary :all: -w /work/prebuilt <name>`.
- Resolve: `uv pip compile requirements.in --python-version 3.15 --python-platform x86_64-manylinux_2_28 --only-binary :all: --find-links /work/prebuilt -o /work/pins.txt`.
- Acquire: `python -m pip download --no-deps --only-binary=:all: -r /work/pins.txt -d /work/dl`.
- Reject any wheel whose platform tag exceeds glibc 2.28.
- Repair: `auditwheel repair --plat manylinux_2_28_x86_64 -w /work/repaired <wheel>` only when `auditwheel show` reports external non-policy libraries; otherwise copy.
- Emit the lock from the final files (`sha256sum`), ordered by name, with the three header lines.
- Verify in a fresh `--seed` venv with `env -i PATH=/usr/bin:/bin`: `uv pip install --no-index --find-links /work/final --require-hashes -r lock`, then import every top, `ldd` every ELF, assert every `bin/*` text script is executable with a shebang containing the venv path, and run `--help` only for the CLI allowlist.
- Copy final wheels + lock into `payload/python-loaded/`; print total bytes and wall time.

- [ ] **Step 5: Static checks**

Run: `bash -n build/build-python-loaded.sh && ./build/build-python-loaded.sh --print-plan`
Expected: rc 0, commands printed, no container started.

- [ ] **Step 6: Run the real build**

Run: `time ./build/build-python-loaded.sh`
Expected: rc 0; lock + wheels written; report the wheel count, total MB, and wall time. Then `python3.15 tests/python-suite` → PASS.

- [ ] **Step 7: Strip and measure**

Run: `./build/strip-all-elf-binaries` (no-op for wheels is acceptable), `python3.15 build/gen-installed-sizes`.
Expected: rc 0; the new wheels appear in `payload/installed-sizes.json`.

- [ ] **Step 8: Commit**

```bash
chmod +x build/build-python-loaded.sh tests/python-suite
git add payload/python-loaded build/build-python-loaded.sh build/python-loaded-*-allowlist.txt tests/python-suite payload/installed-sizes.json .strip-manifest
git commit -m "feat(python-loaded): EL8 wheel pipeline, lock, and private wheelhouse"
```

---

### Task 3: Wheelhouse closure predicate and suite check

**Files:**
- Modify: `tests/wheelhouse-closure` (`wheel_is_abi_compatible`, indexing, suite branch, `--self-test`)
- Modify: `build/release` (`_payload_consistency_step` gate list)

**Interfaces:**
- Consumes: lock and wheels from Task 2.
- Produces: `wheel_is_abi_compatible(filename: str, shipped: str) -> bool` accepting EL8-legal pure-platform wheels; `suite_lock_entries(path) -> list[dict]`.

- [ ] **Step 1: Add `--self-test` cases first**

```python
check("pure any", wheel_is_abi_compatible("x-1-py3-none-any.whl", "3.15"))
check("pure manylinux", wheel_is_abi_compatible("x-1-py3-none-manylinux_2_28_x86_64.whl", "3.15"))
check("abi3", wheel_is_abi_compatible("x-1-cp36-abi3-manylinux_2_17_x86_64.whl", "3.15"))
check("cp315 el8", wheel_is_abi_compatible("x-1-cp315-cp315-manylinux_2_28_x86_64.whl", "3.15"))
check("cp315 too new", not wheel_is_abi_compatible("x-1-cp315-cp315-manylinux_2_39_x86_64.whl", "3.15"))
check("cp314 locked", not wheel_is_abi_compatible("x-1-cp314-cp314-manylinux_2_28_x86_64.whl", "3.15"))
```

- [ ] **Step 2: Run and watch it fail**

Run: `python3.15 tests/wheelhouse-closure --self-test`
Expected: FAIL on "pure manylinux".

- [ ] **Step 3: Implement the predicate and suite branch**

Parse the compressed platform tag set (`manylinux_2_28_x86_64.manylinux2014_x86_64`), accept `abi none` with an EL8-legal platform, keep the existing `cp315`/`abi3` rules, and reject `musllinux`/`win`/`macosx`. Index `*.whl` and reassemble `*.whl.part-NNN` to a temp file for `wheel_metadata`. Add a suite branch: every lock entry must match the private wheelhouse at the exact version, hash must recompute, and no `sdist`/`tar.gz` may be present.

- [ ] **Step 4: Run the gate**

Run: `python3.15 tests/wheelhouse-closure --self-test && python3.15 tests/wheelhouse-closure`
Expected: PASS, including the suite section.

- [ ] **Step 5: Add to release**

Add `tests/python-suite` to `_payload_consistency_step`'s `gates` tuple in `build/release`.

- [ ] **Step 6: Commit**

```bash
git add tests/wheelhouse-closure build/release
git commit -m "test: make wheel closure EL8-platform and chunk aware; gate python-loaded"
```

---

### Task 4: Artifact attribution for the private wheelhouse

**Files:**
- Modify: `loadout_main.py:6375-6427` (`_artifact_paths`)
- Modify: `tests/python-suite`

**Interfaces:**
- Consumes: `wheels_dir` registry field.
- Produces: `_artifact_paths(entry, repo_dir, platform_dir) -> set[str]` includes every wheel file under `wheels_dir`, chunked or whole.

- [ ] **Step 1: Add the failing assertion**

In `tests/python-suite`:
```python
paths = m._artifact_paths(registry["python-loaded"], REPO, platform_dir)
assert any(p.endswith(".whl") for p in paths)
assert all("python-loaded/wheels" in p for p in paths if p.endswith(".whl"))
```

- [ ] **Step 2: Run and watch it fail**

Run: `python3.15 tests/python-suite`
Expected: FAIL, no `.whl` paths.

- [ ] **Step 3: Implement the branch**

Resolve `entry["wheels_dir"]` (`PLATFORM` substitution allowed), walk it, add regular files including `.part-NNN`.

- [ ] **Step 4: Run and commit**

Run: `python3.15 tests/python-suite` → PASS.

```bash
git add loadout_main.py tests/python-suite
git commit -m "feat(python-loaded): size the private wheelhouse in transaction/doctor paths"
```

---

### Task 5: Installer phase, versioned venv, stamp, ABI gate

**Files:**
- Modify: `loadout_main.py` (new helpers + `install_python_suite`, call site after `install_portable_python`)
- Create: `tests/python-suite-install` (Tier 2)
- Modify: `tests/python-suite` (unit checks for helpers)

**Interfaces:**
- Produces:
  - `install_python_suite(repo_dir, home, selected_tools, registry) -> None`
  - `_suite_lock_meta(lock_path) -> dict` with keys `version`, `abi`, `python`
  - `_suite_abi(python_bin) -> str` (`cpython-315`)
  - `_suite_stamp_path(dest) -> str`
  - `_suite_stamp_matches(stamp: dict, lock_sha: str, abi: str) -> bool`
  - `_suite_version_dir(dest, version, lock_sha) -> str`
  - `_suite_swap_symlink(dest, target_rel) -> None`
  - `_suite_warn_abi_drift(home) -> None`
- Produces: `suite.lock.json` keys `schema`, `abi`, `python`, `lock_sha256`, `built_at`.

- [ ] **Step 1: Write the Tier 2 test**

`tests/python-suite-install` (chmod +x) creates a temp HOME and dest, runs
`HOME=... ./loadout install python-loaded --dest-dir "$dest" --no-backup --assume-yes`,
then asserts:
- `$dest/share/python-loaded/venv/bin/python3 -c 'import sys; print(sys.implementation.cache_tag)'` prints `cpython-315`;
- every lock distribution's version matches `importlib.metadata.version`;
- the curated module map imports (`Django→django`, `PyYAML→yaml`, `Pillow→PIL`, `scikit-learn→sklearn`);
- every ELF under `site-packages` passes `ldd` under `env -i`;
- no `venv/bin` script name exists in `$dest/bin`;
- a console script's first line names the versioned directory, and it runs through `$dest/share/python-loaded/venv/bin`;
- second install is a SKIP (stamp mtime unchanged);
- rewriting the stamp to `cpython-316` makes the install exit non-zero with the D4 message and leaves the venv untouched;
- `$dest/share/python-loaded/venv` resolves and `$dest/share/python-loaded/versions/` has exactly one child.

- [ ] **Step 2: Run and watch it fail**

Run: `python3.15 tests/python-suite-install`
Expected: FAIL, no suite venv at the dest.

- [ ] **Step 3: Implement the helpers and phase**

Implement per spec D2/D4 and the step list under "Install behavior". Use `uv venv --python <prefix>/bin/python3.15 <versioned>/venv`, then `uv pip install --python ... --no-index --find-links <private> --no-cache --offline --require-hashes -r <lock>`. Swap with a temp symlink + `os.replace`. Record `FAIL` on missing lock/wheel/uv and on ABI mismatch. Call `_suite_warn_abi_drift(home)` at the end of `install_portable_python`.

- [ ] **Step 4: Run the full install test and record timing**

Run: `time python3.15 tests/python-suite-install`
Expected: PASS. Record wall time and installed size.

- [ ] **Step 5: Commit**

```bash
chmod +x tests/python-suite-install
git add loadout_main.py tests/python-suite tests/python-suite-install
git commit -m "feat(python-loaded): versioned venv installer with ABI gate and stamp"
```

---

### Task 6: Update command, suite wiring, release gate

**Files:**
- Modify: `build/update` (`AUTOMATED`, `_run_automated`)
- Modify: `tests/run-all` (Tier 1 and Tier 2 registrations)
- Modify: `tests/update-cadence` (new assertions)

**Interfaces:**
- Consumes: `build/build-python-loaded.sh`.
- Produces: `_run_python_loaded(dry_run=False, tag=None) -> bool`; `AUTOMATED["python-loaded"]` with `auto_update_interval: "90d"` and `git_paths: ["payload/python-loaded/", "payload/installed-sizes.json"]`.

- [ ] **Step 1: Add failing update tests**

In `tests/update-cadence`:
```python
check("python-loaded is automated", "python-loaded" in upd.AUTOMATED)
check("has runner", callable(getattr(upd, "_run_python_loaded", None)))
check("has cadence", upd.AUTOMATED["python-loaded"].get("auto_update_interval"))
```

- [ ] **Step 2: Run and watch it fail**

Run: `python3.15 tests/update-cadence`
Expected: FAIL on the first new check.

- [ ] **Step 3: Implement the runner and wiring**

`_run_python_loaded` runs `build/build-python-loaded.sh` through `_run`, returning False on non-zero, and prints a clear "Docker/EL8 required" line on a missing Docker. Add the `python-loaded` branch in `_run_automated`. Register `tests/python-suite` in Tier 1 after `wheelhouse-closure`, and `tests/python-suite-install` in Tier 2 with `--deps auto`.

- [ ] **Step 4: Run the checks**

Run: `python3.15 tests/update-cadence && ./build/update python-loaded --dry-run`
Expected: PASS; dry-run prints the container/build commands and exits 0 without touching the payload.

- [ ] **Step 5: Commit**

```bash
git add build/update tests/run-all tests/update-cadence
git commit -m "feat(update): add python-loaded refresh and test wiring"
```

---

### Task 7: Version display, docs, manifests

**Files:**
- Modify: `loadout_main.py` (`cmd_describe` branch for `python-suite`)
- Modify: `docs/ARCHITECTURE.md`, `docs/HANDOFF.md`, `.github/copilot-instructions.md`
- Regenerate: `payload/installed-sizes.json`, `.content-manifest`

**Interfaces:**
- Consumes: lock header + stamp paths from Task 5.
- Produces: `./loadout info python-loaded` prints lock date, abi, top count, pinned count, wheelhouse size, and installed stamp when present.

- [ ] **Step 1: Add the failing output check**

Extend `tests/python-suite`: invoke `cmd_describe` with a positional shim and capture stdout; assert it contains `lock:`, `abi:`, `pins:`.

- [ ] **Step 2: Run and watch it fail**

Run: `python3.15 tests/python-suite`
Expected: FAIL, missing `lock:` line.

- [ ] **Step 3: Implement the describe branch**

For `kind == "python-suite"`, read the lock header and count pins; if `<prefix>/share/python-loaded/suite.lock.json` exists, print the installed stamp. Keep the existing generic fields.

- [ ] **Step 4: Update docs**

Add `python-suite` to the architecture kind list and artifact-field list; add a short HANDOFF section (what it is, commands, the EL8 rebuild obligation); add the kind and behavior to `.github/copilot-instructions.md` next to the python-tool description.

- [ ] **Step 5: Regenerate manifests and run gates**

Run: `python3.15 build/gen-installed-sizes && python3.15 build/gen-content-manifest && python3.15 tests/content-verify && python3.15 tests/content-manifest-shipped-set && python3.15 tests/python-suite`
Expected: all exit 0.

- [ ] **Step 6: Commit**

```bash
git add loadout_main.py tests/python-suite docs/ARCHITECTURE.md docs/HANDOFF.md .github/copilot-instructions.md payload/installed-sizes.json .content-manifest
git commit -m "docs(python-loaded): document the suite, version display, and manifests"
```

---

## Self-review notes

- Spec coverage: D1→Task 1, D2/D4→Task 5, D3→Task 2, D5/D6→Task 2 inputs, D7→Task 2 script, D8→Task 2/4, D9→Task 1, D10→Task 2/3, D11→Task 4, D12→Task 7; verification section→Tasks 2, 3, 5, 6.
- Deliberately not planned: the `chrome-headless-shell` package and `kaleido` (deferred by the user), and any CUDA work.
- Type consistency: lock header keys (`version`, `abi`, `python`) are used by Tasks 2, 3, 5, 7; stamp keys by Tasks 5 and 7.
