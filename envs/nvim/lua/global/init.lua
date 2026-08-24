-- ── Early options (Kickstart defaults) ──────────────────────────────────
vim.o.showmode    = false
vim.o.smartcase   = true
vim.o.signcolumn  = "yes"
vim.o.updatetime  = 250
vim.o.timeoutlen  = 300
vim.o.splitright  = true
vim.o.splitbelow  = true
vim.o.list        = true
vim.opt.listchars = { tab = "» ", trail = "·", nbsp = "␣" }
vim.o.inccommand  = "split"
vim.o.cursorline  = true
vim.o.confirm     = true

-- ── Basic keymaps ────────────────────────────────────────────────────────
vim.keymap.set("n", "<Esc>", "<cmd>nohlsearch<CR>")
vim.keymap.set("t", "<Esc><Esc>", "<C-\\><C-n>", { desc = "Exit terminal mode" })
vim.keymap.set("n", "<C-h>", "<C-w><C-h>", { desc = "Move focus to the left window" })
vim.keymap.set("n", "<C-l>", "<C-w><C-l>", { desc = "Move focus to the right window" })
vim.keymap.set("n", "<C-j>", "<C-w><C-j>", { desc = "Move focus to the lower window" })
vim.keymap.set("n", "<C-k>", "<C-w><C-k>", { desc = "Move focus to the upper window" })

-- ── Basic autocmds ───────────────────────────────────────────────────────
vim.api.nvim_create_autocmd("TextYankPost", {
    desc     = "Highlight when yanking (copying) text",
    group    = vim.api.nvim_create_augroup("kickstart-highlight-yank", { clear = true }),
    callback = function() vim.hl.on_yank() end,
})

-- ── Options table ────────────────────────────────────────────────────────
local options = {
    cmdheight     = 1,
    encoding      = "utf-8",
    fileencoding  = "utf-8",
    tabstop       = vim.g.cfg_tab_width or 4,
    softtabstop   = vim.g.cfg_tab_width or 4,
    shiftwidth    = vim.g.cfg_tab_width or 4,
    expandtab     = true,
    autoindent    = true,
    guicursor     = "i:block",
    foldmethod    = "manual",
    foldlevel     = 99,
    startofline   = false,
    hidden        = true,
    mouse         = "",
    mousefocus    = true,
    mousehide     = true,
    mousemodel    = "extend",
    textwidth     = 130,
    backspace     = "indent,eol,start",
    completeopt   = { "menuone", "preview" },
    conceallevel  = 0,
    hlsearch      = true,
    ignorecase    = true,
    smartindent   = false,
    pumheight     = 10,
    showmode      = false,
    showtabline   = 1,
    scrolloff     = 999,
    cursorline    = true,
    termguicolors = true,
    swapfile      = true,
    backup        = false,
    writebackup   = true,
    directory     = vim.g.cfg_swap_dir or "/tmp",
    wildmenu      = true,
    wildmode      = "longest:full,full",
    timeoutlen    = 300,
    updatetime    = 250,
    number        = false,
    relativenumber = false,
    numberwidth   = 2,
    signcolumn    = "yes",
    wrap          = true,
    splitright    = true,
    splitbelow    = true,
    viewoptions   = "folds,cursor",
    sessionoptions = "folds",
    visualbell    = false,
    errorbells    = false,
    laststatus    = 2,
    cpoptions     = "ceFs",
    sidescrolloff = 8,
    clipboard     = "",
}

for k, v in pairs(options) do
    pcall(function() vim.opt[k] = v end)
end

vim.cmd([[
    highlight DiagnosticUnderlineError guisp='Red' gui=undercurl
    highlight DiagnosticUnderlineWarn guisp='Cyan' gui=undercurl
]])

vim.api.nvim_set_hl(0, "DiagnosticUnnecessary", { fg = "#00FFFF" })

vim.opt.formatoptions:remove("t")

-- ── Autocmds ─────────────────────────────────────────────────────────────
local my_augroup1 = vim.api.nvim_create_augroup("my_augroup1", { clear = true })

local utils = require("global.utils")
vim.api.nvim_create_autocmd("BufWinEnter", {
    group    = my_augroup1,
    callback = function() vim.opt.incsearch = utils.buf_smaller_than(50) end,
})

