-- Teal compiler settings, shared by `tl`, the Makefile and editor tooling.
return {
	include_dir = { "src" },
	-- LuaTeX runs Lua 5.3.
	gen_target = "5.3",
	gen_compat = "off",
}
