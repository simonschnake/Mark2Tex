local type nodes = require("mark2tex.nodes")
local type Config = require("mark2tex.default_config")

local type Inline = nodes.Inline
local type Block = nodes.Block
local type Document = nodes.Document

local lecture = {}

local function slide_paragraph(): nodes.SlideParagraph
	return { type = "slide_paragraph" }
end

local function slide_pause(): nodes.SlidePause
	return { type = "slide_pause" }
end

local function is_whitespace(node: Block): boolean
	if node is nodes.Other then
		for _, inline in ipairs(node.content) do
			if not (inline is nodes.Text) or inline.content:find("%S") then return false end
		end
		return true
	end
	return false
end

function lecture.structure(ast: Document, config: Config): Document
	local output: Document = { comments = ast.comments }
	local body: {Block} = {}
	local title: {Inline} = nil
	local has_content, pending_pause = false, false

	local footer: string = nil
	local notes: {string} = {}
	local section_only = false
	local handout = config.profile == "handout"
	local function finish()
		if handout then
			if (title or has_content) and (footer or #notes > 0) then
				local annotations: nodes.LectureAnnotations = { type = "lecture_annotations", footer = footer, notes = notes }
				output[#output + 1] = annotations
			end
		elseif title or has_content then
			local frame: nodes.SlideFrame = { type = "slide_frame", content = body, title = title,
				footer = footer, notes = notes }
			output[#output + 1] = frame
		end
		body, title, footer, notes = {}, nil, nil, {}
		has_content, pending_pause, section_only = false, false, false
	end

	for _, node in ipairs(ast) do
		local h1 = false
		if not handout and node is nodes.Header then
			h1 = not node.indented and node.level == 1
		end
		if h1 and config.h1 == "hide" then goto continue end
		if section_only and node.type ~= "slide_footer" and node.type ~= "slide_note"
			and not is_whitespace(node) then finish() end
		if node is nodes.SlideFooter then
			footer = footer or node.title
		elseif node is nodes.SlideNote then
			notes[#notes + 1] = node.title
		elseif node is nodes.Header and not node.indented and node.level <= config.slide_level then
			finish()
			title = node.content
			if handout then output[#output + 1] = node end
			section_only = node.level < config.slide_level and not (h1 and config.h1 == "frame")
		elseif node is nodes.SlideBreak then
			finish()
			if handout then output[#output + 1] = slide_paragraph() end
		elseif node is nodes.SlidePause then
			if handout then
				output[#output + 1] = slide_paragraph()
			else
				pending_pause = has_content
			end
		elseif not handout and config.standalone_learning_blocks and node is nodes.Latex
			and node.content:match("^%s*\\begin%s*{Lernblock}") then
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
			local block: Block = node
			if node is nodes.Header then
				local subheading: nodes.SlideSubheading = { type = "slide_subheading", content = node.content }
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
