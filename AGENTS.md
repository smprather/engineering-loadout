# Agent Notes

Scope: entire repository.

## Commit Rule

Before every commit, sync every project Markdown doc that helps agents or users
cold-start. Do this before staging the commit, and do not commit known doc drift.
At minimum check and update:

- `README.md` for user-facing behavior and install options.
- `CLAUDE.md` for detailed repository architecture and operational notes.
- `AGENTS.md` for current agent rules, repo-specific pitfalls, and lessons learned.
- `.github/copilot-instructions.md` for GitHub/Copilot agent cold-start notes.
- Any active plan or handoff Markdown when the area it describes changes.

Use `rg` to search these docs for renamed commands, retired flags, new
environment variables, and changed install behavior. The docs must match the
code being committed.

## Cold Start

This repository is engineering-loadout: an offline-first, no-root package manager for Linux/Windows compute environments. `./loadout` is a POSIX-sh shim that self-bootstraps the bundled portable Python 3.14 (no system Python required) and execs `loadout_main.py` under it. Driven by `pre_built/packages.json` (`schema_version: 3`). Prefer changes that preserve RedHat/Alma/RHEL 7/8/9, Suse, WSL, Windows PowerShell, and locked-down corporate machines.

Use `rg` first. Use `python3 -m py_compile loadout` and `bash -n bash/global/bashrc` after installer/shell edits. For Neovim config checks in this sandbox, use temporary writable state/cache dirs:

```bash
XDG_CACHE_HOME=/tmp/codex-nvim-cache XDG_STATE_HOME=/tmp/codex-nvim-state nvim --headless +qa
```

## Lessons Learned

