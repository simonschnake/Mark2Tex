--[[
elements:
- header
- latex environment
- item
- enum
- code
- other
- citation
- verbatim
- math
- latex_cmd
- italic
- bold
- text
--]]

local function is_list_node(ast)
	return ast.type == "item" or ast.type == "enum"
end

local function list_environment(list_type)
	if list_type == "item" then
		return "itemize"
	end
	return "enumerate"
end

local function close_list(out, stack)
	local current = table.remove(stack)
	out[1] = out[1] .. "\n\\end{" .. list_environment(current.type) .. "}"
end

local function close_lists_until(out, stack, level)
	while #stack > 0 and stack[#stack].level > level do
		close_list(out, stack)
	end
end

local function close_all_lists(out, stack)
	while #stack > 0 do
		close_list(out, stack)
	end
end

local function open_list(out, stack, ast)
	table.insert(stack, { type = ast.type, level = ast.level })
	out[1] = out[1] .. "\n\\begin{" .. list_environment(ast.type) .. "}"
end

local function ensure_list_environment(out, stack, ast)
	close_lists_until(out, stack, ast.level)

	if #stack > 0 and stack[#stack].level == ast.level and stack[#stack].type ~= ast.type then
		close_list(out, stack)
	end

	if #stack == 0 or stack[#stack].level < ast.level or stack[#stack].type ~= ast.type then
		open_list(out, stack, ast)
	end
end

local function walk(ast, out, config)
	if ast.type == nil then
		for _, v in ipairs(ast) do
			walk(v, out, config)
		end
	else
		if ast.type == "header" then
			out[1] = out[1] .. "\n\\"
			if ast.level > #config.header then
				ast.level = #config.header -- max level
			end
			out[1] = out[1] .. config.header[ast.level]

			out[1] = out[1] .. "{"
			walk(ast.content, out, config)
			out[1] = out[1] .. "}"
		elseif ast.type == "latex" then
			out[1] = out[1] .. "\n" .. ast.content
		elseif ast.type == "item" then
			out[1] = out[1] .. "\n\\item "
			walk(ast.content, out, config)
		elseif ast.type == "enum" then -- TODO: add
			out[1] = out[1] .. "\n\\item" -- TODO: the space after \item is not always needed
			walk(ast.content, out, config)
		elseif ast.type == "code" then
			-- TODO: add code type
			out[1] = out[1] .. "\n\\begin{verbatim}\n" .. ast.content .. "\\end{verbatim}"
		elseif ast.type == "blockquote" then
			out[1] = out[1] .. "\n\\begin{quote}\n"
			walk(ast.content, out, config)
			out[1] = out[1] .. "\n\\end{quote}"
		elseif ast.type == "table" then
			out[1] = out[1] .. "\n\\begin{center}\n\\begin{tabular}{" .. table.concat(ast.alignments) .. "}\n\\hline\n"
			for index = 1, #ast.alignments do
				if index > 1 then
					out[1] = out[1] .. " & "
				end
				if ast.headers[index] then
					walk(ast.headers[index], out, config)
				end
			end
			out[1] = out[1] .. " \\\\\n\\hline"

			for _, row in ipairs(ast.rows) do
				out[1] = out[1] .. "\n"
				for index = 1, #ast.alignments do
					if index > 1 then
						out[1] = out[1] .. " & "
					end
					if row[index] then
						walk(row[index], out, config)
					end
				end
				out[1] = out[1] .. " \\\\"
			end

			out[1] = out[1] .. "\n\\hline\n\\end{tabular}\n\\end{center}"
		elseif ast.type == "other" then
			walk(ast.content, out, config)
		elseif ast.type == "paren_citation" then
			out[1] = out[1] .. "\\" .. config.paren_citation
			if ast.locator then
				out[1] = out[1] .. "[" .. ast.locator .. "]"
			end
			out[1] = out[1] .. "{" .. table.concat(ast.content, ", ") .. "}"
		elseif ast.type == "citation" then
			out[1] = out[1] .. "\\" .. config.citation .. "{" .. ast.content .. "}"
		elseif ast.type == "verbatim" then
			out[1] = out[1] .. "\\texttt{" .. ast.content .. "}"
		elseif ast.type == "math" or ast.type == "latex_cmd" then
			out[1] = out[1] .. ast.content
		elseif ast.type == "italic" then
			out[1] = out[1] .. "\\emph{"
			walk(ast.content, out, config)
			out[1] = out[1] .. "}"
		elseif ast.type == "bold" then
			out[1] = out[1] .. "\\textbf{"
			walk(ast.content, out, config)
			out[1] = out[1] .. "}"
		elseif ast.type == "strikethrough" then
			out[1] = out[1] .. "\\sout{"
			walk(ast.content, out, config)
			out[1] = out[1] .. "}"
		elseif ast.type == "text" then
			out[1] = out[1] .. ast.content
		else
			error("Unknown type: " .. ast.type)
		end
	end
end

local function write(ast, config)
	local output = { "" }
	local list_stack = {}

	for _, node in ipairs(ast) do
		if is_list_node(node) then
			ensure_list_environment(output, list_stack, node)
			walk(node, output, config)
		else
			close_all_lists(output, list_stack)
			walk(node, output, config)
		end
	end

	close_all_lists(output, list_stack)

	return output[1]:sub(2) -- remove first newline that was added
end

return write
