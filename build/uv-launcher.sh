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
#     .python-version, .python-versions, or pyproject.toml requires-python in
#     the project root or any ancestor: run, sync, lock, venv, add, remove,
#     build, export. UV_PYTHON outranks a project pin (measured: a 3.13
#     project silently rebuilt on the pinned interpreter), so a project pin
#     must turn the default OFF rather than be overridden by it.
#
# The subcommand is the first NON-OPTION argument, not necessarily $1, and
# uv's global options are accepted on either side of it (`uv -q venv`,
# `uv venv --directory DIR`, `uv --offline sync`). Matching $1 alone let those
# bypass every carve-out above. Every value-taking global option is consumed
# with its value, and --directory/--project supply the directory the pin walk
# starts from.
#
# UV_PYTHON_DOWNLOADS=never is set for every invocation (spec 6.4): on an
# air-gapped node a missing interpreter must be a loud refusal, never a
# download attempt. A caller that genuinely wants managed downloads can run
# bin/uv.bin directly.
#
# The prefix is derived from this script's own location, never $HOME, so
# --dest-dir and shared-prefix installs work.

bin_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P) || exit 1

# True when START (default $PWD) or an ancestor declares a Python version:
# .python-version, .python-versions, or a pyproject.toml with a
# requires-python assignment. uv reads all three.
project_pins_python() {
    dir=${1:-$PWD}
    if resolved=$(CDPATH= cd -P -- "$dir" 2>/dev/null && pwd -P); then
        dir=$resolved
    else
        # A nonexistent --directory/--project must not stall the walk: turn a
        # still-relative value into an absolute one against $PWD.
        case "$dir" in
            /*) ;;
            *) dir=$PWD/$dir ;;
        esac
    fi
    while [ -n "$dir" ]; do
        if [ -f "$dir/.python-version" ] || [ -f "$dir/.python-versions" ]; then
            return 0
        fi
        if [ -f "$dir/pyproject.toml" ] \
            && grep -Eq '^[[:space:]]*requires-python[[:space:]]*=' "$dir/pyproject.toml" 2>/dev/null; then
            return 0
        fi
        [ "$dir" = "/" ] && break
        parent=$(dirname -- "$dir")
        # dirname's fixed point ('.', '/') ends the walk instead of spinning.
        [ "$parent" = "$dir" ] && break
        dir=$parent
    done
    return 1
}

# First non-option argument = uv subcommand. uv accepts its global options on
# either side of the subcommand, so the scan continues past it: --directory and
# --project move the pin walk's starting root wherever they appear, and every
# value-taking option is skipped with its value so a path/host can never be
# mistaken for the subcommand. `--` ends option parsing. Iterate a copy
# (`for arg in "$@"`) so the original arguments are still intact for exec.
walk_dir=$PWD
command_name=""
expect_value=""
options_open=1
for arg in "$@"; do
    case "$expect_value" in
        root)
            walk_dir=$arg
            expect_value=""
            continue
            ;;
        plain)
            expect_value=""
            continue
            ;;
    esac
    if [ "$options_open" = 0 ]; then
        [ -n "$command_name" ] || command_name=$arg
        continue
    fi
    case "$arg" in
        --)
            options_open=0
            ;;
        --directory | --project)
            expect_value=root
            ;;
        --config-file | --cache-dir | --color | --allow-insecure-host | --trusted-host | --python-preference)
            expect_value=plain
            ;;
        --directory=* | --project=*)
            walk_dir=${arg#*=}
            ;;
        --config-file=* | --cache-dir=* | --color=* | --allow-insecure-host=* | --trusted-host=* | --python-preference=*)
            ;;
        -?*)
            ;;
        *)
            [ -n "$command_name" ] || command_name=$arg
            ;;
    esac
done

pin=1
case "$command_name" in
    pip)
        pin=0
        ;;
    run)
        if [ -n "${VIRTUAL_ENV:-}" ] || project_pins_python "$walk_dir"; then
            pin=0
        fi
        ;;
    sync | lock | venv | add | remove | build | export)
        if project_pins_python "$walk_dir"; then
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

UV_PYTHON_DOWNLOADS=never
export UV_PYTHON_DOWNLOADS

exec "$bin_dir/uv.bin" "$@"
