local h = require('tests.helpers')
return function(t)
 local function preamble(md)
  return h.transform(md):match('begin{tabularx}[^\n]+')
 end
 function test_table_formatting_and_unicode_do_not_inflate_width()
  local plain = '| Wert | Beschreibung |\n|---:|---|\n| äöüßé | Ein ausreichend langer Text in dieser Zelle |'
  local formatted = plain:gsub('äöüßé', '**äöüßé**')
  t.assertEquals(preamble(plain), preamble(formatted))
  t.assertNotNil(preamble(plain):find('p{', 1, true))
 end
 function test_table_long_header_requires_wrapping()
  local spec = preamble('| Eine sehr lange Spaltenüberschrift | Kurz |\n|---|---|\n| a | b |')
  t.assertNotNil(spec:find('arraybackslash}X', 1, true))
 end
 function test_table_one_long_cell_prevents_compact_column()
  local spec = preamble('| A | B |\n|---|---|\n| kurz | kurz |\n| Hier steht ein langer erklärender Satz | kurz |')
  t.assertNotNil(spec:find('@{}>{\\raggedright\\arraybackslash}X', 1, true))
 end
 function test_table_all_short_or_all_long_columns_use_x()
  for _, cell in ipairs({'kurz', 'Eine lange Beschreibung mit mehreren Wörtern'}) do
   local spec = preamble('| A | B |\n|:---:|---:|\n| ' .. cell .. ' | ' .. cell .. ' |')
   t.assertEquals(spec:find('p{', 1, true), nil)
   t.assertNotNil(spec:find('>{\\centering\\arraybackslash}X>{\\raggedleft\\arraybackslash}X', 1, true))
  end
 end
end
