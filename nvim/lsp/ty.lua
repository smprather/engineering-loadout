---@brief
---
--- https://github.com/astral-sh/ty
---
--- A Language Server Protocol implementation for ty, an extremely fast Python type checker and language server, written in Rust.
---
--- For installation instructions, please refer to the [ty documentation](https://github.com/astral-sh/ty/blob/main/README.md#getting-started).

---@type vim.lsp.Config
return {
  cmd = { 'ty', 'server' },
  filetypes = { 'python' },
  root_markers = { 'ty.toml', 'pyproject.toml', '.git' },
  -- Attach in single-file mode when no project root is found. ty's basic
  -- type checks work per-file even without a project graph; loose scripts
  -- (e.g. a copy of engineering-loadout in $HOME) still get diagnostics.
  single_file_support = true,
}
