# Code and Doc Review (2026-10-27) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix every defect found in the 2026-10-27 top-to-bottom code and doc review, and add the gates that keep code and docs in sync from now on.

**Architecture:** The findings register below is the spec. Each task fixes one subsystem's findings test-first, updates the docs that describe that subsystem in the same commit (AGENTS.md Commit Rule), and registers its new test in `tests/run-all`. Phase A is security, Phase B is correctness (three findings reproduced live), Phase C is tooling and docs.

**Tech Stack:** Python 3.15 (bundled portable-python, PEP 758 forms), POSIX sh / bash / zsh / tcsh, Lua (Neovim 0.12), vendored click/rich-click, git, `ssh-keygen -Y`.

**Spec:** This document's "Findings register". There is no separate design doc. Each task names the finding IDs it closes.

## Global Constraints

- Interpreter: run every Python test with the bundled interpreter, `PY=.loadout-bootstrap/bin/python3.15` (or the installed `<prefix>/bin/python3.15`). Never run a pre-3.14 interpreter or analyzer over `loadout_main.py`.
- PEP 758: the bare `except A, B:` form is canonical. Parentheses only with `as`. `ruff format` (py314) must stay clean: `ruff format --check --force-exclude` and `ruff check`.
- Indentation: spaces only, never tabs; 4 spaces in Python/sh/Lua, 2 in Markdown/YAML. Makefile recipes are the only exception.
- Temp files: honor `TMPDIR`; installer-internal temps are dot-hidden (`.loadout-*`); never hardcode `/tmp` except where a protocol requires it.
- Automation passes `-y` to `./loadout install` (non-TTY stdin aborts). Integration tests use `env -i` with a temp `HOME`.
- Payload changes (Task 1 touches `payload/pending-daemon/`) go through the regen chain in order: `build/gen-installed-sizes` then `build/gen-content-manifest`, then commit both with the change.
- Tier wiring: new fast tests register in the Tier 1 `run_test` block of `tests/run-all`; new install tests go in the Tier 2 list. `tests/run-all` records every test's runtime in `~/.cache/engineering-loadout/ci-runtimes.tsv`, which satisfies the AGENTS.md Timing Requirement. Run gates through it, not ad hoc.
- Docs: before every commit, run the AGENTS.md Commit Rule `rg` sweep over README.md, AGENTS.md, `.github/copilot-instructions.md`, docs/HANDOFF.md and the subsystem's doc, and fix any drift the change causes.
- Terminology: "EL8/EL9" for Red Hat releases; bare "EL" means the loadout. A disabled package is "out of service" or "disabled", never "offline" or "online".
- Commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Branch off `main` before the first commit.

## Review Focus

1. **A hostile co-tenant pre-creates a predictable path** (`/tmp/loadout-pending-<user>`, `/dev/shm/<user>`, `/dev/shm/<uid>`). Expected: loadout refuses to use it, says so, and never executes or writes through it. Tests: Task 1 (`test_stage_pending_refuses_insecure_dir`, `test_daemon_refuses_insecure_dir`) and Task 2 (`hostile-dir` cases). A foreign *owner* cannot be simulated without root, so Task 1 also has a manual two-account check.
2. **Reinstall or upgrade while the tools are running** (a GUI holding mesa/firefox libs, nvim holding parsers). Expected: running processes keep their old inode and never SIGBUS. Test: Task 8 `test_extract_mapped_reader_survives`.
3. **Interrupted operations** (Ctrl-C, ENOSPC, kill) mid-extract or mid-bootstrap. Expected: no partial tree is ever accepted as complete. Tests: Task 8 `test_extract_unsafe_member_leaves_no_stage`, Task 12 `interrupted-bootstrap` case.
4. **An install root containing spaces, `$`, quotes or backticks.** Expected: generated wrappers and shims still exec the right target. Test: Task 16 `test_generated_wrappers_quote_paths`.
5. **A minimal environment**: `env -i`, no `USER`/`LOGNAME`, uid absent from `/etc/passwd` (containers). Expected: the installer starts. Test: Task 1 `test_tmp_user_fallback`.

---

## Findings register

Severity: **S1** = cross-user code execution or data loss; **S2** = wrong behavior a user will hit; **S3** = edge case or latent defect; **S4** = hygiene, docs or performance. "Repro" means reproduced live in a scratch HOME during this review. "Read" means established by reading the code. Line numbers are at `2e8332d`.

### Security

| ID | Sev | Where | Finding | Basis |
|---|---|---|---|---|
| SEC-1 | S1 | `loadout_main.py:1882,1946-1951,2032-2069`; `payload/pending-daemon/loadout-pending-daemon:40-45,185-208` | `${TMPDIR:-/tmp}/loadout-pending-<user>` has a predictable name and is never checked for owner, mode or symlink. A co-tenant who pre-creates it controls `pending.json`, so the daemon copies attacker bytes to attacker-chosen `dest` paths as the victim. They also control `daemon.py`, which the installer copies in and then executes with `sys.executable`. | Read. The only `st_uid` check in the file is in `cmd_clean`. |
| SEC-2 | S1 | `envs/bash/global/bashrc:476-493` | eza is copied to `/dev/shm/$USER/bin/eza` and run by every `ls`. `mkdir -p` accepts a pre-existing directory owned by someone else, and as the directory owner that person can swap the binary under the sticky bit. | Read |
| SEC-3 | S1 | `bashrc:116`, `zsh/global/zshrc:93`, `tcsh/global/tcshrc:143` | `PYTHONPYCACHEPREFIX=/dev/shm/$USER/pycache`. An attacker-owned prefix lets them plant `.pyc` files whose headers match the source mtime and size, so every Python the user runs (stdlib included) imports attacker code. | Read |
| SEC-4 | S2 | `bashrc:108-111`, `zshrc:159`, `tcshrc:226-231`, `tcsh/global/helpers/seed-history:36` | The `XDG_RUNTIME_DIR` fallback `/dev/shm/<uid>` is created with umask permissions and no owner check. Per-PID bash history (it may hold secrets) becomes readable and injectable, and the `.loadout-net` online-verdict cache becomes attacker-controlled. | Read |
| SEC-5 | S2 | `nvim/lua/global/config.lua:134-146`, `nvim/lsp/lua_ls.lua:24-31` | The swap dir, `vitmp` and lua_ls logs go to `$TMPDIR/<user>`, `/dev/shm/<user>` or `/tmp/<user>` with no ownership check, so buffer contents can leak into a co-tenant's directory. | Read |
| SEC-6 | S3 | `loadout_main.py:1342-1355` | The run log `${TMPDIR}/loadout.<user>.log` is opened `"a"` with no `O_NOFOLLOW` and no owner check. `fs.protected_symlinks` mitigates the symlink case on most hosts, but an attacker-owned regular file still receives the install log. | Read |
| SEC-7 | S2 | `loadout_main.py:2322-2332` (portable-python), `2686` (typelibs), `3060-3107` (uv_tool wheels: `--find-links` with no hashes), `4205-4220` (Tree-sitter parsers, native code loaded into nvim), `4245-4256` (vendor), `2036` (daemon script) | Content verification covers only files that pass through `_Bz2Store.resolve`. The interpreter archive, wheels, parsers, typelibs, vendored Lua and the daemon script are installed unverified. Every `payload/` file is in `.content-manifest` (4,458 entries), so verifying them would not trip on unlisted files. | Read |
| SEC-8 | S3 | `loadout_main.py:871,7115-7118` | Verification fails open: a missing `.content-manifest` only prints a warning, and the install proceeds unverified. | Read |
| SEC-9 | S2 | `build/release:1422`; `tools/fetch-stash:8-11,156-186`; `docs/SECURITY.md:149-150,223`; AGENTS.md "Trust chain" | The documented chain "signed tag -> sha256sums.txt -> stash" is not implemented. The tag message is just the tag name, `sha256sums.txt` is an unsigned release asset, and `fetch-stash` trusts whatever sums file it downloads or is handed. The SBOM claim ("the signed tag binds it") is likewise false. In `--from-file` mode a mismatch prints "The file is being deleted", but the file is (correctly) not deleted. | Read |
| SEC-10 | S4 | `config.lua:71-81` (`string.format` of env-supplied host and timeout into `vim.fn.system`), `config.lua:106` (Lua `%q` used as shell quoting); `loadout_main.py:2932-2934,5033,7251` | Shell strings are built from paths and env values without shell quoting. Today this is self-injection only, but the wrappers break on install roots containing `"`, `$` or backticks. | Read |

### Correctness

