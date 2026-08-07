local lpeg = require("lpeg")
local nodes = require("mark2tex.nodes")

local P, S, R, C, Ct, V = lpeg.P, lpeg.S, lpeg.R, lpeg.C, lpeg.Ct, lpeg.V

local space = P(" ") ^ 1
local hash = P("#")
local double_dollar = P("$$")
local newline = P("\n")
local rest_of_line = (P(1) - newline) ^ 1
local horizontal_space = S(" \t") ^ 0

local grammar = {}

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

grammar.latex_env_in_double_dollar = double_dollar * S(" \n") ^ 0 * C(V("begin_end")) * S(" \n") ^ 0 * double_dollar
grammar.double_dollar_env = C(double_dollar * (P(1) - double_dollar) ^ 1 * double_dollar)

grammar.latex_env = newline
	* space ^ 0
	* (V("latex_env_in_double_dollar") + V("double_dollar_env") + V("begin_end"))
	/ function(t)
		return nodes.latex(t)
	end

--------------------
-- Item
--------------------

local start_of_item = newline * C(S(" \t") ^ 0) * S("-*+") * space
local follow_item_line = newline ^ 1 * S(" \t") ^ 1 * (P(1) - S("-*+#") - (R("09") ^ 1 * S(".)"))) * rest_of_line

grammar.item = Ct(start_of_item * C(rest_of_line * follow_item_line ^ 0))
	/ function(t)
		return nodes.item(#t[1], t[2])
	end

--------------------
-- Enum
--------------------

local start_of_enum = newline * C(S(" \t") ^ 0) * R("09") ^ 1 * S(".)")
local follow_enum_line = newline ^ 1 * S(" \t") ^ 1 * (P(1) - S("-*+#") - (R("09") ^ 1 * S(".)"))) * rest_of_line

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
	local in_code = false

	for index = 1, #line do
		local character = line:sub(index, index)
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

grammar.outer_elements = V("table") + V("header") + V("code") + V("latex_env") + V("blockquote") + V("item") + V("enum")

grammar.other = C((P(1) - V("outer_elements")) ^ 1) / function(t)
	return nodes.other(t)
end

--------------------
-- Outer
--------------------

grammar.outer = Ct((V("outer_elements") + V("other")) ^ 0)
grammar[1] = V("outer")
grammar = P(grammar) * -1

local function parse_blocks(str)
	return grammar:match(str)
end

return parse_blocks
