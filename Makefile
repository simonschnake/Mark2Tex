LUA ?= lua
PACKAGE ?= mark2tex
VERSION ?= 0.2.0
REVISION ?= 2
DIST_DIR ?= dist
DIST_BUILD_DIR := $(DIST_DIR)/build/$(PACKAGE)
DIST_ARCHIVE := $(DIST_DIR)/$(PACKAGE).tar.xz
OVERLEAF_BUILD_DIR := $(DIST_DIR)/build/$(PACKAGE)-overleaf
OVERLEAF_ARCHIVE := $(DIST_DIR)/$(PACKAGE)-overleaf.zip
TLMGR_USER_TREE ?= $(abspath $(DIST_DIR)/tlmgr-usertree)

.PHONY: test latex-smoke dist overleaf-zip clean-dist tlmgr-install-dry-run

test:
	$(LUA) tests/run.lua

latex-smoke:
	cd tests/latex-smoke && TEXINPUTS=.:$(CURDIR)//: LUAINPUTS=$(CURDIR)//: lualatex -recorder -interaction=nonstopmode -halt-on-error main.tex
	grep -Eq '^INPUT (\./)?content\.md$$' tests/latex-smoke/main.fls
	grep -Eq '^INPUT (\./)?chapter\.md$$' tests/latex-smoke/main.fls
	! grep -Eq '^INPUT (\./)?excluded\.md$$' tests/latex-smoke/main.fls

dist: $(DIST_ARCHIVE)

overleaf-zip: $(OVERLEAF_ARCHIVE)


$(DIST_ARCHIVE): mark2tex.sty mark2tex.lua README.md LICENSE $(wildcard src/mark2tex/*.lua)
	@mkdir -p "$(DIST_BUILD_DIR)/texmf-dist/tex/latex/mark2tex"
	@mkdir -p "$(DIST_BUILD_DIR)/texmf-dist/scripts/mark2tex/src/mark2tex"
	@mkdir -p "$(DIST_BUILD_DIR)/texmf-dist/doc/lualatex/mark2tex"
	@mkdir -p "$(DIST_BUILD_DIR)/tlpkg/tlpobj"
	@cp mark2tex.sty "$(DIST_BUILD_DIR)/texmf-dist/tex/latex/mark2tex/"
	@cp mark2tex.lua "$(DIST_BUILD_DIR)/texmf-dist/scripts/mark2tex/"
	@cp src/mark2tex/*.lua "$(DIST_BUILD_DIR)/texmf-dist/scripts/mark2tex/src/mark2tex/"
	@cp README.md LICENSE "$(DIST_BUILD_DIR)/texmf-dist/doc/lualatex/mark2tex/"
	@{ \
		echo "name $(PACKAGE)"; \
		echo "category Package"; \
		echo "revision $(REVISION)"; \
		echo "shortdesc Markdown-like fragments for LuaLaTeX documents"; \
		echo "longdesc Mark2TeX reads Markdown-like .md files during LuaLaTeX compilation,"; \
		echo "longdesc converts the supported LaTeX-oriented subset to TeX, and inputs"; \
		echo "longdesc the generated file back into the document."; \
		echo "depend latex"; \
		echo "depend luacode"; \
		echo "depend ulem"; \
		echo "runfiles size=1"; \
		find "$(DIST_BUILD_DIR)/texmf-dist/tex" "$(DIST_BUILD_DIR)/texmf-dist/scripts" -type f | LC_ALL=C sort | sed 's#^$(DIST_BUILD_DIR)/# #'; \
		echo "docfiles size=1"; \
		find "$(DIST_BUILD_DIR)/texmf-dist/doc" -type f | LC_ALL=C sort | sed 's#^$(DIST_BUILD_DIR)/# #'; \
		echo "catalogue-license mit"; \
		echo "catalogue-version $(VERSION)"; \
	} > "$(DIST_BUILD_DIR)/tlpkg/tlpobj/$(PACKAGE).tlpobj"
	@tar -C "$(DIST_BUILD_DIR)" -cf - texmf-dist tlpkg | xz -9e > "$(DIST_ARCHIVE)"
	@echo "Built $(DIST_ARCHIVE)"

$(OVERLEAF_ARCHIVE): mark2tex.sty mark2tex.lua README.md LICENSE $(wildcard src/mark2tex/*.lua)
	@mkdir -p "$(OVERLEAF_BUILD_DIR)/src/mark2tex"
	@cp mark2tex.sty mark2tex.lua README.md LICENSE "$(OVERLEAF_BUILD_DIR)/"
	@cp src/mark2tex/*.lua "$(OVERLEAF_BUILD_DIR)/src/mark2tex/"
	@cd "$(OVERLEAF_BUILD_DIR)" && zip -qr "../../$(notdir $(OVERLEAF_ARCHIVE))" mark2tex.sty mark2tex.lua src README.md LICENSE
	@echo "Built $(OVERLEAF_ARCHIVE)"

tlmgr-install-dry-run: $(DIST_ARCHIVE)
	@if [ ! -f "$(TLMGR_USER_TREE)/tlpkg/texlive.tlpdb" ]; then \
		tlmgr --usermode --usertree "$(TLMGR_USER_TREE)" init-usertree; \
	fi
	tlmgr --usermode --usertree "$(TLMGR_USER_TREE)" install --dry-run --file "$(DIST_ARCHIVE)"

clean-dist:
	rm -rf "$(DIST_DIR)"
