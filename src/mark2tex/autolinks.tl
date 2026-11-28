local enum Kind
	"inline"
	"autolink"
	"email"
end

-- Shared with links.match; title is only set for inline links.
local record Match
	destination: string
	label: string
	title: string
	kind: Kind
	finish: integer
	label_end: integer
end

-- Types are exported as aliases: nested records would emit runtime tables.
local record autolinks
	type Kind = Kind
	type Match = Match
end

-- The caller has already matched the opening angle bracket at position.
function autolinks.match(source: string, position: integer): Match
	local last = source:find(">", position + 1, true)
	if not last then return nil end
	local value = source:sub(position + 1, last - 1)
	if value:find("[%z\1-\32\127<>]") then return nil end
	local scheme = value:match("^([%a][%w+.-]*):")
	if scheme and #scheme >= 2 and #scheme <= 32 then
		return { destination = value, label = value, kind = "autolink", finish = last, label_end = position }
	end
	local localpart, domain = value:match("^([%w.!#$%%&'*+/=?^_`{|}~-]+)@([%w.-]+)$")
	if localpart and domain then
		local valid = true
		for part in (domain .. "."):gmatch("(.-)%.") do
			if #part == 0 or #part > 63 or not part:match("^[%w].*[%w]$") and not part:match("^[%w]$") then valid = false end
		end
		if valid then return { destination = "mailto:" .. value, label = value, kind = "email", finish = last, label_end = position } end
	end
	return nil
end

return autolinks
