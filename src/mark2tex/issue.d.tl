-- Common shape of all parser warnings; modules narrow the fields to enums.
local interface Issue
	category: string
	kind: string
	delimiter: string
	environment: string
	identifier: string
	line: integer
	column: integer
	message: string
	expected_end: string
	actual_end: string
end

return Issue
