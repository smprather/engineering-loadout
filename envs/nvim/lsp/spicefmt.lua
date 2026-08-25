---@brief
--- https://github.com/smprather/spice-netlist-ls
---
--- Native config for `spice-netlist-ls` (also aliased as `spice_netlist_ls`).
--- Copy to `~/.config/nvim/lsp/spicefmt.lua` and `vim.lsp.enable("spicefmt")`.
--- See `after/ftplugin/spice.lua` for the zero-config alternative that needs no
--- `lsp/` file at all.

---@type vim.lsp.Config
return {
    cmd = { vim.env.SPICEFMT_LS_CMD or "spice-netlist-ls" },
    filetypes = { "spice" },
    root_markers = { ".git", "spicefmt.toml" },
    single_file_support = true,
}
