.DEFAULT_GOAL := dist

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

.PHONY: test latex-smoke latex-lecture lecture-handout lecture-slides lecture-blocks dist overleaf-zip clean-dist tlmgr-install-dry-run

test:
	$(LUA) tests/run.lua

TEAL_VERSION := 0.24.1
TEXLUA ?= texlua
TEAL_LOCAL := .luarocks/teal-$(TEAL_VERSION)/tl
ifeq ($(origin TL),undefined)
TL := $(shell command -v tl 2>/dev/null)
ifeq ($(TL),)
TL := $(TEXLUA) $(TEAL_LOCAL)
TEAL_PREREQUISITE := $(TEAL_LOCAL)
endif
endif
TEAL_SOURCES := $(filter-out %.d.tl,$(wildcard src/mark2tex/*.tl))
# Compiler settings (include path, gen target) live in tlconfig.lua.
TEAL_GEN = $(TL) gen --check

.PHONY: teal-version teal-gen teal-check
teal-version: $(TEAL_PREREQUISITE)
	@test "$$($(TL) --version)" = "$(TEAL_VERSION)" || { echo "Expected Teal $(TEAL_VERSION) (set TL to override the compiler command)" >&2; exit 1; }

$(TEAL_LOCAL): scripts/bootstrap-teal.sh
	sh scripts/bootstrap-teal.sh "$(TEAL_VERSION)" "$(@D)"

# $(call teal_emit,source.tl,output.lua): compile and prepend a generated-file header.
teal_emit = $(TEAL_GEN) -o "$(2)" "$(1)"; \
	{ printf '%s\n' "-- Generated from $(1) by Teal $(TEAL_VERSION). Edit the .tl file and run 'make teal-gen'."; \
	cat "$(2)"; } > "$$tmp.header"; mv "$$tmp.header" "$(2)"

teal-gen: teal-version
	@set -e; tmp=$$(mktemp); trap 'rm -f "$$tmp" "$$tmp.header"' EXIT; \
	for src in $(TEAL_SOURCES); do \
		$(call teal_emit,$$src,$${src%.tl}.lua); \
	done

teal-check: teal-version
	@set -e; tmp=$$(mktemp); trap 'rm -f "$$tmp" "$$tmp.header"' EXIT; \
	for src in $(TEAL_SOURCES); do \
		$(call teal_emit,$$src,$$tmp); \
		diff -u "$${src%.tl}.lua" "$$tmp"; \
	done

latex-smoke:
	cd tests/latex-smoke && TEXINPUTS=.:$(CURDIR)//: LUAINPUTS=$(CURDIR)//: lualatex -recorder -interaction=nonstopmode -halt-on-error main.tex
	cd tests/latex-smoke && TEXINPUTS=.:$(CURDIR)//: LUAINPUTS=$(CURDIR)//: lualatex -recorder -interaction=nonstopmode -halt-on-error main.tex
	grep -Eq '^INPUT (\./)?content\.md$$' tests/latex-smoke/main.fls
	grep -Eq '^INPUT (\./)?chapter\.md$$' tests/latex-smoke/main.fls
	! grep -Eq '^INPUT (\./)?excluded\.md$$' tests/latex-smoke/main.fls
	grep -Fq '\subsection{Smoke}' tests/latex-smoke/mark2tex-output/content_*.tex
	grep -Fq '\textbf{single}' tests/latex-smoke/mark2tex-output/content_*.tex
	grep -Fq '\textit{group}' tests/latex-smoke/mark2tex-output/content_*.tex
	$(LUA) tests/check_links_pdf.lua
	$(LUA) tests/check_footnotes.lua

latex-lecture: lecture-handout lecture-slides lecture-blocks
	cd tests/lecture && TEXINPUTS=.:$(CURDIR)//: LUAINPUTS=$(CURDIR)//: lualatex -interaction=nonstopmode -halt-on-error annotations.tex
	cd tests/lecture && TEXINPUTS=.:$(CURDIR)//: LUAINPUTS=$(CURDIR)//: lualatex -interaction=nonstopmode -halt-on-error -jobname=annotations-dozent '\def\LectureDozent{}\input{annotations.tex}'
	cd tests/lecture && TEXINPUTS=.:$(CURDIR)//: LUAINPUTS=$(CURDIR)//: lualatex -interaction=nonstopmode -halt-on-error -jobname=annotations-handout '\def\LectureHandout{}\input{annotations.tex}'
	cd tests/lecture && sh check-pdfs.sh

lecture-handout: LECTURE_JOB = handout
lecture-slides: LECTURE_JOB = folien
lecture-blocks: LECTURE_JOB = blocks
lecture-handout lecture-slides lecture-blocks:
	cd tests/lecture && TEXINPUTS=.:$(CURDIR)//: LUAINPUTS=$(CURDIR)//: lualatex -recorder -interaction=nonstopmode -halt-on-error $(LECTURE_JOB).tex

dist: teal-gen
	$(MAKE) test
	$(MAKE) "$(DIST_ARCHIVE)"

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
		echo "depend kvoptions"; \
		echo "depend ulem"; \
		echo "depend tools"; \
		echo "depend adjustbox"; \
		echo "depend pgf"; \
		echo "depend booktabs"; \
		echo "runfiles size=1"; \
		find "$(DIST_BUILD_DIR)/texmf-dist/tex" "$(DIST_BUILD_DIR)/texmf-dist/scripts" -type f | LC_ALL=C sort | sed 's#^$(DIST_BUILD_DIR)/# #'; \
		echo "docfiles size=1"; \
		find "$(DIST_BUILD_DIR)/texmf-dist/doc" -type f | LC_ALL=C sort | sed 's#^$(DIST_BUILD_DIR)/# #'; \
		echo "catalogue-license mit"; \
		echo "catalogue-version $(VERSION)"; \
	} > "$(DIST_BUILD_DIR)/tlpkg/tlpobj/$(PACKAGE).tlpobj"
	@COPYFILE_DISABLE=1 tar -C "$(DIST_BUILD_DIR)" -cf - texmf-dist tlpkg | xz -9e > "$(DIST_ARCHIVE)"
	@echo "Built $(DIST_ARCHIVE)"

$(OVERLEAF_ARCHIVE): mark2tex.sty mark2tex.lua README.md LICENSE $(wildcard src/mark2tex/*.lua)
	@mkdir -p "$(OVERLEAF_BUILD_DIR)/src/mark2tex"
	@cp mark2tex.sty mark2tex.lua README.md LICENSE "$(OVERLEAF_BUILD_DIR)/"
	@cp src/mark2tex/*.lua "$(OVERLEAF_BUILD_DIR)/src/mark2tex/"
	@cd "$(OVERLEAF_BUILD_DIR)" && zip -qr "../../$(notdir $(OVERLEAF_ARCHIVE))" mark2tex.sty mark2tex.lua src README.md LICENSE
	@echo "Built $(OVERLEAF_ARCHIVE)"

tlmgr-install-dry-run: dist
	@if [ ! -f "$(TLMGR_USER_TREE)/tlpkg/texlive.tlpdb" ]; then \
		tlmgr --usermode --usertree "$(TLMGR_USER_TREE)" init-usertree; \
	fi
	tlmgr --usermode --usertree "$(TLMGR_USER_TREE)" install --dry-run --file "$(DIST_ARCHIVE)"

clean-dist:
	rm -rf "$(DIST_DIR)"
