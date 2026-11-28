local parse_blocks = require("mark2tex.parse_blocks")
local parse_inlines = require("mark2tex.parse_inlines")
local diagnostics = require("mark2tex.diagnostics")
local comments = require("mark2tex.comments")
local divs = require("mark2tex.divs")
local nodes = require("mark2tex.nodes")
local type links = require("mark2tex.links")
local md5 = require("md5")

local type Config = require("mark2tex.default_config")
local type Inline = nodes.Inline
local type RawBlock = nodes.RawBlock
local type Block = nodes.Block
local type Document = nodes.Document
local type Issue = diagnostics.Issue

local record ReferenceEntry
	label: string
	target: links.Reference
	used: boolean
end

local record InlineContext
	definitions: {string: string}
	seen: {string: string}
	count: integer
	resolve: function(string): nodes.Footnote
	-- Link reference definitions by normalized label, in definition order.
	references: {string: ReferenceEntry}
	reference_order: {ReferenceEntry}
	resolve_reference: function(string): links.Reference
end

local record DuplicateWarning is Issue
end

local record LinkWarning is Issue
end

local function normalize_input(str: string): string
	return "\n" .. str
end

local function same_warning(left: Issue, right: Issue): boolean
	return left.category == right.category
		and left.kind == right.kind
		and left.delimiter == right.delimiter
		and left.environment == right.environment
		and left.identifier == right.identifier
end

