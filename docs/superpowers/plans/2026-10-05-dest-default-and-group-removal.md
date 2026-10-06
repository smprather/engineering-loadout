# XDG Default Root, Group Retirement, PATH Preference — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task (inline). A fresh-context review subagent runs once on the finished branch before the release.

**Goal:** Make `$XDG_DATA_HOME/loadout` the built-in install root, keep config/cache out of it, retire `@engineering-loadout`, and give users an explicit per-tool `prefer/` mechanism — so EL stops silently shadowing system binaries.

**Architecture:** Two roots are threaded through the installer: `user_home` (real HOME: config, caches, per-user nvim data) and `install_root` (shared tree: bin/lib/share, default `$XDG_DATA_HOME/loadout`). `_local_root()` maps `.local` only for HOME-mode roots. A `prefer/` shim directory (prepended to PATH) opts specific tools ahead of system copies; the shared `bin` is appended. Registry `prefer` declarations (env-tmux → tmux) plus `config.toml` `prefer`/`prefer_off` drive reconciliation.

**Tech Stack:** Python 3.14 installer (`loadout_main.py`), POSIX sh shim, bash/zsh/tcsh env configs, shell test harness (`tests/run-all`), Tier 3 EL8 container.

**Spec:** `docs/superpowers/specs/2026-10-05-dest-default-and-group-removal-design.md` (authoritative; the plan argues from it).

## Global Constraints

- Python 3.14 syntax only (PEP 758); the installer must import under the bundled interpreter.
- Non-TTY stdin aborts (`pipe is not consent`); every automated install passes `-y`.
- File writes are atomic (temp + `os.replace`); temp dirs are dot-hidden and honor `$TMPDIR`; never hardcode `/tmp`.
- No payload artifact bytes change in this plan; only `payload/packages.json` (registry) and generated manifest/completions.
- Registry or CLI change → regenerate `.content-manifest` and `envs/bash/global/completions/loadout.bash`.
- Before every commit: sync the affected Markdown docs (README, AGENTS, `.github/copilot-instructions.md`, `docs/HANDOFF.md`) per the AGENTS.md commit rule.
- Tests: `tests/run-all --fast` (T1) and `tests/run-all` (T1+T2) must pass; this change is release class C, so the Tier 3 container gate is mandatory.
- Commit style: imperative subject with scope, e.g. `feat(installer): ...`, `docs: ...`.

## Review Focus

1. **`XDG_DATA_HOME` set but relative/empty** — must fall back to `~/.local/share/loadout`; never create a relative path or install into `$PWD`.
2. **Machine with an existing legacy `~/.local` install** — `doctor` must report the legacy copies and their PATH precedence; nothing may silently treat them as the current install.
3. **Mixed selection with explicit `--dest-dir`** — env config must land in the real `$HOME`; env-only with explicit `--dest-dir` must stage (tests depend on it).
4. **Foreign files in `<root>/prefer/` or `~/.local/bin`** — never deleted or overwritten; only EL-marker shims are pruned, foreign files are reported.
5. **Read-only install root or `$HOME`** — prefer reconciliation and env writes warn and continue per area; install never dies mid-pipeline.

---

### Task 1: XDG default install root

**Files:**
- Modify: `loadout_main.py` (config/resolve block: `_loadout_config`, `_config_dest_dir`, `_resolve_home`, `_dest_dir_option`)
- Test: `tests/config-toml-dest-dir`

**Interfaces:**
- Produces: `_xdg_data_home() -> str`, `_default_install_root() -> str`, `_resolve_home(dest_dir) -> str` (precedence: `dest_dir` > config > XDG default).

- [ ] **Step 1: Extend the failing test**

Add to `tests/config-toml-dest-dir` (same `load_module(home)` style; delete `XDG_DATA_HOME` in setup unless a case sets it):

