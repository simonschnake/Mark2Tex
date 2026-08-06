if debug and debug.getinfo then
    local source = debug.getinfo(1, "S").source
    if source:sub(1, 1) == "@" then
        local dir = source:sub(2):match("^(.*)[/\\][^/\\]-$")
        if dir then
            package.path = dir .. "/src/?.lua;" .. dir .. "/src/?/init.lua;" .. package.path
        end
    end
end

return require("mark2tex.core")
