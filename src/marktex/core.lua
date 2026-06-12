local parse = require "marktex.parse"
local write = require "marktex.write"
local default_config = require "marktex.default_config"
local fu = require "marktex.fileutils"

local self = {}

local function copy_table(value)
    if type(value) ~= "table" then
        return value
    end

    local copy = {}
    for k, v in pairs(value) do
        copy[k] = copy_table(v)
    end
    return copy
end

local function resolve_config(cfg)
    local config = copy_table(default_config)

    if cfg then
        for k, v in pairs(cfg) do
            config[k] = copy_table(v)
        end
    end

    return config
end

self.resolve_config = resolve_config

-- Main function
self.convert = function (input_path, cfg)
    local config = resolve_config(cfg)

    -- Create mdtex directory if it does not exist
    local success, err = fu.create_directory(config.save_dir)
    if not success then
        return nil, err
    end

    -- Output file path
    local output_path = fu.get_output_filename(
        input_path, config.save_dir)

    local last_modified = fu.getLastModifiedTime(input_path)
    if not last_modified then
        return nil, "Unable to stat file: " .. input_path
    end

    -- Check if file has been modified since last conversion
    local last_conversion = fu.getFirstLine(output_path)
    if last_conversion == "% " .. last_modified then
        return output_path
    end

    local content, err = fu.read_file(input_path)
    if not content then
        return nil, err
    end

    local ast = parse(content, config)
    local tex = write(ast, config)

    -- Add last modified time to the first line of the output file
    tex = "% " .. last_modified .. "\n" .. tex

    local success, err = fu.save_file(output_path, tex)
    if not success then
        return nil, err
    elseif config.verbose then
        print("\nFile processed and saved to " .. output_path)
    end
    return output_path
end

return self
