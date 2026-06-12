# marktex

marktex is a LuaLaTeX package for writing selected parts of a LaTeX document in
Markdown and converting them during compilation.

## Current Scope

The project currently supports a focused Markdown subset that grew out of a
dissertation workflow:

- headings
- emphasis, strong emphasis, and strikethrough
- inline code and fenced code blocks
- inline math and LaTeX commands
- unordered and ordered lists
- citations
- raw LaTeX environments

## Development

Run the regression tests with:

```sh
make test
```

The test runner uses `luaunit` when it is installed. If `luaunit` is missing, it
falls back to a small built-in assertion runner so the parser and writer fixtures
can still be checked.
