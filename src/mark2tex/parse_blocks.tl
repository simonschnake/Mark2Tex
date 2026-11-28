local lpeg = require("lpeg")
local nodes = require("mark2tex.nodes")
local links = require("mark2tex.links")
local spans = require("mark2tex.spans")

local type RawBlock = nodes.RawBlock
local type Pattern = lpeg.Pattern
local type Grammar = {string | integer: Pattern}

local P, S, R, C, Ct, V = lpeg.P, lpeg.S, lpeg.R, lpeg.C, lpeg.Ct, lpeg.V

local space = P(" ") ^ 1
local hash = P("#")
local newline = P("\n")
local rest_of_line = (P(1) - newline) ^ 1
local horizontal_space = S(" \t") ^ 0
local line_end = #newline + -P(1)

local Cp, Cmt = lpeg.Cp, lpeg.Cmt
local colons = P(":") ^ 3
local name = (R("az", "AZ", "09") + S("_-")) ^ 1
local attributes = C(P("{") * (P(1) - S("}\n")) ^ 1 * P("}") + name)
local fence_body = horizontal_space * Cp() * C(colons)
	* horizontal_space * (attributes + C(P(""))) * horizontal_space * line_end
local fence = newline * fence_body

local grammar: Grammar = {}

-- Definitions are blocks, so fenced code and raw LaTeX remain untouched.
local footnote_indent = P("    ") + P("\t")
local footnote_continuation = newline * (horizontal_space * newline) ^ 0
	* -fence_body * footnote_indent * (P(1) - newline) ^ 0
grammar.footnote_definition = newline * P(" ") ^ -3 * P("[^")
	* C((P(1) - S("[] \t\r\n")) ^ 1) * P("]:")
	* C((P(1) - newline) ^ 0 * footnote_continuation ^ 0)
	/ function(identifier: string, content: string): RawBlock
		content = content:gsub("\n    ", "\n"):gsub("\n\t", "\n")
		return nodes.footnote_definition(identifier, content:match("^%s*(.-)%s*$"))
	end

--------------------
-- Header
--------------------

-- An optional closing sequence of #s after a space is not part of the text.
local function atx_content(content: string): string
	content = content:gsub("[ \t]+$", "")
	if content:match("^#+$") then return "" end
	return (content:gsub("[ \t]+#+$", ""))
end

grammar.header = newline
	* space ^ 0
	* Ct(C(hash ^ 1) * space * C((P(1) - newline) ^ 1))
	/ function(t: {string}): RawBlock
		return nodes.header(#t[1], atx_content(t[2]))
	end

--------------------
-- Horizontal Rule
--------------------

-- Keep the rule line-oriented so that hyphens inside ordinary paragraphs and
-- table separator rows are not interpreted as horizontal rules. Three or more
-- of -, * or _, optionally spaced; it takes precedence over a list item.
local function rule_run(character: string): Pattern
	return P(character) * (S(" \t") ^ 0 * P(character)) ^ 2
end
local thematic_break = rule_run("-") + rule_run("*") + rule_run("_")

grammar.horizontal_rule = newline
	* horizontal_space
	* thematic_break
	* horizontal_space
	* line_end
	/ nodes.horizontal_rule

--------------------
-- Latex Environment
--------------------

local begin_env = P("\\begin{")
	* (P(1) - P("}")) ^ 1
	* P("}")

local end_env = P("\\end{")
	* (P(1) - P("}")) ^ 1
	* P("}")

grammar.begin_end = begin_env * (V("begin_end_inner") + (1 - begin_env - end_env)) ^ 0 * end_env
grammar.begin_end_inner = V("begin_end") + (1 - (begin_env + end_env)) ^ 1

grammar.latex_env = newline
	* space ^ 0
	* V("begin_end")
	/ function(t: string): RawBlock
		return nodes.latex(t)
	end

--------------------
-- Display Math
--------------------

local standalone_display_environments: {string: boolean} = {
	align = true,
	["align*"] = true,
	alignat = true,
	["alignat*"] = true,
	displaymath = true,
	equation = true,
	["equation*"] = true,
	eqnarray = true,
	["eqnarray*"] = true,
	flalign = true,
	["flalign*"] = true,
	gather = true,
	["gather*"] = true,
	multline = true,
	["multline*"] = true,
}

local function display_node(content: string): RawBlock
	local environment, closing = content:match("^%s*\\begin{([^}]+)}.*\\end{([^}]+)}%s*$")
	if environment == closing and standalone_display_environments[environment] then
		return nodes.latex(content:match("^%s*(.-)%s*$"))
	end
	return nodes.display_math(content)
end

grammar.display_math_dollar = P("$$")
	* C((P(1) - P("$$")) ^ 1)
	* P("$$")
	/ display_node

grammar.display_math_bracket = P("\\[")
	* C((P(1) - P("\\]")) ^ 1)
	* P("\\]")
	/ display_node

grammar.display_math = newline
	* space ^ 0
	* (V("display_math_dollar") + V("display_math_bracket"))

--------------------
-- Lists
--------------------

-- Lists are container blocks and are read line by line: an item owns the
-- lines indented further than its marker and the blank lines between them.
-- Those lines, with the item's indentation removed (up to its content
-- column, as in CommonMark), are parsed as blocks of their own (by parse,
-- like blockquotes), so items hold paragraphs, code, quotes and nested
-- lists. Unlike CommonMark, a line without that indentation always ends the
-- item (no lazy continuation), a marker indented further than its item's
-- marker always nests, even short of the content column ("1. a" followed by
-- "  - b"), and any marker interrupts a paragraph.

