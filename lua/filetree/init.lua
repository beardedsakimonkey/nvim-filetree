local vim = vim
local api = vim.api
local uv = vim.loop
local u = require'filetree/util'

local state_by_win = {}

local REMOVE = 'REMOVE'
local RENAME = 'RENAME'
local COPY   = 'COPY'
local CREATE = 'CREATE'

local function remove(file)
    if file.type == 'file' then
        local path = u.join(file.location, file.name)
        u.log('os.remove', path)
        local success, err = os.remove(path)
        if not success then error(err) end
    else
        local path = vim.fn.shellescape(u.join(file.location, file.name))
        u.log('rm -r', path)
        local status = os.execute('rm -r ' .. path)
        if status ~= 0 then
            error(string.format('failed to remove directory %q with status code %d', path, status))
        end
    end
end

local function rename(from, to)
    local from_path = u.join(from.location, from.name)
    local to_path = u.join(to.location, to.name)
    u.log('os.rename', from_path, to_path)
    local success, err = os.rename(from_path, to_path)
    if not success then error(err) end
end

local function make_needed_dirs(path)
    local dir_exists, fail = uv.fs_access(path, 'R')
    assert(not fail)
    if dir_exists then return end
    local path_esc = vim.fn.shellescape(path)
    -- avoiding vim.fn.mkdir because that call would get buffered
    u.log('mkdir -p', path_esc)
    os.execute('mkdir -p ' .. path_esc)
    if vim.v.shell_error ~= 0 then
        error(string.format('failed to make directory %q', path_esc))
    end
end

local function copy(from, to)
    make_needed_dirs(to.location)
    local from_path = u.join(from.location, from.name)
    local to_path = u.join(to.location, to.name)
    u.log('uv.fs_copyfile', from_path, to_path)
    local success = uv.fs_copyfile(from_path, to_path)
    if not success then error(err) end
end

local function create(file)
    if file.type == 'file' then
        make_needed_dirs(file.location)
        local path = vim.fn.shellescape(u.join(file.location, file.name))
        u.log('touch', path)
        local status = os.execute('touch ' .. path)
        if status ~= 0 then
            error(string.format('failed to make file %q with status code %d', path, status))
        end
    else
        local path = vim.fn.shellescape(u.join(file.location, file.name))
        u.log('mkdir -p', path)
        os.execute('mkdir -p ' .. path)
        if vim.v.shell_error ~= 0 then
            error(string.format('failed to make directory %q with status code %d', path, status))
        end
    end
end

local function apply_changes(changes)
    for _, change in ipairs(changes) do
        if change[1] == REMOVE then
            remove(change[2])
        elseif change[1] == RENAME then
            rename(change[2], change[3])
        elseif change[1] == COPY then
            copy(change[2], change[3])
        elseif change[1] == CREATE then
            create(change[2])
        end
    end
end

local function calculate_changes(state, new_files)
    local changes = {}
    local errors = {}
    local seen_nums = u.keys(state.files)
    -- dont use ipairs because new_files has gaps
    for _, new_file in pairs(new_files) do
        local num = new_file.num
        if num then
            local old_file = state.files[num]
            local old_file_abs_path = u.join(old_file.location, old_file.name)
            local new_file_abs_path = u.join(new_file.location, new_file.name)
            if old_file then
                if seen_nums[num] then
                    if old_file_abs_path ~= new_file_abs_path then
                        table.insert(changes, {COPY, old_file, new_file})
                    end
                else
                    seen_nums[num] = true
                    if old_file_abs_path ~= new_file_abs_path then
                        table.insert(changes, {RENAME, old_file, new_file})
                    end
                end
            else
                table.insert(errors, string.format('no corresponding number %d', num))
            end
        else
            -- no num, so this is a new file
            if u.is_valid_filename(new_file.name) then
                table.insert(changes, {CREATE, new_file})
            else
                table.insert(errors, string.format('invalid file name %q', new_file.name))
            end
        end
    end
    for num, seen in ipairs(seen_nums) do
        if not seen then
            local file = assert(state.files[num])
            table.insert(changes, {REMOVE, file})
        end
    end
    local priority = {
        [COPY] = 1,
        [RENAME] = 2,
        [CREATE] = 3,
        [REMOVE] = 4,
    }
    table.sort(changes, function (a, b)
        if priority[a[1]] < priority[b[1]] then return true end
        if priority[a[1]] > priority[b[1]] then return false end
        -- create directories before creating files
        if a[1] == CREATE and a[2].type ~= b[2].type then return a[2].type == 'directory' end
        -- remove files before removing directories
        if a[1] == REMOVE and a[2].type ~= b[2].type then return a[2].type == 'file' end
        return a[2].name < b[2].name
    end)
    return changes, errors
end

local function parse_buffer(state)
    local files = {}
    local errors = {}
    -- list of directory names that are ancestors to the current line
    local context = {}

    for line_num, line in ipairs(api.nvim_buf_get_lines(state.buf, 0, -1, false)) do
        if line:find('%S') then
            local num, indent, name = line:match('^ *(%d*) ?([\t]*)(.+)$')
            if name then
                local depth = indent and indent:len() or 0

                while #context > depth do
                    table.remove(context)
                end

                if #context < depth then
                    local prev_file = assert(files[line_num - 1], 'invalid depth')
                    assert(prev_file.type == 'directory')
                    table.insert(context, prev_file.name)
                end

                -- TODO: make u.join() variadic
                local location = state.cwd
                for _, v in ipairs(context) do
                    location = u.join(location, v)
                end

                local type = name:sub(-1) == '/' and 'directory' or 'file'
                if type == 'directory' and name ~= '/' then name = name:sub(1, -2) end

                files[line_num] = {
                    num = num and tonumber(num) or nil,
                    name = name,
                    location = location,
                    type = type,
                }
            else
                table.insert(errors, string.format('failed to parse line %q', line))
            end
        end
    end
    return files, errors
end

local function reconcile_changes(state)
    local new_files, parse_errors = parse_buffer(state)
    if next(parse_errors) then error('parse errors', vim.inspect(parse_errors)) end

    local changes, errors = calculate_changes(state, new_files)
    if next(errors) then error('errors', vim.inspect(errors)) end

    if next(changes) then
        u.log('changes', vim.inspect(changes))
        apply_changes(changes)
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
        ['gw'] = '<cmd>lua require"filetree".exit_edit_mode(' .. win .. ', true)<cr>',
        ['gq'] = '<cmd>lua require"filetree".exit_edit_mode(' .. win .. ', false)<cr>',
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
        return vim.endswith(file.name, '.bs.js')
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
