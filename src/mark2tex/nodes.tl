local type comments = require("mark2tex.comments")
local type Issue = require("mark2tex.issue")

-- The AST has two stages. parse_blocks (and divs) produce RawBlock nodes whose
-- text is still unparsed; parse turns them into Block nodes holding Inline
-- lists. Every node type is its own record, discriminated by its type field.

local interface NodeBase
	type: string
end

--------------------
-- Inline nodes
--------------------

local record Text is NodeBase where self.type == "text"
	content: string
end

local record Bold is NodeBase where self.type == "bold"
	content: {Inline}
end

local record Italic is NodeBase where self.type == "italic"
	content: {Inline}
end

local record Strikethrough is NodeBase where self.type == "strikethrough"
	content: {Inline}
end

local record Verbatim is NodeBase where self.type == "verbatim"
	content: string
end

local record LatexCmd is NodeBase where self.type == "latex_cmd"
	content: string
end

local record Citation is NodeBase where self.type == "citation"
	content: string
end

local record ParenCitation is NodeBase where self.type == "paren_citation"
	-- Citation keys.
	content: {string}
	locator: string
end

local record InlineMath is NodeBase where self.type == "inline_math"
	content: string
end

-- Display math occurs as a block and, inside paragraphs, as an inline node.
local record DisplayMath is NodeBase where self.type == "display_math"
	content: string
end

local record Link is NodeBase where self.type == "link"
	destination: string
	content: {Inline}
	title: string
	kind: string
end

local record Footnote is NodeBase where self.type == "footnote"
	-- Inline footnotes (inline = true) hold content, resolved definitions hold
	-- blocks; repeated references hold neither.
	content: {Inline}
	blocks: {Block}
	label: string
	repeated: boolean
	inline: boolean
end

-- A single source character that the writer escapes for TeX.
local record Literal is NodeBase where self.type == "literal"
	content: string
end

-- A paragraph, or a run of inlines kept together (e.g. a rejected footnote).
local record Other is NodeBase where self.type == "other"
	content: {Inline}
end

-- A hard line break: a backslash at the end of a line inside a paragraph.
local record LineBreak is NodeBase where self.type == "line_break"
end

-- An image inside text; standalone image lines are Image blocks.
local record InlineImage is NodeBase where self.type == "inline_image"
	path: string
	width: string
end

local type Inline = Text | Bold | Italic | Strikethrough | Verbatim | LatexCmd
	| Citation | ParenCitation | InlineMath | DisplayMath | Link | Footnote
	| Literal | Other | LineBreak | InlineImage

--------------------
-- Blocks shared by both stages
--------------------

local record HorizontalRule is NodeBase where self.type == "horizontal_rule"
end

local record Latex is NodeBase where self.type == "latex"
	content: string
end

local record Code is NodeBase where self.type == "code"
	code_type: string
	content: string
end

local record Image is NodeBase where self.type == "image"
	path: string
	width: string
end

local record SlideBreak is NodeBase where self.type == "slide_break"
end

local record SlidePause is NodeBase where self.type == "slide_pause"
end

local record SlideNote is NodeBase where self.type == "slide_note"
	title: string
end

local record SlideFooter is NodeBase where self.type == "slide_footer"
	title: string
end

--------------------
-- Raw blocks (before inline parsing)
--------------------

local record RawHeader is NodeBase where self.type == "header"
	level: integer
	content: string
	indented: boolean
end

-- A list item's source with the item's indentation removed. Like a
-- blockquote, parse fills in its blocks while collecting definitions.
local record RawListItem is NodeBase where self.type == "list_item"
	content: string
	blocks: {RawBlock}
end

-- A list of consecutive items of one kind: "bullet", "decimal" or "alpha".
-- Nested lists are blocks inside an item.
local record RawList is NodeBase where self.type == "list"
	kind: string
	start: integer
	content: {RawListItem}
end

