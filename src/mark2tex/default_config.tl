-- The module is both the Config type and the default values. core.lua copies
-- it with pairs, so it must not contain nested records (enums emit no code).
local record Config
	enum Profile
		"handout"
		"slides"
	end

	enum H1
		"section"
		"frame"
		"hide"
	end

	enum Audience
		"instructor"
		"student"
	end

	enum SlideAudience
		"regular"
		"dozent"
	end

	header: {string}
	paren_citation: string
	citation: string
	save_dir: string

	-- Optional settings, as normalized by core.resolve_config.
	profile: Profile
	slide_level: integer
	h1: H1
	audience: Audience
	slide_audience: SlideAudience
	standalone_learning_blocks: boolean
	document_id: string
	verbose: boolean
end

Config.header = {
	"section",
	"subsection",
	"subsubsection",
	"paragraph",
	"subparagraph"
}

Config.paren_citation = "parencite"
Config.citation = "cite"

Config.save_dir = "mark2tex"

return Config
