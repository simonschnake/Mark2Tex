-- CommonMark conformance: every example of the spec (tests/commonmark/spec.lua)
-- is converted by Mark2TeX and compared with the spec's HTML. Neither side is
-- compared as text: both are reduced to one canonical form of block and inline
-- markers (paragraphs, headings, lists, emphasis, code, links, ...) with
-- whitespace normalized, built from the expected HTML on one side and from
-- the parsed Mark2TeX AST on the other.
--
--   lua tests/commonmark/conformance.lua           report, check for regressions
--   lua tests/commonmark/conformance.lua --update  rewrite passing.txt and report.md
--   lua tests/commonmark/conformance.lua --show N  both canonical forms of example N
--
-- passing.txt lists the examples that pass; make test fails when one of them
-- stops passing. report.md summarizes each spec section.

local conformance = {}

local DIR = "tests/commonmark/"

-- Spec sections that Mark2TeX deliberately does not follow, with the reason
-- (see "Deliberately unsupported" in README.md). Failures elsewhere are
-- either smaller deviations or not implemented yet.
conformance.DEVIATIONS = {
	["Tabs"] = "mostly indented code blocks",
	["Indented code blocks"] = "indentation is ordinary text; LaTeX bodies are often indented",
	["HTML blocks"] = "HTML has no meaning in LaTeX output",
	["Raw HTML"] = "HTML has no meaning in LaTeX output",
	["Entity and numeric character references"] = "write the Unicode character instead",
}

--------------------
-- Canonical form
--------------------

local BLOCK_TAGS = { p = true, hr = true, ul = true, ol = true, li = true, blockquote = true, pre = true, br = true,
	h1 = true, h2 = true, h3 = true, h4 = true, h5 = true, h6 = true }

-- Text never contains a marker: angle brackets become guillemet-like signs.
local function escape(text)
	return (text:gsub("<", "\226\128\185"):gsub(">", "\226\128\186"))
end

-- Preformatted content keeps its whitespace through normalization.
local function preformatted(text)
	text = text:gsub("\n+$", "")
	return (escape(text):gsub("\n", "\226\143\142"):gsub(" ", "\194\183"):gsub("\t", "\226\135\165"))
end

local function decode_entities(text)
	return (text:gsub("&(#?)([%w]+);", function(hash, name)
		if hash == "#" then
			local code = name:match("^[xX](%x+)$") and tonumber(name:sub(2), 16) or tonumber(name)
			if code and code > 0 and code < 0x110000 then return utf8.char(code) end
			return nil
		end
		local named = { amp = "&", lt = "<", gt = ">", quot = '"' }
		return named[name]
	end))
end

local function decode_percent(text)
	return (text:gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end))
end

local function href(destination)
	return escape(decode_percent(decode_entities(destination)))
end

local function normalize(canonical)
	canonical = canonical:gsub("%s+", " ")
	canonical = canonical:gsub(" ?(</?(%a[%w]*)[^>]*>) ?", function(tag, name)
		if BLOCK_TAGS[name] then return tag end
	end)
	return (canonical:gsub("^ ", ""):gsub(" $", ""))
end

