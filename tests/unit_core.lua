local core = require("marktex.core")
local lfs = require("lfs")
local helpers = require("tests.helpers")

return function(luaunit)
	function test_convert_creates_output_directory()
		local input_path = helpers.TMP_DIR .. "/convert_input.md"
		local save_dir = helpers.TMP_DIR .. "/convert-output"

		helpers.write_file(input_path, "# Title\n")

		local output_path, err = core.convert(input_path, { save_dir = save_dir })

		luaunit.assertNotNil(output_path, tostring(err))
		luaunit.assertEquals(lfs.attributes(save_dir, "mode"), "directory")
		luaunit.assertEquals(helpers.file_exists(output_path), true)
	end

	function test_convert_writes_cache_hash_header()
		local input_path = helpers.TMP_DIR .. "/cache_header_input.md"
		local save_dir = helpers.TMP_DIR .. "/cache-header-output"

		helpers.write_file(input_path, "# Title\n")

		local output_path, err = core.convert(input_path, { save_dir = save_dir })

		luaunit.assertNotNil(output_path, tostring(err))

		local first_line = helpers.read_file(output_path):match("([^\n]*)")
		luaunit.assertNotNil(first_line)
		luaunit.assertEquals(first_line:match("^%% cache:[0-9a-f]+$") ~= nil, true)
	end

	function test_convert_re_renders_when_config_changes()
		local input_path = helpers.TMP_DIR .. "/cache_invalidation_input.md"
		local save_dir = helpers.TMP_DIR .. "/cache-invalidation-output"

		helpers.write_file(input_path, "# Title\n")

		local original_output, err = core.convert(input_path, { save_dir = save_dir })
		luaunit.assertNotNil(original_output, tostring(err))

		local original_content = helpers.read_file(original_output)

		local updated_output, updated_err = core.convert(input_path, {
			save_dir = save_dir,
			header = { "chapter", "section", "subsection", "paragraph", "subparagraph" },
		})

		luaunit.assertNotNil(updated_output, tostring(updated_err))
		luaunit.assertEquals(updated_output, original_output)

		local updated_content = helpers.read_file(updated_output)
		luaunit.assertEquals(updated_content ~= original_content, true)
		luaunit.assertEquals(updated_content:match("\\chapter{Title}") ~= nil, true)
	end

	function test_convert_returns_error_for_missing_input()
		local output_path, err = core.convert(helpers.TMP_DIR .. "/missing-input.md", {
			save_dir = helpers.TMP_DIR .. "/missing-input-output",
		})

		luaunit.assertEquals(output_path, nil)
		luaunit.assertNotNil(err)
	end

	function test_save_dir_shell_metacharacters_are_treated_as_path()
		local input_path = helpers.TMP_DIR .. "/shell_meta_input.md"
		local marker_path = helpers.TMP_DIR .. "/shell-meta-marker"
		local save_dir = helpers.TMP_DIR .. "/literal;touch shell-meta-marker"

		helpers.write_file(input_path, "Plain text.\n")

		local output_path, err = core.convert(input_path, { save_dir = save_dir })

		luaunit.assertNotNil(output_path, tostring(err))
		luaunit.assertEquals(lfs.attributes(save_dir, "mode"), "directory")
		luaunit.assertEquals(helpers.file_exists(marker_path), false)
		luaunit.assertEquals(helpers.read_file(output_path):match("Plain text%."), "Plain text.")
	end
end
