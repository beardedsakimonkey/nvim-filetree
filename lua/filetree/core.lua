local api = vim.api
local uv = vim.loop
local fs = require 'filetree/fs'
local edit = require 'filetree/edit'
local u = require 'filetree/util'

local state_by_win = {}

local function render(state)
    local state = assert(state_by_win[u.key(state.win)])
    local lines = {}
    for i = #state.files, 1, -1 do
        local file = state.files[i]
        local indent = ('\t'):rep(file.depth)
        local symbol
        if state.in_edit_mode then
            symbol = file.type == 'directory' and '/' or ''
        else
            symbol = file.type == 'directory' and '/'
            or file.link_dest and '@'
            or file.is_executable and '*'
            or ''
        end
        local number = ''
        if state.in_edit_mode then
            local max_digits = tostring(#state.files):len()
            local digits = tostring(i):len()
            number = (' '):rep(max_digits - digits) .. i .. ' '
        end
        lines[i] = number .. indent .. file.name .. symbol
    end
    api.nvim_buf_set_option(state.buf, 'modifiable', true)
    api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
    if not state.in_edit_mode then
        api.nvim_buf_set_option(state.buf, 'modifiable', false)
    end
end

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

local function update_files_rec(state, dir, depth)
    for _, file in ipairs(list_dir(dir)) do
        local path = u.join(dir, file.name)
        local new_file = {
            name = file.name,
            type = file.type, -- "file" | "directory" | "link"
            depth = depth, -- for convenience
            location = dir,
            is_executable = uv.fs_access(path, 'X') or false,
            link_dest = uv.fs_readlink(path), -- realtive path or nil
        }
        if state.show_hidden_files or not state.is_file_hidden(new_file) then
            table.insert(state.files, new_file)
            if state.expanded_dirs[path] then
                update_files_rec(state, path, depth + 1)
            end
        end
    end
end

local function watch_dir(state, dir)
    local watcher = uv.new_fs_event()
    local on_change = function (err, filename, events)
        watcher:stop()
        u.log('onchage')
        local line, _ = unpack(api.nvim_win_get_cursor(state.win))
        local maybe_hovered_file = state.files[line]
        state.files = {}
        update_files_rec(state, state.cwd, 0)
        render(state)
        if maybe_hovered_file then
            local _, i = u.find(state.files, function (file)
                return file.name == maybe_hovered_file.name and file.depth == maybe_hovered_file.depth
            end)
            api.nvim_win_set_cursor(state.win, {i or 1, 0})
        end
        if state.watcher then state.watcher:stop() end
        state.watcher = watch_dir(state, state.cwd)
    end
    -- TODO: make this non-recursive
    watcher:start(dir, {recursive = true}, vim.schedule_wrap(on_change))
    return watcher
end

local function update_files(state)
    state.files = {}
    update_files_rec(state, state.cwd, 0)
    if state.watcher then state.watcher:stop() end
    -- FIXME
    -- state.watcher = watch_dir(state, state.cwd)
end

local function update_files_and_render(state)
    local line, _ = unpack(api.nvim_win_get_cursor(state.win))
    local maybe_hovered_file = state.files[line]
    update_files(state)
    render(state)
    if maybe_hovered_file then
        local _, i = u.find(state.files, function (file)
            return file.name == maybe_hovered_file.name and file.depth == maybe_hovered_file.depth
        end)
        api.nvim_win_set_cursor(state.win, {i or 1, 0})
    end
end

local function toggle_hidden_files(win)
    local state = assert(state_by_win[u.key(win)])
    state.show_hidden_files = not state.show_hidden_files
    update_files_and_render(state)
end

local function setup_keymaps(buf, win)
    u.nnoremap(buf, {
        ['q']     = '<cmd>lua require"filetree/core".quit(' .. win .. ')<cr>',
        ['R']     = '<cmd>lua require"filetree/core".reload(' .. win .. ')<cr>',
        ['<cr>']  = '<cmd>lua require"filetree/core".open("edit", ' .. win .. ')<cr>',
        ['l']     = '<cmd>lua require"filetree/core".open("edit", ' .. win .. ')<cr>',
        ['s']     = '<cmd>lua require"filetree/core".open("split", ' .. win .. ')<cr>',
        ['v']     = '<cmd>lua require"filetree/core".open("vsplit", ' .. win .. ')<cr>',
        ['t']     = '<cmd>lua require"filetree/core".open("tabedit", ' .. win .. ')<cr>',
        ['h']     = '<cmd>lua require"filetree/core".up_dir(' .. win .. ')<cr>',
        ['-']     = '<cmd>lua require"filetree/core".up_dir(' .. win .. ')<cr>',
        ['<tab>'] = '<cmd>lua require"filetree/core".toggle_tree(' .. win .. ')<cr>',
        ['ge']    = '<cmd>lua require"filetree/core".enter_edit_mode(' .. win .. ')<cr>',
        ['gh']    = '<cmd>lua require"filetree/core".toggle_hidden_files(' .. win .. ')<cr>',
    })
    u.xnoremap(buf, {
        ['<cr>']  = ':<c-u>lua require"filetree/core".open_VISUAL("edit", ' .. win .. ')<cr>',
        ['l']     = ':<c-u>lua require"filetree/core".open_VISUAL("edit", ' .. win .. ')<cr>',
        ['s']     = ':<c-u>lua require"filetree/core".open_VISUAL("split", ' .. win .. ')<cr>',
        ['v']     = ':<c-u>lua require"filetree/core".open_VISUAL("vsplit", ' .. win .. ')<cr>',
        ['t']     = ':<c-u>lua require"filetree/core".open_VISUAL("tabedit", ' .. win .. ')<cr>',
        ['<tab>'] = ':<c-u>lua require"filetree/core".toggle_tree_VISUAL(' .. win .. ')<cr>',
    })
end

local function remove_keymaps(buf)
    for _, mode in ipairs{'n', 'x'} do
        local maps = api.nvim_buf_get_keymap(buf, mode)
        for _, map in ipairs(maps) do
            api.nvim_buf_del_keymap(buf, mode, map.lhs)
        end
    end
end

local function enter_edit_mode(win)
    local state = assert(state_by_win[u.key(win)])
    state.in_edit_mode = true
    remove_keymaps(state.buf)
    u.nnoremap(state.buf, {
        ['gw'] = '<cmd>lua require"filetree/core".exit_edit_mode(' .. win .. ', true)<cr>',
        ['gq'] = '<cmd>lua require"filetree/core".exit_edit_mode(' .. win .. ', false)<cr>',
    })
    render(state)
end

local function exit_edit_mode(win, save_changes)
    local state = assert(state_by_win[u.key(win)])
    state.in_edit_mode = false
    setup_keymaps(state.buf, state.win)
    if save_changes then
        edit.reconcile_changes(state)
    end
    update_files(state)
    render(state)
end

local function set_current_buf(buf)
    if buf and vim.fn.bufexists(buf) then
        local _success = pcall(api.nvim_set_current_buf, buf)
    end
end

local function cleanup(state)
    if state.watcher then
        state.watcher:stop()
    end
    state_by_win[u.key(win)] = nil
end

local function quit(win)
    local state = assert(state_by_win[u.key(win)])
    set_current_buf(state.alt_buf)
    set_current_buf(state.origin_buf)
    cleanup(state)
end

local function resolve_file(path)
    local realpath = assert(uv.fs_realpath(path))
    local resolved_file = uv.fs_stat(path)
    assert(uv.fs_access(path, 'R'), string.format('failed to read %q', path))
    return resolved_file, realpath
end

local function open_file(cmd, path)
    vim.cmd(cmd .. ' ' .. vim.fn.fnameescape(path))
end

local function open(cmd, win)
    local state = assert(state_by_win[u.key(win)])
    local line, _ = unpack(api.nvim_win_get_cursor(win))
    local file = assert(state.files[line])
    local resolved_file, realpath = resolve_file(u.join(file.location, file.name))
    if resolved_file.type == 'directory' then
        -- TODO: add ability to :vsplit on directories
        state.cwd = realpath
        update_files(state)
        render(state)
        local hovered_filename = state.hovered_filename_cache[state.cwd]
        local _, i = u.find(state.files, function (file)
            return file.name == hovered_filename
        end)
        api.nvim_win_set_cursor(win, {i or 1, 0})
    else
        set_current_buf(state.origin_buf)
        open_file(cmd, realpath)
        cleanup(state)
    end
end

local function open_VISUAL(cmd, win)
    local state = assert(state_by_win[u.key(win)])
    local start_line = vim.fn.line("'<")
    local end_line = vim.fn.line("'>")
    set_current_buf(state.origin_buf)
    for line = start_line, end_line do
        local file = assert(state.files[line])
        local resolved_file, realpath = resolve_file(u.join(file.location, file.name))
        if resolved_file.type ~= 'directory' then
            open_file(cmd, realpath)
        end
    end
    cleanup(state)
end

local function up_dir(win)
    local state = assert(state_by_win[u.key(win)])
    local path = vim.fn.fnamemodify(state.cwd, ':h')
    assert(uv.fs_access(path, 'R'), string.format('failed to read %q', path))
    local from_dir = vim.fn.fnamemodify(state.cwd, ':t')

    -- cache hovered filename
    local line, _ = unpack(api.nvim_win_get_cursor(win))
    while state.files[line] and state.files[line].depth > 0 do
        line = line - 1
    end
    local hovered_file = state.files[line]
    if hovered_file then
        state.hovered_filename_cache[state.cwd] = hovered_file.name
    end

    state.cwd = path
    update_files(state)
    render(state)
    local _, i = u.find(state.files, function (file)
        return file.name == from_dir
    end)
    api.nvim_win_set_cursor(win, {i or 1, 0})
end

local function toggle_expanded(state, line)
    local file = assert(state.files[line])
    if file.type ~= 'directory' then return end
    local abs_path = u.join(file.location, file.name)
    assert(uv.fs_access(abs_path, 'R'), string.format('failed to read %q', abs_path))
    local is_expanded = state.expanded_dirs[abs_path] ~= nil
    if is_expanded then
        state.expanded_dirs[abs_path] = nil
    else 
        state.expanded_dirs[abs_path] = true
    end
end

local function toggle_tree(win)
    -- TODO: local count = vim.v.count1
    local state = assert(state_by_win[u.key(win)])
    local line, col = unpack(api.nvim_win_get_cursor(win))
    toggle_expanded(state, line)
    update_files(state)
    render(state)
    api.nvim_win_set_cursor(win, {line, col})
end

local function toggle_tree_VISUAL(win)
    local state = assert(state_by_win[u.key(win)])
    local start_line = vim.fn.line("'<")
    local end_line = vim.fn.line("'>")
    for i = start_line, end_line do
        toggle_expanded(state, i)
    end
    update_files(state)
    render(state)
end

local function reload(win)
    local state = assert(state_by_win[u.key(win)])
    update_files_and_render(state)
end

local function on_VimLeave()
    for _, state in pairs(state_by_win) do
        cleanup(state)
    end
end

return {
    quit = quit,
    open = open,
    open_VISUAL = open_VISUAL,
    up_dir = up_dir,
    toggle_tree = toggle_tree,
    toggle_tree_VISUAL = toggle_tree_VISUAL,
    toggle_hidden_files = toggle_hidden_files,
    enter_edit_mode = enter_edit_mode,
    exit_edit_mode = exit_edit_mode,
    reload = reload,

    cleanup = cleanup,
    -- TODO: combine update_files + render?
    render = render,
    update_files = update_files,
    state_by_win = state_by_win,
    setup_keymaps = setup_keymaps,
    on_VimLeave = on_VimLeave,
}
