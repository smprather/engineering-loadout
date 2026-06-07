-- Feature toggles (override in corp/site/project/user config.lua)
vim.g.cfg_enable_lsp        = true
vim.g.cfg_enable_treesitter = true
vim.g.cfg_enable_completion = true
vim.g.cfg_enable_git        = true
vim.g.cfg_enable_format     = true

-- Appearance
vim.g.cfg_colorscheme = "tokyonight-night"
vim.g.have_nerd_font  = true

-- Editor behavior
vim.g.cfg_tab_width = 4

-- Shared source locations
vim.g.cfg_nvim_plugin_catalog_dir =
    os.getenv("LOADOUT_CFG_NVIM_PLUGIN_CATALOG_DIR")
    or (vim.fn.stdpath("data") .. "/loadout/vendor/catalog-plugins")

-- DPC (read-only/offline machine) detection via /proc/mounts anvil_release overlay
vim.g.cfg_dpc = (function()
    local file = io.open("/proc/mounts", "r")
    if not file then return false end
    for line in file:lines() do
        if string.match(line, "anvil_release.*ro,") then
            file:close()
            return true
        end
    end
    file:close()
    return false
end)()

-- Platform detection
local _is_windows = vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1
local _username   = os.getenv("USER") or os.getenv("USERNAME") or "nvimuser"

local _swap_dir, _vitmp_file
if _is_windows then
    _swap_dir   = vim.fn.expand("$TEMP") .. "\\nvim\\swap"
    _vitmp_file = vim.fn.expand("$TEMP") .. "\\nvim_vitmp"
elseif vim.fn.isdirectory("/dev/shm") == 1 then
    _swap_dir   = "/dev/shm/" .. _username .. "/vim"
    _vitmp_file = "/dev/shm/" .. _username .. "/vitmp"
else
    _swap_dir   = "/tmp/" .. _username .. "/vim"
    _vitmp_file = "/tmp/vitmp_" .. _username
end
vim.fn.mkdir(_swap_dir, "p")

vim.g.cfg_swap_dir   = _swap_dir
vim.g.cfg_vitmp_file = _vitmp_file
vim.g.cfg_is_windows = _is_windows
