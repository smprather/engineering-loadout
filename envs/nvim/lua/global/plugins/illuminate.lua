return {
    "RRethy/vim-illuminate",
    event = { "BufReadPost", "BufWritePost", "BufNewFile" },
    opts = {
        delay              = 200,
        large_file_cutoff  = 2000,
        large_file_overrides = { providers = { "lsp" } },
    },
    config = function(_, opts)
        require("illuminate").configure(opts)

        Snacks.toggle({
            name = "Illuminate",
            get  = function() return not require("illuminate.engine").is_paused() end,
            set  = function(enabled)
                local m = require("illuminate")
                if enabled then m.resume() else m.pause() end
            end,
        }):map("<leader>ux")

    end,
    keys = {},
}
