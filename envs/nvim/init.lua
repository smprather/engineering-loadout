-- Phase 0: Must be set before lazy.nvim and before any plugin spec evaluates them.
vim.g.mapleader      = " "
vim.g.maplocalleader = " "
vim.g.loaded_netrw       = 1
vim.g.loaded_netrwPlugin = 1

local LAYERS = { "global", "corp", "site", "team", "project", "user" }

local function layer_dir(layer)
    return vim.fn.stdpath("config") .. "/lua/" .. layer
end
local function source_layer(layer, mod)
    -- A missing layer module is normal (most layers are user-created); any
    -- other failure is a broken layer file and must not vanish silently.
    local name = layer .. "." .. mod
    local ok, err = pcall(require, name)
    if not ok and not tostring(err):find("module '" .. name .. "' not found", 1, true) then
        vim.schedule(function()
            vim.notify(("loadout layer '%s' failed to load:\n%s"):format(name, err), vim.log.levels.WARN)
        end)
    end
end

-- Phase 1: Config variables — global defaults, then corp/site/project/user override.
for _, layer in ipairs(LAYERS) do
    source_layer(layer, "config")
end

-- Phase 2: Bootstrap lazy.nvim (offline-safe: skips plugin setup if git clone fails).
--
-- With an offline stash installed, lazy.nvim is cloned FROM THE STASH and every plugin
-- resolves through it (see loadout_git_opts below) -- no github, no network. Without a
-- stash, this is the stock upstream bootstrap and online installs behave as before.
local loadout_paths = require("global.paths")
local loadout_stash = loadout_paths.stash()
loadout_paths.ensure_git()   -- private git for nvim only; never on the user's PATH

local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
local loadout_plugins_enabled = true
if not (vim.uv or vim.loop).fs_stat(lazypath) then
    local lazy_url = loadout_stash
        and (loadout_stash .. "/folke/lazy.nvim.git")
        or "https://github.com/folke/lazy.nvim.git"
    local clone = { "git", "clone", "--filter=blob:none", lazy_url, lazypath }
    if not loadout_stash then
        table.insert(clone, 4, "--branch=stable")   -- upstream only; a local mirror has no such branch
    end
    local out = vim.fn.system(clone)
    if vim.v.shell_error ~= 0 then
        loadout_plugins_enabled = false
        vim.g.loadout_lazy_bootstrap_error = out
        vim.api.nvim_create_autocmd("VimEnter", {
            once     = true,
            callback = function()
                vim.notify("lazy.nvim unavailable; plugin setup skipped", vim.log.levels.WARN)
            end,
        })
    end
end
vim.g.loadout_plugins_enabled = loadout_plugins_enabled

-- Phase 3: Collect plugin specs from all layers that have a plugins/ dir.
if loadout_plugins_enabled then
    vim.opt.rtp:prepend(lazypath)

    local specs = {}
    for _, layer in ipairs(LAYERS) do
        if vim.fn.isdirectory(layer_dir(layer) .. "/plugins") == 1 then
            table.insert(specs, { import = layer .. ".plugins" })
        end
    end

    -- Point lazy at the offline stash when one exists: plugins are then cloned from
    -- local bare mirrors and `:Lazy update` fetches from them. url_format receives the
    -- plugin's "owner/repo" shorthand, which is exactly how the stash is laid out.
    -- filter=false is load-bearing, not a preference. lazy defaults to
    -- `--filter=blob:none` (a partial clone), which git CANNOT serve from a shallow
    -- local mirror -- the clone hangs forever, and the stash's catalog mirrors are
    -- shallow (full history for all 55 would triple the payload). A partial clone buys
    -- nothing from a local path anyway: git hardlinks the objects instead of copying.
    local loadout_git_opts = loadout_stash
        and { url_format = loadout_stash .. "/%s.git", filter = false }
        or nil

    require("lazy").setup(specs, {
        git = loadout_git_opts,
        checker = {
            enabled = not vim.g.cfg_dpc,
            notify  = not vim.g.cfg_dpc,
        },
        ui = {
            icons = vim.g.have_nerd_font and {} or {
                cmd     = "⌘", config  = "🛠", event   = "📅", ft      = "📂",
                init    = "⚙", keys    = "🗝", plugin  = "🔌", runtime = "💻",
                require = "🌙", source  = "📄", start   = "🚀", task    = "📌",
                lazy    = "💤 ",
            },
        },
        performance = {
            rtp = {
                disabled_plugins = {
                    "matchit", "matchparen", "netrwPlugin",
                    "tarPlugin", "tohtml", "tutor", "zipPlugin",
                },
            },
        },
    })
else
    vim.api.nvim_create_user_command("Lazy", function()
        vim.notify("lazy.nvim unavailable; plugin setup skipped", vim.log.levels.WARN)
    end, {})
end

-- Phase 4: Behavior — options, keymaps, autocmds, LSP (global first, then user overrides).
for _, layer in ipairs(LAYERS) do
    source_layer(layer, "init")
end

-- vim: tabstop=4 softtabstop=4 shiftwidth=4 expandtab
