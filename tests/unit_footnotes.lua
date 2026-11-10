local parse = require("mark2tex.parse")
local helpers = require("tests.helpers")

local function output(source)
	return helpers.transform(source):gsub("mark2tex:footnote:%x+:", "fn:"):gsub("^\n+", ""):gsub("\n+$", "")
end

return function(unit)
	function test_footnotes_forward_backward_and_number_order()
		unit.assertEquals(output('First[^b], second[^a], again[^b].\n\n[^a]: Alpha.\n[^b]: Beta.'),
			'First\\footnote{\\label{fn:1}Beta.}, second\\footnote{\\label{fn:2}Alpha.}, again\\footref{fn:1}.')
		unit.assertEquals(output('[^a]: Before.\n\nText[^a].'), 'Text\\footnote{\\label{fn:1}Before.}.')
	end

	function test_footnotes_inline_balanced_brackets_and_formatting()
		unit.assertEquals(output('Text^[A **bold** and *italic* note, `]` and $x^2$, [brackets]].'),
			'Text\\footnote{A \\textbf{bold} and \\emph{italic} note, \\texttt{]} and $x^2$, [brackets]}.')
		unit.assertEquals(output('^[First] ^[Second] ^[]'), '\\footnote{First} \\footnote{Second} \\footnote{}')
		unit.assertEquals(output('^[A \\emph{raw [argument]}]'), '\\footnote{A \\emph{raw [argument]}}')
	end

	function test_footnotes_multiline_paragraphs_and_lists()
		unit.assertEquals(output('Text[^a].\n\n[^a]: First\n    continued.\n\n    Second paragraph.\n\n    - **one**\n    - two'),
			'Text\\footnote{\\label{fn:1}First\ncontinued.\n\nSecond paragraph.\n\n\\begin{itemize}\n\\item \\textbf{one}\n\\item two\n\\end{itemize}}.')
		unit.assertEquals(output('Text[^a].\n\n[^a]: First\n\tcontinued.\n\nAfter.'),
			'Text\\footnote{\\label{fn:1}First\ncontinued.}.\n\n\nAfter.')
	end

	function test_footnotes_document_scope_blockquotes_and_lists()
		local source = '> Quote[^a].\n>\n> [^a]: Shared.\n\n- Item[^a].'
		local result = output(source)
		unit.assertNotNil(result:find('Quote\\footnote{\\label{fn:1}Shared.}', 1, true))
		unit.assertNotNil(result:find('\\item Item\\footref{fn:1}.', 1, true))
	end

	function test_footnotes_protected_code_math_and_tex()
		local source = '`[^a] ^[code]` $[^a]$ \\textbf{[^a] ^[raw]}\n\n```\n[^a]: code definition\n^[code]\n```\n\n\\begin{quote}\n[^a]: raw definition\n\\end{quote}'
		local ast = parse(source)
		unit.assertEquals(#ast.warnings, 0)
		local result = output(source)
		unit.assertEquals(result:find('\\footnote{', 1, true), nil)
		unit.assertNotNil(result:find('[^a]: code definition', 1, true))
		unit.assertNotNil(result:find('[^a]: raw definition', 1, true))
	end

	function test_footnotes_links_and_citations_in_notes()
		local result = output('Text[^a].\n\n[^a]: [Web](https://example.org) and @key.')
		unit.assertNotNil(result:find('Markdown links require hyperref', 1, true))
		unit.assertNotNil(result:find('\\href{\\detokenize{https://example.org}}{Web} and \\cite{key}.', 1, true))
		result = output('^[See [Web](https://example.org/a^[b])].')
		unit.assertNotNil(result:find('\\Uchar94 ', 1, true))
		unit.assertNotNil(result:find('\\footnote{See ', 1, true))
	end

	function test_footnotes_unknown_duplicate_unused_and_case_sensitive()
		local ast = parse('Text[^missing].')
		unit.assertEquals(ast.warnings[1].category, 'footnote')
		unit.assertEquals(ast.warnings[1].kind, 'undefined')
		unit.assertEquals(ast.warnings[1].identifier, 'missing')
		unit.assertEquals(output('Text[^missing].'), 'Text[\\textasciicircum{}missing].')
		local source = 'Text[^a].\n\n[^a]: First.\n[^a]: Duplicate.\n[^unused]: Hidden.'
		unit.assertEquals(output(source), 'Text\\footnote{\\label{fn:1}First.}.')
		unit.assertEquals(parse(source).warnings[1].kind, 'duplicate')
		unit.assertEquals(parse('Text[^A].\n\n[^a]: Lowercase.').warnings[1].kind, 'undefined')
		unit.assertEquals(output('[^unused]: Hidden.'), '')
	end

	function test_footnotes_malformed_nested_and_restricted_contexts()
		unit.assertEquals(output('Text^[unclosed'), 'Text\\textasciicircum{}[unclosed')
		unit.assertEquals(output('Text[^unclosed'), 'Text[\\textasciicircum{}unclosed')
		unit.assertEquals(parse('Text^[unclosed').warnings[1].kind, 'unclosed')
		unit.assertEquals(output('^[Outer ^[inner]]'), '\\footnote{Outer \\textasciicircum{}[inner]}')
		unit.assertEquals(output('Text[^a].\n\n[^a]: Recursive[^a].'), 'Text\\footnote{\\label{fn:1}Recursive[\\textasciicircum{}a].}.')
		for _, source in ipairs({ '# Heading^[note]', '[Label^[note]](url)' }) do
			unit.assertEquals(parse(source).warnings[1].kind, 'nested-or-restricted')
			unit.assertEquals(output(source):find('\\footnote{', 1, true), nil)
		end
	end

	function test_footnotes_labels_are_safe_and_distinct_between_inputs()
		local first = helpers.transform('Text[^a].\n\n[^a]: One.')
		local second = helpers.transform('Text[^a].\n\n[^a]: Two.')
		unit.assertNotNil(first:match('\\label{mark2tex:footnote:%x+:1}'))
		unit.assertEquals(first:match('\\label{([^}]+)}') == second:match('\\label{([^}]+)}'), false)
		unit.assertEquals(output('MARKTWOTEXFOOTNOTE1END ^[note]'), 'MARKTWOTEXFOOTNOTE1END \\footnote{note}')
		unit.assertEquals(output('Text[^a#}].\n\n[^a#}]: Safe.'), 'Text\\footnote{\\label{fn:1}Safe.}.')
	end

	function test_footnotes_state_does_not_leak_between_conversions()
		output('Text[^a].\n\n[^a]: Defined.')
		unit.assertEquals(parse('Text[^a].').warnings[1].kind, 'undefined')
	end

	function test_footnotes_code_blocks_inside_definition_are_safe_tex()
		unit.assertEquals(output('Text[^a].\n\n[^a]: Code:\n\n    ```\n    a_b & c\n    ```'),
			'Text\\footnote{\\label{fn:1}Code:\n\n\\texttt{a\\_b \\& c\n}}.')
	end

	function test_footnotes_file_paths_namespace_identical_contents()
		local write = require('mark2tex.write')
		local config = require('mark2tex.default_config')
		local source = 'Text[^a].\n\n[^a]: Note.'
		local first = write(parse(source, config, 'first.md'), config)
		local second = write(parse(source, config, 'second.md'), config)
		unit.assertEquals(first:match('\\label{([^}]+)}') == second:match('\\label{([^}]+)}'), false)
	end
end
