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
# hello: prints the text. R1 ends one past the 0 word: TEXT is at 0x12,
#        and the 12 characters and the 0 are 13 words, so R1 = 0x1F.
# copy:  DST is at 0x10 and holds 1 to 5. R1 and R2 end at SRC+5 and DST+5.
# irq:   one '*' for each of the two IRQs, then the newline. R14 keeps
#        E = 1 and VBASE = 1, and the countdown leaves Z = 1.
EXAMPLES = sum hello copy irq
OPTS_copy = -d 0x10:5
OPTS_irq  = --irq 5:5 --irq 12:5

define check
	@$(ASM) -o examples/$(1).bin examples/$(1).nasm
	@$(EMU) $(OPTS_$(1)) examples/$(1).bin > examples/$(1).out; echo "exit $$?" >> examples/$(1).out
	@if cmp -s examples/$(1).out examples/$(1).expected; then echo "PASS $(1)"; \
	else echo "FAIL $(1)"; diff examples/$(1).expected examples/$(1).out; exit 1; fi

endef

test: emulator
	$(foreach t,$(EXAMPLES),$(call check,$(t)))
	@rm -f examples/*.out examples/*.bin

emulator:
	$(MAKE) -C ../../emulator build

clean:
	rm -rf build
	rm -f examples/*.out examples/*.bin *.aux *.log *.nav *.out *.snm *.toc *.vrb

.PHONY: pdf pdfcheck test emulator clean
