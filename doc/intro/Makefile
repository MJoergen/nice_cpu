PYTHON ?= python3
ASM = $(PYTHON) ../../assembler/niceasm.py
EMU = ../../emulator/zig-out/bin/niceemu

# The slides, built with pdflatex. Run twice for the page numbers.
pdf: nice_intro.pdf

nice_intro.pdf: nice_intro.tex
	pdflatex -interaction=nonstopmode -halt-on-error nice_intro.tex
	pdflatex -interaction=nonstopmode -halt-on-error nice_intro.tex

# Checks that the checked-in PDF is up to date. The slides are rebuilt in
# build/ and the text of each page is compared with pdftotext, because the
# PDF bytes hold the build date.
pdfcheck:
	mkdir -p build
	pdflatex -interaction=nonstopmode -halt-on-error -output-directory build nice_intro.tex > /dev/null
	pdflatex -interaction=nonstopmode -halt-on-error -output-directory build nice_intro.tex > /dev/null
	pdftotext -layout nice_intro.pdf build/old.txt
	pdftotext -layout build/nice_intro.pdf build/new.txt
	@if cmp -s build/old.txt build/new.txt; then echo "PASS nice_intro.pdf"; \
	else echo "FAIL nice_intro.pdf is out of date; run make pdf"; diff build/old.txt build/new.txt; exit 1; fi

# The example programs on the slides. Each is assembled and run with its
# options, and the output and exit status are compared with
# examples/X.expected. The expected values are checked by hand in the
# comments below.
#
# sum:   R1 = 4096*4097/2 = 0x800800, after 2 + 3*4096 + 1 = 12291 steps.
# hello: prints the text. R1 ends one past the 0 word: TEXT is at 0xE,
#        and the 12 characters and the 0 are 13 words, so R1 = 0x1B.
#        Steps: 3 up to the CALL, 4 for each of the 12 characters, 2 at
#        the 0, and the newline and the HALT: 55. The HALT is at 8, so
#        PC = 9.
# copy:  DST is at 0xF and holds 1 to 5. R1 and R2 end at SRC+5 and DST+5.
# poll:  the read of CYCLE_LO in step s returns s - 1, the steps before
#        it. The SUBs read 3, 6, 9, 12: due at 10, so 4 ADDs, then 19,
#        22 (due 20) and 29, 32 (due 30), 2 ADDs each: R3 = 8, and the
#        stars at steps 15, 25, and 35. R2 ends at 40, and the last DEC
#        leaves Z = 1. The ADD, DEC, JMP, newline, and HALT after the last
#        star end at step 40, with PC = 0x14, after the 20 words.
# keys:  keys.txt is DEL, "Hello, N", ESC, "ICEx", DEL, "!", and CR. The
#        first DEL, at column 0, and the ESC change nothing, and the
#        second DEL deletes the "x", so row 2 is "Hello, NICE!" in white
#        on black, under the title in yellow on blue. The cursor ends
#        hidden, at column 12 of row 2, on the white space the program
#        keeps under it, which the screen's print trims: R3 = 0xFFFF00A0
#        + 12, and R2 the CR. TITLE is at 0x3C and has 30 characters and
#        the 0, so R1 = 0x5B. Steps: 124 for the title, 6 to set up, 18
#        for each of the 13 keys written, 11 for each of the first DEL
#        and the ESC, 17 for the second DEL, and 9 for the CR: 412.
EXAMPLES = sum hello copy poll keys
OPTS_copy = -d 0xF:5
OPTS_keys = --color -d 0xFFFFFF80:3 -i examples/keys.txt

define check
	@$(ASM) -o examples/$(1).bin examples/$(1).nasm
	@$(EMU) $(OPTS_$(1)) examples/$(1).bin > examples/$(1).out; echo "exit $$?" >> examples/$(1).out
	@if cmp -s examples/$(1).out examples/$(1).expected; then echo "PASS $(1)"; \
	else echo "FAIL $(1)"; diff examples/$(1).expected examples/$(1).out; exit 1; fi

endef

test: emulator
	$(foreach t,$(EXAMPLES),$(call check,$(t)))
	@rm -f examples/*.out examples/*.bin
	@$(PYTHON) ../check_readme.py

emulator:
	$(MAKE) -C ../../emulator build

clean:
	rm -rf build
	rm -f examples/*.out examples/*.bin *.aux *.log *.nav *.out *.snm *.toc *.vrb

.PHONY: pdf pdfcheck test emulator clean
