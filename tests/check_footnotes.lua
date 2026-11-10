-- Check LaTeX-assigned numbers, including inline notes between named notes.
local file = assert(io.open('tests/latex-smoke/main.aux', 'r'))
local aux = file:read('*a')
file:close()
local numbers = {}
for number in aux:gmatch('\\newlabel{mark2tex:footnote:[^}]+}{{(%d+)}') do
    numbers[#numbers + 1] = tonumber(number)
end
table.sort(numbers)
assert(table.concat(numbers, ',') == '1,3,5', 'unexpected named footnote numbers in LaTeX output')
local log = assert(io.open('tests/latex-smoke/main.log', 'r'))
local content = log:read('*a')
log:close()
assert(not content:find('undefined references', 1, true), 'footnote references were not resolved')
assert(not content:find('multiply defined', 1, true), 'duplicate footnote labels')
print('Footnote numbers and references verified')
