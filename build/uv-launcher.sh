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
# managed CPython.  An explicit --python, an active virtualenv, or a caller-set
# UV_PYTHON always wins over this default.
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
#
# The prefix is derived from this script's own location, never $HOME, so
# --dest-dir and shared-prefix installs work.

bin_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P) || exit 1

pin=1
case "${1:-}" in
    pip) pin=0 ;;
    run) [ -n "${VIRTUAL_ENV:-}" ] && pin=0 ;;
esac

if [ "$pin" = 1 ] && [ -z "${UV_PYTHON:-}" ]; then
    prefix=$(CDPATH= cd -- "$bin_dir/.." && pwd -P) || exit 1
    if [ -x "$prefix/bin/python3" ]; then
        UV_PYTHON="$prefix/bin/python3"
        export UV_PYTHON
    fi
fi
exec "$bin_dir/uv.bin" "$@"
