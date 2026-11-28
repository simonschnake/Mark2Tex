--[[
elements:
- header
- horizontal_rule
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
local links = require("mark2tex.links")
local type nodes = require("mark2tex.nodes")
local type Config = require("mark2tex.default_config")

local type Node = nodes.Node
local type Document = nodes.Document

-- The writer runs on the fully parsed AST: container nodes hold node lists,
-- leaf nodes hold strings. Casts below rely on that invariant.

local record ListState
	type: string
	level: integer
	style: string
end

local function is_list_node(ast: Node): boolean
	return ast.type == "item" or ast.type == "enum"
end

local function list_environment(list_type: string): string
	if list_type == "item" then
		return "itemize"
	end
	return "enumerate"
end

local function close_list(out: {string}, stack: {ListState})
	local current = table.remove(stack)
	out[1] = out[1] .. "\n\\end{" .. list_environment(current.type) .. "}"
end

local function close_lists_until(out: {string}, stack: {ListState}, level: integer)
	while #stack > 0 and stack[#stack].level > level do
		close_list(out, stack)
	end
end

local function close_all_lists(out: {string}, stack: {ListState})
	while #stack > 0 do
		close_list(out, stack)
	end
end

local function open_list(out: {string}, stack: {ListState}, ast: Node)
	table.insert(stack, { type = ast.type, level = ast.level, style = ast.style or "decimal" })
	out[1] = out[1] .. "\n\\begin{" .. list_environment(ast.type) .. "}"
	if ast.type == "enum" then
		local counter = "\\csname @enumctr\\endcsname"
		if ast.style == "alpha" then
			-- Capture the counter name for references from nested lists.
			out[1] = out[1] .. "\n\\expandafter\\edef\\csname the" .. counter .. "\\endcsname{"
				.. "\\expandafter\\noexpand\\csname int_to_alph:n\\endcsname"
				.. "{\\noexpand\\value{" .. counter .. "}}}"
				.. "\n\\expandafter\\def\\csname @itemlabel\\endcsname{"
				.. "\\csname the" .. counter .. "\\endcsname)}"
		end
		if ast.start and ast.start ~= 1 then
			out[1] = out[1] .. "\n\\setcounter{" .. counter .. "}{" .. tostring(ast.start - 1) .. "}"
		end
	end
end

local function ensure_list_environment(out: {string}, stack: {ListState}, ast: Node)
	close_lists_until(out, stack, ast.level)

	local style = ast.style or "decimal"
	if #stack > 0 and stack[#stack].level == ast.level
		and (stack[#stack].type ~= ast.type or stack[#stack].style ~= style) then
		close_list(out, stack)
	end

	if #stack == 0 or stack[#stack].level < ast.level or stack[#stack].type ~= ast.type then
		open_list(out, stack, ast)
	end
end

-- Estimate displayed text from inline nodes, excluding Markdown formatting.
-- TeX commands/math are deliberately conservative: their source length is only
-- an approximation of their typeset width.
local function cell_length(value: string | {Node | string}): integer
	if value is string then
		local _, count = value:gsub("[^\128-\191]", "")
		return count
	end
	-- Like the original writer, any table with content is measured as a node.
	local content = (value as Node).content
	if content then
		return cell_length(content)
	end
	local length = 0
	for _, child in ipairs(value) do
		length = length + cell_length(child as string | {Node | string})
	end
	return length
end

local function table_columns(ast: Node): string
	local count = #ast.alignments
	local lengths: {integer} = {}
	local compact: {boolean} = {}
	local text_columns = 0
	for index = 1, count do
		local header: string | {Node | string} = ast.headers[index]
		if header == nil then header = {} end
		local maximum = cell_length(header)
		local total = maximum
		for _, row in ipairs(ast.rows) do
			local cell: string | {Node | string} = row[index]
			if cell == nil then cell = {} end
			local length = cell_length(cell)
			maximum = math.max(maximum, length)
			total = total + length
		end
		lengths[index] = maximum
		compact[index] = maximum <= 18 and total / (#ast.rows + 1) <= 10
		if not compact[index] then text_columns = text_columns + 1 end
	end

	local alignment: {string: string} = { l = "raggedright", c = "centering", r = "raggedleft" }
	local columns: {string} = {}
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

local write: function(ast: Document, config: Config, nested?: boolean): string

-- An ampersand in ordinary prose is a LaTeX alignment character. Escape it
-- here, while leaving raw LaTeX nodes untouched.
local function write_text(text: string): string
	return (text:gsub("&", "\\&"))
end

-- Inline code is literal text inside a TeX argument. Escape in one pass so
-- generated commands are not escaped again. Raw LaTeX has its own AST nodes.
local function write_inline_code(text: string): string
	local escapes: {string: string} = {
		["\\"] = "\\textbackslash{}",
		["^"] = "\\textasciicircum{}",
		["~"] = "\\textasciitilde{}",
	}
	return (text:gsub("[\\%%{}#&_$^~]", function(character: string): string
		return escapes[character] or "\\" .. character
	end))
end

-- Slide annotations are written on one line.
local function write_annotation(text: string): string
	return write_inline_code((text:gsub("%s+", " ")))
end

local function has_verbatim(blocks: {Node}): boolean
	for _, node in ipairs(blocks) do
		if node.type == "code"
			or (node.type == "latex" and (node.content as string):find("\\begin{verbatim", 1, true))
			or (node.type == "blockquote" and has_verbatim(node.content as {Node})) then
			return true
		end
	end
	return false
end

local walk: function(ast: Node, out: {string}, config: Config)

-- walk dispatches on the table itself, so lists and single nodes both work.
local function walk_nodes(list: {Node | string}, out: {string}, config: Config)
	walk(list as Node, out, config)
end

walk = function(ast: Node, out: {string}, config: Config)
	if ast.type == nil then
		-- An untyped table is a node list.
		for _, v in ipairs(ast as {Node | string}) do
			walk(v as Node, out, config)
		end
	elseif ast.type == "header" then
		out[1] = out[1] .. "\n\\"
		if ast.level > #config.header then
			ast.level = #config.header -- max level
		end
		out[1] = out[1] .. config.header[ast.level]

		out[1] = out[1] .. "{"
		walk_nodes(ast.content as {Node}, out, config)
		out[1] = out[1] .. "}"
	elseif ast.type == "slide_frame" then
		local options = has_verbatim(ast.content as {Node}) and "t,fragile" or "t"
		out[1] = out[1] .. "\n\\begin{frame}[" .. options .. "]\n"
		if ast.title then
			out[1] = out[1] .. "\\frametitle{"
			walk_nodes(ast.title as {Node}, out, config)
			out[1] = out[1] .. "}\n"
		end
		if ast.footer then
			out[1] = out[1] .. "\\SlideFooter{" .. write_annotation(ast.footer) .. "}\n"
		end
		if ast.notes and #ast.notes > 0 then
			local notes: {string} = {}
			for _, note in ipairs(ast.notes) do
				notes[#notes + 1] = write_annotation(note)
			end
			out[1] = out[1] .. "\\note{" .. table.concat(notes, "\\par ") .. "}\n"
		end
		out[1] = out[1] .. write(ast.content as Document, config, true) .. "\n\\end{frame}\n"
	elseif ast.type == "slide_pause" then
		out[1] = out[1] .. "\n\\par\\pause\n"
	elseif ast.type == "slide_subheading" then
		out[1] = out[1] .. "\n\\par\\medskip\\noindent\\textbf{"
		walk_nodes(ast.content as {Node}, out, config)
		out[1] = out[1] .. "}\\par\n"
	elseif ast.type == "lecture_annotations" then
		if ast.footer then
			out[1] = out[1] .. "\n\\par\\noindent{\\small " .. write_annotation(ast.footer) .. "}\\par\n"
		end
		for _, note in ipairs(ast.notes) do
			out[1] = out[1] .. "\n\\par\\noindent\\textbf{Vortragsnotiz:} "
				.. write_annotation(note) .. "\\par\n"
		end
	elseif ast.type == "slide_paragraph" then
		out[1] = out[1] .. "\n\\par\n"
	elseif ast.type == "horizontal_rule" then
		out[1] = out[1] .. "\n\\par\\addvspace{\\medskipamount}\n\\noindent\\rule{\\linewidth}{0.4pt}\n\\par\\addvspace{\\medskipamount}"
	elseif ast.type == "image" then
		local size = ast.width ~= "" and ("width=" .. ast.width .. ",") or ""
		out[1] = out[1] .. "\n\\adjustbox{" .. size .. "max width=\\linewidth}{\\includegraphics{" .. ast.path .. "}}"
	elseif ast.type == "latex" then
		out[1] = out[1] .. "\n" .. (ast.content as string)
	elseif ast.type == "item" then
		out[1] = out[1] .. "\n\\item "
		walk_nodes(ast.content as {Node}, out, config)
	elseif ast.type == "enum" then -- TODO: add
		out[1] = out[1] .. "\n\\item" -- TODO: the space after \item is not always needed
		walk_nodes(ast.content as {Node}, out, config)
	elseif ast.type == "code" then
		-- TODO: add code type
		out[1] = out[1] .. "\n\\begin{verbatim}\n" .. (ast.content as string) .. "\\end{verbatim}"
	elseif ast.type == "blockquote" then
		out[1] = out[1] .. "\n\\begin{quote}\n"
		out[1] = out[1] .. write(ast.content as Document, config, true)
		out[1] = out[1] .. "\n\\end{quote}"
	elseif ast.type == "table" then
		out[1] = out[1] .. "\n\\par\\addvspace{\\medskipamount}\n\\noindent\\begin{tabularx}{\\linewidth}{" .. table_columns(ast) .. "}\n\\toprule\n"
		for index = 1, #ast.alignments do
			if index > 1 then
				out[1] = out[1] .. " & "
			end
			if ast.headers[index] then
				walk_nodes(ast.headers[index] as {Node}, out, config)
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
					walk_nodes(row[index] as {Node}, out, config)
				end
			end
			out[1] = out[1] .. " \\\\"
		end

		out[1] = out[1] .. "\n\\bottomrule\n\\end{tabularx}\n\\par\\addvspace{\\medskipamount}"
	elseif ast.type == "other" then
		walk_nodes(ast.content as {Node}, out, config)
	elseif ast.type == "paren_citation" then
		out[1] = out[1] .. "\\" .. config.paren_citation
		if ast.locator then
			out[1] = out[1] .. "[" .. ast.locator .. "]"
		end
		out[1] = out[1] .. "{" .. table.concat(ast.content as {string}, ", ") .. "}"
	elseif ast.type == "link" then
		local destination = ast.destination
		if destination:match("^[%a][%w+.-]*:") then
			destination = destination:gsub(" ", "%%20")
		end
		if ast.kind == "autolink" then
			out[1] = out[1] .. "\\url{" .. links.tex_destination(destination) .. "}"
		else
			if destination:sub(1, 1) == "#" and #destination > 1 then
				out[1] = out[1] .. "\\hyperref[" .. links.tex_destination(destination:sub(2)) .. "]{"
			else
				out[1] = out[1] .. "\\href{" .. links.tex_destination(destination) .. "}{"
			end
			if ast.kind == "email" then
				local address = ast.destination:sub(8)
				out[1] = out[1] .. "\\nolinkurl{" .. links.tex_destination(address) .. "}"
			else
				walk_nodes(ast.content as {Node}, out, config)
			end
			out[1] = out[1] .. "}"
		end
	elseif ast.type == "footnote" then
		if ast.repeated then
			out[1] = out[1] .. "\\footref{" .. ast.label .. "}"
		else
			out[1] = out[1] .. "\\footnote{"
			if ast.label then out[1] = out[1] .. "\\label{" .. ast.label .. "}" end
			if ast.inline then walk_nodes(ast.content as {Node}, out, config)
			else out[1] = out[1] .. write(ast.content as Document, config, true) end
			out[1] = out[1] .. "}"
		end
	elseif ast.type == "literal" then
		local escapes: {string: string} = { ["\\"] = "\\textbackslash{}", ["^"] = "\\textasciicircum{}", ["~"] = "\\textasciitilde{}" }
		local content = ast.content as string
		out[1] = out[1] .. (escapes[content] or content:gsub("[%%{}#&_$]", "\\%0"))
	elseif ast.type == "citation" then
		out[1] = out[1] .. "\\" .. config.citation .. "{" .. (ast.content as string) .. "}"
	elseif ast.type == "verbatim" then
		out[1] = out[1] .. "\\texttt{" .. write_inline_code(ast.content as string) .. "}"
	elseif ast.type == "inline_math" or ast.type == "latex_cmd" then
		out[1] = out[1] .. (ast.content as string)
	elseif ast.type == "display_math" then
		local trimmed, removed = out[1]:gsub("\n[ \t]+$", "\n")
		out[1] = trimmed
		if removed == 0 then
			out[1] = out[1] .. "\n"
		end
		out[1] = out[1] .. "\\[" .. (ast.content as string) .. "\\]"
	elseif ast.type == "italic" then
		out[1] = out[1] .. "\\emph{"
		walk_nodes(ast.content as {Node}, out, config)
		out[1] = out[1] .. "}"
	elseif ast.type == "bold" then
		out[1] = out[1] .. "\\textbf{"
		walk_nodes(ast.content as {Node}, out, config)
		out[1] = out[1] .. "}"
	elseif ast.type == "strikethrough" then
		out[1] = out[1] .. "\\sout{"
		walk_nodes(ast.content as {Node}, out, config)
		out[1] = out[1] .. "}"
	elseif ast.type == "text" then
		out[1] = out[1] .. write_text(ast.content as string)
	else
		error("Unknown type: " .. ast.type)
	end
end

local function contains_links(ast: {Node | string}): boolean
	for _, value in ipairs(ast) do
		local node = value as Node
		if node.type == "link" then return true end
		local content = node.content
		if content is {Node | string} and contains_links(content) then return true end
		if node.type == "slide_frame" and node.title and contains_links(node.title as {Node}) then return true end
		if node.type == "table" then
			for _, cell in ipairs(node.headers) do if contains_links(cell as {Node}) then return true end end
			for _, row in ipairs(node.rows) do
				for _, cell in ipairs(row) do if contains_links(cell as {Node}) then return true end end
			end
		end
	end
	return false
end

write = function(ast: Document, config: Config, nested?: boolean): string
	local output = { "" }
	local list_stack: {ListState} = {}

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

	local result = comments.restore(output[1]:sub(2), ast.comments)
	if not nested and contains_links(ast) then
		result = "\\ifcsname hyper@normalise\\endcsname\\else\\PackageError{mark2tex}{Markdown links require hyperref}{Load \\string\\usepackage{hyperref} in the document preamble.}\\fi\n" .. result
	end
	return result -- remove first newline that was added
end

return write