| ID | Sev | Where | Finding | Basis |
|---|---|---|---|---|
| COR-1 | S2 | `loadout_main.py:7837-7851,7878-7892` | `reinstall` and `upgrade` reach `cli_install` through `ctx.invoke`, which loses the parameter source. An explicit `--dest-dir` on an env-only selection is treated as config-supplied: the installer prints "ignoring dest_dir" and writes into the real `$HOME`. | **Repro** (`reinstall env-editorconfig --dest-dir X` wrote to HOME; `install` staged to X) |
| COR-2 | S2 | `loadout_main.py:1427-1432` (`remove_path`), `4735-4739`, `1555-1563` | `remove_path` uses a plain `rmtree`, which cannot delete inside the sealed 0555 managed trees. `snapshot restore` dies with a `PermissionError` traceback. `sync_dir(delete=True)` fails the same way when upstream removes a subdirectory of a sealed tree. | **Repro** (install env-nvim, snapshot create, snapshot restore: traceback) |
| COR-3 | S2 | `loadout_main.py:6486-6492` | `doctor` crashes with `ValueError: list.index(x)` when a newer system copy of a payload bin is a symlink into a directory that is not on PATH (alternatives, `/usr/local/bin -> /opt/...`). `sys_dir` is taken from the resolved target, not from the PATH directory. | **Repro** (`_system_newer_rows` fixture) |
| COR-4 | S2 | `loadout_main.py:3592-3624,3939,4026,4084,4152,4211-4219,2686,4164` | Runtime archives (tarfile `makefile` opens `"wb"`), Tree-sitter parsers, typelibs and the nvim-qt shim overwrite files **in place**. On upgrade, a running process with a mapped library SIGBUSes or runs mixed old/new pages, and a running executable fails with ETXTBSY. Only `write_bz2_atomic` follows the AGENTS.md atomicity rule. | Read (confirmed `tarfile.makefile` opens `"wb"` in the bundled stdlib) |
| COR-5 | S2 | `loadout_main.py:1242,3552,8192-8207` | `run_install_step` catches only `InstallRefused`, `KeyboardInterrupt`, `OSError` and `CalledProcessError`. `RuntimeError` (unsafe tar member), `tarfile.TarError`, `zipfile.BadZipFile` and `ValueError` abort the whole install with a traceback and no summary. `ContentVerificationError` is reported, but earlier phases' results are never printed and the backup is left uncompressed. | Read |
| COR-6 | S2 | `loadout_main.py:3906-3986` | One bad runtime archive aborts every runtime archive after it; there is no per-package isolation. | Read |
| COR-7 | S3 | `loadout_main.py:4031-4035` | Vim runtime reports success falsely: a missing sentinel only warns, so the summary says "done". | Read |
| COR-8 | S3 | `loadout_main.py:4710-4746,4823-4848` | Backup and restore use different target lists. Backup omits `.config/tcsh`, the zsh entrypoints and `.config/zsh`, `.config/st`, `.config/bash/profile`, and generic env targets (wezterm, btop). Restore removes a third set (missing `.tcshrc`, helix, pip), then `cp -rPp` collides with existing symlinks. | Read |
| COR-9 | S3 | `loadout_main.py:7389-7398` | `snapshot create` with nothing to back up still writes an empty archive; the "nothing to snapshot" branch is unreachable. | Read |
| COR-10 | S3 | `loadout_main.py:4552-4576` | A failed plugin clone or pin checkout leaves `lazy/<plugin>` behind. The next install counts it as "kept" and reports OK forever, with the plugin unpinned. | Read |
| COR-11 | S3 | `loadout_main.py:4619-4625,4656-4662`; `run()` at `1393-1415` | Headless `Lazy! sync`/`restore` has no timeout, so the documented partial-clone hang class hangs the installer indefinitely. | Read |
| COR-12 | S2 | `envs/bash/global/bashrc:65-69` | The non-interactive early return runs `unset ${!_@}`, which also removes **exported** variables such as Environment Modules' `_LMFILES_` and `_JAVA_OPTIONS`. This happens in every `ssh host cmd` and `bash -l` job. `unset_bashrc_local_vars` already skips exported variables. | Read |
| COR-13 | S3 | `envs/bash/global/bashrc:497-501` | The fallback `ls()` (`LOADOUT_CFG_PREFERRED_LS=ls`) leaves `$option_g $option_h $option_a` unescaped inside the eval'd double-quoted body. They expand to nothing at definition time, so `list_all`, `human_readable` and `show_group` never apply. | Read |
| COR-14 | S4 | `envs/bash/global/bashrc:562` | The ERR trap's file branch runs `cd` inside `( ... )`. It is dead code. | Read |
| COR-15 | S3 | `loadout:31-34,46` | The shim probes only `~/.local/bin/python3.15`. Default installs put the interpreter under `~/.local/share/loadout/bin`, so the installed interpreter is never used, and the error message points users at the legacy path. AGENTS.md, `docs/ARCHITECTURE.md:206` and `docs/PYTHON-CA-TLS.md:69` describe the intended `<prefix>` probe. | Read |
| COR-16 | S3 | `loadout:64-77` | The cold bootstrap is not atomic. An interrupted `bzip2 \| tar` (no pipefail) leaves a partial `.loadout-bootstrap/` that a later run accepts once `bin/python3.15` exists. `$HOME` is used at `:46` under `set -u`. The cache is never cleaned on a minor-version bump: today it holds both 3.14 and 3.15 trees. | Read |
| COR-17 | S4 | `loadout_main.py:519-592,645-649` | Latent: the hard `depends` of recommended packages are never walked, and the walkers check only explicit `disabled`, not the cascade. No current registry entry triggers it (verified: no recommended package has `depends`). | Read |
| COR-18 | S3 | `loadout_main.py:6277` | `info python-loaded` looks for its stamp at the HOME-mode path, so it reports "not installed" for default (XDG root) installs. | Read |
| COR-19 | S4 | `loadout_main.py:1440-1441` | `lns()` calls `sys.exit(1)` mid-install, so no summary is printed and the backup is left uncompressed. | Read |

### Robustness and performance

| ID | Sev | Where | Finding |
|---|---|---|---|
| ROB-1 | S3 | `loadout_main.py:3452-3465` | Every fonts reinstall moves the whole fonts dir to `fonts.bak[.N]`: about 2 GB per run, unbounded, and it also moves the user's own fonts out of fontconfig's path. This works against the quota goal AGENTS.md states. |
| ROB-2 | S3 | `loadout_main.py:918-928,949-954` | Chunked artifacts are rejoined into `TMPDIR` and held until process exit, so every rejoined runtime and font zip accumulates on tmpfs during an `@shared-all` install. |
| ROB-3 | S4 | `loadout_main.py:3153-3181,7230` | The `ldd` sweep runs over every binary in the tree even on env-only installs (slow, and noisy about tools installed earlier), and it is not wrapped by `run_install_step`. |
| ROB-4 | S4 | `loadout_main.py:2764,2807,3049`; `loadout`; `hooks/pre-commit:52,105` | The Python minor version is hardcoded in five places, while `_suite_python_bin` already explains why it uses `bin/python3`. The next minor bump silently FAILs the Python-tools phase. |
| ROB-5 | S4 | `loadout_main.py:1342` | `getpass.getuser()` at import time raises `OSError` when there is no `USER`/`LOGNAME` and the uid is not in passwd, so the installer cannot start. |
| ROB-6 | S4 | install phases | Every reinstall re-extracts every runtime archive and re-hashes the payload. Noted only; no task. |

### Tooling

| ID | Sev | Where | Finding |
|---|---|---|---|
| TOOL-1 | S2 | `hooks/pre-commit:15-25` | Step 1 runs `find .` over the whole worktree, including ignored directories, and deletes every nested `.git` (destroying local clones kept in ignored dirs). It then runs `git add -A`, which sweeps every untracked file into the commit. Today that would commit the untracked `.repowise/`. |
| TOOL-2 | S3 | `hooks/pre-commit:151-158` | Step 4 calls `strip-all-elf-binaries` without step 2's python3.15 PATH fix and with `2>/dev/null \|\| true`. A shebang failure is silent, and a file over 40 MiB is committed unchunked. |
| TOOL-3 | S4 | `hooks/pre-commit:103-115`; `hooks/README.md` | Step 3 hardcodes `/tmp/py314-check-err` and labels the check "3.14". The header lists 3 steps where there are 4, and the README documents only step 1. |
| TOOL-4 | S4 | `build/iverilog/iverilog-vpi:82-86` | A shellcheck directive sits between `\|\|` and its continuation, which makes the file unparseable for shellcheck. |
| TOOL-5 | S4 | `build/release` reuse path | The `gh release edit --draft=false` exit status is ignored. This is mitigated by `_verify_published_stash`; noted only. |
| TOOL-6 | S3 | `build/build-bash.sh:28`, `build/build-expect.sh:40`, `build/build-gtkwave.sh:66` | These hard-code `PATCHELF="${HOME}/.local/bin/patchelf"`. Each is `set -eu`, so it fails loudly, but it fails everywhere: the host no longer populates `~/.local/bin`, and `build/build-shell` sets `HOME=/tmp` and `LOADOUT_PATCHELF=/usr/bin/patchelf`, which these scripts ignore. Fix: follow `build-fio.sh` (`LOADOUT_PATCHELF`, then `command -v patchelf`). Added 2026-10-27 after the node RUNPATH regression, which had the same root cause in `build/import-nodejs` (fixed in `74ed71f`). This needs one extra Phase C task (or an addition to Task 16) when the plan runs. |

### Docs (the user asked that everything be in sync)

