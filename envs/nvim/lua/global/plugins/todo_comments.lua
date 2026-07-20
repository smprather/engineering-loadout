local utils = require("global.utils")

return {
    "folke/todo-comments.nvim",
    cond         = utils.buf_smaller_than(10),
    event        = "VimEnter",
    dependencies = { "nvim-lua/plenary.nvim" },
    opts         = { signs = true },
}
