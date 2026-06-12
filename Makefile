LUA ?= lua

.PHONY: test latex-smoke

test:
	$(LUA) tests/run.lua

latex-smoke:
	cd tests/latex-smoke && TEXINPUTS=.:$(CURDIR)//: lualatex -interaction=nonstopmode -halt-on-error main.tex
