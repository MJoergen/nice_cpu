GHDL ?= ghdl
PYTHON ?= python3
ASM = $(PYTHON) ../assembler/niceasm.py
EMU = ../emulator/zig-out/bin/niceemu
BUILD = build

SOURCES = src/nice_pkg.vhd src/trace_pkg.vhd src/pipe_pkg.vhd src/multicycle.vhd src/pipe_fetch.vhd src/pipe_decode.vhd src/pipe_prepare.vhd src/pipe_dbus.vhd src/pipe_write.vhd src/pipeline.vhd src/mpu.vhd src/perf.vhd src/timer.vhd src/fetch_stats.vhd src/wb_dmux.vhd src/debug_link.vhd
SIM_SOURCES = sim/wb_mem.vhd sim/trace.vhd
TEST_SOURCES = test/tb_mem.vhd test/tb_shift.vhd test/tb_mpu.vhd test/tb_perf.vhd test/tb_perf_hz.vhd test/tb_timer.vhd test/tb_fetch_stats.vhd test/tb_wb_dmux.vhd test/tb_debug_link.vhd test/tb_link.vhd \
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
UNITS = tb_mem tb_shift tb_mpu tb_perf tb_perf_hz tb_timer tb_fetch_stats tb_wb_dmux tb_debug_link
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

# The core that tb_core runs, its generic G_CORE: pipeline for
# src/pipeline.vhd, or multicycle for src/multicycle.vhd. The PASS and FAIL
# lines name it. make test runs the cores of CORES; make random and make
# programs run CORE.
CORE ?= pipeline
CORES ?= pipeline multicycle

# tb_link connects the debug link to a core, the data bus decoder, the
# memory model, and the math unit, and loads and runs test/linkecho.nasm
# over the link. It runs on each core of CORES.
LINK_RUNS = $(CORES:%=run/link/%)

$(LINK_RUNS): run/link/%: $(BUILD)/linkecho.bin
	@($(in_rundir) && $(GHDLRUN) tb_link -gG_CORE=$* -gG_INIT_FILE=$(abspath test/link_init.bin) \
	  -gG_PROG_FILE=$(abspath $(BUILD)/linkecho.bin) > tb_link.log 2>&1); \
	if [ $$? -eq 0 ]; then echo "PASS tb_link $*"; else echo "FAIL tb_link $*"; cat $(RUNDIR)/tb_link.log; exit 1; fi

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
# stalls in 30% of the cycles. cputest and after run again with random
# pauses, and cputest and irq with pauses held for a random time, so that
# requests come while the core is paused. cputest, reads, irq, and
# test/rtiread.nasm run one step at a time. rtiread returns from an
# interrupt to instructions with data reads, which a step over RTI must not
# run. These are G_PAUSE, G_PAUSE_HOLD, and G_SINGLE_STEP of
# test/tb_core.vhd, and must not change the trace (MICROARCH.md §6.1).
EXAMPLES = count replicate print wrap
PROBES = logic dest carry r15 cond rotate vbase selfmod addr irq merge after start cputest \
  console screen iofetch reads reserved mpu mpu64 perf timer input \
  r15modes r0dest r14mem skipconst carryin shiftc wrapmem smcown
INTR_irq   = --nmi 2:1 --irq 2:2 --nmi 9:1 --irq 17:2 --nmi 17:1 --irq 100:2
INTR_merge = --nmi 1:1 --nmi 1:2 --irq 1:3 --irq 4:4 --irq 7:5
INTR_after = --nmi 3:1 --nmi 10:1
INTR_start = --nmi 0:3
INTR_perf  = --nmi 3:0x41
INTR_perf_stall = $(INTR_perf)
INTR_irq_step   = $(INTR_irq)
INTR_irq_hold   = $(INTR_irq)
INTR_after_pause = $(INTR_after)
INTR_rtiread_step = --nmi 2:1 --nmi 5:1
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

