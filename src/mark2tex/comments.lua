-- Hide HTML comments from Markdown parsing, then restore them as TeX comments.
local comments = {}

local variants = { script = true, slides = true, instructor = true, student = true }

local function variant_marker(content)
	if content:find("[\r\n]") then return nil end
	content = content:match("^%s*(.-)%s*$")
	if content == "end" then return "end" end
	local name = content:match("^([a-z]+):[ \t]*begin$")
	return variants[name] and name or nil
end

local function starts_line(source, position)
	local left = position - 1
	while left > 0 and position - left <= 3 and source:sub(left, left) == " " do
		left = left - 1
	end
	return left == 0 or source:sub(left, left):match("[\r\n]") ~= nil
end

function comments.protect(source, track_closure)
	local prefix = "MARKTWOTEXCOMMENT"
	while source:find(prefix, 1, true) do
		prefix = prefix .. "X"
	end
	local output, masked, tokens, markers = {}, {}, {}, {}
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
			local content = source:sub(position + 4, closing and closing - 1 or #source)
			local marker = closing and variant_marker(content)
			if marker and starts_line(source, position)
				and source:match("^[^\r\n]*", ending + 1):match("^[ \t]*$") then
				markers[#markers + 1] = { kind = marker, first = position, last = ending }
			end
			local token = prefix .. tostring(#tokens + 1) .. "END"
			tokens[#tokens + 1] = {
				token = token,
				content = content,
				closed = track_closure and closing ~= nil or nil,
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
	return table.concat(output), tokens, table.concat(masked), markers
end

function comments.select(source, markers, config, source_id)
	local slides = config and config.profile == "slides"
	local instructor = config and (config.audience == "instructor" or config.slide_audience == "dozent")
	local enabled = { script = not slides, slides = slides, instructor = instructor, student = not instructor }
	local output, stack, position, hidden = {}, {}, 1, 0
	local function fail(marker, message)
		local _, lines = source:sub(1, marker.first - 1):gsub("\n", "")
		error((source_id or "Markdown") .. ":" .. (lines + 1) .. ": " .. message, 0)
	end
	for _, marker in ipairs(markers) do
		local before = source:sub(position, marker.first - 1)
		output[#output + 1] = hidden == 0 and before or before:gsub("[^\r\n]", "")
		if marker.kind == "end" then
			local opener = table.remove(stack)
			if not opener then fail(marker, "unexpected variant block end") end
			if not enabled[opener.kind] then hidden = hidden - 1 end
		else
			stack[#stack + 1] = marker
			if not enabled[marker.kind] then hidden = hidden + 1 end
		end
		position = marker.last + 1
	end
	local unclosed = stack[#stack]
	if unclosed then fail(unclosed, "unclosed " .. unclosed.kind .. " variant block") end
	output[#output + 1] = source:sub(position)
	return table.concat(output)
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
