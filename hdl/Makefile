GHDL ?= ghdl
PYTHON ?= python3
ASM = $(PYTHON) ../assembler/niceasm.py
EMU = ../emulator/zig-out/bin/niceemu
BUILD = build

SOURCES = src/nice_pkg.vhd src/trace_pkg.vhd src/pipe_pkg.vhd src/multicycle.vhd src/pipe_fetch.vhd src/pipe_decode.vhd src/pipe_prepare.vhd src/pipe_dbus.vhd src/pipe_write.vhd src/pipeline.vhd src/mpu.vhd src/perf.vhd src/timer.vhd src/fetch_stats.vhd src/wb_dmux.vhd
SIM_SOURCES = sim/wb_mem.vhd sim/trace.vhd
TEST_SOURCES = test/tb_mem.vhd test/tb_shift.vhd test/tb_mpu.vhd test/tb_perf.vhd test/tb_timer.vhd test/tb_fetch_stats.vhd test/tb_wb_dmux.vhd \
  test/tb_trace.vhd test/tb_core.vhd

# The runs of make test and make random go in parallel: each
# is a target run/GROUP/NAME, where GROUP is unit, trace, or a core. A run
# leaves its files in its own directory, RUNDIR, $(BUILD)/run/GROUP/NAME,
# and GHDL runs there, because its LLVM and GCC backends write an
# executable where they run. Paths given to GHDL are absolute. The runs
# take JOBS jobs, one per CPU, unless make was given -j; their PASS and FAIL
# lines come in the order they finish.
JOBS ?= $(shell nproc)
PARALLEL = $(if $(filter -j%,$(MAKEFLAGS)),,-j$(JOBS)) -O
RUNDIR = $(BUILD)/$@
GHDLRUN = $(GHDL) --elab-run --std=08 --workdir=$(abspath $(BUILD))
# Empties RUNDIR and changes to it, in the shell of one recipe line.
in_rundir = rm -rf $(RUNDIR) && mkdir -p $(RUNDIR) && cd $(RUNDIR)

# The programs that the runs assemble, from test/ or written by a script.
$(BUILD)/%.bin: test/%.nasm ../assembler/niceasm.py
	@mkdir -p $(BUILD)
	@$(ASM) -o $@ $<

$(BUILD)/%.bin: $(BUILD)/%.nasm ../assembler/niceasm.py
	@$(ASM) -o $@ $<

# The scripts write their programs as .nasm files, which are kept.
.PRECIOUS: $(BUILD)/%.nasm

$(BUILD)/%.nasm: test/%_prog.py
	@mkdir -p $(BUILD)
	@$(PYTHON) $< $@

# tb_mem checks the memory model itself, tb_shift the ALU and the shifter of
# src/nice_pkg.vhd, tb_mpu the math unit, tb_perf the performance counters,
# tb_timer the timer, tb_fetch_stats the fetch statistics, and tb_wb_dmux
# the data bus decoder.
UNITS = tb_mem tb_shift tb_mpu tb_perf tb_timer tb_fetch_stats tb_wb_dmux
GENERICS_tb_mem = -gG_BIN_FILE=$(abspath test/mem.bin) -gG_INPUT_FILE=$(abspath test/mem.input)

$(UNITS:%=run/unit/%): run/unit/%:
	@($(in_rundir) && $(GHDLRUN) $* $(GENERICS_$*) > $*.log 2>&1); \
	if [ $$? -eq 0 ]; then echo "PASS $*"; else echo "FAIL $*"; cat $(RUNDIR)/$*.log; exit 1; fi

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
	@($(in_rundir) && $(GHDLRUN) tb_trace -gG_BIN_FILE=$(abspath $(BUILD)/trace.bin) -gG_TRACE_FILE=trace.out \
	  $(GENERICS_$(1)) > trace.log 2>&1); echo "exit $$?" >> $(RUNDIR)/trace.out
	@$(EMU) $(OPTS_$(1)) $(BUILD)/trace.bin < /dev/null > $(RUNDIR)/trace.expected; \
	  echo "exit $$?" >> $(RUNDIR)/trace.expected
	@if cmp -s $(RUNDIR)/trace.expected $(RUNDIR)/trace.out; then echo "PASS tb_trace $(1)"; \
	else echo "FAIL tb_trace $(1)"; cat $(RUNDIR)/trace.log; \
	  diff $(RUNDIR)/trace.expected $(RUNDIR)/trace.out; exit 1; fi

