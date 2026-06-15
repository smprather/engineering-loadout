-- Aggregator for global plugin specs.
-- Returns a flat list of plugin specs by requiring all files in this
-- directory (except init.lua). Honor `vim.g.loadout_user_plugins_only`
-- to allow users to completely replace the bundled plugin set.

if vim.g.loadout_user_plugins_only then
    return {}
end

local M = {}

-- Determine directory of this file and glob for .lua files.
local this_file = debug.getinfo(1, 'S').source:sub(2)
local dir = vim.fn.fnamemodify(this_file, ':h')
local files = vim.fn.globpath(dir, '*.lua', 0, 1)
if type(files) == 'string' then
    files = { files }
end

table.sort(files)
for _, f in ipairs(files) do
    if not f:match('/init%.lua$') then
        local name = vim.fn.fnamemodify(f, ':t'):gsub('%.lua$', '')
        local mod = 'global.plugins.' .. name
        local ok, rv = pcall(require, mod)
        if ok and type(rv) == 'table' then
            for _, v in ipairs(rv) do
                table.insert(M, v)
            end
        end
    end
end

return M
