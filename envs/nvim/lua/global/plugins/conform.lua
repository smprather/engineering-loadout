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
        formatters_by_ft = {
            lua        = { "stylua" },
            python     = { "ruff_format", "ruff_organize_imports" },
            javascript = { "prettierd", "prettier", stop_after_first = true },
            bash       = { "shfmt" },
            sh         = { "shfmt" },
            markdown   = { "rumdl" },
            yaml       = { "yamlfmt" },
            json       = { "biome" },
            jsonc      = { "biome" },
            toml       = { "taplo" },
        },
        formatters = {
            stylua   = { prepend_args = { "--indent-type", "Spaces", "--collapse-simple-statement", "Always" } },
            injected = { options = { ignore_errors = true } },
            yamlfmt  = { prepend_args = { "-quiet" }, options = { ignore_errors = true } },
            prettier = { prepend_args = { "--tab-width", "4" } },
            mdformat = { prepend_args = { "--wrap", "keep" } },
        },
    },
}
