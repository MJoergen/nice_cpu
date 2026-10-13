PYTHON ?= python3

TESTS = count replicate print encoding

# Assemble each test/X.asm and compare with the expected test/X.bin.
test:
	@for t in $(TESTS); do \
	  $(PYTHON) niceasm.py -o test/$$t.out test/$$t.asm || exit 1; \
	  if cmp -s test/$$t.out test/$$t.bin; then echo "PASS $$t"; \
	  else echo "FAIL $$t"; diff test/$$t.bin test/$$t.out; exit 1; fi; \
	done
	@rm -f test/*.out

# Needs mypy (pip install mypy).
typecheck:
	$(PYTHON) -m mypy --strict niceasm.py

clean:
	rm -f test/*.out

.PHONY: test typecheck clean
