#!/bin/sh
# loadout uv launcher -- ties uv to the loadout's managed Python.
#
# Ships as payload bin/uv (a text file); the real upstream binary is bin/uv.bin
# from the same package (the same wrapper pattern as expect/expect.bin,
# gvim/gvim.bin, firefox/firefox-bin).
#
# WHY: without a pin, uv discovers the system python3 first (EL8: 3.6), so
# `uv venv` / `uv tool install` / `uv run` build against an interpreter modern
# tools cannot use; on an air-gapped node uv would instead try to download a
# managed CPython.  An explicit --python, an active virtualenv, a caller-set
# UV_PYTHON, or a project that pins its own Python always wins over this
# default.
#
# Pin source, in order:
#   1. $LOADOUT_PYTHON when it names an executable interpreter -- set by the
#      `module load python/3.12` modulefile, so the loaded version is the
#      default without the module exporting UV_PYTHON itself.
#   2. <prefix>/bin/python3 -- the bundled 3.15.
# LOADOUT_PYTHON is only READ, never exported: it is a loadout-private
# selector, and exporting UV_PYTHON instead would outrank project pins.
#
# The pin is deliberately NOT set for:
#   * `uv pip` -- there UV_PYTHON acts as an implicit install TARGET, so a
#     pinned run would redirect an activated venv's installs into the managed
#     Python (measured).  Without the pin, uv's own target discovery applies:
#     a bare `uv pip install` is refused by uv ("No virtual environment
#     found"), a venv/--python/--system installs where the caller asked.
#   * `uv run` while a virtualenv is active -- VIRTUAL_ENV is the caller's
#     chosen target and UV_PYTHON outranks it (measured), so the pin steps
#     aside.
#   * project-scoped commands in a project that pins its own Python, via
#     .python-version or pyproject.toml requires-python in $PWD or any
#     ancestor: run, sync, lock, venv, add, remove, build, export. UV_PYTHON
#     outranks a project pin (measured: a 3.13 project silently rebuilt on the
#     pinned interpreter), so a project pin must turn the default OFF rather
#     than be overridden by it.
#
# The prefix is derived from this script's own location, never $HOME, so
# --dest-dir and shared-prefix installs work.

bin_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P) || exit 1

# True when the current directory or an ancestor declares a Python version:
# a .python-version file, or a pyproject.toml with a requires-python
# assignment. uv reads both; `uv python pin` with no arguments catches only
# the first, so the launcher detects them itself.
project_pins_python() {
    dir=$PWD
    while [ -n "$dir" ]; do
        if [ -f "$dir/.python-version" ]; then
            return 0
        fi
        if [ -f "$dir/pyproject.toml" ] \
            && grep -Eq '^[[:space:]]*requires-python[[:space:]]*=' "$dir/pyproject.toml" 2>/dev/null; then
            return 0
        fi
        [ "$dir" = "/" ] && break
        dir=$(dirname -- "$dir")
    done
    return 1
}

pin=1
case "${1:-}" in
    pip)
        pin=0
        ;;
    run)
        if [ -n "${VIRTUAL_ENV:-}" ] || project_pins_python; then
            pin=0
        fi
        ;;
    sync | lock | venv | add | remove | build | export)
        if project_pins_python; then
            pin=0
        fi
        ;;
esac

if [ "$pin" = 1 ] && [ -z "${UV_PYTHON:-}" ]; then
    if [ -n "${LOADOUT_PYTHON:-}" ] && [ -x "${LOADOUT_PYTHON}" ]; then
        UV_PYTHON="$LOADOUT_PYTHON"
    else
        prefix=$(CDPATH= cd -- "$bin_dir/.." && pwd -P) || exit 1
        if [ -x "$prefix/bin/python3" ]; then
            UV_PYTHON="$prefix/bin/python3"
        fi
    fi
    if [ -n "${UV_PYTHON:-}" ]; then
        export UV_PYTHON
    fi
fi
exec "$bin_dir/uv.bin" "$@"
