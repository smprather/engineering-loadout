#!/usr/bin/env python3
"""Build the offline JSON Schema cache that makes `taplo lint` useful air-gapped.

WHY THIS EXISTS. taplo has two independent validation layers. The TOML grammar
is compiled into the binary and always works. JSON Schema validation -- the
layer that knows `[package] nmae = "x"` is a typo in a Cargo.toml -- resolves
schemas from a remote catalog (schemastore.org, taplo.tamasfe.dev). On a farm
node with no route to the internet that layer is simply dead, and taplo exits 0
on a file full of misspelled keys. That is a silent degrade, which is the
failure mode this repo has been bitten by most often.

So the catalog and every schema it names are vendored into the payload.

WHAT IS TRUSTED. Of the ~113 TOML-matching entries in schemastore's catalog,
only 48 are actually hosted by SchemaStore itself; the rest point at ~20
third-party hosts, most of them `raw.githubusercontent.com/<user>/<repo>/master`
URLs that are mutable by definition. Vendoring those would mean adopting 20
more upstreams whose content can change under a fixed URL, and re-downloading
them on every refresh for a diff nobody can review.

The rule here is one trust anchor, matching how `yara-rules` (YARA-Forge) and
`tldr-data` (tldr-pages) are sourced:

  * accept https://www.schemastore.org/... and https://json.schemastore.org/...
  * accept https://raw.githubusercontent.com/SchemaStore/schemastore/... --
    the SAME upstream, just referenced by repo path. This is not a loophole:
    it is where pyproject.toml, uv.toml and hatch.toml live, which are three of
    the most valuable schemas in the set.
  * plus ALLOWLIST below, which today holds exactly one entry, for a tool this
    repo already ships and whose schema it already vendors.

Everything else is skipped and COUNTED, so the exclusion is visible in the
build output rather than being a silent policy.

WHY ABSOLUTE file:// URLS + A RELOCATION TOKEN. taplo requires catalog entries
to carry a `format: uri` URL; a relative path is rejected outright with
`data did not match any variant of untagged enum SchemaCatalog`. An absolute
path cannot be baked at build time either, because the install prefix varies
($HOME/.local, a --dest-dir staging tree, a shared read-only tree). So the
catalog ships with the repo's standard relocation token and the installer
rewrites it to the deployed local root -- the same mechanism `modules` and
`verilator` use. See relocate_token / relocate_root in payload/packages.json.

Usage:
    build/taplo/fetch-schemas.py                 # write the payload archive
    build/taplo/fetch-schemas.py --dry-run       # report what would be fetched
    build/taplo/fetch-schemas.py --out /tmp/x    # stage somewhere else

Normally driven by `./build/update taplo-schemas`, which also re-runs
strip-all-elf-binaries (to normalise the tar) and gen-content-manifest.
"""

import argparse
import concurrent.futures as futures
import hashlib
import json
import os
import re
import shutil
import sys
import tarfile
import tempfile
import urllib.error
import urllib.request

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

CATALOG_URL = "https://www.schemastore.org/api/json/catalog.json"

# Must match packages.json -> taplo-schemas -> relocate_token. The installer
# replaces it with the deployed local root (e.g. /home/u/.local), so the shipped
# URL `file:///__LOADOUT_RELOC_ROOT__/share/...` becomes `file:///home/u/.local/share/...`.
RELOC_TOKEN = "/__LOADOUT_RELOC_ROOT__"
INSTALL_REL = "share/taplo/schemas"

TRUSTED_PREFIXES = (
    "https://www.schemastore.org/",
    "https://json.schemastore.org/",
    "https://raw.githubusercontent.com/SchemaStore/schemastore/",
)

# Non-SchemaStore URLs admitted by name, with the reason. Keep this list short
# and justified -- every entry is another upstream this repo has to trust.
ALLOWLIST = {
    # This repo bundles starship AND already vendors this exact schema at
    # envs/starship/config-schema.json for editor completions on Linux. Taking
    # it here is not a new trust relationship, and starship.toml is a file
    # every loadout user actually has.
    "https://starship.rs/config-schema.json": "starship is bundled by this repo",
}

USER_AGENT = "engineering-loadout-taplo-schema-fetch/1"
TIMEOUT_S = 60


def fetch(url):
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=TIMEOUT_S) as resp:
        return resp.read()


