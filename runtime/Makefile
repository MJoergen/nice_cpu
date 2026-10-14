PYTHON ?= python3
ASM = $(PYTHON) ../assembler/niceasm.py
EMU = ../emulator/zig-out/bin/niceemu

# Each test/X.asm is joined with a start-up file and lib.asm into one
# program, as ISA.md §9.3 describes. The program is assembled and run, and
# the output and exit status are compared with test/X.expected.
TESTS = start start_wasm mul trap div div64 mul64 bits
START_start_wasm = start_wasm.asm
START_trap       = start_wasm.asm
OPTS_start      = -d 0xfffffeff:1
OPTS_start_wasm = -d 0x1b:1 -d 0xfffffeff:1
OPTS_mul        = -d 0x34:10
OPTS_div        = -d 0x4b:32
OPTS_div64      = -d 0x6f:64
OPTS_mul64      = -d 0x48:16
OPTS_bits       = -d 0x54:54

define check
	@cat $(or $(START_$(1)),start.asm) test/$(1).asm lib.asm > test/$(1).out.asm
	@$(ASM) -o test/$(1).out.bin test/$(1).out.asm
	@$(EMU) $(OPTS_$(1)) test/$(1).out.bin > test/$(1).out; echo "exit $$?" >> test/$(1).out
	@if cmp -s test/$(1).out test/$(1).expected; then echo "PASS $(1)"; \
	else echo "FAIL $(1)"; diff test/$(1).expected test/$(1).out; exit 1; fi

endef

test: emulator
	$(foreach t,$(TESTS),$(call check,$(t)))
	@rm -f test/*.out test/*.out.asm test/*.out.bin

emulator:
	$(MAKE) -C ../emulator build

clean:
	rm -f test/*.out test/*.out.asm test/*.out.bin

.PHONY: test emulator clean
