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

.PHONY: test golden-update fuzz latex-smoke latex-lecture lecture-handout lecture-slides lecture-blocks dist overleaf-zip clean-dist tlmgr-install-dry-run

test:
	$(LUA) tests/run.lua
	$(LUA) tests/golden.lua
	@$(MAKE) --no-print-directory fuzz FUZZ_SAMPLES=$(TEST_FUZZ_SAMPLES)

# make test runs a short fuzz pass; make fuzz runs a long one.
TEST_FUZZ_SAMPLES ?= 2000

# Accept intended output changes into tests/golden/ (review the diff first).
golden-update:
	$(LUA) tests/golden.lua --update

# Property-based fuzzing; failures are shrunk and written to tests/tmp/.
# FUZZ_JOBS processes run in parallel, each with its own seed (FUZZ_SEED,
# FUZZ_SEED+1, ...) and an equal share of FUZZ_SAMPLES.
FUZZ_SAMPLES ?= 16000
FUZZ_SEED ?= 20261128
FUZZ_JOBS ?= $(shell getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)
fuzz:
	@mkdir -p tests/tmp; status=0; pids=""; \
	share=$$(( ($(FUZZ_SAMPLES) + $(FUZZ_JOBS) - 1) / $(FUZZ_JOBS) )); \
	for job in $$(seq 0 $$(( $(FUZZ_JOBS) - 1 ))); do \
		$(LUA) tests/fuzz.lua $$share $$(( $(FUZZ_SEED) + job )) > tests/tmp/fuzz-job-$$job.log 2>&1 & pids="$$pids $$!"; \
	done; \
	for pid in $$pids; do wait $$pid || status=1; done; \
	cat tests/tmp/fuzz-job-*.log; exit $$status

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

# Per-module Lua is an intermediate build product; only the bundle is committed.
TEAL_BUILD_DIR := build/teal
TEAL_MODULES := $(patsubst src/mark2tex/%.tl,$(TEAL_BUILD_DIR)/%.lua,$(TEAL_SOURCES))

# $(call teal_bundle,output.lua): compile every Teal module into $(TEAL_BUILD_DIR)
# and combine them into one bundle (see scripts/bundle.lua).
teal_bundle = mkdir -p $(TEAL_BUILD_DIR); \
	for src in $(TEAL_SOURCES); do \
		log=$$($(TEAL_GEN) -o "$(TEAL_BUILD_DIR)/$$(basename "$$src" .tl).lua" "$$src" 2>&1) || { echo "$$log" >&2; exit 1; }; \
	done; \
	$(LUA) scripts/bundle.lua "$(1)" "$(VERSION)" "$(TEAL_VERSION)" $(TEAL_MODULES)

# Regenerate the committed bundle after changing a Teal source.
teal-gen: teal-version
	@set -e; $(call teal_bundle,mark2tex.lua); echo "Wrote mark2tex.lua"

# Fail when the committed bundle does not match the Teal sources.
teal-check: teal-version
	@set -e; $(call teal_bundle,$(TEAL_BUILD_DIR)/bundle-check.lua); \
	if ! cmp -s mark2tex.lua "$(TEAL_BUILD_DIR)/bundle-check.lua"; then \
		diff -u mark2tex.lua "$(TEAL_BUILD_DIR)/bundle-check.lua" | head -40; \
		echo "mark2tex.lua is out of date; run 'make teal-gen'." >&2; exit 1; \
	fi

