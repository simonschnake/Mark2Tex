local lfs = require("lfs")
local md5 = require("md5")

local self = {}

local path_separator = package.config:sub(1, 1)

local function is_windows_absolute_path(path)
    return path:match("^%a:[/\\]") ~= nil
end

local function is_absolute_path(path)
    return path:sub(1, 1) == "/" or is_windows_absolute_path(path)
end

local function join_path(base, part)
    if base == "" then
        return part
    end
    return base .. path_separator .. part
end

-- Function to read file content
self.read_file = function (path)
    local file = io.open(path, "r")
    if not file then
        return nil, "Unable to open file: " .. path
    end
    local content = file:read("*a")
    file:close()
    return content
end


-- Function to save file content
self.save_file = function (path, content)
    local file = io.open(path, "w")
    if not file then
        return nil, "Unable to write file: " .. path
    end
    file:write(content)
    file:close()
    return true
end

-- Function to create a directory if it doesn't exist
self.create_directory = function (path)
    if path == nil or path == "" then
        return nil, "Unable to create directory: empty path"
    end

    local current = ""
    if is_absolute_path(path) then
        current = path:sub(1, 1)
    end

    for part in path:gmatch("[^/\\]+") do
        current = join_path(current, part)

        local mode = lfs.attributes(current, "mode")
        if mode == nil then
            local ok, err = lfs.mkdir(current)
            if not ok then
                return nil, "Unable to create directory '" .. current .. "': " .. tostring(err)
            end
        elseif mode ~= "directory" then
            return nil, "Unable to create directory '" .. current .. "': path exists and is not a directory"
        end
    end

    return true
end

-- Function to get the output filename
self.get_output_filename = function(input_path, out_dir)
    local _, name_with_ext = string.match(input_path, "(.-)([^\\/]-%.?([^%.\\/]*))$")
    local name = name_with_ext:match("(.+)%..+$") -- Extract name without extension
    local md5_hash = md5.sumhexa(input_path)
    return out_dir .. "/" .. (name or name_with_ext) .. "_" .. md5_hash .. ".tex"
end

-- Function to get the last modification time of a file
self.getLastModifiedTime = function(filePath)
    local attributes = lfs.attributes(filePath)
    return attributes and os.date("%Y-%m-%d %H:%M:%S", attributes.modification)
end

-- Function to get the first line of a file
self.getFirstLine = function(filePath)
    local file = io.open(filePath, "r")
    if file then
        local firstLine = file:read("*l")
        file:close()
        return firstLine
    end
    return nil
end

return self