| ID | Where | Drift |
|---|---|---|
| DOC-1 | `loadout_main.py:7783-7791` (`install --help`); `tools/refresh-stash:28,110` | They still say `/foo/bar/local` and `<shared>/local/...`. The un-dotted `local/` level is gone. |
| DOC-2 | `README.md:462` (`pip3.14`); AGENTS.md Python-tools paragraph (`pip3.14 download ... --python-version 3.14`, "all 13 tools"; the registry has 14 python-tools); `build/ADDING_BINARIES.md:806-835` | The generic wheel recipe still targets 3.14/cp314. Following it fetches wheels the 3.15 interpreter cannot install. |
| DOC-3 | AGENTS.md:80 | It says "15 per-user config-source dirs"; `envs/` has 14. |
| DOC-4 | AGENTS.md Repository Map test list | 11 tests are missing: env-bash-profile-shim, env-managed-readonly, install-env-bash, install-env-xfce4-terminal, install-nvim-shared-stash, payload-interpreter-abi, prompt-no-rc, python-suite, python-suite-install, test-cleanup, wheelhouse-closure. |
| DOC-5 | AGENTS.md kinds list; `_load_tool_registry` docstring; `.github/copilot-instructions.md:93-94`; `docs/ARCHITECTURE.md`; `docs/INSTALLATION.md` | `kind: python-suite` (used by python-loaded) is undocumented, and `@all` and `disabled` are missing from copilot-instructions, ARCHITECTURE and INSTALLATION. |
| DOC-6 | `.github/copilot-instructions.md:151` and the whole file | It places the resolver "in `loadout`" (the sh shim). The file is a 645-line second copy of AGENTS.md content, so it drifts on every change. |
| DOC-7 | AGENTS.md cold start, `docs/ARCHITECTURE.md:206`, `docs/PYTHON-CA-TLS.md:69` | The shim order they describe is right; the code is stale (COR-15). They will be correct once Task 12 lands. |
| DOC-8 | `docs/SECURITY.md:149-150,223`, AGENTS.md trust chain | These overclaim the signing (SEC-9). |
| DOC-9 | `loadout_main.py:406,441,512-513,561,3574,6350-6352,6782` | Stale internal docs: the `expand_groups` table says "@envs env-bash only"; the follow-symlinks docstring says the default is `no` (it is `auto`); doctor says "shadows ... via ~/.local/bin"; disabled-package messages say "offline/online". |
| DOC-10 | repo root, `docs/` | `enhancement-request-permissions-management.md` (fielded and implemented 2026-09-04) breaks the "root kept minimal" rule. `docs/SESSION-HANDOFF-2026-10-02.md` is superseded. `docs/HANDOFF.md` (6,803 lines) is the mandated cold-start document. |
| DOC-11 | `hooks/README.md` | See TOOL-3. |

### Known debt (already recorded elsewhere; tracked, no new task)

- DEBT-1: 32 cp314 wheels, about 730 MB (including both `pyosys` 0.69 and 0.70, duckdb, klayout, sqlalchemy, orjson, zstandard), cannot install under the cp315 interpreter. Recorded in HANDOFF 2026-10-11 (1). Next step when taken up: make `tests/wheelhouse-closure` fail on any wheel whose ABI tag is not the interpreter's unless it is listed in an accepted-debt table with a reason, then prune the duplicate pyosys. This is a payload change, so it follows the regen chain and a release.
- DEBT-2: The repo-wide NEEDED-closure auditor and the GUI-toolkit ceiling (AGENTS.md "Known gap").

### Coverage of this review

- Read line by line: `loadout`, all 8,237 lines of `loadout_main.py`, `tools/fetch-stash`, `hooks/pre-commit`, `envs/bash/bashrc`, `envs/bash/global/bashrc`.
- Read in targeted sections: `envs/bash/functions.sh`, the pending daemon, `tools/refresh-stash`, `envs/nvim/lua/global/config.lua`, the tmux popout scripts, and the publish path of `build/release`.
- Lint only: all 138 shell scripts under `build/`, `tests/` and `tools/` (`shellcheck -S warning`; one parse error, TOOL-4, plus false positives), and the Python tooling (`ruff --select F,E9,B`: clean).
- Docs: mechanical cross-checks across all 47 first-party `.md` files, plus close reads of README, AGENTS.md, copilot-instructions, ARCHITECTURE, INSTALLATION, SECURITY, PYTHON-CA-TLS, the generic recipes in ADDING_BINARIES and hooks/README.
- Not reviewed: vendored code (`installer_vendor/`, nvim/vim/tmux plugins, bash-completion, grc, icecream), the upstream-copied `envs/nvim/lsp/*.lua`, `build-*.sh` logic beyond lint, test logic beyond lint, and the contents of historical records (HANDOFF entries, specs, plans), which were checked only for stale references presented as current.

### Decisions to confirm before execution

- **D-A (Task 4):** Bind `sha256sums.txt` into the signed tag annotation and make `fetch-stash` verify it (recommended), or limit the fix to correcting the docs so they say trust is GitHub-over-HTTPS.
- **D-B (Task 13):** Stop moving the fonts dir aside on reinstall and replace loadout's own font files atomically in place (recommended), or keep one rolling `fonts.bak`.
- **D-C (Task 17):** Slim `.github/copilot-instructions.md` to a pointer stub of 80 lines or fewer (recommended), or keep the full copy and let `tests/docs-sync` police it.
- **D-D (Task 2):** Keep the eza copy in `/dev/shm`, but only behind the private-dir check (recommended), or delete the copy entirely.

---

## Phase A: Security

### Task 1: Private temp state for the installer and the pending-ops daemon

Closes SEC-1, SEC-6, ROB-5.

**Files:**
- Modify: `loadout_main.py:1340-1375` (`_TMP_USER`, `_RUN_LOG_FIXED_PATH`, `_setup_run_log`), `:1882-1908` (`_PENDING_DIR`, `_pending_lock`), `:1941-2075` (`stage_pending_ops`), `:7450-7519` (`cmd_clean`)
- Modify: `payload/pending-daemon/loadout-pending-daemon:30-45` and `main()`
- Create: `tests/unit-private-state` (python, Tier 1; register after `unit-resolver`)
- Regenerate: `payload/installed-sizes.json`, `.content-manifest` (the daemon is payload)
- Docs: AGENTS.md "Atomicity" paragraph (pending dir contract), `docs/SECURITY.md` (new "Local multi-user hardening" subsection)

**Interfaces:**
- Produces: `_tmp_user() -> str` returns `getpass.getuser()`, falling back to `str(os.getuid())` on `OSError`/`KeyError`.
- Produces: `_secure_private_dir(path: str) -> bool` creates the directory with mode 0o700 when absent. It returns True only if `lstat` shows a real directory (not a symlink) owned by `os.getuid()` with no group or other **write** bit. When the directory is ours and merely group/other readable it is tightened to 0o700. Otherwise it warns and returns False.
- Produces: `_open_private_append(path: str) -> io.TextIOWrapper | None` opens with `os.open(path, O_WRONLY|O_APPEND|O_CREAT|O_NOFOLLOW|O_CLOEXEC, 0o600)` and returns None when `fstat().st_uid != os.getuid()` or the open fails.
- Produces (daemon): `secure_pending_dir() -> bool` uses the same rules. `main()` exits 1 before reading `pending.json` when it returns False.
- Consumed by: Task 3 (daemon script verification happens inside `stage_pending_ops`).

- [ ] **Step 1: Write the failing tests** in `tests/unit-private-state`, loading the module the way `tests/unit-resolver` does (`SourceFileLoader`) and the daemon from `PENDING_DAEMON_PATH`. All of them run under a `tempfile.TemporaryDirectory()`.

```python
def test_private_dir_creates_0700():      # absent -> True, stat.S_IMODE == 0o700
def test_private_dir_rejects_symlink():   # symlink -> real dir: False, link untouched
def test_private_dir_rejects_group_other_writable():  # own dir chmod 0o777: False, mode unchanged
def test_private_dir_tightens_readable():  # own dir 0o755: True, mode now 0o700
def test_stage_pending_refuses_insecure_dir():
    # monkeypatch lm._PENDING_DIR to a 0o777 dir and lm.subprocess.Popen to raise
    # AssertionError; stage_pending_ops({"tmux"}, fixture_bin_dir, dest, fixture_repo)
    # -> returns None, no pending.json, no daemon.py written
def test_run_log_nofollow():               # path is a symlink -> _open_private_append is None; target size unchanged
def test_tmp_user_fallback():              # getpass.getuser raises OSError -> _tmp_user() == str(os.getuid())
def test_daemon_refuses_insecure_dir():    # daemon module with PENDING_DIR -> 0o777 dir: secure_pending_dir() is False
```

- [ ] **Step 2: Run them and confirm they fail.**
  Run: `$PY tests/unit-private-state`. Expected: FAIL (`AttributeError: ... _secure_private_dir`).

- [ ] **Step 3: Implement** the four functions above. Compute `_TMP_USER = _tmp_user()`. Route every `os.makedirs(_PENDING_DIR)` and the daemon's directory creation through the private-dir check. Open the run log through `_open_private_append`. When the check fails, `stage_pending_ops` warns `pending-ops directory <path> is not private (owner/mode/symlink); deferred binaries were not staged` and returns. `cmd_clean --pending` also refuses an insecure dir rather than `rmtree` someone else's tree.

