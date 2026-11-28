local type nodes = require("mark2tex.nodes")
local type Config = require("mark2tex.default_config")

local type Node = nodes.Node
local type Document = nodes.Document

local lecture = {}

-- Runs after inline parsing: "other" nodes hold inline lists, text nodes strings.
local function is_whitespace(node: Node): boolean
	if node.type ~= "other" then return false end
	for _, inline in ipairs(node.content as {Node}) do
		if inline.type ~= "text" or (inline.content as string):find("%S") then return false end
	end
	return true
end

function lecture.structure(ast: Document, config: Config): Document
	local output: Document = { comments = ast.comments }
	local body: {Node} = {}
	local title: string | {Node | string} = nil
	local has_content, pending_pause = false, false

	local footer: string = nil
	local notes: {string} = {}
	local section_only = false
	local handout = config.profile == "handout"
	local function finish()
		if handout then
			if (title ~= nil or has_content) and (footer ~= nil or #notes > 0) then
				output[#output + 1] = { type = "lecture_annotations", footer = footer, notes = notes }
			end
		elseif title ~= nil or has_content then
			output[#output + 1] = { type = "slide_frame", content = body, title = title,
				footer = footer, notes = notes }
		end
		body, title, footer, notes = {}, nil, nil, {}
		has_content, pending_pause, section_only = false, false, false
	end

	for _, node in ipairs(ast) do
		local h1 = not handout and node.type == "header" and not node.indented and node.level == 1
		if h1 and config.h1 == "hide" then goto continue end
		if section_only and node.type ~= "slide_footer" and node.type ~= "slide_note"
			and not is_whitespace(node) then finish() end
		if node.type == "slide_footer" then
			-- Slide annotations always carry a plain string title (see divs).
			footer = footer or (node.title as string)
		elseif node.type == "slide_note" then
			notes[#notes + 1] = node.title as string
		elseif node.type == "header" and not node.indented and node.level <= config.slide_level then
			finish()
			title = node.content
			if handout then output[#output + 1] = node end
			section_only = node.level < config.slide_level and not (h1 and config.h1 == "frame")
		elseif node.type == "slide_break" then
			finish()
			if handout then output[#output + 1] = { type = "slide_paragraph" } end
		elseif node.type == "slide_pause" then
			if handout then
				output[#output + 1] = { type = "slide_paragraph" }
			else
				pending_pause = has_content
			end
		elseif not handout and config.standalone_learning_blocks and node.type == "latex"
			and (node.content as string):match("^%s*\\begin%s*{Lernblock}") then
			finish()
			output[#output + 1] = node
		elseif handout then
			output[#output + 1] = node
			has_content = has_content or not is_whitespace(node)
		else
			if not is_whitespace(node) then
				if pending_pause then body[#body + 1] = { type = "slide_pause" } end
				pending_pause, has_content = false, true
			end
			if node.type == "header" then
				node = { type = "slide_subheading", content = node.content }
			end
			body[#body + 1] = node
		end
		::continue::
	end

	finish()
	return output
end

return lecture
