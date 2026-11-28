local type comments = require("mark2tex.comments")
local type Issue = require("mark2tex.issue")

local record AstNode
	type: string
	content: string | {AstNode | string}
	label: string
	repeated: boolean
	inline: boolean
	identifier: string
	destination: string
	-- A string for links and slide annotations; parsed header content for slide frames.
	title: string | {AstNode | string}
	footer: string
	notes: {string}
	kind: string
	level: integer
	style: string
	start: integer
	code_type: string
	headers: {string | {AstNode}}
	alignments: {string}
	rows: {{string | {AstNode}}}
	locator: string
	position: integer
	ending: integer
	length: integer
	attributes: string
	path: string
	width: string
	indented: boolean
end

-- The AST root carries document-wide comments and parser warnings.
local record AstDocument
	{AstNode}
	comments: {comments.Token}
	warnings: {Issue}
end

local record nodes
	type Node = AstNode
	type Document = AstDocument
end

local type Node = nodes.Node

function nodes.footnote(content?: {Node}, label?: string, repeated?: boolean): Node
	return { type = "footnote", content = content, label = label, repeated = repeated }
end

function nodes.footnote_definition(identifier: string, content: string): Node
	return { type = "footnote_definition", identifier = identifier, content = content }
end

function nodes.link(destination: string, content: {Node}, title?: string, kind?: string): Node
	return { type = "link", destination = destination, content = content, title = title, kind = kind or "inline" }
end

function nodes.header(level: integer, content: string): Node
	return { type = "header", level = level, content = content }
end

function nodes.horizontal_rule(): Node
	return { type = "horizontal_rule" }
end

function nodes.latex(content: string): Node
	return { type = "latex", content = content }
end

function nodes.item(level: integer, content: string): Node
	return { type = "item", level = level, content = content }
end

function nodes.enum(level: integer, content: string, style: string, start: integer): Node
	return { type = "enum", level = level, content = content, style = style, start = start }
end

function nodes.code(code_type: string, content: string): Node
	return { type = "code", code_type = code_type, content = content }
end

function nodes.blockquote(content: string): Node
	return { type = "blockquote", content = content }
end

function nodes.table(headers: {string}, alignments: {string}, rows: {{string}}): Node
	return { type = "table", headers = headers, alignments = alignments, rows = rows }
end

function nodes.other(content: string | {Node}): Node
	return { type = "other", content = content }
end

function nodes.paren_citation(content: {string}, locator?: string): Node
	return { type = "paren_citation", content = content, locator = locator }
end

function nodes.citation(content: string): Node
	return { type = "citation", content = content }
end

function nodes.verbatim(content: string): Node
	return { type = "verbatim", content = content }
end

function nodes.inline_math(content: string): Node
	return { type = "inline_math", content = content }
end

function nodes.display_math(content: string): Node
	return { type = "display_math", content = content }
end

function nodes.latex_cmd(content: string): Node
	return { type = "latex_cmd", content = content }
end

function nodes.italic(content: {Node}): Node
	return { type = "italic", content = content }
end

function nodes.bold(content: {Node}): Node
	return { type = "bold", content = content }
end

function nodes.strikethrough(content: {Node}): Node
	return { type = "strikethrough", content = content }
end

function nodes.text(content: string): Node
	return { type = "text", content = content }
end

return nodes