latex-smoke:
	cd tests/latex-smoke && TEXINPUTS=.:$(CURDIR): LUAINPUTS=$(CURDIR): lualatex -recorder -interaction=nonstopmode -halt-on-error main.tex
	cd tests/latex-smoke && TEXINPUTS=.:$(CURDIR): LUAINPUTS=$(CURDIR): lualatex -recorder -interaction=nonstopmode -halt-on-error main.tex
	grep -Eq '^INPUT (\./)?content\.md$$' tests/latex-smoke/main.fls
	grep -Eq '^INPUT (\./)?chapter\.md$$' tests/latex-smoke/main.fls
	! grep -Eq '^INPUT (\./)?excluded\.md$$' tests/latex-smoke/main.fls
	grep -Fq '\subsection{Smoke}' tests/latex-smoke/mark2tex-output/content_*.tex
	grep -Fq '\textbf{single}' tests/latex-smoke/mark2tex-output/content_*.tex
	grep -Fq '\textit{group}' tests/latex-smoke/mark2tex-output/content_*.tex
	$(LUA) tests/check_links_pdf.lua
	$(LUA) tests/check_footnotes.lua

latex-lecture: lecture-handout lecture-slides lecture-blocks
	cd tests/lecture && TEXINPUTS=.:$(CURDIR): LUAINPUTS=$(CURDIR): lualatex -interaction=nonstopmode -halt-on-error annotations.tex
	cd tests/lecture && TEXINPUTS=.:$(CURDIR): LUAINPUTS=$(CURDIR): lualatex -interaction=nonstopmode -halt-on-error -jobname=annotations-dozent '\def\LectureDozent{}\input{annotations.tex}'
	cd tests/lecture && TEXINPUTS=.:$(CURDIR): LUAINPUTS=$(CURDIR): lualatex -interaction=nonstopmode -halt-on-error -jobname=annotations-handout '\def\LectureHandout{}\input{annotations.tex}'
	cd tests/lecture && sh check-pdfs.sh

lecture-handout: LECTURE_JOB = handout
lecture-slides: LECTURE_JOB = folien
lecture-blocks: LECTURE_JOB = blocks
lecture-handout lecture-slides lecture-blocks:
	cd tests/lecture && TEXINPUTS=.:$(CURDIR): LUAINPUTS=$(CURDIR): lualatex -recorder -interaction=nonstopmode -halt-on-error $(LECTURE_JOB).tex

dist: teal-check
	$(MAKE) test
	$(MAKE) "$(DIST_ARCHIVE)"

overleaf-zip: $(OVERLEAF_ARCHIVE)


$(DIST_ARCHIVE): mark2tex.sty mark2tex.lua README.md LICENSE
	@mkdir -p "$(DIST_BUILD_DIR)/texmf-dist/tex/latex/mark2tex"
	@mkdir -p "$(DIST_BUILD_DIR)/texmf-dist/scripts/mark2tex"
	@mkdir -p "$(DIST_BUILD_DIR)/texmf-dist/doc/lualatex/mark2tex"
	@mkdir -p "$(DIST_BUILD_DIR)/tlpkg/tlpobj"
	@cp mark2tex.sty "$(DIST_BUILD_DIR)/texmf-dist/tex/latex/mark2tex/"
	@cp mark2tex.lua "$(DIST_BUILD_DIR)/texmf-dist/scripts/mark2tex/"
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

$(OVERLEAF_ARCHIVE): mark2tex.sty mark2tex.lua README.md LICENSE
	@mkdir -p "$(OVERLEAF_BUILD_DIR)"
	@cp mark2tex.sty mark2tex.lua README.md LICENSE "$(OVERLEAF_BUILD_DIR)/"
	@cd "$(OVERLEAF_BUILD_DIR)" && zip -qr "$(abspath $(OVERLEAF_ARCHIVE))" mark2tex.sty mark2tex.lua README.md LICENSE
	@echo "Built $(OVERLEAF_ARCHIVE)"

tlmgr-install-dry-run: dist
	@if [ ! -f "$(TLMGR_USER_TREE)/tlpkg/texlive.tlpdb" ]; then \
		tlmgr --usermode --usertree "$(TLMGR_USER_TREE)" init-usertree; \
	fi
	tlmgr --usermode --usertree "$(TLMGR_USER_TREE)" install --dry-run --file "$(DIST_ARCHIVE)"

clean-dist:
	rm -rf "$(DIST_DIR)"