```python
# no config -> XDG default
failures += check("no config -> XDG default",
                  lm._resolve_home(None), os.path.join(home, ".local", "share", "loadout"))

# XDG_DATA_HOME absolute wins over the fallback
os.environ["XDG_DATA_HOME"] = os.path.join(tmp, "xdgdata")
failures += check("XDG_DATA_HOME honored", lm._resolve_home(None),
                  os.path.join(tmp, "xdgdata", "loadout"))

# relative XDG_DATA_HOME ignored
os.environ["XDG_DATA_HOME"] = "relative/data"
failures += check("relative XDG_DATA_HOME ignored", lm._resolve_home(None),
                  os.path.join(home, ".local", "share", "loadout"))
del os.environ["XDG_DATA_HOME"]

# config dest_dir still wins over the XDG default; explicit flag still wins over config
# config dest_dir="~" -> legacy $HOME
```

- [ ] **Step 2: Run to verify it fails**

Run: `tests/config-toml-dest-dir`
Expected: FAIL on the XDG-default cases (old default returns `$HOME`).

- [ ] **Step 3: Implement**

```python
def _xdg_data_home() -> str:
    # XDG spec: only absolute values are valid.
    val = os.environ.get("XDG_DATA_HOME", "").strip()
    if val and os.path.isabs(val):
        return val
    return os.path.join(os.path.expanduser("~"), ".local", "share")

def _default_install_root() -> str:
    return os.path.join(_xdg_data_home(), "loadout")

def _resolve_home(dest_dir):
    chosen = dest_dir or _config_dest_dir()
    return os.path.abspath(chosen) if chosen else _default_install_root()
```

Update `_dest_dir_option` help: `"Install root (default: $XDG_DATA_HOME/loadout)."`.

- [ ] **Step 4: Run test to verify it passes**

Run: `tests/config-toml-dest-dir && tests/check-installer`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add loadout_main.py tests/config-toml-dest-dir
git commit -m "feat(installer): default install root is \$XDG_DATA_HOME/loadout"
```

---

### Task 2: Prefix layout (`_local_root`, `.local` dropping)

**Files:**
- Modify: `loadout_main.py` (`_local_name` → `_local_root`; `_resolve_install_to`; every `os.path.join(home, _local_name(home), ...)` call site, ~20 sites)
- Create: `tests/dest-layout-and-env-routing`
- Modify: every test with a `local/`-level layout expectation (sweep list from `rg -l 'local/(bin|lib|share)' tests/`; known: `tests/prebuilt-binaries`, `tests/install-linux-tmp-home`, `tests/install-split-shared-envs`, `tests/install-parity-plot`, `tests/install-typescript-language-server`, `tests/install-xdesk`, `tests/optional-packages`, `tests/install-python-tool-upgrade`, `tests/install-readonly-tree`, `tests/install-nvim-deployments`, `tests/rust-offline-almalinux8`)
- Test: `tests/unit-resolver`, `tests/check-installer`

**Interfaces:**
- Produces: `_is_home_root(home) -> bool`, `_local_root(home) -> str` (`<home>/.local` in HOME mode, else `<home>`), `_resolve_install_to(raw, home) -> str` (leading `.local` component kept only in HOME mode).
- Consumes: `_resolve_home` from Task 1.

- [ ] **Step 1: Write the failing test**

Create `tests/dest-layout-and-env-routing` (Python, executable, `HOME` pointed at a temp dir before importing `loadout_main`, same loader as `tests/config-toml-dest-dir`). Cases:

```python
# HOME mode keeps .local
assert lm._local_root(home) == os.path.join(home, ".local")
assert lm._resolve_install_to("~/.local/share/helix", home) == os.path.join(home, ".local", "share", "helix")
# prefix mode drops .local (not renames it)
assert lm._local_root("/tmp/lo") == "/tmp/lo"
assert lm._resolve_install_to("~/.local/share/helix", "/tmp/lo") == "/tmp/lo/share/helix"
assert lm._resolve_install_to("~/.config/tmux", "/tmp/lo") == "/tmp/lo/.config/tmux"
# absolute passthrough
assert lm._resolve_install_to("/opt/abs", "/tmp/lo") == "/opt/abs"
```

- [ ] **Step 2: Run to verify it fails**

Run: `tests/dest-layout-and-env-routing`
Expected: FAIL — `_local_root` does not exist / prefix mode returns `local/...`.

- [ ] **Step 3: Implement and update call sites**

```python
def _is_home_root(home) -> bool:
    try:
        return os.path.realpath(home) == os.path.realpath(os.path.expanduser("~"))
    except OSError:
        return False

