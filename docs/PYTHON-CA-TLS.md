# Python CA / TLS notes

Canonical notes for the bundled Python's certificate store. Read this before
debugging any `CERTIFICATE_VERIFY_FAILED`, `unable to get local issuer
certificate`, or "works with `SSL_CERT_FILE` but not without it" report.

## TL;DR

- The portable Python ships `lib/pythonX.Y/sitecustomize.py` (stdlib), which
  sets `SSL_CERT_FILE` to the first existing host bundle:
  1. `/etc/ssl/certs/ca-certificates.crt` (Arch, Debian, Alpine)
  2. `/etc/pki/tls/certs/ca-bundle.crt` (RHEL family)
  3. `/etc/ssl/cert.pem`
- A caller-set `SSL_CERT_FILE` **or** `SSL_CERT_DIR` is never overridden.
- The build's original hook is preserved as `sitecustomize_portable.py`
  (`OPENSSL_MODULES`, `TCL_LIBRARY`, `TK_LIBRARY`) and runs after the CA setup.
- `tests/portable-python-ca` is the regression gate.

## Why this exists

The EL8 portable build compiles OpenSSL's default certificate paths to the
build prefix (`/opt/cpython3150p/ssl`), which does not exist after deployment.
Its original `sitecustomize.py` only probed the RHEL path
(`/etc/pki/tls/certs/ca-bundle.crt`), so on Arch/Debian-family hosts the
interpreter had **zero** trusted roots while the host store was present and
valid.

Observed 2026-10-20: `build/check-versions --outdated-only` failed 111 of 158
lookups with `CERTIFICATE_VERIFY_FAILED`; the same command succeeded when
`SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt` was exported. The workaround
masked the bug: an exported `SSL_CERT_FILE` is inherited by every child Python,
including the one under test.

## What ships, and where

| Path | Purpose |
|---|---|
| `build/portable-python-sitecustomize.py` | Source of the CA hook |
| `<python>/lib/pythonX.Y/sitecustomize.py` | Installed hook (stdlib, read by `site`) |
| `<python>/lib/pythonX.Y/sitecustomize_portable.py` | The build's original hook, renamed |
| `tests/portable-python-ca` | Extracts the archive and pins the behavior |

`build/import-portable-python` injects the hook when packaging an archive. It
must go in **lib/pythonX.Y**, not site-packages: `sys.path` places the stdlib
directory before site-packages, so a site-packages `sitecustomize.py` is
shadowed and silently never runs.

The hook is idempotent: repacking an already-injected tree detects the
`LOADOUT_CA_HOOK` marker, overwrites `sitecustomize.py`, and leaves
`sitecustomize_portable.py` alone.

## Diagnose in one command

```bash
env -u SSL_CERT_FILE -u SSL_CERT_DIR \
  .loadout-bootstrap/bin/python3.15 -c '
import os, ssl
print("CA=", os.environ.get("SSL_CERT_FILE"))
print("certs=", len(ssl.create_default_context().get_ca_certs()))
print("TCL=", os.environ.get("TCL_LIBRARY"))'
```

Expected: `CA=` one of the three bundle paths, `certs=` non-zero (121 on the
2026-10-20 Arch host), `TCL=` pointing inside the portable tree. `CA= None`
and `certs= 0` means the hook is missing or shadowed.

Which interpreter is actually running? `./loadout` resolves, in order:

1. `~/.local/bin/python3.15` (or `<prefix>/bin/python3.15` installed copy)
2. `<repo>/.loadout-bootstrap/bin/python3.15` (warm cache)
3. cold extraction of `payload/<platform>/portable-python-*.tar.bz2`

Each is a **copy**. Patching the repo archive does not update 1 or 2.

## Testing / debugging traps

- **Never test with `SSL_CERT_FILE` exported.** It hides the failure. Use
  `env -u SSL_CERT_FILE -u SSL_CERT_DIR` for the negative path.
- `ssl.get_default_verify_paths().cafile` is meaningful only after
  `sitecustomize` runs. If it prints `None`, the hook did not run.
- `check-versions` exits **2** when any upstream lookup fails; the warning lists
  them. A lone 503 is incomplete data, not a TLS failure. `--offline` skips
  network entirely.
- `uv` is a separate Rust binary with its own root store; this hook does not
  affect it. `pip` and `urllib` use the Python `ssl` module and are affected.
- Do not set `SSL_CERT_DIR` casually: it expects an OpenSSL-hashed directory,
  and setting it disables this hook.

## Stale copies (the other never-ending source)

After updating the payload archive:

```bash
rm -rf .loadout-bootstrap          # dev clone: next ./loadout re-extracts
./loadout reinstall portable-python -y   # installed copy
```

Then restart any long-running Python process. A shell that already imported
`ssl` keeps its old context.

## Internal CAs / air-gapped sites

The host trust store is used on purpose; loadout does not bundle a CA set.
For an internal root, point the shell at a PEM bundle:

```bash
export SSL_CERT_FILE=/path/to/corp-bundle.pem
```

The hook respects it. Appending the internal root to the host bundle works too.
Air-gapped installs are unaffected: verification only matters when a tool
actually reaches the network.

## Rebuilding the archive

```bash
rm -rf /tmp/pp && mkdir -p /tmp/pp
tar -xjf payload/<platform>/portable-python-<ver>.tar.bz2 -C /tmp/pp
build/import-portable-python /tmp/pp/portable-python-<ver> --platform <platform>
build/gen-installed-sizes
build/gen-content-manifest
tests/portable-python-ca
```

`import-portable-python` also runs the `libpython` `.dynsym` repair check.
Release artifacts are normally repacked in the EL8 `loadout-build` container
(see `build/ADDING_BINARIES.md`); host-side repacks are fine for local
verification, but the container's bzip2 is the byte-identical toolchain.

## Incident log

| Date | Symptom | Resolution |
|---|---|---|
| 2026-10-20 | 111/158 `check-versions` lookups failed with `CERTIFICATE_VERIFY_FAILED` on Arch; `SSL_CERT_FILE` worked around it | Hook added, archive repacked, `tests/portable-python-ca` added |
