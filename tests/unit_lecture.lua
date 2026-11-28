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
	function test_columns_and_tikz_script_caption()
		local markdown = assert(files.read_file("examples/cli/waermeleitung.md"))
		local slides = render(markdown, "slides")
		local handout = render(markdown, "handout")
		assert(slides:find("\\begin{columns}", 1, true))
		assert(not handout:find("\\begin{column", 1, true))
		assert(not slides:find("Temperaturverlauf", 1, true))
		assert(handout:find("Temperaturverlauf", 1, true))
		for _, output in ipairs({ slides, handout }) do
			assert(output:find("width=12em,max width=\\linewidth", 1, true))
			assert(output:find("\\begin{tikzpicture}", 1, true))
		end
	end

	function test_variant_blocks_and_local_slide_boundary()
		local markdown = [=[
## Common

::: script
### ScriptHeading
:::: instructor
InstructorScript
::::
AfterInner
:::

::: slides

## SlideHeading

:::

SharedBody

::: student
StudentText
:::

::: instructor
InstructorText

## InstructorContinuation

RestrictedBody
:::
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
			{ "Intro\n:::", "Markdown:2: unexpected" },
			{ "Intro\r\n::: script", "Markdown:2: unclosed div" },
		}) do
			local ok, err = pcall(render, example[1])
			assertions.assertEquals(ok, false)
			assertions.assertEquals(err:sub(1, #example[2]), example[2])
		end
		local output = render("Before\n\n```markdown\n:::\n```\n")
		assertions.assertEquals(count(output, ":::"), 1)
	end

	function test_div_warnings_keep_nested_content_and_source_locations()
		local markdown = [=[
<!-- a
multiline comment -->
::: {.slides .instructor}
::: slides
Restricted
::::
:::
]=]
		local config = assert(mark2tex.resolve_config({ profile = "slides", audience = "instructor" }))
		local ast = parse(markdown, config, "lecture.md")
		assertions.assertEquals(#ast.warnings, 2)
		assertions.assertEquals(ast.warnings[1].category, "div-fence")
		assertions.assertEquals(ast.warnings[1].line, 4)
		assertions.assertEquals(ast.warnings[2].line, 6)
		assertions.assertEquals(count(write(lecture.structure(ast, config), config), "Restricted"), 1)
		assertions.assertEquals(count(render(markdown, "slides"), "Restricted"), 0)
		assertions.assertEquals(count(render(markdown, "handout", nil, { audience = "instructor" }), "Restricted"), 0)
	end

	function test_titleless_separator_and_slide_only_heading()
		local markdown = "## Start\n\nFirst.\n\n---\n\nSecond.\n\n::: slides\n## Third\n:::\n\nThird body."
		local slides = render(markdown, "slides")
		assertions.assertEquals(count(slides, "\\begin{frame}"), 3)
		assertions.assertEquals(count(slides, "\\frametitle"), 2)
		assertions.assertEquals(count(slides, "\\frametitle{Third}[^}]*Third body"), 1)
		local handout = render(markdown, "handout")
		assertions.assertEquals(count(handout, "\\subsection"), 1)
		assertions.assertEquals(count(handout, "Second%.%s*Third body"), 1)
	end

	function test_divs_filter_list_items_and_footnote_definitions()
		local markdown = [=[
1. Visible
::: instructor
2. Restricted
:::
3. Also visible

Shared.[^source]

::: instructor
[^source]: Hidden definition
:::
]=]
		local student = render(markdown)
		local instructor = render(markdown, nil, nil, { audience = "instructor" })
		assertions.assertEquals(count(student, "\\begin{enumerate}"), 1)
		assertions.assertEquals(count(instructor, "\\begin{enumerate}"), 1)
		assertions.assertEquals(count(student, "Restricted"), 0)
		assertions.assertEquals(count(instructor, "Restricted"), 1)
		assertions.assertEquals(count(student, "Hidden definition"), 0)
		assertions.assertEquals(count(instructor, "\\footnote{\\label{[^}]+}Hidden definition}"), 1)
	end

	function test_compact_divs_keep_paragraph_boundaries()
		local markdown = "Before.\n::: instructor\nRestricted.\n:::\nAfter."
		local student = render(markdown)
		local instructor = render(markdown, nil, nil, { audience = "instructor" })
		assertions.assertEquals(count(student, "Before%.\n\nAfter%."), 1)
		assertions.assertEquals(count(instructor, "Before%.\n\nRestricted%.\n\nAfter%."), 1)
	end

	function test_old_comment_directives_are_ordinary_comments()
		local markdown = [=[
## Visible

<!-- instructor: begin -->
Still visible. <!-- dozent -->
<!-- end -->

<!-- footer: Old footer -->
<!-- note: Old note -->

---

<!-- title: Old title -->
<!-- mark2tex: slide-title="Legacy title" -->

Continuation.
]=]
		local output = render(markdown, "slides")
		assertions.assertEquals(count(output, "Still visible"), 1)
		assertions.assertEquals(count(output, "%% instructor: begin"), 1)
		assertions.assertEquals(count(output, "\\frametitle"), 1)
		assertions.assertEquals(count(output, "\\SlideFooter"), 0)
		assertions.assertEquals(count(output, "\\note{"), 0)
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

::: footer
Quelle & Kontext
:::

Frage.

. . .

::: instructor
Erste Zeile der Lösung
mit Fußnote.[^quelle]
:::

- Sichtbarer Punkt
::: instructor
- Interner Punkt
  mit Fortsetzung.
:::

Sichtbarer Verweis.[^quelle]

::: notes
Erste Zeile
zweite Zeile.
:::
::: notes
Weitere Notiz.
:::

::: slides
## Weiter
:::

Nächster Inhalt.

[^quelle]: Fußnotentext.
]=]
		local slides = render(markdown:gsub("\n", "\r\n"), "slides")
		local dozent = render(markdown, "slides", "dozent")
		local handout = render(markdown, "handout")
		assertions.assertEquals(count(slides, "Lösung"), 0)
		assertions.assertEquals(count(slides, "Interner Punkt"), 0)
		assertions.assertEquals(count(slides, "\\footnote{"), 1)
		assertions.assertEquals(count(slides, "\\footref{"), 0)
		assertions.assertEquals(count(slides, "\\SlideFooter{Quelle \\& Kontext}"), 1)
		assertions.assertEquals(count(slides, "\\frametitle{Weiter}"), 1)
		assertions.assertEquals(count(slides, "Erste Zeile zweite Zeile"), 1)
		assertions.assertEquals(count(dozent, "Lösung"), 1)
		assertions.assertEquals(count(dozent, "Interner Punkt"), 1)
		assertions.assertEquals(count(handout, "Interner Punkt"), 0)
		assertions.assertEquals(count(handout, "Vortragsnotiz:"), 2)
		assertions.assertEquals(count(handout, "Quelle \\& Kontext"), 1)
	end

	function test_lecture_directives_in_code_are_literal()
		local markdown = "## Code\n\n" .. string.rep("\x60", 3)
			.. "\n::: footer\nAusgabe\n:::\n" .. string.rep("\x60", 3) .. "\n"
			.. "\n\\begin{verbatim}\n::: instructor\n\\end{verbatim}\n"
		local slides = render(markdown, "slides")
		assertions.assertEquals(count(slides, "\\SlideFooter"), 0)
		assertions.assertEquals(count(slides, "Ausgabe"), 1)
		assertions.assertEquals(count(slides, "::: instructor"), 1)
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
