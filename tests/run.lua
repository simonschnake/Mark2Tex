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

local luaunit = load_luaunit()
local core = require("marktex.core")
local parse = require("marktex.parse")
local write = require("marktex.write")
local default_config = require("marktex.default_config")

local TEST_DIR = "tests"
local FIXTURE_SEPARATOR = "^%.+$"

local function transform (markdown, config)
    config = config or default_config
    local ast = parse(markdown, config)
    return write(ast, config)
end

local function strip_newlines_at_start_and_end (str)
    return str:gsub("^[\n\r]+", ""):gsub("[\n\r]+$", "")
end

local function split_lines(content)
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

local function join_lines(lines, first, last)
    if last < first then
        return ""
    end

    return table.concat(lines, "\n", first, last)
end

local function read_test_file(filePath)
    local file = io.open(filePath, "r")
    if not file then
        return nil, nil, "unable to open fixture"
    end

    local content = file:read("*all")
    file:close()

    local lines = split_lines(content)

    for index, line in ipairs(lines) do
        if line:match(FIXTURE_SEPARATOR) then
            return join_lines(lines, 1, index - 1), join_lines(lines, index + 1, #lines)
        end
    end

    return nil, nil, "missing fixture separator line"
end

local function fixture_name(filePath)
    local name = filePath:match("([^/\\]-)%.test$")
    name = name or filePath:gsub("[/\\%.]", "_")
    return "test_" .. name:gsub("[^%w_]", "_")
end

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
    for filename in lfs.dir(TEST_DIR) do
        if filename:match("%.test$") then
            table.insert(files, TEST_DIR .. "/" .. filename)
        end
    end

    return files
end

local function list_fixtures_with_popen()
    local command = "find " .. TEST_DIR .. " -maxdepth 1 -type f -name '*.test' -print"
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
        local markdown, expectedLatex, err = read_test_file(filePath)
        luaunit.assertNotNil(markdown, filePath .. ": " .. tostring(err))
        luaunit.assertNotNil(expectedLatex, filePath .. ": " .. tostring(err))

        expectedLatex = strip_newlines_at_start_and_end(expectedLatex)
        local actualLatex = transform(markdown)
        actualLatex = strip_newlines_at_start_and_end(actualLatex)

        luaunit.assertEquals(actualLatex, expectedLatex)
    end
end

local fixtures = list_fixtures()
if #fixtures == 0 then
    error("no test fixtures found")
end

for _, filePath in ipairs(fixtures) do
    _G[fixture_name(filePath)] = create_test_case(filePath)
end

function test_config_overrides_do_not_mutate_defaults()
    local original_save_dir = default_config.save_dir
    local original_header_1 = default_config.header[1]

    local config = core.resolve_config({
        save_dir = "custom-output",
        header = { "chapter", "section" },
        citation = "autocite",
    })

    luaunit.assertEquals(config.save_dir, "custom-output")
    luaunit.assertEquals(config.header[1], "chapter")
    luaunit.assertEquals(config.header[2], "section")
    luaunit.assertEquals(config.citation, "autocite")
    luaunit.assertEquals(config.paren_citation, default_config.paren_citation)

    luaunit.assertEquals(default_config.save_dir, original_save_dir)
    luaunit.assertEquals(default_config.header[1], original_header_1)
    luaunit.assertEquals(default_config.citation, "cite")
end

function test_config_tables_are_not_shared()
    local config = core.resolve_config()

    config.header[1] = "chapter"

    luaunit.assertEquals(default_config.header[1], "section")
end

os.exit(luaunit.LuaUnit.run())
