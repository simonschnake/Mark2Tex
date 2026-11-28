# Mark2TeX Projektstatus

Stand: 28. November 2026. Die genaue Syntax und Installation stehen in README.md.

## Aktueller Stand

Mark2TeX ist ein LuaLaTeX-Paket für einen bewusst LaTeX-nahen Markdown-Subset,
ergänzt um eine Python-CLI, die aus einer einzelnen Markdown-Datei ein PDF baut.
Die Implementierung ist in Module für Block- und Inline-Parsing, Mathematik,
Links, Fußnoten, Fenced Divs, Vorlesungslayout, Kommentare, Diagnosen,
AST-Knoten, Ausgabe und Konvertierung aufgeteilt.

Unterstützt werden Überschriften, Absätze, horizontale Linien, Formatierungen,
Inline-Code, fenced Code und rohe TeX-Blöcke, Listen mit Verschachtelung,
Blockquotes, Pipe-Tabellen, Zitationen, Mathematik, rohe LaTeX-Umgebungen,
Links und Fußnoten. HTML-Kommentare bleiben als Kommentare im generierten TeX
erhalten.

### Teal

- Alle Module in `src/mark2tex/` sind in Teal geschrieben; dort liegt kein
  generiertes Lua mehr. `make teal-gen` baut daraus ein einziges Bundle
  `mark2tex.lua`, das alle Module per `package.preload` registriert. Nur das
  Bundle ist committet (als `linguist-generated`, ohne Diff-Anzeige). Paket,
  Overleaf-ZIP und Wheel bestehen zur Laufzeit aus `mark2tex.sty` und
  `mark2tex.lua` und brauchen kein Teal.
- Teal 0.24.1 ist gepinnt. Ohne `tl` im `PATH` wird es per texlua nach
  `.luarocks/` gebootstrappt. Compiler-Einstellungen liegen in `tlconfig.lua`.
- `make teal-check` schlägt fehl, wenn das committete Bundle von den Quellen
  abweicht. `make dist` prüft das per `teal-check` und führt vor dem Packen die
  Tests aus.
- Typisiert sind AST (ein Record je Knotentyp, getrennt in die Stufen
  `nodes.RawBlock` vor und `nodes.Block`/`nodes.Inline` nach dem Inline-Parsing,
  dazu `nodes.Document`), Konfiguration
  (`default_config` ist Typ und Default zugleich) und die gemeinsame
  Warnungsschnittstelle `diagnostics.Issue`. Externe Module (LPeg, LFS, MD5)
  sind über `.d.tl`-Dateien deklariert.

### CLI und Vorlesungen

- `mark2tex notes.md` baut ein PDF ohne eigenes LaTeX-Projekt; Installation
  per `uv tool install .` oder pip. Die Wheel bündelt Lua-, TeX-Quellen und
  Templates.
- Formate `text`, `handout` und `slides` (Beamer) aus derselben Quelle,
  jeweils auch als Dozentenausgabe (`--instructor`/`--dozent`). Dazu
  Speaker-Notes, Schreibrand, `--slide-level`, `--h1 section|frame|hide`.
- Eigene vollständige LaTeX-Templates können CLI-Optionen auswerten;
  Beispiele liegen in `examples/cli/`.
- `--watch`, `--cache` und `--cache-format` für schnelle Rebuilds. Der
  LuaLaTeX-Fontcache wird in `.mark2tex-cache/tex-cache/` wiederverwendet und
  atomar aktualisiert. Fehlgeschlagene Builds behalten das letzte PDF.
- Paketoptionen `profile=handout|slides`, `slide-level`, `audience` und `h1`
  bieten dasselbe Vorlesungslayout auch für `\mdinput` in eigenen Projekten.
- Folienstruktur nach Pandoc-Beamer-Konventionen: Überschriften, `---` (oder `***`, `___`) als
  Fortsetzungsfolie, `. . .` als Overlay.
- Fenced Divs im Pandoc-Stil steuern die Sichtbarkeit (`script`, `slides`,
  `instructor`, `student`, auch kombiniert) und Annotationen (`footer`,
  `notes`). Falsche Verschachtelung erzeugt Warnungen, fehlende oder
  überzählige Schlusszäune einen Abbruch mit Zeilennummer. Die früheren
  HTML-Kommentar-Direktiven sind ersetzt.
- `columns`/`column`-, `figure`- und `caption`-Divs für Spaltenlayout und
  Abbildungen (TikZ, `\input`, Bilder). Eigenständige Markdown-Bilder mit
  `{width=…em}` werden unterstützt; das Paket lädt dafür TikZ und adjustbox.

### Weitere Ergänzungen seit dem letzten Stand

- Alphabetische Aufzählungen und Startwerte für nummerierte Listen.
- Referenzierte und Inline-Fußnoten mit Formatierung, mehrzeiligen
  Definitionen und wiederholten Verweisen; Warnungen bei ungültigen Markern.
- CommonMark-Konstrukte, die nicht mit LaTeX kollidieren: Flanking-Regeln für
  Hervorhebungen (`snake_case` bleibt wörtlich und wird als `\_` ausgegeben),
  horizontale Linien aus `***`, `___` und `- - -`, schließende `#`-Folgen,
  lose Listen, harte Zeilenumbrüche mit `\` am Zeilenende, Referenzlinks,
  Inline-Bilder, Setext-Überschriften mit `===` und Markdown-Escapes für
  `* + < > | ? \``. Tests in `tests/commonmark_*.test` und
  `tests/unit_commonmark.lua`; der Fuzzer erzeugt die neuen Konstrukte mit.
