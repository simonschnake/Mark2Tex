-- Usage: texlua scripts/convert.lua INPUT OUTPUT_DIR [key=value ...]
local directory = arg[0]:match("^(.*)[/\\]scripts[/\\][^/\\]+$") or "."
local function convert()
    assert(arg[1] and arg[2], "expected input path and output directory")
    local config = { save_dir = arg[2] }
    local options = {
        profile = true, slide_level = true, slide_audience = true, audience = true, h1 = true,
        document_id = true, citation = true, paren_citation = true, header = true,
    }
    for index = 3, #arg do
        local key, value = arg[index]:match("^([%w_]+)=(.+)$")
        assert(options[key], "invalid converter option: " .. arg[index])
        if key == "header" then
            config.header = {}
            for heading in (value .. ","):gmatch("(.-),") do
                heading = heading:match("^%s*(.-)%s*$")
                assert(heading ~= "", "empty heading command")
                config.header[#config.header + 1] = heading
            end
        else
            config[key] = value
        end
    end
    config.standalone_learning_blocks = config.profile == "slides"
    local mark2tex = dofile(directory .. "/mark2tex.lua")
    return assert(mark2tex.convert(arg[1], config))
end

local success, result = pcall(convert)
if not success then
    io.stderr:write(result .. "\n")
    os.exit(1)
end
io.write(result .. "\n")
