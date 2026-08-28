# Current Handoff

Last updated: 2026-08-28. `v2026.08.28` is published and verified:
signed tag good, `origin/main == v2026.08.28^{commit}`, all three release
assets present, and the nvim stash asset hash matches `sha256sums.txt`.
Current post-release changes: none.

The 2026-08-24 through 2026-08-27 batches below are included in `v2026.08.28`.

## 2026-08-27 batch: TypeScript LSP + Python tool progress (released in v2026.08.28)

| area | what |
|---|---|
| typescript-language-server | Add `typescript-language-server` 6.0.0 as a pure Node runtime archive built by `build/build-typescript-language-server.sh`. The archive bundles the upstream npm server package plus `typescript` 6.0.3, exposes only `bin/typescript-language-server`, hard-depends on loadout `nodejs`, and smokes version + bundled TypeScript + stdio LSP initialize/shutdown before writing the payload. |
| env-nvim | Add guarded `ts_ls` to the default LSP set. Missing `typescript-language-server` stays quiet through the existing `vim.g.loadout_missing_lsp_servers` path; installed package enables JS/TS buffers without first-run npm/network work. |
| installer UX | `install_python_tools` now renders one Rich progress bar over selected uv_tool packages instead of printing a running command list. Top-level `--verbose` still prints exact `uv tool install ... --force ...` commands/stdout for diagnostics and the force-reinstall regression test. |
| xdesk hardening | Final `tests/run-all` exposed inherited `XDG_RUNTIME_DIR=/run/user/$uid` can exist but be read-only in constrained sessions. `xdesk` now falls back to writable `$TMPDIR`/`/tmp`, exports the private state dir as `XDG_RUNTIME_DIR`, and `tests/install-xdesk` skips when `$DISPLAY` is set but not reachable. |
| constrained test hosts | `tests/cargo-offline-fallback` now skips when host policy forbids local loopback socket creation; that test's live/dead network probe cases cannot run under such a sandbox. |

Gates: post-payload chain green (`strip-all-elf-binaries` ->
`gen-installed-sizes` -> `gen-content-manifest`), focused TS LSP install smoke
green, `tests/run-all` green, and Tier 3 green
(`tests/prebuilt-binaries-almalinux8 --full`: 299 binaries OK, 25 expected
host-contract skips, runtimes OK). A spec review flagged the bash `cd`
completion as possible scope drift; owner clarified it is intentional and it
remains in the commit.

## 2026-08-27 batch: headless Neovim Lazy sync on install (released in v2026.08.28)

| area | what |
|---|---|
| installer | `install_nvim_lazy_update` now runs `nvim --headless -n '+Lazy! sync' '+qa'` by default whenever a relevant nvim package is in the resolved selection, `~/.config/nvim/init.lua` exists, a loadout nvim binary exists locally or under `LOADOUT_CFG_SHARED_PREFIX`, and the offline plugin stash is installed. The sync now runs after Tree-sitter parsers are installed, so the smoke sees the final runtime/parser state. |
| split deploys | A per-user `env-nvim` install with `LOADOUT_CFG_SHARED_PREFIX=<shared>/local` now resolves the shared nvim binary, seeds per-user `lazy/` from the shared stash, then runs headless Lazy sync before first interactive launch. `@shared --dest-dir` still installs binary/stash/parsers only and does not seed shared `lazy/`. |
| trust model | Default plugin sync remains offline-only. If the stash is missing, the installer skips Lazy sync with a message that the quiet first-run guarantee requires `nvim-plugin-stash`; network restore still requires explicit `--allow-online-plugin-sync` and uses `Lazy! restore` against `lazy-lock.json`, not a default GitHub sync. |
| tests/docs | `tests/install-nvim-deployments` now captures install logs and asserts headless Lazy sync ran for both single-HOME and split env installs, then blackholes network and asserts the first headless nvim launch has plugins/parsers and no Lazy/missing-tool noise. README, AGENTS, Copilot notes, and `envs/nvim/README.md` document the new guarantee and offline default. |

## 2026-08-26 batch: tcsh first-class refurb (released in v2026.08.28)

| area | what |
|---|---|
| tcsh architecture | tcsh now has `TCSH_CONFIG_ROOT_DIR`, matching the bash/zsh config-root model. The shared root supplies the loadout-owned `global/` layer while home-local `corp/site/team/project/user` overlays still source afterwards, so shared config deployments do not block personal/site layers. |
| split installs | `LOADOUT_CFG_SHARED_PREFIX` is now baked into `tcsh/global/config.csh` as well as `bash/global/config.sh`; direct tcsh logins can find shared `bin/`, terminfo, typelibs, and GUI helper paths without relying on inherited parent environment. |
| docs/tests | `envs/tcsh/README.md`, `README.md`, `AGENTS.md`, and Copilot notes now describe tcsh as first-class but bash-led. `tests/install-env-tcsh` covers shared config-root overlay and tcsh shared-prefix bake; `tests/install-split-shared-envs` asserts the bake and smokes tcsh against the shared prefix when native tcsh/script are available. |

## 2026-08-26 batch: TMPDIR-respecting scratch state (released in v2026.08.28)

| area | what |
|---|---|
| installer temp state | `loadout_main.py` now derives run logs, pending-daemon state, wheel rejoin dirs, portable-Python extract dirs, snapshot-restore scratch, preserved bash-layer scratch, and `clean --all` sweep roots from Python's tempdir resolver (`TMPDIR`, then normal fallback). Dot-hidden `.loadout-*` scratch remains excluded from `clean --all`; `clean --all` removes `loadout-*` only under the current temp root. |
| user env temp files | nvim/vim/tmux/bash/tcsh temp files now honor `$TMPDIR` for cross-host yank files, Lua LSP logs, tmux buffer export, shell `p`/`cdp`, alias dump, and strace output. `/dev/shm` remains the nvim fallback when `TMPDIR` is unset; X11 socket paths remain fixed under `/tmp/.X11-unix`. |
| tests/build scratch | Shell tests that create temp HOMEs/dest dirs and build scripts with hardcoded `mktemp /tmp/...` scratch roots now use `${TMPDIR:-/tmp}`. Version-scoped build prefixes and protocol paths that intentionally document `/tmp` were left alone. Regression coverage: `tests/unit-resolver` imports `loadout_main.py` in a fresh subprocess with custom `TMPDIR` and asserts run-log/pending roots follow it. |

## 2026-08-25 batch: env-nvim live config sync (released in v2026.08.28)

| area | what |
|---|---|
| env-nvim | Synced the live GUI mouse-selection behavior, SPICE filetype coverage, `spice_netlist_ls` command override, `spicefmt` alias config, and SPICE semantic-token/format-on-save ftplugin into the shipped env. The shipped defaults now enable only language servers whose command exists on `PATH` (`lua-language-server`, `ruff`, `ty`, `markdown-oxide`, `biome`, `taplo`, `tclsp`, `spice-netlist-ls`/`$SPICEFMT_LS_CMD`), recording skipped entries in `vim.g.loadout_missing_lsp_servers` instead of producing startup/open-buffer noise. `spicefmt` conform integration is registered only when `spicefmt`/`$SPICEFMT_CMD` exists. `tests/install-nvim-deployments` now opens a `.sp` file in an env-only split install and asserts missing `spice-netlist-ls` leaves both `spice_netlist_ls` and `spicefmt` disabled. |

## 2026-08-25 batch: env-tmux live config sync (released in v2026.08.28)

| area | what |
|---|---|
| env-tmux | Synced top-level config from `~/.config/tmux`: `tmux.conf`, `shell-state-export.sh`, `tmux-popin.sh`, and `tmux-popout.sh`. Installer now deploys the three helper scripts alongside `tmux.conf`, `tmux-3col-layout.sh`, and `tmux-word-separators`; `tests/install-linux-tmp-home` asserts the helpers are present. The copied pop-out helpers were hardened before commit: private `mktemp` snapshot dir, quoted injected paths, argv arrays for `bash --rcfile`, and comments now match the unbound helper behavior. Vendored plugin trees were not copied from the live config because active config drift was only top-level; plugin update still goes through `./build/update tmux-plugins`. |

## 2026-08-24 release: v2026.08.24 (published)

All unreleased 2026-08-22 through 2026-08-24 payload changes were gated:
post-payload chain green, nvim assurance repin + dynamic detonation green,
`tests/run-all` green, and Tier 3 `tests/prebuilt-binaries-almalinux8 --full`
green (**298 binaries OK, 25 expected host-contract skips, runtimes OK**).

Release-prep notes: refreshed the nvim plugin stash for the nvim 0.12.5 bump
(78 bare mirrors, 24 active plugins clone offline; stash sha256
`28a5ad38ccd430d09e15e47ff2de09945f6f1b68111f93f706e8b9e4e4bc0e30`). The local
ignored `.content-manifest.fetched` was temporarily aligned to that local stash
only so pre-release dev/test installs can verify the asset. Do not treat that
ignored file as release provenance; after publish, regenerate it through
`tools/fetch-stash` against the signed release checksums.
Content-heuristic hits during stash rebuild were reviewed and were in upstream
plugin bootstrap/test/doc paths (`blink.cmp`, `lazy.nvim`, `snacks.nvim`,
`tokyonight.nvim`, `which-key.nvim`). Currency cadence is held after explicitly
refreshing `env-nvim`, same-version `nodejs` 26.7.0, and YARA-Forge rules
`20260823`. `sudo freshclam` updated daily DB to 28102; ClamAV engine warned
local 1.4.5 is behind recommended 1.4.6.

One small cleanup landed with the release candidate: Node 26.7.0 ships
`node`/`npm`/`npx` but no `corepack`, and the old registry/doc/importer claim
was stale. `nodejs` metadata now names npm/npx only, and `build/import-nodejs`
fails instead of warning if a declared bundle path is missing.

## 2026-08-24 batch: spice-netlist-ls 0.3.0 (released in v2026.08.28)

| area | what |
|---|---|
| spice-netlist-ls | Added at 0.3.0 using `build/build-prebuilt-bin.sh --tool spice-netlist-ls --tag v0.3.0`. Upstream x86_64 Linux musl asset checksum verified (`sha256:4bc790f3060438ac56d4a65fb7b5ab2886913a0477d24cebd308426db186df18`). Ships the two static-pie musl binaries from the same archive: `spicefmt` (CLI formatter+linter) and `spice-netlist-ls` (LSP server). Build-import smoke passed: both binaries had no NEEDED deps/GLIBC symbols; `spicefmt --version` reported 0.3.0, formatted a sample deck, reported `undefined-subckt`, and proved format idempotency; `spice-netlist-ls` answered a minimal stdio LSP initialize/shutdown session. |

Gates: post-payload chain green (`strip-all-elf-binaries` ->
`gen-installed-sizes` -> `gen-content-manifest`), Tier 1+2 green
(`tests/run-all`), Tier 3 green (`tests/prebuilt-binaries-almalinux8 --full`:
298 binaries OK, 25 expected host-contract skips, runtimes OK).

## 2026-08-23 batch: OpenVAF 23.5.0 (unreleased)

| area | what |
|---|---|
| openvaf | New package: OpenVAF 23.5.0 (`kind: bin`) — Verilog-A compiler, compiles Verilog-A compact model files to OSDI shared objects for circuit simulators (ngspice, Melange). GPL-3.0, Rust + statically-linked LLVM. Member of `@eda`. Build: `build/build-openvaf.sh --tag OpenVAF-v23.5.0`. Two patches: (1) `openvaf/llvm/build.rs` version parser strips non-numeric suffix (handles `23.0.0git`); (2) `openvaf/osdi/stdlib.c` adds `extern` declarations under `NO_STD` for `strlen/malloc/memcpy/strcmp/realloc/log` (clang 15 C99 rejects implicit declarations). Build requires upstream's prebuilt LLVM 15.0.7 (LLVM 16+ removed `PassManagerBuilder.h`); the build script fetches it automatically. Binary: 58MB stripped, GLIBC_2.28, no bundled libs (glibc + libstdc++ + libgcc_s only). Smoke: compiles `current_source.va` → `current_source.osdi` (valid ELF shared object). farm-versions entry. Full note in ADDING_BINARIES.md. |

Gates: included in aggregate release candidate gates above; Tier 3 smoke reports
`openvaf 23.5.0` OK.

## 2026-08-23 batch: tclint 0.9.0 + nvim 0.12.5 (unreleased)

| area | what |
|---|---|
| tclint | New package: tclint 0.9.0 (`python-tool`, `uv_tool: tclint`) — modern dev tools for Tcl: `tclint` linter, `tclfmt` formatter, `tclsp` language server. Pure-Python wheel (`py3-none-any`); zero-ver project (0ver.org). 9 wheels in the closure (tclint + ply/pathspec/importlib-metadata/pygls/voluptuous + lsprotocol/cattrs/zipp; attrs/typing-extensions already shared). Member of `@dev-tools`. Drives new `envs/nvim/lsp/tclsp.lua` (added to `vim.lsp.enable` list) and `envs/helix/languages.toml` (`tcl` language gains `tclsp`). farm-versions entry. Full note in ADDING_BINARIES.md. |
| nvim | Bumped 0.12.4 → 0.12.5 (EL8 source build via `build/build-nvim.sh --tag v0.12.5 --clean`). GLIBC_2.28 (at EL8 floor, same as 0.12.4). Binary + runtime archive rebuilt. |

Gates: included in aggregate release candidate gates above. Extra nvim-specific
gates green: `tests/prebuilt-binaries-almalinux8 --no-build --dynamic`
(10/10 dynamic canary/network checks) and `tests/install-nvim-deployments`
(single-HOME, split shared/envs, offline update path, opt-in catalog plugin).

## 2026-08-23 batch: valgrind 3.27.1 (unreleased)

| area | what |
|---|---|
| valgrind | New package: EL8 source build 3.27.1 (`build/build-valgrind.sh`), upstream moved tools from `lib/valgrind/` to `libexec/valgrind/` in 3.27.x and switched `bin/valgrind` from shell to an ELF dispatcher. Wrapper at `bin/valgrind` exports `VALGRIND_LIB=<prefix>/libexec/valgrind` then execs that dispatcher. NEEDED = glibc only. Stage-verify compiles a `malloc(16)` leak and requires exit 42 + "definitely lost: 16 bytes". Member of `@dev-tools`. Test: `tests/valgrind-smoke` (T2). |
| perf | Deliberately NOT bundled — kernel-ABI-tied (EL8 4.18 vs WSL2 6.18 mismatch class). Documented in `build/ADDING_BINARIES.md`. |

Gates: included in aggregate release candidate gates above; `tests/run-all`
includes `valgrind-smoke`, and Tier 3 smoke reports `valgrind-3.27.1` OK. ~70
MB compressed payload cost; 108 MB installed.

## 2026-08-22 batch (unreleased, one commit)