endef

$(TRACE_RUNS:%=run/trace/%): run/trace/%: $(BUILD)/trace.bin
	$(call check_trace,$*)

# The core that tb_core runs, its generic G_CORE: multicycle for
# src/multicycle.vhd, or pipeline for src/pipeline.vhd. The PASS and FAIL
# lines name it. make test runs the cores of CORES; make random and make
# programs run CORE.
CORE ?= multicycle
CORES ?= multicycle pipeline

# tb_core runs a program on the core. Its trace, output, and
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
# The program of the interrupt timing diagram, doc/interrupt.tex: a request
# taken at once, and one that comes just after a data read was issued.
INTR_irqwave = --irq 2:9 --irq 10:9
# The runs whose program starts the timer, which raises requests too.
TIMER_timer       = yes
TIMER_timer_stall = yes
# A run has interrupt requests from the options or from the timer.
requests = $(INTR_$(1))$(TIMER_$(1))
# The console input of a run, a file, as the emulator's --input takes it.
INPUT_input = ../emulator/test/input.txt

# $(1) is the name of the run, $(2) the program, and $(3) any more generics.
define check_core
	@($(in_rundir) && $(GHDLRUN) tb_core -gG_CORE=$(CORE) -gG_BIN_FILE=$(abspath $(2)) -gG_TRACE_FILE=core.out \
	  $(if $(INTR_$(1)),"-gG_INTERRUPTS=$(INTR_$(1))") \
	  $(if $(call requests,$(1)),-gG_INTR_LOG=core.intr) \
	  $(if $(INPUT_$(1)),-gG_INPUT_FILE=$(abspath $(INPUT_$(1)))) \
	  $(3) > core.log 2>&1); echo "exit $$?" >> $(RUNDIR)/core.out
	@$(EMU) -t $(INTR_$(1)) $(if $(INPUT_$(1)),--input $(INPUT_$(1))) $(2) < /dev/null \
	  > $(RUNDIR)/core.expected; \
	  echo "exit $$?" >> $(RUNDIR)/core.expected
	$(if $(and $(call requests,$(1)),$(IRQ_LATE)),,@if cmp -s $(RUNDIR)/core.expected $(RUNDIR)/core.out; \
	then echo "PASS $(CORE) $(1)"; \
	else echo "FAIL $(CORE) $(1)"; cat $(RUNDIR)/core.log; \
	  diff $(RUNDIR)/core.expected $(RUNDIR)/core.out | head -20; exit 1; fi)
	$(if $(call requests,$(1)),@$(IRQ_COMPARE) --name $(1) $(2) $(RUNDIR)/core.out $(RUNDIR)/core.intr)

endef

# A run with interrupt requests is also compared with test/irq_compare.py,
# which runs the emulator with the steps where the core took each request,
# from the core's interrupt log, and checks that none was taken late. On
# the multi-cycle core it must agree with the comparison above, which uses
# the steps the requests were raised for (MICROARCH.md §9).
# The pipelined core may take a request after instructions that had issued
# a data read when it came (MICROARCH.md §6), so for it the comparison above
# cannot be exact, and irq_compare.py alone judges the runs with requests.
IRQ_LATE = $(if $(filter pipeline,$(CORE)),--read-delay)
# The delays in cycles with which irq_sweep.py raises each request, so that
# it arrives at different points within an instruction.
SWEEP_DELAYS_multicycle = 0,3,7
SWEEP_DELAYS_pipeline = 0,1,2,3
IRQ_COMPARE = $(PYTHON) test/irq_compare.py --emu $(EMU) $(IRQ_LATE)

