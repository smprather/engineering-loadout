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
local lsp_log_dir
if is_windows then
    lsp_log_dir = vim.fn.expand("$TEMP") .. "\\lua_language_server"
elseif env_tmp_root ~= nil then
    lsp_log_dir = env_tmp_root .. "/" .. username .. "/lua_language_server"
elseif vim.fn.isdirectory("/dev/shm") == 1 then
    lsp_log_dir = "/dev/shm/" .. username .. "/lua_language_server"
else
    lsp_log_dir = "/tmp/" .. username .. "/lua_language_server"
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
