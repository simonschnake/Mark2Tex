-- Generated from src/mark2tex/nodes.tl by Teal 0.24.1. Edit the .tl file and run 'make teal-gen'.


























































































































































































































































local nodes = {}




















































function nodes.content(node)
   return (node).content
end





function nodes.footnote(content, label, repeated)
   return { type = "footnote", content = content, label = label, repeated = repeated }
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
