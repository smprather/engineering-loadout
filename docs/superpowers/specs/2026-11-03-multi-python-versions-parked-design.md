# Multiple Python versions — decision record and parked design

Status: PARKED (not being built) · Date: 2026-11-03 · Decision: case-driven

This records a design conversation held 2026-11-02/03, so that if a real case
ever needs a second Python, the work starts from what was already learned. It
has three parts: the decision and the triage that applies it (§1–§2); the
facts, both stated and measured (§3–§5); and the design that was worked out
and then parked (§6–§9).

Labels: **[user]** = the user said it. **[my call]** = the assistant's decision,
open to override. **[guess]** = an assumption nobody confirmed. Everything under
"Measured" was run on the CachyOS dev host. uv measurements used the installed
launcher's **uv 0.12.17** (the registry has since moved to 0.13.5), and uv's
behavior moves fast, so **re-measure any uv row before relying on it.**

## 1. Decision

EL stays single-version: the bundled CPython (3.15 today) plus python-loaded
built on it. **No second interpreter is added on speculation.** Another version
is added only when a specific script arrives that cannot move to EL's Python
(triage in §2), and then only that version. **[user]**

Why:

- The only input so far is a general comment ("you need to support multiple
  versions of Python"). No specific script is behind it, and there is no data
  on which versions scripts actually need. **[user]**
- Moving a script's own code forward is now cheap: one prompt to an AI agent.
  **[user]** Breakage between minors is mostly loud (ImportError or SyntaxError
  at startup), so an up-rev is low-risk even for a script with no tests.
- Each extra version has a real cost (§6.5): about 870 MB installed for its
  python-loaded, plus its interpreter; about 190 MB of git payload per refresh;
  one more EL8 container build; and, for old versions, shipping code that no
  longer gets security fixes.
- Nothing closes the door. Adding a version later only adds things; nothing
  already in place has to change (§6.8).

How we got here, briefly. The first proposal was "Way A": PEP 723 scripts run
by uv, plus EL-shipped modulefiles as "Way B". The user then supplied three
facts: the site is strictly air-gapped, engineers prefer a prebuilt curated
environment (python-loaded), and they will not build packaged applications. That
moved the center to "python-loaded per version" (§6.5). The user's final call
was to drop speculative support altogether and let individual cases drive it,
relying on AI up-revs. **[user]** The user also corrected one assumption: EDA
tools ship their own Python builds, so tool bindings are not a reason for EL to
add interpreters (§2).

## 2. Triage when a real case arrives

1. **Can the script's code move to EL's Python?** Up-rev it with an agent.
   Typical breakage is stdlib removal:
   - 3.12 removed `distutils`, `imp`, `asynchat`, `asyncore` and `smtpd`.
   - 3.13 removed the PEP 594 "dead batteries" (`telnetlib`, `cgi`, `cgitb`,
     `crypt`, `pipes`, `audioop`, `aifc`, `chunk`, `imghdr`, `sndhdr`,
     `mailcap`, `nntplib`, `nis`, `spwd`, `sunau`, `uu`, `xdrlib`,
     `ossaudiodev`, `msilib`) and also `lib2to3`.

   `telnetlib` is likely common in lab and instrument scripts. **[guess]**
2. **Is it blocked by a dependency that has no build for EL's Python?** That is
   temporary and usually clears within months of a new minor. Wait, or exclude
   the package; `evidently` in python-loaded is the precedent. **Do not add an
   interpreter for this.** The gap is widest right after EL moves to a new
   minor. As of 2026-11, a month after 3.15.0, EL itself has librelane,
   parity-plot and pygwalker `disabled`, and `evidently` excluded from
   python-loaded, for exactly this reason.
3. **Is it blocked by something that can never move?** One example is a script
   nobody is allowed to change, such as vendor or foundry collateral.
   **[guess]** This is the trigger. Add that one version (§6), its modulefile,
   and a python-loaded for it only if the case needs packages.

**Not a trigger: EDA tool Python bindings.** EDA tools ship their own bound
Python builds **[user]**, so a script that needs a tool's API runs on that
tool's Python.

## 3. Users and constraints (as stated)

- Thousands of electrical engineers at a large EDA company, with scripts across
  the organization that need different Python versions. **[user]**
- Strictly offline, for foundry-legal reasons: no internet. An internal PyPI
  mirror is not assumed. **[user]**
- The engineers are not software engineers. They understand Environment
  Modules. They will not produce a `uv tool install`-able application; AI may
  change that, but it has not yet. **[user]**
- They like python-loaded, one prebuilt environment with a curated package set.
  That is how they would consume multi-version support. **[user]**
- The habit for a version-specific script is a wrapper that runs `module load`
  for the right Python and then executes a script starting with
  `#!/usr/bin/env python3`. **[user]**
- EL is deployed as a shared, read-only tree, and engineers install nothing.
  Whoever installs EL (admins, team leads) may also write modulefiles. tcsh is
  the majority shell. **[user confirmed these guesses]**
- The user does not require EL to ship modulefiles, but is open to it with a
  rationale (§6.3). They asked for pushback on anti-patterns rather than
  following their framing. **[user]**

## 4. EL facts this rests on (2026-11-03)

- **Bundled interpreter:** portable-python 3.15.0, an EL8 clang-23 build with
  PGO/LTO/BOLT, installed at `<prefix>/bin/python3.15`. Patch updates land in
  place.
- **uv launcher** (`build/uv-launcher.sh`): exports `UV_PYTHON=<prefix>/bin/python3`
  unless the caller already set `UV_PYTHON`. It does not set it for `uv pip`,
  or for `uv run` inside an active virtualenv, because `UV_PYTHON` outranks
  `VIRTUAL_ENV` (measured earlier and documented in AGENTS.md).
- **python-loaded** (design: `2026-10-23-python-loaded-design.md`):
  - 50 top-level packages in `payload/python-loaded/requirements.in` resolve
    to a hashed lock of 130 pins and 131 private wheel files (pyarrow is
    chunked).
  - Size: 243 MB in git, 869 MB uncompressed. Of the 243 MB, 187 MB is
    cp315-specific, 58 MB pure-Python and 10 MB abi3/py3-native.
  - Three sdists are compiled in EL8: PyYAML, python-ldap and pyeda. The build
    is `build/build-python-loaded.sh` inside `almalinux:8.10`.
  - The lock header `# abi: cpython-315` ties it to one interpreter, and the
    installer refuses a mismatch.
  - It installs `<prefix>/share/python-loaded/venv` → `versions/<lockdate>-<hash8>/venv`.
    The venv's python → `<prefix>/bin/python3`, a stable path, which is why
    patch updates need no rebuild.
  - The documented user shebang target is the stable venv path.
- **modules:** Environment Modules 5.6.1, opt-in through
  `LOADOUT_CFG_USE_LOADOUT_MODULES=1`. The site also runs its own Environment
  Modules; its version is unknown.

## 5. Measured

### uv and interpreters

All runs used `UV_OFFLINE=1` and `UV_PYTHON_DOWNLOADS=never`, with
python-build-standalone (PBS) interpreters taken from uv's managed directory or
copied out of it.

| # | Setup | Result |
|---|---|---|
| U1 | `UV_PYTHON=<abs path to 3.12>` with `uv init` | `.python-version` = `3.12`, `requires-python = ">=3.12"`. This is the right outcome. |
| U2 | Project pinned to 3.12, `UV_PYTHON=<abs 3.13>`, `uv run` | Ran 3.13 and **silently rebuilt `.venv` on 3.13**. `UV_PYTHON` overrides `.python-version`. |
| U3 | Same project, `UV_PYTHON` unset | Back on 3.12, after rebuilding `.venv` again. |
| U4 | PATH-first `python3` → a uv-managed 3.12, `UV_NO_MANAGED_PYTHON=1`, `uv init` | Wrote `3.14`: uv skipped the PATH-first 3.12 and used the system `/usr/bin/python3`. Hypothesis: uv recognized the symlink target as a managed install and excluded it. **PATH alone does not steer uv.** |
| U5 | Only 3.12 on PATH, project pins 3.13, no managed pythons | `error: No interpreter found for Python 3.13 in search path`. It never tries to download. |
| U6 | `UV_PYTHON_INSTALL_DIR` → a **read-only** (`chmod a-w`) dir holding `cpython-3.12.13-…` and `cpython-3.13.16-…` | `python list`, `python find`, `run`, `init` and `venv` all work. Nothing needs to be written. |
| U7 | `uv python list` with that dir set | Lists everything: system pythons, EL's 3.14 and `~/.local/bin`. Discovery cannot hide other versions; only an explicit request isolates one. |
| U8 | `UV_PYTHON=3.12` (a version request) with the read-only install dir, then `uv init` and `uv run` | `.python-version` 3.12; `.venv/bin/python` → `<dir>/cpython-3.12.13-…/bin/python3.12`, the **patch-named** dir. |
| U9 | Added a relative minor link `cpython-3.12-linux-x86_64-gnu → cpython-3.12.13-…` in that dir | uv ignored it; the venv still points at the patch dir. uv's own managed dir uses an absolute minor link that uv created itself, and U2's venv pointed through that link. |
| U10 | `UV_PYTHON=3.12 uv python find` | Returned 3.13.16: `UV_PYTHON` does not feed `python find`. The positional form `uv python find 3.12` works. |
| U11 | Interpreter copied to a stable per-minor dir `opt/python/3.12/`, then `UV_PYTHON=<that>/bin/python3` with `uv venv` and `uv init` | The venv's python → `opt/python/3.12/bin/python3`, `home = opt/python/3.12/bin`, and `.python-version` = 3.12. **A venv built from a stable path keeps that path**, so it survives in-place patch updates. |
| U12 | `uv python pin` with no arguments | Inside a project with `.python-version`, it prints the pin and exits 0 (it warns if the pin cannot be resolved). With no file, it exits 2 with `No Python version file found`. **A project that only has `requires-python` reads as "no pin."** |

### PEP 723 scripts

| # | Setup | Result |
|---|---|---|
| P1 | `#!/usr/bin/env -S uv run --script`, `requires-python = "==3.12.*"`, no dependencies, read-only install dir | Ran 3.12.13. A cached run took 0.049 s. |
| P2 | As P1 plus `dependencies = ["rich"]`, `UV_NO_INDEX=1`, `UV_FIND_LINKS=<dir of 4 wheels>` | First run 0.25 s (`Installed 4 packages in 2ms` on stderr); later runs 0.08 s; cache 7.2 MB. |
| P3 | `uv lock --script` | Writes `<script>.py.lock` with exact pins. |
| P4 | A dependency missing from the wheel dir | Refuses and never downloads. The message misleadingly blames the cache ("numpy was not found in the cache … the network was disabled"); a launcher hint would help. |

### python-build-standalone 3.12.13 (what uv downloads)

- Highest GLIBC symbol version is 2.17 (`readelf -V`), so it runs on EL8 and
  newer hosts.
- The install dir is 113 MB, not stripped, and bundles `libtcl9.0`/`libtcl9tk9.0`.
- Layout is `bin/ include/ lib/ share/ BUILD`. `bin/` holds `python`,
  `python3`, `python3.12`, `pip`, `pip3`, `pip3.12`, `idle3`, `pydoc3`, `2to3`
  and `python3.12-config`.

### Environment Modules 5.6.1 (man pages in the installed tree)

- `extended_default` defaults to 1: `module load python/3.12` matches
  `python/3.12.13`, choosing the highest match unless an explicit default is
  among the matches.
- `implicit_default` and `auto_handling` default to 1, and `conflict_unload`
  defaults to 0. Loading a second member of a family therefore errors unless
  `conflict_unload` is enabled or the user runs `module switch`.
- `family python` allows only one member to be loaded, and it sets
  `MODULES_FAMILY_PYTHON` and `LMOD_FAMILY_PYTHON`.
- `envml [MODULE_ACTION]... [--] COMMAND [ARG]...` runs one command in a
  module-adjusted environment.

## 6. Parked design (for the day a case triggers it)

### 6.1 Interpreters

- **Source:** python-build-standalone `install_only_stripped`,
  `x86_64-unknown-linux-gnu`, the builds uv itself downloads. Verify them
  against the release's published sha256 sums, and import them inside
  `build/build-shell`, since payload-mutating work stays in the container.
  They are **not** built through the portable-python PGO/LTO/BOLT pipeline,
  which would be hours of build work per version for no benefit here.
  **[my call]**
- **CA trust:** give them the same treatment as portable-python
  (`docs/PYTHON-CA-TLS.md`): inject the sitecustomize that probes the host CA
  store.
- **Closure:** run `tests/needed-closure` over them. PBS links little beyond
  glibc, but tkinter's Tk pulls in X11 libraries (gui_libs).
- **Layout:** one **stable per-minor path**, with patch releases updated in
  place by EL's atomic install, e.g. `<prefix>/opt/python/3.12/` (name TBD).
  **[my call]**
  - Every venv records its interpreter's path (U8, U11, and python-loaded's
    venv → `<prefix>/bin/python3`), so a patch-named path would break every
    venv at each patch upgrade.
  - This is the Debian/Fedora model, and what EL already does for 3.15.
