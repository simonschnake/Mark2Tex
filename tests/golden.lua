-- Golden snapshot test: render every example and fixture input in several
-- profiles and compare the TeX with the snapshots in tests/golden/.
--
--   lua tests/golden.lua           check against the snapshots
--   lua tests/golden.lua --update  rewrite the snapshots after an intended change

package.path = "./src/?.lua;./src/?/init.lua;./?.lua;" .. package.path

local lfs = require("lfs")
local helpers = require("tests.helpers")
local parse = require("mark2tex.parse")
local write = require("mark2tex.write")
local lecture = require("mark2tex.lecture")
local core = require("mark2tex.core")

local GOLDEN_DIR = "tests/golden"
local INPUT_DIRS = { "examples", "tests" }
local SKIP_DIRS = { ["tests/golden"] = true, ["tests/tmp"] = true }

local VARIANTS = {
	{ name = "default", config = {} },
	{ name = "instructor", config = { audience = "instructor" } },
	{ name = "handout", config = { profile = "handout" } },
	{ name = "slides", config = { profile = "slides" } },
	{ name = "slides-dozent-h1-frame", config = { profile = "slides", slide_audience = "dozent", h1 = "frame" } },
	{ name = "slides-h1-hide-level-1", config = { profile = "slides", h1 = "hide", slide_level = 1 } },
}

local update = arg and arg[1] == "--update"

local function collect(directory, inputs)
	local entries = {}
	for entry in lfs.dir(directory) do
		if entry ~= "." and entry ~= ".." then entries[#entries + 1] = entry end
	end
	table.sort(entries)
	for _, entry in ipairs(entries) do
		local path = directory .. "/" .. entry
		local mode = lfs.attributes(path, "mode")
		if mode == "directory" and not SKIP_DIRS[path] then
			collect(path, inputs)
		elseif mode == "file" and (entry:match("%.md$") or (directory == "tests" and entry:match("%.test$"))) then
			inputs[#inputs + 1] = path
		end
	end
	return inputs
end

local function read_input(path)
	if path:match("%.test$") then
		local input, _, err = helpers.read_test_file(path)
		return assert(input, err)
	end
	return helpers.read_file(path)
end

local function render(source, path, variant)
	local config = assert(core.resolve_config(variant.config))
	local ok, result = pcall(function()
		local ast = parse(source, config, path)
		if config.profile then ast = lecture.structure(ast, config) end
		return write(ast, config)
	end)
	if ok then return result end
	return "%%% error: " .. tostring(result)
end

local function snapshot(path)
	local source = read_input(path)
	local parts = {}
	for _, variant in ipairs(VARIANTS) do
		parts[#parts + 1] = "%%% variant: " .. variant.name .. "\n" .. render(source, path, variant) .. "\n"
	end
	return table.concat(parts)
end

local function golden_path(path)
	return GOLDEN_DIR .. "/" .. path:gsub("/", "__") .. ".tex"
end

local function read_optional(path)
	local file = io.open(path, "r")
	if not file then return nil end
	local content = file:read("a")
	file:close()
	return content
end

local function first_difference(expected, actual)
	local expected_lines, actual_lines = helpers.split_lines(expected), helpers.split_lines(actual)
	for index = 1, math.max(#expected_lines, #actual_lines) do
		if expected_lines[index] ~= actual_lines[index] then
			return index, expected_lines[index] or "<end>", actual_lines[index] or "<end>"
		end
	end
end

lfs.mkdir(GOLDEN_DIR)
local inputs = {}
for _, directory in ipairs(INPUT_DIRS) do collect(directory, inputs) end

local expected_files, failures, written = {}, {}, 0
for _, path in ipairs(inputs) do
	local target = golden_path(path)
	expected_files[target] = true
	local actual = snapshot(path)
	local expected = read_optional(target)
	if expected ~= actual then
		if update then
			helpers.write_file(target, actual)
			written = written + 1
		elseif expected == nil then
			failures[#failures + 1] = target .. ": missing snapshot"
		else
			local line, want, got = first_difference(expected, actual)
			failures[#failures + 1] = ("%s:%d\n    expected: %s\n    actual:   %s"):format(target, line, want, got)
		end
	end
end

for entry in lfs.dir(GOLDEN_DIR) do
	local target = GOLDEN_DIR .. "/" .. entry
	if entry:match("%.tex$") and not expected_files[target] then
		if update then
			os.remove(target)
			written = written + 1
		else
			failures[#failures + 1] = target .. ": snapshot without input"
		end
	end
end

if update then
	print(("Golden snapshots: %d inputs, %d files updated"):format(#inputs, written))
elseif #failures > 0 then
	io.stderr:write(table.concat(failures, "\n"), "\n")
	io.stderr:write(("%d of %d golden snapshots differ; run `make golden-update` if the change is intended.\n")
		:format(#failures, #inputs))
	os.exit(1)
else
	print(("Golden snapshots: %d inputs x %d variants match"):format(#inputs, #VARIANTS))
end
