PYTHON ?= python3

TESTS = count replicate print encoding wrap crlf

# Assemble each test/X.nasm and compare with the expected test/X.bin, then run
# the error tests in test/errors.py.
test:
	@for t in $(TESTS); do \
	  $(PYTHON) niceasm.py -o test/$$t.out test/$$t.nasm || exit 1; \
	  if cmp -s test/$$t.out test/$$t.bin; then echo "PASS $$t"; \
	  else echo "FAIL $$t"; diff test/$$t.bin test/$$t.out; exit 1; fi; \
	done
	@rm -f test/*.out
	@$(PYTHON) test/errors.py

# Needs mypy (pip install mypy).
typecheck:
	$(PYTHON) -m mypy --strict niceasm.py test/errors.py

clean:
	rm -f test/*.out

.PHONY: test typecheck clean