# test/breaks.nasm stops at the breakpoints of BREAKS_breaks, in hex, with
# the requests of INTR_breaks: in a loop, at an instruction with a data
# read, at a false condition, at an interrupt routine, after an RTI, and
# with an IRQ pending at a jump target and at an instruction that the
# pipelined core holds already (doc/DEBUG.md §6). tb_core's
# G_BREAK_AT sets them, and its G_BREAK_LOG lists the stops. check_breaks
# compares that list with the emulator's, from test/break_stops.py. The
# run breaks_stall does the same on a stalling memory, and breaks_hold
# adds pauses held for a random time, which must not change the trace.
# A pause at a breakpoint is not a stop of the core's own, so that run's
# list is not compared.
BREAKS_breaks = 4 5 8 D
BREAKS_breaks_stall = $(BREAKS_breaks)
INTR_breaks = --irq 6:2 --nmi 8:2 --irq 18:2
INTR_breaks_stall = $(INTR_breaks)
INTR_breaks_hold = $(INTR_breaks)
BREAK_GENERICS = "-gG_BREAK_AT=$(BREAKS_breaks)" -gG_BREAK_LOG=stops.out

# $(1) is the name of the run, and $(2) the program.
define check_breaks
	@$(PYTHON) test/break_stops.py --emu $(EMU) $(2) "$(BREAKS_$(1))" -- $(INTR_$(1)) \
	  > $(RUNDIR)/stops.expected
	@if cmp -s $(RUNDIR)/stops.expected $(RUNDIR)/stops.out; then echo "PASS $(CORE) $(1) stops"; \
	else echo "FAIL $(CORE) $(1) stops"; diff $(RUNDIR)/stops.expected $(RUNDIR)/stops.out; exit 1; fi

endef

# test/pausepatch.nasm runs one step at a time, and tb_core writes a word
# of its code while the core is paused (G_PATCH_STEP). The emulator sees no
# such write, so the trace is compared with the hand-checked
# test/pausepatch.expected instead. $(1) is the name of the run, $(2) the
# program, and $(3) any more generics.
define check_expected
	@($(in_rundir) && $(GHDLRUN) tb_core -gG_CORE=$(CORE) -gG_BIN_FILE=$(abspath $(2)) -gG_TRACE_FILE=core.out \
	  $(3) > core.log 2>&1); echo "exit $$?" >> $(RUNDIR)/core.out
	@if cmp -s test/$(1).expected $(RUNDIR)/core.out; then echo "PASS $(CORE) $(1)"; \
	else echo "FAIL $(CORE) $(1)"; cat $(RUNDIR)/core.log; \
	  diff test/$(1).expected $(RUNDIR)/core.out | head -20; exit 1; fi

endef

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
SWEEP_STRIDE = 16
IRQ_COMPARE = $(PYTHON) test/irq_compare.py --emu $(EMU) $(IRQ_LATE)

# The hazard programs of MICROARCH.md §9, step 4: test/hazard.nasm, the
# programs that test/sidefx_prog.py, test/pcfx_prog.py, and
# test/smc_prog.py write, and the HAZARD_PROGS below, each also on a
# memory that stalls. pcfx_prog.py's program has every pair of side
# effects on R15, and smc_prog.py's stores into its own code 1 to 40 words
# ahead. Both check themselves like hazard.nasm.
# hazard.nasm checks itself, so the emulator's run must end at its last HALT,
# with R12 = 0 and exit status 0, before the core's trace means anything.
# test/irq_sweep.py then runs hazard.nasm with an NMI before each of its
# steps, and with an IRQ before each, on the stalling memory (MICROARCH.md
# §9, step 5). It runs them in parallel, on all cores. It sweeps
# irqhazard.nasm and latecount.nasm the same way, without the delays, and
# the programs of pcfx_prog.py and sidefx_prog.py with a request before
# every SWEEP_STRIDE-th step in each run, which takes SWEEP_STRIDE runs per
# kind instead of one per step. make sweep sweeps those two with one
# request per run instead, on CORE.
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
# with one register in all three fields of a shift. smcskid came later:
# stores into an instruction in DECODE's skid register.
HAZARD_PROGS = latecount twocycle r15mix r14cond r0odd smclate readorder instret_late \
  jumpwords condlate irqhazard shiftjump smcskid predict

