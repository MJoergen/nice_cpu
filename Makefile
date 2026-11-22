# Top-level Makefile: runs the targets of the subdirectories' Makefiles.
# Each subdirectory can also be used on its own; see README.md and CONTRIBUTING.md.

# The quick tests. The hdl tests need GHDL.
TEST_DIRS      = assembler emulator debugger runtime translator bench demo hdl doc/intro doc release
TYPECHECK_DIRS = assembler emulator debugger runtime translator bench hdl doc release
CLEAN_DIRS     = assembler emulator runtime bench demo hdl doc/intro

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
	@echo "  make slow        the benchmark, Dhrystone, CoreMark, and the float benchmark on each"
	@echo "                   core of CORES (default both), the FPU's long vectors, and the fuzz of"
	@echo "                   the C library (clang), in parallel, in nvc, or SIM=ghdl"
	@echo "  make release-check  the gates of RELEASE.md, then a stamp for release.py tag (about an hour)"
	@echo "  make hazards     count the pipeline hazards in the benchmark"
	@echo "  make wasmcheck   rebuild the checked-in .wasm files and compare them (clang, zig, rustc)"
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

# The hdl tests run GHDL, so a missing GHDL stops make test before anything
# runs, not minutes in. Without GHDL, drop hdl: make test TEST_DIRS="...".
GHDL ?= ghdl

test:
	@if echo " $(TEST_DIRS) " | grep -q ' hdl ' && ! command -v $(GHDL) >/dev/null 2>&1; then \
	  echo "make test: $(GHDL) not found, and the tests of hdl need GHDL (README.md)."; \
	  echo "Install it, set GHDL, or leave hdl out: make test TEST_DIRS=\"$(filter-out hdl,$(TEST_DIRS))\""; \
	  exit 1; \
	fi
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

# make slow: on each core of CORES, the benchmark's two programs,
# Dhrystone, CoreMark, and the float benchmark with and without
# --inline-fpu, and beside them the FPU's vectors with a million random
# accesses and the fuzz of the C library, which needs clang, all at once.
# The emulator, the VHDL, and the programs are built first, and the runs
# are told so with PREBUILT=1, as two builds at once would race. Each
# simulation takes a CPU. SIM is the simulator (hdl/sim.mk): nvc, which
# takes minutes where GHDL takes more than half an hour, or ghdl.
CORES ?= pipeline multicycle
SIM ?= nvc
SLOW_RUNS = $(foreach c,$(CORES),$(foreach r,bench hand dhry coremark float,slow/$(c)/$(r))) \
  slow/fpu-long slow/fuzz

slow:
	$(MAKE) -C emulator build
	$(MAKE) -C hdl analyze SIM=$(SIM)
	$(MAKE) -C bench build/bench.bin build/hand.bin build/dhry.bin build/coremark.bin build/float.bin \
	  build/float_inline.bin
	$(MAKE) -C runtime/libc libc.a
	@$(MAKE) --no-print-directory -j$(words $(SLOW_RUNS)) -O $(SLOW_RUNS)

slow/%/bench:
	@$(MAKE) --no-print-directory -C bench core CORE=$* CORE_PROGRAMS=bench PREBUILT=1 SIM=$(SIM)
slow/%/hand:
	@$(MAKE) --no-print-directory -C bench core CORE=$* CORE_PROGRAMS=hand PREBUILT=1 SIM=$(SIM)
slow/%/dhry:
	@$(MAKE) --no-print-directory -C bench core-dhry CORE=$* PREBUILT=1 SIM=$(SIM)
slow/%/coremark:
	@$(MAKE) --no-print-directory -C bench core-coremark CORE=$* PREBUILT=1 SIM=$(SIM)
slow/%/float:
	@$(MAKE) --no-print-directory -C bench core CORE=$* CORE_PROGRAMS="float float_inline" PREBUILT=1 SIM=$(SIM)
slow/fpu-long:
	@$(MAKE) --no-print-directory -C emulator fpu-long
slow/fuzz:
	@$(MAKE) --no-print-directory -C runtime/libc fuzz

hazards:
	$(MAKE) -C bench hazards

# The checked-in .wasm files against their sources: rebuild them, compare,
# and put the checked-in ones back. Needs clang, zig, and rustc (CLANG, ZIG,
# and RUSTC name them), so make test leaves it out. The bytes of a Rust
# module depend on the version of rustc, so a difference there is a note, not
# a failure.
wasmcheck:
	@t=$$(mktemp -d); trap 'rm -rf $$t' EXIT; files=$$(git ls-files '*.wasm'); \
	for f in $$files; do mkdir -p $$t/$$(dirname $$f); cp -p $$f $$t/$$f; done; \
	for d in runtime runtime/libc translator bench; do \
	  $(MAKE) -s -C $$d wasm >/dev/null 2>$$t/err || { cat $$t/err; for f in $$files; do cp -p $$t/$$f $$f; done; exit 1; }; \
	done; \
	bad=; rust=; for f in $$files; do \
	  if ! cmp -s $$f $$t/$$f; then if [ -f $${f%.wasm}.rs ]; then rust="$$rust $$f"; else bad="$$bad $$f"; fi; fi; \
	  cp -p $$t/$$f $$f; done; \
	if [ -n "$$rust" ]; then echo "NOTE: rustc made other bytes, as another rustc may:$$rust"; fi; \
	if [ -n "$$bad" ]; then echo "STALE, run make wasm in its directory:$$bad"; exit 1; fi; \
	echo "PASS wasmcheck ($$(echo $$files | wc -w) files)"

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
DIAGRAMS = doc/pipeline doc/flow

diagrams: $(addsuffix .png,$(DIAGRAMS))

doc/flow.png: doc/timing.sty

%.png: %.tex
	TEXINPUTS=doc: pdflatex -interaction=nonstopmode -halt-on-error -output-directory=$(dir $@) $<
	pdftoppm -r 150 -png -singlefile $*.pdf $*
	rm -f $*.pdf $*.aux $*.log

all: test typecheck lint pdfcheck

clean:
	@for d in $(CLEAN_DIRS); do $(MAKE) -C $$d clean || exit 1; done
	@find . -path ./.git -prune -o \( -name .mypy_cache -o -name __pycache__ \) -type d -print0 | xargs -0 -r rm -rf

.PHONY: help test $(addprefix test-,$(TEST_DIRS)) typecheck lint formal slow release-check hazards wasmcheck pdf pdfcheck diagrams all clean
