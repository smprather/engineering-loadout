# st Runtime Configuration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a deployed st user change font and colors — and see the change live — by editing a text file, with no compiler on the destination system.

**Architecture:** One loadout-owned patch teaches st to merge an `XrmDatabase` from a colon-separated file list in `$ST_XRESOURCES` (over `RESOURCE_MANAGER`, under compiled `config.h` defaults) and to re-read it on `SIGUSR1`. `bin/st` becomes a POSIX-sh wrapper that builds the six-layer chain under `~/.config/st/`; the real ELF moves to `bin/st.bin`. A new `env-st` package ships the `global` layer plus a fully-commented `user` template whose bundled-font list is machine-generated from `payload/fonts/*.zip`.

**Tech Stack:** C (st 0.9.3, Xlib `Xrm*` API), POSIX sh (wrappers), Python 3.14 (`loadout_main.py`, generator, tests), `fontconfig` (`fc-scan`, build-time only).

Spec: `docs/superpowers/specs/2026-07-13-st-runtime-config-design.md`

## Global Constraints

- **EL8 build machine is the current session.** `gcc-toolset-14` at `/opt/rh/gcc-toolset-14/enable`, glibc 2.28. Never frame a build step as needing a separate or remote host.
- **Stable tags only.** st stays at `--tag 0.9.3` (`https://dl.suckless.org/st/`). No HEAD, no nightly.
- **Never bundle** glibc components, `libstdc++`/`libgcc_s`, or the OpenGL dispatcher. st links `libX11`/`libXft`/`libfontconfig`/`libfreetype` from the existing `gui_libs` bundle — no new libs in this work.
- **ELF packaging order is strip → patchelf → bzip2.** Stripping after patchelf corrupts `.dynstr`.
- **`./strip-all-elf-binaries` after any payload change.** It also regenerates `.content-manifest`. Both get committed.
- **Registry changes require** `./loadout completion bash > envs/bash/global/completions/loadout.bash` (a Tier 2 test diffs it).
- **Every bundled-binary change requires a `build/ADDING_BINARIES.md` note** complete enough to reproduce without re-deriving anything (CLAUDE.md mandate).
- **Stock EL8 is the verification baseline, not this dev box.** Anything touching install behavior must pass `tests/run-all --container` (Tier 3, clean `almalinux:8.10`) before it is trusted.
- **Backward compatibility is a hard requirement:** st with no config files present must behave exactly as it does today (compiled `config.h` defaults).
- Config keys are `st.<name>` in X resource syntax; comments start with `!`.

---

## File Structure

**Create:**
- `build/st/0001-runtime-xresources-config.patch` — the C patch (generated in Task 4, committed as the reproducible artifact).
- `build/st/st` — POSIX-sh wrapper, installed as `bin/st`.
- `build/st/st-reload` — POSIX-sh reload helper, installed as `bin/st-reload`.
- `build/gen-st-font-comments` — regenerates the bundled-font comment block; `--check` mode for the test suite.
- `envs/st/global/st.xresources` — shipped global layer (live defaults).
- `envs/st/user/st.xresources.template` — commented cheatsheet, seeded into `~/.config/st/user/st.xresources` if absent.
- `envs/st/README.md` — layer model, reload, regeneration.
- `tests/st-wrapper` — X-free test of the `ST_XRESOURCES` chain and `st-reload` pid selection.
- `tests/install-env-st` — fresh-HOME install, seeding, and non-destructive-reinstall test.

**Modify:**
- `build/build-st.sh` — apply the new patch; split wrapper/`st.bin`; package `st-reload`; fix the stale terminfo staging path.
- `payload/packages.json` — `st.bins`; new `env-st` entry.
- `loadout_main.py` — `_install_env_st` + `ENV_HANDLERS` registration.
- `tests/run-all` — register the three new checks.
- `envs/bash/global/completions/loadout.bash` — regenerate.
- `build/ADDING_BINARIES.md`, `CLAUDE.md` — docs.

**Task order rationale:** Tasks 1–3 are pure text/shell/Python and need no rebuild, so each lands independently green. Task 4 is the single C/rebuild task. Task 5 is docs + the full gate.

---

### Task 1: Bundled-font comment generator + config layer files

**Files:**
- Create: `build/gen-st-font-comments`
- Create: `envs/st/global/st.xresources`
- Create: `envs/st/user/st.xresources.template`
- Modify: `tests/run-all:69` (add generator `--check` next to the other `--check` generators)

**Interfaces:**
- Consumes: nothing.
- Produces: `build/gen-st-font-comments [--check]` — exit 0 when the committed blocks match a fresh scan, exit 1 on drift. Rewrites the text between `! BEGIN generated font list` and `! END generated font list` in both `envs/st/global/st.xresources` and `envs/st/user/st.xresources.template`. Task 2 installs those two files; Task 3's wrapper points st at their installed copies.

**Why generated:** the fontconfig family name is not the zip name for a third of what we ship (`CascadiaCode.zip` → `CaskaydiaCove Nerd Font`, `SourceCodePro.zip` → `SauceCodePro Nerd Font`, `DejaVuSansMono.zip` → `DejaVuSansM Nerd Font`, `Meslo.zip` → `MesloLGS Nerd Font`). A hand-written list will be wrong.

- [ ] **Step 1: Write the generator**

Create `build/gen-st-font-comments` (mode 0755):

