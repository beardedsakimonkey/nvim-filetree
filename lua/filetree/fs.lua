local api = vim.api
local uv = vim.loop
local u = require 'filetree/util'

local M = {}

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

M.remove = function(file)
    if file.type == 'file' then
        local path = u.join(file.location, file.name)
        u.log('os.remove', path)
        local success, err = os.remove(path)
        if not success then error(err) end
        -- wipe buffer
        local buf = vim.fn.bufnr('^' .. path .. '$')
        if buf ~= -1 then
            api.nvim_buf_delete(buf, {})
        end
    else
        local path = vim.fn.shellescape(u.join(file.location, file.name))
        u.log('rm -r', path)
        local status = os.execute('rm -r ' .. path)
        if status ~= 0 then
            error(string.format('failed to remove directory %q with status code %d', path, status))
        end
    end
end

M.rename = function(from, to)
    local from_path = u.join(from.location, from.name)
    local to_path = u.join(to.location, to.name)
    -- TODO: rename buffer
    u.log('os.rename', from_path, to_path)
    local success, err = os.rename(from_path, to_path)
    if not success then error(err) end
end

M.copy = function(from, to)
    make_needed_dirs(to.location)
    local from_path = u.join(from.location, from.name)
    local to_path = u.join(to.location, to.name)
    u.log('uv.fs_copyfile', from_path, to_path)
    local success = uv.fs_copyfile(from_path, to_path)
    if not success then error(err) end
end

M.create = function(file)
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

return M
