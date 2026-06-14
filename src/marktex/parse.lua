local parse_blocks = require("marktex.parse_blocks")
local parse_inlines = require("marktex.parse_inlines")

local INLINE_BLOCK_TYPES = {
	header = true,
	item = true,
	enum = true,
	other = true,
}

local function normalize_input(str)
	return "\n" .. str
end

local function add_inline_nodes(ast)
	for _, element in ipairs(ast) do
		if INLINE_BLOCK_TYPES[element.type] then
			element.content = parse_inlines(element.content)
		end
	end
	return ast
end

local function normalize_ast(ast)
	return ast
end

local function parse(str, config)
	local input = normalize_input(str)
	local block_ast = parse_blocks(input)
	local inline_ast = add_inline_nodes(block_ast)
	return normalize_ast(inline_ast)
end

return parse