# test/fstats.nasm reads the fetch statistics (MICROARCH.md §8.1), which
# only the pipelined core has, and checks itself. The emulator has none, so the run
# is not compared with it: it must end at the last HALT, with R12 = 0 and
# exit status 0. test/bubble.nasm measures the bubbles of the pipelined
# core with the cycle counter, which the emulator counts in steps, and
# checks itself the same way. $(1) is the name of the run, $(2) the
# program, and $(3) any more generics.
# test/readwait.nasm makes one data read that waits a cycle for its
# condition, one that waits a cycle for an older micro-operation, and one
# on the wrong path that waits 2 cycles for an older one, as tb_core counts
# them on the pipelined core and prints when it halts. $(1) is the name of
# the run.
define check_waits
	@if grep -q ' cycles; went on: 1 for the condition, 1 for an older micro-operation; dropped: 0, 2$$' \
	  $(RUNDIR)/core.log; \
	then echo "PASS $(CORE) $(1) waits"; \
	else echo "FAIL $(CORE) $(1) waits"; grep '^Read waits:' $(RUNDIR)/core.log; exit 1; fi

endef

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
# --no-cycle-counter. The fetch statistics read 0 and ignore writes in
# both: G_FETCH_STATS=false. random_prog.py writes the program, and
# prints the requests, which go in random_N.opts. The seeds of PAUSE_SEEDS
# run again with random pauses, as random_pause_N, and with pauses held for
# a random time, as random_hold_N (G_PAUSE and G_PAUSE_HOLD of
# test/tb_core.vhd), which must not change the trace. In check_random, $(2)
# is any more generics, and $(3) the suffix of the name.
RANDOM_SEEDS = $(shell seq 1 30)
PAUSE_SEEDS = $(shell seq 1 8)
RANDOM_STEPS = 3000
RANDOM_STALL = 30

$(BUILD)/random_%.bin $(BUILD)/random_%.opts: test/random_prog.py
	@mkdir -p $(BUILD)
	@$(PYTHON) test/random_prog.py $* $(BUILD)/random_$*.bin > $(BUILD)/random_$*.opts

define check_random
	@o=$$(cat $(BUILD)/random_$(1).opts); \
	  ($(in_rundir) && $(GHDLRUN) tb_core -gG_CORE=$(CORE) -gG_BIN_FILE=$(abspath $(BUILD)/random_$(1).bin) \
	  -gG_TRACE_FILE=core.out -gG_MAX_STEPS=$(RANDOM_STEPS) -gG_STALL=$(RANDOM_STALL) -gG_SEED=$(1) \
	  -gG_CYCLE_COUNTER=false -gG_FETCH_STATS=false $(2) \
	  $${o:+"-gG_INTERRUPTS=$$o"} -gG_INTR_LOG=core.intr > core.log 2>&1); \
	  echo "exit $$?" >> $(RUNDIR)/core.out
	@$(EMU) -t -n $(RANDOM_STEPS) --no-cycle-counter $$(cat $(BUILD)/random_$(1).opts) $(BUILD)/random_$(1).bin \
	  < /dev/null > $(RUNDIR)/core.expected; echo "exit $$?" >> $(RUNDIR)/core.expected
	$(if $(IRQ_LATE),,@if cmp -s $(RUNDIR)/core.expected $(RUNDIR)/core.out; then echo "PASS $(CORE) random$(3) $(1)"; \
	else echo "FAIL $(CORE) random$(3) $(1)"; cat $(RUNDIR)/core.log; \
	  diff $(RUNDIR)/core.expected $(RUNDIR)/core.out | head -20; exit 1; fi)
	@$(IRQ_COMPARE) --name random$(3)_$(1) $(BUILD)/random_$(1).bin $(RUNDIR)/core.out \
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

