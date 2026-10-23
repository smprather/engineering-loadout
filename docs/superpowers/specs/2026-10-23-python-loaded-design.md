# python-loaded — design of record

Status: DRAFT (awaiting approval) · Date: 2026-10-23 · Release class: B

## Context

Every offline script on this box currently has two bad choices: write it against
the shared loadout Python and hope each third-party package is in some tool's
venv, or vendor wheels by hand. `@shared` installs 14 independent `uv tool`
venvs; none of them is an import library. The EL portable Python ships with an
empty site-packages and no additional packages.

The request: one separately-installable package that is a single Python
environment — the EL portable Python 3.15 plus a maintained package set — with
its own `bin/`, nothing linked into `<prefix>/bin`, automatic correctness across
EL Python updates, and a build-time EL8 wheel pipeline that carries the shared
libraries any native extension needs.

## Goals

- `./loadout install python-loaded` produces a venv at
  `<prefix>/share/python-loaded/venv` whose `bin/python3` satisfies
  `#!/abs/path/to/python3` and can import every maintained top-level package.
- No file from the suite is linked or copied into `<prefix>/bin`.
- The maintained artifact is a short `requirements.in` of tops. Everything else
  is resolver output in a fully pinned, hashed `requirements.lock.txt`.
- Patch-level EL Python updates require no action (CPython's ABI is stable
  within a minor). Minor-level updates (3.15 → 3.16) are a hard, explicit error
  until the release regenerates the lock and wheelhouse.
- Every ELF in the installed environment resolves all non-host `NEEDED` entries
  from libraries shipped alongside it, with no dependence on `LD_LIBRARY_PATH`.
- Fully offline install from a suite-private wheelhouse.

## Non-goals

- A general-purpose `pip install` environment. Users add packages by editing
  `requirements.in` and running the build; the venv on disk is replaceable.
- Isolating suite packages from each other. This is one shared environment: a
  version conflict between two tops is resolved once, at lock time.
- Host-Python compatibility. The suite runs only on the bundled interpreter.
- CUDA/GPU. Excluded by decision D5.
- Windows/macOS (retired project-wide).

## Anti-goals

- Linking suite console scripts into `<prefix>/bin` — a suite upgrade must never
  break an unrelated loadout tool, and a shared name (`rich`, `watchfiles`,
  `uvicorn`) must never shadow a host or loadout command.
- Resolving on the user's host at install time. The host may be EL9 with newer
  glibc tags; resolution happens in AlmaLinux 8.
- Rebuilding the venv on every patch-level interpreter bump (unnecessary churn,
  and a failed rebuild would take a working environment down).
- Silently reinstalling from a stale ABI wheelhouse after a minor bump.
- Letting the suite's pins change what an unrelated `python-tool` installs (D8).
- Shipping a lock whose hashes do not describe the bytes actually installed (D10).

## Decisions

**D1 — One package, new kind `python-suite`.** Registry entry:

```json
"python-loaded": {
  "kind": "python-suite",
  "version": "2026.10.23",
  "standalone": true,
  "platforms": ["linux"],
  "depends": ["portable-python", "uv"],
  "requirements": "payload/python-loaded/requirements.in",
  "lock": "payload/python-loaded/requirements.lock.txt",
  "wheels_dir": "payload/python-loaded/wheels",
  "tags": ["python", "suite"],
  "description": "Curated EL8 Python 3.15 import environment; own bin, not on PATH"
}
```

No `bins` field: nothing is claimed in the shared bin. `wheels_dir` feeds
transaction sizing and doctor (D11). `standalone: true` is honored by the three
synthetic sweeps (D9).

**D2 — Wheels + lock at install time, not a prebuilt venv tarball.** A venv
embeds absolute paths and does not survive `--dest-dir`; the repo already has an
installer precedent for offline wheel installs. The venv is created **at its
final absolute path**, so console-script shebangs are correct without
relocation tricks. To keep upgrades from renaming it, the final path is a
versioned directory behind a stable symlink:

