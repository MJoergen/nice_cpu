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

# The programs: bench, translated from bench.wasm, hand, the hand-written
# hand.nasm, and simple, hand.nasm with vm and strings as a simple C
# compiler would emit them (README.md, A simple compiler). make core runs
# the first two.
PROGRAMS = bench hand simple
CORE_PROGRAMS = bench hand

# Dhrystone 2.1, ported in dhrystone/ (README.md, Dhrystone), and its
# console input, the number of runs. The 1988 C of its sources is compiled
# as C89, as it stands, so without the warnings of CFLAGS, and with no
# inlining, which the ground rules of Dhrystone forbid.
DHRY = dhrystone
DHRY_CFLAGS = --target=wasm32 -mbulk-memory -O2 -ffreestanding -nostdlibinc -isystem $(LIBC)/include \
  -std=gnu89 -fno-inline -DNICE -Wno-deprecated-non-prototype -Wno-return-type
DHRY_RUNS = $(DHRY)/dhry.input

# Runs both on the emulator and prints their tables. bench.wasm is checked
# in, so this needs no C compiler.
run: $(BUILD)/bench.bin $(BUILD)/hand.bin $(BUILD)/simple.bin emulator
	@echo "bench.c through nicewasm:"
	@$(EMU) $(BUILD)/bench.bin < /dev/null | sed '/^Halted/,$$d'
	@echo "hand.nasm:"
	@$(EMU) $(BUILD)/hand.bin < /dev/null | sed '/^Halted/,$$d'
	@echo "simple.nasm:"
	@$(EMU) $(BUILD)/simple.bin < /dev/null | sed '/^Halted/,$$d'

# Runs Dhrystone on the emulator and prints its output.
dhry: $(BUILD)/dhry.bin emulator
	@$(EMU) --input $(DHRY_RUNS) $(BUILD)/dhry.bin < /dev/null | sed '/^Halted/,$$d'

# The same, and checks that every phase has its expected result, that main
# returns 0 in R1, and that the expected values in bench.c, hand.nasm, and
# simple.nasm are those of expected.py.
define check
	@$(EMU) $(BUILD)/$(1).bin < /dev/null > $(BUILD)/$(1).out; sed '/^Halted/,$$d' $(BUILD)/$(1).out
	@if grep -q ' R1  00000000 ' $(BUILD)/$(1).out && ! grep -q FAIL $(BUILD)/$(1).out; \
	then echo "PASS $(1)"; else echo "FAIL $(1)"; exit 1; fi

endef

test: $(BUILD)/bench.bin $(BUILD)/hand.bin $(BUILD)/simple.bin $(BUILD)/dhry.bin emulator
	@$(PYTHON) expected.py --check bench.c hand.nasm simple.nasm
	@$(PYTHON) hazards.py --test
	@NICEEMU=$(EMU) $(PYTHON) pipecycles.py --test
	@NICEEMU=$(EMU) $(PYTHON) cycprof.py --test
	@$(PYTHON) words.py --test
	$(foreach p,$(PROGRAMS),$(call check,$(p)))
	@NICEEMU=$(EMU) $(PYTHON) pipecycles.py --phases 6 $(BUILD)/bench.bin $(BUILD)/hand.bin $(BUILD)/simple.bin \
	  > /dev/null \
	  && echo "PASS pipecycles.py --phases 6"
	@$(PYTHON) dhrycheck.py --test
	@$(EMU) --input $(DHRY_RUNS) $(BUILD)/dhry.bin < /dev/null > $(BUILD)/dhry.out
	@$(PYTHON) dhrycheck.py --runs $$(cat $(DHRY_RUNS)) $(BUILD)/dhry.out
	@echo 0 | $(EMU) $(BUILD)/dhry.bin | grep -q 'must be at least 1' && echo "PASS dhrystone with 0 runs"
	@echo x | $(EMU) $(BUILD)/dhry.bin | grep -q 'must be at least 1' && echo "PASS dhrystone with no number"

