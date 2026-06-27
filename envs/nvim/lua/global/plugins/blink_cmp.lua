local utils = require("global.utils")

return {
    "saghen/blink.cmp",
    cond         = utils.buf_smaller_than(10),
    event        = "VimEnter",
    version      = "1.*",
    dependencies = {
        { "rafamadriz/friendly-snippets" },
        { "folke/lazydev.nvim" },
    },

    --- @module 'blink.cmp'
    --- @type blink.cmp.Config
    opts = {
        keymap = { preset = "super-tab" },

        appearance = { nerd_font_variant = "mono" },

        completion = {
            documentation = { auto_show = true, auto_show_delay_ms = 500 },
        },

        sources = {
            default   = { "path", "lsp", "lazydev", "buffer", "omni" },
            providers = {
                lazydev = { module = "lazydev.integrations.blink", score_offset = 100 },
            },
        },

        fuzzy     = { implementation = "lua" },
        signature = { enabled = true },
    },
}
