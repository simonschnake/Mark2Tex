# Mark2TeX

Mark2TeX lets me write scientific material in Markdown and use LaTeX wherever I need it. The same Lua converter supports two ways of working.

1. **Markdown chapters inside a LaTeX project.** The main document controls the class, bibliography, layout, and chapter order. Each chapter can live in a Markdown file, with TeX equations, citations, commands, and environments alongside the prose.
2. **A PDF from a standalone Markdown file.** The command-line tool supplies a consistent layout or uses a template of my choice. From one lecture source, I can build a handout and presentation slides. Both can have an instructor edition with teaching notes or solutions.

## How it got here

I wrote the first version for my PhD thesis. It was a large LaTeX project, and I wanted to write each chapter as a Markdown file while keeping all the possibilities of TeX. Embedding Markdown in the existing document let me keep the preamble and the typesetting decisions I had already made. The first parser handled just the syntax my thesis needed. The LaTeX package `markdown` was an inspiration, though its design choices did not fit the way I wanted to write.

I kept using Mark2TeX after the thesis. Its Markdown support grew as I needed new constructs in real documents. The way I develop it has changed as well. I wrote the original thesis version myself. Since then, AI has written an increasing share of the code.

The CLI came later, when most of my everyday writing had become individual documents. I wanted to start with one Markdown file and get a consistently formatted PDF without setting up a LaTeX project each time. Lectures are the current focus of that workflow. I want to explain a derivation in the script, present it in stages on slides, and keep a solution in the instructor edition, while editing the shared equations and prose only once.

## Compatibility and scope

I am currently the only user, so my day-to-day work shapes what gets built. There is no fixed roadmap. Other people's use cases could change the direction. I want to keep writing new LaTeX projects with Markdown chapters, so direct integration remains a core use case. My thesis is a concrete compatibility benchmark for the package. Lecture profiles and slide layout options are opt-in.

I use Mark2TeX daily and maintain automated parser, LaTeX, and CLI tests. Security has received less attention. Source files can contain executable TeX, and custom templates are complete LaTeX documents compiled with LuaLaTeX. I use this workflow for trusted inputs. Compiling a stranger's document calls for an isolated environment with restricted file access.

## Usage and reference

