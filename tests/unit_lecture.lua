local mark2tex = require("mark2tex")
local parse = require("mark2tex.parse")
local write = require("mark2tex.write")
local lecture = require("mark2tex.lecture")
local files = require("mark2tex.fileutils")

local source = "tests/lecture/lecture.md"

local function render(markdown, profile, audience)
	local config = assert(mark2tex.resolve_config({ profile = profile, slide_audience = audience }))
	local ast = parse(markdown, config)
	return write(profile and lecture.structure(ast, config) or ast, config)
end

local function count(text, pattern)
	local _, matches = text:gsub(pattern, "")
	return matches
end

return function(assertions)
	function test_lecture_classic_output_matches_original()
		assertions.assertEquals(render(assert(files.read_file(source))),
			assert(files.read_file("tests/lecture/classic.expected.tex")))
	end

	function test_lecture_profiles_share_structure()
		local markdown = assert(files.read_file(source))
		local slides = render(markdown:gsub("\n", "\r\n"), "slides")
		local handout = render(markdown, "handout")
		assertions.assertEquals(count(slides, "\\begin{frame}"), 3)
		assertions.assertEquals(count(slides, "\\pause"), 1)
		assertions.assertEquals(count(slides, "\\frametitle{Die Geometrie"), 1)
		assertions.assertEquals(count(handout, "\\subsection{"), 2)
		assertions.assertEquals(count(handout, "Die Geometrie"), 0)
		assertions.assertEquals(count(handout, "\\pause"), 0)
	end

	function test_lecture_markers_in_protected_blocks_and_empty_frames()
		local markdown = [=[
---

## A

```markdown
## Code

---

. . .
```

> ## Quote
>
> ---
>
> . . .

### Detail

---

---

## B

. . .

Text

. . .

---
]=]
		local slides = render(markdown, "slides")
		assertions.assertEquals(count(slides, "\\begin{frame}"), 2)
		assertions.assertEquals(count(slides, "\\begin{frame}%[t,fragile%]"), 1)
		assertions.assertEquals(count(slides, "\\pause"), 0)
		assertions.assertEquals(count(slides, "\\textbf{Detail}"), 1)
	end

	function test_lecture_annotations_and_audience()
		local markdown = [=[
## Frage

<!-- footer: Quelle & Kontext -->

Frage.

. . .

Erste Zeile der Lösung
mit Fußnote.[^quelle] <!-- dozent -->

- Sichtbarer Punkt
- Interner Punkt
  mit Fortsetzung. <!-- dozent -->

Sichtbarer Verweis.[^quelle]

<!-- note: Erste Zeile
zweite Zeile. -->
<!-- note: Weitere Notiz. -->

---

<!-- title: Weiter -->

Nächster Inhalt.

[^quelle]: Fußnotentext.
]=]
		local slides = render(markdown:gsub("\n", "\r\n"), "slides")
		local dozent = render(markdown, "slides", "dozent")
		local handout = render(markdown, "handout")
		assertions.assertEquals(count(slides, "Lösung"), 1)
		assertions.assertEquals(count(slides, "Interner Punkt"), 1)
		assertions.assertEquals(count(slides, "\\footnote{"), 1)
		assertions.assertEquals(count(slides, "\\footref{"), 1)
		assertions.assertEquals(count(slides, "\\SlideFooter{Quelle \\& Kontext}"), 1)
		assertions.assertEquals(count(slides, "\\frametitle{Weiter}"), 1)
		assertions.assertEquals(count(slides, "Erste Zeile zweite Zeile"), 1)
		assertions.assertEquals(count(dozent, "Lösung"), 1)
		assertions.assertEquals(count(dozent, "Interner Punkt"), 1)
		assertions.assertEquals(count(handout, "Interner Punkt"), 1)
		assertions.assertEquals(count(handout, "Vortragsnotiz:"), 2)
		assertions.assertEquals(count(handout, "Quelle \\& Kontext"), 1)
	end

	function test_lecture_dozent_blocks_keep_space_and_pauses()
		local markdown = "## Frage\n\nSichtbar.\n\n. . .\n\nIntern. <!-- dozent -->\n"
		assertions.assertEquals(count(render(markdown, "slides"), "\\pause"), 1)
		assertions.assertEquals(count(render(markdown, "slides", "dozent"), "\\pause"), 1)
	end

	function test_lecture_dozent_display_math_is_wrapped()
		local markdown = "## Formel\n\n$$\nx = y\n$$ <!-- dozent -->\n\nDanach.\n"
		for _, profile in ipairs({ "slides", "handout" }) do
			local tex = render(markdown, profile)
			assertions.assertEquals(count(tex, "\\begin{MarkTwoTeXDozent}"), 1)
			assertions.assertEquals(count(tex, "\\end{MarkTwoTeXDozent}"), 1)
			assertions.assertEquals(count(tex, "x = y"), 1)
		end
	end

	function test_lecture_dozent_comment_group()
		local markdown = [=[
## Frage

<!-- dozent:begin -->

Lösung.[^quelle]

$$
x = y
$$

1. Erster Schritt
2. Zweiter Schritt

<!-- dozent:end -->

Danach.

[^quelle]: Quelle.
]=]
		for _, profile in ipairs({ "slides", "handout" }) do
			local tex = render(markdown, profile)
			assertions.assertEquals(count(tex, "\\begin{MarkTwoTeXDozent}"), 1)
			assertions.assertEquals(count(tex, "\\end{MarkTwoTeXDozent}"), 1)
			assertions.assertEquals(count(tex, "Lösung%.\\footnote{"), 1)
			assertions.assertEquals(count(tex, "x = y"), 1)
			assertions.assertEquals(count(tex, "\\end{enumerate}%s*\\par%s*\\end{MarkTwoTeXDozent}"), 1)
			assertions.assertEquals(count(tex, "\\end{MarkTwoTeXDozent}%s*Danach%."), 1)
		end
	end

	function test_lecture_dozent_group_does_not_cross_frames()
		local markdown = "## A\n\n<!-- dozent:begin -->\n\nText.\n\n## B\n\n<!-- dozent:end -->"
		local tex = render(markdown, "slides")
		assertions.assertEquals(count(tex, "\\begin{frame}"), 2)
		assertions.assertEquals(count(tex, "\\begin{MarkTwoTeXDozent}"), 0)
		assertions.assertEquals(count(tex, "Text%."), 1)
	end

	function test_lecture_directives_in_code_are_literal()
		local markdown = "## Code\n\n" .. string.rep("\x60", 3)
			.. "\n<!-- footer: Im Code -->\nAusgabe <!-- dozent -->\n" .. string.rep("\x60", 3) .. "\n"
		local slides = render(markdown, "slides")
		assertions.assertEquals(count(slides, "\\SlideFooter"), 0)
		assertions.assertEquals(count(slides, "Ausgabe"), 1)
	end

	function test_lecture_output_paths_and_validation()
		local classic = assert(mark2tex.get_output_path(source))
		local slides = assert(mark2tex.get_output_path(source, { profile = "slides" }))
		local handout = assert(mark2tex.get_output_path(source, { profile = "handout" }))
		assertions.assertEquals(slides, (classic:gsub("%.tex$", "-slides-2.tex")))
		assertions.assertEquals(assert(mark2tex.get_output_path(source, { profile = "slides", slide_audience = "dozent" })), (classic:gsub("%.tex$", "-slides-2-dozent.tex")))
		assertions.assertEquals(mark2tex.get_output_path(source, { profile = "handout", slide_audience = "dozent" }), nil)
		assertions.assertEquals(handout, (classic:gsub("%.tex$", "-handout-2.tex")))
		assertions.assertEquals(mark2tex.get_output_path(source, { profile = "slides", slide_level = 7 }), nil)
	end
end
