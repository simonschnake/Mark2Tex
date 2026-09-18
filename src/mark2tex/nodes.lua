local nodes = {}

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

function nodes.enum(level, content)
	return { type = "enum", level = level, content = content }
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

return nodes
