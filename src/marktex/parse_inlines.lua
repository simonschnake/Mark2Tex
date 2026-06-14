local lpeg = require("lpeg")
local nodes = require("marktex.nodes")

local P, S, C, Ct, V = lpeg.P, lpeg.S, lpeg.C, lpeg.Ct, lpeg.V

local newline = P("\n")
local escape = S("@$`*\\") + P("[@") + P("_") + P("~~")

local grammar = {}

--------------------
-- Citation
--------------------

grammar.cite = C(P(P(1) - S("\n;,] ")) ^ 1)
grammar.cite2 = C(P(P(1) - S("\n;, .] ")) ^ 1)
grammar.citation_start = P("[@") + P("[\n@")
grammar.citation_break = ((S(",; ") ^ 0 * newline) + S(",; ") ^ 1) * newline ^ 0 * P("@")

grammar.paren_citation = V("citation_start")
	* Ct(V("cite") * (V("citation_break") * V("cite")) ^ 0)
	* S(";, ") ^ 0
	* newline ^ 0
	* P("]")
	/ function(t)
		return nodes.paren_citation(t)
	end

grammar.citation = P("@") * V("cite2") / function(t)
	return nodes.citation(t)
end

--------------------
-- Verbatim
--------------------

grammar.verbatim = P("`")
	* C((P(1) - P("`")) ^ 1)
	* P("`")
	/ function(t)
		return nodes.verbatim(t)
	end

--------------------
-- Math
--------------------

grammar.math = C(P("$") * (1 - P("$")) ^ 1 * P("$")) / nodes.math

--------------------
-- Latex Command
--------------------

grammar.latex_cmd_in_verbatim = P("`")
	* C(P("\\") * (1 - S("{[ `")) ^ 1 * (V("brace_group") + V("bracket_group")) ^ 0)
	* P("`")
	/ function(t)
		return nodes.latex_cmd(t)
	end

grammar.brace_group = P("{") * (V("brace_group") + V("bracket_group") + (P(1) - S("{}[]"))) ^ 0 * P("}")
grammar.bracket_group = P("[") * (V("brace_group") + V("bracket_group") + (P(1) - S("{}[]"))) ^ 0 * P("]")

grammar.latex_cmd = C(P("\\") * (1 - S("{[ ")) ^ 1 * (V("brace_group") + V("bracket_group")) ^ 0)
	/ function(t)
		return nodes.latex_cmd(t)
	end

--------------------
-- Formatting
--------------------

grammar.italic_star = P("*")
	* Ct((V("final_elements") + V("bold") + V("text")) ^ 1)
	* P("*")
	/ function(t)
		return nodes.italic(t)
	end

grammar.italic_underline = P("_")
	* Ct((V("final_elements") + V("bold") + V("strikethrough") + V("text")) ^ 1)
	* P("_")
	/ function(t)
		return nodes.italic(t)
	end

grammar.italic = V("italic_star") + V("italic_underline")

grammar.bold_star = P("**")
	* Ct((V("final_elements") + V("italic") + V("strikethrough") + V("text")) ^ 1)
	* P("**")
	/ function(t)
		return nodes.bold(t)
	end

grammar.bold_underline = P("__")
	* Ct((V("final_elements") + V("italic") + V("text")) ^ 1)
	* P("__")
	/ function(t)
		return nodes.bold(t)
	end

grammar.bold = V("bold_star") + V("bold_underline")

grammar.strikethrough = P("~~")
	* Ct((V("final_elements") + V("italic") + V("bold") + V("text")) ^ 1)
	* P("~~")
	/ function(t)
		return nodes.strikethrough(t)
	end

--------------------
-- Text
--------------------

grammar.text = C((P(1) - escape) ^ 1) / function(t)
	return nodes.text(t)
end

--------------------
-- Inner
--------------------

grammar.final_elements = V("paren_citation") + V("citation") + V("latex_cmd_in_verbatim") + V("verbatim") + V("math") + V("latex_cmd")
grammar.elements = V("final_elements") + V("italic") + V("bold") + V("strikethrough")

grammar[1] = Ct((V("elements") + V("text")) ^ 0)
grammar = P(grammar) * -1

local function parse_inlines(str)
	local parsed = grammar:match(str)
	if parsed == nil then
		return { nodes.text(str) }
	end
	return parsed
end

return parse_inlines
