# envs XDG migration and dead-code trim — design

Date: 2026-10-08
Status: approved 2026-10-08 (operator: prefer-vim = yes, drop plain csh = yes,
XDG hook sibling = yes); W1-W2 landed and gated, W3-W5 pending
Evidence base: 2026-10-08 audit session (live probes + code references inline)
Scope: `envs/*` configuration packages, their installer handlers, and the registry
fields that drive them. Out of scope: payload tool behavior, the nvim plugin
stash, uninstall (separate spec), and pruning vendored *content* (completions,
vim plugins, tmux plugins) — only unshipped/dead trees are in scope here.
Release class: **C** (installer + registry + `envs/` layout) per `docs/RELEASE.md` §0.

Execution: workstreams **W1–W5 are independent** and each lands as its own
commit with tests + docs in the same change. W6 rides whichever commit is last
before a release. This document is the checklist of record; tick steps here as
they land (the file is committed, so progress is visible in git).

---

## 1. Problem (audit findings)

### F1 — Vim plugins and the shipped markdown ftplugin are dead (real defect)

Live evidence (`/home/mylesp`, bundled vim 9.2.1169 via the loadout shim):

- `~/.vim` is **absent**; `~/.vimrc -> .config/vim/vimrc` exists and **is**
  sourced (pty probe: `$MYVIMRC=/home/mylesp/.vimrc`).
- Because `~/.vimrc` exists, vim stays in legacy mode: `&packpath` is
  `~/.vim, <prefix>/share/vim/vimfiles, <prefix>/share/vim/vim92,
  <prefix>/share/vim/vimfiles/after, ~/.vim/after` — `~/.config/vim` is **not**
  on it. `globpath(&packpath, 'pack/*/start/*')` finds **nothing**, while the
  vendored plugins live at `~/.config/vim/vim/pack/vendor/{start,opt}`.
- `envs/vim/vim/after/ftplugin/markdown.vim` is tracked but never installed
  (`find ~/.config/vim` has no `after/`), so the markdown ftplugin is dead too.

Mechanism: vim's own docs (`$VIMRUNTIME/doc/starting.txt`, `*xdg-vimrc*`) say
`$XDG_CONFIG_HOME/vim/vimrc` is read **only if no `$HOME/.vimrc` and no
`$HOME/.vim/vimrc` exist**, and when it is used, `runtimepath`/`packpath`
switch to the XDG tree. `_install_env_vim` explicitly
`remove_if_exists(~/.vim)` and never recreates it; the only declaration of
that link is `env-vim`'s `extra_links` entry — and `extra_links` is processed
only by `_install_env_generic`, which never runs for a package listed in
`ENV_HANDLERS` (F2). So the link has been absent on install for as long as the
dedicated handler has existed.

Additional constraint: `env-vim` declares no `prefer`, and the PATH contract
appends `<prefix>/bin` — so on EL8 the **system vim 8.0** wins. Vim 8.0
supports neither the XDG vimrc nor the XDG packpath, so a naive XDG migration
would remove the config from system-vim users entirely.

### F2 — `extra_links` is dead registry data (and is what hid F1)

- Declared by: `env-bash` (4 entries), `env-vim` (2), `env-zsh` (3),
  `env-starship` (1).
- Consumed by: `_install_env_generic` only (`for link in
  pkg_entry.get("extra_links", [])`). The generic path runs only for env
  packages absent from `ENV_HANDLERS`; those are `env-btop` and `env-wezterm`,
  and neither declares `extra_links`.
- The four declarers all have dedicated handlers that either hardcode the
  links (`_install_env_bash`/`_install_env_zsh`/`_install_env_vim`) or install
  the file directly (`_install_env_starship` copies the schema itself).
- Other references: `_validate_registry_gates`' field list, and
  `gen-installed-sizes` resolving non-`~/` targets (the starship schema is the
  only such entry).
- Net: every declared link is inert at install time. `env-vim`'s `.vim` entry
  is the proof (F1).

### F3 — Dead shell entrypoints

`BASH_ENTRYPOINTS = (".bashrc", ".bash_profile", ".bash_login", ".profile")`.

- bash reads the first existing of `~/.bash_profile` → `~/.bash_login` →
  `~/.profile`; `.bash_profile` is always created, so **`.bash_login` and
  `.profile` are never read by bash**.
