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

-- A TeX command (backslash, letters or @, optional star) with its bracket and
-- brace arguments, which every pass treats as opaque raw TeX. Returns the
-- index of its last character, or nil when no command starts at position.
function spans.command_end(source: string, position: integer): integer
	local command = source:match("^\\[%a@]+%*?", position)
	if not command then return nil end
	local index = position + #command
	while source:sub(index, index) == "{" or source:sub(index, index) == "[" do
		local opening = source:sub(index, index)
		local stack = { opening == "{" and "}" or "]" }
		local group = index + 1
		while #stack > 0 and group <= #source do
			local character = source:sub(group, group)
			if character == "\\" then group = group + 1
			elseif character == "{" or character == "[" then stack[#stack + 1] = character == "{" and "}" or "]"
			elseif character == stack[#stack] then table.remove(stack) end
			group = group + 1
		end
		-- [label](destination) after a command is a Markdown link, not an argument.
		-- Later passes see a placeholder where an earlier pass replaced the
		-- "(...)" or another construct, so a placeholder counts the same.
		local following = source:sub(group, group)
		if opening == "[" and #stack == 0 and following ~= ""
			and (following == "(" or placeholders.markers:find(following, 1, true)) then break end
		-- An optional argument must be closed; an unclosed [ is ordinary text.
		if opening == "[" and #stack > 0 then break end
		index = group
	end
	-- An unclosed argument runs to the end of the source.
	return math.min(index - 1, #source)
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
