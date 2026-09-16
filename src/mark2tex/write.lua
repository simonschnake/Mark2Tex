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
- inline_math
- display_math
- latex_cmd
- italic
- bold
- text
--]]

local comments = require("mark2tex.comments")

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

-- Estimate displayed text from inline nodes, excluding Markdown formatting.
-- TeX commands/math are deliberately conservative: their source length is only
-- an approximation of their typeset width.
local function cell_length(node)
	if type(node) == "string" then
		local _, count = node:gsub("[^\128-\191]", "")
		return count
	end
	if node.content then
		return cell_length(node.content)
	end
	local length = 0
	for _, child in ipairs(node) do
		length = length + cell_length(child)
	end
	return length
end

local function table_columns(ast)
	local count = #ast.alignments
	local lengths, compact = {}, {}
	local text_columns = 0
	for index = 1, count do
		local maximum = cell_length(ast.headers[index] or {})
		local total = maximum
		for _, row in ipairs(ast.rows) do
			local length = cell_length(row[index] or {})
			maximum = math.max(maximum, length)
			total = total + length
		end
		lengths[index] = maximum
		compact[index] = maximum <= 18 and total / (#ast.rows + 1) <= 10
		if not compact[index] then text_columns = text_columns + 1 end
	end

	local alignment = { l = "raggedright", c = "centering", r = "raggedleft" }
	local columns = {}
	for index, align in ipairs(ast.alignments) do
		local column = "X"
		if compact[index] and text_columns > 0 then
			-- Reserve at least half the usable width for text columns. Subtract
			-- intercolumn padding before allocating widths; @{} removes outer padding.
			local fraction = math.min(0.5 / count, 0.04 + lengths[index] * 0.008)
			column = string.format("p{\\dimexpr %.4f\\linewidth - %.4f\\tabcolsep\\relax}",
				fraction, fraction * 2 * (count - 1))
		end
		columns[index] = ">{\\" .. alignment[align] .. "\\arraybackslash}" .. column
	end
	return "@{}" .. table.concat(columns) .. "@{}"
end

local write

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
			out[1] = out[1] .. write(ast.content, config)
			out[1] = out[1] .. "\n\\end{quote}"
		elseif ast.type == "table" then
			out[1] = out[1] .. "\n\\par\\addvspace{\\medskipamount}\n\\noindent\\begin{tabularx}{\\linewidth}{" .. table_columns(ast) .. "}\n\\toprule\n"
			for index = 1, #ast.alignments do
				if index > 1 then
					out[1] = out[1] .. " & "
				end
				if ast.headers[index] then
					walk(ast.headers[index], out, config)
				end
			end
			out[1] = out[1] .. " \\\\\n\\midrule"

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

			out[1] = out[1] .. "\n\\bottomrule\n\\end{tabularx}\n\\par\\addvspace{\\medskipamount}"
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
		elseif ast.type == "inline_math" or ast.type == "latex_cmd" then
			out[1] = out[1] .. ast.content
		elseif ast.type == "display_math" then
			local trimmed, removed = out[1]:gsub("\n[ \t]+$", "\n")
			out[1] = trimmed
			if removed == 0 then
				out[1] = out[1] .. "\n"
			end
			out[1] = out[1] .. "\\[" .. ast.content .. "\\]"
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

write = function(ast, config)
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

	return comments.restore(output[1]:sub(2), ast.comments) -- remove first newline that was added
end

return write
