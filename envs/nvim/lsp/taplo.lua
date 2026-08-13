---@brief
---
--- https://taplo.tamasfe.dev/cli/usage/language-server.html
---
--- Language server for Taplo, a TOML toolkit. Bundled by this repo -- see
--- build/build-taplo.sh; `cmd` resolves the wrapper at <prefix>/bin/taplo.
---
--- OFFLINE SCHEMAS. taplo validates TOML at two independent levels. The grammar
--- is compiled into the binary and always works. JSON Schema validation -- the
--- level that knows `[package] nmae = "x"` is a typo in a Cargo.toml -- resolves
--- schemas from a catalog, and upstream's defaults (schemastore.org,
--- taplo.tamasfe.dev) are dead on a farm node with no route out. A dead catalog
--- does NOT produce an error; taplo quietly drops to grammar-only checking, so
--- the editor looks healthy while silently accepting misspelled keys.
---
--- So the loadout ships the catalog: the `taplo` package installs 49
--- SchemaStore-upstream schemas to <prefix>/share/taplo/schemas/, with absolute
--- file:// URLs rewritten to the deployed prefix at install time. This config
--- points the server at that copy and turns the REMOTE sources off, so nothing
--- here ever reaches for the network.
---
--- Networked users who want live schemastore instead can override in a layer:
---
--- ```lua
--- -- lua/user/init.lua
--- vim.lsp.config('taplo', {
---   settings = { evenBetterToml = { schema = {
---     enabled = true,
---     repositoryEnabled = true,
---     catalogs = { 'https://www.schemastore.org/api/json/catalog.json' },
---   } } },
--- })
--- ```

local paths = require("global.paths")

-- nil when the taplo package is installed without its schema archive (or when
-- only the binary was selected). Schemas then stay off rather than falling back
-- to upstream's remote catalogs, which would hang an air-gapped editor on every
-- TOML buffer.
local catalog = paths.share("taplo/schemas/catalog.json")

local schema = catalog
        and {
            enabled = true,
            -- `repositoryEnabled` is taplo's OTHER remote source (its own schema
            -- index). Off for the same reason the default catalogs are.
            repositoryEnabled = false,
            catalogs = { "file://" .. catalog },
        }
    or { enabled = false, repositoryEnabled = false, catalogs = {} }

---@type vim.lsp.Config
return {
    cmd = { "taplo", "lsp", "stdio" },
    filetypes = { "toml" },
    root_markers = { ".taplo.toml", "taplo.toml", ".git" },
    -- TOML files are overwhelmingly standalone config; without this, a
    -- pyproject.toml or Cargo.toml opened outside a git checkout gets no
    -- server at all.
    single_file_support = true,
    settings = {
        -- taplo asks for this section by name over workspace/configuration;
        -- the key must stay `evenBetterToml` (its default configurationSection,
        -- inherited from the VS Code extension) or the request resolves to nil
        -- and every setting below is silently ignored.
        evenBetterToml = {
            schema = schema,
        },
    },
}