```
<share>/python-loaded/
  versions/2026.10.23-<lockhash8>/venv/
  venv -> versions/2026.10.23-<lockhash8>/venv
  suite.lock.json
```

The user-facing shebang target is `.../python-loaded/venv/bin/python3`; inside,
`uv` emitted absolute shebangs into the versioned directory, which is never
renamed. Upgrade builds the new version directory, then atomically replaces the
`venv` symlink; the previous directory survives until the swap succeeds, then is
removed. `uv venv --relocatable` is rejected: it replaces the absolute-python
shebang with sh trampolines, which is not the contract we want.

**D3 — Resolution and wheel acquisition happen in AlmaLinux 8, and Docker is
mandatory for a refresh.** The resolver must see glibc 2.28 and cp315 only.
`build/build-python-loaded.sh` exits non-zero when no Docker/EL8 runtime is
available; `./build/update python-loaded` propagates the failure and leaves the
existing lock and wheelhouse untouched. No host-side fallback.

**D4 — Patch vs minor is a hard boundary, not a rebuild trigger.** Stamp is
`{abi, lock_sha256}`, where `abi` is `sys.implementation.cache_tag`
(`cpython-315`). Patch change → same abi → skip. Minor change → installer fails
before invoking `uv`:

```
python-loaded: suite lock is cpython-315, interpreter is cpython-316.
Regenerate the lock and wheelhouse in the same release that bumps
portable-python (`build/build-python-loaded.sh`).
```

**D5 — CPU only.** Drop `nvidia-nccl-cu12`; use `xgboost-cpu` (module name
`xgboost`, no NCCL dependency). No CUDA wheels in the payload.

**D6 — `requirements.in` is tops only; sdist builds are an explicit allowlist.**
The 130-line starter list collapses to the tops in Appendix A; deps are never
maintained by hand. A top or transitive dep with no EL8/cp315-installable wheel
must either be on `build/python-loaded-sdist-allowlist.txt` (built in the
container; currently `PyYAML`, `python-ldap`, `pyeda`) or the build fails naming
it. Exclusions are made by editing `requirements.in`, never by filtering the
lock: the lock must reproduce the file. `uWSGI` moves out of the suite — it is a
server executable, not an import library, and does not fit the wheel model; it
is a candidate standalone binary package. Dropped as wrong or abandoned: `bst`
(a toy binary-search-tree package, not BuildStream), `pdfutil` 0.0.1, `pdf2jpg`
1.1. `importlib_metadata`/`zipp` stay out of the tops even though upstream
packages still pull them.

**D7 — Repair is `auditwheel repair`, not a hand-rolled patchelf pass.**
auditwheel already does what the naive recipe gets wrong: per-file RPATH depth
(`numpy/_core/...so` → `$ORIGIN/../../numpy.libs`), RUNPATH on each bundled
dependency, content-hash soname rewriting so two packages cannot bind to
whichever `libssl` loaded first, and wheel retagging to `manylinux_2_28`. It
refuses to bundle policy-blacklisted host libraries (glibc family,
`libstdc++`/`libgcc_s`, `libpython`), which is exactly the intended host set.
Anything auditwheel cannot resolve is a hard build failure naming the library.
Repair runs before hashing (D10). Pure/`abi3` wheels pass through unchanged.

**D8 — Suite-private wheelhouse.** `payload/python-loaded/wheels/`. The shared
`payload/<platform>/wheels` is used by `install_python_tools` with **no version
pins**; adding the suite's newer numpy/pandas/matplotlib would silently change
what `cicwave`, `pygwalker`, `time-plot`, `jupyterlab`, `ipython`, `librelane`
and friends install on their next run. The suite therefore owns its own
directory, with the same chunking and size conventions. Duplicate bytes are the
price; hermetic tool installs are worth it.