- Do not use `xset +fp ~/.local/share/fonts` from shell startup. Even with valid `fonts.dir`, X may reject user-home paths such as `/home/mylesp` when the home directory is `700`. Use fontconfig (`fc-cache`) for modern Linux apps and WSLg.
- Vendored fonts belong in `~/.local/share/fonts`. Generate `fonts.scale`/`fonts.dir` when `mkfontscale`/`mkfontdir` exist, but rely on `fc-cache` for actual desktop app discovery.
- Font archives live under top-level `fonts/`. Archives over normal GitHub size limits should be split as `fonts/Name.zip.part-000`, `Name.zip.part-001`, etc. The installer rejoins split archives under `/tmp` before unzipping. Use 45 MiB chunks to stay below GitHub's 50 MB warning threshold.
- Before each install area writes files, the installer verifies that the target directory is writable. If an area is not writable, it refuses that area with a warning, continues later areas when possible, and ends with an install results table using `yes`, `no`, and `skip`.
- Pre-built Linux binaries live under `pre_built/<platform>/`, for example `pre_built/el8.x86_64.glibc2p28/`. `RPATH=$ORIGIN/../lib64:$ORIGIN/../lib` is pre-baked into each binary in the repo before bzip2 compression — the installer is pure decompress + chmod, no runtime patchelf step. Installer runs `ldd` on installed binaries and warns about missing `.so` dependencies. If a running binary cannot be replaced, installer continues and prints a retry notice.
- **Binary bundling order is critical: strip → patchelf → bzip2.** Never strip after patchelf. patchelf reorganizes ELF segments to accommodate the new RPATH string; stripping after patchelf moves `.dynstr` outside a `PT_LOAD` segment and corrupts the binary (symptom: segfault or "undefined symbol" at runtime). `strip_all_elf_binaries` detects patchelf'd payloads via `readelf -d` RPATH check and skips re-stripping them.
- **Go binaries must use compile-time strip flags, not post-build strip.** Build with `go build -ldflags="-w -s"`. Running `strip --strip-all` on a Go binary post-build removes GC maps and stack unwind metadata, causing SIGSEGV. `-w` drops DWARF, `-s` drops the symbol table — identical effect to strip but safe because Go's linker handles the removal correctly.
- **`pre_built/build_scripts/test-prebuilt-binaries` is the release gate.** Run `./release --dry-run` before tagging. The script does a full `./loadout install @engineering-loadout --dest-dir /tmp/...`, probes each binary for loader failures and signal crashes, checks editor runtime sentinels, and runs installed `nvim` headless against the installed runtime. Portable Python intentionally keeps generic `python3`/`pip3` links in `~/.local/bin` so `python3` on PATH resolves to 3.14; the only hard py3.6 holdout is Meld's `bin/meld` launcher, which pins `/usr/bin/python3.6` for PyGObject compatibility.
- **Never bundle glibc components** (`libc.so.6`, `libm.so.6`, `libpthread.so.0`, `libdl.so.2`, `librt.so.1`). They must match the system `ld-linux.so.2` exactly. Bundling them causes `undefined symbol: ..., version GLIBC_PRIVATE` crashes. These are always present on EL8 systems.
- Use `./strip_all_elf_binaries` (Python 3.14) after adding vendored binaries, libs, parser grammars, or tar archives. It walks the repo outside `.git`, strips raw ELF files in place, strips ELF payloads inside standalone `.bz2`, and rewrites tar archives as `.tar.bz2`. Tar archives are skipped on later runs when their size and modification time still match the strip manifest.
- `./update tldr-data` writes `tldr/tldr-pages.tar.bz2`; installer still accepts legacy `.tar.gz`, replaces any existing tealdeer cache unless `--skip tldr-data` is passed (or `tldr-data` is not in the selected set), and strip normalization will convert tar archives to bzip2.
- Platform runtime archives live under `pre_built/<platform>/runtime/`. `helix.tar.bz2` installs to `~/.config/helix/runtime` with `runtime/tutor` as sentinel. `vim92.tar.bz2` installs to `~/.local/share/vim/vim92` with `filetype.vim` as sentinel. `nvim.tar.bz2` installs to `~/.local/share/nvim/runtime` with `filetype.lua` as sentinel.
- Runtime launchers must derive install prefix from their installed path, not `$HOME`. `--dest-dir` installs can be run with a fake `HOME`, so wrappers like Vim/GVim and Meld must find bundled runtime/data under the staged root.
- Tmux double-click word selection is controlled by `tmux/tmux-word-separators`, because tmux `word-separators` is a literal character list and cannot express a Unicode emoji class. Keep the helper installed with `tmux.conf` so Starship prompt emoji such as the read-only lock are treated as separators.
- WSL Windows Terminal does not read WSL fontconfig. Fonts must also be installed on the Windows side for Windows Terminal UI selection.
- Do not backup font files during pre-install backups; vendored Nerd Font archives are large. Backup uses `rsync` with font-extension excludes.
- `Snacks.nvim` provides the no-argument Neovim dashboard. Its dashboard buffer has filetype `snacks_dashboard`.
- `mini.trailspace` highlights trailing whitespace via window-local matches. Disabling only by filetype can race with dashboard rendering. For Snacks dashboard, set `vim.b.minitrailspace_disable = true`, `list = false`, and delete existing `MiniTrailspace` matches on dashboard open/update.
- Fresh Neovim config must start on locked-down machines. If `lazy.nvim` is missing and `git` cannot clone it, `nvim/init.lua` disables the plugin layer cleanly (`vim.g.loadout_plugins_enabled = false`) instead of erroring.
- Tree-sitter offline support targets Neovim v0.12+ only. Vendored `nvim-treesitter` and `treesitter-parser-registry` live under `treesitter/vendor/`; prebuilt parsers, parser-info, queries, and registry cache live under `treesitter/prebuilt/<platform>/`, where platform is `$(uname -s lower)-$(uname -m)-<glibc|musl>`. Build all supported parsers with `./treesitter/build_parsers`; it stores parsers as `parser/*.so.bz2`. Installer copies vendor plugins to `~/.local/share/nvim/loadout/vendor/`, decompresses matching parser artifacts to installed `parser/*.so`, and copies metadata directories to `~/.local/share/nvim/tree-sitter-parsers/`.
- `tests/install_linux_tmp_home` simulates a fresh Linux user by running the real installer with a temp `HOME`, temp XDG cache/state dirs, test `--post-install-hook` scripts, and `--skip @fonts-all`, then smoke-tests offline Tree-sitter with headless Neovim.
- Project Codex config lives in `.codex/config.toml`; this project sets `approval_policy = "never"` and default caveman full style through `developer_instructions`.
- Corp/site/user add-ons can be invoked explicitly with `./loadout install … --post-install-hook <script>`. Multiple hooks are allowed and run in argument order. Hooks are executed directly, so each must be executable and provide its own shebang or binary format. Hooks run after global install steps, before automatic layer `install.sh` scripts, with `LOADOUT_*` environment variables: `LOADOUT_REPO`, `LOADOUT_HOME`, `LOADOUT_BACKUP_DIR`, `LOADOUT_DEST_DIR`, `LOADOUT_NO_BACKUP`. Skip fonts or the tldr cache via `--skip @fonts-all` / `--skip tldr-data` selectors.
- Linux installer manages Starship at `~/.config/starship/starship.toml` from `starship/starship.linux.toml` and `starship/config-schema.json`; Windows uses `starship/starship.windows.toml`.
- Linux installer entry point is `./loadout` (POSIX-sh shim) which bootstraps Python 3.14 from the bundled portable-python archive and execs `loadout_main.py` (Python 3.14+). Resolves the repo from the script path; must work when invoked from outside the repo root. `tests/install_linux_tmp_home` runs it from `/tmp` to catch regressions.
- Bash startup converges `~/.bashrc`, `~/.bash_profile`, `~/.bash_login`, and `~/.profile` onto `~/.config/bash/bashrc`. Keep the non-exported `LOADOUT_BASHRC_SOURCED` guard so accidental double-sourcing in one shell returns immediately without blocking exec into a preferred bash.
- Package registry (`pre_built/packages.json`, `schema_version: 3`): every installable thing has a named entry with `kind` (`bin`/`lib-bundle`/`runtime`/`typelib`/`python-base`/`python-tool`/`env`/`font`/`data`/`group`), `platforms: [...]`, and per-kind artifact fields. Packages can declare hard `depends` and soft `recommends`. Groups (keys starting with `@`) bundle related packages and expand recursively with cycle detection. Synthetic groups: `@shared` (every non-env package) and `@envs` (every env config bundle); `all` also resolves to every non-group package. There is no "default install" — users always name packages or groups explicitly (dnf/apt style). Resolver: `expand_groups` → `walk_depends` (raise on skip-set conflict unless `--no-deps`/`--force`) → `walk_recommends` (silent drop) → `filter_by_platform`. CLI verbs: `install`, `reinstall`, `upgrade`/`update`, `list [--groups|--tag T]`, `search PATTERN`, `info`/`describe`, `resolve`, `doctor`, `snapshot {create|restore|list}`, `clean`; selection via positional PKG args plus `--skip` / `--no-deps` / `--force` / `--dry-run`. Bare `install` (no positional args) errors with non-zero exit.
