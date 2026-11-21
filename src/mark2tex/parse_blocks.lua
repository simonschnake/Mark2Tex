local lpeg = require("lpeg")
local nodes = require("mark2tex.nodes")
local links = require("mark2tex.links")

local P, S, R, C, Ct, V = lpeg.P, lpeg.S, lpeg.R, lpeg.C, lpeg.Ct, lpeg.V

local space = P(" ") ^ 1
local hash = P("#")
local double_dollar = P("$$")
local newline = P("\n")
local rest_of_line = (P(1) - newline) ^ 1
local horizontal_space = S(" \t") ^ 0
local line_end = #newline + -P(1)

local grammar = {}

-- Definitions are blocks, so fenced code and raw LaTeX remain untouched.
local footnote_indent = P("    ") + P("\t")
local footnote_continuation = newline * (horizontal_space * newline) ^ 0
	* footnote_indent * (P(1) - newline) ^ 0
grammar.footnote_definition = newline * P(" ") ^ -3 * P("[^")
	* C((P(1) - S("[] \t\r\n")) ^ 1) * P("]:")
	* C((P(1) - newline) ^ 0 * footnote_continuation ^ 0)
	/ function(identifier, content)
		content = content:gsub("\n    ", "\n"):gsub("\n\t", "\n")
		return nodes.footnote_definition(identifier, content:match("^%s*(.-)%s*$"))
	end

--------------------
-- Header
--------------------

