local parse = require("marktex.parse")
local parse_blocks = require("marktex.parse_blocks")
local parse_inlines = require("marktex.parse_inlines")
local default_config = require("marktex.default_config")
local helpers = require("tests.helpers")

return function(luaunit)
	function test_block_parser_leaves_inline_content_unparsed()
		local ast = parse_blocks("\n# Heading with **bold** and @cite\n")
		local header = ast[1]

		helpers.assert_node(luaunit, header, "header")
		luaunit.assertEquals(header.content, "Heading with **bold** and @cite")
	end

	function test_inline_parser_parses_inline_nodes()
		local ast = parse_inlines("Heading with **bold** and @cite")

		helpers.assert_node(luaunit, ast[1], "text")
		helpers.assert_node(luaunit, ast[2], "bold")
		helpers.assert_node(luaunit, ast[3], "text")
		helpers.assert_node(luaunit, ast[4], "citation")
		luaunit.assertEquals(ast[4].content, "cite")
	end

	function test_inline_parser_keeps_broken_inline_cases_as_text()
		local cases = {
			"Text with @ only",
			"Text with $5 and no math",
			"Text with `open code",
			"Text with **open bold",
			"Text with [@broken citation",
		}

		for _, input in ipairs(cases) do
			local ast = parse_inlines(input)
			helpers.assert_node(luaunit, ast[1], "text")
			luaunit.assertEquals(#ast, 1)
			luaunit.assertEquals(ast[1].content, input)
		end
	end

	function test_inline_parser_supports_nested_latex_command_args()
		local ast = parse_inlines("Text with \\cmd{a{b}c}")

		helpers.assert_node(luaunit, ast[1], "text")
		helpers.assert_node(luaunit, ast[2], "latex_cmd")
		luaunit.assertEquals(ast[2].content, "\\cmd{a{b}c}")
	end

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

	function test_ast_falls_back_to_text_for_unclosed_inline_markers()
		local ast = parse("*open only\nThis has `unterminated\nThis has $unterminated\nText with [@missing\n", default_config)
		local expected = "*open only\nThis has `unterminated\nThis has $unterminated\nText with [@missing"
		local actual = helpers.strip_newlines_at_start_and_end(ast[1].content[1].content)

		helpers.assert_node(luaunit, ast[1], "other")
		luaunit.assertEquals(#ast[1].content, 1)
		helpers.assert_node(luaunit, ast[1].content[1], "text")
		luaunit.assertEquals(actual, expected)

		local transformed = helpers.strip_newlines_at_start_and_end(
			helpers.transform("*open only\nThis has `unterminated\nThis has $unterminated\nText with [@missing\n")
		)
		luaunit.assertEquals(transformed, expected)
	end

	function test_ast_preserves_mixed_block_order()
		local ast = parse(
			[[# Heading with *inline*

Paragraph before

```lua
print(1)
```

\begin{align}
a = b
\end{align}

- Item one
  - Child one
- Item two

Trailing text
]],
			default_config
		)

		luaunit.assertEquals(#ast, 10)
		luaunit.assertEquals(ast[1].type, "header")
		luaunit.assertEquals(ast[2].type, "other")
		luaunit.assertEquals(ast[3].type, "code")
		luaunit.assertEquals(ast[4].type, "other")
		luaunit.assertEquals(ast[5].type, "latex")
		luaunit.assertEquals(ast[6].type, "other")
		luaunit.assertEquals(ast[7].type, "item")
		luaunit.assertEquals(ast[8].type, "item")
		luaunit.assertEquals(ast[9].type, "item")
		luaunit.assertEquals(ast[10].type, "other")

		luaunit.assertEquals(ast[1].content[1].content, "Heading with ")
		helpers.assert_node(luaunit, ast[1].content[2], "italic")
		luaunit.assertEquals(ast[3].code_type, "lua")
		luaunit.assertEquals(ast[3].content, "print(1)\n")
		luaunit.assertEquals(ast[7].level, 0)
		luaunit.assertEquals(ast[8].level, 2)
		luaunit.assertEquals(ast[9].level, 0)
		luaunit.assertEquals(helpers.strip_newlines_at_start_and_end(ast[10].content[1].content), "Trailing text")
	end
end
