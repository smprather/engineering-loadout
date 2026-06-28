#!/usr/bin/env python3.14
"""loadout -- package-manager installer body.

Invoked via the POSIX-sh shim `loadout`, which resolves the bundled
portable Python 3.14 and execs this module under it. Direct execution
under any other interpreter is rejected.
"""

import os
import sys

if sys.version_info < (3, 14):  # noqa: UP036 -- defensive: direct invocation under wrong interpreter
    version = ".".join(str(part) for part in sys.version_info[:3])
    print(
        f"Error: loadout_main.py requires Python >= 3.14; found {version}.\n"
        "Run via the './loadout' shim, which bootstraps the bundled "
        "portable Python automatically.",
        file=sys.stderr,
    )
    raise SystemExit(1)

# Vendor path: installer_vendor/ next to this script (rich lives here).
_VENDOR_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "installer_vendor")
if os.path.isdir(_VENDOR_DIR):
    sys.path.insert(0, _VENDOR_DIR)

try:
    from rich.console import Console as _RichConsole
    from rich.progress import (
        BarColumn,
        MofNCompleteColumn,
        TextColumn,
        TimeElapsedColumn,
    )
    from rich.progress import (
        Progress as _RichProgress,
    )
    from rich.table import Table as _RichTable

    _RICH = True
    _console = _RichConsole(highlight=False)
except Exception:
    _RICH = False
    _console = None

# CLI: vendored click + rich-click (in installer_vendor/). rich-click is a drop-in
# replacement for click that renders help text via Rich panels. If either fails to
# import we surface a clear error at startup -- the CLI cannot function without it.
try:
    import rich_click as click

    click.rich_click.USE_RICH_MARKUP = True
    click.rich_click.STYLE_OPTION = "bold cyan"
    click.rich_click.STYLE_ARGUMENT = "bold cyan"
    click.rich_click.STYLE_COMMAND = "bold cyan"
    click.rich_click.STYLE_HELPTEXT = ""
    click.rich_click.STYLE_HELPTEXT_FIRST_LINE = "bold"
    click.rich_click.MAX_WIDTH = 100
except ImportError as exc:
    print(
        f"Error: loadout requires vendored 'click' + 'rich-click' under {_VENDOR_DIR}. Import failed: {exc}",
        file=sys.stderr,
    )
    raise SystemExit(1) from exc


def _vprint(msg):
    """Print only when rich is unavailable (suppresses per-file noise when rich shows progress)."""
    if not _RICH:
        print(msg)


def _progress(description, total):
    """Return a started rich Progress context for `total` items, or None when rich unavailable."""
    if not _RICH:
        return None, None
    p = _RichProgress(
        TextColumn("[cyan]{task.description}"),
        BarColumn(),
        MofNCompleteColumn(),
        TimeElapsedColumn(),
        console=_console,
        transient=True,
    )
    p.start()
    task = p.add_task(description, total=total)
    return p, task


def _show_cursor():
    """Re-emit the DECTCEM show-cursor sequence (ESC[?25h) on exit.

    Rich's transient Progress hides the cursor (ESC[?25l) on .start() and
    restores it on .stop(). On laggy remote terminals (ThinLinc/VNC/SSH) the
    restore can be dropped or reordered across many rapid Progress cycles, and
    an exception mid-extract skips .stop() entirely -- either way the cursor is
    left invisible after the installer exits ('reset' fixes it). Registered via
    atexit so it fires on every normal exit and on sys.exit() (incl. the SIGINT
    handler). Writes to the REAL terminal (sys.__stdout__, not the tee wrapper);
    no-op when that is not a TTY (piped/teed/redirected output).
    """
    try:
        f = sys.__stdout__
        if f is not None and f.isatty():
            f.write("\x1b[?25h")
            f.flush()
    except Exception:
        pass


def _section(title):
    """Print a section heading. Rich: styled bold; plain: plain print."""
    if _RICH:
        assert _console is not None
        _console.print(f"[bold]{title}[/bold]")
    else:
        print(title)


import atexit
import bz2
import contextlib
import datetime
import errno
import fcntl
import fnmatch
import getpass
import json
import types

try:
    import pwd
except ImportError:  # pragma: no cover - Linux installer path has pwd.
    pwd = None
import re
import shlex
import shutil
import signal
import socket
import subprocess
import tarfile
import tempfile
import time
import traceback
import zipfile

FONT_EXCLUDES = (
    "*.bdf",
    "*.eot",
    "*.fon",
    "*.otf",
    "*.pcf",
    "*.ttc",
    "*.ttf",
    "*.woff",
    "*.woff2",
)

BASH_LAYERS = ("corp", "site", "team", "project", "user")
BASH_ENTRYPOINTS = (".bashrc", ".bash_profile", ".bash_login", ".profile")
NVIM_LAYERS = ("corp", "site", "team", "project", "user")


SUPPORTED_SCHEMA_VERSION = 3


def _load_tool_registry(repo_dir):
    """Load pre_built/packages.json. Returns {} if missing or unreadable.

    Required top-level shape (schema_version 3):
        {"schema_version": 3, "packages": {name: entry, ...}, ...}

    Per-entry fields (all optional unless noted otherwise):
      kind         -- package type: 'bin', 'lib-bundle', 'runtime', 'typelib',
                     'python-base', 'python-tool', 'env', 'font', 'data', 'group'.
                     Defaults to 'bin' when absent.
      platforms    -- list of platforms where the entry is valid: 'linux',
                     'macos', 'windows'. Reserved for the resolver.
      depends      -- list of hard-dependency package names. Reserved for the
                     resolver.
      recommends   -- list of soft-dependency package names. Reserved for the
                     resolver.
      bins         -- bin/*.bz2 stems exclusively owned by this entry.
      libs         -- lib64/*.bz2 stems exclusively owned by this entry.
                     Omit or leave empty for libs shared by multiple tools.
      typelibs     -- typelibs/*.typelib files documented as required.
      wheels       -- Python wheel basenames bundled offline.
      uv_tool      -- package name passed to 'uv tool install'.

    Files not claimed by any entry are unregistered and always installed.
    """
    path = os.path.join(repo_dir, "pre_built", "packages.json")
    if not os.path.isfile(path):
        return {}
    try:
        with open(path) as _f:
            raw = json.load(_f)
        if not isinstance(raw, dict) or "schema_version" not in raw or not isinstance(raw.get("packages"), dict):
            warn(f"unsupported packages.json shape; expected schema_version {SUPPORTED_SCHEMA_VERSION}")
            return {}
        version = raw.get("schema_version")
        if version != SUPPORTED_SCHEMA_VERSION:
            warn(
                f"packages.json schema_version is {version!r}; "
                f"installer requires {SUPPORTED_SCHEMA_VERSION}. Tool selection disabled."
            )
            return {}
        entries = raw["packages"]
        return {k: v for k, v in entries.items() if isinstance(v, dict) and not k.startswith("_")}
    except (OSError, ValueError) as _e:
        warn(f"could not read pre_built/packages.json: {_e}; tool selection disabled")
        return {}


class ResolverError(Exception):
    pass


def _current_platform():
    """Return the current OS platform key used by the resolver."""
    if sys.platform.startswith("linux"):
        return "linux"
    if sys.platform == "darwin":
        return "macos"
    if sys.platform == "win32":
        return "windows"
    return "linux"


def _parse_namelist(raw):
    """Split a comma-separated CLI value into a list of trimmed names."""
    if not raw:
        return []
    return [t.strip() for t in raw.split(",") if t.strip()]


# Synthetic groups are computed at runtime (not stored in packages.json).
# expand_groups() special-cases each name below; the descriptions here drive
# `list --groups` and `describe`.
_SYNTHETIC_GROUPS = {
    "@shared": "Every non-env, non-optional package -- install set for a shared/read-only tree.",
    "@shared-all": "@shared plus every non-env optional package (surfer, cicwave, rust, ...).",
    "@envs": "Every per-user env config bundle (the complement of @shared).",
}


def expand_groups(names, registry, _stack=None):
    """Expand @group references recursively into leaf package names.

    @shared is special: every non-group package except per-user "env" config
    bundles -- i.e. everything you install into a shared/read-only tree. @envs
    is its complement (every "env" package); pair them as
    `--only @shared --skip @envs` to keep env recommends out of a shared tree.
    `all` (and the @shared / @engineering-loadout sweeps that build on it) skip
    packages flagged "optional": true -- those install only when named explicitly
    or pulled in by a group that lists them (e.g. surfer, the @rust trio).
    @shared-all is @shared with those optionals folded back in (every non-env
    package regardless of "optional") -- the full shared/read-only tree in one
    name. Cycles in the group graph raise ResolverError.
    Unknown package names produce a warning and are dropped.
    """
    if _stack is None:
        _stack = ()
    out = set()
    for name in names:
        if name == "all":
            out |= {n for n, e in registry.items() if not n.startswith("@") and not e.get("optional")}
            continue
        if name == "@shared":
            out |= {
                n
                for n, e in registry.items()
                if not n.startswith("@") and e.get("kind") != "env" and not e.get("optional")
            }
            continue
        if name == "@shared-all":
            # @shared but optionals INCLUDED -- the full shared/read-only tree.
            out |= {n for n, e in registry.items() if not n.startswith("@") and e.get("kind") != "env"}
            continue
        if name == "@envs":
            out |= {n for n, e in registry.items() if not n.startswith("@") and e.get("kind") == "env"}
            continue
        if name.startswith("@"):
            if name in _stack:
                raise ResolverError("group cycle detected: {} -> {}".format(" -> ".join(_stack), name))
            entry = registry.get(name)
            if entry is None:
                warn(f"unknown group '{name}' (ignored)")
                continue
            members = entry.get("members", [])
            out |= expand_groups(members, registry, _stack + (name,))
            continue
        if name not in registry:
            warn(f"unknown package '{name}' (ignored)")
            continue
        if name.startswith("@"):
            continue  # group key without @-prefix? unreachable, but safe
        out.add(name)
    return out


def walk_depends(names, registry, forbidden=None, force=False):
    """Return names plus the transitive closure of hard 'depends'.

    forbidden: a set of pkg names the user has skipped. If a depended-upon pkg
               is in forbidden, raise ResolverError (unless force is True).
    """
    if forbidden is None:
        forbidden = set()
    out = set()
    pending = list(names)
    parent = {n: None for n in names}
    while pending:
        name = pending.pop()
        if name in out:
            continue
        out.add(name)
        entry = registry.get(name, {})
        for dep in entry.get("depends", []):
            if dep.startswith("@"):
                dep_set = expand_groups([dep], registry)
            else:
                dep_set = {dep}
            for d in dep_set:
                if d in forbidden:
                    if force:
                        warn(f"package '{name}' hard-depends on '{d}' which was skipped (--force: continuing)")
                        continue
                    raise ResolverError(
                        f"package '{name}' hard-depends on '{d}', but '{d}' was passed to --skip. "
                        f"Either remove from --skip, drop '{name}' from selection, or pass --no-deps / --force."
                    )
                if d not in out:
                    parent[d] = name
                    pending.append(d)
    return out


def walk_recommends(names, registry, forbidden=None):
    """Add transitive soft 'recommends'. Silently drop forbidden / unknown."""
    if forbidden is None:
        forbidden = set()
    out = set(names)
    pending = list(names)
    while pending:
        name = pending.pop()
        entry = registry.get(name, {})
        for rec in entry.get("recommends", []):
            if rec.startswith("@"):
                rec_set = expand_groups([rec], registry)
            else:
                rec_set = {rec}
            for r in rec_set:
                if r in forbidden or r in out or r not in registry:
                    continue
                out.add(r)
                pending.append(r)
    return out


def filter_by_platform(names, registry, platform):
    """Drop pkgs whose 'platforms' list excludes the current platform."""
    out = set()
    for n in names:
        entry = registry.get(n, {})
        plats = entry.get("platforms", ["linux"])
        if platform in plats:
            out.add(n)
    return out


def resolve_tool_selection(args, registry):
    """Resolve CLI selectors into a frozenset of package names.

    Resolution steps:
      1. Parse --skip (groups expanded).
      2. Build initial set from --only / --add (groups expanded).
         At least one of --only or --add must be non-empty; the caller is
         responsible for enforcing that.
      3. Subtract --skip.
      4. Walk hard 'depends' (error if any dep is in skip set, unless --no-deps/--force).
      5. Walk soft 'recommends' (silently drop anything in skip set).
      6. Filter by current platform.

    When the registry is empty (legacy / missing JSON) returns None as before.
    """
    if not registry:
        return None  # sentinel: no registry -> install everything

    no_deps = bool(getattr(args, "no_deps", False))
    force = bool(getattr(args, "force", False))

    skip_set = expand_groups(_parse_namelist(args.skip), registry) if args.skip else set()

    only = getattr(args, "only", None)
    add = getattr(args, "add", None)
    if only:
        if add:
            warn("--only overrides --add; --add is ignored")
        selected = expand_groups(_parse_namelist(only), registry)
    elif add:
        selected = expand_groups(_parse_namelist(add), registry)
    else:
        raise ResolverError("no packages specified")

    selected -= skip_set

    if not no_deps:
        selected = walk_depends(selected, registry, forbidden=skip_set, force=force)
        selected = walk_recommends(selected, registry, forbidden=skip_set)

    selected = filter_by_platform(selected, registry, _current_platform())

    return frozenset(selected)


def _tool_bin_sets(selected_tools, registry):
    """Return (allowed_bins, registered_bins) for install-time filtering.

    allowed_bins    -- bin stems that should be installed.
    registered_bins -- every bin stem claimed by any tool entry.

    Bins that appear in no tool entry are unregistered and always installed.
    When selected_tools is None the registry is not consulted (install all).
    """
    registered_bins = set()
    allowed_bins = set()
    for name, info in registry.items():
        bins = info.get("bins", [])
        registered_bins.update(bins)
        if selected_tools is None or name in selected_tools:
            allowed_bins.update(bins)
    return allowed_bins, registered_bins


def _tool_lib_sets(selected_tools, registry):
    """Return (allowed_libs, registered_libs) for install-time filtering.

    Only lib64 stems in a tool's "libs" entry are managed; everything else
    is always installed (shared deps with no single declared owner).
    When selected_tools is None the registry is not consulted (install all).
    """
    registered_libs = set()
    allowed_libs = set()
    for name, info in registry.items():
        libs = info.get("libs", [])
        registered_libs.update(libs)
        if selected_tools is None or name in selected_tools:
            allowed_libs.update(libs)
    return allowed_libs, registered_libs


def eprint(*args):
    print(*args, file=sys.stderr)


def warn(msg):
    eprint(f"  WARNING: {msg}")


def _find_tool(*candidates):
    """Return the first candidate path that is an executable file, or None."""
    for path in candidates:
        if os.path.isfile(path) and os.access(path, os.X_OK):
            return path
    return None


def _bz2_matches_dest(bz2_file, dest_file):
    """True iff decompressed bz2_file is byte-identical to dest_file.

    Used to skip deferred-binary install when the bundled bz2 matches what's
    already on disk (avoids spawning the pending-ops daemon for a no-op).
    Returns False on any I/O error rather than raising.
    """
    if not os.path.isfile(dest_file):
        return False
    try:
        with bz2.open(bz2_file, "rb") as src, open(dest_file, "rb") as dst:
            while True:
                a = src.read(64 * 1024)
                b = dst.read(64 * 1024)
                if a != b:
                    return False
                if not a:
                    return True
    except OSError, EOFError:
        return False


def write_bz2_atomic(bz2_file, dest_file, mode):
    """Decompress bz2_file into dest_file via an atomic rename.

    Writing through a temp file in the same directory means the rename is
    always on the same filesystem (no EXDEV) and the running process keeps
    its mmap to the old inode -- preventing SIGBUS when overwriting in-use
    shared libraries.
    """
    dest_dir = os.path.dirname(dest_file)
    fd, tmp_path = tempfile.mkstemp(dir=dest_dir, prefix=".bz2tmp.")
    try:
        with os.fdopen(fd, "wb") as tmp_fh, bz2.open(bz2_file, "rb") as src_fh:
            shutil.copyfileobj(src_fh, tmp_fh)
        os.chmod(tmp_path, mode)
        os.rename(tmp_path, dest_file)
        tmp_path = None
    finally:
        if tmp_path is not None:
            try:
                os.unlink(tmp_path)
            except OSError:
                pass


class _Bz2Store:
    """Transparent split-bz2 resolver and directory scanner.

    Tracks temp files created when rejoining split parts and removes them
    on process exit.
    """

    def __init__(self):
        self._tmpfiles = []
        import atexit

        atexit.register(self._cleanup)

    def resolve(self, path):
        """Return real filesystem path for logical bz2 path.

        Returns *path* directly when it exists as a plain file.
        When *path* does not exist but ``path + ".part-000"`` does, rejoins
        all ``.part-NNN`` siblings into a temp file and returns that path.
        Returns ``None`` when neither the file nor its parts are present.
        """
        if os.path.isfile(path):
            return path
        part0 = path + ".part-000"
        if not os.path.isfile(part0):
            return None
        parts = glob_paths_glob(path + ".part-*")
        fd, tmp = tempfile.mkstemp(
            prefix="loadout-rejoin.",
            suffix="." + os.path.basename(path),
        )
        self._tmpfiles.append(tmp)
        with os.fdopen(fd, "wb") as out:
            for p in parts:
                with open(p, "rb") as inp:
                    shutil.copyfileobj(inp, out)
        return tmp

    def find(self, dir_path):
        """Return sorted list of logical .bz2 paths in *dir_path*.

        Includes both real .bz2 files and virtual .bz2 paths synthesised from
        ``.bz2.part-000`` sentinels.  Deduplicates when both exist (real wins).
        """
        seen = set()
        results = []
        for name in sorted(os.listdir(dir_path)):
            if name.endswith(".bz2") and ".part-" not in name:
                results.append(os.path.join(dir_path, name))
                seen.add(name)
            elif name.endswith(".bz2.part-000"):
                base = name[: -len(".part-000")]
                if base not in seen:
                    results.append(os.path.join(dir_path, base))
                    seen.add(base)
        return sorted(results)

    def _cleanup(self):
        for p in self._tmpfiles:
            try:
                os.unlink(p)
            except OSError:
                pass


_bz2 = _Bz2Store()


def _prepare_wheels_dir(wheels_dir):
    """Return a directory where all wheels are available as whole (non-chunked) files.

    If wheels_dir contains any *.whl.part-000 chunk files, a temp directory is
    created, all wheels (chunked or whole) are assembled there, and its path is
    returned alongside a cleanup callable.  If no chunks exist, returns the
    original wheels_dir directly with a no-op cleanup.

    Usage::

        effective_dir, cleanup = _prepare_wheels_dir(wheels_dir)
        try:
            # pass effective_dir to uv --find-links
        finally:
            cleanup()
    """
    import glob as _glob_mod

    chunked = _glob_mod.glob(os.path.join(wheels_dir, "*.whl.part-000"))
    if not chunked:
        return wheels_dir, lambda: None

    tmp_dir = tempfile.mkdtemp(prefix="loadout-wheels.")

    # Copy whole wheels directly.
    for whl in _glob_mod.glob(os.path.join(wheels_dir, "*.whl")):
        shutil.copy2(whl, tmp_dir)

    # Rejoin chunked wheels.
    for part0 in chunked:
        base = part0[: -len(".part-000")]  # logical .whl path
        dest = os.path.join(tmp_dir, os.path.basename(base))
        parts = sorted(_glob_mod.glob(base + ".part-*"))
        print(f"  Rejoining: {os.path.basename(base)} ({len(parts)} parts)")
        with open(dest, "wb") as out:
            for part in parts:
                with open(part, "rb") as inp:
                    shutil.copyfileobj(inp, out)

    def _cleanup():
        shutil.rmtree(tmp_dir, ignore_errors=True)

    return tmp_dir, _cleanup


FINAL_NOTICES = []
INSTALL_RESULTS = []
INSTALL_BLOCKERS = []
_SILENT_AREAS = set()  # area names whose non-FAIL results are omitted from install results table


class InstallRefused(Exception):
    pass


def _local_name(home):
    """Name of the per-user tree under the install root: '.local' when the
    root is the real $HOME, 'local' otherwise (an explicit --dest-dir tree).

    Dot-hiding a 'local' dir only makes sense inside a user's HOME; a staged or
    shared deployment under --dest-dir is a normal filesystem location (like
    /usr/local), so it uses an un-dotted 'local'. '.config'/'.cache' are left
    dotted regardless -- they are only written for HOME installs.
    """
    try:
        if os.path.realpath(home) == os.path.realpath(os.path.expanduser("~")):
            return ".local"
    except OSError:
        return ".local"
    return "local"


def _resolve_install_to(raw, home):
    """Anchor a packages.json 'install_to' (e.g. '~/.local/share/helix') to the
    install root, mapping a leading '.local' component to _local_name(home).

    Replaces the old crude `raw.replace('~', home)` so --dest-dir trees land
    under 'local/...'. Absolute install_to values pass through unchanged.
    """
    if raw.startswith("~"):
        rel = raw[1:].lstrip("/")
    elif os.path.isabs(raw):
        return raw
    else:
        rel = raw
    parts = [p for p in rel.split("/") if p]
    if parts and parts[0] == ".local":
        parts[0] = _local_name(home)
    return os.path.join(home, *parts)


def display_name(path):
    home = os.path.expanduser("~")
    try:
        if path == home:
            return "~"
        if path.startswith(home + os.sep):
            return "~/" + os.path.relpath(path, home)
    except ValueError:
        pass
    return path


def nearest_existing_parent(path):
    path = os.path.abspath(path)
    while path and not os.path.exists(path):
        parent = os.path.dirname(path)
        if parent == path:
            break
        path = parent
    return path


def require_writable_dir(path, thing):
    target = os.path.abspath(path)
    existing = target if os.path.exists(target) else nearest_existing_parent(target)
    if not existing:
        existing = os.path.abspath(os.sep)
    if os.path.exists(target) and not os.path.isdir(target):
        existing = os.path.dirname(target)
    if not os.path.isdir(existing) or not os.access(existing, os.W_OK | os.X_OK):
        raise InstallRefused(f"{thing} target directory is not writable: {display_name(existing)}")
    if os.path.isdir(target) and not os.access(target, os.W_OK | os.X_OK):
        raise InstallRefused(f"{thing} target directory is not writable: {display_name(target)}")


def require_writable_parent(path, thing):
    require_writable_dir(os.path.dirname(os.path.abspath(path)) or ".", thing)


def record_result(thing, status, detail=""):
    INSTALL_RESULTS.append((thing, status, detail))


_INTERRUPT_REQUESTED = False
_INTERRUPT_PHASE = None  # "backup" while backup_existing is running, else None
_ACTIVE_BACKUP_DIR = None  # set by backup_existing for sigint cleanup
_ACTIVE_SUBPROCESS = None  # set by run() so handler can SIGTERM child before cleanup
_FOLLOW_SYMLINKS = "auto"  # "yes"|"no"|"auto" -- set by --install-follows-symlinks


