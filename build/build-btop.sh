#!/usr/bin/env python3.14
"""
Pack the btop theme set and the theme-tour helper into the payload.

WHY THIS SCRIPT EXISTS. Two gaps, both silent:

1. btop's own theme directory lookup is <real binary>/../share/btop/themes,
   then /usr/local/share/btop/themes, then /usr/share/btop/themes
   (src/btop.cpp, v1.4.7). The bundled binary was installed at
   <root>/local/bin/btop, so the first candidate resolves to
   <root>/local/share/btop/themes -- which the payload never populated. On a
   farm node with no /usr/share/btop, the only themes left are whatever the
   user hand-downloaded, and btop's Options menu shows a two-entry list
   ("Default"/"TTY") with no error at all. That directory is what this script
   now fills.

2. The theme-tour helper was a personal ~/.local/bin script. Shipping it as
   part of the btop package is what makes `btop-theme-tour` exist on a fresh
   node, and it is the only thing that exercises every shipped theme.

THE WRAPPER QUESTION, DECIDED BY btop's OWN SOURCE. Passing --themes-dir would
have made the bundled directory explicit, but Theme::updateThemes() searches
custom_theme_dir -> user_theme_dir -> theme_dir, i.e. --themes-dir OUTRANKS
~/.config/btop/themes and would HIDE the user's own themes; and because <real
binary>/../share/btop/themes is already one of the defaults, the explicit flag
buys nothing on any host where /proc/self/exe resolves. So there is no wrapper:
bin/btop stays the real ELF. Consequence worth knowing: btop's
`make install`-style /usr/local and /usr candidates still apply underneath, but
they are only reached when the bundle directory is empty, which it is not.

Layout installed by the runtime archive ('archive', 'sentinel', 'install_to' in
the btop registry entry):

    <root>/local/share/btop/themes/*.theme    84 themes, sentinel btop.conf
    <root>/local/bin/btop-theme-tour          script wrapper (bin/*.bz2)

Usage (run from any directory -- nothing here is platform-dependent):
    ./build/build-btop.sh --tag 1.4.7           # (re)pack theme archive + tour
    ./build/build-btop.sh --tag 1.4.7 --check   # verify packed bytes match source

The archive is built with tar's own bzip2 filter. It is NOT passed through
strip-all-elf-binaries' tar rewrite path: there are no ELF files in it, and the
repo's rule for archives with no ELF content is to leave them alone (the
tar-meta manifest entry keeps later runs from repacking them).
"""

import bz2
import os
import subprocess
import sys
import tarfile
import tempfile

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PLATFORM = os.environ.get("LOADOUT_PLATFORM", "el8.x86_64.glibc2p28")
PAYLOAD = os.path.join(REPO, "payload", PLATFORM)
BIN_DIR = os.path.join(PAYLOAD, "bin")
RUNTIME_DIR = os.path.join(PAYLOAD, "runtime")

THEMES_SRC = os.path.join(REPO, "envs", "btop", "themes")
TOUR_SRC = os.path.join(REPO, "build", "btop", "btop-theme-tour")

ARCHIVE = os.path.join(RUNTIME_DIR, "btop-themes.tar.bz2")
TOUR_BZ2 = os.path.join(BIN_DIR, "btop-theme-tour.bz2")

FAILED = 0


def check(name, cond, detail=""):
    global FAILED
    if cond:
        print(f"  PASS  {name}")
    else:
        FAILED += 1
        print(f"  FAIL  {name}  {detail}")


def theme_files():
    names = sorted(n for n in os.listdir(THEMES_SRC) if n.endswith(".theme"))
    return names


def build_archive():
    """tar.bz2 the theme tree, staged so paths are exactly share/btop/themes/*.

    Reproducibility matters more than size here: mtime, uid/gid and owner names
    are normalised, entries are sorted, and the bzip2 block size is pinned, so
    repacking unchanged themes produces byte-identical bytes and does not churn
    .content-manifest on every run.
    """
    names = theme_files()
    if not names:
        print(f"ERROR: no .theme files under {THEMES_SRC}", file=sys.stderr)
        return 1
    stage = tempfile.mkdtemp(prefix=".loadout-btop-themes.", dir=tempfile.gettempdir())
    try:
        root = os.path.join(stage, "share", "btop", "themes")
        os.makedirs(root)
        for n in names:
            src = os.path.join(THEMES_SRC, n)
            dst = os.path.join(root, n)
            with open(src, "rb") as fh_in, open(dst, "wb") as fh_out:
                fh_out.write(fh_in.read())
            os.chmod(dst, 0o644)

        # Two-stage for determinism: a deterministic tar body, then bzip2 with a
        # pinned block size (the CLI default has varied across releases).
        plain = os.path.join(stage, "btop-themes.tar")
        with open(plain, "wb") as fh:
            # filter_ = sort + normalise; format PAX would stamp an mtime into
            # the extended header, so USTAR/GNU-free default is used with an
            # explicit zero mtime instead.
            with tarfile.open(fileobj=fh, mode="w", format=tarfile.GNU_FORMAT) as tf:
                for n in names:
                    path = os.path.join(root, n)
                    info = tf.gettarinfo(path, arcname=f"share/btop/themes/{n}")
                    info.mtime = 0
                    info.uid = info.gid = 0
                    info.uname = info.gname = "root"
                    info.mode = 0o644
                    with open(path, "rb") as fh_in:
                        tf.addfile(info, fh_in)

        with open(plain, "rb") as fh_in, bz2.open(ARCHIVE, "wb", compresslevel=9) as fh_out:
            while True:
                block = fh_in.read(1 << 20)
                if not block:
                    break
                fh_out.write(block)
        os.chmod(ARCHIVE, 0o644)
    finally:
        subprocess.run(["rm", "-rf", stage], check=False)

    installed = sum(os.path.getsize(os.path.join(THEMES_SRC, n)) for n in names)
    print(
        f"  packed: {os.path.relpath(ARCHIVE, REPO)} ({len(names)} themes, {installed} bytes installed, {os.path.getsize(ARCHIVE)} packed)"
    )
    return 0


