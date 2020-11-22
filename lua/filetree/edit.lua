local api = vim.api
local fs = require 'filetree/fs'
local u = require 'filetree/util'

local M = {}

local REMOVE = 'REMOVE'
local RENAME = 'RENAME'
local COPY   = 'COPY'
local CREATE = 'CREATE'

local function is_valid_filename(filename)
    return filename:len() > 0 and not filename:find('/')
end

function keys(table)
    local ret = {}
    for k, _ in ipairs(table) do
        ret[k] = false
    end
    return ret
end

local function apply_changes(changes)
    for _, change in ipairs(changes) do
        if change[1] == REMOVE then
            fs.remove(change[2])
        elseif change[1] == RENAME then
            fs.rename(change[2], change[3])
        elseif change[1] == COPY then
            fs.copy(change[2], change[3])
        elseif change[1] == CREATE then
            fs.create(change[2])
        end
    end
end

local function calculate_changes(state, new_files)
    local changes = {}
    local seen_nums = keys(state.files)
    -- dont use ipairs because new_files has gaps
    for _, new_file in pairs(new_files) do
        local num = new_file.num
        if num then
            local old_file = state.files[num]
            local old_file_abs_path = u.join(old_file.location, old_file.name)
            local new_file_abs_path = u.join(new_file.location, new_file.name)
            assert(old_file, string.format('no corresponding number %d', num))
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
            -- no num, so this is a new file
            assert(is_valid_filename(new_file.name), string.format('invalid file name %q', new_file.name))
            table.insert(changes, {CREATE, new_file})
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
    return changes
end

local function parse_buffer(state)
    local files = {}
    -- list of directory names that are ancestors to the current line
    local context = {}

    for line_num, line in ipairs(api.nvim_buf_get_lines(state.buf, 0, -1, false)) do
        if line:find('%S') then
            local num, indent, name = line:match('^ *(%d*) ?([\t]*)(.+)$')
            assert(name, string.format('failed to parse line %q', line))
            local depth = indent and indent:len() or 0

            while #context > depth do
                table.remove(context)
            end

            if #context < depth then
                local prev_file = assert(files[line_num - 1], 'invalid depth')
                assert(prev_file.type == 'directory')
                table.insert(context, prev_file.name)
            end

            local location = u.join(state.cwd, unpack(context))

            local type = name:sub(-1) == '/' and 'directory' or 'file'
            if type == 'directory' and name ~= '/' then name = name:sub(1, -2) end

            files[line_num] = {
                num = num and tonumber(num) or nil,
                name = name,
                location = location,
                type = type,
            }
        end
    end
    return files
end

-- XXX: potentially operating on stale file state
M.reconcile_changes = function(state)
    local new_files = parse_buffer(state)
    local changes = calculate_changes(state, new_files)

    if next(changes) then
        -- u.log('changes', vim.inspect(changes))
        apply_changes(changes)
    end
end

return M