```python
#!/usr/bin/env python3
"""gen-st-font-comments -- regenerate the bundled-font comment block in the
shipped st config files.

st's font is an Xft/fontconfig pattern whose family name frequently differs
from the name of the zip we ship it in (CascadiaCode.zip -> "CaskaydiaCove
Nerd Font"). Users cannot be expected to guess that, so the shipped config
files list every bundled family as a ready-to-paste `st.font:` line -- and
that list is generated from the actual font metadata, never hand-typed.

Reads payload/fonts/*.zip (rejoining .part-NNN chunks the way the installer
does), extracts each face to a temp dir, and asks fc-scan for its family.

Runs under any python3 (stdlib only); needs fc-scan (fontconfig) on PATH.

Usage:
    build/gen-st-font-comments           # rewrite the block in the config files
    build/gen-st-font-comments --check   # exit 1 if the committed block drifted
"""

import argparse
import glob
import os
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FONTS_DIR = os.path.join(REPO, "payload", "fonts")
TARGETS = [
    os.path.join(REPO, "envs", "st", "global", "st.xresources"),
    os.path.join(REPO, "envs", "st", "user", "st.xresources.template"),
]
BEGIN = "! BEGIN generated font list"
END = "! END generated font list"
DEFAULT_SIZE = 12
FACE_SUFFIXES = (".ttf", ".otf")


def logical_zips(fonts_dir):
    """Return sorted logical zip paths, deduping real files and .part-000 heads."""
    names = set()
    for path in glob.glob(os.path.join(fonts_dir, "*.zip")):
        names.add(path)
    for part0 in glob.glob(os.path.join(fonts_dir, "*.zip.part-000")):
        names.add(part0[: -len(".part-000")])
    return sorted(names)


def resolve_zip(path, tmpdir):
    """Return a real readable path for *path*, rejoining .part-NNN if needed."""
    if os.path.isfile(path):
        return path
    parts = sorted(glob.glob(path + ".part-*"))
    if not parts:
        return None
    joined = os.path.join(tmpdir, os.path.basename(path))
    with open(joined, "wb") as out:
        for p in parts:
            with open(p, "rb") as inp:
                shutil.copyfileobj(inp, out)
    return joined


def families_in_zip(zip_path, tmpdir):
    """Return the sorted set of fontconfig family names inside *zip_path*."""
    families = set()
    with zipfile.ZipFile(zip_path) as zf:
        faces = [n for n in zf.namelist() if n.lower().endswith(FACE_SUFFIXES)]
        for name in faces:
            dest = os.path.join(tmpdir, os.path.basename(name))
            with zf.open(name) as src, open(dest, "wb") as out:
                shutil.copyfileobj(src, out)
            try:
                res = subprocess.run(
                    ["fc-scan", "--format", "%{family[0]}\\n", dest],
                    capture_output=True,
                    text=True,
                    check=True,
                )
            finally:
                os.unlink(dest)
            fam = res.stdout.strip().splitlines()
            if fam and fam[0].strip():
                families.add(fam[0].strip())
    return sorted(families)


def build_block():
    """Return the generated block text (BEGIN/END markers included)."""
    if not shutil.which("fc-scan"):
        sys.exit("gen-st-font-comments: fc-scan not found (dnf install fontconfig)")
    rows = []
    with tempfile.TemporaryDirectory(prefix="gen-st-fonts.") as tmpdir:
        for logical in logical_zips(FONTS_DIR):
            real = resolve_zip(logical, tmpdir)
            if real is None:
                continue
            zipname = os.path.basename(logical)
            stem = zipname[: -len(".zip")]
            for fam in families_in_zip(real, tmpdir):
                # Annotate only when the family name is not guessable from the zip.
                note = "" if fam.replace(" ", "").startswith(stem) else f"({zipname})"
                rows.append((fam, note))
    if not rows:
        sys.exit(f"gen-st-font-comments: no fonts found under {FONTS_DIR}")
    rows.sort(key=lambda r: r[0].lower())
    width = max(len(f"!   st.font: {fam}:size={DEFAULT_SIZE}") for fam, _ in rows)
    lines = [BEGIN]
    for fam, note in rows:
        line = f"!   st.font: {fam}:size={DEFAULT_SIZE}"
        if note:
            line = f"{line.ljust(width)}  {note}"
        lines.append(line)
    lines.append(END)
    return "\n".join(lines) + "\n"


def splice(text, block):
    """Replace the BEGIN..END region of *text* with *block*."""
    pattern = re.compile(
        re.escape(BEGIN) + r".*?" + re.escape(END) + r"\n", re.DOTALL
    )
    if not pattern.search(text):
        sys.exit("gen-st-font-comments: BEGIN/END markers missing from target file")
    return pattern.sub(lambda _: block, text, count=1)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true", help="exit 1 on drift")
    args = ap.parse_args()

    block = build_block()
    drifted = []
    for target in TARGETS:
        with open(target) as f:
            old = f.read()
        new = splice(old, block)
        if old == new:
            continue
        if args.check:
            drifted.append(target)
        else:
            with open(target, "w") as f:
                f.write(new)
            print(f"updated: {os.path.relpath(target, REPO)}")

    if args.check and drifted:
        for t in drifted:
            print(f"STALE: {os.path.relpath(t, REPO)}", file=sys.stderr)
        print(
            "Run build/gen-st-font-comments and commit the result.", file=sys.stderr
        )
        return 1
    if args.check:
        print("st font list in sync")
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 2: Write the global layer with an empty marker block**

Create `envs/st/global/st.xresources`. The `BEGIN/END` block is left empty here — Step 4 fills it. Everything else is final:

```
! st -- loadout global layer.  Managed by the loadout; edit the USER layer instead:
!   ~/.config/st/user/st.xresources
!
! Layers merge in this order, later wins:
!   global -> corp -> site -> team -> project -> user
! Apply changes to running windows:  st-reload   (or Ctrl+Shift+R inside st)
!
! ---- Fonts bundled by loadout (exact Xft strings; generated -- do not edit) ----
! BEGIN generated font list
! END generated font list
!
! Syntax: <family>:size=<pt>[:style=Bold][:antialias=true][:autohint=false]
! Check what X actually resolves:  fc-match 'JetBrainsMono Nerd Font'
! List every installed family:     fc-list : family | sort -u

st.font: JetBrainsMono Nerd Font:size=12

! ---- Colors: tokyonight (matches the nvim colorscheme and starship) ----
! Accepts #rrggbb or an X color name.
st.background:  #1a1b26
st.foreground:  #c0caf5
st.cursorColor: #c0caf5

st.color0:  #15161e
st.color1:  #f7768e
st.color2:  #9ece6a
st.color3:  #e0af68
st.color4:  #7aa2f7
st.color5:  #bb9af7
st.color6:  #7dcfff
st.color7:  #a9b1d6
st.color8:  #414868
st.color9:  #f7768e
st.color10: #9ece6a
st.color11: #e0af68
st.color12: #7aa2f7
st.color13: #bb9af7
st.color14: #7dcfff
st.color15: #c0caf5

