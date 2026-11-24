local divs = {}

local annotations = { notes = "slide_note", footer = "slide_footer" }

local function append_block(output, node)
	local previous = output[#output]
	if previous and previous.type == "other" and node.type == "other"
		and previous.content:find("%S") and node.content:find("%S") then
		local gap = previous.content:match("%s*$") .. node.content:match("^%s*")
		local _, newlines = gap:gsub("\n", "")
		if newlines < 2 then node.content = string.rep("\n", 2 - newlines) .. node.content end
	end
	output[#output + 1] = node
end

local function classes(attributes)
	if attributes:sub(1, 1) ~= "{" then return { attributes } end
	local result = {}
	-- Ignore quoted attribute values, which may themselves contain dots.
	attributes = attributes:gsub('"[^"]*"', '""'):gsub("'[^']*'", "''")
	for class in attributes:sub(2, -2):gmatch("%S+") do
		if class:match("^%.[%w_-]+$") then result[#result + 1] = class:sub(2) end
	end
	return result
end

function divs.select(ast, protected, source, comments, config, source_id, warnings)
	local slides = config and config.profile == "slides"
	local lecture = slides or (config and config.profile == "handout")
	local instructor = config and (config.audience == "instructor" or config.slide_audience == "dozent")
	local enabled = { slides = slides == true, script = not slides,
		instructor = instructor == true, student = not instructor }
	local output, stack = {}, {}
	local previous_fence_end
	local comment_index, offset = 1, 0
	local line, line_start, scanned = 0, 1, 1

	local function locate(position)
		while comments[comment_index] and comments[comment_index].protected_position < position do
			local comment = comments[comment_index]
			offset = comment.source_end - comment.protected_position - #comment.token
			comment_index = comment_index + 1
		end
		position = position + offset
		local newline = source:find("\n", scanned, true)
		while newline and newline < position do
			line, line_start = line + 1, newline + 1
			newline = source:find("\n", line_start, true)
		end
		scanned = position
		return line, position - line_start + 1
	end

	local function warn(message, at_line, at_column)
		warnings[#warnings + 1] = { category = "div-fence", message = message,
			line = at_line, column = at_column }
	end

	local function fail(message, at_line)
		error((source_id or "Markdown") .. ":" .. at_line .. ": " .. message, 0)
	end

	for _, node in ipairs(ast) do
		local parent = stack[#stack]
		if node.type ~= "div_fence" then
			if not parent or (parent.visible and not parent.annotation) then
				append_block(output, node)
			end
		else
			node.line, node.column = locate(node.position)
			if parent and parent.visible and parent.annotation then
				local chunks = parent.annotation.chunks
				chunks[#chunks + 1] = protected:sub(previous_fence_end, node.position - 1)
			end
			previous_fence_end = node.ending
			if node.attributes == "" then
				if not parent then fail("unexpected div closing fence", node.line) end
				if parent.length ~= node.length then
					warn("expected " .. parent.length .. " closing colons, found " .. node.length, node.line, node.column)
				end
				stack[#stack] = nil
				if lecture and parent.visible and parent.annotation and parent.annotation.owner == parent then
					local title = table.concat(parent.annotation.chunks):match("^%s*(.-)%s*$")
					if title ~= "" then
						output[#output + 1] = { type = parent.annotation.kind, title = title }
					end
				end
			else
				if parent and node.length <= parent.length then
					warn("inner div fence should be longer than its enclosing fence", node.line, node.column)
				end
				node.annotation = parent and parent.annotation
				node.visible = not parent or parent.visible
				for _, class in ipairs(classes(node.attributes)) do
					if enabled[class] == false then node.visible = false end
					if annotations[class] and not node.annotation then
						node.annotation = { kind = annotations[class], chunks = {}, owner = node }
					end
				end
				stack[#stack + 1] = node
			end
		end
	end
	local unclosed = stack[#stack]
	if unclosed then fail("unclosed div fence (" .. unclosed.attributes .. ")", unclosed.line) end
	return output
end

return divs
