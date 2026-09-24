#!/usr/bin/env python3.14
"""Pinned pipeline security tools: syft + osv-scanner (fetch and verify).

gitleaks is committed under build/gitleaks/ because the T1 secret scan must
work offline. syft (SBOM) and osv-scanner (vulnerability scan) are large static
binaries used by the release gates, so they are fetched on demand into the
per-user cache and verified against the pins below -- URL and digests as
published by the GitHub releases API when the pin was reviewed. Both are
CGO_ENABLED=0 ("statically linked") and were run on a stock almalinux:8.10
container with --network=none before being pinned.

These are pipeline tools. Nothing here enters payload/, packages.json, or a
release tarball (docs/SECURITY.md section 5). Bumping a pin means: fetch the
new release, verify the asset digest against the API, run the binary in the
EL8 container with --network=none, then update both digests here.

Usage:
    build/security_tools.py list
    build/security_tools.py check        # validate the pin table (T1 gate; no network)
    build/security_tools.py path syft    # fetch if needed, print the cached path
"""

import glob
import hashlib
import os
import shutil
import stat
import sys
import tarfile
import tempfile
import urllib.request

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CACHE = os.path.join(
    os.environ.get("XDG_CACHE_HOME") or os.path.join(os.path.expanduser("~"), ".cache"),
    "engineering-loadout",
    "security-tools",
)

PINS = {
    "syft": {
        "version": "1.52.0",
        "url": "https://github.com/anchore/syft/releases/download/v1.52.0/syft_1.52.0_linux_amd64.tar.gz",
        "asset_sha256": "caeedb81fb0491615f1ebd1761e4145d41ee86dd2cc7bf80669f9f5ad9d6133d",
        "kind": "tar.gz",
        "member": "syft",
        "member_sha256": "15a52d0122953081d16e6695f48055216a4de293bb005948663bb739a63880f9",
    },
    "osv-scanner": {
        "version": "2.6.0",
        "url": "https://github.com/google/osv-scanner/releases/download/v2.6.0/osv-scanner_linux_amd64",
        "asset_sha256": "ca69b3d3cd08f889a49dc0a383122f71cc528b83803671df5fd874d97485b108",
        "kind": "binary",
        "member": "osv-scanner",
        "member_sha256": "ca69b3d3cd08f889a49dc0a383122f71cc528b83803671df5fd874d97485b108",
    },
}


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def payload_platform_dir():
    """The active payload platform dir (the one carrying the wheelhouse)."""
    candidates = sorted(glob.glob(os.path.join(REPO, "payload", "*", "wheels")))
    if not candidates:
        raise RuntimeError("no payload/*/wheels directory found")
    return os.path.dirname(candidates[0])


def _download(url, dest):
    req = urllib.request.Request(url, headers={"User-Agent": "loadout-security-tools/1.0"})
    with urllib.request.urlopen(req, timeout=300) as resp, open(dest, "wb") as fh:
        shutil.copyfileobj(resp, fh, length=1024 * 1024)


def _fetch(name, pin):
    dest_dir = os.path.join(CACHE, f"{name}", pin["version"])
    os.makedirs(dest_dir, exist_ok=True)
    dest = os.path.join(dest_dir, pin["member"])
    print("Fetching {} {} ...".format(name, pin["version"]), flush=True)
    with tempfile.TemporaryDirectory(prefix=".loadout-security-tool-", dir=CACHE) as tmp:
        asset = os.path.join(tmp, "asset")
        _download(pin["url"], asset)
        got = sha256_file(asset)
        if got != pin["asset_sha256"]:
            raise RuntimeError("sha256 mismatch for {}: pinned {}, got {}".format(pin["url"], pin["asset_sha256"], got))
        if pin["kind"] == "tar.gz":
            with tarfile.open(asset, "r:gz") as tf:
                member = tf.getmember(pin["member"])
                if not member.isfile():
                    raise RuntimeError("{} in {} is not a regular file".format(pin["member"], pin["url"]))
                src = tf.extractfile(member)
                with open(dest, "wb") as fh:
                    shutil.copyfileobj(src, fh)
        else:
            shutil.copyfile(asset, dest)
    os.chmod(dest, stat.S_IRWXU | stat.S_IRGRP | stat.S_IXGRP | stat.S_IROTH | stat.S_IXOTH)
    got = sha256_file(dest)
    if got != pin["member_sha256"]:
        os.unlink(dest)
        raise RuntimeError("extracted {} sha256 mismatch: pinned {}, got {}".format(name, pin["member_sha256"], got))
    return dest


def tool_path(name):
    """Cached path to a pinned tool, fetching + verifying it when absent."""
    pin = PINS[name]
    dest = os.path.join(CACHE, name, pin["version"], pin["member"])
    if os.path.isfile(dest) and sha256_file(dest) == pin["member_sha256"]:
        return dest
    return _fetch(name, pin)


def check_pins():
    """Return a list of problems with the pin table (empty == valid). No network."""
    problems = []
    for name, pin in PINS.items():
        for key in ("version", "url", "asset_sha256", "kind", "member", "member_sha256"):
            if not pin.get(key):
                problems.append(f"{name}: missing {key}")
        if not pin["url"].startswith("https://"):
            problems.append(f"{name}: url is not https")
        for key in ("asset_sha256", "member_sha256"):
            digest = pin.get(key, "")
            if len(digest) != 64 or any(c not in "0123456789abcdef" for c in digest):
                problems.append(f"{name}: {key} is not a lowercase sha256")
        if pin.get("version") not in pin.get("url", ""):
            problems.append("{}: version {} does not appear in the url".format(name, pin["version"]))
    return problems


def main(argv):
    if not argv or argv[0] in ("-h", "--help"):
        print(__doc__.strip())
        return 0
    cmd = argv[0]
    if cmd == "list":
        for name, pin in sorted(PINS.items()):
            print(
                "{} {} {}\n    asset  {}\n    member {}".format(
                    name, pin["version"], pin["url"], pin["asset_sha256"], pin["member_sha256"]
                )
            )
        return 0
    if cmd == "check":
        problems = check_pins()
        if problems:
            for p in problems:
                print(f"FAIL: {p}")
            return 1
        print(f"security-tools pins OK ({len(PINS)} tools)")
        return 0
    if cmd == "path" and len(argv) == 2:
        name = argv[1]
        if name not in PINS:
            print("ERROR: unknown tool {!r} (known: {})".format(name, ", ".join(sorted(PINS))), file=sys.stderr)
            return 2
        print(tool_path(name))
        return 0
    print(f"ERROR: unknown command {cmd!r}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
