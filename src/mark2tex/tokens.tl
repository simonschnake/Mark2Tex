-- Placeholders that the inline passes (footnotes, links, math) put into the
-- source while protecting a construct. They are framed by two control
-- characters that never occur in Markdown, so grammars can exclude them from
-- citation keys and TeX command names and never swallow a placeholder.

local START = string.char(30)
local FINISH = string.char(31)

local record tokens
	-- The two frame characters, for lpeg.S / pattern character classes.
	markers: string
end

tokens.markers = START .. FINISH

-- The placeholder prefix for one protection pass over source. Nested passes
-- (footnote content, link labels) see the placeholders of their outer pass in
-- their source, so each pass extends its kind letter until it is unused.
function tokens.prefix(source: string, kind: string): string
	local prefix = START .. kind
	while source:find(prefix, 1, true) do
		prefix = prefix .. "x"
	end
	return prefix
end

-- The placeholder number index under a prefix from tokens.prefix.
function tokens.make(prefix: string, index: integer): string
	return prefix .. tostring(index) .. FINISH
end

return tokens
