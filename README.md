# marktex

marktex is a LuaLaTeX package for Markdown-like text fragments inside
LaTeX documents. It reads `.md` files during LaTeX compilation, translates
the currently supported dialect to LaTeX, and inputs the generated `.tex`
file back into the document.

The focus is on a LaTeX-friendly writing style for scientific documents, not
on full Markdown or CommonMark compatibility. If compatibility with common
Markdown tools happens as a side effect, that is welcome, but it is not the
primary project goal.

## What marktex is for

marktex is useful when larger chunks of text are more convenient to write in a
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
- inline math with `$...$`
- LaTeX commands such as `\alpha`, `\cref{...}`, or `\textit{...}`
- unordered lists with `-`, `*`, or `+`
- ordered lists with `1.` or `1)`
- some nested list forms
- single citations such as `@key`
- Pandoc-style citation groups such as `[@key1; @key2]`
- raw LaTeX environments with `\begin{...}` and `\end{...}`
- LaTeX environments inside `$$ ... $$`, with the dollar wrappers removed

The output is LaTeX-like:

- headings are mapped by default to `\section`, `\subsection`,
  `\subsubsection`, `\paragraph`, and `\subparagraph`
- `@key` becomes `\cite{key}` by default
- `[@key1; @key2]` becomes `\parencite{key1, key2}` by default
- lists become `itemize` or `enumerate`
- normal code blocks are emitted as `verbatim`
- `tex` code blocks are emitted unchanged as LaTeX
- normal text is not automatically escaped for LaTeX special characters

## Deliberately unsupported

marktex is not a full Markdown converter. In particular, do not expect the
following to work like they do in CommonMark, Pandoc, or GitHub Markdown:

- tables in Markdown syntax
- links and images in Markdown syntax
- blockquotes
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

In a LuaLaTeX document, marktex is loaded as a package:

```tex
\documentclass{article}
\usepackage{marktex}

\begin{document}

\mdinput{content.md}

\end{document}
```

`\mdinput{...}` converts the given Markdown file to LaTeX and inputs the
generated file via `\input`. Generated files are placed in the `marktex/`
directory by default.

For chapter-like files there is also:

```tex
\mdinclude{chapter.md}
```

This inputs the generated file via `\include`.

Important: marktex requires LuaLaTeX. Other engines such as pdfLaTeX are not
supported.

## Installation

You can build a TeX Live package archive from this repository:

```sh
make dist
```

This produces `dist/marktex.tar.xz`. The archive contains a TDS structure and
an embedded `tlpobj`, so it can be installed directly with `tlmgr`:

```sh
tlmgr install --file dist/marktex.tar.xz
```

To check the archive without installing it, use:

```sh
make tlmgr-install-dry-run
```

The package installs `marktex.sty` under `tex/latex/marktex/` and the Lua
implementation under `scripts/marktex/`.

### Overleaf

Overleaf usually does not allow project-local installation via `tlmgr`.
For Overleaf there is therefore a separate bundle:

```sh
make overleaf-zip
```

This produces `dist/marktex-overleaf.zip`. That archive is not a TeX Live
installation; instead it contains the files in a form that can be uploaded
directly into an Overleaf project:

```text
marktex.sty
marktex.lua
src/marktex/*.lua
README.md
LICENSE
```

In Overleaf, `marktex.sty` and `marktex.lua` must live at the top level of the
project; the `src/marktex/` directory must remain relative to them. In the
Overleaf menu, the compiler must be set to LuaLaTeX. After that, the package
can be used like it is locally:

```tex
\usepackage{marktex}

\begin{document}
\mdinput{content.md}
\end{document}
```

## Configuration

If a `marktex_config.lua` file exists in the working directory, it is used when
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

  save_dir = "generated-marktex",
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

  save_dir = "marktex",
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

- `src/marktex/` contains the Lua implementation.
- `marktex.lua` is the compatibility entry point.
- `marktex.sty` integrates marktex into LuaLaTeX.
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
