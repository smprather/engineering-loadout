# Neovim Configuration

Layered Neovim configuration for the engineering-loadout offline-first
toolkit. The repo ships a curated set of plugins (Lazy.nvim, locked
versions), 326 prebuilt Tree-sitter parsers, and LSP server entries for
nearly every language Neovim's `vim.lsp.config` can target.

For the install workflow and the prebuilt parser bundle see the top-level
[README](../README.md). For the architecture deep-dive see
[`docs/ARCHITECTURE.md`](../docs/ARCHITECTURE.md).

## Layer Dispatcher

`nvim/init.lua` is a thin dispatcher. The six layers
(`global → corp → site → team → project → user`) match the bash layer
system — each layer overrides the previous without touching upstream files.

Phases (in order, see `init.lua`):

1. **Config variables.** Source `lua/<layer>/config.lua` for each layer.
   Sets `vim.g.cfg_*` defaults — colorscheme, feature toggles, `dpc`
   (offline mode), `swap_dir`, etc.
2. **Bootstrap lazy.nvim** (offline-safe — if `lazy.nvim` is missing and
   `git` cannot clone it, sets `vim.g.loadout_plugins_enabled = false`
   and continues so the core editor still starts on locked-down machines).
3. **Plugin specs.** Collect lazy.nvim specs from each layer's `plugins/`
   directory via `{ import = "LAYER.plugins" }`.
4. **Per-layer `init.lua`.** Source `lua/<layer>/init.lua` for options,
   keymaps, autocmds, and LSP setup.

```
~/.config/nvim/lua/
  global/      ← repo-managed: config.lua, init.lua, plugins/, utils.lua
  corp/        ← corporation overrides (user-created, not committed here)
  site/        ← site overrides
  team/        ← team overrides
  project/     ← project overrides
  user/        ← personal overrides
```

## Bundled Plugins

Repo-managed plugin specs live under `lua/global/plugins/` — one Lua file
per plugin. Versions are locked in `lazy-lock.json`. Notable inclusions:

- `blink.cmp` — completion engine
- `snacks.nvim` — dashboard, picker, notifier (no-argument `nvim` opens the
  dashboard, filetype `snacks_dashboard`)
- `gitsigns.nvim` — git status in the gutter
- `conform.nvim` — formatters
- `nvim-lint` — linters
- `nvim-treesitter` (offline parsers via the loadout vendor tree)
- `tokyonight.nvim` — default colorscheme
- `mini.trailspace` — trailing whitespace highlighter
- `lualine.nvim`, `which-key.nvim`, `bufdel.nvim`, `todo-comments.nvim`,
  `indent-blankline.nvim`, `illuminate.nvim`, plus the markdown and
  lazydev plugins

## LSP

`nvim/lsp/<server>.lua` files hold one `vim.lsp.config` entry per server.
Coverage is broad — most languages Neovim knows about have an entry here.
Enable in your user layer with `vim.lsp.enable("<server>")`.

## Tree-sitter — Offline

326 prebuilt parsers ship in `treesitter/prebuilt/<platform>/`. The
installer decompresses matching parsers to
`~/.local/share/nvim/tree-sitter-parsers/parser/*.so` and copies queries,
parser-info, registry cache, and build-info into the same tree. Neovim
v0.12+ appends that directory to `runtimepath` and starts native
Tree-sitter highlighting offline.

Rebuild the full set with `./treesitter/build_parsers` from the repo root.

## Sanity Check

```bash
XDG_CACHE_HOME=/tmp/nvim-cache XDG_STATE_HOME=/tmp/nvim-state \
  nvim --headless +qa
```

Use temp writable XDG dirs when checking config from sandboxes whose `$HOME`
is read-only.
