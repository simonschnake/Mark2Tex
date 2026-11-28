-- Generated from src/mark2tex/fileutils.tl by Teal 0.24.1. Edit the .tl file and run 'make teal-gen'.
local lfs = require("lfs")
local md5 = require("md5")

local fileutils = {}

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


function fileutils.read_file(path)
   local file = io.open(path, "r")
   if not file then
      return nil, "Unable to open file: " .. path
   end
   local content = file:read("*a")
   file:close()
   return content
end



function fileutils.save_file(path, content)
   local file = io.open(path, "w")
   if not file then
      return nil, "Unable to write file: " .. path
   end
   file:write(content)
   file:close()
   return true
end


function fileutils.create_directory(path)
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
         if not ok and lfs.attributes(current, "mode") ~= "directory" then
            return nil, "Unable to create directory '" .. current .. "': " .. tostring(err)
         end
      elseif mode ~= "directory" then
         return nil, "Unable to create directory '" .. current .. "': path exists and is not a directory"
      end
   end

   return true
end


function fileutils.get_output_filename(input_path, out_dir)
   local _, name_with_ext = string.match(input_path, "(.-)([^\\/]-%.?([^%.\\/]*))$")
   local name = name_with_ext:match("(.+)%..+$")
   local md5_hash = md5.sumhexa(input_path)
   return out_dir .. "/" .. (name or name_with_ext) .. "_" .. md5_hash .. ".tex"
end


function fileutils.getFirstLine(filePath)
   local file = io.open(filePath, "r")
   if file then
      local firstLine = file:read("*l")
      file:close()
      return firstLine
   end
   return nil
end

return fileutils
