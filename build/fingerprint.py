#!/usr/bin/env python3.14
"""Content fingerprinting shared by the release gates and the test suite.

Two modes, same output shape:

  --fast   mtime+size sidecar fingerprint. ~2 s for the whole payload tree
           (vs ~40 s for byte hashing). Correct for "did anything change
           since the last run" -- the sidecar records the previous state, so
           a touched-but-identical file costs one needless re-run, never a
           false green. Use for test-result caches and the smoke install
           tree cache.
  --exact  byte-hash fingerprint (sha256 of every file, folded in sorted
           order). ~40 s. Use for anything that must not trust mtimes:
           release smoke/scan caches, content verification.

Both fold in the platform fingerprint (uname + glibc) so a cache recorded
on one host never validates on another.

Usage:
  build/fingerprint.py --fast [--roots payload loadout loadout_main.py ...]
  build/fingerprint.py --exact [--roots ...]
  build/fingerprint.py --fast --check <sidecar>   # exit 0 if unchanged
  build/fingerprint.py --fast --write <sidecar>   # record current state
"""

import argparse
import concurrent.futures
import hashlib
import json
import os
import subprocess
import sys

SCHEMA = 1


def _sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        while True:
            chunk = fh.read(1 << 20)
            if not chunk:
                break
            h.update(chunk)
    return h.hexdigest()


def _iter_files(roots):
    for root in roots:
        if os.path.isfile(root):
            yield root
            continue
        for dirpath, dirnames, filenames in os.walk(root):
            dirnames.sort()
            for name in sorted(filenames):
                full = os.path.join(dirpath, name)
                if os.path.isfile(full) and not os.path.islink(full):
                    yield full


def _platform_fingerprint():
    uname = subprocess.run(["uname", "-s", "-m"], capture_output=True, text=True)
    glibc = subprocess.run(["getconf", "GNU_LIBC_VERSION"], capture_output=True, text=True)
    return {
        "uname": uname.stdout.strip(),
        "glibc": glibc.stdout.strip(),
    }


def _fold(entries):
    h = hashlib.sha256()
    for rel, digest in sorted(entries):
        h.update(b"file\0")
        h.update(rel.encode("utf-8", "surrogateescape"))
        h.update(b"\0")
        h.update(digest.encode("ascii"))
        h.update(b"\0")
    return h.hexdigest()


def _mem_available_mb():
    """MemAvailable from /proc/meminfo, or None when unreadable."""
    try:
        with open("/proc/meminfo") as fh:
            for line in fh:
                if line.startswith("MemAvailable:"):
                    return int(line.split()[1]) // 1024
    except OSError:
        pass
    return None


def _hash_workers():
    """Hash workers scaled to free memory: each worker reads a 1 MB chunk at
    a time, but the page cache pressure of ~3 GB of concurrent reads on a
    memory-tight box can still push the OOM killer. Cap at 8, and drop to 2
    when free memory is low."""
    mem = _mem_available_mb()
    if mem is None:
        return 8
    if mem < 2048:
        return 2
    if mem < 6144:
        return 4
    return 8


def fingerprint(roots, exact):
    files = sorted(_iter_files(roots))
    if exact:
        digests = {}
        with concurrent.futures.ThreadPoolExecutor(max_workers=_hash_workers()) as ex:
            futs = {ex.submit(_sha256_file, f): f for f in files}
            for fut in concurrent.futures.as_completed(futs):
                digests[futs[fut]] = fut.result()
        entries = [(f, digests[f]) for f in files]
    else:
        entries = []
        for f in files:
            st = os.stat(f)
            entries.append((f, f"{st.st_mtime_ns}:{st.st_size}"))
    return {
        "schema": SCHEMA,
        "mode": "exact" if exact else "fast",
        "platform": _platform_fingerprint(),
        "files": len(files),
        "sha256": _fold(entries),
    }


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--fast", action="store_true", help="mtime+size fingerprint (seconds)")
    ap.add_argument("--exact", action="store_true", help="byte-hash fingerprint (~40 s)")
    ap.add_argument("--roots", nargs="+", required=True, help="files/dirs to fingerprint")
    ap.add_argument("--check", metavar="SIDECAR", help="exit 0 if sidecar matches current state")
    ap.add_argument("--write", metavar="SIDECAR", help="record current state to sidecar")
    args = ap.parse_args()

    if args.fast == args.exact:
        ap.error("exactly one of --fast / --exact is required")
    data = fingerprint(args.roots, exact=args.exact)

    if args.check:
        try:
            with open(args.check) as fh:
                prev = json.load(fh)
        except OSError:
            sys.exit(1)
        sys.exit(0 if prev == data else 1)

    if args.write:
        os.makedirs(os.path.dirname(args.write) or ".", exist_ok=True)
        with open(args.write, "w") as fh:
            json.dump(data, fh, sort_keys=True, indent=2)
            fh.write("\n")

    print(json.dumps(data, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