def is_toml_entry(entry):
    """True when the catalog entry claims at least one *.toml file."""
    for pattern in entry.get("fileMatch") or []:
        if str(pattern).lower().endswith(".toml"):
            return True
    return False


def trusted(url):
    if url in ALLOWLIST:
        return True
    return url.startswith(TRUSTED_PREFIXES)


def slug(entry, url, taken):
    """A stable, filesystem-safe basename for the schema file.

    Derived from the catalog NAME rather than the URL: two SchemaStore entries
    can share a basename across the www/ and raw.githubusercontent/ forms, and
    a collision would silently make one schema shadow the other.
    """
    base = re.sub(r"[^a-z0-9]+", "-", entry.get("name", "").lower()).strip("-")
    if not base:
        base = re.sub(r"[^a-z0-9]+", "-", os.path.basename(url).lower()).strip("-") or "schema"
    candidate = f"{base}.json"
    n = 2
    while candidate in taken:
        candidate = f"{base}-{n}.json"
        n += 1
    taken.add(candidate)
    return candidate


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--out", help="stage directory (default: a temp dir); archive still goes to payload/")
    ap.add_argument("--archive", help="output archive path (default: payload/<platform>/runtime/taplo-schemas.tar.bz2)")
    ap.add_argument("--catalog-url", default=CATALOG_URL)
    ap.add_argument("--jobs", type=int, default=8)
    ap.add_argument("--dry-run", action="store_true", help="report the selection; download nothing")
    args = ap.parse_args()

    archive = args.archive
    if not archive:
        platform_dirs = sorted(
            d
            for d in os.listdir(os.path.join(REPO, "payload"))
            if os.path.isdir(os.path.join(REPO, "payload", d, "runtime"))
        )
        if len(platform_dirs) != 1:
            sys.exit(f"cannot pick a platform dir automatically (found {platform_dirs!r}); pass --archive explicitly")
        archive = os.path.join(REPO, "payload", platform_dirs[0], "runtime", "taplo-schemas.tar.bz2")

    print(f"==> Fetching catalog {args.catalog_url}")
    catalog = json.loads(fetch(args.catalog_url))
    entries = [e for e in catalog.get("schemas", []) if is_toml_entry(e) and e.get("url")]
    keep = [e for e in entries if trusted(e["url"])]
    skipped = [e for e in entries if not trusted(e["url"])]

    hosts = {}
    for e in skipped:
        host = e["url"].split("/")[2] if "//" in e["url"] else e["url"]
        hosts[host] = hosts.get(host, 0) + 1
    print(f"  {len(entries)} TOML-matching entries; keeping {len(keep)}, skipping {len(skipped)} untrusted")
    for host, count in sorted(hosts.items(), key=lambda kv: -kv[1]):
        print(f"    skip {count:3d}  {host}")

    if args.dry_run:
        for e in sorted(keep, key=lambda x: x.get("name", "")):
            print(f"  keep  {e.get('name')}  {e.get('fileMatch')}")
        return 0

    stage_tmp = None
    if args.out:
        stage = args.out
        os.makedirs(stage, exist_ok=True)
    else:
        stage_tmp = tempfile.mkdtemp(prefix="taplo-schemas-")
        stage = stage_tmp

    try:
        return build(keep, stage, archive, args.jobs)
    finally:
        if stage_tmp:
            shutil.rmtree(stage_tmp, ignore_errors=True)


