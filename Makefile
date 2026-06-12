LUA ?= lua

.PHONY: test

test:
	$(LUA) tests.lua