# The same for a random program, run/CORE/randomSUFFIX_SEED, which
# RANDOM_CORE lists too: $(1) is the core, $(2) the seed, $(3) any more
# generics, and $(4) the suffix.
define random_run
RUNS_$(1) += run/$(1)/random$(4)_$(2)
RANDOM_$(1) += run/$(1)/random$(4)_$(2)
.PHONY: run/$(1)/random$(4)_$(2)
run/$(1)/random$(4)_$(2): override CORE = $(1)
run/$(1)/random$(4)_$(2): $(BUILD)/random_$(2).bin $(BUILD)/random_$(2).opts
	$$(call check_random,$(2),$(3),$(4))

endef

# The runs of the core $(1). The sweeps take longest, so they come first,
# and make starts them first.
define core_runs
$(eval $(call sweep_run,$(1),hazard,--delays $$(SWEEP_DELAYS_$(1)) --self-check))
$(eval $(call sweep_run,$(1),irqhazard))
$(eval $(call sweep_run,$(1),latecount))
$(eval $(call sweep_run,$(1),pcfx,--stride $(SWEEP_STRIDE)))
$(eval $(call sweep_run,$(1),sidefx,--stride $(SWEEP_STRIDE)))
$(foreach t,$(EXAMPLES),$(eval $(call core_run,$(1),$(t),../assembler/test/$(t).bin)))
$(foreach t,$(PROBES),$(eval $(call core_run,$(1),$(t),../emulator/test/$(t).bin)))
$(eval $(call core_run,$(1),shift,$(BUILD)/shift.bin))
$(eval $(call core_run,$(1),cputest_stall,../emulator/test/cputest.bin,-gG_STALL=30))
$(eval $(call core_run,$(1),reads_stall,../emulator/test/reads.bin,-gG_STALL=30 -gG_SEED=7))
$(eval $(call core_run,$(1),mpu_stall,../emulator/test/mpu.bin,-gG_STALL=30 -gG_SEED=3))
$(eval $(call core_run,$(1),mpu64_stall,../emulator/test/mpu64.bin,-gG_STALL=30 -gG_SEED=5))
$(eval $(call core_run,$(1),perf_stall,../emulator/test/perf.bin,-gG_STALL=30 -gG_SEED=9))
$(eval $(call core_run,$(1),timer_stall,../emulator/test/timer.bin,-gG_STALL=30 -gG_SEED=11))
$(eval $(call core_run,$(1),cputest_pause,../emulator/test/cputest.bin,-gG_PAUSE=60 -gG_STALL=30 -gG_SEED=23))
$(eval $(call core_run,$(1),cputest_hold,../emulator/test/cputest.bin,-gG_PAUSE=5 -gG_PAUSE_HOLD=40 -gG_SEED=31))
$(eval $(call core_run,$(1),cputest_step,../emulator/test/cputest.bin,-gG_SINGLE_STEP=true))
$(eval $(call core_run,$(1),reads_step,../emulator/test/reads.bin,-gG_SINGLE_STEP=true -gG_STALL=30 -gG_SEED=25))
$(eval $(call core_run,$(1),irq_step,../emulator/test/irq.bin,-gG_SINGLE_STEP=true))
$(eval $(call core_run,$(1),irq_hold,../emulator/test/irq.bin,-gG_PAUSE=10 -gG_PAUSE_HOLD=40 -gG_STALL=30 -gG_SEED=33))
$(eval $(call core_run,$(1),after_pause,../emulator/test/after.bin,-gG_PAUSE=50 -gG_SEED=27))
$(eval $(call core_run,$(1),rtiread_step,$(BUILD)/rtiread.bin,-gG_SINGLE_STEP=true))
$(eval $(call core_run,$(1),pausepatch,$(BUILD)/pausepatch.bin,-gG_SINGLE_STEP=true -gG_PATCH_STEP=2 \
  -gG_PATCH_ADDR=5 -gG_PATCH_DATA=00010100,check_expected))