# The hazard programs of MICROARCH.md §9, step 4: test/hazard.nasm, the
# programs that test/sidefx_prog.py and test/smc_prog.py write, and the
# HAZARD_PROGS below, each also on a memory that stalls. smc_prog.py's
# program stores into its own code 1 to 40 words ahead, and checks itself
# like hazard.nasm.
# hazard.nasm checks itself, so the emulator's run must end at its last HALT,
# with R12 = 0 and exit status 0, before the core's trace means anything.
# test/irq_sweep.py then runs hazard.nasm with an NMI before each of its
# steps, and with an IRQ before each, on the stalling memory (MICROARCH.md
# §9, step 5). It runs them in parallel, on all cores.
define check_selfcheck
	@if grep -q '^R12 00000000' $(RUNDIR)/core.expected && \
	  tail -n 1 $(RUNDIR)/core.expected | grep -qx 'exit 0'; then echo "PASS emulator $(1)"; \
	else echo "FAIL emulator $(1): the program's own checks failed"; \
	  tail -n 6 $(RUNDIR)/core.expected; exit 1; fi

endef

# $(1) is the program, in $(BUILD), and $(2) any more options.
define check_sweep
	@$(PYTHON) test/irq_sweep.py --core $(CORE) $(IRQ_LATE) $(2) --stall 30 --build $(BUILD) --emu $(EMU) \
	  $(BUILD)/$(1).bin

endef

# The programs of the third repository review against the operand rules of
# the re-timed core (doc/review/third-repository-review.md §1.5): the shift
# counts WRITE reduces in a cycle of its own, the destinations adjusted by
# one, R14 and R15 in every field, R0, stores into fetched code from late
# instructions, the read counter and the instruction counter around them,
# jumps into constant words, and every shift into R15. Each runs on both
# cores, plain and on a stalling memory, compared with the emulator, and
# irqhazard also with a request before each step, through
# test/irq_sweep.py, without delays. test/samereg_prog.py writes one more,
# with one register in all three fields of a shift.
HAZARD_PROGS = latecount twocycle r15mix r14cond r0odd smclate readorder instret_late \
  jumpwords condlate irqhazard shiftjump

# test/fstats.nasm reads the fetch statistics (MICROARCH.md §8.1), which
# only the pipelined core has, and checks itself. The emulator has none, so the run
# is not compared with it: it must end at the last HALT, with R12 = 0 and
# exit status 0. test/bubble.nasm measures the bubbles of the pipelined
# core with the cycle counter, which the emulator counts in steps, and
# checks itself the same way. $(1) is the name of the run, $(2) the
# program, and $(3) any more generics.
define check_selfonly
	@($(in_rundir) && $(GHDLRUN) tb_core -gG_CORE=$(CORE) -gG_BIN_FILE=$(abspath $(2)) -gG_TRACE_FILE=core.out \
	  -gG_TRACE=false $(3) > core.log 2>&1); echo "exit $$?" >> $(RUNDIR)/core.out
	@if grep -q '^R12 00000000' $(RUNDIR)/core.out && \
	  tail -n 1 $(RUNDIR)/core.out | grep -qx 'exit 0'; then echo "PASS $(CORE) $(1)"; \
	else echo "FAIL $(CORE) $(1)"; cat $(RUNDIR)/core.log; tail -n 6 $(RUNDIR)/core.out; exit 1; fi

endef

# Random programs from test/random_prog.py, each run for RANDOM_STEPS steps
# with random interrupt requests, on a memory that stalls in RANDOM_STALL
# percent of the cycles, and compared in the same way. A random program
# may read any address, so the cycle counter, which the core and the
# emulator count differently, is memory in both: G_CYCLE_COUNTER=false and
# --no-cycle-counter. So are the fetch statistics, which the emulator has
# as memory: G_FETCH_STATS=false. random_prog.py writes the program, and
# prints the requests, which go in random_N.opts.
RANDOM_SEEDS = $(shell seq 1 30)
RANDOM_STEPS = 3000
RANDOM_STALL = 30

