local mark2tex = require("mark2tex")
local parse = require("mark2tex.parse")
local write = require("mark2tex.write")
local lecture = require("mark2tex.lecture")
local files = require("mark2tex.fileutils")

local source = "tests/lecture/lecture.md"

local function render(markdown, profile, audience, options)
	local config = options or {}
	config.profile, config.slide_audience = profile, audience
	config = assert(mark2tex.resolve_config(config))
	local ast = parse(markdown, config)
	return write(profile and lecture.structure(ast, config) or ast, config)
end

local function count(text, pattern)
	local _, matches = text:gsub(pattern, "")
	return matches
end

return function(assertions)
	function test_variant_blocks_and_local_slide_boundary()
		local markdown = [=[
## Common

<!-- script: begin -->
### ScriptHeading
<!-- instructor: begin -->
InstructorScript
<!-- end -->
AfterInner
<!-- end -->

<!-- slides: begin -->

---

<!-- title: SlideHeading -->

<!-- end -->

SharedBody

<!-- student: begin -->
StudentText
<!-- end -->

<!-- instructor: begin -->
InstructorText

---

<!-- title: InstructorContinuation -->

RestrictedBody
<!-- end -->
]=]
		for _, profile in ipairs({ "text", "handout", "slides" }) do
			for _, audience in ipairs({ "student", "instructor" }) do
				local actual_profile = profile ~= "text" and profile or nil
				local output = render(markdown, actual_profile, nil, { audience = audience })
				local slides, instructor = profile == "slides", audience == "instructor"
				assertions.assertEquals(count(output, "ScriptHeading"), slides and 0 or 1)
				assertions.assertEquals(count(output, "SlideHeading"), slides and 1 or 0)
				assertions.assertEquals(count(output, "InstructorScript"), not slides and instructor and 1 or 0)
				assertions.assertEquals(count(output, "AfterInner"), slides and 0 or 1)
				assertions.assertEquals(count(output, "StudentText"), instructor and 0 or 1)
				assertions.assertEquals(count(output, "InstructorText"), instructor and 1 or 0)
				assertions.assertEquals(count(output, "SharedBody"), 1)
				assertions.assertEquals(count(output, "\\frametitle{InstructorContinuation}"), slides and instructor and 1 or 0)
				assertions.assertEquals(count(output, "RestrictedBody"), instructor and 1 or 0)
				if slides then
					assertions.assertEquals(count(output, "\\begin{frame}"), instructor and 3 or 2)
				end
			end
		end
	end

	function test_variant_markers_report_errors_and_preserve_code()
		for _, example in ipairs({
			{ "Intro\n<!-- end -->", "Markdown:2: unexpected" },
			{ "Intro\r\n<!-- script: begin -->", "Markdown:2: unclosed script" },
		}) do
			local ok, err = pcall(render, example[1])
			assertions.assertEquals(ok, false)
			assertions.assertEquals(err:sub(1, #example[2]), example[2])
		end
		local output = render("Before\n\n```markdown\n<!-- end -->\n```\n")
		assertions.assertEquals(count(output, "<!%-%- end %-%->"), 1)
	end

	function test_h1_slide_modes_and_heading_levels()
		local markdown = "# Top\n\nLead\n\n## Middle\n\n### Detail\n\nBody\n"
		for _, mode in ipairs({ "section", "frame", "hide" }) do
			local output = render(markdown, "slides", nil, { h1 = mode })
			assertions.assertEquals(count(output, "\\begin{frame}"), mode == "section" and 3 or 2)
			assertions.assertEquals(count(output, "\\frametitle{Top}"), mode == "hide" and 0 or 1)
			local immediate = render("# Top\n\n## Middle\n\nBody", "slides", nil, { h1 = mode })
			assertions.assertEquals(count(immediate, "\\begin{frame}"), mode == "hide" and 1 or 2)
		end
		local deeper = render(markdown, "slides", nil, { slide_level = 3 })
		assertions.assertEquals(count(deeper, "\\frametitle{Detail}"), 1)
		local first = render(markdown, "slides", nil, { slide_level = 1 })
		assertions.assertEquals(count(first, "\\begin{frame}"), 1)
		local script = render(markdown, "handout")
		assertions.assertEquals(count(script, "\\section{Top}"), 1)
		assertions.assertEquals(count(script, "\\subsection{Middle}"), 1)
		assertions.assertEquals(count(script, "\\subsubsection{Detail}"), 1)
	end

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
