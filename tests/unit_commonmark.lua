-- CommonMark constructs adopted where they do not conflict with LaTeX.
local parse = require("mark2tex.parse")
local parse_inlines = require("mark2tex.parse_inlines")
local parse_blocks = require("mark2tex.parse_blocks")
local links = require("mark2tex.links")
local lecture = require("mark2tex.lecture")
local write = require("mark2tex.write")
local mark2tex = require("mark2tex")
local helpers = require("tests.helpers")

local guard = "\\ifcsname hyper@normalise\\endcsname\\else\\PackageError{mark2tex}{Markdown links require hyperref}{Load \\string\\usepackage{hyperref} in the document preamble.}\\fi\n"

-- The first node of a type anywhere in a parsed tree.
local function find(nodes, node_type)
	for _, node in ipairs(nodes) do
		if node.type == node_type then return node end
		if type(node.content) == "table" then
			local found = find(node.content, node_type)
			if found then return found end
		end
	end
	return nil
end

local function types(blocks)
	local result = {}
	for index, block in ipairs(blocks) do result[index] = block.type end
	return table.concat(result, " ")
end

return function(unit)
	function test_commonmark_reference_definition_parsing()
		local label, target = links.definition('[Foo  Bar]: <a b.pdf> "Title"')
		unit.assertEquals(label, "foo bar")
		unit.assertEquals(target.destination, "a b.pdf")
		unit.assertEquals(target.title, "Title")
		label, target = links.definition("   [x]:/url 'single'")
		unit.assertEquals(label, "x")
		unit.assertEquals(target.destination, "/url")
		unit.assertEquals(target.title, "single")
		label, target = links.definition("[x]: /url (paren title)")
		unit.assertEquals(target.title, "paren title")
		label, target = links.definition("[empty]: <>")
		unit.assertEquals(target.destination, "")
		-- Not definitions: footnotes, four spaces of indentation, prose after
		-- the destination, a missing destination, nested brackets.
		for _, line in ipairs({ "[^note]: text", "    [x]: /url", "[Note]: see below", "[x]:", "[x]: ",
			"[a [b]]: /url", "[x] : /url", "[ ]: /url", '[x]: /url "unclosed' }) do
			unit.assertEquals(links.definition(line), nil)
		end
	end

	function test_commonmark_reference_label_normalization()
		unit.assertEquals(links.normalize_label("  Foo\n\tBAR  "), "foo bar")
		unit.assertEquals(helpers.transform("[FOO   bar]\n\n[Foo Bar]: /u"), guard .. "\\href{\\detokenize{/u}}{FOO   bar}\n")
	end

	function test_commonmark_reference_link_forms_and_titles()
		local ast = parse_inlines("[text][ref] [ref][] [ref]", { resolve_reference = function(label)
			if label == "ref" then return { destination = "/u", title = "T" } end
		end })
		local count = 0
		for _, node in ipairs(ast) do
			if node.type == "link" then
				count = count + 1
				unit.assertEquals(node.destination, "/u")
				unit.assertEquals(node.title, "T")
			end
		end
		unit.assertEquals(count, 3)
		-- Without definitions nothing is a reference.
		unit.assertEquals(helpers.find_node(parse_inlines("[text][ref] [ref]"), "link"), nil)
	end

	function test_commonmark_reference_definitions_do_not_interrupt_paragraphs()
		local ast = parse("Paragraph\n[x]: /url\n\n[x]")
		unit.assertEquals(find(ast, "link"), nil)
		unit.assertNotNil(find(parse("Paragraph\n\n[x]: /url\n\n[x]"), "link"))
		-- Consecutive definitions are fine.
		ast = parse("[a]\n[b]\n\n[a]: /a\n[b]: /b")
		unit.assertEquals(#ast.warnings, 0)
		unit.assertEquals(helpers.transform("[a] [b]\n\n[a]: /a\n[b]: /b"),
			guard .. "\\href{\\detokenize{/a}}{a} \\href{\\detokenize{/b}}{b}\n")
	end

	function test_commonmark_reference_scope_and_warnings()
		-- Definitions are document-wide: quotes and footnotes see them too.
		local tex = helpers.transform("> [q]\n\nText[^n].\n\n[^n]: See [q].\n\n[q]: /q")
		local _, links_found = tex:gsub("\\href{\\detokenize{/q}}{q}", "")
		unit.assertEquals(links_found, 2)
		-- The first definition wins, quietly; unused ones are reported.
		local ast = parse("[x]\n\n[x]: /first\n[x]: /second\n[unused]: /u")
		unit.assertEquals(find(ast, "link").destination, "/first")
		unit.assertEquals(#ast.warnings, 1)
		unit.assertEquals(ast.warnings[1].category, "link")
		unit.assertEquals(ast.warnings[1].kind, "unused")
		unit.assertEquals(ast.warnings[1].message, "unused link definition [unused]; omitted")
	end

	function test_commonmark_inline_images()
		local image = parse_inlines("a ![alt](img/x.png){width=2em} b")[2]
		unit.assertEquals(image.type, "inline_image")
		unit.assertEquals(image.path, "img/x.png")
		unit.assertEquals(image.width, "2em")
		-- Remote or TeX-unsafe paths stay literal.
		for _, source in ipairs({ "![x](https://e.org/a.png)", "![x](a%b.png)", "![x](a#b.png)", "![x]()" }) do
			unit.assertEquals(helpers.find_node(parse_inlines(source), "inline_image"), nil)
		end
		-- An escaped ! makes it a link.
		unit.assertEquals(helpers.transform("\\![x](a.png)"), guard .. "\\!\\href{\\detokenize{a.png}}{x}")
		-- A standalone image line stays an image block.
		unit.assertEquals(parse("![x](a.png)")[1].type, "image")
	end

	function test_commonmark_emphasis_flanking()
		unit.assertEquals(helpers.transform("foo_bar_baz _a_ __b__"), "foo\\_bar\\_baz \\emph{a} \\textbf{b}")
		unit.assertEquals(helpers.transform("x * a * and *b*"), "x * a * and \\emph{b}")
		unit.assertEquals(helpers.transform("x **a ** and **b**"), "x **a ** and \\textbf{b}")
		unit.assertEquals(helpers.transform("foo*bar*"), "foo\\emph{bar}")
		-- Math, code and placeholders count as word-adjacent content.
		unit.assertEquals(helpers.transform("_$x$_ and *`c`*"), "\\emph{$x$} and \\emph{\\texttt{c}}")
	end

	function test_commonmark_backslash_escapes()
		local ast = parse_inlines("\\* \\+ \\< \\> \\| \\? \\`")
		local literals = {}
		for _, node in ipairs(ast) do if node.type == "literal" then literals[#literals + 1] = node.content end end
		unit.assertEquals(table.concat(literals), "*+<>|?`")
		-- TeX meanings win where TeX has one.
		for _, source in ipairs({ "\\#", "\\_", "\\-", "\\\\", "\\`{e}", "\\,", "\\'e" }) do
			unit.assertEquals(helpers.transform(source), source)
		end
	end

	function test_commonmark_hard_line_breaks()
		local ast = parse_inlines("a\\\nb")
		unit.assertEquals(ast[2].type, "line_break")
		unit.assertEquals(helpers.transform("a\\\nb"), "a\\\\\nb")
		-- Not at the end of a paragraph, and \\ stays TeX.
		unit.assertEquals(helpers.transform("a\\\n\nb"), "a\\\n\nb")
		unit.assertEquals(helpers.transform("a\\\\\nb"), "a\\\\\nb")
		unit.assertEquals(helpers.transform("- item\\\n  next"), "\\begin{itemize}\n\\item item\\\\\n  next\n\\end{itemize}")
	end

	function test_commonmark_trailing_backslash_is_literal()
		-- Found by the fuzzer: \section{\} left a brace unclosed.
		unit.assertEquals(helpers.transform("# \\"), "\\section{\\textbackslash{}}")
		unit.assertEquals(helpers.transform("## a \\ ##"), "\\subsection{a \\textbackslash{}}")
		-- In [a \](u) the bracket is escaped, so that is no link at all.
		unit.assertEquals(helpers.find_node(parse_inlines("[a \\](u)"), "link"), nil)
		-- Inside a paragraph it is followed by a newline: TeX's control space.
		unit.assertEquals(helpers.transform("a \\\n\nb"), "a \\\n\nb")
	end

	function test_commonmark_thematic_breaks_and_atx_closing()
		for _, rule in ipairs({ "---", "***", "___", "- - -", "* * *", "_ _ _", "  ***  ", "-----" }) do
			unit.assertEquals(types(parse_blocks("\n" .. rule)), "horizontal_rule")
		end
		for _, text in ipairs({ "--", "**", "***bold***", "- -", "-- -x" }) do
			unit.assertNotNil(types(parse_blocks("\n" .. text)) ~= "horizontal_rule" or nil)
		end
		unit.assertEquals(parse_blocks("\n## a ##")[1].content, "a")
		unit.assertEquals(parse_blocks("\n## a#")[1].content, "a#")
		unit.assertEquals(parse_blocks("\n## a \\#")[1].content, "a \\#")
		unit.assertEquals(parse_blocks("\n# #")[1].content, "")
	end

	function test_commonmark_setext_headings()
		local blocks = parse_blocks("\nintro\n\nTitle\n  ===\nbody")
		unit.assertEquals(types(blocks), "other header other")
		unit.assertEquals(blocks[2].level, 1)
		unit.assertEquals(blocks[2].content, "Title")
		-- Four spaces of indentation, a blank line, or other characters: no heading.
		for _, source in ipairs({ "\nTitle\n    ===", "\nTitle\n\n===", "\nTitle\n=== x", "\n===" }) do
			unit.assertEquals(types(parse_blocks(source)), "other")
		end
		-- --- under text stays a rule, as before.
		unit.assertEquals(types(parse_blocks("\nTitle\n---")), "other horizontal_rule")
	end

	function test_commonmark_indented_fences_and_quotes()
		-- Up to three spaces; the opening indentation is removed from content lines.
		unit.assertEquals(helpers.transform("  ```\n  a\n    b\n c\n  ```"), "\\begin{verbatim}\na\n  b\nc\n\\end{verbatim}")
		unit.assertEquals(helpers.transform("```\nx\n   ```"), "\\begin{verbatim}\nx\n\\end{verbatim}")
		-- An empty fence is a code block too; a run on the opening line is no fence.
		unit.assertEquals(helpers.transform("```\n```"), "\\begin{verbatim}\n\\end{verbatim}")
		unit.assertEquals(parse("``` a ```")[1].type, "other")
		-- A fence ends a list item: items hold no blocks.
		unit.assertEquals(helpers.transform("- a\n  ```\n  x\n  ```\n- b"),
			"\\begin{itemize}\n\\item a\n\\end{itemize}\n\\begin{verbatim}\nx\n\\end{verbatim}\n\\begin{itemize}\n\\item b\n\\end{itemize}")
		-- An unclosed fence line stays item text.
		unit.assertEquals(helpers.transform("- a\n  ```b"), "\\begin{itemize}\n\\item a\n  ```b\n\\end{itemize}")
		-- Four spaces are no fence (no indented code blocks either).
		unit.assertEquals(parse("    ```\n    x\n    ```")[1].type, "other")
		-- Comments inside an indented fence stay literal, as in every fence.
		unit.assertEquals(helpers.transform("   ~~~\n   <!-- c -->\n   ~~~"), "\\begin{verbatim}\n<!-- c -->\n\\end{verbatim}")
		unit.assertEquals(helpers.transform("   > quoted"), "\\begin{quote}\nquoted\n\\end{quote}")
		unit.assertEquals(parse("    > not quoted")[1].type, "other")
	end

	function test_commonmark_code_span_whitespace()
		unit.assertEquals(helpers.transform("`a\nb`"), "\\texttt{a b}")
		unit.assertEquals(helpers.transform("``\nfoo\n``"), "\\texttt{foo}")
		unit.assertEquals(helpers.transform("` a `"), "\\texttt{a}")
		-- Only one space each side, and only when both are there.
		unit.assertEquals(helpers.transform("`  a  `"), "\\texttt{ a }")
		unit.assertEquals(helpers.transform("` a`"), "\\texttt{ a}")
		unit.assertEquals(helpers.transform("`  `"), "\\texttt{  }")
	end

	function test_commonmark_loose_lists()
		unit.assertEquals(helpers.transform("- a\n\n- b\n\n\n- c"), "\\begin{itemize}\n\\item a\n\\item b\n\\item c\n\\end{itemize}")
		unit.assertEquals(helpers.transform("1. a\n\n2. b"), "\\begin{enumerate}\n\\item a\n\\item b\n\\end{enumerate}")
		-- A comment between lists still separates them.
		unit.assertEquals(select(2, helpers.transform("- a\n\n<!-- x -->\n\n- b"):gsub("\\begin{itemize}", "")), 2)
	end

	function test_commonmark_lecture_breaks_and_setext()
		-- Any thematic break separates slides; setext headings title them.
		local config = assert(mark2tex.resolve_config({ profile = "slides" }))
		local function slides(source) return write(lecture.structure(parse(source, config), config), config) end
		local expected = slides("# Slide one\n\nA\n\n---\n\nB")
		unit.assertNotNil(expected:find("\\frametitle{Slide one}", 1, true))
		for _, rule in ipairs({ "***", "___", "- - -" }) do
			unit.assertEquals(slides("Slide one\n=========\n\nA\n\n" .. rule .. "\n\nB"), expected)
		end
	end
end
