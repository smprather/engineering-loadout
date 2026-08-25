-- after/ftplugin/spice.lua — drop-in for Neovim ≥0.11 without any plugin manager.
-- Copy or symlink this file into `~/.config/nvim/after/ftplugin/spice.lua`,
-- or `rsync -a after/ftplugin/ ~/.config/nvim/after/ftplugin/` from the repo.

local function executable(cmd)
    if type(cmd) == "table" then
        cmd = cmd[1]
    end
    if type(cmd) ~= "string" or cmd == "" then
        return false
    end
    return vim.fn.executable(cmd) == 1
end

local lsp_cmd = vim.env.SPICEFMT_LS_CMD or "spice-netlist-ls"

-- Respect the loadout-wide LSP switch when this file is used inside env-nvim.
-- A standalone copy with no such global still defaults on.
if vim.g.cfg_enable_lsp ~= false and executable(lsp_cmd) then
    local cfg = {
        cmd = { lsp_cmd },
        filetypes = { "spice" },
        root_markers = { ".git", "spicefmt.toml" },
        single_file_support = true,
    }
    vim.lsp.config["spicefmt"] = cfg
    vim.lsp.config["spice_netlist_ls"] = cfg

    -- Only enable from ftplugin if neither name was already enabled globally
    -- (e.g. via `vim.lsp.enable("spicefmt")` in init.lua or `lsp/spicefmt.lua`).
    -- This avoids double-attach when the user copied both the ftplugin *and* an
    -- lsp/ file — the lsp/ path already enables the server for all spice buffers.
    local enabled = false
    if vim.lsp.is_enabled then
        enabled = vim.lsp.is_enabled("spicefmt") or vim.lsp.is_enabled("spice_netlist_ls")
    end
    if not enabled then
        vim.lsp.enable("spicefmt")
    end

    -- Format-on-save through the LSP (`textDocument/formatting`) for standalone
    -- drop-in use. The full loadout plugin layer already has a global conform
    -- BufWritePre hook with LSP fallback, so avoid double-formatting there.
    if vim.g.loadout_plugins_enabled ~= true then
        local format_group = vim.api.nvim_create_augroup("SpicefmtFormatOnSave", { clear = false })
        vim.api.nvim_clear_autocmds({ group = format_group, buffer = 0 })
        vim.api.nvim_create_autocmd("BufWritePre", {
            group = format_group,
            buffer = 0,
            callback = function()
                vim.lsp.buf.format({ async = false })
            end,
        })
    end
end

vim.bo.commentstring = "* %s"

-- Semantic-token highlights: Neovim uses per-filetype groups like
-- `@lsp.type.variable.spice` for nets. Generic `@lsp.type.variable`
-- alone does not color spice buffers, so link the spice-specific groups
-- to sensible defaults. `default = true` preserves any user override.
local hl_groups = {
    ["@lsp.type.variable"] = "Identifier", -- nets, ports — the "net names" that look missing when this link is absent
    ["@lsp.type.type"] = "Type", -- subckt / model names
    ["@lsp.type.function"] = "Function", -- instance names (R1, X1)
    ["@lsp.type.keyword"] = "Keyword", -- directives (.param, .subckt, .ends)
    ["@lsp.type.property"] = "Identifier", -- param keys
    ["@lsp.type.string"] = "String",
    ["@lsp.type.number"] = "Number",
    ["@lsp.type.comment"] = "Comment",
    ["@lsp.type.operator"] = "Operator",
}
local function link_spice_hl()
    for base, target in pairs(hl_groups) do
        for _, ft in ipairs({ "spice", "cir", "scs", "subckt", "sp", "ckt", "net" }) do
            vim.api.nvim_set_hl(0, base .. "." .. ft, { link = target, default = true })
        end
        vim.api.nvim_set_hl(0, base, { link = target, default = true })
    end
end
link_spice_hl()
vim.api.nvim_create_autocmd("ColorScheme", {
    group = vim.api.nvim_create_augroup("SpicefmtHighlightLinks", { clear = false }),
    callback = link_spice_hl,
    desc = "re-link spice semantic-token highlights after colorscheme change",
})