- CommonMark-Konformitätstest: Alle 652 Beispiele der Spezifikation 0.31.2
  (`tests/commonmark/spec.lua`, CC-BY-SA 4.0) werden konvertiert und über eine
  gemeinsame Normalform mit dem HTML der Spezifikation verglichen. Aktuell
  bestehen 369; `tests/commonmark/report.md` zeigt den Stand je Abschnitt,
  `make test` schlägt fehl, wenn ein Beispiel aus `passing.txt` zurückfällt.
  Nach Verbesserungen: `lua tests/commonmark/conformance.lua --update`.
- Ein `#` in Prosa und Überschriften wird als `\#` ausgegeben. Ein
  einzelner Backslash am Ende einer Überschrift bleibt sichtbar. Interne
  Fußnoten-Platzhalter werden auch neben unvollständigen optionalen
  TeX-Argumenten aufgelöst. Die Cache-Versionskennung steht bei v22.

### Älterer Stand, weiterhin gültig

- Inline-Links, URL- und E-Mail-Autolinks; Links setzen separat geladenes
  `hyperref` voraus.
- Inline-Code stellt LaTeX-Sonderzeichen wörtlich dar. Der Text außerhalb
  von LaTeX-Kommandos und Mathematik erhält Escape-Sequenzen für `&`,
  `%`, `#` und wörtliche Unterstriche. Kommentare verwenden `<!-- -->`.
- Der Ausgabe-Cache berücksichtigt Inhalt, Konfiguration und die
  Versionskennung.
- Markdown-Dateien werden im LuaTeX-Recorder registriert; `\mdincludeonly`
  unterstützt selektive Includes.
- `make dist` baut ein TeX-Live-Archiv; `make overleaf-zip` ein Upload-Bundle.

## Verifikation

- `make test` führt 169 Lua- und Fixture-Tests sowie einen kurzen Fuzzlauf
  aus. Es vergleicht die Beispiele und Fixtures in sechs Profilvarianten mit
  den Golden-Snapshots in `tests/golden/`.
- `make teal-check`: das Bundle stimmt mit den Teal-Quellen überein.
- `make latex-smoke`: zwei LuaLaTeX-Läufe für aufgelöste Verweise,
  Recorder-/Ausgabeprüfungen und tatsächliche PDF-Linkziele.
- `make -j2 latex-lecture`: Handout, Folien und Annotationen als PDFs bauen
  und mit `pdfinfo`/`pdftotext` prüfen.
- `make cli-integration` baut und installiert ein frisches Wheel und testet
  die CLI außerhalb des Checkouts. Der CommonMark-PDF-Test prüft
  Überschriften, Umbruch, Liste, Inline-Bild und die beiden Linkziele.
- GitHub Actions führt diese Prüfungen bei Pushes und Pull Requests aus.
  Der wöchentliche Lauf prüft auf dem Standardbranch zusätzlich 16.000
  Fuzz-Eingaben mit einem Seed aus dem UTC-Datum.

Die Tests decken unter anderem reale Dissertationstexte, Listen, Tabellen,
Mathematik, Kommentare, Fußnoten, Links, Vorlesungsprofile und fehlerhafte
Eingaben ab. Das Testverzeichnis `tests/tmp/` wird bei frischen Checkouts
automatisch angelegt.

## Offene Arbeiten

- Der AST ist nur teilweise streng typisiert: stufenabhängige Felder
  (Inhalt, Titel, Tabellenzellen) sind eine lose Union, der Writer castet.
- Die Blockebene nutzt weiterhin LPeg und flache Listen-Nodes mit Levelwerten.
  Ein zeilenorientierter Blockparser und echte List-/List-Item-Nodes bleiben
  sinnvolle größere Umbauten; die Teal-Typen erleichtern das jetzt.
- Diagnosen existieren für Mathematik, LaTeX-Umgebungen und Fenced Divs;
  Positionsangaben und Warnungen für weitere Parserfälle können verbessert werden.
- Vollständige CommonMark-Kompatibilität ist kein Ziel; die README-Liste
  „Deliberately unsupported“ nennt die bewussten Abweichungen (u. a.
  eingerückte Codeblöcke, Setext mit `---`, TeX-Escapes, HTML, Task-Listen).
  Weitere Lücken laut Konformitätsbericht: Blöcke in Listenpunkten (Zitate,
  Code; Items enthalten nur Inline-Inhalt), die Einrückungsregeln für
  Fortsetzungszeilen von Listen, eingerückte Zitate (`   >`) und Code-Fences,
  Lazy Continuation in Zitaten sowie Code-Spans über Zeilenumbrüche
  (Randleerzeichen werden nicht entfernt).
- Die CLI verarbeitet keine Bibliographie (BibTeX/Biber sind deaktiviert).
- Normaler Text wird bewusst nicht vollständig für LaTeX escaped. Rohe
  LaTeX-Kommandos und Mathematik bleiben Teil des Schreibstils.
- Weitere Grenzfälle für verschachtelte Inlines, Include-Pfade und große
  Dateien sowie Performance sind noch nicht systematisch abgesichert.
- Die Archive sind eine Grundlage für Distribution; eine CTAN-Veröffentlichung
  und die dazugehörigen Prüfungen stehen noch aus.

## Designentscheidungen

LaTeX-Funktionalität hat Vorrang vor strikter Markdown-Konformität. Unklare
Eingaben sollen möglichst erhalten bleiben und gezielt Warnungen liefern.
Caching soll konservativ bleiben. Ziel ist ein normal installierbares
LaTeX-Paket; LuaRocks ist kein zentrales Distributionsziel. Teal ist ein
reines Entwicklungswerkzeug, ausgeliefert wird generiertes Lua. Die CLI ist
ein Zusatz für Einzeldokumente; die direkte Einbindung in LaTeX-Projekte
bleibt ein Kernanwendungsfall, die Dissertation der Kompatibilitätsmaßstab.
