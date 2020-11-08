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

local function create_win()
    local equalalways_save = vim.o.equalalways
    local eadirection_save = vim.o.eadirection
    vim.o.eadirection = 'ver'
    vim.o.equalalways = false
    vim.cmd(api.nvim_win_get_width(0) .. 'vnew')
    vim.o.equalalways = equalalways_save
    vim.o.eadirection = eadirection_save
    local win = vim.fn.win_getid()

    local buf = vim.fn.bufnr()
    assert(buf ~= -1)
    -- TODO: this should go in plugin/ so it can be overridden
    api.nvim_buf_set_option(buf, 'filetype', 'filetree')
    api.nvim_win_set_option(win, 'cursorline', true)
    api.nvim_win_set_option(win, 'foldenable', false)
    api.nvim_win_set_option(win, 'number', false)
    api.nvim_buf_set_option(buf, 'buftype', 'nofile')
    api.nvim_buf_set_option(buf, 'modifiable', false)

    api.nvim_win_set_option(win, 'list', true)
    api.nvim_win_set_option(win, 'listchars', 'tab:| ')
    api.nvim_buf_set_option(buf, 'expandtab', false)
    api.nvim_buf_set_option(buf, 'tabstop', 8)
    api.nvim_buf_set_option(buf, 'shiftwidth', 8)
    api.nvim_buf_set_option(buf, 'softtabstop', 0)
    return buf, win
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
    local msg = table.concat({...}, ' ')
    vim.cmd(string.format('echom "[filetree]: " %q', msg))
end

local function key(win)
    return tostring(win)
end

local function time_fn(fn)
    local timed_fn = function(...)
        local t1 = os.clock()
        fn(...)
        local t2 = os.clock()
        print((t2 - t1) * 1000 .. ' ms')
    end
    return timed_fn
end

local function find(list, predicate)
    for i, item in ipairs(list) do
        if predicate(item) then
            return item, i
        end
    end
    return nil
end

-- TODO: make this better
local function join(p1, p2)
    if p1 == '/' then 
        return p1 .. p2
    else
        return p1 .. '/' .. p2
    end
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
    create_win = create_win,
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