- [Include Markdown in a LaTeX project](#latex-usage)
- [Compile a standalone PDF or use a custom template](#compile-markdown-to-pdf)
- [Prepare lecture scripts and slides](#lectures-as-handouts-and-slides)
- [Look up supported Markdown syntax](#supported-markdown-subset)

## LaTeX usage

With the package installed, put these two files in the same directory.

`main.tex`

```tex
\documentclass{article}
\usepackage{mark2tex}

\begin{document}

\mdinput{content.md}

\end{document}
```

`content.md`

```md
# Introduction

This chapter combines **Markdown prose** with TeX math such as $E = mc^2$.
```

Build `main.pdf` with:

```sh
latexmk -lualatex main.tex
```

`\mdinput{...}` converts the given Markdown file to LaTeX and inputs the
generated file via `\input`. Generated files are placed in the `mark2tex/`
directory by default.

For chapter-like files there is also:

```tex
\mdinclude{chapter.md}
```

This inputs the generated file via `\include`.

To compile only selected Markdown includes, use `\mdincludeonly` in the
preamble with the same Markdown paths passed to `\mdinclude`:

```tex
\mdincludeonly{introduction.md,conclusion.md}
```

Like LaTeX's `\includeonly`, excluded files retain their auxiliary data. They
are not converted or registered as inputs during that run. An empty
`\mdincludeonly{}` excludes all `\mdinclude` files. `\mdinput` is unaffected.

Both `\mdinput` and `\mdinclude` register their Markdown source files with
LuaTeX's recorder. Build tools such as `latexmk` can therefore detect Markdown
changes from the generated `.fls` file and rebuild the document automatically.

Important: Mark2TeX requires LuaLaTeX. Other engines such as pdfLaTeX are not
supported.

## Install the LaTeX package

You can build a TeX Live package archive from this repository:

```sh
make dist
```

This produces `dist/mark2tex.tar.xz`. The archive contains a TDS structure and
an embedded `tlpobj`, so it can be installed directly with `tlmgr`:

```sh
tlmgr install --file dist/mark2tex.tar.xz
```

To check the archive without installing it, use:

```sh
make tlmgr-install-dry-run
```

The package installs `mark2tex.sty` under `tex/latex/mark2tex/` and the Lua
implementation under `scripts/mark2tex/`.

### Overleaf

Overleaf usually does not allow project-local installation via `tlmgr`.
For Overleaf there is therefore a separate bundle:

```sh
make overleaf-zip
```

This produces `dist/mark2tex-overleaf.zip`. That archive is not a TeX Live
installation; instead it contains the files in a form that can be uploaded
directly into an Overleaf project:

```text
mark2tex.sty
mark2tex.lua
src/mark2tex/*.lua
README.md
LICENSE
```

In Overleaf, `mark2tex.sty` and `mark2tex.lua` must live at the top level of the
project; the `src/mark2tex/` directory must remain relative to them. In the
Overleaf menu, the compiler must be set to LuaLaTeX. After that, the package
can be used like it is locally:

```tex
\usepackage{mark2tex}

\begin{document}
\mdinput{content.md}
\end{document}
```

## Configuration

Configure Mark2TeX directly when loading the package:

```tex
\usepackage[
  citation=autocite,
  paren-citation=parencite,
  save-dir=generated-mark2tex,
  header={chapter,section,subsection,subsubsection,paragraph}
]{mark2tex}
```

| Option | Default | Meaning |
| --- | --- | --- |
| `citation` | `cite` | Command used for `@key` |
| `paren-citation` | `parencite` | Command used for `[@key]` and citation groups |
| `save-dir` | `mark2tex` | Directory for generated LaTeX files |
| `header` | `{section,subsection,subsubsection,paragraph,subparagraph}` | Heading commands, from level 1 upward |
| `verbose` | `false` | Log files when they are converted; use `verbose` or `verbose=true` to enable |

Command names are written without a leading backslash. Load any package that
provides your chosen citation commands separately. Enclose the comma-separated
`header` list in braces; it replaces the entire mapping. Deeper headings use
the last command in the list. Omitted or empty string options use their defaults.

The package no longer reads `mark2tex_config.lua`. Move existing settings into
package options, using `save-dir` for `save_dir`, `paren-citation` for
`paren_citation`, and a braced comma-separated list for `header`.

## Compile Markdown to PDF

From the repository checkout, install the CLI with `uv` in an isolated tool
environment:

```sh
uv tool install .
```

You can also install the Python package into your current environment with
`python -m pip install .`.
The command requires Python 3.9 or newer and a TeX installation with
`latexmk`, `texlua`, LuaLaTeX, Beamer, STIX Two and Latin Modern. The wheel
bundles Mark2TeX's Lua and TeX sources and its document templates.
The TeX Live and Overleaf archives can still be used independently with
`\usepackage{mark2tex}` and `\mdinput`.

```sh
mark2tex notes.md                                                      # notes.pdf
mark2tex lecture.md --format handout --writing-margin                    # lecture-handout.pdf
mark2tex lecture.md --format handout --instructor                        # lecture-handout-dozent.pdf
mark2tex lecture.md --format slides                                      # lecture-slides.pdf
mark2tex lecture.md --format slides --dozent                             # lecture-slides-dozent.pdf
mark2tex lecture.md --format slides --speaker-notes                      # lecture-slides-speaker-notes.pdf
```

Pass `-o path/to/file.pdf` to choose a destination. Relative TeX graphics
paths are resolved from the Markdown file's directory. Use `--title`,
`--author`, and `--date` for metadata. The author and date default to empty.
With the built-in template, text and handout builds support
`--paper a4|letter`, `--toc`, and `--numbered`. Handouts and slides accept
`--slide-level` (default 2). Slides also accept `--h1 section|frame|hide`
and `--speaker-notes`. Use `--instructor` or its alias `--dozent` in any
format to select the instructor edition and add `-dozent` to the default
filename.

Mark2TeX converts Markdown citations into LaTeX citation commands. The CLI
disables automatic BibTeX and Biber runs. To build a bibliography from a
`.bib` file, use the LaTeX package workflow with your bibliography setup.

For raw TeX learning blocks, the built-in templates define
`\begin{Lernblock}{Title}` to begin a section or a slide. The starred form
continues the previous section in text and handouts.

Use `--watch` to build immediately and rebuild when the Markdown source
changes. `--watch-delay` sets the quiet period before rebuilding (default
0.5 seconds). `--cache` reuses successful builds from `.mark2tex-cache/`
in the working directory and checks the TeX recorder's inputs, including
graphics. `--cache-format` also caches the static preamble and retries with
a fresh regular build if it cannot use the format. A failed build preserves
the last PDF and prints the build directory. `--log`, `--log-file`,
`--verbose`, and `--keep-build` expose build diagnostics.

LuaLaTeX reuses its font cache in `.mark2tex-cache/tex-cache/` in the working
directory, including in watch mode and without `--cache`. An explicit
`TEXMFCACHE` overrides this location. Each build uses a local copy and
publishes updated cache files atomically for parallel builds.

### Use a complete LaTeX template

The commented examples show how a template can read CLI options and turn
them into LaTeX settings. Both use the same [sample Markdown](examples/cli/beispiel.md).

| Output | Template | CLI format |
| --- | --- | --- |
| Text | [Article template](examples/cli/text.tex) | `text` (default) |
| Lecture handout | [Article template](examples/cli/text.tex) | `handout` |
| Lecture slides | [Beamer template](examples/cli/vorlesung.tex) | `slides` |

Run these commands from the repository root:

```sh
mark2tex examples/cli/beispiel.md --template examples/cli/text.tex --title "Wärmelehre"
mark2tex examples/cli/beispiel.md --template examples/cli/text.tex --format handout --title "Wärmelehre" --writing-margin
mark2tex examples/cli/beispiel.md --template examples/cli/vorlesung.tex --format slides --title "Wärmelehre"
```


```sh
mark2tex lecture.md --format slides --template path/to/lecture.tex \
  --title "Lecture 5" --title-image images/cover.png --dozent --speaker-notes
```

The UTF-8 `.tex` template supplies the document class, preamble, fonts, theme,
and body. Paths passed to `--template` and `--title-image` are relative to
the working directory. Title images can be PNG, JPEG, or PDF.
Load the generated `mark2tex-template.tex` before using the interface. Insert
the converted Markdown with `\MarkTwoTeXContent` inside the document body.

```latex
\documentclass[aspectratio=169]{beamer}
\input{mark2tex-template.tex}
\usepackage{mark2tex}
\providecommand{\SlideFooter}[1]{}
\MarkTwoTeXHideDozent
\ifMarkTwoTeXSpeakerNotes
  \setbeameroption{show notes on second screen=right}
\fi
\title{\MarkTwoTeXTitle}
\author{\MarkTwoTeXAuthor}
\date{\MarkTwoTeXDate}
\ifMarkTwoTeXHasTitleImage
  \titlegraphic{\includegraphics[height=1.5cm]{\MarkTwoTeXTitleImage}}
\fi
\begin{document}
\ifMarkTwoTeXHasTitle
  \begin{frame}\titlepage\end{frame}
\fi
\MarkTwoTeXContent
\end{document}
```

- `\MarkTwoTeXTitle`, `\MarkTwoTeXAuthor`, and `\MarkTwoTeXDate` contain escaped text.
  `\ifMarkTwoTeXHasTitle` indicates whether `--title` was supplied.
- `\MarkTwoTeXFormat`, `\MarkTwoTeXSlideLevel`, `\MarkTwoTeXLanguage`,
  `\MarkTwoTeXPaper`, and `\MarkTwoTeXFontSize` expose the CLI settings.
  Font size is empty by default. Load the template data before
  `\documentclass` if the class options depend on these settings.
- `\ifMarkTwoTeXDozent`, `\ifMarkTwoTeXSpeakerNotes`, `\ifMarkTwoTeXNoFooter`,
  `\ifMarkTwoTeXWritingMargin`, `\ifMarkTwoTeXNumbered`, and `\ifMarkTwoTeXTOC`
  let the template apply those presentation choices.
- `\ifMarkTwoTeXHasTitleImage` indicates whether `--title-image` supplied an
  image. Pass `\MarkTwoTeXTitleImage` to the template's image command.

The template applies layout flags itself. If the Markdown uses raw TeX
environments such as `Lernblock`, define them in the template.

The Markdown and template directories are both searched for relative input
files, with the Markdown directory first. Set `TEXINPUTS` for additional
class, theme, or asset directories. The build cache checks the template,
title image, and recorded TeX dependencies. Watch mode monitors the Markdown,
main template, and title image. `--cache-format` also precompiles the template
prefix if it contains a line `% mark2tex runtime`. Keep the generated template
data, runtime Lua initialization, and document body after that marker. Without
the marker, the CLI uses the regular build and PDF cache.

### Offline installation and standalone conversion

To build a wheel for offline installation, run
`python -m pip wheel --no-deps -w dist .` from the checkout. Install that
wheel with `python -m pip install dist/mark2tex-*.whl`. The installed-wheel
integration test uses a temporary working directory and needs Poppler:

```sh
python tests/cli_integration.py "$(command -v mark2tex)"
```

The standalone `texlua scripts/convert.lua INPUT OUTPUT_DIR` entry point
prints the generated TeX fragment path. It accepts optional Lua profile
settings such as `profile=slides slide_level=2`. An explicit `document_id`
keeps generated footnote label prefixes stable across source edits.

## Lectures as handouts and slides

Both LuaLaTeX documents read the same Markdown file with
`\mdinput{lecture.md}`. For an `article` handout, load
`\usepackage[profile=handout,slide-level=2]{mark2tex}`. For Beamer slides,
load `\usepackage[profile=slides,slide-level=2]{mark2tex}`. The standard
conversion is the default. Direct Lua calls use `profile` and `slide_level`.

- Unindented headings at the selected level start a titled slide. Higher-level
  headings create section title slides. Lower-level headings appear as
  subheadings within a slide. In handouts, `header` controls heading formatting.
- A line of at least three hyphens with a blank line on each side starts a
  continuation slide. In handouts, it adds paragraph spacing.
- A continuation slide started by a separator has no title. For a titled
  slide whose heading is omitted from the handout, put a heading at the
  slide level inside a `slides` block.
- A standalone `. . .` paragraph creates a Beamer overlay. In handouts, the
  blocks appear in sequence.

Headings, separators, and pauses follow the conventions of
[Pandoc's Beamer output](https://pandoc.org/MANUAL.html#structuring-the-slide-show).
A standard Markdown preview displays the pauses as three dots and the
separators as horizontal rules.

The [black hole example](tests/lecture/lecture.md) includes an
[A4 template](tests/lecture/handout.tex) and a
[16:9 template](tests/lecture/folien.tex). The
[shared style](tests/lecture/satzstil.tex) sets a 155 mm text column and
12.75 bp body type, with STIX Two fonts and Latin Modern Sans for titles.
Run `make -j2 latex-lecture` to build and check the PDFs in `tests/lecture/`.
The test uses LuaLaTeX, Beamer, STIX Two, and Poppler's `pdfinfo` and `pdftotext`.

### Content visibility and top-level headings

Use `::: script` for standard and handout output, `::: slides` for slides,
`::: instructor` for the instructor edition, and `::: student` for the
regular edition. Close each block with a line containing only colons.
Nested blocks require every enclosing condition to match. The attribute
form `::: {.slides .instructor}` combines both conditions in one block.

Use matching fence lengths and add one colon at each nesting level.
An unmatched length or a nested fence that is no longer than its parent
produces a warning. Missing and extra closing fences stop conversion with
a line number. Mark2TeX filters these blocks before laying out slides or
resolving footnotes. Excluded content takes up no space.

Use `--instructor` or `--dozent` in the CLI. Direct Lua calls and package
options use `audience=instructor`. The default is `audience=student`.

Use `--h1 section|frame|hide` to control top-level headings on slides.
The default `section` follows the slide-level rule. `frame` uses the heading
as the title of a regular content slide. `hide` drops the heading, keeps
its content, and skips the slide break. Direct Lua calls and package options
use `h1`. The handout preserves the heading levels of visible content.

```markdown
## Energy balance

The balance follows from the first law of thermodynamics.

::: script
### Derivation

:::: instructor
Review the sign convention here.
::::
:::

::: slides
## Derivation
:::

For a closed system, $\Delta U = Q + W$.
```

### Footers and speaker notes

```markdown
::: footer
Handout section 5
:::

::: notes
Draw the pipe first.
:::
```

The first footer on a slide takes precedence. Notes can span multiple lines
and appear in source order. In handouts, both annotations appear at the end
of the current slide section. A Beamer theme can use `\SlideFooter{…}`
to display footers. Define `\providecommand{\SlideFooter}[1]{}` to suppress them.

The colon fences and attribute notation follow Pandoc's Markdown syntax.
Mark2TeX defines the meaning of the visibility and annotation classes.
Earlier HTML comment directives are handled as ordinary comments.

## Markdown and LaTeX in one source

A typical snippet:

````md
# Motivation

The calibration follows @calibration and uses $\alpha < 0.1$ as threshold.

For the final selection we use:

- **nominal** reconstruction
- systematic variations with \cref{sec:systematics}
- the response model from [@response; @detector]

```tex
\begin{align}
  y &= f(x) \\
    &= x^2 + \alpha
\end{align}
```
````

This turns into LaTeX output such as:

```tex
\section{Motivation}

The calibration follows \cite{calibration} and uses $\alpha < 0.1$ as threshold.

For the final selection we use:

\begin{itemize}
\item \textbf{nominal} reconstruction
\item systematic variations with \cref{sec:systematics}
\item the response model from \parencite{response, detector}
\end{itemize}

\begin{align}
  y &= f(x) \\
    &= x^2 + \alpha
\end{align}
```

HTML comments remain in the generated `.tex` source as `%` comments and do
not appear in the PDF. Both single-line and multiline comments are supported:

```md
<!-- This is a comment -->
<!--
TODO:
Complete this section later.
-->
```

Comments can also occur within text. Each comment line receives a `%` prefix,
and following text resumes on a new source line so it stays visible. Markdown
and LaTeX inside comments are not parsed. An unclosed comment extends to the
end of the input. Comment syntax inside backtick code spans and fenced code
blocks stays literal.

## Supported Markdown subset

The current parser intentionally supports only a small, tested subset:

- headings with `#`, `##`, `###`, ...
- horizontal rules with `---` on its own line
- paragraph detection for normal text
- HTML comments (`<!-- ... -->`), preserved as LaTeX `%` comments
- italics with `*text*` or `_text_`
- bold with `**text**` or `__text__`
- strikethrough with `~~text~~`
- inline code with backticks, e.g. `` `code` ``; LaTeX special characters stay literal
- inline links (`[label](target)`), URL autolinks, and email autolinks
- fenced code blocks with three backticks
- fenced `tex` blocks as raw LaTeX output
- blockquotes with `>`
- inline math with `$...$` or `\\(...\\)`
- display math with `$$...$$` or `\\[...\\]`
- pipe tables, including inline formatting and math inside cells
- LaTeX commands such as `\alpha`, `\cref{...}`, or `\textit{...}`
- unordered lists with `-`, `*`, or `+`
- ordered lists with `1.`, `1)`, or lowercase letters followed by a closing
  parenthesis and whitespace, as in `a) First item`. The first marker sets
  the starting number or letter (for example, `4.` or `c)`). Subsequent
  items count consecutively. Switching between alphabetic and numeric
  markers at the same indentation starts a new list.
- some nested list forms
- single citations such as `@key`
- Pandoc-style citation groups such as `[@key1; @key2]`, including locators such as `[@key, p. 433]`
- referenced footnotes (`[^name]` with `[^name]: ...`) and inline footnotes (`^[...]`)
- raw LaTeX environments with `\begin{...}` and `\end{...}`
- raw LaTeX environments with optional `$$ ... $$` or `\\[ ... \\]` wrappers

The output is LaTeX-like:

- headings are mapped by default to `\section`, `\subsection`,
  `\subsubsection`, `\paragraph`, and `\subparagraph`
- `@key` becomes `\cite{key}` by default
- `[@key1; @key2]` becomes `\parencite{key1, key2}` by default
- `[@key, p. 433]` becomes `\parencite[p. 433]{key}` by default
- lists become `itemize` or `enumerate`
- blockquotes become LaTeX `quote` environments
- pipe tables become full-width `tabularx` environments with wrapping cells and automatic compact/text column selection; delimiter colons preserve alignment
- normal code blocks are emitted as `verbatim`
- `tex` code blocks are emitted unchanged as LaTeX
- `$$...$$` is normalized to `\\[...\\]`; `\\[...\\]` is kept in that form
- normal text is mostly kept as written; ampersands are escaped for LaTeX

### Links

Load `\usepackage{hyperref}` in your document preamble when using Markdown
links. Mark2TeX reports a package error if it is missing.

```md
[Website](https://example.org/page?x=1&y=2#part)
[PDF](<materials/Selected readings.pdf>)
[Section](#grundlagen)
<https://example.org/a_b>
<a_b@example.org>
```

Inline labels support formatting, code, and inline math. Destinations stay
opaque to Markdown parsing. Parentheses may be balanced or escaped; angle
brackets allow spaces in a destination. Optional quoted or parenthesized titles
are parsed but do not appear in the output. URI spaces become `%20`; local file
paths retain their spaces. A target beginning with `#` refers to an existing
LaTeX label through `\hyperref`.

Reference links, images, and nested links are unsupported. Bare URLs require
angle brackets to become autolinks. Links inside code, math, and raw LaTeX
arguments are left alone.

### Footnotes

Use a named definition or write a short footnote directly in the text:

```md
Text with a footnote[^note] and an inline note^[An *inline* footnote.].
Another reference to the same note[^note].

[^note]: A footnote with **formatting**, `code`, $x^2$, and @citation.
    Continue a line with four spaces or a tab.

    Indented paragraphs and lists are supported too.
```

Definitions may appear before or after their references. Identifiers are
case-sensitive, contain no whitespace or brackets, and are scoped to one
Markdown input file, including its blockquotes. Unused definitions are omitted;
for duplicate definitions the first wins and a `footnote` warning is emitted.
The first reference emits a LaTeX `\footnote`; later references use `\footref`
with the same number. Compile twice to resolve repeated references. Numbering
uses the document's normal LaTeX footnote counter.

Notes support inline formatting, code, math, citations, links, and raw LaTeX.
Referenced definitions also support paragraphs and lists. Fenced code in a
definition is rendered as literal `\texttt` text, with ordinary TeX whitespace,
because a `verbatim` environment cannot be used inside a footnote argument.
Links still require `hyperref`. Footnote markers work in paragraphs, list items,
blockquotes, and pipe-table cells. Nested footnotes and footnotes in headings
or link labels are unsupported: their markers are displayed literally and
reported as warnings. Undefined references and unclosed markers also produce
warnings; their carets are escaped for safe LaTeX output. Code, math, and raw
LaTeX arguments are not scanned for footnote syntax. Direct `\footnote{...}`
commands remain unchanged and use LaTeX syntax inside their arguments.

### Mathematics

Mathematics is a Mark2TeX extension; CommonMark itself does not define math
delimiters. The supported forms and their output are:

| Input | Context | Output |
| --- | --- | --- |
| `$x^2$` | inline text, headings, lists, blockquotes, and table cells | unchanged |
| `\\(x^2\\)` | inline text, headings, lists, blockquotes, and table cells | unchanged |
| `$$x^2$$` | display block, including lists and blockquotes | `\\[x^2\\]` |
| `\\[x^2\\]` | display block, including lists and blockquotes | unchanged |
| `\\begin{align}...\\end{align}` | raw LaTeX block | unchanged |

Markdown syntax inside math is not interpreted. LaTeX sub-environments that do
not open math mode themselves, such as `aligned`, `cases`, and matrix
environments, remain inside the normalized `\\[...\\]` display block. A
self-contained display environment such as `align`, `gather`, or `equation` is
emitted as that environment alone, avoiding an invalid nested display mode.
Display delimiters in pipe-table cells are kept literal and reported as
warnings; inline math is supported there.

Unclosed, empty, or mismatched math delimiters are preserved literally and
produce a `math-delimiter` warning during file conversion. Unclosed or
mismatched LaTeX environments produce a `latex-environment` warning. These
warnings include line and column when the position can be determined. A
delimiter preceded by an odd number of backslashes is treated as escaped. Code
spans, fenced code blocks, and `tex` blocks are never parsed as math.

### Blockquotes

A blockquote is written by starting every quoted line with `>`:

```md
> **Observations** → data → patterns → model → application to new cases
>
> A second line with *inline formatting*.
```

Mark2TeX removes the markers, parses the content as Markdown blocks, and
wraps the complete block in a LaTeX `quote` environment. This supports paragraphs,
tables, lists, fenced code, and nested blockquotes (`> > ...`), including the
usual inline formatting and math. Tables use the available width inside the quote.
Blank lines inside a blockquote must be written as `>` lines. Lazy continuation
lines without a `>` marker are not supported.

```md
> **Board:** Organize the results in two columns.
>
> | Data | Model |
> | --- | --- |
> | Input $x$ | Parameter $w,b$ |
> | Target $y$ | Prediction $\hat y=wx+b$ |
```

## Robustness rules

Mark2TeX only transforms complete, unambiguous Markdown constructs. An
underscore in ordinary text (for example `snake_case`) is kept literally;
italics require a matching closing underscore or asterisk. Likewise, an
unclosed fenced code block or an unclosed `\begin{...}` environment is emitted
as ordinary text instead of being partially converted. Paragraphs immediately
before or after a list remain separate paragraphs.

## Deliberately unsupported

Mark2TeX is not a full Markdown converter. In particular, do not expect the
following to work like they do in CommonMark, Pandoc, or GitHub Markdown:

- images in Markdown syntax
- HTML blocks other than comments
- task lists
- reference links
- arbitrary escaping rules
- fully specified edge cases for nested inline elements

If you need such constructs, the preferred approach at the moment is usually
direct LaTeX, for example as a `tex` code block or a raw LaTeX environment.

## Examples of LaTeX-friendly Markdown files

Inline LaTeX is preserved:

```md
The corrected energy is $E_\mathrm{corr}$ and the result is shown in
\cref{fig:energy-response}.
```

Citations can be written concisely:

```md
The detector model follows @detector-note and the calibration strategy follows
[@calibration-paper; @run2-performance].
```

For a parenthetical citation with a page or section locator, place the locator
after a comma. It is passed as the optional argument of `\parencite`:

```md
The original proposal is discussed in [@Turing1950, p. 433].
```

Pipe tables accept the usual alignment markers in their delimiter row and can
contain the supported inline Markdown and LaTeX syntax:

```md
| Quantity | Value | Comment |
| :------- | :---: | ------: |
| Energy   | $E$   | **fit** |
| Events   | 42    | @sample |
```

This produces a `tabularx` spanning `\linewidth`, with left-, center-, and
right-aligned cells respectively. Font size stays unchanged. `mark2tex.sty`
automatically loads `array`, `tabularx`, and `booktabs`; standalone converter
output requires these packages in your document preamble.

Column selection is automatic and includes the header: a column is compact if
its maximum cell length is at most 18 characters and its average at most 10.
Markdown formatting does not count toward length; Unicode characters count once.
Math and raw TeX use source length as a conservative approximation.

In mixed tables, compact columns use wrapping `p{...}` cells. Their widths are
computed from their longest cell and capped at half an equal column share of
the usable width (after intercolumn padding). Text columns share the remaining
space equally using `X`. If every column is compact, all columns use `X`, so
there is always a flexible column and no unused width. There are no weighted
text columns or per-table settings.

Tables use `\toprule`, `\midrule`, and `\bottomrule`, without outer column
padding or a `center` wrapper. Paragraph spacing separates tables from nearby
text. `\linewidth` also respects narrower containers such as minipages.

This handles ordinary prose by wrapping instead of scaling. Unbreakable words,
URLs, or long formulas can still overflow, and very many columns can become too
narrow. `tabularx` does not split tables across pages. For these cases, or for
captions and custom widths, use a raw LaTeX table.

More complex LaTeX blocks can be written directly in Markdown:

````md
```tex
\begin{table}[h]
\centering
\caption{Nominal binning}
\label{tab:binning}
\begin{tabular}{l|c}
\toprule
Layer & bins \\
\midrule
1 & 32 \\
\bottomrule
\end{tabular}
\end{table}
```
````

Raw environments without a code fence are also recognized:

```md
\begin{align}
  p(x) &= p(z)\left.\dv{f^{-1}}{x}\right|_{x=x_0}
\end{align}
```

## Development

Project layout:

- `src/mark2tex/` contains the Lua implementation.
- `mark2tex.lua` is the compatibility entry point.
- `mark2tex.sty` integrates Mark2TeX into LuaLaTeX.
- `tests/` contains fixture tests, unit tests, and a LaTeX smoke test.
- `scripts/` contains development helpers.

Run regression tests:

```sh
make test
```

Run individual fixtures:

```sh
lua tests/run.lua tests/header.test tests/lists.test
```

Test LuaLaTeX integration:

```sh
make latex-smoke
```

The test runner uses `luaunit` if it is installed. If `luaunit` is missing, it
falls back to a small built-in assertion runner so that parser and writer
fixtures can still be checked.

## Dependencies

At runtime, the project currently uses Lua modules for LPeg, filesystem access,
and MD5:

- `lpeg`
- `lfs`
- `md5`

A working LuaLaTeX installation is required for the LaTeX integration.
`luaunit` is optional for tests.
