local lpeg = require("lpeg")

local P, S, R, C, Cs, Ct, V = lpeg.P, lpeg.S, lpeg.R, lpeg.C, lpeg.Cs, lpeg.Ct, lpeg.V

local space = P(" ")^1
local hash = P("#")
local double_dollar = P("$$")
local newline = P("\n")
local rest_of_line = (P(1) - newline)^1
local escape = S"$`*\\" + P("[@") + P"_" + P"~~"

local outer_grammar = {}

--------------------
-- Header
--------------------

local header = V"header"

outer_grammar.header = newline * space^0 * Ct(C(hash^1) * space * C((P(1) - newline)^1)) / function(t) return {type = "header", level = #t[1], content = t[2]} end

--------------------
-- Latex Environment
--------------------

local latex_env = V"latex_env"
local latex_env_in_double_dollar = V"latex_env_in_double_dollar"
local double_dollar_env = V"double_dollar_env"
local beginend_env = V"beginend_env"
local begin_end = P("\\begin{") * (P(1) - P"}")^1 * P"}" * space^0 * (P(1) - P("\\end{"))^1 * P("\\end{") * (P(1) - P"}")^1 * P"}"

outer_grammar.latex_env_in_double_dollar = double_dollar * S(" \n")^0 * C(begin_end) * S(" \n")^0 * double_dollar
outer_grammar.double_dollar_env = C(double_dollar * (P(1) - double_dollar)^1 * double_dollar)
outer_grammar.beginend_env = C(begin_end)

outer_grammar.latex_env = newline * space^0 * (latex_env_in_double_dollar + double_dollar_env + beginend_env) / function(t) return {type = "latex", content = t} end

--------------------
-- Item
--------------------

local item = V"item"

local start_of_item = newline * C(S(" \t")^0) * S("-*+") * space
local follow_item_line = newline^1 * S(" \t")^1 * (P(1) - S("-*+#") - (R("09")^1 * S(".)"))) * rest_of_line

outer_grammar.item = Ct(start_of_item * C(rest_of_line * follow_item_line^0)) /
function(t) return {type = "item", level = #t[1], content = t[2]} end

--------------------
-- Enum
--------------------
local enum = V"enum"

local start_of_enum = newline * C(S(" \t")^0) * R("09")^1 * S(".)")
local follow_enum_line = newline^1 * S(" \t")^1 * (P(1) - S("-*+#") - (R("09")^1 * S(".)"))) * rest_of_line

outer_grammar.enum = Ct(start_of_enum * C(rest_of_line * follow_enum_line^0)) /
function(t) return {type = "enum", level = #t[1], content = t[2]} end

--------------------
-- Code
--------------------

local code = V"code"

outer_grammar.code = newline * P("`")^3 * C(rest_of_line^-1) * newline * C((P(1) - P("`")^3)^1) * P("`")^3 /
function(type, content) 
	if type == "tex" then
		return {type = "latex", content = content}
	else
		return {type = "code", code_type = type, content = content}
	end
end

--------------------
-- Other
--------------------

local other = V"other"
local outer_elements = V"outer_elements"
outer_grammar.outer_elements = header + code + latex_env + item + enum

outer_grammar.other = C((P(1) - outer_elements)^1) / function(t) return {type = "other", content = t} end


--------------------
-- Outer
--------------------

local outer = V"outer"
outer_grammar.outer = Ct((outer_elements + other)^0)

outer_grammar[1] = outer
outer_grammar = P(outer_grammar) * -1

--------------------

--- Inner Grammar

local inner_grammar = {}

-- Variables

local citation = V"citation"
local cite = V"cite"
local verbatim = V"verbatim"
local math = V"math"
local latex_cmd = V"latex_cmd"
local latex_cmd_in_verbatim = V"latex_cmd_in_verbatim"
local italic = V"italic"
local bold = V"bold"
local strikethrough = V"strikethrough"
local text = V"text"
local final_elements = V"final_elements"
local elements = V"elements"

--------------------
-- Citation
--------------------

inner_grammar.cite = C(P(1 - P";" - P"]")^1)
inner_grammar.citation = P"[@" * Ct(cite * (P"; @" + cite)^0) * P"]" /
function(t) return {type = "citation", content = t} end

--------------------
-- Verbatim
--------------------

inner_grammar.verbatim = P"`" * C((P(1) - P"`")^1) * P"`" / function(t) return {type = "verbatim", content = t} end

--------------------
-- Math
--------------------

inner_grammar.math = C(P"$" * (1 - P"$")^1 * P"$") / function(t) return {type = "math", content = t} end

--------------------
--- Latex Command
--------------------

inner_grammar.latex_cmd = C(P"\\" * (1 - S"{[ ")^1 * (S"[{]" * (1 - S"}]")^1 * S"]}")^0) /
function(t) return {type = "latex_cmd", content = t} end

inner_grammar.latex_cmd_in_verbatim = P"`" * C(P"\\" * (1 - S"{[ `")^1 * (S"[{]" * (1 - S"}]")^1 * S"]}")^0) * P"`" /
function(t) return {type = "latex_cmd", content = t} end

--------------------
-- Italic
--------------------

inner_grammar.italic_star = P"*" * Ct((final_elements + bold + text)^1) * P"*" / function(t) return {type = "italic", content = t} end

inner_grammar.italic_underline = P"_" * Ct((final_elements + bold + strikethrough + text)^1) * P"_" / function(t) return {type = "italic", content = t} end

inner_grammar.italic = inner_grammar.italic_star + inner_grammar.italic_underline

--------------------
-- Bold
--------------------

inner_grammar.bold_star = P"**" * Ct((final_elements + italic + strikethrough + text)^1) * P"**" / function(t) return {type = "bold", content = t} end

inner_grammar.bold_underline = P"__" * Ct((final_elements + italic + text)^1) * P"__" / function(t) return {type = "bold", content = t} end

inner_grammar.bold = inner_grammar.bold_star + inner_grammar.bold_underline

--------------------
-- Striketrough
-- ---------------

inner_grammar.strikethrough = P"~~" * Ct((final_elements + italic + bold + text)^1) * P"~~" / function(t) return {type = "strikethrough", content = t} end


--------------------
-- Text
--------------------

--inner_grammar.text = C((1 - elements)^1) / function(t) return {type = "text", content = t} end
inner_grammar.text = C((P(1) - escape)^1) / function(t) return {type = "text", content = t} end


--------------------
-- Inner
--------------------

inner_grammar.final_elements = citation + latex_cmd_in_verbatim + verbatim + math + latex_cmd
inner_grammar.elements = final_elements + italic + bold + strikethrough

inner_grammar[1] = Ct((elements + text)^0)

inner_grammar = P(inner_grammar) * -1

--------------------

local function parse_outer_ast(str)
    return outer_grammar:match(str)
end


local function parse_inner_ast(ast)
    for _, element in ipairs(ast) do
        if element.type == "header" or element.type == "item" or element.type == "enum" or element.type == "other" then
            element.content = inner_grammar:match(element.content)
        end
        ---table.insert(final_ast, element)
    end
    return ast
end

local function parse(str, config)
    str = "\n" .. str -- add newline to beginning of string to make parsing easier
    local outer_ast = parse_outer_ast(str)
    local inner_ast = parse_inner_ast(outer_ast)
    return inner_ast
end

return parse
