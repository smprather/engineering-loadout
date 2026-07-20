return {
    "pteroctopus/faster.nvim",
    opts = {
        behaviours = {
            bigfile = {
                on = true,
                features_disabled = {
                    "illuminate", "matchparen", "lsp", "treesitter",
                    "indent_blankline", "vimopts", "syntax", "filetype",
                },
                filesize = 2,
            },
        },
    },
}
