# Assurance ledger

Machine-checkable provenance and behavioral-analysis records for every bundled
package. The threat is a compromised upstream or build box smuggling
ransomware/wiper behavior into a bundle that installs on chip-design machines
where **no project backups exist**. Each record is a live claim, not prose:
`tests/assurance-check` re-hashes the `[artifacts]` of every record against the
files on disk, so a record cannot drift from reality without failing CI.

## Layout

```
assurance/
  records/<package>.toml    per-package provenance + artifact hashes + scan/dynamic status
  profiles/<package>.toml   dynamic-analysis profile (invocations + fs/net allowlists)
  crate-store.lock          committed name/version/cksum closure of the offline crate store
  treesitter-parser-locks.json  per-grammar url + revision + shipped-.so sha256
  downloads.log             append-only TSV of every ./update fetch: date  url  sha256
```

## Record schema (schema = 1)

| key | meaning |
|-----|---------|
| `schema` | record format version |
| `package` | registry package name |
| `version` | bundled version |
| `verified_utc` | when this record was last regenerated |
| `status` | `verified` (full), `partial` (some coverage pending, e.g. GUI apps or dynamic profile TODO), `unverified` |
| `[source]` | `upstream` URL, `ref` (tag), optional `commit`, `dep_pinning` note |
| `[build]` | `script`, build `policy`, optional reproducibility result |
| `[scan]` | scanner engine, YARA-Forge tag, `result` |
| `[artifacts]` | repo-relative path → `sha256:<hex>` for each shipped file (re-checked by assurance-check) |
| `[dynamic]` | `profile`, `harness`, `result` |
| package extras | per-package blocks validated by assurance-check: nvim `[plugins]` (lockfile + per-plugin commit pins); rust-crate-store `[crate_store]` (`lock`, `verifier`, `count`); treesitter `[parsers]` (`lock`, `generator`, `count`) |

## Trust chain

Records and the `.content-manifest` they reference live in git; the release
tag is SSH-signed (S1). Tampering with a shipped payload therefore requires the
signing key, not just a file drop -- and any mismatch is caught by
`loadout install` (default `--verify`), `loadout doctor --verify`, and
`tests/assurance-check`.

## Coverage status

Rolled out package-by-package. `verified` so far: `nvim` (pilot -- record +
plugin pins + content hashes + dynamic detonation), and the S2 batch `rust`,
`rust-crate-store`, and `treesitter-parsers` (upstream provenance + content
hashes + per-crate/per-grammar pins; dynamic is n/a for the compiler/data or
covered by the nvim profile for parsers). Batches follow: python wheels, GUI
shanghai bundles, remaining source builds.
