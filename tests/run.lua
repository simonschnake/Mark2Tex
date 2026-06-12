local function load_luaunit()
    local ok, luaunit = pcall(require, "luaunit")
    if ok then
        return luaunit
    end

    local fallback = {}

    function fallback.assertNotNil(value)
        if value == nil then
            error("expected value not to be nil", 2)
        end
    end

    function fallback.assertEquals(actual, expected)
        if actual ~= expected then
            error(
                "\nexpected:\n" .. tostring(expected) ..
                "\nactual:\n" .. tostring(actual),
                2
            )
        end
    end

    fallback.LuaUnit = {}

    function fallback.LuaUnit.run()
        local test_names = {}
        local total = 0
        local failed = 0

        for name, test in pairs(_G) do
            if type(name) == "string" and name:match("^test_") and type(test) == "function" then
                table.insert(test_names, name)
            end
        end

        table.sort(test_names)

        for _, name in ipairs(test_names) do
            local test = _G[name]
            total = total + 1
            io.write(name .. " ... ")

            local ok, err = pcall(test)
            if ok then
                io.write("ok\n")
            else
                failed = failed + 1
                io.write("failed\n" .. err .. "\n")
            end
        end

        print(string.format("%d tests, %d failures", total, failed))

        if failed == 0 then
            return 0
        end
        return 1
    end

    return fallback
end

package.path = "./src/?.lua;./src/?/init.lua;" .. package.path

local luaunit = load_luaunit()
local parse = require("marktex.parse")
local write = require("marktex.write")
local default_config = require("marktex.default_config")

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