local record RawOther is NodeBase where self.type == "other"
	content: string
end

local record RawBlockquote is NodeBase where self.type == "blockquote"
	content: string
	-- Set by parse while collecting footnote definitions.
	blocks: {RawBlock}
end

local record RawTable is NodeBase where self.type == "table"
	headers: {string}
	alignments: {string}
	rows: {{string}}
end

-- [label]: destination "title"; parse collects these document-wide.
local record LinkDefinition is NodeBase where self.type == "link_definition"
	label: string
	destination: string
	title: string
end

local record FootnoteDefinition is NodeBase where self.type == "footnote_definition"
	identifier: string
	content: string
end

local record DivFence is NodeBase where self.type == "div_fence"
	position: integer
	ending: integer
	length: integer
	attributes: string
end

local type RawBlock = RawHeader | RawList | RawOther | RawBlockquote
	| RawTable | FootnoteDefinition | LinkDefinition | DivFence | HorizontalRule | Latex | Code
	| DisplayMath | Image | SlideBreak | SlidePause | SlideNote | SlideFooter

--------------------
-- Parsed blocks
--------------------

local record Header is NodeBase where self.type == "header"
	level: integer
	content: {Inline}
	indented: boolean
end

local record ListItem is NodeBase where self.type == "list_item"
	content: {Block}
end

local record List is NodeBase where self.type == "list"
	kind: string
	start: integer
	content: {ListItem}
end

local record Blockquote is NodeBase where self.type == "blockquote"
	content: {Block}
end

local record Table is NodeBase where self.type == "table"
	headers: {{Inline}}
	alignments: {string}
	rows: {{{Inline}}}
end

-- Lecture structure (lecture.structure).
local record SlideFrame is NodeBase where self.type == "slide_frame"
	content: {Block}
	title: {Inline}
	footer: string
	notes: {string}
end

local record LectureAnnotations is NodeBase where self.type == "lecture_annotations"
	footer: string
	notes: {string}
end

local record SlideParagraph is NodeBase where self.type == "slide_paragraph"
end

local record SlideSubheading is NodeBase where self.type == "slide_subheading"
	content: {Inline}
end

local type Block = Header | List | ListItem | Other | Blockquote | Table
	| HorizontalRule | Latex | Code | DisplayMath | Image | SlideBreak
	| SlidePause | SlideNote | SlideFooter | SlideFrame | LectureAnnotations
	| SlideParagraph | SlideSubheading

-- Any parsed node, for traversals that treat inlines and blocks alike.
local type Any = Inline | Block

-- The AST root carries document-wide comments and parser warnings.
local record AstDocument
	{Block}
	comments: {comments.Token}
	warnings: {Issue}
end

-- The view that generic traversals use: every node may carry content.
local record ContentView
	content: string | {Any | string}
end

-- Types are exported as aliases: nested records would emit runtime tables.
local record nodes
	type Inline = Inline
	type RawBlock = RawBlock
	type Block = Block
	type Any = Any
	type Document = AstDocument

	type Text = Text
	type Bold = Bold
	type Italic = Italic
	type Strikethrough = Strikethrough
	type Verbatim = Verbatim
	type LatexCmd = LatexCmd
	type Citation = Citation
	type ParenCitation = ParenCitation
	type InlineMath = InlineMath
	type DisplayMath = DisplayMath
	type Link = Link
	type Footnote = Footnote
	type Literal = Literal
	type Other = Other
	type LineBreak = LineBreak
	type InlineImage = InlineImage

	type HorizontalRule = HorizontalRule
	type Latex = Latex
	type Code = Code
	type Image = Image
	type SlideBreak = SlideBreak
	type SlidePause = SlidePause
	type SlideNote = SlideNote
	type SlideFooter = SlideFooter

	type RawHeader = RawHeader
	type RawList = RawList
	type RawListItem = RawListItem
	type RawOther = RawOther
	type RawBlockquote = RawBlockquote
	type RawTable = RawTable
	type FootnoteDefinition = FootnoteDefinition
	type LinkDefinition = LinkDefinition
	type DivFence = DivFence

	type Header = Header
	type List = List
	type ListItem = ListItem
	type Blockquote = Blockquote
	type Table = Table
	type SlideFrame = SlideFrame
	type LectureAnnotations = LectureAnnotations
	type SlideParagraph = SlideParagraph
	type SlideSubheading = SlideSubheading
