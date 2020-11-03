local api = vim.api
local uv = vim.loop
local u = require'filetree/util'

local state_by_win = {}

local function apply_changes(changes)
    for _, change in ipairs(changes) do
        -- TODO: make needed dirs
        if change[1] == 'remove' then
            -- TODO: remove non-empty dirs
            local success, err = os.remove(change[2])
            if not success then
                u.err(err)
                return false
            end
        elseif change[1] == 'rename' then
            local success, err = os.rename(change[2], change[3])
            if not success then
                u.err(err)
                return false
            end
        elseif change[1] == 'copy' then
            local success = uv.fs_copyfile(change[2], change[3])
            if not success then
                u.err(err)
                return false
            end
        elseif change[1] == 'create' then
            -- templates?
            vim.fn.system('touch ' .. vim.fn.shellescape(change[2]))
        else
            u.err('not handled', vim.inspect(change))
        end
    end
    return true
end

-- TODO: handle copy
local function reconcile_changes(state)
    local changes = {}
    local errors = {}
    local seen_lines = u.keys(state.files)
    local lines = api.nvim_buf_get_lines(state.buf, 0, -1, false)
    for _line_num, line in ipairs(lines) do
        -- TODO: resolve lines to absolute paths, then calculate changes
        local num, new_filename = line:match('^(%d+):%s+(.+)$')
        num = tonumber(num)
        if new_filename and new_filename:sub(-1) == '/' and new_filename ~= '/' then
            new_filename = new_filename:sub(1, -2)
        end
        if num and new_filename then
            local old_file = state.files[num]
            local old_file_abs_path = u.join(old_file.location, old_file.name)
            local new_file_abs_path = u.join(old_file.location, new_filename)
            if old_file then
                seen_lines[num] = true
                if old_file_abs_path ~= new_file_abs_path then
                    table.insert(changes, {'rename', old_file_abs_path, new_file_abs_path})
                end
            else
                table.insert(errors, string.format('no corresponding number %d', num))
            end
        elseif line:len() > 0 then
            local line_trimmed = u.trim(line)
            if u.is_valid_filename(line_trimmed) then
                local path = u.join(state.cwd, line_trimmed)
                table.insert(changes, {'create', path})
            end
        else
            table.insert(errors, string.format('failed to parse line %q', line))
        end
    end

    for i, seen in ipairs(seen_lines) do
        if not seen then
            local file = assert(state.files[i])
            local abs_path = u.join(file.location, file.name)
            table.insert(changes, {'remove', abs_path})
        end
    end
    if next(errors) then
        u.err('errors', vim.inspect(errors))
    end
    if next(changes) then
        print('changes', vim.inspect(changes))
        apply_changes(changes)
    else
        print('no changes')
    end
end

local function update_files_rec(state, dir, depth)
    for _, file in ipairs(u.list_dir(dir)) do
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

local function update_files(state)
    state.files = {}
    update_files_rec(state, state.cwd, 0)
end

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
    api.nvim_win_set_option(state.win, 'statusline', vim.fn.fnamemodify(state.cwd, ':~'))
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
        ['q']     = '<cmd>lua require"filetree".quit(' .. win .. ')<cr>',
        ['R']     = '<cmd>lua require"filetree".reload(' .. win .. ')<cr>',
        ['<cr>']  = '<cmd>lua require"filetree".open("edit", ' .. win .. ')<cr>',
        ['l']     = '<cmd>lua require"filetree".open("edit", ' .. win .. ')<cr>',
        ['s']     = '<cmd>lua require"filetree".open("split", ' .. win .. ')<cr>',
        ['v']     = '<cmd>lua require"filetree".open("vsplit", ' .. win .. ')<cr>',
        ['t']     = '<cmd>lua require"filetree".open("tabedit", ' .. win .. ')<cr>',
        ['h']     = '<cmd>lua require"filetree".up_dir(' .. win .. ')<cr>',
        ['-']     = '<cmd>lua require"filetree".up_dir(' .. win .. ')<cr>',
        ['<tab>'] = '<cmd>lua require"filetree".toggle_tree(' .. win .. ')<cr>',
        ['ge']    = '<cmd>lua require"filetree".enter_edit_mode(' .. win .. ')<cr>',
        ['gh']    = '<cmd>lua require"filetree".toggle_hidden_files(' .. win .. ')<cr>',
    })
    u.xnoremap(buf, {
        ['<tab>'] = ':<c-u>lua require"filetree".toggle_tree_VISUAL(' .. win .. ')<cr>',
    })
end

local function remove_keymaps(buf)
    for _, mode in ipairs({'n', 'x'}) do
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
        ['gw'] = '<cmd>lua require"filetree".exit_edit_mode(' .. win .. ', true)<cr>',
        ['gq']  = '<cmd>lua require"filetree".exit_edit_mode(' .. win .. ', false)<cr>',
    })
    render(state)
end

local function exit_edit_mode(win, save_changes)
    local state = assert(state_by_win[u.key(win)])
    state.in_edit_mode = false
    setup_keymaps(state.buf, state.win)
    if save_changes then
        reconcile_changes(state)
    end
    update_files(state)
    render(state)
end

local function start()
    -- before creating a new window
    local origin_win = api.nvim_get_current_win()
    local cwd = vim.fn.expand('%:p:h')
    local origin_filename = vim.fn.expand('%:t')

    local buf, win = u.create_win()
    setup_keymaps(buf, win)

    local is_file_hidden = function (file)
        return not not file.name:find('[.]resi$')
    end
    local show_hidden_files = false

    local state = {
        buf = buf,
        win = win,
        origin_win = origin_win,
        cwd = cwd,
        files = {},
        expanded_dirs = {},
        hovered_filename_cache = {},
        in_edit_mode = false,
        is_file_hidden = is_file_hidden,
        show_hidden_files = show_hidden_files,
    }

    update_files(state)
    state_by_win[u.key(win)] = state
    render(state)

    local _, i = u.find(state.files, function (file)
        return file.name == origin_filename
    end)
    if i then api.nvim_win_set_cursor(win, {i, 0}) end
end

local function quit(win)
    local state = assert(state_by_win[u.key(win)])
    api.nvim_win_close(state.win, false)
    vim.cmd('bwipeout ' .. state.buf)
    api.nvim_set_current_win(state.origin_win)
    state_by_win[u.key(win)] = nil
end

local function open(cmd, win)
    local state = assert(state_by_win[u.key(win)])
    local line, _ = unpack(api.nvim_win_get_cursor(win))
    local file = assert(state.files[line])
    local path = assert(uv.fs_realpath(u.join(file.location, file.name)))
    local resolved_file = uv.fs_stat(path)
    assert(uv.fs_access(path, 'R'), string.format('failed to read %q', path))
    if resolved_file.type == 'file' then
        quit(win)
        vim.cmd(cmd .. ' ' .. path)
    else
        state.cwd = path
        update_files(state)
        render(state)
        local hovered_filename = state.hovered_filename_cache[state.cwd]
        local _, i = u.find(state.files, function (file)
            return file.name == hovered_filename
        end)
        api.nvim_win_set_cursor(win, {i or 1, 0})
    end
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

return {
    start = u.time_fn(start),
    quit = quit,
    open = u.time_fn(open),
    up_dir = u.time_fn(up_dir),
    toggle_tree = u.time_fn(toggle_tree),
    toggle_tree_VISUAL = u.time_fn(toggle_tree_VISUAL),
    toggle_hidden_files = toggle_hidden_files,
    enter_edit_mode = enter_edit_mode,
    exit_edit_mode = exit_edit_mode,
    reload = reload,
}
