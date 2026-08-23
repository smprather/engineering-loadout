# Enhancement Request: cargo offline mirror must fall back to crates.io when online

> **RESOLVED 2026-08-22.** env-cargo now writes a stock (replacement-free)
> `~/.cargo/config.toml`; the shell `cargo` wrapper probes crates.io per
> invocation (short-TTL cached) and injects the local-registry replacement
> only when unreachable and the store exists — requested behavior #1. The
> probe is per-source (crates.io edge hosts, not a global flag), startup uses
> a once-per-day cache, and the tcsh/zsh environments track bash. Gate:
> `tests/cargo-offline-fallback`. See docs/HANDOFF.md, "cargo online-first
> with offline fallback".

**To:** Engineering Loadout
**From:** Myles (spice-netlist-ls project)
**Date:** 2026-08-21
**Priority:** Medium — actively blocks work whenever the mirror lags upstream

## Summary

My workstation is configured for offline-first cargo usage via a source replacement
pointing at a local registry mirror:

```
~/.cargo/config.toml:
[source.crates-io]
replace-with = "local-mirror"

[source.local-mirror]
local-registry = "/home/mylesp/.local/share/cargo/registry-store"
```

Offline support itself is working well and should stay. The problem is that this
configuration is **total, not fallback**: even when the machine has connectivity,
crates.io is unreachable through normal cargo commands. Today that turned into a
real block: the official `editorconfig` crate was needed and simply does not exist
in the mirror — `cargo add editorconfig` fails, and `--registry crates-io` also
fails ("the crate `editorconfig` could not be found in registry index"), because
the replaced source is consulted regardless.

## Problems

1. **No failover.** Source replacement (`replace-with`) is unconditional; cargo
   never tries crates.io when the local mirror misses a crate.
2. **The escape hatch doesn't work.** The documented `--registry crates-io`
   override still resolves against the replaced index in this setup.
3. **Mirror staleness is invisible.** Nothing warns when a required crate is
   absent from the mirror; failures surface as confusing "could not be found"
   errors mid-build.

## Requested behavior

1. **Online-first with offline fallback** (preferred): when connectivity to
   crates.io is available, resolve/download from it normally; use the local
   mirror only when offline or when the crate is already vendored locally.
2. If true automatic failover isn't feasible with stock cargo, provide a
   supported wrapper/profile switch — e.g., a `loadout cargo-online` toggle that
   swaps `~/.cargo/config.toml` (or sets `CARGO_HOME` with a clean config),
   plus a matching `cargo-offline` to restore the mirror.
3. A `loadout doctor cargo` check that reports: mirror path validity, crate
   presence for the current workspace's dependencies, and whether crates.io is
   currently reachable.
4. Documented sync path for refreshing the mirror (e.g., periodic
   `rsync`/`sparse-index` pull of crates used by active projects), so new
   dependencies stop being surprise-absent.

## Acceptance criteria

- Adding a dependency that exists on crates.io but not in the mirror succeeds
  while online, without manual config edits.
- Fully-offline builds continue to work unchanged against the mirror.
- Clear error message distinguishing "crate not in mirror" from "no network".

## Environment

- WSL2, Linux; cargo 1.96.0; registry store at
  `/home/mylesp/.local/share/cargo/registry-store` (~2,273 crates).
- Repro: `cargo add editorconfig --registry crates-io` →
  "the crate `editorconfig` could not be found in registry index".
