-- Recognize links before math/formatting, keeping destinations opaque.
local autolinks = require("mark2tex.autolinks")
local delimiters = require("mark2tex.delimiters")
local placeholders = require("mark2tex.tokens")
local spans = require("mark2tex.spans")
local nodes = require("mark2tex.nodes")

local type Match = autolinks.Match
local type Inline = nodes.Inline

-- The target of a link reference definition.
local record Reference
	destination: string
	title: string
end

local record Options
	disable_links: boolean
	link_label: boolean
	-- Looks up a normalized reference label (see links.normalize_label).
	resolve_reference: function(string): Reference
end

-- Placeholder token in the protected source and the node it stands for.
local record Token
	token: string
	node: Inline
end

-- Types are exported as aliases: nested records would emit runtime tables.
local record links
	type Token = Token
	type Reference = Reference
	protected_end: function(source: string, position: integer): integer
end

local punctuation = "!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~"

local function unescape(value: string): string
	return (value:gsub("\\(.)", function(character: string): string
		return punctuation:find(character, 1, true) and character or "\\" .. character
	end))
end

-- Skip code, complete math and raw TeX command arguments during link scanning.
-- The rules live in spans, which every pass shares.
local function protected_end(source: string, position: integer): integer
	local character = source:sub(position, position)
	if character == "`" and not delimiters.is_escaped(source, position) then
		return spans.code_or_run_end(source, position)
	end
	local opening, closing = spans.math_span(source, position)
	if opening then
		-- An unclosed delimiter is skipped as a whole, as the math pass does.
		return closing and closing + #spans.math_closer(opening) - 1 or position + #opening - 1
	end
	if character == "\\" then
		local command = spans.command_end(source, position)
		if command then return command end
		if punctuation:find(source:sub(position + 1, position + 1), 1, true) then
			return position + 1
		end
	end
	return nil
end

local function spaces(source: string, index: integer): integer, boolean
	local start, lines = index, 0
	while source:sub(index, index):match("[ \t\r\n]") do
		if source:sub(index, index) == "\n" then lines = lines + 1 end
		index = index + 1
	end
	if lines > 1 then return nil end
	return index, index > start
end

-- Recover a malformed inline-link candidate as literal source, without hiding
-- following formatting after an unclosed destination.
-- Returns the end of the candidate and the index of its closing label bracket.
local function malformed_end(source: string, position: integer): integer, integer
	if source:sub(position, position) ~= "[" then return nil end
	-- Only the bracket that closes this label counts, skipping code, math and
	-- nested brackets; a later "](" on the line belongs to another candidate.
	local depth, label_end = 1, position + 1
	while label_end <= #source do
		local character = source:sub(label_end, label_end)
		local protected = protected_end(source, label_end)
		if character == "\n" then return nil end
		if protected then
			label_end = protected + 1
		else
			if character == "[" then depth = depth + 1 end
			if character == "]" then depth = depth - 1 end
			if depth == 0 then break end
			label_end = label_end + 1
		end
	end
	if depth ~= 0 or source:sub(label_end + 1, label_end + 1) ~= "(" then return nil end
	local finish = source:find(")", label_end + 2, true)
	local newline = source:find("\n", label_end + 2, true)
	if finish and (not newline or finish < newline) then return finish, label_end end
	local space = source:find("[ \t\r\n]", label_end + 2)
	return space and space - 1 or #source, label_end
end

