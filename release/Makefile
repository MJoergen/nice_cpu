PYTHON ?= python3

# The tests of release.py that need no repository, tools, or network.
test:
	@$(PYTHON) test.py

# Needs mypy (pip install mypy).
typecheck:
	$(PYTHON) -m mypy --strict release.py test.py

.PHONY: test typecheck
