local utils = require("global.utils")
local paths = require("global.paths")

-- Vendored nvim-treesitter, the parser registry and the 251 MB parser set are
-- read-only payloads. In a split deployment they live in the shared tree, not in
-- $HOME, so every path here resolves through paths.data (user copy first, shared
-- tree second) rather than assuming stdpath("data").
return {
    "nvim-treesitter/nvim-treesitter",
    cond  = utils.buf_smaller_than(10),
    build = false,
    dir   = paths.has("loadout/vendor/nvim-treesitter")
            and paths.data("loadout/vendor/nvim-treesitter") or nil,
    dependencies = {
        {
            "neovim-treesitter/treesitter-parser-registry",
            dir = paths.has("loadout/vendor/treesitter-parser-registry")
                    and paths.data("loadout/vendor/treesitter-parser-registry") or nil,
        },
    },
    config = function()
        local parser_install_dir = paths.data("tree-sitter-parsers")
        if vim.fn.isdirectory(parser_install_dir .. "/parser") == 1 then
            vim.opt.runtimepath:append(parser_install_dir)
        end

        local ok, treesitter = pcall(require, "nvim-treesitter")
        if ok then treesitter.setup({ install_dir = parser_install_dir }) end

        local disable_highlight = { verilog = true }
        local disable_indent    = { ruby = true, tcl = true, yaml = true }

        vim.api.nvim_create_autocmd("FileType", {
            group    = vim.api.nvim_create_augroup("loadout_native_treesitter", { clear = true }),
            callback = function(args)
                if vim.bo[args.buf].buftype ~= "" then return end
                local filetype = vim.bo[args.buf].filetype
                if filetype == "" or disable_highlight[filetype] then return end
                pcall(vim.treesitter.start, args.buf)
                if ok and not disable_indent[filetype] then
                    vim.bo[args.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
                end
            end,
        })
    end,
}
