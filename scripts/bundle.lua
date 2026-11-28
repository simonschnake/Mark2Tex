-- Combine the Lua modules generated from src/mark2tex/*.tl into mark2tex.lua.
--
--   lua scripts/bundle.lua OUTPUT TEAL_VERSION MODULE.lua...
--
-- Each module becomes a package.preload entry named mark2tex.<file name>, so
-- the bundle is a single file that Kpathsea, Overleaf and the CLI can load
-- without knowing the source layout. Loading it returns mark2tex.core.

local output_path, teal_version = arg[1], arg[2]
assert(output_path and teal_version and arg[3], "usage: bundle.lua OUTPUT TEAL_VERSION MODULE.lua...")

local modules = {}
for index = 3, #arg do
	local path = arg[index]
	local name = assert(path:match("([^/\\]+)%.lua$"), "not a Lua file: " .. path)
	modules[#modules + 1] = { name = "mark2tex." .. name, path = path }
end
table.sort(modules, function(left, right) return left.name < right.name end)

local parts = {
	"-- Mark2TeX: Markdown-like fragments for LuaLaTeX.\n",
	"-- Generated from src/mark2tex/*.tl by Teal ", teal_version, " and scripts/bundle.lua.\n",
	"-- Do not edit; change the Teal sources and run 'make teal-gen'.\n",
}
for _, module in ipairs(modules) do
	local file = assert(io.open(module.path, "r"))
	local code = file:read("a")
	file:close()
	parts[#parts + 1] = ("\npackage.preload[%q] = function(...)\n"):format(module.name)
	parts[#parts + 1] = code
	if code:sub(-1) ~= "\n" then parts[#parts + 1] = "\n" end
	parts[#parts + 1] = "end\n"
end
parts[#parts + 1] = '\nreturn require("mark2tex.core")\n'

local output = assert(io.open(output_path, "w"))
output:write(table.concat(parts))
output:close()
