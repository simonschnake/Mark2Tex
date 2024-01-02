local dump = require("pl.pretty").dump
local parse = require("parse")
local default_config = require("default_config")

local function dump_ast (markdown, config)
    config = config or default_config
    local ast = parse(markdown, config)
    dump(ast)
end

-- Function to read and split test file content
local function dump_markdown(filePath)
    local file = io.open(filePath, "r")
    if not file then return nil, nil end

    local content = file:read("*all")
    file:close()

    local input, expected = content:match("^(.*)\n%.+\n(.*)$")
    
    dump_ast(input)
end

-- Check if the file path was provided as an argument
if not arg[1] then
    print("Please provide the file path as an argument.")
    os.exit(1)  -- Exit if no argument is given
end

-- The first argument is the path to the test file
local filePath = arg[1]

dump_markdown(filePath)
