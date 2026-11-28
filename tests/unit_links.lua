local parse = require("mark2tex.parse")
local parse_inlines = require("mark2tex.parse_inlines")
local links = require("mark2tex.links")
local helpers = require("tests.helpers")

local guard = "\\ifcsname hyper@normalise\\endcsname\\else\\PackageError{mark2tex}{Markdown links require hyperref}{Load \\string\\usepackage{hyperref} in the document preamble.}\\fi\n"

return function(unit)
	function test_links_parse_formatted_label_and_opaque_destination()
		local ast, warnings = parse_inlines('[Book, *title*, $x$](<books/a_b $@.pdf> "Details")')
		unit.assertEquals(#warnings, 0)
		unit.assertEquals(#ast, 1)
		local link = ast[1]
		unit.assertEquals(link.type, "link")
		unit.assertEquals(link.destination, "books/a_b $@.pdf")
		unit.assertEquals(link.title, "Details")
		unit.assertEquals(link.kind, "inline")
		unit.assertNotNil(helpers.find_node(link.content, "italic"))
		unit.assertNotNil(helpers.find_node(link.content, "inline_math"))
	end

	function test_links_destinations_balanced_parentheses_and_escapes()
		for _, source in ipairs({ '[x](a(b(c(d)))e)', '[x](a\\(b\\(c\\(d\\)\\)\\)e)' }) do
			unit.assertEquals(parse_inlines(source)[1].destination, "a(b(c(d)))e")
		end
		unit.assertEquals(parse_inlines('[x](<a\\>b\\<c>)')[1].destination, "a>b<c")
		unit.assertEquals(parse_inlines('[x]()')[1].destination, "")
		unit.assertEquals(parse_inlines('[x](<>)')[1].destination, "")
		unit.assertEquals(parse_inlines('[](url)')[1].content[1], nil)
	end

	function test_links_titles_and_whitespace()
		for _, title in ipairs({ '"some \\"title\\""', "'some title'", '(some title)' }) do
			local node = parse_inlines('[x](\n url ' .. title .. ' \n)')[1]
			unit.assertEquals(node.type, "link")
			unit.assertEquals(node.destination, "url")
			unit.assertNotNil(node.title)
		end
		unit.assertEquals(parse_inlines('[x](url "one\ntwo")')[1].title, "one\ntwo")
		unit.assertEquals(parse_inlines('[x](url "one\n\ntwo")')[1].type, "text")
	end

	function test_links_autolinks_and_email()
		local ast, warnings = parse_inlines('<https://example.org/a_$@?a=1&b=2#c> <a_b+tag@example.org>')
		unit.assertEquals(#warnings, 0)
		unit.assertEquals(ast[1].kind, "autolink")
		unit.assertEquals(ast[3].kind, "email")
		unit.assertEquals(ast[3].destination, "mailto:a_b+tag@example.org")
		for _, source in ipairs({ '<https://a b>', '<a@-example.org>', '<a@example..org>', '<a@example.org->', '<plain text>', 'https://example.org' }) do
			unit.assertEquals(helpers.find_node(parse_inlines(source), "link"), nil)
		end
	end

	function test_links_labels_brackets_code_math_and_escapes()
		local label = parse_inlines('[a [b] `]` $x$ \\(y\\) \\*z\\* \\[c\\]](url)')[1].content
		unit.assertNotNil(helpers.find_node(label, "verbatim"))
		local math_count = 0
		for _, child in ipairs(label) do if child.type == "inline_math" then math_count = math_count + 1 end end
		unit.assertEquals(math_count, 2)
		unit.assertEquals(helpers.transform('[\\*x\\* \\_y\\_ \\[z\\]](url)'), guard .. '\\href{\\detokenize{url}}{*x* \\_y\\_ [z]}')
	end

	function test_links_protected_contexts_and_images()
		for _, source in ipairs({ '`[x](url)`', '$[x](url)$', '\\([x](url)\\)', '\\textbf{[x](url)}', '![x](<a_b.pdf>)', '\\[x](url)' }) do
			unit.assertEquals(helpers.find_node(parse_inlines(source), "link"), nil)
		end
		local outer = parse_inlines('[outer [inner](url)](other)')[1]
		unit.assertEquals(helpers.find_node(outer.content, "link"), nil)
		local ast = parse('```\n[x](url)\n```\n\n\\begin{quote}\n[x](url)\n\\end{quote}')
		unit.assertEquals(ast[1].type, "code")
		unit.assertEquals(ast[#ast].type, "latex")
	end

	function test_links_malformed_preserve_source_and_following_formatting()
		for _, source in ipairs({ '[x](a b)', '[x](<a b)', '[x](a(b)', '[x](url "unclosed)' }) do
			unit.assertEquals(helpers.transform(source .. ' **after**'), source .. ' \\textbf{after}')
		end
		-- The broken destination is kept literally, so its underscore is escaped.
		unit.assertEquals(helpers.transform('[broken](foo_bar **after**'), '[broken](foo\\_bar \\textbf{after}')
		-- The label stays inline text: code in it is still typeset as code.
		unit.assertEquals(helpers.transform('[a `{`](b c'), '[a \\texttt{\\{}](b c')
		unit.assertEquals(helpers.transform('[x][ref] **after**'), '[x][ref] \\textbf{after}')
	end

	function test_links_writer_target_semantics_and_titles()
		unit.assertEquals(helpers.transform('[x](<https://example.org/a b%20c?x=1&y=$#frag> "hidden")'), guard .. '\\href{\\detokenize{https://example.org/a}\\%\\detokenize{20b}\\%\\detokenize{20c?x=1&y=$}\\#\\detokenize{frag}}{x}')
		unit.assertEquals(helpers.transform('[PDF](<unterlagen/Auswahl der Inhalte.pdf>)'), guard .. '\\href{\\detokenize{unterlagen/Auswahl der Inhalte.pdf}}{PDF}')
		unit.assertEquals(helpers.transform('[x](#grundlagen)'), guard .. '\\hyperref[\\detokenize{grundlagen}]{x}')
		unit.assertEquals(helpers.transform('<https://example.org/a_b>'), guard .. '\\url{\\detokenize{https://example.org/a_b}}')
		unit.assertEquals(helpers.transform('<a_b@example.org>'), guard .. '\\href{\\detokenize{mailto:a_b@example.org}}{\\nolinkurl{\\detokenize{a_b@example.org}}}')
		unit.assertEquals(links.tex_destination('a{b}\\c^^d%20'), '\\detokenize{a}\\Uchar123 \\detokenize{b}\\Uchar125 \\Uchar92 \\detokenize{c}\\Uchar94 \\Uchar94 \\detokenize{d}\\%\\detokenize{20}')
	end

	function test_links_in_all_inline_block_contexts()
		local ast = parse('# [heading](url)\n\n- [item](url)\n\n> [quote](url)\n\n| A | B |\n| --- | --- |\n| [cell](https://example.org/$@_) | end |')
		unit.assertEquals(ast[1].content[1].type, "link")
		local list = helpers.find_node(ast, "list")
		unit.assertEquals(list.content[1].content[1].content[2].type, "link")
		unit.assertNotNil(helpers.find_node(ast, "blockquote"))
		local tab = helpers.find_node(ast, "table")
		unit.assertEquals(#tab.rows[1], 2)
		unit.assertEquals(tab.rows[1][1][1].type, "link")
		unit.assertEquals(tab.rows[1][2][1].content, "end")
		unit.assertEquals(#ast.warnings, 0)
	end

	function test_links_diagnostics_ignore_destination_and_title_math()
		local ast = parse('[x](https://example.org/$$ "$$")\n\n$$unclosed')
		unit.assertEquals(#ast.warnings, 1)
		unit.assertEquals(ast.warnings[1].line, 3)
		unit.assertEquals(ast.warnings[1].category, "math-delimiter")
	end

	function test_links_token_collision_and_guard_only_when_needed()
		unit.assertEquals(helpers.transform('MARKTWOTEXLINK1END [x](url)'), guard .. 'MARKTWOTEXLINK1END \\href{\\detokenize{url}}{x}')
		unit.assertEquals(helpers.transform('**ordinary**'), '\\textbf{ordinary}')
	end
end
