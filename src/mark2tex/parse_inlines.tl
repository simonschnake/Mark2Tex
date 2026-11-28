local lpeg = require("lpeg")
local nodes = require("mark2tex.nodes")
local math_parser = require("mark2tex.math")
local links = require("mark2tex.links")
local footnotes = require("mark2tex.footnotes")
local placeholders = require("mark2tex.tokens")
local spans = require("mark2tex.spans")

local type diagnostics = require("mark2tex.diagnostics")
local type Issue = diagnostics.Issue
local type Inline = nodes.Inline

local record Options
	allow_display: boolean
	disable_links: boolean
	link_label: boolean
	disable_footnotes: boolean
	resolve_footnote: function(string): nodes.Footnote
	resolve_reference: function(string): links.Reference
end

local P, S, C, Ct, V, Cp, Cmt = lpeg.P, lpeg.S, lpeg.C, lpeg.Ct, lpeg.V, lpeg.Cp, lpeg.Cmt

local newline = P("\n")
-- Placeholder frames: no key or command name may run into a placeholder.
local marker = S(placeholders.markers)
local escape = S("@$`*\\") + P("[@") + P("_") + P("~~")

local grammar: {string | integer: lpeg.Pattern} = {}

--------------------
-- Citation
--------------------

grammar.cite = C(P(P(1) - S("\n;,] `\\{}") - marker) ^ 1)
grammar.cite2 = C(P(P(1) - S("\n;, .] `\\{}") - marker) ^ 1)
grammar.citation_start = P("[@") + P("[\n@")
grammar.citation_break = ((S(",; ") ^ 0 * newline) + S(",; ") ^ 1) * newline ^ 0 * P("@")
grammar.citation_locator = P(",") * S(" ") ^ 0 * C((P(1) - S("\n]`") - marker) ^ 1)

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

-- A single-backtick span holding exactly one TeX command stays raw TeX.
local command_only: {string | integer: lpeg.Pattern} = {}
command_only.command = P("\\") * (1 - S("{[ `") - marker) ^ 1 * (V("brace") + V("bracket")) ^ 0 * -1
command_only.brace = P("{") * (V("brace") + V("bracket") + (P(1) - S("{}[]"))) ^ 0 * P("}")
command_only.bracket = P("[") * (V("brace") + V("bracket") + (P(1) - S("{}[]"))) ^ 0 * P("]")
command_only[1] = V("command")
local raw_command = P(command_only)

-- Code spans follow spans.code_end, the rule every pass shares: n backticks
-- up to the next run of exactly n. With several backticks one space on each
-- side is stripped, so a span can start or end with a backtick.
grammar.code_span = Cmt(Cp() * P("`"), function(subject: string, _: integer, start: integer): integer | boolean, string, integer
	local finish = spans.code_end(subject, start)
	if not finish then return false end
	local run = spans.run_length(subject, start)
	return finish + 1, subject:sub(start + run, finish - run), run
end) / function(content: string, run: integer): Inline
	if run == 1 and raw_command:match(content) then
		return nodes.latex_cmd(content)
	end
	if run > 1 and content:match("^ .* $") and content:find("[^ ]") then
		content = content:sub(2, -2)
	end
	return nodes.verbatim(content)
end

--------------------
-- Math
--------------------

--------------------
-- Latex Command
--------------------


