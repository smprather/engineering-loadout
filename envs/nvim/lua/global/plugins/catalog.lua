-- Curated plugin catalog — disabled by default.
-- Users enable individual plugins in their user layer, e.g.:
--   return {{ "folke/flash.nvim", enabled = true, keys = { ... } }}
--
-- Offline: every catalog plugin is mirrored in the loadout's plugin stash (bare git
-- repos, shared read-only). init.lua points lazy's git.url_format at the stash, so
-- enabling one of these clones it FROM THE STASH -- no network, no github. Online
-- machines with no stash fall back to github exactly as upstream lazy does.
--
-- That is why no spec below pins `dir`: the old dir-pinning hack pointed at
-- a bundled directory that the installer never actually created, so enabling a catalog
-- plugin only ever worked online.

-- Flip to true to enable the whole catalog at once (normally you enable individual
-- plugins in your user layer).
local _CATALOG_ENABLED = false

return {

    -- ─── LSP & Dev Infrastructure ────────────────────────────────────────────

    {
        "neovim/nvim-lspconfig",
        enabled = _CATALOG_ENABLED,
        -- Enable in user layer and add server configs; see :h lspconfig-setup
    },

    {
        "williamboman/mason.nvim",
        enabled = _CATALOG_ENABLED,
        -- GUI package manager for LSP servers, DAP adapters, linters, formatters
        -- build = ":MasonUpdate",
    },

    {
        "williamboman/mason-lspconfig.nvim",
        enabled      = _CATALOG_ENABLED,
        dependencies = { "williamboman/mason.nvim", "neovim/nvim-lspconfig" },
    },

    {
        "j-hui/fidget.nvim",
        enabled = _CATALOG_ENABLED,
        opts    = {},
        -- LSP progress spinner in bottom-right; also replaces nvim-notify for LSP msgs
    },

    {
        "nvimtools/none-ls.nvim",
        enabled      = _CATALOG_ENABLED,
        dependencies = { "nvim-lua/plenary.nvim" },
        -- Inject non-LSP formatters/linters as LSP sources (successor to null-ls)
    },

    {
        "smjonas/inc-rename.nvim",
        enabled = _CATALOG_ENABLED,
        opts    = {},
        -- Incremental LSP rename with live preview: :IncRename <newname>
    },

    -- ─── Snippets ────────────────────────────────────────────────────────────

    {
        "L3MON4D3/LuaSnip",
        enabled      = _CATALOG_ENABLED,
        version      = "v2.*",
        build        = "make install_jsregexp",
        dependencies = { "rafamadriz/friendly-snippets" },
        -- Snippet engine; pairs with blink.cmp's luasnip source or nvim-cmp
    },

    -- ─── Fuzzy Finding ───────────────────────────────────────────────────────

    {
        "nvim-telescope/telescope.nvim",
        enabled      = _CATALOG_ENABLED,
        branch       = "0.1.x",
        dependencies = {
            "nvim-lua/plenary.nvim",
            { "nvim-telescope/telescope-fzf-native.nvim", build = "make" },
            { "nvim-telescope/telescope-ui-select.nvim" },
        },
        -- The canonical fuzzy finder; <leader>ff files, <leader>fg grep, etc.
    },

    {
        "ibhagwan/fzf-lua",
        enabled      = _CATALOG_ENABLED,
        dependencies = { "nvim-tree/nvim-web-devicons" },
        -- Faster fzf-based alternative to telescope; lower latency on large repos
    },

    -- ─── File Management ─────────────────────────────────────────────────────

    {
        "nvim-neo-tree/neo-tree.nvim",
        enabled      = _CATALOG_ENABLED,
        branch       = "v3.x",
        dependencies = {
            "nvim-lua/plenary.nvim",
            "nvim-tree/nvim-web-devicons",
            { "MunifTanjim/nui.nvim" },
        },
        -- Sidebar file explorer; <leader>e to toggle
    },

    {
        "stevearc/oil.nvim",
        enabled      = _CATALOG_ENABLED,
        dependencies = { "nvim-tree/nvim-web-devicons" },
        opts         = {},
        -- Edit filesystem like a buffer; - to open, rename/delete like text
    },

    -- ─── Git ─────────────────────────────────────────────────────────────────

    {
        "NeogitOrg/neogit",
        enabled      = _CATALOG_ENABLED,
        dependencies = {
            "nvim-lua/plenary.nvim",
            { "sindrets/diffview.nvim" },
            { "MunifTanjim/nui.nvim" },
        },
        opts = {},
        -- Magit-inspired git client; <leader>gg to open
    },

    {
        "sindrets/diffview.nvim",
        enabled = _CATALOG_ENABLED,
        -- Git diff/merge tool; :DiffviewOpen, :DiffviewFileHistory
    },

    {
        "kdheepak/lazygit.nvim",
        enabled      = _CATALOG_ENABLED,
        dependencies = { "nvim-lua/plenary.nvim" },
        -- Open lazygit in a floating terminal; requires lazygit binary
    },

    -- ─── Terminal ────────────────────────────────────────────────────────────

    {
        "akinsho/toggleterm.nvim",
        enabled = _CATALOG_ENABLED,
        version = "*",
        opts    = { open_mapping = [[<C-\>]] },
        -- Persistent terminal windows; <C-\> to toggle; multiple named terminals
    },

    -- ─── Navigation & Motion ─────────────────────────────────────────────────

    {
        "folke/flash.nvim",
        enabled = _CATALOG_ENABLED,
        opts    = {},
        -- Jump anywhere with labeled char search; replaces easymotion/sneak/leap
    },

    {
        "smoka7/hop.nvim",
        enabled = _CATALOG_ENABLED,
        version = "*",
        opts    = { keys = "etovxqpdygfblzhckisuran" },
        -- EasyMotion-style word/line/pattern jumping
    },

    {
        "christoomey/vim-tmux-navigator",
        enabled = _CATALOG_ENABLED,
        -- Seamless <C-h/j/k/l> pane navigation between nvim splits and tmux panes
    },

    {
        "ThePrimeagen/harpoon",
        enabled      = _CATALOG_ENABLED,
        branch       = "harpoon2",
        dependencies = { "nvim-lua/plenary.nvim" },
        -- Pin and instantly jump to up to 4 files per project
    },

    -- ─── Editing ─────────────────────────────────────────────────────────────

    {
        "kylechui/nvim-surround",
        enabled = _CATALOG_ENABLED,
        version = "*",
        opts    = {},
        -- Add/change/delete surrounding pairs; ys, cs, ds motions
    },

    {
        "windwp/nvim-autopairs",
        enabled = _CATALOG_ENABLED,
        opts    = {},
        -- Auto-close brackets/quotes; integrates with blink.cmp and nvim-cmp
    },

    {
        "numToStr/Comment.nvim",
        enabled = _CATALOG_ENABLED,
        opts    = {},
        -- gcc/gbc line/block comment; gc motion in visual mode
    },

    {
        "nvim-treesitter/nvim-treesitter-textobjects",
        enabled      = _CATALOG_ENABLED,
        dependencies = { "nvim-treesitter/nvim-treesitter" },
        -- TS-aware text objects: @function.outer, @class.inner, etc.
    },

    {
        "Wansmer/treesj",
        enabled      = _CATALOG_ENABLED,
        dependencies = { "nvim-treesitter/nvim-treesitter" },
        opts         = {},
        -- Split/join blocks (arrays, dicts, args) with <leader>m
    },

    {
        "monaqa/dial.nvim",
        enabled = _CATALOG_ENABLED,
        -- Enhanced <C-a>/<C-x>: cycles true/false, dates, hex, enums, etc.
    },

    {
        "mg979/vim-visual-multi",
        enabled = _CATALOG_ENABLED,
        branch  = "master",
        -- Multi-cursor; <C-n> to select next occurrence
    },

    {
        "mbbill/undotree",
        enabled = _CATALOG_ENABLED,
        -- Visual undo history tree; <leader>u to toggle
    },

    {
        "MagicDuck/grug-far.nvim",
        enabled = _CATALOG_ENABLED,
        opts    = {},
        -- Project-wide find-and-replace with live preview; <leader>sr
    },

    -- ─── Debug & Test ────────────────────────────────────────────────────────

    {
        "mfussenegger/nvim-dap",
        enabled = _CATALOG_ENABLED,
        -- Debug Adapter Protocol client; requires per-language adapter config
    },

    {
        "rcarriga/nvim-dap-ui",
        enabled      = _CATALOG_ENABLED,
        dependencies = {
            "mfussenegger/nvim-dap",
            { "nvim-neotest/nvim-nio" },
        },
        -- UI panels for DAP (breakpoints, variables, call stack, REPL)
    },

    {
        "theHamsta/nvim-dap-virtual-text",
        enabled      = _CATALOG_ENABLED,
        dependencies = { "mfussenegger/nvim-dap", "nvim-treesitter/nvim-treesitter" },
        opts         = {},
        -- Inline variable values during DAP debug sessions
    },

    {
        "nvim-neotest/neotest",
        enabled      = _CATALOG_ENABLED,
        dependencies = {
            "nvim-lua/plenary.nvim",
            "nvim-treesitter/nvim-treesitter",
            { "nvim-neotest/nvim-nio" },
        },
        -- Test runner framework; add language adapters (neotest-python, etc.)
    },

    -- ─── Color Schemes ───────────────────────────────────────────────────────

    {
        "catppuccin/nvim",
        enabled = _CATALOG_ENABLED,
        name    = "catppuccin",
        -- Pastel colorscheme; flavours: latte, frappe, macchiato, mocha
    },

    {
        "rebelot/kanagawa.nvim",
        enabled = _CATALOG_ENABLED,
        -- Japanese wave-inspired dark theme; kanagawa-wave, kanagawa-dragon
    },

    {
        "ellisonleao/gruvbox.nvim",
        enabled = _CATALOG_ENABLED,
        opts    = {},
        -- Classic Gruvbox in pure Lua with treesitter support
    },

    {
        "sainnhe/everforest",
        enabled = _CATALOG_ENABLED,
        -- Green-tinted nature theme; soft/medium/hard contrast variants
    },

    -- ─── UI & Appearance ─────────────────────────────────────────────────────

    {
        "folke/noice.nvim",
        enabled      = _CATALOG_ENABLED,
        dependencies = {
            { "MunifTanjim/nui.nvim" },
            { "rcarriga/nvim-notify" },
        },
        -- Overhauls cmdline, messages, and popupmenu with floating UI
    },

    {
        "stevearc/aerial.nvim",
        enabled      = _CATALOG_ENABLED,
        dependencies = { "nvim-treesitter/nvim-treesitter", "nvim-tree/nvim-web-devicons" },
        opts         = {},
        -- Symbol outline / code navigation sidebar; <leader>a
    },

    {
        "kevinhwang91/nvim-ufo",
        enabled      = _CATALOG_ENABLED,
        dependencies = {
            { "kevinhwang91/promise-async" },
        },
        opts = { provider_selector = function() return { "treesitter", "indent" } end },
        -- Modern fold provider using LSP/treesitter; zR/zM/za to open/close
    },

    {
        "petertriho/nvim-scrollbar",
        enabled = _CATALOG_ENABLED,
        opts    = {},
        -- Scrollbar with search result and diagnostic markers
    },

    {
        "HiPhish/rainbow-delimiters.nvim",
        enabled = _CATALOG_ENABLED,
        -- TS-powered rainbow bracket colorization
    },

    {
        "lukas-reineke/virt-column.nvim",
        enabled = _CATALOG_ENABLED,
        opts    = { char = "│" },
        -- Virtual colorcolumn that doesn't highlight the whole column
    },

    {
        "akinsho/bufferline.nvim",
        enabled      = _CATALOG_ENABLED,
        version      = "*",
        dependencies = { "nvim-tree/nvim-web-devicons" },
        opts         = {},
        -- Buffer tabs at top of screen with LSP diagnostics and close buttons
    },

    {
        "norcalli/nvim-colorizer.lua",
        enabled = _CATALOG_ENABLED,
        -- Inline hex/rgb/hsl color previews; :ColorizerToggle
    },

    -- ─── Productivity ────────────────────────────────────────────────────────

    {
        "folke/persistence.nvim",
        enabled = _CATALOG_ENABLED,
        opts    = {},
        -- Auto-save and restore sessions per directory
    },

    {
        "ahmedkhalf/project.nvim",
        enabled = _CATALOG_ENABLED,
        main    = "project_nvim",
        opts    = {},
        -- Auto-detects project root (git, .svn, Makefile, etc.) and cd's to it
    },

    {
        "folke/twilight.nvim",
        enabled = _CATALOG_ENABLED,
        opts    = {},
        -- Dim inactive code sections; pairs well with zen-mode
    },

    {
        "folke/zen-mode.nvim",
        enabled      = _CATALOG_ENABLED,
        dependencies = { "folke/twilight.nvim" },
        opts         = {},
        -- Distraction-free writing/coding; <leader>z to toggle
    },

}
