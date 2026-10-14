GHDL ?= ghdl
PYTHON ?= python3
ASM = $(PYTHON) ../assembler/niceasm.py
EMU = ../emulator/zig-out/bin/niceemu
BUILD = build
# GHDL runs in $(BUILD), where the LLVM and GCC backends leave their
# executables, so paths given to it start with ../.
GHDLRUN = cd $(BUILD) && $(GHDL) --elab-run --std=08

SOURCES = src/trace_pkg.vhd
SIM_SOURCES = sim/wb_mem.vhd sim/trace.vhd
TEST_SOURCES = test/tb_mem.vhd test/tb_trace.vhd

# tb_trace stands in for the core and runs test/trace.asm. Each run's output
# and exit status must equal those of the emulator on the same program, with
# the same NMI. The runs are: the full trace; no trace; a step limit right
# after the skipped instruction; and a step limit at the NMI.
TRACE_RUNS = full quiet skip nmi
GENERICS_quiet = -gG_TRACE=false
OPTS_quiet     = --nmi 5:0x20
GENERICS_skip  = -gG_MAX_STEPS=4
OPTS_skip      = -t -n 4 --nmi 5:0x20
GENERICS_nmi   = -gG_MAX_STEPS=6
OPTS_nmi       = -t -n 6 --nmi 5:0x20
OPTS_full      = -t --nmi 5:0x20

define check_trace
	@($(GHDLRUN) tb_trace -gG_BIN_FILE=trace.bin -gG_TRACE_FILE=trace_$(1).out \
	  $(GENERICS_$(1)) > trace_$(1).log 2>&1); echo "exit $$?" >> $(BUILD)/trace_$(1).out
	@$(EMU) $(OPTS_$(1)) $(BUILD)/trace.bin > $(BUILD)/trace_$(1).expected; \
	  echo "exit $$?" >> $(BUILD)/trace_$(1).expected
	@if cmp -s $(BUILD)/trace_$(1).expected $(BUILD)/trace_$(1).out; then echo "PASS tb_trace $(1)"; \
	else echo "FAIL tb_trace $(1)"; cat $(BUILD)/trace_$(1).log; \
	  diff $(BUILD)/trace_$(1).expected $(BUILD)/trace_$(1).out; exit 1; fi

endef

# tb_mem checks the memory model itself.
test: emulator analyse
	@($(GHDLRUN) tb_mem -gG_BIN_FILE=../test/mem.bin > tb_mem.log 2>&1); \
	if [ $$? -eq 0 ]; then echo "PASS tb_mem"; else echo "FAIL tb_mem"; cat $(BUILD)/tb_mem.log; exit 1; fi
	@$(ASM) -o $(BUILD)/trace.bin test/trace.asm
	$(foreach r,$(TRACE_RUNS),$(call check_trace,$(r)))

analyse:
	@mkdir -p $(BUILD)
	cd $(BUILD) && $(GHDL) -a --std=08 $(addprefix ../,$(SOURCES) $(SIM_SOURCES) $(TEST_SOURCES))

emulator:
	$(MAKE) -C ../emulator build

clean:
	rm -rf $(BUILD)

.PHONY: test analyse emulator clean
