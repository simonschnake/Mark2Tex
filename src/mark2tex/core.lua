local parse = require "mark2tex.parse"
local write = require "mark2tex.write"
local lecture = require "mark2tex.lecture"
local default_config = require "mark2tex.default_config"
local fu = require "mark2tex.fileutils"
local md5 = require("md5")

local self = {}
-- Increase this whenever parser or writer behavior changes so existing output
-- files are regenerated instead of serving stale LaTeX from the cache.
local CACHE_VERSION = "v17"

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

    if config.profile ~= nil then
        if config.profile ~= "handout" and config.profile ~= "slides" then
            return nil, "profile must be handout or slides"
        end
        local level = config.slide_level == nil and 2 or tonumber(config.slide_level)
        if not level or level % 1 ~= 0 or level < 1 or level > 6 then
            return nil, "slide-level must be an integer from 1 to 6"
        end
        config.slide_level = math.floor(level)
    elseif config.slide_level ~= nil then
        return nil, "slide-level requires a handout or slides profile"
    end

    if config.slide_audience ~= nil then
        if config.profile ~= "slides" then
            return nil, "slide-audience requires the slides profile"
        end
        if config.slide_audience ~= "regular" and config.slide_audience ~= "dozent" then
            return nil, "slide-audience must be regular or dozent"
        end
        if config.slide_audience == "regular" then config.slide_audience = nil end
    end

    if config.h1 ~= nil then
        if config.profile ~= "slides" then return nil, "h1 requires the slides profile" end
        if config.h1 ~= "section" and config.h1 ~= "frame" and config.h1 ~= "hide" then
            return nil, "h1 must be section, frame or hide"
        end
        if config.h1 == "section" then config.h1 = nil end
    end
    if config.audience ~= nil and config.audience ~= "instructor" and config.audience ~= "student" then
        return nil, "audience must be student or instructor"
    end

    return config
end

self.resolve_config = resolve_config

self.get_output_path = function(input_path, cfg)
    local config, err = resolve_config(cfg)
    if not config then return nil, err end
    local path = fu.get_output_filename(input_path, config.save_dir)
    local variant = config.audience == "instructor" or config.slide_audience == "dozent"
    local suffix = config.profile and ("-" .. config.profile .. "-" .. config.slide_level) or ""
    if variant then suffix = suffix .. "-dozent" end
    if config.h1 then suffix = suffix .. "-h1-" .. config.h1 end
    return (path:gsub("%.tex$", suffix .. ".tex"))
end

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
    local config, config_error = resolve_config(cfg)
    if not config then return nil, config_error end

    -- Create mdtex directory if it does not exist
    local success, err = fu.create_directory(config.save_dir)
    if not success then
        return nil, err
    end

    -- Output file path
    local output_path = self.get_output_path(input_path, config)

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

	local ok, ast = pcall(parse, content, config, input_path)
	if not ok then return nil, ast end
	for _, warning in ipairs(ast.warnings or {}) do
		local subject = warning.identifier and ("footnote " .. warning.identifier)
			or warning.delimiter and ("delimiter " .. warning.delimiter) or ("environment " .. warning.environment)
		if warning.kind == "mismatched" then
			subject = subject .. " (expected \\end{" .. warning.expected_end .. "}, found \\end{" .. warning.actual_end .. "})"
		end
		local location = warning.line and (input_path .. ":" .. warning.line .. ":" .. warning.column .. ": ") or ""
		local action = warning.kind == "duplicate" and "; first definition used" or "; kept literal"
		io.stderr:write("mark2tex warning [" .. warning.category .. "] " .. location .. warning.kind .. " " .. subject .. action .. "\n")
	end
	if config.profile then ast = lecture.structure(ast, config) end
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
