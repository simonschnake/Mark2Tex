local luaunit = require("luaunit")
local parse = require("parse")
local write = require("write")
local default_config = require("default_config")

local function transform (markdown, config)
    config = config or default_config
    local ast = parse(markdown, config)
    return write(ast, config)
end

local function strip_newlines_at_start_and_end (str)
    return str:gsub("^[\n\r]+", ""):gsub("[\n\r]+$", "")
end

-- Function to read and split test file content
local function readTestFile(filePath)
    local file = io.open(filePath, "r")
    if not file then return nil, nil end

    local content = file:read("*all")
    file:close()

    local input, expected = content:match("^(.*)\n%.+\n(.*)$")
    return input, expected
end

-- Function to create a test case for a file
local function createTestCase(filePath)
    return function()
        local markdown, expectedLatex = readTestFile(filePath)
        luaunit.assertNotNil(markdown)
        luaunit.assertNotNil(expectedLatex)

	expectedLatex = strip_newlines_at_start_and_end(expectedLatex)
        local actualLatex = transform(markdown)
	actualLatex = strip_newlines_at_start_and_end(actualLatex)

        luaunit.assertEquals(actualLatex, expectedLatex)
    end
end

-- Load all test files and create test cases
for filename in io.popen('ls tests/*.test'):lines() do
    local testName = 'test_' .. filename:match("([^/]-)%.test$")
    _G[testName] = createTestCase(filename)
end

-- Run the test suite
os.exit(luaunit.LuaUnit.run())