- tcsh reads `.tcshrc`/`.cshrc`; zsh reads `.zshenv`/`.zprofile`/`.zshrc`/
  `.zlogin`/`.zlogout`. Neither reads `.profile`.
- The `.profile` target is `envs/bash/bashrc`, whose header states "bashrc
  bash-only syntax" — a POSIX login shell sourcing it would break, so the
  link never served its only possible purpose.
- `.cshrc` is redundant for tcsh (`.tcshrc` wins); only plain `csh` reads it,
  and `csh` is not a supported shell here (the package is tcsh).

Consumers to touch: `BASH_ENTRYPOINTS` → `restore_targets`, `install_bash`'s
link loop, the backup list, `_install_env_bash`'s prune loop;
`tests/install-linux-tmp-home` asserts both; `tests/install-env-tcsh` asserts
`.cshrc`; docs (INSTALLATION table, AGENTS entrypoint list + symlink map,
`envs/tcsh/README.md`, `envs/tcsh/tcshrc` comment, copilot instructions).

### F4 — `supports_layers` is cosmetic and drifted

- Consumers: a comment in `_install_env_zsh` ("only ever read by `loadout
  info`"), registry validation, and one test block
  (`tests/install-env-tmux-nvim-layers` asserts `env-tmux`/`env-nvim` ==
  `["global","user"]`).
- Values are inconsistent: `env-bash` `["corp","site","project","user"]`
  (missing `global`/`team`), `env-zsh` six layers, `env-nvim`/`env-tmux`
  `["global","user"]`, `env-tcsh` none.

### F5 — `tmux-yank` is an undocumented opt-in catalog entry

`envs/tmux/vendor/plugins/tmux-yank` (136 KB) ships, but its `@plugin` line is
commented out in the managed `tmux-global.conf`. The vendored copy is what
makes an offline opt-in possible (the nvim catalog precedent), so this is a
documentation gap, not dead weight.

### F6 — Docs describe the pre-fix layout

`docs/INSTALLATION.md` still documents `~/.vim/ <- envs/vim/vim/`; AGENTS'
symlink map documents `.vimrc`/`.vim`; the copilot instructions list
`extra_links`/`supports_layers` among the registry fields.

---

## 2. Principles

- **P1 — Prefer tool-native XDG paths.** A compatibility shim is legitimate
  only when a *named* consumer needs it; record that consumer in a comment
  next to the shim, or delete the shim. (Precedents: the retired `~/.tmux` +
  `~/.tmux.conf` redirects; the retained `.tcshrc` for tcsh <7 and the
  `prefer` shim for the bundled tmux 3.7c.)
- **P2 — Dead data is a bug class.** A registry field the installer never
  executes is worse than absent: it documents behavior that does not happen
  and it hid F1. Delete inert fields; do not keep them "for later".
- **P3 — Every removal ships its tests and docs in the same change.** T1 plus
  the focused T2 tests locally; class C requires the full
  `tests/run-all --container` before the next release.
- **P4 — Migrations keep a one-release safety net.** Removed paths stay in the
  backup list for one release, the installer prunes the legacy tree, and the
  HANDOFF records the trade.

---

## 3. Decisions

### D1 — Vim goes XDG-native (no symlink restore)

Rejected alternative: restore the `~/.vim` symlink (one line, works on vim
8.0 and 9.2). It keeps the legacy layout and the vimrc-in-legacy-mode
behavior forever; it is the opposite of the stated direction.

Chosen design:

- Source layout: `envs/vim/vim/pack` → `envs/vim/pack`, `envs/vim/vim/after`
  → `envs/vim/after` (drop the extra `vim` level, mirroring the retired
  `~/.tmux`/`tmux/tmux` and `~/.config/tmux/tmux`→`plugins` cleanups).
  `envs/vim/vimrc` stays.
- Installed layout: `~/.config/vim/vimrc`, `~/.config/vim/pack/vendor/{start,opt}`,
  `~/.config/vim/after/ftplugin/markdown.vim`.
- `~/.vimrc` and `~/.vim` are no longer created; both stay in the backup list
  (P4) and the installer prunes any existing copies.
- `env-vim` gains `prefer: ["vim"]` so the bundled 9.2 is the one that runs
  (tmux precedent: `env-tmux` declares `prefer: ["tmux"]`). Trade, recorded:
  `/usr/bin/vim` (EL8 8.0) no longer sees the loadout config or plugins; vim
  8.0 cannot read XDG config, so this is inherent to the migration.
- `~/.vimrc_hook.bottom` keeps being sourced, and
  `~/.config/vim/vimrc_hook.bottom` is read first when present (the legacy path
  is read otherwise, so existing hooks keep working without double-sourcing;
  operator decision 2026-10-08).
- `after/` is user-adjacent (users add their own ftplugins there), so the
  installer ships the tracked files **per file** — extend the tuple when a new
  shipped `after/` file is added (the env-helix "silently never installed"
  lesson). Do not `sync_dir(delete=True)` into `after/`.

### D2 — Delete the `extra_links` mechanism

Remove the field from `env-bash`/`env-vim`/`env-zsh`/`env-starship`; delete the
link loop from `_install_env_generic` (keep `source`/`install_to`); drop the
field from the validation tuple and from docs. The link behavior moves to the
handlers that already implement it.

Sizing consequence: the starship `config-schema.json` is currently counted in
`installed-sizes.json` only via `extra_links`. Fix by pointing `env-starship`'s
`source` at the directory `envs/starship/` (the dedicated handler already
installs both files), then regenerate the sizes map. Verify with
`build/gen-installed-sizes --check` that the schema is still counted.

### D3 — Trim the shell entrypoints

- `BASH_ENTRYPOINTS = (".bashrc", ".bash_profile")`.
- Drop `.cshrc` from the tcsh entrypoint loop (tcsh prefers `.tcshrc`; plain
  csh is unsupported).
- Existing installs: prune the removed links explicitly on install (the
  handlers' remove-then-create loops no longer cover them), and keep them in
  the backup list for one release (P4).
- Do not re-add `.profile` for a POSIX login shell unless a POSIX-valid target
  exists; linking a bash-only file there was never functional.

### D4 — Delete `supports_layers`

Remove the field from every `kind: env` entry, the validation tuple, the
comment in `_install_env_zsh`, and the test block whose only purpose is to
assert the field. The dispatcher-order behavior the test block sat next to is
already asserted in the same test by sourcing the config files; add a
comment pointing at that assertion.

### D5 — Keep `tmux-yank` as a documented opt-in catalog entry

Document in `docs/TMUX.md` (and a comment next to the commented `@plugin`
line) that enabling it is a user-layer action
(`~/.config/tmux/tmux-user.conf`) and that the vendored copy makes it work
offline. Note that `build/update tmux-plugins` discovers declarations in
`tmux-global.conf` only, so a user-layer plugin is not refreshed by it.

---

## 4. Workstreams

Each workstream is a candidate for its own commit. Steps are checkbox items;
tick them in this file as they land.

### W1 — Vim XDG migration (D1) — LANDED

**Files:** `envs/vim/` (layout move), `loadout_main.py`
(`_install_env_vim`), `payload/packages.json` (`env-vim`, `vim`),
`tests/install-env-vim-xdg` (new), `tests/install-linux-tmp-home`, docs.

- [x] `git mv envs/vim/vim/pack envs/vim/pack` and
      `git mv envs/vim/vim/after envs/vim/after`; the empty `envs/vim/vim/`
      removed.
- [x] `_install_env_vim`: prunes `~/.vimrc`, `~/.vim`, and the legacy nested
      `~/.config/vim/vim`; installs `vimrc` to `~/.config/vim/vimrc`; syncs
      `envs/vim/pack/vendor/{start,opt}` (`delete=True`); installs each tracked
      `after/` file individually (tuple `after/ftplugin/markdown.vim`).
- [x] Registry `env-vim`: `prefer: ["vim"]` added; `extra_links` dropped
      (the field itself is W2's).
- [x] New T2 test `tests/install-env-vim-xdg`, wired into `tests/run-all` T2
      **and** the Tier 3 smoke entrypoint. Installs `vim` + `env-vim` into a
      temp HOME, then probes the bundled vim **through a PTY**: the first draft
      used `vim -es`, which does NOT read the vimrc, so it passed while proving
      nothing. Asserts `$MYVIMRC`, XDG-first `&packpath`, the shipped plugins
      and `after/ftplugin/markdown.vim`, and the absence of the legacy paths.
      Control: a stray `~/.vimrc` flips the same probe back to legacy mode, so
      the assertions are proven able to fail.
- [x] `tests/install-linux-tmp-home`: asserts the XDG vimrc/pack/after files
      exist and `~/.vimrc`/`~/.vim` do not.
- [x] Docs: INSTALLATION table, AGENTS repo map + symlink map + test list,
      copilot plugin paths, and the `envs/vim/vimrc` XDG comment with the hook
      sibling.
- [x] **Found by the test: `install vim` alone shipped a broken binary.**
      `vim.bin` NEEDs `libselinux.so.1` — a payload stem claimed by `gui_libs`
      only, so a vim-only selection skipped it (dead on hosts without a system
      libselinux, e.g. Arch/CachyOS; masked on EL8 BaseOS) — plus a spurious
      `libpixman-1.so.0` NEEDED (`vim --version` reports `-X11`, so it is a
      link-time artifact the loader still requires). Both are now declared in
      the `vim` entry's `libs`. Build-hygiene follow-up: a vim rebuild could
      drop the pixman link and the declaration.
- [x] Gates: `install-env-vim-xdg` + `install-linux-tmp-home` + T1 green; full
      `tests/run-all --container` green, with the new test also running in the
      Tier 3 smoke (`install-env-vim-xdg: OK` inside the container).

**Acceptance:** met — the new test passes on the dev host and inside the Tier 3
container; a fresh install creates no `~/.vimrc`/`~/.vim`, and the bundled vim
loads its vimrc, packpath and after/ftplugin from `~/.config/vim`.

### W2 — Remove `extra_links` (D2) — LANDED

**Files:** `payload/packages.json`, `loadout_main.py`, `build/gen-installed-sizes`,
docs.

- [x] Delete the `extra_links` blocks from `env-bash`, `env-vim`, `env-zsh`,
      `env-starship` (`env-vim`'s was already dropped in W1; the `_schema`
      description went with them).
- [x] Delete the link loop from `_install_env_generic` and its docstring
      mention.
- [x] Remove `extra_links` from the field lists (`cmd_describe`, `_schema`,
      copilot docs).
- [x] Remove the `extra_links` branch from the installed-size accounting;
      change `env-starship`'s `source` to `envs/starship/` and regenerate
      `payload/installed-sizes.json` + `.content-manifest`; confirmed the
      schema file is still counted (`_artifact_paths(env-starship)` =
      toml + schema).
- [x] Docs: AGENTS sizing note, copilot registry-field list, any
      INSTALLATION mention (none existed).

**Acceptance:** `rg extra_links` finds only HANDOFF history; T1
(`gen-installed-sizes --check`, `registry-integrity`, `check-installer`) green.

### W3 — Trim shell entrypoints (D3) — LANDED

**Files:** `loadout_main.py`, `payload/packages.json` (if env-bash's
`extra_links` interacts — W2 handles the field), tests, docs.

- [x] `BASH_ENTRYPOINTS` → `(".bashrc", ".bash_profile")` (+ explicit
      `BASH_ENTRYPOINTS_RETIRED` / `TCSH_ENTRYPOINTS(_RETIRED)` constants).
- [x] `_install_env_bash`: prune `.bash_login` and `.profile` if present
      (legacy sweep), keep the backup list entries for one release.
- [x] `_install_env_tcsh`: loop becomes `(".tcshrc",)`; prune `.cshrc`.
      `.cshrc` stays in the backup list for one release — and the tcsh
      entrypoints had never been in the backup list at all; now they are.
- [x] Tests: `tests/install-linux-tmp-home` (assert the two are absent, the
      two kept ones are present), `tests/install-env-tcsh` (assert `.cshrc`
      absent, `.tcshrc` present and functional); both pre-seed the legacy
      links so the prune itself is asserted.
- [x] Docs: INSTALLATION per-user table + retirement note, AGENTS entrypoint
      list + symlink map, `.github/copilot-instructions.md` layer sections,
      `envs/bash/README.md` file map, `envs/tcsh/README.md`,
      `envs/tcsh/tcshrc` header comment.

**Acceptance:** a temp-HOME install creates exactly `.bashrc`/`.bash_profile`
for bash and `.tcshrc` for tcsh; reinstall over a legacy layout prunes the
removed links.

**Correction (2026-10-08, entry 10):** `.profile` is NOT pruned. It was restored
with a POSIX-valid target (`envs/bash/profile`) after finding that RHEL's X session
wrapper (`/etc/X11/xinit/xinitrc-common`, sourced by the `#!/bin/bash` `Xsession`)
reads `~/.profile` -- the old `~/.profile -> bashrc` link worked on EL8 and is the
X-session env hook, exporting PATH/TERMINFO_DIRS into a startx/X11 session. Only
`.bash_login` (and tcsh's `.cshrc`) stay retired; D3's carve-out ("do not re-add
`.profile` ... unless a POSIX-valid target exists") is what this implements.

### W4 — Delete `supports_layers` (D4) — LANDED

**Files:** `payload/packages.json`, `loadout_main.py`,
`tests/install-env-tmux-nvim-layers`, docs.

- [x] Remove the field from every `kind: env` entry (+ its `_schema` entry).
- [x] Remove it from the validation tuple (`cmd_describe` field list) and from
      the `_install_env_zsh` comment.
- [x] Replace the test block's field assertion with a comment referencing the
      existing dispatcher-order assertions (tmux dispatcher order + nvim layer
      layout).
- [x] Docs: copilot field list, AGENTS "supports_layers is cosmetic" note.

**Acceptance:** `rg supports_layers` empty; `loadout info env-tmux` output
unchanged except the missing field; T1 green.

### W5 — Document the `tmux-yank` opt-in (D5) — LANDED

**Files:** `docs/TMUX.md`, `envs/tmux/tmux-global.conf` (comment).

- [x] Document the opt-in in the user layer (`envs/tmux/tmux-user.conf` block +
      `docs/TMUX.md` section) and the offline rationale (the vendored copy makes
      TPM skip the clone; needs xclip/xsel or wl-copy).
- [x] Note the `build/update tmux-plugins` scope (global layer only) in both the
      `tmux-global.conf` comment and `docs/TMUX.md`; AGENTS carries the one-liner.

**Acceptance:** docs only; no code change.

### W6 — Docs sync + release (all)

- [ ] Update HANDOFF with one dated entry per landed workstream.
- [ ] Full `tests/run-all --container` (class C) before the next release.
- [ ] Follow `docs/RELEASE.md` from §0.

---

## 5. Acceptance criteria (overall)

- No registry field that the installer does not execute.
- Every retained compatibility shim has a named consumer in a comment.
- A fresh install creates no `~/.vimrc`, `~/.vim`, `~/.bash_login`,
  `~/.profile`, or `~/.cshrc`, and a reinstall prunes them from an old tree.
- Vim's bundled plugins and ftplugins load from the XDG tree; a fresh
  `vim` reports `$MYVIMRC` under `~/.config/vim/`.
- T1 green after each workstream; T2 focused tests for the changed env;
  Tier 3 green before the release that ships them.

## 6. Risks and rollbacks

| risk | mitigation / rollback |
|---|---|
| EL8 system vim 8.0 loses config (XDG-only) | `prefer: ["vim"]` shim; trade recorded; rollback = restore the two symlinks and drop `prefer` |
| users' legacy `~/.vim` plugin content | backup list keeps it one release; `--no-backup` users accept loss (documented) |
| `.profile` needed by some login flow | it never worked (bash-only target); if a real need appears, ship a POSIX-valid target rather than the bashrc link |
| starship schema under-counted in sizes | W2 explicitly verifies `installed-sizes --check` after the `source` change |
| test cache churn from `tests/` edits | expected; container sidecar is keyed on `tests/` (`FP_ROOTS_CONTAINER`) |

## 7. Decisions closed (operator, 2026-10-08)

1. Plain `csh` support is NOT required — D3 drops `.cshrc`.
2. `prefer: ["vim"]` approved — the bundled vim shadows system vim on PATH,
   as the tmux shim already does.
3. The XDG hook sibling is approved — D1 reads
   `~/.config/vim/vimrc_hook.bottom` first, the legacy path second.