def _sigint_handler(signum, frame):
    global _INTERRUPT_REQUESTED
    if _INTERRUPT_PHASE == "backup":
        eprint("\n^C during backup -- removing partial backup and exiting.")
        # Kill any active subprocess still writing into the backup dir.
        # so cleanup doesn't race against its writes. Use os.kill rather than
        # proc.wait() since main thread is already blocked inside communicate().
        proc = _ACTIVE_SUBPROCESS
        if proc is not None:
            try:
                os.kill(proc.pid, signal.SIGKILL)
            except OSError:
                pass
            # Brief settle so the kernel reaps the writes already in flight.
            time.sleep(0.1)
        if _ACTIVE_BACKUP_DIR and os.path.isdir(_ACTIVE_BACKUP_DIR):
            try:
                shutil.rmtree(_ACTIVE_BACKUP_DIR)
                eprint(f"Removed: {_ACTIVE_BACKUP_DIR}")
            except OSError as exc:
                eprint(f"Warning: could not remove {_ACTIVE_BACKUP_DIR}: {exc}")
        _close_run_log("interrupted-during-backup")
        # Silence any post-mortem death-rattle from dying subprocesses
        # "broken pipe" on stderr) -- the install is already aborted, the noise is just noise.
        try:
            sys.stderr.flush()
            devnull = os.open(os.devnull, os.O_WRONLY)
            os.dup2(devnull, 2)
            os.close(devnull)
        except OSError:
            pass
        sys.exit(130)
    if _INTERRUPT_REQUESTED:
        eprint("\n^C^C -- force exit.")
        _close_run_log("interrupted-force")
        sys.exit(130)
    _INTERRUPT_REQUESTED = True
    eprint("\n^C received -- finishing current step then exiting. (Press Ctrl-C again to force quit.)")


def run_install_step(thing, func, *args, **kwargs):
    silent = kwargs.pop("silent", False)
    if silent:
        _SILENT_AREAS.add(thing)
    # No eager "Installing X..." banner -- phases that do work print their own
    # concise line; phases that no-op stay silent (package-manager style).
    try:
        result = func(*args, **kwargs)
        if not any(row[0] == thing for row in INSTALL_RESULTS):
            record_result(thing, "OK", "")
    except InstallRefused as exc:
        warn(str(exc))
        record_result(thing, "FAIL", str(exc))
        result = None
    except KeyboardInterrupt:
        record_result(thing, "FAIL", "interrupted by user (Ctrl-C)")
        global _INTERRUPT_REQUESTED
        _INTERRUPT_REQUESTED = True
        result = None
    except (OSError, subprocess.CalledProcessError) as exc:
        if isinstance(exc, OSError) and exc.errno == errno.ETXTBSY:
            path = _os_error_path(exc)
            artifact = os.path.basename(os.path.normpath(path)) if path else thing
            record_in_use_blocker(thing, artifact, path)
            detail = f"{thing} failed: in use"
            if path:
                detail += f": {path}"
            warn(detail)
            record_result(thing, "FAIL", detail)
            result = None
            if _INTERRUPT_REQUESTED:
                eprint(f"Stopping after '{thing}' step due to Ctrl-C.")
                print_install_results()
                print_install_blockers()
                _close_run_log(130)
                sys.exit(130)
            return result
        detail = f"{thing} failed: {exc}"
        warn(detail)
        traceback.print_exc()
        record_result(thing, "FAIL", detail)
        result = None
    if _INTERRUPT_REQUESTED:
        eprint(f"Stopping after '{thing}' step due to Ctrl-C.")
        print_install_results()
        print_install_blockers()
        _close_run_log(130)
        sys.exit(130)
    return result


def skipped(reason, consequence=None):
    # Intentionally silent. A phase that is not selected (or has no artifact to
    # install) is not news -- package managers don't announce what they skipped.
    # Genuine problems go through warn()/FAIL rows/the blockers table instead.
    return


def command_exists(name):
    return shutil.which(name) is not None


# --- run-log: when invoked from inside a repo clone, tee every print/eprint
# and every subprocess invocation into repo/.loadout-logs/install-<ts>-<pid>.log
# so an AI assistant (or the user) can review post-mortem. Setup happens in
# main() once we know repo_dir; before then this stays None and is a no-op.
_RUN_LOG_FILE = None
_RUN_LOG_PATH = ""


def _log(msg):
    """Append one timestamped line to the run-log if it is open."""
    if _RUN_LOG_FILE is None:
        return
    try:
        ts = datetime.datetime.now().strftime("%H:%M:%S.%f")[:-3]
        _RUN_LOG_FILE.write(f"[{ts}] {msg}\n")
        _RUN_LOG_FILE.flush()
    except OSError, ValueError:
        pass


class _TeeStream:
    """Wraps a stdio stream; mirrors output into the run-log with timestamps."""

    def __init__(self, original, kind):
        self._original = original
        self._kind = kind
        self._buf = ""

    def write(self, s):
        self._original.write(s)
        if _RUN_LOG_FILE is None:
            return
        self._buf += s
        while "\n" in self._buf:
            line, self._buf = self._buf.split("\n", 1)
            try:
                ts = datetime.datetime.now().strftime("%H:%M:%S.%f")[:-3]
                _RUN_LOG_FILE.write(f"[{ts}] [{self._kind}] {line}\n")
                _RUN_LOG_FILE.flush()
            except OSError, ValueError:
                pass

    def flush(self):
        self._original.flush()
        if _RUN_LOG_FILE is not None:
            try:
                _RUN_LOG_FILE.flush()
            except OSError, ValueError:
                pass

    def __getattr__(self, name):
        return getattr(self._original, name)


# Per-user suffix on shared-/tmp state so concurrent users on one farm node
# don't collide on (or fail to open) each other's log/pending files.
_TMP_USER = getpass.getuser()

_RUN_LOG_FIXED_PATH = f"/tmp/loadout.{_TMP_USER}.log"


def _setup_run_log(repo_dir, argv):
    """If repo_dir is a git clone, append this run's activity to the single
    rolling per-user log file (see _RUN_LOG_FIXED_PATH)."""
    global _RUN_LOG_FILE, _RUN_LOG_PATH
    if not os.path.isdir(os.path.join(repo_dir, ".git")):
        return
    _RUN_LOG_PATH = _RUN_LOG_FIXED_PATH
    try:
        _RUN_LOG_FILE = open(_RUN_LOG_PATH, "a", buffering=1)
    except OSError as exc:
        sys.stderr.write(f"Note: could not open run-log {_RUN_LOG_PATH}: {exc}\n")
        _RUN_LOG_FILE = None
        return
    # Per-run header -- separator + metadata so successive runs are distinguishable
    # when grep-ing/tailing the rolling log.
    _RUN_LOG_FILE.write("\n")
    _RUN_LOG_FILE.write("================================================================\n")
    _RUN_LOG_FILE.write("# loadout run\n")
    _RUN_LOG_FILE.write(f"# started: {datetime.datetime.now().isoformat()}\n")
    _RUN_LOG_FILE.write(f"# repo:    {repo_dir}\n")
    _RUN_LOG_FILE.write("# argv:    {}\n".format(" ".join(argv)))
    _RUN_LOG_FILE.write(f"# pid:     {os.getpid()}\n")
    _RUN_LOG_FILE.write(f"# cwd:     {os.getcwd()}\n")
    _RUN_LOG_FILE.write("================================================================\n")
    _RUN_LOG_FILE.flush()
    # Replace stdio so all print/eprint output flows in.
    sys.stdout = _TeeStream(sys.stdout, "out")
    sys.stderr = _TeeStream(sys.stderr, "err")
    # No "Run log: ..." print -- path is fixed per user (_RUN_LOG_FIXED_PATH).


def _close_run_log(exit_code):
    global _RUN_LOG_FILE
    if _RUN_LOG_FILE is None:
        return
    try:
        _RUN_LOG_FILE.write("#\n")
        _RUN_LOG_FILE.write(f"# ended:   {datetime.datetime.now().isoformat()}\n")
        _RUN_LOG_FILE.write(f"# exit:    {exit_code}\n")
        _RUN_LOG_FILE.flush()
        _RUN_LOG_FILE.close()
    except OSError, ValueError:
        pass
    _RUN_LOG_FILE = None


def run(cmd, cwd=None, env=None, check=True, stdout=None, stderr=None):
    global _ACTIVE_SUBPROCESS
    # start_new_session=True isolates the child from the terminal's process group
    # so a Ctrl-C at the keyboard only reaches the installer, not child processes.
    # The installer's SIGINT handler decides whether to SIGKILL the child (backup
    # cleanup) or let it finish (other steps).
    if _RUN_LOG_FILE is not None:
        _log(f"subprocess.run: cwd={cwd or os.getcwd()} cmd={cmd}")
    _t0 = time.time()
    proc = subprocess.Popen(cmd, cwd=cwd, env=env, stdout=stdout, stderr=stderr, start_new_session=True)
    _ACTIVE_SUBPROCESS = proc
    try:
        out, err = proc.communicate()
    finally:
        _ACTIVE_SUBPROCESS = None
    if _RUN_LOG_FILE is not None:
        _log(
            "subprocess.done rc={} dur={:.2f}s cmd={}".format(proc.returncode, time.time() - _t0, cmd[0] if cmd else "")
        )
    if check and proc.returncode != 0:
        raise subprocess.CalledProcessError(proc.returncode, cmd, output=out, stderr=err)
    completed = subprocess.CompletedProcess(cmd, proc.returncode, stdout=out, stderr=err)
    return completed


def output(cmd, cwd=None, env=None, check=True):
    if _RUN_LOG_FILE is not None:
        _log(f"subprocess.output: cwd={cwd or os.getcwd()} cmd={cmd}")
    proc = subprocess.run(cmd, cwd=cwd, env=env, check=check, capture_output=True)
    if _RUN_LOG_FILE is not None:
        _log("subprocess.output done rc={} cmd={}".format(proc.returncode, cmd[0] if cmd else ""))
    return proc.stdout.decode("utf-8", "replace")


def remove_path(path):
    require_writable_parent(path, "remove")
    if os.path.islink(path) or os.path.isfile(path):
        os.unlink(path)
    elif os.path.isdir(path):
        shutil.rmtree(path)


def lns(target, link_name, unsafe=False, verbose=False):
    require_writable_parent(link_name, "symlink")
    if os.path.lexists(link_name):
        if os.path.isdir(link_name) and not os.path.islink(link_name):
            if not unsafe:
                eprint(f"Error: '{link_name}' exists as a directory and cannot be removed (use --unsafe to override)")
                sys.exit(1)
            if verbose and not _RICH:
                eprint(f"rm -rf '{link_name}'")
            shutil.rmtree(link_name)
        else:
            if verbose and not _RICH:
                eprint(f"rm -f '{link_name}'")
            os.unlink(link_name)
    if verbose and not _RICH:
        eprint(f"ln -s {target} {link_name}")
    os.symlink(target, link_name)


def mkdirn(base_dir):
    require_writable_dir(os.path.dirname(os.path.abspath(base_dir)), "backup")
    counter = 1
    while True:
        target_dir = f"{base_dir}.{counter}"
        archive = target_dir + ".tar.bz2"
        if not os.path.exists(target_dir) and not os.path.exists(archive):
            try:
                os.makedirs(target_dir)
                return target_dir
            except FileExistsError:
                pass  # concurrent run claimed this number -- keep counting
        counter += 1


def _is_excluded(rel_path, excludes):
    rel_path = rel_path.strip("/")
    if not rel_path:
        return False
    base = os.path.basename(rel_path)
    parts = rel_path.split("/")
    for pattern in excludes or ():
        if fnmatch.fnmatch(rel_path, pattern) or fnmatch.fnmatch(base, pattern):
            return True
        if any(fnmatch.fnmatch(part, pattern) for part in parts):
            return True
    return False


def _copy_tree_item(src, dest, excludes=(), rel_path=""):
    if _is_excluded(rel_path, excludes):
        return
    # Match rsync's behavior for a source entry that disappears between listdir()
    # and copy/stat, which can happen when another session edits generated trees.
    if not os.path.lexists(src):
        return
    if os.path.islink(src):
        if os.path.lexists(dest):
            remove_path(dest)
        ensure_dir(os.path.dirname(dest))
        try:
            link_target = os.readlink(src)
        except FileNotFoundError:
            return
        os.symlink(link_target, dest)
        try:
            shutil.copystat(src, dest, follow_symlinks=False)
        except FileNotFoundError, OSError:
            pass
        return
    if os.path.isdir(src):
        if os.path.lexists(dest) and not os.path.isdir(dest):
            remove_path(dest)
        ensure_dir(dest)
        try:
            names = os.listdir(src)
        except FileNotFoundError:
            return
        for name in names:
            child_rel = os.path.join(rel_path, name) if rel_path else name
            _copy_tree_item(os.path.join(src, name), os.path.join(dest, name), excludes, child_rel)
        try:
            shutil.copystat(src, dest)
        except FileNotFoundError, OSError:
            pass
        return
    if os.path.lexists(dest):
        remove_path(dest)
    ensure_dir(os.path.dirname(dest))
    try:
        shutil.copy2(src, dest, follow_symlinks=False)
    except FileNotFoundError:
        return


def sync_dir(src, dest, delete=False, excludes=None):
    excludes = tuple(excludes or ())
    if os.path.islink(dest):
        require_writable_parent(dest, "copy")
        remove_path(dest)
    src_real = os.path.realpath(src)
    dest_real = os.path.realpath(dest)
    if src_real == dest_real:
        return
    try:
        common = os.path.commonpath([src_real, dest_real])
    except ValueError:
        common = ""
    if common in (src_real, dest_real):
        raise InstallRefused(f"copy source and destination overlap: {display_name(src)} -> {display_name(dest)}")
    require_writable_dir(dest if os.path.isdir(dest) else os.path.dirname(dest), "copy")
    ensure_dir(dest)
    if delete and os.path.isdir(dest):
        try:
            src_names = set(os.listdir(src)) if os.path.isdir(src) else set()
        except FileNotFoundError:
            src_names = set()
        for name in os.listdir(dest):
            if name in src_names or _is_excluded(name, excludes):
                continue
            remove_path(os.path.join(dest, name))
    try:
        names = os.listdir(src)
    except FileNotFoundError:
        return
    for name in names:
        _copy_tree_item(os.path.join(src, name), os.path.join(dest, name), excludes, name)


def install_path(src, dest, links_mode):
    if links_mode:
        lns(src, dest, verbose=True)
        return

    require_writable_parent(dest, "install")
    if os.path.isdir(src) and not os.path.islink(src):
        if os.path.islink(dest):
            os.unlink(dest)
        ensure_dir(dest, "install")
        sync_dir(src, dest, delete=True)
        _vprint(f"  copy: {src}/ -> {dest}/")
    else:
        if os.path.lexists(dest):
            remove_path(dest)
        parent = os.path.dirname(dest)
        if parent:
            ensure_dir(parent)
        shutil.copy2(src, dest)
        _vprint(f"  cp: {src} -> {dest}")


def backup_item(src, dest):
    require_writable_parent(dest, "backup")
    ensure_dir(os.path.dirname(dest))
    _copy_tree_item(src, dest, FONT_EXCLUDES)


def is_wsl():
    try:
        with open("/proc/version") as fh:
            return re.search(r"microsoft|wsl", fh.read(), re.IGNORECASE) is not None
    except OSError:
        return False


def _is_online(timeout=2.0):
    """Return True if we appear to have internet access.

    Checks LOADOUT_ONLINE env var first (set by bash loadout_detect_online).
    Falls back to a direct TCP probe to github.com:443.
    """
    env_val = os.environ.get("LOADOUT_ONLINE", "")
    if env_val == "1":
        return True
    if env_val == "0":
        return False
    try:
        conn = socket.create_connection(("github.com", 443), timeout=timeout)
        conn.close()
        return True
    except OSError:
        return False


_UNAME = _find_tool("/usr/bin/uname")
_LDD = _find_tool("/usr/bin/ldd")
_GETCONF = _find_tool("/usr/bin/getconf")
_PGREP = _find_tool("/usr/bin/pgrep")
_CP = _find_tool("/usr/bin/cp")
_GIT = _find_tool("/usr/bin/git", "/usr/local/bin/git")


def _get_version(repo_dir):
    """Return version string for this installer.

    Tries `git describe --tags --always --dirty` from the repo dir; falls back
    to "unknown" if git isn't available or the repo dir isn't a git checkout.
    """
    if _GIT and os.path.isdir(os.path.join(repo_dir, ".git")):
        try:
            return (
                output(
                    [_GIT, "-C", repo_dir, "describe", "--tags", "--always", "--dirty"],
                    check=False,
                ).strip()
                or "unknown"
            )
        except OSError, subprocess.CalledProcessError:
            pass
    return "unknown"


def _exes_by_path(path):
    """Return list of PIDs whose /proc/<pid>/exe resolves to path."""
    pids = []
    path = os.path.realpath(path)
    try:
        for entry in os.listdir("/proc"):
            if not entry.isdigit():
                continue
            try:
                exe = os.readlink(f"/proc/{entry}/exe")
            except OSError:
                continue
            # Kernel appends " (deleted)" when the inode was replaced after exec.
            if exe == path or exe == path + " (deleted)":
                pids.append(int(entry))
    except OSError:
        pass
    return pids


def _pid_owner(pid):
    try:
        with open(f"/proc/{pid}/status") as fh:
            for line in fh:
                if line.startswith("Uid:"):
                    uid = int(line.split()[1])
                    if pwd is not None:
                        try:
                            return pwd.getpwuid(uid).pw_name
                        except KeyError:
                            pass
                    return str(uid)
    except OSError, ValueError:
        pass
    return "unknown"


def _pid_command(pid):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as fh:
            raw = fh.read().rstrip(b"\0")
        if raw:
            cmd = raw.replace(b"\0", b" ").decode("utf-8", "replace")
            return cmd if len(cmd) <= 180 else cmd[:177] + "..."
    except OSError:
        pass
    try:
        with open(f"/proc/{pid}/comm") as fh:
            return fh.read().strip()
    except OSError:
        return "unknown"


def _process_records_for_path(path):
    records = []
    for pid in _exes_by_path(path):
        records.append({"pid": str(pid), "owner": _pid_owner(pid), "command": _pid_command(pid)})
    if not records:
        records.append({"pid": "unknown", "owner": "unknown", "command": "process exited or hidden"})
    return records


def _install_blocker_key(row):
    return (row["area"], row["artifact"], row["path"], row["pid"], row["command"])


def record_in_use_blocker(area, artifact, path):
    """Record processes blocking an install path. Tmux is reported separately."""
    path = os.path.normpath(path) if path else ""
    if artifact == "tmux" or os.path.basename(path) == "tmux":
        return

    seen = {_install_blocker_key(row) for row in INSTALL_BLOCKERS}
    records = (
        _process_records_for_path(path) if path else [{"pid": "unknown", "owner": "unknown", "command": "unknown"}]
    )
    for rec in records:
        row = {
            "area": area,
            "artifact": artifact,
            "path": path,
            "reason": "in use",
            "pid": rec.get("pid", "unknown"),
            "owner": rec.get("owner", "unknown"),
            "command": rec.get("command", "unknown"),
        }
        key = _install_blocker_key(row)
        if key not in seen:
            INSTALL_BLOCKERS.append(row)
            seen.add(key)


def _os_error_path(exc):
    return getattr(exc, "filename", None) or getattr(exc, "filename2", None) or ""


def uname(flag):
    return output([_UNAME, flag]).strip()


