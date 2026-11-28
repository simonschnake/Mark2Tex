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

	-- A stray special character stays literal without dropping the formatting
	-- of the rest of the paragraph.
	function test_robustness_stray_character_keeps_formatting()
		unit.assertEquals(output("`}`\\"), "\\texttt{\\}}\\")
		unit.assertEquals(output("**bold** and `code` \\"), "\\textbf{bold} and \\texttt{code} \\")
		unit.assertEquals(output("**bold** and *open"), "\\textbf{bold} and *open")
	end
end
