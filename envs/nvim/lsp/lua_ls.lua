local root_files = {
    ".luarc.json",
    ".luarc.jsonc",
    ".luacheckrc",
    ".stylua.toml",
    "stylua.toml",
    "selene.toml",
    "selene.yml",
    ".git",
    ".",
}

local is_windows = vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1
local username = os.getenv("USER") or os.getenv("USERNAME") or "nvimuser"
local function tmp_root()
    local tmp = os.getenv("TMPDIR")
    if tmp == nil or tmp == "" then return nil end
    tmp = tmp:gsub("/+$", "")
    if tmp == "" then return "/" end
    return tmp
end
local env_tmp_root = tmp_root()
-- Logs go under a per-user scratch dir only when it is private to us
-- (global.paths.private_dir); otherwise under stdpath("log").
local lsp_log_dir
if is_windows then
    lsp_log_dir = vim.fn.expand("$TEMP") .. "\\lua_language_server"
else
    local shm_root = os.getenv("LOADOUT_CFG_SHM_DIR")
    if shm_root == nil or shm_root == "" then shm_root = "/dev/shm" end
    local scratch
    if env_tmp_root ~= nil then
        scratch = env_tmp_root
    elseif vim.fn.isdirectory(shm_root) == 1 then
        scratch = shm_root
    else
        scratch = "/tmp"
    end
    local mine = require("global.paths").private_dir(scratch .. "/" .. username)
    lsp_log_dir = (mine or vim.fn.stdpath("log")) .. "/lua_language_server"
end

return {
    cmd = { "lua-language-server", "--logpath=" .. lsp_log_dir },
    filetypes = { "lua" },
    root_markers = root_files,
    settings = {
        Lua = {
            runtime = {
                version = "LuaJIT",
                path = { "lua/?.lua", "lua/?/init.lua" },
            },
            diagnostics = {
                globals = { "vim" },
                disable = { "missing-fields" },
            },
            telemetry = {
                enable = false,
            },
            workspace = {
                checkThirdParty = false,
                library = {
                    vim.env.VIMRUNTIME,
                },
            },
            completion = {
                callSnippet = "Replace",
            },
        },
    },
}
