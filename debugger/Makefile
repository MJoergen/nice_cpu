PYTHON ?= python3
EMU     = ../emulator/zig-out/bin/niceemu

# The error cases of test/errors.py, which need no emulator, then
# test/link.py, which runs nicelink.py, nicebin.py, and nicedbg.py on
# niceemu --link.
test: $(EMU)
	@$(PYTHON) test/errors.py
	@NICEEMU=$(abspath $(EMU)) $(PYTHON) test/link.py

$(EMU):
	$(MAKE) -C ../emulator build

# Needs mypy (pip install mypy). nicedbg.py imports ../assembler/nicedis.py.
typecheck:
	MYPYPATH=../assembler $(PYTHON) -m mypy --strict nicelink.py nicebin.py nicedbg.py test/link.py test/errors.py

.PHONY: test typecheck
