local parse = require("marktex.parse")
local default_config = require("marktex.default_config")
local helpers = require("tests.helpers")

return function(luaunit)
	function test_ast_header_and_inline_nodes()
		local ast = parse("# Heading with **bold** and @cite\n", default_config)
		local header = ast[1]

		helpers.assert_node(luaunit, header, "header")
		luaunit.assertEquals(header.level, 1)
		helpers.assert_node(luaunit, header.content[1], "text")
		helpers.assert_node(luaunit, header.content[2], "bold")
		helpers.assert_node(luaunit, header.content[3], "text")
		helpers.assert_node(luaunit, header.content[4], "citation")
		luaunit.assertEquals(header.content[4].content, "cite")
	end

	function test_ast_list_nodes_keep_level_and_inline_content()
		local ast = parse("- Parent\n  - Child with `code`\n", default_config)

		helpers.assert_node(luaunit, ast[1], "item")
		luaunit.assertEquals(ast[1].level, 0)
		luaunit.assertEquals(ast[1].content[1].content, "Parent")

		helpers.assert_node(luaunit, ast[2], "item")
		luaunit.assertEquals(ast[2].level, 2)
		helpers.assert_node(luaunit, ast[2].content[2], "verbatim")
		luaunit.assertEquals(ast[2].content[2].content, "code")
	end

	function test_ast_code_and_latex_nodes()
		local ast = parse("```lua\nprint(1)\n```\n\n```tex\n\\begin{center}\nText\n\\end{center}\n```\n", default_config)

		helpers.assert_node(luaunit, ast[1], "code")
		luaunit.assertEquals(ast[1].code_type, "lua")
		luaunit.assertEquals(ast[1].content, "print(1)\n")

		helpers.assert_node(luaunit, ast[3], "latex")
		luaunit.assertEquals(ast[3].content, "\\begin{center}\nText\n\\end{center}\n")
	end

	function test_ast_parenthetical_citation_node()
		local ast = parse("[@alpha; @beta]\n", default_config)
		local citation = helpers.find_node(ast[1].content, "paren_citation")

		helpers.assert_node(luaunit, citation, "paren_citation")
		luaunit.assertEquals(citation.content[1], "alpha")
		luaunit.assertEquals(citation.content[2], "beta")
	end
end
