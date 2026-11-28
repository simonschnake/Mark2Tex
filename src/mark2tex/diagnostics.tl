local type ParserIssue = require("mark2tex.issue")
local delimiters = require("mark2tex.delimiters")

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

local function mask_inline_code(line: string): string
	local output: {string} = {}
	local position = 1
	while position <= #line do
		local opening = line:find("`", position, true)
		if not opening then
			output[#output + 1] = line:sub(position)
			break
		end
		output[#output + 1] = line:sub(position, opening - 1)
		local closing = line:find("`", opening + 1, true)
		local last = closing or #line
		output[#output + 1] = string.rep(" ", last - opening + 1)
		position = last + 1
	end
	return table.concat(output)
end

local function mask_code(source: string): string
	local output: {string} = {}
	local position = 1
	local in_fence = false
	while position <= #source do
		local newline = source:find("\n", position, true)
		local last = newline and newline - 1 or #source
		local line = source:sub(position, last)
		local fence = line:match("^%s*```") ~= nil
		if in_fence or fence then
			output[#output + 1] = string.rep(" ", #line)
		else
			output[#output + 1] = mask_inline_code(line)
		end
		if fence then
			in_fence = not in_fence
		end
		if newline then
			output[#output + 1] = "\n"
		end
		position = last + 2
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
