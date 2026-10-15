PYTHON ?= python3
CLANG ?= clang
GHDL ?= ghdl
NICEWASM = $(PYTHON) ../translator/nicewasm.py
ASM = $(PYTHON) ../assembler/niceasm.py
EMU = ../emulator/zig-out/bin/niceemu
LIBC = ../runtime/libc
BUILD = build

CFLAGS = --target=wasm32 -mbulk-memory -O2 -ffreestanding -nostdlibinc -isystem $(LIBC)/include \
  -Wall -Wextra
LDFLAGS = -nostdlib -Wl,--no-entry -Wl,--export=main -Wl,--stack-first -Wl,-z,stack-size=4096 \
  -Wl,--initial-memory=65536

# The two programs: bench, translated from bench.wasm, and hand, the
# hand-written hand.nasm.
PROGRAMS = bench hand

# Runs both on the emulator and prints their tables. bench.wasm is checked
# in, so this needs no C compiler.
run: $(BUILD)/bench.bin $(BUILD)/hand.bin emulator
	@echo "bench.c through nicewasm:"
	@$(EMU) $(BUILD)/bench.bin < /dev/null | sed '/^Halted/,$$d'
	@echo "hand.nasm:"
	@$(EMU) $(BUILD)/hand.bin < /dev/null | sed '/^Halted/,$$d'

# The same, and checks that every phase has its expected result, that main
# returns 0 in R1, and that the expected values in bench.c and hand.nasm
# are those of expected.py.
define check
	@$(EMU) $(BUILD)/$(1).bin < /dev/null > $(BUILD)/$(1).out; sed '/^Halted/,$$d' $(BUILD)/$(1).out
	@if grep -q ' R1  00000000 ' $(BUILD)/$(1).out && ! grep -q FAIL $(BUILD)/$(1).out; \
	then echo "PASS $(1)"; else echo "FAIL $(1)"; exit 1; fi

endef

test: $(BUILD)/bench.bin $(BUILD)/hand.bin emulator
	@$(PYTHON) expected.py --check bench.c hand.nasm
	@$(PYTHON) hazards.py --test
	$(foreach p,$(PROGRAMS),$(call check,$(p)))

# Runs both on the multi-cycle core in GHDL, so that the cycles are the
# core's. This takes about 20 minutes. The program is given relative to
# hdl/build, where GHDL runs, and the output is written there too.
define core_run
	@echo "$(1) on the multi-cycle core:"
	@cd ../hdl/build && $(GHDL) --elab-run --std=08 tb_multicycle \
	  -gG_BIN_FILE=../../bench/$(BUILD)/$(1).bin -gG_TRACE_FILE=$(1)_core.out -gG_TRACE=false \
	  > $(1)_core.log 2>&1; status=$$?; sed '/^Halted/,$$d' $(1)_core.out; \
	  if [ $$status -ne 0 ]; then cat $(1)_core.log; exit 1; fi

endef

core: $(BUILD)/bench.bin $(BUILD)/hand.bin
	$(MAKE) -C ../hdl analyse
	$(foreach p,$(PROGRAMS),$(call core_run,$(p)))

$(BUILD)/bench.nasm: bench.wasm ../translator/nicewasm.py
	@mkdir -p $(BUILD)
	$(NICEWASM) -o $@ bench.wasm

$(BUILD)/bench.full.nasm: ../runtime/start_wasm.nasm $(BUILD)/bench.nasm ../runtime/lib.nasm \
  ../runtime/muldiv_mpu.nasm
	cat $^ > $@

$(BUILD)/hand.full.nasm: ../runtime/start.nasm hand.nasm
	@mkdir -p $(BUILD)
	cat $^ > $@

$(BUILD)/%.bin: $(BUILD)/%.full.nasm ../assembler/niceasm.py
	$(ASM) -o $@ $<

# Counts the pipeline hazards of doc/MICROARCH.md §5 in both programs, from
# the emulator's traces (README.md, The hazard profile).
hazards: $(BUILD)/bench.bin $(BUILD)/hand.bin emulator
	@NICEEMU=$(EMU) $(PYTHON) hazards.py $(BUILD)/bench.bin $(BUILD)/hand.bin

# Needs mypy (pip install mypy).
typecheck:
	$(PYTHON) -m mypy --strict expected.py hazards.py

# Rebuilds bench.wasm from bench.c. Needs clang with the wasm32 target and
# wasm-ld, and builds the C library first.
wasm:
	$(MAKE) -C $(LIBC) libc.a
	$(CLANG) $(CFLAGS) $(LDFLAGS) -o bench.wasm bench.c $(LIBC)/libc.a

# Builds and runs bench.c on the host, as a second check of its results.
# The counters read 0 there.
native:
	@mkdir -p $(BUILD)
	$(CLANG) -O2 -Wall -Wextra -o $(BUILD)/bench.native bench.c
	@./$(BUILD)/bench.native

emulator:
	$(MAKE) -C ../emulator build

clean:
	rm -rf $(BUILD)

.PHONY: run test core hazards typecheck wasm native emulator clean
