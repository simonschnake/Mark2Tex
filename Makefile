LUA ?= lua

.PHONY: test

test:
	$(LUA) tests/run.lua