def build(keep, stage, archive, jobs):
    schemas_dir = os.path.join(stage, "schemas")
    # Rebuild from scratch: a schema dropped upstream must disappear here too,
    # or the catalog and the directory drift apart.
    shutil.rmtree(schemas_dir, ignore_errors=True)
    os.makedirs(schemas_dir)

    taken = set()
    planned = [(e, slug(e, e["url"], taken)) for e in sorted(keep, key=lambda x: x.get("name", ""))]

    print(f"==> Downloading {len(planned)} schemas ...")
    results = {}
    failures = []
    with futures.ThreadPoolExecutor(max_workers=jobs) as pool:
        pending = {pool.submit(fetch, e["url"]): (e, name) for e, name in planned}
        for fut in futures.as_completed(pending):
            entry, name = pending[fut]
            try:
                body = fut.result()
            except (urllib.error.URLError, OSError, TimeoutError) as exc:
                failures.append((entry.get("name"), entry["url"], str(exc)))
                continue
            try:
                json.loads(body)
            except ValueError as exc:
                # A login page or an error blob would otherwise be vendored as a
                # "schema" and only surface as a confusing taplo error later.
                failures.append((entry.get("name"), entry["url"], f"not JSON: {exc}"))
                continue
            results[name] = (entry, body)

    if failures:
        print(f"  {len(failures)} schema(s) could not be fetched:")
        for name, url, why in failures:
            print(f"    FAIL {name}  {url}\n         {why}")
    if not results:
        print("ERROR: no schemas fetched; refusing to write an empty cache", file=sys.stderr)
        return 1
    # A handful of upstream URLs going stale is normal churn; half of them
    # vanishing means something is wrong with the run (proxy, DNS, rate limit)
    # and the cache should not be silently gutted.
    if len(results) < len(planned) * 0.8:
        print(
            f"ERROR: only {len(results)}/{len(planned)} schemas fetched -- "
            "too many failures to trust this as a refresh",
            file=sys.stderr,
        )
        return 1

    schemas = []
    sources = []
    for name in sorted(results):
        entry, body = results[name]
        with open(os.path.join(schemas_dir, name), "wb") as fh:
            fh.write(body)
        schemas.append(
            {
                "name": entry.get("name", name),
                "description": entry.get("description", ""),
                "fileMatch": entry.get("fileMatch", []),
                "url": f"file://{RELOC_TOKEN}/{INSTALL_REL}/schemas/{name}",
            }
        )
        sources.append((name, entry["url"], hashlib.sha256(body).hexdigest(), len(body)))

    catalog_out = {
        "$schema": "https://json.schemastore.org/schema-catalog.json",
        "version": 1,
        "schemas": schemas,
    }
    with open(os.path.join(stage, "catalog.json"), "w") as fh:
        json.dump(catalog_out, fh, indent=1, sort_keys=False)
        fh.write("\n")

    # Provenance record: which upstream URL each vendored file came from, and
    # its hash. Ships inside the archive so it is auditable on a deployed node,
    # not only in the build tree.
    with open(os.path.join(stage, "SOURCES.tsv"), "w") as fh:
        fh.write("# file\tupstream_url\tsha256\tbytes\n")
        for row in sources:
            fh.write("\t".join(str(c) for c in row) + "\n")

    os.makedirs(os.path.dirname(archive), exist_ok=True)
    print(f"==> Writing {archive}")
    with tarfile.open(archive, "w:bz2") as tf:
        for rel in ("catalog.json", "SOURCES.tsv"):
            tf.add(os.path.join(stage, rel), arcname=f"./{INSTALL_REL}/{rel}")
        for name in sorted(os.listdir(schemas_dir)):
            tf.add(
                os.path.join(schemas_dir, name),
                arcname=f"./{INSTALL_REL}/schemas/{name}",
            )

    total = sum(row[3] for row in sources)
    print(
        f"Done: {len(sources)} schemas ({total // 1024} KiB raw) -> {os.path.getsize(archive) // 1024} KiB compressed"
    )
    verify(archive)
    return 0


def verify(archive):
    """Prove the shipped catalog carries the token and nothing else does.

    The installer hard-fails if the token is absent ("relocation token was not
    found"), so catching it here turns a broken release gate into a broken
    build, which is the cheaper place to find it.
    """
    with tarfile.open(archive, "r:bz2") as tf:
        names = tf.getnames()
        member = f"./{INSTALL_REL}/catalog.json"
        if member not in names:
            sys.exit(f"BUG: {member} missing from {archive}")
        body = tf.extractfile(member).read().decode()
    if RELOC_TOKEN not in body:
        sys.exit(f"BUG: relocation token {RELOC_TOKEN} absent from the shipped catalog")
    doc = json.loads(body)
    for entry in doc["schemas"]:
        if not entry["url"].startswith(f"file://{RELOC_TOKEN}/"):
            sys.exit(f"BUG: catalog entry {entry['name']!r} has a non-relocatable url: {entry['url']}")
    print(f"  verified: {len(doc['schemas'])} catalog entries, all relocatable file:// URLs")


if __name__ == "__main__":
    sys.exit(main())
