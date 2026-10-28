# Copilot Instructions

This file is a pointer, not a copy. The authoritative agent reference is
[`AGENTS.md`](../AGENTS.md) at the repo root; read it in full before changing
anything. A second copy of it used to live here and drifted on every change
(`tests/docs-sync` now keeps this file short).

## What this repo is

Engineering Loadout ("EL"): an offline-first, no-root package manager for Linux
compute environments. It installs bundled CLI tools, GUI library bundles,
runtimes, fonts and per-user shell/editor configs (bash, tcsh, zsh, vim, nvim,
tmux, ...) from `payload/`, driven by `payload/packages.json`. Linux only.
**EL8 / EL9** means RHEL 8 / RHEL 9 and their rebuilds; a bare **EL** always
means this project.

## Cold start

1. [`AGENTS.md`](../AGENTS.md) -- architecture, rules, pitfalls, terminology.
2. [`docs/HANDOFF.md`](../docs/HANDOFF.md) -- current branch state,
   verification gates, and follow-ups that git history does not show.

Two rules that bite first:

- `./loadout` is a POSIX-sh shim that runs `loadout_main.py` under the bundled
  Python 3.15. The source uses PEP 758 (`except A, B:`); never run a pre-3.14
  interpreter or analyzer over it, and never add parentheses back.
- All compiling and payload-mutating work happens in the EL8 build container
  (`build/build-shell`), never on the host.

## Gates

```bash
sh -n loadout
python3.15 -m py_compile loadout_main.py
bash -n envs/bash/global/bashrc
ruff format --check --force-exclude
tests/run-all --fast        # Tier 1
tests/run-all               # Tier 1 + Tier 2 (installs into temp roots)
tests/prebuilt-binaries-almalinux8 --full   # Tier 3, EL8 container, --network=none
```

Automation passes `-y` to `./loadout install` (non-TTY stdin aborts).

## Commit Rule

Before every commit, sync the cold-start docs (README.md, AGENTS.md, this file,
docs/HANDOFF.md and the subsystem's own doc) with the code being committed. Use
`rg` over them for renamed commands, retired flags, new env vars and changed
install behavior. `tests/docs-sync` (Tier 1) catches the mechanical classes of
drift; it does not replace reading the docs.
