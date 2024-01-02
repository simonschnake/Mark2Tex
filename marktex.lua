local parse = require "parse"
local write = require "write"
local default_config = require "default_config"
local fu = require "fileutils"

local self = {}
-- Main function
self.convert = function (input_path, config)
    config = config or default_config
    -- Create mdtex directory if it does not exist
    fu.create_directory(config.save_dir)

    -- Output file path
    local output_path = fu.get_output_filename(
        input_path, config.save_dir)

    -- Check if file has been modified since last conversion
    local last_conversion = fu.getFirstLine(output_path)
    local last_modified = fu.getLastModifiedTime(input_path)
    if last_conversion == "% " .. last_modified then
        return output_path
    end

    local content, err = fu.read_file(input_path)
    if not content then
        print(err)
        return
    end

    local ast = parse(content, config)
    local tex = write(ast, config)

    -- Add last modified time to the first line of the output file
    tex = "% " .. last_modified .. "\n" .. tex

    local success, err = fu.save_file(output_path, tex)
    if not success then
        print(err)
    else
        print("\nFile processed and saved to " .. output_path)
    end
    return output_path
end

return self