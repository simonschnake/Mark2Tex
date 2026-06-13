# marktex

marktex ist ein LuaLaTeX-Paket fuer Markdown-nahe Textfragmente in
LaTeX-Dokumenten. Es liest `.md`-Dateien waehrend der LaTeX-Kompilierung,
uebersetzt den aktuell unterstuetzten Dialekt nach LaTeX und bindet das
generierte `.tex` wieder in das Dokument ein.

Der Fokus liegt auf einer LaTeX-nahen Schreibweise fuer wissenschaftliche
Dokumente, nicht auf vollstaendiger Markdown- oder CommonMark-Kompatibilitaet.
Falls sich Kompatibilitaet mit ueblichen Markdown-Tools ergibt, ist das ein
willkommenes Nebenprodukt, aber kein primaeres Projektziel.

## Wofuer marktex gedacht ist

marktex ist nuetzlich, wenn groessere Textteile angenehmer in einer
Markdown-aehnlichen Syntax geschrieben werden sollen, das Zieldokument aber
weiterhin ein echtes LaTeX-Dokument bleibt. LaTeX-Kommandos, mathematische
Ausdruecke, Zitationen und rohe LaTeX-Umgebungen duerfen deshalb bewusst im
Markdown vorkommen.

Ein typischer Ausschnitt:

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

Daraus wird LaTeX-Ausgabe wie:

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

## Unterstuetzter Markdown-Subset

Der aktuelle Parser unterstuetzt bewusst nur einen kleinen, getesteten Subset:

- Ueberschriften mit `#`, `##`, `###`, ...
- Absatzerkennung fuer normalen Text
- kursiv mit `*text*` oder `_text_`
- fett mit `**text**` oder `__text__`
- durchgestrichen mit `~~text~~`
- Inline-Code mit Backticks, z.B. `` `code` ``
- fenced code blocks mit drei Backticks
- fenced `tex`-Bloecke als rohe LaTeX-Ausgabe
- Inline-Math mit `$...$`
- LaTeX-Kommandos wie `\alpha`, `\cref{...}` oder `\textit{...}`
- ungeordnete Listen mit `-`, `*` oder `+`
- geordnete Listen mit `1.` oder `1)`
- einige verschachtelte Listenformen
- einzelne Zitationen wie `@key`
- Pandoc-aehnliche Zitationsgruppen wie `[@key1; @key2]`
- rohe LaTeX-Umgebungen mit `\begin{...}` und `\end{...}`
- LaTeX-Umgebungen innerhalb von `$$ ... $$`, wobei die Dollar-Wrapper entfernt werden

Die Ausgabe ist LaTeX-nah:

- Ueberschriften werden standardmaessig auf `\section`, `\subsection`,
  `\subsubsection`, `\paragraph` und `\subparagraph` gemappt.
- `@key` wird standardmaessig zu `\cite{key}`.
- `[@key1; @key2]` wird standardmaessig zu `\parencite{key1, key2}`.
- Listen werden zu `itemize` oder `enumerate`.
- normale Code-Bloecke werden als `verbatim` ausgegeben.
- `tex`-Code-Bloecke werden unveraendert als LaTeX ausgegeben.
- normaler Text wird nicht automatisch fuer LaTeX-Sonderzeichen escaped.

## Bewusst nicht unterstuetzt

marktex ist kein vollstaendiger Markdown-Konverter. Insbesondere sollte man
aktuell nicht davon ausgehen, dass folgende Bereiche wie in CommonMark, Pandoc
oder GitHub Markdown funktionieren:

- Tabellen in Markdown-Syntax
- Links und Bilder in Markdown-Syntax
- Blockquotes
- HTML-Bloecke
- Footnotes
- Task lists
- Referenz-Links
- beliebige Escaping-Regeln
- vollstaendig spezifizierte Edge Cases fuer verschachtelte Inline-Elemente
- hilfreiche Parserdiagnosen mit Zeile und Spalte

Wenn solche Konstrukte gebraucht werden, ist die bevorzugte Schreibweise im
Moment meistens direktes LaTeX, etwa als `tex`-Codeblock oder rohe
LaTeX-Umgebung.

## LaTeX-Nutzung

In einem LuaLaTeX-Dokument wird marktex als Paket geladen:

```tex
\documentclass{article}
\usepackage{marktex}

\begin{document}

\mdinput{content.md}

\end{document}
```

