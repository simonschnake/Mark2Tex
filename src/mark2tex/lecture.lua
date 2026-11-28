-- Generated from src/mark2tex/lecture.tl by Teal 0.24.1. Edit the .tl file and run 'make teal-gen'.







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