$(BUILD)/random_%.bin $(BUILD)/random_%.opts: test/random_prog.py
	@mkdir -p $(BUILD)
	@$(PYTHON) test/random_prog.py $* $(BUILD)/random_$*.bin > $(BUILD)/random_$*.opts

define check_random
	@o=$$(cat $(BUILD)/random_$(1).opts); \
	  ($(in_rundir) && $(GHDLRUN) tb_core -gG_CORE=$(CORE) -gG_BIN_FILE=$(abspath $(BUILD)/random_$(1).bin) \
	  -gG_TRACE_FILE=core.out -gG_MAX_STEPS=$(RANDOM_STEPS) -gG_STALL=$(RANDOM_STALL) -gG_SEED=$(1) \
	  -gG_CYCLE_COUNTER=false -gG_FETCH_STATS=false \
	  $${o:+"-gG_INTERRUPTS=$$o"} -gG_INTR_LOG=core.intr > core.log 2>&1); \
	  echo "exit $$?" >> $(RUNDIR)/core.out
	@$(EMU) -t -n $(RANDOM_STEPS) --no-cycle-counter $$(cat $(BUILD)/random_$(1).opts) $(BUILD)/random_$(1).bin \
	  < /dev/null > $(RUNDIR)/core.expected; echo "exit $$?" >> $(RUNDIR)/core.expected
	$(if $(IRQ_LATE),,@if cmp -s $(RUNDIR)/core.expected $(RUNDIR)/core.out; then echo "PASS $(CORE) random $(1)"; \
	else echo "FAIL $(CORE) random $(1)"; cat $(RUNDIR)/core.log; \
	  diff $(RUNDIR)/core.expected $(RUNDIR)/core.out | head -20; exit 1; fi)
	@$(IRQ_COMPARE) --name random_$(1) $(BUILD)/random_$(1).bin $(RUNDIR)/core.out \
	  $(RUNDIR)/core.intr -- -n $(RANDOM_STEPS) --no-cycle-counter

endef

# The target of one run on a core, run/CORE/NAME, which RUNS_CORE lists:
# $(1) is the core, $(2) the name of the run, $(3) the program, $(4) any
# more generics, and $(5) the defines that make the run, called with the
# name, the program, and the generics; check_core if empty. The program
# is a prerequisite if it is made in $(BUILD).
define core_run
RUNS_$(1) += run/$(1)/$(2)
.PHONY: run/$(1)/$(2)
run/$(1)/$(2): override CORE = $(1)
run/$(1)/$(2): $(filter $(BUILD)/%,$(3))
	$(foreach d,$(or $(5),check_core),$$(call $(d),$(2),$(3),$(4)))

endef

# The same for a sweep of test/irq_sweep.py, run/CORE/sweep_PROGRAM: $(1)
# is the core, $(2) the program, in $(BUILD), and $(3) any more options.
define sweep_run
RUNS_$(1) += run/$(1)/sweep_$(2)
.PHONY: run/$(1)/sweep_$(2)
run/$(1)/sweep_$(2): override CORE = $(1)
run/$(1)/sweep_$(2): $(BUILD)/$(2).bin
	$$(call check_sweep,$(2),$(3))

endef

# The same for a random program, run/CORE/random_SEED, which RANDOM_CORE
# lists too: $(1) is the core and $(2) the seed.
define random_run
RUNS_$(1) += run/$(1)/random_$(2)
RANDOM_$(1) += run/$(1)/random_$(2)
.PHONY: run/$(1)/random_$(2)
run/$(1)/random_$(2): override CORE = $(1)
run/$(1)/random_$(2): $(BUILD)/random_$(2).bin $(BUILD)/random_$(2).opts
	$$(call check_random,$(2))

endef

