# marktex Projektstatus

Dieses Dokument beschreibt den aktuellen Stand des Projekts, bekannte
Schwachstellen im Code und sinnvolle naechste Schritte. Es ist als
Arbeitsnotiz gedacht: kurz genug, um aktuell gehalten zu werden, aber konkret
genug, um daraus Issues oder eine Roadmap abzuleiten.

## Aktueller Stand

marktex ist ein LuaLaTeX-Paket, das einen bewusst kleinen Markdown-Dialekt in
LaTeX uebersetzt. Der aktuelle Code ist deutlich modularer als der
urspruengliche Stand:

- `src/marktex/` enthaelt die Lua-Implementierung.
- `marktex.lua` ist der Kompatibilitaets-Einstiegspunkt.
- `marktex.sty` bindet marktex in LuaLaTeX ein.
- `tests/` enthaelt Fixture-Tests, Unit-Tests und einen LaTeX-Smoke-Test.
- `scripts/` enthaelt Entwicklungshelfer.

Die wichtigsten Verbesserungen der letzten Runde:

- Die Quellstruktur wurde von einer einzelnen Lua-Datei in Module aufgeteilt.
- Der Test-Runner wurde robuster gemacht und kann auch ohne `luaunit` laufen.
- Es gibt Unit-Tests fuer Konfiguration, Core-Verhalten und AST-Knoten.
- Aus der Dissertation wurden realistische Regression-Fixtures extrahiert.
- Nested Lists, besonders gleiche Listentypen und Listen am Dateiende, sind
  abgesichert.
- Konfiguration wird nicht mehr durch einzelne Konvertierungen mutiert.
- Dateisystemzugriffe geben Fehler zurueck, statt stillschweigend zu scheitern.
- `marktex.sty` hat einen LuaLaTeX-Smoke-Test und meldet Konvertierungsfehler
  per `tex.error`.
- Der Parser ist intern in Block-Parsing, Inline-Parsing und eine kleine
  Orchestrierung in `parse.lua` getrennt.

## Verifikation

Aktuell relevante Checks:

```sh
make test
make latex-smoke
```

`make test` prueft die Lua-Unit-Tests und Markdown-Fixtures. `make
latex-smoke` kompiliert ein kleines LuaLaTeX-Dokument mit `marktex.sty` und
stellt sicher, dass die Paket-Integration grundsaetzlich funktioniert.

## Unterstuetztes Verhalten

Der Markdown-Dialekt ist bewusst kein vollstaendiges CommonMark. Aktuell
abgedeckt sind vor allem:

- Ueberschriften
- einfache Absatzerkennung
- kursiv, fett und durchgestrichen
- Inline-Code und fenced code blocks
- Inline-Math und LaTeX-Kommandos
- ungeordnete und geordnete Listen, inklusive einiger nested-list Faelle
- Pandoc-artige Zitationen
- rohe LaTeX-Umgebungen
- thesis-nahe LaTeX-/Markdown-Mischformen

Das ist eine brauchbare Grundlage, aber die Grenzen sollten dokumentiert und
bewusst gehalten werden.

## Bekannte Probleme und Risiken

### Parser

Der Parser ist weiterhin eine handgeschriebene LPeg-Grammatik fuer einen
projektgewachsenen Markdown-Subset. Das ist schnell und kontrollierbar, aber
fragil bei Grenzfaellen:

- Fehlerdiagnosen sind noch sehr schwach. Wenn etwas nicht zur Grammatik passt,
  gibt es keine hilfreiche Meldung mit Position oder Kontext.
- Verschachtelte Inline-Elemente sind nur fuer einige Kombinationen getestet.
- Escaping ist unvollstaendig und eher historisch gewachsen.
- Unterstriche in normalem Text, Zitationssyntax und LaTeX-Kommandos koennen
  sich gegenseitig beeinflussen.
- LaTeX-Kommandos mit verschachtelten Klammern sind nur begrenzt robust.
- Unvollstaendige Marker wie offene Backticks, offene Math-Dollar oder
  ungeschlossene Formatierungen brauchen mehr definierte Tests.

### Writer

Der Writer gibt LaTeX direkt aus und ist dadurch nah am Zielsystem, aber einige
Entscheidungen sind noch implizit:

