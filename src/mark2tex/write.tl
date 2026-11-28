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
local nodes = require("mark2tex.nodes")
local type Config = require("mark2tex.default_config")

local type Block = nodes.Block
local type Any = nodes.Any
local type Document = nodes.Document
local type ListNode = nodes.Item | nodes.Enum
local type CommentToken = comments.Token

local record ListState
	type: string
	level: integer
	style: string
end

local function list_style(ast: ListNode): string
	if ast is nodes.Enum then
		return ast.style or "decimal"
	end
	return "decimal"
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

local function open_list(out: {string}, stack: {ListState}, ast: ListNode)
	table.insert(stack, { type = ast.type, level = ast.level, style = list_style(ast) })
	out[1] = out[1] .. "\n\\begin{" .. list_environment(ast.type) .. "}"
	if ast is nodes.Enum then
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

local function ensure_list_environment(out: {string}, stack: {ListState}, ast: ListNode)
	close_lists_until(out, stack, ast.level)

	local style = list_style(ast)
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
-- an approximation of their typeset width. Footnotes in a cell count as well.
local function cell_length(value: string | {Any | string}): integer
	if value is string then
		local _, count = value:gsub("[^\128-\191]", "")
		return count
	end
	local length = 0
	for _, child in ipairs(value) do
		if child is string then
			length = length + cell_length(child)
		else
			local content = nodes.content(child)
			if content then
				length = length + cell_length(content)
			end
		end
	end
	return length
end

local function table_columns(ast: nodes.Table): string
	local count = #ast.alignments
	local lengths: {integer} = {}
	local compact: {boolean} = {}
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

local write_blocks: function(ast: {Block}, config: Config, nested: boolean, comment_tokens?: {CommentToken}): string

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

local function has_verbatim(blocks: {Block}): boolean
	for _, node in ipairs(blocks) do
		if node is nodes.Code
			or (node is nodes.Latex and node.content:find("\\begin{verbatim", 1, true))
			or (node is nodes.Blockquote and has_verbatim(node.content)) then
			return true
		end
	end
	return false
end

local walk: function(ast: Any, out: {string}, config: Config)

local function walk_nodes(list: {Any}, out: {string}, config: Config)
	for _, node in ipairs(list) do
		walk(node, out, config)
	end
end