! ---- Behavior ----
st.cursorshape: 2
```

- [ ] **Step 3: Write the user template**

Create `envs/st/user/st.xresources.template`. Every directive is commented out, so the file changes nothing until the user edits it:

```
! st -- your personal layer.  Yours to edit; the loadout never overwrites this file.
!
! Layers merge in this order, later wins:
!   global -> corp -> site -> team -> project -> user
! Anything you uncomment here overrides ~/.config/st/global/st.xresources.
!
! Apply changes to already-running st windows:
!   st-reload            signal every st on your $DISPLAY
!   st-reload --all      every st you own, any display
!   Ctrl+Shift+R         from inside an st window
! No restart, no recompile.
!
! ---- Fonts bundled by loadout (exact Xft strings; generated -- do not edit) ----
! BEGIN generated font list
! END generated font list
!
! Syntax: <family>:size=<pt>[:style=Bold][:antialias=true][:autohint=false]
! Check what X actually resolves:  fc-match 'JetBrainsMono Nerd Font'
! List every installed family:     fc-list : family | sort -u
!
! st.font: JetBrainsMono Nerd Font:size=14
!
! ---- Colors ----
! Accepts #rrggbb or an X color name. The loadout default (tokyonight) is set in
! the global layer; override any single key here.
!
! st.background:  #1a1b26
! st.foreground:  #c0caf5
! st.cursorColor: #c0caf5
! st.color0:  #15161e      ! black          st.color8:  #414868   ! bright black
! st.color1:  #f7768e      ! red            st.color9:  #f7768e   ! bright red
! st.color2:  #9ece6a      ! green          st.color10: #9ece6a   ! bright green
! st.color3:  #e0af68      ! yellow         st.color11: #e0af68   ! bright yellow
! st.color4:  #7aa2f7      ! blue           st.color12: #7aa2f7   ! bright blue
! st.color5:  #bb9af7      ! magenta        st.color13: #bb9af7   ! bright magenta
! st.color6:  #7dcfff      ! cyan           st.color14: #7dcfff   ! bright cyan
! st.color7:  #a9b1d6      ! white          st.color15: #c0caf5   ! bright white
!
! ---- Behavior ----
! st.cursorshape:  2            ! 2=block  4=underline  6=bar; odd values blink (1/3/5)
! st.borderpx:     2            ! px of padding inside the window
! st.blinktimeout: 800          ! ms; 0 disables cursor blinking
! st.bellvolume:   0            ! -100..100; 0 = silent
! st.tabspaces:    8
! st.termname:     st-256color  ! must match a terminfo entry the loadout ships
! st.shell:        /bin/bash
! st.cwscale:      1.0          ! cell width  multiplier (tighten/loosen columns)
! st.chscale:      1.0          ! cell height multiplier (line spacing)
!
! Keybindings are NOT settable here -- they are compiled into st. The only
! exception is the reload key (Ctrl+Shift+R), which is built in.
```

- [ ] **Step 4: Run the generator and inspect the result**

```bash
chmod +x build/gen-st-font-comments
build/gen-st-font-comments
sed -n '/BEGIN generated font list/,/END generated font list/p' envs/st/global/st.xresources
```

Expected: 12+ `!   st.font: <Family> Nerd Font:size=12` lines, sorted, with `(CascadiaCode.zip)`-style annotations on the families whose name does not match their zip. Confirm `CaskaydiaCove`, `SauceCodePro`, `DejaVuSansM`, and `MesloLG*` all appear — if they do not, `fc-scan` is reading the wrong faces and the generator is broken.

- [ ] **Step 5: Verify `--check` catches drift**

```bash
build/gen-st-font-comments --check                  # expect: "st font list in sync", exit 0
sed -i 's/^!   st.font: Hack Nerd Font.*/!   st.font: Bogus Font:size=12/' envs/st/global/st.xresources
build/gen-st-font-comments --check; echo "exit=$?"  # expect: STALE: envs/st/global/st.xresources, exit=1
build/gen-st-font-comments                          # restore
build/gen-st-font-comments --check                  # expect: in sync, exit 0
```

- [ ] **Step 6: Register the check in the Tier 1 suite**

In `tests/run-all`, immediately after the `parser-locks in sync` line (currently line 70):

```sh
run_test "st font list in sync" "$PY" build/gen-st-font-comments --check
```

- [ ] **Step 7: Run Tier 1**

Run: `tests/run-all --fast`
Expected: all green, including `st font list in sync`.

- [ ] **Step 8: Commit**

```bash
git add build/gen-st-font-comments envs/st/global/st.xresources envs/st/user/st.xresources.template tests/run-all
git commit -m "feat(st): generated bundled-font comment block + st config layer files"
```

---

### Task 2: `env-st` package + non-destructive installer handler

**Files:**
- Modify: `payload/packages.json` (new `env-st` entry)
- Modify: `loadout_main.py` (`_install_env_st`, `ENV_HANDLERS` at :3612)
- Create: `tests/install-env-st`
- Modify: `tests/run-all` (Tier 2)
- Modify: `envs/bash/global/completions/loadout.bash` (regenerate)

**Interfaces:**
- Consumes: `envs/st/global/st.xresources` and `envs/st/user/st.xresources.template` from Task 1.
- Produces: an installed layer tree at `~/.config/st/` — `global/st.xresources` (synced, delete semantics) and `user/st.xresources` (seeded once, never overwritten). Task 3's wrapper builds `ST_XRESOURCES` against exactly these paths.

**Why a custom handler and not `_install_env_generic`:** `install_path()` on a directory calls `sync_dir(..., delete=True)` (`loadout_main.py:1187`). Pointing that at `~/.config/st` would delete the user's own `user/`, `site/`, `corp/` layers on every install. The handler must sync only `global/`.

- [ ] **Step 1: Write the failing test**

Create `tests/install-env-st` (mode 0755):

```sh
#!/bin/sh
# env-st install: ships the global layer, seeds the user layer exactly once,
# and never clobbers user-created layers on reinstall.
set -eu

REPO="$(cd "$(dirname "$0")/.." && pwd)"
TMPHOME="$(mktemp -d /tmp/loadout-env-st.XXXXXX)"
trap 'rm -rf "$TMPHOME"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

HOME="$TMPHOME" "$REPO/loadout" install env-st --no-backup >/dev/null

ST="$TMPHOME/.config/st"
[ -f "$ST/global/st.xresources" ] || fail "global layer not installed"
[ -f "$ST/user/st.xresources" ] || fail "user layer not seeded"

grep -q '^st.font:' "$ST/global/st.xresources" || fail "global layer has no live st.font"
grep -q 'BEGIN generated font list' "$ST/global/st.xresources" || fail "font block missing"
grep -q 'Nerd Font:size=' "$ST/global/st.xresources" || fail "font block is empty"

# The seeded user layer must be inert: no uncommented directives.
if grep -qv '^\s*\(!.*\)\?$' "$ST/user/st.xresources"; then
    fail "seeded user layer contains an active directive; it must ship fully commented"
fi

# Reinstall must not clobber the user's edits, and must not delete sibling layers.
echo 'st.font: FiraCode Nerd Font:size=18' >> "$ST/user/st.xresources"
cp "$ST/user/st.xresources" "$TMPHOME/user.expected"
mkdir -p "$ST/site"
echo 'st.color4: #ff0000' > "$ST/site/st.xresources"

HOME="$TMPHOME" "$REPO/loadout" install env-st --no-backup >/dev/null

