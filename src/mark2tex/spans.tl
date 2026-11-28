-- The one set of rules every pass uses to decide what is code, math or raw
-- TeX: comment protection, diagnostics, footnotes, links, math, the inline
-- grammar and table cells. Passes that disagree desynchronise each other, so
-- no pass may scan these constructs on its own.

local delimiters = require("mark2tex.delimiters")
local placeholders = require("mark2tex.tokens")

local spans = {}

-- Inline passes see several paragraphs at once; no inline construct may run
-- past the next blank line.
local function paragraph_end(source: string, position: integer): integer
	return (source:find("\n[ \t]*\n", position))
end

-- Length of the backtick run at position (0 when there is none).
function spans.run_length(source: string, position: integer): integer
	local run = source:match("^`+", position)
	return run and #run or 0
end

-- A CommonMark code span: a run of n backticks is closed by the next run of
-- exactly n backticks in the same paragraph. Returns the index of the last
-- closing backtick, or nil when the run at position is escaped or has no
-- partner; such a run is literal text and callers skip all of it.
function spans.code_end(source: string, position: integer): integer
	if source:sub(position, position) ~= "`" or delimiters.is_escaped(source, position) then
		return nil
	end
	local length = spans.run_length(source, position)
	local limit = paragraph_end(source, position + length) or #source + 1
	local index = position + length
	while true do
		local first, last = source:find("`+", index)
		if not first or first >= limit then return nil end
		if last - first + 1 == length then return last end
		index = last + 1
	end
end

-- Where a construct starting at position ends when it is not a code span: a
-- matched span, or the whole unmatched run as literal text.
function spans.code_or_run_end(source: string, position: integer): integer
	return spans.code_end(source, position) or position + spans.run_length(source, position) - 1
end

-- The next unescaped delimiter at or after start within the same paragraph.
function spans.find_closing(source: string, delimiter: string, start: integer): integer
	local limit = paragraph_end(source, start) or #source + 1
	local found = delimiters.find_unescaped(source, delimiter, start)
	if found and found < limit then return found end
	return nil
end

-- Math at position: its opening delimiter and where the closing one starts,
-- or just the opening delimiter when it is never closed in the paragraph.
-- A single $ is not closed by the first half of a $$.
function spans.math_span(source: string, position: integer): string, integer
	local character = source:sub(position, position)
	local pair = source:sub(position, position + 1)
	if (pair == "\\(" or pair == "\\[") and not delimiters.is_escaped(source, position) then
		return pair, spans.find_closing(source, pair == "\\(" and "\\)" or "\\]", position + 2)
	end
	if character ~= "$" or delimiters.is_escaped(source, position) then return nil end
	if pair == "$$" then
		return "$$", spans.find_closing(source, "$$", position + 2)
	end
	local closing = spans.find_closing(source, "$", position + 1)
	while closing and source:sub(closing, closing + 1) == "$$" do
		closing = spans.find_closing(source, "$", closing + 2)
	end
	return "$", closing
end

-- The closing delimiter for an opening one from math_span.
function spans.math_closer(opening: string): string
	if opening == "\\(" then return "\\)" end
	if opening == "\\[" then return "\\]" end
	return opening
end

-- One argument starting at index, read as TeX reads it: in {...} only braces
-- count; in [...] braces nest and the first ] outside them (brackets nest,
-- forgivingly) closes it. Returns the index of its last character, or nil and
-- why: "unclosed", "invalid" (a } with no {, which TeX cannot read) or
-- "placeholder" (an earlier pass replaced characters inside it, so the
-- placeholder belongs to that pass).
local function argument_end(source: string, index: integer): integer, string
	local optional = source:sub(index, index) == "["
	local braces, brackets = optional and 0 or 1, optional and 1 or 0
	local group = index + 1
	while group <= #source do
		local character = source:sub(group, group)
		if placeholders.markers:find(character, 1, true) then return nil, "placeholder" end
		if character == "\\" then
			local escaped = source:sub(group + 1, group + 1)
			if escaped ~= "" and placeholders.markers:find(escaped, 1, true) then return nil, "placeholder" end
			group = group + 1
		elseif character == "{" then
			braces = braces + 1
		elseif character == "}" then
			if braces == 0 then return nil, "invalid" end
			braces = braces - 1
			if not optional and braces == 0 then return group end
		elseif optional and braces == 0 then
			if character == "[" then brackets = brackets + 1 end
			if character == "]" then
				brackets = brackets - 1
				if brackets == 0 then return group end
			end
		end
		group = group + 1
	end
	return nil, "unclosed"
end

-- A TeX command (backslash, letters or @, optional star) with its bracket and
-- brace arguments, which every pass treats as opaque raw TeX. Returns the
-- index of its last character, or nil when no command starts at position.
function spans.command_end(source: string, position: integer): integer
	local command = source:match("^\\[%a@]+%*?", position)
	if not command then return nil end
	local index = position + #command
	while source:sub(index, index) == "{" or source:sub(index, index) == "[" do
		local optional = source:sub(index, index) == "["
		local last, problem = argument_end(source, index)
		-- An unclosed mandatory argument runs to the end of the source; an
		-- unclosed or unreadable optional one is ordinary text.
		if problem == "unclosed" and not optional then return #source end
		if not last then break end
		-- [label](destination) after a command is a Markdown link, not an argument.
		-- Later passes see a placeholder where an earlier pass replaced the
		-- "(...)" or another construct, so a placeholder counts the same.
		local following = source:sub(last + 1, last + 1)
		if optional and following ~= ""
			and (following == "(" or placeholders.markers:find(following, 1, true)) then break end
		index = last + 1
	end
	return index - 1
end

-- A fenced code block at position, which must start a line: three or more
-- backticks or tildes, closed by a run of the same character at least as
-- long. Returns the index of the closing run's last character, or nil when
-- there is no fence or it is never closed (parse_blocks keeps it as text).
function spans.fence_end(source: string, position: integer): integer
	local character = source:sub(position, position)
	if character ~= "`" and character ~= "~" then return nil end
	local pattern = character == "`" and "`+" or "~+"
	local run = source:match("^" .. pattern, position)
	if #run < 3 then return nil end
	local index = position + #run
	while true do
		local first, last = source:find(pattern, index)
		if not first then return nil end
		if last - first + 1 >= #run then return last end
		index = last + 1
	end
end

return spans
