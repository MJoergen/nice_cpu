# Top-level Makefile: runs the targets of the subdirectories' Makefiles.
# Each subdirectory can also be used on its own; see CLAUDE.md and README.md.

# The quick tests. The hdl tests need GHDL.
TEST_DIRS      = assembler emulator runtime translator bench hdl doc/intro doc release
TYPECHECK_DIRS = assembler emulator runtime translator bench hdl doc release
CLEAN_DIRS     = assembler emulator runtime bench hdl doc/intro

PYTHON ?= python3

help:
	@echo "NICE CPU: top-level targets"
	@echo ""
	@echo "  make help        show this text (the default)"
	@echo "  make test        the quick tests of every part:"
	@echo "                     $(TEST_DIRS)"
	@echo "  make typecheck   mypy --strict on the Python tools"
	@echo "  make lint        vsg style check of the VHDL (pip install vsg)"
	@echo "  make formal      SymbiYosys checks of the cores, their stages, the devices, and the shared functions"
	@echo "  make slow        the runtime and translator programs, the benchmark,"
	@echo "                   Dhrystone, and the full interrupt sweeps, on CORE (default"
	@echo "                   pipeline; hours)"
	@echo "  make release-check  the gates of RELEASE.md, then a stamp for release.py tag (hours)"
	@echo "  make hazards     count the pipeline hazards in the benchmark"
	@echo "  make pdf         rebuild the introduction slides"
	@echo "  make pdfcheck    check that nice_intro.pdf matches the .tex"
	@echo "  make diagrams    render the diagrams in doc/ (pdflatex, pdftoppm)"
	@echo "  make all         test, typecheck, lint, and pdfcheck"
	@echo "  make clean       remove build output and the Python and mypy caches"
	@echo ""
	@echo "Each subdirectory has its own Makefile, for example:"
	@echo "  make -C emulator test"

# The emulator, which most of the tests run, is built first. Then the
# subdirectories run their tests at the same time, in JOBS jobs, one per
# CPU, unless make was given -j. The output of each is kept together.
JOBS ?= $(shell nproc)

test:
	@$(MAKE) --no-print-directory -C emulator build
	@$(MAKE) $(if $(filter -j%,$(MAKEFLAGS)),,-j$(JOBS)) -O $(addprefix test-,$(TEST_DIRS))

$(addprefix test-,$(TEST_DIRS)): test-%:
	@$(MAKE) -C $* test

typecheck:
	@for d in $(TYPECHECK_DIRS); do $(MAKE) -C $$d typecheck || exit 1; done

lint:
	$(MAKE) -C hdl lint

formal:
	$(MAKE) -C hdl formal

slow:
	$(MAKE) -C hdl programs
	$(MAKE) -C bench core
	$(MAKE) -C bench core-dhry
	$(MAKE) -C hdl sweep

hazards:
	$(MAKE) -C bench hazards

# The release procedure of RELEASE.md; see release/README.md.
release-check:
	$(PYTHON) release/release.py check

pdf:
	$(MAKE) -C doc/intro pdf

pdfcheck:
	$(MAKE) -C doc/intro pdfcheck

# The diagrams: standalone TikZ, rendered at 150 dpi. Both the .tex and
# the .png are committed, as in qnice_cpu. The timing diagrams use the
# macros of doc/timing.sty, and their values are read off a simulation by
# hand, as each header says: render them again only after reading them
# again.
DIAGRAMS = doc/pipeline doc/interrupt doc/flow

diagrams: $(addsuffix .png,$(DIAGRAMS))

doc/interrupt.png doc/flow.png: doc/timing.sty

%.png: %.tex
	TEXINPUTS=doc: pdflatex -interaction=nonstopmode -halt-on-error -output-directory=$(dir $@) $<
	pdftoppm -r 150 -png -singlefile $*.pdf $*
	rm -f $*.pdf $*.aux $*.log

all: test typecheck lint pdfcheck

clean:
	@for d in $(CLEAN_DIRS); do $(MAKE) -C $$d clean || exit 1; done
	@find . -path ./.git -prune -o \( -name .mypy_cache -o -name __pycache__ \) -type d -print0 | xargs -0 -r rm -rf

.PHONY: help test $(addprefix test-,$(TEST_DIRS)) typecheck lint formal slow release-check hazards pdf pdfcheck diagrams all clean
