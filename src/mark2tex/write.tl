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

-- Output is collected in a buffer and joined once; growing one string by
-- concatenation would copy it on every write.
local record Buffer
	parts: {string}
end

local function emit(out: Buffer, ...: string)
	for index = 1, select("#", ...) do
		out.parts[#out.parts + 1] = select(index, ...)
	end
end

-- Display math joins the buffer to inspect its end; that is rare.
local function remove_trailing_indent(out: Buffer): boolean
	local trimmed, removed = table.concat(out.parts):gsub("\n[ \t]+$", "\n")
	out.parts = { trimmed }
	return removed > 0
end

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

local function close_list(out: Buffer, stack: {ListState})
	local current = table.remove(stack)
	emit(out, "\n\\end{", list_environment(current.type), "}")
end

local function close_lists_until(out: Buffer, stack: {ListState}, level: integer)
	while #stack > 0 and stack[#stack].level > level do
		close_list(out, stack)
	end
end

local function close_all_lists(out: Buffer, stack: {ListState})
	while #stack > 0 do
		close_list(out, stack)
	end
end

local function open_list(out: Buffer, stack: {ListState}, ast: ListNode)
	table.insert(stack, { type = ast.type, level = ast.level, style = list_style(ast) })
	emit(out, "\n\\begin{", list_environment(ast.type), "}")
	if ast is nodes.Enum then
		local counter = "\\csname @enumctr\\endcsname"
		if ast.style == "alpha" then
			-- Capture the counter name for references from nested lists.
			emit(out, "\n\\expandafter\\edef\\csname the", counter, "\\endcsname{",
				"\\expandafter\\noexpand\\csname int_to_alph:n\\endcsname",
				"{\\noexpand\\value{", counter, "}}}",
				"\n\\expandafter\\def\\csname @itemlabel\\endcsname{",
				"\\csname the", counter, "\\endcsname)}")
		end
		if ast.start and ast.start ~= 1 then
			emit(out, "\n\\setcounter{", counter, "}{", tostring(ast.start - 1), "}")
		end
	end
end

local function ensure_list_environment(out: Buffer, stack: {ListState}, ast: ListNode)
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
local INLINE_CODE_ESCAPES: {string: string} = {
	["\\"] = "\\textbackslash{}",
	["^"] = "\\textasciicircum{}",
	["~"] = "\\textasciitilde{}",
}

local function write_inline_code(text: string): string
	return (text:gsub("[\\%%{}#&_$^~]", function(character: string): string
		return INLINE_CODE_ESCAPES[character] or "\\" .. character
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

--------------------
-- One writer per node type, dispatched on the type field
--------------------

local type Handler = function(node: Any, out: Buffer, config: Config)

local walk: function(ast: Any, out: Buffer, config: Config)

local function walk_nodes(list: {Any}, out: Buffer, config: Config)
	for _, node in ipairs(list) do
		walk(node, out, config)
	end
end

-- Wrap inline content in a TeX command.
local function wrapped(command: string): Handler
	return function(ast: Any, out: Buffer, config: Config)
		emit(out, command, "{")
		walk_nodes(nodes.content(ast) as {Any}, out, config)
		emit(out, "}")
	end
end

local function write_header(ast: nodes.Header, out: Buffer, config: Config)
	-- Deeper headers than configured use the deepest configured command.
	local level = math.min(ast.level, #config.header)
	emit(out, "\n\\", config.header[level], "{")
	walk_nodes(ast.content, out, config)
	emit(out, "}")
end

local function write_slide_frame(ast: nodes.SlideFrame, out: Buffer, config: Config)
	local options = has_verbatim(ast.content) and "t,fragile" or "t"
	emit(out, "\n\\begin{frame}[", options, "]\n")
	if ast.title then
		emit(out, "\\frametitle{")
		walk_nodes(ast.title, out, config)
		emit(out, "}\n")
	end
	if ast.footer then
		emit(out, "\\SlideFooter{", write_annotation(ast.footer), "}\n")
	end
	if ast.notes and #ast.notes > 0 then
		local notes: {string} = {}
		for _, note in ipairs(ast.notes) do
			notes[#notes + 1] = write_annotation(note)
		end
		emit(out, "\\note{", table.concat(notes, "\\par "), "}\n")
	end
	emit(out, write_blocks(ast.content, config, true), "\n\\end{frame}\n")
end

local function write_slide_subheading(ast: nodes.SlideSubheading, out: Buffer, config: Config)
	emit(out, "\n\\par\\medskip\\noindent\\textbf{")
	walk_nodes(ast.content, out, config)
	emit(out, "}\\par\n")
end

local function write_lecture_annotations(ast: nodes.LectureAnnotations, out: Buffer)
	if ast.footer then
		emit(out, "\n\\par\\noindent{\\small ", write_annotation(ast.footer), "}\\par\n")
	end
	for _, note in ipairs(ast.notes) do
		emit(out, "\n\\par\\noindent\\textbf{Vortragsnotiz:} ", write_annotation(note), "\\par\n")
	end
end

local function write_image(ast: nodes.Image, out: Buffer)
	local size = ast.width ~= "" and ("width=" .. ast.width .. ",") or ""
	emit(out, "\n\\adjustbox{", size, "max width=\\linewidth}{\\includegraphics{", ast.path, "}}")
end

local function write_item(ast: nodes.Item, out: Buffer, config: Config)
	emit(out, "\n\\item ")
	walk_nodes(ast.content, out, config)
end

local function write_enum(ast: nodes.Enum, out: Buffer, config: Config)
	emit(out, "\n\\item") -- TODO: the space after \item is not always needed
	walk_nodes(ast.content, out, config)
end

local function write_blockquote(ast: nodes.Blockquote, out: Buffer, config: Config)
	emit(out, "\n\\begin{quote}\n", write_blocks(ast.content, config, true), "\n\\end{quote}")
end

local function write_table(ast: nodes.Table, out: Buffer, config: Config)
	emit(out, "\n\\par\\addvspace{\\medskipamount}\n\\noindent\\begin{tabularx}{\\linewidth}{", table_columns(ast), "}\n\\toprule\n")
	for index = 1, #ast.alignments do
		if index > 1 then emit(out, " & ") end
		if ast.headers[index] then walk_nodes(ast.headers[index], out, config) end
	end
	emit(out, " \\\\\n\\midrule")

	for _, row in ipairs(ast.rows) do
		emit(out, "\n")
		for index = 1, #ast.alignments do
			if index > 1 then emit(out, " & ") end
			if row[index] then walk_nodes(row[index], out, config) end
		end
		emit(out, " \\\\")
	end

	emit(out, "\n\\bottomrule\n\\end{tabularx}\n\\par\\addvspace{\\medskipamount}")
end

local function write_other(ast: nodes.Other, out: Buffer, config: Config)
	walk_nodes(ast.content, out, config)
end

local function write_paren_citation(ast: nodes.ParenCitation, out: Buffer, config: Config)
	emit(out, "\\", config.paren_citation)
	if ast.locator then emit(out, "[", ast.locator, "]") end
	emit(out, "{", table.concat(ast.content, ", "), "}")
end

local function write_link(ast: nodes.Link, out: Buffer, config: Config)
	local destination = ast.destination
	if destination:match("^[%a][%w+.-]*:") then
		destination = destination:gsub(" ", "%%20")
	end
	if ast.kind == "autolink" then
		emit(out, "\\url{", links.tex_destination(destination), "}")
		return
	end
	if destination:sub(1, 1) == "#" and #destination > 1 then
		emit(out, "\\hyperref[", links.tex_destination(destination:sub(2)), "]{")
	else
		emit(out, "\\href{", links.tex_destination(destination), "}{")
	end
	if ast.kind == "email" then
		emit(out, "\\nolinkurl{", links.tex_destination(ast.destination:sub(8)), "}")
	else
		walk_nodes(ast.content, out, config)
	end
	emit(out, "}")
end

local function write_footnote(ast: nodes.Footnote, out: Buffer, config: Config)
	if ast.repeated then
		emit(out, "\\footref{", ast.label, "}")
		return
	end
	emit(out, "\\footnote{")
	if ast.label then emit(out, "\\label{", ast.label, "}") end
	if ast.inline then
		walk_nodes(ast.content, out, config)
	else
		emit(out, write_blocks(ast.blocks, config, true))
	end
	emit(out, "}")
end

local LITERAL_ESCAPES: {string: string} = { ["\\"] = "\\textbackslash{}", ["^"] = "\\textasciicircum{}", ["~"] = "\\textasciitilde{}" }

local function write_literal(ast: nodes.Literal, out: Buffer)
	emit(out, LITERAL_ESCAPES[ast.content] or (ast.content:gsub("[%%{}#&_$]", "\\%0")))
end

local function write_display_math(ast: nodes.DisplayMath, out: Buffer)
	-- Display math starts on its own line, without the indentation before it.
	if not remove_trailing_indent(out) then emit(out, "\n") end
	emit(out, "\\[", ast.content, "\\]")
end

local function raw(prefix: string, suffix: string): Handler
	return function(ast: Any, out: Buffer)
		emit(out, prefix, nodes.content(ast) as string, suffix)
	end
end

local function constant(text: string): Handler
	return function(_: Any, out: Buffer)
		emit(out, text)
	end
end

-- slide_break, slide_note and slide_footer are consumed by lecture.structure.
local WRITERS: {string: Handler} = {
	header = write_header as Handler,
	slide_frame = write_slide_frame as Handler,
	slide_pause = constant("\n\\par\\pause\n"),
	slide_subheading = write_slide_subheading as Handler,
	lecture_annotations = write_lecture_annotations as Handler,
	slide_paragraph = constant("\n\\par\n"),
	horizontal_rule = constant("\n\\par\\addvspace{\\medskipamount}\n\\noindent\\rule{\\linewidth}{0.4pt}\n\\par\\addvspace{\\medskipamount}"),
	image = write_image as Handler,
	latex = raw("\n", ""),
	item = write_item as Handler,
	enum = write_enum as Handler,
	code = raw("\n\\begin{verbatim}\n", "\\end{verbatim}"),
	blockquote = write_blockquote as Handler,
	table = write_table as Handler,
	other = write_other as Handler,
	paren_citation = write_paren_citation as Handler,
	link = write_link as Handler,
	footnote = write_footnote as Handler,
	literal = write_literal as Handler,
	verbatim = function(ast: Any, out: Buffer)
		emit(out, "\\texttt{", write_inline_code(nodes.content(ast) as string), "}")
	end,
	inline_math = raw("", ""),
	latex_cmd = raw("", ""),
	display_math = write_display_math as Handler,
	italic = wrapped("\\emph"),
	bold = wrapped("\\textbf"),
	strikethrough = wrapped("\\sout"),
	text = function(ast: Any, out: Buffer)
		emit(out, write_text(nodes.content(ast) as string))
	end,
}

-- citation uses the configured command, so it needs the config.
WRITERS.citation = function(ast: Any, out: Buffer, config: Config)
	emit(out, "\\", config.citation, "{", nodes.content(ast) as string, "}")
end

walk = function(ast: Any, out: Buffer, config: Config)
	local writer = WRITERS[ast.type]
	if not writer then
		error("Unknown type: " .. ast.type)
	end
	writer(ast, out, config)
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
	local out: Buffer = { parts = {} }
	local list_stack: {ListState} = {}

	for _, node in ipairs(ast) do
		if node is nodes.Item or node is nodes.Enum then
			ensure_list_environment(out, list_stack, node)
		else
			close_all_lists(out, list_stack)
		end
		walk(node, out, config)
	end

	close_all_lists(out, list_stack)

	-- Every block starts with a newline; drop the one before the first block.
	local result = comments.restore(table.concat(out.parts):sub(2), comment_tokens)
	if not nested and contains_links(ast) then
		result = "\\ifcsname hyper@normalise\\endcsname\\else\\PackageError{mark2tex}{Markdown links require hyperref}{Load \\string\\usepackage{hyperref} in the document preamble.}\\fi\n" .. result
	end
	return result
end

local function write(ast: Document, config: Config, nested?: boolean): string
	return write_blocks(ast, config, nested, ast.comments)
end

return write