walk = function(ast: Any, out: {string}, config: Config)
	if ast is nodes.Header then
		out[1] = out[1] .. "\n\\"
		if ast.level > #config.header then
			ast.level = #config.header -- max level
		end
		out[1] = out[1] .. config.header[ast.level]

		out[1] = out[1] .. "{"
		walk_nodes(ast.content, out, config)
		out[1] = out[1] .. "}"
	elseif ast is nodes.SlideFrame then
		local options = has_verbatim(ast.content) and "t,fragile" or "t"
		out[1] = out[1] .. "\n\\begin{frame}[" .. options .. "]\n"
		if ast.title then
			out[1] = out[1] .. "\\frametitle{"
			walk_nodes(ast.title, out, config)
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
		out[1] = out[1] .. write_blocks(ast.content, config, true) .. "\n\\end{frame}\n"
	elseif ast is nodes.SlidePause then
		out[1] = out[1] .. "\n\\par\\pause\n"
	elseif ast is nodes.SlideSubheading then
		out[1] = out[1] .. "\n\\par\\medskip\\noindent\\textbf{"
		walk_nodes(ast.content, out, config)
		out[1] = out[1] .. "}\\par\n"
	elseif ast is nodes.LectureAnnotations then
		if ast.footer then
			out[1] = out[1] .. "\n\\par\\noindent{\\small " .. write_annotation(ast.footer) .. "}\\par\n"
		end
		for _, note in ipairs(ast.notes) do
			out[1] = out[1] .. "\n\\par\\noindent\\textbf{Vortragsnotiz:} "
				.. write_annotation(note) .. "\\par\n"
		end
	elseif ast is nodes.SlideParagraph then
		out[1] = out[1] .. "\n\\par\n"
	elseif ast is nodes.HorizontalRule then
		out[1] = out[1] .. "\n\\par\\addvspace{\\medskipamount}\n\\noindent\\rule{\\linewidth}{0.4pt}\n\\par\\addvspace{\\medskipamount}"
	elseif ast is nodes.Image then
		local size = ast.width ~= "" and ("width=" .. ast.width .. ",") or ""
		out[1] = out[1] .. "\n\\adjustbox{" .. size .. "max width=\\linewidth}{\\includegraphics{" .. ast.path .. "}}"
	elseif ast is nodes.Latex then
		out[1] = out[1] .. "\n" .. ast.content
	elseif ast is nodes.Item then
		out[1] = out[1] .. "\n\\item "
		walk_nodes(ast.content, out, config)
	elseif ast is nodes.Enum then -- TODO: add
		out[1] = out[1] .. "\n\\item" -- TODO: the space after \item is not always needed
		walk_nodes(ast.content, out, config)
	elseif ast is nodes.Code then
		-- TODO: add code type
		out[1] = out[1] .. "\n\\begin{verbatim}\n" .. ast.content .. "\\end{verbatim}"
	elseif ast is nodes.Blockquote then
		out[1] = out[1] .. "\n\\begin{quote}\n"
		out[1] = out[1] .. write_blocks(ast.content, config, true)
		out[1] = out[1] .. "\n\\end{quote}"
	elseif ast is nodes.Table then
		out[1] = out[1] .. "\n\\par\\addvspace{\\medskipamount}\n\\noindent\\begin{tabularx}{\\linewidth}{" .. table_columns(ast) .. "}\n\\toprule\n"
		for index = 1, #ast.alignments do
			if index > 1 then
				out[1] = out[1] .. " & "
			end
			if ast.headers[index] then
				walk_nodes(ast.headers[index], out, config)
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
					walk_nodes(row[index], out, config)
				end
			end
			out[1] = out[1] .. " \\\\"
		end

		out[1] = out[1] .. "\n\\bottomrule\n\\end{tabularx}\n\\par\\addvspace{\\medskipamount}"
	elseif ast is nodes.Other then
		walk_nodes(ast.content, out, config)
	elseif ast is nodes.ParenCitation then
		out[1] = out[1] .. "\\" .. config.paren_citation
		if ast.locator then
			out[1] = out[1] .. "[" .. ast.locator .. "]"
		end
		out[1] = out[1] .. "{" .. table.concat(ast.content, ", ") .. "}"
	elseif ast is nodes.Link then
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
				walk_nodes(ast.content, out, config)
			end
			out[1] = out[1] .. "}"
		end
	elseif ast is nodes.Footnote then
		if ast.repeated then
			out[1] = out[1] .. "\\footref{" .. ast.label .. "}"
		else
			out[1] = out[1] .. "\\footnote{"
			if ast.label then out[1] = out[1] .. "\\label{" .. ast.label .. "}" end
			if ast.inline then walk_nodes(ast.content, out, config)
			else out[1] = out[1] .. write_blocks(ast.blocks, config, true) end
			out[1] = out[1] .. "}"
		end
	elseif ast is nodes.Literal then
		local escapes: {string: string} = { ["\\"] = "\\textbackslash{}", ["^"] = "\\textasciicircum{}", ["~"] = "\\textasciitilde{}" }
		out[1] = out[1] .. (escapes[ast.content] or ast.content:gsub("[%%{}#&_$]", "\\%0"))
	elseif ast is nodes.Citation then
		out[1] = out[1] .. "\\" .. config.citation .. "{" .. ast.content .. "}"
	elseif ast is nodes.Verbatim then
		out[1] = out[1] .. "\\texttt{" .. write_inline_code(ast.content) .. "}"
	elseif ast is nodes.InlineMath or ast is nodes.LatexCmd then
		out[1] = out[1] .. ast.content
	elseif ast is nodes.DisplayMath then
		local trimmed, removed = out[1]:gsub("\n[ \t]+$", "\n")
		out[1] = trimmed
		if removed == 0 then
			out[1] = out[1] .. "\n"
		end
		out[1] = out[1] .. "\\[" .. ast.content .. "\\]"
	elseif ast is nodes.Italic then
		out[1] = out[1] .. "\\emph{"
		walk_nodes(ast.content, out, config)
		out[1] = out[1] .. "}"
	elseif ast is nodes.Bold then
		out[1] = out[1] .. "\\textbf{"
		walk_nodes(ast.content, out, config)
		out[1] = out[1] .. "}"
	elseif ast is nodes.Strikethrough then
		out[1] = out[1] .. "\\sout{"
		walk_nodes(ast.content, out, config)
		out[1] = out[1] .. "}"
	elseif ast is nodes.Text then
		out[1] = out[1] .. write_text(ast.content)
	else
		-- slide_break, slide_note and slide_footer are consumed by lecture.structure.
		error("Unknown type: " .. ast.type)
	end
end

local contains_links: function(list: {Any | string}): boolean

contains_links = function(list: {Any | string}): boolean
	for _, node in ipairs(list) do
		-- Strings are citation keys and hold no links.
		if not (node is string) then
			if node is nodes.Link then return true end
			local content = nodes.content(node)
			if content is {Any | string} and contains_links(content) then return true end
			if node is nodes.SlideFrame and node.title and contains_links(node.title) then return true end
			if node is nodes.Table then
				for _, cell in ipairs(node.headers) do if contains_links(cell) then return true end end
				for _, row in ipairs(node.rows) do
					for _, cell in ipairs(row) do if contains_links(cell) then return true end end
				end
			end
		end
	end
	return false
end

write_blocks = function(ast: {Block}, config: Config, nested: boolean, comment_tokens?: {CommentToken}): string
	local output = { "" }
	local list_stack: {ListState} = {}

	for _, node in ipairs(ast) do
		if node is nodes.Item or node is nodes.Enum then
			ensure_list_environment(output, list_stack, node)
			walk(node, output, config)
		else
			close_all_lists(output, list_stack)
			walk(node, output, config)
		end
	end

	close_all_lists(output, list_stack)

	local result = comments.restore(output[1]:sub(2), comment_tokens)
	if not nested and contains_links(ast) then
		result = "\\ifcsname hyper@normalise\\endcsname\\else\\PackageError{mark2tex}{Markdown links require hyperref}{Load \\string\\usepackage{hyperref} in the document preamble.}\\fi\n" .. result
	end
	return result -- remove first newline that was added
end

local function write(ast: Document, config: Config, nested?: boolean): string
	return write_blocks(ast, config, nested, ast.comments)
end

return write
