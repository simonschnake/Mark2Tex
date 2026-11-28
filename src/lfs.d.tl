-- LuaFileSystem operations used by fileutils.
local record lfs
    attributes: function(path: string, attribute: string): string, string
    mkdir: function(path: string): boolean, string
end

return lfs
