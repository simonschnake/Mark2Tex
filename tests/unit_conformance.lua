-- The CommonMark spec examples recorded in tests/commonmark/passing.txt must
-- keep passing (see tests/commonmark/conformance.lua).
local conformance = require("tests.commonmark.conformance")

return function(unit)
	function test_commonmark_conformance_has_no_regressions()
		local regressions = conformance.compare(conformance.results(), conformance.read_passing())
		-- Inspect one with: lua tests/commonmark/conformance.lua --show N
		unit.assertEquals(table.concat(regressions, ", "), "")
	end
end
