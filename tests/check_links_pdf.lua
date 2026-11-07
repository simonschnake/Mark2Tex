-- The smoke document disables PDF compression so link actions are inspectable
-- without an additional PDF library. Check destinations, not only compilation.
local file = assert(io.open("tests/latex-smoke/main.pdf", "rb"))
local pdf = file:read("*a")
file:close()

for _, action in ipairs({
	"/URI(https://example.org/a%20b%20c?x=1&y=$@_#frag)",
	"/URI(https://example.org/bold%20text?a=1&b=2#part)",
	"/URI(https://example.org/a_b?x=1&y=2#part)",
	"/URI(mailto:a_b+tag@example.org)",
	"/F(unterlagen/Auswahl\\040der\\040Inhalte.pdf)",
	"/F(books/Book_name.pdf)",
	"/F(unterlagen/a{b}.pdf)",
	"/URI(https://example.org/a{b}^^c\\\\d)",
	"/URI(https://example.org/list)",
	"/URI(https://example.org/quote)",
	"/URI(https://example.org/$@_)",
}) do
	assert(pdf:find(action, 1, true), "Missing PDF link action: " .. action)
end
assert(pdf:match("/Type /Annot /Subtype /Link[^\n]+/S /GoTo /D %(section%.1%)"),
	"Missing internal PDF link to section.1")
print("PDF link destinations verified")
