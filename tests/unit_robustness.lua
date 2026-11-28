-- Regressions found by tests/fuzz.lua.
local helpers = require("tests.helpers")

local guard = "\\ifcsname hyper@normalise\\endcsname\\else\\PackageError{mark2tex}{Markdown links require hyperref}{Load \\string\\usepackage{hyperref} in the document preamble.}\\fi\n"

local function output(source)
	return (helpers.transform(source):gsub("^\n+", ""):gsub("\n+$", ""))
end

return function(unit)
	-- Placeholders of protected constructs must never become part of a
	-- citation key or a TeX command name.
	function test_robustness_constructs_after_citation_marker()
		unit.assertEquals(output("@[Simon](https://x.org)"), guard .. "@\\href{\\detokenize{https://x.org}}{Simon}")
		unit.assertEquals(output("@<https://x.org>"), guard .. "@\\url{\\detokenize{https://x.org}}")
		unit.assertEquals(output("@key^[n]"), "\\cite{key}\\footnote{n}")
		unit.assertEquals(output("@$x$"), "@$x$")
	end

	function test_robustness_constructs_after_tex_command()
		unit.assertEquals(output("\\LaTeX^[note]"), "\\LaTeX\\footnote{note}")
		unit.assertEquals(output("\\LaTeX<https://x.org>"), guard .. "\\LaTeX\\url{\\detokenize{https://x.org}}")
		unit.assertEquals(output("x\\\n<https://x.org>"), guard .. "x\\\n\\url{\\detokenize{https://x.org}}")
	end

	-- Every pass delimits code, math and TeX by the shared rules in spans.tl.
	function test_robustness_code_spans_follow_one_rule()
		unit.assertEquals(output("``a ` b`` and `c`"), "\\texttt{a \\textasciigrave{} b} and \\texttt{c}")
		-- An unmatched run is literal and the rest is parsed as usual.
		unit.assertEquals(output("`open **bold** and $x$"), "`open \\textbf{bold} and $x$")
		unit.assertEquals(output("`[l](u)` and `^[n]` stay code"), "\\texttt{[l](u)} and \\texttt{\\textasciicircum{}[n]} stay code")
	end

	function test_robustness_fences()
		unit.assertEquals(output("~~~\n$x$ <!-- c -->\n~~~"), "\\begin{verbatim}\n$x$ <!-- c -->\n\\end{verbatim}")
		unit.assertEquals(output("````\n```\n````"), "\\begin{verbatim}\n```\n\\end{verbatim}")
	end

	function test_robustness_tex_commands_and_links()
		unit.assertEquals(output("\\ref{a}[x](u)"), guard .. "\\ref{a}\\href{\\detokenize{u}}{x}")
		unit.assertEquals(output("\\cite[p. 3]{k} and \\f{\\[}"), "\\cite[p. 3]{k} and \\f{\\[}")
		unit.assertEquals(output("@key\\` x"), "\\cite{key}\\` x")
	end

	function test_robustness_non_links_keep_destination_literal()
		unit.assertEquals(output("[a `{`](b c"), "[a \\texttt{\\{}](b c")
		unit.assertEquals(output("[a [b](https://e.org/x%20y) c](d e"), guard .. "[a \\href{\\detokenize{https://e.org/x}\\%\\detokenize{20y}}{b} c](d e")
		unit.assertEquals(output("see ![a](my_file.png) here"), "see ![a](my\\_file.png) here")
		unit.assertEquals(output("[](^["), "[](\\textasciicircum{}[")
	end

	-- A percent sign in prose is a percent sign, not a TeX comment.
	function test_robustness_percent_in_text()
		unit.assertEquals(output("**50% faster** & more"), "\\textbf{50\\% faster} \\& more")
		unit.assertEquals(output("`50%` and $x % y$ stay raw"), "\\texttt{50\\%} and $x % y$ stay raw")
	end

	-- A stray special character stays literal without dropping the formatting
	-- of the rest of the paragraph.
	function test_robustness_stray_character_keeps_formatting()
		unit.assertEquals(output("`}`\\"), "\\texttt{\\}}\\")
		unit.assertEquals(output("**bold** and `code` \\"), "\\textbf{bold} and \\texttt{code} \\")
		unit.assertEquals(output("**bold** and *open"), "\\textbf{bold} and *open")
	end
end
