local delimiters = require("mark2tex.delimiters")
local spans = require("mark2tex.spans")
local nodes = require("mark2tex.nodes")
local type diagnostics = require("mark2tex.diagnostics")

local type Inline = nodes.Inline

local record Options
	allow_display: boolean
end

local enum WarningKind
	"empty"
	"unclosed"
	"display-in-table"
end

local enum WarningCategory
	"math-delimiter"
end

local record Warning is diagnostics.Issue
	category: WarningCategory
	kind: WarningKind
	delimiter: string
end

-- Types are exported as aliases: nested records would emit runtime tables.
local record math_parser
	type Options = Options
	type WarningCategory = WarningCategory
	type WarningKind = WarningKind
	type Warning = Warning
	expand_tokens: function({Inline}, {Inline}): {Inline}
end

local TOKEN_START = string.char(30) .. "M"
local TOKEN_END = string.char(31)

local function token(index: integer): string
	return TOKEN_START .. tostring(index) .. TOKEN_END
end

local function add_token(tokens: {Inline}, node: Inline): string
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
function math_parser.protect_inlines(input: string, options?: Options): string, {Inline}, {Warning}
	options = options or {}
	local allow_display = options.allow_display ~= false
	local tokens: {Inline} = {}
	local warnings: {Warning} = {}
	local output: {string} = {}
	local index = 1

	while index <= #input do
		local character = input:sub(index, index)
		-- Code spans and TeX commands with their arguments stay opaque, exactly as
		-- in every other pass (see spans).
		local opaque = (character == "`" and not delimiters.is_escaped(input, index)
			and spans.code_or_run_end(input, index))
			or (character == "\\" and spans.command_end(input, index))

		-- Delimiters pair exactly as in every other pass (spans.math_span).
		local opening, closing = spans.math_span(input, index)

		if opaque then
			output[#output + 1] = input:sub(index, opaque)
			index = opaque + 1
		elseif opening == "\\(" then
			if closing and closing > index + 2 then
				output[#output + 1] = add_token(tokens, nodes.inline_math(input:sub(index, closing + 1)))
				index = closing + 2
			else
				warn(warnings, closing and "empty" or "unclosed", "\\(")
				local ending = closing and closing + 1 or index + 1
				output[#output + 1] = add_token(tokens, nodes.text(input:sub(index, ending)))
				index = ending + 1
			end
		elseif opening == "\\[" then
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
		elseif opening == "$$" then
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
		elseif opening == "$" then
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

local function copy_with_content(node: Inline, content: string): Inline
	-- Carry through node fields owned by other parser stages.
	local copy: {string: any} = {}
	for key, value in pairs(node as {string: any}) do
		copy[key] = value
	end
	copy.content = content
	return copy as Inline
end

-- Split every node with string content at the math tokens and descend into
-- inline containers. Link and footnote nodes are only inserted afterwards.
local function expand_node(node: Inline, tokens: {Inline}): {Inline}
	local content = nodes.content(node)
	if content is string then
		local result: {Inline} = {}
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
	if node is nodes.Bold or node is nodes.Italic or node is nodes.Strikethrough
		or node is nodes.Link or node is nodes.Other then
		node.content = math_parser.expand_tokens(node.content, tokens)
	end
	return { node }
end

function math_parser.expand_tokens(ast: {Inline}, tokens: {Inline}): {Inline}
	local expanded: {Inline} = {}
	for _, node in ipairs(ast) do
		local replacement = expand_node(node, tokens)
		for _, value in ipairs(replacement) do
			expanded[#expanded + 1] = value
		end
	end
	return expanded
end

return math_parser