- [ ] **Step 4: Run the tests and confirm they pass.**
  Run: `$PY tests/unit-private-state && $PY tests/unit-resolver`. Expected: both exit 0.

- [ ] **Step 5: Manual two-account check** (cannot be automated without root). As user B: `mkdir -m 777 /tmp/loadout-pending-<A>`. As user A: run a reinstall while tmux is running from the install root. Expected: the warning above, no `daemon.py` under B's directory, exit status unchanged. Record the result in HANDOFF.

- [ ] **Step 6: Regenerate and gate.**
  Run: `$PY build/gen-installed-sizes && $PY build/gen-content-manifest && tests/run-all --fast`. Expected: Tier 1 green.

- [ ] **Step 7: Commit.**

```bash
git add loadout_main.py payload/pending-daemon/loadout-pending-daemon payload/installed-sizes.json .content-manifest tests/unit-private-state tests/run-all AGENTS.md docs/SECURITY.md docs/HANDOFF.md
git commit -m "fix(security): refuse non-private pending-ops and run-log temp state"
```

### Task 2: Private runtime dirs in bash, zsh, tcsh and nvim

Closes SEC-2, SEC-3, SEC-4, SEC-5. Assumes decision D-D (keep the eza copy behind the check).

**Files:**
- Modify: `envs/bash/functions.sh` (new function, shared with zsh), `envs/bash/global/config.sh` and `envs/tcsh/global/config.csh` (new config var), `envs/bash/global/bashrc:108-117,476-493`, `envs/zsh/global/zshrc:93,159`, `envs/tcsh/global/tcshrc:143,226-231`, `envs/tcsh/global/helpers/seed-history:36`, `envs/nvim/lua/global/paths.lua`, `envs/nvim/lua/global/config.lua:132-147`, `envs/nvim/lsp/lua_ls.lua:13-31`
- Create: `envs/tcsh/global/helpers/private-dir` (POSIX sh, executable)
- Create: `tests/env-private-dirs` (sh, Tier 2)
- Docs: `envs/bash/global/README.md`, `envs/tcsh/README.md`, `envs/zsh/README.md`, `docs/BASH.md` (new var), AGENTS.md "Config vars" list

**Interfaces:**
- Produces: config var `LOADOUT_CFG_SHM_DIR`, default `/dev/shm`. It must be defined in BOTH `config.sh` and `config.csh`, or `tests/env-shell-parity` fails on a dead switch. It exists so tests can point the scratch root somewhere other than the real `/dev/shm`.
- Produces: `loadout_private_dir DIR` (bash and zsh, in `functions.sh`, POSIX test syntax only). It creates the directory with mode 700 in a `umask 077` subshell, then succeeds only if `[ -d DIR ] && [ ! -L DIR ] && [ -O DIR ]` and the octal mode (`stat -c %a`) has no group or other write bit. A merely group/other-readable directory is tightened to 700. It prints nothing.
- Produces: `helpers/private-dir DIR` (tcsh calls it as `sh "$TCSH_CONFIG_ROOT_DIR/global/helpers/private-dir" "$d"`). Same rules and exit status.
- Produces: `require("global.paths").private_dir(path) -> string|nil` uses `vim.uv.fs_lstat`, `vim.fn.mkdir(path, "p", tonumber("700", 8))` and `vim.uv.getuid()`, with the same rules.
- Fallbacks when the check fails: `XDG_RUNTIME_DIR` falls back to `$HOME/.cache/loadout/runtime` (made private); `PYTHONPYCACHEPREFIX` stays unset; `ls` runs eza from PATH; the nvim swap dir becomes `stdpath("state") .. "/swap"` and lua_ls logs go to `stdpath("log")`.

- [ ] **Step 1: Write the failing test** `tests/env-private-dirs`. It installs `@envs env-zsh env-nvim` into a temp HOME (`env -i ... ./loadout install ... --dest-dir "$H" --no-backup -y`). For each shell it sets `LOADOUT_CFG_SHM_DIR=$T/shm` with `XDG_RUNTIME_DIR` unset and runs three cases:

```sh
# hostile-dir:  mkdir -m 777 "$T/shm/$USER" "$T/shm/$USER/bin"; plant bin/eza that touches "$T/pwned"
#   bash (PTY via script -qfc 'bash -i -c "ls >/dev/null; env"'): [ ! -e "$T/pwned" ]
#   all shells: PYTHONPYCACHEPREFIX unset or not under "$T/shm"; XDG_RUNTIME_DIR not under "$T/shm"
# symlink-dir:  ln -s "$T/elsewhere" "$T/shm/$USER" -> same assertions; "$T/elsewhere" stays empty
# clean:        empty "$T/shm" -> stat -c %a "$T/shm/$USER" == 700; PYTHONPYCACHEPREFIX == "$T/shm/$USER/pycache"
# nvim:         nvim --headless +'lua io.write(vim.g.cfg_swap_dir)' +qa under hostile-dir -> output not under "$T/shm"
```

  Use the PTY rules from AGENTS.md "Shell-config test harness traps": a real PTY, `env -i`, and scanning stdout for shell error vocabulary.

- [ ] **Step 2: Run it and confirm it fails.**
  Run: `tests/env-private-dirs`. Expected: FAIL on hostile-dir (`$T/pwned` exists).

- [ ] **Step 3: Implement** the helpers and switch every `/dev/shm` and `/tmp/<user>` use listed under Files to `private_dir` with the fallbacks above. Keep startup silent.

- [ ] **Step 4: Run the tests and confirm they pass.**
  Run: `tests/env-private-dirs && $PY tests/env-shell-parity && tests/shell-typeahead && $PY tests/prompt-no-rc`. Expected: all exit 0.

- [ ] **Step 5: Gate.** Register the test in Tier 2. Run: `tests/run-all`. Expected: green.

- [ ] **Step 6: Commit** with message `fix(security): per-user runtime dirs must be private (shells, nvim)`.

### Task 3: Content verification for every payload file the installer uses, failing closed

Closes SEC-7, SEC-8.

**Files:**
- Modify: `loadout_main.py` at `install_portable_python` (2322-2332: resolve the archive through `_bz2.resolve`), `_prepare_wheels_dir` (960-1000) and `install_python_tools` (3042-3060), `install_typelibs` (2671-2686), `install_treesitter_parsers` (4186-4222), `install_nvim_treesitter_vendor` (4244-4256), `stage_pending_ops` (2032-2036), `install_python_suite` (2523: verify the lock file), `cmd_install` (7114-7118)
- Test: `tests/content-verify` (extend; it already builds a temp repo)
- Docs: AGENTS.md "Content verification", `docs/SECURITY.md` (coverage list), README `--no-verify` text

**Interfaces:**
- Produces: `_verify_tree(src_dir: str) -> None` runs `_verify_source_files` over every regular file under `src_dir`, skipping `.git`, and raises `ContentVerificationError`.
- Changes: `_prepare_wheels_dir(wheels_dir)` verifies every `*.whl` and every `.part-NNN` before copying or returning, and `install_python_tools` calls it before checking whether a wheel exists.
- Changes: with `.content-manifest` missing and no `--no-verify`, `cmd_install` prints `content verification: .content-manifest not found -- refusing to install unverified payload (pass --no-verify to override)` and returns 1.
- Scope: `payload/` only. `envs/` is only partly in the manifest (144 entries), so env sources stay out of scope.

- [ ] **Step 1: Write the failing tests** (extend `tests/content-verify`). Each case tampers one byte of a fixture file *after* writing the manifest, then calls the phase function:

```python
check("tampered typelib refused", raises(ContentVerificationError, lm.install_typelibs, repo, home, None))
check("tampered parser refused", raises(..., lm.install_treesitter_parsers, repo, home, None))
check("tampered wheel refused before uv runs", raises(...) and not uv_called)   # monkeypatch lm.run
check("tampered portable-python refused", raises(..., lm.install_portable_python, repo, home, None))
check("missing manifest fails closed", lm.cmd_install(args_no_verify_false, reg, None, repo, home) == 1)
check("--no-verify still installs", ...)   # existing escape hatch unchanged
```

- [ ] **Step 2: Run them and confirm they fail.** Run: `$PY tests/content-verify`. Expected: the new checks FAIL.
- [ ] **Step 3: Implement** the changes listed under Files and Interfaces.
- [ ] **Step 4: Run the tests and confirm they pass.** Run: `$PY tests/content-verify && tests/run-all`. Expected: green. Every Tier 2 install must still pass, which proves the real payload is fully manifested.
- [ ] **Step 5: Commit** with message `fix(security): verify interpreter, wheels, parsers, typelibs; fail closed without manifest`.

### Task 4: Make the release trust chain real (decision D-A)

Closes SEC-9, DOC-8.

