-- Generated from src/mark2tex/delimiters.tl by Teal 0.24.1. Edit the .tl file and run 'make teal-gen'.
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
