-- Hide HTML comments from Markdown parsing, then restore them as TeX comments.
local comments = {}

function comments.protect(source)
	local prefix = "MARKTWOTEXCOMMENT"
	while source:find(prefix, 1, true) do
		prefix = prefix .. "X"
	end
	local output, masked, tokens = {}, {}, {}
	local position = 1
	while position <= #source do
		local first, last = source:find("^`+", position)
		if first then
			local delimiter = source:sub(first, last)
			local closing = source:find(delimiter, last + 1, true)
			local ending = closing and closing + #delimiter - 1 or #source
			local code = source:sub(position, ending)
			output[#output + 1], masked[#masked + 1] = code, code
			position = ending + 1
		elseif source:sub(position, position + 3) == "<!--" then
			local closing = source:find("-->", position + 4, true)
			local ending = closing and closing + 2 or #source
			local original = source:sub(position, ending)
			local token = prefix .. tostring(#tokens + 1) .. "END"
			tokens[#tokens + 1] = {
				token = token,
				content = source:sub(position + 4, closing and closing - 1 or #source),
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
	end
	return table.concat(output), tokens, table.concat(masked)
end

function comments.restore(output, tokens)
	for _, comment in ipairs(tokens or {}) do
		output = output:gsub(comment.token .. "([ \t]*)(\r?\n?)", function(spaces, newline)
			local content = comment.content:gsub("\r\n", "\n"):gsub("\r", "\n")
			-- Terminate every comment before any following text or generated brace.
			-- Move following spaces before the comment: TeX ignores line-leading spaces.
			return spaces .. "%" .. content:gsub("\n", "\n%%") .. (newline ~= "" and newline or "\n")
		end)
	end
	return output
end

return comments