-- The expected HTML of an example in canonical form.
function conformance.html_canonical(html)
	local out = {}
	local index = 1
	local in_item = 0
	while index <= #html do
		local first, last, closing, name, attributes = html:find("^<(/?)(%a[%w]*)([^>]*)>", index)
		if first then
			name = name:lower()
			if name == "pre" and closing == "" then
				local finish = html:find("</pre>", last + 1, true) or #html + 1
				local inner = html:sub(last + 1, finish - 1):gsub("^<code[^>]*>", ""):gsub("</code>$", "")
				out[#out + 1] = "<pre>" .. preformatted(decode_entities(inner)) .. "</pre>"
				index = finish + #"</pre>"
			elseif name == "code" and closing == "" then
				local finish = html:find("</code>", last + 1, true) or #html + 1
				out[#out + 1] = "<code>" .. escape(decode_entities(html:sub(last + 1, finish - 1))) .. "</code>"
				index = finish + #"</code>"
			else
				if name == "li" then in_item = in_item + (closing == "" and 1 or -1) end
				if name == "a" and closing == "" then
					out[#out + 1] = "<a " .. href(attributes:match('href="([^"]*)"') or "") .. ">"
				elseif name == "img" then
					out[#out + 1] = "<img " .. href(attributes:match('src="([^"]*)"') or "") .. ">"
				elseif name == "p" and in_item > 0 then
					out[#out + 1] = " "
				elseif BLOCK_TAGS[name] or name == "em" or name == "strong" or name == "a" or name == "del" then
					out[#out + 1] = "<" .. closing .. name .. ">"
				else
					out[#out + 1] = "{html}"
				end
				index = last + 1
			end
		elseif html:sub(index, index) == "<" then
			-- Comments, processing instructions, declarations.
			local finish = html:find(">", index + 1, true) or #html
			out[#out + 1] = "{html}"
			index = finish + 1
		else
			local finish = (html:find("<", index, true) or #html + 1) - 1
			out[#out + 1] = escape(decode_entities(html:sub(index, finish)))
			index = finish + 1
		end
	end
	return normalize(table.concat(out))
end

-- TeX control symbols that print exactly the character CommonMark shows.
local TEX_SYMBOLS = { ["\\#"] = "#", ["\\$"] = "$", ["\\%"] = "%", ["\\&"] = "&", ["\\_"] = "_",
	["\\{"] = "{", ["\\}"] = "}" }

local inline_canonical

local function inline(node)
	local kind = node.type
	if kind == "text" or kind == "literal" then return escape(node.content) end
	if kind == "latex_cmd" then return escape(TEX_SYMBOLS[node.content] or node.content) end
	if kind == "verbatim" then return "<code>" .. escape(node.content) .. "</code>" end
	if kind == "italic" then return "<em>" .. inline_canonical(node.content) .. "</em>" end
	if kind == "bold" then return "<strong>" .. inline_canonical(node.content) .. "</strong>" end
	if kind == "strikethrough" then return "<del>" .. inline_canonical(node.content) .. "</del>" end
	if kind == "link" then
		local label = node.content and inline_canonical(node.content) or escape(node.destination)
		return "<a " .. href(node.destination) .. ">" .. label .. "</a>"
	end
	if kind == "inline_image" then return "<img " .. href(node.path) .. ">" end
	if kind == "line_break" then return "<br>" end
	if kind == "inline_math" or kind == "citation" then return escape(node.content) end
	if kind == "display_math" then return escape("$$" .. node.content .. "$$") end
	if kind == "paren_citation" then return escape("[@" .. table.concat(node.content, "; @") .. "]") end
	if kind == "other" then return inline_canonical(node.content) end
	return "{" .. kind .. "}"
end

inline_canonical = function(list)
	local out = {}
	for _, node in ipairs(list or {}) do out[#out + 1] = inline(node) end
	return table.concat(out)
end

local blocks_canonical

local function paragraphs(text)
	local out = {}
	for paragraph in (text .. "\n\n"):gmatch("(.-)\n[ \t]*\n") do
		if paragraph:find("%S") then out[#out + 1] = "<p>" .. paragraph .. "</p>" end
	end
	return table.concat(out)
end

blocks_canonical = function(blocks, in_item)
	local out = {}
	for _, node in ipairs(blocks) do
		local kind = node.type
		if kind == "list" then
			local tag = node.kind == "bullet" and "ul" or "ol"
			out[#out + 1] = "<" .. tag .. ">"
			for _, item in ipairs(node.content) do
				out[#out + 1] = "<li>" .. blocks_canonical(item.content, true) .. "</li>"
			end
			out[#out + 1] = "</" .. tag .. ">"
		elseif kind == "header" then
			out[#out + 1] = "<h" .. node.level .. ">" .. inline_canonical(node.content) .. "</h" .. node.level .. ">"
		elseif kind == "other" then
			-- The expected HTML turns paragraphs inside items into spaces.
			local text = paragraphs(inline_canonical(node.content))
			out[#out + 1] = in_item and text:gsub("</?p>", " ") or text
		elseif kind == "horizontal_rule" then
			out[#out + 1] = "<hr>"
		elseif kind == "code" then
			out[#out + 1] = "<pre>" .. preformatted(node.content) .. "</pre>"
		elseif kind == "blockquote" then
			out[#out + 1] = "<blockquote>" .. blocks_canonical(node.content) .. "</blockquote>"
		elseif kind == "latex" then
			out[#out + 1] = "<p>" .. escape(node.content) .. "</p>"
		elseif kind == "image" then
			out[#out + 1] = "<p><img " .. href(node.path) .. "></p>"
		elseif kind == "display_math" then
			out[#out + 1] = "<p>" .. escape("$$" .. node.content .. "$$") .. "</p>"
		else
			out[#out + 1] = "{" .. kind .. "}"
		end
	end
	return table.concat(out)
end

-- Mark2TeX's result for an example in canonical form, or nil and the error.
function conformance.mark2tex_canonical(markdown)
	local parse = require("mark2tex.parse")
	local ok, ast = pcall(parse, markdown, require("mark2tex.default_config"))
	if not ok then return nil, tostring(ast) end
	return normalize(blocks_canonical(ast))
end

--------------------
-- Running the spec
--------------------

function conformance.results()
	local examples = dofile(DIR .. "spec.lua")
	local results = {}
	for _, example in ipairs(examples) do
		local actual, err = conformance.mark2tex_canonical(example.markdown)
		results[#results + 1] = {
			example = example.example,
			section = example.section,
			pass = actual ~= nil and actual == conformance.html_canonical(example.html),
			error = err,
		}
	end
	return results, examples
end

function conformance.read_passing()
	local passing = {}
	local file = io.open(DIR .. "passing.txt")
	if not file then return passing end
	for line in file:lines() do
		local number = tonumber(line:match("^(%d+)"))
		if number then passing[number] = true end
	end
	file:close()
	return passing
end

-- Examples recorded as passing that fail now, and passing ones not recorded.
function conformance.compare(results, passing)
	local regressions, improvements = {}, {}
	for _, result in ipairs(results) do
		if passing[result.example] and not result.pass then regressions[#regressions + 1] = result.example end
		if result.pass and not passing[result.example] then improvements[#improvements + 1] = result.example end
	end
	return regressions, improvements
end

local function sections(results)
	local order, by_name = {}, {}
	for _, result in ipairs(results) do
		local section = by_name[result.section]
		if not section then
			section = { name = result.section, total = 0, passed = 0, first = result.example }
			by_name[result.section] = section
			order[#order + 1] = section
		end
		section.total = section.total + 1
		if result.pass then section.passed = section.passed + 1 end
	end
	return order
end

function conformance.report(results)
	local lines = {
		"# CommonMark conformance",
		"",
		"Generated by `lua tests/commonmark/conformance.lua --update` from the",
		"[CommonMark Spec 0.31.2](https://spec.commonmark.org/0.31.2/). An example passes",
		"when Mark2TeX produces the same structure as the spec's HTML (paragraphs,",
		"headings, lists, emphasis, code, links, images, line breaks) with the same text.",
		"TeX escapes that print the same character, such as `\\#`, count as that character.",
		"",
		"| Section | Passing | Status |",
		"| --- | ---: | --- |",
	}
	local passed = 0
	for _, section in ipairs(sections(results)) do
		passed = passed + section.passed
		local status = conformance.DEVIATIONS[section.name]
		status = status and ("deliberate deviation: " .. status)
			or (section.passed == section.total and "supported" or "partly supported")
		lines[#lines + 1] = string.format("| %s | %d / %d | %s |", section.name, section.passed, section.total, status)
	end
	lines[#lines + 1] = string.format("| **All** | **%d / %d** | |", passed, #results)
	lines[#lines + 1] = ""
	lines[#lines + 1] = "Failures outside the deliberate deviations are listed in"
	lines[#lines + 1] = "`tests/commonmark/passing.txt` by omission; inspect one with"
	lines[#lines + 1] = "`lua tests/commonmark/conformance.lua --show N`."
	return table.concat(lines, "\n") .. "\n", passed
end

local function write(path, content)
	local file = assert(io.open(path, "w"))
	file:write(content)
	file:close()
end

function conformance.main(args)
	-- Loading the bundle may reset the global arg table.
	args = { table.unpack(args) }
	package.path = "./?.lua;" .. package.path
	dofile("mark2tex.lua")
	if args[1] == "--show" then
		local number = tonumber(args[2])
		for _, example in ipairs(dofile(DIR .. "spec.lua")) do
			if example.example == number then
				print("section:  " .. example.section)
				print("markdown: " .. string.format("%q", example.markdown))
				print("expected: " .. conformance.html_canonical(example.html))
				local actual, err = conformance.mark2tex_canonical(example.markdown)
				print("actual:   " .. (actual or ("error: " .. err)))
				return 0
			end
		end
		io.stderr:write("no example " .. tostring(args[2]) .. "\n")
		return 1
	end
	local results = conformance.results()
	local report, passed = conformance.report(results)
	if args[1] == "--update" then
		local numbers = {}
		for _, result in ipairs(results) do
			if result.pass then numbers[#numbers + 1] = tostring(result.example) end
		end
		write(DIR .. "passing.txt", table.concat(numbers, "\n") .. "\n")
		write(DIR .. "report.md", report)
		print(string.format("CommonMark: %d of %d examples pass; wrote passing.txt and report.md", passed, #results))
		return 0
	end
	local regressions, improvements = conformance.compare(results, conformance.read_passing())
	print(string.format("CommonMark: %d of %d examples pass", passed, #results))
	if #improvements > 0 then
		print("newly passing (run with --update to record): " .. table.concat(improvements, ", "))
	end
	if #regressions > 0 then
		print("no longer passing: " .. table.concat(regressions, ", "))
		return 1
	end
	return 0
end

-- Run as a script, not when required by the test suite.
if arg and arg[0] and arg[0]:match("conformance%.lua$") then
	os.exit(conformance.main(arg))
end

return conformance
