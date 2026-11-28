-- Hide HTML comments from Markdown parsing, then restore them as TeX comments.
local spans = require("mark2tex.spans")
local record CommentToken
	token: string
	content: string
	source_end: integer
	protected_position: integer
end

local record comments
	type Token = CommentToken
end

function comments.protect(source: string): string, {CommentToken}, string
	local prefix = "MARKTWOTEXCOMMENT"
	while source:find(prefix, 1, true) do
		prefix = prefix .. "X"
	end
	local output, masked: {string}, {string} = {}, {}
	local tokens: {CommentToken} = {}
	local position, protected_position = 1, 1
	while position <= #source do
		-- Comments inside fenced code and code spans stay literal (see spans).
		local at_line_start = position == 1 or source:sub(position - 1, position - 1) == "\n"
		local code_end = at_line_start and spans.line_fence_end(source, position) or nil
		if not code_end and source:sub(position, position) == "`" then
			code_end = spans.code_or_run_end(source, position)
		end
		if code_end then
			local ending = code_end
			local code = source:sub(position, ending)
			output[#output + 1], masked[#masked + 1] = code, code
			position = ending + 1
		elseif source:sub(position, position + 3) == "<!--" then
			local closing = source:find("-->", position + 4, true)
			local ending = closing and closing + 2 or #source
			local original = source:sub(position, ending)
			local content = source:sub(position + 4, closing and closing - 1 or #source)
			local token = prefix .. tostring(#tokens + 1) .. "END"
			tokens[#tokens + 1] = {
				token = token,
				content = content,
				source_end = ending + 1,
				protected_position = protected_position,
			}
			output[#output + 1] = token
			-- Preserve locations for diagnostics in the remaining source.
			masked[#masked + 1] = original:gsub("[^\r\n]", " ")
			position = ending + 1
		else
			local character = source:sub(position, position)
			output[#output + 1], masked[#masked + 1] = character, character
			position = position + 1
		end
		protected_position = protected_position + #output[#output]
	end
	return table.concat(output), tokens, table.concat(masked)
end

function comments.restore(output: string, tokens?: {CommentToken}): string
	for _, comment in ipairs(tokens or {}) do
		output = output:gsub(comment.token .. "([ \t]*)(\r?\n?)", function(spaces: string, newline: string): string
			local content = comment.content:gsub("\r\n", "\n"):gsub("\r", "\n")
			-- Terminate every comment before any following text or generated brace.
			-- Move following spaces before the comment: TeX ignores line-leading spaces.
			return spaces .. "%" .. content:gsub("\n", "\n%%") .. (newline ~= "" and newline or "\n")
		end)
	end
	return output
end

return comments