**D9 — Explicit install only.** `python-loaded` joins neither `@shared` nor
`@shared-all` (the documented `./loadout install @shared-all` must not grow a
~1.3 GB venv). A new registry flag `standalone: true` is honored by `@shared`,
`@shared-all`, and `@all`; the `@all` doc comment is updated to say "everything
except standalone packages", and `./loadout list` marks them.

**D10 — Hashes describe the final, repaired bytes.** Acquisition records the
exact wheel filename chosen for every requirement. auditwheel rewrites any wheel
that needs it. The lock is then emitted with `--hash=sha256:<digest of the final
file>` per requirement, and installs run `--require-hashes`. A verifier
recomputes every hash against the private wheelhouse. There is no second resolve
and no post-hash rewrite.

**D11 — Artifact attribution.** `_artifact_paths` gains a `wheels_dir` branch
that unions every `*.whl` / `*.whl.part-*` under the resolved directory, so
transaction size and `doctor --verify` see the suite's real footprint.
`gen-installed-sizes` already scans `payload/`, so it needs no change.

**D12 — Versioning is CalVer of the lock, not any one package's version.**
There is no single upstream version to report: the suite is a pinned set. The
registry `version` is `YYYY.MM.DD`, with `.postN` appended only when a second
lock lands on the same day (`2026.10.23.post1`). This parses correctly through
the existing no-downgrade guard, sorts lexically, and is honest in `list`/`info`.

- The authoritative version set is `requirements.lock.txt`; its header records
  `# python-loaded lock <YYYY.MM.DD> (<abi>)`. A diff of that file is the
  changelog for a suite upgrade.
- The interpreter version is **not** embedded in the package version. It lives
  in the lock header, `suite.lock.json`, and `./loadout info python-loaded`,
  because a leading `3.15-…` parses as a downgrade-then-upgrade.
- `./loadout info python-loaded` prints: lock date, abi, top count, pinned
  distribution count, private wheelhouse size, and the installed stamp.
- `build/update python-loaded` bumps the version only when the emitted lock's
  sha256 differs from the shipped one; a no-op resolve leaves the version alone.
- `build/update --list-outdated` cannot compare the suite to an upstream, so it
  reports staleness by cadence (`auto_update_interval`) and names the current
  lock date instead of inventing a version comparison.

## Layout

```
payload/python-loaded/
  requirements.in                  # maintained tops, one per line
  requirements.lock.txt            # pinned + hashed, generated
  wheels/<dist>-<ver>-<tags>.whl   # private, repaired, chunked by convention
  sdist-allowlist.txt              # names allowed to build from source
<prefix>/share/python-loaded/
  versions/<lockdate>-<hash8>/venv/
    bin/python3                    # the shebang target (via the symlink below)
    bin/<console scripts>
  venv -> versions/<lockdate>-<hash8>/venv
  suite.lock.json                  # stamp: schema, abi, python, lock_sha256, built_at
```

`python-loaded` exports nothing and adds nothing to `PATH`. Consumers who want
the console scripts on `PATH` do it themselves with the absolute venv path.

## Build pipeline — `build/build-python-loaded.sh`

Runs in `almalinux:8.10` (same image/build shape as
`tests/prebuilt-binaries-almalinux8`), repo bind-mounted read-only and copied
into `/work`, network enabled only for this step.

1. Extract the EL8 portable Python from `payload/.../portable-python-*.tar.bz2`
   into a scratch prefix. Use the bundled `uv`.
2. Pre-build the allowlisted sdist distributions into wheels with the EL8
   toolchain (`gcc-toolset-14`, `openldap-devel`, `cyrus-sasl-devel`,
   `openssl-devel`, `zlib-devel`, `libffi-devel`).
3. Resolve `requirements.in` → exact versions with
   `uv pip compile --python-version 3.15 --python-platform x86_64-manylinux_2_28
   --only-binary :all:` plus the pre-built wheels as a local `--find-links`
   source. No sdist may appear. This stage produces pins, not the shipped lock.
4. Acquire each pinned wheel on the EL8 interpreter and copy it into the private
   wheelhouse. A wheel tagged above glibc 2.28 is a hard failure.