-- Markdown escapes for punctuation that means nothing (or only something in
-- math or tabbing) to TeX. Escapes TeX shares, such as \# or \_, stay raw
-- TeX, as do \- (hyphenation), \[ (display math) and the accent commands.
local markdown_escapes: {string: boolean} = {
	["*"] = true, ["+"] = true, ["<"] = true, [">"] = true, ["|"] = true, ["?"] = true,
}

-- Raw TeX: a command with its arguments exactly as spans.command_end (and so
-- every scanner) delimits it, or a control symbol such as \] or \\ on its own.
grammar.latex_cmd = Cmt(Cp() * P("\\"), function(subject: string, _: integer, start: integer): integer | boolean, Inline
	local finish = spans.command_end(subject, start)
	if finish then return finish + 1, nodes.latex_cmd(subject:sub(start, finish)) end
	local symbol = subject:sub(start + 1, start + 1)
	-- A backslash with nothing to escape, at the end of a heading or before
	-- a placeholder, would escape a brace the writer adds after it.
	if symbol == "" or placeholders.markers:find(symbol, 1, true) then
		return start + 1, nodes.literal("\\")
	end
	-- \`{e} is the grave accent; otherwise \` is a literal backtick.
	if markdown_escapes[symbol] or (symbol == "`" and subject:sub(start + 2, start + 2) ~= "{") then
		return start + 2, nodes.literal(symbol)
	end
	return start + 2, nodes.latex_cmd(subject:sub(start, start + 1))
end)

-- A backslash at the end of a line breaks the line, unless the paragraph
-- ends there. \\ is consumed as a pair by latex_cmd first.
grammar.line_break = P("\\") * newline * #(S(" \t") ^ 0 * (P(1) - newline)) / function(): Inline
	return nodes.line_break()
end

--------------------
-- Formatting
--------------------

-- Simplified CommonMark flanking rules: an opening delimiter is not followed
-- by whitespace and a closing one not preceded by it. Underscores also may
-- not open or close inside a word, so snake_case_names stay literal.
local word = "[%w\128-\255]"

local function opener(delimiter: string, intraword: boolean): lpeg.Pattern
	return Cmt(P(delimiter), function(subject: string, position: integer): boolean
		local following = subject:sub(position, position)
		if following == "" or following:match("%s") then return false end
		return intraword or not subject:sub(position - #delimiter - 1, position - #delimiter - 1):match(word)
	end)
end

local function closer(delimiter: string, intraword: boolean): lpeg.Pattern
	return Cmt(P(delimiter), function(subject: string, position: integer): boolean
		local preceding = subject:sub(position - #delimiter - 1, position - #delimiter - 1)
		if preceding == "" or preceding:match("%s") then return false end
		return intraword or not subject:sub(position, position):match(word)
	end)
end

grammar.italic_star = opener("*", true)
	* Ct((V("final_elements") + V("bold") + V("text")) ^ 1)
	* closer("*", true)
	/ function(t: {Inline}): Inline
		return nodes.italic(t)
	end

grammar.italic_underline = opener("_", false)
	* Ct((V("final_elements") + V("bold") + V("strikethrough") + V("text")) ^ 1)
	* closer("_", false)
	/ function(t: {Inline}): Inline
		return nodes.italic(t)
	end

grammar.italic = V("italic_star") + V("italic_underline")

grammar.bold_star = opener("**", true)
	* Ct((V("final_elements") + V("italic") + V("strikethrough") + V("text")) ^ 1)
	* closer("**", true)
	/ function(t: {Inline}): Inline
		return nodes.bold(t)
	end

grammar.bold_underline = opener("__", false)
	* Ct((V("final_elements") + V("italic") + V("text")) ^ 1)
	* closer("__", false)
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

grammar.final_elements = V("paren_citation") + V("citation") + V("code_span") + V("line_break") + V("latex_cmd")
grammar.elements = V("final_elements") + V("italic") + V("bold") + V("strikethrough")

-- A special character that starts no construct (an unclosed `*`, a trailing
-- backslash) stays literal instead of failing the whole paragraph.
grammar.stray = C(P("[@") + P("`") ^ 1 + S("@$*\\_[~")) / function(t: string): Inline
	return nodes.text(t)
end

grammar[1] = Ct((V("elements") + V("text") + V("stray")) ^ 0)
local inline_pattern = P(grammar) * -1

-- Join neighbouring text nodes, e.g. around a literal stray character.
local function merge_text(list: {Inline}): {Inline}
	local merged: {Inline} = {}
	for _, node in ipairs(list) do
		local previous = merged[#merged]
		if node is nodes.Text and previous and previous is nodes.Text then
			merged[#merged] = nodes.text(previous.content .. node.content)
		else
			merged[#merged + 1] = node
		end
	end
	return merged
end

local function parse_inlines(str: string, options?: Options): {Inline}, {Issue}
	options = options or {}
	local footnote_protected, footnote_tokens, footnote_warnings = footnotes.protect(str, options.resolve_footnote, function(content: string): {Inline}, {Issue}
		return parse_inlines(content, { disable_footnotes = true, resolve_reference = options.resolve_reference })
	end, options.disable_footnotes)
	local link_protected, link_tokens, link_warnings = links.protect(footnote_protected, function(label: string): {Inline}, {Issue}
		return parse_inlines(label, { allow_display = false, disable_links = true, link_label = true, disable_footnotes = true })
	end, { disable_links = options.disable_links, link_label = options.link_label,
		resolve_reference = options.resolve_reference })
	local protected, tokens, math_warnings = math_parser.protect_inlines(link_protected, { allow_display = options.allow_display })
	local warnings: {Issue} = {}
	for _, warning in ipairs(math_warnings) do warnings[#warnings + 1] = warning end
	for _, warning in ipairs(link_warnings) do warnings[#warnings + 1] = warning end
	for _, warning in ipairs(footnote_warnings) do warnings[#warnings + 1] = warning end
	local parsed = inline_pattern:match(protected) as {Inline}
	if parsed == nil then
		parsed = { nodes.text(protected) }
	end
	local expanded = links.expand(links.expand(math_parser.expand_tokens(parsed, tokens), link_tokens), footnote_tokens)
	return merge_text(expanded), warnings
end

return parse_inlines