| area | what |
|---|---|
| sqlite | New package: EL8 source build 3.53.4 (`build/build-sqlite.sh`), bin/sqlite3 + libsqlite3.so.0; readline via already-shipped unregistered lib64 stems; upstream `--all` extensions. Session-probe traps documented in ADDING_BINARIES.md |
| pyright | Retired PyPI wheel (runtime nodeenv download = air-gapped killer); now pure-Node runtime archive (`build/build-pyright.sh`) exec'ing bundled node by absolute path; depends [nodejs]; wheels + nodeenv removed from wheelhouse; stale uv shims cleaned content-gated |
| docker tests | ALL automated docker runs now `--network=none` (prebuilt smoke previously had network unless `--dynamic` — that masking hid pyright's nodeenv download) |
| @envs | Synthetic group now env-bash + env-tcsh (+recommends) — fixes tcsh onboarding reported by a work-side agent |

Verified offline in almalinux:8.10 container with `--network none`: cold
bootstrap → `install pyright nodejs --dest-dir` → pyright type-checks.

## cargo online-first with offline fallback (2026-08-22, second change set)

Closes `enhancement-request-cargo-offline-fallback.md`. Upstream cargo has no
source failover (rust-lang/cargo#3066), so the choice is made before cargo
runs:

- `_install_env_cargo` now writes a STOCK `~/.cargo/config.toml` (no
  `replace-with`). Existing installs migrate by reinstalling env-cargo.
- `cargo()` wrapper in functions.sh (zsh gets it via the shared file; tcsh via
  new `helpers/cargo-wrap`, alias wired in aliases.csh) probes
  `index.crates.io:443 static.crates.io:443` per invocation with a short-TTL
  disk cache (`${XDG_RUNTIME_DIR:-/tmp}/.loadout-net/`), and only when
  unreachable AND the registry-store exists injects the replacement via two
  `--config` CLI args placed before the subcommand. Verified end-to-end with
  real cargo 1.96 against the real store (offline fetch resolves from the
  store; online search passes through untouched).
- Startup detection is now cached once per day:
  bashrc's LOADOUT_ONLINE block calls `loadout_detect_online_cached`; tcsh's
  `helpers/detect-online` shares the same cache files. New shell startup pays
  zero network cost except the first login of the day.
- Overrides: `LOADOUT_CARGO_OFFLINE=1` (force offline mode) / `=0` (never
  wrap); hosts via `LOADOUT_CFG_CARGO_PROBE_HOSTS`; probe TTL via
  `LOADOUT_NET_PROBE_TTL`.
- Gate: `tests/cargo-offline-fallback` (T1, fake cargo + live/dead listener
  sockets drives bash/zsh/tcsh-helper through identical scenarios).

Note for build scripts: the build-tree-sitter trap below still applies — an
offline build box now gets store injection via the wrapper instead of a
static config, so isolated `CARGO_HOME` remains mandatory there.

---

Last updated: 2026-08-17. **`v2026.08.17` is RELEASED** (class C, signed,
verified per `docs/RELEASE.md` §9: `isDraft=false`, Good ED25519 signature, all
three assets, stash sha256 matching local, and the released commit `f5fbe0c`
equal to `origin/main`). It carried fourteen commits since `v2026.08.11`: the
ten listed below plus four from 2026-08-17 (three build-tool fixes `ebf0bd8` /
`c911f38` / `f5fbe0c`, and the currency sweep `94ddafe`).

Release gates as run: Tier 1+2 33/33, Tier 3 292 binaries with 25 expected
host-contract skips, release smoke 317 binaries (more than Tier 3 because the
dev box supplies the host GLVND/perl/py3.6/Tk that the container lacks), malware
scan **CLEAN, 0 detections across 77,634 files** on a genuine cache miss against
signatures refreshed the same morning.

The ten that were already gated: three from 2026-08-13 (taplo `aaadf10`, shell
history flush `dc5f5c1`, open-item fixes `2ed6627`) plus seven from 2026-08-14
to 08-16:

| commit | what |
|---|---|
| `af1092c` | helix rebuilt from master + workspace-trust config; **less 704** |
| `5ac4472` | `./build/update` cadence (`auto_update_interval`, default 6mo) |
| `36f2642` | OpenROAD EL8 build recipe (docs) |
| `4dd93fe` | `@all` group; why there is no online-only variant |
| `2416382` | **OpenROAD 26Q3** packaged (`openroad` + `sta` + 10 solver libs) |
| `cdf0f4e` | install transaction summary, installed sizes, `[Y/n]`, `-y` |
| `ac7a655` | non-TTY install ABORTS (dnf behaviour); 18 call sites pass `-y` |

All tiers green as of the last commit:

* **Tier 1 + Tier 2** (`tests/run-all`): exit 0, no FAIL lines. New since
  2026-08-13: `env-helix-config`, `update-cadence`, `installed-sizes in sync`.
* **Tier 3** (`tests/prebuilt-binaries-almalinux8 --full`, clean
  `almalinux:8.10`): exit 0, **292 binaries OK**, 25 expected host-contract
  skips. 287 -> 290 was `less`/`lessecho`/`lesskey`; 290 -> 292 is
  `openroad`/`sta`.

## The currency sweep for this release, and the bug it exposed (2026-08-16)

The class-C sweep ran `yara-rules`, `tldr-data`, `taplo-schemas`,
`tmux-plugins`, `nodejs` and the four rolling-git wheels, serialised (never two
payload jobs at once). Results: YARA-Forge moved to `20260816`, `lefdef-tools`
`b9ac43e -> cda0e5a`, the other three rolling projects had not moved,
`tmux-plugins` unchanged. **`env-nvim` was skipped deliberately** --
`envs/nvim/lazy-lock.json` has not moved since `v2026.08.11`, and the pins are
the source of truth, so the stash is equivalent. It therefore stays DUE in
`build/currency-state.json`, which is correct rather than a bug.

### `nodejs` downgraded the payload and the guard fired too late

`./build/update nodejs` with no `--tag` runs `nvm install --lts`, which bundles
whatever this box happens to have -- **26.2.0, older than the bundled 26.7.0**.
`build/update`'s `_check_no_downgrade` did fire, but it runs *after*
`import-nodejs` has rewritten `node.tar.bz2`, stamped `packages.json`, and
re-run strip + sizes + manifest. The error arrived with the tree already
poisoned and both maps re-pinned to the downgrade -- a loud error wrapped in a
chain that had already succeeded.

**The guard now lives in `build/import-nodejs`** (`assert_no_downgrade`), at the
first point where the version is known and nothing has been written: right
after `packages_json` is resolved, before bundle assembly. It exits 1 saying
"Nothing was written", and takes `--allow-downgrade`. Version strings that are
git SHAs return `None` from `_version_tuple` and are never compared, so
rolling-git packages are unaffected. `build/update`'s post-hoc check is left in
place as a backstop.

Recovery, if it happens again: `git checkout -- <the archive>`, restore the
version field in `packages.json`, then re-run
`strip-all-elf-binaries -> gen-installed-sizes -> gen-content-manifest`. The
restored archive comes back **byte-identical** because strip pins tar
mtime/ownership.

### `gen-installed-sizes` was never wired into `build/update`

`cdf0f4e` added the sizes map to the post-payload chain but only taught the
*manual* path about it; `build/update` still ran strip + content-manifest only,
so any sweep left `payload/installed-sizes.json` stale and Tier 1 red. Fixed at
the single choke point -- `_run_content_manifest` became
`_run_payload_manifests` and runs sizes first, manifest second -- plus the four
printed guidance blocks and `docs/RELEASE.md` §4, which still documented the old
two-step chain.

**The ordering is the whole point**: `installed-sizes.json` lives under
`payload/`, so `.content-manifest` hashes it. Sizes last means the manifest pins
the previous sizes file.

## Start here after a context clear

Three things changed shape recently and are easy to trip over:

1. **`./loadout install` now asks.** A dnf-style transaction summary prints, then
   `Is this ok [Y/n]:`. **Non-interactive callers must pass `-y`** or the
   transaction aborts with exit 1 having written nothing. Any new automation
   needs `-y`; that is deliberate, not a bug.
2. **The post-payload chain gained a step, and ORDER MATTERS**:
   `./build/strip-all-elf-binaries` -> `python3.14 build/gen-installed-sizes` ->
   `python3.14 build/gen-content-manifest`. The sizes map lives under `payload/`
   so the manifest hashes it; regenerating sizes last leaves the manifest stale.
   Both have `--check` in Tier 1.
3. **`@all` exists** and means literally everything (`@shared-all` +
   `@envs-all`). There is deliberately no "@all minus the offline caches"
   variant -- the caches ARE the product; see `expand_groups` in
   `loadout_main.py` for the reasoning.

**A methodology note that keeps paying off.** Several greens this week were not
evidence: a run whose inputs were edited mid-flight, a build-time smoke that
tested the build tree instead of the packaged artifact, and repeated "exit 0"
notifications that reported a wrapper's status rather than the work's. Verify
the artifact on disk, and serialise anything that writes `payload/`.

## STILL NEEDS THE OWNER

* **`sudo dnf install qt5-qtcharts-devel`** -- the only thing standing between
  here and an OpenROAD GUI build. EPEL has `qt5-qtcharts-5.15.3-1.el8`, an exact
  match for the Qt5 already in `gui_libs`.

**Cleared on 2026-08-17, recorded because both cost a cycle:**

* `sudo freshclam` was run; `daily.cld` v28095, 355,605 signatures. Check the DB
  build date before trusting any CLEAN verdict.
* **Tag signing now uses a FIXED agent socket, `~/.ssh/loadout-agent.sock`.**
  Probing `/tmp/ssh-*/agent.*` -- what `docs/RELEASE.md` §1 used to tell you to
  do -- found nothing while the owner had a perfectly good agent loaded: all ten
  sockets there were stale, and the live one was not visible from the releasing
  process at all. `eval "$(ssh-agent -s)"` exports `SSH_AUTH_SOCK` into one
  shell only, so anything not descended from that shell cannot address it. The
  owner's user-layer `bashrc` also **shadows `ssh-add`**; it is now a function
  using the fixed socket that reuses a live agent, but always call
  `/usr/bin/ssh-add` explicitly. Never resolve this with `--allow-unsigned`.
* **OpenROAD GUI** -- `-DBUILD_GUI=OFF` today. Only blocker is Qt5Charts, and
  EPEL ships `qt5-qtcharts 5.15.3-1.el8`, an exact match for the Qt5 already in
  `gui_libs`, so enabling it is additive.
* **Leftover build trees** (not cleaned automatically, several GB):
  `/tmp/or-tools-install-9.14`, `/tmp/openroad-deps`,
  `/tmp/openroad-install-26Q3`. `build/build-openroad.sh --reuse-build` needs
  them; delete when done with OpenROAD packaging.

## UNRELEASED on main: OpenROAD 26Q3 -- packaged, gated, RTL-to-GDS place & route (committed `2416382`)

The old scoping below ("3-5 day project, prebuilts DEAD on EL8, OR-Tools is the
monster") was right about the shape and too pessimistic about several specifics.
**Status: PACKAGED.** `build/build-openroad.sh --tag 26Q3` reproduces it end to
end, the payload carries `bin/{openroad,sta}` plus 10 COIN-OR/SCIP libs, and
`tests/prebuilt-binaries` drives a real LEF/DEF smoke. Full build note in
`build/ADDING_BINARIES.md`; the detail below is the reasoning behind the pins.

### What is settled

* **26Q3** (2026-06-30) is the current stable tag. OpenROAD moved to quarterly
  tags (`26Q1`/`26Q2`/`26Q3`); `v2.0` is a 2021 fossil. This satisfies the
  stable-release policy -- no `--rev` exception needed, unlike helix.
* Upstream **officially supports EL8** now (`etc/DependencyInstaller.sh` has a
  RHEL-8 branch using gcc-toolset-13 + Python 3.12). That is new since the
  scoping was written.
* **C++20 is mandatory** (`CMAKE_CXX_STANDARD 20`), so EL8's gcc 8.5 cannot
  build it and gcc-toolset is unavoidable. `-static-libstdc++ -static-libgcc`
  makes that safe: the binary ends up with **GLIBC_2.27** and **no GLIBCXX
  symbols at all**, so it does not floor above stock EL8's 3.4.25.
* Verified functionally, not by `-version`: reads `gscl45nm.lef` +
  `design.def`, reports `SMOKE_INSTANCES=12` / `SMOKE_NETS=24` through the Tcl
  API. `openroad -version` prints `26Q3` from a binary that cannot load Tcl at
  all, so it is worthless as a gate -- see the Tcl trap below.

### Dependencies -- all source-built, none available at a usable version

| dep | version | note |
|---|---|---|
| OR-Tools | 9.14 | `-DBUILD_DEPS=ON` pulls abseil/protobuf/re2/SCIP/HiGHS/Cbc |
| Boost | **1.87** | NOT upstream's 1.89 -- matches what OR-Tools compiled against, so one Boost in the link |
| swig | 4.3.0 | EL8 ships 3.0.12; needs bison >= 3.5 to build |
| bison | 3.8.2 | EL8 ships 3.0.4; OpenROAD needs >= 3.2 |
| spdlog | 1.15.0 | |
| eigen | 3.4 | |
| lemon | 1.3.1 | **needs a patch**: hardcodes `CMAKE_POLICY(SET CMP0048 OLD)`, which CMake 4 removed. Delete the line; lemon's `project()` passes no VERSION so the policy is irrelevant |
| cudd | 3.0.0 | autotools |
| yaml-cpp | **0.6.3** | NOT 0.8.0 -- 0.8 exports only `yaml-cpp::yaml-cpp`, but OpenROAD links the bare `yaml-cpp` target, so 0.8 fails with `cannot find -lyaml-cpp`. 0.6.3 is what EL8's EPEL ships and what upstream tests |
| gtest | 1.17.0 | required even with `-DENABLE_TESTS=OFF` |

**flex is NOT required** despite upstream pinning 2.6.4 -- `find_package(FLEX)`
carries no `REQUIRED` and the version line is commented out. (flex 2.6.4 also
fails to build under GCC 14, which is wasted effort to discover.)

Every configure needs `-DCMAKE_POLICY_VERSION_MINIMUM=3.5`; this box has CMake
4.3.2, which hard-refuses projects declaring `cmake_minimum_required < 3.5`.

### The two findings that decide the packaging

**1. OR-Tools must be built with STATIC deps, or the closure is unusable.**
`cmake/dependencies/CMakeLists.txt` **hardcodes** `set(BUILD_SHARED_LIBS ON)`
for its FetchContent deps -- it is not an option, and `-DBUILD_SHARED_LIBS=OFF`
at the top level reaches `libortools` but not them. Left alone, `openroad` needs
**111 shared libraries**, ~100 of them abseil, none present on EL8. Patching
that one line (plus `protobuf_BUILD_SHARED_LIBS`) drops the closure to **26
NEEDED, 15 of which are EL8 base**. Note `-DBUILD_ZLIB=OFF` does NOT work --
it is a `CMAKE_DEPENDENT_OPTION` forced back ON by `BUILD_DEPS`; it is harmless
only because the static build emits `libz.a` instead of the `libz.so` whose
absence broke an earlier link.

Remaining to bundle: **10 libs** -- the 9 COIN-OR solvers (`Cbc`, `CbcSolver`,
`Clp`, `ClpSolver`, `Osi`, `OsiCbc`, `OsiClp`, `Cgl`, `CoinUtils`) plus
`libscip.so.9.2`. That is routine next to `gui_libs`' ~80.

**2. The Tcl trap -- this is the `expect` hazard, and it decides the deps.**
`libpython3.14.so.1.0` and `libtcl8.6.so` BOTH live in portable-python's
`~/.local/lib`, and portable-python's Tcl script library at `~/.local/lib/tcl8.6`
is **8.6.17** whose `init.tcl` does `package require -exact Tcl 8.6.17`. EL8's
system Tcl is **8.6.8**. So the two CANNOT be mixed in either direction:

* build-tree run, prefix `/tmp/openroad-install-26Q3`: dies with
  `Can't find a usable init.tcl`, having searched portable-python's dead
  compiled-in prefix `/opt/cpython3144-portablelib/lib/tcl8.6`;
* forcing system `libtcl8.6` (8.6.8) would then be rejected by the 8.6.17
  script tree once installed under `~/.local`.

**The resolution is to lean INTO portable-python rather than away from it** --
but the RPATH ORDER is load-bearing, and getting it wrong is what shipped past
the dev box. A full install holds THREE Tcl 8.6 patchlevels:

| path | version | owner |
|---|---|---|
| `lib64/libtcl8.6.so` | 8.6.16 | bundled for `expect` |
| `lib/libtcl8.6.so` | 8.6.17 | portable-python |
| `lib/tcl8.6/` (scripts) | 8.6.17 | portable-python -- the only script tree on the search path |
| `/usr/lib64/libtcl8.6.so` | 8.6.8 | EL8 system |

`init.tcl` does `package require -exact`, so library and script tree must be the
SAME patchlevel, and only the `lib/` pair is. RPATH is therefore
**`$ORIGIN/../lib:$ORIGIN/../lib64` -- lib FIRST**, the reverse of this repo's
usual pair. With the usual order the 8.6.16 copy in `lib64` wins and openroad
dies with `Can't find a usable init.tcl` on the first real command, while
`-version` keeps printing `26Q3`.

**How that got past a green dev-box smoke, because the lesson generalises:** the
build script smoked the BUILD-TREE binary, whose RUNPATH pointed straight at
portable-python's lib dir, not the PACKAGED binary, whose RPATH did not. It
passed for a reason unrelated to what ships. Only the clean-container gate
caught it. The smoke now runs after packaging, on the decompressed payload
`.bz2` artifacts in a staged install tree, and fails specifically on `init.tcl`
with a message naming the RPATH order.

So the package is: `depends: [portable-python]`, RPATH
`$ORIGIN/../lib:$ORIGIN/../lib64`, 10 bundled libs, **no wrapper**, no
`TCL_LIBRARY` export.

### What shipped

`build/build-openroad.sh` (carries the lemon CMP0048 patch, the OR-Tools
static-deps patch and the yaml-cpp 0.6.3 pin, and asserts each one applied),
`build/openroad/` smoke fixtures, registry entry with `depends:
[portable-python]` + `@eda` membership, `farm-versions` entry, README row, the
mandatory `ADDING_BINARIES.md` note, and a `tests/prebuilt-binaries` probe that
reads LEF+DEF and requires 12 instances / 24 nets -- failing specifically on
`init.tcl` so a Tcl regression names itself.

Payload cost: `openroad.bz2` 39.5 MB, `sta.bz2` 2.7 MB, 7.6 MB of solver libs.

### Still to do

**The GUI.** `-DBUILD_GUI=OFF` throughout. The only blocker is Qt5Charts and it
is cheap: EPEL ships `qt5-qtcharts 5.15.3-1.el8`, an exact match for the Qt5
already in `gui_libs`. `find_package(Qt5 ... Charts)` in `src/gui` is QUIET and
`BUILD_GUI` is a normal option, so enabling it is additive.

Unsettled and deferred: OpenROAD proper vs OpenROAD-flow-scripts. ORFS is a
scripts+PDK layer ON TOP of this binary, so it changes nothing above; it only
decides whether the PDK data also ships.

## UNRELEASED on main: less 704 — current pager, replacing EL8's 2017 build (committed `af1092c`)

Three binaries (`less`, `lessecho`, `lesskey`), `kind: bin`, in `@core-cli`.
EL8 ships less 530 from 2017; this bundles upstream's current **RECOMMENDED**
release so farm nodes get six years of search/filter/key-binding work without
root. `build/build-less.sh --tag 704`, with a build note in
`build/ADDING_BINARIES.md`.

Two version decisions in the build script are load-bearing and should not be
"upgraded" casually:

* **704, not the v705–v708 git tags.** gwsw/less publishes **zero** GitHub
  releases, so those tags are development tags, which the stable-release policy
  forbids. 704 stands until a new tarball appears on greenwoodsoftware.com.
* **`--with-regex=posix`, not PCRE2.** PCRE2 puts `libpcre2-8.so.0` in NEEDED,
  and that lib belongs to **gui_libs** — coupling the pager to the GUI bundle
  would leave a headless compute node with no gui_libs and no working pager.
  Shipped closure is `libtinfo.so.6` (bundled) + `libc.so.6`; glibc floor 2.14.

### Two gaps closed while adopting it

* **It was invisible to the release currency sweep.** The registry had a
  `version_url` but no `version_pattern`, so `check-versions` marked it `n/a`
  and filtered it out — a package whose entire rationale is "upstream moved on
  and EL8 did not" would never have been flagged when upstream moved again. Now
  scraped: `less 704 704 scrape current`. The pattern is anchored on the word
  **RECOMMENDED** (`RECOMMENDED</strong>\s*version\s*([0-9]+)`) rather than a
  bare `version ([0-9]+)`, because the download page also lists older *and*
  sometimes newer development versions, and the naive pattern takes the highest
  number on the page — which would report exactly the dev build the script
  refuses to ship.
* **Nothing at test time guarded the regex-backend choice.** `build-less.sh`
  asserts the NEEDED closure, but only when someone runs it, and the generic
  `ldd` probe cannot catch a PCRE2 regression: the clean-container run installs
  `@shared`, which **includes gui_libs**, so a PCRE2-linked less resolves fine
  there and scores green — breaking only on the headless nodes this repo
  targets. `tests/prebuilt-binaries` now asserts the backend. Pleasant surprise:
  `--version` is a genuine gate here for once, because less names its backend in
  the banner (`less 704 (POSIX regular expressions)`), so no ELF inspection is
  needed.

## UNRELEASED on main: taplo 0.10.0 — TOML lint / format / LSP (2026-08-12, committed `aaadf10`)

One package, two payload artifacts: the static-pie musl binary (wrapper split,
`bin/taplo` + `bin/taplo.bin`) and `runtime/taplo-schemas.tar.bz2`, an **offline
JSON Schema catalog** of 49 SchemaStore-upstream schemas (388 KiB). Enabled in
nvim (`vim.lsp.enable`), formatted through conform, added to `@dev-tools`, and
wired into helix. Build with `build/build-taplo.sh --tag 0.10.0`; refresh the
schemas with `./build/update taplo-schemas`. Full note in `ADDING_BINARIES.md`.

**Why the schema half exists at all.** taplo's default schema catalogs are
remote (schemastore.org, taplo.tamasfe.dev). On an air-gapped node they are
dead — and a dead catalog **does not error**. taplo silently drops to
grammar-only checking and exits 0 on a Cargo.toml full of misspelled keys. Same
silent-degrade class as the ngspice dead datadir. Hence: vendor the catalog,
point `lint` at it from the wrapper, and gate it with a probe that validates a
real document (`tests/prebuilt-binaries` now lints a bogus `Cargo.toml` and
requires the unknown key to be caught).

Three constraints that are not obvious and cost real time to find:

* taplo **rejects a catalog with relative URLs** outright (`data did not match
  any variant of untagged enum SchemaCatalog`), so entries must be absolute
  `file://`. That cannot be baked at build time, so the catalog ships with
  `/__LOADOUT_RELOC_ROOT__` and rides the existing `relocate_token` machinery.
* `taplo lsp stdio` takes **no catalog flag**, so the wrapper's mechanism cannot
  serve the editors. They pass catalogs as LSP *client settings* — a separate
  code path, separately smoke-tested (`build/taplo/lsp-smoke.py` with a catalog
  argument).
* `taplo format` accepts no schema options at all, so the wrapper injects only
  for `lint`/`check`/`validate`.

**VERIFIED:** CLI format/lint, offline schema lint through the installed wrapper
in a network namespace, and the **nvim** path end to end — a headless nvim on a
real installed tree produced `Additional properties are not allowed
('not_a_real_cargo_key' was unexpected)`. Install-time relocation verified in a
temp HOME with no residual tokens.

**helix VERIFIED too, and the earlier "the sandbox blocks helix" diagnosis was
WRONG.** helix 25.07.1 gates language-server launch behind a **workspace-trust
modal** — *"Trusted workspaces may load local config files and auto-start
language servers"*. Under `script` with stdin at `/dev/null` nobody answers it,
so no server ever spawned and `helix.log` stayed empty. It looked exactly like a
sandbox restriction and was not one. Setting `insecure = true` inside the
existing `[editor]` table made taplo start immediately and the shipped
`languages.toml` render `Additional properties are not allowed
('not_a_real_cargo_key' …)` on a real installed tree.

The duplicated schema block is **resolved and pruned**. Captured from a live
session: taplo asks `{"items":[{"section":"evenBetterToml"}, …]}` and helix
answers by INDEXING `config` with that section. Both spellings were then ablated
in isolation with a fresh cache and HOME per case:

| config | diagnostic |
|---|---|
| only `config.evenBetterToml.schema` | present |
| only `config.schema` | present (helix also passes `config` as initializationOptions, and taplo takes a top-level `schema` from there) |
| neither | **absent** — the control that proves the test can see the difference |

The section-indexed form is kept (documented mechanism, same channel as nvim);
the flat one is deleted. **The first ablation attempt scored both as passing for
a bad reason** — a shared `XDG_CACHE_HOME` let taplo serve the second case from
schemas cached by the first. Isolate the cache when re-testing this.

## CLOSED 2026-08-13 — four open items, and the fact that settled each

None of these needed a judgement call in the end. Three of them had a *fact*
nobody had checked, and the fact decided it. That is the transferable part.

### 1. `loadout_save_history` has its tcsh form — Tier 1 is green (`dc5f5c1`)

`tests/env-shell-parity` had been failing on `no tcsh form for:
loadout_save_history`, the in-flight `history -a` precmd hook in
`envs/bash/global/bashrc`.

**zsh needed nothing** — `envs/zsh/global/zshrc` has carried
`INC_APPEND_HISTORY` since the parity work; that is the same property, native.

**tcsh has NO incremental append.** `history -S` rewrites the whole 10k-line
file where bash's `history -a` writes only what is new, so it hangs off
`periodic` with `set tperiod = 5`, **not** `precmd` — per prompt it would be a
full rewrite after every command on an NFS farm home. The alias lives in
`aliases.csh` because that is the only file the parity gate reads; `tperiod` and
`alias periodic` sit in `tcshrc` with the rest of the history block, and the
forward reference across files is fine because alias bodies resolve at run time.

**Verified by KILLING the shell, not exiting it.** `exit` saves anyway via
`savehist`, so an exit-based test proves nothing — it passes with the feature
removed. Under a real PTY with `kill -9 $$`: flushed shell's histfile holds the
canary; the negative control leaves **no history file at all**.

### 2. `yamlls` dropped from the nvim enable list (`2ed6627`)

It hardcoded `/home/myles/node_modules/.bin/yaml-language-server` while being in
`vim.lsp.enable`, so every user got an enabled server that could never start.
Dropped from the list (the marksman precedent); `cmd` reverted to upstream's
bare name so the file is inert rather than wrong. Re-enabling means **bundling**
the server and its `node_modules` closure offline — feasible (`nodejs` is
already in the payload) but a package, not a config edit. A repo-wide sweep for
`/home/myles*` now returns nothing outside `ADDING_BINARIES.md` prose.

### 3. The `meld` probe: **the PIN WAS RIGHT**, the TIMEOUT was wrong (`2ed6627`)

This file previously suspected `EXPECT_NONZERO["meld"] = 1` of being
environment-dependent and wrong. **It is not.** Measured under the exact probe
env (staged install, `DISPLAY=""`, cut-down PATH), 12 runs: exit **1** every
time, **0.08 s** warm / 0.67 s cold, always carrying `Unable to init server`.
meld exits 0 by hand only because a real DISPLAY is present. The remedy this
file used to suggest — widen to `(0, 1)` and drop the display-refusal
requirement — would have **thrown away a working assertion**.

What actually failed is the **4-second probe timeout**. `./build/release` runs
its gates CONCURRENTLY (the malware scan hashes ~77k files while this smoke
runs) and meld is a Python 3.6 launcher importing the whole GTK/gi stack, so a
cold-cache start under that I/O can cross 4 s. A timeout does not satisfy a
pinned exit code, hence a hard block.

Fix is patience, not a weaker assertion: an `EXPECT_NONZERO` probe that times
out retries once at `SLOW_PROBE_TIMEOUT = 60`; the pinned code and the output
marker still have to hold. Negative-tested all four paths — slow-but-correct
passes; slow-with-wrong-code, slow-with-marker-missing and a genuine hang all
still fail.

### 4. helix workspace trust: documented, then `insecure = true` TURNED ON by owner decision

> **SPELLING SUPERSEDED 2026-08-13.** Everything below about the *decision* still
> holds, but the key is no longer `[editor] insecure`; upstream replaced it with
> `[editor.workspace-trust] level = "insecure"`. See the helix-rebuild section at
> the top of this file.

Landed in two steps. `2ed6627` documented the trade and left the setting off;
the owner then decided to enable it, and it is on as of 2026-08-13.

**The decision.** `[editor] insecure = true` is set in `envs/helix/config.toml`.
The cost is real and is recorded in the comment block there: on a shared
filesystem, any directory a user opens -- including another user's -- has its
local `.helix/` config honoured and its language servers launched. It is
accepted because this loadout's deployment target is a closed, highly controlled
engineering environment (TSMC and comparable self-imposed constraints), where
who can place files on the shared tree is governed by controls outside the
editor. **Revisit if the loadout is ever deployed somewhere that is not true** --
an untrusted multi-tenant box, a contractor share, anything reachable from
outside the controlled environment.

**VERIFIED FUNCTIONALLY, with a negative control, because the failure mode here
is silent and severe.** An unknown key in `config.toml` makes helix discard the
ENTIRE file and fall back to defaults -- losing theme, keybindings, soft-wrap,
everything -- with no error. Two checks that did NOT establish this, both
abandoned after their controls came back identical:

* `hx --health` reports `Config file: <path>` whether the config parsed or not.
* `insecure` appearing in the binary's strings proves nothing -- `workspace-trust`
  appears there too and is NOT a valid config key (those are the `:workspace-trust`
  COMMAND strings).

What settled it was running the real thing on a real installed tree with
`hx -vv` and reading `helix.log`:

| config | result |
|---|---|
| `insecure = true` | `Starting lsp "taplo"`, with the catalog passed as `file:///<shared>/share/taplo/schemas/catalog.json` |
| flag removed (control) | zero taplo hits; `Current workspace is not trusted. Run :workspace-trust` |

So the key is valid, the config is not discarded, and the setting does what it
claims. That run also re-verified taplo's schema relocation through
`LOADOUT_CFG_SHARED_PREFIX` end to end.

The two facts below are what made the ORIGINAL (leave-it-off) recommendation.

* ~~**The upgrade option is BLOCKED, not pending.**~~ **SUPERSEDED same day —
  this was WRONG, see the helix-rebuild section at the top of this file.** It
  assumed the bundled binary was the 25.07.1 release and that the stable-release
  policy therefore ruled master out. The bundled binary **was already a master
  build**; nothing was blocking `level = "servers"`. The reasoning below is kept
  only to show where the error entered: `hx --version` printing `25.07.1` was
  read as evidence of a release build, and a master build prints exactly that.
* **Trust PERSISTS and has commands.** The bundled binary carries
  `:workspace-trust` / `:workspace-untrust` and a `helix_loader::workspace_trust`
  module writing `trusted_workspaces` / `excluded_workspaces` under helix's data
  dir (`~/.local/share/helix`). The cost is one answer per workspace, **ever** —
  not a per-session prompt.

Together those said: leave it off, since the cost was one keystroke per
workspace and the narrower upstream fix does not exist yet. **The owner
overrode that on the deployment-environment grounds above**, which is the input
the recommendation did not have — the controlled-environment premise is the
owner's to assert, not something derivable from the repo.

Documented where a user will hit it: a comment block atop
`envs/helix/config.toml` (which also records that `_install_env_helix`
overwrites that file every install, so editing the INSTALLED copy does not
survive a reinstall) and a subsection in `docs/KNOWLEDGE-BASE.md` under *Editor
behaviour*. Both name `:workspace-trust` as the fix for anyone in a tree where
LSP is dead, and both carry the revisit condition.

## STILL NEEDS THE OWNER

* **The release.** All three commits are gated but unreleased. Tag signing needs
  the ssh-agent socket (see the release-signing notes below).
* **`sudo freshclam`**, still outstanding from v2026.08.09, then
  `./build/scan-for-malware --no-cache` — `--no-cache` is load-bearing, the
  clean verdict is keyed on the signature fingerprint.
* **`ty` 0.0.70 + crate-store refresh**, unchanged and deliberately not started
  unattended: `build/build-tool-crate-store.sh` is 320 MB of churn over ~2199
  crates plus a `crate-store` assurance re-pin, and it is the operation that
  once produced a silently truncated archive from a concurrent payload job.

## Released: v2026.08.11 (class C)

https://github.com/smprather/engineering-loadout/releases/tag/v2026.08.11 —
signed tag (ED25519 `SHA256:XlxLB4kh...`, `git tag -v` = Good signature),
**verified published, not a draft**, by re-reading the release rather than
trusting the publish exit code. Tag and `origin/main` both at `7b0460a`. Assets:
`nvim-plugin-stash.tar.bz2` (343.8 MB), `sha256sums.txt`,
`default.content-manifest`.

Class **C** — forced by `loadout_main.py` (the `_install_env_helix` fix) *and*
`packages.json` group membership (`@eda` gained iverilog + yosys); the class
table says that is C regardless of diff size. All three tiers green (32/32),
Tier 3 clean container 285 binaries OK, `tests/prebuilt-binaries` 310 binaries
OK on the dev box. Malware scan CLEAN, 0 detections across **77,434** files
(YARA-Forge 20260809 + ClamAV signatures refreshed to 2026-08-11 the same day —
a scan against stale signatures is a green light that means nothing).
Assurance 33/0; **re-pin N/A** — records exist only for `crate-store`,
`git-nvim`, `nvim`, `rust`, `treesitter-parsers` and none of them moved.

**The first release attempt was BLOCKED** by the flaky meld probe (below). It
stopped before tagging, so there was no partial state — the gate behaved
correctly.

## THE ONE PATTERN WORTH CARRYING FORWARD

**Every real bug this session was caught by testing the INSTALLED artifact, and
none by reading the repo file.** Four of them, each invisible to a diff:

| bug | how it hid |
|---|---|
| `_install_env_helix` named `config.toml` literally | a new `envs/helix/languages.toml` would silently never install; the repo diff looks identical either way |
| iverilog's compiled-in prefix WINS when it exists | worked on a clean node, silently broke on the dev box, writing a dead interpreter into every `.vvp` shebang |
| yosys sentinel pointed at the SOURCE layout | install works, warns on every run, red row in the summary (the fish bug) |
| `yosys-witness` imports `click` | passes here because this box has click; `ModuleNotFoundError` on a stock farm node |

Three of my own iverilog "relocation" tests also passed for bad reasons before
the real bug surfaced: copying a tree while the ORIGINAL still existed; hiding
`iverilog-inst-13_0` when the build used `iverilog-inst-v13_0`; and smoking with
`vvp file.vvp`, which bypasses the shebang entirely. **Before believing a pass,
ask what the test would have printed had the feature been absent.**

## RESOLVED — the `meld` smoke probe (was: FLAKY, blocked a release)

`./build/release` was blocked once by:

```
FAIL: meld  expected exit 1, timed out instead
```

**Fixed 2026-08-13 in `2ed6627`, and the diagnosis in the original entry was
wrong** — it is kept here because the wrong theory is instructive. This section
suspected the *pin*; the pin was right and the *timeout* was the bug. Full
account in *CLOSED 2026-08-13* above. Short version: under the exact probe env
meld exits 1 in 0.08 s, 12/12, always carrying `Unable to init server`; the
4-second budget just could not survive `./build/release` running its gates
concurrently. `EXPECT_NONZERO` probes now retry once at 60 s with the pinned
code and marker still enforced.

The measurement advice from the original entry stands and is why the retraction
was possible: **measure without a pipe** — `meld --version | head -3; echo $?`
reports *head's* status, not meld's, which is how the exit code got misread in
the first place.

## OPEN — needs a decision, not a fix

### xdotool — requested 2026-08-17 by the owner, not started

Package `xdotool` (X11 automation: synthetic keystrokes/mouse, window search,
move/resize/activate). Nothing investigated yet beyond the request; the notes
below are what to check first, not conclusions.

* **Source vs shanghai.** EL8 ships `xdotool` in EPEL. It is a small C program
  over `libX11`/`libXtst`/`libXinerama`/`libxkbcommon`, so either route is
  cheap; `gui_libs` already carries the X11 client stack, and the question is
  whether `libXtst` (XTEST extension — the part that injects input) is in it
  or needs adding. **Check `gui_libs` for `libXtst.so.6` before anything else.**
* **It needs a real X display to do anything**, so it inherits the same
  host-contract caveat as the GL GUI apps in `tests/prebuilt-binaries`: a probe
  must either be a genuine skip on a headless container or run under `xdesk`.
  `xdesk` already exists for exactly this and `tests/install-xdesk` shows the
  pattern -- prefer that over a `--version`-only smoke, which proves nothing
  here (the failure mode is "cannot open display", not a bad binary).
* **Decide the audience.** The owner's Windows-side automation is AutoHotKey;
  `xdotool` is the Linux analogue and would pair with the `xdesk` nested
  session. Worth settling whether it ships in `@gui-suite` or stays name-only.

### DigitalJS / OpenROAD — scoped, not started

- **DigitalJS**: the cheap part. It is a browser JS library (BSD-2-Clause, no
  CLI). The chain is `design.v -> yosys -> yosys2digitaljs -> browser`, and
  **yosys was the only hard piece — it is now done**. Remaining: `yosys2digitaljs`
  (BSD-2-Clause npm CLI that shells out to yosys) plus the digitaljs assets and a
  launcher, ~1-2 days. The genuine unknown is vendoring a `node_modules` closure
  offline — **no precedent in this repo**; every JS-adjacent thing today
  (`lua-language-server`, `biome`) ships as a self-contained binary.
- **OpenROAD**: BSD-3-Clause and viable, but a 3-5 day project, not a package.
  Prebuilts are DEAD on EL8 — verified by running one: needs **GLIBC_2.29** and
  **GLIBCXX_3.4.26**, EL8 has 2.28 / 3.4.25, both miss by one version. A source
  build fixes both automatically, but eight RUNTIME deps are below floor (Boost
  1.89 vs EL8's 1.66, CMake 3.31, SWIG 4.3, spdlog 1.15, Eigen 3.4, OR-Tools
  9.14, LEMON 1.3.1, CUDD 3.0) and **OR-Tools is the monster**. Contrast yosys,
  whose only gap was BUILD-TIME bison. Settle **OpenROAD proper vs
  OpenROAD-flow-scripts** before anyone starts.

### Deferred currency, unchanged reasons

`vim`/`gvim` 9.2.0933 (upstream tags patches daily), `fresh` 0.4.7 (major bump +
EL8 source build; its prebuilt wants GLIBC_2.35), `jupyterlab` 4.6.3 (blocked on
pip's `--platform` resolver backtracking into httpcore/anyio). `pdftotext` is
correctly **pinned** — the blocker is now fontconfig 2.15 at poppler 26.06+, not
freetype.

**`ty` -- IN PROGRESS 2026-08-17 at 0.0.72** (upstream moved past the 0.0.70 in
the account below). Doing it properly this time: the binary is bumped
(sha256-verified against upstream's published sum, `GLIBC_2.17` floor, base libs
only), `build/rust-tool-locks.txt` is re-pinned to 0.0.72, and the crate store is
being rebuilt so the store can still rebuild the tool offline. A `crate-store`
assurance re-pin follows. The history below is why the shortcut was refused:

**`ty` 0.0.70 was bumped and then DELIBERATELY REVERTED to 0.0.69.** `ty` is a
Rust tool, and `verify-crate-store --check-policy` correctly failed the release
gate: `build/rust-tool-locks.txt` still pinned 0.0.69, and the shipped crate
store is built from those refs, so a stale ref means the store can no longer
rebuild that tool **offline**. Re-pinning the locks alone would have made the
gate pass while leaving the store genuinely missing 0.0.70's dependency
closure — papering over exactly what the gate is for. A real bump needs
`build/build-tool-crate-store.sh` (320 MB payload churn, network, ~2199 crates)
**plus** a `crate-store` assurance re-pin, because that package has a record.
Deliberately not done immediately before a context clear; the store rebuild is
also the operation that once produced a silently truncated archive from a
concurrent payload job. **Bundle the ty bump with the next crate-store refresh.**
`mlr` is Go, is not in the store, and bumped freely.

## miller 6.21.0 + ty 0.0.70, and a new prebuilt-import script (2026-08-11)

Both were bundled with **no build script and no ADDING_BINARIES note** — the
provenance gap `lua-language-server`, `liberty-filter`, `tmux-path-store` and
the five small C tools each had. Now covered by
`build/build-prebuilt-bin.sh --tool {ty|mlr} --tag X`, multi-tool in the style
of `build-simple-c.sh`. Three traps encoded in it:

- **Tag format differs per tool**: `ty` uses a bare `0.0.70`, miller uses
  `v6.21.0`.
- **Binary name != registry key for miller**: the binary is `mlr`, the
  `packages.json` key is `miller`. `loadout_package_bin` wants the binary name,
  `loadout_stamp_version` the registry key — the wrong one fails with a bare
  `KeyError`.
- **`loadout_package_bin` ABORTS on a static binary.** It always runs
  `patchelf --set-rpath`, which dies with `cannot find section '.dynamic'` on
  static Go binaries like `mlr`. Those need `strip` -> `bzip2`, no patchelf, no
  RPATH. The script branches on an empty NEEDED set.

Smokes are functional, not `--version`: `ty` must REPORT a genuine type error
(a checker that silently passes everything would sail through a version probe),
`mlr` must round-trip CSV to JSON. `ty` publishes a sibling `.sha256` for its
asset and the script verifies against it; miller publishes none, so the script
prints the hash it computed.

## iverilog 13.0 added (2026-08-10); the compiled-in prefix WINS when it exists

New package `iverilog` (Icarus Verilog 13.0, GPL-2.0, EL8 source build), now a
member of `@eda` alongside gtkwave/klayout/verilator. Build:
`build/build-iverilog.sh --tag v13_0`. Cheap: 79 MB built -> **2.3 MB** shipped,
max GLIBC_2.14 / GLIBCXX_3.4.21, and every NEEDED (`libbz2`, `libz`,
`libreadline.so.7`, `libtinfo.so.6`) was already in `lib64/` -- nothing new
bundled. Unlike verilator it *simulates*, so it needs no host `g++` at runtime.

### The finding worth keeping

The `iverilog` ELF has `<build-prefix>/lib/ivl` compiled in and derives it from
its own location **only when that path does not exist**. The build prefix
therefore *wins whenever it is still on disk*. That is **build-box masking in
reverse**: a clean farm node is fine and the developer's own machine is the one
that silently breaks, because `/tmp/iverilog-inst-v13_0` is still there from the
build.

Not cosmetic: `lib/ivl/vvp.conf` carries `VVP_EXECUTABLE`, which iverilog writes
into the **shebang** of the compiled `.vvp`. Wrong `lib/ivl` means every
`./sim.vvp` gets `bad interpreter: No such file or directory`. Fixed by shipping
`bin/iverilog` as a wrapper passing `-B <prefix>/lib/ivl` (explicit user `-B`
still wins). **`vvp` is deliberately NOT wrapped** -- it is the interpreter
named in that shebang and Linux does not honour a shebang pointing at another
script, so it must stay a real ELF.

**Three of my own tests passed for bad reasons before this surfaced**, which is
the transferable lesson:

1. copied the tree and ran the copy while the **original still existed**;
2. hid a directory named `iverilog-inst-13_0` while the build actually used
   `iverilog-inst-v13_0` -- so nothing was hidden at all;
3. smoked with `vvp file.vvp`, which **bypasses the shebang entirely**.

Only inspecting the *installed* artifact caught it. The build script now runs
the smoke twice -- once with the build prefix **present** (the hostile case) and
once with it moved away -- and both passes execute the generated file via
`./smoke.vvp` as well as `vvp smoke.vvp`, and assert the shebang text.

### Relocation shape

`relocate_token` + `relocate_root: lib/ivl`, covering `vvp.conf` / `vvp-s.conf`
only. `bin/iverilog-vpi` (upstream generates it with the prefix baked into
CFLAGS/LDFLAGS) was replaced with a repo-owned `$0`-deriving wrapper, which is
what collapses relocation to the single root the installer accepts. The ELFs
keep the real build prefix as an unused fallback and must never contain the
token -- `relocate_runtime_token()` hard-errors on that by design, and the build
script asserts the separation.

Two shell traps, both fixed: `sort` collates `vvp.conf` vs `vvp-s.conf`
differently by locale, so the token-placement assertion needs `LC_ALL=C` on
**both** sides; and a trailing `[ test ] && { ...; }` as the last command in a
`while` body returns non-zero on the common case, which `set -e` treats as a
build failure (and an `exit` inside a piped `while` is a subshell and would not
have stopped the script anyway).

Gates: Tier 1 + 2 green (30/30). Tier 3 clean container exit 0, **280 binaries**
OK (up from 276), including `OK (sim): iverilog compiled, ./smoke.vvp ran, VCD
written` -- the container is the only environment with no build prefix present.

## markdown-oxide added; BOTH markdown LSPs were broken (2026-08-10)

New package `markdown-oxide` 0.25.12 (`kind: bin`, upstream x86_64 prebuilt,
Apache-2.0) -- a PKM language server giving wikilinks, backlinks, daily notes
and unresolved-link creation over a directory of markdown. User-facing docs:
`docs/KNOWLEDGE-BASE.md`. Build: `build/build-markdown-oxide.sh --tag v0.25.12`.

**Obsidian itself is NOT bundled and cannot be, on licence grounds.** Its terms
grant a "non-sublicensable, non-transferable" licence to install and execute it
"on machines operated by or for you" and separately forbid the customer to
"distribute or share the Services or Software or make any of them available for
access by third parties". Bundling it into `payload/` and publishing that as a
release is exactly that. **Free for commercial USE is not permission to
REDISTRIBUTE** -- an easy and expensive thing to conflate. For the record it
would otherwise have fit (main ELF floors at GLIBC_2.25 vs EL8's 2.28; a plain
129 MB `tar.gz` exists in its GitHub release though not on the download page;
only `obsidian-cli` at GLIBC_2.34 would be dead), so if an enterprise agreement
ever permits internal redistribution the path is a shanghai of that tarball, not
a research project. Users install Obsidian themselves and point it at their own
vault; markdown-oxide indexes the same plain files from nvim/helix. **The vault
is org content and never belongs in this repo** -- that is what the unbundled
corp/site/team/project/user layers and `--post-install-hook` are for.

### The finding worth keeping: a shipped LSP config proves nothing

`markdown_oxide.lua` had been in `envs/nvim/lsp/` for ages and was dead for
**two independent reasons**. Fixing either alone changes nothing:

1. the binary was never in the payload, so `cmd = { 'markdown-oxide' }`
   resolved to nothing; and
2. `envs/nvim/lsp/` is the **entire upstream nvim-lspconfig catalogue** (~300
   files, almost all inert). Presence there does not enable a server -- only the
   explicit `vim.lsp.enable({...})` list in `envs/nvim/lua/global/init.lua`
   does, and `markdown_oxide` was not in it.

**`marksman` was the mirror-image bug in the same list: enabled but never
bundled**, so nvim tried to spawn a binary that does not exist and failed
silently on every markdown buffer. It has been replaced by `markdown_oxide`
rather than added alongside -- two markdown servers attach to the same buffer
and double completions and go-to-definition results. Helix had the same trap
from the other direction: its *built-in* default for markdown is also
`marksman`, so `envs/helix/languages.toml` (new) names `markdown-oxide`
explicitly, and listing `language-servers` there replaces the default list
rather than appending.

That audit was then run against the other five enabled servers, and **it found
one more**:

| enabled server | `cmd` | bundled? |
|---|---|---|
| `lua_ls` | `lua-language-server` | yes |
| `ruff` | `ruff` | yes |
| `ty` | `ty` | yes |
| `biome` | `biome` | yes |
| `markdown_oxide` | `markdown-oxide` | yes (new) |
| **`yamlls`** | **`/home/myles/node_modules/.bin/yaml-language-server`** | **NO** |

### RESOLVED 2026-08-13: `yamlls` pointed at a hardcoded personal home directory

`envs/nvim/lsp/yamlls.lua` hardcoded
`/home/myles/node_modules/.bin/yaml-language-server` -- an absolute path into
somebody's personal `$HOME` (note it was not even the current dev user,
`mylesp`). It was in the `vim.lsp.enable` list, so every user got an enabled
YAML server that could never start. It was deliberately **not** fixed as part of
the markdown-oxide change: a different package, and a real choice rather than a
typo repair.

**Fixed in `2ed6627` by taking the first of the two options below** -- dropped
from the enable list, `cmd` reverted to upstream's bare name so the file is
inert rather than wrong. Kept for the record:

- **Drop `yamlls` from the enable list**, as was done for `marksman`. Zero
  payload cost, and honest about what is shipped. *(chosen)*
- **Bundle `yaml-language-server`** and point `cmd` at the bare name. It is an
  npm package and `nodejs` is already bundled, so this is feasible -- but it
  means owning a node-based LSP and its `node_modules` closure offline. This
  remains the path if YAML LSP is wanted later.

### Packaging notes

Nothing ships alongside it: upstream's binary floors at **GLIBC_2.18** and its
NEEDED set is glibc plus `libgcc_s`, all on the never-bundle list -- no `lib64/`
additions, no wrapper, no runtime archive. The build script asserts both rather
than assuming, since a future release built against a newer toolchain would
install cleanly on the dev box and be dead on a farm node. No
`rust-tool-locks.txt` pin is needed while it stays a prebuilt import; if the
glibc assertion ever fires it becomes an EL8 Rust source build and *then* needs
one.

`markdown-oxide --version` exits 0 from a binary that cannot resolve a single
wikilink, so `build/markdown-oxide/lsp-smoke.py` drives the real protocol
(initialize -> didOpen -> textDocument/definition) against a two-note temp
vault and requires `[[note-b]]` to resolve. It runs at build time **and** from
`tests/prebuilt-binaries`, so the release gate cannot false-green either.
Two protocol details cost time: the server emits `window/logMessage` **before**
the initialize result, so the reader must match on request **id**; and it is
spawned with `cwd=<vault>`, so the server path must be absolute or a relative
one silently resolves against the temp vault and vanishes.

`gen-readme-table` only **syncs existing rows** -- it warns about a new package
rather than adding one, so the README row was added by hand. Expect that on the
next new package.

### `_install_env_helix` installed exactly one hardcoded filename

Adding `envs/helix/languages.toml` was not enough to ship it: `env-helix` has a
custom handler that named `config.toml` **literally**, so any other file in
`envs/helix/` was silently never installed. Caught only because the install was
verified into a temp `--dest-dir` and the file was checked for -- a repo-file
diff looks identical either way. The handler now iterates a `_shipped` tuple,
and the post-install verification list gained `.config/helix/languages.toml`.
It stays per-file rather than a directory sync **on purpose**: `install_path()`
on a directory syncs with `delete=True` and would wipe anything the user keeps
beside these, which is the env-st lesson. **Adding a new shipped helix file
means editing that tuple.**

Gates: Tier 1 + 2 green (30/30); Tier 3 clean container exit 0, 276 binaries OK
(up from 275) including `OK (lsp): markdown-oxide wikilink resolved`.

## freetype 2.9.1 -> 2.14.3, source-built (2026-08-10)

`libfreetype.so.6` was EL8's system 2.9.1, shanghai'd into `gui_libs` like the
other 90 GUI libs. It is now source-built by the new
**`build/build-freetype.sh --tag 2.14.3`**. Two reasons: it is a 2018 rasterizer
carrying six years of unpatched upstream CVEs *and* it is the shared font engine
for every GUI/terminal tool in the bundle (xterm, st, urxvt, gvim, Qt5, GTK3,
cairo, pango, `libxul.so`, Xephyr, the octave fltk plugins); and it was the sole
reason `pdftotext` sat on poppler 22.12.0.

Build is ~9 s and the payload got *smaller* (380K -> 356K bz2). Nothing else in
the tree needed rebuilding -- everything links by SONAME and the direction
(older consumer, newer lib) is the compatible one.

**The ABI was never the risk; the pixels were, so they were measured.**
`build/freetype/compare-rendering.c` renders a glyph set under each lib and
reports bitmap dims, pixel bytes and advance *separately*. Over 8 faces x 24
chars x 7 sizes: `normal` 1.9% of glyphs differ with **0** advance and **0**
dimension changes; `light` 4.3% with **0** advance; `mono` 38.4% (the v35 ->
v40 interpreter change, 1-bit only, unused by modern toolkits). Every advance
change is confined to *forced-autohint* mode on *proportional* faces -- never a
`NerdFontMono-*` face -- so no terminal cell grid can shift. Two traps worth
keeping:

- **A one-font check gives a false all-clear.** `DejaVuSans`/`DejaVuSansMono`
  were **bit-identical** across the whole jump while every CascadiaCode face
  moved. Test the bundled Nerd Fonts.
- **A dropped export is the failure that would actually bite**, silently, at
  first font load on a farm node. 2.14.3 removes `FT_Outline_New_Internal` and
  `FT_Outline_Done_Internal`. The build script proves no consumer wants them
  rather than asserting it: it collects every undefined `FT_*` symbol across
  `bin/` and `lib64/` (and, under `--deep-check`, the runtime archives) and
  fails if the new lib does not export one. Closure is 66 distinct symbols from
  14 consumers. The guard was negative-tested by doctoring the export list.

`--with-harfbuzz=no` and `--with-brotli=no` are load-bearing, not tidiness:
harfbuzz would be a circular bundled dep (EL8's 1.7.5 is below what 2.10+ wants
anyway), and brotli would add a NEEDED this repo does not bundle -- textbook
build-box masking, since `brotli-devel` is installed here and absent on a stock
node. The script hard-fails on any NEEDED outside the allowlist.

### pdftotext 22.12.0 -> 26.04.0, and the ceiling that replaced freetype

The old pin is gone; the new one is **fontconfig**. poppler's requirements by
release: 23.12 wants freetype 2.10 / fontconfig 2.13; 24.08..**26.04** want
2.11 / 2.13; **26.06+** wants 2.13 / **2.15**. EL8 has fontconfig 2.13.1, so
26.04.0 is the last buildable release. Going further means bundling fontconfig
too -- a bigger blast radius than freetype was, because fontconfig 2.15 also
moves the font-cache format and would force a cache rebuild for every user.

`build-pdftotext.sh` now **requires** `--with-freetype <prefix>` (the
`build-modules.sh --with-tcl` convention), and `build-freetype.sh` leaves its
install tree at the version-scoped `/tmp/loadout-freetype-instdir-<TAG>` to
supply it. EL8's `freetype-devel` headers are still 2.9.1, so without the flag
cmake configures against those and fails -- and, more insidiously, if a future
EL8 point release nudged the system version past the minimum, the build would
silently link against a freetype that is *not* the one shipped in `lib64/`.

Three things bit during the bump, all now encoded in the script:

- **The `GlobalParams` sed silently matched nothing.** The constructor went
  from `const char *customPopplerDataDir` to `std::string` between 22.x and
  26.04. A pdftotext built without that patch does not crash -- it extracts
  CJK as garbage -- so nothing downstream would have noticed. The script greps
  for the applied expression *and* the injected `#include <cstdlib>` and
  hard-fails on either.
- **`ENABLE_GPGME=OFF` is mandatory**, not cosmetic: poppler added signature
  support wanting Gpgmepp >= 1.19, which EL8 has no package for, and configure
  *errors* rather than degrading.
- **`ENABLE_LIBTIFF=OFF`**: poppler >= 25.x wants tiff >= 4.3, EL8 has 4.0.9.
  TIFF only feeds `pdfimages`/`pdftoppm`, which this package does not ship.

The build's CJK smoke now stages the **patchelf'd** binary next to a populated
`lib64/`, so it exercises the deployed `$ORIGIN/../lib64` resolution instead of
the build box's `/usr/lib64`. It previously staged the unpatched binary, which
would have tested against EL8's *older* freetype. Verified with a negative
control: same binary without poppler-data returns
`Missing language pack for 'Adobe-Japan1'`, so the smoke is load-bearing.

### Gates for this change

- Tier 1 + Tier 2 (`tests/run-all`): green.
- Tier 3 (`tests/prebuilt-binaries-almalinux8 --full`, clean `almalinux:8.10`):
  **275/275 binaries OK**, 25 expected host-contract skips (klayout + the 12
  `strm*` converters need host GLVND). `pdftotext 26.04.0` and its CJK runtime
  probe both OK; xterm/`resize` and gvim -- direct freetype consumers -- OK.
  This is the gate that matters: the dev box's freetype-2.9.1 headers and
  `brotli-devel` are exactly the masking this change had to avoid.
- `build/verify-binaries` provenance and `check-versions` were **not** re-run;
  do that at release time. `pdftotext` stays `pinned` in `check-versions`
  output, now against 26.06+ rather than 23.01+.

## POLICY REVERSAL: tcsh now tracks bash/zsh (2026-08-08)

`envs/tcsh/` is a **first-class tracked environment**. A change to the bash env is
not finished until the tcsh form lands, or is recorded as one of the five
upstream-has-no-tcsh-target exceptions.

This reverses the policy that stood 2026-07-13..2026-08-08 ("deliberate ONE-TIME
port, does NOT track, no drift test"). That policy's entire justification was an
expected tcsh user count "near zero". **The owner's actual position is the
opposite: the EE community this project serves is ~90% tcsh** -- the majority
shell of the target audience, not a courtesy port. Every argument for not
tracking rested on the bad premise, so none of them survive it.

Consequences, so nobody re-derives them:

- **"csh has no functions" is not an exemption.** It selects the implementation:
  a one-line wrapper is an alias (aliases take args -- `\!:1`, `\!*`, `\!:2-`);
  loops/locals/`case` go in a POSIX-sh helper under `envs/tcsh/global/helpers/`
  and are aliased; anything mutating the caller's cwd/PATH/env is a helper that
  *prints* the command, run through `` eval `helper` ``. `git-branch.sh` was
  already this pattern.
- **Genuinely absent, all because upstream ships no tcsh target:** Starship
  (`starship init` has no tcsh), fzf keybindings (`--bash|--zsh|--fish` only),
  zoxide (`zoxide init` has no tcsh), OSC 133 semantic zones (needs
  bash-preexec; OSC 7 cwd *does* ship, via tcsh `precmd`), IceCream-Bash
  (`${!var}` + `export -f`). Anything else missing is a bug.
- **Prefer csh-native mechanisms where they beat the bash one:** `cwdcmd` fires
  on every directory change, so "every cd lists" needs no `cd` wrapper at all;
  `set implicitcd` replaces bash's ERR-trap directory-execution hack.
- Project memory `tcsh-env-one-time-pass` was **deleted** and replaced by
  `tcsh-env-tracks-bash`; `AGENTS.md` and `envs/tcsh/README.md` are updated. The
  July 2026 plan/spec under `docs/superpowers/` carry SUPERSEDED banners rather
  than being edited -- they are a record of what was decided then.

### What landed with the reversal (2026-08-08)

The tcsh env went from 358 lines to a full port. New files under
`envs/tcsh/global/`: `completions.csh`, `keybinds.csh`, `grc-aliases.csh`,
`modules-init.csh`, and `helpers/` (19 POSIX-sh scripts, all shellcheck-clean).
`aliases.csh` now carries the whole bash alias surface; `config.csh` carries
every `LOADOUT_CFG_*` tcsh can act on; `tcshrc` carries the PATH list, the
environment exports, shell options, per-PID history with parent inheritance, the
online probe, GRC, Environment Modules, and a prompt with the farm/LSF colour
swap and uid/host handling.

**`tests/env-shell-parity` is the gate that makes "tracks" real** (Tier 1). It
asserts every bash alias/function name has a tcsh alias, and every
`LOADOUT_CFG_*` is handled -- with exception tables that require a written
reason. The old policy refused exactly this gate; the premise it refused it on
is gone. It also self-checks its own extractors, because a regex that silently
matches nothing turns the whole gate into a no-op that always passes.

**Four bugs it and the extended test caught, all of which would have shipped:**

1. **tcsh has no `$PPID`.** Naming it printed `PPID: Undefined variable.` on
   every interactive startup. `helpers/seed-history` derives the parent pid from
   `/proc` instead.
2. **`!` triggers history expansion inside DOUBLE quotes too**, so the rg
   aliases' `--glob='!*.snapshot*'` produced `0: Event not found.` on every
   startup. Must be `\!`.
3. **`LOADOUT_CFG_PROMPT_COLOR_*` is shared with bash AND exported there**, so a
   tcsh started from a loadout bash shell inherited a *bash* prompt string
   wrapped in readline's `\[` / `\]` markers and printed them literally.
   `helpers/prompt-color` strips them and converts a literal `\033`/`\e` to a
   real ESC; `%{...%}` is tcsh's own zero-width wrapper.
4. **The tcsh test's headline "empty stderr" assertion could not see any of
   this.** `script -qec` gives the child a PTY, so tcsh's own diagnostics arrive
   on **stdout** while the stderr file stays empty. Bugs 1 and 2 both printed on
   every startup while the test was green. `assert_no_csh_noise` now scans the
   captured output for tcsh's error vocabulary, and both bugs were deliberately
   re-introduced to confirm it fails.

**csh-native wins over porting the bash mechanism**, used deliberately:
`cwdcmd` fires on every directory change (cd, pushd, popd, implicitcd), so
"every cd lists" needs no `cd` wrapper and has no call site that can forget --
strictly better than the bash env, which needs `cd()` plus a `__zoxide_cd`
override plus care in `latest`. `set implicitcd` replaces the ERR-trap
directory-execution hack. `cwdcmd` also carries OSC 7 (cwd reporting), which is
the one piece of the WezTerm integration csh can do.

**Gap CLOSED (2026-08-09):** `tmux-path-store` emitted `--bash` only, so
`LOADOUT_CFG_ENABLE_TMUX_PATH_STORE` sat in the parity gate's exception table.
Upstream v1.1.0 added `--zsh` and `--csh`/`--tcsh`; the loadout now bundles
1.1.0 and wires it into all three shells, and the gate exception is gone.

## zsh brought to bash parity (2026-08-08)

The zsh env was a self-described MVP. It now tracks `envs/bash/` under the same
policy as tcsh, but by a **different mechanism, and the difference matters**:
zsh has functions, arrays and `local`, so it **REUSES** the bash env rather than
reimplementing it. `envs/zsh/zshrc` sources `envs/bash/functions.sh`,
`envs/bash/global/config.sh` (+ the corp..user layers) and
`envs/bash/global/aliases.sh` directly. That is why `env-zsh` depends on
`env-bash`, and why its alias surface tracks **automatically** instead of by
discipline -- there is one alias file, not two.

**The corollary is the important part: those three files are SHARED CODE, and a
bashism in any of them is a zsh bug.** Running them under zsh found five, and
every one was also a latent bug for bash users:

1. **`path_modify` / `path_trim` / `std_paths`** used bash's `${!var}` indirect
   expansion and 0-based array indexing. The documented two-arg form
   (`path_append LD_LIBRARY_PATH /opt/lib`) died with `bad substitution` under
   zsh -- while the one-arg PATH form worked, so it looked fine. The old
   `envs/zsh/zshrc` hand-rolled its TERMINFO_DIRS handling to route around it.
   Now eval-indirection + `setopt LOCAL_OPTIONS KSH_ARRAYS SH_WORD_SPLIT`,
   verified byte-identical in both shells.
2. **`pl`** lower-cased with bash-4 `${var,,}` -- a runtime parse error under
   zsh, so `pl` simply did not work there. Now `tr`.
3. **`a`** dumped functions with `declare -f`; `typeset -f` means the same in
   bash and is the only spelling zsh knows.
4. **`check_extended_keys` ate the user's type-ahead.** Its Secondary-DA probe
   reads the reply with `read -r -d 'c'`; when the terminal does not answer,
   that consumes whatever the user typed, up to their first literal `c`. Typing
   `echo MARK-ALIVE` during startup ran `ho MARK-ALIVE` -- and `ho` is the
   loadout's `hostname -s` alias, so it failed with a usage banner rather than
   anything obviously wrong. **This affected bash equally** and had shipped for
   as long as the function existed. It now answers from TERM/tmux *first*
   (neither touches stdin) and refuses the probe when input is already pending.
   `tests/shell-typeahead` (Tier 1) pins it in both shells.
5. **`loadout_detect_online`** backgrounded its probes directly from the calling
   shell; zsh reports jobs it owns, so every startup printed `[9] 2825450` /
   `[9] + done (timeout ...)`. `NO_NOTIFY`/`NO_MONITOR` is NOT enough --
   `LOCAL_OPTIONS` restores them on return and the reap notice lands afterwards
   anyway. The fan-out now runs inside one subshell.

**Two zsh-specific bugs of its own, both pre-existing:**

- **`env-zsh` used the GENERIC installer**, whose `install_path()` syncs with
  `delete=True` -- so every reinstall **deleted
  `~/.config/zsh/{corp,site,team,project,user}`** while the shipped zshrc went
  on sourcing them. Exactly the failure the env-st and env-tcsh handlers exist
  to prevent. The registry's `supports_layers` field does not help: it is only
  ever read by `loadout info` for display. New `_install_env_zsh` handler.
- **Only `.zshrc` and `.zprofile` were linked.** zsh splits startup files by
  shell TYPE and `.zshrc` is **interactive-only**, so `zsh script.zsh` got no
  PATH and none of the exported environment. `.zshenv` is now linked too, with a
  non-exported `_LOADOUT_ZSH_SOURCED` re-entry guard for the double-source that
  causes in interactive shells.

**Prefer zsh-native mechanisms** -- used deliberately, and better than the bash
originals: `chpwd` gives "every cd lists" with no `cd` wrapper and no call site
that can forget (bash needs the `ls` inside `cd()` plus a `__zoxide_cd`
override); `AUTO_CD` replaces the `trap ... ERR` directory-execution hack; and
native `precmd`/`preexec` carry **full OSC 133** semantic zones -- the vendored
`wezterm.sh` is the bash-preexec variant with no zsh path at all, so
`wezterm-integration.zsh` implements the protocol directly. Hooks are registered
by appending to the `${hook}_functions` **arrays**, never via `add-zsh-hook`:
that is an autoloaded function from the zsh function library, which an env-only
HOME does not have, so hooks registered through it silently never fired.

**starship needs the `zsh/mathfunc` MODULE** (its init calls `int()`), so it is
probed with `zmodload -i` first; without that an env-only HOME failed loudly on
every prompt with `failed to load module: zsh/mathfunc` / `unknown function: int`.

`tests/env-shell-parity` gained a zsh section. It does not compare alias lists
(they are the same list by construction) -- it asserts the **reuse wiring is
still in place**, since a well-meaning "cleanup" that copied the aliases into a
zsh-native file would silently end the tracking, and compares the bashrc-level
export surface that zsh does have to reimplement.

Absent by upstream limitation only: IceCream-Bash (`${!var}` + `export -f`).
Unlike tcsh, **starship, fzf and zoxide all work** -- upstream ships real zsh
support for each, and `tmux-path-store` joined them in v1.1.0.

## Where things stand right now

- **Released: `v2026.08.09`** -- https://github.com/smprather/engineering-loadout/releases/tag/v2026.08.09
  Signed tag (ED25519 `SHA256:XlxLB4kh...`), published (not a draft), assets
  verified by re-reading the release rather than trusting the publish exit code:
  `nvim-plugin-stash.tar.bz2` (343,752,246 B, stash asset REUSED -- sha256
  unchanged, not re-uploaded), `sha256sums.txt`, `default.content-manifest`.
- **Re-released the same day**, per the date-based-tag policy: the tag first
  pointed at `b4e954f` (the tcsh/zsh parity release), then moved to `7388727`
  when the `uv tool install --force` fix landed. Binary smoke re-ran from scratch
  (`loadout_main.py` is in the smoke fingerprint): all 300 binaries OK.
- `origin/main` == the released commit `7388727`; working tree clean. The first
  publish that day needed a manual branch push; the second did not -- see below.
- Malware scan CLEAN, 0 detections across 77,051 files.
- Class **C** (registry bumps + env packages). Tier 3 container green, currency
  sweep done (4 packages, below), assurance re-pin **not applicable**.
- **No assurance re-pin was needed, despite class C.** Records exist only for
  `crate-store`, `git-nvim`, `nvim`, `rust` and `treesitter-parsers`;
  `RELEASE.md` §4 defines the re-pin as updating a *bumped* package's record, and
  none of those five moved. The `tree-sitter` **CLI** went 0.26.11 -> 0.26.12,
  which does not touch the `treesitter-parsers` record: that record pins
  `ts-0.26.8` as the runtime the parsers were *built* against, and the parsers
  were not rebuilt. `tests/assurance-check` passes 33/0.

### FIXED: the release commit was on no remote branch (2026-08-09)

`./build/release` pushed the **tag** and nothing else. After v2026.08.09
published, `origin/main` was still at `8969353` (the *previous* release) while the
release advertised `b4e954f` -- a commit reachable only through the tag. Anyone
pulling `main` got the pre-release tree. Pushed by hand at the time; `main` and
the tag now agree.

Every check in `RELEASE.md` §9 passes while this is true. The tag is real, its
signature is good, all three assets are present and byte-correct. Same shape as
the 2026-07-22 unsigned-tag incident: **invisible unless something re-reads state
afterwards.**

**The fix ran for real on the same-day re-release** and did exactly what it should,
before the tag existed:

```
To https://github.com/smprather/engineering-loadout.git
   b4e954f..7388727  main -> main
  pushing branch main (7388727) ...
  origin/main verified at 7388727
```

Fixed in the tool, not in the prose, because a documented step nothing enforces
is the failure mode this repo keeps hitting. Step 4 of `build/release` now calls
`_push_release_branch()` **before** creating the tag: it refuses a detached HEAD,
pushes the current branch, and re-reads `git ls-remote origin refs/heads/<branch>`
to confirm the remote ref moved. Ordering is deliberate -- a branch pushed without
a release is an ordinary commit, a release published without its branch is the
broken state -- so a failure blocks the release instead of half-publishing one.
All three paths (push, detached-HEAD refusal, push-failure refusal) were
exercised against a scratch remote. `RELEASE.md` §8, §9 and failure-catalogue
entry 13 record it.

### python-tool installs now pass `--force` (2026-08-09), and the near-miss behind it

`install_python_tools` now passes `--force` to `uv tool install`. The reasoning
went wrong twice before it went right, so the corrected version is the one worth
keeping:

**What is actually true.** `uv tool install` no-ops on an already-installed tool
(prints ``​`<pkg>` is already installed``, exits 0, changes nothing) **unless the
requested options differ from the `[tool.options]` block in the tool's
`uv-receipt.toml`** -- which records `find-links`. The payload has chunked wheels,
so `_prepare_wheels_dir` rejoins into a fresh `/tmp/.loadout-wheels.XXXXXX` every
run; that path lands in the receipt, never matches next time, and uv reinstalls.
**Upgrades land today by accident of the temp path, not by design.** Delete the
last chunked wheel and `_prepare_wheels_dir` returns the stable payload `wheels/`
dir, the options match, and all 12 `uv_tool` packages freeze silently while the
installer still prints `Installed Python tool: <name>` off uv's exit 0.

**Two claims I made and had to retract**, both stated confidently before being
checked, both wrong:

1. *"`./loadout upgrade <python-tool>` cannot upgrade anything."* False -- the
   temp-dir difference means it does. The no-op reproduces only with a stable
   `--find-links`.
2. *"`tmux-path-store` is in no group, so the curated set never installs it."*
   False -- `@engineering-loadout` pulls `@shared`, and the synthetic `@shared`
   includes every non-optional non-env package, this one among them.
   `./loadout resolve @engineering-loadout` lists all 11 python-tools.

**Both retractions came from running the check instead of reasoning from the
code** -- `./loadout resolve` and a receipt diff each took seconds and each
overturned a confident conclusion.

**The original symptom is still UNEXPLAINED, and that is recorded rather than
papered over.** A box sat at `tmux-path-store` 1.0.0 across two releases that
shipped 1.0.1 and 1.1.0. I then guessed a third time -- "no full install ran
between the bumps" -- and the owner corrected it: they ran an install naming
`tmux-path-store` explicitly ~20 minutes before, and did not get 1.1.0. That
selection reaches `install_python_tools`, and the temp-`find-links` theory
predicts a reinstall, so the theory does not account for what was observed.
Something else no-opped that run. `--force` makes the question moot for users, so
it was deliberately not chased further; if a python-tool is ever found stale
again, start here rather than re-deriving. Candidates not yet excluded: the
ETXTBSY/pending-daemon deferred-replace path, and a uv receipt comparison that
ignores `find-links` under conditions not reproduced here.

**The first version of the test was a no-op gate.** It installed twice and
asserted the second run was not a no-op -- which passes with or without `--force`
under today's chunked payload, because the temp path already forces a reinstall.
It was caught by deliberately removing `--force` and watching it still pass.
`tests/install-python-tool-upgrade` now asserts the flag reaches the logged uv
command line, which is the property that survives the payload changing
underneath it; removing `--force` fails it on the first assertion. Registered in
Tier 2 of `tests/run-all`.

### Recorded deviation: ClamAV signatures 6 days stale at release

Both v2026.08.09 publishes scanned with ClamAV signatures 6 days old
(`/var/lib/clamav/daily.cld` dated 2026-08-03; YARA-Forge was same-day). The scan
is a blocking gate and passed both times, but per `RELEASE.md` §2b that is weaker
evidence than a fully-current scan. Recorded rather than left implicit; better
than the xephyr release's 17 days. Still outstanding -- `freshclam` needs root,
so it did not run during either release. To clear it:

```bash
sudo freshclam && ./build/scan-for-malware --no-cache
```

`--no-cache` is load-bearing -- the clean verdict is cached and keyed on the
ClamAV signature fingerprint, so a plain re-run reuses the cached pass.

### What shipped in v2026.08.09

| area | detail |
|---|---|
| tcsh | policy reversal + full port to bash parity (see top of this file); `tests/env-shell-parity` is the gate |
| zsh | brought to bash parity by **reuse** of the shared bash files, not reimplementation |
| shared-shell fixes | 7, all latent for bash users too -- `path_modify`/`path_trim`/`std_paths` `${!var}`, `pl` `${var,,}`, `a` `declare -f`, `check_extended_keys` type-ahead, `loadout_detect_online` job notices |
| currency | `tmux-path-store` 1.1.0, `lua-language-server` 3.19.0, `gnuplot` 6.0.5, `tree-sitter` 0.26.12 |
| new build scripts | `build-lua-language-server.sh`, `build-gnuplot.sh`, `build-tree-sitter.sh` |
| gate change | `tests/prebuilt-binaries` now requires exit 0 (42 binaries had been passing on non-zero) |

### What shipped in v2026.08.07

| area | detail |
|---|---|
| new packages | `gtkwave` 3.3.116, `klayout` 0.30.10, `verilator` 5.050, `ipython` 9.16.1 |
| new group | `@eda` (gtkwave + klayout + verilator), member of `@engineering-loadout` |
| new bundled lib | `libQt5XmlPatterns.so.5` added to `gui_libs` (KLayout's `HAVE_QT_XML`) |
| kebab migration | all five first-party executables renamed -- see below |
| currency | `uv` 0.12.3, `ruff` 0.16.2, `ty` 0.0.69, `biome` 2.5.7, `nodejs` 26.7.0, `ipython` 9.16.1 |
| new build scripts | `build-gtkwave.sh`, `build-verilator.sh`, `build-klayout.sh`, `build-liberty-filter.sh`, `build-tmux-path-store.sh` |
| gate fixes | four, listed under *Test-gate fixes* below |
| env fix | `modules-init.bash` inconsistency flush + `MODULEPATH` preservation |

### Fixed: the "no plugin stash" warning sent users in a loop (2026-08-08)

`./tools/fetch-stash` succeeded, and the very next `./loadout install @envs-all`
still printed `no plugin stash found, so NO PLUGINS were installed` with
instructions to run `./tools/fetch-stash` and re-run — i.e. exactly what had just
been done. Nothing in the message hinted at the real cause.

**Fetching is step one of two.** `_resolve_nvim_stash` looks only at the
INSTALLED tree (`<local>/share/nvim/loadout/vendor/plugin-stash`). Getting the
archive into the repo does not extract it; that is `install_nvim_plugin_stash`,
gated on the **`nvim-plugin-stash`** package. That package is `kind: data` and is
a member of **no group at all**, so `@shared` reaches it only via the synthetic
"every non-group, non-optional, non-env package" rule — and `@envs` / `@envs-all`,
being env-only by definition, never do. A user installing env packages therefore
gets `env-nvim` (which is what the plugin phase is gated on) with no stash.

The warning now branches on whether the archive is actually present in the repo,
and the archive-present message names the package instead of repeating the fetch
advice. Fix for anyone hitting it:

```bash
./loadout install nvim-plugin-stash treesitter-parsers env-nvim
```

`treesitter-parsers` is worth naming alongside it — it is also `kind: data`, so
an `@envs-all` install has no parsers either, for the same reason.

### RESOLVED: the crate-store policy gate (was red since v2026.08.07)

`tests/run-all` failed `crate-store policy` because the v2026.08.07 partial sweep
bumped `uv` and `ty` in `payload/packages.json` without re-pinning
`build/rust-tool-locks.txt`. Fixed properly -- re-pinned **and** rebuilt, because
editing the pins alone would have turned a true failure into a false green while
the shipped store stayed built from the old refs.

Three things came out of it worth keeping:

- **`tree-sitter` was absent from `rust-tool-locks.txt` entirely.** Its Cargo.lock
  closure had therefore never been in the shipped store, so the tool was bundled
  with **no offline rebuild path at all** -- on an air-gapped node you could not
  have rebuilt it. Now pinned (295 crates); the store went 2195 -> 2272.
- **`ty` is a new skip:** `no lock and generate-lockfile failed`, so its closure is
  not in the store. It joins the documented skips (`time-plot`, `text-serdes` --
  first-party HEAD; `surfer` -- vendored git submodules). `ty` ships as a
  downloaded prebuilt, so nothing is broken today, but it cannot be source-built
  offline.
- **`assurance-check` passed while `assurance/crate-store.lock` was stale**, because
  the record and the lock were stale *together* (both 2195). Only
  `verify-crate-store --check-lock` compares the lock against the actual store.
  Re-pinning means: `--emit-lock`, then update the record's count, `verified_utc`,
  `yara_forge_tag` and all eight artifact hashes -- and do it **after**
  `strip-all-elf-binaries`, since strip can rewrite archives and invalidate hashes
  pinned before it runs.

### Currency sweep done this release (2026-08-09)

| package | move | how |
|---|---|---|
| `tmux-path-store` | 1.0.1 -> **1.1.0** | upstream added `--zsh` and `--csh`/`--tcsh`; now wired into all three shells |
| `lua-language-server` | 3.18.2 -> **3.19.0** | upstream linux-x64 prebuilt, floor GLIBC_2.17 |
| `gnuplot` | 6.0.2 -> **6.0.5** | EL8 source build, no Qt |
| `tree-sitter` | 0.26.11 -> **0.26.12** | EL8 source build -- upstream prebuilt needs GLIBC_2.35 |

**Three of those four had no build script.** `build-lua-language-server.sh`,
`build-gnuplot.sh` (a prose note existed, no script) and `build-tree-sitter.sh`
are new, each with an `ADDING_BINARIES.md` entry. Every one asserts the EL8 glibc
floor and the dependency closure rather than assuming them.

**The trap that cost a build:** `build-tree-sitter.sh` first failed with
`failed to select a version for anyhow ^1.0.100 (locked to 1.0.103) ... perhaps a
crate was updated and forgotten to be re-vendored?`. That reads as store
corruption; it is not. `env-cargo` writes a `~/.cargo/config.toml` replacing
crates-io with the loadout's offline store, so a plain `cargo build` on a machine
with the loadout installed resolves against the **installed** store -- whatever
was last deployed, not what you are about to ship. Fix is an isolated
`CARGO_HOME`, the same bypass both crate-store builders and the surfer note use.
The script now does it and says why.

### The probe now requires exit 0 (2026-08-08/09)

`tests/prebuilt-binaries` used to pass **any** exit code outside `{126,127,139}`,
so a binary that never ran could score green off its own error message. Audited
all 300 installed binaries: **42 were passing on a non-zero exit.**

The rule is inverted: **exit 0 is the pass condition.** A non-zero exit is
accepted only through an `EXPECT_NONZERO` entry that pins the flags, the code and
a required output substring, so every acceptance is a written-down decision. 14
entries; the rest gained correct `PROBE_FLAGS` (`xterm -version`, `pdftotext -v`,
`restic version`, `lld -flavor gnu --version`, ...).

**What it caught that had been shipping:**

- **`jupyter-labhub` was a permanently dead command** on every user's PATH -- a
  JupyterHub-only entry point from the jupyterlab wheel, and jupyterhub is
  deliberately not bundled. The installer now prunes it.
- **The `spice-subckt-rc-reduce` functional smoke had been dead since the kebab
  rename** -- gated on the old underscore name, so the smoke written *because*
  the tool has no `--version` never ran. That is a FIFTH edit the "a rename is
  four edits" lesson does not list: functional smokes keyed on the binary name.
- **`firefox` and `idle3`/`idle3.14` fail in the Tier 3 container** and always
  had; the old rule scored them green off their error text in every container
  run. firefox's sandbox calls `clone(CLONE_NEWUSER)` before it will print
  `--version` and Docker blocks it; IDLE imports Tkinter at module scope, before
  argument parsing, so it cannot reach exit 0 without a loadable Tk.

Those last three needed a new mechanism, not an exception. They exit **0 on a
normal host** and fail only in the container, so an `EXPECT_NONZERO` entry -- which
pins one exit code -- would be wrong in both directions. `HOST_REQUIRED_CAPABILITIES`
probes the facility (`unshare -U true`, `python3.14 -c "import tkinter"`) and
skips only when it is genuinely absent, so on a host that HAS it the binary must
still exit 0. That widens the skip set without weakening the gate.

Also fixed: `real_elf_for_wrapper` could not resolve `lib/firefox/firefox-bin`
(it knew `<name>` and `<name>.bin`, not upstream's `<name>-bin`), so the firefox
wrapper was exec-probed instead of resolved for the host-`.so` skip.

### Deferred, each with a reason (next currency sweep)

| item | why deferred |
|---|---|
| `vim` / `gvim` 9.2.0901 -> 9.2.0927 | source build; vim tags patches daily, bump on a deliberate cadence |
| `fresh` 0.3.8 -> 0.4.7 | major bump, deserves its own change; the upstream prebuilt also needs GLIBC_2.35 against EL8's 2.28, so it is an EL8 source build |
| `jupyterlab` 4.6.1 -> 4.6.2 | **blocked**, not forgotten: pip's `--platform` resolver backtracks into `httpcore 0.18.0` then reports no usable `anyio`; constrain that and it moves to `jupyterlab-server`. Not worth a hand-assembled wheel set for a patch bump |
| ~~`pdftotext`~~ | **RESOLVED 2026-08-10** -- was "correctly pinned: poppler >= 23.01 needs freetype >= 2.10, EL8 has 2.9.1". The loadout now source-builds freetype 2.14.3 and pdftotext moved 22.12.0 -> 26.04.0. New (real) ceiling is fontconfig 2.15 at poppler 26.06+; see below |

### Unspecced idea the owner raised (2026-08-07)

Expose the bundled wheelhouse (`payload/<platform>/wheels/`, 203 wheels + 5
chunked, 549 MB) to *users*, not just the installer, so `uv pip install numpy`
works air-gapped. Findings from the initial look, so it need not be re-derived:

- uv has **no** online->offline fallback; an unreachable index is an error. But it
  is fully env-var driven (`UV_FIND_LINKS`, `UV_NO_INDEX`, `UV_OFFLINE`), so
  **do not write a `uv` wrapper** -- shadowing `uv` on PATH invites the same class
  of breakage this repo already documents for `git` and `ssh`.
- The repo already computes the online signal: `bashrc` sets `LOADOUT_ONLINE=1/0`
  once per login and exports it to child shells and tmux panes. Wire the uv env
  vars to that.
- Two open decisions: the wheelhouse is **not installed today** (read from the repo
  at install time), so exposing it means a new `kind: data` package (~549 MB per
  shared tree) or pointing at the shared-prefix repo path; and `UV_FIND_LINKS` on
  by default is a reproducibility footgun (a user's project could silently resolve
  a loadout-pinned wheel), so it should be opt-in behind a `LOADOUT_CFG_*` toggle.
- Only `scipy` and `sympy` are genuinely missing from the current wheel set.

## Kebab-case executable migration (2026-08-05..07) -- COMPLETE

Every first-party executable is kebab-case. The name always comes from upstream's
`[project.scripts]` / `[[bin]]`, never from the registry, so each needed the
upstream change first -- renaming `bins` here without it makes the registry lie
about what the wheel or binary installs.

| package | was | now | built from |
|---|---|---|---|
| `liberty-tools` | `liberty_format`, `liberty_view` | `liberty-format`, `liberty-view` | rolling HEAD |
| `text-serdes` | `enc`, `dec` | `text-serdes-enc`, `text-serdes-dec` | rolling HEAD |
| `liberty-filter` | `liberty_filter` | `liberty-filter` | tag `v2026.08.06.1` (Cargo 1.0.1) |
| `spice-subckt-rc-reduce` | `spice_subckt_rc_reduce` | `spice-subckt-rc-reduce` | tag `v0.1.1` |
| `tmux-path-store` | `tmux_path_store` | `tmux-path-store` | tag `v1.0.1` |

The only underscore executables left are `verilator_bin`, `verilator_coverage`,
`verilator_coverage_bin_dbg`, `verilator_gantt`, `verilator_profcfunc` -- upstream
Verilator's own names. **Do not "finish the job" on those.**

`text-serdes` was more than a case change: bare `enc`/`dec` became namespaced. Good
PATH hygiene, but it **breaks user aliases** -- mention it in user-facing notes.

### Renaming an executable moves FOUR things

Learned across three packages in one session:

1. `bins` in `payload/packages.json` (names the payload stem / expected launcher),
2. the binary-name key in `build/farm-versions` **and its match regex** -- the
   *program* name changes too (`liberty-format --version` prints
   `liberty-format 1.0.1.dev0`), so updating only the key leaves the probe blind,
3. `EXPECT_BIN` / `EXPECT_SCRIPT` in the build script,
4. **delete the old `bin/<old-name>.bz2` or the superseded `<dist>-*.whl`** --
   `loadout_package_bin` writes the new stem but does not remove the old, and
   leaving both makes `doctor` report an unregistered payload; a stale wheel
   sibling leaves two versions of one dist in `--find-links`.

Every build script now reads the name from the ARTIFACT (`Cargo.toml [[bin]]`, or
the built wheel's `entry_points.txt`) and hard-fails naming the mismatch.

### Two packages had NO build script at all

`liberty-filter` and `tmux-path-store` were bundled with no build script and no
`ADDING_BINARIES.md` note -- the same provenance gap twice, both from the
`ad63c48` bootstrap-snapshot era. liberty-filter's origin had to be recovered from
the shipped binary's own strings (`/tmp/liberty-rebuild-*/liberty-filter`, a
*separate* repo from liberty-tools). Both now have scripts and notes. **If you
bundle a wheel or binary by hand, write the script in the same change.**

Other things worth keeping:

- **liberty-filter builds offline with no crate-store**: depends on flate2 + regex,
  but upstream commits `vendor/` (466 files) + a `.cargo/config.toml` redirecting
  crates-io to vendored-sources. The script asserts both, so a future de-vendoring
  fails loudly rather than quietly hitting the network.
- **Prefer the tag; refuse `-dev`.** liberty-filter HEAD is the post-release bump
  `1.0.2-dev`. The script refuses `-dev`/`rc` and stamps Cargo's semantic version
  (not the date-based tag) because `--version` prints the Cargo one -- a mismatch
  makes `check-versions` permanent noise.
- **liberty-filter flag trap:** `--filter-in-cells` is an exception list to
  `--filter-out-cells`, not a standalone allowlist
  (`match_filter_out_cell && !match_filter_in_cell`). Used alone it drops nothing,
  which looks exactly like a pass-through bug -- it produced one false bug report
  here. The build smoke passes both flags and asserts 1308 -> 149 cells.
- **`spice-subckt-rc-reduce`'s documented name asymmetry is gone** as of v0.1.1;
  `ADDING_BINARIES.md` records it as history, not a rule.

## Four new packages (gtkwave, klayout, verilator, ipython) -- 2026-08-05

Target users are **industrial** engineers who already have paid tooling, so this is
deliberately not an open-source-EDA-flow push.

| package | payload | notes |
|---|---|---|
| `ipython` | **0** | whole wheel closure was already bundled for jupyterlab/pygwalker |
| `gtkwave` | ~1.4 MB | GTK3 against `gui_libs`; 16 binaries; **no wrapper needed** |
| `verilator` | ~5 MB | relocatable Perl driver; needs **host perl** + the user's `g++` |
| `klayout` | ~53 MB (2 shards) | Qt5 + embedded Ruby 3.3 + portable Python 3.14 |

`@eda` is deliberately *only* the new tools: `ngspice`, `spice-subckt-rc-reduce`
and `espresso` stay in `@scientific`, and `surfer`/`liberty-tools`/`lefdef-tools`
stay reachable by name, so nothing existing changed behaviour. Migrating them in is
a reasonable follow-up.

Build notes for all five source builds are in `build/ADDING_BINARIES.md`;
per-package runtime behaviour is in `AGENTS.md`.

**`klayout` closed a loop that had been open in a build note only.** The `ruby`
entry called ruby "the interpreter KLayout embeds for DRC/LVS scripting" -- but
KLayout was never built, and that intent was recorded *nowhere else*. If you add a
package because another depends on it, say so in THIS file too.

### KLayout requires host GLVND even for BATCH use -- do not promise otherwise

Its clean-container status is **skipped by host contract, not passing**. The 12
`strm*` converters link the same `libklayout_lay`/`laybasic` set as the GUI, so a
node with no OpenGL runs *nothing* in this package -- not `klayout -zz`, not
`strm2gds`. EL8 supplies `libGL.so.1` via `mesa-libGL`.

This is the one thing Tier 3 caught that local testing could not: the dev box has
`libGL`, so Tier 1, Tier 2 and hand-verification under `env -i` were all green
while the container failed 14 checks. **Textbook build-box masking.**

KLayout also blocks on a **first-run modal dialog** (`lay::TipDialog` via
`MainWindow::about_to_exec`) until dismissed -- every user sees it once.
Suppress with `tip-window-hidden` in `~/.klayout/klayoutrc` if rolling out to a farm.

## Test-gate fixes (2026-08-05..07) -- four, all of the same family

Each was a gate that was green when it should not have been:

1. **The generic binary probe scores errors as success.** Any exit code outside
   `{126,127,139}` passes, so gtkwave's `rtlbrowse`/`shmidcat`/`twinwave` -- which
   exit **255** printing `Could not open '--version'` -- were green *off an error
   message*. A broken FST reader would have shipped. All three new packages now
   have real functional probes in `smoke_runtime_layout`; the verilator one lints a
   **deliberately broken** module and requires that to fail. **Other silent-255
   binaries deserve the same audit.**
2. **`gen-readme-table --check` had no missing-row check** -- only stale versions,
   so a package with *no row at all* passed. Its own docstring cites "6 missing
   packages" as the failure it was written for. Now checks both.
3. **The host-`.so` skip could not see through a wrapper** to `lib/<pkg>/<name>`,
   only `bin/<name>.bin`, so KLayout's 13 launchers hit a fatal 127 instead of
   skipping. `real_elf_for_wrapper()` now searches `lib/*/<name>[.bin]` too. A
   `lib/<name>/<name>` guess would NOT work: one lib dir, 13 differently-named
   launchers.
4. **No pinned `python-tool` was addressable in `build/update`** -- `jupyterlab`,
   `visidata`, `pygwalker`, `parity-plot` and `ipython` were all rejected as
   "unknown package(s)" because `ALL_KNOWN` covered `kind: bin` but never
   `python-tool`. `check-versions` flagged them outdated from PyPI while `update`
   could not even print guidance: a live signal with no way to act on it. New
   `PYPI_WHEEL` class + guidance printer.

## Environment Modules inconsistency flush (2026-08-05)

`envs/bash/global/modules-init.bash` detects an **inconsistent** inherited EM
state before re-sourcing `init/bash` -- a loaded modulefile deleted on disk, or
`LOADEDMODULES` and `_LMFILES_` not 1:1 (e.g. `LOADEDMODULES=foo` with an empty
`_LMFILES_`, which makes the next `module load` error *"Loaded environment state
is inconsistent"*). A healthy state is left alone; no purge.

Two things about it are load-bearing:

- **`MODULEPATH` must survive the flush.** It matches a naive `^MODULE` sweep, and
  the first cut of this cleared it. That is worse than the bug being fixed and it
  is *silent*: with `MODULEPATH` unset, upstream `init/bash` substitutes its own
  default (`<local>/lib/modules/modulefiles`), so the site's modulefiles are
  quietly swapped for the loadout's rather than obviously disappearing. The narrow
  `unset MODULESHOME MODULES_CMD` immediately below documents the same invariant.
- **It is fork-free.** This runs in every interactive shell that sets
  `LOADOUT_CFG_USE_LOADOUT_MODULES=1`, and the common case is "do nothing", so it
  uses bash array splitting and `${!prefix@}` instead of `tr|grep` pipelines and
  `printenv|grep|cut`. Same reasoning as `loadout_restore_echo` replacing its
  forking `stty` snapshot.

`tests/install-modules` gates both halves: one case poisons the state and asserts
recovery *and* that `MODULEPATH` is intact, another asserts a healthy state
survives a re-source with its module still loaded. Verified to fail against the
pre-fix file. **Watch the subshell trap when extending it:** `module` is a
function that `eval`s emitted shell code, so `$(module load demo)` applies the
environment changes to a subshell and discards them -- capture stderr to a file,
never with a command substitution.

## Repo root reorganised (2026-08-05)

GitHub renders the repo root first and nine utility scripts were burying the
README. They moved along a line `.gitattributes` already drew:

- **`build/`** (dev-only, already export-ignored wholesale): `update`, `release`,
  `strip-all-elf-binaries`, `scan-for-malware`, `split-bz2`, `dev-onboard`,
  `export`. Seven individual `export-ignore` entries collapsed into the one
  `/build` line.
- **`tools/`** (ships; deliberately *not* export-ignored): `fetch-stash`,
  `refresh-stash`, joining `download-release.ps1`.

Root now holds only entry points and config. **The trap:** every moved Python
script derived its repo root as `dirname(abspath(__file__))`, which silently
became `build/` or `tools/`. `build/release` was worst -- it built
`tests/prebuilt-binaries` and `build/farm-versions` off that value, so the
release gates would have searched `build/tests/` and `build/build/`. All fixed;
verified by importing each module and printing the resolved root, not by reading
the diff. `hooks/pre-commit` execs the new path. Commands are now
`./build/update`, `./build/release`, `./build/strip-all-elf-binaries`,
`./tools/fetch-stash`, etc.

## PENDING: linux-process-resource-monitor (blocked on upstream)

`github.com/smprather/linux-process-resource-monitor` is to be added as a
first-party **rolling-git `python-tool`**, same class as `text-serdes`. Nothing
has been committed for it yet -- no registry entry, no wheels.

Shape: Python CLI (`process-monitor`, `resource_monitor` console scripts) that
owns help and offline Plotly reports, and `os.execv`s a **Rust sampler binary**
carried *inside* the wheel at `process_monitor_tool/bin/process-monitor`
(resolved via `importlib.resources`, `PROCESS_MONITOR_CORE` overrides). No PATH
collision despite both being named `process-monitor`.

**The blocker, and it is upstream's to fix:** `uv build --wheel` *succeeds* but
emits `py3-none-any` containing only the `.py` files -- **no Rust binary**.
There is no `[build-system]` table, so PEP 517 falls back to setuptools and
`scripts/build-wheel.py` (which runs `cargo build --release` and copies the
binary in) never runs. `./build/update`'s rolling-git path calls exactly
`uv build --wheel`, so it would ship a tool that installs cleanly and then dies
with its own `missing Rust core binary` message. Owner has been asked to add a
`[build-system]` whose backend does what `build-wheel.py` does, give the wheel a
platform tag, and drop `[tool.uv] package = false`.

Two things already settled, do not re-litigate:

- **`kaleido==0.2.1` is fine, keep it.** It was wrongly flagged as a conflict
  with the bundled `kaleido 1.3.0`. `uv tool install` isolates per tool and the
  wheelhouse already carries multiple versions of several deps. 0.2.1 also
  bundles its own headless Chromium, so PNG/PDF export works on a Chrome-less
  farm node, which 1.x cannot do. Costs ~76 MB of payload, nothing else.
- **plotly 6.9.0 still supports kaleido v0.** `plotly/io/_kaleido.py` keeps
  `kaleido_major() < 1` branches and the `PlotlyScope` path; `kaleido>=1.3.0`
  appears only under plotly's optional `[kaleido]` extra. Deprecation warnings,
  but functional.

Its other deps are already bundled: `plotly 6.9.0`, `rich_click 1.9.8`. Rust
edition 2024 needs cargo >= 1.85; the box has 1.96.0.

Also corrected in `AGENTS.md` while diagnosing this: the claim that
`--platform manylinux_2_28_x86_64` finds manylinux1/2010/2014 wheels. It does
not -- pip matches tags exactly, which is what made kaleido 0.2.1 look like it
had vanished from PyPI.

## Sweep finished, 2026-08-04 -- 21 packages, and what is genuinely left

The currency debt from 2026-08-03 is cleared. Everything outdated that could be
built on EL8 has been, and the things that could not are named below with the
reason, not left as a vague "TODO".

**Source-built this round:** vim + gvim 9.2.0901, octave 11.3.0, fish 4.8.1,
flameshot 14.0.0, numr 0.8.0, tree-sitter 0.26.11, htop 3.5.2, rsync 3.4.4,
xsel 1.2.1, yank 1.4.0, yara 4.5.8. **Prebuilt:** rg, uv, ruff, ty, fzf, just,
lazygit, btm, amux, agent-deck, biome, nodejs 26.6.0.

**Three build scripts were broken or missing** and are now fixed, which matters
more than the version numbers:

- `build/build-vim.sh` is **new**. `build-gvim.sh` took no `--tag`, wanted a
  checkout you had prepared, and only *printed* the packaging commands. The new
  one builds all three artifacts (terminal vim, gvim, the runtime archive) from
  one checkout so they cannot drift apart, enforces `--without-wayland` for
  terminal vim with a hard NEEDED check, and carries an EL8 Pango back-port
  (9.2.0901 calls `pango_font_metrics_get_height()`, Pango >= 1.44; EL8 has
  1.42.3).
- `build/build-octave.sh` had `$ORIGIN` in a double-quoted `echo` (unbound
  variable under `set -u`, so it died *after* a full compile), `11.1.0`
  hardcoded in six paths, and a fixed `/tmp/octave-install` that had
  accumulated two versions. Now `--tag`-driven and version-scoped. Octave's
  registry entry is version-bearing: `version`, `sentinel` and three
  `octave/<VERSION>` paths move together.
- `build/build-simple-c.sh` is **new**, covering htop, rsync, xsel, yank and
  yara -- five tools that had no script and no `ADDING_BINARIES.md` note at all,
  in a repo that mandates one per tool.

**The EL8 glibc floor check rejected four upstream prebuilts** (bottom 2.34,
fresh 2.35, tree-sitter 2.39, htop). Each would have installed cleanly here and
been dead on a stock farm node.

Genuinely blocked, with reasons:

- **jupyterlab stays at 4.6.1.** pip's `--platform` resolver backtracks into
  httpcore 0.18.0 and then reports no usable `anyio`; constrain that and the
  conflict moves to `jupyterlab-server`. Every package resolves individually and
  the deps are already bundled -- this is a cross-platform-resolver limitation,
  not a real incompatibility. Not worth a hand-assembled wheel set for a patch
  bump.
- **`pdftotext` stays pinned** (poppler >= 23.01 needs freetype >= 2.10; EL8 has
  2.9.1).
- **vim tags patches daily.** 9.2.0901 was current at build time and 9.2.0907
  landed hours later. Chasing it is a treadmill; bump on a deliberate cadence.
- **fish still cannot build fully offline** -- see the crate-store entry below.

## Crate store refreshed, 2026-08-04 -- and the three things still open

Cleared the `rust-crate-store` debt the previous entry recorded. Root cause was
**not** a stale store as such: `build/rust-tool-locks.txt`, which pins the refs
the superset builder harvests, had drifted from `payload/packages.json` on 11
tools. fish was pinned at 4.7.1 while the loadout shipped 4.8.1, so the store
never saw 4.8.1's localization deps. `surfer` and `tokei` were absent entirely.
Re-pinned, added, rebuilt: 2101 -> 2199 crates, assurance record re-pinned, and
`build/verify-crate-store --check-policy` now gates ref-vs-registry drift in
Tier 1.

**Two builders, do not confuse them.** `build-crate-store.sh` makes the lean
user-only store and legitimately bans `aws-lc-*`; `build-tool-crate-store.sh`
makes the **shipped** superset and downgrades that ban to a warning because a
bundled tool's lock may pin it (numr's does, via `reqwest -> rustls`). The
`[build] script =` field in `assurance/records/crate-store.toml` is the
authority on which one ships. Both now isolate `CARGO_HOME`, because each
previously resolved against the store it was rebuilding and so could never add
a crate -- a stale store could not be repaired by rebuilding it.

Still open, deliberately recorded rather than hidden:

- **fish cannot build fully offline from the store.** 4.8.1 takes `fluent`,
  `fluent-bundle`, `fluent-syntax` and `intl-memoizer` from a git fork
  (`danielrainer/fluent-rs` at a pinned rev). `cargo local-registry` mirrors
  registry crates only, so git deps are structurally out of scope. Vendoring
  that dep separately (a git mirror, as the nvim plugin stash does) is the only
  route. `unic-langid` -- the crate the build actually failed on -- is a
  registry crate and is now present.
- **The builder skipped `surfer` with "sync failed".** Surfer vendors f128 and
  instruction-decoder as git submodules (see `ADDING_BINARIES.md`), which is the
  likely cause; its closure is therefore not in the store.
- **`time-plot` and `text-serdes` skipped**: "no lock and generate-lockfile
  failed". Both are first-party rolling repos tracked at HEAD.

## Currency sweep, 2026-08-03 -- what moved, what did not, and why

Ran the sweep the previous entry said was owed. It cleared a good part of the
debt and turned up two destructive bugs in `./build/update` itself, both now fixed.

**Bumped and verified** (15 packages): `rg` 15.2.0, `fzf` 0.74.2, `uv` 0.12.1,
`ruff` 0.16.1, `ty` 0.0.65, `just` 1.57.0, `lazygit` 0.63.1, `btm` 0.14.7,
`amux` 0.0.20, `agent-deck` 1.11.0, `biome` 2.5.6, `nodejs` 26.6.0,
`fish` 4.8.1, `numr` 0.8.0, `flameshot` 14.0.0. Plus `text-serdes` -> `e624d2d`
and the YARA-Forge ruleset.

**Two `./build/update` bugs, both silent, both would have shipped:**

- `./build/update env-nvim` repacked *this box's* `~/.local/share/nvim/lazy` over the
  plugin stash: 328 MB of bare mirrors replaced by 47 MB of flat plugin dirs
  that lazy cannot clone from. The stash is gitignored *and* excluded from
  `.content-manifest`, so there was no baseline to diff and no gate to fail;
  recovery needed `./tools/fetch-stash` against a published release.
- `./build/update nodejs` with no `--tag` runs `nvm install --lts` and bundled the
  build box's own v26.2.0, stamping the registry *backwards* from 26.5.0. A
  bare `./build/update` -- what the procedure told you to run -- did this.

Both are fixed, and `./build/update` now hard-errors on any version that goes
backwards (`--allow-downgrade` to override).

**Left undone, deliberately** -- the remaining packages are all source builds
and this was cut as a "ship what is verified" release rather than claiming a
class C it did not meet:

- `vim`/`gvim` 9.2.0901 and `octave` 11.3.0. **`build-gvim.sh` and
  `build-octave.sh` take no `--tag`** and want a source checkout you supply --
  AGENTS.md's claim that all `build/build-*.sh` enforce `--tag` is wrong for
  these two.
- `htop`, `rsync`, `xsel`, `yank`, `yara`: **no build script and no
  `ADDING_BINARIES.md` note at all.** Bumping them means authoring the
  procedure first, which the repo mandates anyway.
- `tree-sitter` 0.26.11 and `fresh` 0.4.6: upstream prebuilts need GLIBC 2.39
  and 2.35 against EL8's 2.28, so both become EL8 source builds.
- `gnuplot` 6.0.5, `jupyterlab` 4.6.2 (wheel closure).
- **`rust-crate-store` is stale.** fish 4.8.1 only built after bypassing the
  offline store with a fresh `CARGO_HOME`, because upstream added
  `fish-fluent`/`unic-langid`. The shipped binary is fine but that build is no
  longer offline-reproducible, and the same wall is waiting for every other
  Rust package. Refreshing the store is the real fix and should come before the
  next Rust bump.

`pdftotext` stays pinned (poppler >= 23.01 needs freetype >= 2.10; EL8 has
2.9.1).

**Also fixed here:** the README package table finally has a generator,
`build/gen-readme-table`, gated by `--check` in Tier 1. It found 16 stale rows
on its first run. That was failure-catalogue entry 8, open since the table was
last found carrying 30 wrong versions -- the instruction to "regenerate from the
registry" had never had a tool behind it.

## Release debt carried by the xephyr release (2026-08-03) -- SUPERSEDED, see above

The xephyr release is **class C** by the rules in `docs/RELEASE.md` §0
(`payload/packages.json` group membership changed: `@gui-suite` gained
`xephyr`), but it was cut with §2 **deliberately deferred**. This is a recorded
deviation, not an oversight, and the debt is real:

- **28 packages are behind upstream** as of this date. Four are build-class and
  need `build/build-<tool>.sh` on this EL8 box: `fish` 4.8.0 -> 4.8.1,
  `vim`/`gvim` 9.2.0782 -> 9.2.0901, `octave` 11.1.0 -> 11.3.0. The rest are
  download-class one-liners. Re-derive the current list with
  `build/check-versions --outdated-only` and `./build/update --list-outdated` --
  do not trust this snapshot.
- **`yara` itself is behind** (4.5.5 -> 4.5.8) and `./build/update yara-rules` was
  **not** run.
- **The ClamAV signature DB was 17 days stale** (`daily.cld` dated 2026-07-17)
  when the release scan ran. `sudo freshclam` needs sudo and was not run. Per
  `docs/RELEASE.md` §2b a scan against stale signatures is a green light that
  means nothing -- so treat this release's CLEAN verdict as weaker evidence than
  usual.

What *was* fully gated: Tier 1 + Tier 2 (24/24), `tests/prebuilt-binaries`
(264/264), and Tier 3 on stock AlmaLinux 8.10 (`--full` 257 OK / 7 skipped,
`--dynamic` 10/10). The class C **container** requirement was met; the currency
and security-data requirements were not.

**The next release should be a real class C** and clear all of the above before
anything else. If you are reading this while planning a "quick" release, that is
exactly the situation the class rules exist for.

## Deep review of xephyr + xdesk (2026-08-03)

Reviewed the uncommitted xephyr work end to end against a real staged install.
Twelve findings, all fixed. Re-verified after the payload rebuild: Tier 1 + Tier 2
**24/24**, `tests/prebuilt-binaries` **264/264**, and Tier 3 on stock
AlmaLinux 8.10 -- `--full` **257 binaries OK (7 skipped)** and the network-isolated
`--dynamic` pass **10/10**. `Xephyr`/`Xephyr.bin` skip on `libGL.so.1` (host GLVND
dispatcher), alongside the existing flameshot / nedit-ng / nvim-qt skips; that is
the documented host contract, and it is the wrapper-sibling change in
`tests/prebuilt-binaries` doing its job -- before it, the `bin/Xephyr` wrapper
was exec-probed and returned 127 in the GL-less container.

**The one that mattered: `xdesk --keep` left a nested X server with no access
control.** `cleanup()` removed the state dir unconditionally, including under
`-k`, and that dir holds the MIT-MAGIC-COOKIE file passed to Xephyr with
`-auth`. Reproduced 3/3: after `xdesk -k` exited, `DISPLAY=:10 xdpyinfo` with no
cookie at all returned the vendor string. On a shared farm node that is exactly
the keystroke exposure the auth block exists to prevent. (The second failure
mode is milder but still fatal to the feature: when clients *had* connected, auth
stayed enforced but the cookie file was gone, so nothing new could ever attach.)
`cleanup()` now keeps both the server and its state dir under `-k` and prints
the display, pid, `XAUTHORITY` path and the `kill`/`rm -rf` disposal command.
`tests/install-xdesk` asserts it: cookie-less connection refused, cookie
connection accepted, state dir retained, then tears the server down itself.

**Second-worst: the nested session inherited the outer compositor's Wayland
environment.** `WAYLAND_DISPLAY` and `QT_QPA_PLATFORM=wayland` passed straight
through, and GTK/Qt prefer Wayland whenever it is set -- so apps launched inside
the nest rendered on the **outer** desktop. This repo's own WSLg guidance to set
`QT_QPA_PLATFORM=wayland` guaranteed it. `xdesk` now unsets `WAYLAND_DISPLAY` and
exports `GDK_BACKEND=x11` / `QT_QPA_PLATFORM=xcb` / `XDG_SESSION_TYPE=x11` for
the session.

**Provenance was half-pinned.** `--tag` pinned the Xephyr RPM while the six
support libs were `cp`'d out of the build box's `/usr/lib64` -- the exact
build-box-masking shape the closure guard next to it was written to catch. They
now come from their own downloaded RPMs (`libXdmcp`, `libXfont2`, `libfontenc`,
`libxcb`), resolved *within* the extracted tree (a bare `readlink -f` on an
absolute symlink would fall back to the host root and silently reintroduce it).
`--tag` is now the **full version-release** (`1.20.11-28.el8_10.3`) matched
exactly, because the release field is where Red Hat's CVE backports live and a
bare `1.20.11` reads as a 2021 X server; `payload/packages.json` records the same
NVR and the build fails if they disagree; every consumed RPM NVR is written to
`build/xephyr/PROVENANCE`. This matters more than usual here because the package
is deliberately absent from `farm-versions`/`check-versions`, so no currency
sweep covers it.

**A dead assertion.** `tests/install-xdesk` guarded its orphan check with
`pgrep -x Xephyr`, which never matches -- the process name is `Xephyr.bin`
(`bin/Xephyr` is a wrapper that `exec`s it), so the check had never run. Also,
the test rewrote `HOME` without carrying `XAUTHORITY`, which would have failed
on any host whose outer display uses cookie auth -- i.e. the NoMachine/GDM hosts
this package exists for. It passed only because WSLg has no outer auth at all.

Smaller: `XDESK_SESSION=" "` died with a `set -u` "unbound variable" instead of
an error message; `--size` accepted `0x0` and `1x2x3`; dead `status=$?` after a
`set -e` exec; the build script's header still said "five" sonames and omitted
`libfontenc` from the bundled list -- the very lib whose omission shipped broken;
`AGENTS.md` had no xephyr/xdesk coverage at all while every comparable package
has a behavior section; and the `Xephyr` wrapper's exported `LD_LIBRARY_PATH` is
inherited by the host helpers Xephyr forks (`xkbcomp`), which is benign on EL8
but is now recorded in a comment.

## xephyr + xdesk (2026-08-02)

New `xephyr` package (`bin`, non-optional, in `@gui-suite` -> `@shared` ->
`@engineering-loadout`): Xephyr `1.20.11-28.el8_10.3` shanghai'd from the EL8
AppStream RPM, plus an `xdesk` launcher. **Uncommitted.**

The problem it solves: on a NoMachine host the desktop is fixed by root-owned
`/usr/NX/etc/node.cfg`, which hardcodes
`DefaultDesktopCommand "... gnome-session --session=gnome"` rather than
`/etc/X11/xinit/Xsession default` -- so the usual per-user `~/.xsession` hook
does not apply and there is no no-root way to change the session. A nested X
server needs none of that. Xvnc was rejected deliberately: it opens a listening
port (590x), Xephyr binds no network socket.

Verified by hand on the dev box: full nested XFCE 4.16 session (xfwm4, panel,
xfdesktop, Thunar, xfsettingsd), clean Logout. **Nested GNOME does not work** --
`gnome-shell` 3.32 dies with `this._userProxy.Display is null` in
`loginManager.js` because it asks logind for a graphical session that a nested
display does not have. Not a GL problem, not fixable from our side; run a WM or
a non-GNOME session inside the nest.

Three things worth remembering:

- **The clean container was the only gate that caught the real bug.** Tier 1 and
  Tier 2 were both green while `libfontenc.so.1` was missing from the payload.
  It is a dependency of *bundled* `libXfont2`, not of the binary, so a closure
  check that walked only the binary never saw it -- and the build box has the X
  libs installed, so nothing local could. The guard in `build/build-xephyr.sh`
  now walks the binary **and every bundled lib**, and immediately found a second
  one (`libfreetype.so.6`, already owned by `gui_libs`, so a depends not a
  bundle). Textbook build-box masking, same shape as the NSS/firefox incident.
- **`mesa3d_libs` already owns `libdrm.so.2` and `libxshmfence.so.1`** at the
  same `lib64/` path, so `xephyr` declares it as a `depends` rather than
  duplicating them. Two packages owning one path is an install hazard. It costs
  nothing: `mesa3d_libs` is non-optional already.
- **`tests/prebuilt-binaries` could not skip wrapper scripts.** `bin/Xephyr`
  (POSIX sh) cannot be ldd-checked, so it was exec-probed in the GL-less
  container and returned 127 while `bin/Xephyr.bin` skipped correctly. The loop
  now resolves a non-ELF `bin/<name>` to its `bin/<name>.bin` sibling for the
  host-`.so` skip decision **only** -- anything missing that is not
  host-required still falls through to the exec probe, so the change can add
  skips but never mask a failure. This helps every wrapper+`.bin` package.

`tests/install-xdesk` is new in Tier 2 and covers what no headless gate can:
nested display comes up at the requested size, a cookie-less connection is
refused (an unauthenticated nested server is readable by any other user on a
shared farm node), and the server plus its state dir are gone afterwards. It
**skips** when `$DISPLAY` is unset. Its predecessor bug is the reason it exists:
`xdesk` first waited for `/tmp/.X11-unix/X$N` and timed out against a healthy
server, because a host whose `/tmp/.X11-unix` has the wrong mode (WSLg, and
hardened hosts) makes Xephyr bind **only** the Linux abstract socket.

No `build/farm-versions` entry on purpose -- X servers of this vintage reject
`-version` and the stripped binary carries no version string, so every strategy
would report a permanent gap.

## Deep review (2026-07-25)

A full consistency/lint/docs pass. Everything below is landed and Tier 1+2 green
(23/23). The two findings worth remembering:

- **`@engineering-loadout` had silently lost 9 env bundles.** Commit `e3f4857`
  narrowed `@envs` from "every non-optional env package" to "env-bash only". The
  curated group listed `@envs` as a member and was never edited, so it inherited
  the narrowing: `env-nvim`, `env-vim`, `env-tmux`, `env-helix`, `env-st`,
  `env-zsh`, `env-editorconfig` and `env-pip` all vanished from the headline
  `./loadout install @engineering-loadout`. Since the nvim plugin/parser phases
  gate on `env-nvim`, that install shipped the 328 MB stash and 251 MB of parsers
  while writing no nvim config and seeding no `lazy/`. The group now lists its ten
  env packages **explicitly** rather than via `@envs`, so a future redefinition of
  `@envs` cannot silently re-narrow it. Lesson: a group that references another
  group inherits every future redefinition of it, including the ones nobody
  connected to this group.
- **Six scripts declared `#!/usr/bin/env python3` but contained PEP 758
  (`except A, B:`) syntax**, which only parses on 3.14: `build/check-versions`,
  `build/farm-versions`, `release`, `scan-for-malware`, `strip-all-elf-binaries`,
  `tests/prebuilt-binaries`. Stock EL8 `python3` is 3.6.8, so all six were dead
  on a clean box and worked here only because `~/.local/bin/python3` is 3.14 --
  textbook build-box masking. All six now say `python3.14`.

Lint infrastructure was the root enabler and is now fixed:

- `ruff.toml`'s excludes were all **pre-reboot paths matching nothing**, so
  `ruff check .` reported 3363 errors (all vendored) and was unusable; and
  `select = ["I", "UP"]` **replaced** ruff's default set, silently disabling
  pyflakes entirely. Excludes repointed (plus the vendored `grc` tree),
  `F,E4,E7,E9,B` enabled, `E402` ignored for the deliberate post-`pwd` imports.
- `tests/run-all` linted exactly **one** file, behind `if command -v ruff` -- a
  missing ruff was a silent skip. It now lints and `py_compile`s every
  first-party Python file and treats a missing ruff as a hard FAIL. This gate is
  what caught the remaining strays (`fetch-stash` B904, `import-nodejs` E741).
- `ty` is wired up but deliberately **advisory, not a gate**. All 11 diagnostics
  on `loadout_main.py` are proven false positives (vendored `rich`/`rich_click`
  lack type info; `_progress_task` is guarded via a correlated variable ty cannot
  narrow). Documented in `ty.toml` with reproduction commands. **Do not add
  blanket `[rules]` suppressions to make it go green** -- an investigation was
  first "fixed" that way and reverted.

Also fixed: `./build/update` never regenerated `.content-manifest` after mutating
`payload/` (Tier 1 failed on drift as a result) -- now automatic on every
payload-mutating path plus all three guidance printers; `./build/update tmux-plugins`
cloned a commented-out `@plugin` line (unanchored `re.search`); two writers of
`assurance/downloads.log` disagreed on date format (now ISO-8601 UTC);
`vercomp` glob-matched its RHS; a duplicated unreachable gate in
`install_nvim_lazy_update`; README's package table had 30 stale versions and 6
missing packages (regenerated from the registry, 122 rows, now exact).

tmux plugins are now genuinely commit-pinned: `envs/tmux/vendor/plugins.lock`
exists with 4 pins (the fixed regex correctly excludes the disabled
`tmux-yank`). `docs/SECURITY.md` had claimed this pin for some time while the
lockfile had never been committed.

## Dependency bumps (2026-07-25)

- **parity-plot v0.5.0 -> v0.6.0** (`e98f08fecb7f250af508e0d81c9c94349cc6b1ea`).
  Two things made this a non-routine bump:
  - **The patch stopped applying.** Upstream re-sorted imports, breaking the
    context of the patch's `__version__` hunk. That hunk was always redundant --
    `build-parity-plot.sh` stamps the real tag into `parity_plot/__init__.py`
    with a `count != 1` assertion right after applying the patch, so the hunk
    set `0.0.0` only to be immediately overwritten. The patch is now a **single
    hunk** (`include_plotlyjs="cdn"` -> `True`, at line 574). Fewer contexts,
    fewer false failures on the next bump.
  - **v0.6.0 is a breaking CLI change**: TOML-only. `parity-plot plot` takes a
    config file (default `parity.toml`), not a CSV path. The old smoke test fed
    it a bare CSV and died with `invalid TOML: Expected '=' after a key`.
    `tests/install-parity-plot` now generates a real `parity.toml`, and also
    covers `init` (documented entry point) and `example` (a second exercise of
    the patched `save()`).
  - The test's expected version is now **read from `packages.json`** instead of
    hard-coded; the literal had gone stale on every previous bump.
  - Dependency closure unchanged -- only `parity_plot-0.5.0-*.whl` replaced by
    `0.6.0`.

## Dependency bumps (2026-07-24)

- **parity-plot v0.4.0 -> v0.5.0** (`ed16b6a446837db78d7502d9062a98d276a66dd4`).
  Rebuilt with `build/build-parity-plot.sh --tag v0.5.0`. The offline-HTML patch
  applies clean to v0.5.0 (the `include_plotlyjs="cdn" -> True` line moved 418->487
  but the context matched; `__version__` still `0.1.0` upstream). Dependency closure
  unchanged vs the vendored wheels -- only `parity_plot-0.5.0-*.whl` replaced
  `0.4.0`. `tests/install-parity-plot` updated to assert 0.5.0 and passes (CLI +
  module version, self-contained Plotly HTML, local NiceGUI designer).
- **Astral tools** via `build/update-prebuilt ruff=0.16.0 ty=0.0.63 uv=0.11.32`:
  ruff 0.15.21->0.16.0, ty 0.0.58->0.0.63, uv 0.11.28->0.11.32. Downloaded, stripped,
  patchelf'd (`$ORIGIN/../lib64:$ORIGIN/../lib`), bz2'd, versions stamped. Astral was
  acquired by OpenAI -- release cadence/URLs unchanged for now; watch for redirects.
- Post-payload chain run: `./build/strip-all-elf-binaries` (3 new bz2 recorded),
  `build/gen-content-manifest` (4312 files, `--check` OK). Bash completion diff = no
  change (only versions/wheels moved, not package names/verbs).

## Release-time reduction (2026-07-23)

Two structural wastes in `./build/release` removed, both on the release critical path:

- **nvim plugin stash reuse.** The ~328 MB stash asset was re-uploaded on every
  re-release even when byte-identical. `./build/release` now keeps the existing release
  object (it holds the asset), moves only the tag, **undrafts** it (deleting a tag
  drafts its release; recreating the tag does not republish -- verified empirically),
  and clobbers only the small assets. Gated on a signed tag + a byte-match (present
  asset, size, and matching SHA-256 in the previous release's `sha256sums.txt`), then
  a post-publish re-read asserts published-not-draft + stash present, self-healing
  with a full upload on any doubt. See AGENTS.md -> "Create a GitHub release".
- **Binary-smoke content cache.** The ~4.5 min smoke gate (the slowest) is now cached
  under `release-smoke-v1/`, keyed on a parallel hash of **actual bytes** (all of
  `payload/**` + `loadout` + `loadout_main.py` + `tests/prebuilt-binaries`, a
  deliberate superset) plus platform `uname`/glibc; pass-only, double-checked key.
  The hash (~a few seconds, parallelised) runs inside the smoke worker so it overlaps
  the version gate. Cache lives in `./build/release`, so `tests/prebuilt-binaries` run
  directly still always executes. `--no-cache` / `--clear-cache` force fresh.

Net: a routine re-release whose payload is unchanged skips both the 328 MB upload and
the 4.5 min smoke re-run. A real payload change re-fingerprints and re-runs, so the
false-green surface is only an *over*-cover (needless re-run), never an under-cover.

## Release signing: the 2026-07-22 unsigned-tag incident

The first `v2026.07.22` release shipped an **unsigned** tag (GitHub reported
`verification.reason = "unsigned"`), silently. `./build/release` decided whether to sign
from `_signing_configured()`, which only asked `git config --get user.signingkey`.
When that resolved empty the script took the `git tag -a` fallback, printed a warning
into a long unattended log, and dropped the `git tag -v` line from the release notes.
Nobody was at the keyboard to notice. The top link of the trust chain was missing.

`./build/release` now runs `_preflight()` **before any gate**, because the gates are slow and
the operator is only reliably present at kickoff:

- checks `gh auth status`;
- proves signing works by signing a throwaway tag with `SSH_ASKPASS_REQUIRE=never`,
  no `DISPLAY`, `stdin=DEVNULL` and a 60s timeout, then greps the resulting object for
  `BEGIN SSH SIGNATURE` -- a zero exit from the signer is not proof;
- blocks with remediation unless `--allow-unsigned` is passed;
- after the real `git tag -s`, re-reads the tag object and aborts (deleting the tag)
  if no signature block is present.

Signing needs a live ssh-agent. **Probe for one before asking anyone to run `ssh-add`** --
it is normally already running and only `SSH_AUTH_SOCK` is missing from tool shells.
Two traps: the agent socket probe fails under a sandbox with `unix_listener: socket:
Operation not permitted` (a sandbox artifact, not a broken agent), and `ssh-add` is
aliased on this box to `eval "$(ssh-agent -s)" && command ssh-add ...`, so a bare call
spawns a fresh **keyless** agent. Use `/usr/bin/ssh-add -l` against each
`/tmp/ssh-*/agent.*` and match the fingerprint of `~/.ssh/id_ed25519.pub`.

## State

- `main` intentionally has a two-commit bootstrap snapshot containing the current tree.
  GitHub enforces a 2 GiB per-push limit, so the snapshot is split only to transfer the
  normal offline payloads safely. All earlier commits and release tags were removed to
  expunge obsolete binary blobs; current payloads remain ordinary Git objects, never LFS.
- A complete pre-reset worktree + `.git` archive was checksum-verified before rewrite.
  It is user-local recovery material, not clone state.
- Current tree carries espresso, restic, reproducible archive stripping, correct
  shared-library check ordering, and the Tier 3 assurance gate. The nvim plugin stash
  remains a GitHub release asset (`nvim-plugin-stash.tar.bz2`) with its checksum and
  content-manifest trust chain; it is not a Git payload.
- `parity-plot` is bundled as a non-optional Linux Python tool from stable upstream
  tag `v0.7.0`. NiceGUI is a core upstream dependency, not a `uv_extras` entry,
  so the local designer still installs offline. Upstream now defaults standalone
  HTML reports to inline Plotly, so reports render offline without a loadout
  patch. Static image/PDF export still needs an already-installed
  Chrome/Chromium for Kaleido. Rebuild with
  `build/build-parity-plot.sh --tag v0.7.0`; it copies a supplied source
  checkout into a disposable build tree and first reuses the vendored lock
  closure offline.
  Upstream still ships no explicit license file/metadata; the owner authorized this
  first-party bundle, but add explicit terms upstream before third-party redistribution.
- `@envs` now intentionally expands only `env-bash` (then its `env-starship`
  recommendation). Install another config bundle by name, or use `@envs-all` for
  every env package. The fresh-home integration test explicitly selects
  `@engineering-loadout @envs-all` to retain broad Nvim/editor/shell coverage.

## Audit 2026-07-18 (pre-reset tree; all gates green)

- `loadout doctor`: clean. `tests/run-all` (Tier 1+2): all pass, incl. assurance-check
  33/33, completion sync, crate-store 2101/2101.
- `scan-for-malware`: CLEAN, 71210 files, 1 documented allowlisted FP (firefox omni.ja).
  User ran `sudo freshclam` 2026-07-17 (sigs were 10 days old).
- `build/verify-binaries`: 9 pass / 0 fail / 139 documented skips. `git fsck`: clean.
- Outdated vs upstream (22 pkgs, mostly patch bumps): htop 3.2.1→3.5.1,
  octave 11.1.0→11.3.0, flameshot 13→14, fish 4.8.0→4.8.1, rg 15.1→15.2, gnuplot
  6.0.2→6.0.4, vim/gvim 9.2.0782→.0785, plus small bumps (`build/check-versions
  --outdated-only` for the list). pdftotext correctly pinned (freetype floor). No
  outdated Python tools.
- git "unable to access '.gitmodules': Permission denied" inside Claude Code sandboxed
  commands is a sandbox artifact, NOT repo state (file doesn't exist outside the
  sandbox). Never "fix" it. See project memory `gitmodules-sandbox-mask`.

## Audit 2026-07-21 (Parity Plot + Bash-only @envs)

- `tests/run-all --container`: PASS. Tier 1/2 integration, the stock
  AlmaLinux 8.10 full smoke (250 binaries OK, 5 documented skips, runtimes OK),
  and isolated dynamic analysis all passed.
- Focused `tests/install-parity-plot`: PASS. It verifies CLI/module 0.4.0,
  self-contained Plotly HTML, `farm-versions` reporting, and a local NiceGUI
  designer page with no external page assets.
- `@envs` resolves exactly `env-bash` plus `env-starship`; the split
  deployment smoke asserts no zsh config is created. `@envs-all` resolves all
  12 env bundles and is selected only by the broad fresh-home coverage test.

## Audit 2026-07-22 (Parity Plot v0.4.0)

- `tests/run-all --container`: PASS (`/tmp/loadout-final-suite-v040.log`).
  Tier 1/2 integration, the stock AlmaLinux 8.10 full smoke (250 binaries OK,
  5 documented skips, runtimes OK), and isolated dynamic analysis all passed.
- Focused `tests/install-parity-plot`: PASS after the v0.4.0 update. It
  verifies CLI/module 0.4.0, self-contained Plotly HTML, `farm-versions`
  reporting, and a local NiceGUI designer page with no external page assets.
- Release gate components: PASS. `./build/scan-for-malware` reports cached CLEAN
  across 75051 files with the known Firefox `omni.ja` allowlisted FP;
  `tests/prebuilt-binaries` reports `All 255 binaries OK; runtimes OK`;
  release checksum/version steps passed and refreshed `sha256sums.txt`.

## Bash env: every directory change lists

`cd()` in `envs/bash/global/bashrc` is the **only** thing that runs the follow-up `ls`,
so anything reaching `builtin cd` silently skips it. Fixed: `loadout_cd_recent_dir`
(backing `cdd`/`cddd`/...) and `latest` in `envs/bash/global/aliases.sh` now call the
`cd` function, and the zoxide block overrides `__zoxide_cd` -- zoxide funnels every jump
through that one generated function, so overriding it covers `z`, `zi` and future verbs.
The `--` was dropped at those call sites: the wrapper does not accept one, and `find`
always emits `./`-prefixed paths. `alias bcd="builtin cd"` stays as the escape hatch.

Verify with a real PTY (`script -qec`) driving `cdd`/`z` in a scratch dir with a marker
file, and check the negative control -- the same harness against a tree without the fix
must print no listing. `bash -lic` will not do: no prompt cycle, so the bug hides.

`cds()` / `cd-surfer` was a failed experiment and is deleted. Unrelated `cds` hits
elsewhere (Cadence `cds.lib` in vim-liberty, SAP `cds-lsp` in nvim) are not related.

## Next steps

1. ~~**Exercise the laptop path for real.**~~ **DONE 2026-08-08** -- validated end
   to end against `v2026.08.07`, the first real asset-bearing release:
   `tools/download-release.ps1 -Tag v2026.08.07` on the Windows laptop, scp to
   nDPC, `./tools/fetch-stash --from-file <stash> --sums sha256sums.txt`. The
   whole air-gapped acquisition path (runbook section 2b) is no longer
   theoretical. Do not re-open this as unvalidated.
2. **Finish the currency sweep.** The v2026.08.07 sweep was deliberately partial;
   what is left and why is in *Where things stand right now* -> *Deferred*. Do not
   re-derive the jupyterlab blocker -- it is recorded there.
3. **Spec the user-facing wheelhouse / uv offline story** the owner raised
   (2026-08-07). Findings so far, including why a `uv` wrapper is the wrong shape,
   are in *Where things stand right now*.
4. ~~**Audit the other silent-255 binaries.**~~ **DONE 2026-08-08/09** -- see
   *The probe now requires exit 0* below. Original note kept for context:
   The generic probe scores any exit code
   outside `{126,127,139}` as OK; three gtkwave binaries were green off an error
   message until this release. Same trap likely exists elsewhere in `bin/`.

Release mechanics: `./build/release` attaches the stash automatically when present;
build it first with `build/build-nvim-plugin-stash` if the checkout lacks it. It
caches a clean malware scan and a passing binary smoke keyed on payload bytes, so a
re-run with unchanged payload is fast.

**Signing (settle this BEFORE the gates, not after).** `./build/release` preflights
tag signing, but a 25-minute gate run that then fails on auth is pure waste. On WSL
a bare `ssh-add` is aliased and re-spawns a fresh KEYLESS agent on every call, so
never trust `$SSH_AUTH_SOCK` (it is usually unset here). Probe instead, with the
real binary:

```bash
for s in /tmp/ssh-*/agent.*; do
    printf '%s ' "$s"; SSH_AUTH_SOCK=$s /usr/bin/ssh-add -l 2>&1 | head -1
done
SSH_AUTH_SOCK=<the one listing a SHA256 key> ./build/release
```

Two further traps proven during the v2026.08.07 release: `git` resolves
`ssh-keygen` from PATH to the loadout's OpenSSH 10 at `~/.local/bin/ssh-keygen`,
which is what supports `-Y sign` -- stock `/usr/bin/ssh-keygen` (EL8's 8.0) does
NOT, so testing with the absolute `/usr/bin` path fails misleadingly. And prove
signing with a real throwaway `git tag -s` + `git tag -v`, not just
`ssh-keygen -Y sign`.

## Lessons (all fixed; keep respecting them)

### A rename is four edits, and the compiler cannot see any of them

Executable renames (v2026.08.07) each needed: registry `bins`, the `farm-versions`
key **and its regex**, the build script's `EXPECT_BIN`, and deletion of the old
stem. Nothing type-checks these against each other, so every build script now reads
the name from the built artifact and hard-fails on a mismatch. Full detail under
*Kebab-case executable migration*.

### A shell-variable rename that bash accepts is worse than one it rejects

`${LOADOUT_CFG_ENABLE_tmux-path-store}` is not a syntax error: it parses as
`${LOADOUT_CFG_ENABLE_tmux-path-store}`, i.e. parameter `LOADOUT_CFG_ENABLE_tmux`
with default `path-store`. Always unset, so it always yields `path-store`, and
`is_truthy()` treats any non-empty string as true -- the documented toggle died
silently and ran unconditionally while `bash -n` stayed happy. Config variables are
SCREAMING_SNAKE and cannot take a dash; a command rename must not follow them in.

### Misusing a tool looks exactly like a bug in the tool

`liberty-filter --filter-in-cells` alone drops nothing -- it is an exception list to
`--filter-out-cells`, not a standalone allowlist. That produced a confident,
incorrect "the filter is a pass-through" report here before the source was read.
Check upstream's own unit tests for intended usage before blaming an artifact.

### Test the artifact, not the repo file

Upstream's `pyproject.toml` / `Cargo.toml` says what upstream *intends*; the built
wheel's `entry_points.txt` and the ELF's `[[bin]]` say what actually ships. The
build scripts now assert against the artifact. Same instinct caught the
`tmux_path_store` console script still being underscored after a release claimed
otherwise.

### A green test that never ran the code is the most dangerous result there is

- **st:** pixel (3,3) sampled the unfocused cursor's outline box → returned cursor color
  for every case. Sample away from the cursor.
- **worker harness:** `opencode … | tee log` makes `$?` *tee's* status. Use
  `set -o pipefail` + `${PIPESTATUS[0]}`.
- **tcsh:** `tcsh -i -c CMD` does not set `$prompt`, silently skipping the interactive
  block under test. Drive a real PTY (`script -qec`).

Before believing a passing test, ask what it would have printed had the feature been absent.

### A stale check trains people to ignore real signal

The fish `FAILED` row was noise for weeks and got logged as "pre-existing" three times.
Same family: the false zsh "may not run" warning (fixed). Assert behavior, not
file layout; never leave a known-false warning in place.

### Silent-no-op patching

Textual patching without a positive assertion is a silent-no-op factory: version stamps
are `json.load/dump` keyed on the exact package name; every `sed` of an artifact is
followed by `grep -q || exit 1`; `build-st.sh` does `rm -f config.h` (Makefile only
copies `config.def.h` when absent).

### Probe leniency masks real breakage

`--version` proves nothing. Fatal-banner patterns plus functional smokes (XSPICE
netlist, tkinter `Tcl()`, pdftotext CJK, restic backup/restore roundtrip) live in
`tests/prebuilt-binaries` — extend that set.

**The exit code proved nothing either, until 2026-08-08.** The probe passed any
code outside `{126,127,139}`, so 42 of 300 binaries were green on a NON-ZERO
exit — several off their own error text. Exit 0 is now the pass condition and
every non-zero acceptance is a written-down `EXPECT_NONZERO` entry. See *The
probe now requires exit 0*.

### The pre-commit hook stages everything

It runs `git add -A`. Partial commits: precise staging + `--no-verify` after running the
hook's checks manually, or keep the tree clean (memory `pre-commit-hook-stages-everything`).

## Assurance ledger interactions

Version bumps of nvim/rust/rust-crate-store/treesitter/git-nvim/crate-store must re-pin
`assurance/records/<pkg>.toml` (version, ref, artifact hashes) and honestly re-run the
malware scan and the dynamic detonation (`tests/prebuilt-binaries-almalinux8
--dynamic`). `assurance-check` now runs in BOTH run-all Tier 1 and the stock-EL8 Tier 3
`--full` gate, so a stale record fails on the container baseline too — but the re-pin is
still a manual step; the checks catch drift, they do not fix it.

## Delegating work to glm-5.2 workers

Subagent work can run on the user's Ollama plan via external `opencode` workers
(`opencode run -m ollama-cloud/glm-5.2`) in a tmux pane — Claude Code's Agent tool
cannot (fixed Anthropic model enum). Traps and pane conventions: memory
`glm5-tmux-worker-delegation`.

## Open low-priority items

- WSLg `SSH_ASKPASS` popup root-cause: gnome-ssh-askpass doesn't appear from background
  shells despite `DISPLAY` + `SSH_ASKPASS` set. Agent workaround reliable and in project
  memory. Optional; pin the fix in `dev-onboard`/docs if found.
