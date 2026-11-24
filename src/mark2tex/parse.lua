local parse_blocks = require("mark2tex.parse_blocks")
local parse_inlines = require("mark2tex.parse_inlines")
local diagnostics = require("mark2tex.diagnostics")
local comments = require("mark2tex.comments")
local divs = require("mark2tex.divs")
local nodes = require("mark2tex.nodes")
local md5 = require("md5")

local INLINE_BLOCK_TYPES = {
	header = true,
	item = true,
	enum = true,
	other = true,
}

local function normalize_input(str)
	return "\n" .. str
end

local function same_warning(left, right)
	return left.category == right.category
		and left.kind == right.kind
		and left.delimiter == right.delimiter
		and left.environment == right.environment
		and left.identifier == right.identifier
end

local function append_warning(warnings, candidate)
	for _, existing in ipairs(warnings) do
		if same_warning(existing, candidate) then
			return
		end
	end
	warnings[#warnings + 1] = candidate
end

local function add_inline_nodes(ast, warnings, context, disabled)
	local function parse_content(content, options)
		options = options or {}
		options.resolve_footnote = context.resolve
		options.disable_footnotes = disabled or options.disable_footnotes
		local parsed, content_warnings = parse_inlines(content, options)
		for _, warning in ipairs(content_warnings) do
			append_warning(warnings, warning)
		end
		return parsed
	end

	for _, element in ipairs(ast) do
		if element.type == "code" and disabled then
			-- verbatim environments cannot occur inside a \footnote argument.
			element.type, element.content = "other", { nodes.text("\n"), nodes.verbatim(element.content) }
		elseif element.type == "blockquote" then
			element.content = add_inline_nodes(element.content, warnings, context, disabled)
		elseif element.type == "table" then
			for index, cell in ipairs(element.headers) do
				element.headers[index] = parse_content(cell, { allow_display = false })
			end
			for _, row in ipairs(element.rows) do
				for index, cell in ipairs(row) do
					row[index] = parse_content(cell, { allow_display = false })
				end
			end
		elseif INLINE_BLOCK_TYPES[element.type] then
			element.content = parse_content(element.content, { disable_footnotes = element.type == "header" })
		end
	end
	return ast
end

-- Collect before resolving, allowing definitions after their references and
-- sharing the document scope with blockquotes. First duplicate wins.
local function collect_definitions(ast, context, warnings, disabled)
	local result = {}
	for _, element in ipairs(ast) do
		if element.type == "footnote_definition" and not disabled then
			if context.definitions[element.identifier] then
				append_warning(warnings, { category = "footnote", kind = "duplicate", identifier = element.identifier })
			else
				context.definitions[element.identifier] = element.content
			end
		else
			if element.type == "footnote_definition" then
				element = nodes.other("[^" .. element.identifier .. "]: " .. element.content)
			elseif element.type == "blockquote" then
				element.content = collect_definitions(parse_blocks(normalize_input(element.content), false, true), context, warnings, disabled)
			end
			result[#result + 1] = element
		end
	end
	return result
end

local function parse(str, config, source_id)
	local lecture_profile = config and (config.profile == "slides" or config.profile == "handout")
	local source = normalize_input(str:gsub("\r\n", "\n"))
	local protected, comment_tokens, masked = comments.protect(source)
	local warnings = diagnostics.collect(masked:sub(2))
	local block_ast = divs.select(parse_blocks(protected, lecture_profile), protected,
		source, comment_tokens, config, source_id, warnings)
	local fingerprint
	if config and config.document_id then
		fingerprint = md5.sumhexa(config.document_id)
	else
		fingerprint = md5.sumhexa(source_id and (source_id .. "\0" .. str) or str)
	end
	local context = { definitions = {}, seen = {}, count = 0 }
	block_ast = collect_definitions(block_ast, context, warnings)
	context.resolve = function(identifier)
		local definition = context.definitions[identifier]
		if definition == nil then return nil end
		if context.seen[identifier] then return nodes.footnote(nil, context.seen[identifier], true) end
		context.count = context.count + 1
		local label = "mark2tex:footnote:" .. fingerprint .. ":" .. context.count
		context.seen[identifier] = label
		local blocks = collect_definitions(parse_blocks(normalize_input(definition), false, true), context, warnings, true)
		return nodes.footnote(add_inline_nodes(blocks, warnings, context, true), label)
	end
	local inline_ast = add_inline_nodes(block_ast, warnings, context)
	inline_ast.warnings = warnings
	inline_ast.comments = comment_tokens
	return inline_ast
end

return parse
