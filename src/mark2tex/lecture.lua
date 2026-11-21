local lecture = {}

local function is_whitespace(node)
	if node.type ~= "other" then return false end
	for _, inline in ipairs(node.content) do
		if inline.type ~= "text" or inline.content:find("%S") then return false end
	end
	return true
end

local suffix = "[ \t]*(MARKTWOTEXCOMMENTX*%d+END)"
local function is_dozent(directives, token)
	return directives[token] and directives[token].type == "dozent"
end

function lecture.mark_dozent_blocks(ast, directives)
	local result = {}
	for _, node in ipairs(ast) do
		if node.type == "other" then
			local previous = result[#result]
			-- Structured blocks consume their closing delimiter separately from its comment.
			local token, ending = node.content:match("^\n?" .. suffix .. "[ \t]*()\n")
			if not token then
				token = node.content:match("^\n?" .. suffix .. "[ \t]*$")
				ending = #node.content + 1
			end
			if previous and is_dozent(directives, token)
				and (previous.type == "display_math" or previous.type == "latex"
					or previous.type == "table" or previous.type == "code"
					or previous.type == "blockquote") then
				previous.dozent = true
				node.content = node.content:sub(ending)
			end

			local start = 1
			while start <= #node.content do
				local first, last = node.content:find("\n[ \t]*\n", start)
				local paragraph = node.content:sub(start, first and first - 1)
				local body, marker = paragraph:match("^(.-)" .. suffix .. "%s*$")
				local marked = body and body:match("[^\n]*%S[^\n]*$") and is_dozent(directives, marker)
				if marked then paragraph = body end
				if first then paragraph = paragraph .. node.content:sub(first, last) end
				result[#result + 1] = { type = "other", content = paragraph, dozent = marked or nil }
				if not first then break end
				start = last + 1
			end
		else
			if node.type == "item" or node.type == "enum" then
				local body, token = node.content:match("^(.-)" .. suffix .. "%s*$")
				if body and is_dozent(directives, token) then
					node.content, node.dozent = body, true
				end
			end
			if node.type == "table" and #node.rows > 0 then
				local row = node.rows[#node.rows]
				local body, token = (row[#row] or ""):match("^(.-)" .. suffix .. "%s*$")
				if body and is_dozent(directives, token) then
					node.dozent = true
					if body == "" and #row > #node.alignments then
						table.remove(row)
					else
						row[#row] = body
					end
				end
			end
			result[#result + 1] = node
		end
	end
	return result
end

local function marker_comment(node)
	return { type = "other", content = "\n" .. node.token .. "\n" }
end

function lecture.group_dozent_blocks(ast)
	local output, pending, depth = {}, {}, 0
	local function flush_unclosed()
		for _, node in ipairs(pending) do
			output[#output + 1] = (node.type == "dozent_begin" or node.type == "dozent_end")
				and marker_comment(node) or node
		end
		pending, depth = {}, 0
	end

	for _, node in ipairs(ast) do
		local boundary = node.type == "slide_break" or node.type == "slide_pause"
			or node.type == "slide_title" or node.type == "slide_footer" or node.type == "slide_note"
			or node.type == "header"
		if boundary and depth > 0 then flush_unclosed() end

		if node.type == "dozent_begin" then
			depth = depth + 1
			pending[#pending + 1] = node
		elseif depth > 0 then
			pending[#pending + 1] = node
			if node.type == "dozent_end" then
				depth = depth - 1
				if depth == 0 then
					local content = {}
					for _, child in ipairs(pending) do
						if child.type ~= "dozent_begin" and child.type ~= "dozent_end" then
							child.dozent = nil
							content[#content + 1] = child
						end
					end
					output[#output + 1] = { type = "dozent_group", content = content, dozent = true }
					pending = {}
				end
			end
		else
			output[#output + 1] = node.type == "dozent_end" and marker_comment(node) or node
		end
	end
	flush_unclosed()
	return output
end

function lecture.structure(ast, config)
	local output = { comments = ast.comments }
	local body, title, plain_title = {}, nil, nil
	local has_content, after_break, pending_pause = false, false, false

	local footer, notes = nil, {}
	local section_only = false
	local handout = config.profile == "handout"
	local function finish()
		if handout then
			if (title or has_content) and (footer or #notes > 0) then
				output[#output + 1] = { type = "lecture_annotations", footer = footer, notes = notes }
			end
		elseif title or has_content then
			output[#output + 1] = { type = "slide_frame", content = body, title = title,
				plain_title = plain_title, footer = footer, notes = notes }
		end
		body, title, plain_title, footer, notes = {}, nil, nil, nil, {}
		has_content, pending_pause, section_only = false, false, false
	end

	for _, node in ipairs(ast) do
		local h1 = not handout and node.type == "header" and not node.indented and node.level == 1
		if h1 and config.h1 == "hide" then goto continue end
		if section_only and node.type ~= "slide_footer" and node.type ~= "slide_note"
			and not is_whitespace(node) then finish() end
		if node.type == "slide_footer" then
			footer = footer or node.title
		elseif node.type == "slide_note" then
			notes[#notes + 1] = node.title
		elseif node.type == "slide_title" and after_break then
			plain_title = node.title
		elseif node.type == "header" and not node.indented and node.level <= config.slide_level then
			finish()
			title = node.content
			if handout then output[#output + 1] = node end
			section_only = node.level < config.slide_level and not (h1 and config.h1 == "frame")
		elseif node.type == "slide_break" then
			finish()
			if handout then output[#output + 1] = { type = "slide_paragraph" } end
		elseif node.type == "slide_pause" then
			if handout then
				output[#output + 1] = { type = "slide_paragraph" }
			else
				pending_pause = has_content
			end
		elseif not handout and config.standalone_learning_blocks and node.type == "latex"
			and node.content:match("^%s*\\begin%s*{Lernblock}") then
			finish()
			output[#output + 1] = node
		elseif handout then
			output[#output + 1] = node
			has_content = has_content or not is_whitespace(node)
		else
			if not is_whitespace(node) then
				if pending_pause then body[#body + 1] = { type = "slide_pause" } end
				pending_pause, has_content = false, true
			end
			if node.type == "header" then
				node = { type = "slide_subheading", content = node.content }
			end
			body[#body + 1] = node
		end
		if not is_whitespace(node) then after_break = node.type == "slide_break" end
		::continue::
	end

	finish()
	return output
end

return lecture
