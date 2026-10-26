PYTHON ?= python3

# Checks that every "FILE.md §n.m" in the repository names a section FILE.md
# has, and that every link of every Markdown file names a file that exists
# and a heading it has (check_refs.py). Also that no checked-in .wasm file is
# executable, which the C compiler's linker makes it and the wasm recipes undo.
test:
	@$(PYTHON) check_refs.py
	@bad=$$(git -C .. ls-files -s '*.wasm' | awk '$$1 == "100755" {print $$4}'); \
	if [ -n "$$bad" ]; then echo "executable .wasm files (git update-index --chmod=-x):"; echo "$$bad"; exit 1; fi

# Needs mypy (pip install mypy).
typecheck:
	$(PYTHON) -m mypy --strict check_refs.py

.PHONY: test typecheck
