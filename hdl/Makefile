GHDL ?= ghdl
PYTHON ?= python3
ASM = $(PYTHON) ../assembler/niceasm.py
EMU = ../emulator/zig-out/bin/niceemu
BUILD = build
# GHDL runs in $(BUILD), where the LLVM and GCC backends leave their
# executables, so paths given to it start with ../.
GHDLRUN = cd $(BUILD) && $(GHDL) --elab-run --std=08

SOURCES = src/trace_pkg.vhd src/multicycle.vhd src/mpu.vhd src/perf.vhd src/timer.vhd
SIM_SOURCES = sim/wb_mem.vhd sim/trace.vhd
TEST_SOURCES = test/tb_mem.vhd test/tb_mpu.vhd test/tb_perf.vhd test/tb_timer.vhd test/tb_trace.vhd test/tb_multicycle.vhd

# tb_trace stands in for the core and runs test/trace.nasm. Each run's output
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
	@$(EMU) $(OPTS_$(1)) $(BUILD)/trace.bin < /dev/null > $(BUILD)/trace_$(1).expected; \
	  echo "exit $$?" >> $(BUILD)/trace_$(1).expected
	@if cmp -s $(BUILD)/trace_$(1).expected $(BUILD)/trace_$(1).out; then echo "PASS tb_trace $(1)"; \
	else echo "FAIL tb_trace $(1)"; cat $(BUILD)/trace_$(1).log; \
	  diff $(BUILD)/trace_$(1).expected $(BUILD)/trace_$(1).out; exit 1; fi

endef

# tb_multicycle runs a program on the multicycle core. Its trace, output, and
# exit status must equal those of "niceemu -t" on the same program, with the
# same interrupt requests. The programs are the 2004 examples and wrap from
# the assembler's tests, the emulator's probes, with the probes' interrupt
# options from emulator/Makefile, and test/shift.nasm, which runs every shift
# with the counts that are hard to get right. The memory dumps of the probes
# are left out, because the trace lists every memory write. The data reads
# are not in the trace, but the probe reads.nasm counts them with the read
# counter, and its registers show the counts. mpu and mpu64 read every word
# of the math unit, src/mpu.vhd, and their registers and the trace's memory
# writes show the results. perf reads the performance counters,
# src/perf.vhd. Its registers hold only instruction counts and flags, which
# do not depend on the cycles an instruction takes. timer runs the timer,
# src/timer.vhd, which counts steps here, as the emulator's does. cputest,
# reads, mpu, mpu64, perf, and timer run a second time with a memory that
# stalls in 30% of the cycles.
EXAMPLES = count replicate print wrap
PROBES = logic dest carry r15 cond rotate vbase selfmod addr irq merge after start cputest \
  console screen iofetch reads reserved mpu mpu64 perf timer input
INTR_irq   = --nmi 2:1 --irq 2:2 --nmi 9:1 --irq 17:2 --nmi 17:1 --irq 100:2
INTR_merge = --nmi 1:1 --nmi 1:2 --irq 1:3 --irq 4:4 --irq 7:5
INTR_after = --nmi 3:1 --nmi 10:1
INTR_start = --nmi 0:3
INTR_perf  = --nmi 3:0x41
INTR_perf_stall = $(INTR_perf)
# The console input of a run, a file, as the emulator's --input takes it.
INPUT_input = ../emulator/test/input.txt

# $(1) is the name of the run, $(2) the program, and $(3) any more generics.
define check_core
	@($(GHDLRUN) tb_multicycle -gG_BIN_FILE=../$(2) -gG_TRACE_FILE=core_$(1).out \
	  $(if $(INTR_$(1)),"-gG_INTERRUPTS=$(INTR_$(1))") $(if $(INPUT_$(1)),-gG_INPUT_FILE=../$(INPUT_$(1))) \
	  $(3) > core_$(1).log 2>&1); echo "exit $$?" >> $(BUILD)/core_$(1).out
	@$(EMU) -t $(INTR_$(1)) $(if $(INPUT_$(1)),--input $(INPUT_$(1))) $(2) < /dev/null \
	  > $(BUILD)/core_$(1).expected; \
	  echo "exit $$?" >> $(BUILD)/core_$(1).expected
	@if cmp -s $(BUILD)/core_$(1).expected $(BUILD)/core_$(1).out; then echo "PASS multicycle $(1)"; \
	else echo "FAIL multicycle $(1)"; cat $(BUILD)/core_$(1).log; \
	  diff $(BUILD)/core_$(1).expected $(BUILD)/core_$(1).out | head -20; exit 1; fi

endef

