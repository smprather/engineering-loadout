return {
    cmd = { "ty", "server" },
    filetypes = { "python" },
    root_dir = function(bufnr, on_dir)
        on_dir(vim.fs.root(bufnr, { ".git", "pyproject.toml" }))
    end,
}
