return {
    "folke/tokyonight.nvim",
    lazy = false,
    priority = 1000,
    dependencies = {
        {
            "xiyaowong/transparent.nvim",
            lazy = false,
            opts = {
                extra_groups  = { "NormalFloat", "NvimTreeNormal" },
                exclude_groups = {},
            },
        },
    },
    config = function()
        require("tokyonight").setup({
            style       = "night",
            transparent = true,
            styles      = {
                sidebars = "transparent",
                floats   = "transparent",
                comments = { italic = true },
            },
        })
        vim.cmd([[colorscheme tokyonight-night]])
        vim.api.nvim_set_hl(0, "Comment",                    { fg = "#EECC99" })
        vim.api.nvim_set_hl(0, "DiagnosticUnderlineError",   { sp = "Red",  undercurl = true })
        vim.api.nvim_set_hl(0, "DiagnosticUnderlineWarn",    { sp = "Cyan", undercurl = true })
    end,
}