# The hazard programs of MICROARCH.md §9, step 4: test/hazard.nasm, and the
# program that test/sidefx_prog.py writes, each also on a memory that stalls.
# hazard.nasm checks itself, so the emulator's run must end at its last HALT,
# with R12 = 0 and exit status 0, before the core's trace means anything.
# test/irq_sweep.py then runs hazard.nasm with an NMI before each of its
# steps, and with an IRQ before each, on the stalling memory (MICROARCH.md
# §9, step 5). It runs them in parallel, on all cores.
define check_selfcheck
	@if grep -q '^R12 00000000' $(BUILD)/core_$(1).expected && \
	  tail -n 1 $(BUILD)/core_$(1).expected | grep -qx 'exit 0'; then echo "PASS emulator $(1)"; \
	else echo "FAIL emulator $(1): the program's own checks failed"; \
	  tail -n 6 $(BUILD)/core_$(1).expected; exit 1; fi

endef

# Random programs from test/random_prog.py, each run for RANDOM_STEPS steps
# with random interrupt requests, on a memory that stalls in RANDOM_STALL
# percent of the cycles, and compared in the same way. A random program
# may read any address, so the cycle counter, which the core and the
# emulator count differently, is memory in both: G_CYCLE_COUNTER=false and
# --no-cycle-counter.
RANDOM_SEEDS = $(shell seq 1 30)
RANDOM_STEPS = 3000
RANDOM_STALL = 30

define check_random
	@$(PYTHON) test/random_prog.py $(1) $(BUILD)/random_$(1).bin > $(BUILD)/random_$(1).opts
	@o=$$(cat $(BUILD)/random_$(1).opts); \
	  ($(GHDLRUN) tb_multicycle -gG_BIN_FILE=random_$(1).bin -gG_TRACE_FILE=random_$(1).out \
	  -gG_MAX_STEPS=$(RANDOM_STEPS) -gG_STALL=$(RANDOM_STALL) -gG_SEED=$(1) -gG_CYCLE_COUNTER=false \
	  $${o:+"-gG_INTERRUPTS=$$o"} > random_$(1).log 2>&1); \
	  echo "exit $$?" >> $(BUILD)/random_$(1).out
	@$(EMU) -t -n $(RANDOM_STEPS) --no-cycle-counter $$(cat $(BUILD)/random_$(1).opts) $(BUILD)/random_$(1).bin \
	  < /dev/null > $(BUILD)/random_$(1).expected; echo "exit $$?" >> $(BUILD)/random_$(1).expected
	@if cmp -s $(BUILD)/random_$(1).expected $(BUILD)/random_$(1).out; then echo "PASS multicycle random $(1)"; \
	else echo "FAIL multicycle random $(1)"; cat $(BUILD)/random_$(1).log; \
	  diff $(BUILD)/random_$(1).expected $(BUILD)/random_$(1).out | head -20; exit 1; fi

endef

# tb_mem checks the memory model itself, tb_mpu the math unit, tb_perf the
# performance counters, and tb_timer the timer.
test: emulator analyse synth
	@($(GHDLRUN) tb_mem -gG_BIN_FILE=../test/mem.bin -gG_INPUT_FILE=../test/mem.input > tb_mem.log 2>&1); \
	if [ $$? -eq 0 ]; then echo "PASS tb_mem"; else echo "FAIL tb_mem"; cat $(BUILD)/tb_mem.log; exit 1; fi
	@($(GHDLRUN) tb_mpu > tb_mpu.log 2>&1); \
	if [ $$? -eq 0 ]; then echo "PASS tb_mpu"; else echo "FAIL tb_mpu"; cat $(BUILD)/tb_mpu.log; exit 1; fi
	@($(GHDLRUN) tb_perf > tb_perf.log 2>&1); \
	if [ $$? -eq 0 ]; then echo "PASS tb_perf"; else echo "FAIL tb_perf"; cat $(BUILD)/tb_perf.log; exit 1; fi
	@($(GHDLRUN) tb_timer > tb_timer.log 2>&1); \
	if [ $$? -eq 0 ]; then echo "PASS tb_timer"; else echo "FAIL tb_timer"; cat $(BUILD)/tb_timer.log; exit 1; fi
	@$(ASM) -o $(BUILD)/trace.bin test/trace.nasm
	$(foreach r,$(TRACE_RUNS),$(call check_trace,$(r)))
	$(foreach t,$(EXAMPLES),$(call check_core,$(t),../assembler/test/$(t).bin))
	$(foreach t,$(PROBES),$(call check_core,$(t),../emulator/test/$(t).bin))
	@$(ASM) -o $(BUILD)/shift.bin test/shift.nasm
	$(call check_core,shift,$(BUILD)/shift.bin)
	$(call check_core,cputest_stall,../emulator/test/cputest.bin,-gG_STALL=30)
	$(call check_core,reads_stall,../emulator/test/reads.bin,-gG_STALL=30 -gG_SEED=7)
	$(call check_core,mpu_stall,../emulator/test/mpu.bin,-gG_STALL=30 -gG_SEED=3)
	$(call check_core,mpu64_stall,../emulator/test/mpu64.bin,-gG_STALL=30 -gG_SEED=5)
	$(call check_core,perf_stall,../emulator/test/perf.bin,-gG_STALL=30 -gG_SEED=9)
	$(call check_core,timer_stall,../emulator/test/timer.bin,-gG_STALL=30 -gG_SEED=11)
	@$(ASM) -o $(BUILD)/hazard.bin test/hazard.nasm
	$(call check_core,hazard,$(BUILD)/hazard.bin)
	$(call check_selfcheck,hazard)
	$(call check_core,hazard_stall,$(BUILD)/hazard.bin,-gG_STALL=30 -gG_SEED=13)
	@$(PYTHON) test/irq_sweep.py --self-check --stall 30 --build $(BUILD) --emu $(EMU) $(BUILD)/hazard.bin
	@$(PYTHON) test/sidefx_prog.py $(BUILD)/sidefx.nasm
	@$(ASM) -o $(BUILD)/sidefx.bin $(BUILD)/sidefx.nasm
	$(call check_core,sidefx,$(BUILD)/sidefx.bin)
	$(call check_core,sidefx_stall,$(BUILD)/sidefx.bin,-gG_STALL=30 -gG_SEED=15)
	$(foreach t,$(RANDOM_SEEDS),$(call check_random,$(t)))

