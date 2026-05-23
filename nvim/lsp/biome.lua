---@brief
---
--- https://biomejs.dev
---
--- Biome — single Rust binary that provides LSP, formatter, and linter
--- for JSON, JSONC, JavaScript, TypeScript, CSS, GraphQL, and HTML.
---
--- The bundled `biome` binary in this repo is the linux-x64-musl release
--- (static-pie, no glibc dependency), so it runs on EL8 farm nodes that
--- can't satisfy biome's GLIBC_2.30 gnu-target.
---
--- We restrict it to json/jsonc here because that's the only thing we
--- actively need; bump the filetypes list if you ever want biome on
--- TS/CSS too.

---@type vim.lsp.Config
return {
  cmd           = { 'biome', 'lsp-proxy' },
  filetypes     = { 'json', 'jsonc' },
  root_markers  = { 'biome.json', 'biome.jsonc', '.git' },
  -- Attach in single-file mode when no project root is found, so loose
  -- JSON files anywhere get formatting + diagnostics.
  single_file_support = true,
}
