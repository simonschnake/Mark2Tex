local parse = require "mark2tex.parse"
local write = require "mark2tex.write"
local default_config = require "mark2tex.default_config"
local fu = require "mark2tex.fileutils"
local md5 = require("md5")

local self = {}
-- Increase this whenever parser or writer behavior changes so existing output
-- files are regenerated instead of serving stale LaTeX from the cache.
local CACHE_VERSION = "v3"

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

local function sort_keys(left, right)
    local left_type = type(left)
    local right_type = type(right)

    if left_type == right_type then
        if left_type == "number" then
            return left < right
        end
        return tostring(left) < tostring(right)
    end

    return left_type < right_type
end

local function serialize_value(value)
    local value_type = type(value)

    if value_type == "table" then
        local keys = {}
        for key in pairs(value) do
            keys[#keys + 1] = key
        end

        table.sort(keys, sort_keys)

        local parts = { "{" }
        for _, key in ipairs(keys) do
            parts[#parts + 1] = serialize_value(key)
            parts[#parts + 1] = "="
            parts[#parts + 1] = serialize_value(value[key])
            parts[#parts + 1] = ";"
        end
        parts[#parts + 1] = "}"
        return table.concat(parts)
    elseif value_type == "string" then
        return string.format("%q", value)
    elseif value_type == "number" or value_type == "boolean" then
        return tostring(value)
    elseif value_type == "nil" then
        return "nil"
    end

    return string.format("%s:%s", value_type, tostring(value))
end

local function build_cache_key(content, config)
    local serialized = table.concat({
        CACHE_VERSION,
        serialize_value(content),
        serialize_value(config),
    }, "\n")

    return md5.sumhexa(serialized)
end

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

    local content, err = fu.read_file(input_path)
    if not content then
        return nil, err
    end

    if kpse and kpse.record_input_file then
        kpse.record_input_file(input_path)
    end

    local cache_key = build_cache_key(content, config)

    -- Check whether the cached output matches the current content and config.
    local last_conversion = fu.getFirstLine(output_path)
    if last_conversion == "% cache:" .. cache_key then
        return output_path
    end

	local ast = parse(content, config)
	for _, warning in ipairs(ast.warnings or {}) do
		io.stderr:write("mark2tex warning [" .. warning.category .. "]: " .. warning.kind .. " delimiter " .. warning.delimiter .. " kept literal\n")
	end
	local tex = write(ast, config)

    -- Add a cache fingerprint to the first line of the output file.
    tex = "% cache:" .. cache_key .. "\n" .. tex

    local success, err = fu.save_file(output_path, tex)
    if not success then
        return nil, err
    elseif config.verbose then
        print("\nFile processed and saved to " .. output_path)
    end
    return output_path
end

return self