**Files:**
- Modify: `build/release:1415-1430`. Write a tag message file whose first line is the tag, followed by `sha256sums.txt sha256 <hex>`, and create the tag with `git tag -s -F <file>`. Signing already gates the release unless `--allow-unsigned`.
- Modify: `tools/fetch-stash`. Add `--tag` handling for `--from-file`, add `verify_tag_binding`, add `--allow-unverified-sums`, write `record_fetched` atomically, and fix the mismatch message.
- Test: create `tests/fetch-stash-trust` (python, Tier 1) and run the existing `tests/release-tag-scheme`.
- Docs: `docs/SECURITY.md:145-153,215-224`, AGENTS.md "Trust chain" and the Data packages paragraph, `docs/RELEASE.md` (signing step), README fetch-stash usage, and the `tools/fetch-stash` docstring.

**Interfaces:**
- Produces: `verify_tag_binding(repo: str, tag: str, sums_bytes: bytes) -> None` runs `git -C repo verify-tag <tag>` (it must exit 0), reads `git cat-file -p <tag>`, finds the line `sha256sums.txt sha256 <hex>` and requires `<hex> == sha256(sums_bytes)`. Otherwise it raises `SystemExit` with a message naming which link failed.
- CLI contract: the online path uses the release's tag; `--from-file` requires `--tag`. Without a verifiable tag (no `.git`, as in release tarballs) the tool refuses unless `--allow-unverified-sums` is given, which prints `trust: GitHub-over-HTTPS only (sums not bound to a signed tag)`.
- Releases made before this change carry no binding line. `--allow-unverified-sums` is the documented path for them.

- [ ] **Step 1: Write the failing test** `tests/fetch-stash-trust`. Build a temp git repo containing a copy of `tools/fetch-stash` under `tools/` (so its `REPO` resolves to the temp repo), generate a throwaway SSH key, set `gpg.format=ssh` and `gpg.ssh.allowedSignersFile`, and make a fixture stash plus sums file. Cases:

```python
# good: signed tag binding sha256(sums) -> rc 0, .content-manifest.fetched has the stash line
# sums file altered after tagging -> rc != 0, fetched manifest unchanged, message names "sums"
# unsigned annotated tag carrying the line -> rc != 0 ("verify-tag")
# --from-file without --tag and without --allow-unverified-sums -> rc 2
# --allow-unverified-sums -> rc 0 and the "HTTPS only" line printed
# mismatch with --from-file never deletes the user's file, and the message does not claim it does
```

- [ ] **Step 2: Run it and confirm it fails.** Run: `$PY tests/fetch-stash-trust`. Expected: FAIL.
- [ ] **Step 3: Implement** the release tag-message change and the fetch-stash changes.
- [ ] **Step 4: Run the tests and confirm they pass.** Run: `$PY tests/fetch-stash-trust && $PY tests/release-tag-scheme && $PY tests/security-pipeline`. Expected: green.
- [ ] **Step 5: Gate and commit.** Run `tests/run-all --fast`, then commit with message `feat(release): bind sha256sums.txt into the signed tag; fetch-stash verifies it`.

## Phase B: Correctness

### Task 5: `reinstall`/`upgrade` keep an explicit `--dest-dir`

Closes COR-1.

**Files:** Modify `loadout_main.py:7751-7892`. Test: `tests/env-routing-dest-dir` (extend). Docs: AGENTS.md `--dest-dir` paragraph (state that the rule applies to all three verbs).

**Interfaces:** Produces `_cli_install_impl(ctx, dest_dir_explicit: bool, **params) -> NoReturn`, shared by `cli_install`, `cli_reinstall` and `cli_upgrade`. Each verb computes `ctx.get_parameter_source("dest_dir") == click.core.ParameterSource.COMMANDLINE` from its **own** context. Remove the `ctx.invoke` calls.

- [ ] **Step 1: Write the failing test.** For each verb in `install reinstall upgrade update`: with an empty temp `H` and `D`, run `env -i HOME="$H" PATH=/usr/bin:/bin ./loadout $verb env-editorconfig --dest-dir "$D" --no-backup -y`. Assert that `$D/.editorconfig` exists, `$H/.editorconfig` does not, and the output has no `ignoring dest_dir`.
- [ ] **Step 2: Run it and confirm it fails.** Run: `tests/env-routing-dest-dir`. Expected: FAIL for reinstall, upgrade and update.
- [ ] **Step 3: Implement** `_cli_install_impl`.
- [ ] **Step 4: Run the tests and confirm they pass.** Run: `tests/env-routing-dest-dir && tests/check-installer`. Expected: green.
- [ ] **Step 5: Commit** with message `fix(cli): reinstall/upgrade honor an explicit --dest-dir`.

### Task 6: Snapshot and backup on sealed trees, with one target table

Closes COR-2, COR-8, COR-9, COR-19.

**Files:**
- Modify: `loadout_main.py:1427-1432` (`remove_path`), `1435-1451` (`lns`: raise `InstallRefused` instead of `sys.exit`), `4697-4750` (`_restore_backup_dir`), `4812-4864` (`backup_existing`), `7389-7399` (`cmd_snapshot` create), and the `backup_existing` call in `cmd_install`
- Test: create `tests/unit-install-steps` (python, Tier 1, shared by Tasks 6-11 and 16) and `tests/snapshot-restore` (sh, Tier 2)
- Docs: AGENTS.md "Backup" paragraph, `docs/INSTALLATION.md` snapshot section, README snapshot verbs

**Interfaces:**
- Produces: `_rmtree_healing(path: str) -> None` wraps `shutil.rmtree(path, onexc=...)`. On `PermissionError` the handler calls `_grant_owner_write` on the failing entry's parent directory and on the entry itself, then retries the failed operation once; any other error re-raises. `remove_path` uses it for directories.
- Produces: `_env_snapshot_targets(registry: dict | None) -> list[str]` returns HOME-relative paths: a static list (bash entrypoints and profile, retired entrypoints, `.tcshrc`, `.cshrc`, `.zshenv`, `.zshrc`, `.zprofile`, `.vimrc`, `.vim`, `.tmux`, `.tmux.conf`, `.tmux.local.conf`, `.editorconfig`, `.config/{vim,nvim,tmux,starship,editorconfig}`, `.config/bash/{global,functions.sh,README.md,bashrc,profile}`, `.config/tcsh/{global,tcshrc}`, `.config/zsh/{global,site-functions,zshrc}`, `.config/st/global`, `.config/helix/{config.toml,languages.toml}`, `.config/pip/pip.conf`) plus every generic env package's `install_to` made relative to HOME.
- Changes: `backup_existing(home, repo_dir, registry=None)` iterates that list. `_restore_backup_dir` removes exactly the targets present in the snapshot (by `lexists` in the snapshot) and then copies. `cmd_snapshot create` removes an empty backup dir and returns 1 with `nothing to snapshot`.

- [ ] **Step 1: Write the failing tests.** In `tests/unit-install-steps`:

```python
def test_rmtree_healing_sealed_tree():   # dirs 0o555 + files 0o444 -> remove_path removes it, no exception
def test_sync_dir_delete_sealed_subdir(): # dest/old sealed, src lacks old -> sync_dir(delete=True) removes it
def test_snapshot_targets_cover_env_handlers():  # every ENV_HANDLERS-managed root appears in _env_snapshot_targets(reg)
def test_lns_on_real_dir_raises_install_refused():
```

  In `tests/snapshot-restore`: install `env-nvim env-tcsh env-zsh env-helix` into temp `H`, then `snapshot create`. Mutate `H/.config/helix/config.toml` (chmod u+w and append a line), then `snapshot restore <archive>`. Assert rc 0, no `Traceback` in the output, the helix file content restored, and `.tcshrc` still a symlink to `.config/tcsh/tcshrc`. A separate case runs `snapshot create` on an empty HOME and expects rc 1 and no `*.tar.bz2`.

- [ ] **Step 2: Run them and confirm they fail.** Run: `$PY tests/unit-install-steps; tests/snapshot-restore`. Expected: FAIL. The restore case fails with the `PermissionError` seen live in this review.
- [ ] **Step 3: Implement** the changes listed under Interfaces.
- [ ] **Step 4: Run the tests and confirm they pass.** Run: `$PY tests/unit-install-steps && tests/snapshot-restore && tests/env-managed-readonly`. Expected: green.
- [ ] **Step 5: Commit** with message `fix(snapshot): heal sealed trees on removal; one backup/restore target table`.

### Task 7: `doctor` survives symlinked system binaries

Closes COR-3.

**Files:** Modify `loadout_main.py:6486-6495`. Test: `tests/doctor-system-newer` (extend).

**Interfaces:** The fix is `sys_dir = os.path.realpath(os.path.dirname(sys_path))`, i.e. the PATH directory, which is always present in `path_dirs`.

- [ ] **Step 1: Write the failing test** `test_symlinked_system_bin_outside_path`. `onpath/fd` is a symlink to `offpath/fd`, a script that prints `fd 99.0.0`. Call `_system_newer_rows({"fd": {"version": "10.0.0", "bins": ["fd"]}}, path_str="onpath:elbin", loadout_dirs={"elbin"})`. Expect one row with standing `system-wins` and no exception.
- [ ] **Step 2: Run it and confirm it fails.** Run: `$PY tests/doctor-system-newer`. Expected: `ValueError: list.index(x): x not in list`.
- [ ] **Step 3: Implement** the one-line fix.
- [ ] **Step 4: Run the test and confirm it passes.** Expected: PASS.
- [ ] **Step 5: Commit** with message `fix(doctor): standing uses the PATH dir, not the symlink target`.

