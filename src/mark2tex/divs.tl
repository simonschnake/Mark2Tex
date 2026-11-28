local type nodes = require("mark2tex.nodes")
local type comments = require("mark2tex.comments")
local type diagnostics = require("mark2tex.diagnostics")
local type Config = require("mark2tex.default_config")

local type Node = nodes.Node
local type CommentToken = comments.Token
local type Issue = diagnostics.Issue

local record Warning is Issue
	category: string
	message: string
	line: integer
	column: integer
end

-- Types are exported as aliases: nested records would emit runtime tables.
local record divs
	type Warning = Warning
end

local record FenceAnnotation
	kind: string
	chunks: {string}
	owner: Fence
end

-- A div_fence node from parse_blocks plus the state collected while selecting.
local record Fence
	type: string
	position: integer
	ending: integer
	length: integer
	attributes: string
	line: integer
	column: integer
	visible: boolean
	annotation: FenceAnnotation
	layout: string
	columns: {Node}
	caption: boolean
end

local annotations: {string: string} = { notes = "slide_note", footer = "slide_footer" }

local function append_block(output: {Node}, node: Node)
	local previous = output[#output]
	if previous and previous.type == "other" and node.type == "other" then
		-- Before inline parsing, "other" nodes still carry raw source text.
		local before, after = previous.content as string, node.content as string
		if before:find("%S") and after:find("%S") then
			local gap = before:match("%s*$") .. after:match("^%s*")
			local _, newlines = gap:gsub("\n", "")
			if newlines < 2 then node.content = string.rep("\n", 2 - newlines) .. after end
		end
	end
	output[#output + 1] = node
end

local function classes(attributes: string): {string}
	if attributes:sub(1, 1) ~= "{" then return { attributes } end
	local result: {string} = {}
	-- Ignore quoted attribute values, which may themselves contain dots.
	attributes = attributes:gsub('"[^"]*"', '""'):gsub("'[^']*'", "''")
	for class in attributes:sub(2, -2):gmatch("%S+") do
		if class:match("^%.[%w_-]+$") then result[#result + 1] = class:sub(2) end
	end
	return result
end

function divs.select(
	ast: {Node},
	protected: string,
	source: string,
	comment_tokens: {CommentToken},
	config: Config,
	source_id: string,
	warnings: {Issue}
): {Node}
	local slides = config and config.profile == "slides"
	local lecture = slides or (config and config.profile == "handout")
	local instructor = config and (config.audience == "instructor" or config.slide_audience == "dozent")
	local enabled: {string: boolean} = { slides = slides == true, script = not slides,
		instructor = instructor == true, student = not instructor }
	local output: {Node} = {}
	local stack: {Fence} = {}
	local function tex(content: string): Node
		local marker: Node = { type = "latex", content = content }
		output[#output + 1] = marker
		return marker
	end
	local previous_fence_end: integer
	local comment_index, offset = 1, 0
	local line, line_start, scanned = 0, 1, 1

	local function locate(position: integer): integer, integer
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

	local function warn(message: string, at_line: integer, at_column: integer)
		local warning: Warning = { category = "div-fence", message = message,
			line = at_line, column = at_column }
		warnings[#warnings + 1] = warning
	end

	local function fail(message: string, at_line: integer)
		error((source_id or "Markdown") .. ":" .. at_line .. ": " .. message, 0)
	end

	for _, block in ipairs(ast) do
		local parent = stack[#stack]
		if block.type ~= "div_fence" then
			if not parent or (parent.visible and not parent.annotation) then
				append_block(output, block)
			end
		else
			local node = block as Fence
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
							marker.content = string.format("\\begin{column}{\\dimexpr(\\linewidth-%d\\columnsep)/%d\\relax}", count-1, count)
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
						output[#output + 1] = { type = parent.annotation.kind, title = title }
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
