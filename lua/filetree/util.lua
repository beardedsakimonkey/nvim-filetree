local api = vim.api

local M = {}

local function noremap(mode, buf, mappings)
    for lhs, rhs in pairs(mappings) do
        api.nvim_buf_set_keymap(buf, mode, lhs, rhs, {
            nowait = true,
            noremap = true,
            silent = true,
        })
    end
end

M.nnoremap = function(buf, mappings)
    noremap('n', buf, mappings)
end

M.xnoremap = function(buf, mappings)
    noremap('x', buf, mappings)
end

M.log = function(...)
    -- TODO: vim.inspect
    local msg = table.concat({...}, ' ')
    api.nvim_out_write(string.format('[filetree] %s\n', msg))
end

M.key = function(win)
    return tostring(win)
end

M.find = function(list, predicate)
    for i, item in ipairs(list) do
        if predicate(item) then
            return item, i
        end
    end
    return nil
end

M.join = function(...)
    local path = table.concat({...}, '/')
    local ret = path:gsub('/+', '/')
    return ret
end

return M
