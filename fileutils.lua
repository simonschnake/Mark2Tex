local lfs = require("lfs")
local md5 = require("md5")

local self = {}

-- Function to read file content
self.read_file = function (path)
    local file = io.open(path, "r")
    if not file then return nil, "Unable to open file" end
    local content = file:read("*a")
    file:close()
    return content
end


-- Function to save file content
self.save_file = function (path, content)
    local file = io.open(path, "w")
    if not file then return nil, "Unable to write file" end
    file:write(content)
    file:close()
    return true
end

-- Function to create a directory if it doesn't exist
self.create_directory = function (path)
    local command = string.format("mkdir -p %s", path)
    print(command)
    os.execute(command)
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