# Runs both on a core in GHDL, so that the cycles are the core's: CORE,
# the generic G_CORE of hdl/test/tb_core.vhd, is pipeline for the
# pipelined core or multicycle for the multi-cycle one. On an idle machine
# the pipelined core takes about 22 minutes and the multi-cycle core about
# 38: the pipelined core runs fewer cycles, but more logic in each. The program is given relative to
# hdl/build, where GHDL runs, and the output is written there too, with
# the retire log that pipecycles.py --retires reads, $(1)_$(CORE).retires.
# GHDL runs in a directory of its own for each program and core, as the
# runs of hdl/ do, because its LLVM and GCC backends write an executable
# where they run; so the top-level make slow can run them all at once.
# The files stay in hdl/build. PREBUILT=1 skips the analysis, which make
# slow has done.
CORE ?= pipeline
HDL_BUILD = $(abspath ../hdl/build)
ANALYZE = $(if $(PREBUILT),,$(MAKE) -C ../hdl analyze)

# Runs tb_core on CORE in its own directory: $(1) is the name of the run,
# $(2) the program, and $(3) more generics.
define ghdl_core
mkdir -p $(HDL_BUILD)/bench_run/$(1)_$(CORE) && cd $(HDL_BUILD)/bench_run/$(1)_$(CORE) && \
	  $(GHDL) --elab-run --std=08 --workdir=$(HDL_BUILD) tb_core -gG_CORE=$(CORE) \
	  -gG_BIN_FILE=$(abspath $(2)) -gG_TRACE_FILE=$(HDL_BUILD)/$(1)_$(CORE).out -gG_TRACE=false $(3) \
	  > $(HDL_BUILD)/$(1)_$(CORE).log 2>&1; status=$$?; sed '/^Halted/,$$d' $(HDL_BUILD)/$(1)_$(CORE).out
endef

define core_run
	@echo "$(1) on the $(CORE) core:"
	@$(call ghdl_core,$(1),$(BUILD)/$(1).bin,-gG_RETIRE_LOG=$(HDL_BUILD)/$(1)_$(CORE).retires); \
	  grep '^Read waits:' $(HDL_BUILD)/$(1)_$(CORE).log; \
	  if [ $$status -ne 0 ]; then cat $(HDL_BUILD)/$(1)_$(CORE).log; exit 1; fi

endef

core: $(BUILD)/bench.bin $(BUILD)/hand.bin
	$(ANALYZE)
	$(foreach p,$(CORE_PROGRAMS),$(call core_run,$(p)))

# Dhrystone on a core in GHDL, CORE as above, with its output checked.
core-dhry: $(BUILD)/dhry.bin
	$(ANALYZE)
	@$(call ghdl_core,dhry,$(BUILD)/dhry.bin,-gG_INPUT_FILE=$(abspath $(DHRY_RUNS))); \
	  if [ $$status -ne 0 ]; then cat $(HDL_BUILD)/dhry_$(CORE).log; exit 1; fi
	@$(PYTHON) dhrycheck.py --runs $$(cat $(DHRY_RUNS)) ../hdl/build/dhry_$(CORE).out

$(BUILD)/bench.nasm: bench.wasm ../translator/nicewasm.py
	@mkdir -p $(BUILD)
	$(NICEWASM) -o $@ bench.wasm

$(BUILD)/bench.full.nasm: ../runtime/start_wasm.nasm $(BUILD)/bench.nasm ../runtime/lib.nasm \
  ../runtime/muldiv_mpu.nasm
	cat $^ > $@

$(BUILD)/dhry.nasm: $(DHRY)/dhry.wasm ../translator/nicewasm.py
	@mkdir -p $(BUILD)
	$(NICEWASM) -o $@ $(DHRY)/dhry.wasm