cmp -s "$ST/user/st.xresources" "$TMPHOME/user.expected" \
    || fail "reinstall overwrote the user layer"
[ -f "$ST/site/st.xresources" ] || fail "reinstall deleted the site layer"

echo "install-env-st: OK"
```

- [ ] **Step 2: Run it and watch it fail**

Run: `chmod +x tests/install-env-st && tests/install-env-st`
Expected: FAIL — `./loadout install env-st` errors with an unknown package name (`env-st` is not in the registry yet).

- [ ] **Step 3: Add the registry entry**

In `payload/packages.json`, add alongside the other `env-*` packages (keep the file's existing key ordering style):

```json
    "env-st": {
      "kind": "env",
      "source": "envs/st/",
      "install_to": "~/.config/st",
      "platforms": ["linux"],
      "tags": ["env", "terminal"],
      "description": "st runtime config layers (global -> corp -> site -> team -> project -> user); font/colors editable without recompiling"
    },
```

Then add `env-st` to the `@envs`-side grouping exactly the way the other `kind: env` packages are picked up — `@envs` is synthetic (the complement of `@shared`), so no group edit is needed; `kind: env` is sufficient. Do **not** add it to `depends` of the `st` binary package: tools and env bundles stay decoupled in both directions (CLAUDE.md).

- [ ] **Step 4: Write the handler**

In `loadout_main.py`, immediately after `_install_env_helix` (ends at :3571):

```python
def _install_env_st(repo_dir, home):
    """Install the st config layers.

    global/ is loadout-owned and synced with delete semantics. user/ is seeded
    from the shipped template exactly once and never touched again -- it is the
    file the user edits. Sibling layers (corp/site/team/project) are user-created
    and must survive every reinstall, which is why this cannot use the generic
    directory handler: install_path() on a dir syncs with delete=True and would
    wipe them.
    """
    src = os.path.join(repo_dir, "envs", "st")
    if not os.path.isdir(src):
        return
    st_dir = os.path.join(home, ".config", "st")
    if os.path.islink(st_dir):
        os.unlink(st_dir)
    ensure_dir(st_dir, "st config")
    install_path(
        os.path.join(src, "global"),
        os.path.join(st_dir, "global"),
        False,
    )
    user_dir = os.path.join(st_dir, "user")
    ensure_dir(user_dir, "st user config")
    user_cfg = os.path.join(user_dir, "st.xresources")
    if not os.path.lexists(user_cfg):
        install_path(
            os.path.join(src, "user", "st.xresources.template"),
            user_cfg,
            False,
        )
        print(f"  st user config seeded -> {user_cfg}")
```

Register it in `ENV_HANDLERS` (:3612):

```python
    "env-st": _install_env_st,
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `tests/install-env-st`
Expected: `install-env-st: OK`

- [ ] **Step 6: Regenerate completions and register the test**

```bash
./loadout completion bash > envs/bash/global/completions/loadout.bash
```

In `tests/run-all`, in the Tier 2 block after `run_test "install-modules" tests/install-modules` (line 82):

```sh
run_test "install-env-st" tests/install-env-st
```

- [ ] **Step 7: Run doctor + the suite**

```bash
./loadout doctor
./loadout info env-st
tests/run-all
```
Expected: `doctor` clean; `info env-st` shows `kind: env`; suite green including `install-env-st` and `completion in sync`.

- [ ] **Step 8: Commit**

```bash
git add payload/packages.json loadout_main.py tests/install-env-st tests/run-all envs/bash/global/completions/loadout.bash
git commit -m "feat(st): env-st package with non-destructive user-layer seeding"
```

---

### Task 3: `bin/st` wrapper + `st-reload`

**Files:**
- Create: `build/st/st`
- Create: `build/st/st-reload`
- Create: `tests/st-wrapper`
- Modify: `tests/run-all` (Tier 1)

**Interfaces:**
- Consumes: the installed layer paths from Task 2.
- Produces: `ST_XRESOURCES` — a colon-separated, `global`→`user`-ordered list of six absolute paths, exported by `bin/st` before it execs `bin/st.bin`. Task 4's C patch reads exactly this variable, in exactly this order (later file wins), skipping paths that do not exist.

The wrapper reads no shell-startup state, so `st` from a `.desktop` file, dmenu, or `ssh host st` behaves identically to `st` from an interactive bash.

- [ ] **Step 1: Write the failing test**

Create `tests/st-wrapper` (mode 0755):

```sh
#!/bin/sh
# X-free tests for the st wrapper: does it build the right ST_XRESOURCES chain,
# and does it get out of the way when the user set one?
set -eu

REPO="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d /tmp/loadout-st-wrapper.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

# Fake install tree: our wrapper as bin/st, a stub bin/st.bin that prints what
# it was handed.
mkdir -p "$TMP/local/bin" "$TMP/home/.config/st"
cp "$REPO/build/st/st" "$TMP/local/bin/st"
chmod +x "$TMP/local/bin/st"
cat > "$TMP/local/bin/st.bin" <<'STUB'
#!/bin/sh
echo "ST_XRESOURCES=$ST_XRESOURCES"
echo "ARGS=$*"
STUB
chmod +x "$TMP/local/bin/st.bin"

CFG="$TMP/home/.config/st"
out=$(HOME="$TMP/home" XDG_CONFIG_HOME="" "$TMP/local/bin/st" -e true)

expected="ST_XRESOURCES=$CFG/global/st.xresources:$CFG/corp/st.xresources:$CFG/site/st.xresources:$CFG/team/st.xresources:$CFG/project/st.xresources:$CFG/user/st.xresources"
echo "$out" | grep -qxF "$expected" \
    || fail "layer chain wrong:
  got:      $(echo "$out" | head -1)
  expected: $expected"

echo "$out" | grep -qxF "ARGS=-e true" || fail "wrapper did not pass args through"

# XDG_CONFIG_HOME must win over ~/.config
xdg="$TMP/xdg"
out=$(HOME="$TMP/home" XDG_CONFIG_HOME="$xdg" "$TMP/local/bin/st")
echo "$out" | grep -qF "$xdg/st/user/st.xresources" \
    || fail "wrapper ignored XDG_CONFIG_HOME"

# An explicit ST_XRESOURCES from the caller must be left alone.
out=$(HOME="$TMP/home" ST_XRESOURCES="/my/own.xresources" "$TMP/local/bin/st")
echo "$out" | grep -qxF "ST_XRESOURCES=/my/own.xresources" \
    || fail "wrapper clobbered a caller-set ST_XRESOURCES"

echo "st-wrapper: OK"
```

- [ ] **Step 2: Run it and watch it fail**

