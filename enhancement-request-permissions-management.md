Enhancement #1 — REQUIRED (config bug).
The env-cargo generator writes a stale, wrong absolute local-registry path in ~/.cargo/config.toml:

- Written: .../psg/external/engineering-loadout/latest/.../registry-store → does not exist (no external/engineering-loadout tree; that path prefix only holds caveman-material/).
- Correct: .../psg/tools/loadout-shared/latest/local/share/cargo/registry-store → exists, 2740 crates + index, builds offline (just verified).

Fix: generator should derive the path from LOADOUT_CFG_SHARED_PREFIX (the consume tree), emitting $LOADOUT_CFG_SHARED_PREFIX/share/cargo/registry-store, not a hardcoded external/engineering-loadout literal. It pointed at the relocatable export tree instead of the consume tree, and the literal broke across a reorg — the same absolute-path snowball the modulefile
design deliberately avoids. Emit a SHARED_PREFIX-relative path so channel promotes/reorgs stay live.

Enhancement #2 — RECOMMENDED (coverage gap).
The store is a curated subset. Missing from our dep set: wide, lexical-core, axum (has rayon/serde/tokio/tower/clap/thiserror/anyhow/tracing). Either document it as a fixed curated set or add a supported "add extra crates" path.

