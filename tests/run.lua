local cli_args = arg or {}
arg = {}

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
            local position = 1
            local max = math.min(#tostring(actual), #tostring(expected))

            while position <= max and actual:sub(position, position) == expected:sub(position, position) do
                position = position + 1
            end

            error(
                "\nexpected:\n" .. tostring(expected) ..
                "\nactual:\n" .. tostring(actual) ..
                "\nfirst difference at byte " .. position,
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
package.path = "./?.lua;" .. package.path

local luaunit = load_luaunit()
local helpers = require("tests.helpers")

local function list_fixtures_from_args()
    if #cli_args == 0 then
        return nil
    end

    local files = {}
    for _, filePath in ipairs(cli_args) do
        table.insert(files, filePath)
    end

    return files
end

local function list_fixtures_with_lfs()
    local ok, lfs = pcall(require, "lfs")
    if not ok then
        return nil
    end

    local files = {}
    for filename in lfs.dir(helpers.TEST_DIR) do
        if filename:match("%.test$") then
            table.insert(files, helpers.TEST_DIR .. "/" .. filename)
        end
    end

    return files
end

local function list_fixtures_with_popen()
    local command = "find " .. helpers.TEST_DIR .. " -maxdepth 1 -type f -name '*.test' -print"
    local handle = io.popen(command)
    if not handle then
        return nil
    end

    local files = {}
    for filePath in handle:lines() do
        table.insert(files, filePath)
    end
    handle:close()

    return files
end

local function list_fixtures()
    local files = list_fixtures_from_args() or list_fixtures_with_lfs() or list_fixtures_with_popen()
    files = files or {}
    table.sort(files)
    return files
end

local function create_test_case(filePath)
    return function()
        local markdown, expectedLatex, err = helpers.read_test_file(filePath)
        luaunit.assertNotNil(markdown, filePath .. ": " .. tostring(err))
        luaunit.assertNotNil(expectedLatex, filePath .. ": " .. tostring(err))

        expectedLatex = helpers.strip_newlines_at_start_and_end(expectedLatex)
        local actualLatex = helpers.transform(markdown)
        actualLatex = helpers.strip_newlines_at_start_and_end(actualLatex)

        luaunit.assertEquals(actualLatex, expectedLatex)
    end
end

local fixtures = list_fixtures()
if #fixtures == 0 then
    error("no test fixtures found")
end

for _, filePath in ipairs(fixtures) do
    _G[helpers.fixture_name(filePath)] = create_test_case(filePath)
end

require("tests.unit_config")(luaunit)
require("tests.unit_core")(luaunit)
require("tests.unit_ast")(luaunit)
require("tests.unit_tables")(luaunit)

os.exit(luaunit.LuaUnit.run())
