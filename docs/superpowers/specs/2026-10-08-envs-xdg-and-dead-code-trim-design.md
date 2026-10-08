# envs XDG migration and dead-code trim — design

Date: 2026-10-08
Status: draft for review
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
- `~/.vimrc_hook.bottom` keeps being sourced (users' existing hooks survive);
  do not add an XDG sibling unless someone asks.
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

### W1 — Vim XDG migration (D1)

**Files:** `envs/vim/` (layout move), `loadout_main.py`
(`_install_env_vim`), `payload/packages.json` (`env-vim`), new
`tests/install-env-vim-xdg`, `tests/install-linux-tmp-home`, docs
(INSTALLATION, AGENTS, copilot, `envs/vim` comments).

- [ ] `git mv envs/vim/vim/pack envs/vim/pack` and
      `git mv envs/vim/vim/after envs/vim/after`; delete the now-empty
      `envs/vim/vim/`.
- [ ] `_install_env_vim`: prune `~/.vimrc`, `~/.vim`, and the legacy nested
      `~/.config/vim/vim`; install `vimrc` to `~/.config/vim/vimrc`; sync
      `envs/vim/pack/vendor/{start,opt}` to `~/.config/vim/pack/vendor/...`
      (`delete=True`); install each tracked `after/` file individually.
- [ ] Registry `env-vim`: add `prefer: ["vim"]`; drop `extra_links`
      (also handled by W2).
- [ ] New T2 test `tests/install-env-vim-xdg` (wire into `tests/run-all`
      T2): install `env-vim` into a temp HOME and run the **bundled** vim
      (absolute `<prefix>/bin/vim` or restricted-PATH) with `-es`:
      assert `$MYVIMRC == <home>/.config/vim/vimrc`,
      `~/.config/vim` is in `&packpath`,
      `globpath(&packpath,'pack/*/start/*')` lists `nerdtree`, and
      `~/.config/vim/after/ftplugin/markdown.vim` exists.
      Negative controls: `~/.vimrc` and `~/.vim` are absent; the legacy
      `~/.config/vim/vim` tree is pruned.
- [ ] `tests/install-linux-tmp-home`: replace the `.vimrc` symlink assertion
      with "XDG vimrc exists, `~/.vimrc`/`~/.vim` absent".
- [ ] Docs: INSTALLATION install table (`~/.config/vim/{vimrc,pack,after}`),
      AGENTS symlink map + Vim mentions, copilot, and a comment in
      `envs/vim/vimrc` about the XDG mode + `vimrc_hook.bottom` path.

**Acceptance:** the new T2 test passes on the dev host and in the Tier 3
container; `vim` started by a plain (post-install) login shell loads the
loadout vimrc and nerdtree; no `~/.vimrc`/`~/.vim` are created.

### W2 — Remove `extra_links` (D2)

**Files:** `payload/packages.json`, `loadout_main.py`, `build/gen-installed-sizes`,
docs.

- [ ] Delete the `extra_links` blocks from `env-bash`, `env-vim`, `env-zsh`,
      `env-starship`.
- [ ] Delete the link loop from `_install_env_generic` and its docstring
      mention.
- [ ] Remove `extra_links` from the validation field tuple.
- [ ] Remove the `extra_links` branch from the installed-size accounting;
      change `env-starship`'s `source` to `envs/starship/` and regenerate
      `payload/installed-sizes.json` + `.content-manifest`; confirm the
      schema file is still counted.
- [ ] Docs: AGENTS sizing note, copilot registry-field list, any
      INSTALLATION mention.

**Acceptance:** `rg extra_links` finds only HANDOFF history; T1
(`gen-installed-sizes --check`, `registry-integrity`, `check-installer`) green.

### W3 — Trim shell entrypoints (D3)

**Files:** `loadout_main.py`, `payload/packages.json` (if env-bash's
`extra_links` interacts — W2 handles the field), tests, docs.

- [ ] `BASH_ENTRYPOINTS` → `(".bashrc", ".bash_profile")`.
- [ ] `_install_env_bash`: prune `.bash_login` and `.profile` if present
      (legacy sweep), keep the backup list entries for one release.
- [ ] `_install_env_tcsh`: loop becomes `(".tcshrc",)`; prune `.cshrc`.
      Keep `.cshrc` in the backup list for one release.
- [ ] Tests: `tests/install-linux-tmp-home` (assert the two are absent, the
      two kept ones are present), `tests/install-env-tcsh` (assert `.cshrc`
      absent, `.tcshrc` present and functional).
- [ ] Docs: INSTALLATION per-user table, AGENTS entrypoint list + symlink map,
      `envs/tcsh/README.md`, `envs/tcsh/tcshrc` header comment.

**Acceptance:** a temp-HOME install creates exactly `.bashrc`/`.bash_profile`
for bash and `.tcshrc` for tcsh; reinstall over a legacy layout prunes the
removed links.

### W4 — Delete `supports_layers` (D4)

**Files:** `payload/packages.json`, `loadout_main.py`,
`tests/install-env-tmux-nvim-layers`, docs.

- [ ] Remove the field from every `kind: env` entry.
- [ ] Remove it from the validation tuple and from the `_install_env_zsh`
      comment.
- [ ] Replace the test block's field assertion with a comment referencing the
      existing dispatcher-order assertions (or drop the block).
- [ ] Docs: copilot field list, AGENTS "supports_layers is cosmetic" note.

**Acceptance:** `rg supports_layers` empty; `loadout info env-tmux` output
unchanged except the missing field; T1 green.

### W5 — Document the `tmux-yank` opt-in (D5)

**Files:** `docs/TMUX.md`, `envs/tmux/tmux-global.conf` (comment).

- [ ] Document the opt-in in the user layer and the offline rationale.
- [ ] Note the `build/update tmux-plugins` scope (global layer only).

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

## 7. Open questions

1. Is plain `csh` support required anywhere? D3 assumes no.
2. Is `prefer: ["vim"]` acceptable (it shadows system vim on PATH, as the tmux
   shim already does)? D1 assumes yes.
3. Should `~/.vimrc_hook.bottom` gain an XDG sibling
   (`~/.config/vim/vimrc_hook.bottom`)? D1 keeps the legacy path only.