local function append_warning(warnings: {Issue}, candidate: Issue)
	for _, existing in ipairs(warnings) do
		if same_warning(existing, candidate) then
			return
		end
	end
	warnings[#warnings + 1] = candidate
end

local add_inline_nodes: function(ast: {RawBlock}, warnings: {Issue}, context: InlineContext, disabled?: boolean): {Block}

-- Parse the inline content of raw blocks, building the parsed block nodes.
add_inline_nodes = function(ast: {RawBlock}, warnings: {Issue}, context: InlineContext, disabled?: boolean): {Block}
	local function parse_content(content: string, allow_display?: boolean, disable_footnotes?: boolean): {Inline}
		local parsed, content_warnings = parse_inlines(content, {
			allow_display = allow_display,
			resolve_footnote = context.resolve,
			resolve_reference = context.resolve_reference,
			disable_footnotes = disabled or disable_footnotes,
		})
		for _, warning in ipairs(content_warnings) do
			append_warning(warnings, warning)
		end
		return parsed
	end

	local result: {Block} = {}
	for _, element in ipairs(ast) do
		local block: Block
		if element is nodes.Code and disabled then
			-- verbatim environments cannot occur inside a \footnote argument.
			block = nodes.other({ nodes.text("\n"), nodes.verbatim(element.content) })
		elseif element is nodes.RawBlockquote then
			local parsed: nodes.Blockquote = { type = "blockquote", content = add_inline_nodes(element.blocks, warnings, context, disabled) }
			block = parsed
		elseif element is nodes.RawTable then
			local headers: {{Inline}} = {}
			for index, cell in ipairs(element.headers) do
				headers[index] = parse_content(cell, false)
			end
			local rows: {{{Inline}}} = {}
			for row_index, row in ipairs(element.rows) do
				local cells: {{Inline}} = {}
				for index, cell in ipairs(row) do
					cells[index] = parse_content(cell, false)
				end
				rows[row_index] = cells
			end
			local parsed: nodes.Table = { type = "table", headers = headers, alignments = element.alignments, rows = rows }
			block = parsed
		elseif element is nodes.RawHeader then
			local parsed: nodes.Header = { type = "header", level = element.level, indented = element.indented,
				content = parse_content(element.content, nil, true) }
			block = parsed
		elseif element is nodes.RawItem then
			local parsed: nodes.Item = { type = "item", level = element.level, content = parse_content(element.content) }
			block = parsed
		elseif element is nodes.RawEnum then
			local parsed: nodes.Enum = { type = "enum", level = element.level, style = element.style, start = element.start,
				content = parse_content(element.content) }
			block = parsed
		elseif element is nodes.RawOther then
			block = nodes.other(parse_content(element.content))
		else
			-- The remaining raw blocks have no inline content and are shared with
			-- the parsed stage. Footnote definitions and div fences never get here.
			block = element as Block
		end
		result[#result + 1] = block
	end
	return result
end

-- Collect before resolving, allowing definitions after their references and
-- sharing the document scope with blockquotes. First duplicate wins.
local function collect_definitions(ast: {RawBlock}, context: InlineContext, warnings: {Issue}, disabled?: boolean): {RawBlock}
	local result: {RawBlock} = {}
	for _, element in ipairs(ast) do
		if element is nodes.LinkDefinition then
			-- Link references anywhere in the document can use these definitions.
			if not context.references[element.label] then
				local entry: ReferenceEntry = { label = element.label,
					target = { destination = element.destination, title = element.title } }
				context.references[element.label] = entry
				context.reference_order[#context.reference_order + 1] = entry
			end
		elseif element is nodes.FootnoteDefinition and not disabled then
			if context.definitions[element.identifier] then
				local duplicate: DuplicateWarning = { category = "footnote", kind = "duplicate", identifier = element.identifier }
				append_warning(warnings, duplicate)
			else
				context.definitions[element.identifier] = element.content
			end
		else
			if element is nodes.FootnoteDefinition then
				element = nodes.raw_other("[^" .. element.identifier .. "]: " .. element.content)
			elseif element is nodes.RawBlockquote then
				element.blocks = collect_definitions(parse_blocks(normalize_input(element.content), false, true), context, warnings, disabled)
			end
			result[#result + 1] = element
		end
	end
	return result
end

local function parse(str: string, config?: Config, source_id?: string): Document
	local lecture_profile = config and (config.profile == "slides" or config.profile == "handout")
	local source = normalize_input((str:gsub("\r\n", "\n")))
	local protected, comment_tokens, masked = comments.protect(source)
	local warnings: {Issue} = {}
	for _, warning in ipairs(diagnostics.collect(masked:sub(2))) do
		warnings[#warnings + 1] = warning
	end
	local block_ast = divs.select(parse_blocks(protected, lecture_profile), protected,
		source, comment_tokens, config, source_id, warnings)
	local fingerprint: string
	if config and config.document_id then
		fingerprint = md5.sumhexa(config.document_id)
	else
		fingerprint = md5.sumhexa(source_id and (source_id .. "\0" .. str) or str)
	end
	local context: InlineContext = { definitions = {}, seen = {}, count = 0, references = {}, reference_order = {} }
	block_ast = collect_definitions(block_ast, context, warnings)
	context.resolve_reference = function(label: string): links.Reference
		local entry = context.references[label]
		if not entry then return nil end
		entry.used = true
		return entry.target
	end
	context.resolve = function(identifier: string): nodes.Footnote
		local definition = context.definitions[identifier]
		if definition == nil then return nil end
		if context.seen[identifier] then return nodes.footnote(nil, context.seen[identifier], true) end
		context.count = context.count + 1
		local label = "mark2tex:footnote:" .. fingerprint .. ":" .. context.count
		context.seen[identifier] = label
		local blocks = collect_definitions(parse_blocks(normalize_input(definition), false, true), context, warnings, true)
		return nodes.footnote_blocks(add_inline_nodes(blocks, warnings, context, true), label)
	end
	local inline_ast = add_inline_nodes(block_ast, warnings, context) as Document
	-- An unused definition may be a paragraph line that was meant as text.
	for _, entry in ipairs(context.reference_order) do
		if not entry.used then
			local unused: LinkWarning = { category = "link", kind = "unused",
				message = "unused link definition [" .. entry.label .. "]; omitted" }
			warnings[#warnings + 1] = unused
		end
	end
	inline_ast.warnings = warnings
	inline_ast.comments = comment_tokens
	return inline_ast
end

return parse
