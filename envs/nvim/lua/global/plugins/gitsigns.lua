local utils = require("global.utils")

return {
    "lewis6991/gitsigns.nvim",
    cond = utils.buf_smaller_than(2),
    opts = {
        signs = {
            add          = { text = "+" },
            change       = { text = "~" },
            delete       = { text = "_" },
            topdelete    = { text = "‾" },
            changedelete = { text = "~" },
        },
    },
}
