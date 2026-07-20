local utils = require("global.utils")

return {
    "nvim-mini/mini.trailspace",
    lazy = false,
    cond = utils.buf_smaller_than(5),
    opts = { only_in_normal_buffers = true },
    init = function()
        local function disable_dashboard_trailspace(buf)
            if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].filetype ~= "snacks_dashboard" then
                return
            end
            vim.b[buf].minitrailspace_disable = true
            for _, win in ipairs(vim.fn.win_findbuf(buf)) do
                vim.api.nvim_win_call(win, function()
                    vim.opt_local.list = false
                    for _, match in ipairs(vim.fn.getmatches()) do
                        if match.group == "MiniTrailspace" then
                            pcall(vim.fn.matchdelete, match.id)
                        end
                    end
                end)
            end
        end

        vim.api.nvim_create_autocmd({ "FileType", "BufEnter" }, {
            pattern  = "*",
            callback = function(args) disable_dashboard_trailspace(args.buf) end,
        })
        vim.api.nvim_create_autocmd("User", {
            pattern  = { "SnacksDashboardOpened", "SnacksDashboardUpdatePost" },
            callback = function() disable_dashboard_trailspace(vim.api.nvim_get_current_buf()) end,
        })
    end,
    keys = {
        {
            "<leader>dtw",
            function()
                local mts = require("mini.trailspace")
                mts.trim()
                mts.trim_last_lines()
            end,
            mode = "",
            desc = "Trim Whitespace",
        },
    },
}
