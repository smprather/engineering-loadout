-- Resolve nvim data dirs across a split shared/per-user deployment.
--
-- The loadout can be deployed two ways:
--   * a default install: the shared tree at the install root (default
--     ~/.local/share/loadout) plus per-user config under $HOME
--     (`install @shared-all` then `install @envs-all`)
--   * a shared read-only tree + a per-user $HOME
--     (`install @shared-all --dest-dir <tree>` then `install @envs` with
--      LOADOUT_CFG_SHARED_PREFIX=<tree> -- the tree is a plain prefix, with no
--      `local/` level)
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
--
-- The shared root comes from LOADOUT_CFG_SHARED_PREFIX when the shell baked it,
-- but `env-nvim` alone does not bake it. So also derive the root from the running
-- nvim binary (<root>/bin/nvim -> <root> when <root>/share/nvim exists). Without
-- that fallback, a user who just puts the shared <root>/bin on PATH falls back to
-- github for every plugin -- and fails offline even though the shared stash is
-- right there.

local M = {}

--- All shared install roots, most explicit first.
--- @return string[]
local function shared_roots()
    local roots = {}
    local env = os.getenv("LOADOUT_CFG_SHARED_PREFIX")
    if env and env ~= "" then
        table.insert(roots, env)
    end

    local prog = vim.v.progpath or ""
    if prog ~= "" then
        local exe = vim.fn.resolve(vim.fn.fnamemodify(prog, ":p"))
        if vim.fn.fnamemodify(exe, ":t") == "nvim" then
            local bin = vim.fn.fnamemodify(exe, ":h")
            local root = vim.fn.fnamemodify(bin, ":h")
            -- <root>/share/nvim is the nvim package's install_to outside HOME
            -- (plain prefix) or inside a HOME root (<home>/.local).
            if vim.fn.isdirectory(root .. "/share/nvim") == 1 then
                local seen = false
                for _, known in ipairs(roots) do
                    if known == root then
                        seen = true
                    end
                end
                if not seen then
                    table.insert(roots, root)
                end
            end
        end
    end
    return roots
end

--- Return `path` when it is a directory only this user can write, else nil.
--- Created 0700 when absent; otherwise it must be a real directory (never a
--- symlink) owned by us that no one else could have written, tightened to
--- 0700. Group write with our PRIVATE group (RHEL UPG umask 002 leaves 0775)
--- is ours to remove; other write, or group write with a shared group, is
--- refused and left alone. Same rule as loadout_private_dir in envs/bash/functions.sh:
--- the temp root and /dev/shm are world-writable and the per-user names under
--- them are predictable, so a co-tenant can create them first and would then
--- receive swap files (buffer contents) and logs.
--- @param path string
--- @return string|nil
function M.private_dir(path)
    if not path or path == "" then return nil end
    local uv = vim.uv or vim.loop
    if not uv.fs_lstat(path) then
        pcall(vim.fn.mkdir, path, "p", tonumber("700", 8))
    end
    local st = uv.fs_lstat(path)
    if not st or st.type ~= "directory" or st.uid ~= uv.getuid() then return nil end
    local perm = st.mode % 512
    if perm == tonumber("700", 8) then return path end
    local group, other = math.floor(perm / 8) % 8, perm % 8
    -- Other write: anyone could have planted content -> refuse, leave it alone.
    if math.floor(other / 2) % 2 == 1 then return nil end
    -- Group write is ours to remove only with our private (UPG) group.
    -- luv has no group lookup, so ask coreutils stat by absolute path (PATH
    -- may hold nvim alone); no stat, or any failure, refuses.
    if math.floor(group / 2) % 2 == 1 then
        local pw = uv.os_get_passwd()
        local stat_bin = vim.fn.executable("/usr/bin/stat") == 1 and "/usr/bin/stat"
            or vim.fn.executable("/bin/stat") == 1 and "/bin/stat"
            or nil
        if not pw or not stat_bin then return nil end
        local ok, out = pcall(vim.fn.systemlist, { stat_bin, "-c", "%G", path })
        if not ok or vim.v.shell_error ~= 0 or (out or {})[1] ~= pw.username then return nil end
    end
    if not uv.fs_chmod(path, tonumber("700", 8)) then return nil end
    return path
end

--- Resolve a path under nvim's data dir, preferring $HOME then the shared tree.
--- @param rel string  e.g. "tree-sitter-parsers" or "loadout/vendor/nvim-treesitter"
--- @return string     absolute path (the $HOME one when neither exists)
function M.data(rel)
    local home_path = vim.fn.stdpath("data") .. "/" .. rel
    if vim.fn.isdirectory(home_path) == 1 then
        return home_path
    end
    for _, root in ipairs(shared_roots()) do
        local shared_path = root .. "/share/nvim/" .. rel
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
    for _, root in ipairs(shared_roots()) do
        table.insert(candidates, root .. "/share/" .. rel)
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
--- LOADOUT_CFG_NVIM_PLUGIN_STASH_DIR / vim.g.cfg_nvim_plugin_stash_dir wins when
--- it points at an existing directory (documented override).
function M.stash()
    local override = vim.g.cfg_nvim_plugin_stash_dir
    if type(override) == "string" and override ~= "" and vim.fn.isdirectory(override) == 1 then
        return override
    end
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
    local roots = { vim.fn.expand("~/.local") }
    for _, root in ipairs(shared_roots()) do
        table.insert(roots, root)
    end
    for _, root in ipairs(roots) do
        local bin = root .. "/lib/loadout-git/bin"
        if vim.fn.executable(bin .. "/git") == 1 then
            -- The private git is an EL8 build, so it needs the loadout's
            -- OpenSSL 1.1 (libcrypto.so.1.1) on hosts that only ship OpenSSL 3
            -- (Arch/Debian). Add the install root's lib dirs for nvim's
            -- subprocesses only; the user's shell is untouched.
            local libdirs = {}
            for _, dir in ipairs({ root .. "/lib64", root .. "/lib" }) do
                if vim.fn.isdirectory(dir) == 1 then
                    table.insert(libdirs, dir)
                end
            end
            if #libdirs > 0 then
                local existing = vim.env.LD_LIBRARY_PATH
                vim.env.LD_LIBRARY_PATH =
                    table.concat(libdirs, ":") .. (existing and existing ~= "" and (":" .. existing) or "")
            end
            vim.env.PATH = bin .. ":" .. vim.env.PATH
            return true
        end
    end
    return false
end

return M