# The runs of the core $(1). The sweeps take longest, so they come first,
# and make starts them first.
define core_runs
$(eval $(call sweep_run,$(1),hazard,--delays $$(SWEEP_DELAYS_$(1)) --self-check))
$(eval $(call sweep_run,$(1),irqhazard))
$(foreach t,$(EXAMPLES),$(eval $(call core_run,$(1),$(t),../assembler/test/$(t).bin)))
$(foreach t,$(PROBES),$(eval $(call core_run,$(1),$(t),../emulator/test/$(t).bin)))
$(eval $(call core_run,$(1),shift,$(BUILD)/shift.bin))
$(eval $(call core_run,$(1),cputest_stall,../emulator/test/cputest.bin,-gG_STALL=30))
$(eval $(call core_run,$(1),reads_stall,../emulator/test/reads.bin,-gG_STALL=30 -gG_SEED=7))
$(eval $(call core_run,$(1),mpu_stall,../emulator/test/mpu.bin,-gG_STALL=30 -gG_SEED=3))
$(eval $(call core_run,$(1),mpu64_stall,../emulator/test/mpu64.bin,-gG_STALL=30 -gG_SEED=5))
$(eval $(call core_run,$(1),perf_stall,../emulator/test/perf.bin,-gG_STALL=30 -gG_SEED=9))
$(eval $(call core_run,$(1),timer_stall,../emulator/test/timer.bin,-gG_STALL=30 -gG_SEED=11))
$(eval $(call core_run,$(1),instret,$(BUILD)/instret.bin))
$(eval $(call core_run,$(1),instret_stall,$(BUILD)/instret.bin,-gG_STALL=30 -gG_SEED=17))
$(eval $(call core_run,$(1),irqwave,$(BUILD)/irqwave.bin))
$(eval $(call core_run,$(1),hazard,$(BUILD)/hazard.bin,,check_core check_selfcheck))
$(eval $(call core_run,$(1),hazard_stall,$(BUILD)/hazard.bin,-gG_STALL=30 -gG_SEED=13))
$(eval $(call core_run,$(1),sidefx,$(BUILD)/sidefx.bin))
$(eval $(call core_run,$(1),sidefx_stall,$(BUILD)/sidefx.bin,-gG_STALL=30 -gG_SEED=15))
$(eval $(call core_run,$(1),smc,$(BUILD)/smc.bin,,check_core check_selfcheck))
$(eval $(call core_run,$(1),smc_stall,$(BUILD)/smc.bin,-gG_STALL=30 -gG_SEED=21))
$(foreach t,$(HAZARD_PROGS),$(eval $(call core_run,$(1),$(t),$(BUILD)/$(t).bin)))
$(foreach t,$(HAZARD_PROGS),$(eval $(call core_run,$(1),$(t)_stall,$(BUILD)/$(t).bin,-gG_STALL=30 -gG_SEED=25)))
$(eval $(call core_run,$(1),samereg,$(BUILD)/samereg.bin))
$(eval $(call core_run,$(1),samereg_stall,$(BUILD)/samereg.bin,-gG_STALL=30 -gG_SEED=27))
$(if $(filter pipeline,$(1)),$(eval $(call core_run,$(1),fstats,$(BUILD)/fstats.bin,,check_selfonly)))
$(if $(filter pipeline,$(1)),$(eval $(call core_run,$(1),fstats_stall,$(BUILD)/fstats.bin,-gG_STALL=30 -gG_SEED=19,check_selfonly)))
$(if $(filter pipeline,$(1)),$(eval $(call core_run,$(1),bubble,$(BUILD)/bubble.bin,,check_selfonly)))
$(foreach t,$(RANDOM_SEEDS),$(eval $(call random_run,$(1),$(t))))
endef

$(foreach c,$(sort $(CORES) $(CORE)),$(eval $(call core_runs,$(c))))

test: emulator analyse synth
	@$(MAKE) --no-print-directory $(PARALLEL) runs

# The runs of make test: the unit tests, tb_trace, and those of each core in
# CORES.
runs: $(UNITS:%=run/unit/%) $(TRACE_RUNS:%=run/trace/%) $(foreach c,$(CORES),$(RUNS_$(c)))

