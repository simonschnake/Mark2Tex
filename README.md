# Mark2TeX

Mark2TeX compiles Markdown to PDF from the command line and reads Markdown-like
fragments inside LuaLaTeX documents. Both use the same Lua converter.

The focus is on a LaTeX-friendly writing style for scientific documents, not
on full Markdown or CommonMark compatibility. If compatibility with common
Markdown tools happens as a side effect, that is welcome, but it is not the
primary project goal.

## Compile Markdown to PDF

Install the Python package from this repository with `python -m pip install .`.
The command requires Python 3.9 or newer and a TeX installation with
`latexmk`, `texlua`, LuaLaTeX, Beamer, STIX Two and Latin Modern. The wheel
bundles Mark2TeX's Lua and TeX sources and its document templates.
The TeX Live and Overleaf archives can still be used independently with
`\usepackage{mark2tex}` and `\mdinput`.

```sh
mark2tex lecture.md                                                    # lecture.pdf
mark2tex lecture.md --format handout --writing-margin                    # lecture-handout.pdf
mark2tex lecture.md --format slides                                      # lecture-slides.pdf
mark2tex lecture.md --format slides --dozent                             # lecture-slides-dozent.pdf
mark2tex lecture.md --format slides --speaker-notes                      # lecture-slides-speaker-notes.pdf
```

Pass `-o path/to/file.pdf` to choose a destination. Relative TeX graphics
paths are resolved from the Markdown file's directory. Use `--title`,
`--author`, and `--date` for metadata. The author and date default to empty.
Text and handout builds support `--paper a4|letter`, `--toc`, and
`--numbered`. Handouts and slides accept `--slide-level` (default 2).
For raw TeX learning blocks, `\begin{Lernblock}{Title}` begins a section
or a slide. The starred form continues the previous section in text and
handouts.

Use `--watch` to build immediately and rebuild when the Markdown source
changes. `--watch-delay` sets the quiet period before rebuilding (default
0.5 seconds). `--cache` reuses successful builds from `.mark2tex-cache/`
in the working directory and checks the TeX recorder's inputs, including
graphics. `--cache-format` also caches the static preamble and retries with
a fresh regular build if it cannot use the format. A failed build preserves
the last PDF and prints the build directory. `--log`, `--log-file`,
`--verbose`, and `--keep-build` expose build diagnostics.

### Migrate from md2pdf

Replace `md2pdf datei.md` with `mark2tex datei.md`. The format flags and
their PDF filenames carry over. The neutral STIX layout is the default.
Pass `--author` to supply an author. Use md2pdf for existing documents that
still require its institution-specific layouts.

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

## What Mark2TeX is for

Mark2TeX is useful when larger chunks of text are more convenient to write in a
Markdown-like syntax, while the target document should still remain a real
LaTeX document. LaTeX commands, mathematical expressions, citations, and raw
LaTeX environments are therefore intentionally allowed inside the Markdown.

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
- ordered lists with `1.` or `1)`
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
[PDF](<unterlagen/Auswahl der Inhalte.pdf>)
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
> **Beobachtungen** → Daten → erkennbare Zusammenhänge → Modell → Anwendung auf neue Fälle
>
> Eine zweite Zeile mit *Inline-Formatierung*.
```

Mark2TeX removes the markers, parses the content as Markdown blocks, and
wraps the complete block in a LaTeX `quote` environment. This supports paragraphs,
tables, lists, fenced code, and nested blockquotes (`> > ...`), including the
usual inline formatting and math. Tables use the available width inside the quote.
Blank lines inside a blockquote must be written as `>` lines. Lazy continuation
lines without a `>` marker are not supported.

```md
> **Tafel:** Zweispaltig sichern.
>
> | Daten | Modell |
> | --- | --- |
> | Eingabe $x$ | Parameter $w,b$ |
> | Zielwert $y$ | Vorhersage $\hat y=wx+b$ |
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

## LaTeX usage

In a LuaLaTeX document, Mark2TeX is loaded as a package:

