local utils = require("global.utils")

local formatters_by_ft = {
    lua        = { "stylua" },
    python     = { "ruff_format", "ruff_organize_imports" },
    -- prettier is the vendored upstream npm package on loadout's bundled Node.js
    -- (no npm install). prettierd is deliberately NOT listed: it is a separate
    -- daemon package (fsouza/prettierd) we do not ship, and it only exists to
    -- speed up repeated formats -- the plain `prettier` below formats fine
    -- without a daemon, and `stop_after_first` keeps the list to one.
    javascript = { "prettier" },
    bash       = { "shfmt" },
    sh         = { "shfmt" },
    -- mdformat is a payload python-tool (pure-Python, py3-none-any), so it is on
    -- PATH in every @shared install and needs no npm/toolchain. This mapping
    -- used to name `rumdl`, which was never a loadout package -- conform found no
    -- binary and silently fell through to lsp_format = "fallback", i.e. the
    -- markdown filetype had no formatter at all. The `formatters.mdformat` entry
    -- below (--wrap keep) was already present and unused; this makes it live.
    markdown   = { "mdformat" },
    yaml       = { "yamlfmt" },
    json       = { "biome" },
    jsonc      = { "biome" },
    toml       = { "taplo" },
    tcl        = { "tclfmt" },
    sdc        = { "tclfmt" },
}

local formatters = {
    stylua   = { prepend_args = { "--indent-type", "Spaces", "--collapse-simple-statement", "Always" } },
    injected = { options = { ignore_errors = true } },
    yamlfmt  = { prepend_args = { "-quiet" }, options = { ignore_errors = true } },
    -- conform's built-in `prettier` feeds the buffer on stdin and passes
    -- `--stdin-filepath $FILENAME` (it does NOT use `-`, which prettier
    -- rejects), so prettier infers the parser from that filename's extension.
    prettier = { prepend_args = { "--tab-width", "4" } },
    -- `keep` = never reflow prose. conform's built-in mdformat runs `mdformat -`
    -- (stdin -> stdout); prepend_args land before that, so the effective command
    -- is `mdformat --wrap keep -`. Reflowing would rewrap the hand-wrapped
    -- paragraphs in this repo docs on every save.
    mdformat = { prepend_args = { "--wrap", "keep" } },
}

local spicefmt_cmd = vim.env.SPICEFMT_CMD or "spicefmt"
if utils.executable(spicefmt_cmd) then
    formatters_by_ft.spice = { "spicefmt" }
    formatters.spicefmt = {
        command = spicefmt_cmd,
        args    = {},
        stdin   = true,
    }
end

return {
    "stevearc/conform.nvim",
    lazy = true,
    cmd  = "ConformInfo",
    keys = {
        {
            "<leader>fi",
            function() require("conform").format({ formatters = { "injected" }, timeout_ms = 500 }) end,
            mode = { "n", "x" },
            desc = "Format Injected Langs",
        },
        {
            "<leader>f",
            function() require("conform").format({ timeout_ms = 500 }) end,
            mode = { "n", "x" },
            desc = "Format file",
        },
    },
    opts = {
        notify_on_error = false,
        default_format_opts = {
            timeout_ms = 500,
            async      = false,
            quiet      = false,
            lsp_format = "fallback",
        },
        formatters_by_ft = formatters_by_ft,
        formatters       = formatters,
    },
}
