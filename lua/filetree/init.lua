local vim = vim
local api = vim.api
local fs = require'filetree/fs'
local edit = require'filetree/edit'
local core = require'filetree/core'
local u = require'filetree/util'

local initialized = false

local function init()
    if initialized then
        return
    else
        initialized = true
    end
    vim.cmd 'aug filetree'
    vim.cmd 'au!'
    vim.cmd "au BufEnter * if !empty(expand('%')) && isdirectory(expand('%')) | Filetree | endif"
    vim.cmd "au VimLeave * lua require'filetree'.on_VimLeave()"
    vim.cmd 'aug END'
end

local function get_buf(cwd)
    local buf = vim.fn.bufnr('^' .. cwd .. '$')
    if buf == -1 then
        buf = api.nvim_create_buf(false, true)
        assert(buf ~= -1)
        api.nvim_buf_set_name(buf, cwd)
    end
    api.nvim_set_current_buf(buf)
    api.nvim_buf_set_option(buf, 'filetype', 'filetree')
    return buf
end

local function start(dir)
    local origin_buf = api.nvim_get_current_buf()
    local alt_buf = vim.fn.bufnr('#')
    alt_buf = alt_buf ~= -1 and alt_buf or nil

    local cwd = dir or vim.fn.expand('%:p:h')
    local origin_filename = vim.fn.expand('%:t')

    local buf = get_buf(cwd)
    local win = vim.fn.win_getid()
    core.setup_keymaps(buf, win)

    local is_file_hidden = function (file)
        return vim.endswith(file.name, '.bs.js')
    end
    local show_hidden_files = false

    local state = {
        buf = buf,
        win = win,
        origin_buf = origin_buf,
        alt_buf = alt_buf,
        cwd = cwd,
        files = {},
        expanded_dirs = {},
        hovered_filename_cache = {},
        in_edit_mode = false,
        is_file_hidden = is_file_hidden,
        show_hidden_files = show_hidden_files,
        watcher = nil,
    }

    core.update_files(state)
    core.state_by_win[u.key(win)] = state
    core.render(state)

    local _, i = u.find(state.files, function (file)
        return file.name == origin_filename
    end)
    if i then api.nvim_win_set_cursor(win, {i, 0}) end
end

local function on_VimLeave()
    for _, state in pairs(core.state_by_win) do
        core.cleanup(state)
    end
end

return {
    init = init,
    start = start,
    on_VimLeave = on_VimLeave,
}