- **uv discovery tension:** uv recognizes interpreters in
  `UV_PYTHON_INSTALL_DIR` only under patch-named dirs and ignores a minor link
  we supply (U9). The module path doesn't need that dir, because an explicit
  interpreter path works (U11). Uses with no module, such as PEP 723 scripts
  (§6.6), would. One untested idea is patch-named entries in a uv-format dir
  that point at the stable dirs; first measure which path the venv records.
- **Size and storage:** about 35 MB compressed per interpreter (an estimate,
  not measured). Whether interpreters ship in the git payload or as fetched
  release assets, like `nvim-plugin-stash`, is open (§8).

### 6.2 Selecting a version

Every selector uses the same interpreters:

1. Modulefiles: `python/3.12` for the bare interpreter and `python-loaded/3.12`
   for the curated environment. This matches the existing wrapper habit.
2. An absolute shebang to that version's python-loaded venv. This is how
   python-loaded is already documented to be used, and it needs no module and
   no wrapper.
3. PEP 723 with `uv run --script`. Optional and secondary (§6.6).

### 6.3 Modulefiles

- **EL generates and ships them** (`<prefix>/share/modulefiles/python/<ver>`,
  `python-loaded/<ver>`). Sites run `module use` on that dir, or wrap the
  entries in their own names. **[my call]** Rationale:
  - The content is coupled to EL's layout and uv wiring. Hand-written copies
    tend to repeat the anti-patterns in §9.
  - Generated files can derive the prefix from their own location, so they
    survive the tree moving.
  - They are regenerated whenever the layout changes; hand copies rot quietly.
