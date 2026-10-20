PYTHON ?= python3

# Checks that every "FILE.md §n.m" in the repository names a section FILE.md
# has, and that every link of every Markdown file names a file that exists
# and a heading it has (check_refs.py).
test:
	@$(PYTHON) check_refs.py

# Needs mypy (pip install mypy).
typecheck:
	$(PYTHON) -m mypy --strict check_refs.py

.PHONY: test typecheck
