Edge cases for inline scanning. Every paragraph is independent; the golden
snapshots record how each pass treats it.

Single backtick code `a_b {x} %` and code with a link inside `[l](u)`.

Double backtick code ``a ` b`` and triple ```x `` y```.

Unclosed code `open **bold** $x$ [link](https://e.org) ^[note].

Unclosed double backtick ``open and then `closed` text.

Empty pair `` and a lone ` backtick.

Code then math `$` and $y$ after.

Math with code inside $a`b`c$ and code with math inside `$x$`.

Escaped dollar \$5 and \$10, then real $x$.

Math inside a TeX argument \textbf{$x$ and $y$} and \text{a $b$ c}.

Display delimiters inside a TeX argument \f{\[} and \g{\(}.

Broken math inside an argument \textbf{$x} stays raw TeX.

Command with option and argument \cmd[o]{$a$} then $b$.

Link label with code [`a]b`](https://e.org) and destination with code [x](`y`).

Malformed link with code [a `](` b] and [c](d `e`.

Footnote inside code `^[not a note]` and a real note^[yes].

Footnote after code `x`^[note] and after math $x$^[note].

Citation next to code @key`c` and [@a; @b] `d`.

Comment inside code `<!-- kept -->` and outside <!-- removed -->.

Backslash before backtick \`not code\` and \\`code`.

Trailing backslash \