# More random programs than make test runs, for example
#     make random RANDOM_SEEDS="$$(seq 31 90)" RANDOM_STALL=60 RANDOM_STEPS=5000
# test/trace_reads.py shows the data reads of the first instruction where
# the emulator's trace and the core's differ.
random: emulator analyse
	@$(MAKE) --no-print-directory $(PARALLEL) $(RANDOM_$(CORE))

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
	@$(PYTHON) test/programs.py --core $(CORE) --build $(BUILD) --emu $(EMU) $(PROGRAMS)/runtime $(PROGRAMS)/translator

analyse:
	@mkdir -p $(BUILD)
	cd $(BUILD) && $(GHDL) -a --std=08 $(addprefix ../,$(SOURCES) $(SIM_SOURCES) $(TEST_SOURCES))

# Checks that GHDL can synthesise the core, the math unit, the performance
# counters, the timer, and the data bus decoder, with the generics in
# SYNTH_GENERICS_unit.
SYNTH = multicycle pipeline mpu perf timer fetch_stats wb_dmux
SYNTH_GENERICS_wb_dmux = -gG_SLAVES=4

define check_synth
	@cd $(BUILD) && $(GHDL) --synth --std=08 $(SYNTH_GENERICS_$(1)) $(1) > $(1)_synth.vhd 2> synth_$(1).log; \
	if [ $$? -eq 0 ]; then echo "PASS synth $(1)"; else echo "FAIL synth $(1)"; cat synth_$(1).log; exit 1; fi

endef

synth: analyse
	$(foreach u,$(SYNTH),$(call check_synth,$(u)))

# The formal checks of formal/: each task of each .sby file must pass. The
# work directories go in $(BUILD).
SBY ?= sby
FORMAL = multicycle timer wb_dmux pipe_fetch pipe_prepare pipe_dbus pipeline
FORMAL_TASKS = prove cover
# The pipelined core is checked for a bounded number of cycles only.
FORMAL_TASKS_pipeline = bmc cover

define check_formal
	@mkdir -p $(BUILD)
	@cd formal && $(SBY) -f --prefix ../$(BUILD)/$(1) $(1).sby $(2) > ../$(BUILD)/formal_$(1)_$(2).log 2>&1; \
	if [ $$? -eq 0 ]; then echo "PASS formal $(1) $(2)"; else echo "FAIL formal $(1) $(2)"; \
	  grep -E "Assert failed|Unreached|ERROR|summary: +(failed|counterexample|unreached)" \
	    ../$(BUILD)/formal_$(1)_$(2).log; exit 1; fi

endef

formal:
	$(foreach f,$(FORMAL),$(foreach t,$(or $(FORMAL_TASKS_$(f)),$(FORMAL_TASKS)),$(call check_formal,$(f),$(t))))

emulator:
	$(MAKE) -C ../emulator build

# The out-of-context timing of the pipelined core in Vivado, which timing.tcl
# describes: the worst register-to-register paths go to build/timing.rpt, and
# the worst one is printed. About 10 minutes.
VIVADO ?= /opt/Xilinx/2025.1/Vivado/bin/vivado

timing:
	@mkdir -p $(BUILD)
	@cd $(BUILD) && $(VIVADO) -mode batch -nolog -nojournal -source ../timing.tcl > timing.log 2>&1 || \
	  { tail -20 timing.log; exit 1; }
	@grep -m1 -E "^Slack" $(BUILD)/timing.rpt; grep -m2 -E "^  (Source|Destination):" $(BUILD)/timing.rpt

# Checks the style of every VHDL file against CODING_STYLE.md. Long lines are
# only warnings.
VSG ?= vsg

lint:
	$(VSG) -c vsg.yml -of syntastic -f $(SOURCES) $(SIM_SOURCES) $(TEST_SOURCES)

clean:
	rm -rf $(BUILD)

.PHONY: test runs programs random analyse synth formal emulator timing lint clean
