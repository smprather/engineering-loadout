local M = {}

function M.buf_smaller_than(threshold_mb)
    local filename = vim.api.nvim_buf_get_name(0)
    if filename == "" then return true end
    local filesize_bytes = vim.fn.getfsize(filename)
    if filesize_bytes == -1 then return true end
    return filesize_bytes < threshold_mb * 1024 * 1024
end

return M
