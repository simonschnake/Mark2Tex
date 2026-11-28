-- Combine the Lua modules generated from src/mark2tex/*.tl into mark2tex.lua.
--
--   lua scripts/bundle.lua OUTPUT VERSION TEAL_VERSION MODULE.lua...
--
-- Each module becomes a package.preload entry named mark2tex.<file name>, so
-- the bundle is a single file that Kpathsea, Overleaf and the CLI can load
-- without knowing the source layout. Loading it returns mark2tex.core.
--
-- Modules are embedded as strings and compiled with the chunk name of their
-- Teal source. Teal keeps line numbers, so errors and tracebacks point to
-- src/mark2tex/<module>.tl at the right line instead of into the bundle.

local output_path, version, teal_version = arg[1], arg[2], arg[3]
assert(output_path and version and teal_version and arg[4], "usage: bundle.lua OUTPUT VERSION TEAL_VERSION MODULE.lua...")

local modules = {}
for index = 4, #arg do
	local path = arg[index]
	local name = assert(path:match("([^/\\]+)%.lua$"), "not a Lua file: " .. path)
	modules[#modules + 1] = { name = name, path = path }
end
table.sort(modules, function(left, right) return left.name < right.name end)

-- The shortest long-bracket level whose closing bracket does not occur in code.
local function long_bracket(code)
	local level = 0
	while code:find("]" .. ("="):rep(level) .. "]", 1, true) do
		level = level + 1
	end
	local equals = ("="):rep(level)
	return "[" .. equals .. "[", "]" .. equals .. "]"
end

local parts = {
	"-- Mark2TeX ", version, ": Markdown-like fragments for LuaLaTeX.\n",
	"-- Generated from src/mark2tex/*.tl by Teal ", teal_version, " and scripts/bundle.lua.\n",
	"-- Do not edit; change the Teal sources and run 'make teal-gen'.\n",
}
for _, module in ipairs(modules) do
	local file = assert(io.open(module.path, "rb"))
	local code = file:read("a")
	file:close()
	assert(not code:find("\r", 1, true), module.path .. ": carriage returns would change inside a long string")
	local open, close = long_bracket(code)
	-- A newline directly after the opening bracket is not part of the string,
	-- so the module's first line stays line 1 of its chunk.
	parts[#parts + 1] = ("\npackage.preload[%q] = function(...)\n"):format("mark2tex." .. module.name)
	parts[#parts + 1] = "\treturn assert(load(" .. open .. "\n" .. code .. close
	parts[#parts + 1] = (", %q))(...)\nend\n"):format("@src/mark2tex/" .. module.name .. ".tl")
end
parts[#parts + 1] = '\nreturn require("mark2tex.core")\n'

local output = assert(io.open(output_path, "wb"))
output:write(table.concat(parts))
output:close()