`\mdinput{...}` konvertiert die angegebene Markdown-Datei nach LaTeX und bindet
die generierte Datei per `\input` ein. Die generierten Dateien landen
standardmaessig im Verzeichnis `marktex/`.

Fuer kapitelartige Dateien gibt es ausserdem:

```tex
\mdinclude{chapter.md}
```

Das bindet die generierte Datei per `\include` ein.

Wichtig: marktex benoetigt LuaLaTeX. Andere Engines wie pdfLaTeX werden vom
Paket nicht unterstuetzt.

## Installation

Aus dem Repository kann ein TeX-Live-Paketarchiv gebaut werden:

```sh
make dist
```

Das erzeugt `dist/marktex.tar.xz`. Das Archiv enthaelt eine TDS-Struktur und
ein eingebettetes `tlpobj`, sodass es direkt mit `tlmgr` installiert werden
kann:

```sh
tlmgr install --file dist/marktex.tar.xz
```

Zum Pruefen ohne Installation gibt es:

```sh
make tlmgr-install-dry-run
```

Das Paket installiert `marktex.sty` unter `tex/latex/marktex/` und die
Lua-Implementierung unter `scripts/marktex/`.

### Overleaf

Overleaf erlaubt normalerweise keine projektlokale Installation per `tlmgr`.
Fuer Overleaf gibt es deshalb ein eigenes Bundle:

```sh
make overleaf-zip
```

Das erzeugt `dist/marktex-overleaf.zip`. Dieses Archiv ist keine
TeX-Live-Installation, sondern enthaelt die Dateien in einer Form, die direkt
in ein Overleaf-Projekt hochgeladen werden kann:

```text
marktex.sty
marktex.lua
src/marktex/*.lua
README.md
LICENSE
```

In Overleaf muessen `marktex.sty` und `marktex.lua` auf der obersten Ebene des
Projekts liegen; der Ordner `src/marktex/` muss relativ dazu erhalten bleiben.
Im Overleaf-Menue muss als Compiler LuaLaTeX ausgewaehlt werden. Danach kann
das Paket wie lokal verwendet werden:

```tex
\usepackage{marktex}

\begin{document}
\mdinput{content.md}
\end{document}
```

## Konfiguration

Wenn im Arbeitsverzeichnis eine `marktex_config.lua` liegt, wird sie beim Laden
des Pakets verwendet. Damit koennen die wichtigsten LaTeX-Mappings angepasst
werden:

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

Die Default-Konfiguration ist:

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

## Beispiele fuer LaTeX-nahe Markdown-Dateien

Inline-LaTeX bleibt erhalten:

```md
The corrected energy is $E_\mathrm{corr}$ and the result is shown in
\cref{fig:energy-response}.
```

Zitationen koennen knapp geschrieben werden:

```md
The detector model follows @detector-note and the calibration strategy follows
[@calibration-paper; @run2-performance].
```

Komplexere LaTeX-Bloecke koennen direkt im Markdown stehen:

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

Auch rohe Umgebungen ohne Code-Fence werden erkannt:

```md
\begin{align}
  p(x) &= p(z)\left.\dv{f^{-1}}{x}\right|_{x=x_0}
\end{align}
```

## Entwicklung

Die Projektstruktur:

- `src/marktex/` enthaelt die Lua-Implementierung.
- `marktex.lua` ist der Kompatibilitaets-Einstiegspunkt.
- `marktex.sty` bindet marktex in LuaLaTeX ein.
- `tests/` enthaelt Fixture-Tests, Unit-Tests und einen LaTeX-Smoke-Test.
- `scripts/` enthaelt Entwicklungshelfer.

Regression-Tests ausfuehren:

```sh
make test
```

Einzelne Fixtures ausfuehren:

```sh
lua tests/run.lua tests/header.test tests/lists.test
```

LuaLaTeX-Integration testen:

```sh
make latex-smoke
```

Der Test-Runner nutzt `luaunit`, wenn es installiert ist. Falls `luaunit`
fehlt, verwendet er einen kleinen eingebauten Assertion-Runner, damit Parser-
und Writer-Fixtures weiterhin geprueft werden koennen.

## Abhaengigkeiten

Zur Laufzeit werden aktuell Lua-Module fuer LPeg, Dateisystemzugriffe und MD5
verwendet:

- `lpeg`
- `lfs`
- `md5`

Fuer die LaTeX-Integration wird eine funktionierende LuaLaTeX-Installation
benoetigt. `luaunit` ist fuer die Tests optional.
