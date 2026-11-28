-- Generated from src/mark2tex/links.tl by Teal 0.24.1. Edit the .tl file and run 'make teal-gen'.

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
