-- Generated from src/mark2tex/parse.tl by Teal 0.24.1. Edit the .tl file and run 'make teal-gen'.
local parse_blocks = require("mark2tex.parse_blocks")
local parse_inlines = require("mark2tex.parse_inlines")
local diagnostics = require("mark2tex.diagnostics")
local comments = require("mark2tex.comments")
local divs = require("mark2tex.divs")
local nodes = require("mark2tex.nodes")
local md5 = require("md5")


















local function normalize_input(str)
   return "\n" .. str
end

local function same_warning(left, right)
   return left.category == right.category and
   left.kind == right.kind and
   left.delimiter == right.delimiter and
   left.environment == right.environment and
   left.identifier == right.identifier
end

local function append_warning(warnings, candidate)
   for _, existing in ipairs(warnings) do
      if same_warning(existing, candidate) then
         return
      end
   end
   warnings[#warnings + 1] = candidate
end

local add_inline_nodes


add_inline_nodes = function(ast, warnings, context, disabled)
   local function parse_content(content, allow_display, disable_footnotes)
      local parsed, content_warnings = parse_inlines(content, {
         allow_display = allow_display,
         resolve_footnote = context.resolve,
         disable_footnotes = disabled or disable_footnotes,
      })
      for _, warning in ipairs(content_warnings) do
         append_warning(warnings, warning)
      end
      return parsed
   end

   local result = {}
   for _, element in ipairs(ast) do
      local block
      if element.type == "code" and disabled then

         block = nodes.other({ nodes.text("\n"), nodes.verbatim(element.content) })
      elseif element.type == "blockquote" then
         local parsed = { type = "blockquote", content = add_inline_nodes(element.blocks, warnings, context, disabled) }
         block = parsed
      elseif element.type == "table" then
         local headers = {}
         for index, cell in ipairs(element.headers) do
            headers[index] = parse_content(cell, false)
         end
         local rows = {}
         for row_index, row in ipairs(element.rows) do
            local cells = {}
            for index, cell in ipairs(row) do
               cells[index] = parse_content(cell, false)
            end
            rows[row_index] = cells
         end
         local parsed = { type = "table", headers = headers, alignments = element.alignments, rows = rows }
         block = parsed
      elseif element.type == "header" then
         local parsed = { type = "header", level = element.level, indented = element.indented,
content = parse_content(element.content, nil, true), }
         block = parsed
      elseif element.type == "item" then
         local parsed = { type = "item", level = element.level, content = parse_content(element.content) }
         block = parsed
      elseif element.type == "enum" then
         local parsed = { type = "enum", level = element.level, style = element.style, start = element.start,
content = parse_content(element.content), }
         block = parsed
      elseif element.type == "other" then
         block = nodes.other(parse_content(element.content))
      else


         block = element
      end
      result[#result + 1] = block
   end
   return result
end



local function collect_definitions(ast, context, warnings, disabled)
   local result = {}
   for _, element in ipairs(ast) do
      if element.type == "footnote_definition" and not disabled then
         if context.definitions[element.identifier] then
            local duplicate = { category = "footnote", kind = "duplicate", identifier = element.identifier }
            append_warning(warnings, duplicate)
         else
            context.definitions[element.identifier] = element.content
         end
      else
         if element.type == "footnote_definition" then
            element = nodes.raw_other("[^" .. element.identifier .. "]: " .. element.content)
         elseif element.type == "blockquote" then
            element.blocks = collect_definitions(parse_blocks(normalize_input(element.content), false, true), context, warnings, disabled)
         end
         result[#result + 1] = element
      end
   end
   return result
end

local function parse(str, config, source_id)
   local lecture_profile = config and (config.profile == "slides" or config.profile == "handout")
   local source = normalize_input((str:gsub("\r\n", "\n")))
   local protected, comment_tokens, masked = comments.protect(source)
   local warnings = {}
   for _, warning in ipairs(diagnostics.collect(masked:sub(2))) do
      warnings[#warnings + 1] = warning
   end
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