$(eval $(call core_run,$(1),breaks,$(BUILD)/breaks.bin,$(BREAK_GENERICS),check_core check_breaks))
$(eval $(call core_run,$(1),breaks_stall,$(BUILD)/breaks.bin,$(BREAK_GENERICS) -gG_STALL=30 -gG_SEED=35,check_core check_breaks))
$(eval $(call core_run,$(1),breaks_hold,$(BUILD)/breaks.bin,$(BREAK_GENERICS) -gG_PAUSE=5 -gG_PAUSE_HOLD=40 -gG_SEED=37))
$(eval $(call core_run,$(1),instret,$(BUILD)/instret.bin))
$(eval $(call core_run,$(1),instret_stall,$(BUILD)/instret.bin,-gG_STALL=30 -gG_SEED=17))
$(eval $(call core_run,$(1),irqwave,$(BUILD)/irqwave.bin))
$(eval $(call core_run,$(1),addwave,$(BUILD)/addwave.bin))
$(eval $(call core_run,$(1),hazard,$(BUILD)/hazard.bin,,check_core check_selfcheck))
$(eval $(call core_run,$(1),hazard_stall,$(BUILD)/hazard.bin,-gG_STALL=30 -gG_SEED=13))
$(eval $(call core_run,$(1),sidefx,$(BUILD)/sidefx.bin))
$(eval $(call core_run,$(1),sidefx_stall,$(BUILD)/sidefx.bin,-gG_STALL=30 -gG_SEED=15))
$(eval $(call core_run,$(1),pcfx,$(BUILD)/pcfx.bin,,check_core check_selfcheck))
$(eval $(call core_run,$(1),pcfx_stall,$(BUILD)/pcfx.bin,-gG_STALL=30 -gG_SEED=29))
$(eval $(call core_run,$(1),smc,$(BUILD)/smc.bin,,check_core check_selfcheck))
$(eval $(call core_run,$(1),smc_stall,$(BUILD)/smc.bin,-gG_STALL=30 -gG_SEED=21))
$(foreach t,$(HAZARD_PROGS),$(eval $(call core_run,$(1),$(t),$(BUILD)/$(t).bin)))
$(foreach t,$(HAZARD_PROGS),$(eval $(call core_run,$(1),$(t)_stall,$(BUILD)/$(t).bin,-gG_STALL=30 -gG_SEED=25)))
$(eval $(call core_run,$(1),samereg,$(BUILD)/samereg.bin))
$(eval $(call core_run,$(1),samereg_stall,$(BUILD)/samereg.bin,-gG_STALL=30 -gG_SEED=27))
$(if $(filter pipeline,$(1)),$(eval $(call core_run,$(1),fstats,$(BUILD)/fstats.bin,,check_selfonly)))
$(if $(filter pipeline,$(1)),$(eval $(call core_run,$(1),fstats_stall,$(BUILD)/fstats.bin,-gG_STALL=30 -gG_SEED=19,check_selfonly)))
$(if $(filter pipeline,$(1)),$(eval $(call core_run,$(1),bubble,$(BUILD)/bubble.bin,,check_selfonly)))
$(if $(filter pipeline,$(1)),$(eval $(call core_run,$(1),readwait,$(BUILD)/readwait.bin,,check_core check_waits)))
$(foreach t,$(RANDOM_SEEDS),$(eval $(call random_run,$(1),$(t))))
$(foreach t,$(PAUSE_SEEDS),$(eval $(call random_run,$(1),$(t),-gG_PAUSE=50,_pause)))
$(foreach t,$(PAUSE_SEEDS),$(eval $(call random_run,$(1),$(t),-gG_PAUSE=5 -gG_PAUSE_HOLD=40,_hold)))
endef

$(foreach c,$(sort $(CORES) $(CORE)),$(eval $(call core_runs,$(c))))

test: emulator analyze synth
	@$(MAKE) --no-print-directory $(PARALLEL) runs

# How test/programs.py divides the programs into shards.
run/split:
	@$(PYTHON) test/programs.py --test

# The runs of make test: the unit tests, tb_link and tb_trace, and those of
# each core in CORES.
runs: run/split $(UNITS:%=run/unit/%) $(LINK_RUNS) $(TRACE_RUNS:%=run/trace/%) $(foreach c,$(CORES),$(RUNS_$(c)))

