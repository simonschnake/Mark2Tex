# Mark2TeX Projektstatus

Stand: 10. November 2026. Die genaue Syntax und Installation stehen in README.md.

## Aktueller Stand

Mark2TeX ist ein LuaLaTeX-Paket für einen bewusst LaTeX-nahen Markdown-Subset.
Die Lua-Implementierung ist in Module für Block- und Inline-Parsing, Mathematik,
Links, Kommentare, Diagnosen, AST-Knoten, Ausgabe und Konvertierung aufgeteilt.

Unterstützt werden Überschriften, Absätze, horizontale Linien, Formatierungen,
Inline-Code, fenced Code und rohe TeX-Blöcke, Listen mit Verschachtelung,
Blockquotes, Pipe-Tabellen, Zitationen, Mathematik und rohe LaTeX-Umgebungen.
HTML-Kommentare bleiben als Kommentare im generierten TeX erhalten.

Die aktuellen Ergänzungen:

- Referenzierte und Inline-Fußnoten mit Formatierung, mehrzeiligen Definitionen
  und wiederholten Verweisen auf dieselbe Nummer; Warnungen bei ungültigen Markern.
- Inline-Links, URL- und E-Mail-Autolinks mit geschützten Linkzielen.
- Formatierung, Inline-Code und Mathematik in Linkbeschriftungen.
- Lokale Dateiziele mit Leerzeichen und Verweise auf bestehende LaTeX-Labels.
- Links setzen ein separat geladenes `hyperref` voraus; fehlendes `hyperref`
  erzeugt eine gezielte Paketfehlermeldung. Linktitel werden nicht ausgegeben.
- Inline-Code escaped LaTeX-Sonderzeichen, normaler Text escaped Ampersands.
- Negative Zahlen in eingerückten Listeninhalten bleiben erhalten.
- Der Ausgabe-Cache berücksichtigt Inhalt, Konfiguration und eine interne
  Versionskennung, die bei Parser-/Writer-Änderungen erhöht wird.
- Paketoptionen ersetzen die frühere Datei `mark2tex_config.lua`.
- Markdown-Dateien werden im LuaTeX-Recorder registriert; `mdincludeonly`
  unterstützt selektive Includes.
- `make dist` baut ein TeX-Live-Archiv; `make overleaf-zip` ein Upload-Bundle.

## Verifikation

- `make test`: Lua-Unit-Tests und Markdown/TeX-Fixtures.
- `make latex-smoke`: zwei LuaLaTeX-Läufe für aufgelöste Verweise,
  Recorder-/Ausgabeprüfungen und Prüfung tatsächlicher PDF-Linkziele.

Die Tests decken unter anderem reale Dissertationstexte, Listen, Tabellen,
Mathematik, Kommentare, fehlerhafte Eingaben und Links ab. LuaLaTeX benötigt
einen beschreibbaren Schriftcache. Build-Ausgaben sind über `.gitignore`
ausgeschlossen.

## Offene Arbeiten

- Die Blockebene nutzt weiterhin LPeg und flache Listen-Nodes mit Levelwerten.
  Ein zeilenorientierter Blockparser und echte List-/List-Item-Nodes bleiben
  sinnvolle größere Umbauten.
- Diagnosen existieren für Mathematik und LaTeX-Umgebungen; Positionsangaben
  und Warnungen für weitere Parserfälle können verbessert werden.
- Vollständige CommonMark-Kompatibilität ist kein Ziel. Bilder, Referenzlinks
  und Task-Listen sind weiterhin nicht unterstützt.
- Normaler Text wird bewusst nicht vollständig für LaTeX escaped. Rohe
  LaTeX-Kommandos und Mathematik bleiben Teil des Schreibstils.
- Weitere Grenzfälle für verschachtelte Inlines, Include-Pfade und große
  Dateien sowie Performance sind noch nicht systematisch abgesichert.
- Eine CI und eine reproduzierbare Entwicklungs-Dependency-Definition fehlen.
- Die Archive sind eine Grundlage für Distribution; eine CTAN-Veröffentlichung
  und die dazugehörigen Prüfungen stehen noch aus.

## Designentscheidungen

LaTeX-Funktionalität hat Vorrang vor strikter Markdown-Konformität. Unklare
Eingaben sollen möglichst erhalten bleiben und gezielt Warnungen liefern.
Caching soll konservativ bleiben. Ziel ist ein normal installierbares
LaTeX-Paket; LuaRocks ist kein zentrales Distributionsziel.
