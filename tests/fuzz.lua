-- Property-based fuzz test: generate random Markdown from the supported
-- constructs, damage it, render it in every profile and check invariants.
--
--   lua tests/fuzz.lua [SAMPLES] [SEED]
--
-- Failing inputs are shrunk to a minimal example and written to tests/tmp/.

package.path = "./?.lua;" .. package.path
-- Test the shipped bundle: loading it registers every mark2tex.* module.
dofile("mark2tex.lua")

local lfs = require("lfs")
local parse = require("mark2tex.parse")
local write = require("mark2tex.write")
local lecture = require("mark2tex.lecture")
local core = require("mark2tex.core")

local SAMPLES = tonumber(arg and arg[1]) or 300
local SEED = tonumber(arg and arg[2]) or 20261128
local TMP_DIR = "tests/tmp"

local VARIANTS = {
	{ name = "default", config = {} },
	{ name = "instructor", config = { audience = "instructor" } },
	{ name = "handout", config = { profile = "handout" } },
	{ name = "slides", config = { profile = "slides" } },
	{ name = "slides-dozent-h1-frame", config = { profile = "slides", slide_audience = "dozent", h1 = "frame" } },
	{ name = "slides-h1-hide-level-1", config = { profile = "slides", h1 = "hide", slide_level = 1 } },
}

-- Errors that mark2tex raises on purpose for malformed div fences.
local INTENDED_ERRORS = {
	"unexpected div closing fence",
	"columns needs at least two visible column blocks",
	"column requires columns",
	"figure width must be expressed in em",
	"expected one caption in figure",
	"unclosed div fence",
}

--------------------
-- Deterministic random numbers (xorshift32), identical on every Lua version
--------------------

local state = SEED

local function random(low, high)
	state = state ~ ((state << 13) & 0xffffffff)
	state = state ~ (state >> 17)
	state = state ~ ((state << 5) & 0xffffffff)
	return low + state % (high - low + 1)
end

