PYTHON ?= python3

TESTS = count replicate print encoding wrap crlf

# Assemble each test/X.nasm and compare with the expected test/X.bin, then run
# the error tests in test/errors.py and the disassembler tests in test/dis.py.
test:
	@for t in $(TESTS); do \
	  $(PYTHON) niceasm.py -o test/$$t.out test/$$t.nasm || exit 1; \
	  if cmp -s test/$$t.out test/$$t.bin; then echo "PASS $$t"; \
	  else echo "FAIL $$t"; diff test/$$t.bin test/$$t.out; exit 1; fi; \
	done
	@rm -f test/*.out
	@$(PYTHON) test/errors.py
	@$(PYTHON) test/fmt.py
	@$(PYTHON) test/dis.py
	@$(MAKE) --no-print-directory layout

# Checks that every .nasm file of the repository is in the layout of
# CLAUDE.md. crlf.nasm tests the line ends, so it is not.
layout:
	@cd .. && git ls-files '*.nasm' | grep -v crlf.nasm | xargs $(PYTHON) assembler/nicefmt.py
	@echo "PASS layout"

# Needs mypy (pip install mypy).
typecheck:
	$(PYTHON) -m mypy --strict niceasm.py nicefmt.py nicedis.py test/errors.py test/fmt.py test/dis.py

clean:
	rm -f test/*.out

.PHONY: test layout typecheck clean