- Normaler Text wird nicht fuer LaTeX-Sonderzeichen escaped. Das kann gewollt
  sein, weil marktex LaTeX-nahe Markdown-Dateien erwartet, sollte aber klar
  dokumentiert oder konfigurierbar werden.
- Header-Level werden beim Schreiben begrenzt, dabei wird aktuell der AST-Knoten
  veraendert. Das ist klein, aber unschoen, weil der Writer Seiteneffekte auf
  Eingabedaten hat.
- Code-Block-Ausgabe nutzt `verbatim`; Sprachangaben werden noch nicht sinnvoll
  weiterverwendet.
- Fehlermeldungen bei unbekannten AST-Typen sind technisch korrekt, aber nicht
  benutzerfreundlich.

### Cache und Ausgabe

Die Konvertierung vermeidet Arbeit ueber einen Cache im generierten
`.tex`-File:

- Der Cache nutzt jetzt einen md5-Fingerprint aus Inhalt und Konfiguration.
- Der Fingerprint wird in der ersten Zeile der generierten Datei gespeichert.
- Das ist deutlich robuster als der alte mtime-Ansatz.
- Fuer spaetere Aenderungen kann man die Fingerprint-Quelle noch enger
  spezifizieren oder versionieren.

### LaTeX-Paketintegration

`marktex.sty` funktioniert wieder mit der neuen Modulstruktur, aber der Ansatz
ist noch etwas spröde:

- Die lokalen Module werden explizit in `package.preload` registriert. Wenn neue
  Module dazukommen, muss das `.sty` angepasst werden.
- Pfade werden nur minimal fuer TeX normalisiert.
- `\mdinclude` entfernt `.tex` am generierten Zielpfad, aber komplexere
  Include-Pfade und Sonderzeichen sind noch nicht systematisch getestet.
- Das Laden von `marktex_config.lua` ist einfach gehalten und nicht weiter
  isoliert.

### Dependencies und Packaging

Die benoetigten Lua-Abhaengigkeiten sind noch nicht sauber als
Entwicklungsumgebung beschrieben:

- `lpeg`, `lfs`, `md5` und optional `luaunit` werden vorausgesetzt.
- Es gibt noch keine committed rockspec oder andere reproduzierbare
  Dependency-Definition.
- Eine spaetere Distribution braucht eine klare Entscheidung: LuaRocks,
  CTAN/TDS-Layout, nur vendored Paketstruktur oder Kombination.

### Tests und CI

Die Testsuite ist deutlich besser als vorher, aber noch lokal gedacht:

- Es gibt noch keine CI, die `make test` ausfuehrt.
- Der LaTeX-Smoke-Test haengt von einer lokalen LuaLaTeX-Installation ab.
- Negative Tests fuer bewusst ungueltiges oder uneindeutiges Markdown fehlen
  noch groesstenteils.
- Performance und grosse Dateien sind nicht abgesichert.

## Sinnvolle naechste Schritte

### 1. Cache weiter haerten

Der naechste pragmatische Schritt waere, den Cache noch bewusster zu
versionieren und zu dokumentieren. Der aktuelle md5-Fingerprint ist schon
deutlich besser als der alte Zeitstempel-Check, aber die genaue Menge der
relevanten Config-Felder sollte langfristig explizit festgelegt sein.

Moegliche Umsetzung:

- Eine kleine interne Versionskennung im Cache-Header festlegen.
- Relevante Konfiguration bewusst als stabilen Satz von Feldern definieren.
- Cache-Header als strukturierte Zeile weiter ausbauen.
- Zusätzliche Tests fuer Cache-Breaking-Changes ergaenzen.

### 2. Parser neu schneiden

Der groesste strukturelle Hebel liegt im Parser selbst. Langfristig sollte die
aktuelle LPeg-Grammatik in eine klarere, lesbarere Form ueberfuehrt werden, die
den Markdown-Workflow explizit abbildet statt ihn nur implizit zu erraten.

Zielbild:

- Block-Parsing und Inline-Parsing voneinander trennen.
- Listen als echte verschachtelte Struktur modellieren.
- Paragraphen, Blank Lines und Blockgrenzen explizit behandeln.
- Source-Positionen pro Node mitfuehren.
- Unsaubere Eingaben kontrolliert behandeln statt stillschweigend zu verwursteln.

Warum das wichtig ist:

- Die aktuelle Grammatik ist stark reihenfolgeabhaengig.
- Viele Regeln sind nur als Sonderfall lesbar.
- Listen- und Inline-Nesting sind schwer zu erweitern.
- Fehlerdiagnosen bleiben sonst dauerhaft oberflaechlich.

Konkreter Umbaupfad:

1. Aktuelles Verhalten als Vertragsbasis festhalten.

   Bevor die Grammatik umgebaut wird, sollten die bestehenden Fixtures als
   erwarteter Kompatibilitaetsvertrag verstanden werden. Zusaetzlich sollten
   einige gezielte Parser-Unit-Tests fuer AST-Formen ergaenzt werden, damit wir
   nicht nur LaTeX-Output vergleichen.

   Erfolgskriterium: Die vorhandenen Tests laufen unveraendert, und die
   wichtigsten Blocktypen haben explizite AST-Tests.

2. Parser-Schnitt intern vorbereiten. Erledigt als erster Umbau-Schritt.

   Der heutige Parser kann nach aussen weiterhin `parse(markdown, config)`
   anbieten, intern aber in klarere Phasen aufgeteilt werden:
   `normalize_input`, `parse_blocks`, `parse_inlines`, `normalize_ast`.
   Diese Phasen bilden aktuell noch bewusst das alte Verhalten nach.

   Erfolgskriterium: Der oeffentliche Einstiegspunkt bleibt stabil, aber die
   Datei ist in klar benannte Schritte zerlegt. Dieses Kriterium ist erfuellt.

3. Einen zeilenorientierten Block-Parser einfuehren.

   Als erster echter Neuschnitt sollte die Blockebene aus der grossen LPeg-
   Grammatik herausgeloest werden. Der Block-Parser sollte Zeilen lesen und
   explizit erkennen:

   - Blank Lines
   - Headings
   - Paragraphen
   - fenced code blocks
   - LaTeX-Bloecke
   - rohe Textbloecke

   Listen koennen in diesem Schritt noch beim alten Verhalten bleiben, damit
   der erste Umbau klein bleibt.

   Erfolgskriterium: Headings, Paragraphen, Code und LaTeX-Bloecke entstehen aus
   dem neuen Block-Parser, waehrend alle Fixtures weiter gruen bleiben.

4. Listen als echte Struktur modellieren.

   Danach sollten Listen nicht mehr als flache `item`-/`enum`-Nodes mit Level
   in den Writer wandern. Stattdessen sollte der Parser echte `list`- und
   `list_item`-Nodes bauen, inklusive verschachtelter Listen.

   Erfolgskriterium: Der Writer muss Listen nicht mehr aus Level-Werten
   rekonstruieren, sondern kann direkt die AST-Struktur ausgeben.

5. Inline-Parser separat stabilisieren.

   Wenn die Blockstruktur klar ist, sollte Inline-Markdown in einer separaten
   Phase verarbeitet werden. Dabei bleiben LaTeX-Kommandos und Math bewusst
   erstklassige Elemente, weil marktex LaTeX-nah bleiben soll.

   Erfolgskriterium: Inline-Parsing ist unabhaengig von der Blockerkennung
   testbar, und unklare Inline-Syntax kann kontrolliert als Text erhalten oder
   als Warning gemeldet werden.

6. Source-Positionen und Warnings einfuehren.

   Sobald Blocks und Inlines getrennt sind, sollten Nodes Positionen bekommen:
   mindestens Zeile, spaeter optional Spalte. Darauf kann ein Warning-System
   aufbauen, das Probleme in `marktex.log` schreibt und ueber `marktex.sty` als
   LaTeX-Warnings durchreicht.

   Erfolgskriterium: Ein bewusst kaputter Markdown-Fall erzeugt eine hilfreiche
   Warning mit Position, laeuft aber nach definierter Regel weiter.

7. Alten Parserpfad entfernen.

   Erst wenn Blockstruktur, Listen, Inlines und Warnings stabil sind, sollte die
   alte kombinierte LPeg-Grammatik entfernt werden. Bis dahin kann sie als
   Sicherheitsnetz fuer noch nicht migrierte Sonderfaelle dienen.

   Erfolgskriterium: Der neue Parser deckt die Fixtures ab, der alte Pfad wird
   nicht mehr benoetigt, und die Parser-Datei ist konzeptionell deutlich
   einfacher zu lesen.

### 3. Supported Markdown dokumentieren