Run: `chmod +x tests/st-wrapper && tests/st-wrapper`
Expected: FAIL — `cp: cannot stat '.../build/st/st'` (the wrapper does not exist yet).

- [ ] **Step 3: Write the wrapper**

Create `build/st/st` (mode 0755):

```sh
#!/bin/sh
# Relocatable st entry point.
#
# st bakes its settings into config.h at compile time. The loadout patch teaches
# it to merge an X resource database from the colon-separated file list in
# ST_XRESOURCES (later file wins, missing files skipped), so this wrapper's only
# job is to name the layer chain. A caller who sets ST_XRESOURCES themselves
# keeps full control.
#
# Reads no shell-startup state on purpose: st launched from a .desktop file,
# dmenu, or `ssh host st` must resolve the same config as an interactive shell.

case "$0" in
    /*) script=$0 ;;
    *) script=$(command -v "$0") || exit 127 ;;
esac

prefix=$(CDPATH= cd -- "$(dirname -- "$script")/.." && pwd) || exit 1

if [ -z "${ST_XRESOURCES:-}" ]; then
    cfg="${XDG_CONFIG_HOME:-$HOME/.config}/st"
    ST_XRESOURCES="$cfg/global/st.xresources:$cfg/corp/st.xresources:$cfg/site/st.xresources:$cfg/team/st.xresources:$cfg/project/st.xresources:$cfg/user/st.xresources"
    export ST_XRESOURCES
fi

exec "$prefix/bin/st.bin" "$@"
```

Note `${XDG_CONFIG_HOME:-$HOME/.config}` treats an empty `XDG_CONFIG_HOME` as unset, which is what the first test case asserts.

- [ ] **Step 4: Run the test to verify it passes**

Run: `tests/st-wrapper`
Expected: `st-wrapper: OK`

- [ ] **Step 5: Write `st-reload`**

Create `build/st/st-reload` (mode 0755):

```sh
#!/bin/sh
# Apply st config changes to already-running windows.
#
# The loadout st patch re-reads every file in ST_XRESOURCES on SIGUSR1 and
# redraws (font, colors, cell metrics). Default scope is the st instances you
# own on the current $DISPLAY, because a config change is per-display in
# practice; --all covers every st you own.
#
# Ctrl+Shift+R does the same thing from inside an st window.

set -eu

scope_all=0
for arg in "$@"; do
    case "$arg" in
        --all) scope_all=1 ;;
        -h|--help)
            echo "usage: st-reload [--all]"
            echo "  (default) signal st instances on \$DISPLAY; --all: every st you own"
            exit 0
            ;;
        *) echo "st-reload: unknown option: $arg" >&2; exit 2 ;;
    esac
done

uid=$(id -u)
signalled=0

for pid in $(pgrep -u "$uid" -x st.bin 2>/dev/null || true); do
    if [ "$scope_all" -eq 0 ] && [ -n "${DISPLAY:-}" ]; then
        # /proc/<pid>/environ is readable for our own processes; entries are
        # NUL-separated.
        pid_display=$(tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null \
            | sed -n 's/^DISPLAY=//p' | head -1) || pid_display=""
        [ "$pid_display" = "$DISPLAY" ] || continue
    fi
    kill -USR1 "$pid" 2>/dev/null && signalled=$((signalled + 1))
done

if [ "$signalled" -eq 0 ]; then
    echo "st-reload: no running st found${DISPLAY:+ on $DISPLAY}" >&2
    exit 1
fi

echo "st-reload: reloaded $signalled st instance(s)"
```

- [ ] **Step 6: Extend the test to cover `st-reload` scoping**

Append to `tests/st-wrapper`, before the final `echo`:

```sh
# st-reload: no st running -> non-zero and a clear message.
out=$(DISPLAY=:99 "$REPO/build/st/st-reload" 2>&1) && fail "st-reload exited 0 with no st running"
echo "$out" | grep -q "no running st" || fail "st-reload: unexpected message: $out"

# st-reload: rejects unknown options rather than silently signalling everything.
if "$REPO/build/st/st-reload" --bogus >/dev/null 2>&1; then
    fail "st-reload accepted an unknown option"
fi
```

Run: `chmod +x build/st/st build/st/st-reload && tests/st-wrapper`
Expected: `st-wrapper: OK`

- [ ] **Step 7: Shellcheck + register in Tier 1**

```bash
shellcheck build/st/st build/st/st-reload    # if shellcheck is present; expect clean
```

In `tests/run-all`, Tier 1, after `run_test "check-installer" tests/check-installer` (line 72):

```sh
run_test "st-wrapper" tests/st-wrapper
```

Run: `tests/run-all --fast`
Expected: green, including `st-wrapper`.

- [ ] **Step 8: Commit**

```bash
git add build/st/st build/st/st-reload tests/st-wrapper tests/run-all
git commit -m "feat(st): bin/st wrapper builds the ST_XRESOURCES layer chain; st-reload helper"
```

---

### Task 4: The C patch + rebuild + repackage

**Files:**
- Create: `build/st/0001-runtime-xresources-config.patch`
- Modify: `build/build-st.sh`
- Modify: `payload/packages.json` (`st.bins`)
- Regenerate: `payload/el8.x86_64.glibc2p28/bin/{st,st.bin,st-reload}.bz2`, `.strip-manifest`, `.content-manifest`

**Interfaces:**
- Consumes: `ST_XRESOURCES` (Task 3, colon-separated, later wins) and the config keys used in Task 1's files.
- Produces: `bin/st` (wrapper), `bin/st.bin` (patched ELF, RPATH `$ORIGIN/../lib64:$ORIGIN/../lib`), `bin/st-reload`. The ELF exports no new symbols to other packages.

**Critical pre-existing bug to fix in the same file:** `build/build-st.sh` currently stages terminfo into `$STAGING/.terminfo/s/` and tars `./.terminfo`, but the committed `st.tar.bz2` contains `./share/terminfo/s/...` and the registry sentinel is `share/terminfo/s/st-256color` with `install_to: ~/.local`. The next `--tag` bump would ship an archive that installs to `~/.local/.terminfo` and fails its sentinel. Fix the staging paths to `share/terminfo/s` while you are in this file.

- [ ] **Step 1: Get the source tree and the two upstream patches**

```bash
cd /tmp
curl -fsSLO https://dl.suckless.org/st/st-0.9.3.tar.gz
tar -xzf st-0.9.3.tar.gz
cd st-0.9.3
git init -q && git add -A && git commit -qm "st 0.9.3 pristine"
curl -fsSL https://st.suckless.org/patches/xresources/ -o /tmp/xres-page.html
```