```tex
\documentclass{article}
\usepackage{mark2tex}

\begin{document}

\mdinput{content.md}

\end{document}
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

## Installation

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

## Vorlesung als Handout und Folien

Beide LuaLaTeX-Hauptdateien lesen dieselbe Markdown-Datei mit
`\mdinput{lecture.md}`. Für ein Handout in der Dokumentklasse
`article` lädst du Mark2Tex mit
`\usepackage[profile=handout,slide-level=2]{mark2tex}`. In der
Dokumentklasse `beamer` wählst du
`\usepackage[profile=slides,slide-level=2]{mark2tex}`.
Das klassische Verhalten ist die Voreinstellung. Die Optionen stehen
in Lua als `profile` und `slide_level` zur Verfügung.

- Linksbündige Überschriften auf der gewählten Ebene beginnen eine betitelte Folie.
  Höherrangige Überschriften ergeben Abschnittstitelfolien, tiefere
  erscheinen als Zwischenüberschriften innerhalb der Folie. Im Handout
  bestimmt die übliche `header`-Option den Satz der Überschriften.
- Eine Zeile aus mindestens drei Bindestrichen mit Leerzeilen davor
  und danach beginnt eine Fortsetzungsfolie. Im Handout setzt sich der
  Abschnitt mit einem Absatzabstand fort.
- `<!-- mark2tex: slide-title="Eigener Titel" -->` kann direkt nach
  einem solchen Trenner als erster Block stehen. Der einzeilige
  Klartexttitel erscheint ausschließlich in Mark2Tex-Folien.
- `. . .` als eigener Absatz zwischen Inhaltsblöcken erzeugt eine
  Beamer-Einblendung. Im Handout erscheinen die Inhaltsblöcke hintereinander.

Überschriften, Bindestrichtrenner und Pausen orientieren sich an
[Pandocs Beamer-Ausgabe](https://pandoc.org/MANUAL.html#structuring-the-slide-show).
In einer gewöhnlichen Markdown-Vorschau sind Pausen als drei Punkte
und Trenner als horizontale Linien sichtbar.

Das [Schwarzloch-Beispiel](tests/lecture/lecture.md) hat eine
[A4-Vorlage](tests/lecture/handout.tex) und eine
[16:9-Vorlage](tests/lecture/folien.tex). Beide nutzen
[den gemeinsamen Satzstil](tests/lecture/satzstil.tex) mit 155 mm
Lesespalte und 12,75 bp Grundschrift. `make -j2 latex-lecture`
erstellt und prüft die PDFs in `tests/lecture/`. Der Test verwendet
LuaLaTeX, Beamer, STIX Two und Popplers `pdfinfo` und `pdftotext`.
Der Satzstil verwendet installierte STIX-Two-Schriften und Latin Modern
Sans für Titel.

### Steuerkommentare für Vorlesungen

- `<!-- footer: Skriptabschnitt 5 -->` setzt den Footer der aktuellen Folie.
  Pro Folie gilt der erste Footer.
- `<!-- note: Erst das Rohr einzeichnen. -->` setzt eine Vortragsnotiz.
  Mehrzeilige Notizen sind möglich. Mehrere Notizen erscheinen in Quellreihenfolge.
- `<!-- dozent -->` am Ende eines Absatzes oder Listenpunkts markiert ihn samt
  seinen Fortsetzungszeilen für die Dozentenfassung.
- `<!-- title: Fortsetzung -->` direkt nach `---` setzt den Titel der
  Fortsetzungsfolie. Die bisherige längere Titelsyntax bleibt gültig.

Mark2TeX setzt markierte Inhaltsblöcke in die Umgebung `MarkTwoTeXDozent`.
Die Standarddefinition lässt den Inhalt sichtbar. Ein Beamer-Template kann die
Umgebung mit `\begin{visibleenv}<0>` und `\end{visibleenv}` definieren, damit
der Inhalt unsichtbar gesetzt wird und seine Fläche behält. In der Mark2TeX-CLI verwenden
reguläre Folien diese Beamer-Definition. Dozentenfolien und Handout zeigen
den Inhalt. Footer und Vortragsnotizen stehen im Handout am Ende des
jeweiligen Folienabschnitts.

Bei abgesetzten Gleichungen steht der Kommentar hinter dem schließenden
`$$ <!-- dozent -->` oder `\] <!-- dozent -->`. Bei Tabellen und Codeblöcken
kann der Kommentar direkt in der nächsten Zeile stehen.

Beamer-Themes mit Folienfooter stellen `\SlideFooter{…}` bereit. Für Dokumente,
die diese Angabe ausblenden sollen, genügt `\providecommand{\SlideFooter}[1]{}`.
Beamer zeigt Vortragsnotizen mit `\setbeameroption{show notes}` auf eigenen
Seiten. Diese Einstellung lässt sich mit beiden Folienfassungen verwenden.

Mehrere Absätze, Gleichungen oder eine Liste lassen sich gemeinsam markieren:

    <!-- dozent:begin -->

    Die Druckkraft folgt aus

    $$
    F = p A.
    $$

    <!-- dozent:end -->

Beide Marker stehen auf eigenen Zeilen innerhalb derselben Folie.
Überschriften, Folienwechsel, Einblendmarken und Folienmetadaten bleiben
außerhalb des Blocks. Ein unvollständiges Paar bleibt ein gewöhnlicher
Kommentar. Der Inhalt bleibt in diesem Fall sichtbar.