def ldd_is_musl():
    if not _LDD:
        return False
    proc = subprocess.run([_LDD, "--version"], stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    return b"musl" in proc.stdout.lower()


def treesitter_platform_id():
    libc = "musl" if ldd_is_musl() else "glibc"
    return "{}-{}-{}".format(uname("-s").lower(), uname("-m"), libc)


def glibc_version_id():
    if _GETCONF:
        try:
            text = output([_GETCONF, "GNU_LIBC_VERSION"], check=False).strip()
            parts = text.split()
            if len(parts) >= 2:
                return parts[1]
        except OSError:
            pass
    if _LDD:
        proc = subprocess.run([_LDD, "--version"], stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        match = re.search(rb"[0-9]+\.[0-9]+", proc.stdout)
        if match:
            return match.group(0).decode("ascii")
    return ""


def glibc_version_num(version):
    match = re.match(r"^([0-9]+)\.([0-9]+)", version or "")
    if not match:
        return 0
    return int(match.group(1)) * 1000 + int(match.group(2))


def read_os_release():
    data = {}
    try:
        with open("/etc/os-release") as fh:
            for line in fh:
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                key, value = line.split("=", 1)
                data[key] = value.strip().strip('"')
    except OSError:
        pass
    return data


def prebuilt_exact_platform_ids():
    arch = uname("-m")
    if ldd_is_musl():
        return [f"linux.{arch}.musl", f"linux-{arch}-musl"]

    glibc_version = glibc_version_id()
    glibc_id = "glibc{}".format(glibc_version.replace(".", "p")) if glibc_version else ""
    osr = read_os_release()
    distro_id = osr.get("ID", "")
    id_like = osr.get("ID_LIKE", "")
    version_id = osr.get("VERSION_ID", "")
    platform_id = osr.get("PLATFORM_ID", "")
    el_id = ""

    if platform_id.startswith("platform:el"):
        el_id = platform_id[len("platform:") :]
    elif any(
        x in (" " + distro_id + " " + id_like + " ") for x in (" rhel ", " centos ", " almalinux ", " rocky ", " ol ")
    ):
        el_id = "el{}".format(version_id.split(".", 1)[0])

    ids = []
    if el_id and glibc_id:
        ids.append(f"{el_id}.{arch}.{glibc_id}")
    if glibc_id:
        ids.append(f"linux.{arch}.{glibc_id}")
    ids.append(f"linux.{arch}.glibc")
    ids.append(f"linux-{arch}-glibc")
    return ids


def select_prebuilt_platform_dir(root_dir):
    for candidate in prebuilt_exact_platform_ids():
        path = os.path.join(root_dir, candidate)
        if os.path.isdir(path):
            return path

    arch = uname("-m")
    host_num = glibc_version_num(glibc_version_id())
    if not host_num:
        return None

    best_dir = None
    best_num = 0
    if not os.path.isdir(root_dir):
        return None
    for name in os.listdir(root_dir):
        path = os.path.join(root_dir, name)
        if not os.path.isdir(path):
            continue
        if not (fnmatch.fnmatch(name, f"el*.{arch}.glibc*p*") or fnmatch.fnmatch(name, f"linux.{arch}.glibc*p*")):
            continue
        match = re.search(r"\.glibc([0-9]+)p([0-9]+)$", name)
        if not match:
            continue
        build_num = glibc_version_num(f"{match.group(1)}.{match.group(2)}")
        if build_num <= host_num and build_num > best_num:
            best_num = build_num
            best_dir = path
    return best_dir


_PENDING_DIR = f"/tmp/loadout-pending-{_TMP_USER}"
_PENDING_TIMEOUT_SECS = 7 * 24 * 3600  # 1 week


def _pending_json_path():
    return os.path.join(_PENDING_DIR, "pending.json")


def _now_utc_iso():
    return datetime.datetime.now(datetime.UTC).strftime("%Y-%m-%dT%H:%M:%SZ")


@contextlib.contextmanager
def _pending_lock():
    """Exclusive flock on pending.lock -- serialises installer and daemon JSON writes."""
    lock_path = os.path.join(_PENDING_DIR, "pending.lock")
    try:
        fh = open(lock_path, "w")
    except OSError:
        yield  # Can't open lock file; proceed without lock (best-effort).
        return
    try:
        fcntl.flock(fh, fcntl.LOCK_EX)
        yield
    finally:
        fcntl.flock(fh, fcntl.LOCK_UN)
        fh.close()


def _read_pending_state():
    """Return (ops_by_dest, last_activity_iso) without holding any lock."""
    try:
        with open(_pending_json_path()) as f:
            data = json.load(f)
        ops = {op["dest"]: op for op in data.get("ops", []) if "dest" in op}
        last_activity = data.get("last_activity", "")
        return ops, last_activity
    except OSError, ValueError:
        return {}, ""


def _write_pending_state(ops_by_dest, last_activity_iso):
    """Atomically write pending.json. Caller must hold _pending_lock()."""
    tmp = _pending_json_path() + ".tmp"
    with open(tmp, "w") as f:
        json.dump(
            {
                "schema_version": 1,
                "last_activity": last_activity_iso,
                "ops": list(ops_by_dest.values()),
            },
            f,
            indent=2,
        )
        f.flush()
        os.fsync(f.fileno())
    os.rename(tmp, _pending_json_path())


def stage_pending_ops(blocked_binaries, bin_dir, dest_bin_dir, repo_dir):
    """Stage blocked binaries to /tmp and spawn the pending-ops daemon."""
    if not blocked_binaries:
        return

    files_dir = os.path.join(_PENDING_DIR, "files")
    try:
        if not os.path.isdir(_PENDING_DIR):
            os.makedirs(_PENDING_DIR)
        if not os.path.isdir(files_dir):
            os.makedirs(files_dir)
    except OSError as exc:
        warn(f"could not create pending dir {_PENDING_DIR}: {exc}")
        return

    # Decompress staged files outside the lock (potentially slow I/O).
    staged_map = {}  # name -> staged_path
    for name in sorted(blocked_binaries):
        bz2_path = os.path.join(bin_dir, name + ".bz2")
        if not os.path.isfile(bz2_path):
            continue
        staged = os.path.join(files_dir, name)
        try:
            write_bz2_atomic(bz2_path, staged, 0o755)
        except OSError as exc:
            warn(f"could not stage {name}: {exc}")
            continue
        staged_map[name] = staged
        print(f"  staged pending op: {staged} -> {os.path.join(dest_bin_dir, name)}")

    if not staged_map:
        return

    # Merge into pending.json under lock; new entry supersedes old by dest path.
    # Always update last_activity so the daemon's 1-week timeout resets.
    now = _now_utc_iso()
    with _pending_lock():
        existing, _ = _read_pending_state()
        for name, staged in staged_map.items():
            dest = os.path.join(dest_bin_dir, name)
            existing[dest] = {
                "type": "install_binary",
                "dest": dest,
                "staged": staged,
                "mode": 0o755,
                "block": {"type": "proc_exe_absent", "path": dest},
            }
        _write_pending_state(existing, now)

    # Copy daemon script to pending dir and spawn if not already running.
    daemon_src = os.path.join(repo_dir, "pre_built", "build_scripts", "loadout-pending-daemon")
    daemon_dst = os.path.join(_PENDING_DIR, "daemon.py")
    if os.path.isfile(daemon_src):
        try:
            shutil.copy2(daemon_src, daemon_dst)
        except OSError as exc:
            warn(f"could not copy daemon script: {exc}")
            return
    elif not os.path.isfile(daemon_dst):
        warn(f"daemon script not found at {daemon_src} -- pending ops will not auto-apply")
        return

    # Check if daemon already running via pidfile.
    pid_file = os.path.join(_PENDING_DIR, "daemon.pid")
    try:
        with open(pid_file) as f:
            pid = int(f.read().strip())
        os.kill(pid, 0)
        print(f"  pending-ops daemon already running (pid {pid})")
        return
    except OSError, ValueError:
        pass

    log_file = os.path.join(_PENDING_DIR, "daemon.log")
    log_fh = None
    try:
        log_fh = open(log_file, "a")
        proc = subprocess.Popen(
            [sys.executable, daemon_dst],
            stdout=log_fh,
            stderr=log_fh,
            close_fds=True,
            start_new_session=True,
        )
        print(f"  pending-ops daemon spawned (pid {proc.pid}), log: {log_file}")
    except OSError as exc:
        warn(f"could not spawn pending-ops daemon: {exc}")
    finally:
        if log_fh is not None:
            log_fh.close()


def install_prebuilt_binaries(repo_dir, home, selected_tools=None):
    root_dir = os.path.join(repo_dir, "pre_built")
    dest_bin_dir = os.path.join(home, _local_name(home), "bin")
    dest_lib64_dir = os.path.join(home, _local_name(home), "lib64")

    if not os.path.isdir(root_dir):
        skipped(
            "pre-built binaries (no pre_built/ directory in repo)",
            "eza, fd, rg, tmux and other bundled tools will NOT be installed",
        )
        record_result("pre-built binaries", "SKIP", "no pre_built/ directory")
        return set()

    src_dir = select_prebuilt_platform_dir(root_dir)
    if not src_dir:
        skipped(
            "pre-built binaries (no matching platform)",
            "eza, fd, rg, tmux and other bundled tools will NOT be installed",
        )
        eprint("  Checked platform IDs: {}".format(" ".join(prebuilt_exact_platform_ids())))
        record_result("pre-built binaries", "SKIP", "no matching platform")
        return set()

    # blocked_deferred: tmux detected running by exe path -> staged for daemon.
    # blocked_failed: other binaries still in use after 10s retry -> name -> "PID,..." string.
    blocked_deferred = set()
    blocked_failed = {}

    _registry = _load_tool_registry(repo_dir)
    _allowed_bins, _registered_bins = _tool_bin_sets(selected_tools, _registry)
    _allowed_libs, _registered_libs = _tool_lib_sets(selected_tools, _registry)

    if selected_tools is not None and not _allowed_bins and not _allowed_libs:
        # Selection contributes no binary or shared library (e.g. an env-only
        # install) -- don't touch ~/.local/bin or ~/.local/lib64 at all, not even
        # the always-on base libs that only exist to support binaries.
        skipped("pre-built binaries (no binaries or libraries selected)", "")
        record_result("pre-built binaries", "SKIP", "no bin/lib packages selected")
        return set()

    def _bin_selected(stem):
        # Unregistered stems (not claimed by any tool) are always installed.
        return stem not in _registered_bins or stem in _allowed_bins

    def _lib_selected(stem):
        return stem not in _registered_libs or stem in _allowed_libs

    bin_dir = os.path.join(src_dir, "bin")
    if os.path.isdir(bin_dir):
        ensure_dir(dest_bin_dir, "pre-built binaries")
        # Long-running session binaries: detected by exe path (not name), deferred via
        # the pending-ops daemon so the user never has to manually re-run the installer.
        # tmux: server/client must be same version; NFS atomic rename still leaves old
        #       server running with the old inode while new clients exec the new binary.
        # bash: safe to replace live -- write_bz2_atomic uses os.rename (atomic inode swap),
        #       so the running shell keeps its old inode and new shells get the new binary.
        #       No bash->bash IPC, so no version-mismatch risk.
        _DEFERRED_BINARIES = {"tmux"}

        _bin_bz2_files = sorted(f for f in _bz2.find(bin_dir) if _bin_selected(os.path.basename(f)[:-4]))
        _max_bin_name = max((len(os.path.basename(f[:-4])) for f in _bin_bz2_files), default=0)
        _bins_unchanged = 0

        # Don't silently "succeed" when a selected package has no built artifact.
        # Only flag genuine bin packages: skip those whose bins come from a runtime
        # archive (e.g. nodejs -> node.tar.bz2) and python-tools (uv launchers).
        if selected_tools is not None:
            _present_stems = {os.path.basename(f)[:-4] for f in _bz2.find(bin_dir)}
            for _pname in sorted(selected_tools):
                _e = _registry.get(_pname, {})
                if _e.get("kind") != "bin" or _e.get("archive") or "uv_tool" in _e:
                    continue
                _claimed = _e.get("bins", [])
                if _claimed and not any(b in _present_stems for b in _claimed):
                    warn(
                        "selected '{}' has no bundled artifact (none of {} present in bin/) -- not installed".format(
                            _pname, "/".join(_claimed[:3]) + ("..." if len(_claimed) > 3 else "")
                        )
                    )
        _progress_ctx = (
            _RichProgress(
                TextColumn("[cyan]{task.description}"),
                BarColumn(),
                MofNCompleteColumn(),
                TimeElapsedColumn(),
                console=_console,
                transient=True,
            )
            if _RICH
            else None
        )
        _progress_task = None
        if _progress_ctx is not None:
            _progress_ctx.start()
            _progress_task = _progress_ctx.add_task("Installing binaries", total=len(_bin_bz2_files))

        for bz2_file in _bin_bz2_files:
            dest_file = os.path.join(dest_bin_dir, os.path.basename(bz2_file[:-4]))
            name = os.path.basename(dest_file)
            bz2_src = _bz2.resolve(bz2_file)
            if bz2_src is None:
                warn(f"skipping {name} -- bz2 or split parts missing at {bz2_file}")
                continue

            if _progress_ctx is not None:
                _progress_ctx.update(_progress_task, description=f"  {name.ljust(_max_bin_name)}")

            if name in _DEFERRED_BINARIES:
                pids = _exes_by_path(dest_file)
                if pids:
                    # Only defer if the bundled bz2 actually differs from what's
                    # already installed. Otherwise a no-op rerun would needlessly
                    # spawn a daemon + ask the user to restart their tmux server.
                    if _bz2_matches_dest(bz2_src, dest_file):
                        print(f"  {name} already current, skipping")
                        if _progress_ctx is not None:
                            _progress_ctx.advance(_progress_task)
                        continue
                    blocked_deferred.add(name)
                    warn(
                        "skipping {} -- running at {} (PIDs: {})".format(
                            name, dest_file, ", ".join(str(p) for p in pids)
                        )
                    )
                    if _progress_ctx is not None:
                        _progress_ctx.advance(_progress_task)
                    continue
                # Not running from this path; attempt install normally and fall through.

            # Skip no-op installs: when dest already byte-identical to the bundled
            # bz2, avoid the decompress + atomic-rename + chmod + fsync. Cuts disk
            # churn on re-runs (matters for restic/rsync delta noise downstream).
            if _bz2_matches_dest(bz2_src, dest_file):
                _bins_unchanged += 1
                _vprint(f"  unchanged: {name}")
                if _progress_ctx is not None:
                    _progress_ctx.advance(_progress_task)
                continue

            try:
                require_writable_parent(dest_file, "pre-built binaries")
                write_bz2_atomic(bz2_src, dest_file, 0o755)
            except OSError as exc:
                if exc.errno != errno.ETXTBSY:
                    if _progress_ctx is not None:
                        _progress_ctx.stop()
                    raise
                if name in _DEFERRED_BINARIES:
                    # Proactive check passed but rename raced with a new exec; defer anyway.
                    blocked_deferred.add(name)
                    warn(f"could not replace {dest_file} (ETXTBSY race) -- deferring")
                    if _progress_ctx is not None:
                        _progress_ctx.advance(_progress_task)
                    continue
                # Non-deferred binary: retry once/second for up to 10 seconds.
                replaced = False
                for _attempt in range(10):
                    time.sleep(1)
                    try:
                        write_bz2_atomic(bz2_src, dest_file, 0o755)
                        replaced = True
                        break
                    except OSError as retry_exc:
                        if retry_exc.errno != errno.ETXTBSY:
                            if _progress_ctx is not None:
                                _progress_ctx.stop()
                            raise
                if not replaced:
                    pids = _exes_by_path(dest_file)
                    pid_str = ", ".join(str(p) for p in pids) if pids else "unknown"
                    blocked_failed[name] = pid_str
                    record_in_use_blocker("pre-built binaries", name, dest_file)
                    warn(f"could not replace {dest_file} after 10s: in use (PIDs: {pid_str})")
                    if _progress_ctx is not None:
                        _progress_ctx.advance(_progress_task)
                    continue
            if _progress_ctx is None:
                print(f"  bzip2: {bz2_file} -> {dest_file}")
            if _progress_ctx is not None:
                _progress_ctx.advance(_progress_task)

        if _progress_ctx is not None:
            _progress_ctx.stop()

    lib64_dir = os.path.join(src_dir, "lib64")
    if os.path.isdir(lib64_dir):
        ensure_dir(dest_lib64_dir, "pre-built libraries")
        # Remove any previously deployed glibc libs -- they must never be bundled because
        # they must match the system ld-linux.so.2 exactly; a mismatch causes GLIBC_PRIVATE
        # symbol lookup errors at runtime.
        _GLIBC_LIBS = ("libc.so.6", "libm.so.6", "libpthread.so.0", "libdl.so.2", "librt.so.1")
        for _glib in _GLIBC_LIBS:
            _glib_path = os.path.join(dest_lib64_dir, _glib)
            if os.path.isfile(_glib_path):
                os.remove(_glib_path)
                print(f"  removed stale glibc lib: {_glib_path}")
        _lib64_bz2_files = sorted(f for f in _bz2.find(lib64_dir) if _lib_selected(os.path.basename(f)[:-4]))
        _libs_unchanged = 0
        _lp, _lpt = _progress("Installing libraries", len(_lib64_bz2_files))
        for bz2_file in _lib64_bz2_files:
            dest_file = os.path.join(dest_lib64_dir, os.path.basename(bz2_file[:-4]))
            bz2_src = _bz2.resolve(bz2_file)
            if bz2_src is None:
                warn(f"skipping {os.path.basename(dest_file)} -- bz2 or split parts missing at {bz2_file}")
                continue
            if _lp:
                _lp.update(_lpt, description=f"  {os.path.basename(dest_file)}")
            # Skip no-op installs: dest already byte-identical to bundled bz2.
            if _bz2_matches_dest(bz2_src, dest_file):
                _libs_unchanged += 1
                _vprint(f"  unchanged: {os.path.basename(dest_file)}")
                if _lp:
                    _lp.advance(_lpt)
                continue
            require_writable_parent(dest_file, "pre-built libraries")
            write_bz2_atomic(bz2_src, dest_file, 0o644)
            _vprint(f"  bzip2: {bz2_file} -> {dest_file}")
            if _lp:
                _lp.advance(_lpt)
        if _lp:
            _lp.stop()

    check_prebuilt_binary_dependencies(dest_bin_dir)
    _bin_count = len(_bin_bz2_files) if os.path.isdir(bin_dir) else 0
    _lib_count = len(_lib64_bz2_files) if os.path.isdir(lib64_dir) else 0
    _bins_unchanged_n = locals().get("_bins_unchanged", 0)
    _libs_unchanged_n = locals().get("_libs_unchanged", 0)
    _unchanged_note = ""
    if _bins_unchanged_n or _libs_unchanged_n:
        _unchanged_note = f" ({_bins_unchanged_n} binaries + {_libs_unchanged_n} libraries already current, skipped)"
    print(
        f"  Installed {_bin_count} binaries, {_lib_count} libraries from {src_dir} -> {home}/{_local_name(home)}/{_unchanged_note}"
    )
    blocked_all = blocked_deferred | set(blocked_failed.keys())
    if blocked_deferred:
        stage_pending_ops(blocked_deferred, bin_dir, dest_bin_dir, repo_dir)
    if blocked_all:
        record_result("pre-built binaries", "FAIL", "in use: {}".format(", ".join(sorted(blocked_all))))
    return blocked_deferred, blocked_failed


def install_portable_python(repo_dir, home, selected_tools=None):
    if selected_tools is not None and "portable-python" not in selected_tools:
        skipped("portable Python (portable-python not selected)", "")
        record_result("portable Python", "SKIP", "portable-python not in selected packages")
        return
    root_dir = os.path.join(repo_dir, "pre_built")
    if not os.path.isdir(root_dir):
        skipped("portable Python (no pre_built/ directory in repo)", "")
        record_result("portable Python", "SKIP", "no pre_built/ directory")
        return

    src_dir = select_prebuilt_platform_dir(root_dir)
    if not src_dir:
        skipped("portable Python (no matching platform)", "")
        record_result("portable Python", "SKIP", "no matching platform")
        return

    archives = sorted(f for f in os.listdir(src_dir) if f.startswith("portable-python-") and f.endswith(".tar.bz2"))
    if not archives:
        skipped(f"portable Python (no portable-python-*.tar.bz2 in {src_dir})", "")
        record_result("portable Python", "SKIP", "no archive found")
        return

    archive = os.path.join(src_dir, archives[-1])
    tmp_dir = tempfile.mkdtemp(prefix="loadout-python-install.", dir="/tmp")
    try:
        print(f"  extracting {archive}...")
        pv_extract_tar(archive, tmp_dir)

        extracted_dirs = [
            os.path.join(tmp_dir, d) for d in os.listdir(tmp_dir) if os.path.isdir(os.path.join(tmp_dir, d))
        ]
        if not extracted_dirs:
            warn("portable Python archive extracted no directories")
            record_result("portable Python", "FAIL", "empty archive")
            return

        installer = os.path.join(extracted_dirs[0], "install.sh")
        if not os.path.isfile(installer):
            warn("portable Python archive missing install.sh")
            record_result("portable Python", "FAIL", "no install.sh")
            return

        prefix = os.path.join(home, _local_name(home))
        cmd = ["/bin/sh", installer, "--prefix", prefix, "--force", "--no-test"]
        print("  running: {}".format(" ".join(cmd)))
        proc = subprocess.run(cmd, capture_output=True)
        out = proc.stdout.decode("utf-8", "replace")
        err = proc.stderr.decode("utf-8", "replace")
        for line in out.splitlines():
            print(f"  {line}")
        if proc.returncode != 0:
            for line in err.splitlines():
                eprint(f"  {line}")
            warn(f"portable Python install.sh exited with code {proc.returncode}")
            record_result("portable Python", "FAIL", f"install.sh exit {proc.returncode}")
            return
    finally:
        shutil.rmtree(tmp_dir)

    record_result("portable Python", "yes", "")
    print(f"  Installed portable Python -> {home}/{_local_name(home)}/")


def install_typelibs(repo_dir, home, selected_tools=None):
    """Copy *.typelib files from pre_built/<platform>/typelibs/ to ~/.local/lib/girepository-1.0/."""
    if selected_tools is not None and "gobject-typelibs" not in selected_tools:
        skipped("GObject typelibs (gobject-typelibs not selected)", "")
        record_result("GObject typelibs", "SKIP", "gobject-typelibs not in selected packages")
        return
    platform_dir = select_prebuilt_platform_dir(os.path.join(repo_dir, "pre_built"))
    if not platform_dir:
        skipped("GObject typelibs (no matching platform)", "")
        record_result("GObject typelibs", "SKIP", "no matching platform")
        return

    src_dir = os.path.join(platform_dir, "typelibs")
    if not os.path.isdir(src_dir):
        skipped("GObject typelibs (no typelibs/ in platform dir)", "")
        record_result("GObject typelibs", "SKIP", "no typelibs directory")
        return

    typelib_files = sorted(f for f in os.listdir(src_dir) if f.endswith(".typelib"))
    if not typelib_files:
        skipped(f"GObject typelibs (no *.typelib files in {src_dir})", "")
        record_result("GObject typelibs", "SKIP", "no typelib files")
        return

    dest_dir = os.path.join(home, _local_name(home), "lib", "girepository-1.0")
    ensure_dir(dest_dir, "GObject typelibs")

    _p, _pt = _progress("GObject typelibs", len(typelib_files))
    for name in typelib_files:
        src = os.path.join(src_dir, name)
        dest = os.path.join(dest_dir, name)
        if _p:
            _p.update(_pt, description=f"  {name}")
        require_writable_parent(dest, "GObject typelibs")
        shutil.copy2(src, dest)
        _vprint(f"  cp: {src} -> {dest}")
        if _p:
            _p.advance(_pt)
    if _p:
        _p.stop()

    record_result("GObject typelibs", "yes", f"{len(typelib_files)} files")
    print(f"  Installed {len(typelib_files)} typelibs -> {dest_dir}/")


def install_python_tools(repo_dir, home, selected_tools, registry):
    """Install Python tools via 'uv tool install' using bundled offline wheels."""
    platform_dir = select_prebuilt_platform_dir(os.path.join(repo_dir, "pre_built"))
    if not platform_dir:
        skipped("Python tools (no matching platform)", "")
        record_result("Python tools", "SKIP", "no matching platform")
        return

    # Compute the selected uv_tool set FIRST -- if nothing needs Python tools, this
    # is a clean SKIP, not a FAIL for a missing uv/python the caller never asked for.
    tools_to_install = []
    for name, info in registry.items():
        if "uv_tool" not in info:
            continue
        if selected_tools is not None and name not in selected_tools:
            continue
        tools_to_install.append((name, info["uv_tool"]))

    if not tools_to_install:
        skipped("Python tools (no selected tools require uv_tool)", "")
        record_result("Python tools", "SKIP", "no uv_tool entries selected")
        return

    wheels_dir = os.path.join(platform_dir, "wheels")
    if not os.path.isdir(wheels_dir):
        skipped("Python tools (no wheels/ in platform dir)", "")
        record_result("Python tools", "SKIP", "no wheels directory")
        return

    uv_bin = os.path.join(home, _local_name(home), "bin", "uv")
    python_bin = os.path.join(home, _local_name(home), "bin", "python3.14")
    if not os.path.isfile(uv_bin):
        warn(f"uv not found at {uv_bin} -- Python tools will NOT be installed")
        record_result("Python tools", "FAIL", "uv not installed")
        return
    if not os.path.isfile(python_bin):
        warn(f"python3.14 not found at {python_bin} -- Python tools will NOT be installed")
        record_result("Python tools", "FAIL", "python3.14 not installed")
        return

    # Rejoin any chunked wheels into a temp dir so uv can find whole files.
    effective_wheels_dir, _wheels_cleanup = _prepare_wheels_dir(wheels_dir)

    installed = []
    failed = []
    skipped_tools = []
    try:
        for tool_name, pkg_name in tools_to_install:
            # Check if a wheel for this package exists (whole or chunked) before install.
            import glob as _glob

            norm = pkg_name.lower().replace("-", "_").replace(".", "_")
            matches = (
                _glob.glob(os.path.join(wheels_dir, pkg_name + "-*.whl"))
                + _glob.glob(os.path.join(wheels_dir, norm + "-*.whl"))
                + _glob.glob(os.path.join(wheels_dir, pkg_name + "-*.whl.part-000"))
                + _glob.glob(os.path.join(wheels_dir, norm + "-*.whl.part-000"))
            )
            if not matches:
                warn(f"skipping {pkg_name} -- no wheel found in {wheels_dir}")
                skipped_tools.append(tool_name)
                continue
            cmd = [
                uv_bin,
                "tool",
                "install",
                pkg_name,
                "--python",
                python_bin,
                "--no-index",
                "--find-links",
                effective_wheels_dir,
                "--no-cache",
            ]
            # Force uv to install into the destination root (matters for --dest-dir runs;
            # uv tool uses HOME-derived XDG paths for the tools dir and launcher symlinks).
            _env = os.environ.copy()
            _env["HOME"] = home
            _env["XDG_DATA_HOME"] = os.path.join(home, _local_name(home), "share")
            _env["XDG_BIN_HOME"] = os.path.join(home, _local_name(home), "bin")
            print("  running: {}".format(" ".join(cmd)))
            proc = subprocess.run(cmd, capture_output=True, env=_env)
            out = proc.stdout.decode("utf-8", "replace")
            err = proc.stderr.decode("utf-8", "replace")
            for line in out.splitlines():
                print(f"  {line}")
            if proc.returncode != 0:
                for line in err.splitlines():
                    eprint(f"  {line}")
                warn(f"uv tool install {pkg_name} exited {proc.returncode}")
                failed.append(tool_name)
            else:
                installed.append(tool_name)
                print(f"  Installed Python tool: {tool_name} -> ~/.local/bin/")
    finally:
        _wheels_cleanup()

    if failed:
        record_result("Python tools", "FAIL", "failed: {}".format(", ".join(failed)))
    elif installed:
        record_result("Python tools", "yes", "installed: {}".format(", ".join(installed)))
    else:
        record_result("Python tools", "SKIP", "no wheels available for: {}".format(", ".join(skipped_tools)))


def check_prebuilt_binary_dependencies(dest_bin_dir):
    if not _LDD:
        warn("ldd is not available -- shared library dependency check skipped")
        return

    missing = False
    for name in sorted(os.listdir(dest_bin_dir)) if os.path.isdir(dest_bin_dir) else []:
        binary = os.path.join(dest_bin_dir, name)
        if not os.path.isfile(binary) or not os.access(binary, os.X_OK):
            continue
        proc = subprocess.run([_LDD, binary], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        out = proc.stdout.decode("utf-8", "replace")
        if "not found" in out:
            missing = True
            warn(f"missing shared libraries for {binary} -- this binary may not run")
            for line in out.splitlines():
                if "not found" in line:
                    # Print the whole ldd line: handles both the missing-file
                    # format ("libX.so => not found") and the version-mismatch
                    # format ("<binary>: /path/lib.so: version `Z' not found
                    # (required by ...)"), where split()[0] would wrongly print
                    # the binary path instead of the offending library.
                    eprint(f"    {line.strip()}")
    if not missing:
        print("  Shared library check OK")


def add_prebuilt_binary_retry_notice(blocked_deferred, blocked_failed):
    # Per-tool deferred messages -- shown even when the daemon was already running,
    # because the user needs to know what will happen and when.
    if "tmux" in blocked_deferred:
        FINAL_NOTICES.append(
            "tmux: a newer version is staged and will install automatically the next time "
            "all running tmux servers shut down."
        )
    other_deferred = blocked_deferred - {"tmux"}
    if other_deferred:
        FINAL_NOTICES.append(
            "Deferred (pending daemon): {}. Will install automatically when those processes exit.".format(
                ", ".join(sorted(other_deferred))
            )
        )
    for name, pid_str in sorted(blocked_failed.items()):
        FINAL_NOTICES.append(
            f"{name} was not installed: binary in use by process(es) {pid_str} "
            "-- kill or wait for them to exit, then re-run the installer."
        )


def print_final_notices():
    if not FINAL_NOTICES:
        return
    print("")
    print("Important final notices:")
    for notice in FINAL_NOTICES:
        print(f"  - {notice}")


def print_install_results():
    # Report what was actually done and any failures -- not what was skipped.
    if not INSTALL_RESULTS:
        return
    rows = []
    for thing, status, detail in INSTALL_RESULTS:
        if status == "FAIL":
            rows.append((thing, "FAILED", detail or ""))
        elif status in ("OK", "yes"):
            if thing in _SILENT_AREAS:
                continue
            rows.append((thing, "done", detail or ""))
        # SKIP (and anything else) is omitted -- a not-selected phase is not news.
    n_fail = sum(1 for r in rows if r[1] == "FAILED")

    def _final(line, error):
        if _RICH:
            assert _console is not None
            _console.print(f"[bold {'red' if error else 'green'}]{line}[/bold {'red' if error else 'green'}]")
        else:
            print(line)

    if not rows:
        _final("Nothing to do.", error=False)
        return

    if _RICH:
        t = _RichTable(title="Summary", show_lines=False, highlight=False)
        t.add_column("Area", style="cyan", no_wrap=True)
        t.add_column("Result", justify="center")
        t.add_column("Detail", style="dim")
        _status_style = {"done": "green", "FAILED": "bold red"}
        for thing, result, detail in rows:
            style = _status_style.get(result, "")
            t.add_row(thing, f"[{style}]{result}[/{style}]", detail)
        assert _console is not None
        _console.print()
        _console.print(t)
    else:
        widths = [
            max(len("Area"), *(len(row[0]) for row in rows)),
            max(len("Result"), *(len(row[1]) for row in rows)),
            max(len("Detail"), *(len(row[2]) for row in rows)),
        ]
        print("")
        print("Summary:")
        print("  {:{}}  {:{}}  {:{}}".format("Area", widths[0], "Result", widths[1], "Detail", widths[2]))
        print("  {}  {}  {}".format("-" * widths[0], "-" * widths[1], "-" * widths[2]))
        for thing, result, detail in rows:
            print("  {:{}}  {:{}}  {:{}}".format(thing, widths[0], result, widths[1], detail, widths[2]))

    if n_fail:
        _final(f"Completed with {n_fail} problem(s) -- see above.", error=True)
    else:
        _final("Complete.", error=False)


def print_install_blockers():
    if not INSTALL_BLOCKERS:
        return
    rows = sorted(INSTALL_BLOCKERS, key=lambda r: (r["area"], r["path"], r["pid"]))

    if _RICH:
        t = _RichTable(title="Processes Blocking Installation", show_lines=False, highlight=False)
        t.add_column("Area", style="cyan", no_wrap=True)
        t.add_column("Artifact", no_wrap=True)
        t.add_column("Reason", no_wrap=True)
        t.add_column("Owner", no_wrap=True)
        t.add_column("PID", justify="right", no_wrap=True)
        t.add_column("Path", style="dim")
        t.add_column("Command", style="dim")
        for row in rows:
            t.add_row(
                row["area"],
                row["artifact"],
                row["reason"],
                row["owner"],
                row["pid"],
                row["path"],
                row["command"],
            )
        assert _console is not None
        _console.print()
        _console.print(t)
        return

    print("")
    print("Processes Blocking Installation")
    headers = ("Area", "Artifact", "Reason", "Owner", "PID", "Path", "Command")
    data = [(r["area"], r["artifact"], r["reason"], r["owner"], r["pid"], r["path"], r["command"]) for r in rows]
    widths = [max(len(headers[i]), *(len(row[i]) for row in data)) for i in range(len(headers))]
    fmt = "  ".join("{:<" + str(w) + "}" for w in widths)
    print(fmt.format(*headers))
    print(fmt.format(*("-" * w for w in widths)))
    for row in data:
        print(fmt.format(*row))


def font_member(name):
    lower = name.lower()
    return lower.endswith((".ttf", ".otf", ".pcf", ".bdf", ".pcf.gz", ".bdf.gz"))


def font_zip_members(zip_path):
    with zipfile.ZipFile(zip_path, "r") as zf:
        return [member for member in zf.namelist() if font_member(member) and os.path.basename(member)]


def extract_font_zip(zip_path, user_fonts_dir, members=None, progress=None, task=None, max_name=0):
    if progress is None:
        print(f"  Extracting: {zip_path} -> {user_fonts_dir}/")
    members = members if members is not None else font_zip_members(zip_path)
    with zipfile.ZipFile(zip_path, "r") as zf:
        for member in members:
            dest = os.path.join(user_fonts_dir, os.path.basename(member))
            if progress is not None:
                name = os.path.basename(member)
                progress.update(task, description=f"  {name.ljust(max_name)}")
            require_writable_parent(dest, "fonts")
            with zf.open(member) as src, open(dest, "wb") as out:
                shutil.copyfileobj(src, out)
            if progress is not None:
                progress.advance(task)


def _logical_zip_name(archive):
    """fonts/Hack.zip -> 'Hack.zip'; fonts/IosevkaTerm.zip.part-* -> 'IosevkaTerm.zip'."""
    b = os.path.basename(archive or "")
    i = b.find(".zip")
    return b[: i + 4] if i != -1 else b


def install_fonts(repo_dir, home, selected_tools=None, registry=None, no_backup=False):
    # Which specific font archives to install. selected_tools=None -> install all
    # (non-selective). When a selection is given, map each selected font-* package
    # to its archive basename and install ONLY those -- otherwise --only font-hack
    # would still install every font.
    selected_zip_names = None
    if selected_tools is not None:
        font_pkgs = [n for n in selected_tools if n.startswith("font-")]
        if not font_pkgs:
            skipped("fonts (no font-* packages selected)", "")
            record_result("fonts", "SKIP", "no font-* packages in selected set")
            return
        selected_zip_names = set()
        for n in font_pkgs:
            entry = (registry or {}).get(n, {})
            archive = entry.get("archive", "")
            if archive:
                selected_zip_names.add(_logical_zip_name(archive))
    vendor_fonts_dir = os.path.join(repo_dir, "fonts")
    user_fonts_dir = os.path.join(home, _local_name(home), "share", "fonts")

    if not os.path.isdir(vendor_fonts_dir):
        print("Installing fonts...")
        skipped("fonts (no fonts/ directory in repo)", "Nerd Fonts will NOT be installed to ~/.local/share/fonts")
        record_result("fonts", "SKIP", "no fonts/ directory")
        return

    if os.path.islink(user_fonts_dir):
        require_writable_parent(user_fonts_dir, "fonts")
        print(f"  Removing symlink: {user_fonts_dir}")
        os.unlink(user_fonts_dir)
    elif os.path.isdir(user_fonts_dir):
        require_writable_parent(user_fonts_dir, "fonts")
        require_writable_dir(user_fonts_dir, "fonts")
        if no_backup:
            print(f"  Reusing existing fonts dir (--no-backup): {user_fonts_dir}")
        else:
            backup_path = user_fonts_dir + ".bak"
            counter = 1
            while os.path.exists(backup_path):
                backup_path = f"{user_fonts_dir}.bak.{counter}"
                counter += 1
            print(f"  Backing up existing fonts dir: {user_fonts_dir} -> {backup_path}")
            shutil.move(user_fonts_dir, backup_path)
    ensure_dir(user_fonts_dir, "fonts")

    # Handles whole zips and chunked zips (.zip.part-000 sentinel, rejoined
    # transparently by _bz2.resolve). Filter to the selected font archives when
    # a selection was given.
    seen_zips = set()
    zip_jobs = []
    for name in sorted(os.listdir(vendor_fonts_dir)):
        if name.endswith(".zip"):
            zip_logical = os.path.join(vendor_fonts_dir, name)
        elif name.endswith(".zip.part-000"):
            zip_logical = os.path.join(vendor_fonts_dir, name[: -len(".part-000")])
        else:
            continue
        if zip_logical in seen_zips:
            continue
        seen_zips.add(zip_logical)
        if selected_zip_names is not None and os.path.basename(zip_logical) not in selected_zip_names:
            continue
        # _bz2.resolve() transparently rejoins chunks to a temp file if needed.
        zip_path = _bz2.resolve(zip_logical)
        if zip_path is None:
            continue
        if zip_logical != zip_path:
            print(f"  Rejoining: {zip_logical}.part-* -> (temp)")
        members = font_zip_members(zip_path)
        if members:
            zip_jobs.append((zip_path, members))

    total_font_files = sum(len(members) for _, members in zip_jobs)
    max_font_name = max((len(os.path.basename(member)) for _, members in zip_jobs for member in members), default=0)
    _p, _pt = _progress("Installing fonts", total_font_files) if total_font_files else (None, None)
    try:
        for zip_path, members in zip_jobs:
            extract_font_zip(zip_path, user_fonts_dir, members, _p, _pt, max_font_name)
    finally:
        if _p is not None:
            _p.stop()

    for name, path in (("mkfontscale", "/usr/bin/mkfontscale"), ("mkfontdir", "/usr/bin/mkfontdir")):
        tool = _find_tool(path)
        if tool:
            proc = subprocess.run([tool, user_fonts_dir], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            if proc.returncode != 0:
                warn(f"{name} failed for {user_fonts_dir} -- font metrics may be incomplete")

    fc_cache = _find_tool("/usr/bin/fc-cache")
    if fc_cache:
        proc = subprocess.run([fc_cache, "-f", user_fonts_dir], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if proc.returncode != 0:
            warn(f"fc-cache failed for {user_fonts_dir} -- fontconfig cache may be stale")
    else:
        warn(
            "fc-cache is not available -- fontconfig cache was NOT refreshed; fonts may not appear until you run fc-cache manually"
        )

    if is_wsl():
        print("  WSL note: Linux GUI apps use these fonts through fontconfig.")
        print("  WSL note: Windows Terminal needs fonts installed on the Windows side.")


def install_tldr_cache(repo_dir, home, selected_tools=None):
    if selected_tools is not None and "tldr-data" not in selected_tools:
        skipped("tldr cache (tldr-data not selected)", "")
        record_result("tldr cache", "SKIP", "tldr-data not in selected packages")
        return
    archive = None
    for candidate in ("tldr-pages.tar.bz2", "tldr-pages.tar.gz"):
        path = os.path.join(repo_dir, "tldr", candidate)
        if os.path.exists(path):
            archive = path
            break
    if not archive:
        skipped(
            "tldr/tldr-pages.tar.bz2 or tldr/tldr-pages.tar.gz not found in repo",
            "run ./update tldr-data on a connected machine to bundle the pages",
        )
        record_result("tldr cache", "SKIP", "no bundled cache archive")
        return

    cache_dir = _resolve_install_to("~/.local/share/tealdeer/cache", home)
    dest_dir = os.path.join(cache_dir, "tldr-pages")
    ensure_dir(cache_dir, "tldr cache")
    if os.path.lexists(dest_dir):
        require_writable_parent(dest_dir, "tldr cache")
        if os.path.isdir(dest_dir) and not os.path.islink(dest_dir):
            require_writable_dir(dest_dir, "tldr cache")
            shutil.rmtree(dest_dir)
        else:
            os.unlink(dest_dir)

    pv_extract_tar(archive, cache_dir)
    print(f"  tldr page cache installed to {dest_dir}")


def install_crate_store(repo_dir, home, selected_tools=None):
    """Extract the bundled offline Cargo local-registry (rust-crate-store).

    Archive lives at envs/rust/crate-store.tar.bz2 (arch-independent crate
    sources) and is auto-chunked into .part-NNN by build-crate-store.sh, so it
    is resolved through _bz2.resolve like the runtime archives. The store
    (index/ + *.crate) is consumed offline via ~/.cargo/config.toml written by
    the env-cargo package.
    """
    if selected_tools is not None and "rust-crate-store" not in selected_tools:
        skipped("Rust crate store (rust-crate-store not selected)", "")
        record_result("Rust crate store", "SKIP", "rust-crate-store not in selected packages")
        return
    archive = _bz2.resolve(os.path.join(repo_dir, "envs", "rust", "crate-store.tar.bz2"))
    if archive is None:
        skipped(
            "envs/rust/crate-store.tar.bz2 not found in repo",
            "run pre_built/build_scripts/build-crate-store.sh on a connected machine",
        )
        record_result("Rust crate store", "SKIP", "no bundled crate store archive")
        return

    store_dir = _resolve_install_to("~/.local/share/cargo/registry-store", home)
    ensure_dir(os.path.dirname(store_dir), "Rust crate store")
    if os.path.lexists(store_dir):
        require_writable_parent(store_dir, "Rust crate store")
        if os.path.isdir(store_dir) and not os.path.islink(store_dir):
            require_writable_dir(store_dir, "Rust crate store")
            shutil.rmtree(store_dir)
        else:
            os.unlink(store_dir)
    ensure_dir(store_dir, "Rust crate store")

    pv_extract_tar(archive, store_dir)
    ncrate = len(glob_paths_glob(os.path.join(store_dir, "*.crate")))
    record_result("Rust crate store", "yes", f"{archive} -> {store_dir}")
    print(f"  Rust crate store installed to {store_dir} ({ncrate} crates)")


def _validate_tar_members(members, dest_real):
    """Shared safety check for tar extraction.

    Python <3.12 lacks tarfile's `filter='data'` parameter, so we have to
    enforce these rules ourselves. Even on 3.12+ we run the same check
    pre-extract to fail fast with a clear error before any side-effects.

    Rules:
      1. member.name must resolve inside dest_real (no absolute paths,
         no `..` escapes).
      2. symlinks and hardlinks must have linknames whose resolved target
         also stays inside dest_real (otherwise the planted link itself
         is fine but follow-on writes can escape).
      3. Reject device, FIFO, and char-special members on the legacy
         (no-filter) extraction path -- we never legitimately ship these.
    """
    for member in members:
        # Use normpath (not realpath) so pre-existing symlinks in dest don't cause false
        # positives -- e.g. ~/.terminfo -> /usr/share/terminfo would fail realpath but the
        # member name ./.terminfo is safe. normpath still catches absolute paths and .. escapes.
        target_norm = os.path.normpath(os.path.join(dest_real, member.name))
        if not (target_norm == dest_real or target_norm.startswith(dest_real + os.sep)):
            raise RuntimeError(f"unsafe tar member path: {member.name}")
        if member.issym() or member.islnk():
            linkname = member.linkname or ""
            # Symlinks resolve relative to the symlink's own directory; hardlinks
            # resolve relative to the archive root (which is dest_real for us).
            if member.issym():
                base = os.path.dirname(os.path.join(dest_real, member.name))
            else:
                base = dest_real
            link_real = os.path.realpath(os.path.join(base, linkname))
            if not (link_real == dest_real or link_real.startswith(dest_real + os.sep)):
                raise RuntimeError(f"unsafe tar link target: {member.name} -> {linkname}")


def _remove_symlinks_blocking_dirs(members, dest_dir):
    """Before extracting, unlink any symlinks in dest that would block directory members.

    Python 3.12+ tarfile filter='data' refuses to follow existing symlinks, but a
    symlink like ~/.terminfo -> /usr/share/terminfo still has to be removed first
    so a directory member by that name can be created in its place.

    Behaviour controlled by --install-follows-symlinks:
      no (default) -- always unlink, replace with real dir.
      yes           -- never unlink, follow all symlinks.
      auto          -- follow only if the symlink target is writable by the
                      current user; otherwise unlink and replace.
    """
    if _FOLLOW_SYMLINKS == "yes":
        return
    for member in members:
        if not member.isdir():
            continue
        dest_path = os.path.join(dest_dir, member.name)
        dest_norm = os.path.normpath(dest_path)
        if os.path.islink(dest_norm):
            if _FOLLOW_SYMLINKS == "auto" and os.access(dest_norm, os.W_OK):
                continue  # writable target -- follow
            os.unlink(dest_norm)


def safe_extract_tar(tf, dest_dir):
    require_writable_dir(dest_dir, "archive extraction")
    dest_real = os.path.realpath(dest_dir)
    members = tf.getmembers()
    _validate_tar_members(members, dest_real)
    _remove_symlinks_blocking_dirs(members, dest_dir)
    tf.extractall(dest_dir, filter="data")


def pv_extract_tar(archive_path, dest_dir):
    """Extract tar archive with Rich member-count progress bar; falls back to plain extractall."""
    require_writable_dir(dest_dir, "archive extraction")
    dest_real = os.path.realpath(dest_dir)

    with tarfile.open(archive_path, "r:*") as tf:
        members = tf.getmembers()
        _validate_tar_members(members, dest_real)
        _remove_symlinks_blocking_dirs(members, dest_dir)

        if not _RICH:
            safe_extract_tar(tf, dest_dir)
            return

        p, task = _progress("  " + os.path.basename(archive_path), len(members))
        assert p is not None
        # try/finally: a raised tf.extract must still stop the Progress, else its
        # cursor-hide (ESC[?25l) is never restored and the terminal cursor vanishes.
        try:
            for member in members:
                tf.extract(member, dest_dir, filter="data")
                p.advance(task)
            p.advance(task)
        finally:
            p.stop()


def install_runtime_archives(repo_dir, home, selected_tools, registry):
    """Generic runtime archive installer driven by packages.json metadata.

    Handles packages where 'sentinel' + 'install_to' are set, following the
    standard pattern: find runtime/<archive_name>.tar.bz2, extract to
    install_to, verify sentinel path.

    Optional fields per package entry:
      archive_name: filename override (default: "<pkg_name>.tar.bz2")
      remove_before_extract: str or list of paths (relative to install_to) to
                             remove before extracting (avoids stale files)
      chmod_sentinel: bool -- chmod 755 on sentinel file after extraction
      missing_hint: str -- shown when archive not found

    Packages with non-trivial post-extract logic stay in dedicated functions:
      vim (rename step), meld (multi-remove+chmod), nvim-qt (shim copy).
    """
    platform_dir = select_prebuilt_platform_dir(os.path.join(repo_dir, "pre_built"))
    if not platform_dir:
        warn("No pre-built platform directory found; skipping runtime archives")
        return

    for pkg_name, entry in registry.items():
        if pkg_name.startswith("@"):
            continue
        sentinel_rel = entry.get("sentinel", "")
        install_to_raw = entry.get("install_to", "")
        if not sentinel_rel or not install_to_raw:
            continue

        if selected_tools is not None and pkg_name not in selected_tools:
            record_result(f"{pkg_name} runtime", "SKIP", "not in selected tools")
            continue

        archive_name = entry.get("archive_name", f"{pkg_name}.tar.bz2")
        archive = _bz2.resolve(os.path.join(platform_dir, "runtime", archive_name))
        if archive is None:
            hint = entry.get("missing_hint", "")
            skipped(
                f"{pkg_name} runtime (no {archive_name} in pre_built/<platform>/runtime/)",
                hint,
            )
            record_result(f"{pkg_name} runtime", "SKIP", f"no bundled {archive_name}")
            continue

        install_to = _resolve_install_to(install_to_raw, home)
        ensure_dir(install_to, f"{pkg_name} runtime")

        rbe = entry.get("remove_before_extract")
        if rbe:
            if isinstance(rbe, str):
                rbe = [rbe]
            for rel in rbe:
                remove_if_exists(os.path.join(install_to, rel))

        pv_extract_tar(archive, install_to)

        sentinel = os.path.join(install_to, sentinel_rel)
        sentinel_ok = os.path.isfile(sentinel) or os.path.isdir(sentinel)

        if entry.get("chmod_sentinel") and os.path.isfile(sentinel):
            os.chmod(sentinel, 0o755)

        if sentinel_ok:
            record_result(f"{pkg_name} runtime", "yes", f"{archive} -> {install_to}")
            print(f"  Installed: {archive} -> {install_to}/")
        else:
            warn(f"{pkg_name} runtime: {archive_name} extracted but {sentinel} not found")
            record_result(f"{pkg_name} runtime", "FAIL", f"sentinel not found at {sentinel}")


def install_vim_runtime(repo_dir, home, selected_tools=None):
    if selected_tools is not None and "vim" not in selected_tools and "gvim" not in selected_tools:
        skipped("Vim runtime (vim/gvim not selected)", "")
        record_result("Vim runtime", "SKIP", "vim/gvim not in selected tools")
        return
    archive = None
    platform_dir = select_prebuilt_platform_dir(os.path.join(repo_dir, "pre_built"))
    if platform_dir:
        archive = _bz2.resolve(os.path.join(platform_dir, "runtime", "vim92.tar.bz2"))
    if archive is None:
        archive = _bz2.resolve(os.path.join(repo_dir, "envs", "vim", "runtime.tar.bz2"))
    if archive is None:
        skipped(
            "Vim runtime (no vim92.tar.bz2 in pre_built/<platform>/runtime/ or vim/)",
            "vim will NOT have the vendored runtime at ~/.local/share/vim/vim92",
        )
        record_result("Vim runtime", "SKIP", "no bundled runtime archive")
        return

    vim_share_dir = os.path.join(home, _local_name(home), "share", "vim")
    runtime_dir = os.path.join(vim_share_dir, "runtime")
    vim92_dir = os.path.join(vim_share_dir, "vim92")
    ensure_dir(vim_share_dir, "Vim runtime")
    remove_if_exists(runtime_dir)
    remove_if_exists(vim92_dir)

    pv_extract_tar(archive, vim_share_dir)

    if os.path.isdir(runtime_dir):
        os.rename(runtime_dir, vim92_dir)

    sentinel = os.path.join(vim92_dir, "filetype.vim")
    if os.path.isfile(sentinel):
        print(f"  Installed: {archive} -> {vim92_dir}/")
    else:
        warn(f"Vim runtime archive did not install {sentinel} as expected")


def install_meld_runtime(repo_dir, home, selected_tools):
    if selected_tools is not None and "meld" not in selected_tools:
        skipped("Meld runtime (meld not selected)", "")
        record_result("Meld runtime", "SKIP", "meld not in selected tools")
        return
    archive = None
    platform_dir = select_prebuilt_platform_dir(os.path.join(repo_dir, "pre_built"))
    if platform_dir:
        archive = _bz2.resolve(os.path.join(platform_dir, "runtime", "meld.tar.bz2"))
    if archive is None:
        skipped("Meld runtime (no meld.tar.bz2 in pre_built/<platform>/runtime/)", "meld will NOT be installed")
        record_result("Meld runtime", "SKIP", "no bundled runtime archive")
        return

    local_dir = os.path.join(home, _local_name(home))
    ensure_dir(local_dir, "Meld runtime")

    # Remove stale meld-owned paths before re-extracting.
    for stale in (
        os.path.join(local_dir, "lib", "python3.6", "site-packages", "meld"),
        os.path.join(local_dir, "lib", "python3.6", "site-packages", "meld3"),
        os.path.join(local_dir, "lib", "python3.6", "site-packages", "gi"),
        os.path.join(local_dir, "lib", "python3.6", "site-packages", "cairo"),
        os.path.join(local_dir, "share", "meld"),
        os.path.join(local_dir, "bin", "meld"),
    ):
        remove_if_exists(stale)

    pv_extract_tar(archive, local_dir)

    # Ensure launcher is executable (may have been extracted without +x).
    meld_bin = os.path.join(local_dir, "bin", "meld")
    if os.path.isfile(meld_bin):
        os.chmod(meld_bin, 0o755)

    sentinel = os.path.join(local_dir, "lib", "python3.6", "site-packages", "meld", "conf.py")
    if os.path.isfile(sentinel):
        record_result("Meld runtime", "yes", f"meld 3.20.4 -> {local_dir}/")
        print(f"  Installed: {archive} -> {local_dir}/")
    else:
        warn(f"Meld runtime archive did not install {local_dir}/lib/python3.6/site-packages/meld as expected")
        record_result("Meld runtime", "FAIL", "archive extracted but meld/conf.py not found")


def install_mate_terminal_runtime(repo_dir, home, selected_tools):
    """Install the mate-terminal shanghai bundle.

    Bundle (from `pre_built/<platform>/runtime/mate-terminal.tar.bz2`) contains:
      bin/mate-terminal            POSIX-sh launcher (sets XDG_DATA_DIRS +
                                    GSETTINGS_BACKEND=keyfile, then execs the ELF)
      bin/mate-terminal.bin        the actual ELF, RPATH=$ORIGIN/../lib64
      share/glib-2.0/schemas/      mate-terminal + org.mate.interface schema XML

    After extraction we run `glib-compile-schemas` against the bundled schema
    dir so GSettings can find the compiled file at runtime. The keyfile
    backend means mate-terminal does not need dconf-service or a session bus
    to launch -- preferences persist to `~/.config/glib-2.0/settings/keyfile`.

    The two non-gui_libs NEEDED libs (libvte-2.91.so.0, libdconf.so.1) ship
    separately as `lib64/*.bz2` payloads listed in the package entry.
    """
    if selected_tools is not None and "mate-terminal" not in selected_tools:
        skipped("mate-terminal runtime (mate-terminal not selected)", "")
        record_result("mate-terminal runtime", "SKIP", "mate-terminal not in selected tools")
        return
    archive = None
    platform_dir = select_prebuilt_platform_dir(os.path.join(repo_dir, "pre_built"))
    if platform_dir:
        archive = _bz2.resolve(os.path.join(platform_dir, "runtime", "mate-terminal.tar.bz2"))
    if archive is None:
        skipped(
            "mate-terminal runtime (no mate-terminal.tar.bz2 in pre_built/<platform>/runtime/)",
            "mate-terminal will NOT be installed",
        )
        record_result("mate-terminal runtime", "SKIP", "no bundled runtime archive")
        return

    local_dir = os.path.join(home, _local_name(home))
    ensure_dir(local_dir, "mate-terminal runtime")

    # Remove stale bundle paths before re-extracting.
    for stale in (
        os.path.join(local_dir, "bin", "mate-terminal"),
        os.path.join(local_dir, "bin", "mate-terminal.bin"),
        os.path.join(local_dir, "share", "glib-2.0", "schemas", "org.mate.interface.gschema.xml"),
        os.path.join(local_dir, "share", "glib-2.0", "schemas", "org.mate.terminal.gschema.xml"),
    ):
        remove_if_exists(stale)

    pv_extract_tar(archive, local_dir)

    # Ensure launcher is executable.
    mt_launcher = os.path.join(local_dir, "bin", "mate-terminal")
    if os.path.isfile(mt_launcher):
        os.chmod(mt_launcher, 0o755)

    # Compile gsettings schemas. glib-compile-schemas ships with glib2 on every
    # supported base system; without the compiled file mate-terminal aborts on
    # startup with "Settings schema 'org.mate.terminal.window' is not installed"
    # or "Settings schema 'org.mate.interface' is not installed".
    schema_dir = os.path.join(local_dir, "share", "glib-2.0", "schemas")
    glib_compile = _find_tool("/usr/bin/glib-compile-schemas")
    if glib_compile and os.path.isdir(schema_dir):
        try:
            run([glib_compile, schema_dir])
        except subprocess.CalledProcessError as exc:
            warn(f"glib-compile-schemas failed for {schema_dir}: {exc}")

    sentinel = os.path.join(local_dir, "bin", "mate-terminal.bin")
    if os.path.isfile(sentinel):
        record_result("mate-terminal runtime", "yes", f"mate-terminal 1.26.1 -> {local_dir}/")
        print(f"  Installed: {archive} -> {local_dir}/")
    else:
        warn(f"mate-terminal runtime archive did not install {local_dir}/bin/mate-terminal.bin as expected")
        record_result("mate-terminal runtime", "FAIL", "archive extracted but mate-terminal.bin not found")


def install_firefox_runtime(repo_dir, home, selected_tools):
    """Install the Firefox shanghai bundle.

    Bundle (from `pre_built/<platform>/runtime/firefox.tar.bz2`, transparently
    rejoined from `.part-NNN` chunks) contains:
      bin/firefox                     thin POSIX-sh wrapper exec'ing firefox-bin
      lib/firefox/                    the EL8 /usr/lib64/firefox/ tree
                                       (libxul.so + libmoz*.so, RPATH=$ORIGIN)
      share/applications/firefox.desktop   optional XDG menu entry

    firefox-bin self-resolves all its bundled .so deps via $ORIGIN; only
    system libs declared as gui_libs (GTK3/cairo/pango/X11/Wayland) plus the
    EL8 base (NSS/NSPR, alsa-lib, freetype, fontconfig) are needed at runtime.
    No glib-compile-schemas or RPATH fix-up needed at install time.
    """
    if selected_tools is not None and "firefox" not in selected_tools:
        skipped("Firefox runtime (firefox not selected)", "")
        record_result("Firefox runtime", "SKIP", "firefox not in selected tools")
        return
    archive = None
    platform_dir = select_prebuilt_platform_dir(os.path.join(repo_dir, "pre_built"))
    if platform_dir:
        archive = _bz2.resolve(os.path.join(platform_dir, "runtime", "firefox.tar.bz2"))
    if archive is None:
        skipped(
            "Firefox runtime (no firefox.tar.bz2 in pre_built/<platform>/runtime/)",
            "firefox will NOT be installed",
        )
        record_result("Firefox runtime", "SKIP", "no bundled runtime archive")
        return

    local_dir = os.path.join(home, _local_name(home))
    ensure_dir(local_dir, "Firefox runtime")

    # Remove stale bundle paths before re-extracting.
    for stale in (
        os.path.join(local_dir, "bin", "firefox"),
        os.path.join(local_dir, "lib", "firefox"),
        os.path.join(local_dir, "share", "applications", "firefox.desktop"),
    ):
        remove_if_exists(stale)

    pv_extract_tar(archive, local_dir)

    # Ensure launcher is executable.
    ff_launcher = os.path.join(local_dir, "bin", "firefox")
    if os.path.isfile(ff_launcher):
        os.chmod(ff_launcher, 0o755)

    sentinel = os.path.join(local_dir, "lib", "firefox", "firefox-bin")
    if os.path.isfile(sentinel):
        record_result("Firefox runtime", "yes", f"firefox -> {local_dir}/")
        print(f"  Installed: {archive} -> {local_dir}/")
    else:
        warn(f"Firefox runtime archive did not install {local_dir}/lib/firefox/firefox-bin as expected")
        record_result("Firefox runtime", "FAIL", "archive extracted but firefox-bin not found")


def install_nvim_qt_runtime(repo_dir, home, selected_tools):
    if selected_tools is not None and "nvim-qt" not in selected_tools:
        skipped("nvim-qt runtime (nvim-qt not selected)", "")
        record_result("nvim-qt runtime", "SKIP", "nvim-qt not in selected tools")
        return
    archive = None
    platform_dir = select_prebuilt_platform_dir(os.path.join(repo_dir, "pre_built"))
    if platform_dir:
        archive = _bz2.resolve(os.path.join(platform_dir, "runtime", "nvim-qt-runtime.tar.bz2"))
    if archive is None:
        skipped(
            "nvim-qt runtime (no nvim-qt-runtime.tar.bz2 in pre_built/<platform>/runtime/)",
            "nvim-qt :Gui* commands (GuiFont, GuiTabline, etc.) will NOT be available",
        )
        record_result("nvim-qt runtime", "SKIP", "no bundled runtime archive")
        return

    # Extract archive to ~/.local/share/nvim-qt/ (keeps runtime/ available for
    # NVIM_QT_RUNTIME_PATH), then also copy the shim plugin directly into
    # ~/.local/share/nvim/site/plugin/ -- that dir is on nvim's default runtimepath
    # unconditionally, which is more reliable than the NVIM_QT_RUNTIME_PATH env var.
    nvim_qt_share = os.path.join(home, _local_name(home), "share", "nvim-qt")
    ensure_dir(nvim_qt_share, "nvim-qt runtime")
    runtime_dir = os.path.join(nvim_qt_share, "runtime")
    remove_if_exists(runtime_dir)

    pv_extract_tar(archive, nvim_qt_share)

    shim_src = os.path.join(runtime_dir, "plugin", "nvim_gui_shim.vim")
    if not os.path.isfile(shim_src):
        warn(f"nvim-qt runtime archive did not install {shim_src} as expected")
        record_result("nvim-qt runtime", "FAIL", "archive extracted but nvim_gui_shim.vim not found")
        return

    # Install shim into nvim site/plugin so it loads unconditionally in all nvim sessions.
    site_plugin_dir = os.path.join(home, _local_name(home), "share", "nvim", "site", "plugin")
    ensure_dir(site_plugin_dir, "nvim-qt runtime (site plugin)")
    shim_dest = os.path.join(site_plugin_dir, "nvim_gui_shim.vim")
    shutil.copy2(shim_src, shim_dest)
    record_result("nvim-qt runtime", "yes", f"shim -> {shim_dest}")
    print(f"  Installed: {shim_src} -> {shim_dest}")


def install_treesitter_parsers(repo_dir, home, selected_tools=None):
    if selected_tools is not None and "treesitter-parsers" not in selected_tools:
        skipped("Tree-sitter parsers (treesitter-parsers not selected)", "")
        record_result("Tree-sitter parsers", "SKIP", "treesitter-parsers not in selected packages")
        return
    platform = treesitter_platform_id()
    src_dir = os.path.join(repo_dir, "treesitter", "prebuilt", platform)
    dest_dir = os.path.join(home, _local_name(home), "share", "nvim", "tree-sitter-parsers")

    if not os.path.isdir(os.path.join(src_dir, "parser")):
        skipped(
            f"Tree-sitter parsers (no prebuilt parsers for {platform})",
            "Neovim Tree-sitter highlighting will NOT work offline",
        )
        record_result("Tree-sitter parsers", "SKIP", f"no prebuilt parsers for {platform}")
        return

    for subdir in ("queries", "build-info", "parser-info", "registry"):
        src = os.path.join(src_dir, subdir)
        if os.path.isdir(src):
            dest = os.path.join(dest_dir, subdir)
            ensure_dir(dest, "Tree-sitter parsers")
            sync_dir(src, dest)

    parser_src = os.path.join(src_dir, "parser")
    parser_dest = os.path.join(dest_dir, "parser")
    ensure_dir(parser_dest, "Tree-sitter parsers")
    parser_files = [
        n
        for n in sorted(os.listdir(parser_src))
        if os.path.isfile(os.path.join(parser_src, n)) and (n.endswith(".so.bz2") or n.endswith(".so"))
    ]
    _max_parser_name = max((len(n.replace(".so.bz2", "").replace(".so", "")) for n in parser_files), default=0)
    _p, _pt = _progress("Tree-sitter parsers", len(parser_files))
    for name in parser_files:
        src = os.path.join(parser_src, name)
        if _p:
            _stripped = name.replace(".so.bz2", "").replace(".so", "")
            _p.update(_pt, description=f"  {_stripped.ljust(_max_parser_name)}")
        if name.endswith(".so.bz2"):
            dest = os.path.join(parser_dest, name[:-4])
            require_writable_parent(dest, "Tree-sitter parsers")
            with bz2.open(src, "rb") as src_fh, open(dest, "wb") as dest_fh:
                shutil.copyfileobj(src_fh, dest_fh)
            os.chmod(dest, 0o644)
            _vprint(f"  bzip2: {src} -> {dest}")
        elif name.endswith(".so"):
            dest = os.path.join(parser_dest, name)
            require_writable_parent(dest, "Tree-sitter parsers")
            shutil.copy2(src, dest)
            os.chmod(dest, 0o644)
            _vprint(f"  cp: {src} -> {dest}")
        if _p:
            _p.advance(_pt)
    if _p:
        _p.stop()
    print(f"  Installed {len(parser_files)} parsers -> {parser_dest}/")


def install_nvim_treesitter_vendor(repo_dir, home, selected_tools=None):
    if selected_tools is not None and "treesitter-parsers" not in selected_tools:
        skipped("vendored nvim-treesitter (treesitter-parsers not selected)", "")
        record_result("nvim-treesitter vendor", "SKIP", "treesitter-parsers not in selected packages")
        return
    src_root = os.path.join(repo_dir, "treesitter", "vendor")
    dest_root = os.path.join(home, _local_name(home), "share", "nvim", "loadout", "vendor")
    if not (
        os.path.isdir(os.path.join(src_root, "nvim-treesitter"))
        and os.path.isdir(os.path.join(src_root, "treesitter-parser-registry"))
    ):
        skipped(
            "vendored nvim-treesitter (missing from treesitter/vendor/)",
            "Neovim Tree-sitter plugin will NOT be available offline",
        )
        record_result("nvim-treesitter vendor", "SKIP", "missing treesitter/vendor/")
        return

    ensure_dir(dest_root, "nvim-treesitter vendor")
    sync_dir(
        os.path.join(src_root, "nvim-treesitter"),
        os.path.join(dest_root, "nvim-treesitter"),
        delete=True,
        excludes=(".git",),
    )
    sync_dir(
        os.path.join(src_root, "treesitter-parser-registry"),
        os.path.join(dest_root, "treesitter-parser-registry"),
        delete=True,
        excludes=(".git",),
    )
    print(f"  Installed: {src_root}/ -> {dest_root}/")


def install_nvim_plugin_bundle(repo_dir, home, selected_tools=None):
    """Seed the bundled active nvim plugins into ~/.local/share/nvim/lazy/.

    The bundle (envs/nvim/vendor/plugins/nvim-catalog-plugins.tar.bz2) is a snapshot of
    the active default plugin set -- including lazy.nvim itself -- each with its .git
    intact. Extracting into lazy/<name> lets lazy.nvim treat them as already
    installed, so plugins work on a fully offline box, while remaining real git
    repos that `:Lazy sync` updates when online (and seeding lazy/lazy.nvim makes
    init.lua's bootstrap a no-op offline).

    Each plugin is seeded only when lazy/<name> is absent, so re-running the
    installer never clobbers a plugin the user has updated via `:Lazy update`.
    """
    if selected_tools is not None and "nvim-catalog-plugins" not in selected_tools:
        skipped("nvim plugin bundle (nvim-catalog-plugins not selected)", "")
        record_result("nvim plugin bundle", "SKIP", "nvim-catalog-plugins not in selected packages")
        return
    archive = _bz2.resolve(os.path.join(repo_dir, "envs", "nvim", "vendor", "plugins", "nvim-catalog-plugins.tar.bz2"))
    if archive is None:
        skipped(
            "nvim plugin bundle (envs/nvim/vendor/plugins/nvim-catalog-plugins.tar.bz2 not found)",
            "Active plugins will NOT be available offline; users must run :Lazy sync online.",
        )
        record_result("nvim plugin bundle", "SKIP", "no bundle archive")
        return

    nvim_share = os.path.join(home, _local_name(home), "share", "nvim")
    lazy_dir = os.path.join(nvim_share, "lazy")
    ensure_dir(lazy_dir, "nvim plugin bundle")
    # Extract under the same filesystem as lazy/ so the per-plugin moves are renames.
    tmp = tempfile.mkdtemp(prefix=".loadout-nvim-bundle.", dir=nvim_share)
    seeded, kept = [], []
    try:
        with tarfile.open(archive, "r:bz2") as tf:
            safe_extract_tar(tf, tmp)
        for name in sorted(os.listdir(tmp)):
            # '.cloning' is lazy's interrupted-clone temp suffix -- a stray artifact
            # in the bundle, not a real plugin. Never seed it.
            if name.endswith(".cloning"):
                continue
            src = os.path.join(tmp, name)
            if not os.path.isdir(src):
                continue
            dst = os.path.join(lazy_dir, name)
            if os.path.exists(dst):
                kept.append(name)
                continue
            shutil.move(src, dst)
            seeded.append(name)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    detail = f"seeded {len(seeded)} into lazy/"
    if kept:
        detail += f"; {len(kept)} already present, kept"
    record_result("nvim plugin bundle", "yes", detail)
    print(f"  Seeded {len(seeded)} plugin(s) -> {lazy_dir}/ ({len(kept)} kept existing)")


def install_nvim_lazy_update(repo_dir, home, selected_tools=None):
    """When online, run headless nvim to bootstrap lazy.nvim and sync all plugins."""
    if selected_tools is not None and "nvim-catalog-plugins" not in selected_tools:
        skipped("Neovim Lazy sync (nvim-catalog-plugins not selected)", "")
        record_result("Neovim Lazy sync", "SKIP", "nvim-catalog-plugins not in selected packages")
        return
    # Lazy sync requires the staged tree to contain a usable nvim config
    # (init.lua + plugin specs). That config ships in the env-nvim package
    # (`kind: env`). When env-nvim isn't in the selection -- e.g. a `@shared`
    # install into a shared release tree, where per-user configs land
    # separately under `@envs` -- there is no init.lua to define `:Lazy`, and
    # the headless invocation fails. Skip cleanly in that case; per-user
    # `:Lazy sync` runs later when each user installs their `@envs` set.
    if selected_tools is not None and "env-nvim" not in selected_tools:
        skipped("Neovim Lazy sync (env-nvim not selected)", "")
        record_result("Neovim Lazy sync", "SKIP", "env-nvim not in selected packages")
        return
    nvim_bin = os.path.join(home, _local_name(home), "bin", "nvim")
    if not os.path.isfile(nvim_bin) or not os.access(nvim_bin, os.X_OK):
        skipped("Neovim Lazy sync (nvim binary not found)", f"install nvim first")
        record_result("Neovim Lazy sync", "SKIP", "nvim binary not found")
        return
    if not _is_online():
        skipped("Neovim Lazy sync (offline)", "run :Lazy sync manually when online")
        record_result("Neovim Lazy sync", "SKIP", "offline")
        return
    print("  Running nvim --headless '+Lazy! sync' (this may take a minute) ...")
    # Point HOME + all XDG base dirs at the install target so the headless nvim
    # reads/writes the STAGED config/data (~/.config/nvim, lazy/, lazy-lock.json),
    # not the real user's ~/.config/nvim. For a normal install home == $HOME, so
    # this is a no-op; for --dest-dir it keeps the staged install self-contained.
    _env = os.environ.copy()
    _env["HOME"] = home
    _env["XDG_CONFIG_HOME"] = os.path.join(home, ".config")
    _env["XDG_DATA_HOME"] = os.path.join(home, _local_name(home), "share")
    _env["XDG_STATE_HOME"] = os.path.join(home, _local_name(home), "state")
    _env["XDG_CACHE_HOME"] = os.path.join(home, ".cache")
    try:
        run([nvim_bin, "--headless", "+Lazy! sync", "+qa"], env=_env)
        record_result("Neovim Lazy sync", "yes", "plugins installed/updated")
    except subprocess.CalledProcessError as exc:
        warn(f"Neovim Lazy sync exited rc={exc.returncode}; run :Lazy sync manually")
        record_result("Neovim Lazy sync", "no", f"Lazy sync rc={exc.returncode}")


def restore_backup(backup_path, home):
    if os.path.isfile(backup_path) and backup_path.endswith(".tar.bz2"):
        tmp_dir = tempfile.mkdtemp(prefix="loadout_restore_", dir="/tmp")
        try:
            with tarfile.open(backup_path, "r:bz2") as tf:
                safe_extract_tar(tf, tmp_dir)
            inner = os.path.basename(backup_path)[: -len(".tar.bz2")]
            extracted = os.path.join(tmp_dir, inner)
            if not os.path.isdir(extracted):
                entries = [e for e in os.listdir(tmp_dir) if os.path.isdir(os.path.join(tmp_dir, e))]
                if not entries:
                    eprint(f"Error: Backup archive is empty: {backup_path}")
                    sys.exit(1)
                extracted = os.path.join(tmp_dir, entries[0])
            _restore_backup_dir(extracted, home, source_display=backup_path)
        finally:
            shutil.rmtree(tmp_dir, ignore_errors=True)
        return

    if not os.path.isdir(backup_path):
        eprint(f"Error: Backup not found: {backup_path}")
        sys.exit(1)
    _restore_backup_dir(backup_path, home, source_display=backup_path)


def _restore_backup_dir(backup_dir, home, source_display=None):
    display = source_display or backup_dir
    print(f"Restoring config bundles from backup: {display}")
    print("")
    print("Removing current config bundles...")
    bash_config = os.path.join(home, ".config", "bash")
    if os.path.islink(bash_config):
        os.unlink(bash_config)
    elif os.path.isdir(bash_config):
        remove_if_exists(os.path.join(bash_config, "global"))
        for name in ("functions.sh", "README.md", "bashrc"):
            remove_if_exists(os.path.join(bash_config, name))

    for rel in list(BASH_ENTRYPOINTS) + [
        ".vimrc",
        ".tmux.conf",
        ".editorconfig",
        ".tmux",
        ".vim",
        ".config/nvim",
        ".config/tmux",
        ".config/editorconfig",
        ".config/starship",
        ".config/vim",
    ]:
        path = os.path.join(home, rel)
        if os.path.exists(path) or os.path.islink(path):
            print(f"  Removing: {path}")
            remove_path(path)

    print("")
    print("Restoring files from backup...")
    if not os.listdir(backup_dir):
        eprint("Error: Backup directory is empty")
        sys.exit(1)
    run([_CP, "-rPp", ".", home], cwd=backup_dir)
    print("")
    print("Backup restored successfully!")
    print("")
    print(f"Restored from: {display}")


def remove_if_exists(path):
    if os.path.exists(path) or os.path.islink(path):
        remove_path(path)


def ensure_dir(path, thing="directory"):
    """Create directory at path, first removing any dangling or non-directory symlink."""
    require_writable_dir(path, thing)
    if os.path.islink(path) and not os.path.isdir(path):
        require_writable_parent(path, thing)
        print(f"  Removing stale symlink: {path}")
        os.unlink(path)
    os.makedirs(path, exist_ok=True)


def preserve_bash_layers_from_symlink(home):
    bash_config = os.path.join(home, ".config", "bash")
    saved = {}
    if os.path.islink(bash_config):
        for layer in BASH_LAYERS:
            src = os.path.join(bash_config, layer)
            if os.path.isdir(src):
                tmp = tempfile.mkdtemp(prefix=f"loadout-layer-{layer}-", dir="/tmp")
                shutil.rmtree(tmp)
                shutil.copytree(src, tmp, symlinks=True)
                saved[layer] = tmp
        require_writable_parent(bash_config, "bash config")
        os.unlink(bash_config)
        ensure_dir(bash_config, "bash config")
        for layer, tmp in saved.items():
            shutil.move(tmp, os.path.join(bash_config, layer))
    else:
        ensure_dir(bash_config, "bash config")


def install_bash(repo_dir, home, links_mode):
    bash_config = os.path.join(home, ".config", "bash")
    preserve_bash_layers_from_symlink(home)
    install_path(os.path.join(repo_dir, "envs", "bash", "global"), os.path.join(bash_config, "global"), links_mode)
    install_path(
        os.path.join(repo_dir, "envs", "bash", "functions.sh"), os.path.join(bash_config, "functions.sh"), links_mode
    )
    install_path(
        os.path.join(repo_dir, "envs", "bash", "README.md"), os.path.join(bash_config, "README.md"), links_mode
    )
    install_path(os.path.join(repo_dir, "envs", "bash", "bashrc"), os.path.join(bash_config, "bashrc"), links_mode)
    for entrypoint in BASH_ENTRYPOINTS:
        lns(".config/bash/bashrc", os.path.join(home, entrypoint), verbose=True)


def backup_existing(home, repo_dir):
    global _INTERRUPT_PHASE, _ACTIVE_BACKUP_DIR
    backup_rel = mkdirn(os.path.join(home, "loadout_backups", "backup"))
    backup_dir = os.path.abspath(backup_rel)
    _INTERRUPT_PHASE = "backup"
    _ACTIVE_BACKUP_DIR = backup_dir
    try:
        print(f"Making backups in: {backup_dir}")
        for rel in list(BASH_ENTRYPOINTS) + [
            ".vimrc",
            ".vim",
            ".tmux",
            ".tmux.conf",
            ".editorconfig",
            ".config/vim",
            ".config/nvim",
            ".config/bash/global",
            ".config/bash/functions.sh",
            ".config/bash/README.md",
            ".config/bash/bashrc",
            ".config/tmux",
            ".config/starship",
            ".config/editorconfig",
            ".config/helix/config.toml",
            ".config/pip/pip.conf",
            ".config/tealdeer/config.toml",
        ]:
            path = os.path.join(home, rel)
            if not (os.path.exists(path) or os.path.islink(path)):
                continue
            if os.path.islink(path):
                link_target = os.readlink(path)
                real = os.path.realpath(path) if os.path.exists(path) else ""
                if link_target.startswith(repo_dir) or real.startswith(repo_dir):
                    print(f"  Skipping (points to repo): {rel}")
                    continue
            print(f"  Backing up: {rel}")
            backup_item(path, os.path.join(backup_dir, rel))
        print("")
        return backup_dir
    finally:
        _INTERRUPT_PHASE = None
        _ACTIVE_BACKUP_DIR = None


def compress_backup(backup_dir):
    if not backup_dir or not os.path.isdir(backup_dir):
        skipped("compress backup (no backup dir)", "")
        return ""
    archive_path = backup_dir + ".tar.bz2"
    if os.path.exists(archive_path):
        i = 1
        while os.path.exists(f"{backup_dir}.{i}.tar.bz2"):
            i += 1
        archive_path = f"{backup_dir}.{i}.tar.bz2"
    base = os.path.basename(backup_dir)
    print(f"Compressing backup: {backup_dir} -> {archive_path}")
    with tarfile.open(archive_path, "w:bz2") as tf:
        tf.add(backup_dir, arcname=base)
    shutil.rmtree(backup_dir)
    return archive_path


def _nvim_save_user_layers(nvim_config):
    """Move user layer dirs out of nvim_config to tmp dirs for safe reinstall. Returns {layer: (tmpdir, layer_path)}."""
    saved = {}
    if not os.path.isdir(nvim_config) or os.path.islink(nvim_config):
        return saved
    lua_dir = os.path.join(nvim_config, "lua")
    for layer in NVIM_LAYERS:
        layer_path = os.path.join(lua_dir, layer)
        if os.path.isdir(layer_path) and not os.path.islink(layer_path):
            tmp = tempfile.mkdtemp(prefix="loadout-nvim-layer-")
            tmp_layer = os.path.join(tmp, layer)
            shutil.move(layer_path, tmp_layer)
            saved[layer] = (tmp, tmp_layer)
    return saved


def _nvim_restore_user_layers(saved, nvim_config):
    """Restore user layer dirs saved by _nvim_save_user_layers; create empty dirs for any not saved."""
    lua_dir = os.path.join(nvim_config, "lua")
    for layer in NVIM_LAYERS:
        layer_dest = os.path.join(lua_dir, layer)
        if layer in saved:
            tmp_dir, tmp_layer = saved[layer]
            if os.path.isdir(tmp_layer):
                shutil.move(tmp_layer, layer_dest)
            try:
                os.rmdir(tmp_dir)
            except OSError:
                pass
        else:
            ensure_dir(layer_dest, f"Neovim {layer} layer")


def _nvim_migration_notice(nvim_config):
    """Warn if old lua/custom/plugins/init.lua has non-trivial content; otherwise remove it."""
    custom = os.path.join(nvim_config, "lua", "custom")
    if not os.path.isdir(custom):
        return
    custom_init = os.path.join(custom, "plugins", "init.lua")
    if os.path.isfile(custom_init):
        try:
            with open(custom_init) as f:
                content = f.read().strip()
            if content and content != "return {}":
                warn(
                    "lua/custom/plugins/init.lua has user content -- migrate it to "
                    "~/.config/nvim/lua/user/plugins/ (the new user layer). "
                    f"Old path preserved: {custom_init}"
                )
                return
        except OSError:
            pass
    shutil.rmtree(custom, ignore_errors=True)


def _mirror_shared_prefix(home):
    """Bake $LOADOUT_CFG_SHARED_PREFIX into the installed global/config.sh.

    The shared/read-only tree is installed separately (`loadout install @shared
    --dest-dir /foo/bar`), by a different run -- often a different user -- than the
    per-user `loadout install @envs`. Nothing else carries that path across, so the
    @envs run reads LOADOUT_CFG_SHARED_PREFIX from its own environment and stamps
    it into the per-user config.sh, where the shell (PATH/TERMINFO_DIRS/tealdeer)
    can derive from it.

    Only the installed copy is stamped; the repo source keeps an empty default.
    Setting it is install-time state: re-running @envs without the env var resets
    it to empty. No-op when unset.
    """
    val = os.environ.get("LOADOUT_CFG_SHARED_PREFIX", "").strip()
    if not val:
        return
    val = os.path.abspath(os.path.expanduser(val))
    if not os.path.isdir(val):
        eprint(f"  WARNING: LOADOUT_CFG_SHARED_PREFIX={val} is not a directory (baking anyway)")
    cfg = os.path.join(home, ".config", "bash", "global", "config.sh")
    # Edit only a real installed file -- never follow a symlink back into the repo.
    if not os.path.isfile(cfg) or os.path.islink(cfg):
        return
    with open(cfg) as f:
        text = f.read()
    new_text, n = re.subn(
        r"^export LOADOUT_CFG_SHARED_PREFIX=.*$",
        "export LOADOUT_CFG_SHARED_PREFIX=" + shlex.quote(val),
        text,
        count=1,
        flags=re.M,
    )
    if not n:
        eprint(f"  WARNING: LOADOUT_CFG_SHARED_PREFIX line not found in {cfg}; not baked")
        return
    with open(cfg, "w") as f:
        f.write(new_text)
    print(f"  LOADOUT_CFG_SHARED_PREFIX baked into config.sh: {val}")


def install_tealdeer_config(repo_dir, home):
    src = os.path.join(repo_dir, "tealdeer", "config.toml")
    if not os.path.isfile(src):
        return
    cfg_dir = os.path.join(home, ".config", "tealdeer")
    ensure_dir(cfg_dir, "tealdeer config")
    prefix = os.environ.get("LOADOUT_CFG_SHARED_PREFIX", "").strip()
    if prefix:
        cache_dir = os.path.join(prefix, "share", "tealdeer", "cache")
    else:
        # Match install_tldr_cache's target so the config and the extracted pages
        # agree in both HOME (.local) and --dest-dir (un-dotted local) layouts.
        cache_dir = _resolve_install_to("~/.local/share/tealdeer/cache", home)
    cache_dir = os.path.abspath(os.path.expanduser(cache_dir))
    with open(src) as f:
        text = f.read()
    text = re.sub(r"(?ms)^\[directories\]\n.*?(?=^\[|\Z)", "", text).rstrip()
    text = f"{text}\n\n[directories]\ncache_dir = {json.dumps(cache_dir)}\n"
    dest = os.path.join(cfg_dir, "config.toml")
    require_writable_parent(dest, "tealdeer config")
    if os.path.exists(dest) or os.path.islink(dest):
        require_writable_dir(dest, "tealdeer config")
    with open(dest, "w") as f:
        f.write(text)


def _install_env_bash(repo_dir, home):
    for entrypoint in BASH_ENTRYPOINTS:
        remove_if_exists(os.path.join(home, entrypoint))
    install_bash(repo_dir, home, links_mode=False)
    _mirror_shared_prefix(home)
    install_tealdeer_config(repo_dir, home)


def _install_env_nvim(repo_dir, home):
    nvim_src = os.path.join(repo_dir, "envs", "nvim")
    nvim_config = os.path.join(home, ".config", "nvim")
    ensure_dir(os.path.join(nvim_config, "after", "lsp"), "Neovim config")
    ensure_dir(os.path.join(nvim_config, "after", "ftplugin"), "Neovim config")
    ensure_dir(os.path.join(nvim_config, "lsp"), "Neovim config")
    install_path(os.path.join(nvim_src, "init.lua"), os.path.join(nvim_config, "init.lua"), False)
    install_path(os.path.join(nvim_src, "lua", "global"), os.path.join(nvim_config, "lua", "global"), False)
    sync_dir(os.path.join(nvim_src, "lsp"), os.path.join(nvim_config, "lsp"), delete=True)
    sync_dir(os.path.join(nvim_src, "after", "ftplugin"), os.path.join(nvim_config, "after", "ftplugin"), delete=True)
    sync_dir(os.path.join(nvim_src, "after", "lsp"), os.path.join(nvim_config, "after", "lsp"), delete=True)
    for layer in NVIM_LAYERS:
        ensure_dir(os.path.join(nvim_config, "lua", layer), f"Neovim {layer} layer")
    _nvim_migration_notice(nvim_config)


def _install_env_vim(repo_dir, home):
    remove_if_exists(os.path.join(home, ".vimrc"))
    remove_if_exists(os.path.join(home, ".vim"))
    vim_config = os.path.join(home, ".config", "vim")
    if os.path.islink(vim_config):
        os.unlink(vim_config)
    ensure_dir(os.path.join(vim_config, "vim", "pack", "vendor", "start"), "Vim config")
    ensure_dir(os.path.join(vim_config, "vim", "pack", "vendor", "opt"), "Vim config")
    for start_or_opt in ("start", "opt"):
        sync_dir(
            os.path.join(repo_dir, "envs", "vim", "vim", "pack", "vendor", start_or_opt),
            os.path.join(vim_config, "vim", "pack", "vendor", start_or_opt),
            delete=True,
        )
    install_path(os.path.join(repo_dir, "envs", "vim", "vimrc"), os.path.join(vim_config, "vimrc"), False)
    lns(".config/vim/vimrc", os.path.join(home, ".vimrc"), verbose=True)


def _install_env_tmux(repo_dir, home):
    remove_if_exists(os.path.join(home, ".tmux.conf"))
    remove_if_exists(os.path.join(home, ".tmux"))
    tmux_config = os.path.join(home, ".config", "tmux")
    if os.path.islink(tmux_config):
        os.unlink(tmux_config)
    ensure_dir(os.path.join(tmux_config, "tmux", "plugins"), "tmux config")
    sync_dir(
        os.path.join(repo_dir, "envs", "tmux", "vendor", "plugins"),
        os.path.join(tmux_config, "tmux", "plugins"),
        delete=True,
    )
    install_path(os.path.join(repo_dir, "envs", "tmux", "tmux.conf"), os.path.join(tmux_config, "tmux.conf"), False)
    install_path(
        os.path.join(repo_dir, "envs", "tmux", "tmux-3col-layout.sh"),
        os.path.join(tmux_config, "tmux-3col-layout.sh"),
        False,
    )
    install_path(
        os.path.join(repo_dir, "envs", "tmux", "tmux-word-separators"),
        os.path.join(tmux_config, "tmux-word-separators"),
        False,
    )
    lns(".config/tmux/tmux.conf", os.path.join(home, ".tmux.conf"), verbose=True)
    lns(".config/tmux/tmux", os.path.join(home, ".tmux"), verbose=True)


def _install_env_editorconfig(repo_dir, home):
    remove_if_exists(os.path.join(home, ".editorconfig"))
    editorconfig_dir = os.path.join(home, ".config", "editorconfig")
    if os.path.islink(editorconfig_dir):
        os.unlink(editorconfig_dir)
    ensure_dir(editorconfig_dir, "editorconfig")
    install_path(
        os.path.join(repo_dir, "envs", "editorconfig", "editorconfig"),
        os.path.join(editorconfig_dir, "editorconfig"),
        False,
    )
    lns(".config/editorconfig/editorconfig", os.path.join(home, ".editorconfig"), verbose=True)


def _install_env_pip(repo_dir, home):
    _pip_conf_src = os.path.join(repo_dir, "envs", "python", "pip.conf")
    if not os.path.isfile(_pip_conf_src):
        return
    _pip_cfg_dir = os.path.join(home, ".config", "pip")
    ensure_dir(_pip_cfg_dir, "pip config")
    install_path(_pip_conf_src, os.path.join(_pip_cfg_dir, "pip.conf"), False)


def _install_env_starship(repo_dir, home):
    starship_dir = os.path.join(home, ".config", "starship")
    if os.path.islink(starship_dir):
        os.unlink(starship_dir)
    ensure_dir(starship_dir, "starship config")
    install_path(
        os.path.join(repo_dir, "envs", "starship", "config-schema.json"),
        os.path.join(starship_dir, "config-schema.json"),
        False,
    )
    install_path(
        os.path.join(repo_dir, "envs", "starship", "starship.linux.toml"),
        os.path.join(starship_dir, "starship.toml"),
        False,
    )


def _install_env_helix(repo_dir, home):
    _helix_cfg = os.path.join(repo_dir, "envs", "helix", "config.toml")
    if not os.path.isfile(_helix_cfg):
        return
    ensure_dir(os.path.join(home, ".config", "helix"), "helix config")
    install_path(_helix_cfg, os.path.join(home, ".config", "helix", "config.toml"), False)


def _install_env_cargo(repo_dir, home):
    """Write ~/.cargo/config.toml pointing Cargo at the bundled offline
    local-registry (installed by the rust-crate-store data package).

    Source replacement makes any project whose deps are in the store resolve
    and build with `cargo build --offline` -- no crates.io, no index fetch.
    The local-registry path tracks the store's install_to and honors a shared
    tree via LOADOUT_CFG_SHARED_PREFIX, exactly like install_tealdeer_config.
    """
    cargo_dir = os.path.join(home, ".cargo")
    ensure_dir(cargo_dir, "cargo config")
    prefix = os.environ.get("LOADOUT_CFG_SHARED_PREFIX", "").strip()
    if prefix:
        store = os.path.join(prefix, "share", "cargo", "registry-store")
    else:
        # Match install_crate_store's target in both HOME (.local) and
        # --dest-dir (un-dotted local) layouts.
        store = _resolve_install_to("~/.local/share/cargo/registry-store", home)
    store = os.path.abspath(os.path.expanduser(store))
    text = (
        "# Managed by loadout (env-cargo). Offline crate resolution against the\n"
        "# bundled local-registry. Delete this file to restore crates.io fetches.\n"
        "[source.crates-io]\n"
        'registry = "sparse+https://index.crates.io/"\n'
        'replace-with = "local-registry"\n'
        "\n"
        "[source.local-registry]\n"
        f"local-registry = {json.dumps(store)}\n"
    )
    dest = os.path.join(cargo_dir, "config.toml")
    require_writable_parent(dest, "cargo config")
    if os.path.exists(dest) or os.path.islink(dest):
        require_writable_dir(dest, "cargo config")
    with open(dest, "w") as f:
        f.write(text)
    print(f"  cargo offline config -> {dest} (local-registry: {store})")


ENV_HANDLERS = {
    "env-bash": _install_env_bash,
    "env-nvim": _install_env_nvim,
    "env-vim": _install_env_vim,
    "env-tmux": _install_env_tmux,
    "env-editorconfig": _install_env_editorconfig,
    "env-pip": _install_env_pip,
    "env-starship": _install_env_starship,
    "env-helix": _install_env_helix,
    "env-cargo": _install_env_cargo,
}


# Order matters: bash first (sets up .bashrc symlinks), then everything else.
ENV_INSTALL_ORDER = (
    "env-bash",
    "env-nvim",
    "env-vim",
    "env-tmux",
    "env-editorconfig",
    "env-pip",
    "env-starship",
    "env-helix",
    "env-cargo",
)


def _install_env_generic(pkg_name, pkg_entry, repo_dir, home):
    """Fallback installer for kind='env' entries that declare a simple
    source + install_to shape but have no custom handler in ENV_HANDLERS.

    Reuses install_path() (recursive copy for dirs, atomic copy for files). Lets
    new single-file or simple-tree env entries land without writing a
    bespoke handler each time. Custom handlers (env-bash, env-nvim, ...)
    still take precedence because the caller checks ENV_HANDLERS first.
    """
    source = pkg_entry.get("source", "")
    install_to = pkg_entry.get("install_to", "")
    if not source or not install_to:
        return False
    src = os.path.join(repo_dir, source)
    dest = os.path.expanduser(install_to)
    if dest.startswith("~"):
        dest = os.path.join(home, dest.lstrip("~/"))
    elif not os.path.isabs(dest):
        dest = os.path.join(home, dest)
    # Anchor ~/-prefixed installs to the install root (--dest-dir aware).
    home_real = os.path.realpath(home)
    expanded_home = os.path.expanduser("~")
    if dest.startswith(expanded_home + os.sep) and home_real != os.path.realpath(expanded_home):
        dest = home_real + dest[len(expanded_home) :]
    if not os.path.exists(src):
        warn(f"env package '{pkg_name}': source not found at {src}")
        return False
    print(f"  Installing env: {pkg_name} ({source} -> {install_to})")
    install_path(src, dest, links_mode=False)
    # Honor declared extra_links (e.g. ~/.zshrc -> ~/.config/zsh/zshrc). The
    # dedicated handlers (env-bash/vim/tmux) hardcode their lns() calls; doing
    # it here lets a simple env package wire its entrypoint symlinks purely from
    # packages.json. Target is home-relative (matches the dedicated handlers, so
    # the link survives a relocated tree); link path is anchored to the install
    # root the same way dest is above (--dest-dir aware).
    for link in pkg_entry.get("extra_links", []):
        link_from = link.get("from", "")
        link_to = link.get("to", "")
        if not link_from or not link_to:
            continue
        target = link_from[2:] if link_from.startswith("~/") else link_from
        link_path = os.path.expanduser(link_to)
        if link_path.startswith("~"):
            link_path = os.path.join(home, link_to.lstrip("~/"))
        elif not os.path.isabs(link_path):
            link_path = os.path.join(home, link_to)
        if link_path.startswith(expanded_home + os.sep) and home_real != os.path.realpath(expanded_home):
            link_path = home_real + link_path[len(expanded_home) :]
        lns(target, link_path, verbose=True)
    return True


def install_env_pkg(pkg_name, pkg_entry, repo_dir, home):
    """Per-package handler for kind='env'. Dispatches to the right helper."""
    handler = ENV_HANDLERS.get(pkg_name)
    if handler is not None:
        handler(repo_dir, home)
        return
    if _install_env_generic(pkg_name, pkg_entry, repo_dir, home):
        return
    warn(f"env package '{pkg_name}' has no handler and no installable shape; skipped")


def install_copy_mode(repo_dir, home, selected_pkgs=None, registry=None):
    """Install env-kind packages.

    Registered handlers (ENV_INSTALL_ORDER) run first, in that fixed order.
    Then any selected env package not in ENV_INSTALL_ORDER falls through to
    the generic source/install_to copy fallback.

    When selected_pkgs is None, install every env that has a Linux handler.
    """
    for pkg_name in ENV_INSTALL_ORDER:
        if selected_pkgs is not None and pkg_name not in selected_pkgs:
            continue
        ENV_HANDLERS[pkg_name](repo_dir, home)
        record_result(pkg_name, "yes", "")

    if selected_pkgs is None or registry is None:
        return
    handled = set(ENV_INSTALL_ORDER)
    for pkg_name in sorted(selected_pkgs):
        if pkg_name in handled:
            continue
        entry = registry.get(pkg_name) or {}
        if entry.get("kind") != "env":
            continue
        if _install_env_generic(pkg_name, entry, repo_dir, home):
            handled.add(pkg_name)
            record_result(pkg_name, "yes", "")


def glob_paths(path):
    if not os.path.isdir(path):
        return []
    return [os.path.join(path, x) for x in os.listdir(path)]


def run_post_install_hooks(hooks, repo_dir, home, args, backup_dir):
    for hook in hooks:
        print(f"Running post-install hook: {hook}")
        env = os.environ.copy()
        env.update(
            {
                "LOADOUT_REPO": repo_dir,
                "LOADOUT_HOME": home,
                "LOADOUT_BACKUP_DIR": backup_dir,
                "LOADOUT_NO_BACKUP": "1" if args.no_backup else "0",
                "LOADOUT_DEST_DIR": home,
            }
        )
        run([hook], env=env)


def run_layer_install_scripts(home):
    ran = []
    for layer in BASH_LAYERS:
        install_script = os.path.join(home, ".config", "bash", layer, "install.sh")
        if os.path.isfile(install_script) and os.access(install_script, os.R_OK):
            print(f"Sourcing '{install_script}' ...")
            run(["/bin/bash", "-c", 'source "$1"', "/bin/bash", install_script])
            ran.append(layer)
    if ran:
        record_result("layer install scripts", "yes", "ran: {}".format(", ".join(ran)))
    else:
        record_result("layer install scripts", "SKIP", "no layer install.sh present")


def _comma_wrap(s, width):
    """Wrap comma-separated groups so each non-last line ends with ','."""
    items = [g.strip() for g in s.split(",") if g.strip()]
    if not items:
        return [s] if s else [""]
    lines = []
    current = []
    for idx, item in enumerate(items):
        is_last = idx == len(items) - 1
        candidate = ", ".join(current + [item]) + ("," if not is_last else "")
        if not current or len(candidate) <= width:
            current.append(item)
        else:
            lines.append(", ".join(current) + ",")
            current = [item]
    if current:
        lines.append(", ".join(current))
    return lines or [""]


def _word_wrap(s, width):
    """Word-wrap s to width; long words are never split."""
    if not s or width <= 0:
        return [s or ""]
    words = s.split()
    if not words:
        return [""]
    lines, cur = [], words[0]
    for word in words[1:]:
        if len(cur) + 1 + len(word) <= width:
            cur += " " + word
        else:
            lines.append(cur)
            cur = word
    lines.append(cur)
    return lines


def _list_table(rows, columns):
    """Render rows as a table (rich when available, plain otherwise).

    rows: list of tuples matching `columns` order.
    columns: list of dicts: {"name", "style", "max_width", "no_wrap", "ratio",
                              "min_width", "wrap"}.
    Columns with "wrap": "comma" or "wrap": "word" are treated as elastic:
    their widths are jointly optimised to minimise total output lines.
    Content wraps (never truncates); GROUPS column breaks only at commas.
    """
    import shutil

    if not rows:
        print("(no rows)")
        return

    n = len(columns)
    sep = 2
    term_cols = shutil.get_terminal_size(fallback=(160, 24)).columns

    # -- Width computation --------------------------------------------------
    # Fixed cols: natural width (capped by max_width when set).
    # Elastic cols: those with a "wrap" key -- share remaining terminal space.
    elastic_indices = [i for i, c in enumerate(columns) if c.get("wrap")]
    fixed_indices = [i for i in range(n) if i not in elastic_indices]

    fixed_widths = {}
    for i in fixed_indices:
        col = columns[i]
        w = max(len(col["name"]), *(len(str(r[i])) for r in rows))
        if col.get("max_width"):
            w = min(w, col["max_width"])
        fixed_widths[i] = w

    # Total chars consumed by fixed columns and all separators.
    fixed_total = sum(fixed_widths.values()) + sep * (n - 1)
    available = term_cols - fixed_total  # shared among elastic cols (no extra sep: already counted)

    # Optimise elastic col widths by minimising total output lines.
    #
    # Search bounds (content-derived, not terminal-derived):
    #   min_g  = longest single group item -- a group that won't fit in less
    #   max_g  = longest full groups string -- beyond this GROUPS never wraps,
    #            only DESCRIPTION gets squeezed; no benefit to going wider
    # Stop early once total_lines stops improving.
    if len(elastic_indices) == 2:
        gi, di = elastic_indices
        g_fn = _comma_wrap if columns[gi].get("wrap") == "comma" else _word_wrap
        d_fn = _word_wrap

        min_g = max(
            max(
                (max((len(x.strip()) for x in str(r[gi]).split(",") if x.strip()), default=1) for r in rows), default=8
            ),
            len(columns[gi]["name"]),
        )
        min_d = max(columns[di].get("min_width", 20), len(columns[di]["name"]))
        # Natural ceiling: widest groups string -- no wrap savings beyond this
        natural_g = max((len(str(r[gi])) for r in rows), default=min_g)
        max_g = min(natural_g, available - min_d)

        best_g, best_lines = min_g, float("inf")
        for w_g in range(min_g, max(max_g + 1, min_g + 1)):
            w_d = available - w_g
            if w_d < min_d:
                break
            total = sum(max(len(g_fn(str(r[gi]), w_g)), len(d_fn(str(r[di]), w_d))) for r in rows)
            if total < best_lines:
                best_lines, best_g = total, w_g
            elif total > best_lines:
                break  # past the minimum; further widening only hurts

        elastic_widths = {gi: best_g, di: available - best_g}
        wrap_fns = {gi: g_fn, di: d_fn}

    elif len(elastic_indices) == 1:
        (ei,) = elastic_indices
        elastic_widths = {ei: max(available, len(columns[ei]["name"]))}
        wrap_fns = {ei: (_comma_wrap if columns[ei].get("wrap") == "comma" else _word_wrap)}

    else:
        # No elastic cols: fixed widths only.
        elastic_widths = {}
        wrap_fns = {}

    widths = {i: fixed_widths.get(i, elastic_widths.get(i, 0)) for i in range(n)}

    # -- Pre-wrap all cells -------------------------------------------------
    # Each cell becomes a list of lines.
    def _cell_lines(r, i):
        s = str(r[i])
        if i in wrap_fns:
            return wrap_fns[i](s, widths[i])
        return [s]

    # -- Render ------------------------------------------------------------
    if _RICH and _console is not None:
        t = _RichTable(
            box=None,
            show_header=True,
            header_style="bold",
            pad_edge=False,
            show_edge=False,
            expand=False,
            padding=(0, 1),
            collapse_padding=True,
        )
        for i, col in enumerate(columns):
            t.add_column(
                col["name"],
                style=col.get("style", ""),
                no_wrap=True,
                min_width=widths[i],
                max_width=widths[i],
                overflow="fold",
            )
        for r in rows:
            cells = ["\n".join(_cell_lines(r, i)) for i in range(n)]
            t.add_row(*cells)
        _console.print(t)
        return

    # Plain fallback.
    header = "  ".join("{:<{}}".format(columns[i]["name"], widths[i]) for i in range(n))
    rule = "  ".join("-" * widths[i] for i in range(n))
    print(header)
    print(rule)
    for r in rows:
        cell_lines = [_cell_lines(r, i) for i in range(n)]
        row_h = max(len(cl) for cl in cell_lines)
        for k in range(row_h):
            parts = []
            for i in range(n):
                line = cell_lines[i][k] if k < len(cell_lines[i]) else ""
                parts.append("{:<{}}".format(line, widths[i]))
            print("  ".join(parts))


def cmd_list(args, registry):
    """Print packages or groups table."""
    if args.list_groups:
        rows = []
        for n in sorted(registry):
            if not n.startswith("@"):
                continue
            entry = registry[n]
            members = entry.get("members", [])
            rows.append((n, str(len(members)), entry.get("description", "")))
        for n, desc in _SYNTHETIC_GROUPS.items():
            rows.append((n, str(len(expand_groups([n], registry))), desc + " (synthetic)"))
        rows.sort(key=lambda r: r[0])
        _list_table(
            rows,
            [
                {"name": "GROUP", "style": "bold cyan"},
                {"name": "MEMBERS"},
                {"name": "DESCRIPTION"},
            ],
        )
        return 0
    tag = args.tag
    # Build reverse map: pkg name -> sorted list of @groups that directly
    # name it in their members list (matches cmd_describe's 'groups:' line).
    pkg_groups = {}
    for gname, gentry in registry.items():
        if gentry.get("kind") != "group":
            continue
        for m in gentry.get("members", []):
            pkg_groups.setdefault(m, []).append(gname)
    rows = []
    for n in sorted(registry):
        entry = registry[n]
        if entry.get("kind") == "group":
            continue
        if tag is not None and tag not in entry.get("tags", []):
            continue
        rows.append(
            (
                n,
                entry.get("kind", ""),
                entry.get("version", ""),
                ", ".join(sorted(pkg_groups.get(n, []))),
                entry.get("description", ""),
            )
        )
    _list_table(
        rows,
        [
            {"name": "PACKAGE", "style": "bold cyan"},
            {"name": "KIND"},
            {"name": "VERSION"},
            {"name": "GROUPS", "wrap": "comma"},
            {"name": "DESCRIPTION", "wrap": "word", "min_width": 30},
        ],
    )
    return 0


def cmd_describe(args, registry):
    """Print full metadata for a package or @group."""
    if not args.positional:
        eprint("Usage: loadout info <package-or-@group>")
        return 1
    name = args.positional[0]
    if name in _SYNTHETIC_GROUPS:
        members = sorted(expand_groups([name], registry))
        print(name)
        print("=" * len(name))
        print("kind:        group (synthetic)")
        print(f"description: {_SYNTHETIC_GROUPS[name]}")
        print(f"members ({len(members)}):")
        for m in members:
            print(f"  - {m}")
        return 0
    entry = registry.get(name)
    if entry is None:
        eprint(f"Unknown package: {name}")
        return 1
    print(f"{name}")
    print("=" * len(name))
    print("kind:        {}".format(entry.get("kind", "(missing)")))
    if entry.get("kind") == "group":
        print("description: {}".format(entry.get("description", "")))
        members = entry.get("members", [])
        print(f"members ({len(members)}):")
        for m in members:
            print(f"  - {m}")
        return 0
    print("version:     {}".format(entry.get("version", "")))
    print("platforms:   {}".format(", ".join(entry.get("platforms", ["linux"]))))
    if entry.get("tags"):
        print("tags:        {}".format(", ".join(entry["tags"])))
    print("description: {}".format(entry.get("description", "")))
    if entry.get("depends"):
        print("depends:     {}".format(", ".join(entry["depends"])))
    if entry.get("recommends"):
        print("recommends:  {}".format(", ".join(entry["recommends"])))
    for fkey in (
        "bins",
        "libs",
        "wheels",
        "typelibs",
        "uv_tool",
        "archive",
        "source",
        "install_to",
        "extra_links",
        "supports_layers",
    ):
        if fkey in entry:
            v = entry[fkey]
            if isinstance(v, list):
                if v:
                    print("{:12} {}".format(fkey + ":", ", ".join(str(x) for x in v)))
            else:
                print("{:12} {}".format(fkey + ":", v))
    # Reverse deps
    rdeps = [n for n, e in registry.items() if name in e.get("depends", []) or name in e.get("recommends", [])]
    if rdeps:
        print("rdeps:       {}".format(", ".join(sorted(rdeps))))
    # Group memberships
    groups = [n for n, e in registry.items() if e.get("kind") == "group" and name in e.get("members", [])]
    if groups:
        print("groups:      {}".format(", ".join(sorted(groups))))
    return 0


def cmd_resolve(args, registry):
    """Resolve selection (treating positional args as --add) and print sorted set."""
    if args.positional and not args.only and not args.add:
        args.add = ",".join(args.positional)
    try:
        selected = resolve_tool_selection(args, registry)
    except ResolverError as _err:
        eprint(f"Resolver error: {_err}")
        return 1
    if selected is None:
        print("(empty registry; resolver returned None -> install-everything sentinel)")
        return 0
    print(f"Resolved {len(selected)} packages:")
    by_kind = {}
    for n in sorted(selected):
        k = registry.get(n, {}).get("kind", "?")
        by_kind.setdefault(k, []).append(n)
    for k in sorted(by_kind):
        pkgs = by_kind[k]
        print("  [{}] ({}): {}".format(k, len(pkgs), ", ".join(pkgs)))
    return 0


def cmd_doctor(args, registry, repo_dir):
    """Platform detection + per-package archive sanity check."""
    print(f"Platform:    {_current_platform()}")
    print(f"Repo dir:    {repo_dir}")
    platform_dir = select_prebuilt_platform_dir(os.path.join(repo_dir, "pre_built"))
    print("Pre-built:   {}".format(platform_dir or "(none matched)"))
    print()

    missing = []
    checked = 0
    for name in sorted(registry):
        entry = registry[name]
        kind = entry.get("kind")
        if kind in ("runtime", "data", "font", "python-base") or (kind == "bin" and entry.get("archive")):
            archive = entry.get("archive", "")
            if not archive:
                continue
            checked += 1
            # Resolve TS_PLATFORM (treesitter-specific) first, then PLATFORM (binary platform)
            resolved = archive
            if "TS_PLATFORM" in resolved:
                resolved = resolved.replace("TS_PLATFORM", treesitter_platform_id())
            if "PLATFORM" in resolved and platform_dir:
                resolved = resolved.replace("PLATFORM", os.path.basename(platform_dir))
            # Glob with shell-style wildcards
            full_path = os.path.join(repo_dir, resolved)
            matches = glob_paths_glob(full_path)
            if not matches:
                # Large archives are auto-chunked into .part-NNN by
                # strip_all_elf_binaries; the bare archive file disappears
                # once that happens. Accept the chunks as a present archive.
                matches = glob_paths_glob(full_path + ".part-*")
            if not matches:
                missing.append((name, kind, resolved))
    if missing:
        print(f"Missing archives ({len(missing)} of {checked} checked):")
        for n, k, p in missing:
            print(f"  [{k}] {n}: {p}")
    else:
        print(f"All {checked} runtime/data/font/python-base archives present.")
    print()

    # Bin/lib artifact check. doctor previously only validated runtime archives, so a
    # registry entry whose bin/*.bz2 or lib64/*.bz2 was never built passed silently --
    # and --only <pkg> "succeeded" while installing nothing. Verify them here.
    def _artifact_present(sub, stem):
        if not platform_dir:
            return True  # can't verify without a platform dir; not this check's job
        base = os.path.join(platform_dir, sub, stem + ".bz2")
        return os.path.exists(base) or os.path.exists(base + ".part-000")

    missing_artifacts = []
    for name in sorted(registry):
        entry = registry[name]
        kind = entry.get("kind")
        # bins are bin/*.bz2 ONLY for bin-kind packages that are not python-tools
        # (uv-created launchers) and do not unpack from a runtime archive (e.g.
        # nodejs node/npm live inside node.tar.bz2, already checked above).
        if kind == "bin" and not entry.get("archive"):
            for b in entry.get("bins", []):
                if not _artifact_present("bin", b):
                    missing_artifacts.append((name, "bin/" + b + ".bz2"))
        # libs are real lib64/*.bz2 artifacts regardless of kind.
        for lib in entry.get("libs", []):
            if not _artifact_present("lib64", lib):
                missing_artifacts.append((name, "lib64/" + lib + ".bz2"))
    if missing_artifacts:
        bypkg = {}
        for n, art in missing_artifacts:
            bypkg.setdefault(n, []).append(art)
        print(f"Missing bin/lib artifacts ({len(missing_artifacts)} files across {len(bypkg)} packages):")
        for n in sorted(bypkg):
            items = bypkg[n]
            shown = ", ".join(items[:6]) + (f" ... (+{len(items) - 6})" if len(items) > 6 else "")
            print(f"  {n}: {shown}")
    else:
        print("All bin/lib artifacts present.")
    print()

    # Registry sanity
    unknown_deps = []
    for n, e in registry.items():
        for field in ("depends", "recommends"):
            for ref in e.get(field, []):
                if ref.startswith("@"):
                    if ref not in registry and ref not in ("@shared", "@envs"):
                        unknown_deps.append((n, field, ref))
                elif ref not in registry:
                    unknown_deps.append((n, field, ref))
    if unknown_deps:
        print("Unresolved references:")
        for n, f, r in unknown_deps:
            print(f"  {n} -> {f} -> {r}")
    else:
        print("All depends/recommends resolve to known packages.")
    print()

    # Env-handler sanity: every env package selectable on the current
    # platform must either have a registered handler in ENV_HANDLERS or a
    # generic-installable shape (source + install_to). Catches
    # env-wezterm-style omissions at registration time.
    current_plat = _current_platform()
    handler_missing = []
    for n, e in registry.items():
        if e.get("kind") != "env":
            continue
        platforms = e.get("platforms") or ["linux"]
        if current_plat not in platforms:
            continue
        if n in ENV_HANDLERS:
            continue
        if e.get("source") and e.get("install_to"):
            continue
        handler_missing.append(n)
    if handler_missing:
        print(f"env packages without handler or installable shape on {current_plat}:")
        for n in handler_missing:
            print(f"  {n}")
        print("  (either register an ENV_HANDLERS entry or add 'source' + 'install_to'.)")
    else:
        print(f"All env packages installable on {current_plat}.")

    return 0 if not missing and not unknown_deps and not handler_missing else 2


def glob_paths_glob(pattern):
    """Glob with shell-style wildcards (handles 'archive.zip.part-*' and similar)."""
    import glob as _glob

    return sorted(_glob.glob(pattern))


def cmd_install(args, registry, selected_tools, repo_dir, home):
    """The default install verb."""
    global _FOLLOW_SYMLINKS
    _FOLLOW_SYMLINKS = getattr(args, "install_follows_symlinks", "auto") or "auto"

    if args.dry_run:
        print("DRY RUN: would install {} packages.".format(len(selected_tools) if selected_tools else "(all)"))
        return cmd_resolve(args, registry)

    print(f"Loadout repo: {repo_dir}")
    if args.dest_dir:
        print(f"Destination: {home}")

    hooks = []
    for hook in args.post_install_hook:
        if not os.path.isfile(hook) or not os.access(hook, os.X_OK):
            eprint(f"Error: Post-install hook is not executable: {hook}")
            return 1
        hooks.append(os.path.abspath(hook))

    print(f"Changing directory to {home}")
    ensure_dir(home, "install destination")
    os.chdir(home)

    backup_dir = ""
    # Backups exist to protect user-owned config files in $HOME / $XDG_CONFIG_HOME
    # that the env-* packages overwrite. When the selection contains no
    # env-* package -- e.g. a `@shared` install into a release tree, or a
    # pure tool-only selection -- nothing user-owned is touched, so the
    # backup phase has nothing to protect and the --no-backup warning
    # ("existing files will be overwritten") has nothing to warn about.
    # Skip both silently in that case.
    selecting_env_pkgs = any(registry.get(name, {}).get("kind") == "env" for name in (selected_tools or ()))
    if not selecting_env_pkgs:
        pass
    elif args.no_backup:
        warn("no backup taken (--no-backup): existing files will be overwritten")
    else:
        backup_dir = run_install_step("backup", backup_existing, home, repo_dir) or ""

    _prebuilt_result = run_install_step("pre-built binaries", install_prebuilt_binaries, repo_dir, home, selected_tools)
    blocked_deferred, blocked_failed = _prebuilt_result if isinstance(_prebuilt_result, tuple) else (set(), {})
    add_prebuilt_binary_retry_notice(blocked_deferred, blocked_failed)

    run_install_step("config files", install_copy_mode, repo_dir, home, selected_tools, registry, silent=True)
    run_install_step("fonts", install_fonts, repo_dir, home, selected_tools, registry, args.no_backup)
    run_install_step("tldr cache", install_tldr_cache, repo_dir, home, selected_tools)
    run_install_step("Rust crate store", install_crate_store, repo_dir, home, selected_tools, silent=True)
    run_install_step("portable Python", install_portable_python, repo_dir, home, selected_tools)
    run_install_step("GObject typelibs", install_typelibs, repo_dir, home, selected_tools)
    run_install_step("Python tools", install_python_tools, repo_dir, home, selected_tools, registry)
    run_install_step(
        "runtime archives", install_runtime_archives, repo_dir, home, selected_tools, registry, silent=True
    )
    run_install_step("Vim runtime", install_vim_runtime, repo_dir, home, selected_tools, silent=True)
    run_install_step("Meld runtime", install_meld_runtime, repo_dir, home, selected_tools, silent=True)
    run_install_step(
        "mate-terminal runtime", install_mate_terminal_runtime, repo_dir, home, selected_tools, silent=True
    )
    run_install_step("Firefox runtime", install_firefox_runtime, repo_dir, home, selected_tools, silent=True)
    run_install_step("nvim-qt runtime", install_nvim_qt_runtime, repo_dir, home, selected_tools, silent=True)
    run_install_step(
        "nvim-treesitter vendor", install_nvim_treesitter_vendor, repo_dir, home, selected_tools, silent=True
    )
    run_install_step("nvim plugin bundle", install_nvim_plugin_bundle, repo_dir, home, selected_tools, silent=True)
    run_install_step("Neovim Lazy sync", install_nvim_lazy_update, repo_dir, home, selected_tools)
    run_install_step("Tree-sitter parsers", install_treesitter_parsers, repo_dir, home, selected_tools, silent=True)
    if hooks:
        run_install_step("post-install hooks", run_post_install_hooks, hooks, repo_dir, home, args, backup_dir)
    else:
        record_result("post-install hooks", "SKIP", "none requested")
    run_install_step("layer install scripts", run_layer_install_scripts, home)
    if backup_dir:
        run_install_step("compress backup", compress_backup, backup_dir)
    print_final_notices()
    print_install_results()
    print_install_blockers()
    # When a shared tree (non-env content) lands in a --dest-dir, tell the admin
    # the exact prefix to export so per-user `@envs` installs resolve against it.
    if getattr(args, "dest_dir", None) and any(
        registry.get(name, {}).get("kind") not in ("env", "group") for name in (selected_tools or ())
    ):
        shared_root = _resolve_install_to("~/.local", home)
        print("")
        print("Shared tree installed. For per-user shells, run each user's env install with:")
        print(f"  LOADOUT_CFG_SHARED_PREFIX={shared_root} loadout install @envs")
    return 0


def _adapt_install_args(args):
    """Map the click-built SimpleNamespace onto fields the legacy install/resolve
    handlers read directly (args.only, args.add, args.positional). Mutates in
    place; idempotent."""
    if not hasattr(args, "only"):
        pkgs = list(getattr(args, "packages", None) or [])
        args.only = ",".join(pkgs) if pkgs else None
        args.add = None
        args.positional = list(pkgs)
    if not hasattr(args, "skip"):
        args.skip = None
    if not hasattr(args, "no_deps"):
        args.no_deps = False
    if not hasattr(args, "force"):
        args.force = False


def cmd_install_v2(args, registry, repo_dir, home):
    """Thin shim: adapt new-CLI args -> legacy cmd_install."""
    pkgs = list(getattr(args, "packages", None) or [])
    if not pkgs:
        eprint("Error: no package specified")
        eprint("Run 'loadout install <PKG> [<PKG>...]' to install packages.")
        eprint("Run 'loadout list' to browse, 'loadout search <pattern>' to search.")
        return 1
    if "@default" in pkgs:
        eprint(
            "Error: @default no longer exists. Use 'loadout install "
            "@engineering-loadout' for the full bundled set, or name "
            "packages explicitly."
        )
        return 1
    _adapt_install_args(args)
    try:
        selected_tools = resolve_tool_selection(args, registry)
    except ResolverError as _err:
        eprint(f"Resolver error: {_err}")
        return 1
    # Catch unknown package names before we proceed (resolver silently drops
    # them with a warn; package managers exit non-zero).
    unknown = [n for n in pkgs if not n.startswith("@") and n != "all" and n not in registry]
    if unknown:
        for n in unknown:
            eprint(f"Error: no match for argument: {n}")
        return 1
    return cmd_install(args, registry, selected_tools, repo_dir, home)


def cmd_resolve_v2(args, registry):
    """Adapter for the new positional-args resolve verb."""
    pkgs = list(getattr(args, "packages", None) or [])
    if not pkgs:
        eprint("Error: no package specified")
        eprint("Run 'loadout resolve <PKG> [<PKG>...]' to dry-resolve a selection.")
        return 1
    _adapt_install_args(args)
    return cmd_resolve(args, registry)


def cmd_search(args, registry):
    """Case-insensitive substring search over package name, description, tags.

    Name hits ranked above description/tag hits (dnf-style). Groups included.
    """
    pat = args.pattern.lower()
    tag = getattr(args, "tag", None)
    name_hits = []
    desc_hits = []
    for name in sorted(registry):
        entry = registry[name]
        if entry.get("kind") == "group":
            # groups have name + description but no tags; still searchable
            pass
        if tag and tag not in entry.get("tags", []):
            continue
        desc = entry.get("description", "")
        tags = entry.get("tags", [])
        haystack_desc = (desc + " " + " ".join(tags)).lower()
        if pat in name.lower():
            name_hits.append((name, entry))
        elif pat in haystack_desc:
            desc_hits.append((name, entry))
    rows = []
    for name, entry in name_hits + desc_hits:
        rows.append(
            (
                name,
                entry.get("kind", ""),
                entry.get("version", ""),
                entry.get("description", ""),
            )
        )
    if not rows:
        print(f"No matches for '{args.pattern}'.")
        return 1
    _list_table(
        rows,
        [
            {"name": "PACKAGE", "style": "bold cyan"},
            {"name": "KIND"},
            {"name": "VERSION"},
            {"name": "DESCRIPTION", "wrap": "word", "min_width": 30},
        ],
    )
    return 0


def cmd_info(args, registry):
    """dnf-style 'info': delegate to cmd_describe with a positional shim."""
    args.positional = [args.name]
    return cmd_describe(args, registry)


def cmd_snapshot(args, repo_dir, home):
    """Dispatcher for snapshot create/restore/list."""
    sub = getattr(args, "snapshot_cmd", None)
    if sub == "create":
        ensure_dir(home, "snapshot destination")
        os.chdir(home)
        backup_dir = backup_existing(home, repo_dir)
        if not backup_dir:
            eprint("Error: nothing to snapshot (no existing files to back up).")
            return 1
        archive = compress_backup(backup_dir)
        if archive:
            print(f"Snapshot: {archive}")
        return 0
    if sub == "restore":
        restore_backup(args.path, home)
        return 0
    if sub == "list":
        backups_dir = os.path.join(home, "loadout_backups")
        if not os.path.isdir(backups_dir):
            print("(no snapshots)")
            return 0
        entries = []
        for name in os.listdir(backups_dir):
            full = os.path.join(backups_dir, name)
            try:
                st = os.stat(full)
            except OSError:
                continue
            entries.append((st.st_mtime, name, full, os.path.isdir(full)))
        if not entries:
            print("(no snapshots)")
            return 0
        entries.sort(reverse=True)
        rows = []
        for mtime, name, full, is_dir in entries:
            kind = "dir" if is_dir else "archive"
            try:
                size = (
                    "{:.1f} MiB".format(
                        sum(os.path.getsize(os.path.join(dp, f)) for dp, _, fs in os.walk(full) for f in fs)
                        / (1024 * 1024)
                    )
                    if is_dir
                    else f"{os.path.getsize(full) / (1024 * 1024):.1f} MiB"
                )
            except OSError:
                size = "?"
            when = time.strftime("%Y-%m-%d %H:%M", time.localtime(mtime))
            rows.append((name, kind, size, when))
        _list_table(
            rows,
            [
                {"name": "NAME", "style": "bold cyan"},
                {"name": "KIND"},
                {"name": "SIZE"},
                {"name": "MTIME"},
            ],
        )
        return 0
    eprint("Usage: loadout snapshot {create|restore|list}")
    return 1


def cmd_clean(args):
    """Remove stale /tmp/loadout* state. Refuses to touch ~/loadout_backups/.

    --logs    -> delete /tmp/loadout.<user>.log
    --pending -> delete /tmp/loadout-pending-<user>/ (only if daemon PID is dead)
    --all     -> both, plus any stale /tmp/loadout-* tempdirs owned by this user
    """
    do_logs = args.logs or args.clean_all
    do_pending = args.pending or args.clean_all
    do_extra = args.clean_all
    if not (do_logs or do_pending or do_extra):
        eprint("Usage: loadout clean [--logs] [--pending] [--all]")
        return 1
    removed = []
    if do_logs:
        for path in (_RUN_LOG_FIXED_PATH,):
            if os.path.exists(path):
                try:
                    os.unlink(path)
                    removed.append(path)
                except OSError as exc:
                    eprint(f"Could not remove {path}: {exc}")
    if do_pending:
        if os.path.isdir(_PENDING_DIR):
            if _pending_daemon_alive():
                eprint(f"Refusing to clean {_PENDING_DIR}: pending-ops daemon is running.")
                return 1
            try:
                shutil.rmtree(_PENDING_DIR)
                removed.append(_PENDING_DIR)
            except OSError as exc:
                eprint(f"Could not remove {_PENDING_DIR}: {exc}")
    if do_extra:
        for name in os.listdir("/tmp"):
            if name.startswith("loadout-") and name != os.path.basename(_PENDING_DIR):
                full = os.path.join("/tmp", name)
                try:
                    if os.lstat(full).st_uid != os.getuid():
                        continue  # another user's state -- not ours to clean
                except OSError:
                    continue
                try:
                    if os.path.isdir(full):
                        shutil.rmtree(full)
                    else:
                        os.unlink(full)
                    removed.append(full)
                except OSError as exc:
                    eprint(f"Could not remove {full}: {exc}")
    for path in removed:
        print(f"removed: {path}")
    if not removed:
        print("(nothing to clean)")
    return 0


def _pending_daemon_alive():
    """True if the pending-ops daemon PID file points at a live process."""
    pid_path = os.path.join(_PENDING_DIR, "daemon.pid")
    try:
        with open(pid_path) as fh:
            pid = int(fh.read().strip())
    except OSError, ValueError:
        return False
    try:
        os.kill(pid, 0)
    except OSError:
        return False
    return True


# Aliases (e.g. `update` -> `upgrade`, `describe` -> `info`) are declared on the
# command itself via rich-click's native `aliases=[...]` kwarg -- no custom Group
# subclass needed.


def _selection_options(f):
    """Decorator stack: positional PKG list + dnf-style selection flags."""
    f = click.option(
        "--force",
        is_flag=True,
        help="Continue past resolver errors (record FAIL, keep going).",
    )(f)
    f = click.option(
        "--no-deps",
        "no_deps",
        is_flag=True,
        help="Do not walk depends/recommends.",
    )(f)
    f = click.option(
        "--skip",
        default=None,
        metavar="NAME,...",
        help="Remove packages or @groups from the install set.",
    )(f)
    f = click.argument("packages", nargs=-1, metavar="PKG...")(f)
    return f


def _install_options(f):
    """Decorator stack: install-like verbs (install, reinstall, upgrade)."""
    f = click.option(
        "--post-install-hook",
        "post_install_hook",
        multiple=True,
        metavar="FILE",
        help="Run a corp/site/user hook after global install steps (repeatable).",
    )(f)
    f = click.option(
        "--install-follows-symlinks",
        "install_follows_symlinks",
        type=click.Choice(["yes", "no", "auto"]),
        default="auto",
        show_default=True,
        help=(
            "How to handle existing directory symlinks during archive extraction. "
            "auto: follow if the symlink target is writable, else replace with a real dir. "
            "yes: always follow. no: always replace."
        ),
    )(f)
    f = click.option(
        "--no-backup",
        "no_backup",
        is_flag=True,
        help="Skip the pre-install snapshot.",
    )(f)
    f = click.option(
        "--dry-run",
        "dry_run",
        is_flag=True,
        help="Resolve and print the plan; no files written.",
    )(f)
    return f


def _ctx_args(ctx, **extra):
    """Build a SimpleNamespace from command-level kwargs.

    The legacy handler functions (cmd_install_v2, cmd_list, cmd_describe, ...) read
    fields like args.packages, args.skip, args.dest_dir straight off the object;
    this shim lets the click decorators feed them without rewriting every handler.
    Verbs that take --dest-dir pass it via **extra.
    """
    return types.SimpleNamespace(**extra)


def _resolve_home(dest_dir):
    """Resolve the install root from a --dest-dir option value (or default $HOME)."""
    return os.path.abspath(dest_dir) if dest_dir else os.path.expanduser("~")


def _dest_dir_option(f):
    """Decorator: attach --dest-dir to verbs that act on the install destination."""
    return click.option(
        "--dest-dir",
        "dest_dir",
        metavar="DIR",
        default=None,
        help="Install root (default: $HOME).",
    )(f)


def _print_version_and_exit(ctx, param, value):
    if not value or ctx.resilient_parsing:
        return
    repo_dir = os.path.dirname(os.path.abspath(__file__))
    click.echo(_get_version(repo_dir))
    ctx.exit(0)


@click.group(
    invoke_without_command=True,
    context_settings={"help_option_names": ["-h", "--help"]},
)
@click.option(
    "--version",
    "-V",
    is_flag=True,
    expose_value=False,
    is_eager=True,
    callback=_print_version_and_exit,
    help="Print version (git describe) and exit.",
)
@click.option("--verbose", is_flag=True, help="Verbose progress output.")
@click.pass_context
def cli(ctx, verbose):
    """loadout -- offline-first package manager.

    Installs bundled packages into the destination directory. Bare 'loadout' and
    bare 'loadout install' both print usage and exit non-zero (dnf parity); always
    name packages or @groups explicitly. Use [bold]@engineering-loadout[/] for the
    full bundled set.

    `--dest-dir` lives on the verbs that act on the install destination
    (`install`, `reinstall`, `upgrade`, and the `snapshot` subcommands); read-only
    verbs (`list`, `search`, `info`, `resolve`, `doctor`, `clean`) never touch the
    destination.
    """
    repo_dir = os.path.dirname(os.path.abspath(__file__))
    ctx.ensure_object(dict)
    ctx.obj.update(repo_dir=repo_dir, verbose=verbose, registry=None)
    if ctx.invoked_subcommand is None:
        click.echo(ctx.get_help())
        ctx.exit(1)
    # Defer registry load + run-log setup until we know a real subcommand fired.
    _setup_run_log(repo_dir, ["loadout"] + sys.argv[1:])
    ctx.obj["registry"] = _load_tool_registry(repo_dir)


@cli.command(name="install", short_help="Install packages.")
@_selection_options
@_install_options
@_dest_dir_option
@click.pass_context
def cli_install(
    ctx, packages, skip, no_deps, force, dry_run, no_backup, install_follows_symlinks, post_install_hook, dest_dir
):
    """Install the named packages or @groups.

    Examples:

      loadout install gvim

      loadout install @core-cli vim nvim

      loadout install @engineering-loadout --skip @fonts-all

      loadout install @engineering-loadout --dest-dir /opt/loadout/2026.06.11

    Environment:

      LOADOUT_CFG_SHARED_PREFIX -- set in the environment of an `@envs` install
      to the local-root of a separately-installed shared/read-only tree (the dir
      holding bin/share/lib64, e.g. /foo/bar/local for `@shared --dest-dir
      /foo/bar`). It is baked into the user's config.sh so PATH, TERMINFO_DIRS,
      and the tealdeer cache resolve against it. Example:

      LOADOUT_CFG_SHARED_PREFIX=/foo/bar/local loadout install @envs
    """
    args = _ctx_args(
        ctx,
        packages=list(packages),
        skip=skip,
        no_deps=no_deps,
        force=force,
        dry_run=dry_run,
        no_backup=no_backup,
        install_follows_symlinks=install_follows_symlinks,
        post_install_hook=list(post_install_hook),
        dest_dir=dest_dir,
    )
    ctx.exit(cmd_install_v2(args, ctx.obj["registry"], ctx.obj["repo_dir"], _resolve_home(dest_dir)))


@cli.command(name="reinstall", short_help="Re-install packages (alias of install today).")
@_selection_options
@_install_options
@_dest_dir_option
@click.pass_context
def cli_reinstall(
    ctx, packages, skip, no_deps, force, dry_run, no_backup, install_follows_symlinks, post_install_hook, dest_dir
):
    """Re-install named packages. Today identical to `install`; will diverge once
    persisted install state lands."""
    ctx.invoke(
        cli_install,
        packages=packages,
        skip=skip,
        no_deps=no_deps,
        force=force,
        dry_run=dry_run,
        no_backup=no_backup,
        install_follows_symlinks=install_follows_symlinks,
        post_install_hook=post_install_hook,
        dest_dir=dest_dir,
    )


@cli.command(name="upgrade", aliases=["update"], short_help="Targeted re-extract of named packages.")
@_selection_options
@_install_options
@_dest_dir_option
@click.pass_context
def cli_upgrade(
    ctx, packages, skip, no_deps, force, dry_run, no_backup, install_follows_symlinks, post_install_hook, dest_dir
):
    """Re-extract the named packages from the current checkout.

    `update` is an alias for this command.
    """
    ctx.invoke(
        cli_install,
        packages=packages,
        skip=skip,
        no_deps=no_deps,
        force=force,
        dry_run=dry_run,
        no_backup=no_backup,
        install_follows_symlinks=install_follows_symlinks,
        post_install_hook=post_install_hook,
        dest_dir=dest_dir,
    )


@cli.command(name="list", short_help="Show all packages (or groups with --groups).")
@click.option("--groups", "list_groups", is_flag=True, help="Show groups instead of packages.")
@click.option("--tag", default=None, help="Filter packages by tag.")
@click.option(
    "--installed",
    is_flag=True,
    help="Stub: warns and falls back to the normal listing (no persisted state yet).",
)
@click.pass_context
def cli_list(ctx, list_groups, tag, installed):
    """Print the package or @group table."""
    args = _ctx_args(ctx, list_groups=list_groups, tag=tag, installed=installed)
    ctx.exit(cmd_list(args, ctx.obj["registry"]))


@cli.command(name="search", short_help="Search packages by name, description, tags.")
@click.argument("pattern")
@click.option("--tag", default=None, help="Filter results by tag.")
@click.pass_context
def cli_search(ctx, pattern, tag):
    """Case-insensitive substring search across package name, description, and tags."""
    args = _ctx_args(ctx, pattern=pattern, tag=tag)
    ctx.exit(cmd_search(args, ctx.obj["registry"]))


@cli.command(name="info", aliases=["describe"], short_help="Show package metadata.")
@click.argument("name")
@click.pass_context
def cli_info(ctx, name):
    """Show full metadata for a package or @group: kind, version, deps, reverse-deps,
    file lists, group memberships."""
    args = _ctx_args(ctx, name=name)
    ctx.exit(cmd_info(args, ctx.obj["registry"]))


@cli.command(name="resolve", short_help="Dry resolver: print the resolved package set.")
@_selection_options
@click.pass_context
def cli_resolve(ctx, packages, skip, no_deps, force):
    """Resolve the named packages/@groups and print the result grouped by kind."""
    args = _ctx_args(ctx, packages=list(packages), skip=skip, no_deps=no_deps, force=force)
    ctx.exit(cmd_resolve_v2(args, ctx.obj["registry"]))


@cli.command(name="doctor", short_help="Platform + registry sanity check.")
@click.pass_context
def cli_doctor(ctx):
    """Verify platform detection, registry integrity, archive presence, and env-handler
    coverage. Exits 0 on a healthy tree; exits 2 if any check fails."""
    args = _ctx_args(ctx)
    ctx.exit(cmd_doctor(args, ctx.obj["registry"], ctx.obj["repo_dir"]))


@cli.group(name="snapshot", cls=click.RichGroup, short_help="Manage destination snapshots.")
def cli_snapshot():
    """Manage snapshots of the destination directory (~/loadout_backups)."""


@cli_snapshot.command(name="create", short_help="Snapshot the destination without installing.")
@click.argument("name", required=False, default=None)
@_dest_dir_option
@click.pass_context
def cli_snapshot_create(ctx, name, dest_dir):
    """Take a snapshot of the destination directory without performing an install."""
    args = _ctx_args(ctx, snapshot_cmd="create", name=name, dest_dir=dest_dir)
    ctx.exit(cmd_snapshot(args, ctx.obj["repo_dir"], _resolve_home(dest_dir)))


@cli_snapshot.command(name="restore", short_help="Restore a snapshot.")
@click.argument("path")
@_dest_dir_option
@click.pass_context
def cli_snapshot_restore(ctx, path, dest_dir):
    """Restore a snapshot from a directory or a .tar.bz2 archive."""
    args = _ctx_args(ctx, snapshot_cmd="restore", path=path, dest_dir=dest_dir)
    ctx.exit(cmd_snapshot(args, ctx.obj["repo_dir"], _resolve_home(dest_dir)))


@cli_snapshot.command(name="list", short_help="List existing snapshots.")
@_dest_dir_option
@click.pass_context
def cli_snapshot_list(ctx, dest_dir):
    """List existing snapshots under <dest>/loadout_backups, newest first."""
    args = _ctx_args(ctx, snapshot_cmd="list", dest_dir=dest_dir)
    ctx.exit(cmd_snapshot(args, ctx.obj["repo_dir"], _resolve_home(dest_dir)))


@cli.command(name="clean", short_help="Remove stale /tmp/loadout* state.")
@click.option("--logs", is_flag=True, help="Delete /tmp/loadout.<user>.log.")
@click.option(
    "--pending",
    is_flag=True,
    help="Delete /tmp/loadout-pending-<user>/ (only when the pending-ops daemon is dead).",
)
@click.option("--all", "clean_all", is_flag=True, help="Delete logs + pending + stale loadout-* tempdirs.")
@click.pass_context
def cli_clean(ctx, logs, pending, clean_all):
    """Remove stale /tmp/loadout* state. Refuses to touch ~/loadout_backups/ and
    refuses to clean /tmp/loadout-pending-<user>/ while the pending-ops daemon is alive."""
    args = _ctx_args(ctx, logs=logs, pending=pending, clean_all=clean_all)
    ctx.exit(cmd_clean(args))


# Bash completion template. Placeholders __PKGS__/__GROUPS__/__TAGS__ are filled
# from the registry by _render_bash_completion. The script is self-contained: it
# computes cur/prev itself rather than depending on bash-completion's
# _init_completion, and only borrows _filedir when that library happens to be
# loaded (falling back to compgen otherwise). Meant to be saved statically and
# sourced at startup -- not eval'd live -- so it must be regenerated when the
# CLI verbs/flags or the package registry change.
_BASH_COMPLETION_TEMPLATE = """\
# loadout(1) bash completion -- GENERATED by `loadout completion bash`.
# Static snapshot of subcommands, flags, and registry names. Do not hand-edit;
# regenerate with `loadout completion bash > loadout.bash` when the CLI verbs,
# flags, or the package registry change.

__loadout_filedir() {
    if declare -F _filedir >/dev/null 2>&1; then
        _filedir
    else
        mapfile -t COMPREPLY < <(compgen -f -- "$cur")
    fi
}

_loadout_complete() {
    local cur prev words cword i
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    words=("${COMP_WORDS[@]}")
    cword=$COMP_CWORD

    local verbs="install reinstall upgrade update list search info describe resolve doctor snapshot clean completion"
    local pkgs="__PKGS__"
    local groups="__GROUPS__"
    local tags="__TAGS__"

    # Option that takes an argument -> complete the argument, not a new word.
    case "$prev" in
        --skip)
            mapfile -t COMPREPLY < <(compgen -W "$pkgs $groups" -- "$cur"); return ;;
        --tag)
            mapfile -t COMPREPLY < <(compgen -W "$tags" -- "$cur"); return ;;
        --dest-dir|--post-install-hook)
            __loadout_filedir; return ;;
        --install-follows-symlinks)
            mapfile -t COMPREPLY < <(compgen -W "yes no auto" -- "$cur"); return ;;
    esac

    # Locate the subcommand: first non-dash word after argv[0].
    local cmd=""
    for (( i=1; i < cword; i++ )); do
        case "${words[i]}" in
            -*) ;;
            *) cmd="${words[i]}"; break ;;
        esac
    done

    if [[ -z "$cmd" ]]; then
        if [[ "$cur" == -* ]]; then
            mapfile -t COMPREPLY < <(compgen -W "-h --help -V --version --verbose" -- "$cur")
        else
            mapfile -t COMPREPLY < <(compgen -W "$verbs" -- "$cur")
        fi
        return
    fi

    case "$cmd" in
        install|reinstall|upgrade|update)
            if [[ "$cur" == -* ]]; then
                mapfile -t COMPREPLY < <(compgen -W "--skip --no-deps --force --dry-run --no-backup --post-install-hook --install-follows-symlinks --dest-dir -h --help" -- "$cur")
            else
                mapfile -t COMPREPLY < <(compgen -W "$pkgs $groups" -- "$cur")
            fi
            ;;
        resolve)
            if [[ "$cur" == -* ]]; then
                mapfile -t COMPREPLY < <(compgen -W "--skip --no-deps --force -h --help" -- "$cur")
            else
                mapfile -t COMPREPLY < <(compgen -W "$pkgs $groups" -- "$cur")
            fi
            ;;
        info|describe)
            mapfile -t COMPREPLY < <(compgen -W "$pkgs $groups -h --help" -- "$cur")
            ;;
        list)
            mapfile -t COMPREPLY < <(compgen -W "--groups --tag --installed -h --help" -- "$cur")
            ;;
        search)
            [[ "$cur" == -* ]] && mapfile -t COMPREPLY < <(compgen -W "--tag -h --help" -- "$cur")
            ;;
        doctor)
            mapfile -t COMPREPLY < <(compgen -W "-h --help" -- "$cur")
            ;;
        clean)
            mapfile -t COMPREPLY < <(compgen -W "--logs --pending --all -h --help" -- "$cur")
            ;;
        completion)
            mapfile -t COMPREPLY < <(compgen -W "bash -h --help" -- "$cur")
            ;;
        snapshot)
            local sub="" j
            for (( j=i+1; j < cword; j++ )); do
                case "${words[j]}" in
                    -*) ;;
                    *) sub="${words[j]}"; break ;;
                esac
            done
            if [[ -z "$sub" ]]; then
                if [[ "$cur" == -* ]]; then
                    mapfile -t COMPREPLY < <(compgen -W "-h --help" -- "$cur")
                else
                    mapfile -t COMPREPLY < <(compgen -W "create restore list" -- "$cur")
                fi
            elif [[ "$sub" == "restore" && "$cur" != -* ]]; then
                __loadout_filedir
            else
                mapfile -t COMPREPLY < <(compgen -W "--dest-dir -h --help" -- "$cur")
            fi
            ;;
    esac
}
complete -F _loadout_complete loadout
complete -F _loadout_complete ./loadout
"""


def _render_bash_completion(registry):
    """Build the static bash completion script with registry names baked in."""
    pkgs = sorted(n for n, e in registry.items() if not n.startswith("@") and e.get("kind") != "group")
    groups = sorted(n for n in registry if n.startswith("@"))
    # Synthetic groups expand at runtime (not registry keys) but are valid CLI names.
    all_groups = sorted(set(groups) | set(_SYNTHETIC_GROUPS) | {"all"})
    tags = sorted({t for e in registry.values() for t in e.get("tags", [])})
    return (
        _BASH_COMPLETION_TEMPLATE.replace("__PKGS__", " ".join(pkgs))
        .replace("__GROUPS__", " ".join(all_groups))
        .replace("__TAGS__", " ".join(tags))
    )


@cli.command(name="completion", short_help="Emit a static shell completion script.")
@click.argument("shell", type=click.Choice(["bash"]))
@click.pass_context
def cli_completion(ctx, shell):
    """Print a shell completion script to stdout (currently bash only).

    The output is a static snapshot meant to be saved to a file and sourced at
    shell startup (e.g. bash/global/completions/loadout.bash) -- not eval'd live.
    Regenerate it when the CLI verbs/flags or the package registry change.
    """
    click.echo(_render_bash_completion(ctx.obj["registry"]), nl=False)
    ctx.exit(0)


def main(argv):
    signal.signal(signal.SIGINT, _sigint_handler)
    # Guarantee the terminal cursor is restored on exit -- Rich transient progress
    # bars can leave it hidden on remote terminals (see _show_cursor docstring).
    atexit.register(_show_cursor)

    try:
        rc = cli.main(args=list(argv), prog_name="loadout", standalone_mode=False)
    except click.exceptions.UsageError as exc:
        exc.show()
        return exc.exit_code or 2
    except click.exceptions.Abort:
        return 130
    except click.exceptions.ClickException as exc:
        exc.show()
        return exc.exit_code or 1
    except SystemExit as exc:
        return exc.code if isinstance(exc.code, int) else 1
    # In non-standalone mode, click returns the exit code from ctx.exit(...);
    # individual command callbacks return None (their work is the side effect),
    # in which case 0 is success.
    return rc if isinstance(rc, int) else 0


if __name__ == "__main__":
    _rc = 1
    try:
        _rc = main(sys.argv[1:])
    except SystemExit as _se:
        _rc = _se.code if isinstance(_se.code, int) else 1
        _close_run_log(_rc)
        raise
    except BaseException:
        _close_run_log("exception")
        raise
    _close_run_log(_rc)
    sys.exit(_rc)
