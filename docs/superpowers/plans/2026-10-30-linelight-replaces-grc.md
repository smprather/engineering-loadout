# linelight Replaces GRC Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove GRC from the bash/zsh/tcsh envs, ship the first-party `linelight` colorizer as a loadout package, and colorize the commands linelight has profiles for in all three shells.

**Architecture:** linelight 2026.10.31 (smprather/linelight issues #1-#6, all closed) ships the whole runtime loadout needs: `linelight run --profile ID -- CMD` (direct exec when colour is off, the command's exit status / 128+N, Ctrl-C keeps ping's summary, `COLUMNS` from the tty, job control) and `linelight init bash|zsh|tcsh` (wrappers only for profiled commands on PATH, existing aliases/functions win, `LINELIGHT_INIT=0` and `~/.config/linelight/adapters.toml` `disable = [...]` opt-outs). Loadout imports the upstream glibc-2.28 release asset as a plain `bin` package and has each shell run the adapter at interactive startup behind `LOADOUT_CFG_ENABLE_LINELIGHT`. Loadout ships no runner of its own.

**Tech Stack:** upstream prebuilt (Rust, linked against glibc 2.28 by upstream's almalinux:8 release workflow), `build/update-prebuilt` (run inside `build/build-shell`), bash/zsh/csh env files, sh/Python test harnesses.

**Spec:** the user's request (2026-10-30): "remove all GRC from the shells, add https://github.com/smprather/linelight to loadout, then integrate it into the shell envs"; then (2026-10-31) "proceed with decommissioning grc and replacing with linelight". Upstream: release v2026.10.31 notes and README.

## Global Constraints

- Payload-mutating work runs inside the EL8 container (`build/build-shell`): the import's bzip2 bytes must be EL8's (AGENTS.md "Build Machine Mandate"). Build-time network is allowed; tests run `--network=none`.
- The binary may NEED only glibc + `libgcc_s.so.1`, highest `GLIBC_` version ≤ 2.28. Verified 2026-10-31 on the current asset: NEEDED {libgcc_s.so.1, libpthread.so.0, libdl.so.2, libc.so.6}, max GLIBC_2.28; on stock almalinux:8.10 (`--network=none`) `--version`, `check`, `filter`, `run` (status, 128+N, 127, direct exec) and `run --pty` all pass.
- Asset pin: `linelight-2026.10.31-x86_64-unknown-linux-gnu.tar.gz` sha256 `2a8b876da8c0950152bcdd2b9621747b3b9bdd8830a32b1c49427bae072c8eb1`, checked against the published `.sha256` sidecar at import. Upstream MOVED tag v2026.10.31 (3bcc76d → 71e5e7b) and replaced the asset in place when fixing #6; the sidecar check plus this recorded hash are the provenance record.
- Payload chain, in this order: import (writes `bin/linelight.bz2`) → `./build/strip-all-elf-binaries` → `build/gen-installed-sizes` → `build/gen-content-manifest`. The `build/ADDING_BINARIES.md` section lands in the same commit as the payload.
- Shell startup stays silent. bash/zsh/tcsh behave the same; the tcsh env must NOT depend on env-bash. Every switch an env reads is defined in that env's own `config.sh`/`config.csh` (`tests/env-shell-parity`).
- Indent with spaces, never tabs. Automation passes `-y`. Never run two `tests/run-all` at once (check `pgrep -f tests/run-all` first; the omp agent shares this tree). `TMPDIR=/var/tmp` for full runs. Private tmux sockets only (`tmux -L <name>`). Commit straight to `main`; push only when asked.

## Decisions

1. **Import, don't build.** Upstream now publishes a glibc-2.28 x86_64 asset whose release workflow builds in almalinux:8 and smoke-tests there, so loadout imports it with `build/update-prebuilt` like ruff/uv/starship. `update-prebuilt` gains a generic sha256-sidecar check (`SHA256_SIDECARS`), since it currently verifies nothing.
2. **Wrapped set = what `linelight init` generates:** `df diff dig free lsblk ping ps sensors ss` when on PATH. `ls` is off and `log` is never wrapped (upstream policy). Coverage shrinks on purpose: GRC wrapped ~45 commands; upstream closed #5 as "no bulk import of grc's list, native-first admission".
3. **Switches:** `LOADOUT_CFG_ENABLE_LINELIGHT` (default `1`) replaces `LOADOUT_CFG_ENABLE_GRC` and decides whether the adapter runs at all. Upstream's `LINELIGHT_INIT=0` and `~/.config/linelight/adapters.toml` keep working unchanged. `colourify` disappears; HANDOFF and the READMEs say so.
4. **`df` is the one collision.** Loadout's own `df` adds `--block-size=G`, and `init` skips names that are already defined. The shells run the adapter BEFORE aliases.sh/aliases.csh, record whether it defined `df` (it does only when df is on PATH and not disabled), and aliases.sh/.csh then define loadout's `df` as `linelight run --profile df -- df --block-size=G` in that case, plain `df --block-size=G` otherwise. So every opt-out also applies to loadout's `df`.
5. **tcsh sources a file, not `eval`.** Upstream's documented `eval "`linelight init tcsh`"` defines nothing (csh joins the substitution into one line; interactively it prints `Badly placed (.`; under `-c` it is silent; upstream CI only tests the source-a-file form). tcshrc writes `linelight init tcsh` into a fresh 0700 `mktemp -d -t .loadout-linelight.XXXXXX` dir, sources it and removes it. (Superseded first version used `$XDG_RUNTIME_DIR`; the final self-review found tcshrc can leave that non-private, and the file is code the shell runs.) This form keeps working after any upstream fix.
6. **stdout only.** The adapter wrappers do not pass `--stderr`; none of the nine commands needs it.

## Review Focus

1. **tcsh actually gets the wrappers:** after login, `alias ps` names `linelight run`. The upstream eval form fails silently, so only a real-PTY tcsh test catches a regression. Test: Task 3 `tty/tcsh`.
2. **Exit status is the command's** in all three shells (`diff a b; echo $?` → 1). Test: Task 3 `status/<shell>`.
3. **Pipelines and redirects are untouched:** `df | cat` and `ps | cat` contain no SGR. Test: Task 3 `piped/<shell>`.
4. **`df` keeps `--block-size=G` with and without colour, and honors opt-outs:** `adapters.toml` `disable = ["df"]` gives a plain `1G-blocks` table. Test: Task 3 `optout/<shell>`.
5. **Upgrades leave no GRC behind:** a reinstall over an old tree removes `~/.config/bash/global/grc/` and `~/.config/tcsh/global/grc-aliases.csh`. Test: Task 2 `stale-grc-pruned`.

---

### Task 1: Package `linelight` 2026.10.31 from the upstream asset

**Files:**
- Modify: `payload/packages.json` (entry + `@core-cli.members`), `build/update-prebuilt` (TOOLS entry + `SHA256_SIDECARS`), `build/verify-binaries` (TOOLS entry, kept in sync), `build/farm-versions`, `build/ADDING_BINARIES.md`, `tests/prebuilt-binaries` (functional probe next to the `bitwuzla` block), `README.md` (regenerated table), `envs/bash/global/completions/loadout.bash` (regenerated)
- Create: `payload/el8.x86_64.glibc2p28/bin/linelight.bz2`; regenerate `payload/installed-sizes.json`, `.content-manifest`, `.strip-manifest`

**Interfaces:**
- Produces: `<prefix>/bin/linelight` (`--version` → `linelight 2026.10.31`); registry package `linelight` in `@core-cli`.

- [ ] **Step 1: Registry entry first** → `tests/registry-integrity` FAILS on the missing payload file. Entry: `{"kind": "bin", "bins": ["linelight"], "version": "2026.10.31", "version_url": "https://github.com/smprather/linelight/tags", "platforms": ["linux"], "tags": ["core", "color"], "description": "Output colorizer: filter, command runner and shell adapters with embedded profiles; replaces GRC"}`.
- [ ] **Step 2: Probe** in `tests/prebuilt-binaries`, `if has_bin("linelight"):`
  - df fixture through `filter --profile df --color always`: output contains `\x1b[`, and stripping `\x1b\[[0-9;]*m` returns the input bytes exactly;
  - `check` exits 0;
  - `run --profile df -- printf 'x\n'` with stdout a pipe prints exactly `x\n`;
  - `run --profile df -- sh -c 'exit 3'` exits 3.
- [ ] **Step 3: `update-prebuilt` sidecar check.** `SHA256_SIDECARS = {"linelight": "{url}.sha256"}`; when a tool has one, fetch it, take its first field, compare it to the archive's sha256, and `sys.exit` on mismatch, before extracting anything. Negative control: point the check at a tampered copy and watch it refuse. TOOLS entry: `"linelight": ("https://github.com/smprather/linelight/releases/download/v{ver}/linelight-{ver}-x86_64-unknown-linux-gnu.tar.gz", "linelight")`.
- [ ] **Step 4: Import in the container:** `build/build-shell ./build/update-prebuilt linelight=2026.10.31`. Expect `sha256 OK`, `patchelf RPATH applied`, `runs: linelight 2026.10.31`. Assert the archive hash equals the pin above.
- [ ] **Step 5: Wire-up.** farm-versions entry (version from `--version`, pattern `linelight ([0-9][0-9.]*)`); verify-binaries entry; ADDING_BINARIES section (source = upstream asset + pin, sidecar check, glibc/NEEDED facts, the moved-tag note, why not a source build); payload chain; `build/gen-readme-table`; `./loadout completion bash > envs/bash/global/completions/loadout.bash`.
- [ ] **Step 6: Verify.** `tests/run-all --fast` passes (registry-integrity, needed-closure, content-manifest, installed-sizes, README table, completion). `tests/prebuilt-binaries` linelight probe PASS.
- [ ] **Step 7: Commit** `feat: package linelight 2026.10.31 (upstream glibc-2.28 asset)`.

### Task 2: Remove GRC from the shells

**Files:**
- Delete: `envs/bash/global/grc/` (whole tree), `envs/tcsh/global/grc-aliases.csh`
- Modify: `envs/bash/global/bashrc` (GRC block ~229-235), `envs/zsh/global/zshrc` (~271-279), `envs/tcsh/global/tcshrc` (~343-372), `envs/bash/global/config.sh:32`, `envs/tcsh/global/config.csh:64`, `envs/bash/global/aliases.sh` (`df()`: plain `command df --block-size=G "$@"` for now), `envs/tcsh/global/aliases.csh:237-241` (plain `alias df 'df --block-size=G'`)
- Modify tests: `tests/install-env-tcsh` (GRC section), `tests/env-shell-parity` (GRC lines), plus the cases below
- Modify docs/config: `ruff.toml` (grc exclude), `tests/docs-sync` (`/grc/` exemption), AGENTS.md (repo map, tcsh paragraph, config-vars line), `envs/bash/README.md`, `envs/bash/global/README.md`, `envs/tcsh/README.md`, any other `rg -i grc` hit outside `docs/archive/` and HANDOFF history

- [ ] **Step 1: Failing tests.**
  - `tests/env-shell-parity` (T1) `no-grc-left`: no file under `envs/` contains `ENABLE_GRC`, `colourify`, `grc -es`, `grc.sh` or `grc/bin`; `envs/bash/global/grc` does not exist.
  - `tests/install-env-bash` and `tests/install-env-tcsh` (T2) `stale-grc-pruned`: pre-create sealed (0555/0444) `~/.config/bash/global/grc/bin/grc` and `~/.config/tcsh/global/grc-aliases.csh`, reinstall, assert both gone and startup silent.
- [ ] **Step 2: Run** → `no-grc-left` FAILS (`stale-grc-pruned` may already pass via delete-sync; it pins it).
- [ ] **Step 3: Remove everything in Files.**
- [ ] **Step 4: Verify.** Step 1 tests pass; `tests/env-shell-parity`, `tests/install-env-{bash,zsh,tcsh}`, `tests/env-ls-choice`, `tests/env-private-dirs` pass; `tests/run-all --fast` passes.
- [ ] **Step 5: Commit** `refactor(envs): remove GRC from bash, zsh and tcsh`.

### Task 3: Colourize with `linelight init` in bash, zsh and tcsh

**Files:**
- Modify: `envs/bash/global/config.sh` (`export LOADOUT_CFG_ENABLE_LINELIGHT="1"`), `envs/tcsh/global/config.csh` (`if ( ! $?LOADOUT_CFG_ENABLE_LINELIGHT ) setenv LOADOUT_CFG_ENABLE_LINELIGHT 1`), `envs/bash/global/bashrc` + `envs/zsh/global/zshrc` + `envs/tcsh/global/tcshrc` (at the old GRC site, i.e. before aliases are sourced), `envs/bash/global/aliases.sh` + `envs/tcsh/global/aliases.csh` (`df`)
- Create: `tests/env-linelight` (T2), registered in `tests/run-all` and AGENTS.md's test list
- Docs: AGENTS.md (config vars; tcsh paragraph; a linelight line under Package Behavior), `envs/bash/global/README.md` + `envs/tcsh/README.md` ("Colour": which commands, opt-outs, `command df` / `\df` to bypass), README.md if it mentions GRC

**Interfaces:**
- Produces: bash/zsh: `eval` of `linelight init bash|zsh` output when the switch is truthy and `linelight` is on PATH; non-exported `_loadout_linelight_df=1` when that output defined `df()`. tcsh: the file-sourced adapter (Decision 5) and `_loadout_linelight_df` set when `alias df` names linelight. aliases.sh/.csh choose the `df` form from it (Decision 4) and the var is unset afterwards.

- [ ] **Step 1: Failing tests** in `tests/env-linelight`. Install `@envs env-zsh linelight` into a temp HOME (tools land in the default root under that HOME, which all three shells append to PATH). Drive each shell in a private tmux server (`tmux -L lo-test-linelight-$$`, as `tests/env-tcsh-prompt-resize`) and read `capture-pane -e` (keeps SGR). Per shell (bash, zsh, tcsh):
  - `tty/<shell>`: `ps` output contains SGR; the shell's own lookup shows the wrapper (`type ps` / `whence -f ps` / `alias ps` mentions `linelight run`).
  - `df/<shell>`: `df` output contains SGR and `1G-blocks`.
  - `piped/<shell>`: `df | cat` and `ps | cat` contain no SGR.
  - `status/<shell>`: `diff a b; echo rc=$?` (tcsh `$status`) → `rc=1`.
  - `optout/<shell>`: `~/.config/linelight/adapters.toml` `schema = 1` + `disable = ["df", "ps"]` → `df` plain with `1G-blocks`, `ps` plain.
  - `off/<shell>`: user layer sets `LOADOUT_CFG_ENABLE_LINELIGHT=0` → no SGR anywhere, `df` still `1G-blocks`.
  - `absent/<shell>`: linelight not installed (`@envs env-zsh` only) → plain output, no shell error vocabulary, `df` still `1G-blocks`.
- [ ] **Step 2: Run** → RED.
- [ ] **Step 3: Implement** Files per Interfaces and Decisions 4-5. Startup stays silent: `2>/dev/null` on `init`, nothing printed when linelight is absent.
- [ ] **Step 4: Verify.** `tests/env-linelight`, `tests/env-shell-parity`, `tests/install-env-{bash,zsh,tcsh}`, `tests/env-tcsh-starship`, `tests/shell-typeahead` pass. Manual smoke in a private tmux pane: `ping -c 3 127.0.0.1` streams line by line; Ctrl-C on `ping 127.0.0.1` shows the coloured summary.
- [ ] **Step 5: Commit** `feat(envs): colourize df/diff/dig/free/lsblk/ping/ps/sensors/ss with linelight`.

### Task 4: Final gates and handoff

- [ ] **Step 1:** Full `TMPDIR=/var/tmp tests/run-all` → `All tests passed.`
- [ ] **Step 2:** Tier 3 (payload change): `TMPDIR=/var/tmp tests/run-all --container` → the almalinux8.10 `--full` smoke PASS with the linelight probe.
- [ ] **Step 3:** HANDOFF entry: what shipped and the asset pin; the moved upstream tag; coverage shrank on purpose and `colourify` is gone; the tcsh eval-form upstream bug (loadout sources a file instead); open follow-up: switch tcsh to `eval` only if upstream fixes that form (no need otherwise). Commit with the timing rows: `chore: linelight integration timings; HANDOFF`.