local function chance(percent) return random(1, 100) <= percent end
local function pick(list) return list[random(1, #list)] end

--------------------
-- Generator: every brace it emits outside code is balanced
--------------------

local WORDS = {
	"alpha", "Beta", "gamma", "x", "42", "3.14", "&", "A&B", "~", "-", "--", ",", ".", ":", ";", "!", "?",
	"'", "\"", "(", ")", "(x)", "[", "]", "<", ">", "/", "*", "_", "`", "$", "@", "!", "snake_case",
	"Ümlaut", "é", "→", "a.b", "e-mail",
}
-- Words without characters that start or end a construct. Clean documents use
-- only these, so every brace in them belongs to one generated construct.
local CLEAN_WORDS = {}
for _, word in ipairs(WORDS) do
	if not word:find("[%$`%*_%[%]<>@~\\!]") then CLEAN_WORDS[#CLEAN_WORDS + 1] = word end
end
local noisy = true

local MATH = { "x", "x^2", "a_b", "\\alpha", "\\frac{1}{2}", "{a}", "a+b", "\\sum_{i=1}^n i", "f(x)", "\\{x\\}" }
local DESTINATIONS = {
	"https://example.org", "https://example.org/a_b%20c?x=1&y=2#frag", "#sec:intro", "file name.pdf",
	"<a b.pdf>", "mailto:a@b.de", "https://e.org/(paren)", "x\\)y",
}
local CODE = { "x", "{", "}", "%", "#", "\\cmd", "a_b", "$x$", "[l](u)", "^[n]", "<!-- -->", "**", "&", "~" }
local CLASSES = { ".notes", ".footer", ".slides", ".script", ".instructor", ".student", ".columns",
	".column", ".figure", ".caption", "{.figure width=12em}", "{.figure width=3cm}" }

local inline

local function words(count)
	local parts = {}
	for _ = 1, count do parts[#parts + 1] = pick(noisy and WORDS or CLEAN_WORDS) end
	return table.concat(parts, " ")
end

local function math_content()
	local parts = {}
	for _ = 1, random(1, 3) do parts[#parts + 1] = pick(MATH) end
	return table.concat(parts, " ")
end

local function code_content()
	local parts = {}
	for _ = 1, random(1, 3) do parts[#parts + 1] = pick(CODE) end
	return table.concat(parts, " ")
end

local INLINE_ATOMS = {
	function() return words(random(1, 4)) end,
	function() return "`" .. code_content() .. "`" end,
	function() return "``" .. pick({ "a ` b", " `x` ", "``", "$x$" }) .. "``" end,
	-- Lone backtick runs shift code span pairing; only noisy documents get them.
	function() return noisy and pick({ "`", "``", "```" }) .. words(1) or words(1) end,
	function() return "$" .. math_content() .. "$" end,
	function() return "\\(" .. math_content() .. "\\)" end,
	function() return "$$" .. math_content() .. "$$" end,
	function() return "\\[" .. math_content() .. "\\]" end,
	function(depth) return "**" .. inline(depth + 1) .. "**" end,
	function(depth) return "*" .. inline(depth + 1) .. "*" end,
	function(depth) return "_" .. inline(depth + 1) .. "_" end,
	function(depth) return "~~" .. inline(depth + 1) .. "~~" end,
	function(depth) return "[" .. inline(depth + 1) .. "](" .. pick(DESTINATIONS) .. (chance(20) and ' "title"' or "") .. ")" end,
	function() return "<https://example.org/" .. pick({ "a", "b_c", "x%20y" }) .. ">" end,
	function() return "<someone@example.org>" end,
	function() return "![alt](image.png)" .. (chance(30) and "{width=2em}" or "") end,
	-- Reference links resolve only when a definition block names the label.
	function(depth) return "[" .. inline(depth + 1) .. "]" .. pick({ "[ref]", "[]", "[missing]", "" }) end,
	function() return pick({ "[ref]", "[Ref]", "![alt][img]" }) end,
	-- A trailing backslash breaks the line.
	function() return words(1) .. "\\\n" .. words(1) end,
	function() return "[^" .. pick({ "a", "b", "missing" }) .. "]" end,
	function(depth) return "^[" .. inline(depth + 1) .. "]" end,
	function() return "@" .. pick({ "key", "Turing1950" }) end,
	function() return "[@a; @b" .. (chance(50) and ", p. 3" or "") .. "]" end,
	function() return "<!-- " .. words(2) .. " -->" end,
	-- TeX command arguments are raw TeX by design, so only TeX-safe text goes in.
	function() return "\\textbf{" .. words(2) .. (chance(50) and " $" .. math_content() .. "$" or "") .. "}" end,
	function() return "\\ref{" .. pick({ "a", "fig:x" }) .. "}" end,
	-- \[ and \] are display math delimiters, not escapes.
	function() return pick({ "\\*", "\\_", "\\$", "\\`", "\\\\", "\\+", "\\|", "\\<", "\\>", "\\?", "\\`{e}" }) end,
}

inline = function(depth)
	depth = depth or 0
	local parts = {}
	for _ = 1, random(1, depth > 2 and 1 or 4) do
		local atom = depth > 3 and INLINE_ATOMS[1] or pick(INLINE_ATOMS)
		parts[#parts + 1] = atom(depth)
	end
	-- Adjacent code spans would merge their backtick runs into one, which
	-- changes their meaning; such neighbours get a space.
	local text = parts[1]
	for index = 2, #parts do
		local separator = pick({ " ", "", " ", "\n" })
		if separator == "" and text:sub(-1) == "`" and parts[index]:sub(1, 1) == "`" then separator = " " end
		text = text .. separator .. parts[index]
	end
	return text
end

local block

local BLOCKS = {
	function() return inline() end,
	function() return ("#"):rep(random(1, 7)) .. " " .. inline() end,
	function() return (" "):rep(random(0, 2) * 2) .. pick({ "- ", "* ", "1. ", "3) ", "a) " }) .. inline() end,
	function() return "> " .. inline() .. "\n> " .. inline() end,
	function(depth) return "> " .. block(depth + 1):gsub("\n", "\n> ") end,
	function()
		local columns = random(1, 3)
		local function row(make) local cells = {} for i = 1, columns do cells[i] = make(i) end return "| " .. table.concat(cells, " | ") .. " |" end
		return row(function() return inline(3) end) .. "\n" .. row(function() return pick({ "---", ":---", "---:", ":---:" }) end)
			.. "\n" .. row(function() return inline(3) end)
	end,
	function() return "```" .. pick({ "", "lua" }) .. "\n" .. code_content() .. "\n```" end,
	function() return "~~~" .. pick({ "", "python" }) .. "\n" .. code_content() .. "\n~~~" end,
	function() return "````\n```\n" .. code_content() .. "\n````" end,
	-- A tex fence is raw TeX, so its content has balanced braces.
	function() return "```tex\n" .. math_content() .. "\n```" end,
	function() return "\\begin{" .. pick({ "center", "align", "quote" }) .. "}\n" .. math_content() .. "\n\\end{center}" end,
	function() return "$$\n" .. math_content() .. "\n$$" end,
	function() return "[^" .. pick({ "a", "b" }) .. "]: " .. inline() .. (chance(30) and "\n    " .. inline() or "") end,
	function() return pick({ "---", "***", "___", "- - -", " * * *" }) end,
	function() return ("#"):rep(random(1, 3)) .. " " .. inline() .. " " .. ("#"):rep(random(1, 3)) end,
	function() return inline() .. "\n" .. ("="):rep(random(1, 5)) end,
	function() return pick({ "[ref]", "[img]", "[REF]" }) .. ": " .. pick(DESTINATIONS) .. (chance(30) and ' "title"' or "") end,
	function() return ". . ." end,
	function() return "![alt](figure.pdf)" .. (chance(50) and "{width=10em}" or "") end,
	function(depth) return (":"):rep(random(3, 5)) .. " " .. pick(CLASSES) .. "\n" .. block(depth + 1) .. "\n" .. (":"):rep(random(3, 5)) end,
	function() return "<!--\n" .. words(3) .. "\n-->" end,
}

block = function(depth)
	depth = depth or 0
	return (depth > 2 and BLOCKS[1] or pick(BLOCKS))(depth)
end

local function document()
	noisy = chance(50)
	local blocks = {}
	for _ = 1, random(1, 8) do blocks[#blocks + 1] = block() end
	local source = table.concat(blocks, pick({ "\n\n", "\n", "\n\n\n" }))
	-- Damage the document the way real drafts are damaged.
	local damaged = false
	if chance(20) then source, damaged = source:sub(1, random(0, #source)), true end
	if chance(15) and #source > 2 then
		local first = random(1, #source)
		source, damaged = source:sub(1, first - 1) .. source:sub(first + random(1, 6)), true
	end
	if chance(10) then
		local position = random(1, #source + 1)
		source = source:sub(1, position - 1) .. pick({ "`", "$", "*", "[", "]", "\n", "::: .notes\n" }) .. source:sub(position)
		damaged = true
	end
	-- Brace balance is only meaningful for clean, undamaged documents.
	return source, damaged or noisy
end

--------------------
-- Properties
--------------------

-- Braces in TeX output outside comments, escapes and verbatim environments.
local function brace_balance(tex)
	local depth, index = 0, 1
	while index <= #tex do
		local character = tex:sub(index, index)
		if character == "\\" then
			if tex:sub(index, index + 15) == "\\begin{verbatim}" then
				local finish = tex:find("\\end{verbatim}", index, true)
				index = finish and finish + #"\\end{verbatim}" or #tex + 1
			else
				index = index + 2
			end
		elseif character == "%" then
			index = (tex:find("\n", index, true) or #tex) + 1
		else
			if character == "{" then depth = depth + 1 end
			if character == "}" then
				depth = depth - 1
				if depth < 0 then return "unmatched } at byte " .. index end
			end
			index = index + 1
		end
	end
	if depth ~= 0 then return depth .. " unclosed {" end
end

-- Raw TeX passes through unchanged, so output braces can only balance when the
-- input braces outside code do.
-- Remove code spans and fences by the CommonMark rule (a run of n backticks
-- closed by the next run of exactly n in the paragraph), written
-- independently of src/mark2tex/spans.tl so the two can be compared.
local function escaped(source, index)
	local slashes = 0
	while index - slashes - 1 >= 1 and source:sub(index - slashes - 1, index - slashes - 1) == "\\" do
		slashes = slashes + 1
	end
	return slashes % 2 == 1
end

-- Math opened before a backtick is raw TeX: its closing delimiter in the same
-- paragraph, or nil. A single $ is not closed by half of a $$.
local function math_end(source, index)
	local opening = source:sub(index, index + 1)
	local closer
	if opening == "$$" then closer = "$$"
	elseif opening == "\\(" then closer = "\\)"
	elseif source:sub(index, index) == "$" then opening, closer = "$", "$"
	else return nil end
	if escaped(source, index) then return nil end
	local paragraph = source:find("\n[ \t]*\n", index) or #source + 1
	local search = index + #opening
	while true do
		local first = source:find(closer, search, true)
		if not first or first >= paragraph then return nil end
		if not escaped(source, first) and (closer ~= "$" or source:sub(first, first + 1) ~= "$$") then
			return first + #closer - 1
		end
		search = first + (closer == "$" and source:sub(first, first + 1) == "$$" and 2 or 1)
	end
end

local function strip_code(source)
	local output, index = {}, 1
	while index <= #source do
		local run = source:match("^[`~]+", index)
		local at_line_start = index == 1 or source:sub(index - 1, index - 1) == "\n"
		local math = math_end(source, index)
		if math then
			output[#output + 1] = source:sub(index, math)
			index = math + 1
		elseif run and at_line_start and #run >= 3 then
			local closing = nil
			local search = index + #run
			while true do
				local first, last = source:find(run:sub(1, 1) == "`" and "`+" or "~+", search)
				if not first then break end
				if last - first + 1 >= #run then closing = last break end
				search = last + 1
			end
			if closing then index = closing + 1 else output[#output + 1] = run; index = index + #run end
		elseif run and run:sub(1, 1) == "`" and source:sub(index - 1, index - 1) ~= "\\" then
			run = source:match("^`+", index)
			local paragraph = source:find("\n[ \t]*\n", index) or #source + 1
			local closing, search = nil, index + #run
			while true do
				local first, last = source:find("`+", search)
				if not first or first >= paragraph then break end
				if last - first + 1 == #run then closing = last break end
				search = last + 1
			end
			if closing then index = closing + 1 else output[#output + 1] = run; index = index + #run end
		else
			output[#output + 1] = source:sub(index, index)
			index = index + 1
		end
	end
	return table.concat(output)
end

local function input_balanced(source)
	local text = strip_code(source)
	local depth, index = 0, 1
	while index <= #text do
		local character = text:sub(index, index)
		if character == "\\" then
			index = index + 1
		elseif character == "{" then
			depth = depth + 1
		elseif character == "}" then
			depth = depth - 1
			if depth < 0 then return false end
		end
		index = index + 1
	end
	return depth == 0
end

local function intended(message)
	for _, expected in ipairs(INTENDED_ERRORS) do
		if message:find(expected, 1, true) and message:match("^[^:]*:%d+: ") then return true end
	end
	return false
end

local function line_count(source)
	local _, newlines = source:gsub("\n", "")
	return newlines + 1
end

-- Returns nil when every property holds, otherwise a description. Brace
-- balance is only checked for undamaged documents: there every raw brace pair
-- sits inside one generated construct.
local function check(source, variant, damaged)
	local config = assert(core.resolve_config(variant.config))
	local ok, ast = pcall(parse, source, config, "fuzz.md")
	if not ok then
		if intended(tostring(ast)) then return nil end
		return "parse error: " .. tostring(ast)
	end
	for _, warning in ipairs(ast.warnings) do
		if warning.line and (warning.line < 1 or warning.line > line_count(source) or (warning.column or 1) < 1) then
			return ("warning %s/%s outside the source at %s:%s"):format(warning.category, tostring(warning.kind),
				tostring(warning.line), tostring(warning.column))
		end
	end
	if config.profile then
		local structured_ok, structured = pcall(lecture.structure, ast, config)
		if not structured_ok then return "lecture error: " .. tostring(structured) end
		ast = structured
	end
	local written_ok, tex = pcall(write, ast, config)
	if not written_ok then return "write error: " .. tostring(tex) end
	local again_ok, again = pcall(write, ast, config)
	if not again_ok or again ~= tex then return "writing the same AST twice differs" end
	if tex:find("MARKTWOTEX", 1, true) or tex:find("[\30\31]") then
		return "placeholder token left in output"
	end
	local braces = not damaged and input_balanced(source) and brace_balance(tex)
	if braces then return "unbalanced braces in output: " .. braces end
end

local function failure(source, damaged)
	for _, variant in ipairs(VARIANTS) do
		local problem = check(source, variant, damaged)
		if problem then return problem, variant end
	end
end

-- Greedy shrinking: drop ever smaller chunks while the same kind of failure remains.
local function shrink(source, problem, damaged)
	local kind = problem:match("^[^:]+")
	local function still_fails(candidate)
		local other = failure(candidate, damaged)
		return other and other:match("^[^:]+") == kind
	end
	local size = #source // 2
	while size >= 1 do
		local index, changed = 1, false
		while index <= #source do
			local candidate = source:sub(1, index - 1) .. source:sub(index + size)
			if candidate ~= source and still_fails(candidate) then
				source, changed = candidate, true
			else
				index = index + size
			end
		end
		if not changed then size = size // 2 end
	end
	return source
end

--------------------
-- Run
--------------------

lfs.mkdir(TMP_DIR)
local failures, seen = 0, {}
for sample = 1, SAMPLES do
	local source, damaged = document()
	local problem, variant = failure(source, damaged)
	if problem then
		local key = problem:gsub("%d+", "N")
		if not seen[key] then
			seen[key] = true
			failures = failures + 1
			local minimal = shrink(source, problem, damaged)
			local minimal_problem, minimal_variant = failure(minimal, damaged)
			-- The seed in the name keeps parallel runs (make fuzz) apart.
			local path = ("%s/fuzz-%d-failure-%d.md"):format(TMP_DIR, SEED, failures)
			for target, content in pairs({ [path] = minimal, [path:gsub("%.md$", ".original.md")] = source }) do
				local file = assert(io.open(target, "w"))
				file:write(content)
				file:close()
			end
			io.stderr:write(("sample %d (%s): %s\n  minimal input (%s, %s): %q\n"):format(sample, variant.name, problem,
				path, minimal_variant and minimal_variant.name or "?", minimal))
			if minimal_problem ~= problem then io.stderr:write("  minimal problem: " .. tostring(minimal_problem) .. "\n") end
		end
	end
end

if failures > 0 then
	io.stderr:write(("Fuzz: %d distinct failures in %d samples (seed %d)\n"):format(failures, SAMPLES, SEED))
	os.exit(1)
end
print(("Fuzz: %d samples x %d variants hold every property (seed %d)"):format(SAMPLES, #VARIANTS, SEED))