def _local_root(home) -> str:
    """Tree holding bin/lib/share. HOME mode keeps the dotted .local; every
    other root is a plain prefix, so the .local component is dropped."""
    return os.path.join(home, ".local") if _is_home_root(home) else home
```

`_resolve_install_to`: after splitting `parts`, if `parts[0] == ".local"` and not `_is_home_root(home)`, drop it. Replace `_local_name` call sites with `_local_root` (joins lose the component for prefix roots; f-string messages use the function).

- [ ] **Step 4: Sweep test layout expectations**

Run: `rg -l 'local/(bin|lib|share)' tests/` and update each to the direct prefix layout (`<dest>/bin`, `<dest>/share/...`). `tests/install-linux-tmp-home` moves to the default XDG root in Task 3 — in this task only its `--dest-dir` path expectations change. `tests/rust-offline-almalinux8` is Tier 3 and is verified in Task 11.

- [ ] **Step 5: Run tests**

Run: `tests/dest-layout-and-env-routing && tests/config-toml-dest-dir && tests/prebuilt-binaries && tests/run-all`
Expected: PASS (full T1+T2: the sweep has to hold before this commit).

- [ ] **Step 6: Commit**

```bash
git add loadout_main.py tests/dest-layout-and-env-routing tests/
git commit -m "feat(installer): install root is a prefix; drop .local for non-HOME roots"
```

---

### Task 3: Two-root install routing, env-only rule, snapshot semantics

**Files:**
- Modify: `loadout_main.py` (`cmd_install`, phase call sites, `cmd_snapshot`, CLI verb wiring, `_adapt_install_args`, `_mirror_shared_prefix`, `install_tealdeer_config`, `_nvim_headless_env`, `_resolve_loadout_nvim_bin`, `_resolve_nvim_stash`, nvim bundle/Lazy call sites)
- Create: `tests/env-routing-dest-dir`
- Modify: `tests/install-linux-tmp-home`, `tests/install-split-shared-envs`

**Interfaces:**
- Produces: module state `_PATHS` (`user_home`, `install_root`, `env_home`, `shared_prefix`, `staging`); `dest_dir_explicit` threaded from `ctx.get_parameter_source("dest_dir") == click.core.ParameterSource.COMMANDLINE`.
- Consumes: `_local_root`, `_resolve_install_to`.

Routing contract (spec D3): `staging = env_only and dest_explicit`; `env_home = install_root if staging else user_home`. Phase map per spec's table (backup/config/fonts/nvim-per-user → `env_home`; everything shared → `install_root`).

- [ ] **Step 1: Write the failing integration test**

`tests/env-routing-dest-dir` (bash, executable, pattern copied from `tests/install-env-*`: `env -i HOME=$test_home ... ./loadout install ... -y`). Four cases, each with a fresh temp HOME/stage:

1. default env-only: `install env-editorconfig -y` (no flag) → `$test_home/.config/editorconfig/editorconfig` and `$test_home/.editorconfig` exist; **nothing** under `$test_home/.local/share/loadout/.config`.
2. staging env-only: `install env-editorconfig --dest-dir $stage -y` → files under `$stage/.config/...` and `$stage/.editorconfig`.
3. mixed explicit: `install env-editorconfig rg --dest-dir $stage -y` → config in `$test_home`, `$stage/bin/rg` exists.
4. config.toml `dest_dir` + env-only: config ignored, note printed once (`note: env bundles always install under $HOME`), files in `$test_home`.

- [ ] **Step 2: Run to verify it fails**

Run: `tests/env-routing-dest-dir`
Expected: FAIL (case 2/4 land under the wrong root or the note is missing).

- [ ] **Step 3: Implement**

- In `cmd_install`: compute `user_home = os.path.expanduser("~")`, `resolved_kinds`, `env_only`, `staging`, `env_home`; set `_PATHS = SimpleNamespace(...)`; print the note when config `dest_dir` is ignored for an env-only install.
- Change phase calls per the spec table; `os.chdir(install_root)` and `ensure_dir(install_root)` stay. `check_prebuilt_binary_dependencies` uses `os.path.join(_local_root(install_root), "bin")`.
- `_mirror_shared_prefix`: value = `os.environ.get("LOADOUT_CFG_SHARED_PREFIX")` or `_PATHS.shared_prefix`.
- `install_tealdeer_config`: cache dir = `_PATHS.shared_prefix/share/tealdeer/cache`.
- nvim: `_resolve_loadout_nvim_bin(install_root)`, `_resolve_nvim_stash(install_root)`; `_nvim_headless_env(env_home, install_root)` sets `XDG_DATA_HOME/XDG_STATE_HOME` off `_local_root(env_home)` and `LOADOUT_CFG_SHARED_PREFIX=_PATHS.shared_prefix` when unset.
- Snapshot verbs: target = explicit `--dest-dir` (COMMANDLINE source) else `user_home`; config `dest_dir` does not move snapshots.

- [ ] **Step 4: Update the two existing tests**

- `tests/install-linux-tmp-home`: set `HOME=$test_home` on the install invocation, drop `--dest-dir` to exercise the default XDG root, update all expected paths (`$test_home/.local/share/loadout/...` for shared, `$test_home/.config` for env), and `LOADOUT_DEST_DIR` = XDG root.
- `tests/install-nvim-deployments`: shared stash/parsers under the shared root, per-user `lazy/` and state under the env HOME with the new routing.
- `tests/install-split-shared-envs`: shared tree layout `$shared_root/bin` (not `local/bin`); keep the explicit `LOADOUT_CFG_SHARED_PREFIX` baking assertions.

- [ ] **Step 5: Run tests**

Run: `tests/env-routing-dest-dir && tests/install-linux-tmp-home && tests/install-split-shared-envs && tests/run-all --fast`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add loadout_main.py tests/env-routing-dest-dir tests/install-linux-tmp-home tests/install-split-shared-envs
git commit -m "feat(installer): config never enters the install root; env-only staging rule"
```

