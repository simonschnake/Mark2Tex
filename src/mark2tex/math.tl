local delimiters = require("mark2tex.delimiters")
local nodes = require("mark2tex.nodes")
local type diagnostics = require("mark2tex.diagnostics")

local type Node = nodes.Node

local record Options
	allow_display: boolean
end

local enum WarningKind
	"empty"
	"unclosed"
	"display-in-table"
end

local record Warning is diagnostics.Issue
	category: string
	kind: WarningKind
	delimiter: string
end

-- Types are exported as aliases: nested records would emit runtime tables.
local record math_parser
	type Options = Options
	type WarningKind = WarningKind
	type Warning = Warning
	type Node = Node
	expand_tokens: function({Node}, {Node}): {Node}
end

local TOKEN_START = string.char(30) .. "M"
local TOKEN_END = string.char(31)

local function token(index: integer): string
	return TOKEN_START .. tostring(index) .. TOKEN_END
end

local function add_token(tokens: {Node}, node: Node): string
	tokens[#tokens + 1] = node
	return token(#tokens)
end

local function warn(warnings: {Warning}, kind: WarningKind, delimiter: string)
	warnings[#warnings + 1] = {
		category = "math-delimiter",
		kind = kind,
		delimiter = delimiter,
	}
end

-- Protect math before the general inline grammar runs.  This keeps Markdown
-- markers inside math literal and lets malformed delimiters coexist with other
-- inline constructs instead of making the entire line fall back to plain text.
function math_parser.protect_inlines(input: string, options?: Options): string, {Node}, {Warning}
	options = options or {}
	local allow_display = options.allow_display ~= false
	local tokens: {Node} = {}
	local warnings: {Warning} = {}
	local output: {string} = {}
	local index = 1
	local in_code = false

	while index <= #input do
		local character = input:sub(index, index)

		if character == "`" and not delimiters.is_escaped(input, index) then
			in_code = not in_code
			output[#output + 1] = character
			index = index + 1
		elseif in_code then
			output[#output + 1] = character
			index = index + 1
		elseif input:sub(index, index + 1) == "\\(" and not delimiters.is_escaped(input, index) then
			local closing = delimiters.find_unescaped(input, "\\)", index + 2)
			if closing and closing > index + 2 then
				output[#output + 1] = add_token(tokens, nodes.inline_math(input:sub(index, closing + 1)))
				index = closing + 2
			else
				warn(warnings, closing and "empty" or "unclosed", "\\(")
				local ending = closing and closing + 1 or index + 1
				output[#output + 1] = add_token(tokens, nodes.text(input:sub(index, ending)))
				index = ending + 1
			end
		elseif input:sub(index, index + 1) == "\\[" and not delimiters.is_escaped(input, index) then
			local closing = delimiters.find_unescaped(input, "\\]", index + 2)
			if closing and closing > index + 2 and allow_display then
				output[#output + 1] = add_token(tokens, nodes.display_math(input:sub(index + 2, closing - 1)))
				index = closing + 2
			elseif closing and closing > index + 2 then
				warn(warnings, "display-in-table", "\\[")
				output[#output + 1] = add_token(tokens, nodes.text(input:sub(index, closing + 1)))
				index = closing + 2
			else
				warn(warnings, closing and "empty" or "unclosed", "\\[")
				local ending = closing and closing + 1 or index + 1
				output[#output + 1] = add_token(tokens, nodes.text(input:sub(index, ending)))
				index = ending + 1
			end
		elseif input:sub(index, index + 1) == "$$" and not delimiters.is_escaped(input, index) then
			local closing = delimiters.find_unescaped(input, "$$", index + 2)
			if closing and closing > index + 2 and allow_display then
				output[#output + 1] = add_token(tokens, nodes.display_math(input:sub(index + 2, closing - 1)))
				index = closing + 2
			elseif closing and closing > index + 2 then
				warn(warnings, "display-in-table", "$$")
				output[#output + 1] = add_token(tokens, nodes.text(input:sub(index, closing + 1)))
				index = closing + 2
			else
				warn(warnings, closing and "empty" or "unclosed", "$$")
				local ending = closing and closing + 1 or index + 1
				output[#output + 1] = add_token(tokens, nodes.text(input:sub(index, ending)))
				index = ending + 1
			end
		elseif character == "$" and not delimiters.is_escaped(input, index) then
			local closing = delimiters.find_unescaped(input, "$", index + 1)
			while closing and input:sub(closing, closing + 1) == "$$" do
				closing = delimiters.find_unescaped(input, "$", closing + 2)
			end
			if closing and closing > index + 1 then
				output[#output + 1] = add_token(tokens, nodes.inline_math(input:sub(index, closing)))
				index = closing + 1
			else
				warn(warnings, closing and "empty" or "unclosed", "$")
				local ending = closing or index
				output[#output + 1] = add_token(tokens, nodes.text(input:sub(index, ending)))
				index = ending + 1
			end
		else
			output[#output + 1] = character
			index = index + 1
		end
	end

	return table.concat(output), tokens, warnings
end

local function copy_with_content(node: Node, content: string): Node
	-- Carry through node fields owned by other parser stages.
	local copy: {string: any} = {}
	for key, value in pairs(node as {string: any}) do
		copy[key] = value
	end
	copy.content = content
	return copy as Node
end

local function expand_node(node: Node, tokens: {Node}): {Node}
	local content = node.content
	if content is string then
		local result: {Node} = {}
		local position = 1
		while true do
			local first, last, number = content:find(TOKEN_START .. "(%d+)" .. TOKEN_END, position)
			if not first then
				if position <= #content then
					result[#result + 1] = copy_with_content(node, content:sub(position))
				end
				break
			end
			if first > position then
				result[#result + 1] = copy_with_content(node, content:sub(position, first - 1))
			end
			result[#result + 1] = tokens[tonumber(number) as integer]
			position = last + 1
		end
		return result
	end
	if content is {Node} then
		node.content = math_parser.expand_tokens(content, tokens)
	end
	return { node }
end

function math_parser.expand_tokens(ast: {Node}, tokens: {Node}): {Node}
	local expanded: {Node} = {}
	for _, node in ipairs(ast) do
		local replacement = expand_node(node, tokens)
		for _, value in ipairs(replacement) do
			expanded[#expanded + 1] = value
		end
	end
	return expanded
end

return math_parser
