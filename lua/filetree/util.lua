local api = vim.api
local uv = vim.loop

local function sort_in_place(files)
    table.sort(files, function (a, b)
        if a.type == b.type then
            return a.name < b.name
        else
            return a.type == 'directory'
        end
    end)
    return files
end

local function list_dir(path)
    local data = assert(uv.fs_opendir(path, nil, 1000))
    local dir = assert(uv.fs_readdir(data))
    assert(uv.fs_closedir(data))
    sort_in_place(dir)
    return dir
end

local function merge(t1, t2)
    local merged = {}
    for k, v in pairs(t1) do merged[k] = v end
    for k, v in pairs(t2) do merged[k] = v end
    return merged
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
    api.nvim_buf_set_option(buf, 'filetype', 'filetree')
    api.nvim_win_set_option(win, 'cursorline', true)
    api.nvim_win_set_option(win, 'foldenable', false)
    api.nvim_win_set_option(win, 'number', false)
    api.nvim_buf_set_option(buf, 'buftype', 'nofile')
    api.nvim_buf_set_option(buf, 'modifiable', false)

    api.nvim_win_set_option(win, 'list', true)
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

local function echo(msg, hl)
    if hl then vim.cmd('echohl ' .. hl) end
    vim.cmd('redraw')
    vim.cmd(string.format('echo %q', msg))
    if hl then vim.cmd('echohl NONE') end
end

local function err(msg)
    echo(msg, 'ErrMsg')
end

local function warn(msg)
    echo(msg, 'WarningMsg')
end

local function key(win)
    return tostring(win)
end

local function time_fn(fn)
    local timed_fn = function(...)
        local t1 = os.clock()
        fn(...)
        local t2 = os.clock()
        echo((t2 - t1) * 1000 .. ' ms')
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

local function trim(str)
    local r = str:gsub('^%s*', ''):gsub('%s*$', '')
    return r
end

local function is_valid_filename(filename)
    return filename and filename:len() > 0 and not filename:find('/')
end

return {
    -- luv
    list_dir = list_dir,
    -- vim
    create_win = create_win,
    setup_win_options = setup_win_options,
    nnoremap = nnoremap,
    xnoremap = xnoremap,
    echo = echo,
    err = err,
    warn = warn,
    -- lua
    key = key,
    time_fn = time_fn,
    find = find,
    join = join,
    merge = merge,
    keys = keys,
    trim = trim,
    is_valid_filename = is_valid_filename,
}
