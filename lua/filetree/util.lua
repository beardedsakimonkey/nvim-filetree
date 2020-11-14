local vim = vim
local api = vim.api
local uv = vim.loop

local function list_dir(path)
    local userdata = assert(uv.fs_opendir(path, nil, 1000))
    local dir, fail = uv.fs_readdir(userdata)
    assert(not fail)
    dir = dir or {}
    assert(uv.fs_closedir(userdata))
    table.sort(dir, function (a, b)
        if a.type == b.type then
            return a.name < b.name
        else
            return a.type == 'directory'
        end
    end)
    return dir
end

local function noremap(mode, buf, mappings)
    for lhs, rhs in pairs(mappings) do
        vim.api.nvim_buf_set_keymap(buf, mode, lhs, rhs, {
            nowait = true,
            noremap = true,
            silent = true,
        })
    end
end

local function nnoremap(buf, mappings)
    noremap('n', buf, mappings)
end

local function xnoremap(buf, mappings)
    noremap('x', buf, mappings)
end

local function log(...)
    -- TODO: vim.inspect
    local msg = table.concat({...}, ' ')
    vim.cmd(string.format('echom "[filetree]" %q', msg))
end

local function key(win)
    return tostring(win)
end

local function time_fn(fn)
    return fn
    -- local timed_fn = function(...)
    --     local t1 = os.clock()
    --     fn(...)
    --     local t2 = os.clock()
    --     print((t2 - t1) * 1000 .. ' ms')
    -- end
    -- return timed_fn
end

local function find(list, predicate)
    for i, item in ipairs(list) do
        if predicate(item) then
            return item, i
        end
    end
    return nil
end

local function join(...)
    local path = table.concat({...}, '/')
    local ret = path:gsub('/+', '/')
    return ret
end

local function keys(table)
    local ret = {}
    for k, _ in ipairs(table) do
        ret[k] = false
    end
    return ret
end

local function is_valid_filename(filename)
    return filename:len() > 0 and not filename:find('/')
end

return {
    -- luv
    list_dir = list_dir,
    -- vim
    nnoremap = nnoremap,
    xnoremap = xnoremap,
    log = log,
    -- lua
    key = key,
    time_fn = time_fn,
    find = find,
    join = join,
    keys = keys,
    is_valid_filename = is_valid_filename,
}