$(BUILD)/dhry.full.nasm: ../runtime/start_wasm.nasm $(BUILD)/dhry.nasm ../runtime/lib.nasm \
  ../runtime/muldiv_mpu.nasm
	cat $^ > $@

$(BUILD)/hand.full.nasm: ../runtime/start.nasm hand.nasm
	@mkdir -p $(BUILD)
	cat $^ > $@

$(BUILD)/simple.full.nasm: ../runtime/start.nasm simple.nasm
	@mkdir -p $(BUILD)
	cat $^ > $@

$(BUILD)/%.bin: $(BUILD)/%.full.nasm ../assembler/niceasm.py
	$(ASM) -o $@ $<

# Counts the pipeline hazards of doc/MICROARCH.md §5 in both programs, from
# the emulator's traces (README.md, The hazard profile).
hazards: $(BUILD)/bench.bin $(BUILD)/hand.bin emulator
	@NICEEMU=$(EMU) $(PYTHON) hazards.py $(BUILD)/bench.bin $(BUILD)/hand.bin

# Estimates the cycles of the three programs on the pipelined core of
# doc/MICROARCH.md, from the emulator's traces (README.md, The cycle
# estimate).
cycles: $(BUILD)/bench.bin $(BUILD)/hand.bin $(BUILD)/simple.bin emulator
	@NICEEMU=$(EMU) $(PYTHON) pipecycles.py $(BUILD)/bench.bin $(BUILD)/hand.bin $(BUILD)/simple.bin

# The estimate beside the cycles the pipelined core took, phase by phase,
# from the output of make core, which must have run first
# (README.md, The cycle estimate).
compare: $(BUILD)/bench.bin $(BUILD)/hand.bin emulator
	@NICEEMU=$(EMU) $(PYTHON) pipecycles.py --against ../hdl/build/bench_pipeline.out $(BUILD)/bench.bin
	@NICEEMU=$(EMU) $(PYTHON) pipecycles.py --against ../hdl/build/hand_pipeline.out $(BUILD)/hand.bin

# The same, charged to the source lines of each program: the listings
# build/bench.cyc.txt and build/hand.cyc.txt.
profile: $(BUILD)/bench.bin $(BUILD)/hand.bin $(BUILD)/bench.full.nasm $(BUILD)/hand.full.nasm emulator
	@NICEEMU=$(EMU) $(PYTHON) cycprof.py $(BUILD)/bench.full.nasm $(BUILD)/bench.bin
	@NICEEMU=$(EMU) $(PYTHON) cycprof.py $(BUILD)/hand.full.nasm $(BUILD)/hand.bin

# The size in words of the translated modules the READMEs quote: the
# benchmark's, translator/test/safe.zig's, and the float library's.
words:
	@$(PYTHON) words.py bench.wasm ../translator/test/safe.wasm
	@$(PYTHON) words.py --library float ../runtime/float.wasm

# Needs mypy (pip install mypy).
typecheck:
	MYPYPATH=../assembler $(PYTHON) -m mypy --strict expected.py hazards.py pipecycles.py cycprof.py words.py dhrycheck.py

# Rebuilds bench.wasm from bench.c, and dhrystone/dhry.wasm from its
# sources. Needs clang with the wasm32 target and wasm-ld, and builds the C
# library first.
wasm:
	$(MAKE) -C $(LIBC) libc.a
	$(CLANG) $(CFLAGS) $(LDFLAGS) -o bench.wasm bench.c $(LIBC)/libc.a
	$(CLANG) $(DHRY_CFLAGS) $(LDFLAGS) -o $(DHRY)/dhry.wasm $(DHRY)/dhry_1.c $(DHRY)/dhry_2.c \
	  $(LIBC)/libc.a
	@chmod -x bench.wasm $(DHRY)/dhry.wasm

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

.PHONY: run dhry test core core-dhry hazards cycles compare profile words typecheck wasm native emulator clean
