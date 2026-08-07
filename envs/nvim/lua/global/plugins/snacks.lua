return {
    "folke/snacks.nvim",
    priority = 1000,
    lazy     = false,
    ---@type snacks.Config
    opts = {
        animate      = { enabled = true },
        bigfile      = { enabled = true },
        dashboard    = { enabled = true },
        -- replace_netrw = false disables the BufEnter-on-directory autocmd that
        -- would otherwise spawn the explorer any time :bnext (or similar) landed
        -- on a directory-named buffer. Startup auto-open for `nvim <dir>` is
        -- handled explicitly in init() below.
        explorer     = { enabled = true, replace_netrw = false },
        picker       = {
            enabled = true,
            -- Default layout for ALL pickers: full-terminal, list on top,
            -- preview on bottom. Modeled on the built-in "vertical" preset
            -- but widened to fill the whole screen (width/height = 1) with
            -- min constraints dropped so nothing clips at small terminal
            -- sizes. `preview = 0.5` gives an even top/bottom split.
            layout = {
                preset = "full_vertical",
                preview = true,
            },
            layouts = {
                -- IMPORTANT: In Snacks's window-size math, `width`/`height`
                -- of 0 means "full parent size", values <1 are fractional,
                -- and values >=1 are literal cells. `1` therefore renders a
                -- 1x1 window (looks broken, empty). Use 0 for full-screen.
                full_vertical = {
                    layout = {
                        backdrop = false,
                        width    = 0,
                        height   = 0,
                        box      = "vertical",
                        border   = "none",
                        title    = "{title} {live} {flags}",
                        title_pos = "center",
                        { win = "input",   height = 1,     border = "bottom" },
                        { win = "list",    border = "none" },
                        { win = "preview", title = "{preview}", height = 0.5, border = "top" },
                    },
                },
            },
            -- Force the explorer to auto-close on focus loss. The explorer
            -- source defaults to auto_close=false (so it lingers unfocused
            -- like a traditional sidebar); we override that so it behaves
            -- like every other picker: focus it, use it, focus elsewhere =
            -- it closes. Reopen with <leader>e.
            --
            -- Also override the explorer's source-level layout so it inherits
            -- our full-terminal preset instead of the built-in "sidebar" it
            -- ships with.
            sources = {
                explorer = {
                    auto_close = true,
                    layout = { preset = "full_vertical", preview = true },
                },
            },
            -- Give the picker its own <C-Up>/<C-Down> = list_up/list_down.
            -- Without this, the user's GLOBAL <C-Up>/<C-Down> (bprevious/
            -- bnext) fires inside the picker list window, which switches
            -- the buffer, causes the picker to auto_close, and loads the
            -- previewed file for real (bad when files are huge). Buffer-
            -- local picker binds shadow the global maps, so the picker
            -- stays open and the preview handles size limits sanely.
            win = {
                input = {
                    keys = {
                        ["<C-Up>"]   = { "list_up",   mode = { "i", "n" } },
                        ["<C-Down>"] = { "list_down", mode = { "i", "n" } },
                    },
                },
                list = {
                    keys = {
                        ["<C-Up>"]   = "list_up",
                        ["<C-Down>"] = "list_down",
                    },
                },
            },
        },
        indent       = { enabled = false },
        input        = { enabled = true },
        notifier     = { enabled = true, timeout = 3000 },
        quickfile    = { enabled = true },
        scope        = { enabled = true },
        scroll       = { enabled = false },
        statuscolumn = { enabled = false },
        words        = { enabled = true },
        styles = {
            dashboard    = { wo = { list = false } },
            notification = {},
        },
    },
    keys = {
        -- Top Pickers & Explorer
        { "<leader><space>", function() Snacks.picker.smart() end,          desc = "Smart Find Files" },
        { "<leader>,",       function() Snacks.picker.buffers() end,         desc = "Buffers" },
        { "<leader>/",       function() Snacks.picker.grep() end,            desc = "Grep" },
        { "<leader>:",       function() Snacks.picker.command_history() end, desc = "Command History" },
        { "<leader>n",       function() Snacks.picker.notifications() end,   desc = "Notification History" },
        {
            "<leader>e",
            function()
                -- Toggle: if an explorer picker is already open, close it; else open one.
                local existing = Snacks.picker.get({ source = "explorer" })[1]
                if existing then existing:close() else Snacks.explorer() end
            end,
            desc = "File Explorer (toggle)",
        },
        -- find
        { "<leader>fb",      function() Snacks.picker.buffers() end,         desc = "Buffers" },
        { "<leader>fc",      function() Snacks.picker.files({ cwd = vim.fn.stdpath("config") }) end, desc = "Find Config File" },
        { "<leader>ff",      function() Snacks.picker.files() end,           desc = "Find Files" },
        { "<leader>fg",      function() Snacks.picker.git_files() end,       desc = "Find Git Files" },
        { "<leader>fp",      function() Snacks.picker.projects() end,        desc = "Projects" },
        { "<leader>fr",      function() Snacks.picker.recent() end,          desc = "Recent" },
        -- git
        { "<leader>gb",      function() Snacks.picker.git_branches() end,   desc = "Git Branches" },
        { "<leader>gl",      function() Snacks.picker.git_log() end,         desc = "Git Log" },
        { "<leader>gL",      function() Snacks.picker.git_log_line() end,    desc = "Git Log Line" },
        { "<leader>gs",      function() Snacks.picker.git_status() end,      desc = "Git Status" },
        { "<leader>gS",      function() Snacks.picker.git_stash() end,       desc = "Git Stash" },
        { "<leader>gd",      function() Snacks.picker.git_diff() end,        desc = "Git Diff (Hunks)" },
        { "<leader>gf",      function() Snacks.picker.git_log_file() end,    desc = "Git Log File" },
        -- gh
        { "<leader>gi",      function() Snacks.picker.gh_issue() end,                        desc = "GitHub Issues (open)" },
        { "<leader>gI",      function() Snacks.picker.gh_issue({ state = "all" }) end,       desc = "GitHub Issues (all)" },
        { "<leader>gp",      function() Snacks.picker.gh_pr() end,                           desc = "GitHub Pull Requests (open)" },
        { "<leader>gP",      function() Snacks.picker.gh_pr({ state = "all" }) end,          desc = "GitHub Pull Requests (all)" },
        -- Grep
        { "<leader>sb",      function() Snacks.picker.lines() end,           desc = "Buffer Lines" },
        { "<leader>sB",      function() Snacks.picker.grep_buffers() end,    desc = "Grep Open Buffers" },
        { "<leader>sg",      function() Snacks.picker.grep() end,            desc = "Grep" },
        { "<leader>sw",      function() Snacks.picker.grep_word() end,       desc = "Visual selection or word", mode = { "n", "x" } },
        -- search
        { '<leader>s"',      function() Snacks.picker.registers() end,       desc = "Registers" },
        { "<leader>s/",      function() Snacks.picker.search_history() end,  desc = "Search History" },
        { "<leader>sa",      function() Snacks.picker.autocmds() end,        desc = "Autocmds" },
        { "<leader>sc",      function() Snacks.picker.command_history() end, desc = "Command History" },
        { "<leader>sC",      function() Snacks.picker.commands() end,        desc = "Commands" },
        { "<leader>sd",      function() Snacks.picker.diagnostics() end,     desc = "Diagnostics" },
        { "<leader>sD",      function() Snacks.picker.diagnostics_buffer() end, desc = "Buffer Diagnostics" },
        { "<leader>sh",      function() Snacks.picker.help() end,            desc = "Help Pages" },
        { "<leader>sH",      function() Snacks.picker.highlights() end,      desc = "Highlights" },
        { "<leader>si",      function() Snacks.picker.icons() end,           desc = "Icons" },
        { "<leader>sj",      function() Snacks.picker.jumps() end,           desc = "Jumps" },
        { "<leader>sk",      function() Snacks.picker.keymaps() end,         desc = "Keymaps" },
        { "<leader>sl",      function() Snacks.picker.loclist() end,         desc = "Location List" },
        { "<leader>sm",      function() Snacks.picker.marks() end,           desc = "Marks" },
        { "<leader>sM",      function() Snacks.picker.man() end,             desc = "Man Pages" },
        { "<leader>sp",      function() Snacks.picker.lazy() end,            desc = "Search for Plugin Spec" },
        { "<leader>sq",      function() Snacks.picker.qflist() end,          desc = "Quickfix List" },
        { "<leader>sR",      function() Snacks.picker.resume() end,          desc = "Resume" },
        { "<leader>su",      function() Snacks.picker.undo() end,            desc = "Undo History" },
        { "<leader>uC",      function() Snacks.picker.colorschemes() end,    desc = "Colorschemes" },
        -- LSP
        { "gd",              function() Snacks.picker.lsp_definitions() end,     desc = "Goto Definition" },
        { "gD",              function() Snacks.picker.lsp_declarations() end,    desc = "Goto Declaration" },
        { "gr",              function() Snacks.picker.lsp_references() end,      nowait = true, desc = "References" },
        { "gI",              function() Snacks.picker.lsp_implementations() end, desc = "Goto Implementation" },
        { "gy",              function() Snacks.picker.lsp_type_definitions() end, desc = "Goto T[y]pe Definition" },
        { "gai",             function() Snacks.picker.lsp_incoming_calls() end,  desc = "C[a]lls Incoming" },
        { "gao",             function() Snacks.picker.lsp_outgoing_calls() end,  desc = "C[a]lls Outgoing" },
        { "<leader>ss",      function() Snacks.picker.lsp_symbols() end,         desc = "LSP Symbols" },
        { "<leader>sS",      function() Snacks.picker.lsp_workspace_symbols() end, desc = "LSP Workspace Symbols" },
        -- Other
        { "<leader>z",       function() Snacks.zen() end,                    desc = "Toggle Zen Mode" },
        { "<leader>Z",       function() Snacks.zen.zoom() end,               desc = "Toggle Zoom" },
        { "<leader>.",       function() Snacks.scratch() end,                desc = "Toggle Scratch Buffer" },
        { "<leader>S",       function() Snacks.scratch.select() end,         desc = "Select Scratch Buffer" },
        { "<leader>bd",      function() Snacks.bufdelete() end,              desc = "Delete Buffer" },
        { "<leader>cR",      function() Snacks.rename.rename_file() end,     desc = "Rename File" },
        { "<leader>gB",      function() Snacks.gitbrowse() end,              desc = "Git Browse", mode = { "n", "v" } },
        { "<leader>gg",      function() Snacks.lazygit() end,                desc = "Lazygit" },
        { "<leader>un",      function() Snacks.notifier.hide() end,          desc = "Dismiss All Notifications" },
        { "<c-/>",           function() Snacks.terminal() end,               desc = "Toggle Terminal" },
        { "<c-_>",           function() Snacks.terminal() end,               desc = "which_key_ignore" },
        { "]]",              function() Snacks.words.jump(vim.v.count1) end,  desc = "Next Reference", mode = { "n", "t" } },
        { "[[",              function() Snacks.words.jump(-vim.v.count1) end, desc = "Prev Reference", mode = { "n", "t" } },
        {
            "<leader>N",
            desc = "Neovim News",
            function()
                Snacks.win({
                    file   = vim.api.nvim_get_runtime_file("doc/news.txt", false)[1],
                    width  = 0.6,
                    height = 0.6,
                    wo     = { spell = false, wrap = false, signcolumn = "yes", statuscolumn = " ", conceallevel = 3 },
                })
            end,
        },
    },
    init = function()
        -- ── Startup auto-open policy for the explorer ─────────────────────
        -- Open the explorer ONLY when nvim was invoked with exactly one arg
        -- and that arg is a directory. In every other case (no args, one file,
        -- multiple files, mixed, multiple dirs), do not spawn the explorer.
        -- Any leftover directory-named buffers are silently wiped so :ls stays
        -- clean and :bnext / ]b never lands on one.
        vim.api.nvim_create_autocmd("VimEnter", {
            once     = true,
            callback = function()
                local argc = vim.fn.argc()
                local single_dir = nil
                if argc == 1 then
                    local a = vim.fn.argv(0)
                    if vim.fn.isdirectory(a) == 1 then single_dir = a end
                end

                -- Wipe any directory-named buffers that were created by argv
                -- expansion (this is what causes the "explorer pops up on
                -- :bnext" symptom when replace_netrw was true).
                for _, buf in ipairs(vim.api.nvim_list_bufs()) do
                    if vim.api.nvim_buf_is_valid(buf) then
                        local name = vim.api.nvim_buf_get_name(buf)
                        if name ~= "" and vim.fn.isdirectory(name) == 1 then
                            pcall(vim.api.nvim_buf_delete, buf, { force = true })
                        end
                    end
                end

                if single_dir then
                    Snacks.explorer({ cwd = single_dir })
                end
            end,
        })

        vim.api.nvim_create_autocmd("User", {
            pattern  = "VeryLazy",
            callback = function()
                _G.dd = function(...) Snacks.debug.inspect(...) end
                _G.bt = function() Snacks.debug.backtrace() end

                if vim.fn.has("nvim-0.11") == 1 then
                    vim._print = function(_, ...) dd(...) end
                else
                    vim.print = _G.dd
                end

                Snacks.toggle.option("spell",          { name = "Spelling" }):map("<leader>us")
                Snacks.toggle.option("wrap",           { name = "Wrap" }):map("<leader>uw")
                Snacks.toggle.option("relativenumber", { name = "Relative Number" }):map("<leader>uL")
                Snacks.toggle.diagnostics():map("<leader>ud")
                Snacks.toggle.line_number():map("<leader>ul")
                Snacks.toggle.option("conceallevel",
                    { off = 0, on = vim.o.conceallevel > 0 and vim.o.conceallevel or 2 }):map("<leader>uc")
                Snacks.toggle.treesitter():map("<leader>uT")
                Snacks.toggle.option("background",
                    { off = "light", on = "dark", name = "Dark Background" }):map("<leader>ub")
                Snacks.toggle.inlay_hints():map("<leader>uh")
                Snacks.toggle.indent():map("<leader>ug")
                Snacks.toggle.dim():map("<leader>uD")
            end,
        })
    end,
}