5. Repair with `auditwheel repair --plat manylinux_2_28_x86_64` where needed;
   unrepaired wheels are verified to have no external non-host `NEEDED`.
6. Emit `requirements.lock.txt` from the final wheelhouse bytes, with per-wheel
   sha256 hashes.
7. Verify from a clean throwaway venv **with `env -i PATH=/usr/bin:/bin`**:
   install offline with `--require-hashes`, import every top, `ldd` every ELF,
   and for every `bin/*` text script assert it is executable and its shebang
   names the versioned venv interpreter. Run `--help` only for the curated CLI
   allowlist in `build/python-loaded-cli-allowlist.txt` (`pylint`, `uvicorn`,
   `django-admin`, `watchmedo`, `pygmentize`, …). Entry points that start a
   server, open a socket, or define no `--help` are not executed.
8. Bump the registry `version` to the lock date, then run the payload manifest
   chain (`gen-installed-sizes`, then `gen-content-manifest`) and
   `build/strip-all-elf-binaries`.

Timing: the script prints its wall time; when invoked from `build/release` the
gate duration lands in `assurance/release-timings.tsv` as usual.

## Install behavior — `install_python_suite`

New phase, immediately after `install_portable_python`, before
`install_python_tools`.

1. Skip unless `python-loaded` is selected.
2. Resolve `<prefix>` (HOME keeps `.local`; `--dest-dir` does not) and read
   `payload/python-loaded/requirements.lock.txt`.
3. Read the interpreter's `sys.implementation.cache_tag` and compare with the
   lock header. Mismatch → record `FAIL` with D4's message, change nothing.
4. Stamp match (`abi` + lock sha256) and a working `venv/bin/python3` → `SKIP`.
5. Build `<share>/python-loaded/versions/<new>/venv` at its final absolute path,
   then swap the `venv` symlink atomically. A failed install leaves the previous
   version in place.
6. `uv venv --python <prefix>/bin/python3.15`, then
   `uv pip install --python <new>/venv/bin/python --no-index --find-links
   <private wheels> --no-cache --offline --require-hashes -r requirements.lock.txt`.
7. Write `suite.lock.json`; remove superseded version directories after the
   swap succeeds.
8. Record a result row. Missing wheel, missing lock, or missing `uv` is `FAIL`,
   not a silent skip.

## Update behavior

- **EL Python patch bump.** Stamp abi unchanged → no action. The venv's
  `bin/python3` symlink already resolves through the replaced
  `<prefix>/bin/python3.15`; cp315 extension modules remain valid.
- **EL Python minor bump.** The release that bumps `portable-python` must rerun
  `build/build-python-loaded.sh` and ship the new lock + wheels. Until then the
  installer refuses. If a suite venv is present on disk but the package is not
  in the selection, `install_portable_python` prints a one-line warning naming
  the mismatch (it changes nothing).
- **Full suite update.** `./build/update python-loaded` runs the build pipeline
  above. It is an `AUTOMATED` entry with an explicit cadence so the no-argument
  sweep does not rebuild a multi-hundred-MB wheel set unattended unless due. It
  hard-fails without Docker (D3).
- **Upgrade.** `./loadout upgrade python-loaded` re-runs the install phase; a
  new lock hash forces a rebuild from the newly shipped wheelhouse.

## Verification

