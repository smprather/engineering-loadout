# Python 3.15 and the Tcl path — design of record

Status: ACTIVE (spike in progress) · Date: 2026-10-10 · Release class: C
Branch: `python-315` (merge to `main` before `./build/release`)

## Context

- Python **3.15.0** final released 2026-10-09 (PEP 790). Stable-release policy
  is satisfied; the ecosystem is ready enough (cp315 wheels ~96.7% of top-360,
  uv Tier 1, ruff py315 support; ty may lag).
- The bundle ships **portable-python 3.14.7**, a custom EL8 source build
  (Clang/LLVM 23, PGO + full LTO + BOLT), imported via
  `build/import-portable-python`, updated only by rebuilding. uv/ruff/ty are
  Astral binaries, but the interpreter is ours.
- The **Astral `python-build-standalone` switch was scouted and queued**
  (HANDOFF 2026-09-02): keep custom 3.14.7, "switch at 3.14.8". It never
  executed. Blockers recorded: Tcl 9.0 (OpenROAD needs Tcl 8.6 `-exact`),
  `_gdbm` missing, CA-trust shim needed, no BOLT.
- The installer enforces `sys.version_info >= (3, 14)` and uses PEP 758
  syntax; the floor is a compatibility promise and does not move.
- JIT: 3.15's JIT is a 7–8% geomean win on x86-64 Linux, still opt-in
  upstream. Default source build is `--enable-experimental-jit=no`; `yes-off`
  compiles it but leaves it off; `PYTHON_JIT=1` enables per process.
- We hold 37 GB free disk; the 3.14.7 build recipe and workspace survive
  (`~/build-work/ppy147`), and the LLVM 23 toolchain is split across
  `~/.local/share/loadout/bin` (binaries; XDG migration) and
  `~/.local/lib` (`clang/23` runtimes, `libbolt_rt_instr.a`).

## Decisions

- **D1 — Adopt 3.15.0 as the bundled interpreter** (class C), built custom:
  same EL8/clang-23/PGO+LTO+BOLT recipe. The Astral switch is *not* part of
  this landing.
- **D2 — JIT is built in, off by default**: configure with
  `--enable-experimental-jit=yes-off`. Enable per workload with
  `PYTHON_JIT=1` (LibreLane/OpenROAD flows, jupyterlab), never globally.
  Rationale: many short-lived Python processes on farm nodes, experimental
  status, perf/gdb cannot unwind JIT frames, and our BOLT layout may shrink
  the marginal gain. Measure before any default flips.
- **D3 — Floor stays `>= 3.14`**; code stays 3.14-compatible; ruff target
  stays `py314` (py315 target is preview-gated upstream).
- **D4 — Tcl path**: the **tcl86 runtime decouple** is the required shim
  *iff* the Astral switch is ever taken; the **OpenROAD Tcl 9 spike** is a
  time-boxed stretch that, if green, removes the 8.6 pairing trap permanently
  (Tcl 9 zipfs) and obviates the shim. Decision rule below.
- **D5 — Branch in-place, merge-then-release**: `build/release` pushes the
  current branch; releasing from `python-315` would publish it. Release is
  cut from `main` after `git merge --ff-only python-315`.

## Workstreams and acceptance

### W1 — Spike A: portable-python 3.15.0 (in progress)

Build in `loadout-build` (container `ppy315-build`, log
`~/build-work/ppy315/build.log`).

- Source `Python-3.15.0.tar.xz` sha256
  `ba4bed1ba346b916890b76d9e320451420aa69f6408997d33c66482eeae3d575` ✓
- Local build patch: `Tools/jit/_llvm.py` `_LLVM_VERSION = "21"` → `"23"`
  (same class as python-build-standalone's version patch; mismatch is a
  printed warning, the lookup regex is the real gate). Candidate upstream
  follow-up if it proves out.
- Configure adds `--enable-experimental-jit=yes-off`; everything else mirrors
  the 3.14.7 recipe (deps: OpenSSL 3.5.6, SQLite 3.53.1, readline 8.3, gdbm
  1.26, zstd 1.5.7, mpdecimal 4.0.1, libffi 3.4.5, Tcl/Tk 8.6.17, Expat
  2.8.0 — tarballs reused from ppy147).
- **Acceptance**: build completes with `profile-bolt-stamp`; staged tree
  passes the phase-2 pipeline (rpaths, scrub, smokes); `python3.15 -VV`
  works; `sys._jit.is_available() == True` and `is_enabled() == False`;
  `PYTHON_JIT=1` flips `is_enabled()`; the BOLT `.dynsym` repair gates on
  import.
- Risk: JIT stencil generation under LLVM 23 (upstream pins 21). If it
  fails, escalate to staging upstream's LLVM 21 externals for the JIT step,
  or fall back to a non-JIT 3.15 build and carry the JIT question forward.
  The 3.15 upgrade itself does not depend on the JIT succeeding.

### W2 — Import + version sweep

- `build/import-portable-python ~/build-work/ppy315/portable-python-3.15.0-el8-clang23`
  (runs the dynsym gate), registry `portable-python` version/archive.
- Sweep the ~339 `python3.14` refs: `./loadout` shim (resolution + bootstrap
  messages), installer uv invocations, tests, `ty.toml`, docs.
  `.loadout-bootstrap` is per-clone/gitignored and re-extracts.
- Regen chain: `gen-installed-sizes` → `gen-content-manifest`; completion
  regen check (no verb/flag change expected).
