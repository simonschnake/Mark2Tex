local lpeg = require("lpeg")
local nodes = require("mark2tex.nodes")
local math_parser = require("mark2tex.math")
local links = require("mark2tex.links")
local footnotes = require("mark2tex.footnotes")

local type diagnostics = require("mark2tex.diagnostics")
local type Issue = diagnostics.Issue
local type Inline = nodes.Inline

local record Options
	allow_display: boolean
	disable_links: boolean
	link_label: boolean
	disable_footnotes: boolean
	resolve_footnote: function(string): nodes.Footnote
end

local P, S, C, Ct, V = lpeg.P, lpeg.S, lpeg.C, lpeg.Ct, lpeg.V

local newline = P("\n")
local escape = S("@$`*\\") + P("[@") + P("_") + P("~~")

local grammar: {string | integer: lpeg.Pattern} = {}

--------------------
-- Citation
--------------------

grammar.cite = C(P(P(1) - S("\n;,] ")) ^ 1)
grammar.cite2 = C(P(P(1) - S("\n;, .] ")) ^ 1)
grammar.citation_start = P("[@") + P("[\n@")
grammar.citation_break = ((S(",; ") ^ 0 * newline) + S(",; ") ^ 1) * newline ^ 0 * P("@")
grammar.citation_locator = P(",") * S(" ") ^ 0 * C((P(1) - S("\n]")) ^ 1)

grammar.paren_citation = V("citation_start")
	* Ct(V("cite") * (V("citation_break") * V("cite")) ^ 0)
	* V("citation_locator") ^ -1
	* S(";, ") ^ 0
	* newline ^ 0
	* P("]")
	/ function(citations: {string}, locator: string): Inline
		return nodes.paren_citation(citations, locator)
	end

grammar.citation = P("@") * V("cite2") / function(t: string): Inline
	return nodes.citation(t)
end

--------------------
-- Verbatim
--------------------

grammar.verbatim = P("`")
	* C((P(1) - P("`")) ^ 1)
	* P("`")
	/ function(t: string): Inline
		return nodes.verbatim(t)
	end

--------------------
-- Math
--------------------

--------------------
-- Latex Command
--------------------

grammar.latex_cmd_in_verbatim = P("`")
	* C(P("\\") * (1 - S("{[ `")) ^ 1 * (V("brace_group") + V("bracket_group")) ^ 0)
	* P("`")
	/ function(t: string): Inline
		return nodes.latex_cmd(t)
	end

grammar.brace_group = P("{") * (V("brace_group") + V("bracket_group") + (P(1) - S("{}[]"))) ^ 0 * P("}")
grammar.bracket_group = P("[") * (V("brace_group") + V("bracket_group") + (P(1) - S("{}[]"))) ^ 0 * P("]")

grammar.latex_cmd = C(P("\\") * (1 - S("{[ ")) ^ 1 * (V("brace_group") + V("bracket_group")) ^ 0)
	/ function(t: string): Inline
		return nodes.latex_cmd(t)
	end

--------------------
-- Formatting
--------------------

grammar.italic_star = P("*")
	* Ct((V("final_elements") + V("bold") + V("text")) ^ 1)
	* P("*")
	/ function(t: {Inline}): Inline
		return nodes.italic(t)
	end

grammar.italic_underline = P("_")
	* Ct((V("final_elements") + V("bold") + V("strikethrough") + V("text")) ^ 1)
	* P("_")
	/ function(t: {Inline}): Inline
		return nodes.italic(t)
	end

grammar.italic = V("italic_star") + V("italic_underline")

grammar.bold_star = P("**")
	* Ct((V("final_elements") + V("italic") + V("strikethrough") + V("text")) ^ 1)
	* P("**")
	/ function(t: {Inline}): Inline
		return nodes.bold(t)
	end

grammar.bold_underline = P("__")
	* Ct((V("final_elements") + V("italic") + V("text")) ^ 1)
	* P("__")
	/ function(t: {Inline}): Inline
		return nodes.bold(t)
	end

grammar.bold = V("bold_star") + V("bold_underline")

grammar.strikethrough = P("~~")
	* Ct((V("final_elements") + V("italic") + V("bold") + V("text")) ^ 1)
	* P("~~")
	/ function(t: {Inline}): Inline
		return nodes.strikethrough(t)
	end

--------------------
-- Text
--------------------

grammar.text = C((P(1) - escape) ^ 1) / function(t: string): Inline
	return nodes.text(t)
end

--------------------
-- Inner
--------------------

grammar.final_elements = V("paren_citation") + V("citation") + V("latex_cmd_in_verbatim") + V("verbatim") + V("latex_cmd")
grammar.elements = V("final_elements") + V("italic") + V("bold") + V("strikethrough")

grammar[1] = Ct((V("elements") + V("text")) ^ 0)
local inline_pattern = P(grammar) * -1

local function parse_inlines(str: string, options?: Options): {Inline}, {Issue}
	options = options or {}
	local footnote_protected, footnote_tokens, footnote_warnings = footnotes.protect(str, options.resolve_footnote, function(content: string): {Inline}, {Issue}
		return parse_inlines(content, { disable_footnotes = true })
	end, options.disable_footnotes)
	local link_protected, link_tokens, link_warnings = links.protect(footnote_protected, function(label: string): {Inline}, {Issue}
		return parse_inlines(label, { allow_display = false, disable_links = true, link_label = true, disable_footnotes = true })
	end, { disable_links = options.disable_links, link_label = options.link_label })
	local protected, tokens, math_warnings = math_parser.protect_inlines(link_protected, { allow_display = options.allow_display })
	local warnings: {Issue} = {}
	for _, warning in ipairs(math_warnings) do warnings[#warnings + 1] = warning end
	for _, warning in ipairs(link_warnings) do warnings[#warnings + 1] = warning end
	for _, warning in ipairs(footnote_warnings) do warnings[#warnings + 1] = warning end
	local parsed = inline_pattern:match(protected) as {Inline}
	if parsed == nil then
		parsed = { nodes.text(protected) }
	end
	return links.expand(links.expand(math_parser.expand_tokens(parsed, tokens), link_tokens), footnote_tokens), warnings
end

return parse_inlines