Vor einer groesseren Parser-Ueberarbeitung sollte klar werden, was marktex
absichtlich unterstuetzt und was nicht. Das schuetzt vor versehentlicher
CommonMark-Erwartung und macht Tests zielgerichteter.

Moegliche Umsetzung:

- README um "Supported Markdown subset" erweitern.
- Beispiele fuer LaTeX-nahe Nutzung aufnehmen.
- Nicht-Ziele explizit nennen, zum Beispiel vollstaendige CommonMark-Kompatibilitaet.

### 4. Parser-Fehler und Edge-Cases haerten

Danach lohnt sich eine Runde Parser-Robustheit:

- Tests fuer offene Marker, unvollstaendige Math-Blöcke und kaputte Zitationen.
- Definieren, ob solche Eingaben als Text erhalten bleiben oder Fehler werfen.
- Optional bessere Fehlerobjekte mit Position und Kontext.

### 5. Packaging entscheiden

Die rockspec-Frage sollte wiederkommen, sobald klar ist, welche Distribution
realistisch ist. Fuer Entwicklung waere eine rockspec nuetzlich; fuer LaTeX-Nutzer
ist aber wahrscheinlich auch ein TDS-/CTAN-artiges Layout relevant.

Moegliche Umsetzung:

- `marktex-dev-1.rockspec` oder stabile rockspec neu bewerten.
- Installationsanleitung fuer lokale Entwicklung schreiben.
- Separate Installationsanleitung fuer LaTeX-Projekte schreiben.

### 6. CI einfuehren

Eine einfache CI mit `make test` waere risikoarm und schnell wertvoll. Der
LaTeX-Smoke-Test kann optional oder in einem separaten Job laufen, weil
TeX-Dependencies groesser sind.

### 7. Writer sauberer machen

Der Writer sollte langfristig keine Eingabe-ASTs mutieren und klarer zwischen
"Markdown-Text" und "rohem LaTeX" unterscheiden. Dazu gehoeren Tests fuer
LaTeX-Sonderzeichen und eine bewusste Entscheidung, ob Escaping Standard,
Option oder Nicht-Ziel ist.

## Designentscheidungen

Die aktuelle Richtung ist klar:

- marktex bleibt bewusst LaTeX-nahes Markdown.
- Obsidian-Syntax ist die naheliegende Referenz fuer den Markdown-Teil.
- LaTeX-Funktionalitaet hat im Zweifel Vorrang vor strikter Markdown-Konformitaet.
- Wo es sinnvoll ist, kann marktex mehr von CommonMark uebernehmen, aber nicht
  auf Kosten der LaTeX-Freiheit.
- LaTeX-Sonderzeichen bewusst nicht automatisch zu escapen ist Teil des
  gewollten Workflows.
- Ein Escape-Modus oder eine Option dafuer kann spaeter ergaenzt werden.
- Der Parser soll Warnungen liefern, auch wenn Inhalte am Ende dennoch nach
  LaTeX weiterlaufen.
- Parser-Probleme sollen in der LaTeX-Kompilierung sichtbar werden, idealerweise
  als Warnings und zusaetzlich in einem eigenen `marktex.log`.
- Das Caching darf eher konservativ als aggressiv sein.
- Die Zielverteilung ist CTAN beziehungsweise ein normales installierbares
  LaTeX-Paket.
- LuaRocks kann auf dem Weg helfen, ist aber kein zentrales Ziel.
- Eine lokale Installation fuer die Entwicklung ist voellig in Ordnung.

Praktisch heisst das fuer den Parser:

- lieber robuste LaTeX-Durchreichung als harte Ablehnung jeder unklaren Eingabe
- klare Warnungen fuer Sonderfaelle und verlorene Struktur
- bekannte Markdown-Faelle sauber abdecken, ohne die LaTeX-Nutzbarkeit zu
  beschneiden

## Kurzfazit

Der aktuelle Stand ist eine gute Basis fuer weitere Modernisierung: Die
kritischen Pfade sind modularisiert, die Tests laufen, reale Dissertation-Faelle
sind abgesichert und die LaTeX-Integration hat einen Smoke-Test. Die groessten
Risiken liegen jetzt nicht mehr in der Ordnerstruktur, sondern in Semantik:
Parser-Grenzen, Cache-Korrektheit, LaTeX-Escaping und Packaging.