# More random programs than make test runs, for example
#     make random RANDOM_SEEDS="$$(seq 31 90)" RANDOM_STALL=60 RANDOM_STEPS=5000
# test/trace_reads.py shows the data reads of the first instruction where
# the emulator's trace and the core's differ.
random: emulator analyze
	@$(MAKE) --no-print-directory $(PARALLEL) $(RANDOM_$(CORE))

# The seeds 1 to RANDOM_LAST of make random on each core of CORES in turn,
# as each run uses every CPU. Run it where hdl/src stays unchanged: GHDL
# checks the timestamps of the sources.
RANDOM_LAST ?= 1000
random-sweep:
	@for c in $(CORES); do \
	  $(MAKE) --no-print-directory CORE=$$c RANDOM_SEEDS="$$(seq 1 $(RANDOM_LAST))" random || exit 1; \
	done

# The programs of pcfx_prog.py and sidefx_prog.py swept with one request
# per run, on CORE, one after the other, as each uses every CPU. It takes
# five hours on the pipelined core and two on the multi-cycle one, on 20 CPUs.
sweep: emulator analyze $(BUILD)/pcfx.bin $(BUILD)/sidefx.bin
	$(call check_sweep,pcfx)
	$(call check_sweep,sidefx)

# The runtime's and the translator's test programs on the core (MICROARCH.md
# §9, step 7). runtime/Makefile with KEEP and translator/test/run.py with
# --keep run their tests and leave the programs in $(PROGRAMS), and
# test/programs.py runs each on the core and on the emulator, in parallel,
# and compares them. It takes minutes, so make test leaves it out.
PROGRAMS = $(BUILD)/programs
FUZZ_PROGRAMS = 10

# SHARD = I/N runs the Ith of N shares of the programs, as CI does.
SHARD = 1/1

programs: emulator analyze
	@rm -rf $(PROGRAMS)
	@$(MAKE) --no-print-directory -C ../runtime test KEEP=$(abspath $(PROGRAMS)/runtime) \
	  > $(BUILD)/programs_runtime.log 2>&1 || { cat $(BUILD)/programs_runtime.log; exit 1; }
	@$(PYTHON) ../translator/test/run.py --keep $(PROGRAMS)/translator \
	  > $(BUILD)/programs_translator.log 2>&1 || { cat $(BUILD)/programs_translator.log; exit 1; }
	@for m in "" --no-mpu --unchecked --grow; do \
	  $(PYTHON) ../translator/test/fuzz.py $$m --keep $(PROGRAMS)/fuzz 1 $(FUZZ_PROGRAMS) \
	    || exit 1; done > $(BUILD)/programs_fuzz.log 2>&1 || { cat $(BUILD)/programs_fuzz.log; exit 1; }
	@$(PYTHON) test/programs.py --core $(CORE) --build $(BUILD) --emu $(EMU) --shard $(SHARD) $(PROGRAMS)/runtime $(PROGRAMS)/translator $(PROGRAMS)/fuzz

analyze:
	@mkdir -p $(BUILD)
	cd $(BUILD) && $(GHDL) -a --std=08 $(addprefix ../,$(SOURCES) $(SIM_SOURCES) $(TEST_SOURCES))

# Checks that GHDL can synthesize the core, the math unit, the performance
# counters, the timer, and the data bus decoder, with the generics in
# SYNTH_GENERICS_unit.
SYNTH = multicycle pipeline mpu perf timer fetch_stats wb_dmux debug_link
SYNTH_GENERICS_wb_dmux = -gG_SLAVES=4

define check_synth
	@cd $(BUILD) && $(GHDL) --synth --std=08 $(SYNTH_GENERICS_$(1)) $(1) > $(1)_synth.vhd 2> synth_$(1).log; \
	if [ $$? -eq 0 ]; then echo "PASS synth $(1)"; else echo "FAIL synth $(1)"; cat synth_$(1).log; exit 1; fi

endef

synth: analyze
	$(foreach u,$(SYNTH),$(call check_synth,$(u)))