# More random programs than make test runs, for example
#     make random RANDOM_SEEDS="$$(seq 31 90)" RANDOM_STALL=60 RANDOM_STEPS=5000
# test/trace_reads.py shows the data reads of the first instruction where
# the emulator's trace and the core's differ.
random: emulator analyse
	$(foreach t,$(RANDOM_SEEDS),$(call check_random,$(t)))

# The runtime's and the translator's test programs on the core (MICROARCH.md
# §9, step 6). runtime/Makefile with KEEP and translator/test/run.py with
# --keep run their tests and leave the programs in $(PROGRAMS), and
# test/programs.py runs each on the core and on the emulator, in parallel,
# and compares them. It takes minutes, so make test leaves it out.
PROGRAMS = $(BUILD)/programs

programs: emulator analyse
	@rm -rf $(PROGRAMS)
	@$(MAKE) --no-print-directory -C ../runtime test KEEP=$(abspath $(PROGRAMS)/runtime) \
	  > $(BUILD)/programs_runtime.log 2>&1 || { cat $(BUILD)/programs_runtime.log; exit 1; }
	@$(PYTHON) ../translator/test/run.py --keep $(PROGRAMS)/translator \
	  > $(BUILD)/programs_translator.log 2>&1 || { cat $(BUILD)/programs_translator.log; exit 1; }
	@$(PYTHON) test/programs.py --build $(BUILD) --emu $(EMU) $(PROGRAMS)/runtime $(PROGRAMS)/translator

analyse:
	@mkdir -p $(BUILD)
	cd $(BUILD) && $(GHDL) -a --std=08 $(addprefix ../,$(SOURCES) $(SIM_SOURCES) $(TEST_SOURCES))

# Checks that GHDL can synthesise the core, the math unit, the performance
# counters, and the timer.
SYNTH = multicycle mpu perf timer

define check_synth
	@cd $(BUILD) && $(GHDL) --synth --std=08 $(1) > $(1)_synth.vhd 2> synth_$(1).log; \
	if [ $$? -eq 0 ]; then echo "PASS synth $(1)"; else echo "FAIL synth $(1)"; cat synth_$(1).log; exit 1; fi

endef

synth: analyse
	$(foreach u,$(SYNTH),$(call check_synth,$(u)))

# The formal checks of formal/: each task of each .sby file must pass. The
# work directories go in $(BUILD).
SBY ?= sby
FORMAL = multicycle timer
FORMAL_TASKS = prove cover

define check_formal
	@mkdir -p $(BUILD)
	@cd formal && $(SBY) -f --prefix ../$(BUILD)/$(1) $(1).sby $(2) > ../$(BUILD)/formal_$(1)_$(2).log 2>&1; \
	if [ $$? -eq 0 ]; then echo "PASS formal $(1) $(2)"; else echo "FAIL formal $(1) $(2)"; \
	  grep -E "Assert failed|Unreached|ERROR|summary: +(failed|counterexample|unreached)" \
	    ../$(BUILD)/formal_$(1)_$(2).log; exit 1; fi

endef

formal:
	$(foreach f,$(FORMAL),$(foreach t,$(FORMAL_TASKS),$(call check_formal,$(f),$(t))))

emulator:
	$(MAKE) -C ../emulator build

# Checks the style of every VHDL file against CODING_STYLE.md. Long lines are
# only warnings.
VSG ?= vsg

lint:
	$(VSG) -c vsg.yml -of syntastic -f $(SOURCES) $(SIM_SOURCES) $(TEST_SOURCES)

clean:
	rm -rf $(BUILD)

.PHONY: test programs random analyse synth formal emulator lint clean