- **Content:**
  - `family python`.
  - Prepend PATH with a bin dir holding only `python`, `python3`, `python3.X`,
    `pip`, `pip3` and `pip3.X`.
  - Set EL's uv pin (§6.4).
  - **Nothing else.** Never `PYTHONPATH`, `PYTHONHOME` or `LD_LIBRARY_PATH`:
    they leak into every child Python, including EDA tools' bundled Pythons
    and EL's own 3.15 tools.
- **Naming:** wrappers should say `python/3.12` and let `extended_default` pick
  the newest patch. The minor version is the compatibility promise, and
  patches move forward for security fixes. **[my call]** Exact names such as
  `python/3.12.13` may exist, but whether old patches are retained is open
  (§8).
- **Moving trees:** resolve the modulefile's real path at load time, so that a
  `latest` symlink moving under a running job does not change an
  already-loaded environment.
- **Site compatibility:** the site's own Environment Modules must support
  `family` (believed to need 5.1 or newer; verify). Otherwise use
  `conflict python`.
- **Wrapper ergonomics:**
  - tcsh scripts get `module` from `/etc/csh.cshrc`. Bash scripts may need
    `source $MODULESHOME/init/bash`. **[guess]**
  - A possible replacement for wrappers is
    `#!/usr/bin/env -S envml python/3.12 -- python3`. Unverified: it needs
    `env -S` (coreutils 8.30 or newer, which EL8 has) and `envml` on PATH.

