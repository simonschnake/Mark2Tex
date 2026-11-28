-- Mark2TeX 0.2.0: Markdown-like fragments for LuaLaTeX.
-- Generated from src/mark2tex/*.tl by Teal 0.24.1 and scripts/bundle.lua.
-- Do not edit; change the Teal sources and run 'make teal-gen'.

package.preload["mark2tex.autolinks"] = function(...)
	return assert(load([[

















local autolinks = {}





function autolinks.match(source, position)
   local last = source:find(">", position + 1, true)
   if not last then return nil end
   local value = source:sub(position + 1, last - 1)
   if value:find("[%z\1-\32\127<>]") then return nil end
   local scheme = value:match("^([%a][%w+.-]*):")
   if scheme and #scheme >= 2 and #scheme <= 32 then
      return { destination = value, label = value, kind = "autolink", finish = last, label_end = position }
   end
   local localpart, domain = value:match("^([%w.!#$%%&'*+/=?^_`{|}~-]+)@([%w.-]+)$")
   if localpart and domain then
      local valid = true
      for part in (domain .. "."):gmatch("(.-)%.") do
         if #part == 0 or #part > 63 or not part:match("^[%w].*[%w]$") and not part:match("^[%w]$") then valid = false end
      end
      if valid then return { destination = "mailto:" .. value, label = value, kind = "email", finish = last, label_end = position } end
   end
   return nil
end

return autolinks
]], "@src/mark2tex/autolinks.tl"))(...)
end

package.preload["mark2tex.comments"] = function(...)
	return assert(load([[








local comments = {}



function comments.protect(source)
   local prefix = "MARKTWOTEXCOMMENT"
   while source:find(prefix, 1, true) do
      prefix = prefix .. "X"
   end
   local output, masked = {}, {}
   local tokens = {}
   local position, protected_position = 1, 1
   while position <= #source do
      local first, last = source:find("^`+", position)
      if first then
         local delimiter = source:sub(first, last)
         local closing = source:find(delimiter, last + 1, true)
         local ending = closing and closing + #delimiter - 1 or #source
         local code = source:sub(position, ending)
         output[#output + 1], masked[#masked + 1] = code, code
         position = ending + 1
      elseif source:sub(position, position + 3) == "<!--" then
         local closing = source:find("-->", position + 4, true)
         local ending = closing and closing + 2 or #source
         local original = source:sub(position, ending)
         local content = source:sub(position + 4, closing and closing - 1 or #source)
         local token = prefix .. tostring(#tokens + 1) .. "END"
         tokens[#tokens + 1] = {
            token = token,
            content = content,
            source_end = ending + 1,
            protected_position = protected_position,
         }
         output[#output + 1] = token

         masked[#masked + 1] = original:gsub("[^\r\n]", " ")
         position = ending + 1
      else
         local character = source:sub(position, position)
         output[#output + 1], masked[#masked + 1] = character, character
         position = position + 1
      end
      protected_position = protected_position + #output[#output]
   end
   return table.concat(output), tokens, table.concat(masked)
end

function comments.restore(output, tokens)
   for _, comment in ipairs(tokens or {}) do
      output = output:gsub(comment.token .. "([ \t]*)(\r?\n?)", function(spaces, newline)
         local content = comment.content:gsub("\r\n", "\n"):gsub("\r", "\n")


         return spaces .. "%" .. content:gsub("\n", "\n%%") .. (newline ~= "" and newline or "\n")
      end)
   end
   return output
end

return comments
]], "@src/mark2tex/comments.tl"))(...)
end

package.preload["mark2tex.core"] = function(...)
	return assert(load([[
local default_config = require("mark2tex.default_config")













local parse = require("mark2tex.parse")
local write = require("mark2tex.write")
local lecture = require("mark2tex.lecture")
local fu = require("mark2tex.fileutils")
local md5 = require("md5")

local core = {}




local CACHE_VERSION = "v19"

local function copy_table(value)
   if type(value) ~= "table" then
      return value
   end

   local copy = {}
   for k, v in pairs(value) do
      copy[k] = copy_table(v)
   end
   return copy
end

local function resolve_config(cfg)
   local config = copy_table(default_config)

   if cfg then
      for k, v in pairs(cfg) do
         config[k] = copy_table(v)
      end
   end

   if config.profile ~= nil then
      if config.profile ~= "handout" and config.profile ~= "slides" then
         return nil, "profile must be handout or slides"
      end
      local level = config.slide_level == nil and 2 or tonumber(config.slide_level)
      if not level or level % 1 ~= 0 or level < 1 or level > 6 then
         return nil, "slide-level must be an integer from 1 to 6"
      end
      config.slide_level = math.floor(level)
   elseif config.slide_level ~= nil then
      return nil, "slide-level requires a handout or slides profile"
   end

   if config.slide_audience ~= nil then
      if config.profile ~= "slides" then
         return nil, "slide-audience requires the slides profile"
      end
      if config.slide_audience ~= "regular" and config.slide_audience ~= "dozent" then
         return nil, "slide-audience must be regular or dozent"
      end
      if config.slide_audience == "regular" then config.slide_audience = nil end
   end

   if config.h1 ~= nil then
      if config.profile ~= "slides" then return nil, "h1 requires the slides profile" end
      if config.h1 ~= "section" and config.h1 ~= "frame" and config.h1 ~= "hide" then
         return nil, "h1 must be section, frame or hide"
      end
      if config.h1 == "section" then config.h1 = nil end
   end
   if config.audience ~= nil and config.audience ~= "instructor" and config.audience ~= "student" then
      return nil, "audience must be student or instructor"
   end

   return config
end

core.resolve_config = resolve_config

function core.get_output_path(input_path, cfg)
   local config, err = resolve_config(cfg)
   if not config then return nil, err end
   local path = fu.get_output_filename(input_path, config.save_dir)
   local variant = config.audience == "instructor" or config.slide_audience == "dozent"
   local suffix = config.profile and ("-" .. config.profile .. "-" .. config.slide_level) or ""
   if variant then suffix = suffix .. "-dozent" end
   if config.h1 then suffix = suffix .. "-h1-" .. config.h1 end
   return (path:gsub("%.tex$", suffix .. ".tex"))
end

local function sort_keys(left, right)
   local left_type = type(left)
   local right_type = type(right)

   if left_type == right_type then
      if left_type == "number" then
         return (left) < (right)
      end
      return tostring(left) < tostring(right)
   end

   return left_type < right_type
end

local function serialize_value(value)
   local value_type = type(value)

   if value_type == "table" then
      local entries = value
      local keys = {}
      for key in pairs(entries) do
         keys[#keys + 1] = key
      end

      table.sort(keys, sort_keys)

      local parts = { "{" }
      for _, key in ipairs(keys) do
         parts[#parts + 1] = serialize_value(key)
         parts[#parts + 1] = "="
         parts[#parts + 1] = serialize_value(entries[key])
         parts[#parts + 1] = ";"
      end
      parts[#parts + 1] = "}"
      return table.concat(parts)
   elseif value_type == "string" then
      return string.format("%q", value)
   elseif value_type == "number" or value_type == "boolean" then
      return tostring(value)
   elseif value_type == "nil" then
      return "nil"
   end

   return string.format("%s:%s", value_type, tostring(value))
end

local function build_cache_key(content, config)
   local serialized = table.concat({
      CACHE_VERSION,
      serialize_value(content),
      serialize_value(config),
   }, "\n")

   return md5.sumhexa(serialized)
end


function core.convert(input_path, cfg)
   local config, config_error = resolve_config(cfg)
   if not config then return nil, config_error end


   local created, directory_error = fu.create_directory(config.save_dir)
   if not created then
      return nil, directory_error
   end


   local output_path = core.get_output_path(input_path, config)

   local content, read_error = fu.read_file(input_path)
   if not content then
      return nil, read_error
   end

   if kpse and kpse.record_input_file then
      kpse.record_input_file(input_path)
   end

   local cache_key = build_cache_key(content, config)


   local last_conversion = fu.getFirstLine(output_path)
   if last_conversion == "% cache:" .. cache_key then
      return output_path
   end

   local ok, ast = pcall(parse, content, config, input_path)
   if not ok then return nil, ast end
   for _, warning in ipairs(ast.warnings or {}) do
      local location = warning.line and (input_path .. ":" .. warning.line .. ":" .. warning.column .. ": ") or ""
      if warning.message then
         io.stderr:write("mark2tex warning [" .. warning.category .. "] " .. location .. warning.message .. "\n")
      else
         local subject = warning.identifier and ("footnote " .. warning.identifier) or
         warning.delimiter and ("delimiter " .. warning.delimiter) or ("environment " .. warning.environment)
         if warning.kind == "mismatched" then
            subject = subject .. " (expected \\end{" .. warning.expected_end .. "}, found \\end{" .. warning.actual_end .. "})"
         end
         local action = warning.kind == "duplicate" and "; first definition used" or "; kept literal"
         io.stderr:write("mark2tex warning [" .. warning.category .. "] " .. location .. warning.kind .. " " .. subject .. action .. "\n")
      end
   end
   if config.profile then ast = lecture.structure(ast, config) end
   local tex = write(ast, config)


   tex = "% cache:" .. cache_key .. "\n" .. tex

   local success, err = fu.save_file(output_path, tex)
   if not success then
      return nil, err
   elseif config.verbose then
      print("\nFile processed and saved to " .. output_path)
   end
   return output_path
end

return core
]], "@src/mark2tex/core.tl"))(...)
end

package.preload["mark2tex.default_config"] = function(...)
	return assert(load([[


local Config = {}





































Config.header = {
   "section",
   "subsection",
   "subsubsection",
   "paragraph",
   "subparagraph",
}

Config.paren_citation = "parencite"
Config.citation = "cite"

Config.save_dir = "mark2tex"

return Config
]], "@src/mark2tex/default_config.tl"))(...)
end

package.preload["mark2tex.delimiters"] = function(...)
	return assert(load([[
local delimiters = {}

function delimiters.is_escaped(input, position)
   local slashes = 0
   local index = position - 1
   while index >= 1 and input:sub(index, index) == "\\" do
      slashes = slashes + 1
      index = index - 1
   end
   return slashes % 2 == 1
end

function delimiters.find_unescaped(input, delimiter, start)
   local index = start
   while true do
      index = input:find(delimiter, index, true)
      if not index or not delimiters.is_escaped(input, index) then
         return index
      end
      index = index + #delimiter
   end
end

return delimiters
]], "@src/mark2tex/delimiters.tl"))(...)
end

package.preload["mark2tex.diagnostics"] = function(...)
	return assert(load([[

local delimiters = require("mark2tex.delimiters")
























local diagnostics = {}











local links = require("mark2tex.links")

local function source_position(source, position)
   local prefix = source:sub(1, position - 1)
   local _, newlines = prefix:gsub("\n", "")
   local last_newline = (prefix:match(".*()\n")) or 0
   return newlines + 1, position - last_newline
end

local function warning(source, position, fields)
   fields.line, fields.column = source_position(source, position)
   return fields
end

local function mask_inline_code(line)
   local output = {}
   local position = 1
   while position <= #line do
      local opening = line:find("`", position, true)
      if not opening then
         output[#output + 1] = line:sub(position)
         break
      end
      output[#output + 1] = line:sub(position, opening - 1)
      local closing = line:find("`", opening + 1, true)
      local last = closing or #line
      output[#output + 1] = string.rep(" ", last - opening + 1)
      position = last + 1
   end
   return table.concat(output)
end

local function mask_code(source)
   local output = {}
   local position = 1
   local in_fence = false
   while position <= #source do
      local newline = source:find("\n", position, true)
      local last = newline and newline - 1 or #source
      local line = source:sub(position, last)
      local fence = line:match("^%s*```") ~= nil
      if in_fence or fence then
         output[#output + 1] = string.rep(" ", #line)
      else
         output[#output + 1] = mask_inline_code(line)
      end
      if fence then
         in_fence = not in_fence
      end
      if newline then
         output[#output + 1] = "\n"
      end
      position = last + 2
   end
   return table.concat(output)
end

local function display_warnings(scanned, source, warnings)
   local position = 1
   while position <= #scanned do
      local dollar = delimiters.find_unescaped(scanned, "$$", position)
      local bracket = delimiters.find_unescaped(scanned, "\\[", position)
      local opening
      local closing_delimiter
      if dollar and (not bracket or dollar < bracket) then
         opening, closing_delimiter = dollar, "$$"
      elseif bracket then
         opening, closing_delimiter = bracket, "\\]"
      else
         break
      end

      local closing = delimiters.find_unescaped(scanned, closing_delimiter, opening + 2)
      if not closing then
         warnings[#warnings + 1] = warning(source, opening, {
            category = "math-delimiter",
            kind = "unclosed",
            delimiter = source:sub(opening, opening + 1),
         })
         break
      end
      position = closing + 2
   end
end


local find_environment = string.find

local function environment_warnings(scanned, source, warnings)
   local stack = {}
   local position = 1
   while true do
      local first, last, command, name = find_environment(scanned, "\\(begin)%s*{([^}]+)}", position)
      local end_first, end_last, end_command, end_name = find_environment(scanned, "\\(end)%s*{([^}]+)}", position)
      if end_first and (not first or end_first < first) then
         first, last, command, name = end_first, end_last, end_command, end_name
      end
      if not first then
         break
      end

      if command == "begin" then
         stack[#stack + 1] = { name = name, position = first }
      elseif #stack == 0 then
         warnings[#warnings + 1] = warning(source, first, {
            category = "latex-environment",
            kind = "unexpected-end",
            environment = name,
         })
      elseif stack[#stack].name == name then
         table.remove(stack)
      else
         local opened = table.remove(stack)
         warnings[#warnings + 1] = warning(source, opened.position, {
            category = "latex-environment",
            kind = "mismatched",
            environment = opened.name,
            expected_end = opened.name,
            actual_end = name,
         })
      end
      position = last + 1
   end

   for _, opened in ipairs(stack) do
      warnings[#warnings + 1] = warning(source, opened.position, {
         category = "latex-environment",
         kind = "unclosed",
         environment = opened.name,
      })
   end
end

function diagnostics.collect(source)
   local warnings = {}
   local scanned = links.mask_destinations(mask_code(source))
   display_warnings(scanned, source, warnings)
   environment_warnings(scanned, source, warnings)
   return warnings
end

return diagnostics
]], "@src/mark2tex/diagnostics.tl"))(...)
end

package.preload["mark2tex.divs"] = function(...)
	return assert(load([[
local nodes = require("mark2tex.nodes")
















local divs = {}






























local annotations = { notes = "slide_note", footer = "slide_footer" }

local function append_block(output, node)
   local previous = output[#output]
   if previous and previous.type == "other" and node.type == "other" and
      previous.content:find("%S") and node.content:find("%S") then
      local gap = previous.content:match("%s*$") .. node.content:match("^%s*")
      local _, newlines = gap:gsub("\n", "")
      if newlines < 2 then node.content = string.rep("\n", 2 - newlines) .. node.content end
   end
   output[#output + 1] = node
end

local function classes(attributes)
   if attributes:sub(1, 1) ~= "{" then return { attributes } end
   local result = {}

   attributes = attributes:gsub('"[^"]*"', '""'):gsub("'[^']*'", "''")
   for class in attributes:sub(2, -2):gmatch("%S+") do
      if class:match("^%.[%w_-]+$") then result[#result + 1] = class:sub(2) end
   end
   return result
end

function divs.select(
   ast,
   protected,
   source,
   comment_tokens,
   config,
   source_id,
   warnings)

   local slides = config and config.profile == "slides"
   local lecture = slides or (config and config.profile == "handout")
   local instructor = config and (config.audience == "instructor" or config.slide_audience == "dozent")
   local enabled = { slides = slides == true, script = not slides,
instructor = instructor == true, student = not instructor, }
   local output = {}
   local stack = {}
   local function tex(content)
      local marker = nodes.latex(content)
      output[#output + 1] = marker
      return marker
   end
   local previous_fence_end
   local comment_index, offset = 1, 0
   local line, line_start, scanned = 0, 1, 1

   local function locate(position)
      while comment_tokens[comment_index] and comment_tokens[comment_index].protected_position < position do
         local comment = comment_tokens[comment_index]
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
      local warning = { category = "div-fence", message = message,
line = at_line, column = at_column, }
      warnings[#warnings + 1] = warning
   end

   local function fail(message, at_line)
      error((source_id or "Markdown") .. ":" .. at_line .. ": " .. message, 0)
   end

   for _, block in ipairs(ast) do
      local parent = stack[#stack]
      if block.type ~= "div_fence" then
         if not parent or (parent.visible and not parent.annotation) then
            append_block(output, block)
         end
      else
         local node = block
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
            if parent.visible and parent.layout == "columns" then
               if #parent.columns < 2 then fail("columns needs at least two visible column blocks", parent.line) end
               if slides then
                  local count = #parent.columns
                  for _, marker in ipairs(parent.columns) do
                     marker.content = string.format("\\begin{column}{\\dimexpr(\\linewidth-%d\\columnsep)/%d\\relax}", count - 1, count)
                  end
                  tex("\\end{columns}")
               end
            elseif parent.visible and parent.layout == "column" then
               tex(slides and "\\end{column}" or "\\par")
            elseif parent.visible and parent.layout == "figure" then
               if not parent.caption then tex("\\end{adjustbox}") end
               tex("\\par\\endgroup")
            end
            if lecture and parent.visible and parent.annotation and parent.annotation.owner == parent then
               local title = table.concat(parent.annotation.chunks):match("^%s*(.-)%s*$")
               if title ~= "" then
                  if parent.annotation.kind == "slide_note" then
                     local note = { type = "slide_note", title = title }
                     output[#output + 1] = note
                  else
                     local footer = { type = "slide_footer", title = title }
                     output[#output + 1] = footer
                  end
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
            if node.visible and not node.annotation then
               for _, class in ipairs(classes(node.attributes)) do
                  if class == "columns" then
                     node.layout, node.columns = class, {}
                     if slides then tex("\\begin{columns}[T,onlytextwidth]") end
                  elseif class == "column" then
                     if not parent or not parent.columns then fail("column requires columns", node.line) end
                     node.layout = class
                     table.insert(parent.columns, tex("\\par"))
                  elseif class == "figure" then
                     node.layout = class
                     local width = node.attributes:match("%swidth=([^%s}]+)")
                     if width and not (width:match("^%d+em$") or width:match("^%d+%.%d+em$")) then
                        fail("figure width must be expressed in em", node.line)
                     end
                     local size = width and ("width=" .. width .. ",") or ""
                     tex("\\par\\begingroup\\centering\\noindent\\begin{adjustbox}{" .. size .. "max width=\\linewidth}")
                  elseif class == "caption" then
                     if not parent or parent.layout ~= "figure" or parent.caption then fail("expected one caption in figure", node.line) end
                     parent.caption = true
                     tex("\\end{adjustbox}\\par")
                     node.visible = not slides
                  end
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
]], "@src/mark2tex/divs.tl"))(...)
end

package.preload["mark2tex.fileutils"] = function(...)
	return assert(load([[
local lfs = require("lfs")
local md5 = require("md5")

local fileutils = {}

local path_separator = package.config:sub(1, 1)

local function is_windows_absolute_path(path)
   return path:match("^%a:[/\\]") ~= nil
end

local function is_absolute_path(path)
   return path:sub(1, 1) == "/" or is_windows_absolute_path(path)
end

local function join_path(base, part)
   if base == "" then
      return part
   end
   return base .. path_separator .. part
end


function fileutils.read_file(path)
   local file = io.open(path, "r")
   if not file then
      return nil, "Unable to open file: " .. path
   end
   local content = file:read("*a")
   file:close()
   return content
end



function fileutils.save_file(path, content)
   local file = io.open(path, "w")
   if not file then
      return nil, "Unable to write file: " .. path
   end
   file:write(content)
   file:close()
   return true
end


function fileutils.create_directory(path)
   if path == nil or path == "" then
      return nil, "Unable to create directory: empty path"
   end

   local current = ""
   if is_absolute_path(path) then
      current = path:sub(1, 1)
   end

   for part in path:gmatch("[^/\\]+") do
      current = join_path(current, part)

      local mode = lfs.attributes(current, "mode")
      if mode == nil then
         local ok, err = lfs.mkdir(current)
         if not ok and lfs.attributes(current, "mode") ~= "directory" then
            return nil, "Unable to create directory '" .. current .. "': " .. tostring(err)
         end
      elseif mode ~= "directory" then
         return nil, "Unable to create directory '" .. current .. "': path exists and is not a directory"
      end
   end

   return true
end


function fileutils.get_output_filename(input_path, out_dir)
   local _, name_with_ext = string.match(input_path, "(.-)([^\\/]-%.?([^%.\\/]*))$")
   local name = name_with_ext:match("(.+)%..+$")
   local md5_hash = md5.sumhexa(input_path)
   return out_dir .. "/" .. (name or name_with_ext) .. "_" .. md5_hash .. ".tex"
end


function fileutils.getFirstLine(filePath)
   local file = io.open(filePath, "r")
   if file then
      local firstLine = file:read("*l")
      file:close()
      return firstLine
   end
   return nil
end

return fileutils
]], "@src/mark2tex/fileutils.tl"))(...)
end

package.preload["mark2tex.footnotes"] = function(...)
	return assert(load([[

local nodes = require("mark2tex.nodes")
local links = require("mark2tex.links")




















local footnotes = {}




local function literal(source)
   local result = {}
   for character in source:gmatch(".") do
      result[#result + 1] = nodes.literal(character)
   end
   return result
end

local function footnote_warning(kind, identifier)
   return { category = "footnote", kind = kind, identifier = identifier }
end


function footnotes.protect(
   source,
   resolve,
   parse_content,
   disabled)

   local prefix = "MARKTWOTEXFOOTNOTE"
   while source:find(prefix, 1, true) do prefix = prefix .. "X" end
   local output = {}
   local tokens = {}
   local warnings = {}
   local function add(node)
      local token = prefix .. tostring(#tokens + 1) .. "END"
      tokens[#tokens + 1] = { token = token, node = node }
      output[#output + 1] = token
   end
   local index = 1
   while index <= #source do
      local last = links.protected_end(source, index)
      local link = not last and links.match(source, index)
      local identifier, content
      local finish
      if not last and not link then
         identifier = source:match("^%[%^([^%[%]%s]+)%]", index)
         if identifier then finish = index + #identifier + 2 end
         if source:sub(index, index + 1) == "^[" then
            local cursor, depth = index + 2, 1
            while cursor <= #source do
               local protected = links.protected_end(source, cursor)
               local character = source:sub(cursor, cursor)
               if protected then cursor = protected + 1
               else
                  if character == "[" then depth = depth + 1 end
                  if character == "]" then depth = depth - 1 end
                  if depth == 0 then finish = cursor; break end
                  cursor = cursor + 1
               end
            end
            if finish then content = source:sub(index + 2, finish - 1) end
         end
      end
      if finish then
         local node
         local kind
         if disabled then kind = "nested-or-restricted"
         elseif identifier then
            node = resolve and resolve(identifier)
            if not node then kind = "undefined" end
         else
            local parsed, inner_warnings = parse_content(content)
            for _, warning in ipairs(inner_warnings) do warnings[#warnings + 1] = warning end
            local footnote = nodes.footnote(parsed)
            footnote.inline = true
            node = footnote
         end
         if not node then
            node = nodes.other(literal(source:sub(index, finish)))
            warnings[#warnings + 1] = footnote_warning(kind, identifier or "inline")
         end
         add(node)
         index = finish + 1
      elseif last or link then
         local ending = last or link.finish
         output[#output + 1], index = source:sub(index, ending), ending + 1
      elseif source:sub(index, index + 1) == "^[" then

         add(nodes.literal("^"))
         warnings[#warnings + 1] = footnote_warning("unclosed", "inline")
         index = index + 1
      elseif source:sub(index, index + 1) == "[^" then
         output[#output + 1] = "["
         add(nodes.literal("^"))
         warnings[#warnings + 1] = footnote_warning("unclosed", "reference")
         index = index + 2
      else
         output[#output + 1], index = source:sub(index, index), index + 1
      end
   end
   return table.concat(output), tokens, warnings
end

return footnotes
]], "@src/mark2tex/footnotes.tl"))(...)
end

package.preload["mark2tex.lecture"] = function(...)
	return assert(load([[







local lecture = {}

local function slide_paragraph()
   return { type = "slide_paragraph" }
end

local function slide_pause()
   return { type = "slide_pause" }
end

local function is_whitespace(node)
   if node.type == "other" then
      for _, inline in ipairs(node.content) do
         if not (inline.type == "text") or inline.content:find("%S") then return false end
      end
      return true
   end
   return false
end

function lecture.structure(ast, config)
   local output = { comments = ast.comments }
   local body = {}
   local title = nil
   local has_content, pending_pause = false, false

   local footer = nil
   local notes = {}
   local section_only = false
   local handout = config.profile == "handout"
   local function finish()
      if handout then
         if (title or has_content) and (footer or #notes > 0) then
            local annotations = { type = "lecture_annotations", footer = footer, notes = notes }
            output[#output + 1] = annotations
         end
      elseif title or has_content then
         local frame = { type = "slide_frame", content = body, title = title,
footer = footer, notes = notes, }
         output[#output + 1] = frame
      end
      body, title, footer, notes = {}, nil, nil, {}
      has_content, pending_pause, section_only = false, false, false
   end

   for _, node in ipairs(ast) do
      local h1 = false
      if not handout and node.type == "header" then
         h1 = not node.indented and node.level == 1
      end
      if h1 and config.h1 == "hide" then goto continue end
      if section_only and node.type ~= "slide_footer" and node.type ~= "slide_note" and
         not is_whitespace(node) then          finish() end
      if node.type == "slide_footer" then
         footer = footer or node.title
      elseif node.type == "slide_note" then
         notes[#notes + 1] = node.title
      elseif node.type == "header" and not node.indented and node.level <= config.slide_level then
         finish()
         title = node.content
         if handout then output[#output + 1] = node end
         section_only = node.level < config.slide_level and not (h1 and config.h1 == "frame")
      elseif node.type == "slide_break" then
         finish()
         if handout then output[#output + 1] = slide_paragraph() end
      elseif node.type == "slide_pause" then
         if handout then
            output[#output + 1] = slide_paragraph()
         else
            pending_pause = has_content
         end
      elseif not handout and config.standalone_learning_blocks and node.type == "latex" and
         node.content:match("^%s*\\begin%s*{Lernblock}") then
         finish()
         output[#output + 1] = node
      elseif handout then
         output[#output + 1] = node
         has_content = has_content or not is_whitespace(node)
      else
         if not is_whitespace(node) then
            if pending_pause then body[#body + 1] = slide_pause() end
            pending_pause, has_content = false, true
         end
         local block = node
         if node.type == "header" then
            local subheading = { type = "slide_subheading", content = node.content }
            block = subheading
         end
         body[#body + 1] = block
      end
      ::continue::
   end

   finish()
   return output
end

return lecture
]], "@src/mark2tex/lecture.tl"))(...)
end

package.preload["mark2tex.links"] = function(...)
	return assert(load([[

local autolinks = require("mark2tex.autolinks")
local delimiters = require("mark2tex.delimiters")
local nodes = require("mark2tex.nodes")
















local links = {}




local punctuation = "!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~"

local function unescape(value)
   return (value:gsub("\\(.)", function(character)
      return punctuation:find(character, 1, true) and character or "\\" .. character
   end))
end


local function protected_end(source, position)
   local character = source:sub(position, position)
   if character == "`" and not delimiters.is_escaped(source, position) then
      local delimiter = source:match("^`+", position)
      local last = source:find(delimiter, position + #delimiter, true)
      return last and last + #delimiter - 1 or #source
   end
   local delimiter, finish
   if character == "$" and not delimiters.is_escaped(source, position) then
      delimiter = source:sub(position, position + 1) == "$$" and "$$" or "$"
      finish = delimiter
   elseif source:sub(position, position + 1) == "\\(" then
      delimiter, finish = "\\(", "\\)"
   elseif source:sub(position, position + 1) == "\\[" then
      delimiter, finish = "\\[", "\\]"
   end
   if delimiter then
      local last = delimiters.find_unescaped(source, finish, position + #delimiter)
      if last then return last + #finish - 1 end
   end
   if character == "\\" then
      local command = source:match("^\\[%a@]+%*?", position)
      if command then
         local index = position + #command
         while source:sub(index, index) == "{" or source:sub(index, index) == "[" do
            local stack = { source:sub(index, index) == "{" and "}" or "]" }
            index = index + 1
            while #stack > 0 and index <= #source do
               local c = source:sub(index, index)
               if c == "\\" then index = index + 1
               elseif c == "{" or c == "[" then stack[#stack + 1] = c == "{" and "}" or "]"
               elseif c == stack[#stack] then table.remove(stack) end
               index = index + 1
            end
         end
         return index - 1
      end
      if punctuation:find(source:sub(position + 1, position + 1), 1, true) then
         return position + 1
      end
   end
   return nil
end

local function spaces(source, index)
   local start, lines = index, 0
   while source:sub(index, index):match("[ \t\r\n]") do
      if source:sub(index, index) == "\n" then lines = lines + 1 end
      index = index + 1
   end
   if lines > 1 then return nil end
   return index, index > start
end



local function malformed_end(source, position)
   if source:sub(position, position) ~= "[" then return nil end
   local label_end = source:find("](", position + 1, true)
   if not label_end or source:sub(position, label_end):find("\n") then return nil end
   local finish = source:find(")", label_end + 2, true)
   local newline = source:find("\n", label_end + 2, true)
   if finish and (not newline or finish < newline) then return finish end
   local space = source:find("[ \t\r\n]", label_end + 2)
   return space and space - 1 or #source
end

local function suffix(source, start)
   local index = spaces(source, start)
   if not index then return nil end
   local first, last = index, index - 1
   if source:sub(index, index) == "<" then
      first, index = index + 1, index + 1
      while index <= #source do
         local c = source:sub(index, index)
         if c == "\\" and punctuation:find(source:sub(index + 1, index + 1), 1, true) then
            index = index + 2
         elseif c == ">" then break
         elseif c == "<" or c == "\n" or c == "\r" then return nil
         else index = index + 1 end
      end
      if source:sub(index, index) ~= ">" then return nil end
      last, index = index - 1, index + 1
   else
      local depth = 0
      while index <= #source do
         local c = source:sub(index, index)
         if c == "\\" and punctuation:find(source:sub(index + 1, index + 1), 1, true) then
            index = index + 2
         elseif c == "(" then
            depth, index = depth + 1, index + 1
            if depth > 128 then return nil end
         elseif c == ")" and depth > 0 then depth, index = depth - 1, index + 1
         elseif c == ")" or c:match("[%z\1-\32\127]") then break
         elseif c == "<" or c == ">" then return nil
         else index = index + 1 end
      end
      if depth ~= 0 then return nil end
      last = index - 1
   end
   local destination = unescape(source:sub(first, last))
   local separated
   index, separated = spaces(source, index)
   if not index then return nil end
   local title
   local quote = source:sub(index, index)
   if separated and (quote == '"' or quote == "'" or quote == "(") then
      local finish = quote == "(" and ")" or quote
      local title_start = index + 1
      index = title_start
      while index <= #source do
         local c = source:sub(index, index)
         if c == "\\" and punctuation:find(source:sub(index + 1, index + 1), 1, true) then index = index + 2
         elseif c == finish then break
         elseif quote == "(" and c == "(" then return nil
         else index = index + 1 end
      end
      if source:sub(index, index) ~= finish then return nil end
      local raw = source:sub(title_start, index - 1)
      if raw:find("\n[ \t\r]*\n") then return nil end
      title = unescape(raw)
      index = spaces(source, index + 1)
   end
   if not index or source:sub(index, index) ~= ")" then return nil end
   return { destination = destination, title = title, finish = index }
end

function links.match(source, position)
   if source:sub(position, position) == "<" then
      return autolinks.match(source, position)
   end
   if source:sub(position, position) ~= "[" then return nil end
   local index, depth = position + 1, 1
   while index <= #source do
      local c = source:sub(index, index)
      local last = protected_end(source, index)
      if last then index = last + 1
      elseif c == "[" then
         depth, index = depth + 1, index + 1
         if depth > 128 then return nil end
      elseif c == "]" then
         depth = depth - 1
         if depth == 0 then break end
         index = index + 1
      else index = index + 1 end
   end
   if depth ~= 0 or source:sub(index + 1, index + 1) ~= "(" then return nil end
   local result = suffix(source, index + 2)
   if not result then return nil end
   result.label, result.kind, result.label_end = source:sub(position + 1, index - 1), "inline", index
   return result
end


function links.protect(source, parse_label, options)
   options = options or {}
   local prefix = "MARKTWOTEXLINK"
   while source:find(prefix, 1, true) do prefix = prefix .. "X" end
   local tokens = {}
   local output = {}
   local warnings = {}
   local index = 1
   local function add(node)
      local token = prefix .. tostring(#tokens + 1) .. "END"
      tokens[#tokens + 1] = { token = token, node = node }
      output[#output + 1] = token
   end
   while index <= #source do
      local last = protected_end(source, index)
      local match = not last and links.match(source, index)
      local malformed = not last and not match and malformed_end(source, index)
      if match then
         local image = index > 1 and source:sub(index - 1, index - 1) == "!" and not delimiters.is_escaped(source, index - 1)
         if image or options.disable_links then
            add(nodes.text(source:sub(index, match.finish)))
         else
            local content = { nodes.text(match.label) }
            if match.kind == "inline" then
               local label_warnings
               content, label_warnings = parse_label(match.label)
               for _, warning in ipairs(label_warnings) do warnings[#warnings + 1] = warning end
            end
            add(nodes.link(match.destination, content, match.title, match.kind))
         end
         index = match.finish + 1
      elseif malformed then
         add(nodes.text(source:sub(index, malformed)))
         index = malformed + 1
      elseif options.link_label and not (last and source:sub(index, index + 1) == "\\(") and source:sub(index, index) == "\\" and punctuation:find(source:sub(index + 1, index + 1), 1, true) then
         add(nodes.literal(source:sub(index + 1, index + 1)))
         index = index + 2
      elseif last then
         output[#output + 1] = source:sub(index, last)
         index = last + 1
      else
         output[#output + 1] = source:sub(index, index)
         index = index + 1
      end
   end
   return table.concat(output), tokens, warnings
end



function links.expand(ast, tokens)
   local result = {}
   for _, node in ipairs(ast) do
      if node.type == "text" then
         local content = node.content
         local position = 1
         while position <= #content do
            local first, last
            local replacement
            for _, token in ipairs(tokens) do
               local start, finish = content:find(token.token, position, true)
               if start and (not first or start < first) then first, last, replacement = start, finish, token.node end
            end
            if not first then result[#result + 1] = nodes.text(content:sub(position)); break end
            if first > position then result[#result + 1] = nodes.text(content:sub(position, first - 1)) end
            result[#result + 1], position = replacement, last + 1
         end
      else
         if node.type == "bold" or node.type == "italic" or node.type == "strikethrough" or
            node.type == "link" or node.type == "other" then
            node.content = links.expand(node.content, tokens)
         end
         result[#result + 1] = node
      end
   end
   return result
end


function links.mask_destinations(source)
   local output = {}
   local index = 1
   while index <= #source do
      local last = protected_end(source, index)
      local match = not last and links.match(source, index)
      if match then
         output[#output + 1] = source:sub(index, match.label_end)
         output[#output + 1] = source:sub(match.label_end + 1, match.finish):gsub("[^\r\n]", " ")
         index = match.finish + 1
      elseif last then output[#output + 1], index = source:sub(index, last), last + 1
      else output[#output + 1], index = source:sub(index, index), index + 1 end
   end
   return table.concat(output)
end



function links.tex_destination(value)
   local output = {}
   local start = 1
   for index = 1, #value do
      local c = value:sub(index, index)
      if c:find("[%%#{}\\%^]") then
         if index > start then output[#output + 1] = "\\detokenize{" .. value:sub(start, index - 1) .. "}" end
         output[#output + 1] = (c == "%" or c == "#") and "\\" .. c or "\\Uchar" .. c:byte() .. " "
         start = index + 1
      end
   end
   if start <= #value then output[#output + 1] = "\\detokenize{" .. value:sub(start) .. "}" end
   return table.concat(output)
end


links.protected_end = protected_end

return links
]], "@src/mark2tex/links.tl"))(...)
end

package.preload["mark2tex.math"] = function(...)
	return assert(load([[
local delimiters = require("mark2tex.delimiters")
local nodes = require("mark2tex.nodes")

























local math_parser = {}







local TOKEN_START = string.char(30) .. "M"
local TOKEN_END = string.char(31)

local function token(index)
   return TOKEN_START .. tostring(index) .. TOKEN_END
end

local function add_token(tokens, node)
   tokens[#tokens + 1] = node
   return token(#tokens)
end

local function warn(warnings, kind, delimiter)
   warnings[#warnings + 1] = {
      category = "math-delimiter",
      kind = kind,
      delimiter = delimiter,
   }
end




function math_parser.protect_inlines(input, options)
   options = options or {}
   local allow_display = options.allow_display ~= false
   local tokens = {}
   local warnings = {}
   local output = {}
   local index = 1
   local in_code = false

   while index <= #input do
      local character = input:sub(index, index)

      if character == "`" and not delimiters.is_escaped(input, index) then
         in_code = not in_code
         output[#output + 1] = character
         index = index + 1
      elseif in_code then
         output[#output + 1] = character
         index = index + 1
      elseif input:sub(index, index + 1) == "\\(" and not delimiters.is_escaped(input, index) then
         local closing = delimiters.find_unescaped(input, "\\)", index + 2)
         if closing and closing > index + 2 then
            output[#output + 1] = add_token(tokens, nodes.inline_math(input:sub(index, closing + 1)))
            index = closing + 2
         else
            warn(warnings, closing and "empty" or "unclosed", "\\(")
            local ending = closing and closing + 1 or index + 1
            output[#output + 1] = add_token(tokens, nodes.text(input:sub(index, ending)))
            index = ending + 1
         end
      elseif input:sub(index, index + 1) == "\\[" and not delimiters.is_escaped(input, index) then
         local closing = delimiters.find_unescaped(input, "\\]", index + 2)
         if closing and closing > index + 2 and allow_display then
            output[#output + 1] = add_token(tokens, nodes.display_math(input:sub(index + 2, closing - 1)))
            index = closing + 2
         elseif closing and closing > index + 2 then
            warn(warnings, "display-in-table", "\\[")
            output[#output + 1] = add_token(tokens, nodes.text(input:sub(index, closing + 1)))
            index = closing + 2
         else
            warn(warnings, closing and "empty" or "unclosed", "\\[")
            local ending = closing and closing + 1 or index + 1
            output[#output + 1] = add_token(tokens, nodes.text(input:sub(index, ending)))
            index = ending + 1
         end
      elseif input:sub(index, index + 1) == "$$" and not delimiters.is_escaped(input, index) then
         local closing = delimiters.find_unescaped(input, "$$", index + 2)
         if closing and closing > index + 2 and allow_display then
            output[#output + 1] = add_token(tokens, nodes.display_math(input:sub(index + 2, closing - 1)))
            index = closing + 2
         elseif closing and closing > index + 2 then
            warn(warnings, "display-in-table", "$$")
            output[#output + 1] = add_token(tokens, nodes.text(input:sub(index, closing + 1)))
            index = closing + 2
         else
            warn(warnings, closing and "empty" or "unclosed", "$$")
            local ending = closing and closing + 1 or index + 1
            output[#output + 1] = add_token(tokens, nodes.text(input:sub(index, ending)))
            index = ending + 1
         end
      elseif character == "$" and not delimiters.is_escaped(input, index) then
         local closing = delimiters.find_unescaped(input, "$", index + 1)
         while closing and input:sub(closing, closing + 1) == "$$" do
            closing = delimiters.find_unescaped(input, "$", closing + 2)
         end
         if closing and closing > index + 1 then
            output[#output + 1] = add_token(tokens, nodes.inline_math(input:sub(index, closing)))
            index = closing + 1
         else
            warn(warnings, closing and "empty" or "unclosed", "$")
            local ending = closing or index
            output[#output + 1] = add_token(tokens, nodes.text(input:sub(index, ending)))
            index = ending + 1
         end
      else
         output[#output + 1] = character
         index = index + 1
      end
   end

   return table.concat(output), tokens, warnings
end

local function copy_with_content(node, content)

   local copy = {}
   for key, value in pairs(node) do
      copy[key] = value
   end
   copy.content = content
   return copy
end



local function expand_node(node, tokens)
   local content = nodes.content(node)
   if type(content) == "string" then
      local result = {}
      local position = 1
      while true do
         local first, last, number = content:find(TOKEN_START .. "(%d+)" .. TOKEN_END, position)
         if not first then
            if position <= #content then
               result[#result + 1] = copy_with_content(node, content:sub(position))
            end
            break
         end
         if first > position then
            result[#result + 1] = copy_with_content(node, content:sub(position, first - 1))
         end
         result[#result + 1] = tokens[tonumber(number)]
         position = last + 1
      end
      return result
   end
   if node.type == "bold" or node.type == "italic" or node.type == "strikethrough" or
      node.type == "link" or node.type == "other" then
      node.content = math_parser.expand_tokens(node.content, tokens)
   end
   return { node }
end

function math_parser.expand_tokens(ast, tokens)
   local expanded = {}
   for _, node in ipairs(ast) do
      local replacement = expand_node(node, tokens)
      for _, value in ipairs(replacement) do
         expanded[#expanded + 1] = value
      end
   end
   return expanded
end

return math_parser
]], "@src/mark2tex/math.tl"))(...)
end

package.preload["mark2tex.nodes"] = function(...)
	return assert(load([[



























































































































































































































































local nodes = {}





















































function nodes.content(node)
   if node.type == "footnote" and node.blocks then
      return node.blocks
   end
   return (node).content
end





function nodes.footnote(content, label, repeated)
   return { type = "footnote", content = content, label = label, repeated = repeated }
end


function nodes.footnote_blocks(blocks, label)
   return { type = "footnote", blocks = blocks, label = label }
end

function nodes.footnote_definition(identifier, content)
   return { type = "footnote_definition", identifier = identifier, content = content }
end

function nodes.link(destination, content, title, kind)
   return { type = "link", destination = destination, content = content, title = title, kind = kind or "inline" }
end

function nodes.header(level, content)
   return { type = "header", level = level, content = content }
end

function nodes.horizontal_rule()
   return { type = "horizontal_rule" }
end

function nodes.latex(content)
   return { type = "latex", content = content }
end

function nodes.item(level, content)
   return { type = "item", level = level, content = content }
end

function nodes.enum(level, content, style, start)
   return { type = "enum", level = level, content = content, style = style, start = start }
end

function nodes.code(code_type, content)
   return { type = "code", code_type = code_type, content = content }
end

function nodes.blockquote(content)
   return { type = "blockquote", content = content }
end

function nodes.table(headers, alignments, rows)
   return { type = "table", headers = headers, alignments = alignments, rows = rows }
end


function nodes.raw_other(content)
   return { type = "other", content = content }
end

function nodes.other(content)
   return { type = "other", content = content }
end

function nodes.paren_citation(content, locator)
   return { type = "paren_citation", content = content, locator = locator }
end

function nodes.citation(content)
   return { type = "citation", content = content }
end

function nodes.verbatim(content)
   return { type = "verbatim", content = content }
end

function nodes.inline_math(content)
   return { type = "inline_math", content = content }
end

function nodes.display_math(content)
   return { type = "display_math", content = content }
end

function nodes.latex_cmd(content)
   return { type = "latex_cmd", content = content }
end

function nodes.italic(content)
   return { type = "italic", content = content }
end

function nodes.bold(content)
   return { type = "bold", content = content }
end

function nodes.strikethrough(content)
   return { type = "strikethrough", content = content }
end

function nodes.text(content)
   return { type = "text", content = content }
end

function nodes.literal(content)
   return { type = "literal", content = content }
end

return nodes
]], "@src/mark2tex/nodes.tl"))(...)
end

package.preload["mark2tex.parse"] = function(...)
	return assert(load([[
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
      return nodes.footnote_blocks(add_inline_nodes(blocks, warnings, context, true), label)
   end
   local inline_ast = add_inline_nodes(block_ast, warnings, context)
   inline_ast.warnings = warnings
   inline_ast.comments = comment_tokens
   return inline_ast
end

return parse
]], "@src/mark2tex/parse.tl"))(...)
end

package.preload["mark2tex.parse_blocks"] = function(...)
	return assert(load([[
local lpeg = require("lpeg")
local nodes = require("mark2tex.nodes")
local links = require("mark2tex.links")





local P, S, R, C, Ct, V = lpeg.P, lpeg.S, lpeg.R, lpeg.C, lpeg.Ct, lpeg.V

local space = P(" ") ^ 1
local hash = P("#")
local newline = P("\n")
local rest_of_line = (P(1) - newline) ^ 1
local horizontal_space = S(" \t") ^ 0
local line_end = #newline + -P(1)

local Cp, Cmt = lpeg.Cp, lpeg.Cmt
local colons = P(":") ^ 3
local name = (R("az", "AZ", "09") + S("_-")) ^ 1
local attributes = C(P("{") * (P(1) - S("}\n")) ^ 1 * P("}") + name)
local fence_body = horizontal_space * Cp() * C(colons) *
horizontal_space * (attributes + C(P(""))) * horizontal_space * line_end
local fence = newline * fence_body

local grammar = {}


local footnote_indent = P("    ") + P("\t")
local footnote_continuation = newline * (horizontal_space * newline) ^ 0 *
-fence_body * footnote_indent * (P(1) - newline) ^ 0
grammar.footnote_definition = newline * P(" ") ^ (-3) * P("[^") *
C((P(1) - S("[] \t\r\n")) ^ 1) * P("]:") *
C((P(1) - newline) ^ 0 * footnote_continuation ^ 0) /
function(identifier, content)
   content = content:gsub("\n    ", "\n"):gsub("\n\t", "\n")
   return nodes.footnote_definition(identifier, content:match("^%s*(.-)%s*$"))
end





grammar.header = newline *
space ^ 0 *
Ct(C(hash ^ 1) * space * C((P(1) - newline) ^ 1)) /
function(t)
   return nodes.header(#t[1], t[2])
end







grammar.horizontal_rule = newline *
horizontal_space *
P("-") ^ 3 *
horizontal_space *
line_end /
nodes.horizontal_rule





local begin_env = P("\\begin{") *
(P(1) - P("}")) ^ 1 *
P("}")

local end_env = P("\\end{") *
(P(1) - P("}")) ^ 1 *
P("}")

grammar.begin_end = begin_env * (V("begin_end_inner") + (1 - begin_env - end_env)) ^ 0 * end_env
grammar.begin_end_inner = V("begin_end") + (1 - (begin_env + end_env)) ^ 1

grammar.latex_env = newline *
space ^ 0 *
V("begin_end") /
function(t)
   return nodes.latex(t)
end





local standalone_display_environments = {
   align = true,
   ["align*"] = true,
   alignat = true,
   ["alignat*"] = true,
   displaymath = true,
   equation = true,
   ["equation*"] = true,
   eqnarray = true,
   ["eqnarray*"] = true,
   flalign = true,
   ["flalign*"] = true,
   gather = true,
   ["gather*"] = true,
   multline = true,
   ["multline*"] = true,
}

local function display_node(content)
   local environment, closing = content:match("^%s*\\begin{([^}]+)}.*\\end{([^}]+)}%s*$")
   if environment == closing and standalone_display_environments[environment] then
      return nodes.latex(content:match("^%s*(.-)%s*$"))
   end
   return nodes.display_math(content)
end

grammar.display_math_dollar = P("$$") *
C((P(1) - P("$$")) ^ 1) *
P("$$") /
display_node

grammar.display_math_bracket = P("\\[") *
C((P(1) - P("\\]")) ^ 1) *
P("\\]") /
display_node

grammar.display_math = newline *
space ^ 0 *
(V("display_math_dollar") + V("display_math_bracket"))





local start_of_item = newline * C(S(" \t") ^ 0) * S("-*+") * space
local decimal_marker = R("09") ^ 1 * S(".)")
local alpha_marker = R("az") * P(")") * #S(" \t")
local continuation_list_marker = fence_body + S("-*+") * space + decimal_marker + alpha_marker + P("#") * space
local follow_item_line = newline ^ 1 * S(" \t") ^ 1 * (P(1) - continuation_list_marker) * rest_of_line ^ (-1)

grammar.item = Ct(start_of_item * C(rest_of_line * follow_item_line ^ 0)) /
function(t)
   return nodes.item(#t[1], t[2])
end





local start_of_enum = newline * C(horizontal_space) * C(decimal_marker + alpha_marker)
local follow_enum_line = newline ^ 1 * S(" \t") ^ 1 * (P(1) - continuation_list_marker) * rest_of_line ^ (-1)

grammar.enum = Ct(start_of_enum * C(rest_of_line * follow_enum_line ^ 0)) /
function(t)
   local marker = t[2]:sub(1, -2)
   local start = tonumber(marker)
   if start then

      return nodes.enum(#t[1], t[3], "decimal", (start <= 2147483647 and start or 1))
   end
   return nodes.enum(#t[1], t[3]:gsub("^\t+", " "), "alpha", marker:byte() - string.byte("a") + 1)
end





grammar.code = newline *
P("`") ^ 3 *
C(rest_of_line ^ (-1)) *
newline *
C((P(1) - P("`") ^ 3) ^ 1) *
P("`") ^ 3 /
function(code_type, content)
   if code_type == "tex" then
      return nodes.latex(content)
   end
   return nodes.code(code_type, content)
end





local quote_line = newline * P(">") * P(" ") ^ (-1) * C(rest_of_line ^ (-1))

grammar.blockquote = Ct(quote_line * quote_line ^ 0) /
function(lines)
   return nodes.blockquote(table.concat(lines, "\n"))
end





local function trim(value)
   return value:match("^%s*(.-)%s*$")
end

local function split_table_row(line)
   line = trim(line)
   if line:sub(1, 1) == "|" then
      line = line:sub(2)
   end
   if line:sub(-1) == "|" then
      line = line:sub(1, -2)
   end

   local cells = {}
   local cell_start = 1
   local in_math = false
   local scanned = links.mask_destinations(line)
   local in_code = false

   for index = 1, #line do
      local character = scanned:sub(index, index)
      local previous = index > 1 and line:sub(index - 1, index - 1) or ""

      if character == "`" and previous ~= "\\" and not in_math then
         in_code = not in_code
      elseif character == "$" and previous ~= "\\" and not in_code then
         in_math = not in_math
      elseif character == "|" and previous ~= "\\" and not in_math and not in_code then
         table.insert(cells, trim(line:sub(cell_start, index - 1)))
         cell_start = index + 1
      end
   end

   table.insert(cells, trim(line:sub(cell_start)))
   return cells
end

local function table_alignment(separator)
   if separator:match("^:.*:$") then
      return "c"
   elseif separator:match(":$") then
      return "r"
   end
   return "l"
end

local table_line = C(#((P(1) - newline - P("|")) ^ 0 * P("|")) * (P(1) - newline) ^ 1)
local separator_cell = horizontal_space * P(":") ^ (-1) * P("-") ^ 3 * P("-") ^ 0 * P(":") ^ (-1) * horizontal_space
local separator_line = C(horizontal_space * P("|") ^ (-1) * separator_cell * (P("|") * separator_cell) ^ 1 * P("|") ^ (-1) * horizontal_space)

grammar.table = newline *
table_line *
newline *
separator_line *
(newline * table_line) ^ 0 /
function(header_line, separator, ...)
   local rows = {}
   local alignments = {}
   for _, cell in ipairs(split_table_row(separator)) do
      table.insert(alignments, table_alignment(cell))
   end
   for index, row in ipairs({ ... }) do
      rows[index] = split_table_row(row)
   end
   return nodes.table(split_table_row(header_line), alignments, rows)
end





grammar.div_fence = (fence * Cp()) / function(position, delimiter, attributes_text, ending)
   return { type = "div_fence", position = position, ending = ending,
length = #delimiter, attributes = attributes_text, }
end


local image_path = C((P(1) - S("(){}%#\\\n")) ^ 1)
local em_width = R("09") ^ 1 * (P(".") * R("09") ^ 1) ^ (-1) * P("em")
grammar.image = newline * horizontal_space * P("![") * (P(1) - S("]\n")) ^ 0 *
P("](") * image_path * P(")") * (P("{width=") * C(em_width) * P("}") + C(P(""))) *
horizontal_space * line_end / function(path, width)
   return { type = "image", path = path, width = width }
end




grammar.outer_elements = V("image") + V("footnote_definition") + V("table") + V("horizontal_rule") + V("header") + V("code") + V("display_math") + V("latex_env") + V("blockquote") + V("item") + V("enum")

grammar.other = C((P(1) - V("outer_elements")) ^ 1) / function(t)
   return nodes.raw_other(t)
end





grammar.outer = Ct((V("outer_elements") + V("other")) ^ 0)
grammar[1] = V("outer")

local lecture = {}
for key, pattern in pairs(grammar) do
   lecture[key] = pattern
end

local end_of_paragraph = #(newline * horizontal_space * (newline + -P(1)) + fence + -P(1))
local function standalone(pattern)
   return Cmt(Cp() * newline * pattern * horizontal_space * end_of_paragraph,
   function(subject, ending, start, node)
      local previous = start - 1
      while previous > 0 and subject:sub(previous, previous):match("[ \t\r]") do
         previous = previous - 1
      end
      local before = subject:sub(1, start - 1):match("([^\n]*)$")
      if previous == 0 or subject:sub(previous, previous) == "\n" or
         lpeg.match(fence, "\n" .. before) then
         return ending, node
      end
   end)
end

lecture.header = newline * C(P(" ") ^ 0) * C(hash ^ 1) * space * C(rest_of_line) /
function(indent, hashes, content)
   local heading = nodes.header(#hashes, content)
   heading.indented = indent ~= ""
   return heading
end
lecture.slide_break = standalone(P("-") ^ 3 / function() return { type = "slide_break" } end)
lecture.slide_pause = standalone(P(". . .") / function() return { type = "slide_pause" } end)
local nested_grammar = P(grammar) * -1
grammar.outer_elements = V("div_fence") + grammar.outer_elements
lecture.outer_elements = V("slide_break") + V("slide_pause") + grammar.outer_elements

local classic_grammar = P(grammar) * -1
local lecture_grammar = P(lecture) * -1

local function parse_blocks(str, lecture_profile, nested)
   if nested then return nested_grammar:match(str) end
   if lecture_profile then
      return lecture_grammar:match(str)
   end
   return classic_grammar:match(str)
end

return parse_blocks
]], "@src/mark2tex/parse_blocks.tl"))(...)
end

package.preload["mark2tex.parse_inlines"] = function(...)
	return assert(load([[
local lpeg = require("lpeg")
local nodes = require("mark2tex.nodes")
local math_parser = require("mark2tex.math")
local links = require("mark2tex.links")
local footnotes = require("mark2tex.footnotes")













local P, S, C, Ct, V = lpeg.P, lpeg.S, lpeg.C, lpeg.Ct, lpeg.V

local newline = P("\n")
local escape = S("@$`*\\") + P("[@") + P("_") + P("~~")

local grammar = {}





grammar.cite = C(P(P(1) - S("\n;,] ")) ^ 1)
grammar.cite2 = C(P(P(1) - S("\n;, .] ")) ^ 1)
grammar.citation_start = P("[@") + P("[\n@")
grammar.citation_break = ((S(",; ") ^ 0 * newline) + S(",; ") ^ 1) * newline ^ 0 * P("@")
grammar.citation_locator = P(",") * S(" ") ^ 0 * C((P(1) - S("\n]")) ^ 1)

grammar.paren_citation = V("citation_start") *
Ct(V("cite") * (V("citation_break") * V("cite")) ^ 0) *
V("citation_locator") ^ (-1) *
S(";, ") ^ 0 *
newline ^ 0 *
P("]") /
function(citations, locator)
   return nodes.paren_citation(citations, locator)
end

grammar.citation = P("@") * V("cite2") / function(t)
   return nodes.citation(t)
end





grammar.verbatim = P("`") *
C((P(1) - P("`")) ^ 1) *
P("`") /
function(t)
   return nodes.verbatim(t)
end









grammar.latex_cmd_in_verbatim = P("`") *
C(P("\\") * (1 - S("{[ `")) ^ 1 * (V("brace_group") + V("bracket_group")) ^ 0) *
P("`") /
function(t)
   return nodes.latex_cmd(t)
end

grammar.brace_group = P("{") * (V("brace_group") + V("bracket_group") + (P(1) - S("{}[]"))) ^ 0 * P("}")
grammar.bracket_group = P("[") * (V("brace_group") + V("bracket_group") + (P(1) - S("{}[]"))) ^ 0 * P("]")

grammar.latex_cmd = C(P("\\") * (1 - S("{[ ")) ^ 1 * (V("brace_group") + V("bracket_group")) ^ 0) /
function(t)
   return nodes.latex_cmd(t)
end





grammar.italic_star = P("*") *
Ct((V("final_elements") + V("bold") + V("text")) ^ 1) *
P("*") /
function(t)
   return nodes.italic(t)
end

grammar.italic_underline = P("_") *
Ct((V("final_elements") + V("bold") + V("strikethrough") + V("text")) ^ 1) *
P("_") /
function(t)
   return nodes.italic(t)
end

grammar.italic = V("italic_star") + V("italic_underline")

grammar.bold_star = P("**") *
Ct((V("final_elements") + V("italic") + V("strikethrough") + V("text")) ^ 1) *
P("**") /
function(t)
   return nodes.bold(t)
end

grammar.bold_underline = P("__") *
Ct((V("final_elements") + V("italic") + V("text")) ^ 1) *
P("__") /
function(t)
   return nodes.bold(t)
end

grammar.bold = V("bold_star") + V("bold_underline")

grammar.strikethrough = P("~~") *
Ct((V("final_elements") + V("italic") + V("bold") + V("text")) ^ 1) *
P("~~") /
function(t)
   return nodes.strikethrough(t)
end





grammar.text = C((P(1) - escape) ^ 1) / function(t)
   return nodes.text(t)
end





grammar.final_elements = V("paren_citation") + V("citation") + V("latex_cmd_in_verbatim") + V("verbatim") + V("latex_cmd")
grammar.elements = V("final_elements") + V("italic") + V("bold") + V("strikethrough")

grammar[1] = Ct((V("elements") + V("text")) ^ 0)
local inline_pattern = P(grammar) * -1

local function parse_inlines(str, options)
   options = options or {}
   local footnote_protected, footnote_tokens, footnote_warnings = footnotes.protect(str, options.resolve_footnote, function(content)
      return parse_inlines(content, { disable_footnotes = true })
   end, options.disable_footnotes)
   local link_protected, link_tokens, link_warnings = links.protect(footnote_protected, function(label)
      return parse_inlines(label, { allow_display = false, disable_links = true, link_label = true, disable_footnotes = true })
   end, { disable_links = options.disable_links, link_label = options.link_label })
   local protected, tokens, math_warnings = math_parser.protect_inlines(link_protected, { allow_display = options.allow_display })
   local warnings = {}
   for _, warning in ipairs(math_warnings) do warnings[#warnings + 1] = warning end
   for _, warning in ipairs(link_warnings) do warnings[#warnings + 1] = warning end
   for _, warning in ipairs(footnote_warnings) do warnings[#warnings + 1] = warning end
   local parsed = inline_pattern:match(protected)
   if parsed == nil then
      parsed = { nodes.text(protected) }
   end
   return links.expand(links.expand(math_parser.expand_tokens(parsed, tokens), link_tokens), footnote_tokens), warnings
end

return parse_inlines
]], "@src/mark2tex/parse_inlines.tl"))(...)
end

package.preload["mark2tex.write"] = function(...)
	return assert(load([[



















local comments = require("mark2tex.comments")
local links = require("mark2tex.links")
local nodes = require("mark2tex.nodes")














local function list_style(ast)
   if ast.type == "enum" then
      return ast.style or "decimal"
   end
   return "decimal"
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
   table.insert(stack, { type = ast.type, level = ast.level, style = list_style(ast) })
   out[1] = out[1] .. "\n\\begin{" .. list_environment(ast.type) .. "}"
   if ast.type == "enum" then
      local counter = "\\csname @enumctr\\endcsname"
      if ast.style == "alpha" then

         out[1] = out[1] .. "\n\\expandafter\\edef\\csname the" .. counter .. "\\endcsname{" ..
         "\\expandafter\\noexpand\\csname int_to_alph:n\\endcsname" ..
         "{\\noexpand\\value{" .. counter .. "}}}" ..
         "\n\\expandafter\\def\\csname @itemlabel\\endcsname{" ..
         "\\csname the" .. counter .. "\\endcsname)}"
      end
      if ast.start and ast.start ~= 1 then
         out[1] = out[1] .. "\n\\setcounter{" .. counter .. "}{" .. tostring(ast.start - 1) .. "}"
      end
   end
end

local function ensure_list_environment(out, stack, ast)
   close_lists_until(out, stack, ast.level)

   local style = list_style(ast)
   if #stack > 0 and stack[#stack].level == ast.level and
      (stack[#stack].type ~= ast.type or stack[#stack].style ~= style) then
      close_list(out, stack)
   end

   if #stack == 0 or stack[#stack].level < ast.level or stack[#stack].type ~= ast.type then
      open_list(out, stack, ast)
   end
end




local function cell_length(value)
   if type(value) == "string" then
      local _, count = value:gsub("[^\128-\191]", "")
      return count
   end
   local length = 0
   for _, child in ipairs(value) do
      if type(child) == "string" then
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

local function table_columns(ast)
   local count = #ast.alignments
   local lengths = {}
   local compact = {}
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


         local fraction = math.min(0.5 / count, 0.04 + lengths[index] * 0.008)
         column = string.format("p{\\dimexpr %.4f\\linewidth - %.4f\\tabcolsep\\relax}",
         fraction, fraction * 2 * (count - 1))
      end
      columns[index] = ">{\\" .. alignment[align] .. "\\arraybackslash}" .. column
   end
   return "@{}" .. table.concat(columns) .. "@{}"
end

local write_blocks



local function write_text(text)
   return (text:gsub("&", "\\&"))
end



local function write_inline_code(text)
   local escapes = {
      ["\\"] = "\\textbackslash{}",
      ["^"] = "\\textasciicircum{}",
      ["~"] = "\\textasciitilde{}",
   }
   return (text:gsub("[\\%%{}#&_$^~]", function(character)
      return escapes[character] or "\\" .. character
   end))
end


local function write_annotation(text)
   return write_inline_code((text:gsub("%s+", " ")))
end

local function has_verbatim(blocks)
   for _, node in ipairs(blocks) do
      if node.type == "code" or
         (node.type == "latex" and node.content:find("\\begin{verbatim", 1, true)) or
         (node.type == "blockquote" and has_verbatim(node.content)) then
         return true
      end
   end
   return false
end

local walk

local function walk_nodes(list, out, config)
   for _, node in ipairs(list) do
      walk(node, out, config)
   end
end

walk = function(ast, out, config)
   if ast.type == "header" then
      out[1] = out[1] .. "\n\\"
      if ast.level > #config.header then
         ast.level = #config.header
      end
      out[1] = out[1] .. config.header[ast.level]

      out[1] = out[1] .. "{"
      walk_nodes(ast.content, out, config)
      out[1] = out[1] .. "}"
   elseif ast.type == "slide_frame" then
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
         local notes = {}
         for _, note in ipairs(ast.notes) do
            notes[#notes + 1] = write_annotation(note)
         end
         out[1] = out[1] .. "\\note{" .. table.concat(notes, "\\par ") .. "}\n"
      end
      out[1] = out[1] .. write_blocks(ast.content, config, true) .. "\n\\end{frame}\n"
   elseif ast.type == "slide_pause" then
      out[1] = out[1] .. "\n\\par\\pause\n"
   elseif ast.type == "slide_subheading" then
      out[1] = out[1] .. "\n\\par\\medskip\\noindent\\textbf{"
      walk_nodes(ast.content, out, config)
      out[1] = out[1] .. "}\\par\n"
   elseif ast.type == "lecture_annotations" then
      if ast.footer then
         out[1] = out[1] .. "\n\\par\\noindent{\\small " .. write_annotation(ast.footer) .. "}\\par\n"
      end
      for _, note in ipairs(ast.notes) do
         out[1] = out[1] .. "\n\\par\\noindent\\textbf{Vortragsnotiz:} " ..
         write_annotation(note) .. "\\par\n"
      end
   elseif ast.type == "slide_paragraph" then
      out[1] = out[1] .. "\n\\par\n"
   elseif ast.type == "horizontal_rule" then
      out[1] = out[1] .. "\n\\par\\addvspace{\\medskipamount}\n\\noindent\\rule{\\linewidth}{0.4pt}\n\\par\\addvspace{\\medskipamount}"
   elseif ast.type == "image" then
      local size = ast.width ~= "" and ("width=" .. ast.width .. ",") or ""
      out[1] = out[1] .. "\n\\adjustbox{" .. size .. "max width=\\linewidth}{\\includegraphics{" .. ast.path .. "}}"
   elseif ast.type == "latex" then
      out[1] = out[1] .. "\n" .. ast.content
   elseif ast.type == "item" then
      out[1] = out[1] .. "\n\\item "
      walk_nodes(ast.content, out, config)
   elseif ast.type == "enum" then
      out[1] = out[1] .. "\n\\item"
      walk_nodes(ast.content, out, config)
   elseif ast.type == "code" then

      out[1] = out[1] .. "\n\\begin{verbatim}\n" .. ast.content .. "\\end{verbatim}"
   elseif ast.type == "blockquote" then
      out[1] = out[1] .. "\n\\begin{quote}\n"
      out[1] = out[1] .. write_blocks(ast.content, config, true)
      out[1] = out[1] .. "\n\\end{quote}"
   elseif ast.type == "table" then
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
   elseif ast.type == "other" then
      walk_nodes(ast.content, out, config)
   elseif ast.type == "paren_citation" then
      out[1] = out[1] .. "\\" .. config.paren_citation
      if ast.locator then
         out[1] = out[1] .. "[" .. ast.locator .. "]"
      end
      out[1] = out[1] .. "{" .. table.concat(ast.content, ", ") .. "}"
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
            walk_nodes(ast.content, out, config)
         end
         out[1] = out[1] .. "}"
      end
   elseif ast.type == "footnote" then
      if ast.repeated then
         out[1] = out[1] .. "\\footref{" .. ast.label .. "}"
      else
         out[1] = out[1] .. "\\footnote{"
         if ast.label then out[1] = out[1] .. "\\label{" .. ast.label .. "}" end
         if ast.inline then walk_nodes(ast.content, out, config)
         else out[1] = out[1] .. write_blocks(ast.blocks, config, true) end
         out[1] = out[1] .. "}"
      end
   elseif ast.type == "literal" then
      local escapes = { ["\\"] = "\\textbackslash{}", ["^"] = "\\textasciicircum{}", ["~"] = "\\textasciitilde{}" }
      out[1] = out[1] .. (escapes[ast.content] or ast.content:gsub("[%%{}#&_$]", "\\%0"))
   elseif ast.type == "citation" then
      out[1] = out[1] .. "\\" .. config.citation .. "{" .. ast.content .. "}"
   elseif ast.type == "verbatim" then
      out[1] = out[1] .. "\\texttt{" .. write_inline_code(ast.content) .. "}"
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
      walk_nodes(ast.content, out, config)
      out[1] = out[1] .. "}"
   elseif ast.type == "bold" then
      out[1] = out[1] .. "\\textbf{"
      walk_nodes(ast.content, out, config)
      out[1] = out[1] .. "}"
   elseif ast.type == "strikethrough" then
      out[1] = out[1] .. "\\sout{"
      walk_nodes(ast.content, out, config)
      out[1] = out[1] .. "}"
   elseif ast.type == "text" then
      out[1] = out[1] .. write_text(ast.content)
   else

      error("Unknown type: " .. ast.type)
   end
end

local contains_links

contains_links = function(list)
   for _, node in ipairs(list) do

      if not (type(node) == "string") then
         if node.type == "link" then return true end
         local content = nodes.content(node)
         if type(content) == "table" and contains_links(content) then return true end
         if node.type == "slide_frame" and node.title and contains_links(node.title) then return true end
         if node.type == "table" then
            for _, cell in ipairs(node.headers) do if contains_links(cell) then return true end end
            for _, row in ipairs(node.rows) do
               for _, cell in ipairs(row) do if contains_links(cell) then return true end end
            end
         end
      end
   end
   return false
end

write_blocks = function(ast, config, nested, comment_tokens)
   local output = { "" }
   local list_stack = {}

   for _, node in ipairs(ast) do
      if node.type == "item" or node.type == "enum" then
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
   return result
end

local function write(ast, config, nested)
   return write_blocks(ast, config, nested, ast.comments)
end

return write
]], "@src/mark2tex/write.tl"))(...)
end

return require("mark2tex.core")