vim.api.nvim_create_autocmd("BufReadPost", {
    group    = my_augroup1,
    callback = function(args)
        local line = vim.fn.line
        local valid_line = line([['"]]) >= 1 and line([['"]]) <= line("$")
        local not_commit = vim.b[args.buf].filetype ~= "commit"
        if valid_line and not_commit then vim.cmd([[normal! g`"zz]]) end
    end,
})

if vim.g.loadout_plugins_enabled then
    vim.api.nvim_create_autocmd({ "BufWritePre", "FileChangedShell", "InsertLeave" }, {
        group    = my_augroup1,
        pattern  = "*",
        callback = function(args) require("conform").format({ bufnr = args.buf }) end,
    })
end

vim.cmd([[
    function! PyAddParensToDebugs()
        execute "normal! mZ"
        execute "%s/^\\(\\s*\\)\\(ic\\)\\( \\(.*\\)\\)\\{-}$/\\1\\2(\\4)/"
        execute "%s/^\\(\\s*\\)\\(ice\\)\\( \\(.*\\)\\)\\{-}$/\\1ic(\\4)\\r\\1exit()/"
        execute "%s/^\\(\\s*\\)\\(exit\\|e\\)$/\\1exit()/"
        execute "normal! `Z"
    endfunction

    filetype plugin indent on
    augroup my_au_group | autocmd!
        autocmd BufWritePre * if count(['python'],&filetype)
            \ |                   silent! call PyAddParensToDebugs()
            \ |               endif
        autocmd BufWinEnter,VimResized * wincmd =
    augroup end
]])

vim.cmd([[
    function! s:ZoomToggle() abort
        if exists('t:zoomed') && t:zoomed
            execute t:zoom_winrestcmd
            let t:zoomed = 0
        else
            let t:zoom_winrestcmd = winrestcmd()
            resize
            vertical resize
            let t:zoomed = 1
        endif
    endfunction
    command! ZoomToggle call s:ZoomToggle()
]])

-- ── LSP ──────────────────────────────────────────────────────────────────
if vim.g.cfg_enable_lsp then
    -- markdown_oxide replaced marksman here (2026-08-10). Both are markdown
    -- language servers and enabling both attaches two servers to every
    -- markdown buffer, doubling completions and go-to-def results. marksman
    -- was never bundled -- it was an enabled server with no binary on an
    -- offline-first box, so it silently never started. markdown-oxide IS
    -- bundled (payload bin/, see build/build-markdown-oxide.sh) and is
    -- Obsidian-vault compatible, which is the PKM story this repo wants.
    -- taplo is the TOML server (bundled; see build/build-taplo.sh). tombi.lua
    -- also ships in lsp/ and is deliberately NOT enabled: it is a second TOML
    -- server, and two of them attach to every .toml buffer -- the same
    -- double-attach that markdown_oxide/marksman is avoiding above.
    --
    -- tclsp is the Tcl language server shipped by tclint (bundled as a
    -- python-tool wheel; see build/ADDING_BINARIES.md). It covers .tcl and
    -- the EDA constraint dialects (.sdc/.xdc/.upf); nvim maps .sdc to its
    -- own filetype so both are listed in tclsp.lua.
    --
    -- spice_netlist_ls is the SPICE formatter/linter/LSP server shipped as
    -- static binaries by the spice-netlist-ls package. It covers .sp/.cir/.scs
    -- and .subckt netlists; see envs/nvim/lsp/spice_netlist_ls.lua.
    --
    -- yamlls was dropped from this list (2026-08-13) for the marksman reason:
    -- yaml-language-server is an npm package and is NOT bundled, so every user
    -- got an enabled server that could never start. Its lsp/yamlls.lua also
    -- hardcoded an absolute path into a personal $HOME, which has been reverted
    -- to the upstream bare command name. Re-enabling it means BUNDLING the
    -- server and its node_modules closure offline first -- nodejs is already in
    -- the payload, so it is feasible, but it is a package, not a config edit.
    vim.lsp.enable({ "lua_ls", "ruff", "ty", "markdown_oxide", "biome", "taplo", "tclsp", "spice_netlist_ls" })
    vim.lsp.config("*", {
        root_markers = { ".git" },
        capabilities = {
            textDocument = {
                semanticTokens = { multilineTokenSupport = true },
            },
        },
    })
    vim.lsp.log.set_level(vim.log.levels.WARN)

    vim.diagnostic.config({
        severity_sort = true,
        float         = { border = "rounded", source = "if_many" },
        underline     = { severity = vim.diagnostic.severity.ERROR },
        signs         = vim.g.have_nerd_font and {
            text = {
                [vim.diagnostic.severity.ERROR] = "󰅚 ",
                [vim.diagnostic.severity.WARN]  = "󰀪 ",
                [vim.diagnostic.severity.INFO]  = "󰋽 ",
                [vim.diagnostic.severity.HINT]  = "󰌶 ",
            },
        } or {},
        virtual_text = {
            source  = "if_many",
            spacing = 2,
            format  = function(diagnostic)
                local msgs = {
                    [vim.diagnostic.severity.ERROR] = diagnostic.message,
                    [vim.diagnostic.severity.WARN]  = diagnostic.message,
                    [vim.diagnostic.severity.INFO]  = diagnostic.message,
                    [vim.diagnostic.severity.HINT]  = diagnostic.message,
                }
                return msgs[diagnostic.severity]
            end,
        },
    })

    vim.api.nvim_create_autocmd("LspAttach", {
        group    = vim.api.nvim_create_augroup("kickstart-lsp-attach", { clear = true }),
        callback = function(event)
            local map = function(keys, func, desc, mode)
                mode = mode or "n"
                vim.keymap.set(mode, keys, func, { buffer = event.buf, desc = "LSP: " .. desc })
            end

            map("grn", vim.lsp.buf.rename,      "[R]e[n]ame")
            map("gra", vim.lsp.buf.code_action, "[G]oto Code [A]ction", { "n", "x" })

            local client = vim.lsp.get_client_by_id(event.data.client_id)
            if client and client:supports_method("textDocument/documentHighlight") then
                local highlight_augroup = vim.api.nvim_create_augroup("kickstart-lsp-highlight", { clear = false })
                vim.api.nvim_create_autocmd({ "CursorHold", "CursorHoldI" }, {
                    buffer   = event.buf,
                    group    = highlight_augroup,
                    callback = vim.lsp.buf.document_highlight,
                })
                vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
                    buffer   = event.buf,
                    group    = highlight_augroup,
                    callback = vim.lsp.buf.clear_references,
                })
                vim.api.nvim_create_autocmd("LspDetach", {
                    group    = vim.api.nvim_create_augroup("kickstart-lsp-detach", { clear = true }),
                    callback = function(event2)
                        vim.lsp.buf.clear_references()
                        vim.api.nvim_clear_autocmds({ group = "kickstart-lsp-highlight", buffer = event2.buf })
                    end,
                })
            end

            end,
    })
end

-- ── Post-layout init ─────────────────────────────────────────────────────
if not vim.api.nvim_get_option_value("diff", { win = 0 }) then
    vim.cmd("silent! sball")
    vim.cmd("silent! only")
end

-- ── Global functions ─────────────────────────────────────────────────────
ToggleStuff = function()
    vim.o.signcolumn = vim.o.signcolumn == "yes" and "no" or "yes"
    vim.cmd(":IBLToggle")
    vim.diagnostic.enable(not vim.diagnostic.is_enabled())
end
ToggleWrap = function() vim.o.wrap = not vim.o.wrap end

-- ── Keymaps ──────────────────────────────────────────────────────────────
local noremap_silent = { noremap = true, silent = true }
local keymap = vim.keymap.set

keymap("n", "<c-d>", "dd",      { noremap = true, silent = true, desc = "Delete line" })
keymap("i", "kj",    "<Esc>",   { noremap = true, silent = true, desc = "Exit insert mode" })
keymap("i", "jk",    "<Esc>",   { noremap = true, silent = true, desc = "Exit insert mode" })
keymap("i", "jj",    "<Esc>",   { noremap = true, silent = true, desc = "Exit insert mode" })
keymap("i", "kk",    "<Esc>",   { noremap = true, silent = true, desc = "Exit insert mode" })
keymap("n", "<c-n>", "<c-w><c-w>", { noremap = true, silent = true, desc = "Move to next window" })

keymap("n", "v",          "V",          noremap_silent)
keymap("n", "V",          "v",          noremap_silent)
keymap("n", "e",          ":e<space>",  { noremap = true, desc = "Open file" })
keymap("n", "<leader>s",  ":w<cr>",     { noremap = true, silent = true, desc = "Save changes to file" })
keymap("n", "<leader>w",  ":set wrap<cr>",   { noremap = true, silent = true, desc = "Enable line wrap" })
keymap("n", "<leader>nw", ":set nowrap<cr>", { noremap = true, silent = true, desc = "Disable line wrap" })
keymap("n", "<leader>ti", ":IBLToggle<cr>",  { noremap = true, silent = true, desc = "Toggle indent lines" })
keymap("n", "<leader>ts", ToggleStuff,  { noremap = true, silent = true, desc = "Toggle prepare for copy selection" })
keymap("n", "<leader>wsq", 'ysiw"',    { desc = "Word Surround Quotes" })
keymap("n", "<leader>F",  "zR",        { desc = "Open all folds" })

keymap("v", "<",  "<gv", noremap_silent)
keymap("v", ">",  ">gv", noremap_silent)

-- Buffer navigation: Pope Standard (vim-unimpaired), now a Neovim 0.10+ default.
-- <C-Up>/<C-Down> mirror the tmux <C-Left>/<C-Right> "cycle through things"
-- convention: horizontal arrows cycle tmux windows, vertical arrows cycle
-- nvim buffers. Both keys freed from previous <C-j>/<C-k> bindings.
keymap("n", "]b",     ":bnext<cr>",     noremap_silent)
keymap("n", "[b",     ":bprevious<cr>", noremap_silent)
keymap("n", "<C-Down>", ":bnext<cr>",     noremap_silent)
keymap("n", "<C-Up>",   ":bprevious<cr>", noremap_silent)

keymap("n", "<leader>q", ":BufDelAll<cr>",   { noremap = true, silent = true, desc = "Close all buffers and exit." })
keymap("n", "<leader>d", ":BufDel<cr>",      { noremap = true, silent = true, desc = "Close the current buffer." })
keymap("n", "<leader>D", ":BufDelOthers<cr>", { noremap = true, silent = true, desc = "Close all other buffers." })
keymap("n", "<leader>Q", ":BufDelAll!<cr>",  { noremap = true, silent = true, desc = "Full exit, discard all changes" })
keymap("n", "<leader>x", ":xa<cr>",          { noremap = true, desc = "Full exit, save all changes." })

keymap("n", "<leader>v", ":vsplit<cr>:bn<cr>", noremap_silent)
keymap("n", "<leader>h", ":split<cr>:bn<cr>",  noremap_silent)

-- Smart :q that skips Vim's "N more files to edit" arglist nag.
-- The nag fires whenever nvim was launched with multiple file args and
-- some remain unvisited. It's a non-destructive prompt (Vim doesn't lose
-- anything by quitting), so it just adds friction.
--
-- Behavior:
--   - If the current buffer has unsaved changes → :confirm quit (prompts,
--     preserving the destructive-action safety net).
--   - Otherwise → :quit! (skip both the arglist check AND the unsaved-
--     changes check; the latter is safe because we already verified the
--     buffer is clean).
--
-- Applies to :q, :Q, and <leader>c. Multi-window/multi-buffer variants
-- (:qa, :wq, etc.) are intentionally NOT touched.
vim.api.nvim_create_user_command("Q", function()
    -- Kill the arglist first. Vim's :quit refuses when there are unvisited
    -- args and asks "N more files to edit. Quit anyway?"  That question is
    -- non-destructive and we never want it, so we drop the arglist before
    -- any quit path runs. pcall because :argdelete errors on an empty list.
    pcall(function() vim.cmd("argdelete *") end)
    if vim.bo.modified then
        vim.cmd("confirm quit")   -- now only prompts about unsaved changes
    else
        vim.cmd("quit!")
    end
end, { desc = "Quit current window, skipping the arglist nag" })

-- Rewrite bare `:q<CR>` and `:q <CR>` to `:Q<CR>` at command-line time.
-- Guarded so `:qa`, `:q!`, `:s/q/x/`, etc. are left alone.
vim.cmd([[
    cnoreabbrev <expr> q  (getcmdtype() == ':' && getcmdline() ==# 'q') ? 'Q' : 'q'
]])

keymap("n", "<leader>c", ":Q<cr>",             { noremap = true, silent = true, desc = "Close current window (smart quit)" })

keymap("n", "<leader>tw", ToggleWrap, { noremap = true, silent = true, desc = "Toggle line wrap" })
keymap("n", "Q",  "@q",  noremap_silent)
keymap("n", ">",  ">>",  noremap_silent)
keymap("n", "<",  "<<",  noremap_silent)
keymap("n", "-",  "<c-w>-", noremap_silent)

vim.cmd([[map  +       <c-w><]])
vim.cmd([[map <leader>rt :%s/\\t/  /g<cr>]])
vim.cmd([[map <leader>a  :wa<cr>]])
vim.cmd([[map <leader>=  <c-w>=]])

-- Cross-platform yank/paste via temp file (avoids NFS clipboard issues)
local _vitmp = vim.g.cfg_vitmp_file or "/tmp/vitmp"
local _read_cmd = vim.g.cfg_is_windows and ("type " .. _vitmp) or ("cat " .. _vitmp)
vim.keymap.set("v", "<leader>y", ":w! " .. _vitmp .. "<CR>",    { noremap = true })
vim.keymap.set("n", "<leader>p", ":r! " .. _read_cmd .. "<CR>", { noremap = true })

vim.cmd([[map <leader># :windo set invnumber<CR>]])
vim.cmd([[noremap <c-@> za]])
vim.cmd([[noremap <BS> <<]])
vim.cmd([[map <leader>ms :mksession! ~/.session.vim<CR>]])
vim.cmd([[map <leader>ls :source ~/.session.vim<CR>]])