### 6.4 uv wiring

Goal: after `module load python/3.12`, `uv init` writes 3.12 (U1, U11) and uv
never tries to download.

- **The module must not export `UV_PYTHON`.** It overrides project pins (U2),
  and inside an activated venv it redirects `uv pip` into the shared
  interpreter.
- Instead, the module exports an EL-specific variable (name TBD, e.g.
  `LOADOUT_PYTHON=<abs path>/opt/python/3.12/bin/python3`). The uv launcher
  uses it as its pin source in place of `<prefix>/bin/python3`, and keeps its
  existing carve-outs. The launcher always sets `UV_PYTHON_DOWNLOADS=never`.
- A user's own uv, not EL's launcher, bypasses all of this. The module could
  also export `UV_PYTHON_DOWNLOADS=never` to cover that case.
- When the module and a project's pin disagree, the behavior is open (§8, Q2).
  One way to detect a pin is `uv python pin` with no arguments (U12). It
  catches `.python-version` but not a `requires-python`-only project.

### 6.5 python-loaded per version

- **Inputs:** one shared tops list. Each minor gets its own lock and wheelhouse
  (`payload/python-loaded/<minor>/…`), resolved in EL8 against that minor's
  interpreter, plus a per-minor exclusion list.
- **Install:** one venv per minor at `<prefix>/share/python-loaded/<minor>/venv`,
  keeping the `versions/` indirection per minor. The lock's ABI header already
  ties each lock to one interpreter.