---

### Task 4: Registry `prefer` field + env-tmux declaration

**Files:**
- Modify: `payload/packages.json` (`env-tmux` gains `"prefer": ["tmux"]`)
- Modify: `loadout_main.py` (`_validate_registry_gates`)
- Test: `tests/registry-integrity`

**Interfaces:**
- Produces: registry field `prefer: [tool, ...]` on env entries; validation that each name exists and is not `kind` env/group.
- Consumes: nothing.

- [ ] **Step 1: Extend the failing test**

In `tests/registry-integrity`, add: every entry's `prefer` is a list of strings; each name exists in the registry; each target's `kind` is not `env`/`group`; `env-tmux` declares `tmux`.

- [ ] **Step 2: Run to verify it fails**

Run: `tests/registry-integrity`
Expected: FAIL (field missing / validation absent).

- [ ] **Step 3: Implement**

Add the field to `env-tmux`; extend `_validate_registry_gates` with the same checks (it already fails loud on invalid relocation metadata).

- [ ] **Step 4: Run tests**

Run: `tests/registry-integrity && tests/check-installer`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add payload/packages.json loadout_main.py tests/registry-integrity
git commit -m "feat(registry): prefer field; env-tmux prefers the bundled tmux"
```

---

### Task 5: Prefer shim reconciliation

**Files:**
- Modify: `loadout_main.py` (new helpers + phase call after the "config files" phase)
- Create: `tests/prefer-shims`
- Test: `tests/run-all --fast`

**Interfaces:**
- Produces: `PREFER_SHIM_MARKER = "# loadout prefer shim"`, `_prefer_shim_body(root, tool) -> str`, `_active_prefer_tools(registry, env_home, config) -> set[str]`, `install_prefer_shims(install_root, env_home, registry, selected_tools=None) -> None`.
- Consumes: `_PATHS` (Task 3), registry `prefer` (Task 4), `_local_root`.

Rules: active = `((default_tools) | config.prefer) - config.prefer_off`, where a default is active when its declaring env package is selected this run or its `install_to` exists under `env_home`. Reconcile only when `_local_root(install_root)/bin` is a writable dir; missing targets warn and create nothing; pruning removes only files whose content starts with the marker, foreign files warn; remove the dir when empty.

- [ ] **Step 1: Write the failing test**

`tests/prefer-shims` (Python, loader style). Build a temp root with `bin/tmux` (executable stub printing `el-tmux`), `env_home/.config/tmux/` dir, and a registry dict `{"env-tmux": {"kind": "env", "install_to": "~/.config/tmux", "prefer": ["tmux"]}, "tmux": {"kind": "bin"}}`. Assert:

- shim created, mode `0755`, content contains the marker and `exec "<root>/bin/tmux" "$@"`; running it prints `el-tmux`;
- `env_home/.config/tmux` removed → default inactive → shim pruned;
- config `prefer_off=["tmux"]` overrides the default;
- config `prefer=["firefox"]` with no `bin/firefox` → no shim, warning;
- a foreign file `<root>/prefer/tmux` (no marker) is never deleted;
- read-only `<root>` (chmod 0555) → warning, no exception.

- [ ] **Step 2: Run to verify it fails**

Run: `tests/prefer-shims`
Expected: FAIL — `install_prefer_shims` does not exist.

- [ ] **Step 3: Implement**

Shim body (exact copy the test asserts):

```sh
#!/bin/sh
# loadout prefer shim
exec "<root>/bin/<tool>" "$@"
```

Write via temp+`os.replace` with `0o755`; ownership = marker prefix. Call the phase after "config files" and before "fonts" in `cmd_install`.

- [ ] **Step 4: Run tests**

Run: `tests/prefer-shims && tests/run-all --fast`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add loadout_main.py tests/prefer-shims
git commit -m "feat(installer): managed prefer/ shims (env-tmux default, config opt-in/out)"
```

