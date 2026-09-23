#!/bin/bash
# Repack the portable-python payload archive with a REPAIRED libpython .dynsym.
#
# Runs INSIDE the loadout-build container: payload bytes must come from the EL8
# userland (bzip2 1.0.6), not the CachyOS host (bzip2 1.0.8 does not round-trip
# EL8 bytes -- see the Build Machine Mandate in AGENTS.md).
set -euo pipefail

ARCHIVE=/repo/payload/el8.x86_64.glibc2p28/portable-python-3.14.7-el8-clang23.tar.bz2
NAME=portable-python-3.14.7-el8-clang23
WORK=/cache/dynsym-repack

echo "=== bzip2 version in this container ==="
bzip2 --version 2>&1 | head -1

echo
echo "=== unpacking $ARCHIVE ==="
rm -rf "$WORK"
mkdir -p "$WORK"
tar xjf "$ARCHIVE" -C "$WORK"
ls -d "$WORK/$NAME"

LIB="$WORK/$NAME/local/lib/libpython3.14.so.1.0"
ls -l "$LIB"

echo
echo "=== .dynsym check BEFORE ==="
python3 /repo/build/repair-libpython-dynsym --check "$LIB" || true

echo
echo "=== repair ==="
python3 /repo/build/repair-libpython-dynsym "$LIB"

echo
echo "=== .dynsym check AFTER ==="
python3 /repo/build/repair-libpython-dynsym --check "$LIB"

echo
echo "=== the repaired library runs under the tree's own interpreter ==="
# Run against a COPY. Executing the interpreter writes __pycache__/*.pyc into
# the tree, and those would be swept into the repack -- the shipped archive has
# zero __pycache__ entries and must keep it that way (the member-list/sha
# comparison below would catch it, but not creating them is better).
SMOKE=/cache/dynsym-smoke
rm -rf "$SMOKE"
mkdir -p "$SMOKE"
cp -a "$WORK/$NAME" "$SMOKE/"
PYTHONDONTWRITEBYTECODE=1 "$SMOKE/$NAME/local/bin/python3.14" -B \
    -c 'import sys, json, sqlite3, ssl; print("  interp OK", sys.version.split()[0])'
rm -rf "$SMOKE"

echo
echo "=== confirm the tree is byte-identical except libpython3.14.so.1.0 ==="
# Guard against contamination: __pycache__ and similar are created by merely
# RUNNING the interpreter, and anything new here would ship in the archive.
if find "$WORK/$NAME" -name '__pycache__' -o -name '*.pyc' | grep -q .; then
    echo "ERROR: interpreter bytecode appeared in the tree -- refusing to repack" >&2
    find "$WORK/$NAME" -name '__pycache__' -o -name '*.pyc' | head >&2
    exit 1
fi
echo "  no __pycache__/*.pyc contamination"

echo
echo "=== repack (same layout: <name>/... at the archive root) ==="
NEW=/cache/$NAME.tar.bz2
rm -f "$NEW"
tar cjf "$NEW" -C "$WORK" "$NAME"
ls -l "$NEW"

echo
echo "=== verify the repacked archive round-trips and is CLEAN ==="
VERIFY=/cache/dynsym-verify
rm -rf "$VERIFY"
mkdir -p "$VERIFY"
tar xjf "$NEW" -C "$VERIFY"
python3 /repo/build/repair-libpython-dynsym --check "$VERIFY/$NAME/local/lib/libpython3.14.so.1.0"

echo
echo "=== compare the file LIST against the original (must be identical) ==="
tar tjf "$ARCHIVE" | sed 's|/$||' | sort > /cache/list-old.txt
tar tjf "$NEW" | sed 's|/$||' | sort > /cache/list-new.txt
if diff -q /cache/list-old.txt /cache/list-new.txt > /dev/null; then
    echo "  identical member list ($(wc -l < /cache/list-old.txt) entries)"
else
    echo "  ERROR: member lists differ:"
    diff /cache/list-old.txt /cache/list-new.txt | head -20
    exit 1
fi

echo
echo "=== verify only libpython3.14.so.1.0 changed inside ==="
mkdir -p /cache/oldx && rm -rf /cache/oldx && mkdir -p /cache/oldx
tar xjf "$ARCHIVE" -C /cache/oldx
python3 - <<'PYEOF'
import hashlib, os, sys

def digest(root, name):
    out = {}
    base = os.path.join(root, name)
    for dirpath, dirnames, filenames in os.walk(base):
        for f in filenames:
            p = os.path.join(dirpath, f)
            rel = os.path.relpath(p, root)
            if os.path.islink(p):
                out[rel] = "link:" + os.readlink(p)
            else:
                h = hashlib.sha256()
                with open(p, "rb") as fh:
                    for chunk in iter(lambda: fh.read(1 << 20), b""):
                        h.update(chunk)
                out[rel] = h.hexdigest()
    for dirpath, dirnames, filenames in os.walk(base):
        for d in dirnames:
            p = os.path.join(dirpath, d)
            out[os.path.relpath(p, root) + "/"] = "dir"
    return out

old = digest("/cache/oldx", "portable-python-3.14.7-el8-clang23")
new = digest("/cache/dynsym-verify", "portable-python-3.14.7-el8-clang23")

changed = sorted(k for k in set(old) | set(new) if old.get(k) != new.get(k))
print(f"  {len(old)} entries compared; {len(changed)} differ:")
for c in changed:
    print(f"    {c}")
PYEOF
