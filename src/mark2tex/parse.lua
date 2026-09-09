local parse_blocks = require("mark2tex.parse_blocks")
local parse_inlines = require("mark2tex.parse_inlines")
local diagnostics = require("mark2tex.diagnostics")

local INLINE_BLOCK_TYPES = {
	header = true,
	item = true,
	enum = true,
	other = true,
}

local function normalize_input(str)
	return "\n" .. str
end

local function same_warning(left, right)
	return left.category == right.category
		and left.kind == right.kind
		and left.delimiter == right.delimiter
		and left.environment == right.environment
end

local function append_warning(warnings, candidate)
	for _, existing in ipairs(warnings) do
		if same_warning(existing, candidate) then
			return
		end
	end
	warnings[#warnings + 1] = candidate
end

local function add_inline_nodes(ast, warnings)
	local function parse_content(content, options)
		local parsed, content_warnings = parse_inlines(content, options)
		for _, warning in ipairs(content_warnings) do
			append_warning(warnings, warning)
		end
		return parsed
	end

	for _, element in ipairs(ast) do
		if element.type == "blockquote" then
			element.content = add_inline_nodes(parse_blocks(normalize_input(element.content)), warnings)
		elseif element.type == "table" then
			for index, cell in ipairs(element.headers) do
				element.headers[index] = parse_content(cell, { allow_display = false })
			end
			for _, row in ipairs(element.rows) do
				for index, cell in ipairs(row) do
					row[index] = parse_content(cell, { allow_display = false })
				end
			end
		elseif INLINE_BLOCK_TYPES[element.type] then
			element.content = parse_content(element.content)
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
	local warnings = diagnostics.collect(str)
	local inline_ast = add_inline_nodes(block_ast, warnings)
	inline_ast.warnings = warnings
	return normalize_ast(inline_ast)
end

return parse