def build_tour():
    """bzip2 the tour script into bin/. Plain script: no strip, no patchelf."""
    with open(TOUR_SRC, "rb") as fh_in, bz2.open(TOUR_BZ2, "wb") as fh_out:
        fh_out.write(fh_in.read())
    os.chmod(TOUR_BZ2, 0o644)
    print(f"  packed: {os.path.relpath(TOUR_BZ2, REPO)} ({os.path.getsize(TOUR_SRC)} bytes installed)")
    return 0


def verify():
    names = theme_files()

    check(f"{os.path.relpath(ARCHIVE, REPO)} exists", os.path.isfile(ARCHIVE), "run without --check first")
    if os.path.isfile(ARCHIVE):
        with tarfile.open(ARCHIVE, "r:bz2") as tf:
            members = {m.name: m for m in tf.getmembers()}

            # build/strip-all-elf-binaries normalises every runtime archive it
            # touches: entry names gain a "./" prefix and explicit directory
            # members appear. Compare on the normalised stem so the check stays
            # valid whether or not the archive has been through that pass yet.
            def norm(name):
                while name.startswith("./"):
                    name = name[2:]
                return name.rstrip("/") if name != "." else ""

            files = {norm(n) for n, m in members.items() if m.isfile()}
            expected = {f"share/btop/themes/{n}" for n in names}
            check(
                "archive holds exactly the shipped themes",
                files == expected,
                f"missing={sorted(expected - files)[:3]} extra={sorted(files - expected)[:3]}",
            )
            drift = []
            for n in names:
                m = members.get(f"share/btop/themes/{n}") or members.get(f"./share/btop/themes/{n}")
                if m is None:
                    continue
                with tf.extractfile(m) as fh:
                    if fh.read() != open(os.path.join(THEMES_SRC, n), "rb").read():
                        drift.append(n)
            check("every theme byte-matches envs/btop/themes/", not drift, f"stale: {drift[:3]}")

    check(f"{os.path.relpath(TOUR_BZ2, REPO)} exists", os.path.isfile(TOUR_BZ2), "run without --check first")
    if os.path.isfile(TOUR_BZ2):
        with open(TOUR_SRC, "rb") as fh:
            check(
                "tour payload matches build/btop/btop-theme-tour",
                fh.read() == bz2.open(TOUR_BZ2, "rb").read(),
                "stale bz2 -- rerun without --check",
            )

    # A config that names a theme the archive does not carry is a silent
    # fallback: btop finds no matching stem and renders Default_theme with no
    # warning at all. This is the only thing that catches that pair drifting.
    cfg = os.path.join(REPO, "envs", "btop", "btop.conf")
    if os.path.isfile(cfg):
        named = ""
        with open(cfg) as fh:
            for line in fh:
                line = line.strip()
                if line.startswith("color_theme"):
                    named = line.split("=", 1)[1].strip().strip('"')
                    break
        stems = [n[: -len(".theme")] for n in names]
        check(
            "env-btop's color_theme exists in the shipped set",
            named in stems or named in ("Default", "TTY"),
            f"btop.conf selects '{named}', which no shipped .theme provides",
        )

    # The registry must point at what was just packed, with a sentinel that a
    # theme-only archive can actually satisfy.
    import json

    with open(os.path.join(REPO, "payload", "packages.json")) as fh:
        entry = json.load(fh)["packages"]["btop"]
    check(
        "registry archive points at btop-themes.tar.bz2",
        entry.get("archive", "").endswith("btop-themes.tar.bz2"),
        entry.get("archive", "<unset>"),
    )
    check(
        "registry install_to is the local root",
        entry.get("install_to") == "~/.local",
        entry.get("install_to", "<unset>"),
    )
    check(
        "registry sentinel is a shipped theme",
        entry.get("sentinel") == "share/btop/themes/default_black.theme",
        entry.get("sentinel", "<unset>"),
    )
    check("registry claims the tour binary", "btop-theme-tour" in entry.get("bins", []), str(entry.get("bins", [])))

    print(f"\n{FAILED} check(s) failed." if FAILED else "\nbuild-btop --check: OK")
    return 1 if FAILED else 0


def main(argv):
    args = list(argv)
    tag = ""
    check_mode = False
    while args:
        a = args.pop(0)
        if a == "--tag":
            if not args:
                print("ERROR: --tag requires a value", file=sys.stderr)
                return 2
            tag = args.pop(0)
        elif a == "--check":
            check_mode = True
        elif a in ("-h", "--help"):
            print(__doc__)
            return 0
        else:
            print(f"unknown option: {a}", file=sys.stderr)
            return 2

    if not tag:
        print(
            "ERROR: --tag is required (the btop release the payload was built from,\n"
            "       e.g. --tag 1.4.7). It must match the version stamped in\n"
            "       payload/packages.json for the 'btop' package.",
            file=sys.stderr,
        )
        return 2
    if tag.startswith("v"):
        tag = tag[1:]

    print(f"==> btop {tag}: theme archive + theme tour" + (" (check)" if check_mode else ""))
    if check_mode:
        return verify()

    os.makedirs(RUNTIME_DIR, exist_ok=True)
    if build_archive() != 0:
        return 1
    if build_tour() != 0:
        return 1

    print()
    print("Next steps:")
    print("  ./build/strip-all-elf-binaries    # regenerates sizes + content manifest")
    print(f"  ./build/build-btop.sh --tag {tag} --check")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