-- The width of a line's leading whitespace in columns (tabs stop every four
-- columns) and the rest of the line.
local function indentation(line: string): integer, string
	local columns, index = 0, 1
	while true do
		local character = line:sub(index, index)
		if character == " " then
			columns = columns + 1
		elseif character == "\t" then
			columns = columns + 4 - columns % 4
		else
			break
		end
		index = index + 1
	end
	return columns, line:sub(index)
end

-- Remove up to count columns of indentation; deeper indentation stays.
local function strip_columns(line: string, count: integer): string
	local columns, rest = indentation(line)
	if columns <= count then return rest end
	return (" "):rep(columns - count) .. rest
end

local record Marker
	kind: string
	start: integer
	indent: integer
	-- The column where the item's content starts; continuation lines are
	-- indented at least this far.
	column: integer
	first: string
end

local MAX_COUNTER = 2147483647

-- A list marker starting the line: -, * or + (bullet), 1. or 1) (decimal) or
-- a) (alpha), followed by whitespace or the end of the line.
local function list_marker(line: string): Marker
	local indent, rest = indentation(line)
	local kind, marker, tail: string, string, string
	local start = 1
	local bullet, after_bullet = rest:match("^([-*+])(.*)$")
	if bullet then
		kind, marker, tail = "bullet", bullet, after_bullet
	else
		local digits, delimiter, after_digits = rest:match("^(%d+)([.)])(.*)$")
		if digits then
			-- TeX counters are signed 32-bit integers.
			local number = tonumber(digits)
			kind, marker, tail = "decimal", digits .. delimiter, after_digits
			start = (number <= MAX_COUNTER and number or 1) as integer
		else
			local letter, after_letter = rest:match("^(%l)%)(.*)$")
			if not letter then return nil end
			kind, marker, tail = "alpha", letter .. ")", after_letter
			start = letter:byte() - string.byte("a") + 1
		end
	end
	if tail ~= "" and not tail:match("^[ \t]") then return nil end
	local spaces, content = indentation(tail)
	local width = indent + #marker
	if content == "" then
		return { kind = kind, start = start, indent = indent, column = width + 1, first = "" }
	elseif spaces >= 5 then
		-- Content indented this far keeps all but one space.
		return { kind = kind, start = start, indent = indent, column = width + 1,
			first = (" "):rep(spaces - 1) .. content }
	end
	return { kind = kind, start = start, indent = indent, column = width + spaces, first = content }
end

local rule_line = horizontal_space * thematic_break * horizontal_space * -1

local function is_rule(line: string): boolean
	return lpeg.match(rule_line, line) ~= nil
end

-- The line starting at start and the index of the newline ending it (or one
-- past the end of the subject).
local function line_from(subject: string, start: integer): string, integer
	local stop = subject:find("\n", start, true) or #subject + 1
	return subject:sub(start, stop - 1), stop
end

local function blank(line: string): boolean
	return not line:find("%S")
end

