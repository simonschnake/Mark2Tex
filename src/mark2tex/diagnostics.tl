local type ParserIssue = require("mark2tex.issue")
local delimiters = require("mark2tex.delimiters")
local spans = require("mark2tex.spans")

local enum WarningCategory
	"math-delimiter"
	"latex-environment"
end

local enum WarningKind
	"unclosed"
	"unexpected-end"
	"mismatched"
end

local record Warning is ParserIssue
	category: WarningCategory
	kind: WarningKind
	line: integer
	column: integer
	delimiter: string
	environment: string
	expected_end: string
	actual_end: string
end

-- Types are exported as aliases: nested records would emit runtime tables.
local record diagnostics
	type Issue = ParserIssue
	type WarningCategory = WarningCategory
	type WarningKind = WarningKind
	type Warning = Warning
end

local record OpenEnvironment
	name: string
	position: integer
end

local links = require("mark2tex.links")

local function source_position(source: string, position: integer): integer, integer
	local prefix = source:sub(1, position - 1)
	local _, newlines = prefix:gsub("\n", "")
	local last_newline = (prefix:match(".*()\n") as integer) or 0
	return newlines + 1, position - last_newline
end

local function warning(source: string, position: integer, fields: Warning): Warning
	fields.line, fields.column = source_position(source, position)
	return fields
end

-- Blank out fenced code and code spans (keeping newlines, so positions stay
-- valid) with the rules every pass shares (see spans).
local function mask_code(source: string): string
	local output: {string} = {}
	local position = 1
	while position <= #source do
		local at_line_start = position == 1 or source:sub(position - 1, position - 1) == "\n"
		local indent = at_line_start and #source:match("^[ \t]*", position) or 0
		local fence = at_line_start and spans.fence_end(source, position + indent) or nil
		local code = not fence and source:sub(position, position) == "`" and spans.code_end(source, position) or nil
		local ending = fence or code
		if ending then
			output[#output + 1] = (source:sub(position, ending):gsub("[^\n]", " "))
			position = ending + 1
		else
			local run = math.max(spans.run_length(source, position), 1)
			output[#output + 1] = source:sub(position, position + run - 1)
			position = position + run
		end
	end
	return table.concat(output)
end

local function display_warnings(scanned: string, source: string, warnings: {Warning})
	local position = 1
	while position <= #scanned do
		local dollar = delimiters.find_unescaped(scanned, "$$", position)
		local bracket = delimiters.find_unescaped(scanned, "\\[", position)
		local opening: integer
		local closing_delimiter: string
		if dollar and (not bracket or dollar < bracket) then
			opening, closing_delimiter = dollar, "$$"
		elseif bracket then
			opening, closing_delimiter = bracket, "\\]"
		else
			break
		end

		local closing = delimiters.find_unescaped(scanned, closing_delimiter, opening + 2)
		if not closing then
			warnings[#warnings + 1] = warning(source, opening, {
				category = "math-delimiter",
				kind = "unclosed",
				delimiter = source:sub(opening, opening + 1),
			})
			break
		end
		position = closing + 2
	end
end

-- Both patterns capture a command and an environment name.
local find_environment = string.find as function(string, string, integer): integer, integer, string, string

local function environment_warnings(scanned: string, source: string, warnings: {Warning})
	local stack: {OpenEnvironment} = {}
	local position = 1
	while true do
		local first, last, command, name = find_environment(scanned, "\\(begin)%s*{([^}]+)}", position)
		local end_first, end_last, end_command, end_name = find_environment(scanned, "\\(end)%s*{([^}]+)}", position)
		if end_first and (not first or end_first < first) then
			first, last, command, name = end_first, end_last, end_command, end_name
		end
		if not first then
			break
		end

		if command == "begin" then
			stack[#stack + 1] = { name = name, position = first }
		elseif #stack == 0 then
			warnings[#warnings + 1] = warning(source, first, {
				category = "latex-environment",
				kind = "unexpected-end",
				environment = name,
			})
		elseif stack[#stack].name == name then
			table.remove(stack)
		else
			local opened = table.remove(stack)
			warnings[#warnings + 1] = warning(source, opened.position, {
				category = "latex-environment",
				kind = "mismatched",
				environment = opened.name,
				expected_end = opened.name,
				actual_end = name,
			})
		end
		position = last + 1
	end

	for _, opened in ipairs(stack) do
		warnings[#warnings + 1] = warning(source, opened.position, {
			category = "latex-environment",
			kind = "unclosed",
			environment = opened.name,
		})
	end
end

function diagnostics.collect(source: string): {Warning}
	local warnings: {Warning} = {}
	local scanned = links.mask_destinations(mask_code(source))
	display_warnings(scanned, source, warnings)
	environment_warnings(scanned, source, warnings)
	return warnings
end

return diagnostics