---

### Task 6: Doctor layout, shadow and prefer audit

**Files:**
- Modify: `loadout_main.py` (`cmd_doctor`)
- Create: `tests/doctor-shadow-audit`

**Interfaces:**
- Produces: `_doctor_layout_audit(repo_dir, registry, install_root, user_home) -> int` (findings count; never affects exit status).
- Consumes: `_resolve_home`, `_local_root`, `_loadout_config`.

Reports: install root + layout mode; EL-managed names present in `~/.local/bin` while the root is not HOME-mode (legacy copies, with migration doc pointer); count of EL names that also exist in system dirs and would win from an EL dir earlier on PATH; prefer shims with missing/non-executable targets. One directory listing per dir; set intersections only.

- [ ] **Step 1: Write the failing test**

`tests/doctor-shadow-audit` (bash, executable): `HOME=$tmp ./loadout doctor` with `$tmp/.local/bin/rg` (copy of `/usr/bin/true`), `$tmp/.local/share/loadout/prefer/firefox` (shim to a nonexistent target), `$tmp/.local/share/loadout/bin/tmux` (stub). Assert exit 0 and output containing the legacy count/names, the dangling shim, and the install root. Negative control: a clean HOME with no legacy copies reports zero.

- [ ] **Step 2: Run to verify it fails**

Run: `tests/doctor-shadow-audit`
Expected: FAIL — no such output.

- [ ] **Step 3: Implement**

Call `_doctor_layout_audit(...)` from `cmd_doctor`; print a compact section. Every finding is informational; `doctor` exit stays 0.

- [ ] **Step 4: Run tests**

