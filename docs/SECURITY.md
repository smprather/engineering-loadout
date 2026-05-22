# Security — Binary Scanning

All binaries shipped in this repo pass a three-layer scan before each release.

## Steps taken

**1 — Decompress.** All `.bz2` blobs are extracted to a temp directory (raw ELF
files, not compressed archives). Scanning is performed on the decompressed
binaries.

**2 — ClamAV** (updated signature database):

```bash
freshclam                           # pull latest signatures
find pre_built/ -name '*.bz2' -exec sh -c 'bzcat "$1" | clamscan -' _ {} \;
# Or extract all first:
tmpdir=$(mktemp -d)
for f in pre_built/el8.x86_64.glibc2p28/bin/*.bz2; do
    bzcat "$f" > "$tmpdir/$(basename "${f%.bz2}")"
done
clamscan -r "$tmpdir"
rm -rf "$tmpdir"
```

Result: **0 detections** (ClamAV 28005 / 355455+ signatures).

**3 — [YARA-Forge](https://github.com/YARAHQ/yara-forge) full ruleset** (11,679 rules from
ReversingLabs, elastic, and community sources; YARA-QA filtered to ≥ quality 20, ≥ score 40):

```bash
# Install: https://github.com/YARAHQ/yara-forge (packages/full/yara-rules-full.yar)
tmpdir=$(mktemp -d)
for f in pre_built/el8.x86_64.glibc2p28/bin/*.bz2; do
    bzcat "$f" > "$tmpdir/$(basename "${f%.bz2}")"
done
yara -r /etc/yara/packages/full/yara-rules-full.yar "$tmpdir"
rm -rf "$tmpdir"
```

Result: **0 detections**.

**4 — Upstream hash verification** (`pre_built/build_scripts/verify-binaries`):
Downloads each tool's official GitHub release, applies the same bundling
transformation (strip → patchelf RPATH for dynamic ELFs), and compares SHA-256
against the decompressed bundled binary.

```bash
pre_built/build_scripts/verify-binaries        # verify all
pre_built/build_scripts/verify-binaries rg bat uv   # spot-check
pre_built/build_scripts/verify-binaries -v     # verbose (shows download URLs)
```

Three outcomes:

- **PASS**: byte-for-byte match with upstream release (after strip + patchelf)
- **PASS** (patchelf layout delta): identical NEEDED libs + near-identical size; only RPATH section layout differs — functionally the same binary
- **SKIP**: source build, dev version, or no matching upstream binary release
- **FAIL**: different shared library dependencies or significant size difference — warrants investigation

Many tools (bash, rg, bat, jq, eza, fd, tmux, vim, gnuplot, rsync, htop, kak, octave, etc.)
are intentionally built from source on EL8 targets rather than downloaded from GitHub releases,
so they are SKIP in the hash verification step but covered by the ClamAV + YARA scans above.