### Task 8: Atomic replacement for every extracted or copied install file

Closes COR-4, ROB-2. Depends on Task 6 (`remove_path` heals).

**Files:**
- Modify: `loadout_main.py` at `_Bz2Store` (885-957), `safe_extract_tar`/`pv_extract_tar` (3592-3624), `install_runtime_archives` (3939), `install_vim_runtime` (4026), `install_mate_terminal_runtime` (4084), `install_nvim_qt_runtime` (4152-4164), `install_treesitter_parsers` (4205-4220), `install_typelibs` (2681-2688), and the callers of `_bz2.resolve` for chunked files
- Test: create `tests/install-atomic-replace` (python, Tier 1, synthetic fixtures)
- Docs: AGENTS.md "Atomicity" (extend the rule from bz2 to all installed files), `docs/ARCHITECTURE.md` install pipeline

**Interfaces:**
- Produces: `extract_tar_replacing(archive_path: str, dest_dir: str) -> int`. It runs the existing `_validate_tar_members` and `_remove_symlinks_blocking_dirs`, extracts with `filter="data"` into `tempfile.mkdtemp(prefix=".loadout-stage.", dir=dest_dir)`, then walks the staging tree top-down. Directories are created in the destination. Files and symlinks move into place with `os.replace`, and when a non-directory replaces a directory, `remove_path` runs first. The staging dir is always removed in `finally`. Returns the number of entries placed and keeps the existing Rich progress bar.
- Changes: `pv_extract_tar(archive_path, dest_dir)` delegates to `extract_tar_replacing` for install destinations. Extraction into a fresh temp dir (portable-python's `install.sh` staging) keeps the direct path.
- Produces: `_copy_atomic(src: str, dest: str, mode: int) -> None` (same-directory temp file, then `os.replace`) and `_write_stream_atomic(fileobj, dest: str, mode: int) -> None`. Tree-sitter `.so` files and typelibs use `_copy_atomic`; `.so.bz2` files use `write_bz2_atomic`. Task 13 consumes `_write_stream_atomic`.
- Produces: `_Bz2Store.release(path: str) -> None` unlinks a rejoined temp file immediately and drops it from `_tmpfiles`; it is a no-op for non-temp paths. Every caller that resolves a chunked artifact releases it after use.

- [ ] **Step 1: Write the failing tests:**

```python
def test_extract_replaces_inode():   # dest/lib/libx.so exists (ino A); fixture tar has new bytes -> content new, st_ino != A
def test_extract_mapped_reader_survives():
    # child: mmap dest/lib/libx.so, signal ready, wait, read every page, exit 0
    # parent: extract_tar_replacing(fixture, dest) while the child holds the map
    # assert child.returncode == 0 (no SIGBUS) and the child's bytes == old bytes
def test_extract_unsafe_member_leaves_no_stage():  # ../evil member -> RuntimeError; dest unchanged; no .loadout-stage.* left
def test_parser_reinstall_swaps_inode():   # install_treesitter_parsers twice on a fixture repo -> st_ino differs
def test_bz2store_release_removes_temp():  # resolve a chunked fixture -> temp exists; release(temp) -> gone
```

- [ ] **Step 2: Run them and confirm they fail.** Run: `$PY tests/install-atomic-replace`. Expected: FAIL. In-place writes keep the inode, and `release` does not exist yet.
- [ ] **Step 3: Implement** the changes listed under Interfaces.
- [ ] **Step 4: Run the tests and confirm they pass.** Run: `$PY tests/install-atomic-replace && $PY tests/tar-safety && tests/run-all`. Expected: green. Tier 2 proves the real runtime archives (zsh relocation, modules relocate_token, wezterm, vim92 rename) still install.
- [ ] **Step 5: Container gate.** Install behavior changed, so run `tests/prebuilt-binaries-almalinux8 --full` (it uses `--network=none`). Expected: PASS. Record the timing row it writes.
- [ ] **Step 6: Commit** with message `fix(install): replace installed files by inode swap, never truncate in place`.

### Task 9: Every phase failure becomes a summary row

Closes COR-5, COR-6, COR-7, ROB-3.

**Files:** Modify `loadout_main.py:1223-1271` (`run_install_step`), `3906-3986` (per-package isolation), `4031-4035` (vim FAIL), `3153-3181` and `7230` (ldd check), `8192-8207` (content-verification report). Test: `tests/unit-install-steps` (extend).

**Interfaces:**
- `run_install_step` also catches `RuntimeError`, `tarfile.TarError`, `zipfile.BadZipFile` and `ValueError` as FAIL rows, and writes the traceback to the run log through `_log` rather than to the console.
- `install_runtime_archives` wraps each package (resolve, extract, relocate, sentinel) in `try/except (OSError, RuntimeError, tarfile.TarError, InstallRefused)`, records `f"{pkg_name} runtime"` as FAIL, and continues. `ContentVerificationError` still propagates.
- `check_prebuilt_binary_dependencies(dest_bin_dir, names: Iterable[str] | None = None)` checks only the binaries this run wrote. `install_prebuilt_binaries` returns them as a third tuple element, `installed_bins: set[str]`. It runs inside `run_install_step("shared-library check", ...)`.
- `main()`'s `ContentVerificationError` handler prints `print_install_results()` and `print_install_blockers()` before its message, and the message says that earlier phases completed and appear in the summary.

- [ ] **Step 1: Write the failing tests:**

```python
def test_runtime_error_is_fail_row():   # run_install_step("x", raise RuntimeError) -> ("x","FAIL",...) recorded; returns None
def test_tar_error_is_fail_row():       # tarfile.ReadError -> FAIL row
def test_bad_archive_does_not_block_next():  # fixture registry a (corrupt tar), b (good) -> b sentinel exists; a FAIL, b OK
def test_vim_missing_sentinel_is_fail(): # vim archive without filetype.vim -> ("Vim runtime","FAIL",...)
def test_ldd_only_checks_written_bins(): # monkeypatch subprocess.run; names={"a"} -> ldd called once, on a
def test_verification_failure_prints_summary(): # main() with a cli that records a row then raises -> stdout has "Summary"
```

- [ ] **Step 2: Run them and confirm they fail.** Expected: FAIL.
- [ ] **Step 3: Implement** the changes listed under Interfaces.
- [ ] **Step 4: Run the tests and confirm they pass.** Run: `$PY tests/unit-install-steps && tests/check-installer && tests/run-all --fast`. Expected: green.
- [ ] **Step 5: Commit** with message `fix(install): phase failures become summary rows; per-archive isolation`.

### Task 10: nvim plugin seeding and headless sync cannot stick or hang

Closes COR-10, COR-11.

**Files:** Modify `loadout_main.py:1393-1415` (`run`), `4552-4576`, `4592-4669`. Test: `tests/unit-install-steps` (extend). Docs: AGENTS.md "nvim Deployment" (timeout and failed-clone cleanup).

**Interfaces:**
- `run(cmd, cwd=None, env=None, check=True, stdout=None, stderr=None, timeout=None)`. On `subprocess.TimeoutExpired` it kills the child's session with `os.killpg(proc.pid, SIGKILL)` (the child runs with `start_new_session=True`), reaps it, and re-raises `TimeoutExpired`.
- `_NVIM_HEADLESS_TIMEOUT = 600` (seconds). On timeout `install_nvim_lazy_update` records `("Neovim Lazy sync", "FAIL", "timed out after 600s")`.
- A failed `git clone` or pin checkout runs `shutil.rmtree(dst, ignore_errors=True)` before recording the failure.

- [ ] **Step 1: Write the failing tests** using stub `git` and `nvim` scripts in a temp bin dir:

```python
def test_failed_checkout_removes_clone():  # stub git: clone ok, checkout exit 1 -> dst absent; 2nd run -> FAIL again (not "kept")
def test_headless_sync_times_out():        # stub nvim sleeps 30; _NVIM_HEADLESS_TIMEOUT=1 -> FAIL "timed out", stub process gone
def test_run_timeout_kills_group():        # run(["sh","-c","sleep 30 & sleep 30"], timeout=1) raises; no sleep left in that pgid
```

- [ ] **Step 2: Run them and confirm they fail.** Expected: FAIL.
- [ ] **Step 3: Implement** the changes listed under Interfaces.
- [ ] **Step 4: Run the tests and confirm they pass.** Run: `$PY tests/unit-install-steps && tests/install-nvim-deployments && tests/install-nvim-shared-stash`. Expected: green.
- [ ] **Step 5: Commit** with message `fix(nvim): clean failed plugin clones; time out headless Lazy sync`.

### Task 11: Bash env correctness

Closes COR-12, COR-13, COR-14.

**Files:** Modify `envs/bash/global/bashrc:65-69,494-502,560-562`. Test: create `tests/env-bash-runtime` (sh, Tier 1; it sources repo files directly with `BASH_CONFIG_ROOT_DIR=$REPO/envs/bash`). Docs: `docs/BASH.md` (non-interactive contract).

**Interfaces:**
- The non-interactive branch calls the existing `unset_bashrc_local_vars`, which skips exported names, instead of `unset ${!_@}`.
- The `ls` fallback body escapes `\$option_g \$option_h \$option_a` and passes `"\$@"` instead of `\$*`. The same `"\$@"` fix applies to the eza and lsd bodies.
- The ERR trap keeps only the directory branch, now quoted: `[[ -d $last_cmd ]] && cd -- "$last_cmd"`. The subshell file branch is deleted.

- [ ] **Step 1: Write the failing test:**

```sh
out=$(env -i HOME="$T" PATH=/usr/bin:/bin BASH_CONFIG_ROOT_DIR="$REPO/envs/bash" \
    _LMFILES_=/m/a _JAVA_OPTIONS=-Xmx1g bash -c '. "$BASH_CONFIG_ROOT_DIR/bashrc"; printf "%s|%s" "$_LMFILES_" "$_JAVA_OPTIONS"')
[ "$out" = "/m/a|-Xmx1g" ] || fail "exported _vars wiped by non-interactive startup"
# ls fallback (interactive, PATH without eza/lsd, LOADOUT_CFG_PREFERRED_LS=ls):
#   bash -i -c 'declare -f ls' | grep -q '\$option_a'   || fail "ls fallback options expanded at definition"
#   bash -i -c 'trap -p ERR'   | grep -q 'dirname'      && fail "dead ERR-trap subshell branch still present"
```

- [ ] **Step 2: Run it and confirm it fails.** Expected: FAIL on the first assertion.
- [ ] **Step 3: Implement** the changes listed under Interfaces.
- [ ] **Step 4: Run the tests and confirm they pass.** Run: `tests/env-bash-runtime && $PY tests/env-shell-parity && tests/shell-typeahead && tests/install-env-bash`. Expected: green.
- [ ] **Step 5: Commit** with message `fix(bash): keep exported _vars; ls fallback options; drop dead ERR branch`.

### Task 12: The shim finds the installed interpreter, bootstraps atomically, and the Python minor lives in one place

Closes COR-15, COR-16, ROB-4, DOC-7.

**Files:**
- Modify: `loadout` (all), `loadout_main.py:2764,2807,3049` plus a new constant near `:226`, `hooks/pre-commit:52,105`
- Test: create `tests/shim-bootstrap` (sh, Tier 1) and extend `tests/payload-interpreter-abi`
- Docs: AGENTS.md cold start (shim order), `docs/ARCHITECTURE.md:203-219`, `docs/PYTHON-CA-TLS.md:66-73`, README bootstrap text

**Interfaces:**
- Shim order: (1) `${XDG_DATA_HOME:-$HOME/.local/share}/loadout/bin/python3.15`, (2) `$HOME/.local/bin/python3.15` (legacy HOME mode), (3) the warm cache `$boot_dir/bin/python3.15`, accepted only when `$boot_dir/.complete` contains exactly the basename of the current `portable-python-*.tar.bz2`, (4) a cold bootstrap that extracts into `"$boot_dir.tmp.$$"`, checks the interpreter runs (`"$tmp/bin/python3.15" -c 'import sys'`), writes `.complete` with the archive basename, removes the old `$boot_dir` and `mv`s the temp dir into place. A stale `.loadout-bootstrap.tmp.*` is removed first. The stamp rule also discards a cache left by an earlier minor version (today's cache holds both 3.14 and 3.15 trees). Every `$HOME` reference uses `${HOME:-}`. The decompress step checks bzip2's status explicitly, since POSIX sh has no pipefail. A config.toml `dest_dir` root is not probed (stated in the docs).
- `loadout_main.py`: `_BUNDLED_PY = "3.15"`, `_BUNDLED_PY_BIN = f"python{_BUNDLED_PY}"`, `_BUNDLED_SITE = f"lib/python{_BUNDLED_PY}/site-packages"`. These replace the three literals.

- [ ] **Step 1: Write the failing tests.** `tests/shim-bootstrap` copies `loadout` into `$T/repo` alongside a stub `loadout_main.py` and a fixture `payload/x/portable-python-T.tar.bz2` whose `local/bin/python3.15` is `#!/bin/sh` with `echo STUB "$0" "$@"`. Cases:

```sh
# cold:        prints STUB; .loadout-bootstrap/.complete == "portable-python-T.tar.bz2"; no .loadout-bootstrap.tmp.* remains
# xdg:         $H/.local/share/loadout/bin/python3.15 prints XDG -> output starts with XDG
# interrupted: pre-create .loadout-bootstrap/bin/python3.15 printing BROKEN and no .complete -> prints STUB, not BROKEN
# stale:       .complete names portable-python-OLD.tar.bz2 -> re-extracts, prints STUB
# no-home:     env -i (no HOME), no archive -> exit 1, stderr lacks "parameter not set"
```

  In `tests/payload-interpreter-abi`, add `test_bundled_py_matches_archive`: `lm._BUNDLED_PY` equals the `X.Y` of the payload portable-python archive's `bin/pythonX.Y`.

- [ ] **Step 2: Run them and confirm they fail.** Expected: the xdg, interrupted and stale cases FAIL (today's shim runs the BROKEN stub and ignores the XDG root).
- [ ] **Step 3: Implement** the changes listed under Interfaces.
- [ ] **Step 4: Run the tests and confirm they pass.** Run: `tests/shim-bootstrap && $PY tests/payload-interpreter-abi && tests/check-installer && sh -n loadout`. Expected: green.
- [ ] **Step 5: Commit** with message `fix(shim): probe the XDG install root; atomic bootstrap; one Python-minor constant`.

### Task 13: Fonts reinstall without unbounded backups (decision D-B)

Closes ROB-1. Depends on Task 8 (`_write_stream_atomic`).

**Files:** Modify `loadout_main.py:3335-3348` (`extract_font_zip`) and `3402-3527` (`install_fonts`: drop the move-aside branch; `no_backup` no longer affects fonts). Test: `tests/install-fonts-rejoin` (extend). Docs: AGENTS.md (remove "fonts phase does its own fonts.bak* move"), `docs/INSTALLATION.md`, README fonts section.

**Interfaces:** `extract_font_zip` writes each member through `_write_stream_atomic(member_stream, dest, 0o644)`. `install_fonts` never renames the fonts dir; files that are not in the bundle are left untouched.

- [ ] **Step 1: Write the failing test.** Install `font-hack` twice into temp `H` without `--no-backup`, planting `H/.local/share/fonts/MyOwn.ttf` between the runs. Assert no `fonts.bak*` sibling exists, `MyOwn.ttf` survives, and the Hack files are present.
- [ ] **Step 2: Run it and confirm it fails.** Expected: FAIL (a `fonts.bak` exists).
- [ ] **Step 3: Implement** the changes listed under Interfaces.
- [ ] **Step 4: Run the tests and confirm they pass.** Run: `tests/install-fonts-rejoin && tests/install-fonts-shared`. Expected: green.
- [ ] **Step 5: Commit** with message `fix(fonts): replace bundle files in place; never move the fonts dir aside`.

### Task 14: Resolver fixed point (latent)

Closes COR-17.

**Files:** Modify `loadout_main.py:519-653`. Test: `tests/unit-resolver` (extend).

**Interfaces:** `walk_depends(names, registry, forbidden=None, force=False, disabled=None)` and `walk_recommends(names, registry, forbidden=None, disabled=None)`. Both treat `disabled` (default `disabled_packages(registry)`) as the out-of-service set. `resolve_tool_selection` alternates depends and recommends until the set stops changing.

- [ ] **Step 1: Write the failing tests:**

```python
reg = {"a": {"recommends": ["r"]}, "r": {"depends": ["d"]}, "d": {},
       "x": {"disabled": True}, "s": {"depends": ["x"]}, "b": {"recommends": ["s"]}}
assert resolve(["a"]) == {"a", "r", "d"}   # recommended pkg's hard dep is pulled
assert resolve(["b"]) == {"b"}             # cascade-disabled recommend is dropped
assert resolve(resolve(["a"])) == resolve(["a"])   # idempotent
```

- [ ] **Step 2: Run them and confirm they fail.** Expected: FAIL (`d` is missing).
- [ ] **Step 3: Implement** the changes listed under Interfaces.
- [ ] **Step 4: Run the tests and confirm they pass.** Run: `$PY tests/unit-resolver && $PY tests/registry-integrity && tests/search-groups`. Expected: green.
- [ ] **Step 5: Commit** with message `fix(resolver): walk depends of recommended packages; honor the disabled cascade`.

## Phase C: Tooling and docs

### Task 15: Pre-commit hook safety

Closes TOOL-1, TOOL-2, TOOL-3, DOC-11.

**Files:** Modify `hooks/pre-commit`, `hooks/README.md`. Test: create `tests/pre-commit-hook` (bash, Tier 1).

**Interfaces:**
- Step 1 only looks for `.git` directories under the parent directories of staged paths (`git diff --cached --name-only`) and under untracked, non-ignored paths (`git ls-files --others --exclude-standard --directory`). It re-stages only the affected paths with `git add -- <paths>` and never runs `git add -A`.
- Step 3 writes its error file with `mktemp "${TMPDIR:-/tmp}/loadout-precommit.XXXXXX"`, removes it on exit, and labels the check with the interpreter's real version.
- Step 4 calls `strip-all-elf-binaries` with the same python3.15 PATH prefix as step 2. If it fails, or if any staged `payload/` file over 40 MiB remains unchunked, the hook exits 1 with a message.
- The README documents all four steps and the file header lists four steps.

- [ ] **Step 1: Write the failing test.** Create a temp git repo with `hooks/pre-commit` installed as `.git/hooks/pre-commit` and a stub `build/strip-all-elf-binaries`. Cases:

```bash
# ignored dir cache/clone/.git (cache/ in .gitignore) -> still present after commit
# untracked notes.txt -> not in `git show --name-only HEAD`
# staged vendor/p/ containing p/.git/ -> p/.git removed, vendor/p files committed
# stub strip exits 1 + staged 41 MiB payload/big.bin -> commit fails (rc != 0)
```

- [ ] **Step 2: Run it and confirm it fails.** Expected: FAIL on the first two cases.
- [ ] **Step 3: Implement** the changes listed under Interfaces.
- [ ] **Step 4: Run the test and confirm it passes.** Expected: PASS.
- [ ] **Step 5: Commit** with message `fix(hooks): scope embedded-.git cleanup; never git add -A; fail loud on chunking`.

### Task 16: Hardening and small-correctness batch

Closes SEC-10, COR-18, DOC-9, TOOL-4.

**Files:**
- Modify: `loadout_main.py` at `_wrap_uv_tool_launchers` (2921-2935), `_prefer_shim_body` (5031-5033), the final hint (7251), `cmd_describe` (6277: use `_resolve_home(None)`), `_load_content_manifest` (857: `with open`), `backup_existing` (4855: `_path_under` instead of `startswith`), and docstrings/messages at 406, 441, 512-513, 561, 3574, 6350-6352, 6782
- Modify: `envs/nvim/lua/global/config.lua:60-81,102-113` (`vim.system` with argument lists, no shell)
- Modify: `build/iverilog/iverilog-vpi:82-86` (move the directive above the command)
- Test: `tests/unit-install-steps` (extend) and `tests/env-private-dirs` (one nvim case)

**Interfaces:** Every generated sh line that embeds a path uses `shlex.quote(path)`. The prefer shim becomes `exec <quoted target> "$@"`. The wrapper uses `PYTHONPATH=<quoted>${PYTHONPATH:+:$PYTHONPATH}`.

- [ ] **Step 1: Write the failing tests:**

```python
def test_generated_wrappers_quote_paths():
    # root = tmp/'a b$c"d`e'; write the prefer shim + PYTHONPATH wrapper for a stub target that prints $PYTHONPATH and its args
    # `sh -n` passes on both; running them reaches the stub; PYTHONPATH starts with the quoted site-packages path
def test_describe_python_suite_uses_install_root():  # stamp under _resolve_home(None) -> "installed: ..." printed
def test_disabled_messages_use_out_of_service_wording():  # ResolverError text has no "online"/"offline"
```

  Add an nvim case to `tests/env-private-dirs`: with `LOADOUT_CFG_ONLINE_DETECT_HOSTS='x;touch $T/pwned:443'`, `LOADOUT_ONLINE` unset and no cache, a headless nvim start leaves `$T/pwned` absent.

- [ ] **Step 2: Run them and confirm they fail.** Expected: FAIL.
- [ ] **Step 3: Implement** the changes listed under Files and Interfaces. Verify the iverilog fix with `shellcheck -S error build/iverilog/iverilog-vpi`; expected: clean.
- [ ] **Step 4: Run the tests and confirm they pass.** Run: `$PY tests/unit-install-steps && tests/env-private-dirs && tests/run-all --fast`. Expected: green.
- [ ] **Step 5: Commit** with message `fix: quote generated wrapper paths; shell-free nvim probes; stale messages`.

### Task 17: A docs-sync gate, plus fixes for the current drift (decision D-C)

Closes DOC-1 through DOC-6.

**Files:**
- Create: `tests/docs-sync` (python, Tier 1; register after `README table in sync`)
- Modify: `loadout_main.py:7783-7791` (help text), `tools/refresh-stash:28,110`, `README.md:462`, AGENTS.md (line 80 count, Repository Map test list, kinds list including `python-suite`, the Python-tools wheel recipe for 3.15/cp315 and "14 tools", cold start "Python 3.14" wording), `build/ADDING_BINARIES.md:801-835` (generic recipe for 3.15/cp315; per-package history sections stay), `.github/copilot-instructions.md` (slim to a pointer stub: what the repo is, the cold-start order AGENTS.md then docs/HANDOFF.md, the gate commands, the Commit Rule), `docs/ARCHITECTURE.md` (add `@all`, `disabled`, `python-suite`), `docs/INSTALLATION.md` (`@all`, `disabled`), `_load_tool_registry` docstring

**Interfaces:** `tests/docs-sync` checks (each a named `check()`):

```python
"every tests/* executable (except run-all) is named in AGENTS.md"
"AGENTS.md '<N> per-user config-source dirs' == len(envs/*/)"
"registry kinds ⊆ kinds named in AGENTS.md and in the _load_tool_registry docstring"
"no stale pattern in current docs or help"  # pip3.14, --python-version 3.14, /foo/bar/local,
                                            # <shared>/local/, "resolve_tool_selection(args, registry)` in `loadout`"
                                            # (history allowlist: docs/HANDOFF.md, docs/archive/**, docs/superpowers/**,
                                            #  per-package dated sections of build/ADDING_BINARIES.md)
"root-level *.md ⊆ {README.md, AGENTS.md}"
".github/copilot-instructions.md <= 80 lines and links AGENTS.md"
"`./loadout install --help` output has no '/local ' prefix example"
"every relative Markdown link in first-party docs resolves to an existing path"
```

- [ ] **Step 1: Write the failing test** with the checks above.
- [ ] **Step 2: Run it and confirm it fails.** Run: `$PY tests/docs-sync`. Expected: FAIL on the test list, envs count, kinds, stale patterns, root md and copilot length.
- [ ] **Step 3: Fix each doc and help-text item** listed under Files. Leave the root-md failure for Task 18 by adding a temporary allowlist entry for `enhancement-request-permissions-management.md` with the comment `# removed by Task 18`.
- [ ] **Step 4: Run the gate and confirm it passes.** Run: `$PY tests/docs-sync && tests/run-all --fast`. Expected: green.
- [ ] **Step 5: Commit** with message `docs: sync AGENTS/README/ARCHITECTURE/help with the code; add tests/docs-sync gate`.

### Task 18: Archive superseded docs and split HANDOFF

Closes DOC-10.

**Files:**
- `git mv enhancement-request-permissions-management.md docs/archive/2026-09-04-enhancement-request-permissions-management.md`
- `git mv docs/SESSION-HANDOFF-2026-10-02.md docs/archive/`
- `git mv docs/PROPOSAL-2026-10-05-dest-default-and-group-removal.md docs/archive/` and update the link in `docs/superpowers/specs/2026-10-05-dest-default-and-group-removal-design.md:5`
- Split `docs/HANDOFF.md`: keep every entry dated 2026-10-01 or later plus a top "Archive" index; move older entries verbatim to `docs/archive/HANDOFF-2026-07-to-09.md`; update the two in-file references (HANDOFF lines 3815 and 3839) to the archived request path
- Modify: `tests/docs-sync` (drop the Task 17 temporary allowlist entry), AGENTS.md "Docs Sync Targets" (mention `docs/archive/` as history, never a sync target)

- [ ] **Step 1: Make the gate fail.** Remove the temporary allowlist entry and run `$PY tests/docs-sync`. Expected: FAIL (`root-level *.md`).
- [ ] **Step 2: Do the moves and the split.** Expected: `wc -l docs/HANDOFF.md` is under 1,500.
- [ ] **Step 3: Run the gate.** Run: `$PY tests/docs-sync && build/verify-manifest-export && $PY build/gen-content-manifest --check`. Expected: green, since moved docs are in the shipped set and the manifest is regenerated if it covers them.
- [ ] **Step 4: Commit** with message `docs: archive superseded docs; split HANDOFF history`.

---

## Execution order and dependencies

- Phase A (Tasks 1-4) first; the four tasks are independent of each other. Task 4 waits on decision D-A.
- Task 6 lands before Task 8 (healing `remove_path`), and Task 8 before Task 13 (`_write_stream_atomic`).
- Task 9 builds on the `tests/unit-install-steps` file created in Task 6, so Task 6 lands first.
- Task 17 lands after every code task, so the docs describe final behavior. Task 18 is last.
- After the last task, run the full gate set once more: `tests/run-all` and `tests/prebuilt-binaries-almalinux8 --full`. Then write a HANDOFF entry listing each finding ID with its commit.