Run: `tests/doctor-shadow-audit && tests/check-installer && tests/run-all --fast`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add loadout_main.py tests/doctor-shadow-audit
git commit -m "feat(doctor): report install layout, legacy shadows and prefer shims"
```

---

### Task 7: Retire `@engineering-loadout`

**Files:**
- Modify: `payload/packages.json` (delete group; fix `optional` doc string)
- Modify: `loadout_main.py` (`expand_groups` retired-name error; 7 help/error strings; CLI docstring)
- Modify: `tests/unit-resolver`, `tests/check-installer`
- Regenerate: `envs/bash/global/completions/loadout.bash`

**Interfaces:**
- Produces: `_RETIRED_GROUPS: dict[str, str]` mapping `"@engineering-loadout"` to the replacement guidance.
- Consumes: registry from Task 4.

- [ ] **Step 1: Update the failing tests**

- `tests/unit-resolver`: bare-`all` error message now points at `@shared-all` / `@envs-all`; add `@engineering-loadout` → `ResolverError` whose message contains both replacements.
- `tests/check-installer` step 4: dry-run `@shared-all` (keep `REQUIRED_FULL` and `>=80`).

- [ ] **Step 2: Run to verify they fail**

Run: `tests/unit-resolver && tests/check-installer`
Expected: FAIL (group still resolves / message mentions the dead name).

- [ ] **Step 3: Implement**

Delete the entry and fix the `optional` text; in `expand_groups`, before the unknown-group warning, raise `ResolverError` for retired names. Repoint strings:

```text
@shared-all  (bundled tools)   then   @envs-all  (per-user shell configs)
```

Regenerate completions: `./loadout completion bash > envs/bash/global/completions/loadout.bash`.

- [ ] **Step 4: Run tests**

Run: `tests/unit-resolver && tests/check-installer && tests/run-all --fast`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add payload/packages.json loadout_main.py tests/unit-resolver tests/check-installer envs/bash/global/completions/loadout.bash
git commit -m "feat(registry): retire @engineering-loadout; point at @shared-all + @envs-all"
```

---

### Task 8: Shell PATH semantics and prefix fallbacks

**Files:**
- Modify: `envs/bash/global/bashrc`, `envs/zsh/global/zshrc`, `envs/tcsh/global/tcshrc`
- Test: `tests/env-shell-parity`

**Interfaces:**
- Produces: `<prefix>` fallback `${LOADOUT_CFG_SHARED_PREFIX:-$HOME/.local/share/loadout}` in all three shells; shared `bin` **appended**, `prefer/` **prepended last** (front of the prepend list, ahead of `~/.local/bin`).
- Consumes: nothing (shells), the layout from Tasks 2–3.

- [ ] **Step 1: Extend the failing parity test**

In `tests/env-shell-parity`, fabricate `$HOME/.local/share/loadout/{bin,prefer}` with dummy executables plus `$HOME/.local/bin`, run each shell non-interactively (existing PTY/harness pattern; `env -i` for isolation), and assert: `prefer` precedes `~/.local/bin` and system dirs; `<prefix>/bin` follows `/usr/bin`; no empty PATH element when the prefix is unset; the same assertions hold with a custom `LOADOUT_CFG_SHARED_PREFIX`.

- [ ] **Step 2: Run to verify it fails**

Run: `tests/env-shell-parity`
Expected: FAIL (shared bin currently prepended from the loop).

- [ ] **Step 3: Implement**

bash/zsh: remove the shared-prefix entry from the prepend loop; `path_prepend_if_dir "$_loadout_prefix/prefer"` after the loop; `path_append_if_dir "$_loadout_prefix/bin"`. tcsh: mirror with the existing `foreach` + `set path = ( ... )` pattern (append uses `$path:q` at the end). Update `_loadout_local_prefix` and the terminfo/Qt/GI/nvim-qt/gnuplot fallbacks to the new default.

- [ ] **Step 4: Run tests**

