local parse = require("mark2tex.parse")
local parse_blocks = require("mark2tex.parse_blocks")
local parse_inlines = require("mark2tex.parse_inlines")
local default_config = require("mark2tex.default_config")
local helpers = require("tests.helpers")

return function(luaunit)
	function test_ast_diagnostics_ignore_html_comments()
		local ast = parse("<!-- $$\n\\begin{hidden}\n-->\n\\end{visible}", default_config)
		luaunit.assertEquals(#ast.warnings, 1)
		luaunit.assertEquals(ast.warnings[1].environment, "visible")
		luaunit.assertEquals(ast.warnings[1].line, 4)
	end

	function test_html_comments_terminate_before_following_tex()
		luaunit.assertEquals(helpers.transform("# Title<!-- note -->"), "\\section{Title% note \n}")
		luaunit.assertEquals(helpers.transform("Before<!-- unfinished\nTODO"), "Before% unfinished\n%TODO\n")
		luaunit.assertEquals(helpers.transform("<!-- MARKTWOTEXCOMMENT1END -->"), "% MARKTWOTEXCOMMENT1END \n")
	end

	function test_ast_nested_quote_table_propagates_warnings()
		local ast = parse("> > | A | B |\n> > | --- | --- |\n> > | $x$ | $$y$$ |", default_config)
		local quote = ast[1]
		helpers.assert_node(luaunit, quote, "blockquote")
		helpers.assert_node(luaunit, quote.content[1], "blockquote")
		local tab = quote.content[1].content[1]
		helpers.assert_node(luaunit, tab, "table")
		helpers.assert_node(luaunit, tab.rows[1][1][1], "inline_math")
		luaunit.assertEquals(#ast.warnings, 1)
		luaunit.assertEquals(ast.warnings[1].kind, "display-in-table")
	end

	function test_block_parser_leaves_inline_content_unparsed()
		local ast = parse_blocks("\n# Heading with **bold** and @cite\n")
		local header = ast[1]

		helpers.assert_node(luaunit, header, "header")
		luaunit.assertEquals(header.content, "Heading with **bold** and @cite")
	end

	function test_inline_parser_parses_inline_nodes()
		local ast = parse_inlines("Heading with **bold** and @cite")

		helpers.assert_node(luaunit, ast[1], "text")
		helpers.assert_node(luaunit, helpers.find_node(ast, "bold"), "bold")
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
			luaunit.assertEquals(table.concat((function()
				local parts = {}
				for _, node in ipairs(ast) do
					parts[#parts + 1] = node.content
				end
				return parts
			end)()), input)
		end
	end

	function test_inline_parser_protects_dollar_and_parenthesis_math()
		local ast = parse_inlines("$a_b$ and \\(x + @citation\\)")

		helpers.assert_node(luaunit, ast[1], "inline_math")
		luaunit.assertEquals(ast[1].content, "$a_b$")
		helpers.assert_node(luaunit, ast[3], "inline_math")
		luaunit.assertEquals(ast[3].content, "\\(x + @citation\\)")
	end

	function test_inline_parser_keeps_math_protected_inside_formatting()
		local ast = parse_inlines("**$a_b$**")

		helpers.assert_node(luaunit, ast[1], "bold")
		helpers.assert_node(luaunit, ast[1].content[1], "inline_math")
		luaunit.assertEquals(ast[1].content[1].content, "$a_b$")
	end

	function test_inline_parser_respects_escaped_math_delimiters()
		local ast, warnings = parse_inlines([[\$not math\$ and \\\(x\\\)]])

		luaunit.assertEquals(#warnings, 0)
		helpers.assert_node(luaunit, ast[#ast], "inline_math")
		luaunit.assertEquals(ast[#ast].content, [[\(x\\\)]])
	end

	function test_inline_parser_reports_invalid_math_delimiters_without_losing_other_formatting()
		local ast, warnings = parse_inlines("$open and **bold**")

		luaunit.assertEquals(#warnings, 1)
		luaunit.assertEquals(warnings[1].category, "math-delimiter")
		luaunit.assertEquals(warnings[1].kind, "unclosed")
		helpers.assert_node(luaunit, helpers.find_node(ast, "bold"), "bold")
	end

	function test_inline_parser_supports_nested_latex_command_args()
		local ast = parse_inlines("Text with \\cmd{a{b}c}")

		helpers.assert_node(luaunit, ast[1], "text")
		helpers.assert_node(luaunit, ast[2], "latex_cmd")
		luaunit.assertEquals(ast[2].content, "\\cmd{a{b}c}")
	end

	function test_inline_parser_keeps_dangerous_underscore_text_intact()
		local ast = parse_inlines("snake_case stays readable")

		helpers.assert_node(luaunit, ast[1], "text")
		luaunit.assertEquals(#ast, 1)
		luaunit.assertEquals(ast[1].content, "snake_case stays readable")
	end

	function test_block_parser_keeps_unclosed_code_fence_as_text()
		local ast = parse_blocks("\n```lua\nprint(1)\n")

		helpers.assert_node(luaunit, ast[1], "other")
		luaunit.assertEquals(#ast, 1)
		luaunit.assertEquals(ast[1].content, "\n```lua\nprint(1)\n")
	end

	function test_block_parser_keeps_unclosed_latex_environment_as_text()
		local ast = parse_blocks([[
\begin{align}
a = b
]])

		helpers.assert_node(luaunit, ast[1], "other")
		luaunit.assertEquals(#ast, 1)
		luaunit.assertEquals(ast[1].content, "\\begin{align}\na = b\n")
	end

	function test_block_parser_keeps_text_and_list_boundaries_separate()
		local ast = parse_blocks([[
Paragraph before
- Item one
Paragraph after
]])

		helpers.assert_node(luaunit, ast[1], "other")
		helpers.assert_node(luaunit, ast[2], "item")
		helpers.assert_node(luaunit, ast[3], "other")
		luaunit.assertEquals(helpers.strip_newlines_at_start_and_end(ast[1].content), "Paragraph before")
		luaunit.assertEquals(ast[2].content, "Item one")
		luaunit.assertEquals(helpers.strip_newlines_at_start_and_end(ast[3].content), "Paragraph after")
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

	function test_ast_display_math_is_a_block_node()
		local ast = parse("$$\nx^2\n$$\n", default_config)

		helpers.assert_node(luaunit, ast[1], "display_math")
		luaunit.assertEquals(ast[1].content, "\nx^2\n")
	end

	function test_ast_keeps_latex_subenvironment_inside_display_math()
		local ast = parse("$$\\begin{aligned}x &= \\begin{cases}1 & x > 0\\\\0 & x \\leq 0\\end{cases}\\end{aligned}$$", default_config)

		helpers.assert_node(luaunit, ast[1], "display_math")
		luaunit.assertEquals(ast[1].content, "\\begin{aligned}x &= \\begin{cases}1 & x > 0\\\\0 & x \\leq 0\\end{cases}\\end{aligned}")
	end

	function test_ast_reports_unclosed_display_environment_with_source_position()
		local ast = parse("First line\n$$\n\\begin{aligned}\nx &= y\n$$\n", default_config)

		luaunit.assertEquals(#ast.warnings, 1)
		luaunit.assertEquals(ast.warnings[1].category, "latex-environment")
		luaunit.assertEquals(ast.warnings[1].kind, "unclosed")
		luaunit.assertEquals(ast.warnings[1].environment, "aligned")
		luaunit.assertEquals(ast.warnings[1].line, 3)
		luaunit.assertEquals(ast.warnings[1].column, 1)
	end

	function test_ast_reports_unclosed_display_delimiter_with_source_position()
		local ast = parse("First line\n$$\nx &= y\n", default_config)

		luaunit.assertEquals(#ast.warnings, 1)
		luaunit.assertEquals(ast.warnings[1].category, "math-delimiter")
		luaunit.assertEquals(ast.warnings[1].kind, "unclosed")
		luaunit.assertEquals(ast.warnings[1].delimiter, "$$")
		luaunit.assertEquals(ast.warnings[1].line, 2)
		luaunit.assertEquals(ast.warnings[1].column, 1)
	end

	function test_ast_diagnostics_ignore_code_spans_and_fences()
		local ast = parse("`\\begin{aligned}`\n```tex\n$$\n\\begin{cases}\n```\n", default_config)

		luaunit.assertEquals(#ast.warnings, 0)
	end

	function test_ast_keeps_display_math_in_tables_literal_with_warning()
		local ast = parse("| left | right |\n|---|---|\n| $x$ | $$y$$ |\n", default_config)

		luaunit.assertEquals(#ast.warnings, 1)
		luaunit.assertEquals(ast.warnings[1].kind, "display-in-table")
		helpers.assert_node(luaunit, ast[1].rows[1][1][1], "inline_math")
		helpers.assert_node(luaunit, ast[1].rows[1][2][1], "text")
		luaunit.assertEquals(ast[1].rows[1][2][1].content, "$$y$$")
	end

	function test_ast_parenthetical_citation_node()
		local ast = parse("[@alpha; @beta]\n", default_config)
		local citation = helpers.find_node(ast[1].content, "paren_citation")

		helpers.assert_node(luaunit, citation, "paren_citation")
		luaunit.assertEquals(citation.content[1], "alpha")
		luaunit.assertEquals(citation.content[2], "beta")
	end

	function test_ast_parenthetical_citation_node_with_locator()
		local ast = parse("[@Turing1950, p. 433]\n", default_config)
		local citation = helpers.find_node(ast[1].content, "paren_citation")

		helpers.assert_node(luaunit, citation, "paren_citation")
		luaunit.assertEquals(citation.content[1], "Turing1950")
		luaunit.assertEquals(citation.locator, "p. 433")
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
