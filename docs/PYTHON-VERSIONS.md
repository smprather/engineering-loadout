# Multiple Python versions

EL bundles one primary interpreter (portable CPython **3.15** at
`<prefix>/bin/python3.15`) plus two optional ones for scripts that cannot move
to 3.15 and cannot be rebuilt:

| package | interpreter | installed at |
|---|---|---|
| `python-3.12` | CPython 3.12.16 (python-build-standalone) | `<prefix>/opt/python/3.12/` |
| `python-3.13` | CPython 3.13.18 (python-build-standalone) | `<prefix>/opt/python/3.13/` |

They are **optional and not part of `@shared`**. Install them explicitly:

```bash
./loadout install @python-versions      # both, or:
./loadout install python-3.12
```

`python-loaded` and EL's own Python tools (`ruff`, `ty`, `pyright`, `sby`, ...)
always stay on 3.15; installing a second interpreter does not change them.

## Selecting a version with Environment Modules

The installer writes one modulefile per installed interpreter under
`<prefix>/share/modulefiles/python/<minor>` (for the default root:
`~/.local/share/loadout/share/modulefiles/python/3.12`). If `module` is not
already available, source the bundled Environment Modules init:

```bash
source <prefix>/lib/modules/init/bash     # or .../init/csh in tcsh
module use <prefix>/share/modulefiles
module load python/3.12
python3 --version                          # Python 3.12.16
module switch python/3.13                  # or: module unload python/3.12; module load python/3.13
```

The modulefile does exactly three things:

- prepends `<prefix>/opt/python/<minor>/bin` to `PATH`, so `python3`,
  `python3.<minor>` and `pip*` are that version;
- sets `LOADOUT_PYTHON=<prefix>/opt/python/<minor>/bin/python3` for the uv
  launcher (see below);
- sets `UV_PYTHON_DOWNLOADS=never`, so even a user's own uv never tries to
  download an interpreter on an air-gapped node.

It deliberately sets **no** `PYTHONPATH`, `PYTHONHOME`, `LD_LIBRARY_PATH` or
`UV_PYTHON`. Those leak into every child Python — including EDA tools' own
bundled interpreters and EL's 3.15 tools — and `UV_PYTHON` outranks a project's
own pin.

Only the minor is shipped (`python/3.12`, not `python/3.12.16`): the minor is
the compatibility promise, and patch releases update the tree in place. The
site's own Environment Modules must support `family` (5.1 or newer) for the
family conflict/switching behavior; older versions can wrap the modulefile with
`conflict python` instead.

## What uv does with a loaded interpreter

After `module load python/3.12`, EL's `uv` launcher (`<prefix>/bin/uv`) uses
`$LOADOUT_PYTHON` as its default interpreter:

```bash
uv init myproj       # .python-version = 3.12, requires-python = ">=3.12"
uv venv              # creates .venv on 3.12
uv run python -V     # 3.12
```

Precedence, highest first:

1. an explicit `uv --python PATH` (or `uv python` arguments);
2. a caller-set `UV_PYTHON`;
3. a project pin in `.python-version` or `pyproject.toml`'s
   `requires-python`, found in the current directory or any ancestor;
4. `$LOADOUT_PYTHON` from the loaded module;
5. `<prefix>/bin/python3` (3.15).

A project pin **wins over the loaded module**: with `python/3.12` loaded, a
project pinned to 3.13 is built on 3.13, not silently rebuilt on 3.12. If no
matching interpreter exists on the machine, uv refuses loudly instead of
downloading one. The launcher also keeps its existing carve-outs: `uv pip`
mutations stay unpinned (they follow `VIRTUAL_ENV`/`--python`/`--system`), and
`uv run` inside an activated virtualenv uses that venv.

A user's own uv (not EL's launcher) ignores `LOADOUT_PYTHON`, but the module's
`UV_PYTHON_DOWNLOADS=never` still prevents downloads.

## Virtual environments and patch updates

Create venvs from the stable per-minor path (`opt/python/<minor>/bin/python3`,
which is what `LOADOUT_PYTHON` names). The venv records that path, so a patch
update that replaces the interpreter tree in place does not break it:

```bash
module load python/3.12
python3 -m venv ~/venvs/py312
~/venvs/py312/bin/python -V        # still 3.12 after `loadout upgrade`
```

## Offline behavior

Everything comes from the payload: the interpreters are bundled archives and
the module disables uv's downloads. Nothing in this feature needs a network,
an internal PyPI mirror, or a compiler.

## When not to add another version

A second interpreter costs payload size, one more EL8 container probe, and —
for old minors — shipping CPython code that no longer receives security fixes
(3.10 reached end of life in October 2026; 3.11 ends October 2027). Prefer
moving the script to 3.15. The versions here exist for scripts that are pinned
by someone else (vendor/foundry collateral) and cannot be changed.
