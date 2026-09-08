-- Feature toggles (override in user/config.lua)
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
-- The offline plugin stash: bare git mirrors, read-only, shared once per tree. lazy
-- clones plugins from it and :Lazy update fetches from it, so plugin updates work with
-- no network. Resolved user-copy-first, shared-tree-second (see global/paths.lua).
vim.g.cfg_nvim_plugin_stash_dir =
    os.getenv("LOADOUT_CFG_NVIM_PLUGIN_STASH_DIR")
    or require("global.paths").data("loadout/vendor/plugin-stash")

-- Online/offline verdict for plugins: anything that would reach the network
-- (lazy's update checker, plugin installs, LSP bootstrap) consults cfg_online
-- and stays quiet when it is false, instead of stalling on timeouts.
--
-- Resolution order, cheapest first:
--   1. LOADOUT_ONLINE env var -- set once per login by the bash/zsh/tcsh
--      configs (loadout_detect_online_cached), inherited by nvim launched
--      from any loadout shell.
--   2. The shared verdict cache ${XDG_RUNTIME_DIR:-/tmp}/.loadout-net/
--      detect-<md5> -- written by the same shell configs; covers nvim
--      launched from a GUI where no shell rc ran. Newest file wins (host
--      lists can differ per user override).
--   3. A live probe of LOADOUT_CFG_ONLINE_DETECT_HOSTS (default
--      github.com/raw.githubusercontent.com/pypi.org :443) with the same
--      0.15s timeout the shell probe uses. Backup only -- paid once per
--      nvim start, never cached here.
--   4. Offline. The safe default: plugins never attempt network, so no
--      timeout delays on air-gapped boxes.
local function _cached_online_verdict()
    local dir = (os.getenv("XDG_RUNTIME_DIR") or "/tmp") .. "/.loadout-net"
    local files = vim.fn.glob(dir .. "/detect-*", false, true)
    local newest, newest_mtime = nil, -1
    for _, f in ipairs(files) do
        local mtime = vim.fn.getftime(f)
        if mtime > newest_mtime then
            newest, newest_mtime = f, mtime
        end
    end
    if newest then
        local verdict = vim.fn.readfile(newest)[1]
        if verdict == "1" then return true end
        if verdict == "0" then return false end
    end
    return nil
end

local function _live_online_probe()
    local hosts = os.getenv("LOADOUT_CFG_ONLINE_DETECT_HOSTS")
        or "github.com:443 raw.githubusercontent.com:443 pypi.org:443"
    local t = os.getenv("LOADOUT_CFG_ONLINE_DETECT_TIMEOUT") or "0.15"
    for hp in hosts:gmatch("%S+") do
        local host, port = hp:match("([^:]+):(%d+)")
        if host and port then
            vim.fn.system(string.format(
                "timeout %s bash -c 'echo >/dev/tcp/%s/%s' 2>/dev/null", t, host, port))
            if vim.v.shell_error == 0 then return true end
        end
    end
    return false
end

vim.g.cfg_online = (function()
    local env = os.getenv("LOADOUT_ONLINE")
    if env == "1" then return true end
    if env == "0" then return false end
    local cached = _cached_online_verdict()
    if cached ~= nil then return cached end
    return _live_online_probe()
end)()

-- Offline machine detection: a read-only overlay mount (e.g. an air-gapped
-- deployment's read-only shared filesystem) means plugin update checks would
-- only fail or stall, so they are disabled up front.
--
-- Compatibility: cfg_dpc was the pre-2026-09-08 name. A user override set
-- before the rename must keep working; the new name wins when both are set.
if vim.g.cfg_dpc ~= nil then
    vim.g.cfg_offline = vim.g.cfg_dpc
elseif vim.g.cfg_offline == nil then
    vim.g.cfg_offline = (function()
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
end

-- Platform detection
local _is_windows = vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1
local _username   = os.getenv("USER") or os.getenv("USERNAME") or "nvimuser"
local function _tmp_root()
    local tmp = os.getenv("TMPDIR")
    if tmp == nil or tmp == "" then return nil end
    tmp = tmp:gsub("/+$", "")
    if tmp == "" then return "/" end
    return tmp
end
local _env_tmp_root = _tmp_root()

local _swap_dir, _vitmp_file
if _is_windows then
    _swap_dir   = vim.fn.expand("$TEMP") .. "\\nvim\\swap"
    _vitmp_file = vim.fn.expand("$TEMP") .. "\\nvim_vitmp"
elseif _env_tmp_root ~= nil then
    _swap_dir   = _env_tmp_root .. "/" .. _username .. "/vim"
    _vitmp_file = _env_tmp_root .. "/vitmp_" .. _username
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