-- The source of a construct that is not a link here, with the part after the
-- label as literal characters so URL characters cannot break the TeX.
local function literal_suffix(source: string, first: integer, last: integer): Inline
	local kept: {Inline} = {}
	local text = source:sub(first, last)
	local index = 1
	while index <= #text do
		local character = text:sub(index, index)
		local token_end = placeholders.markers:sub(1, 1) == character and text:find(placeholders.markers:sub(2, 2), index, true)
		if token_end then
			-- A placeholder of an earlier pass stays whole, so it is still expanded.
			kept[#kept + 1] = nodes.text(text:sub(index, token_end))
			index = token_end + 1
		else
			kept[#kept + 1] = nodes.literal(character)
			index = index + 1
		end
	end
	return nodes.other(kept)
end

local function suffix(source: string, start: integer): Match
	local index = spaces(source, start)
	if not index then return nil end
	local first, last = index, index - 1
	if source:sub(index, index) == "<" then
		first, index = index + 1, index + 1
		while index <= #source do
			local c = source:sub(index, index)
			if c == "\\" and punctuation:find(source:sub(index + 1, index + 1), 1, true) then
				index = index + 2
			elseif c == ">" then break
			elseif c == "<" or c == "\n" or c == "\r" then return nil
			else index = index + 1 end
		end
		if source:sub(index, index) ~= ">" then return nil end
		last, index = index - 1, index + 1
	else
		local depth = 0
		while index <= #source do
			local c = source:sub(index, index)
			if c == "\\" and punctuation:find(source:sub(index + 1, index + 1), 1, true) then
				index = index + 2
			elseif c == "(" then
				depth, index = depth + 1, index + 1
				if depth > 128 then return nil end
			elseif c == ")" and depth > 0 then depth, index = depth - 1, index + 1
			elseif c == ")" or c:match("[%z\1-\32\127]") then break
			elseif c == "<" or c == ">" then return nil
			else index = index + 1 end
		end
		if depth ~= 0 then return nil end
		last = index - 1
	end
	local destination = unescape(source:sub(first, last))
	local separated: boolean
	index, separated = spaces(source, index)
	if not index then return nil end
	local title: string
	local quote = source:sub(index, index)
	if separated and (quote == '"' or quote == "'" or quote == "(") then
		local finish = quote == "(" and ")" or quote
		local title_start = index + 1
		index = title_start
		while index <= #source do
			local c = source:sub(index, index)
			if c == "\\" and punctuation:find(source:sub(index + 1, index + 1), 1, true) then index = index + 2
			elseif c == finish then break
			elseif quote == "(" and c == "(" then return nil
			else index = index + 1 end
		end
		if source:sub(index, index) ~= finish then return nil end
		local raw = source:sub(title_start, index - 1)
		if raw:find("\n[ \t\r]*\n") then return nil end
		title = unescape(raw)
		index = spaces(source, index + 1)
	end
	if not index or source:sub(index, index) ~= ")" then return nil end
	return { destination = destination, title = title, finish = index }
end

-- Reference labels match case-insensitively, with whitespace runs collapsed.
function links.normalize_label(label: string): string
	return (label:gsub("%s+", " "):gsub("^ ", ""):gsub(" $", ""):lower())
end

-- A link reference definition on one line, [label]: destination "title".
-- Returns the normalized label and its target, or nil for any other line.
function links.definition(line: string): string, Reference
	local indent, rest = line:match("^( *)(%[.*)$")
	if not rest or #indent > 3 or rest:sub(2, 2) == "^" then return nil end
	local index = 2
	while index <= #rest do
		local c = rest:sub(index, index)
		if c == "\\" then index = index + 2
		elseif c == "[" then return nil
		elseif c == "]" then break
		else index = index + 1 end
	end
	if rest:sub(index, index + 1) ~= "]:" then return nil end
	local label = rest:sub(2, index - 1)
	if not label:find("%S") or #label > 999 then return nil end
	-- The inline-link suffix parser reads "destination title)", so close the
	-- line with a parenthesis that must be the one it stops at.
	local destination_start = rest:find("%S", index + 2)
	if not destination_start then return nil end
	local closed = rest:gsub("%s+$", "") .. ")"
	local result = suffix(closed, index + 2)
	if not result or result.finish ~= #closed then return nil end
	if result.destination == "" and rest:sub(destination_start, destination_start + 1) ~= "<>" then return nil end
	return links.normalize_label(label), { destination = result.destination, title = result.title }
end

-- After a label: [label](destination), [label][reference], [label][] or the
-- shortcut [label]. References only match a definition from resolve.
local function reference_suffix(source: string, position: integer, label_end: integer,
	resolve: function(string): Reference): Match
	local label = source:sub(position + 1, label_end - 1)
	local key, finish = label, label_end
	if source:sub(label_end + 1, label_end + 1) == "[" then
		local close = source:find("]", label_end + 2, true)
		local reference = close and source:sub(label_end + 2, close - 1)
		if reference and not reference:find("[%[\n]") then
			if reference:find("%S") then key = reference end
			finish = close
		end
	end
	if not key:find("%S") then return nil end
	local target = resolve(links.normalize_label(key))
	if not target then return nil end
	return { destination = target.destination, title = target.title, label = label,
		kind = "inline", label_end = label_end, finish = finish }
end

function links.match(source: string, position: integer, resolve?: function(string): Reference): Match
	if source:sub(position, position) == "<" then
		return autolinks.match(source, position)
	end
	if source:sub(position, position) ~= "[" then return nil end
	local index, depth = position + 1, 1
	while index <= #source do
		local c = source:sub(index, index)
		local last = protected_end(source, index)
		if last then index = last + 1
		elseif c == "[" then
			depth, index = depth + 1, index + 1
			if depth > 128 then return nil end
		elseif c == "]" then
			depth = depth - 1
			if depth == 0 then break end
			index = index + 1
		else index = index + 1 end
	end
	if depth ~= 0 then return nil end
	local result = source:sub(index + 1, index + 1) == "(" and suffix(source, index + 2)
	if not result then
		return resolve and reference_suffix(source, position, index, resolve) or nil
	end
	result.label, result.kind, result.label_end = source:sub(position + 1, index - 1), "inline", index
	return result
end

-- Image paths go to \includegraphics, which takes local files only; TeX
-- metacharacters would break its argument.
local function image_path(destination: string): boolean
	return destination ~= "" and not destination:match("^[%a][%w+.-]*:")
		and not destination:find("[%%#{}\\%^~]")
end

local em_width = "^{width=(%d+%.?%d*em)}"


-- Label warnings come from the inline parser and are passed through unchanged.
function links.protect<W>(source: string, parse_label: function(string): ({Inline}, {W}), options?: Options): string, {Token}, {W}
	options = options or {}
	local prefix = placeholders.prefix(source, "L")
	local tokens: {Token} = {}
	local output: {string} = {}
	local warnings: {W} = {}
	local index = 1
	local function add(node: Inline)
		local token = placeholders.make(prefix, #tokens + 1)
		tokens[#tokens + 1] = { token = token, node = node }
		output[#output + 1] = token
	end
	-- For a candidate that is not a link here, scanning continues inside its
	-- label (so nested constructs are handled) and its "](destination" part,
	-- registered by start index, is kept as literal characters.
	local literal_until: {integer: integer} = {}
	while index <= #source do
		local literal_end = literal_until[index]
		local last = not literal_end and protected_end(source, index)
		local match = not literal_end and not last and links.match(source, index, options.resolve_reference)
		local malformed, malformed_label: integer, integer
		if not literal_end and not last and not match then malformed, malformed_label = malformed_end(source, index) end
		if literal_end then
			add(literal_suffix(source, index, literal_end))
			index = literal_end + 1
		elseif match then
			local image = index > 1 and source:sub(index - 1, index - 1) == "!" and not delimiters.is_escaped(source, index - 1)
				and output[#output] == "!" and match.kind == "inline"
			if image and image_path(match.destination) then
				-- The "!" was copied as a character of its own.
				output[#output] = nil
				local width = source:match(em_width, match.finish + 1)
				add(nodes.inline_image(match.destination, width))
				index = match.finish + 1 + (width and #"{width=}" + #width or 0)
			elseif image or options.disable_links then
				-- Not a link here (an image, or a link inside a link label).
				output[#output + 1] = source:sub(index, index)
				literal_until[match.label_end + 1] = match.finish
				index = index + 1
			else
				local content: {Inline} = { nodes.text(match.label) }
				if match.kind == "inline" then
					local label_warnings: {W}
					content, label_warnings = parse_label(match.label)
					for _, warning in ipairs(label_warnings) do warnings[#warnings + 1] = warning end
				end
				add(nodes.link(match.destination, content, match.title, match.kind))
				index = match.finish + 1
			end
		elseif malformed then
			-- A broken link: the label stays inline text.
			output[#output + 1] = source:sub(index, index)
			literal_until[malformed_label + 1] = malformed
			index = index + 1
		elseif options.link_label and not (last and source:sub(index, index + 1) == "\\(") and source:sub(index, index) == "\\" and punctuation:find(source:sub(index + 1, index + 1), 1, true) then
			add(nodes.literal(source:sub(index + 1, index + 1)))
			index = index + 2
		elseif last then
			output[#output + 1] = source:sub(index, last)
			index = last + 1
		else
			output[#output + 1] = source:sub(index, index)
			index = index + 1
		end
	end
	return table.concat(output), tokens, warnings
end

-- Replace placeholder tokens in text nodes, descending into inline containers.
-- Footnote nodes are only inserted by the last expansion, so never descended.
function links.expand(ast: {Inline}, tokens: {Token}): {Inline}
	local result: {Inline} = {}
	for _, node in ipairs(ast) do
		if node is nodes.Text then
			local content = node.content
			local position = 1
			while position <= #content do
				local first, last: integer, integer
				local replacement: Inline
				for _, token in ipairs(tokens) do
					local start, finish = content:find(token.token, position, true)
					if start and (not first or start < first) then first, last, replacement = start, finish, token.node end
				end
				if not first then result[#result + 1] = nodes.text(content:sub(position)); break end
				if first > position then result[#result + 1] = nodes.text(content:sub(position, first - 1)) end
				result[#result + 1], position = replacement, last + 1
			end
		else
			if node is nodes.Bold or node is nodes.Italic or node is nodes.Strikethrough
				or node is nodes.Link or node is nodes.Other then
				node.content = links.expand(node.content, tokens)
			end
			result[#result + 1] = node
		end
	end
	return result
end

-- Keep diagnostic line/column offsets while hiding destinations and titles.
function links.mask_destinations(source: string): string
	local output: {string} = {}
	local index = 1
	while index <= #source do
		local last = protected_end(source, index)
		local match = not last and links.match(source, index)
		if match then
			output[#output + 1] = source:sub(index, match.label_end)
			output[#output + 1] = source:sub(match.label_end + 1, match.finish):gsub("[^\r\n]", " ")
			index = match.finish + 1
		elseif last then output[#output + 1], index = source:sub(index, last), last + 1
		else output[#output + 1], index = source:sub(index, index), index + 1 end
	end
	return table.concat(output)
end

-- detokenize handles TeX metacharacters even inside previously read arguments.
-- Uchar is expandable in LuaTeX and preserves otherwise unrepresentable bytes.
function links.tex_destination(value: string): string
	local output: {string} = {}
	local start = 1
	for index = 1, #value do
		local c = value:sub(index, index)
		if c:find("[%%#{}\\%^]") then
			if index > start then output[#output + 1] = "\\detokenize{" .. value:sub(start, index - 1) .. "}" end
			output[#output + 1] = (c == "%" or c == "#") and "\\" .. c or "\\Uchar" .. c:byte() .. " "
			start = index + 1
		end
	end
	if start <= #value then output[#output + 1] = "\\detokenize{" .. value:sub(start) .. "}" end
	return table.concat(output)
end

-- Shared by inline extensions so code, math and TeX stay opaque.
links.protected_end = protected_end

return links
