# Current Handoff

## 2026-10-08 (5): envs cleanup -- W2 extra_links removal (UNRELEASED)

Spec: same as (4). **W2 landed** per D2. `extra_links` was inert registry data:
its only consumer was `_install_env_generic`, and every declarer
(`env-bash`/`env-vim`/`env-zsh`/`env-starship`) has a dedicated handler that
hardcodes its links. It also hid W1's dead `~/.vim` link.

- Registry: the field is gone from `env-bash`, `env-zsh`, `env-starship`
  (`env-vim`'s was dropped in W1) and from `_schema`; `tests/registry-integrity`
  enforces `_schema` == fields in use.
- Installer: `_install_env_generic`'s link loop, `cmd_describe`'s field list,
  and `_artifact_paths`' extra_links resolver are deleted. The dedicated
  handlers still create every link they did before -- no behavior change.
- Sizing (D2's consequence): `env-starship`'s `source` is now the directory
  `envs/starship/`, so the directory walk counts `config-schema.json` beside
  `starship.linux.toml`; `_artifact_paths('env-starship')` verified to return
  both files. `gen-installed-sizes` regenerated (map unchanged, 6368
  artifacts), then `.content-manifest`.
- Docs: AGENTS sizing note rewritten (directory sources count their tree),
  copilot field list trimmed.
- Advisory-noise note: pi-lens' pyright runner reports 26 pre-existing
  diagnostics on `loadout_main.py` (rich/rich_click live in `installer_vendor/`,
  which the runner is not configured with; `ty.toml` documents the same class).
  Proven identical at HEAD and dispositioned as false-positives -- no config or
  code suppression added, per repo policy.

**Next:** W3 (dead entrypoints `.bash_login`/`.profile`/`.cshrc`), W4
(`supports_layers`), W5 (`tmux-yank` opt-in note). Each its own commit; class C
at the next release.

## 2026-10-08 (4): envs cleanup -- spec + W1 vim XDG migration (UNRELEASED)

Spec of record: `docs/superpowers/specs/2026-10-08-envs-xdg-and-dead-code-trim-design.md`
(findings F1-F6 from the envs audit, decisions D1-D5, workstreams W1-W6). The
operator closed the three open questions: prefer-vim = yes, drop plain csh =
yes, XDG hook sibling = yes. **W2-W5 are the remaining workstreams; the spec's
checklists are the source of truth.**

**W1 landed and gated.** Vim is XDG-native now:

- `envs/vim/vim/{pack,after}` -> `envs/vim/{pack,after}`; installed to
  `~/.config/vim/{vimrc,pack/vendor,after}`; `~/.vimrc`/`~/.vim` are no longer
  created (pruned on install, kept in the backup list for one release).
- `env-vim` gains `prefer: ["vim"]` (the bundled 9.2 wins on PATH; trade:
  `/usr/bin/vim` 8.0 never sees the config -- inherent to XDG, recorded in the
  spec) and drops its `extra_links` entries (the mechanism itself is W2).
- `envs/vim/vimrc` sources `~/.config/vim/vimrc_hook.bottom` first, the legacy
  `~/.vimrc_hook.bottom` second.
- **The change exposed a pre-existing packaging bug: `install vim` alone
  shipped a broken binary.** `vim.bin` NEEDs `libselinux.so.1`, a payload stem
  claimed only by `gui_libs`, so a vim-only selection skipped it -- dead on
  hosts without a system libselinux (Arch/CachyOS), masked on EL8 BaseOS. It
  also carries a spurious `libpixman-1.so.0` NEEDED (`vim --version` reports
  `-X11`; the loader still requires the soname). Both are now declared in the
  `vim` entry's `libs`. Build-hygiene follow-up: a vim rebuild could drop the
  pixman link and its declaration.
- New T2 test `tests/install-env-vim-xdg`, wired into `tests/run-all` T2 **and**
  the Tier 3 smoke entrypoint: installs `vim` + `env-vim` into a temp HOME and
  probes the bundled vim **through a PTY** (`vim -es` does not read the vimrc --
  a non-PTY probe would pass while proving nothing), asserting `$MYVIMRC`,
  XDG-first `&packpath`, the shipped plugins and after/ftplugin; a stray
  `~/.vimrc` control flips the probe back to legacy mode so the assertions are
  proven able to fail. `tests/install-linux-tmp-home` asserts the XDG layout and
  the absence of the legacy symlinks.
- Gates: focused tests + T1 green; full `tests/run-all --container` green, with
  `install-env-vim-xdg: OK` running inside the Tier 3 container smoke.

**Next:** W2 (delete `extra_links`: 3 remaining declarers + generic loop +
validation + sizes branch; `env-starship` `source` -> `envs/starship/`), then
W3 (dead entrypoints `.bash_login`/`.profile`/`.cshrc`), W4 (`supports_layers`),
W5 (`tmux-yank` opt-in note). Each lands as its own commit; class C at the next
release.

## 2026-10-08 (3): tmux XDG cleanup -- plugin tree + config symlink off legacy paths (RELEASED as 2026.10.5)

Operator call: the extra `~/.config/tmux/tmux/` level and the `~/.tmux` symlink
are legacy compat not worth keeping. The plugin tree now lives at TPM's own XDG
path, `~/.config/tmux/plugins/`; the dispatcher's `run` line and the
`TMUX_PLUGIN_MANAGER_PATH` pin in `tmux-global.conf` both point there (the pin
no longer has to defeat TPM's auto-detection). The installer prunes the nested
`~/.config/tmux/tmux/` tree and stops creating `~/.tmux` and `~/.tmux.conf`;
`.tmux`/`.tmux.conf` stay in the BACKUP list so a first reinstall preserves an
old tree, and env-tmux's `extra_links` key is gone entirely (both entries).

Personal box migrated first: the flat `~/.config/tmux/plugins/` tree was
byte-identical to the nested one, so the nested copy + symlink were removed. An
isolated-server probe with the new config confirms
`TMUX_PLUGIN_MANAGER_PATH=/home/mylesp/.config/tmux/plugins/` and
`@persist-initialized 1`. Snapshots were already XDG data
(`~/.local/share/tmux/resurrect` -- the plugin's fallback, since no
`~/.tmux/persist` existed); docs now say XDG data instead of `~/.tmux/persist`.
The running session keeps the old paths until `Prefix+r` or a server restart.

Tests: `tests/install-env-tmux-nvim-layers` asserts no `~/.tmux`, no nested tree,
TPM at `~/.config/tmux/plugins/tpm/tpm`, and the new pin. Docs synced: AGENTS,
TMUX.md, INSTALLATION, README, copilot-instructions, ARCHITECTURE.

**Stale-PATH trap found while verifying (not caused by the migration).** The
operator's long-running server (started 2026-10-06, PATH ending in the deleted
legacy `~/.loadout/local/bin`) had no `tmux` on the PATH it hands to `run-shell`
children. Every TPM/plugin script shells out to `tmux`, so reload failed with
`'~/.config/tmux/plugins/tpm/tpm' returned 1`. Most plugin scripts mask the
failure (persist ends `return 0`; better-mouse-mode's version check skips its
binds); `tmux-yank` is the one that does not, which is how the missing binary
was confirmed. Fix on the live server:
`tmux set-environment -g PATH "<prefix>/prefer:<prefix>/bin:<old minus legacy>"`
then `Prefix+r`. Verified: TPM rc=0, the `@resurrect-*-script-path` options
repointed at the new plugin tree, and a save round-trip wrote a fresh snapshot
to `~/.local/share/tmux/resurrect`. Diagnostic one-liner:
`tmux run-shell 'command -v tmux'`. A server started from a post-migration
login shell never has this; long-lived panes may still need `exec bash`.

**Also retired: the `~/.tmux.conf` symlink.** tmux >= 3.1 reads
`~/.config/tmux/tmux.conf` natively (probed on 3.7c, including a non-default
`XDG_CONFIG_HOME`), so the installer no longer creates the link and Prefix+r
now sources the XDG dispatcher. Trade recorded: tmux < 3.1 (EL8's system 2.7,
if invoked directly instead of the bundled/preferred 3.7c) would no longer see
the loadout config. Docs synced in the same change (TMUX.md, INSTALLATION,
README, ARCHITECTURE, copilot, AGENTS symlink map).

**RELEASED 2026.10.5 (class C).** Gates: full `tests/run-all --container` green
(T1 + T2 + T3 `--full` + `--dynamic`) -- the first run caught the missed
`~/.tmux.conf` assertion in `tests/install-linux-tmp-home` (the T3 smoke runs
that test inside the container too), fixed as `94d732b` before the second,
green run. `./build/release` passed every gate and published. Section 9
verified: `isDraft=false`; four assets (`sha256sums.txt` 525 B,
`default.content-manifest` 647,898 B, `nvim-plugin-stash.tar.bz2`
344,538,464 B matching local, `sbom.cdx.json` 1,340,180 B); the downloaded
`default.content-manifest` is byte-identical to the local file (e9283b3b...);
`git tag -v` prints a Good ED25519 signature; `origin/main` ==
`2026.10.5^{commit}` (`94d732b`).

## 2026-10-08 (2): class C release prep -- currency + security sweep (RELEASED as 2026.10.4)

Preparing the release on top of the offline-Rust retirement (payload ~3.0 GB,
manifest 4452).

- **nodejs 26.10.0 -> 26.11.1**: `build/import-nodejs /tmp/node-v26.11.1-linux-x64`,
  in-container, from the official tarball sha256-verified against nodejs.org's
  `SHASUMS256.txt`; the importer's GLIBC_2.28 audit passed. nvm is NOT needed for
  a targeted bump -- the importer takes a prefix dir -- but a bare
  `./build/update nodejs` still wants nvm (dev tool, not installed here).
- **tldr-data refreshed** (984,862 -> 985,198 B canonical; 7569 members).
- **yara-rules** already current (20261004, digest verified); **ClamAV** DB
  2026-10-07 (`freshclam` is log-locked by the running daemon -- benign, seen
  before).
- `check-versions`: the only remaining outdated entries are `less` and
  `pdftotext` (deliberately pinned) and `ncdu`, whose upstream lookup still
  503s -- an INCOMPLETE report, not a clean bill. No Rust tool is outdated.

- **Tier 3 harness fixes found by the full `--container` run** (the `--full`
  smoke never exercises these paths):
  - `build/docker/almalinux8.10-smoke-entrypoint` hardcoded the dynamic smoke's
    `--bindir /work/dyn/local/bin`; since the 2026-10-05 XDG re-architecture a
    non-`$HOME` `--dest-dir` is a plain prefix, so nvim lands at `/work/dyn/bin`.
    Fixed (`3f1796b`) and verified standalone (`--dynamic`: 10 passed, 0 failed).
  - `tests/run-all`'s container cache key did not include the smoke harness
    (`build/docker/*`), so a stale pre-XDG `.pass` blessed the broken test as
    CACHED PASS right after it had failed. Container tests now use
    `FP_ROOTS_CONTAINER` (`578ffc7`); all-mode caching is unchanged.

- **vuln-scan `--no-resolve` (release-blocking find).** The first dry-run
  aborted at Step 5: osv-scanner 2.6.0's transitive resolver hard-fails on
  `lefdef-tools` ("package System(7):lefdef-tools: not found", exit 127) -- a
  first-party wheel that will never be on PyPI. The same scanner and wheelhouse
  passed earlier runs, so the resolver's external lookups make that path
  non-deterministic; the wheelhouse listing is already the complete dependency
  closure, so transitive resolution adds nothing and is now disabled. CLEAN:
  215 wheels, 0 advisories.

Gates: full `tests/run-all --container` green afterwards -- T1 + T2 + T3
`--full` + `--dynamic`, 22m52s fresh, both T3 tests genuinely re-run. Assurance
re-pin is NOT owed (none of nvim/rust/treesitter/git-nvim was bumped). Next:
`./build/release` -> 2026.10.4.

**RELEASED 2026.10.4 (class C).** Gates: fresh `tests/run-all --container`
green (T1 + T2 + T3 `--full` + `--dynamic`), then a release dry-run that first
caught the two T3-harness issues and the vuln-scan resolver problem above -- all
fixed before publishing. Section 9 verified: `isDraft=false`; four assets
(`sha256sums.txt` 525 B, `default.content-manifest` 647,898 B,
`nvim-plugin-stash.tar.bz2` 344,538,464 B matching local, `sbom.cdx.json`
1,340,125 B); the downloaded `default.content-manifest` is byte-identical to
the local file (a5601d5d...); `git tag -v` prints a Good ED25519 signature;
`origin/main` == `2026.10.4^{commit}` (`46246f9`).

## 2026-10-08: offline-Rust subsystem retired -- uv unpinned and bumped (in 2026.10.4)

**Decision (operator):** offline `cargo build` on farm nodes was aspirational.
The crate store + its wiring are gone; the shipped Rust **toolchain** (`rust`
runtime) and every prebuilt Rust **tool** stay, and build-host cargo for
fish/tokei/numr/models/surfer + first-party maturin wheels was never the store.

**Removed** (payload 3.3 GB -> 3.0 GB):
- `payload/crate-store/` (10 parts, 364 MB), registry `rust-crate-store` +
  `env-cargo` + `@rust`, and the installer's crate-store phase / env-cargo
  handler / hardcoded gate.
- Shell: bash `cargo()` wrapper + `loadout_net_probe` +
  `LOADOUT_CFG_CARGO_PROBE_HOSTS`/`LOADOUT_NET_PROBE_TTL`; tcsh `helpers/cargo-wrap`
  + alias/config wiring.
- Build: `build-crate-store.sh`, `build-tool-crate-store.sh`,
  `verify-crate-store`, `rust-crate-list.txt`, `rust-tool-locks.txt`,
  `docker/almalinux8.10-rust.{Dockerfile,entrypoint}`; the crate-store inputs in
  `sbom` / `vuln-scan` (which lost `--strict-rust`) / `scan-for-malware`;
  `enhancement-request-cargo-offline-fallback.md`.
- Tests: `cargo-offline-fallback` + `rust-offline-almalinux8` (T1/T3 entries);
  the rust-lock cases in `security-pipeline`; `crate-store.lock`,
  `crate-store-tools.tsv`, `records/crate-store.toml`. Kept: `records/rust.toml`.

**Kept:** `rust` 1.96.0 runtime (5 chunks, NOSTRIP), `build/build-rust.sh`, all
Rust tools. `./loadout install rust` now installs a toolchain with no bundled
registry -- bring your own dependency source (network, `cargo vendor`, mirror).

**Bumped/unpinned:** uv 0.12.17 -> 0.12.23, then the rest of the pinned quartet --
ty 0.0.82 -> 0.0.85, delta 0.19.2 -> 0.20.1, hyperfine 1.20.0 -> 2.0.0 (commit
`2c7e672`); all via in-container `build/update-prebuilt`. No Rust tool remains
outdated (`check-versions`). Also bumped vim + gvim 9.2.1169 -> 9.2.1172
(`build/build-vim.sh --tag v9.2.1172`, in-container; the vim92 runtime archive
came out byte-identical -- nothing in the runtime changed between patches -- so
only the two bins changed). `build/update-prebuilt` now resolves patchelf via
`LOADOUT_PATCHELF` -> PATH -> legacy `~/.local/bin` (the XDG migration moved it)
and fails clearly when missing.

**Verified:** registry/completion/README regenerated (stale `rust-crate-store`
README row removed by hand -- the generator only warns); `content-manifest` OK
(4620 -> 4452 across both changes), `installed-sizes` OK (6368), README table OK,
strip pass clean. T1 focused: registry-integrity, security-pipeline,
assurance-check, content-verify, update-cadence, check-installer PASS; full
`tests/run-all` T1+T2 green. T2 focused: `install-linux-tmp-home` (@shared-all
@envs-all; with the stale `LOADOUT_CFG_SHARED_PREFIX` unset) and `uv-launchers`
PASS. `tests/prebuilt-binaries` on the bumped payload: All 348 binaries OK
(1 skipped), runtimes OK. `ty` advisory unchanged (7 diagnostics before/after;
the stale "11" note in ty.toml corrected).

**Release implication:** registry + installer change => the next release is
class C (Tier 3 + currency sweep required).

## 2026-10-07 (2): .content-manifest shipped-set fix -- the export blocker (RELEASED as 2026.10.3)

**The defect.** The committed `.content-manifest` in 2026.10.2 listed 158 files
under `envs/tmux/vendor/plugins/tmux-persist/{.agents,.codex,.claude}`. Those
files existed on this host (the vendored tree was cloned here) but are
gitignored and untracked, so they are not in the commit. `gen-content-manifest`
walked the filesystem; `--check` therefore passed here and every clean clone or
`git archive` export failed with 158 MISSING entries, and PSG's
`deploy-loadout` wrapper (`./build/export ...`) refused to publish. A signed tag
does not catch this: the tag signs the commit, and the commit's manifest named
files the commit does not contain. (The `.content-manifest` asset itself was
also wrong -- it is the same file `sha256sums.txt` pins.)

**One shipped-set rule, three layers.**

- `build/gen-content-manifest` now skips untracked+ignored files
  (`git ls-files -o -i --exclude-standard`: any-depth `.gitignore`,
  `.git/info/exclude`, `core.excludesFile`). Tracked-but-ignored files
  (`git add -f`) and untracked-not-ignored files stay covered, because both are
  part of the documented payload chain (build -> copy -> gen -> `git add`);
  symlinks are still skipped. `--check` now reports a manifest entry that is
  present on the host but not shipped as `NOT-SHIPPED`, so the generating host
  can no longer false-green. A git checkout that cannot be queried is a hard
  error, not a silent fallback to the unfiltered walk; the git call carries
  `-c safe.directory=REPO`, so a foreign-owned bind mount (the EL8 build
  container running as root) still filters instead of failing.
- `build/verify-manifest-export` (NEW) reads `HEAD:.content-manifest` and
  streams `git archive HEAD` through a tar reader, requiring every manifest
  entry to be an exported regular file with a matching sha256, and every
  exported regular file under the manifest roots to be listed. Symlinks are
  skipped. The stash exception is untouched: the stash is untracked, so it is
  on neither side, and its `sha256sums.txt` -> `.content-manifest.fetched`
  chain is unchanged.
- Wiring: Tier 1 `content-manifest matches export` (uncached -- `test_script`
  resolves to nothing, so no cache can stand on stale HEAD), `build/export`
  preflight (prints `manifest : ...`, refuses with the drift list),
  `build/release` Step 3b (uncached, mandatory). `tests/run-all`'s
  `FP_ROOTS` now includes both scripts so the cached shipped-set regression
  test cannot stand on stale tooling. `tests/content-manifest-shipped-set`
  (NEW, T1) pins the ignored-vendored-file class in a synthetic repo with RED
  controls: host NOT-SHIPPED, clean-export MISSING, gate MISSING-FROM-EXPORT,
  and a manifest whose hash matches a dirty tree rather than HEAD.

**Manifest regenerated wholesale: 4620 -> 4462 entries, exactly the 158
ignored-untracked deletions** (no other line changed; the 29 ignored-untracked
`.claude/skills/*` symlinks were never in the manifest).

**Verified.** RED before the fix: new `--check` = 158 `NOT-SHIPPED`; the gate =
158 `MISSING-FROM-EXPORT`; `build/export`'s new preflight returns False with
that list (tested in-process -- the real command refuses at `check_clean_tree`
while the fix is uncommitted). GREEN after regeneration + commit: `--check` OK
(4462); gate OK; synthetic regression test all PASS; `tests/run-all --fast`
green. Full T1+T2 green except `install-linux-tmp-home`, which fails only
because this session inherited the stale pre-XDG
`LOADOUT_CFG_SHARED_PREFIX=/home/mylesp/.loadout/local` (test-harness env leak:
the test overrides HOME/XDG but inherits the rest) and passes under
`env -u LOADOUT_CFG_SHARED_PREFIX` -- same stale-session class as the PATH note
above.

**End-to-end export proof (the blocked PSG path).** `./build/export <dir>` now
runs clean: `manifest : verify-manifest-export: OK (4462 files match
.content-manifest at HEAD)`, `payload : content-manifest verified: 4463 files`,
stash copied + re-verified. `./loadout doctor --verify` inside the exported
git-less tree: `content-manifest verified: 4463 files match`, rc=0. Container
path exercised too: as root on the foreign-owned bind mount, plain git fails
"dubious ownership" while the fixed generator reports OK (4462). Class A change
(no payload bytes -- manifest metadata + export-ignored tooling), so Tier 3 was
not required.

**RELEASED 2026.10.3 (class A).** Bumped rather than overwriting 2026.10.2:
that release was section-9-verified and trusted, and an overwritten tag is
invisible to offline consumers (`-V` unchanged) -- policy in docs/RELEASE.md
section 8. `./build/release` ran the standard gates plus the new Step 3b
(`verify-manifest-export: OK (4462 files match .content-manifest at HEAD)`),
pushed `main` (5cad458 -> 00dd80b), signed the tag, and published. Section 9
verified: `isDraft=false`; four assets present (`sha256sums.txt`,
`default.content-manifest` 649,128 B, `nvim-plugin-stash.tar.bz2` 344,538,464 B
-- bytes unchanged, `sbom.cdx.json`); the downloaded
`default.content-manifest` asset is byte-identical to the working-tree file
(fe8e55ae...); `git tag -v` prints a Good ED25519 signature; `origin/main` ==
`2026.10.3^{commit}` (`00dd80b`).

## 2026-10-07: uv/uvx launchers + xfce4-terminal (release 2026.10.2)

**uv/uvx.** `uv` was already a package but bare upstream: no `uvx`, and
`uv venv` / `uv tool install` / `uv run` created environments with whatever
interpreter uv discovered. Now `bin/uv` (POSIX-sh launcher) + `bin/uv.bin`
(official 0.12.17 release binary) + `bin/uvx` (-> `uv tool run`), built by
`./build/update-prebuilt uv=0.12.17` from `build/uv-launcher.sh` /
`build/uvx-launcher.sh` (LAUNCHERS table, output stem `uv.bin`), so a bump is
one command. Pin semantics are measured, not assumed: `UV_PYTHON` is set to
`<prefix>/bin/python3` for `uv venv` / `uv tool install` / `uv run`, but NOT
for `uv pip` -- on 0.12.17 `UV_PYTHON` outranks `VIRTUAL_ENV`, so a pinned
`uv pip install` inside an activated venv would install into the managed
Python instead of the venv. Without the pin, uv's native target discovery
refuses a bare install and honors the venv / `--python` / `--system`; an
explicit `--python` or caller-set `UV_PYTHON` always wins. `tests/uv-launchers`
(T2, network blackholed) gates all of it. `uvx --version` is special-cased to
uv's version (`uv tool run --version` errors upstream). `uv self update` may
replace `uv.bin` in place -- accepted (an explicit user action; the wrapper
keeps working).

**xfce4-terminal 1.0.4** (EPEL8 shanghai repack, `build/build-xfce4-terminal.sh`):
`bin/xfce4-terminal` launcher (gui + gtk3 shared blocks) +
`bin/xfce4-terminal.bin`, four bundled lib stems (`libxfce4ui-2.so.0`,
`libxfce4util.so.7`, `libxfconf-0.so.3`, `libstartup-notification-1.so.0`) plus
the `libvte-2.91.so.0` stem shared with mate-terminal (declared in both
entries). `libstartup-notification-1` is a NEEDED of our bundled libxfce4ui and
is absent from stock almalinux:8.10 -> bundled (the Xephyr/libfontenc class;
the build's closure guard walks every shipped ELF for this reason). Measured:
starts, maps a window and opens Preferences with NO session bus and no xfconfd;
preferences simply do not persist, so xfconfd is deliberately not bundled.
Member of @gui-suite; build notes in build/ADDING_BINARIES.md.

**Gates:** T1+T2 `tests/run-all` green; Tier 3
`tests/prebuilt-binaries-almalinux8 --full` (--network=none) green -- 326
binaries OK, runtimes OK. Dev-host gotcha, recorded because it bit this
session: a shell started before the XDG migration still had the OLD
`~/.loadout/local/bin` on PATH (now deleted), so `ruff`/`tmux` lookups failed
and `tests/run-all` reported three false failures. Prefix
`~/.local/share/loadout/bin` to PATH on a migrated box -- a fresh login shell
gets it via appended PATH; a long-lived tool session predating the migration
does not.

**Released 2026-10-07 as `2026.10.2`** -- branch pushed before tag, ED25519
signed tag verified, all four assets present (sha256sums.txt,
default.content-manifest 674914 B matching local, nvim-plugin-stash.tar.bz2
344538464 B matching local, sbom.cdx.json), `git ls-remote origin
refs/heads/main` == `git rev-parse 2026.10.2^{commit}`.

## 2026-10-06 (post-2026.10.1): tmux focus-follows-mouse preference

`focus-follows-mouse` is now a layered tmux preference: the managed baseline
sets it **off** (guarded with `%if "#{>=:#{version},3.7}"` -- the option landed
in tmux 3.7, the bundle is 3.7c), the seeded `tmux-settings-user.conf` carries
a commented opt-in, and `tests/install-env-tmux-nvim-layers` asserts both the
defaults and a real-server override (managed off -> user layer on).
`docs/TMUX.md` documents it. The operator's live user layer enables it.

Last updated: 2026-10-08 (**released 2026.10.5**; in flight: the envs cleanup
spec + W1 vim XDG migration -- W2-W5 pending, spec is the checklist).
Previous: 2026.10.5 (class C: tmux XDG cleanup; section-9 verified).
Previous: 2026.10.4 (offline-Rust retirement, uv/ty/delta/hyperfine/vim/gvim/
nodejs sweep, T3 harness + vuln-scan fixes; section-9 verified).
Previous: 2026.10.3 (`.content-manifest` shipped-set fix + clean-export gate,
class A; section-9 verified: signed tag, 4 assets, origin/main == tag).
2026.10.2 (uv/uvx launchers + xfce4-terminal; verified 2026-10-07).
Prior releases: 2026.10.1 (October currency sweep on top of the XDG
re-architecture), `v2026.09.23` RELEASED + verified
(release commit `032c1d0`). Committed since v2026.09.18: `b6e769a` (librelane
end-to-end, btop themes, nethogs, xclip), `032c1d0` (marktext + fused-line
launcher fix + gate fixes), the three 2026-09-24 gates (versioning scheme,
scanner de-productification, security pipeline), the 2026-09-25 security wheel
refresh, and the 2026-09-27 xschem onboarding.

## 2026-10-06: October currency sweep (released as 2026.10.1)

Class C release prep on top of the XDG re-architecture. `build/check-versions`
started at ~23 outdated; after the sweep:

Bumped (16): nodejs 26.9.0 -> 26.10.0, vim + gvim 9.2.1119 -> 9.2.1169, rsync
3.5.0 -> 3.5.1, fio 3.42 -> 3.43, typescript-language-server 6.0.0 -> 6.0.1,
marktext 0.19.1 -> 0.20.0, librelane 3.0.14 -> 3.0.16, ruff 0.16.8 -> 0.16.10,
miller 6.21.0 -> 6.22.0, lazygit 0.65.1 -> 0.66.0, yq 4.53.6 -> 4.54.1, broot
1.60.1 -> 1.61.0, biome 2.5.14 -> 2.5.15, fresh 0.5.1 -> 0.5.2. Security data:
yara-rules 20261004, tldr-data refreshed (1.0 MB archive). Pinned by design:
less, pdftotext (pre-existing reasons).

**Pinned in THIS sweep (4) -- crate-store coupling, not upstream choice:** uv,
ty, delta, hyperfine carry `pin_reason`: the EL8 build image cannot rebuild the
crate store because `cargo-local-registry` (latest and 0.2.7 both tried) fails
to compile -- its dependency chain pulls a curl-sys that requires OpenSSL 3
`OPENSSL_VERSION_STRING`, EL8 ships OpenSSL 1.1.1 headers. The image also could
not be rebuilt during this sweep (ftp.gnu.org unreachable at the autoconf
layer), so the follow-up is to bake EPEL `openssl3-devel` (3.5.5 available) plus
a working cargo-local-registry (or move the sync off cargo). Until then,
bumping any of the four flips `tests/run-all`'s crate-store policy red, by
design.

Build-tooling fixes riding along:

- `build/Dockerfile`: `libatomic` baked (node stage-smokes run the bundled
  Node; it NEEDs libatomic.so.1, a host contract EL8 BaseOS supplies).
- `build/build-marktext.sh`: tarball sha256 pinned PER VERSION from the GitHub
  release asset digest; an unknown version now fails instead of silently
  reusing 0.19.1's hash (the first 0.20.0 attempt hit exactly that).
- `build/build-simple-c.sh`: stamp the registry without a leading `v` (rsync
  stamped `v3.5.1` against the registry's `3.5.1` convention).
- `build/update-prebuilt`: delta + hyperfine musl entries added (ready for the
  day the crate-store block lifts).
- librelane 3.0.16: wheelhouse gained its wheel; the closure kept the LOCALLY
  BUILT `lln_libparse-0.56.0-cp314` wheel -- upstream publishes no cp314 wheel
  at all, so that artifact's provenance is a local EL8 build. Offline install
  proved with `--network=none` plus launcher exec.

False positives / incomplete lookups: lefdef-tools + time-plot `--outdated` is
a format artifact -- the GitHub "latest" SHA IS the tag commit (`git describe`
== registry version; the updater correctly skips). bash, octave and ncdu
upstream lookups failed (unreachable / 503), so those results are incomplete,
not a clean bill; none is known-outdated.

Gates: T1+T2 `tests/run-all` 48/48; Tier 3
`tests/prebuilt-binaries-almalinux8 --full` green (322 binaries, 23 skipped,
runtimes OK). ClamAV DB current (1.5.4/28145, 2026-10-06) -- no
`sudo freshclam` needed before the malware scan. Next: `./build/release`.

Security refresh after the first gate run: `build/vuln-scan` flagged two
unbaselined WHEELHOUSE advisories (urllib3 2.7.0, multidict 6.7.1 -- both
pre-existing wheels, not from this sweep). Refreshed to urllib3 2.8.0 and
multidict 6.9.1 (aiohttp requires multidict<7.0), pruned the superseded
wheels, and proved preservation before/after with a per-tool offline `uv pip
compile` (only the two intended version changes appeared; nothing regressed)
plus end-to-end network-disabled installs of jupyterlab (jupyter-lab 4.6.4)
and parity-plot. `build/vuln-scan` is now CLEAN with 0 baseline entries. The
same proof surfaced PRE-EXISTING incomplete closures: cicwave (pyqt6-qt6
absent), liberty-tools and pygwalker do not resolve offline against the
wheelhouse -- unchanged by the refresh, recorded here as debt.

Dev-host scratch: full T2 runs and the release gates now need disk-backed
scratch (`TMPDIR=/var/tmp/...`). The 16 GB `/tmp` tmpfs filled during the
aborted dry-run (the malware scan alone extracted ~12 GB) and produced seven
false ENOSPC test failures; after cleaning, T2 + Tier 3 re-ran green.

**RELEASED 2026.10.1** (signed tag, commit 7b214fa, 2026-10-06). Gates green:
T1+T2 48/48, Tier 3 `--full` (322 binaries / 23 skipped), and every release
gate (malware scan, binary smoke, version table, checksums + SBOM, secret
scan, vulnerability scan). §9 verified: `isDraft=false`, four assets
(`sha256sums.txt`, `default.content-manifest`, `nvim-plugin-stash.tar.bz2`
344,538,464 bytes matching local, `sbom.cdx.json`), `git tag -v` prints Good
signature, and `origin/main` equals the tag commit.

## 2026-10-05: XDG default root, group retirement, prefer shims (COMMITTED dabaadf..46ecdea, UNRELEASED)

Behavioral re-architecture that stops the loadout silently shadowing system
binaries, and lands the preconditions for a future uninstall. Spec
`docs/superpowers/specs/2026-10-05-dest-default-and-group-removal-design.md`,
plan `docs/superpowers/plans/2026-10-05-dest-default-and-group-removal.md`.

What landed:

- **Default install root** is `$XDG_DATA_HOME/loadout` (fallback
  `~/.local/share/loadout`). Resolution: explicit `--dest-dir` > `config.toml`
  `dest_dir` > XDG default; `dest_dir = "~"` restores the legacy `$HOME/.local`
  layout. (`69af0a2`)
- **Prefix layout + two-root routing**: the shared tree is a plain prefix for
  any non-`$HOME` root (`_local_root`), so `<root>/local/` is gone; config,
  cache and per-user nvim data always resolve under the real `$HOME`. A mixed
  selection never drags config into a dest tree; env-only + explicit
  `--dest-dir` stages a whole HOME (tests/previews); env-only + config
  `dest_dir` ignores it with a printed note. Snapshot targets the real `$HOME`
  unless `--dest-dir` was typed on the command line. (`dabaadf`)
- **`prefer/` mechanism**: registry `prefer` field (env-tmux → tmux) +
  `config.toml` `prefer`/`prefer_off`; `install_prefer_shims()` writes
  marker-carrying exec shims under `<prefix>/prefer/<tool>`, prunes only its
  own, warns on foreign files and missing targets. (`0e5bb2a`, `bf354c7`)
- **`@engineering-loadout` retired**: `_RETIRED_GROUPS` raises a loud resolver
  error naming `@shared-all` then `@envs-all` (superset, 177 vs 167 names);
  completions regenerated. (`d74de05`)
- **`doctor` layout audit**: read-only "Install layout" section -- root + mode,
  legacy `~/.local/bin` EL-managed names, names ahead of system dirs on PATH,
  prefer shims with missing targets; exit status unchanged. (`bc85bfb`)
- **Shell PATH**: `<prefix>/bin` appended (system copies keep priority),
  `<prefix>/prefer` prepended last, fallback
  `${LOADOUT_CFG_SHARED_PREFIX:-$HOME/.local/share/loadout}` in bash/zsh/tcsh;
  `LOADOUT_CFG_SHARED_PREFIX` now baked unconditionally by split env installs
  (`_local_root(install_root)`). (`a6cb682`)

Tests: new gates `dest-layout-and-env-routing`, `env-routing-dest-dir`,
`prefer-shims`, `doctor-shadow-audit` (plus updated `config-toml-dest-dir`,
`registry-integrity`, `unit-resolver`, `check-installer`, `env-shell-parity`,
`install-linux-tmp-home`, `install-split-shared-envs`, `install-nvim-deployments`).
Run green: T1 + **full T2** (`tests/run-all`); **Tier 3**
`tests/prebuilt-binaries-almalinux8 --full` (network disabled): 322 binaries OK,
23 skipped, runtimes OK. Tier 3 caught one test-harness bug the host missed: the
tmp-home hook2 resolved its python via a test-scope `$prefix` (undefined in the
hook); CachyOS has `/bin/python3.14` so the host passed, EL8 does not. Fixed to
use `LOADOUT_DEST_DIR` from the hook environment.

Pending:

- Class C release per `docs/RELEASE.md` (currency sweep, assurance re-pin,
  post-payload chain, tag, publish, post-publish verification).
- Docs synced in this change: README, `docs/INSTALLATION.md` (new migration
  section), `docs/ARCHITECTURE.md`, AGENTS, copilot-instructions,
  `envs/bash/global/README.md`, `envs/nvim/lua/global/paths.lua` comment.
- **Uninstall remains a future spec** (this change lands its preconditions:
  dedicated root, config separation, doctor footprint reporting).
- Known gap: the GUI session `PATH` does not include the install root; systemd
  `DefaultEnvironment` cannot override it, so session-wide changes need
  `/etc/environment` via `pam_env`.

## 2026-10-04: tmux env synced to the live golden tree, loadout1 default (uncommitted)

The live `~/.config/tmux` had diverged from what the installer manages (hyphen
names live vs dotted names in repo; settings + theme layering lived only in
the live tree). Per the user's call -- live is golden, except the shipped
default theme is loadout1 -- the repo now mirrors the live tree byte-for-byte
with one deliberate difference: both shipped settings layers select `loadout1`
(live's global baseline already did; live's user layer says `loadout2`).

Layout change (repo `envs/tmux/`): `tmux.global.conf` -> `tmux-global.conf`,
`tmux.user.conf` -> `tmux-user.conf`, helpers into `scripts/` (including the
bash *generator* `scripts/tmux-word-separators`, which replaces the old Python
run-shell script), new `tmux-settings-global.conf` +
`tmux-settings-user.conf` (seed), new `word-separators.conf` (committed
generated output, 3812 chars), new `themes/tmux-theme-loadout{1,2}.conf`
(hyphen names; byte-identical to live apart from two comment lines whose
filenames were fixed to the new names). Dispatcher drops `-q` and the legacy
`~/.tmux.local.conf` fallback (live policy: missing files fail loud; the file
is no longer loaded). Installer: managed settings-global/themes/word-separators,
seed-if-absent settings-user, dotted `tmux.user.conf` migrated forward,
superseded top-level managed files pruned. `build/update tmux-plugins` follows
the rename. `tests/install-env-tmux-nvim-layers` covers dispatcher order
(settings-global -> settings-user -> global -> user -> TPM), the loadout1
defaults, settings preservation, dotted migration, and pruning;
`tests/install-linux-tmp-home` asserts the new tree.

Verified: isolated-server smoke (`@theme` = loadout1, prefix, theme values,
3812-char separators, reload OK, server killed by PID, live untouched);
`install-env-tmux-nvim-layers` OK; `install-linux-tmp-home` OK;
`run-all --fast` green; sizes (6362 artifacts) + manifest (4611 files)
regenerated, README table OK.

Two notes for the operator: (1) the live `tmux-settings-user.conf` still says
`loadout2` and is preserved on reinstall, so the running session stays on
loadout2 until that file is flipped by hand; (2) the next `env-tmux` install
refreshes the live theme files' header comments to the fixed filenames.

## 2026-09-29: prettier 3.8.1 + yamlfmt 0.21.0 -- the last two formatters (unreleased)

Closes the two gaps the mdformat entry above recorded as debt. `env-nvim`'s
conform.nvim config named **four** formatters the payload never installed; all
four filetypes (markdown / javascript / yaml) silently fell through to
`lsp_format = "fallback"`. After this change every formatter conform names
resolves to a real, installed payload binary, and the
`tests/nvim-formatters-resolve` gate's `KNOWN_EXTERNAL` table is EMPTY.

**prettier** (javascript/typescript) -- the same npm runtime-archive shape as
`pyright`/`netlistsvg`/`typescript-language-server`: the upstream npm package
vendored under `lib/node_modules/prettier` and run on loadout's bundled
Node.js through a prefix-derived sh launcher, `depends: [nodejs]`. Unlike the
other npm packages prettier has **zero runtime dependencies** (single entry
point `bin/prettier.cjs`, `engines.node >= 14`), so the tarball IS the whole
payload. Integrity is the npm registry's own `dist.integrity` (sha512, base64),
pinned per version in `build/build-prettier.sh` and recomputed from the
downloaded bytes; a mismatch aborts before unpacking.

**yamlfmt** (yaml) -- `google/yamlfmt` publishes per-platform tarballs plus a
`checksums.txt`; the linux/x86_64 archive is verified with `sha256sum -c`
before use. The binary is **statically linked** (zero `NEEDED`, no glibc
involvement), so it is a plain download+strip+bzip2 with no compile step, and
the build script asserts it is still static (a dynamic build would mean
upstream changed the release layout and the "no glibc floor" argument in its
header would no longer hold).

**Two invocation gotchas, both load-bearing (documented in ADDING_BINARIES):**

1. **prettier is NOT fed `-`.** conform's built-in `prettier` formatter reads
   the buffer on **stdin** and passes `--stdin-filepath $FILENAME` (prettier
   infers the parser from that filename's extension). A bare `-` makes prettier
   exit with `No files matching the pattern were found: "-"` and format
   NOTHING -- silently, because conform treats a no-op formatter as success.
   The build script asserts both the positive form and that `-` is rejected.
2. **prettierd is deliberately NOT shipped.** It is a separate daemon npm
   package (fsouza/prettierd) that only exists to speed up repeated formats,
   and its conform entry does config-file discovery (`cwd` walks for
   `.prettierrc*`). Plain `prettier` formats correctly without a daemon, so
   the mapping is now just `javascript = { "prettier" }` and `prettierd` is
   dropped from it (and from the gate's KNOWN_EXTERNAL).

**Verified:**

- `./loadout resolve prettier yamlfmt` -> 3 packages (nodejs pulled in);
  a real `./loadout install prettier yamlfmt --dest-dir` installs both
  launchers plus the nodejs dependency, and `prettier --version` -> 3.8.1,
  `yamlfmt --version` -> 0.21.0.
- **headless nvim end-to-end**: with the repo env as config and the real
  loadout installs on PATH, `conform.format()` on a messy `.js` and `.yaml`
  reformatted both (js object literal spacing + function body; yaml key and
  list-item spacing).
- the gate now reports 12 filetypes mapped, zero unresolved, KNOWN_EXTERNAL
  empty.
- regen chain in the correct order, all three sync gates green, `run-all
  --fast` green.

## 2026-09-29: mdformat 1.0.0 -- markdown formatting enabled in env-nvim (unreleased)

**The bug.** `envs/nvim/lua/global/plugins/conform.lua` mapped
`markdown = { "rumdl" }`, but rumdl was never a loadout package and is not
installed. conform.nvim resolves a formatter name to a binary on PATH; finding
none it does not error -- it falls through to `lsp_format = "fallback"`, and a
filetype with no LSP then gets a **silent no-op**. Markdown therefore had no
formatter at all, and nothing said so: the payload was complete, the registry
valid, the manifest matched, and every existing gate stayed green. The file
also carried a **dead `formatters.mdformat` entry** (`--wrap keep`) that nothing
referenced -- someone had started exactly this change and never finished it.

**The fix.** `mdformat` is now a non-optional `python-tool`. It was the right
pick over the alternatives:

- **pure-Python, py3-none-any** -- installs offline from the wheelhouse with no
  source build and no glibc risk (contrast rumdl, a Rust tool that would have
  needed a cargo build wired into `build/update`).
- **closure is 1 new wheel** -- `markdown-it-py` and `mdurl` were ALREADY in
  the wheelhouse (my first grep missed them because wheel filenames use
  underscores, not hyphens); `tomli` is gated `python_version < "3.11"`, so the
  whole addition is `mdformat-1.0.0-py3-none-any.whl` (53 KB).
- conform.nvim's pinned version already has a built-in `mdformat` formatter
  (`command = "mdformat", args = { "-" }`), so `prepend_args = { "--wrap", "keep" }`
  yields the effective `mdformat --wrap keep -`. `keep` matters: without it
  mdformat would rewrap every hand-wrapped paragraph in this repo's docs on
  save.
- the pre-existing, already-correct `formatters.mdformat` entry is finally live.

**The gate this forced.** `tests/nvim-formatters-resolve` (T1, wired into
`run-all`) parses conform.nvim's `formatters_by_ft` and requires every named
formatter to resolve to a payload `bins` entry, a python-tool **console script**
(uv exposes every wheel entry point to `~/.local/bin` even when the registry
`bins` list is empty -- that is how `tclfmt` resolves via tclint), or an LSP
provider. RED/GREEN proven: restoring `rumdl` fails the gate, `mdformat` passes.

**Pre-existing debt the gate now records rather than hides.** The same
silent-no-op class affected two more formatters, recorded in the test's
`KNOWN_EXTERNAL` table with reasons rather than hidden:

- `javascript = { "prettierd", "prettier" }` -- `envs/nvim/package.json`
  declares `prettier 3.8.1` as a devDependency, but **nothing runs an npm
  install** and the env ships no `node_modules`, so both were absent.
- `yaml = { "yamlfmt" }` -- not a loadout package.

Both were closed the same day (see the entry below), so `KNOWN_EXTERNAL` is
now EMPTY.

**Verified:**

- `./loadout resolve mdformat` -> 3 packages; offline
  `uv tool install mdformat --no-index --find-links <wheelhouse>` resolves
  (3 packages, 6 ms) and `mdformat --version` -> `mdformat 1.0.0`.
- a real `./loadout install mdformat --dest-dir` installs the launcher and it
  formats correctly.
- **headless nvim end-to-end**: with the repo env as the config and the real
  loadout install on PATH, `conform.format()` on a messy `.md` normalised the
  heading, converted `*` lists to `-`, collapsed stray prose spacing and
  re-padded the table, leaving the code fence alone. The **negative control**
  matters: the same test against the *installed* `~/.config/nvim` (still
  rumdl) produced NO CHANGE, which is exactly the broken state being fixed.
- regen chain in the required order (completion -> sizes -> manifest; running
  sizes before completion re-staled it, since sizes hashes the completion file),
  all three sync gates green, `run-all --fast` green.

## 2026-09-27: librelane stage-32 -- root cause + io_place source patch (unreleased)

The 2026-09-22 open question assumed a tool-version *skew* in slew/cap
estimation. That premise was wrong. The resizer was reacting to a **corrupt
placement input**, and the whole cascade traces to one upstream API unit
change.

**Root cause: `dbTechLayer::getArea()` changed its return units between
OpenROAD 24Q3 and 26Q1.** Measured on both binaries against the same LEF:

| | `met2 getArea()` | computed pin length | signal-pin y |
| --- | --- | --- | --- |
| reference (Feb-2026 build) | 0.0676 (um^2) | 280 dbu | +107,180 (die edge) |
| ours (26Q3) | 67600 (dbu^2) | 241,428,572 dbu | -120,714,286 (~60,000 um off-die) |

67600 dbu^2 IS 0.0676 um^2 -- the same physical area in different units (the
return type went `double` -> `int64_t`, a breaking SWIG change). LibreLane
3.0.14's `io_place.py` (step `Odb.CustomIOPlacement`) computes the pin length
as `getArea() * micron_in_units^2 / WIDTH`, which assumes um^2, so against a
>=26Q1 OpenROAD the length inflates ~1e6x and **every signal IO pin lands
~120 million dbu below the die**. The placer then reports HPWL 4,581,651 um
instead of 1,778 um, the resizer inserts 4374 buffers (35 slew violations),
and the flow dies at `OpenROAD.RepairDesignPostGPL` with DPL-0038 (283%
utilization). The documented "2 slew vs 37 slew" was a downstream symptom of long
nets, not a STA difference.

**Isolation (all measured, all reproducible):**

- Both flows re-run to a kept run dir; the reference (docker
  `ghcr.io/librelane/librelane:3.0.14`, our PDK mounted at the same absolute
  path) completes all 80 stages.
- Synthesized netlists are structurally identical (222 cells, same mix) ->
  yosys 0.69 vs 0.62 exonerated.
- Die/core, 161 fixed taps, PDN fill (62), and the resolved config
  (`PL_TARGET_DENSITY_PCT` 57.3812, padding 0, routability 1) all identical.
- Stage-26 ODBs: same 259 nets, 383 instances, and **identical instance
  name->location for all 383**.
- **2x2 with one fixed binary**: our OpenROAD on the REFERENCE's stage-26 ODB
  -> HPWL 1,768 um (healthy); on OUR ODB -> 4,581,651 um. Deterministic over
  3 repeats. So the binary is fine and the ODB is the problem.
- Probe fidelity control: the reference binary + reference ODB through the
  same standalone probe reproduces 1,778.559 -- bit-identical to the
  reference flow's own number.
- The 9-corner liberty read works standalone (exit 0); the stage-32/35/47
  deaths in my runs are this box's transient SIGKILLs, not a tool defect.

**The fix (option B, user-chosen): a loadout-local source patch, not an
OpenROAD regression.** `_UV_TOOL_SOURCE_PATCHES` + `_patch_uv_tool_sources()`
in `loadout_main.py` rewrite the installed copy of `io_place.py` after every
`uv tool install` (which recreates the venv, so the patch is re-applied every
time by design). It normalizes a dbu^2-scale area back to um^2 in **both** the
H and V length branches -- patching only V was caught by the end-to-end run
(HPWL 6.0e5 instead of 1.8e3). The shipped WHEEL BYTES STAY PRISTINE: the
artifact in payload/ is the pinned upstream wheel, hash-covered by
`.content-manifest`, so the trust chain over what we ship is untouched; the
patch only ever touches the installed copy.

Each patch is idempotent (re-run finds the new text and no-ops) and GUARDED
(if the anchor is absent and the new text is absent too, upstream moved the
code -- warn and leave it alone rather than blind-write). The result is
compile-checked before writing, and the write is atomic with the original mode
preserved.

**Verified (cheap, no multi-GB install):**

- `tests/python-tool-source-patches` (new T1): every anchor occurs exactly once
  in the real payload wheel, the replacement differs from the anchor, and the
  patched upstream file compiles. This makes the anchor load-bearing -- a wheel
  bump that moves the code fails the gate instead of silently no-op'ing the
  patch (the exact failure mode the installer's own guard exists for).
- A/B on the same input ODB, same LEFs, same config, same binary -- only the
  patch differs: pristine upstream `io_place.py` places the signal pin at
  **y = -120,714,286**; the installer-patched one at **y = -140** (die edge).
  Both exit 0, so the script runs either way -- the difference is purely
  where the pins land.
- A real `./loadout install librelane --dest-dir` reports
  `Patched librelane/.../io_place.py (upstream/toolchain incompatibility)` and
  the installed file compiles.

**VERIFIED (2026-09-28, within the RAM constraint): the flow now reaches stage
80.** Two separate blockers were found and separated:

1. **The io_place patch fixes the documented stage-32 blocker.** With it, the
   flow clears `OpenROAD.RepairDesignPostGPL` every run and progresses to the
   end. Measured on the way: stage-26 signal pins move from y = -120,714,286 to
   y = -140 (die edge), and stage-28 GPL HPWL from 4,581,651 um to 1,769.9 um
   (reference: 1,778.6).
2. **A second, independent blocker sits one step from the end: `Netgen.LVS`.**
   It is NOT a payload defect -- it is the dev host's *system* netgen. The
   reference container's netgen (1.5.316, compiled Feb-2026) runs headless
   fine and its stage-70 log ends `Circuits match uniquely. LVS Done.`; the
   dev host's netgen is GUI-bound and fails fast with `no display name and no
   $DISPLAY` when DISPLAY is unset, and HANGS (needs SIGKILL) when DISPLAY=:0
   is set. With `--skip Netgen.LVS` the flow runs all 80 stages and logs
   `Flow complete.` with **0 ERROR lines** (only the expected `lvs_error_count
   not reported` / `VSRC_LOC_FILES` warnings from the skip).

So the patch is confirmed end-to-end as far as this box allows: the flow is
sound through stage 80, and the only step that cannot run here is the one that
needs a headless netgen the dev host does not have. On a farm node (or once
netgen is available headless) that step should pass the same way, since the
reference image proves the step itself works.

Also resolved along the way: the earlier "dies at a different heavy stage each
time" pattern was partly a CORRUPT SCRATCH INSTALL, not the flow -- the first
`--dest-dir` install was SIGKILLed mid-extraction, leaving `ruby` as a mix of
3.3.10 and 3.4.10 (`ruby lib version (3.3.10) doesn't match executable version
(3.4.10)`), which broke klayout at stage 62. Reinstalling ruby + klayout fixed
it. Worth remembering: a killed install leaves a half-written tree that fails
much later and far from the cause.

Also landed today: `tk-devel` added to `build/Dockerfile` (xschem's
`Makefile.conf.in` requires the tk node or configure ABORTS), and
`strip-all-elf-binaries` now skips `build/` -- calling it from a build script
re-stripped the committed `build/gitleaks/gitleaks.bz2`, changing its bytes and
breaking the pinned digest `tests/security-pipeline` asserts, and recorded
three `build/` archives in `.strip-manifest` that no committed manifest ever
contained.

## 2026-09-27: xschem 3.4.7 onboarded + strip walk-scope fix (unreleased)

New `kind:bin` package: xschem, the schematic-capture / SPICE-VHDL-Verilog
netlister from Codeberg (`stef_xschem/xschem`, tags carry no release assets, so
it is a mandatory source build). It is the capture front end for what we already
ship (ngspice to simulate, the `liberty-*` models, spice-netlist-ls for netlist
hygiene) and the only loadout alternative for the job. Member of `@eda`, so
`@eda` now resolves 20 packages; non-optional, so it also joins `@shared`.
`depends: [gui_libs]` for the X11/cairo/xcb/jpeg side. Full recipe + the four
traps in `build/ADDING_BINARIES.md`; invariants in AGENTS.md.

**The design decision: it is a Tcl/Tk application, so it ships a private Tcl/Tk
8.6.** `xschem.tcl` IS the netlister and UI and the ELF imports
`Tk_Init`/`Tk_MainLoop`, so the `-ltk8.6` link is REQUIRED. The payload's
`tcl`/`tk` packages are 9.0 and xschem's layer is 8.6-era; EL8's Tcl/Tk 8.6 is
AppStream, not BaseOS, so a host Tk is not acceptable either. The build
therefore makes it self-contained: Tcl 8.6.16 + Tk 8.6.16 from pinned tarballs
into `lib/xschem/lib` beside `lib/xschem/bin/xschem.bin`, with the `tcl8.6`/
`tcl8`/`tk8.6` script libraries. **No `TCL_LIBRARY`/`TK_LIBRARY` export and
nothing under `<prefix>/lib/tcl8.6`** -- Tcl's own `<exedir>/../lib/tcl8.6`
fallback finds the script library, so the LAYOUT is the mechanism and
portable-python's tree is untouched (the `package require -exact` cross-clobber
hazard). Pinned to 8.6.16 to MATCH expect's `libtcl8.6.so`, so the payload's two
same-soname copies can never skew a script-library patchlevel check.

**Four traps, each of which shipped a broken binary before being fixed:**
1. strip BEFORE patchelf (stripping after moves `.dynstr` out of PT_LOAD ->
   "no version information available"; immediate here, everything is versioned).
2. a DT_RPATH ANYWHERE in the loaded set disables the executable's DT_RUNPATH
   PROCESS-WIDE -- Tcl bakes its build-tree RPATH into `libtcl8.6.so`, so
   `gui_libs`' `libjpeg.so.62` was never searched and xschem died with
   "cannot open shared object file" DESPITE gui_libs being installed. Caught by
   the NATIVE ceiling install (CachyOS has no libjpeg.so.62; the container has
   system X11/cairo/jpeg, so it would have shipped). The build now
   `--remove-rpath`s the private Tcl and ASSERTS no DT_RPATH survives.
3. RPATH depth counts from the ELF: at `<prefix>/lib/xschem/bin/` the payload
   lib64 is `../../../lib64`; a two-level element silently resolves to the
   nonexistent `<prefix>/lib/lib64`. Stage-verify asserts each element resolves.
4. upstream ships the system `xschemrc` library-path block COMMENTED OUT and on
   Unix only rebuilds it from `XSCHEM_SHAREDIR` when it thinks it is in a source
   dir, so a relocated install silently loses its symbol library. Fixed at
   upstream's own documented customization point (the shipped `xschemrc` derives
   the path from the launcher's `XSCHEM_SHAREDIR`) -- no ELF rewrite, unlike the
   zsh `_relocate_zsh_prefix` route.

The launcher composes `build/gui-wrapper-env.sh`: without it the payload's EL8
fontconfig 2.13 parses a newer host's `/etc/fonts` and prints pages of
"invalid constant used" on every launch (4+ measured on the dev host, 0 after).

Also shipped: `tk-devel` added to `build/Dockerfile` (xschem's `Makefile.conf.in`
requires the tk node, so configure ABORTS without it), `build/update`
BUILD_SCRIPTS entry, `verify-binaries` skip reason, `farm-versions` entry
(`-v` -> `XSCHEM V3.4.7`), README row, completion regen, and a FUNCTIONAL smoke
in `tests/prebuilt-binaries`: a headless netlist (`-q -x -r -n -o out`, no
display, so it runs in the Tier 3 container too) of a bundled example copied
under a UNIQUE name -- the unique name forces the top level from the caller's
directory while the child cell resolves only through the shipped library path.
Exit 10 = netlist completed WITH warnings (upstream's own harness says so), so
the gate asserts CONTENT, never exit 0.

**Collateral defect fixed: `strip-all-elf-binaries` walked `build/`.** Calling it
from a build script re-stripped the committed `build/gitleaks/gitleaks.bz2`,
CHANGING its bytes and breaking the pinned digest `tests/security-pipeline`
asserts, and it recorded three `build/` archives in `.strip-manifest` -- which no
committed manifest ever contained. `build` is now in `_WALK_SKIP_DIRS`:
committed dev tooling (the pinned gitleaks engine, the build/yara engine+rules
moved OUT of payload on 2026-09-24 precisely to stop being installer-visible) is
not payload and must never be touched by the payload strip pass. Same class as
the marktext in-repo-scratch trap, one directory over. Verified: a strip run
now reports `Processed: 0` and leaves `build/` byte-identical.

Verified: build script stage-verifies green (relocated netlist with the BUILD
PREFIX MOVED AWAY = 0 missing symbols; every RUNPATH element asserted; GUI up
under Xvfb); `tests/prebuilt-binaries` native `All 341 binaries OK (1 skipped)`
with `OK (netlist): xschem headless NAND netlist, 22 lines, 0 missing symbols`;
Tier 3 `tests/prebuilt-binaries-almalinux8 --no-build` `All 319 binaries OK
(23 skipped)` with the same netlist assertion on the EL8 floor; `run-all --fast`
green; sizes (12.9 MB installed) + manifest + README table + completion
regenerated. xschem's footprint: 3.9 MB archive (27 MB upstream install minus
the 12 MB HTML manual and the 7.7 MB gschem importer), no `.part-NNN` chunking.

Next: Tier 3 `--full` (doctor/resolver/completion/idempotence) is deferred to the
release cycle as usual; commit is ready. A release would be class C (new payload
bytes) and, under the new scheme, would be the first `2026.9.1`.

## 2026-09-25: security wheel refresh -- vuln baseline emptied (unreleased)

The 8-package / 32-advisory debt from the 2026-09-24 security pipeline is
cleared. This is the "dedicated bump with per-tool smokes" the jupyterlab
deferral called for:

| wheel | from -> to | resolved by |
|---|---|---|
| aiohttp | 3.14.1 -> 3.14.3 | parity-plot |
| cryptography | 48.0.0 -> 50.0.1 | text-serdes |
| jupyter-server | 2.20.0 -> 2.21.1 | jupyterlab |
| jupyterlab | 4.6.1 -> 4.6.4 | registry `version` + README row |
| msgpack | 1.1.2 -> 1.2.2 | time-plot |
| setuptools | 82.0.1 -> 84.0.0 | (closure member; no tool resolves it) |
| soupsieve | 2.8.4 -> 2.10 | jupyterlab |
| tornado | 6.5.7 -> 6.5.10 | jupyterlab |

EL8/cp314-compatible wheels (manylinux_2_28 / abi3 / py3-none-any) fetched
with `pip download --no-deps` + every acceptable platform tag; the
superseded wheels pruned so no stale sibling sits in `--find-links`.

Preservation proof, because the shared-wheelhouse hazard is exactly that a
bump changes what OTHER tools resolve:

- uv `pkg==version` closure captured for all 13 `python-tool` packages
  BEFORE and AFTER against a rejoined flat wheelhouse. The only moves are the
  8 wheels above, inside the 4 dependent tools (jupyterlab closure,
  parity-plot, text-serdes, time-plot); the other 9 closures are identical.
- all 13 tools installed OFFLINE from the candidate wheelhouse with the
  installer's exact `uv tool install --no-index --find-links ...`; all OK.
- end-to-end `./loadout install jupyterlab parity-plot text-serdes time-plot
  --dest-dir` on the real payload: venvs carry the fixed versions and the
  four CLIs smoke clean.
- `build/vuln-scan`: CLEAN with `assurance/vuln-baseline.json` now
  `accepted: {}` -- all 8 old entries reported STALE after the refresh.
- `tests/run-all --fast` green; `tests/install-parity-plot` and
  `tests/install-python-tool-upgrade` green; `gen-installed-sizes` (exactly
  the 8 wheel keys changed), `gen-content-manifest`, `gen-readme-table`
  regenerated. No ELF work: wheels are not stripped.

Next: push the four local commits when ready, then a class-C release
(first new-scheme tag would be `2026.9.1`).

## 2026-09-24: release versioning scheme -> `YYYY.M.N` (unreleased)

`./build/release` no longer derives `v<YYYY.MM.DD>` tags. New tags are
`YYYY.M.N` (canonical PEP 440: no leading zeros, no `v` prefix), N a 1-based
month counter; the first new-scheme release is therefore `2026.9.1`, then
`2026.10.1` after the month rolls (September's legacy `v2026.09.*` releases do
not count). Old `v*` tags/releases stay -- renaming them would break the signed
trust chain -- and `_get_version` / `.release-version` need no change (git
describe just returns the new string).

Bare runs derive the next N and REFUSE to bump when the month's latest tag has
no fully published release (missing/draft/unreadable -> prints the exact
`--tag YYYY.M.N` repair). Explicit `--tag` is the overwrite/repair path and now
prints the old release's `publishedAt` before replacing. Policy (docs/RELEASE.md
section 8): overwrite only a release that has not earned trust (bad before
section 9 verification / half-finished run); once trusted, any fix however small
gets the next N -- offline consumers cannot see an in-place tag move (`-V` is
unchanged), so a new N is the only update signal. Pinned by T1
`tests/release-tag-scheme` (fake-`gh` draft/missing cases included).

## 2026-09-24: security pipeline -- secret scan, vulnerability scan, SBOM, rules pinning (unreleased)

"Use security software to the max" on the pipeline side, not the product:

- `build/gitleaks/` (engine 8.30.1: bzip2 + sha256 + PROVENANCE + config) and
  `build/secret-scan`: gitleaks over the working tree AND full history (both
  ~seconds; the 638 initial hits were all vendored trees or generated hash
  inventories -- allowlisted in `loadout.toml`; first-party residue was zero).
  Wired into T1 (`tests/security-pipeline`) and the release gates.
- `build/security_tools.py`: pinned syft 1.52.0 + osv-scanner 2.6.0 (URL +
  asset/member sha256 from the GitHub releases API; both static, run in stock
  almalinux:8.10 with `--network=none`). Fetched on demand into the per-user
  cache; nothing enters `payload/` or the registry.
- `build/sbom`: CycloneDX (syft over extracted wheels + crate-store + registry
  components; file-evidence components pruned because `.content-manifest`
  already pins every file). Built inside the release checksum step so
  `sha256sums.txt` covers it; attached as a fourth release asset.
- `build/vuln-scan`: osv-scanner over the wheelhouse (newest per package -- what
  a fresh uv resolve selects) and the crate store (converted to Cargo.lock
  shape). Wheel findings are baseline-gated via `assurance/vuln-baseline.json`
  (landed with 8 packages / 32 advisories, every one with a published fix;
  the 2026-09-25 security wheel refresh cleared them all and the baseline is
  now `accepted: {}` -- stale-baseline reporting forces entries out as
  refreshes land). Crate-store findings are reported
  ADVISORY (source-only offline registry) unless `--strict-rust`.
- `./build/update yara-rules` now verifies the downloaded rules zip against the
  sha256 GitHub publishes for that asset; mismatch aborts, missing digest warns
  and falls back to TOFU (recorded in `assurance/downloads.log`).
- `build/release` step numbering is now: Step 4 secret scan, Step 5
  vulnerability scan, Step 6 tag and release; the checksum step also generates the SBOM. Docs synced:
  `docs/SECURITY.md` section 8, `docs/RELEASE.md` sections 0/8/9, AGENTS.md,
  `.github/copilot-instructions.md`.
- Verified: `tests/security-pipeline` green; `run-all --fast` green;
  secret-scan tree+history CLEAN; vuln-scan CLEAN with the curated baseline;
  sbom 3185 components / 1.7 MB; yara-rules digest dry-run prints the pinned
  digest for an older tag.

## 2026-09-24: scanner tooling out of the product; yara engine/rules -> build/ (unreleased)

De-productification, following the versioning-scheme commit: the malware
scanner is pipeline tooling, not something users install.

- `yara` (registered `bin`) and `agent-deck` removed from
  `payload/packages.json`; `@security` dissolved (its only other member was
  agent-deck, an AI-agent session manager -- not security software, and not a
  good fit here: it drives the default tmux server and mutates it -- status
  line, bind-key, global set-option -- unless its own opt-in socket isolation
  is configured, and its installer edits `~/.tmux.conf`, which loadout manages
  as a symlink).
- The YARA-Forge rules and the scan engine moved `payload/` -> `build/yara/`
  (export-ignored: no release tarball, no content-manifest entry, not
  installer-visible; still git-tracked for the EL8 build box).
  `build/update yara-rules` writes there and no longer touches payload
  manifests; `build/update yara` guidance now says `git add build/yara/` and
  reports the version from `build/yara/version.txt`; `build-simple-c.sh
  --tool yara` redirects its output and stamps that file.
- `build/dev-onboard` no longer installs system yara (the engine is pinned
  under build/); ClamAV remains the system-provided half.
- New regression gates: `tests/registry-integrity` asserts scanner tooling is
  absent from payload/ and present under build/yara/; `build/gen-readme-table`
  gained a stale-row check (a removed package used to leave its README row
  behind forever).
- Verified: `./tests/run-all --fast` green; `./build/scan-for-malware --fast
  --no-clamav` CLEAN 0/461 loading the engine from build/yara/; manifests,
  sizes, README table and bash completion regenerated.

## 2026-09-23: marktext 0.19.1 + fused-line launcher fix (release v2026.09.23)

### marktext (NEW package, `@editor-gui`)

Electron 42 markdown editor: official Linux release bundle repacked (not a
source build). Two native addons are module-scope `require()`s with no
fallback and ship built above the EL8 floor: `ced.node` (GLIBCXX_3.4.29) and
`native-keymap.node` (GLIBC_2.34). Both rebuilt against EL8 (gcc-toolset-14,
node-gyp run via portable-python; native-keymap uses MarkText's own patch).
NSS/NSPR + libsecret + libxkbfile + libcups/avahi co-located in the package
lib64 (RPATH $ORIGIN; never libnssckbi -- firefox rule). The first cut assumed
libcups host-provided ("EL8 AppStream"); a STOCK almalinux:8.10 image has no
cups-libs/avahi-libs, so Tier 3 failed the marktext addon smoke with
`libcups.so.2: cannot open shared object file`. Rebuilt with the three libs
co-located and a new main-process poison negative control in the build verify
(the build image's own cups had masked the gap); re-verified in a stock EL8
container: no missing NEEDEDs, `marktext --no-sandbox --version` = v0.19.1.
`chrome-sandbox` deleted (SUID 4755 impossible in a per-user tree; Chromium
FATALs on a misconfigured helper), so the app needs unprivileged userns: the
probe skips when CLONE_NEWUSER is blocked, like firefox. depends [gui_libs, mesa3d_libs]; non-optional, so it
joins `@shared` and `@editor-gui` (gvim+meld+marktext). Artifacts:
`runtime/marktext.tar.bz2.part-000..002` + `build/build-marktext.sh` (both
untracked before this release). Build: `build/build-marktext.sh --tag v0.19.1`
in the EL8 container; pinned hashes + stage-verify in ADDING_BINARIES.md.
Dest-dir verified: `marktext --version` = `MarkText: v0.19.1` / Electron
42.1.0, all three addons dlopen via ELECTRON_RUN_AS_NODE, wrapper has no fused
line.

### Fused GTK3 launcher composition (payload fix)

`build/gui-wrapper-env.sh` had no trailing newline, so the next concatenated
fragment's first line fused into its last: `unset _host_fc _fc_mode# ...`
shipped in gtkwave/twinwave/rtlbrowse/gvim/mate-terminal wrappers (still runs,
but leaks `not a valid identifier` to stderr and leaves `_fc_mode` set). Fixed
in the fragment + `build/gvim-launcher.sh` + the mate-terminal launcher; the
five payload artifacts repacked. `build/klayout/klayout` dropped the blank
line after the marker so the (unrepacked) KLayout payload still matches the
composed source byte-for-byte -- verified by recomposition. `tests/prebuilt-binaries`
now asserts fragment newline-termination, composes marktext's wrapper against
the sources, and fused-line-scans EVERY installed wrapper (RED proven by the
marktext smoke before the fix).

### packages.json writer regression (fixed)

`build/build-marktext.sh` re-dumped the whole registry with the json default
`ensure_ascii=True`, escaping every em-dash and violating the file's raw-UTF-8
policy (set 2026-09-14). All 17 whole-file writers now pass
`ensure_ascii=False` (firefox/fish/klayout/verilator already did);
`tests/registry-integrity` gained a `\uXXXX`-escape gate (RED/GREEN proven).
HEAD itself had one escaped line (nethogs, from build-simple-c.sh) -- also
normalized.

### run-all Tier 3 cache hole (fixed)

`tests/run-all`'s all-mode cache compared the current tree against a sidecar
written by the LAST full run -- and a plain (non---container) Tier 2 run
rewrote that sidecar. A following `--container` run therefore CACHED-PASSed
the container smoke on a stale `.pass` from any earlier container run
(observed this session: the first `--container` after T2 reported CACHED PASS
for a payload the container had never seen). Container tests now use their own
`fingerprint-container.json`, written only by `--container` runs, so a plain
Tier 2 run can no longer bless them. The re-run immediately found the libcups
defect above, which had shipped through the build-time stage verify.

### Currency + security (this release)

- `check-versions --outdated-only`: agent-deck 1.16.16, fio 3.43, gvim/vim
  9.2.1125, jupyterlab 4.6.4, nodejs 26.10.0, rsync 3.5.1, ty 0.0.83, uv
  0.12.18 -- all DELIBERATELY carried (see deferrals); ncdu lookup 503;
  less/pdftotext remain pinned.
- `./build/update --currency`: every automated package `held` (6mo cadence;
  v2026.09.18 swept four days ago). Named refreshes only.
- Security: yara-rules 20260913 -> 20260920; tldr-data refreshed; ClamAV
  daily built 2026-09-23 (freshclam log-locked by the running daemon --
  benign, DB verified current).
- Post-payload chain re-run to green: sizes 6196 artifacts, manifest 4450
  files; strip in the EL8 container rewrote 2 tars (tldr + yara data
  pass-through).
- assurance: no re-pin owed (portable-python is not assurance-tracked;
  nvim/rust/treesitter/git-nvim/crate-store untouched); `assurance-check`
  35/35 green.

### Carried deferrals (unchanged from v2026.09.18)

jupyterlab shared-dep hazard (now 4.6.4), ncdu (code.blicky.net 503), less 704
(upstream 710 deleted lesskey), pdftotext pin (fontconfig floor), crate-store
closures for bumped ty/uv, librelane stage-32 tool-version skew (see the
librelane section below -- packaging complete, not chased).

### Release checklist state (v2026.09.23, class C)

- [x] gh auth ok; signing key loaded into `~/.ssh/loadout-agent.sock`
- [x] currency + security above
- [x] post-payload chain + `--check`s (sizes 6197 artifacts, manifest 4451)
- [x] docs sync: README table, AGENTS (marktext + composition invariant),
      copilot-instructions, ADDING_BINARIES, completion regen, this file
- [x] Tier 1/2/3 green on the final tree: `tests/run-all --container` rc=0;
      container smoke `All 320 binaries OK (23 skipped)`; marktext wrapper
      smoke `OK (wrapper): launcher composition + 3 native addons` (the
      `--version` skip is the probe-based userns host contract)
- [x] Two gate findings fixed during the release (see above): libcups/avahi
      co-location + the run-all container-cache hole
- [x] committed `032c1d0`; `./build/release --tag v2026.09.23` published;
      §9 verified (below)

### v2026.09.23 (RELEASED 2026-09-24)

Class C. Tag signed ED25519 (Good signature), `origin/main ==
v2026.09.23^{commit}` (`032c1d0`), `isDraft=false`. All three assets present:
sha256sums.txt, default.content-manifest, nvim-plugin-stash.tar.bz2
(344538464 B; sha `28a5ad38...` matches both the local stash and the
v2026.09.18 hash -- bytes unchanged, re-uploaded as a new-tag asset).
Published `.content-manifest` sha `b62d2acc...` matches the local file. Gates:
T1+T2+T3 `tests/run-all --container` rc=0 (container smoke `All 320 binaries
OK (23 skipped)`), dry-run + real scan CLEAN 0/78645 (YARA-Forge 20260920,
ClamAV 1.5.4/28132), native smoke `All 342 binaries OK (1 skipped)`. Release
notes table still comes from farm-versions (open defect entry 9). Two gate
defects were found and fixed BY this release cycle: the libcups/avahi closure
and the run-all container-cache hole (both above). Follow-ups carried:
jupyterlab 4.6.4, ncdu (code.blicky.net 503), less 704, pdftotext pin,
crate-store closures, librelane stage-32 tool-version skew.

## 2026-09-22: xclip 0.13 onboarded + btop theme set finished (COMMITTED b6e769a, UNRELEASED)

Two workstreams, both from the 2026-09-21 btop session's leftovers (that
session was interrupted while proving them; xclip had been requested and only
reconnoitered).

### xclip 0.13 (NEW package, `@gui-suite`)

- `build/build-simple-c.sh` gained an `xclip` recipe (`./bootstrap;
  ./configure; make`) -- GitHub tags ship `configure.ac` + `bootstrap` only.
  Built in the EL8 container:
  `build/build-shell sh -c 'PATH=/repo/.loadout-bootstrap/bin:$PATH
  ./build/build-simple-c.sh --tool xclip --tag 0.13 --src
  /repo/.build-src/xclip-0.13.tar.gz'` (the image has no system python3.14,
  so the registry-stamp step needs the bootstrap interpreter on PATH).
  Tarball `astrand/xclip` tag `0.13`, sha256
  `ca5b8804e3c910a66423a882d79bf3c9450b875ac8528791fb60ec9de667f758`.
- NEEDED = `libXmu.so.6 libX11.so.6 libc.so.6`, max GLIBC_2.14 (EL8 floor is
  fine). Both X libs come from `gui_libs`, which the stock almalinux:8.10
  image does NOT have -- so the registry entry carries
  `depends: [gui_libs]` (xsel's entry does not, and xsel only NEEDs libX11;
  xclip's libXmu is the load-bearing difference).
- Registry: `kind: bin`, `bins: [xclip]`, `version: 0.13`, tags
  `[gui, clipboard]`, member of `@gui-suite` next to xsel.
  `build/update` (BUILD_SCRIPTS + non-downloadable list),
  `build/verify-binaries` (_SKIP_REASONS "built from source"),
  `build/farm-versions` (`-version` -> `xclip version ([0-9]+\.[0-9]+)`).
- `tests/prebuilt-binaries`: `PROBE_FLAGS["xclip"] = [["-version"]]` --
  `--version`/`-V`/`--help` are read as input FILENAMEs and exit 1.
- Verify: dest-dir install of `xclip env-btop btop` rc=0 (3 binaries, 99
  libs); installed `local/bin/xclip -version` = `xclip version 0.13` with a
  restricted PATH.
- Add a clipboard tool for tmux-yank's `xsel`-first ladder: xsel stays the
  preferred copy command (it is checked before xclip), xclip is the
  fallback.

### btop theme set + btop-theme-tour (finishing the 2026-09-21 work)

The previous session had packed both artifacts and verified the install, but
stopped before the permanent proof and the doc/test entries.

- Theme resolution proven with strace under a SIZED pty (a width-0 pty makes
  btop exit 1 -- the "can't find pane / no winsize" harness artifact): with
  the managed config and an empty `~/.config/btop/themes`, btop opens
  `<prefix>/share/btop/themes/default_black.theme` by itself -- no wrapper,
  no flags. btop reads `<real binary>/../share/btop/themes` via
  `/proc/self/exe` (src/btop.cpp, v1.4.7).
- `tests/prebuilt-binaries`: `PROBE_FLAGS["btop-theme-tour"] = [["--help"]]`
  (`--version` exits 2 as an unknown option) plus a functional
  `smoke_runtime_layout` block: the installed themes dir must hold the
  shipped set, `btop-theme-tour --list` must enumerate exactly those themes
  (proving its argv[0] prefix resolution), and when env-btop's config is
  installed alongside, its `color_theme` must name a shipped theme.
- `env-btop` registry entry reaches the completion file
  (`env-btop` + `@gui-suite`/`clipboard` tags regen'd); README row for btop
  updated to mention the theme set + tour, xclip row added.
- `build/ADDING_BINARIES.md`: new "btop 1.4.7 -- theme set + btop-theme-tour"
  section (silent-failure rationale, no-wrapper decision, deterministic
  archive recipe, smoke) and the small-C-tools section now covers xclip.

Next: Tier 3 `tests/prebuilt-binaries-almalinux8 --full` (covers btop, xclip,
mermaid-ascii, netlistsvg, librelane -- one run); commit + release when
requested (payload bytes added -> class C). librelane is NOT yet runnable
end-to-end -- see the audit below (three blockers).

## 2026-09-22: librelane component audit -- three blockers, ALL FIXED (COMMITTED b6e769a, UNRELEASED)

Question asked: does the onboarded `librelane` package have every component a
real flow needs? Answer: no. Audit used the package's own acceptance test,
`librelane --smoke-test` -- the bundled `spm` design driven through the full
80-stage Classic flow with real tools (`PDK_ROOT=~/.ciel`; smoke used sky130A,
which is present next to ihp-sg13g2).

Ladder (each row = one fix applied, then re-run):
- librelane 3.0.6, stock tree: dies at stage 5 `Yosys.JsonHeader` (4/80 done),
  `Error parsing options: Option 'y' does not exist`.
- 3.0.6 + pyosys shim: stage 5 passes (5/80), dies at stage 6
  `Yosys.Synthesis`, `Syntax error in command 'abc -fast'`.
- 3.0.14 + pyosys shim: 15/80 -- clears synthesis AND everything OpenROAD did
  before the crash (CheckSDCFiles, CheckMacroInstances, STAPrePNR, Floorplan,
  DumpRCValues), dies at stage 16 `Odb.SetPowerConnections` SIGSEGV inside our
  `libpython3.14.so.1.0`.

### Blocker 1 -- yosys has no pyosys, so `yosys -y` does not exist (FIXED)

Every shipped flow (Classic / Chip / VHDLClassic / Optimizing /
SynthesisExploration) runs `Yosys.JsonHeader` + `Yosys.Synthesis` as
`PyosysStep`, which execs `yosys -y <script.py>`; those scripts
(`librelane/scripts/pyosys/*.py`) `import pyosys.libyosys`. `-y` is
compile-time-gated in `kernel/driver.cc` (registered only under
`YOSYS_ENABLE_PYTHON`, which needs `-DYOSYS_WITH_PYTHON=ON` plus a
`Python3Devel` prefix and a PyosysEnv with `pybind11>3,<4` + `cxxheaderparser`
or `uv`). Our yosys 0.69+post build passes none of that -- the option is not
registered at all, so it is not an argument-parsing quirk.
- IMPLEMENTED (Fix A, the wheel route -- chosen over rebuilding yosys with
  `-DYOSYS_WITH_PYTHON=ON`, which needs a py3.14 dev prefix plus
  pybind11/cxxheaderparser/uv that the build container has none of):
  `bin/yosys` is now a WRAPPER (`build/yosys/yosys-wrapper`, ~135 lines) and the
  real binary is `bin/yosys.bin` (wezterm/expect/octave precedent). The wrapper
  passes through untouched, and on `-y` execs portable-python over the script
  with a pyosys package dir on PYTHONPATH -- prepended, not replaced, because
  librelane sets PYTHONPATH to its own scripts dir and those imports must keep
  working. `lib/yosys-pyosys/{pyosys/{__init__.py,libyosys.so},click/}` rides in
  the existing `runtime/yosys.tar.bz2` (the registry `archive` is ONE field, so
  a second archive has nowhere to be listed; `remove_before_extract` gained
  `lib/yosys-pyosys`). That is the MINIMAL import surface -- the wheel's other
  ~32MB (duplicate `share/` tree + second yosys-abc) is dropped because
  libyosys resolves `share/` and `yosys-abc` through `/proc/self/exe` and the
  interpreter is the prefix's own `python3.14`, so it lands on the
  already-installed `share/yosys` and `yosys-abc`. click is vendored there too
  (portable-python has no click; the pyosys scripts are click CLIs).
  `build-yosys.sh` fetches the cp314 manylinux wheel from PyPI when absent and
  verifies a pinned sha256 (`c3575960...0147`); the wheel is committed under
  `payload/<platform>/wheels/` as a build input (build-cicwave/build-sby
  precedent); a version with no pin warns instead of accepting silently. The
  relocation smoke gained a `-y` test using the exact API the librelane scripts
  use (`Design()`, `run_pass("synth")`, `run_pass("stat")`).
- VERIFIED beyond the smoke: the REAL
  `librelane/scripts/pyosys/json_header.py` from the 3.0.14 install was run
  through the deployed wrapper exactly as librelane invokes it (`yosys -y
  <script> -Q -q -- --config-in ... --extra-in ... --output ...`, PYTHONPATH =
  librelane's scripts dir) and produced the JSON header librelane consumes --
  rc=0, valid modules/ports/netnames. That exercises click, pyosys import,
  `Design()`, and the techlib tree in one shot.
- **ARGV CONTRACT (driver.cc:530-553) -- the failure that survived the first
  cut.** The spec is `special_args = everything after the literal --` and
  `sys.argv = [scriptfile] + special_args`. `PyosysStep.get_command()` emits
  `yosys -y <script.py> -Q -q -- --config-in <config.json>`, and the scripts are
  click CLIs that read `--config-in` out of `sys.argv`. An earlier revision of
  the wrapper forwarded the ORIGINAL argv, so the script received
  `["-y","-Q","-q","--","--config-in",...]` -- click rejects the leading `-y`,
  `--config-in` is never reached, and EVERY stage-5 script dies. Note the shape
  of the blind spot: a bare `yosys -y script.py` (what a casual smoke writes)
  works fine, because there is no `--` and no click argument; only the real
  invocation fails. The wrapper now shifts past `--` before exec and the smoke
  asserts the contract explicitly (rejects any leaked `-y`/`-q`/`-Q`, requires
  `--config-in` and its value, checks `sys.argv[0]`). That smoke was run against
  the deployed tree and the real `json_header.py` completed and wrote its header.
- Fix B (the alternative, NOT taken): rebuild yosys with
  `-DYOSYS_WITH_PYTHON=ON` in `build/build-yosys.sh`. The build container has no
  python3.14 dev prefix, no pybind11/cxxheaderparser and no uv (checked), so
  this needs image work before the build script could enable it.

### Blocker 2 -- librelane 3.0.6 hardcodes `abc -fast`, removed in yosys >= 0.68 (FIXED)

`synthesize.py` in the 3.0.6 wheel calls `abc -fast` unconditionally; yosys
dropped `-fast` from the abc pass in 0.68. 3.0.7 still hardcodes it; by 3.0.14
it is gated on the pyosys-reported version
(`if not yosys_version_at_least(0, 68): abc_pass.append("-fast")`).
3.0.14 was installed FULLY OFFLINE in scratch
(`uv tool install --no-index --find-links <payload wheels> librelane==3.0.14`)
and its `Requires-Dist` set is identical to 3.0.6's -- a straight re-pin of
`version` + wheel names in the registry, no new dependencies. DONE: the
registry pin is now `3.0.14` and the wheelhouse carries
`librelane-3.0.14-py3-none-any.whl` (3.0.6 retired).

### Blocker 3 -- our `openroad -python` segfaults (payload bug; Tcl mode is fine) (FIXED)

`openroad -python -c 'pass'` died with SIGSEGV, `si_addr=0x8`, backtrace
`main -> Py_InitializeFromConfig -> pycore_interp_init -> init_static_type ->
type_ready -> PyErr_Format`. Reproduced on the dev host, in a FRESH
`--dest-dir` install, AND inside the EL8 container -- so it was the payload, not
tree rot and not a newer-glibc ceiling issue.

**ROOT CAUSE: the shipped `libpython3.14.so.1.0` has invalid `.dynsym` section
indices.** From the portable-python 3.14.7 archive:

```
payload: PyExc_TypeError  value=0x67ebb8  OBJECT GLOBAL  shndx=38
system : PyExc_TypeError  value=0x5f7678  OBJECT GLOBAL  shndx=24
```

Section 38 in the payload library is `.rela.data.rel.ro` -- a RELOCATION
section; section 24 in the system library is `.data`, which is correct. The
library's `.symtab` is FINE (it says `D PyExc_TypeError`); only `.dynsym`, the
table the linker and dynamic loader actually use, is wrong. **1822 entries** are
affected: 205 OBJECT (170 at `.rela.data.rel.ro`, 27 at `.rela.init_array`, 7 at
`.rela.eh_frame`, 1 at `.rela.fini_array`) and 1617 FUNC (all at
`.rela.rodata`). Almost certainly a BOLT artifact (`--enable-bolt`); the EL8 3.6
and Arch 3.14 libraries, neither BOLT'd, are clean.

**Do NOT assume only the OBJECT symbols matter.** That was the first cut's
mistake, and it is a trap: functions are normally referenced by name through the
PLT/GOT, so a bad section index looks harmless -- but a consumer that takes a
FUNCTION'S ADDRESS gets an ABSOLUTE (`A`) definition instead of a GLOB_DAT
reference, and that is exactly what CPython's type machinery does
(`tp_getattro = PyObject_GenericGetAttr`, `tp_new = PyType_GenericNew`,
`tp_repr = PyObject_Repr`, ...). Measured on the openroad 26Q3 rebuild: after an
OBJECT-only repair, 17 of 18 `A` symbols were gone and the last one,
`PyObject_GenericGetAttr`, still crashed. A 12-line reproducer with a
`PyTypeObject` holding six function pointers separates the two cases cleanly --
OBJECT-only repair: 6 `A` symbols, core dump; full repair: 0 `A`, runs.

**Why that crashes an embedder.** A consumer taking the address of a CPython
data object normally gets an `R_X86_64_COPY` relocation, which the loader fills
from libpython at run time. A COPY relocation can only be emitted when the
defining library's `.dynsym` entry names a REAL section; because this one names
a relocation section, the linker instead treats the symbol as locally defined by
the consumer -- a PC-relative reference to a zero-filled `.bss` slot for data, or
a frozen link-time ABSOLUTE value for an address-taken function. Nothing ever
fills or relocates either. Confirmed under gdb: the payload consumer's slot
reads `0x0000000000000000`, the system consumer's holds the live object. First
dereference -> SIGSEGV in `type_ready`.

**The discriminator that every earlier guard missed:** the symbol CLASS is not
enough. A correct PIE consumer still shows `B PyExc_TypeError` -- what
distinguishes it is the presence of a `COPY` relocation for that name (for data)
and the ABSENCE of any `A` definition (for anything). Matching on `[ABDRW]`
alone both rejects correct builds (the `B` data symbols, and the `T PyInit__*_py`
functions every Python-bound tool exports) and can miss broken ones.

| link target | A-syms | COPY relocs | result |
|---|---|---|---|
| payload libpython (shipped) | 2 | **0** | **core dump** |
| payload libpython (repaired, OBJECT only) | 6 | 3 | **core dump** |
| payload libpython (repaired, full) | **0** | 3 | `address = 0x7faccb046170` |
| system libpython | -- | -- | works |

- **Fix, applied (UNCOMMITTED):** new `build/repair-libpython-dynsym` rewrites
  each bad `.dynsym st_shndx` from the intact `.symtab` entry of the same name
  (validation: symbol present in `.symtab`, symbol TYPE and `st_value` agree
  between the two tables, target section is of the right kind -- executable for a
  FUNC, an allocated data section with a known object-bearing name for an
  OBJECT -- and the value lies inside it; refuses a partial fix and re-checks
  after writing). New `build/repack-portable-python-dynsym.sh` runs it in the EL8
  container and repacks the archive -- verified byte-identical member list (4076
  entries) with EXACTLY ONE file changed (`libpython3.14.so.1.0`). The shipped
  archive gained a `__pycache__` guard in the process: merely RUNNING the
  interpreter writes `.pyc` files into the tree, and those would have shipped.
  `build/import-portable-python` now runs the repair as a gate before packaging,
  so a defective interpreter cannot reach the payload again.
- **Guard rewritten** in `build/build-openroad.sh` to the real rule: fail on any
  `A` Py data symbol (frozen link-time vaddr, always fatal) or any `BDRW` Py data
  symbol with no matching COPY relocation. Validated against five binaries --
  fails the shipped 26Q3 build and the unrepaired repro, passes the repaired
  repro, the distro interpreter, and a non-ELF control.
- **The build smoke now runs the LibreLane path.** The old smoke only exercised
  Tcl mode, which is exactly why this shipped; `-python` is used from stage 16.
  See also Blocker 1 -- the yosys smoke had the same one-sided blind spot.
- `openroad` rebuild against the repaired library: **DONE (rebuild6, guard green,
  `-python` smoke evaluates a script)**. Superseded -- see the LibreLane
  end-to-end status note below for the current state (32 stages, all four
  packaging blockers fixed).
- Two incidental build-script repairs were needed to get the rebuild going at
  all, both worth keeping: the clone MUST use `--recurse-submodules`
  (`third-party/abc`, `src/sta`, `third-party/slang-elab` are gitlinks), and
  the script must stage a portable-python prefix itself for
  `find_package(Python3 COMPONENTS Development)` at `src/CMakeLists.txt:138`
  (the original build found py3.14 dev headers in `~/.local`; the container has
  `HOME=/tmp`). The staging must NOT use `tar --strip-components=1` -- that
  drops the archive's `local/` dir and install.sh then nests the payload a
  level deeper, so the Development check fails with no Python.h.

### Also noted
- **LibreLane end-to-end status (2026-09-22): all FOUR packaging blockers fixed;
  the only remaining smoke failure is a tool-VERSION difference.** See the
  librelane section in `build/ADDING_BINARIES.md` for the full account. Summary:
  (1) yosys `-y` argv contract, (2) the portable-python `libpython` `.dynsym`
  defect, (3) openroad's undeclared ICU deps, (4) the `openroad -python` helper
  scripts unable to import click/rich/yaml. After (1)-(4) the flow runs 32
  stages (was 17) and stops at `OpenROAD.RepairDesignPostGPL` on a detail-placer
  utilization error.
- **OPEN QUESTION for the next session: the tool-version skew between this
  bundle and the upstream LibreLane image.** RESOLVED 2026-09-27 -- the
  premise was wrong, and the real cause is a single upstream API unit change.
  See the top entry of this file ("librelane stage-32: root cause + io_place
  patch"). The skew table below is kept as the evidence that started it. The `--smoke-test` diverges at
  stage 32 with identical inputs and identical placement -- the ONLY difference
  is tool versions:

  | tool | this bundle | librelane 3.0.14 image |
  |---|---|---|
  | Verilator | 5.052 | 5.044 |
  | Yosys | 0.69 | 0.62 |
  | OpenROAD | 26Q3 (tag) | git `dcf36133` (2026-02-17 snapshot) |

  At `OpenROAD.RepairDesignPostGPL` our repair finds **37 slew + 35 cap
  violations** and inserts **4353 buffers** where the reference finds **2 slew**
  and inserts **25**; 4353 > the core's capacity (283.5% util), so the detail
  placer aborts with DPL-0038. Everything upstream of that stage is
  byte-for-byte identical (same utilization 0.457, same GPL 52.040%, same
  Movable area 3294.410 um^2, same `repair_design -slew_margin 20.0 -cap_margin
  20.0` flags), and the first 32 stages match exactly. So this is NOT a
  packaging defect and NOT the OpenROAD tag alone: the slew/cap estimates differ
  between the tool revisions. Options for the next session: (a) run our bundle's
  OpenROAD standalone on the saved stage-32 ODB and compare `report_slew`/STA
  against the reference's numbers to isolate WHICH tool introduces the extra
  violations; (b) align the tool pins to what the upstream image ships (Yosys
  0.62 not 0.69, Verilator 5.044 not 5.052); (c) accept the stage-32 stop as a
  documented limitation. Do NOT chase the toolchain blindly -- isolate first.
- **The odbpy/PYTHONPATH defect (FIXED 2026-09-22).** With the SIGSEGV and the
  ICU gap both cleared, the flow advanced 17 stages and then died at
  `Odb.SetPowerConnections` with `No module named 'click'`. Chain:
  `librelane/steps/odb.py` runs ODB steps as `openroad -python <script>`, and
  `openroad` executes that script with its EMBEDDED interpreter -- which in this
  bundle is portable-python, deliberately minimal, with no click/rich/yaml. The
  scripts (`odbpy/power_utils.py` -> `reader.py`) import all three. LibreLane's
  own venv HAS them, but a venv's site-packages is not on a subprocess's
  sys.path; only PYTHONPATH crosses that boundary, and LibreLane sets it to just
  its scripts dir. The upstream image has no such gap because its openroad
  embeds a python whose site-packages carries the flow's deps.
- **The fix is a launcher wrapper, not more bundling.** `_UV_TOOL_LAUNCHER_PYTHONPATH`
  (keyed by uv_tool dist name) + `_wrap_uv_tool_launchers()` in
  `loadout_main.py`: uv's `<bin>/librelane` symlink becomes a small sh wrapper
  that prepends the tool venv's site-packages to PYTHONPATH and execs the real
  console script. Prepending keeps any caller PYTHONPATH (LibreLane appends its
  own scripts dir, and must keep resolving). It is idempotent -- the wrapper
  refuses to wrap an already-wrapped launcher -- and it lives in the installer,
  so every uv_tool package that needs the same treatment is one table entry.
  VERIFIED: with it, `openroad -python` imports `power_utils` where it
  previously died, and the smoke advanced from stage 17 to **stage 32**
  (`OpenROAD.RepairDesignPostGPL`) -- 15 further stages.
- **Smoke status after all three fixes:** `librelane --smoke-test` now reaches
  `OpenROAD.RepairDesignPostGPL` and fails there on
  `[DPL-0038] Utilization greater than 100%, impossible to legalize`. That is a
  FLOW-DESIGN failure on the smoke netlist, NOT a packaging/toolchain defect --
  it needs a decision about the smoke configuration, and should not be "fixed"
  by chasing the toolchain further.
- `magic`/`netgen` are not loadout packages (system `/usr/bin` on this dev
  box); the Classic flow needs both (DRC/LVS) plus klayout further on -- fine
  for the dev host, a gap for the farm-node story.
- **openroad's ICU dependency was undeclared (FIXED).** `openroad` NEEDs
  `libicudata.so.60`, `libicui18n.so.60`, `libicuuc.so.60` (the SWIG `*_py`
  modules link against the ICU-using python prefix). The payload already carried
  all three -- as `gui_libs`' files -- but openroad never DECLARED them, so a
  minimal `openroad`+`portable-python` install had no ICU on the loader path and
  died with `error while loading shared libraries: libicudata.so.60`. The
  registry entry now lists them (`libs`), and `SHARED_WITH_PAYLOAD` in
  `build-openroad.sh` documents why the script must not re-package them (they
  are already stripped with RPATH `$ORIGIN`).
- **The openroad smoke was environment-masked, and now is not.** It staged the
  binary + solver libs + portable-python and then ran it with the container's
  `/usr/lib64` implicitly on the search path, so every host-provided soname
  resolved for free -- which is how the ICU gap survived a green smoke. The
  smoke now walks each binary's DT_NEEDED entries with `readelf` (not `ldd`,
  which would re-introduce the masking) and fails on anything that is neither
  staged, declared, nor on an explicit host-provided allowlist (glibc, the C++
  runtime, and the EL8-BASEOS compression/OpenMP libs verified with `rpm -qf`
  in the container). Negative control run: dropping the ICU claim makes the
  check flag `libicudata.so.60`, so the declaration is load-bearing.
- The ASIC project's own `flow/run_librelane.sh` runs the docker image
  (`ghcr.io/librelane/librelane:3.0.14`), so none of this blocks that work --
  it blocks the NO-DOCKER farm-node path this package exists for.
- `--smoke-test` needs real tools + a PDK, so it cannot live in T1/T2; it
  belongs in the container/native EDA gate once the blockers are fixed.

## 2026-09-20: librelane 3.0.6 onboarded (COMMITTED b6e769a, UNRELEASED)

New `kind:python-tool` package: LibreLane ASIC implementation-flow
infrastructure, **Python layer only** (Classic/Chip flows; EDA tools and PDKs
explicitly out of scope -- bring your own). Six console-script launchers
(`librelane`, `librelane.config/env_info/help/state/steps`) from
`entry_points.txt`, mirrored 1:1 in `bins`. Member of `@eda` (resolve = 19
packages incl. librelane); non-optional so `@shared` reaches it.

- Wheel closure (29 dists, machine-verified zero-missing/zero-conflict for
  cp314/Linux): librelane 3.0.6 + ciel 2.6.1 (note: unconstrained resolve
  picks ciel 3.0.0, violating the `<3` bound) + click 8.2.1 (house 8.4.x
  violates `<8.3`; coexist fine) + cloup/deprecated/httpx/lxml/psutil/pyyaml/
  rapidfuzz/rich/semver/yamlcore + transitive anyio/certifi/h11/httpcore/idna/
  typing-extensions/markdown-it-py/mdurl/pcpp/pygments/wrapt/zstandard +
  `wheel` 0.48.0/`packaging` 26.3 (load-bearing: lln-libparse
  `Requires-Dist: wheel`, wheel needs `packaging>=24`).
- klayout wheel decision: upstream
  `klayout-0.30.12-cp314-...-manylinux_2_27/2_28` bundled as-is
  (byte-identical to the verified trial copy; `==` our source-built KLayout
  0.30.12) -- do NOT shim pymod. Live `klayout.rdb.ReportDatabase`
  construct under python3.14 verified.
- lln-libparse 0.56.0: sdist-only for cp314 (upstream wheels stop at cp313),
  so EL8 source-built in `loadout-build` (base gcc 8.5; `CC=gcc CXX=g++`
  override for the baked clang path + `ld.lld->ld` shim for the baked
  `-fuse-ld=lld`; stripped + retagged to `manylinux_2_28`; audit NEEDED =
  system-only, max GLIBC_2.14). Full recipe in `build/ADDING_BINARIES.md`.
- `build/farm-versions`: entry added (`LibreLane v3.0.6` parses cleanly;
  verified `librelane 3.0.6 ok` via `--bin-dir` against the staged install).
- Verify: dest-dir install rc=0 (`installed: librelane`); 6/6 launchers
  `--help` exit 0, `Flow.factory.get('Classic')` imports,
  `klayout.rdb.ReportDatabase` constructs (restricted PATH);
  `doctor --verify` rc=0; regen chain in-container green
  (readme-table --check, completion, strip 0/815, sizes 6102, manifest 4440);
  T1 (`run-all --fast`) rc=0; native `prebuilt-binaries` rc=0
  (`All 336 binaries OK (1 skipped)`).
- Standing phase-4 doctor work (loadout_main.py, tests/doctor-system-newer,
  tests/run-all, this file) preserved byte-identical; this diff only adds
  librelane files (20 wheels + registry/README/completion/farm-versions/
  ADDING_BINARIES/sizes/manifest).
- Disposable scratch: `/var/tmp/librelane-wheels/`, `/var/tmp/lln-probe/`,
  `/var/tmp/ckvenv/`, `/var/tmp/loadout-librelane-test/` (safe to rm;
  `/var/tmp/klayout-spike/` predates this work, left alone).

Next: Tier 3 `tests/prebuilt-binaries-almalinux8 --full` (pending, time);
commit + release when requested (payload bytes added -> class C).

## v2026.09.18 (RELEASED 2026-09-19)

Class C (mermaid-ascii + netlistsvg additions, klayout launcher fix,
portable-Python FTS5 fix, currency sweep). §9 verified: signed tag good
(ED25519), `origin/main == v2026.09.18^{commit}` (`44f4613`),
`isDraft=false`, all three assets present (sha256sums.txt,
default.content-manifest, nvim-plugin-stash.tar.bz2 328 MB, hash
`28a5adb...` matches sums = byte-reused stash), published manifest matches
tree. Gates: T1+T2 green, Tier 3 `--full` green, release dry-run gates
passed (scan CLEAN 0/76773 YARA+ClamAV), `All 310 binaries OK (22
skipped)`. Release-run notes: freshclam log-locked by a running daemon,
but ClamAV daily 28127 dated 2026-09-18 verified current via clamscan;
TMPDIR=/var/tmp/loadout-release-tmp used per the dev-host scratch rule.
Follow-ups: (1) jupyterlab 4.6.3 + crate-store closures (now incl. ty/uv
at new refs, store unrebuilt) still deferred; (2) less pinned at 704
(upstream 710 deleted lesskey); (3) system-package-precedence methodology
still NOT STARTED.

## 2026-09-19 release (IN PROGRESS, class C)

Scheduled release since v2026.09.14. New packages: mermaid-ascii 1.6.1
(@core-cli), netlistsvg 1.0.2 (@eda). Launcher fix: klayout host-GL/
Fontconfig adaptation + xcb default. Private SQLite FTS5 for portable
Python (rebuilt lib only). Currency bumps: ruff 0.16.8, uv 0.12.17, ty
0.0.82, biome 2.5.14, dust 1.2.6, nodejs 26.9.0, time-plot v2026.9.15,
vim/gvim 9.2.1119, bash 5.3.20. lefdef-tools unchanged (no rebuild).
Deliberate deferrals (carried): jupyterlab 4.6.1 (shared-dep hazard),
less 704 (upstream 710 deleted lesskey; pin_reason added to registry),
ncdu 2.9.2 (code.blicky.net 503s version checks), pdftotext pinned
(fontconfig floor), crate-store closures follow-up, system-package-
precedence methodology NOT STARTED. Crate-store: rust-tool-locks.txt
re-pinned ty 0.0.82 + uv 0.12.17 to match the bumps (--check-policy green,
--check-lock green) but the store was NOT rebuilt (known-broken env: see
carried closure follow-up) -- its ty/uv closures are still the old
versions' deps. Security: yara 20260913 current,
tldr refreshed, ClamAV daily 28127 dated 2026-09-18 (freshclam log-locked
by a running daemon; signatures verified current via clamscan).
Post-payload chain + all --check modes green. Release completed as
v2026.09.18 (see top). Next: deferred follow-ups above.

## 2026-09-19: netlistsvg 1.0.2 onboarded (UNCOMMITTED, UNRELEASED)

New `kind:bin` package following the pyright/typescript-language-server
pure-Node runtime pattern: Neil Turley Yosys-netlist→SVG renderer (npm
`netlistsvg@1.0.2`, still the latest upstream; GitHub tag `v1.0.2`, 2020, no
release assets -- the npm tarball is the source). Build note with source URL +
sha512 + pinned dep closure + smoke in `build/ADDING_BINARIES.md`
("netlistsvg 1.0.2").

- `build/build-netlistsvg.sh --tag 1.0.2` modeled on
  `build-typescript-language-server.sh`: fetch_npm with dist.integrity sha512
  verification (`g6E7Q58H...WfQw==`, matches registry metadata), then
  `npm install --omit=dev --no-audit --no-fund` with the loadout node/npm at
  build time (no lockfile upstream; 78 packages vendored), ELF guard (pure JS),
  two absolute-node sh wrappers (`netlistsvg` over `bin/netlistsvg.js`,
  `netlistsvg-dumplayout` over `bin/exportLayout.js`), functional stage-verify.
  One deviation from the brief: `--help` does NOT exit 0 -- yargs 6 demand(1)
  fires before help/version handling, so both CLIs exit 1 with a usage banner
  (verified: `--version` behaves identically, so there is no version output at
  all). The script asserts the usage text and carries weight with the AND-gate
  fixture render (`<svg` asserted). Payload built IN the loadout-build
  container (fresh `--rm` container each `build-shell` run, so nodejs is
  staged + build chained in ONE invocation):
  `build/build-shell sh -c '... ./loadout install nodejs --dest-dir
  /var/tmp/loadout-node-stage ...; ./build/build-netlistsvg.sh --tag 1.0.2'`
  (image ships only python3.6, so PATH is prefixed with
  `/repo/.loadout-bootstrap/bin`; TMPDIR=/var/tmp disk-backed). Output:
  `payload/el8.x86_64.glibc2p28/runtime/netlistsvg.tar.bz2` (2.3M archive,
  13601068 B installed; 0 ELF stripped).
- `payload/packages.json`: `kind:bin`, `bins: [netlistsvg,
  netlistsvg-dumplayout]`, hard `depends: [nodejs]`, version 1.0.2,
  `tags: [eda, yosys, svg]`; member of `@eda` next to yosys/sby/z3/bitwuzla.
  Non-optional, so synthetic `@shared` (and transitively
  `@engineering-loadout`) reaches it -- verified via `./loadout resolve`
  (`@eda` = 19 packages incl. netlistsvg, librelane and openroad;
  `@engineering-loadout` contains it).
- `build/farm-versions`: NO entry (neither CLI exposes a version: `--version`
  exits 1 with the yargs demand banner; gocheat precedent -- version tracked
  only in packages.json; check-versions reports n/a, accepted).
- `tests/prebuilt-binaries`: EXPECT_NONZERO entries for both CLIs
  (`--help`, exit 1, `input_json_file` marker) + a functional
  `netlistsvg (render)` block in `smoke_runtime_layout` (hand-written AND-gate
  `write_json` fixture → exit 0 + `<svg` in output).
- Regen chain IN container: gen-readme-table --check OK (row added by hand --
  descriptions hand-owned), completion regen (`netlistsvg` + tags svg/yosys),
  strip-all-elf-binaries (1 tar rewritten = the new archive, 814 skipped),
  gen-installed-sizes (6082 artifacts), gen-content-manifest (4420 files).
- Verify: `TMPDIR=/var/tmp ./loadout install netlistsvg --dest-dir
  /var/tmp/loadout-nlsvg-test -y` rc=0 (`done` on nodejs + netlistsvg
  runtimes); AND-gate fixture through the installed absolute wrapper with
  `env -i PATH=/usr/bin:/bin` renders a 2079-byte SVG (`INSTALLED-RENDER-OK`);
  `doctor --verify` rc=0 (4421 files match). `TMPDIR=/var/tmp tests/run-all
  --fast` rc=0 (Tier 1 passed). Native `tests/prebuilt-binaries` rc=0
  (`All 331 binaries OK (1 skipped)` -- was 329 pre-netlistsvg; skips
  unchanged; render smoke `OK (render)`).
- README diff is exactly the one new row (plus the still-uncommitted
  mermaid-ascii row); no other docs warranted. The pre-existing uncommitted
  mermaid-ascii work (bin/mermaid-ascii.bz2 + registry/docs edits) is
  preserved untouched -- this diff only adds netlistsvg files.
- Pre-existing `/var/tmp/nlsvg-probe/` host scratch (tarball + flag probing
  with `~/.local/bin` loadout node, read-only, no payload writes) and
  `/var/tmp/loadout-nlsvg-test/` dest-dir install are disposable; safe to rm.

Next: Tier 3 `tests/prebuilt-binaries-almalinux8 --full` (deferred, time --
  covers both mermaid-ascii and netlistsvg); commit + release when requested
  (payload bytes added -> class C).

## 2026-09-19: mermaid-ascii 1.6.1 onboarded (UNCOMMITTED, UNRELEASED)

New `kind:bin` package following the glow/update-prebuilt pattern: terminal
mermaid-to-ASCII renderer (Go, statically linked, upstream tag `1.6.1` with no
`v` prefix). Build note with source URL + sha256 + smoke in
`build/ADDING_BINARIES.md` ("mermaid-ascii 1.6.1").

- `build/update-prebuilt`: `mermaid-ascii` entry in the Go section, `{ver}`
  template bare (no `v`). `build/verify-binaries` has NO glow entry to mirror
  (its registry covers only a subset; absent tools SKIP) -- no mirror added.
- `payload/packages.json`: `kind:bin`, `bins: [mermaid-ascii]`, version 1.6.1,
  `tags: [diagram,mermaid,ascii]`; member of `@core-cli` next to glow.
  Non-optional, so synthetic `@shared` (and transitively `@engineering-loadout`)
  reaches it -- verified via `./loadout resolve`.
- `build/farm-versions`: NO entry (binary has zero version output: `--version`
  errors `unknown flag`; gocheat precedent -- version tracked only in
  packages.json; check-versions reports n/a, accepted).
- Payload built IN the loadout-build container:
  `build/build-shell /repo/.loadout-bootstrap/bin/python3.14
  ./build/update-prebuilt mermaid-ascii=1.6.1` (image ships only python3.6, so
  the warm bootstrap interpreter is driven explicitly). Output: `static ELF, no
  patchelf`; `runs: Error: unknown flag: --version`; wrote
  `payload/el8.x86_64.glibc2p28/bin/mermaid-ascii.bz2`; registry 1.6.1 -> 1.6.1.
  Tarball sha256 `9c284482...ce8d41` matches the published checksums file
  (assurance/downloads.log +1 line).
- Regen chain IN container: gen-readme-table (row added by hand -- descriptions
  hand-owned), completion regen (`mermaid-ascii` + tags ascii/diagram/mermaid;
  verified byte-identical to a fresh `./loadout completion bash`),
  strip-all-elf-binaries (1 stripped = the new file, 813 manifest-skipped),
  gen-installed-sizes (6081 artifacts, mermaid-ascii 13524440 B installed),
  gen-content-manifest (4419 files).
- Verify: `TMPDIR=/var/tmp ./loadout install mermaid-ascii --dest-dir
  /var/tmp/loadout-mermaid-test -y` rc=0 (`done / pre-built binaries`);
  `graph LR / A --> B` via stdin exits 0 with correct ASCII boxes (`--help`
  also exits 0, so the default smoke probe passes with no new entry);
  `doctor --verify` rc=0 (4420 files match). `TMPDIR=/var/tmp tests/run-all
  --fast` rc=0 (Tier 1 passed). Native `tests/prebuilt-binaries` rc=0
  (`All 329 binaries OK (1 skipped)` -- was 328, skips unchanged).
- README diff is exactly the one new row; no other docs warranted.

Next: Tier 3 `tests/prebuilt-binaries-almalinux8 --full` (deferred, time);
commit + release when requested (payload bytes added -> class C).

## 2026-09-17: klayout launcher environment fix (UNCOMMITTED, UNRELEASED)

Diagnosed on the CachyOS dev host (KDE/Wayland): the installed klayout 0.30.10
wrapper unconditionally exported `$prefix/lib64` on LD_LIBRARY_PATH, so the
bundled EL8 fontconfig 2.13 parsed the host's newer `/etc/fonts` and printed ~91
diagnostics; Qt auto-selected its Wayland platform even with WAYLAND_DISPLAY
unset (XDG_SESSION_TYPE=wayland is enough) and rendered invisibly. Verified
fix conditions: host `LD_PRELOAD=/usr/lib/libfontconfig.so.1` clears every
diagnostic; `QT_QPA_PLATFORM=xcb` + host fontconfig yields a real PID-mapped
800x600 window on DISPLAY=:0 in ~3 s. Deep native-Wayland root cause NOT
established; do not claim one.

- Fix is launcher/packaging only; **no C++ rebuild, all 85 ELF payload members
  byte-identical** (SHA256 proof; only the 13 `bin/` launcher members + strip's
  0775->0755 directory-mode normalization changed; member set identical).
- `build/klayout/klayout` is now a TEMPLATE: its single `loadout_gui_env` line
  is replaced by `build/gui-wrapper-env.sh` in `build/build-klayout.sh` at
  packaging time (wezterm/surfer pattern; sed `r` in-place marker replacement).
  Installed wrappers stay self-contained. Qt defaults to xcb when DISPLAY is
  set AND `QT_QPA_PLATFORM` is unset (`${VAR+x}` — explicit values, including
  empty, always win); host Fontconfig preload + host-GL-gated Mesa exports now
  shared via the existing block, knobs LOADOUT_GUI_HOST_GL/HOST_FONTCONFIG
  apply. One EL8-compatible build for all distros; no per-distro builds.
- Repack done IN the loadout-build EL8 container (--network=none): replaced the
  13 launcher members in `payload/el8.x86_64.glibc2p28/runtime/klayout.tar.bz2`
  (rejoin -> splice -> bzip2), pruned stale part-shards, then strip -> sizes ->
  manifest IN container. Original archive kept at
  `/var/tmp/loadout-klayout-fix/original.tar.bz2`.
- New regression: `smoke_klayout_wrappers` in `tests/prebuilt-binaries` —
  installed wrappers must equal the composed template and pass 143
  relocation/environment cases (13 launchers x 11: xcb default with DISPLAY,
  caller overrides incl. empty, GL-less fallback exports, additive caller
  paths, ruby/python derivation). Runs in the clean Tier 3 container without
  host GLVND. Test evidence uses ONLY the absolute isolated payload path
  (`--dest-dir /var/tmp/loadout-klayout-fix/install`); system klayout
  (workaround install) never invoked.
- Real-GUI proof from the isolated updated payload: `klayout -nc -rx` with
  DISPLAY=:0 and no WAYLAND_DISPLAY → two PID-matched viewable windows
  ("KLayout 0.30.12" 800x600 + Tip dialog), stderr EMPTY (zero fontconfig
  diagnostics), host libfontconfig + bundled libqxcb mapped, no libqwayland.
- Gates: ruff + py_compile + shellcheck + `sh -n` green; `ty check
  loadout_main.py` = same 5 advisory diagnostics (installer untouched).
  `tests/run-all --fast` rc=0; native `tests/prebuilt-binaries` rc=0
  (`All 328 binaries OK (1 skipped)`, klayout wrapper+DRC+batch OK);
  Tier 3 `tests/prebuilt-binaries-almalinux8 --no-build --full` rc=0
  (`All 307 binaries OK (22 skipped)`; GLVND skips expected — batch tools
  NEED host libGL, and the wrapper matrix still ran).
- Docs synced: README (isolated test discipline + behavior),
  copilot-instructions (template + don't-use-system-KLayout rule),
  AGENTS (klayout entry + GUI WRAPPER SHARED BLOCK member list + ty 5),
  ADDING_BINARIES (composition + GL/fontconfig behavior). Mermaid-ascii
  documentation deferred by user request — do not implement.

**Rollout (authorized repo-package fix; live `~/.local` intentionally NOT
touched):** `./loadout reinstall klayout -y` (re-extracts the runtime archive
and rewrites the 13 launchers; the running GUI, if any, must be restarted).
Then verify: `~/.local/bin/klayout -v` and on the desktop
`klayout <file>.gds` should map a visible 800x600 window with zero fontconfig
noise; if a session ever needs the old behavior,
`LOADOUT_GUI_HOST_FONTCONFIG=0 QT_QPA_PLATFORM=wayland ~/.local/bin/klayout`.

Next: commit + release when requested (payload bytes changed → class C).

## 2026-09-16: portable Python SQLite FTS5 fix (COMMITTED 2422c0a, UNRELEASED)

The old `portable-python-3.14.7-el8-clang23.tar.bz2` imported `sqlite3` but its
private SQLite **3.53.1 lacked FTS5**. SQLite **3.53.4 CLI/lib64** already had
FTS5 and is separate: `_sqlite3` NEEDED `libsqlite3.so`, RUNPATH
`$ORIGIN/../..`, resolves `local/lib/libsqlite3.so -> libsqlite3.so.3.53.1`.

- Fixed entirely offline in the EL8 `loadout-build` container: fresh-unpack
  cached SQLite source, configure with `--enable-fts5`, build only the shared
  library, strip-debug then patchelf `$ORIGIN`, replace the real private lib
  (755, symlinks preserved), update archive `BUILD.md`, and import in-container.
  **No CPython rebuild.** Reproducible narrow recipe: `build/ADDING_BINARIES.md`,
  "Portable Python 3.14.7 -- private SQLite FTS5 fix". External future builder
  `/home/mylesp/build-work/ppy147/build.sh:59` also adds `--enable-fts5`.
- Evidence: NEEDED glibc + `libz.so.1` only, max `GLIBC_2.28`, RUNPATH
  `$ORIGIN`, no SONAME (same as original). Archive-member SHA comparison:
  only real SQLite library + `BUILD.md` changed; all other **4074** members
  (Python/libpython/`_sqlite3` included) untouched. Compile-options sole delta:
  `ENABLE_FTS5`.
- Offline EL8 create/insert/`MATCH` proof passed; CPython `test_sqlite3`:
  **510 tests, OK (5 skipped)**. Permanent Python FTS5 smoke added in
  `tests/prebuilt-binaries`, independent of the tkinter capability skip.
- Metadata chain **strip -> sizes -> manifest completed IN EL8**. Final
  `TMPDIR=/var/tmp tests/run-all --fast` passed. Native `tests/prebuilt-binaries`: **rc=0, All 328 binaries OK
  (1 skipped)**. EL8 `tests/prebuilt-binaries-almalinux8 --no-build --full`:
  **rc=0, All 307 binaries OK (22 skipped)**. Python FTS5 passed both;
  **full integration green**.
- Ruff + py_compile passed. Advisory `ty check loadout_main.py` reports
  **5 diagnostics**: 2 TaskID invalid-argument and 3 click unresolved-attribute
  reports. Installer unchanged; these are existing documented categories,
  not new installer regressions. The documented baseline of 11 is stale.
- No commit or release done. Developer host `~/.local` intentionally NOT
  reinstalled. Preserve unrelated changes, including deleted `.codex` files.

**Rollout:** obtain the updated checkout/archive on the other machine, run
`./loadout reinstall portable-python -y`, then restart Python processes /
notebook kernels (old mapped library persists). Quick installed-Python proof:

```bash
~/.local/bin/python3.14 -c 'import sqlite3; c = sqlite3.connect(":memory:"); c.execute("CREATE VIRTUAL TABLE probe USING fts5(body)"); print("FTS5 OK")'
```

Next: rollout (reinstall + process restarts) and commit when requested. The
clean-tree/HEAD/gate claims below are historical, not the state of this
uncommitted fix.

Previous update: 2026-09-14 (`v2026.09.14` RELEASED + verified, HEAD `8003271`,
tree clean, origin/main synced).

## v2026.09.14 (RELEASED 2026-09-14)

Class C (currency sweep batches 1-5 + nodejs RPATH fix + cicwave stamp +
Tier 3 lock hardening). §9 verified: signed tag good (ED25519),
`origin/main == v2026.09.14^{commit}` (`21503fe`), `isDraft=false`, all
three assets present (sha256sums.txt, default.content-manifest,
nvim-plugin-stash.tar.bz2 328 MB, hash `28a5adb...` matches sums =
byte-reused stash), published manifest matches tree. Gates: T1+T2 green,
Tier 3 `--full` green (`All 307 binaries OK (22 skipped)`, codecs OK),
release dry-run gates passed (scan CLEAN 0/74178 YARA+ClamAV, smoke 328 OK
cached, versions, checksums). Release-run notes: first dry-run scan died
ENOSPC on the 16 GB /tmp tmpfs (parallel scan+smoke) -- re-ran with
`TMPDIR=/var/tmp/loadout-release-tmp` per the dev-host scratch rule, then
CLEAN; second dry-run exited after steps 1-3 with no Step 0/verdict (cause
unknown -- scan run directly afterwards was fine), third dry-run fully
green. Follow-ups: (1) that silent dry-run2 exit wants an explanation if
seen again; (2) jupyterlab 4.6.3 + 7 crate-store closures still deferred
(below); (3) system-package-precedence methodology still NOT STARTED.

## Session state (read this first)

Everything below is committed and the working tree is clean. HEAD = `0eefd39`.
The firefox-codecs, bitwuzla, sby+z3 sections further down are still accurate
(all UNRELEASED in-tree, all formerly Tier-3-green). Since those sections were
written, this session also landed:

- `bfc71cc` check-versions false-green fix + `tests/check-versions-contract`
  (T1). `--outdated-only` no longer hides error rows; exits 2 on lookup
  failure. Exposed 36+ outdated packages that had been hidden two releases.
- Currency sweep batches 1-5 (`cdd3304`, `8e3d4b2`, `b9fff15`, `c322a7f`,
  `f95e4c1`, `8360b2f`): ~45 package bumps -- astral tools, nodejs 26.8.2,
  fish 4.9.3, vim 9.2.1099, tmux 3.7c, yosys 0.69, verilator 5.052, klayout
  0.30.12, tree-sitter 0.27.0, htop, rsync, xterm, Go/Rust static CLIs, musl
  Rust CLIs, tokei + models EL8 source builds, cicwave 0.7.2 (broken PyQt6
  patch regenerated; import of `cicwave.wave_pg` verified from installed
  tree), ipython 9.17.1, tldr 1.9.0, fresh 0.5.1, tmux-path-store 2026.8.26.
  packages.json normalized to raw UTF-8 (ensure_ascii=False everywhere;
  three writers fixed). update-prebuilt: per-tool stamping (mid-batch yq
  crash used to leave registry unstamped), Go+musl+raw-asset support.
  build/update BUILD_SCRIPTS now classifies EL8 source builds (klayout/
  verilator/xterm/tree-sitter/yosys/htop/rsync) so `--list-outdated` stops
  advertising download recipes for source tools.
- `e632ad4` + `d890fcb` cicwave registry stamp fix (build-cicwave.sh never
  wrote version back; now sources build/lib.sh + loadout_stamp_version).
- `0eefd39` nodejs RPATH fix -- IMPORTANT regression story: the 26.8.2 import
  ran on the host, where import-nodejs's patchelf probe (/usr/bin,
  /usr/local/bin only) found nothing, so bin/node shipped WITHOUT its
  `$ORIGIN/../lib64` RUNPATH. Node NEEDs libatomic.so.1 (declared + bundled),
  but without the runpath it died exit 127 for node/npm/npx/pyright/
  typescript-language-server. Tier 3 caught it (T1+T2 were green; CachyOS
  host has system libatomic.so.1 = ceiling masking the floor gap). Fixed:
  probe honors LOADOUT_PATCHELF + ~/.local/bin; archive re-imported IN THE
  CONTAINER with runpath verified; `node --version` = v26.8.2 from an
  installed dest tree. LESSON: run import-nodejs (and any patchelf-dependent
  import) inside build-shell, or export LOADOUT_PATCHELF.

Gates status: T1+T2 `tests/run-all` rc=0 (includes new check-versions-contract).
Sync gates all green (content-manifest, installed-sizes, README table,
completion, assurance 35/35). Security data current: ClamAV daily Sep 13,
yara 20260913, tldr refreshed. No assurance-tracked package bumped (rust/
nvim/git-nvim/treesitter-parsers untouched) so no re-pin owed.

## BLOCKER (RESOLVED 2026-09-14): Tier 3 phantom cache lock -- fixed, --full green

`tests/prebuilt-binaries-almalinux8 --no-build --full` failed twice Sep 13
(rc=3, `cache lock /cache/fingerprint.lock held for 900s`). Root causes, three
lock-logic defects in `build/docker/almalinux8.10-smoke-entrypoint` (all fixed,
uncommitted):

1. Silent 900 s wait: the loop printed nothing until the timeout, so the
   failure looked like it happened "right after the python bootstrap line"
   after 15 min of silence. Now announces immediately + progress every 60 s.
2. EXIT trap deleted locks it never owned (`rmdir $_lock` unconditionally):
   a waiter timing out on a LIVE lock freed a second runner into the same
   cache tree. Now `_release_lock` checks `_got_lock` -- waiters never touch
   another run's lock.
3. No distinction between contention and a broken mount: mkdir failing with
   no lock dir present now fails fast with `ls -lad`/`id`/`df` diagnostics
   instead of a hopeless 900 s wait.

Plus forensics: owner stamp (`host:pid + UTC date` in `$lock/owner`, removed
before rmdir) and `LOADOUT_SMOKE_OWNER=$(hostname):$$` from the wrapper; the
timeout message prints the stamp (or notes its absence = pre-fix stale lock),
the exact host-side `rmdir` to clear, and `docker ps` advice. Lock semantics
proven without a full run (extracted-block harness: acquire+release,
stale-preserved + exit 3).

What actually happened Sep 13: stale lock from the `docker rm -f ff61`
SIGKILL (trap never fires); both failures waited the silent 900 s against it.
First failure's trap accidentally cleaned it, so the next `--full` (Sep 14,
with fix, full rebuild so the image carries the new entrypoint) acquired
instantly and went green: doctor/resolvers/completion/unit
(63+11+7)/assurance (35) clean, tmp-home + split-shared + modules passed,
`All 307 binaries OK (22 skipped)`, firefox `OK (codecs)`, lock released
(log `/var/tmp/tier3-full8.log`).

NEXT: `./build/release` (gates: scan-for-malware, tests/prebuilt-binaries,
farm-versions tsv, sha256sums; tag/publish waits), then post-publish
verification per docs/RELEASE.md. Release notes should add: nodejs 26.8.2
re-import (runpath fix), cicwave 0.7.2 wheel + regenerated patch, Tier 3
lock-logic fix, jupyterlab deferral (below). Working tree has ONLY the two
intended files dirty (entrypoint + wrapper).

## Release plan (class C, everything else is done)

docs/RELEASE.md is authoritative. State: currency sweep done, security data
fresh, post-payload chain run + committed, T1+T2 green, assurance green.
Remaining: Tier 3 --full green (blocked above), then ./build/release (gates:
scan-for-malware, tests/prebuilt-binaries, farm-versions tsv, sha256sums;
tag/publish waits on those), then post-publish verification per RELEASE.md.
Release should also note: nodejs 26.8.2 re-import (runpath fix), cicwave 0.7.2
wheel + regenerated patch, jupyterlab deferral (below).

## Deferred currency debt (all with evidence, all deliberate)

- jupyterlab 4.6.1 -> 4.6.3: the historical pip --platform resolver blocker
  is GONE (90 wheels resolve cleanly now, no backtracking). But the closure
  moves 29 wheels including shared deps (prompt_toolkit, traitlets, pygments)
  that other bundled tools resolve against -- exactly the "silently changes
  what OTHER tools resolve" hazard ADDING_BINARIES documents. Deferred to a
  dedicated bump with per-tool smokes, NOT this release.
- ncdu 2.9.2 -> ?: upstream (code.blicky.net) timed out during version check;
  delta unconfirmed.
- pdftotext 26.04.0 -> 26.09.0: deliberately pinned (poppler >= 26.06 needs
  fontconfig >= 2.15; EL8 has 2.13.1). pin_reason in registry.
- Crate-store: 7 bumped tool closures NOT absorbed --
  cargo-local-registry cannot build in the container (curl-sys/openssl
  compile failure) and the host binary needs libgit2.so.1.9 (absent on EL8).
  Store validates (2776 crates, 0 mismatch) and --check-policy is green
  against the new refs; absorb in a follow-up.

## System-package-precedence methodology (user ask; phase 4 DONE, rest pending)

User's standing request, in their words: investigate a methodology to skip
installing packages when a newer/manually-preferred system package takes
precedence. Methodology investigated 2026-09-19: the installer has NO
system-version awareness (writes payload into ~/.local/bin unconditionally;
only precedents are the hardcoded git/ssh deferrals), and doctor did NOT
compare versions (presence/hashes only -- the earlier note claiming it did
was wrong; probe machinery lives in build/farm-versions + shell vercomp).
Ranked options: (1) opt-in registry field reusing farm-versions probe
strategies [recommended], (2) --prefer-system flag, (3) persistent user
skip-list, (4) doctor report mode first, (5) not changing the default.
Phase 4 landed (uncommitted): `doctor` prints every payload bin with a newer
system copy (`_system_newer_rows` in loadout_main.py; --version/-V probes,
letter-run version guard e.g. base64, loadout dirs excluded by realpath,
fail-closed on unparseable, payload-wins/system-wins/off-path standing,
never affects exit code), plus `tests/doctor-system-newer` (27 cases, Tier 1
gated). Live proof on the dev box: system nvim 0.13.0, ruby 3.4.10,
coreutils 9.11 all shadow-flagged. Next when requested: opt-in skip on top
of this detection (registry field and/or flag).

## firefox H.264/AAC codecs (UNRELEASED, in tree)

Firefox's ffvpx covers VP8/VP9/AV1/Opus/Vorbis/FLAC/MP3 but NOT H.264/AAC;
those come from a system FFmpeg it dlopens by soname (libavcodec.so.61 first,
down to .53). EL8 ships none, so Facebook Reels / AVC YouTube failed
NS_ERROR_DOM_MEDIA_METADATA_ERR while the `--version` probe stayed green.

`build/build-firefox.sh` now builds a decode-only FFmpeg 7.1.5 (avcodec .61 +
avutil .59 + swresample .5, ~5.7 MB stripped, sha256-pinned tarball, nasm from
the image) and co-locates it in lib/firefox/ with RPATH $ORIGIN. ABI guard
(macro <=61, micro >=100, decoders resolve) plus a real decode of committed
raw H.264/ADTS vectors via build/firefox/check-decode.py -- the same script
tests/prebuilt-binaries runs against the installed tree (27 video + 88 audio
frames). Verified: host smoke `All 328 binaries OK`; Tier 3 `--full`
`All 307 binaries OK (22 skipped)` with `OK (codecs)`; installed-tree
screenshot shows H.264/AAC and VP9/Opus both `LOADED 160x120 ok`. Docs synced
(AGENTS/ADDING_BINARIES/README). Class C on release (payload tar bytes
changed); the formerly-owed currency sweep is now done -- see Session state.

Also fixed this session (committed `e04edf6`): portable-python's
sitecustomize.py hardcoded only the EL8 CA path, so bundled Python 3.14 / pip
/ check-versions / build/update all failed every HTTPS request on
Debian/Arch hosts (OpenSSL fell back to the vanished build prefix
/opt/cpython3147p/ssl/cert.pem). Now probes distro CA paths in order.

(The former "STILL OPEN" items from the interrupted release prep -- the
check-versions false green, the uncommitted yara/tldr refreshes, the
incomplete currency sweep -- are all fixed and committed; see Session state
above.)

## bitwuzla 0.9.1 (SMT solver, UNRELEASED, in tree)

`build/build-bitwuzla.sh --tag 0.9.1` (new). EL8 SOURCE build of the third
solver beside z3; plain single ELF, no wrapper/runtime tree, member of `@eda`.
Upstream's official Linux zip is GLIBC_2.38/GLIBCXX_3.4.32 (dead on EL8) and
0.9.0+ requires GMP>=6.3 + MPFR>=4.2.1 (EL8: 6.1.2/3.1.6), so the script
builds GMP 6.3.0 + MPFR 4.2.2 statically from GNU tarballs and links them in;
NEEDED stays system-only (libstdc++/libgcc_s/libm/libpthread/libc). Base gcc
8.5.0 suffices (GLIBC_2.14 / GLIBCXX_3.4.22 out). One asserted patch: drop
upstream's forced `-static` executable link in `src/main/meson.build` (EL8
never static-links libc/libstdc++). Meson 1.11.1 + python3.12 baked into
`build/Dockerfile` (powertools meson is 0.58.2, < 0.64 required); CaDiCaL from
the meson wrap at build time. sby's `smtbmc bitwuzla` engine works with zero
changes (smtio detects `--lang`); proven end-to-end from an installed tree:
`DONE (PASS` (2-bit counter). Post-payload chain run; T1+T2 green; Tier 3
`--full` green in the EL8 container (`All 307 binaries OK (22 skipped)`, both
bitwuzla lines OK); new functional probe in `tests/prebuilt-binaries`
(`OK (solve): bitwuzla sat model + unsat proof`); host smoke
`All 328 binaries OK (1 skipped)`. README/AGENTS/ADDING_BINARIES/
farm-versions/packages.json/completion synced. Class C on release (touched
@eda membership) -- release procedure still owed; T3 already run.

## sby + z3 (SymbiYosys formal + Z3 solver, UNRELEASED, in tree)

`build/build-sby.sh --tag b1a1e98cba941ec8433f8dc27f416cd7bb7f14be` stages
both: sby is pure Python (no stable upstream release -- commit-pinned,
strace-ui precedent; click 8.4 vendored from the wheelhouse); z3 5.1.0.0 from
the official manylinux_2_27 wheel (EL8-compatible by readelf, self-contained
binary only). `yosys` gained explicit `libs` (libffi/libz/libtcl8.6/libedit)
so minimal installs work on newer hosts (was free-riding on @shared).
Proven: real `DONE (PASS` prove (2-bit counter, smtbmc+z3) with Yosys 0.68,
plus host smoke 327 binaries OK. T1 green, README/farm-versions/AGENTS synced.
Class C on release (touched @eda membership) -- needs T3 + release procedure.

## 2026-09-09 batch 2: installer size accounting, intended permissions, zsh relocatable prefix, xdesk -s fix (RELEASED as v2026.09.09.1)

Class C (installer + payload). Five distinct fixes:

1. **Transaction size accounting (commits `941b4e6`).** `_artifact_paths`
   walked `source` with `os.walk`, which yields nothing for a FILE source --
   `env-starship`/`env-wezterm`/`env-editorconfig`/`env-pip` all reported
   `0 B`. File sources are now added directly, and non-`~/` `extra_links`
   (`starship/config-schema.json`, 170 k) are resolved via repo/envs. Real
   sizes now: env-starship 168 k, wezterm 4.6 k, editorconfig 298 B,
   pip 35 B.
2. **Intended-permissions rule (`85663fa`).** `_grant_owner_write` factored
   out of `_copy_tree_item` and applied to the `install_path` file branch and
   dir `copystat` targets; `require_writable_dir` heals owner-RO dirs instead
   of refusing, refuses only when healing fails (foreign owner, RO mount).
   Reinstall over `chmod -R a-w` is idempotent again; fresh files always
   carry the installer's intended modes. `tests/install-readonly-source`
   grown 9 -> 18 checks.
3. **zsh relocatable prefix (`3b926f0` + payload `fa5381c`).** zsh bakes
   `--prefix` into libzsh as default module_path+fpath and IGNORES
   `MODULE_PATH`, so the shipped `/tmp/zsh-install-5.9` prefix was dead and
   `zle` never loaded -- `shell-typeahead` (zsh leg) red everywhere. Build now
   uses a 96-byte placeholder prefix (asserted in `build-zsh.sh`); installer
   `_relocate_zsh_prefix` rewrites it to the deployed prefix (ELF in place +
   NUL pad, whole-occurrence so suffixes survive, text rewritten, loud FAIL
   on misfit). Build-script stage-verify proves the round trip on a relocated
   copy (negative control first). New T1 `tests/install-zsh-relocation`
   (14 checks). `shell-typeahead` now fully green.
4. **xdesk `-s WxH` fix (`60cf22b`).** xdesk always passed `-resizeable`;
   Xephyr honors `-screen` only while the window is fixed-size, so on any
   WM-managed desktop (KWin window rules / Plasma Zones / tiling WMs) the WM
   assigned the size on map and the root followed -- `-s 640x480` landed at
   1720x1366. Verified: with `-resizeable` -> 1720x1366, without -> exactly
   640x480. Dropped it; `-s` is now authoritative.
5. **valgrind-smoke host-contract skip (`33f58e9`).** CachyOS dev host lacks
   glibc debuginfo, so valgrind refuses to start ("Cannot continue"); that
   specific failure now SKIPs cleanly (covered by the T3 EL8 container gate,
   where it PASSes). Any other nonzero still fails.

Gates: T1 green (incl. new install-zsh-relocation); T2 green (valgrind SKIP
on host); T3 `--full` + `--dynamic` + rust-offline green in the EL8
container. Currency: check-versions no outdated rows; yara-rules/tldr-data
already current (20260906 / refreshed); ClamAV DB current. Post-payload
chain run (strip -> sizes -> manifest, both --check).

**Published + verified (§9):** signed tag good (ED25519),
`origin/main == v2026.09.09.1^{commit}` (`667832d`), `isDraft=false`, all
three assets present (sha256sums.txt, default.content-manifest,
nvim-plugin-stash.tar.bz2 328 MB). Smoke `All 325 binaries OK (1 skipped)`.

**OOM-guard reap (DONE, post-release):** the memory watchdog aborted the gate
parent with `os._exit()` when free RAM dropped, but did NOT reap the in-flight
parallel `clamscan` shard children (grandchildren of the release process) --
one dry-run abort left 11 orphans holding ~12 GB until manually `pkill`ed.
Fix: `_kill_descendants()` in `build/release` walks `/proc`, collects the
descendant tree, and SIGKILLs leaves-first before exiting; the watchdog (both
the parallel path and the low-memory sequential path) now calls `_abort_oom()`
which reaps first. New T1 gate `tests/oom-guard-reap` spawns a child+grandchild
and asserts both die (zombie-aware), with a proven negative control.

**Tier 3 lock caveat (FIXED, post-release):** `--full` takes a `mkdir`
`fingerprint.lock` on the persistent bind mount. Two real bugs, both fixed:
(1) the entrypoint ended with `exec`, which replaces the shell so the EXIT
trap removing the lock NEVER fired -- every successful run leaked the lock
and the next stalled 900 s then exited 3 (fixed: run + exit instead of exec,
so the trap fires); (2) a genuinely stale lock (killed run) still blocks --
`rmdir ~/.cache/engineering-loadout/tier3-v1/fingerprint.lock` to clear it.
(3) 2026-09-14 hardening: the wait is noisy (announce + 60 s progress), the
trap only removes the lock the run itself acquired (waiters never steal a
live lock), mkdir-failing-with-no-lock-dir fails fast with mount
diagnostics, and the lock carries an owner stamp (`host:pid + date`, via
`LOADOUT_SMOKE_OWNER`) printed by the timeout message.
Still do NOT run two `--full` runs concurrently.

**Tier 2 per-test dependency cache (DONE, post-release):** the old cache was
all-or-nothing on a payload+envs+installer superset hash, so any one payload
byte change re-ran every T2 test. Installer-driven T2 tests now use
`--deps auto`: the installer records the exact payload/installer files a test
touched (`_record_install_deps` + `_dep_capture_add`, armed by the repo-local
`.loadout-dep-capture` marker -- env vars do not survive the tests' `env -i`),
and the test's PASS is keyed on that file set's fingerprint. T1 sync gates and
non-installer tests keep the whole-payload `all` fingerprint. Verified: warm
re-run 797s -> 55s; touching `bin/xdesk.bz2` re-ran only the 4 tests whose
deps include it. New T1 gate `tests/dep-capture` proves armed-capture is
correct and narrow and that unmarked installs capture nothing. Both capture
files are gitignored and never written by production installs.

**CI runtime tracking (DONE):** `tests/run-all` times every test and the suite
total, `build/release` times every gate and the release total, all appended to
`~/.cache/engineering-loadout/ci-runtimes.tsv` (machine-local, never committed).
`build/ci-runtimes` shows per-test runs/last/median/max plus CACHED counts and
flags `!!` when the last PASS exceeds 2x the median (and by >60 s); `--recent`
lists suite totals, `--test` filters. CACHED rows never enter the averages.

Last updated (previous): 2026-09-04 (v2026.09.04 RELEASED). `v2026.09.04` is
published and verified: signed tag good (ED25519), `origin/main ==
v2026.09.04^{commit}` (`c0a6efb`), `isDraft=false`, all three release
assets present. Fast path: targeted gates only (new regression test 9/9,
T1 green except zsh typeahead WIP, assurance 35/35, rust-offline green on
the new store) + the release script's own gates (scan/smoke/versions/
checksums); full run-all tiers deferred. `v2026.09.03` is
published and verified: signed tag good (ED25519), `origin/main ==
v2026.09.03^{commit}` (`65986ef`), `isDraft=false`, all three release
assets present (sha256sums.txt, default.content-manifest,
nvim-plugin-stash 344 MB), and the stash hash `28a5adb...` matches the
published sha256sums.txt. `v2026.08.28` notes retained below for history.

## 2026-09-09 batch: gate speedups, OOM guard, Tier 3 install cache, read-only tree contract (RELEASED as v2026.09.09)

Release v2026.09.09 shipped commits `8ecdccf`..`47e5876` (strace batch,
tmux/nvim two-layer, nvim online probe, terminology sweep, gate
speedups, OOM guard, Tier 3 cache, RO-tree contract). Verified: signed tag
good (ED25519), `origin/main == v2026.09.09^{commit}` (`78651ad`), all
three assets present. The speedup/OOM/Tier3/RO work below is the
post-release follow-up batch (commits `a547df8`, `47e5876`).

### Gate speedups (049f4a3)

- `build/fingerprint.py` — shared fingerprint module: `--fast` (mtime+size,
  ~2 s) for test caches, `--exact` (byte-hash, ~40 s) for the release smoke
  cache. `build/release` delegates to it (same trust semantics, one
  implementation). `--exclude NAME` for release-asset/bootstrap dirs.
- `tests/prebuilt-binaries` — persistent install tree at
  `~/.cache/engineering-loadout/smoke-install-v1` (NOT relocatable: the
  installer bakes absolute paths into taplo's schema catalog and tealdeer's
  cache dir, so the tree lives at its install path and the probe scratch
  dir symlinks to it; nvim runtime check uses realpath). Probes run in
  parallel (16 workers, memory-scaled). Cache hit: 3m18s -> 9s.
- `tests/run-all` — Tier 2 result cache keyed on (payload+envs+installer+
  test-script fingerprint, platform). Full suite ~35 min -> ~1m22s on
  unchanged inputs. `--no-cache` forces. Sidecar written once at end of
  run; failed tests have no `.pass` entry and always re-run.

### OOM guard (78651ad)

The 2026-09-09 release dry-run OOM-killed the terminal: 32 GB box, 12 GB
already in swap, four parallel gates (smoke installs ~8 GB, scan + hash
read the whole payload). `build/release` now scales gate workers with
MemAvailable (4 -> 2 -> sequential below 6 GB / 2 GB), a watchdog aborts
with a clear message below 1 GB free, and the smoke probe/hash workers are
memory-scaled too. The actual trigger was ENOSPC in /tmp (a killed
terminal left a 3.2 GB test dir on the 16 GB tmpfs), which the disk
preflight below now catches.

### Tier 3 install cache + disk preflight (a547df8)

- `tests/prebuilt-binaries-almalinux8` bind-mounts
  `~/.cache/engineering-loadout/tier3-v1` at `/cache`; the entrypoint
  fingerprints the tar-copied repo (proved deterministic across
  containers) and skips the `@shared` install phases on unchanged payloads
  (`install_cached` + `gen_stamp` sidecars, written only after the phase
  passed). `install-split-shared-envs` honors `LOADOUT_TEST_SHARED_SEED`
  to reuse the seeded tree. `install-linux-tmp-home` is NOT cached (the
  install IS its assertion). Warm `--full` ~14 min -> ~8 min.
- Gotchas fixed: `__pycache__/*.pyc` written by the pending-daemon spawn
  into the fresh repo copy broke the fingerprint (excluded); `--check`
  compares the fold fields only so older sidecars without `entries` still
  validate; cache lock is a mkdir with a noisy 900 s wait (announce + 60 s
progress), own-lock-only EXIT-trap removal, fail-fast mount diagnostics, and
an owner stamp printed on timeout.
- Disk preflight in the entrypoint: `df` check on /work (12 GB needed)
  fails fast with a clear message instead of the confusing ENOSPC cascade.

### Read-only install-tree contract (47e5876)

`tests/install-readonly-tree` (Tier 2): installs `@shared` + per-user
`@envs`, chmods the tree `a-w`, probes 15 binaries + tldr + python
bytecode, and asserts ZERO write attempts into the tree via strace (the
bundled strace serves as the trace engine). A negative control proves the
detector fires on a deliberate write, so a clean scan is a real proof.
Tree-identity check (path+size+mtime) is the no-strace backstop. The
contract holds because portable-python/uv/tealdeer already redirect
writes to user space; this gate now enforces it.

## 2026-09-08 batch: strace 7.2 + strace-ui, tmux/nvim two-layer, nvim online probe, terminology sweep (UNRELEASED, in tree)

Four changes landed together (commits `8ecdccf`, `b105e63`, `1eb9b54` + the
uncommitted probe/terminology work):

1. **strace 7.2 + strace-ui** — see the 2026-09-05 batch section below for the
   full record; gates were green before this batch and remain so.
2. **tmux + Neovim two-layer config** — `env-tmux`/`env-nvim` expose only
   `global -> user`; tmux XDG dispatcher + managed `tmux.global.conf` +
   preserved `tmux.user.conf`; legacy `~/.tmux.local.conf` migration with
   unattended/declined fallback; snapshot restore only removes the legacy file
   when the snapshot carries it. Covered by `tests/install-env-tmux-nvim-layers`.
3. **nvim online probe** — `vim.g.cfg_online` resolved in
   `envs/nvim/lua/global/config.lua`: `LOADOUT_ONLINE` env → newest
   `${XDG_RUNTIME_DIR:-/tmp}/.loadout-net/detect-*` cache file → live 0.15s
   TCP probe of `LOADOUT_CFG_ONLINE_DETECT_HOSTS` → false (offline-first).
   Lazy's update checker now gates on `cfg_online and not cfg_offline`, so
   plugins never stall on timeouts on air-gapped boxes. `cfg_offline` is the
   read-only-overlay detector.
4. **Terminology sweep** — Cadence-internal terms removed from all
   docs; replaced with generic "online box" (partially online, R/W shared FS)
   and "offline box" (air-gapped, R/O shared FS). `docs/DEPLOYMENT-RUNBOOK.md`,
   the stash design spec, and `docs/HANDOFF.md` updated. The offline
   detector is now generic: any read-only mount of the install root
   (findmnt), no vendor-specific labels.

Gates: focused two-layer test green; `tests/install-nvim-deployments` green
(both shapes, network blackholed); nvim headless probe matrix green (env
1/0, cache 1/0, live probe); generators in sync; fast suite green except the
two pre-existing host/checkout failures (`shell-typeahead` cannot load the
staged zsh/zle module, and doctor reports the release-only nvim plugin-stash
asset absent from this checkout).

## 2026-09-05 batch: strace 7.2 + strace-ui (UNRELEASED, in tree)

Option A from the strace_ui scoping (build-time opam/OxCaml, ship one
native binary). `strace` 7.2 source-built (`build/build-strace.sh --tag
7.2`, non-optional, in @shared): `--without-libunwind --without-libselinux`
(EPEL-only / absent on newer distros -- the CachyOS ceiling gate caught
libselinux loader-failing; both serve flags strace-ui never passes).
`strace-ui` optional, depends [strace] (`build/build-strace-ui.sh --tag
<b48e51a>`: no upstream tags so the commit IS the pin + OX_REPO_COMMIT pins
the OxCaml repo; ~35 min, 264 opam pkgs build-time only; ships native
main.exe 12.7MB bz2, NEEDED glibc+libstdc+++libgcc_s with GLIBCXX 3.4.21 in
EL8's 3.4.25). Dockerfile absorbs opam 2.5.2 + autoconf 2.72 (/usr/local,
distro 2.69 too old for oxcaml configure.ac) + rsync (compiler install dies
127). `-version` = NO_VERSION_UTIL exit 0 (probe + farm-versions marker);
render proven under winsize-set pty (0x0 paints nothing -- harness
artifact). Gates: unit-resolver 64/64, registry-integrity 11/11, README
table OK, optional-packages (new strace-ui section) green, Tier-3
--full 304 OK, host @shared install + Arch ceiling (strace traces,
farm-versions 7.2/NO_VERSION_UTIL) green. Full notes in
build/ADDING_BINARIES.md (strace + strace-ui sections).
## 2026-09-08 batch: tmux + Neovim two-layer config (UNRELEASED)

`env-tmux` and `env-nvim` now expose only `global -> user`. Tmux installs an
XDG dispatcher plus managed `tmux.global.conf` and preserved
`tmux.user.conf`; TPM starts after both layers. Interactive installs offer to
migrate `~/.tmux.local.conf`, unattended/declined installs keep it as a
fallback, and conflicts or symlinks warn without changing user data. Neovim
stops creating/loading corp/site/team/project layers, preserves existing ones,
and warns when they contain files. `tests/install-env-tmux-nvim-layers` covers
fresh installs, reinstall preservation, migration cases, backups, old/new
snapshot restores, malformed canonical paths, and registry metadata. Restore
removes `.tmux.local.conf` only when the snapshot contains that path, so a
pre-layering snapshot cannot erase newer legacy config. `build/update
tmux-plugins` now reads plugin declarations from the global layer rather than
the dispatcher. Gates: focused two-layer test green;
full `tests/install-linux-tmp-home` green; installed-size/content/README
generators in sync; fast suite green except the two pre-existing host/checkout
failures (`shell-typeahead` cannot load the staged zsh/zle module, and doctor
reports the release-only nvim plugin-stash asset absent from this checkout).

## 2026-09-04 batch: read-only install source fix (UNRELEASED, in tree)

Implements enhancement-request-permissions-management.md (rewritten since
the cargo items: now a single bug -- @envs fails when the install source
tree is read-only). Diagnosis verified exact: copy2 preserves the 0o444
mode, then the prefix bake's open(w) dies uncaught. Fix, three layers:
(1) `_copy_tree_item` grants u+w on the destination copy (central -- covers
the whole class, exec bits preserved); (2) `_rewrite_shared_prefix_line`
rewrites atomically (mkstemp + replace) with source mode preserved +u+w,
same pattern as relocate_runtime_token (NOT hardcoded 644);
(3) helix languages.toml relocation hardened identically (it warned and
continued; tealdeer fresh-write and relocate-token were already safe).
New tests/install-readonly-source (9/9, Tier 2): copy u+w, bash+tcsh bake
through 0o444 dests, mode preservation, no temp litter, helix relocation.
Proven to catch the bug (fails on pre-fix code with 0o444). T1 green
except zsh typeahead WIP; assurance 35/35, crate lock/policy OK.

2026-09-09 follow-up (in tree): same rule extended to the destination side.
`_grant_owner_write` factored out of `_copy_tree_item` and applied to the
`install_path` file branch (bare copy2, no guard) and to dir `copystat`
targets; `require_writable_dir` heals owner RO dirs instead of refusing,
refuses only when healing fails (foreign owner, RO mount) — reinstall over
`chmod -R a-w` stays idempotent, fresh files always carry intended modes
(bins already explicit 755/644 via `write_bz2_atomic`). Test now 18 checks:
+dir-copy u+w/x, +install_path u+w, +gate-heals, +gate-still-refuses.

## 2026-09-04 batch: enhancement-request-permissions-management.md fielded

#1 (REQUIRED, stale registry path): NOT a live bug -- already fixed by
d3adc7c (cargo online-first, v2026.08.28). The pre-08-22 writer baked an
absolute `replace-with` path at install time; a work-side reorg
(external/engineering-loadout -> tools/loadout-shared) stranded it. Current
code writes a comments-only stock config (proven: fresh env-cargo install)
and both wrappers (bash functions.sh, tcsh helpers/cargo-wrap) derive
`$LOADOUT_CFG_SHARED_PREFIX/share/cargo/registry-store` (or
`$HOME/.local/...`) per-invocation -- proven with a fake-cargo arg capture
for both layouts. Remedy for the stale box: reinstall env-cargo. No code
changed. (Also confirmed ADDING_BINARIES already documents the stock-config
design, and no work-side literal exists in-tree.)

#2 (RECOMMENDED, crate coverage): wide/lexical-core/axum were absent from
the 2740-crate store (axum sat in the seed list's REMOVED block, whose own
comment anticipates pull-backs). Added as unpinned seeds, rebuilt the store
via build-tool-crate-store.sh: 2776 crates incl. axum 0.8.9,
lexical-core 1.0.6, wide 1.7.0. Build note: `cargo install
cargo-local-registry` cannot compile on EL8 (vendored curl-sys needs
OpenSSL 3+) -- installed the plugin on the CachyOS host and ran the
(all-download, arch-independent) store build there; tar/bzip2 bytes
canonicalized by container strip-all as usual. Re-pinned honestly:
verify-crate-store lock re-emitted, crate-store.toml artifacts/count/yara
re-pinned, malware scan CLEAN over the new parts (YARA 20260830 + ClamAV),
rust-offline-almalinux8 green on the new store, plus a targeted offline
resolve+build of all three new crates (61 packages locked, axum compiled).
TEXT-SERDES/TIME-PLOT zero-coverage warnings are pre-existing (submodule
path-deps, catalogue #14).

## 2026-09-04 batch: GTK3 launcher batch + tk land (UNRELEASED, in tree)

Native-@all survey (335 exes, CachyOS): ZERO loader gaps, ZERO signals.
Four clusters, two landed here:

(a) GTK3 abort on Wayland sessions (gtkwave/twinwave/gvim/mate-terminal):
bundled gdk-3 reads xsettings over GSettings on the Wayland path, newer
GNOME dropped the `antialiasing' key -> GLib-GIO-ERROR abort (133), even
`--version`. New shared `build/gtk3-launcher-env.sh` (GDK_BACKEND=x11 +
GIO suppression, Wayland+XWayland gated, explicit env always wins, EL8/X11
takes neither branch), composed with gui-wrapper-env (GL probe + fontconfig
preload) into: gtkwave/twinwave/rtlbrowse (recipe-generated wrapper-split,
.bin ELFs byte-identical), gvim (new `build/gvim-launcher.sh` source),
mate-terminal (new `build/mate-terminal/mate-terminal-launcher.sh` source,
re-tarred runtime). Proof: 3 live windows on :0, 0 aborts, FST roundtrip
191k lines. Registry: gtkwave bins += 3 .bin; smoke gains twinwave.bin /
rtlbrowse.bin entries + tk lib/tk9.0/tk.tcl sentinel. Gates: T1 clean
(except zsh typeahead WIP), host smoke 324 OK, container --full 303 OK.

(b) wish/tkdiff dead EVERYWHERE (zipfs): build-tk patchelfs the zipfs lib
-> central offset stale -> "Can't find a usable tk.tcl". Fix: file tree
`lib/tk9.0` (untarred from the intact embedded zip) ships as new
`runtime/tk.tar.bz2` (registry archive+sentinel+remove_before_extract);
recipe drops the lib patchelf (guard fails on RPATH) + emits the tree tar.
Proof: Tk 9.0.3 require clean in a bare dest tree, TkDiff windows render.
Side effect: container tcl rebuild refreshed libtcl9.0.so.bz2
(container-canonical, tclsh zipfs verified). OPEN: full tk rebuild is
blocked -- tk 9.0.3 compile fails with unknown-type Tcl_Size against the
fresh tcl build-tree headers (configure used the build-tree tclConfig, not
the installed one); shipped libtcl9tk9.0.so untouched. Meld (py3.6) and the
fontconfig-theme cosmetics remain host-contract/future.

## 2026-09-04 batch: tk rebuild unblocked (tcl sources persist) -- UNRELEASED

wish/tkdiff dead everywhere (above) needed a source rebuild, which was
blocked: tk died in pages of unknown-type Tcl_Size. Root cause was NOT
headers -- the installed tcl.h is fine. The tcl recipe's EXIT trap deleted
its mktemp build tree on return, but the installed tclConfig.sh points
TCL_SRC_DIR at that (now-dead) tree for PRIVATE headers; tk's compile then
silently skipped the missing -I dirs and fell through to system tcl 8.6
(/usr/include/tcl.h, tcl-devel is in the image). Fix: build-tcl.sh persists
sources to stable `/tmp/loadout-tcl-src-<ver>` (cleaned first, repoints
TCL_SRC_DIR, fails loud if either step misses) instead of trap-deleting;
build-tk.sh preflights TCL_SRC_DIR/generic/tcl.h with a one-line error.
Same boot required for both (both die on reboot -- honest, documented).

Rebuild surfaced two more, both fixed in-recipe: (1) fresh wish linked
libcups (auto-detected, absent on minimal EL8 -- Tier 3 caught it), fixed
with --disable-libcups + a closure guard (no libcups, no /tmp loader
paths); fresh wish also NEEDs libcrypt.so.1, which the registry had
ruby-owned while AGENTS/SHARED_LIBS documented it unclaimed -- removed
from ruby libs so it lands with every lib64 selection as documented.
(2) strip-all would now STRIP the RPATH-less zipfs lib (tail truncation),
so it gained an `elf_has_zipfs_tail` skip (EOCD signature) in all three
paths. Final proof: full container tcl+tk rebuild green incl. the no-tree
zipfs test; host smoke 324 OK; container --full 303 OK. tk.tar.bz2 file-tree
idea REVERTED (zipfs proven clean -- simpler payload, no registry churn).

The 2026-08-24 through 2026-08-28 batches below are included in `v2026.08.28`.

## 2026-09-03 batch: release prep (time-plot + lefdef-tools + updater fixes)

Rolling-git updates, all verified forward (old SHAs confirmed ancestors of HEAD):

- `time-plot` `7e9859e` -> `v0.2.0` (pure-Python, native `uv build` fine).
  Smoke: offline wheelhouse install, `--help` exit 0, txt -> self-contained
  HTML renders. First run hit the downgrade-guard false positive below
  (payload already correct); re-run skipped rebuild and stamped currency.
- `lefdef-tools` `cda0e5a` -> `v2026.9.0` (upstream moved 1244b22 -> 90a2e23
  mid-batch and switched to CalVer). NATIVE BUILD FAILS on CachyOS: maturin
  `manylinux_2_28` audit rejects GLIBC_2.30/2.33/2.34 symbols from the host
  toolchain. Built in `loadout-build` instead (rustup 1.96.0 + astral uv
  inside the container, source bind-mounted at /src, wheel to /src/dist):
  `lefdef_tools-2026.9.0-cp314-cp314-manylinux_2_28` with max GLIBC_2.28 and
  glibc-only NEEDED (libgcc_s/libpthread/libdl/libc/ld-linux). Recipe is
  manual -- `_run_rolling` has no container path; the updater then ran the
  skip path (describe == stamped version) and stamped currency 2026-09-03.
  Smoke: offline install, `import lefdef_tools` 2026.9.0, CLI + `--version`.
  LESSON: rolling-git Rust wheels can no longer be rebuilt natively since
  the WSL2->CachyOS move. Next time one is due, either teach `_run_rolling`
  a container build or repeat the manual recipe. Baking a Rust toolchain
  into the image is deferred (size vs frequency).
- `build/update` downgrade-guard false positive (fixed): `_version_tuple`
  parsed short SHA `7e9859e` as version `(7,9859)` -> "BACKWARDS 7e9859e ->
  v0.2.0" on a genuine forward update. Docstring already claimed SHAs
  return None; now true for hex SHAs starting with a digit: 7-40 lowercase
  hex chars containing an `a-f` letter return None. All-digit strings
  (`20260823` date versions) still compare; all-digit SHAs (~4%) still slip
  (indistinguishable from date versions -- accepted). 9-case check green.
- `build/update tldr-data` wrong-cache-dir failure (fixed): user's live
  `~/.config/tealdeer/config.toml` sets absolute
  `cache_dir=~/.local/share/tealdeer/cache`, updater assumed
  `~/.cache/tealdeer` and errored after a successful `tldr --update`.
  `_tldr_cache_dir()` now parses `tldr --show-paths` (`Cache dir:` line),
  falls back to the XDG default.

Security refresh: `yara-rules` updated (19 MB, manifests regen'd);
`tldr-data` refreshed after the fix above; ClamAV daily.cld v28112 built
TODAY 2026-09-03 (system `freshclam -d` daemon holds the log lock -- the
`sudo freshclam` lock error is benign, DB is current). No assurance re-pin:
nvim/rust/rust-crate-store/treesitter/git-nvim/crate-store versions
unchanged since v2026.08.28.

Currency triage: `check-versions --outdated-only` FIRST RETURNED ZERO ROWS
because portable-python's compiled-in CA path (`/etc/pki/tls/...`, EL8)
does not exist on CachyOS -- every urllib fetch failed verify. Same
universal-host class as the firefox ckbi bug. Workaround for the sweep:
`SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt`. Real list: ~38
outdated (agent-deck, biome, fish 4.9.0, nodejs 26.8.1, tmux 3.7c, uv
0.12.9, vim 9.2.1036, ...; pdftotext still pinned). All are build/download
jobs, none DUE by cadence -- deferred to normal bumps, NOT this release.
Two follow-ups worth tracking: (1) portable-python needs a CA-trust story
on non-EL8 hosts (env default? wrapper?); (2) `time-plot` always shows in
`--list-outdated` (describe `v0.2.0` vs HEAD-short `eb37f4e` never equal --
list noise only, `_run_rolling` compares correctly).

Doc drift fixed in-tree: README `gvim nedit-ng` example -> `gvim` alone +
table regen'd (lefdef/time-plot rows); AGENTS dropped three dead
nedit-ng/nvim-qt refs (phase list, klayout contract, shared-prefix list).
`farm-versions` already clean (80470b3). ADDING_BINARIES removal notes kept
deliberately (restore recipes).

## 2026-09-03 batch: Tier 1/2/3 gates for the release (all Tier 3 green)

- `fetch-stash` from v2026.08.28 (sha256 `28a5adb...`, matches the 08-24
  recorded hash) UNBLOCKED FIVE GATES: `check-installer`, `install-nvim-
  deployments`, and container `--full` (whose entrypoint runs `doctor`,
  exit 2 on the missing stash). System python3 was the loadout 3.14 via
  PATH (compiled-in CA `/opt/cpython3147p/...` = dead build prefix), so
  `SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt` was still required.
- Container `--full`: first blocked on harness infra (`/work/dotfiles`
  mkdir denied -- legacy docker creates WORKDIR root-owned, BuildKit chowns
  to USER; fixed with explicit `mkdir+chown` in BOTH smoke and rust
  Dockerfiles), then caught a REAL floor regression: rebuilt Xephyr.bin
  NEEDs `libunwind.so.8`, absent on stock almalinux:8.10 (the recipe assumed
  it present -- same assumption class as libffi/libselinux). Bundled
  libunwind 1.3.1 (NEEDED = libc/libgcc_s only, stripped, no RPATH) into
  the xephyr package libs; recipe comment corrected. Re-run: **300 binaries
  OK, 22 skips, runtimes OK**.
- `--dynamic`: 10/10 PASS. `rust-offline`: was STRUCTURALLY BROKEN since
  the 08-22 cargo-fallback change (entrypoint drove bare `sh cargo` against
  a stock config that can never resolve offline, and its config-content
  assertion matched a COMMENT). Rewrote it to drive the real product path:
  install `@rust env-bash`, assert the config is stock (no `replace-with=`),
  build under bash with the installed bashrc sourced so the `cargo` wrapper
  injects the store. Mode-2 subtlety: the staged config.sh bakes
  `LOADOUT_CFG_SHARED_PREFIX=""`, so the prefix travels as
  LOADOUT_TEST_PREFIX and is exported AFTER sourcing. Result: **both modes
  + ripgrep 15.2.0 rebuild ALL PASSED**, no network.
- Still red (pre-existing, NOT release payload; owner WIP or host-env):
  `shell-typeahead` (zsh), `install-env-zsh` (test picks loadout zsh from
  PATH but installs env-only HOME: binary's built-in module_path is the
  dead `/tmp/zsh-install-5.9` prefix; works only after the env repoints it
  at an installed runtime -- design gap in the owner's WIP area),
  `valgrind-smoke` (CachyOS host lacks glibc debuginfo; valgrind refuses to
  start -- needs a debuginfo package installed on the host, not payload).
  (`registry-integrity` went 10/11 -> 11/11 once the stash existed;
  final host suite: only these 3 fail.)

## 2026-09-03 batch: ruby extension RPATH (release-smoke catch, fixed)

The release dry-run's host smoke failed 6 checks; 5 were MY tmpfs (16 GB,
squatting an 8 GB @shared tree from manual probing -- parallel/sequential
@shared installs then ENOSPC mid-extraction with FLAKY missing files, a
different set each run). Lesson: keep /tmp clear of install trees before
any @shared-shaped run; the smoke cleans its own tmpdir, manual trees do
not. The 1 real catch: `ruby -ropenssl` dies with `libssl.so.1.1: cannot
open shared object file` on non-EL8 hosts. Root cause chain: the stems ARE
installed (unclaimed, every lib64 selection) but nothing points at them --
dlopen'd extensions do not inherit ruby.bin's RUNPATH, and the build smoke
ran everything under LD_LIBRARY_PATH (masking again). EL8 carries openssl
1.1 system-wide, so Tier 3 stayed green while newer hosts broke -- the
wezterm batch's "RPATH does the loading" claim for ruby was never true.

Fix in `build/build-ruby.sh` (new Fixup 5/5, renumbered 1-4): scan every
`.so` under lib64/ruby + share/gems/extensions for NEEDEDs on bundled libs
(libssl/libcrypto/libffi) and patchelf a per-file `$ORIGIN`-relative RPATH
to lib64 (computed depth -- the two layouts differ). openssl.so + fiddle.so
patched; psych (libyaml) and zlib (libz) stay host-assumed. The recipe's
four LD_LIBRARY_PATH uses are GONE from the post-fixup stages -- the staged
tree now proves itself bare. Current tar repacked surgically (patchelf 2
files, re-tar, container `strip-all-elf-binaries` for EL8 bzip2 bytes --
host strip-all first poisoned it with 1.0.8 bytes, caught and redone) and
the chain re-pinned. Proof: `ruby -ropenssl -rfiddle -rpsych` green with
gui_libs; openssl alone green WITHOUT it (stems always present); fiddle
without gui_libs still fails BY DESIGN (ruby does not depend on gui_libs;
klayout pulls it -- noted in the recipe).

## 2026-09-02 batch: portable-python 3.14.7 (this batch)

Bumps portable-python `3.14.4 → 3.14.7` (CachyOS now at 3.14.7; fixes the bad look).
EL8 container build (PGO + LTO + BOLT) via `build/build-shell`, same 9-dep recipe
as 3.14.4 (OpenSSL 3.5.6, SQLite 3.53.1, readline 8.3, gdbm 1.26, zstd 1.5.7,
mpdecimal 4.0.1, libffi 3.4.5, Tcl/Tk 8.6.17, Expat 2.8.0). Toolchain gaps from the
WSL2→CachyOS move healed first: `~/.local/lib/clang/23/include` (241 headers) +
`libclang_rt.profile.a` + `libbolt_rt_instr.a` (BOLT runtime, manual build — old
bolt/runtime CMakeLists generates a broken `cmake -E copy` with kitware 4.4.3).
Pipeline traps hit: perl `-i` length bug corrupted `libcrypto.so.3`/`libzstd.so.1.5.7`
headers (17 vs 25 byte placeholder, shift → `readelf: out of range`; fix: exact-length
`/work/deps/prefix`→`/opt/cpython3147p` (17) and `/work/deps/build`→`/opt/cpython314b`
(16) via binary-safe python `bytes.replace`), plus missing `libgdbm_compat` (dropped
in gdbm 1.26) and missing `bin/pip` wrapper (ensurepip only left `pip3`; added `pip`).
Stage at `~/build-work/ppy147/stage` (off tmpfs — 16 GB tmpfs filled at PGO profile
write), audits clean (no `/work` leaks in ELFs, rpaths `$ORIGIN`/ `$ORIGIN/../lib`),
smoke `python 3.14.7 / openssl 3.5.6 / sqlite 3.53.1 / tk 8.6` green. Payload repacked
via `import-portable-python --platform el8.x86_64.glibc2p28`; old 3.14.4 archive
removed. Post-payload chain `strip-all` (NOSTRIP) → `gen-installed-sizes` →
`gen-content-manifest` → `gen-readme-table` green.

Queued next: shanghai `astral-sh/python-build-standalone` `20260901` (verified:
`install_only` has `libpython3.14.so.1.0` + `include/` + `tk 9.0`; glibc floor 2.17
— lower than ours; PGO+LTO yes, BOLT no; ca trust needs our `sitecustomize` shim;
`_gdbm` missing). Blocker is Tcl 9.0 — OpenROAD needs `8.6.17` pair
(`package require -exact` + `libtcl8.6.so` NEEDED); fix is a decoupled `tcl86`
runtime so base python's Tcl can float. Keep custom 3.14.7 now, switch at 3.14.8.

## 2026-09-01 batch: build-image refound + libcrypt + ssh-agent

- Refound `loadout-build` on docker `almalinux:8.10` (CachyOS is now the dev host,
  glibc 2.44). Mandate rewritten: container = only build surface, cross-compile
  forbidden, `--network=none` is test-only, toolchain binds in.
- `libcrypt.so.1` unclaimed stem for ruby (libxcrypt 4.4.36+ hosts ship `2` only).
- `LOADOUT_CFG_ENABLE_SSH_AGENT` fixed-socket across bash/zsh/tcsh (tcsh parity).
- Grand image doctrine codified; first prereq sweep baked (Qt5 -devel set, etc.).
- Forward-compat doctrine (EL8 = floor).

## 2026-08-31 batch: Windows/macOS retirement

The repo is now 100% Linux-only. Windows and macOS support was retired
2026-08-31; all artifacts live in the owner's personal `windows-dotfiles`
repo (commit `c4ca05b` "Offload all Windows/macOS artifacts from
engineering-loadout" holds installer/loadout.ps1+cmd+pwsh-bootstrap,
envs/powershell, envs/autohotkey, starship.windows.toml,
payload/windows.x86_64 PowerShell zip chunks, download-release.ps1, nvim
lsp/{powershell_es,autohotkey_lsp}.lua, and full package-registry doc
snapshots). macOS may be revisited someday; windows will not.

- Deleted from this repo: `loadout.ps1`, `loadout.cmd`,
  `loadout-pwsh-bootstrap.ps1`, `envs/powershell/`, `envs/autohotkey/`,
  `envs/starship/starship.windows.toml`,
  `envs/nvim/lsp/{autohotkey_lsp,powershell_es}.lua`,
  `payload/windows.x86_64/powershell/` (3 zip chunks + README),
  `tools/download-release.ps1`.
- `payload/packages.json`: `_schema.platforms` comment updated; every
  package's `platforms` is `["linux"]` (or omitted, same default).
- `loadout_main.py`: `_current_platform()` returns `"linux"` unconditionally
  (darwin/win32 branches removed); docstring records the retirement; the
  fonts-phase "Windows Terminal needs fonts installed on the Windows side"
  WSL note dropped (fonts for Windows Terminal are a windows-dotfiles
  concern).
- Tests: `registry-integrity` KNOWN_PLATFORMS = {linux};
  `unit-resolver`'s `winonly` fixture now uses a fictional platform value to
  keep guarding the resolver's platform-filter mechanics without naming a
  retired platform, plus a new `--force still platform-filters` check.
- Docs swept: README (Windows install section, PowerShell/AHK table rows,
  multi-platform line), AGENTS.md (scope, repo map, registry, fonts, tldr
  acquisition paths, PowerShell/AHK/Windows-install sections → one
  retirement note), copilot-instructions (install block, platforms field,
  Windows section → retirement note), docs/INSTALLATION.md (Windows chapter
  → "not supported"), docs/ARCHITECTURE.md (platforms field),
  docs/SECURITY.md (scan coverage), build/ADDING_BINARIES.md (PowerShell
  ZIP section → retirement note), docs/DEPLOYMENT-RUNBOOK.md (Windows
  laptop fetch path → generic "any github-capable box" scp path; TLS
  guidance de-PowerShelled).
- Stash fetch story: TWO paths now -- `fetch-stash` (online) and
  `fetch-stash --from-file --sums` (hand-carried from any github-capable
  machine, still verified). The Windows-laptop PS5.1 path is gone from
  this repo; how someone downloads assets on the far end is their own
  business. `fetch-stash`/`refresh-stash` error messages updated to match.
- `installed-sizes.json` + `.content-manifest` regenerated (order:
  sizes then manifest) to drop the deleted files; `--check` green.

Gates: unit-resolver 64/64, registry-integrity 10/11 (sole FAIL is the
PRE-EXISTING `envs/nvim/vendor/plugins` dir miss, owner's separate WIP),
Tier 1 syntax gates green. `loadout_main.py` diff also carries the
unrelated `_ItemProgress` refactor and the nvim-qt gate-comment (owner's
in-flight work, committed together).

## 2026-08-31 batch: wezterm universal-host fixes (unreleased)

Surfaced the same way firefox's did: loadout wezterm on the CachyOS host.

### fontconfig warning spam -> shared GUI wrapper env block

After the openssl/GL fixes, wezterm still spewed ~91 fontconfig
parse errors/warnings per launch: the bundled EL8 libfontconfig 2.13
(RPATH-resolved) cannot parse Arch 2.18's /etc/fonts conf.d. Fix took
the genericity the owner asked for:

- NEW `build/gui-wrapper-env.sh` -- one shared env-adaptation block
  (POSIX sh) inlined at BUILD time into wrapper heredocs; installed
  wrappers stay self-contained. Contains: (1) host-GL probe (ldconfig
  libEGL.so.1) gating the Mesa/GLVND exports -- host GL present means
  ZERO exports, children inherit clean env; farm nodes keep the
  fallback; (2) host-fontconfig LD_PRELOAD when the host provides
  libfontconfig.so.1 -- host lib+config pair stays version-consistent;
  LD_PRELOAD pins exactly that SONAME. Env knobs for no-rebuild
  adaptation: LOADOUT_GUI_HOST_GL=auto|1|0,
  LOADOUT_GUI_HOST_FONTCONFIG=auto|0|<abs-path>,
  LOADOUT_GUI_LIB64=<dir>. RUNPATH precedence documented: env
  outranks baked RUNPATH; never --force-rpath these payloads.
- Consumers: wezterm x3 wrappers + surfer (which had the identical
  unconditional-poison bug). Both build scripts restructured to
  assemble wrappers as header + `cat gui-wrapper-env.sh` + exec tail.
- Payload: wezterm.tar.bz2 repacked (2x40MiB chunks), surfer.bz2
  wrapper restuffed; deployed via `./loadout upgrade wezterm surfer -y`.
  Verified: `wezterm ls-fonts` 0 fontconfig warnings, GUI clean, cli
  list OK, flatpak + host grep healthy, surfer --help runs; knob
  overrides parse. Tier-1 sync gates green; Tier 2/3 still deferred.

### wezterm: openssl 1.1 sonames + child-env poisoning

Two independent bugs, both universal-host regressions masked on EL8:

1. `wezterm{,-gui,-mux-server}` NEED `libssl.so.1.1` + `libcrypto.so.1.1`
   (EL8 openssl; hosts on openssl 3 ship `.so.3` only) -> wezterm died at
   startup with "error while loading shared libraries: libssl.so.1.1".
   Fix: two UNCLAIMED lib64 stems (payload lib64/lib{ssl,crypto}.so.1.1.bz2,
   from the EL8 openssl-libs rpm 1.1.1k-17, stripped + RPATH $ORIGIN) --
   unclaimed stems install with every lib64 selection (sqlite/readline
   precedent), so wezterm, Qt5Network, AND ruby's openssl.so all resolve.
   RPATH (not env) does the loading.
2. The wrappers exported `LD_LIBRARY_PATH=<prefix>/lib64` unconditionally
   (Mesa/GLVND fallback for GL-less farm nodes). On hosts WITH their own GL,
   that shadowed host glib/pcre2 with gui_libs' EL8-era copies for wezterm
   AND EVERY CHILD it spawned: `flatpak: symbol lookup error:
   /usr/lib/libaccountsservice.so.1: undefined symbol g_once_init_leave_pointer`
   (EL8 glib 2.56 vs host 2.8x), host `grep` broke against the old bundled
   libpcre2. Fix: all three wrappers (wezterm, -gui, -mux-server) now
   platform-condition the Mesa/GLVND exports on an ldconfig probe for host
   `libEGL.so.1` -- host GL present -> no exports at all (children stay
   clean; binaries' RPATH already resolves every NEEDED lib); host GL absent
   -> exports as before (farm-node fallback preserved).

Built/verified on CachyOS: payload wezterm.tar.bz2 repacked with the gated
wrappers (re-chunked 2x40MiB), `./loadout upgrade wezterm -y` deployed;
`wezterm --version`, `cli list`, and a real GUI window all work; flatpak +
host grep healthy again. Tier 1 sync gates green (sizes/content-manifest).
Tier 2/3 still deferred per owner.

### Ride-alongs

- `docs/SHARED_LIBS.md`: libssl/libcrypto.so.1.1 rows added to the
  always-installed table.
- AGENTS.md wezterm entry rewritten for both fixes.

## 2026-08-30 batch: firefox universal-host fixes + bash PS0 preservation (committed 80470b3)

Work happened on the CachyOS (Arch-family) dev box, NOT the EL8 build box.
Everything verified there; Tier 2/3 NOT run yet (owner said stop at T1).

### firefox 140.11.0 -> 140.14.0esr + offline rpm-staging build path

- Current upstream ESR in the 140 line: 140.14.0esr (product-details
  `firefox_versions.json`: FIREFOX_ESR=140.14.0esr, ESR_NEXT=153.1.0esr).
- `build/build-firefox.sh --from-rpms <dir>`: OFFLINE staging path --
  stages from downloaded Alma 8 AppStream rpms (firefox + nspr + nss-3 +
  nss-util + nss-softokn-3 + nss-softokn-freebl) with bsdtar, no
  dnf/EL8-host needed. libffi.so.6/libjpeg.so.62 fall back to the loadout
  payload copies when the host lacks the EL8 sonames. `.desktop` comes
  from the rpm or the currently-deployed payload tar. Glob trap fixed
  along the way: `nss-*.rpm` also matches nss-util/nss-softokn; the core
  NSS rpm must be globbed as `nss-3*`.
- 140.14.0 was built through this path on CachyOS (rpms:
  firefox-140.14.0-1.el8_10.alma.1, nss 3.112.0-8, nspr 4.36.0-2 from
  repo.almalinux.org AppStream). `packages.json` + README table updated
  to 140.14.0; payload re-chunked; sizes/content manifests regenerated
  (`--check` green).
- Box deployed via `./loadout upgrade firefox -y`; `--version` =
  140.14.0esr. Verification: fresh-profile headless
  `--screenshot https://example.com` renders BYTE-IDENTICAL to the
  user-verified-good 140.11 v4 bundle (same md5) -- no trust regression
  in the bump.
- NOTE: firefox CANNOT self-update in this layout (no `updater` binary
  ships; even upstream's would need root + the Mozilla install layout).
  Updates flow through build-firefox.sh bumps only. Upstream ESR 140
  point-releases land in Alma 8 AppStream within days.

### firefox: universal-host TLS fix -- trust module stays system-provided

First failure layer (fixed earlier this batch): `libxul.so` NEEDEDs the
EL8 sonames `libffi.so.6` + `libjpeg.so.62`; newer hosts ship `.so.8`
only -> `XPCOMGlueLoad`. Both now bundle co-located (`RPATH=$ORIGIN`)
via the NSS staging loop, and the wrapper keeps its loader path
strictly inside the bundle (`$libdir` only; a `$prefix/lib64` prepend
was tried and REVERTED -- it shadowed the host GTK3/dbus stack on newer
hosts; rule: bundle only sonames the host can't supply, host copy wins
for everything else). See AGENTS.md firefox entry +
build/ADDING_BINARIES.md firefox section for the full rationale.

Then gmail still showed `SEC_ERROR_UNKNOWN_ISSUER` on every HTTPS site,
in fresh profiles, on the CachyOS host (HTTP loaded fine; TLS never
trusted anything).

Root cause: the bundle shipped EL8's `libnssckbi.so` +
`libnsssysinit.so`, whose ckbi is an **alternatives symlink to
p11-kit's trust proxy** -- it reads the system trust store from
hardcoded EL8 paths (`/etc/pki/ca-trust/...`), nonexistent on Arch- 
family hosts -> zero roots. Works on EL8, dead TLS everywhere else;
evaded the smoke because `--version`/`data:` screenshots never verify a
cert. (The EL8 build-script copy follows the symlink via `readlink -f`,
so the bundle silently received the proxy, not classic roots.)

Fix:

- `build/build-firefox.sh`: `libnssckbi.so` + `libnsssysinit.so`
  REMOVED from the NSS staging list + a build-time guard that fails the
  build if either reappears in the stage. Without a bundled ckbi, NSS
  dlopens the HOST trust module -- classic roots or the host's own
  working proxy. This matches upstream: Mozilla's official Linux
  tarballs ship no ckbi either.
- Payload repacked (v4): trust modules deleted from the tar, ffi/jpeg
  co-location kept; re-chunked; sizes/content manifests regenerated.
- Verified on the CachyOS host: example.com + gmail.com load with the
  lock icon in a fresh profile.

Diagnosis journey worth remembering (three separate build-box-masking
layers had to fall): (1) libffi.so.6 soname gap -> XPCOMGlueLoad;
(2) `$prefix/lib64` wrapper prepend -> host stack shadowing (firefox
"reached outside its install space"); (3) EL8 p11-kit trust proxy ->
SEC_ERROR_UNKNOWN_ISSUER. Universal-host rule that fell out: keep the
loader path inside the bundle, bundle ONLY sonames the host cannot
supply, and never ship a distro-specific trust proxy.

### bashrc: keep functions referenced by inherited PS0 across the clean-slate

`/etc/profile.d/80-systemd-osc-context.sh` (systemd OSC-3008, shipped via
tmpfiles on Arch-family) sets `PS0='$(__systemd_osc_context_ps0)'` and
defines that function. The clean-slate `unset -f $(declare -F)` in
`envs/bash/bashrc` deleted the function but left PS0, so bash expanded a
dangling `$(...)` before EVERY command:
`-bash: __systemd_osc_context_ps0: command not found`.

Fix: the clean-slate keep-list now also harvests identifiers from
inherited PS0 and preserves any that name a currently-defined function
(alongside `LOADOUT_CFG_PRESERVE_FUNCTIONS`). No hardcoded systemd name
list; any profile.d hook using the same pattern survives. Verified via
real-PTY login shell + `exec bash` on a live host. Box-side, the same
fix was applied to the installed copy at `~/.config/bash/bashrc`
(installed copies are real files, not symlinks into the repo).

## 2026-08-28 batch: env-tmux pane factory (released in v2026.08.28)

| area | what |
|---|---|
| env-tmux | `Prefix+o` now opens a new seven-pane work window: split, re-tile after each split so tmux does not preserve an early skewed split tree, then run `tmux-3col-layout.sh` to center the active pane full-height with balanced side columns. README documents `Prefix+6` as the manual 3-column re-layout key and `Prefix+o` as the seven-pane factory. |

Gates: isolated tmux smoke installed `env-tmux` into a temp `--dest-dir`,
sourced the deployed config, executed the `Prefix+o` command sequence, and
verified the new window had seven panes with the custom 3-column layout.

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

## Evergreen notes (former "start here" section, still all true)

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

* **Run Tier 2 + Tier 3 after this batch** (`./tests/run-all` full, then
  `--container`). Tier 1 is green except 4 PRE-EXISTING WIP failures (below);
  nothing in the 2026-08-30 batch added failures. Tier 2/3 were explicitly
  deferred by the owner mid-batch.
* **Pre-existing WIP T1 failures (all owner's in-flight work, not this batch):**
  `registry-integrity` (farm-versions still lists nedit-ng/nvim-qt/flameshot;
  `envs/nvim/vendor/plugins` dir missing), `env-shell-parity`
  (LOADOUT_CFG_ENABLE_SSH_AGENT unmapped in tcsh -- the ssh-agent bashrc WIP),
  `shell-typeahead` (zsh, envs/zsh/global/zshrc WIP), `check-installer`
  (doctor: nvim-plugin-stash release asset absent on this box -- expected
  off-build-box, fetch with tools/fetch-stash).
* **Smoke-gap worth closing next:** tests/prebuilt-binaries probes firefox
  `--version` only -- that is why THREE universal-host regressions
  (libffi soname, libjpeg soname, trust proxy) all shipped green. Add an
  HTTPS fetch/smoke to the firefox probe on the dest-dir shape.
  **PARTIAL FIX 2026-09-13:** the codec probe (below) now runs the bundled
  FFmpeg through a real decode on every smoke; the HTTPS fetch check is
  still open.
* **firefox bytes not build-box-canonical:** the 140.14.0 tar was
  strip/bzip2'd on CachyOS. Content is identical (RPATH'd ELFs skip strip)
  but a future EL8 rebuild will churn hashes; expected, harmless.
* **`bin/rsync.bz2`** was left at its churned-but-stripped state after a
  strip-all mishap this session (biome.bz2 was restored to HEAD). Re-verify
  both against the in-flight rsync/biome WIP before committing.
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
   online box, `./tools/fetch-stash --from-file <stash> --sums sha256sums.txt`. The
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
