-- Footnote syntax is protected before ordinary inline formatting is parsed.
local nodes = require("mark2tex.nodes")
local links = require("mark2tex.links")
local type diagnostics = require("mark2tex.diagnostics")

local type Node = nodes.Node
local type Token = links.Token
local type Issue = diagnostics.Issue

local enum WarningKind
	"undefined"
	"nested-or-restricted"
	"unclosed"
end

local record Warning is Issue
	category: string
	kind: WarningKind
	-- The reference identifier, or "inline" / "reference" for unclosed openers.
	identifier: string
end

-- Types are exported as aliases: nested records would emit runtime tables.
local record footnotes
	type WarningKind = WarningKind
	type Warning = Warning
end

local function literal(source: string): {Node}
	local result: {Node} = {}
	for character in source:gmatch(".") do
		result[#result + 1] = { type = "literal", content = character }
	end
	return result
end

local function footnote_warning(kind: WarningKind, identifier: string): Warning
	return { category = "footnote", kind = kind, identifier = identifier }
end

-- Warnings from parse_content are passed through alongside footnote warnings.
function footnotes.protect<W is Issue>(
	source: string,
	resolve: function(identifier: string): Node,
	parse_content: function(content: string): ({Node}, {W}),
	disabled?: boolean
): string, {Token}, {Issue}
	local prefix = "MARKTWOTEXFOOTNOTE"
	while source:find(prefix, 1, true) do prefix = prefix .. "X" end
	local output: {string} = {}
	local tokens: {Token} = {}
	local warnings: {Issue} = {}
	local function add(node: Node)
		local token = prefix .. tostring(#tokens + 1) .. "END"
		tokens[#tokens + 1] = { token = token, node = node }
		output[#output + 1] = token
	end
	local index = 1
	while index <= #source do
		local last = links.protected_end(source, index)
		local link = not last and links.match(source, index)
		local identifier, content: string, string
		local finish: integer
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
			local node: Node
			local kind: WarningKind
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
			-- A malformed opener must not introduce an unescaped TeX superscript.
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
