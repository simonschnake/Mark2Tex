# Mark2TeX

Mark2TeX is a LuaLaTeX package for Markdown-like text fragments inside
LaTeX documents. It reads `.md` files during LaTeX compilation, translates
the currently supported dialect to LaTeX, and inputs the generated `.tex`
file back into the document.

The focus is on a LaTeX-friendly writing style for scientific documents, not
on full Markdown or CommonMark compatibility. If compatibility with common
Markdown tools happens as a side effect, that is welcome, but it is not the
primary project goal.

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

## Supported Markdown subset

The current parser intentionally supports only a small, tested subset:

- headings with `#`, `##`, `###`, ...
- paragraph detection for normal text
- italics with `*text*` or `_text_`
- bold with `**text**` or `__text__`
- strikethrough with `~~text~~`
- inline code with backticks, e.g. `` `code` ``
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
- normal text is not automatically escaped for LaTeX special characters

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

Markdown syntax inside math is not interpreted. A raw LaTeX environment wrapped
in `$$...$$` or `\\[...\\]` is emitted as the environment alone, avoiding
invalid nested display math. Display delimiters in pipe-table cells are kept
literal and reported as warnings; inline math is supported there.

Unclosed, empty, or mismatched math delimiters are preserved literally and
produce a `math-delimiter` warning during file conversion. A delimiter
preceded by an odd number of backslashes is treated as escaped. Code spans,
fenced code blocks, and `tex` blocks are never parsed as math.

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

- links and images in Markdown syntax
- HTML blocks
- footnotes
- task lists
- reference links
- arbitrary escaping rules
- fully specified edge cases for nested inline elements
- helpful parser diagnostics with line and column numbers

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

If a `mark2tex_config.lua` file exists in the working directory, it is used when
the package is loaded. This lets you adjust the main LaTeX mappings:

```lua
return {
  header = {
    "chapter",
    "section",
    "subsection",
    "subsubsection",
    "paragraph",
  },

  citation = "autocite",
  paren_citation = "parencite",

  save_dir = "generated-mark2tex",
}
```

The default configuration is:

```lua
return {
  header = {
    "section",
    "subsection",
    "subsubsection",
    "paragraph",
    "subparagraph"
  },

  paren_citation = "parencite",
  citation = "cite",

  save_dir = "mark2tex",
}
```

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