Run: `tests/env-shell-parity && tests/run-all --fast`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add envs/bash/global/bashrc envs/zsh/global/zshrc envs/tcsh/global/tcshrc tests/env-shell-parity
git commit -m "feat(env): append shared bin, prepend prefer dir, XDG-root fallbacks"
```

---

### Task 9: Documentation sync

**Files:**
- Modify: `README.md`, `docs/INSTALLATION.md`, `docs/ARCHITECTURE.md`, `AGENTS.md`, `.github/copilot-instructions.md`, `docs/HANDOFF.md`, `envs/bash/global/README.md`, `docs/BASH.md`, `envs/nvim/lua/global/paths.lua` (comment)

- [ ] **Step 1: Rewrite user-facing install guidance**

README + INSTALLATION: two-step install (`install @shared-all` then `install @envs-all`), default root, `config.toml` keys (`dest_dir`, `prefer`, `prefer_off`), PATH semantics, prefer mechanism, and a new "Migrating an existing install" section (spec D9): install shared at the new root, re-point envs, prune legacy `~/.local/bin` copies **by name** with an absolute `/usr/bin/rm`, remove legacy `~/.local` payload subtrees, open new terminals, `eval "$(starship init bash)"; hash -r`, GUI-session PATH gap note.

- [ ] **Step 2: Update architecture/agent docs**

ARCHITECTURE (two roots, phase routing table), AGENTS (default root, groups, prefer, `_local_root`, tests), copilot-instructions (one-liners), `envs/bash/global/README.md` and `docs/BASH.md` (PATH order), `paths.lua` comment.

- [ ] **Step 3: New HANDOFF entry**

Add the current-handoff section for this change (branch state, what landed, gates, follow-ups).

- [ ] **Step 4: Sweep for stale references**

Run: `rg -n "@engineering-loadout|~/.local/bin|\\$HOME/\\.local[^/]" README.md docs/ARCHITECTURE.md docs/INSTALLATION.md AGENTS.md .github/copilot-instructions.md envs/bash/global/README.md docs/BASH.md`
Expected: only historical records (HANDOFF history, old specs, the archived proposal) keep the name.

- [ ] **Step 5: Commit**

```bash
git add README.md docs/INSTALLATION.md docs/ARCHITECTURE.md AGENTS.md .github/copilot-instructions.md docs/HANDOFF.md envs/bash/global/README.md docs/BASH.md envs/nvim/lua/global/paths.lua
git commit -m "docs: XDG default root, group retirement, prefer mechanism, migration"
```

---

### Task 10: Payload chain and T1/T2 gates

**Files:**
- Regenerate: `.content-manifest`
- Verify: `payload/installed-sizes.json` unchanged

- [ ] **Step 1: Regenerate the manifest and check sizes**

```bash
python3.14 build/gen-installed-sizes --check
python3.14 build/gen-content-manifest
git diff --stat .content-manifest
```

Expected: manifest updated for `payload/packages.json` only; sizes check clean.

- [ ] **Step 2: Run T1 + T2**

Run: `tests/run-all --fast && tests/run-all`
Expected: all green.

- [ ] **Step 3: Commit generated files**

```bash
git add .content-manifest
git commit -m "chore(payload): regenerate manifest after registry change"
```

---

### Task 11: Tier 3 container gate (class C)

- [ ] **Step 1: Confirm the container image is current**

Run: `build/build-shell true`
Expected: container starts (no rebuild needed unless `build/Dockerfile` changed).

- [ ] **Step 2: Run the full prebuilt smoke against EL8, network off**

Run: `tests/prebuilt-binaries-almalinux8 --full --network=none`
(invoke per the test's usage header; it cold-bootstraps Python inside the container)
Expected: PASS. This proves installer layout changes against the glibc floor and with no fetch fallback.

- [ ] **Step 3: Record the result in HANDOFF**

Update the Task 9 HANDOFF entry with the gate results (test names, pass/fail).

---

### Task 12: Class C release

- [ ] **Step 1: Follow `docs/RELEASE.md` from §0**

Settle `gh auth status` and the signing agent at `~/.ssh/loadout-agent.sock` **before** any slow work. Class C requires: full currency sweep (`./build/update` per cadence/`--currency`), security/assurance re-pin (`build/assurance-check`, vuln baseline), the mandatory post-payload chain, doc sync, Tier 3, then `./build/release` gates (scan, smoke, checksums + SBOM, secret scan, vuln scan), tag, publish.

- [ ] **Step 2: Post-publish verification**

Re-download the release assets, verify `sha256sums.txt` against the signed tag, and run the documented new-user install from the release (not the working tree).

- [ ] **Step 3: Final HANDOFF update + commit**

Record the release tag, verification evidence, and any follow-ups (uninstall spec remains next).

---

## Self-review notes

- Spec coverage: D1→T1, D2→T2, D3→T3, D4→T8, D5→T4+T5, D6→T7, D7→T9, D8→T6, D9→T9, D10→T10–T12.
- Review Focus mapping: 1→T1, 2→T6, 3→T3, 4→T5, 5→T5 (RO case) + T11 (container).
- Type consistency: `_local_root`, `_PATHS`, `PREFER_SHIM_MARKER`, `_active_prefer_tools`, `install_prefer_shims`, `_doctor_layout_audit`, `_RETIRED_GROUPS` are defined once and referenced by the same names in later tasks.