New `tests/python-suite` (T1, added to `build/release`'s gate list), with a 2 GB
disk preflight; gate duration recorded in `assurance/release-timings.tsv`:

- Offline install into a temp HOME; assert `sys.prefix` is the versioned suite
  venv and `sys.implementation.cache_tag == cpython-315`.
- Every distribution in the lock reports its pinned version via
  `importlib.metadata`; a curated dist→module map is imported for the tops
  (`Django→django`, `PyYAML→yaml`, `Pillow→PIL`, `scikit-learn→sklearn`, …).
- Every ELF under `site-packages` passes `ldd` under `env -i`.
- No console-script name from `venv/bin` exists in `<prefix>/bin`.
- A console script's shebang names the versioned path, and running it through
  the stable `venv/bin` symlink works after the symlink swap.
- Second install with an unchanged stamp is a `SKIP` and leaves the venv's mtime
  unchanged.
- A stamp rewritten to `cpython-316` makes the installer exit non-zero with the
  D4 message and leaves the venv untouched.
- `--dest-dir` install produces a working interpreter at the alternate prefix.

Extend `tests/wheelhouse-closure` with a suite branch whose predicate is
"installable by cp315 on `el8.x86_64`":

- `abi3`, or pure Python with `plat == any`, or pure Python whose platform tag
  set contains a manylinux tag at glibc ≤ 2.28, or `cp315` with such a platform
  tag. (The current helper wrongly rejects `xgboost-cpu`'s legitimate
  `py3-none-manylinux_2_28_x86_64`; fix the helper for all users.)
- Index chunked `.whl.part-NNN` wheels by rejoining to a temp file for metadata.
- Every lock entry must match a wheel in the **private** wheelhouse at the exact
  version, and every hash must recompute.

This is what makes a stale lock/wheelhouse pairing a gate failure instead of a
user-facing install failure.

## Risks

- **Size.** Excluding NCCL, the suite wheel set is roughly 350 MB (pyarrow ~40,
  xgboost-cpu ~57, scipy ~38, numpy ~19, pandas ~13, plus the rest); the
  installed venv is roughly 0.9–1.3 GB. Measure the first build and record it.
  The private wheelhouse duplicates distributions the shared one also carries.
- **Repair surprises.** Most wheels are self-contained; the repaired set is
  expected to be small (`python-ldap`, possibly `pyeda`). auditwheel turns an
  unknown into a named failure, not a broken install.
- **Resolver drift.** A new release of a top can pull a new transitive dep with
  no cp315 wheel. The build pipeline fails at step 3/4 rather than shipping a
  broken lock.
- **Docker dependency.** A release that bumps the interpreter cannot regenerate
  the suite without an EL8 container; that is a deliberate hard stop (D3).

## Open items for the builder

- Exact `uv pip compile` flag spelling for the bundled uv, and whether `uv lock`
  is a better fit for the version-selection stage. The hash-emitting stage is
  ours regardless (D10).
- Where the `standalone` flag is surfaced (`list`, `info`, transaction table).
- Chunking threshold for the private wheelhouse (reuse the existing payload
  rule).
- The initial contents of `build/python-loaded-cli-allowlist.txt`; entries are
  added only after a script is shown to answer `--help` without side effects.

## Appendix A — maintained tops

Web / services: `Django`, `django-auth-ldap`, `django-filter`, `Flask`, `dash`,
`litestar`, `litestar-htmx`, `uvicorn`.

Data: `numpy`, `pandas`, `scipy`, `matplotlib`, `scikit-learn`, `statsmodels`,
`xgboost-cpu`, `shapely`, `pyarrow`, `openpyxl`, `pikepdf`, `img2pdf`, `pillow`,
`nltk`, `graphviz`.

ML / telemetry: `evidently`.

AWS: `boto3`.

Tooling: `pylint`, `pylintfileheader`, `pydantic`, `rich`, `typer`, `httpx`,
`requests`, `jsonschema`, `SQLObject`, `PyMySQL`, `pyeda`, `ruamel.yaml`,
`python-dotenv`, `psutil`, `pexpect`, `prettytable`, `more-itertools`,
`tenacity`, `setproctitle`, `websockets`, `uvloop`, `httptools`, `watchfiles`,
`watchdog`.

Deferred: `kaleido` and static Plotly image export (needs a ~300 MB
`chrome-headless-shell` runtime; revisit as its own optional package).

Dropped: `nvidia-nccl-cu12` (D5), `uWSGI` (D6, candidate standalone binary),
`bst`, `pdfutil`, `pdf2jpg` (D6), and every name that is only a dependency.