end

-- The content of any node (nil for nodes without one), for generic
-- traversals such as measuring or searching the AST. A resolved footnote
-- definition yields its blocks.
function nodes.content(node: Any): string | {Any | string}
	if node is Footnote and node.blocks then
		return node.blocks
	end
	return (node as ContentView).content
end

--------------------
-- Constructors
--------------------

function nodes.footnote(content?: {Inline}, label?: string, repeated?: boolean): Footnote
	return { type = "footnote", content = content, label = label, repeated = repeated }
end

-- A footnote whose definition was parsed as blocks.
function nodes.footnote_blocks(blocks: {Block}, label: string): Footnote
	return { type = "footnote", blocks = blocks, label = label }
end

function nodes.footnote_definition(identifier: string, content: string): FootnoteDefinition
	return { type = "footnote_definition", identifier = identifier, content = content }
end

function nodes.link(destination: string, content: {Inline}, title?: string, kind?: string): Link
	return { type = "link", destination = destination, content = content, title = title, kind = kind or "inline" }
end

function nodes.header(level: integer, content: string): RawHeader
	return { type = "header", level = level, content = content }
end

function nodes.horizontal_rule(): HorizontalRule
	return { type = "horizontal_rule" }
end

function nodes.latex(content: string): Latex
	return { type = "latex", content = content }
end

function nodes.raw_list(kind: string, start: integer): RawList
	return { type = "list", kind = kind, start = start, content = {} }
end

function nodes.raw_list_item(content: string): RawListItem
	return { type = "list_item", content = content }
end

function nodes.code(code_type: string, content: string): Code
	return { type = "code", code_type = code_type, content = content }
end

function nodes.blockquote(content: string): RawBlockquote
	return { type = "blockquote", content = content }
end

function nodes.table(headers: {string}, alignments: {string}, rows: {{string}}): RawTable
	return { type = "table", headers = headers, alignments = alignments, rows = rows }
end

-- An unparsed paragraph.
function nodes.raw_other(content: string): RawOther
	return { type = "other", content = content }
end

function nodes.other(content: {Inline}): Other
	return { type = "other", content = content }
end

function nodes.paren_citation(content: {string}, locator?: string): ParenCitation
	return { type = "paren_citation", content = content, locator = locator }
end

function nodes.citation(content: string): Citation
	return { type = "citation", content = content }
end

function nodes.verbatim(content: string): Verbatim
	return { type = "verbatim", content = content }
end

function nodes.inline_math(content: string): InlineMath
	return { type = "inline_math", content = content }
end

function nodes.display_math(content: string): DisplayMath
	return { type = "display_math", content = content }
end

function nodes.latex_cmd(content: string): LatexCmd
	return { type = "latex_cmd", content = content }
end

function nodes.italic(content: {Inline}): Italic
	return { type = "italic", content = content }
end

function nodes.bold(content: {Inline}): Bold
	return { type = "bold", content = content }
end

function nodes.strikethrough(content: {Inline}): Strikethrough
	return { type = "strikethrough", content = content }
end

function nodes.text(content: string): Text
	return { type = "text", content = content }
end

function nodes.line_break(): LineBreak
	return { type = "line_break" }
end

function nodes.inline_image(path: string, width?: string): InlineImage
	return { type = "inline_image", path = path, width = width or "" }
end

function nodes.literal(content: string): Literal
	return { type = "literal", content = content }
end

return nodes
