-- Generated from src/mark2tex/footnotes.tl by Teal 0.24.1. Edit the .tl file and run 'make teal-gen'.

local nodes = require("mark2tex.nodes")
local links = require("mark2tex.links")




















local footnotes = {}




local function literal(source)
   local result = {}
   for character in source:gmatch(".") do
      result[#result + 1] = { type = "literal", content = character }
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
            node = nodes.footnote(parsed)
            node.inline = true
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

         add({ type = "literal", content = "^" })
         warnings[#warnings + 1] = footnote_warning("unclosed", "inline")
         index = index + 1
      elseif source:sub(index, index + 1) == "[^" then
         output[#output + 1] = "["
         add({ type = "literal", content = "^" })
         warnings[#warnings + 1] = footnote_warning("unclosed", "reference")
         index = index + 2
      else
         output[#output + 1], index = source:sub(index, index), index + 1
      end
   end
   return table.concat(output), tokens, warnings
end

return footnotes