-- line_start is the first line of the list, after a newline. Returns the
-- newline after its last non-blank line; trailing blank lines are not part
-- of the list.
local function scan_list(subject: string, line_start: integer): integer | boolean, RawBlock
	local position = line_start - 1
	local line, stop = line_from(subject, line_start)
	if is_rule(line) then return false end
	local marker = list_marker(line)
	if not marker then return false end
	if marker.first == "" and position > 1 then
		-- An empty item cannot interrupt a paragraph.
		local previous = subject:sub(1, position - 1):match("([^\n]*)$")
		if not blank(previous) then return false end
	end

	local list = nodes.raw_list(marker.kind, marker.start)
	local finish = stop
	while marker do
		local lines = { marker.first }
		local column, marker_indent = marker.column, marker.indent
		local pending = 0
		local next_start = stop + 1
		while next_start <= #subject do
			local text, text_stop = line_from(subject, next_start)
			local indent, rest = indentation(text)
			if rest == "" then
				-- An item that starts with a blank line ends at a second one.
				if #lines == 1 and lines[1] == "" then break end
				pending = pending + 1
			elseif indent > marker_indent then
				-- A code fence, as every pass reads it (spans), belongs to the
				-- item only as a whole; otherwise it ends the item.
				local fence_end = spans.line_fence_end(subject, next_start)
				if fence_end then
					text_stop = subject:find("\n", fence_end, true) or #subject + 1
					local fenced_lines: {string} = {}
					for fenced_line in subject:sub(next_start, text_stop - 1):gmatch("[^\n]*") do
						local fenced_indent, fenced_rest = indentation(fenced_line)
						if fenced_rest ~= "" and fenced_indent <= marker_indent then
							fenced_lines = nil
							break
						end
						fenced_lines[#fenced_lines + 1] = strip_columns(fenced_line, column)
					end
					if not fenced_lines then break end
					for _ = 1, pending do lines[#lines + 1] = "" end
					for _, fenced_line in ipairs(fenced_lines) do lines[#lines + 1] = fenced_line end
				else
					for _ = 1, pending do lines[#lines + 1] = "" end
					lines[#lines + 1] = strip_columns(text, column)
				end
				pending = 0
				finish = text_stop
			else
				break
			end
			next_start = text_stop + 1
		end
		list.content[#list.content + 1] = nodes.raw_list_item(table.concat(lines, "\n"))

		-- The next item of the same kind, possibly after blank lines.
		marker = nil
		while next_start <= #subject do
			local text, text_stop = line_from(subject, next_start)
			if not blank(text) then
				local sibling = not is_rule(text) and list_marker(text)
				if sibling and sibling.kind == list.kind then
					marker, stop, finish = sibling, text_stop, text_stop
				end
				break
			end
			next_start = text_stop + 1
		end
	end
	return finish, list
end

-- Only lines that look like a marker are scanned.
grammar.list = #(newline * horizontal_space * (S("-*+") + R("09") + R("az") * P(")")))
	* Cmt(newline, scan_list)

--------------------
-- Code
--------------------

-- A fence of three or more backticks or tildes, indented by up to three
-- spaces and closed by a run of the same character at least as long
-- (spans.line_fence_end, shared with every pass). As in CommonMark, the
-- opening fence's indentation is removed from each content line.
local function fenced(character: string): Pattern
	return newline * Cmt(Cp() * P(" ") ^ -3 * P(character) ^ 3 * C(rest_of_line ^ -1) * newline * Cp(),
		function(subject: string, _: integer, line_start: integer, info: string, content_start: integer): integer | boolean, string, string
			local finish, indent = spans.line_fence_end(subject, line_start)
			if not finish then return false end
			local closing = finish
			while subject:sub(closing - 1, closing - 1) == character do closing = closing - 1 end
			-- The closing run must follow the opening line; the block may be
			-- empty, as in CommonMark (a run on the opening line is no fence).
			if closing < content_start then return false end
			local content = subject:sub(content_start, closing - 1)
			if indent > 0 then
				content = ("\n" .. content):gsub("\n" .. (" ?"):rep(indent), "\n"):sub(2)
			end
			-- The closing fence's own indentation is not content.
			return finish + 1, info, (content:gsub("\n +$", "\n"))
		end)
end

grammar.code = (fenced("`") + fenced("~"))
	/ function(code_type: string, content: string): RawBlock
		if code_type == "tex" then
			return nodes.latex(content)
		end
		return nodes.code(code_type, content)
	end

--------------------
-- Blockquote
--------------------

-- Up to three spaces may precede the marker, as in CommonMark.
local quote_line = newline * P(" ") ^ -3 * P(">") * P(" ") ^ -1 * C(rest_of_line ^ -1)

grammar.blockquote = Ct(quote_line * quote_line ^ 0)
	/ function(lines: {string}): RawBlock
		return nodes.blockquote(table.concat(lines, "\n"))
	end

--------------------
-- Table
--------------------

local function trim(value: string): string
	return value:match("^%s*(.-)%s*$")
end

local function split_table_row(line: string): {string}
	line = trim(line)
	if line:sub(1, 1) == "|" then
		line = line:sub(2)
	end
	if line:sub(-1) == "|" then
		line = line:sub(1, -2)
	end

	local cells: {string} = {}
	local cell_start = 1
	local in_math = false
	local scanned = links.mask_destinations(line)
	local index = 1

	while index <= #line do
		local character = scanned:sub(index, index)
		local previous = index > 1 and line:sub(index - 1, index - 1) or ""

		if character == "`" and previous ~= "\\" and not in_math then
			-- Pipes inside a code span do not split cells (see spans).
			index = spans.code_or_run_end(scanned, index)
		elseif character == "$" and previous ~= "\\" then
			in_math = not in_math
		elseif character == "|" and previous ~= "\\" and not in_math then
			table.insert(cells, trim(line:sub(cell_start, index - 1)))
			cell_start = index + 1
		end
		index = index + 1
	end

	table.insert(cells, trim(line:sub(cell_start)))
	return cells
end

local function table_alignment(separator: string): string
	if separator:match("^:.*:$") then
		return "c"
	elseif separator:match(":$") then
		return "r"
	end
	return "l"
end

local table_line = C(#((P(1) - newline - P("|")) ^ 0 * P("|")) * (P(1) - newline) ^ 1)
local separator_cell = horizontal_space * P(":") ^ -1 * P("-") ^ 3 * P("-") ^ 0 * P(":") ^ -1 * horizontal_space
local separator_line = C(horizontal_space * P("|") ^ -1 * separator_cell * (P("|") * separator_cell) ^ 1 * P("|") ^ -1 * horizontal_space)

grammar.table = newline
	* table_line
	* newline
	* separator_line
	* (newline * table_line) ^ 0
	/ function(header_line: string, separator: string, ...: string): RawBlock
		local rows: {{string}} = {}
		local alignments: {string} = {}
		for _, cell in ipairs(split_table_row(separator)) do
			table.insert(alignments, table_alignment(cell))
		end
		for index, row in ipairs({ ... }) do
			rows[index] = split_table_row(row)
		end
		return nodes.table(split_table_row(header_line), alignments, rows)
	end

--------------------
-- Link reference definition
--------------------

-- A definition cannot interrupt a paragraph: the line before it is blank or
-- another definition. Definitions take a single line.
grammar.link_definition = Cmt(Cp() * newline * #(P(" ") ^ -3 * P("[") * -P("^")) * C(rest_of_line),
	function(subject: string, finish: integer, start: integer, line: string): integer | boolean, RawBlock
		local label, target = links.definition(line)
		if not label then return false end
		local previous_start = start - 1
		while previous_start > 0 and subject:sub(previous_start, previous_start) ~= "\n" do
			previous_start = previous_start - 1
		end
		local previous = subject:sub(previous_start + 1, start - 1)
		if previous:find("%S") and not links.definition(previous) then return false end
		return finish, { type = "link_definition", label = label, destination = target.destination, title = target.title }
	end)

--------------------
-- Other
--------------------

grammar.div_fence = (fence * Cp()) / function(position: integer, delimiter: string, attributes_text: string, ending: integer): RawBlock
	return { type = "div_fence", position = position, ending = ending,
		length = #delimiter, attributes = attributes_text }
end

-- A standalone image can carry a width or inherit its figure's width.
local image_path = C((P(1) - S("(){}%#\\\n")) ^ 1)
local em_width = R("09") ^ 1 * (P(".") * R("09") ^ 1) ^ -1 * P("em")
grammar.image = newline * horizontal_space * P("![") * (P(1) - S("]\n")) ^ 0
	* P("](") * image_path * P(")") * (P("{width=") * C(em_width) * P("}") + C(P("")))
	* horizontal_space * line_end / function(path: string, width: string): RawBlock
		return { type = "image", path = path, width = width }
	end

-- Display math must be considered before a generic raw LaTeX environment.
-- Otherwise an environment such as `aligned` consumes its surrounding
-- delimiters and is emitted outside math mode.
grammar.outer_elements = V("image") + V("footnote_definition") + V("link_definition") + V("table") + V("horizontal_rule") + V("header") + V("code") + V("display_math") + V("latex_env") + V("blockquote") + V("list")

grammar.other = C((P(1) - V("outer_elements")) ^ 1) / function(t: string): RawBlock
	return nodes.raw_other(t)
end

--------------------
-- Outer
--------------------

grammar.outer = Ct((V("outer_elements") + V("other")) ^ 0)
grammar[1] = V("outer")

local lecture: Grammar = {}
for key, pattern in pairs(grammar) do
	lecture[key] = pattern
end

local end_of_paragraph = #(newline * horizontal_space * (newline + -P(1)) + fence + -P(1))
local function standalone(pattern: Pattern): Pattern
	return Cmt(Cp() * newline * pattern * horizontal_space * end_of_paragraph,
		function(subject: string, ending: integer, start: integer, node: RawBlock): integer, RawBlock
			local previous = start - 1
			while previous > 0 and subject:sub(previous, previous):match("[ \t\r]") do
				previous = previous - 1
			end
			local before = subject:sub(1, start - 1):match("([^\n]*)$")
			if previous == 0 or subject:sub(previous, previous) == "\n"
				or lpeg.match(fence, "\n" .. before) then
				return ending, node
			end
		end)
end

lecture.header = newline * C(P(" ") ^ 0) * C(hash ^ 1) * space * C(rest_of_line)
	/ function(indent: string, hashes: string, content: string): RawBlock
		local heading = nodes.header(#hashes, atx_content(content))
		heading.indented = indent ~= ""
		return heading
	end
lecture.slide_break = standalone(thematic_break / function(): RawBlock return { type = "slide_break" } end)
lecture.slide_pause = standalone(P(". . .") / function(): RawBlock return { type = "slide_pause" } end)
local nested_grammar = P(grammar) * -1
grammar.outer_elements = V("div_fence") + grammar.outer_elements
lecture.outer_elements = V("slide_break") + V("slide_pause") + grammar.outer_elements

local classic_grammar = P(grammar) * -1
local lecture_grammar = P(lecture) * -1

-- A setext heading: paragraph lines underlined by a line of = signs (up to
-- three spaces indented). The --- underline stays a horizontal rule, and a
-- slide break in lecture profiles. Splits the paragraph text around it.
local function setext_headings(block: nodes.RawOther, result: {RawBlock})
	local content = block.content
	local paragraph_start: integer -- first character of the current paragraph line run
	local consumed = 1 -- content before this index has been emitted
	local position = 1
	while position <= #content do
		local line_end_index = content:find("\n", position, true) or #content + 1
		local line = content:sub(position, line_end_index - 1)
		local indent = line:match("^( *)=+[ \t]*$")
		if indent and #indent <= 3 and paragraph_start then
			-- Like an ATX heading, the heading owns the newline before it.
			local before = content:sub(consumed, paragraph_start - 2)
			if before:find("%S") then result[#result + 1] = nodes.raw_other(before) end
			local lines: {string} = {}
			for text in content:sub(paragraph_start, position - 2):gmatch("[^\n]+") do
				lines[#lines + 1] = text:match("^%s*(.-)%s*$")
			end
			result[#result + 1] = nodes.header(1, table.concat(lines, "\n"))
			consumed, paragraph_start = line_end_index, nil
		elseif line:find("%S") then
			paragraph_start = paragraph_start or position
		else
			paragraph_start = nil
		end
		position = line_end_index + 1
	end
	if consumed == 1 then
		result[#result + 1] = block
	elseif consumed <= #content then
		result[#result + 1] = nodes.raw_other(content:sub(consumed))
	end
end

-- Setext headings are found in the paragraphs the grammar leaves.
local function postprocess(blocks: {RawBlock}): {RawBlock}
	if not blocks then return blocks end
	local result: {RawBlock} = {}
	for _, block in ipairs(blocks) do
		if block is nodes.RawOther then
			setext_headings(block, result)
		else
			result[#result + 1] = block
		end
	end
	return result
end

local function parse_blocks(str: string, lecture_profile?: boolean, nested?: boolean): {RawBlock}
	if nested then return postprocess(nested_grammar:match(str) as {RawBlock}) end
	if lecture_profile then
		return postprocess(lecture_grammar:match(str) as {RawBlock})
	end
	return postprocess(classic_grammar:match(str) as {RawBlock})
end

return parse_blocks