grammar.header = newline
	* space ^ 0
	* Ct(C(hash ^ 1) * space * C((P(1) - newline) ^ 1))
	/ function(t)
		return nodes.header(#t[1], t[2])
	end

--------------------
-- Horizontal Rule
--------------------

-- Keep the rule line-oriented so that hyphens inside ordinary paragraphs and
-- table separator rows are not interpreted as horizontal rules.
grammar.horizontal_rule = newline
	* horizontal_space
	* P("-") ^ 3
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
	/ function(t)
		return nodes.latex(t)
	end

--------------------
-- Display Math
--------------------

local standalone_display_environments = {
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

local function display_node(content)
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
-- Item
--------------------

local start_of_item = newline * C(S(" \t") ^ 0) * S("-*+") * space
local continuation_list_marker = S("-*+") * space + R("09") ^ 1 * S(".)") + P("#") * space
local follow_item_line = newline ^ 1 * S(" \t") ^ 1 * (P(1) - continuation_list_marker) * rest_of_line ^ -1

grammar.item = Ct(start_of_item * C(rest_of_line * follow_item_line ^ 0))
	/ function(t)
		return nodes.item(#t[1], t[2])
	end

--------------------
-- Enum
--------------------

local start_of_enum = newline * C(S(" \t") ^ 0) * R("09") ^ 1 * S(".)")
local follow_enum_line = newline ^ 1 * S(" \t") ^ 1 * (P(1) - continuation_list_marker) * rest_of_line ^ -1

grammar.enum = Ct(start_of_enum * C(rest_of_line * follow_enum_line ^ 0))
	/ function(t)
		return nodes.enum(#t[1], t[2])
	end

--------------------
-- Code
--------------------

grammar.code = newline
	* P("`") ^ 3
	* C(rest_of_line ^ -1)
	* newline
	* C((P(1) - P("`") ^ 3) ^ 1)
	* P("`") ^ 3
	/ function(type, content)
		if type == "tex" then
			return nodes.latex(content)
		end
		return nodes.code(type, content)
	end

--------------------
-- Blockquote
--------------------

local quote_line = newline * P(">") * P(" ") ^ -1 * C(rest_of_line ^ -1)

grammar.blockquote = Ct(quote_line * quote_line ^ 0)
	/ function(lines)
		return nodes.blockquote(table.concat(lines, "\n"))
	end

--------------------
-- Table
--------------------

local function trim(value)
	return value:match("^%s*(.-)%s*$")
end

local function split_table_row(line)
	line = trim(line)
	if line:sub(1, 1) == "|" then
		line = line:sub(2)
	end
	if line:sub(-1) == "|" then
		line = line:sub(1, -2)
	end

	local cells = {}
	local cell_start = 1
	local in_math = false
	local scanned = links.mask_destinations(line)
	local in_code = false

	for index = 1, #line do
		local character = scanned:sub(index, index)
		local previous = index > 1 and line:sub(index - 1, index - 1) or ""

		if character == "`" and previous ~= "\\" and not in_math then
			in_code = not in_code
		elseif character == "$" and previous ~= "\\" and not in_code then
			in_math = not in_math
		elseif character == "|" and previous ~= "\\" and not in_math and not in_code then
			table.insert(cells, trim(line:sub(cell_start, index - 1)))
			cell_start = index + 1
		end
	end

	table.insert(cells, trim(line:sub(cell_start)))
	return cells
end

local function table_alignment(separator)
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
	/ function(header_line, separator, ...)
		local rows = { ... }
		local alignments = {}
		for _, cell in ipairs(split_table_row(separator)) do
			table.insert(alignments, table_alignment(cell))
		end
		for index, row in ipairs(rows) do
			rows[index] = split_table_row(row)
		end
		return nodes.table(split_table_row(header_line), alignments, rows)
	end

--------------------
-- Other
--------------------

-- Display math must be considered before a generic raw LaTeX environment.
-- Otherwise an environment such as `aligned` consumes its surrounding
-- delimiters and is emitted outside math mode.
grammar.outer_elements = V("footnote_definition") + V("table") + V("horizontal_rule") + V("header") + V("code") + V("display_math") + V("latex_env") + V("blockquote") + V("item") + V("enum")

grammar.other = C((P(1) - V("outer_elements")) ^ 1) / function(t)
	return nodes.other(t)
end

--------------------
-- Outer
--------------------

grammar.outer = Ct((V("outer_elements") + V("other")) ^ 0)
grammar[1] = V("outer")

local lecture = {}
for key, pattern in pairs(grammar) do
	lecture[key] = pattern
end

local Cp, Cmt, Carg = lpeg.Cp, lpeg.Cmt, lpeg.Carg
local end_of_paragraph = #(newline * horizontal_space * (newline + -P(1)) + -P(1))
local function standalone(pattern)
	return Cmt(Cp() * newline * pattern * horizontal_space * end_of_paragraph,
		function(subject, ending, start, node)
			local previous = start - 1
			while previous > 0 and subject:sub(previous, previous):match("[ \t\r]") do
				previous = previous - 1
			end
			if previous == 0 or subject:sub(previous, previous) == "\n" then
				return ending, node
			end
		end)
end

lecture.header = newline * C(P(" ") ^ 0) * C(hash ^ 1) * space * C(rest_of_line)
	/ function(indent, hashes, content)
		local heading = nodes.header(#hashes, content)
		heading.indented = indent ~= ""
		return heading
	end
lecture.slide_break = standalone(P("-") ^ 3 / function() return { type = "slide_break" } end)
lecture.slide_pause = standalone(P(". . .") / function() return { type = "slide_pause" } end)
lecture.slide_directive = newline * Cmt(
	C(P("MARKTWOTEXCOMMENT") * P("X") ^ 0 * R("09") ^ 1 * P("END")) * horizontal_space * line_end * Carg(1),
	function(_, ending, token, directives)
		if directives[token] and directives[token].type ~= "dozent" then
			return ending, directives[token]
		end
	end)
lecture.outer_elements = V("slide_break") + V("slide_pause") + V("slide_directive") + grammar.outer_elements

local classic_grammar = P(grammar) * -1
local lecture_grammar = P(lecture) * -1

local function parse_blocks(str, directives)
	if directives then
		return lecture_grammar:match(str, 1, directives)
	end
	return classic_grammar:match(str)
end

return parse_blocks