- **Acceptance**: T1 `./loadout -V` bootstraps 3.15 on a clean clone path;
  `install portable-python` lands `bin/python3.15` + `python3`; uv tools
  install into 3.15 venvs offline.

### W3 — Wheelhouse refresh (cp314 → cp315)

- Re-download the **46 cp314** compiled wheels with every acceptable
  platform tag (pip matches tags exactly); abi3 wheels (`cryptography`,
  `pyqt6`, `psutil`, `pyzmq`, `tornado`, `argon2`) are already
  version-agnostic.
- Rebuild the **3 first-party maturin wheels** (`lefdef_tools`,
  `liberty_tools`, `lln_libparse`) in EL8 via `build/update` rolling-git.
- Prove preservation, not just resolution: per-tool `uv pip compile` closure
  before/after, offline `uv tool install` for every python-tool, end-to-end
  install of an affected tool; `build/vuln-scan` back to CLEAN with
  `accepted: {}`.
- Watch the existing incomplete closures (cicwave, liberty-tools,
  pygwalker) — must not regress.
- **Acceptance**: `python-tool` installs and launchers work under 3.15
  offline; no cp314 ABI wheels remain.

### W4 — JIT measurement

Benchmark `PYTHON_JIT=0/1` on: interpreter startup, LibreLane
`--smoke-test` timing, jupyterlab startup, RSS. Decide whether any wrapper
gets `PYTHON_JIT=1`; record the numbers in this spec/HANDOFF either way.

### W5 — Tcl path (independent of W1–W4)

Time-boxed spike: build OpenROAD 26Q3 against Tcl 9.0.3 + SWIG 4.3 in the
EL8 container (Tcl 9 headers staged from our own `build-tcl.sh` output).
26Q3 upstream already has the `tcl90` discovery fix (#6139) and the Bazel
tcl9 switch (#10094); OpenSTA carries partial Tcl 9 conditionals.

- **Go criteria**: packaged smoke (LEF+DEF, 12 instances / 24 nets), the
  `openroad -python` canary, and standalone `sta`, all on the relocated
  payload.
- If green with a **small patch set**: carry locally, submit upstream PRs
  (OpenROAD and/or OpenSTA), and mark the Astral Tcl blocker resolved by
  migration rather than by shim.
- If not: build the **tcl86 runtime package** (Tcl 8.6.17 `libtcl8.6.so` +
  script tree, `$ORIGIN` rpath) and repoint `openroad`'s deps/RPATH; that
  unblocks the Astral switch.
- **Decision gate for the Astral interpreter switch** (separate, not this
  release): tcl86-or-Tcl9 resolved **and** the candidate Astral 3.15
  artifact verified for `sys._jit.is_available()`, `_gdbm`, Tcl version,
  and CA-trust behaviour.

### W6 — Docs + class C release

- Sync AGENTS, copilot-instructions, README, INSTALLATION, ARCHITECTURE,
  HANDOFF; regenerate shipped-file artifacts in order.
- Gates: `tests/run-all` T1+T2; Tier 3
  `tests/prebuilt-binaries-almalinux8 --full` with `--network=none`;
  librelane smoke; `tests/prebuilt-binaries` probes (JIT toggle, python
  version); dynamic-analysis.
- Release per `docs/RELEASE.md` class C (currency sweep, assurance re-pin,
  post-payload chain, tag, publish, §9 verification) from `main`.

## Out of scope

- Free-threaded builds / stable-ABI free-threading.
- Raising the installer floor or adopting 3.15-only syntax.
- JIT on by default.
- The Astral switch itself (scoped as its own future landing once W5's
  decision gate is met).
- Opportunistic tool bumps beyond the wheelhouse ABI refresh.

## Execution log

- 2026-10-10: branch `python-315` created; spec committed (`bc9474c`). Spike A
  launched in container `ppy315-build` (detached) with the JIT patch and
  `--enable-experimental-jit=yes-off`; log at `~/build-work/ppy315/build.log`.
- 2026-10-11: **first attempt failed at `.jit-stamp`** (rc=2 after ~2 min):
  CPython's JIT generator runs the *bootstrap* Python
  (`python3.14 ./Tools/jit/build.py ...`), which resolved to the
  loadout-installed interpreter mounted at `/hostllvm/bin` — but the mount
  carried only binaries, not `libpython3.14.so.1.0`, so it died with
  `error while loading shared libraries ... Error 127`. Root cause: the XDG
  migration split the old `~/.local` toolchain root (bin in the loadout tree,
  `lib/clang/23` + `libbolt_rt_instr.a` left in `~/.local/lib`).
  Fix: hardlink-merge the loadout `lib/` into the combined toolchain root
  (`ppy315/hostllvm`). `python3.14 -VV` and the clang profile-runtime lookup
  both pass in-container now.
- 2026-10-11: **supervised run** — `supervise.sh` drives build → pipeline →
  repair → audit with narrow auto-recovery (JIT-stencil failure → retry once
  with JIT off; memory-pressure failure → retry once at `-j8`), writes
  `/work/STATE` + timestamped `/work/supervisor.log`, and a terminal
  `/work/RESULT` (`OK …`/`FAILED …`). Host helpers: `status.sh` (one-shot) and
  `wait.sh` (blocks until terminal). An async subagent watcher (delegate) is
  attached to `wait.sh`, so build completion/failure wakes the working
  session without human polling.
