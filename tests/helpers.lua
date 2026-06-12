local parse = require("marktex.parse")
local write = require("marktex.write")
local default_config = require("marktex.default_config")

local helpers = {
	TEST_DIR = "tests",
	FIXTURE_SEPARATOR = "^%.+$",
	TMP_DIR = "tests/tmp",
}

function helpers.transform(markdown, config)
	config = config or default_config
	local ast = parse(markdown, config)
	return write(ast, config)
end

function helpers.strip_newlines_at_start_and_end(str)
	return str:gsub("^[\n\r]+", ""):gsub("[\n\r]+$", "")
end

function helpers.split_lines(content)
	local lines = {}
	local start = 1

	while true do
		local newline = content:find("\n", start, true)
		if not newline then
			table.insert(lines, content:sub(start))
			break
		end

		table.insert(lines, content:sub(start, newline - 1))
		start = newline + 1
	end

	return lines
end

function helpers.join_lines(lines, first, last)
	if last < first then
		return ""
	end

	return table.concat(lines, "\n", first, last)
end

function helpers.read_test_file(filePath)
	local file = io.open(filePath, "r")
	if not file then
		return nil, nil, "unable to open fixture"
	end

	local content = file:read("*all")
	file:close()

	local lines = helpers.split_lines(content)

	for index, line in ipairs(lines) do
		if line:match(helpers.FIXTURE_SEPARATOR) then
			return helpers.join_lines(lines, 1, index - 1), helpers.join_lines(lines, index + 1, #lines)
		end
	end

	return nil, nil, "missing fixture separator line"
end

function helpers.fixture_name(filePath)
	local name = filePath:match("([^/\\]-)%.test$")
	name = name or filePath:gsub("[/\\%.]", "_")
	return "test_" .. name:gsub("[^%w_]", "_")
end

function helpers.write_file(path, content)
	local file = assert(io.open(path, "w"))
	file:write(content)
	file:close()
end

function helpers.file_exists(path)
	local lfs = require("lfs")
	return lfs.attributes(path) ~= nil
end

function helpers.read_file(path)
	local file = assert(io.open(path, "r"))
	local content = file:read("*a")
	file:close()
	return content
end

function helpers.assert_node(luaunit, node, node_type)
	luaunit.assertNotNil(node)
	luaunit.assertEquals(node.type, node_type)
end

function helpers.find_node(nodes, node_type)
	for _, node in ipairs(nodes) do
		if node.type == node_type then
			return node
		end
	end
	return nil
end

return helpers