Read `/tmp/xres-page.html` to get the current diff filenames for the `xresources` and `xresources-with-reload` patches (upstream renames these on each st release; do not hardcode a filename from memory). Download both, then:

```bash
patch -p1 < /tmp/st-xresources-<version>.diff
patch -p1 < /tmp/st-xresources-with-reload-<version>.diff
```

Hunks will reject against 0.9.3 — that is expected and is precisely why we ship one curated patch instead of stacking upstream diffs at build time. Resolve every `.rej` by hand, then proceed. The upstream patches are the starting point for the code below, not the shipped artifact.

- [ ] **Step 2: Replace the upstream `config_init()` with the file-list version**

The upstream patch reads only `RESOURCE_MANAGER` (the X server's global property, set by `xrdb`). We keep that as a seed but layer our files on top. In `x.c`, the resource-loading block becomes:

```c
/* Loadout: runtime config.
 *
 * Settings are merged into one XrmDatabase, lowest priority first:
 *   1. the X server's RESOURCE_MANAGER (so plain `xrdb` users still work)
 *   2. each file in $ST_XRESOURCES, in order, later file wins
 *   3. anything still unset keeps its compiled config.h default
 * A missing file is not an error -- an unused layer simply does not exist.
 */
#define XRESOURCE_LOAD_META(NAME)					\
	if (!XrmGetResource(xdb, "st." NAME, "St." NAME, &type, &ret))	\
		if (!XrmGetResource(xdb, "*." NAME, "*." NAME, &type, &ret)) \
			break;						\
	if (ret.addr != NULL && !strncmp("String", type, 64))

#define XRESOURCE_LOAD_STRING(NAME, DST)	\
	do {					\
		XRESOURCE_LOAD_META(NAME)	\
			DST = ret.addr;		\
	} while (0)

#define XRESOURCE_LOAD_INTEGER(NAME, DST)			\
	do {							\
		XRESOURCE_LOAD_META(NAME)			\
			DST = strtoul(ret.addr, NULL, 10);	\
	} while (0)

#define XRESOURCE_LOAD_FLOAT(NAME, DST)		\
	do {					\
		XRESOURCE_LOAD_META(NAME)	\
			DST = strtof(ret.addr, NULL); \
	} while (0)

static XrmDatabase xdb;

void
config_init(Display *dpy)
{
	char *resm, *paths, *path, *save;
	XrmValue ret;
	char *type;

	XrmInitialize();

	if (xdb != NULL) {
		XrmDestroyDatabase(xdb);
		xdb = NULL;
	}

	/* 1. RESOURCE_MANAGER, when the display has one. */
	if ((resm = XResourceManagerString(dpy)) != NULL)
		xdb = XrmGetStringDatabase(resm);

	/* 2. every file in $ST_XRESOURCES, in order; later wins. */
	if ((resm = getenv("ST_XRESOURCES")) != NULL && *resm != '\0') {
		paths = strdup(resm);
		if (paths == NULL)
			die("strdup: %s\n", strerror(errno));
		for (path = strtok_r(paths, ":", &save); path != NULL;
		     path = strtok_r(NULL, ":", &save)) {
			if (*path == '\0' || access(path, R_OK) != 0)
				continue;
			XrmCombineFileDatabase(path, &xdb, True);
		}
		free(paths);
	}

	if (xdb == NULL)
		return;

	XRESOURCE_LOAD_STRING("font", font);
	XRESOURCE_LOAD_STRING("color0", colorname[0]);
	XRESOURCE_LOAD_STRING("color1", colorname[1]);
	XRESOURCE_LOAD_STRING("color2", colorname[2]);
	XRESOURCE_LOAD_STRING("color3", colorname[3]);
	XRESOURCE_LOAD_STRING("color4", colorname[4]);
	XRESOURCE_LOAD_STRING("color5", colorname[5]);
	XRESOURCE_LOAD_STRING("color6", colorname[6]);
	XRESOURCE_LOAD_STRING("color7", colorname[7]);
	XRESOURCE_LOAD_STRING("color8", colorname[8]);
	XRESOURCE_LOAD_STRING("color9", colorname[9]);
	XRESOURCE_LOAD_STRING("color10", colorname[10]);
	XRESOURCE_LOAD_STRING("color11", colorname[11]);
	XRESOURCE_LOAD_STRING("color12", colorname[12]);
	XRESOURCE_LOAD_STRING("color13", colorname[13]);
	XRESOURCE_LOAD_STRING("color14", colorname[14]);
	XRESOURCE_LOAD_STRING("color15", colorname[15]);
	XRESOURCE_LOAD_STRING("background", colorname[defaultbg]);
	XRESOURCE_LOAD_STRING("foreground", colorname[defaultfg]);
	XRESOURCE_LOAD_STRING("cursorColor", colorname[defaultcs]);
	XRESOURCE_LOAD_STRING("termname", termname);
	XRESOURCE_LOAD_STRING("shell", shell);
	XRESOURCE_LOAD_INTEGER("cursorshape", cursorshape);
	XRESOURCE_LOAD_INTEGER("borderpx", borderpx);
	XRESOURCE_LOAD_INTEGER("blinktimeout", blinktimeout);
	XRESOURCE_LOAD_INTEGER("bellvolume", bellvolume);
	XRESOURCE_LOAD_INTEGER("tabspaces", tabspaces);
	XRESOURCE_LOAD_FLOAT("cwscale", cwscale);
	XRESOURCE_LOAD_FLOAT("chscale", chscale);
}
```

Notes for the implementer:
- `colorname[]`, `font`, `termname`, `shell`, `cursorshape`, `borderpx`, `blinktimeout`, `bellvolume`, `tabspaces`, `cwscale`, `chscale` are the `config.h` globals; several are `const` in stock `config.def.h`. Drop the `const` on exactly the ones you assign here (the upstream patch does the same) — do not `const`-cast at the assignment site.
- `defaultbg` / `defaultfg` / `defaultcs` are `unsigned int` indices into `colorname[]`. If `defaultbg` is defined as `MAX(LEN(colorname), 256)` in your `config.h`, keep the array-bounds semantics upstream uses.
- Add `#include <X11/Xresource.h>`, `<errno.h>`, `<unistd.h>` if not already present. `strtok_r` needs `_GNU_SOURCE` or `_POSIX_C_SOURCE >= 200112L`, which st's `config.mk` already sets — verify, don't assume.

- [ ] **Step 3: Wire the reload path**

In `x.c`, add the signal plumbing and the reload entry point:

```c
static volatile sig_atomic_t reload_requested = 0;

static void
sigusr1_handler(int unused)
{
	(void)unused;
	reload_requested = 1;	/* no X calls in a signal handler */
}

void
xreload(void)
{
	config_init(xw.dpy);

	xunloadfonts();
	xloadfonts(font, 0);
	xloadcols();

	/* Font metrics may have changed: re-derive cell size, resize the tty. */
	cresize(win.w, win.h);
	ttyresize(win.tw, win.th);
	xhints();

	redraw();
}
```

In `main()`, after the display is opened and before `xinit()`, install the handler and load the config:

```c
	if (!(xw.dpy = XOpenDisplay(NULL)))
		die("Can't open display\n");
	config_init(xw.dpy);
	signal(SIGUSR1, sigusr1_handler);
```

(The upstream xresources patch already moves `XOpenDisplay` out of `xinit()` into `main()` — keep that hunk; `xinit()` must use the existing `xw.dpy` rather than opening a second connection.)

In `run()`, service the flag once per loop iteration, at the top of the `for (;;)` body, before `XPending`:

```c
		if (reload_requested) {
			reload_requested = 0;
			xreload();
		}
```

`select()` in `run()` will return `EINTR` when `SIGUSR1` lands; make sure the existing `if (errno == EINTR) continue;` path is present so the loop re-checks the flag promptly rather than dying.

- [ ] **Step 4: Add the `Ctrl+Shift+R` shortcut**

In `config.def.h`, in the `shortcuts[]` array:

```c
	{ ControlMask|ShiftMask, XK_R,          reload,         {.i =  0} },
```

and the matching function in `x.c` (a shortcut callback takes `const Arg *`):

```c
void
reload(const Arg *arg)
{
	(void)arg;
	xreload();
}
```

Declare `void reload(const Arg *);` next to the other shortcut callbacks in `st.h` (or wherever `zoom`/`numlock` are declared in 0.9.3).

- [ ] **Step 5: Build and prove the config actually lands**

```bash
cd /tmp/st-0.9.3
make clean && make -j"$(nproc)"
```
Expected: compiles clean. Warnings about assigning to a `const char *` mean you missed a `const` removal in Step 2.

Then a real behavioral check (this is an X app; run it on the dev box's display, not headless):

```bash
mkdir -p /tmp/sttest
printf 'st.background: #ff0000\nst.font: FiraCode Nerd Font:size=20\n' > /tmp/sttest/a.xresources
ST_XRESOURCES=/tmp/sttest/a.xresources ./st
```
Expected: red background, 20pt FiraCode. Then, from another terminal, with that st still open:

```bash
printf 'st.background: #0000ff\nst.font: JetBrainsMono Nerd Font:size=10\n' > /tmp/sttest/a.xresources
pkill -USR1 -x st
```
Expected: the running window turns blue and re-renders at 10pt JetBrainsMono, and the window resizes to the new cell metrics without corrupting the grid. Also press `Ctrl+Shift+R` inside the window — same result.

Then the backward-compat check, which is the one that must not regress:

```bash
env -u ST_XRESOURCES ./st
```
Expected: stock st appearance (compiled `config.h` defaults), no errors on stderr. A `RESOURCE_MANAGER`-only user must still work:

```bash
echo 'st.background: #00ff00' | xrdb -merge
env -u ST_XRESOURCES ./st     # green background
```

- [ ] **Step 6: Extract the patch**

```bash
cd /tmp/st-0.9.3
git add -A
git diff --cached > /home/mylesp/engineering-loadout/build/st/0001-runtime-xresources-config.patch
```

Prepend a provenance header to the patch file:

```
From: engineering-loadout
Subject: [PATCH] st: runtime configuration via $ST_XRESOURCES + SIGUSR1 reload

Derived from the upstream st `xresources` and `xresources-with-reload` patches
(https://st.suckless.org/patches/xresources/), MIT-licensed like st itself, with
two loadout changes:

  * config_init() takes the Display and merges every file named in the
    colon-separated $ST_XRESOURCES (later file wins) on top of RESOURCE_MANAGER,
    instead of reading RESOURCE_MANAGER alone. This keeps per-user config in a
    plain file, works over X-forwarding to a farm node, and needs no xrdb.
  * Ctrl+Shift+R triggers the same reload path as SIGUSR1.

Unset resources keep their compiled config.h defaults, so st with no config
files behaves exactly as an unpatched build.

Applies on top of: st 0.9.3 + the undercurl patch (see build-st.sh).
```

- [ ] **Step 7: Teach `build-st.sh` to apply the patch and split the wrapper**

In `build/build-st.sh`:

1. In the header comment block, document the new patch and its ordering (undercurl first, then `0001-runtime-xresources-config.patch`).
2. After the undercurl fixups, apply the new patch — and **fail loudly** rather than continuing on reject:

```sh
    echo "Applying loadout runtime-xresources patch..."
    patch -p1 --forward < "$REPO/build/st/0001-runtime-xresources-config.patch" || {
        echo "ERROR: runtime-xresources patch did not apply cleanly against st ${tag}." >&2
        echo "Re-derive it against this tag (see build/ADDING_BINARIES.md -> st)." >&2
        exit 1
    }
```

3. Replace the packaging block (`WORK=/tmp/st_work_${tag}` … `Installed: $BIN_DIR/st.bz2`) so the ELF ships as `st.bin` and the two shell scripts ship alongside it. Order stays strip → patchelf → bzip2:

```sh
WORK="/tmp/st_work_${tag}"
cp st "$WORK"
strip "$WORK"
"$PATCHELF" --set-rpath '$ORIGIN/../lib64:$ORIGIN/../lib' "$WORK"
bzip2 -kf "$WORK"
cp "${WORK}.bz2" "$BIN_DIR/st.bin.bz2"
rm -f "$WORK" "${WORK}.bz2"
echo "Installed: $BIN_DIR/st.bin.bz2"

# The wrapper (bin/st) and the reload helper are plain POSIX sh -- no strip, no
# patchelf, just bzip2 into the payload alongside the ELF.
for helper in st st-reload; do
    bzip2 -kfc "$REPO/build/st/$helper" > "$BIN_DIR/${helper}.bz2"
    echo "Installed: $BIN_DIR/${helper}.bz2"
done

# Remove the pre-split single-binary artifact if this is an upgrade from the
# old layout, so the payload never carries a stale ELF at bin/st.bz2.
if [ -f "$BIN_DIR/st.bz2" ] && bzip2 -dc "$BIN_DIR/st.bz2" | head -c4 | grep -q ELF; then
    echo "NOTE: replacing old ELF-at-bin/st.bz2 with the wrapper" >&2
fi
```

4. Fix the terminfo staging bug: change `mkdir -p "$STAGING/.terminfo/s"` → `mkdir -p "$STAGING/share/terminfo/s"`, `cp "$TI_DIR"/s/st* "$STAGING/.terminfo/s/"` → `"$STAGING/share/terminfo/s/"`, and `tar -cjf "$RUNTIME_DIR/st.tar.bz2" ./.terminfo` → `./share`. This matches the committed archive layout and the registry sentinel `share/terminfo/s/st-256color`.

- [ ] **Step 8: Rebuild through the real script**

```bash
cd /home/mylesp/engineering-loadout
build/build-st.sh --tag 0.9.3 --clean
tar -tjf payload/el8.x86_64.glibc2p28/runtime/st.tar.bz2 | head -3
```
Expected: `st.bin.bz2`, `st.bz2`, `st-reload.bz2` all reported as installed; the archive listing starts with `./share/terminfo/...` (not `./.terminfo/...`).

- [ ] **Step 9: Update the registry `bins` list**

In `payload/packages.json`, the `st` entry:

```json
    "bins": ["st", "st.bin", "st-reload"],
```

Leave `depends`, `archive`, `sentinel`, `install_to`, and `version` as they are.

- [ ] **Step 10: Re-strip, re-manifest, verify, and install-test**

```bash
./strip-all-elf-binaries
./loadout completion bash > envs/bash/global/completions/loadout.bash
build/verify-binaries st
DEST=$(mktemp -d /tmp/st-dest.XXXXXX)
./loadout install st --dest-dir "$DEST" --no-backup
file "$DEST/local/bin/st" "$DEST/local/bin/st.bin"
"$DEST/local/bin/st" -v
```
Expected: `bin/st` is a POSIX shell script, `bin/st.bin` is an ELF, `st -v` prints `st 0.9.3`. (`st -v` exercises the wrapper → ELF exec path without needing X.)

- [ ] **Step 11: Full suite**

Run: `tests/run-all`
Expected: green, including `st-wrapper`, `install-env-st`, `st font list in sync`, `content-verify`, `content-manifest in sync`, `completion in sync`.

- [ ] **Step 12: Commit**

```bash
git add build/st/0001-runtime-xresources-config.patch build/build-st.sh payload/ .strip-manifest .content-manifest envs/bash/global/completions/loadout.bash
git commit -m "feat(st): runtime xresources config + SIGUSR1 reload; ship bin/st wrapper + st.bin"
```

---

### Task 5: Docs + clean-container gate

**Files:**
- Create: `envs/st/README.md`
- Modify: `build/ADDING_BINARIES.md` (st entry)
- Modify: `CLAUDE.md`

**Interfaces:**
- Consumes: everything above. Produces: no code.

- [ ] **Step 1: Write `envs/st/README.md`**

Cover, with real commands: the six-layer chain and merge order; that `global/` is loadout-owned and `user/` is yours; the three ways to reload (`st-reload`, `st-reload --all`, `Ctrl+Shift+R`); that keybindings are compile-time and why; that the font list is generated by `build/gen-st-font-comments` and guarded by a Tier 1 sync test; and the `ST_XRESOURCES` escape hatch for users who want to name their own files.

- [ ] **Step 2: Add the `ADDING_BINARIES.md` st entry**

This is a CLAUDE.md mandate, not a nicety. It must be reproducible without re-deriving anything:
- st 0.9.3 from `https://dl.suckless.org/st/`, EL8, `gcc-toolset-14`.
- Patch order: undercurl (+ the three existing `st.c`/`st.info` fixups) → `build/st/0001-runtime-xresources-config.patch`.
- The patch's provenance (upstream `xresources` + `xresources-with-reload`) and the two loadout deltas.
- The wrapper/`st.bin` split, RPATH `$ORIGIN/../lib64:$ORIGIN/../lib`, strip → patchelf → bzip2 order.
- The terminfo archive layout (`./share/terminfo/s/`) and why the sentinel depends on it.
- On a tag bump: re-derive the patch against the new tree (Task 4 Steps 1–6), and re-verify the undercurl fixups.

- [ ] **Step 3: Add a `CLAUDE.md` section**

Add **"st runtime config behavior"** next to the other per-tool behavior sections: the `ST_XRESOURCES` colon-list contract, the layer chain under `~/.config/st/`, merge precedence (`config.h` < `RESOURCE_MANAGER` < files, later file wins), `SIGUSR1` / `Ctrl+Shift+R` reload, `env-st`'s non-destructive user seeding (and why the generic env handler cannot be used), and the generated font block + its sync test.

Also update the `st terminfo behavior` paragraph if the staging-path fix changes anything a reader would rely on.

- [ ] **Step 4: Manual X smoke (the part CI cannot do)**

`tests/prebuilt-binaries` cannot drive GUI apps, so do this by hand on the dev box and paste the result into the commit message:

```bash
./loadout install st env-st --no-backup
st &
$EDITOR ~/.config/st/user/st.xresources     # uncomment st.font, bump the size
st-reload
```
Expected: the running window changes font live; `Ctrl+Shift+R` does the same; a second `st` launched fresh picks up the same settings.

- [ ] **Step 5: Clean-container gate**

Run: `tests/run-all --container`
Expected: green. st is a GUI app and stays an explicit host-contract skip in the binary probe; what the container proves here is the install behavior — `env-st` seeding, the wrapper chain, the font-list sync, and the registry integrity — on stock EL8 rather than on this dev box.

- [ ] **Step 6: Commit**

```bash
git add envs/st/README.md build/ADDING_BINARIES.md CLAUDE.md
git commit -m "docs(st): runtime config layers, reload, and patch provenance"
```

---

## Self-Review

**Spec coverage:** patch → T4; wrapper + chain → T3; `st-reload` + `Ctrl+Shift+R` → T3/T4; layer chain → T2/T3; opinionated global + commented user template → T1; generated font block + sync test → T1; `env-st` + custom handler → T2; registry/completions → T2/T4; tests → T1/T2/T3; docs → T5; manual X smoke → T5. No spec section is unclaimed.

**Naming consistency:** `ST_XRESOURCES` (env var), `config_init(Display *)`, `xreload(void)`, `reload(const Arg *)`, `reload_requested`, `_install_env_st`, `env-st`, `build/gen-st-font-comments`, `tests/st-wrapper`, `tests/install-env-st` — used identically in every task that references them.

**Known deviation from the spec, deliberate:** the spec's file inventory said the patch would be *derived* from the upstream diffs; Task 4 Step 1 makes that an explicit, reproducible procedure (download upstream, resolve rejects, hand-edit, `git diff`) because upstream renames those diff files per release and a hardcoded URL would rot.