- **Cost per minor** (extrapolated from today's suite):
  - About 190 MB of new git payload per refresh. Pure-Python wheels dedupe
    only when the same versions resolve.
  - About 870 MB installed, once per tree, not per user.
  - One more container build; time it.
- **Older minors freeze.** Scientific Python follows SPEC 0 and drops a Python
  minor about three years after its release. The older the minor, the older
  its numpy/pandas/scipy, until eventually no build exists at all.
- **End of life** (PEP 602): 3.9 ended Oct 2025, 3.10 ended Oct 2026, and 3.11
  ends Oct 2027. Shipping an end-of-life version means shipping unpatched
  CPython. Being offline lowers that risk but does not remove it.
- **Adding a package:** add it to the shared tops list, and every minor picks
  it up at the next refresh.

### 6.6 PEP 723 scripts (optional, secondary)

- **The mechanism:**
  - A script declares its Python version and its packages in a `# /// script`
    comment block and starts with `#!/usr/bin/env -S uv run --script`.
  - Helpers: `uv init --script`, `uv add --script` and `uv lock --script`.
- **Offline:**
  - Interpreters come from EL's directory (U6, P1).
  - Packages come from the per-minor python-loaded wheelhouse through
    `--find-links` (P2). That means also installing the wheelhouse into the
    tree, about 243 MB per minor, or reading it from the repo checkout.
  - EL's launcher would set the offline, no-index, find-links and install-dir
    variables, so users set nothing.
- **Cache:** each user's `~/.cache/uv` holds unpacked copies of the packages
  they use. If home quotas are tight, `UV_CACHE_DIR` can point at scratch
  disk.
- **Priority:** the user base prefers python-loaded, so this is a second way
  for scripts that need something outside the curated set, not the primary
  one.

### 6.7 Unchanged by any of this

- EL's own python-tools (`uv tool` venvs) keep using 3.15 whichever module is
  loaded, because their interpreter paths are absolute.
- With no module loaded, the uv launcher's default is unchanged.

### 6.8 Why adding a version later only adds things

- python-loaded is already tied to one interpreter by its lock's ABI header.
- The uv launcher's pin is only a default that a module-provided variable can
  replace.
- New interpreters go in new directories.

None of today's layout has to change.

## 7. Prior art

The assistant's summary from general knowledge; not re-verified in-session.

| System | How versions coexist | How one is selected | Notes |
|---|---|---|---|
| Debian / Ubuntu | `python3.X` packages side by side; one default `python3`; deadsnakes PPA for extras | Versioned executable name | Minor is the contract; patches move forward. `update-alternatives` on `python3` is discouraged. PEP 668 marks the system env externally managed. |
| Fedora / RHEL 8–9 | AppStream `python3.11`, `python3.12` side by side; `/usr/bin/python3` = platform version | Versioned executable name | RHEL 7's Software Collections (`rh-python3x`, `scl enable` environment switching) were superseded by this. |
| Homebrew | `python@3.X` kegs | Versioned name; the unversioned links come only from the default formula | |
| conda / mamba | An environment = interpreter + packages | `conda activate`; `python=3.12` means the newest 3.12.x | The closest analogue of python-loaded. |
| pyenv / asdf / mise | Built-from-source versions behind shims | `PYENV_VERSION` > `.python-version` > global | uv reads the same `.python-version`. |
| uv | PBS builds in a managed dir | `.python-version`, `requires-python`, PEP 723 | Downloads on demand; disable that offline. |
| Spack | `python@3.12.1` in hashed prefixes | Generated modules (`spack module tcl/lmod refresh`) | Pins exact versions because whole compiled stacks build against one build. |
| EasyBuild + Lmod | `Python/3.12.3-GCCcore-13.3.0` modules | Lmod `family("python")` | `SciPy-bundle` modules are the HPC python-loaded: a curated set per Python/toolchain. |
| Nix | `python312`, `python313` derivations | Per-project shells | |
| Windows `py` launcher (PEP 397/514/773) | Registered installs side by side | `py -3.12`, or the script's `#!/usr/bin/env python3.12` | |

Common lessons:

- The version request belongs with the script or project. Switching the whole
  environment is a convenience for interactive work.
- The minor version is the compatibility promise, and patches advance for
  security. Everyone works this way except Spack and EasyBuild, which pin
  exact versions for compiled-stack reproducibility.
- What went badly: repointing the system `python3` (`alternatives --set` breaks
  OS tools), SCL-style environment switching, and modules that set
  `PYTHONPATH` or `PYTHONHOME`.

## 8. Open questions (the user's to answer, on that day)

1. **Which version(s)?** Whatever the triggering case needs.
2. **Module versus project pin when they disagree.** The candidates:
   - **(a)** The module wins. Measured to silently rebuild `.venv` (U2); reject.
   - **(b)** The project pin wins, and the module only sets the default where
     no pin exists. Detection via `uv python pin` misses
     `requires-python`-only projects (U12).
   - **(c)** Refuse, with a message naming both versions.

   The assistant leans toward (b) or (c).
3. **Exact-patch modulefile names:** offer them at all? If so, what is the
   retention policy for old patches?
4. **End-of-life versions:** carry them or not?
5. **Storage:** interpreters and per-minor wheelhouses in the git payload, or
   as fetched release assets (stash-style signed-tag trust chain)?
6. **Versioned executables on the shared PATH?** Putting `python3.12` there
   (the Debian model) would let `#!/usr/bin/env python3.12` work without a
   module. EL appends `<prefix>/bin`, though, so a host `/usr/bin/python3.12`
   would win.
7. **Per-minor wheelhouse in the tree?** Install it as well, for PEP 723
   scripts?

## 9. Rejected / anti-patterns

- Wrappers pinned to exact patches (`python/3.12.1`) as the norm.
- A modulefile exporting `UV_PYTHON` (U2, plus the `uv pip` redirection).
- Steering uv through PATH alone (U4).
- Any modulefile setting `PYTHONPATH`, `PYTHONHOME` or `LD_LIBRARY_PATH`.
- Repointing `python3` globally (`alternatives --set`).
- Building each version through the portable-python PGO/LTO/BOLT pipeline.
- Interpreter paths that name the patch, when venvs depend on them (U8, U9;
  contrast U11).
