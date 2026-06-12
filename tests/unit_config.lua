local core = require("marktex.core")
local default_config = require("marktex.default_config")

return function(luaunit)
	function test_config_overrides_do_not_mutate_defaults()
		local original_save_dir = default_config.save_dir
		local original_header_1 = default_config.header[1]

		local config = core.resolve_config({
			save_dir = "custom-output",
			header = { "chapter", "section" },
			citation = "autocite",
		})

		luaunit.assertEquals(config.save_dir, "custom-output")
		luaunit.assertEquals(config.header[1], "chapter")
		luaunit.assertEquals(config.header[2], "section")
		luaunit.assertEquals(config.citation, "autocite")
		luaunit.assertEquals(config.paren_citation, default_config.paren_citation)

		luaunit.assertEquals(default_config.save_dir, original_save_dir)
		luaunit.assertEquals(default_config.header[1], original_header_1)
		luaunit.assertEquals(default_config.citation, "cite")
	end

	function test_config_tables_are_not_shared()
		local config = core.resolve_config()

		config.header[1] = "chapter"

		luaunit.assertEquals(default_config.header[1], "section")
	end
end
