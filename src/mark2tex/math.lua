local nodes = require("mark2tex.nodes")

local self = {}

local TOKEN_START = string.char(30) .. "M"
local TOKEN_END = string.char(31)

local function is_escaped(input, position)
	local slashes = 0
	local index = position - 1
	while index >= 1 and input:sub(index, index) == "\\" do
		slashes = slashes + 1
		index = index - 1
	end
	return slashes % 2 == 1
end

local function find_unescaped(input, delimiter, start)
	local index = start
	while true do
		index = input:find(delimiter, index, true)
		if not index or not is_escaped(input, index) then
			return index
		end
		index = index + #delimiter
	end
end

local function token(index)
	return TOKEN_START .. tostring(index) .. TOKEN_END
end

local function add_token(tokens, node)
	tokens[#tokens + 1] = node
	return token(#tokens)
end

local function warn(warnings, kind, delimiter)
	warnings[#warnings + 1] = {
		category = "math-delimiter",
		kind = kind,
		delimiter = delimiter,
	}
end

-- Protect math before the general inline grammar runs.  This keeps Markdown
-- markers inside math literal and lets malformed delimiters coexist with other
-- inline constructs instead of making the entire line fall back to plain text.
function self.protect_inlines(input, options)
	options = options or {}
	local allow_display = options.allow_display ~= false
	local tokens = {}
	local warnings = {}
	local output = {}
	local index = 1
	local in_code = false

	while index <= #input do
		local character = input:sub(index, index)

		if character == "`" and not is_escaped(input, index) then
			in_code = not in_code
			output[#output + 1] = character
			index = index + 1
		elseif in_code then
			output[#output + 1] = character
			index = index + 1
		elseif input:sub(index, index + 1) == "\\(" and not is_escaped(input, index) then
			local closing = find_unescaped(input, "\\)", index + 2)
			if closing and closing > index + 2 then
				output[#output + 1] = add_token(tokens, nodes.inline_math(input:sub(index, closing + 1)))
				index = closing + 2
			else
				warn(warnings, closing and "empty" or "unclosed", "\\(")
				local ending = closing and closing + 1 or index + 1
				output[#output + 1] = add_token(tokens, nodes.text(input:sub(index, ending)))
				index = ending + 1
			end
		elseif input:sub(index, index + 1) == "\\[" and not is_escaped(input, index) then
			local closing = find_unescaped(input, "\\]", index + 2)
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
		elseif input:sub(index, index + 1) == "$$" and not is_escaped(input, index) then
			local closing = find_unescaped(input, "$$", index + 2)
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
		elseif character == "$" and not is_escaped(input, index) then
			local closing = find_unescaped(input, "$", index + 1)
			while closing and input:sub(closing, closing + 1) == "$$" do
				closing = find_unescaped(input, "$", closing + 2)
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

local function copy_with_content(node, content)
	local copy = {}
	for key, value in pairs(node) do
		copy[key] = value
	end
	copy.content = content
	return copy
end

local function expand_node(node, tokens)
	if type(node.content) == "string" then
		local result = {}
		local position = 1
		while true do
			local first, last, number = node.content:find(TOKEN_START .. "(%d+)" .. TOKEN_END, position)
			if not first then
				if position <= #node.content then
					result[#result + 1] = copy_with_content(node, node.content:sub(position))
				end
				break
			end
			if first > position then
				result[#result + 1] = copy_with_content(node, node.content:sub(position, first - 1))
			end
			result[#result + 1] = tokens[tonumber(number)]
			position = last + 1
		end
		return result
	end
	if type(node.content) == "table" then
		node.content = self.expand_tokens(node.content, tokens)
	end
	return { node }
end

function self.expand_tokens(ast, tokens)
	local expanded = {}
	for _, node in ipairs(ast) do
		local replacement = expand_node(node, tokens)
		for _, value in ipairs(replacement) do
			expanded[#expanded + 1] = value
		end
	end
	return expanded
end

return self
