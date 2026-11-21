#!/bin/sh
set -eu

test "$(pdfinfo handout.pdf | awk '/^Pages:/ {print $2}')" = 1
test "$(pdfinfo folien.pdf | awk '/^Pages:/ {print $2}')" = 4
pdfinfo folien.pdf | awk '/^Page size:/ {
    found = ($3 > 496.05 && $3 < 496.08 && $5 > 279.02 && $5 < 279.05)
} END { exit !found }'
pdftotext handout.pdf - | grep -Fq 'Der Schwarzschild-Radius'
if pdftotext handout.pdf - | grep -Fq 'Die Geometrie außerhalb des Horizonts'; then exit 1; fi
if pdftotext -f 1 -l 1 folien.pdf - | grep -Fq '2𝐺𝑀'; then exit 1; fi
pdftotext -f 2 -l 2 folien.pdf - | grep -Fq '2𝐺𝑀'
pdftotext -f 3 -l 3 folien.pdf - | tr '\n' ' ' | grep -Fq 'Die Geometrie außerhalb des Horizonts'
pdftotext blocks.pdf - | grep -Fq 'Beispielcode'
pdftotext blocks.pdf - | grep -Fq 'Eine Fußnote'
grep -Eq '^INPUT (\./)?blocks\.md$' blocks.fls
if grep -Eq '^INPUT (\./)?excluded\.md$' blocks.fls; then exit 1; fi
pdftotext annotations.pdf - | grep -Fq 'Skriptabschnitt 5'
if pdftotext annotations.pdf - | grep -Eq 'Wandreibung|Rohr einzeichnen'; then exit 1; fi
pdftotext -f 1 -l 1 annotations-dozent.pdf - | grep -Fq 'Wandreibung'
if pdftotext -f 1 -l 1 annotations-dozent.pdf - | grep -Fq 'Rohr einzeichnen'; then exit 1; fi
pdftotext -f 2 -l 2 annotations-dozent.pdf - | grep -Fq 'Rohr einzeichnen'
for text in 'Skriptabschnitt 5' 'Wandreibung' 'Vortragsnotiz' 'Rohr einzeichnen'; do
    pdftotext annotations-handout.pdf - | grep -Fq "$text"
done
