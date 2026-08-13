-- Resolve nvim data dirs across a split shared/per-user deployment.
--
-- The loadout can be deployed two ways:
--   * everything in $HOME              (a normal `install @engineering-loadout`)
--   * a shared read-only tree + a per-user $HOME
--     (`install @shared-all --dest-dir <tree>` then `install @envs` with
--      LOADOUT_CFG_SHARED_PREFIX=<tree>/local)
--
-- nvim always resolves its data from stdpath("data") = $HOME/.local/share/nvim, so
-- anything installed into the shared tree is invisible to it unless we look there
-- explicitly. That is exactly how the air-gapped deployment ended up with
-- "lazy.nvim unavailable; plugin setup skipped": the plugins were installed, just
-- into the shared tree, where nvim never looked.
--
-- Rule: prefer the user's own copy, fall back to the shared tree. That keeps large
-- read-only payloads (the 251 MB treesitter parser set, the plugin catalog) shared
-- once instead of copied per user, while letting any user override a directory
-- simply by having their own.

local M = {}

local shared = os.getenv("LOADOUT_CFG_SHARED_PREFIX")

--- Resolve a path under nvim's data dir, preferring $HOME then the shared tree.
--- @param rel string  e.g. "tree-sitter-parsers" or "loadout/vendor/nvim-treesitter"
--- @return string     absolute path (the $HOME one when neither exists)
function M.data(rel)
    local home_path = vim.fn.stdpath("data") .. "/" .. rel
    if vim.fn.isdirectory(home_path) == 1 then
        return home_path
    end
    if shared and shared ~= "" then
        local shared_path = shared .. "/share/nvim/" .. rel
        if vim.fn.isdirectory(shared_path) == 1 then
            return shared_path
        end
    end
    return home_path
end

--- True when `rel` resolves to a directory that actually exists somewhere.
function M.has(rel)
    return vim.fn.isdirectory(M.data(rel)) == 1
end

--- Resolve a FILE under the loadout's share/ root, user-copy-first.
---
--- Same user-then-shared rule as M.data, but for payloads that are not nvim's
--- own -- e.g. taplo's offline JSON Schema catalog at share/taplo/schemas/. Those
--- live under the install prefix, not under stdpath("data"), so M.data cannot
--- reach them.
--- @param rel string  e.g. "taplo/schemas/catalog.json"
--- @return string|nil absolute path, or nil when the file exists in neither tree
function M.share(rel)
    local candidates = { vim.fn.expand("~/.local/share/") .. rel }
    if shared and shared ~= "" then
        table.insert(candidates, shared .. "/share/" .. rel)
    end
    for _, path in ipairs(candidates) do
        if vim.fn.filereadable(path) == 1 then
            return path
        end
    end
    return nil
end

--- The offline plugin stash (bare git mirrors), or nil when there is none.
--- With a stash present, lazy clones plugins FROM IT instead of github, and
--- :Lazy update fetches from it -- so plugin updates work with no network.
function M.stash()
    local dir = M.data("loadout/vendor/plugin-stash")
    if vim.fn.isdirectory(dir) == 1 then
        return dir
    end
    return nil
end

--- Make a git available to nvim's subprocesses WITHOUT touching the user's PATH.
---
--- lazy shells out to `git`. The loadout never puts its own git on the user's PATH: a
--- loadout git would shadow the corp git and silently break its subcommands,
--- credential helpers and git-lfs (the same reason the openssh package ships `ssh10`
--- and leaves /usr/bin/ssh alone). So if -- and only if -- the system has no git, we
--- prepend the private one (the optional `git-nvim` package) to *nvim's* PATH.
--- The user's shell is untouched.
function M.ensure_git()
    if vim.fn.executable("git") == 1 then
        return true
    end
    for _, root in ipairs({ vim.fn.expand("~/.local"), os.getenv("LOADOUT_CFG_SHARED_PREFIX") or "" }) do
        if root ~= "" then
            local bin = root .. "/lib/loadout-git/bin"
            if vim.fn.executable(bin .. "/git") == 1 then
                vim.env.PATH = bin .. ":" .. vim.env.PATH
                return true
            end
        end
    end
    return false
end

return M