# The formal checks of formal/: each task of each .sby file must pass. Each
# is a target formal/FILE/TASK, and they run in parallel, as the runs of
# make test do. The work directories go in $(BUILD).
SBY ?= sby
FORMAL = nice_pkg multicycle timer wb_dmux pipe_fetch pipe_decode pipe_prepare pipe_dbus pipe_write pipeline perf fetch_stats mpu debug_link
FORMAL_TASKS = prove cover
# The pipelined core is checked for a bounded number of cycles only.
FORMAL_TASKS_pipeline = bmc cover
# The debug link is proven twice, with and without a ROM.
FORMAL_TASKS_debug_link = prove prove_held cover

define check_formal
	@mkdir -p $(BUILD)
	@cd formal && $(SBY) -f -d ../$(BUILD)/$(1)_$(2) $(1).sby $(2) > ../$(BUILD)/formal_$(1)_$(2).log 2>&1; \
	if [ $$? -eq 0 ]; then echo "PASS formal $(1) $(2)"; else echo "FAIL formal $(1) $(2)"; \
	  grep -E "Assert failed|Unreached|ERROR|summary: +(failed|counterexample|unreached)" \
	    ../$(BUILD)/formal_$(1)_$(2).log; exit 1; fi

endef

FORMAL_RUNS = $(foreach f,$(FORMAL),$(foreach t,$(or $(FORMAL_TASKS_$(f)),$(FORMAL_TASKS)),formal/$(f)/$(t)))
.PHONY: $(FORMAL_RUNS)
$(FORMAL_RUNS):
	$(call check_formal,$(word 2,$(subst /, ,$@)),$(word 3,$(subst /, ,$@)))

formal:
	@$(MAKE) --no-print-directory $(PARALLEL) $(FORMAL_RUNS)

emulator:
	$(MAKE) -C ../emulator build

# The out-of-context timing of the pipelined core in Vivado, which timing.tcl
# describes, for the part of BOARD (mega65 or nexys4ddr) with the directives
# of FLOW (default, or timing as NiceMonMEGA65 builds), a clock of PERIOD
# ns, and BREAKS breakpoints. The reports go to build/timing/BOARD-FLOW-BREAKS/: the worst
# register-to-register paths to timing.rpt, the worst from an input to
# timing_in.rpt, the worst to an output to timing_out.rpt, and the endpoints
# with less than 1 ns of slack, by group, to timing_groups.rpt. The worst of
# each is printed, and the groups. About 10 minutes with the default flow.
VIVADO ?= /opt/Xilinx/2025.1/Vivado/bin/vivado
BOARD  ?= mega65
FLOW   ?= default
PERIOD ?= 10.0
BREAKS ?= 4
PART_mega65    = xc7a200tfbg484-2
PART_nexys4ddr = xc7a100tcsg324-1
TIMING_DIR = $(BUILD)/timing/$(BOARD)-$(FLOW)-$(BREAKS)

timing:
	@test -n "$(PART_$(BOARD))" || { echo "unknown BOARD $(BOARD)"; exit 1; }
	@mkdir -p $(TIMING_DIR)
	@cd $(TIMING_DIR) && $(VIVADO) -mode batch -nolog -nojournal -source $(CURDIR)/timing.tcl \
	  -tclargs $(PART_$(BOARD)) $(FLOW) $(PERIOD) $(BREAKS) > timing.log 2>&1 || \
	  { tail -20 timing.log; exit 1; }
	@for r in timing timing_in timing_out; do \
	  echo "$$r.rpt:"; grep -m1 -E "^Slack" $(TIMING_DIR)/$$r.rpt; \
	  grep -m2 -E "^  (Source|Destination):" $(TIMING_DIR)/$$r.rpt; done
	@cat $(TIMING_DIR)/timing_groups.rpt

# Checks the style of every VHDL file against CODING_STYLE.md. Long lines are
# only warnings.
VSG ?= vsg

# Needs mypy (pip install mypy).
typecheck:
	cd test && $(PYTHON) -m mypy --strict *.py

lint:
	$(VSG) -c vsg.yml -of syntastic -f $(SOURCES) $(SIM_SOURCES) $(TEST_SOURCES)

clean:
	rm -rf $(BUILD)

.PHONY: test runs programs random sweep analyze synth formal emulator timing typecheck lint clean
