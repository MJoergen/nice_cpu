PYTHON ?= python3
ASM = $(PYTHON) ../assembler/niceasm.py
EMU = ../emulator/zig-out/bin/niceemu
BUILD = build

SOURCES = src/nice_pkg.vhd src/trace_pkg.vhd src/pipe_pkg.vhd src/multicycle.vhd src/pipe_fetch.vhd src/pipe_decode.vhd src/pipe_prepare.vhd src/pipe_dbus.vhd src/pipe_write.vhd src/pipeline.vhd src/mpu.vhd src/fpu_pkg.vhd src/fpu_seq_pkg.vhd src/fpu_unit.vhd src/fpu.vhd src/perf.vhd src/tod.vhd src/fetch_stats.vhd src/wb_dmux.vhd src/debug_link.vhd src/sd_regs.vhd src/net_regs.vhd src/eth_regs.vhd
SIM_SOURCES = sim/wb_mem.vhd sim/trace.vhd sim/sd_sim.vhd sim/eth_sim.vhd
TEST_SOURCES = test/tb_mem.vhd test/tb_shift.vhd test/tb_mpu.vhd test/tb_fpu_unit.vhd test/tb_fpu.vhd test/tb_perf.vhd test/tb_perf_hz.vhd test/tb_tod.vhd test/tb_fetch_stats.vhd test/tb_wb_dmux.vhd test/tb_debug_link.vhd test/tb_sd_regs.vhd test/tb_net_regs.vhd test/tb_eth_regs.vhd test/tb_link.vhd \
  test/tb_trace.vhd test/tb_core.vhd

# The runs of make test and make random go in parallel: each
# is a target run/GROUP/NAME, where GROUP is unit, trace, or a core. A run
# leaves its files in its own directory, RUNDIR, $(BUILD)/run/GROUP/NAME,
# and the simulator runs there, because GHDL's LLVM and GCC backends write
# an executable where they run. Paths given to it are absolute. The runs
# take JOBS jobs, one per CPU, unless make was given -j; their PASS and FAIL
# lines come in the order they finish.
JOBS ?= $(shell nproc)
PARALLEL = $(if $(filter -j%,$(MAKEFLAGS)),,-j$(JOBS)) -O
RUNDIR = $(BUILD)/$@

SIM_BUILD = $(abspath $(BUILD))
include sim.mk
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
# tb_tod the clock of the time of day, tb_fetch_stats the fetch statistics, tb_wb_dmux
# the data bus decoder, tb_sd_regs the SD card controller, tb_net_regs
# the network station, and tb_eth_regs the port for Ethernet frames.
UNITS = tb_mem tb_shift tb_mpu tb_perf tb_perf_hz tb_tod tb_fetch_stats tb_wb_dmux tb_debug_link tb_sd_regs tb_net_regs tb_eth_regs
GENERICS_tb_mem = -gG_BIN_FILE=$(abspath test/mem.bin) -gG_INPUT_FILE=$(abspath test/mem.input)

$(UNITS:%=run/unit/%): run/unit/%:
	@($(in_rundir) && $(call sim_run,$*,$(GENERICS_$*)) > $*.log 2>&1); \
	if [ $$? -eq 0 ]; then echo "PASS $*"; else echo "FAIL $*"; cat $(RUNDIR)/$*.log; exit 1; fi

# tb_fpu_unit checks the FPU's arithmetic unit against the model of
# emulator/test/fpu_model.py: small, every operation on every operand or
# pair of a format of 8 bits; and wide, random operands of binary64,
# FPU_UNIT_WIDE of each operation, from the seed FPU_UNIT_SEED.
FPU_UNIT_WIDE ?= 3000
FPU_UNIT_SEED ?= 1
FPU_UNIT_RUNS = small wide
OPTS_FPU_UNIT_small =
OPTS_FPU_UNIT_wide  = --wide $(FPU_UNIT_WIDE) --seed $(FPU_UNIT_SEED)
GENERICS_FPU_UNIT_small =
GENERICS_FPU_UNIT_wide  = -gG_EBITS=11 -gG_FBITS=52 -gG_SEBITS=8 -gG_SFBITS=23 -gG_CHUNK=17

$(FPU_UNIT_RUNS:%=run/fpu_unit/%): run/fpu_unit/%:
	@($(in_rundir) && $(PYTHON) $(CURDIR)/test/fpu_unit_vectors.py $(OPTS_FPU_UNIT_$*) vectors \
	  && $(call sim_run,tb_fpu_unit,-gG_VECTORS=vectors $(GENERICS_FPU_UNIT_$*)) > tb_fpu_unit.log 2>&1); \
	if [ $$? -eq 0 ]; then echo "PASS tb_fpu_unit $*"; else echo "FAIL tb_fpu_unit $*"; \
	  tail -30 $(RUNDIR)/tb_fpu_unit.log; exit 1; fi

# tb_fpu replays the vectors of the FPU's model,
# emulator/test/fpu_vectors.py, over the FPU's bus: the directed ones and
# a random sequence from the seed FPU_SEED, FPU_COUNT accesses long, and
# then the slowest commands of test/fpu_slow_vectors.py, whose cycles it
# bounds. Each line stands alone, so the lines are dealt out in turn to
# FPU_SHARES shares, run/fpu/1 to run/fpu/N, which run in parallel, each
# with its share of the timed lines after its own "#timed". run/fpu runs
# them all.
FPU_SEED ?= 1
FPU_COUNT ?= 20000
FPU_SHARES ?= 8
FPU_RUNS = $(addprefix run/fpu/,$(shell seq 1 $(FPU_SHARES)))

run/fpu: $(FPU_RUNS)

$(FPU_RUNS): run/fpu/%:
	@($(in_rundir) && $(PYTHON) $(CURDIR)/../emulator/test/fpu_vectors.py --seed $(FPU_SEED) \
	  --count $(FPU_COUNT) -o all > /dev/null \
	  && $(PYTHON) $(CURDIR)/test/fpu_slow_vectors.py >> all \
	  && awk -v k=$* -v n=$(FPU_SHARES) '/^#timed/ { print; next } /^#/ || /^$$/ { next } \
	    i++ % n == k - 1' all > vectors \
	  && $(call sim_run,tb_fpu,-gG_VECTORS=vectors) > tb_fpu.log 2>&1); \
	if [ $$? -eq 0 ]; then echo "PASS tb_fpu $*/$(FPU_SHARES)"; else echo "FAIL tb_fpu $*/$(FPU_SHARES)"; \
	  tail -30 $(RUNDIR)/tb_fpu.log; exit 1; fi

# tb_trace stands in for the core and runs test/trace.nasm. Each run's output
# and exit status must equal those of the emulator on the same program, with
# the same steps. The runs are: the full trace; no trace; a step limit
# right after the skipped instruction; and a step limit right before the
# halt.
TRACE_RUNS = full quiet skip limit
GENERICS_quiet = -gG_TRACE=false
GENERICS_skip  = -gG_MAX_STEPS=4
OPTS_skip      = -t -n 4
GENERICS_limit = -gG_MAX_STEPS=6
OPTS_limit     = -t -n 6
OPTS_full      = -t

define check_trace
	@($(in_rundir) && $(call sim_run,tb_trace,-gG_BIN_FILE=$(abspath $(BUILD)/trace.bin) -gG_TRACE_FILE=trace.out \
	  $(GENERICS_$(1))) > trace.log 2>&1); echo "exit $$?" >> $(RUNDIR)/trace.out
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
	@($(in_rundir) && $(call sim_run,tb_link,-gG_CORE=$* -gG_INIT_FILE=$(abspath test/link_init.bin) \
	  -gG_PROG_FILE=$(abspath $(BUILD)/linkecho.bin)) > tb_link.log 2>&1); \
	if [ $$? -eq 0 ]; then echo "PASS tb_link $*"; else echo "FAIL tb_link $*"; cat $(RUNDIR)/tb_link.log; exit 1; fi

# tb_core runs a program on the core. Its trace, output, and
# exit status must equal those of "niceemu -t" on the same program. The
# programs are the 2004 examples and wrap from the assembler's tests, the
# emulator's probes, and test/shift.nasm, which runs every shift
# with the counts that are hard to get right. The memory dumps of the probes
# are left out, because the trace lists every memory write. The data reads
# are not in the trace, but the probe reads.nasm counts them with the read
# counter, and its registers show the counts. mpu, mpu64, and mpubits read
# every word of the math unit, src/mpu.vhd, and their registers and the
# trace's memory writes show the results. perf reads the performance counters,
# src/perf.vhd. Its registers hold only instruction counts and flags, which
# do not depend on the cycles an instruction takes. events reads the event
# counters of src/perf.vhd, which count the same on every core and in the
# emulator. cputest, reads, mpu, mpu64, mpubits, perf, and events run a
# second time with a memory that stalls in 30% of the cycles. cputest runs
# again with random pauses, and with pauses held for a random time.
# cputest and reads run one step at a time. These are G_PAUSE,
# G_PAUSE_HOLD, and G_SINGLE_STEP of test/tb_core.vhd, and must not change
# the trace (MICROARCH.md §6).
# sd uses the SD card controller, src/sd_regs.vhd, with the engine
# sim/sd_sim.vhd, and runs again on a stalling memory and with held pauses.
# net reads and writes the network station, src/net_regs.vhd. eth uses the
# port for Ethernet frames, src/eth_regs.vhd, with the station
# sim/eth_sim.vhd and the frames of emulator/test/eth.in, and runs again
# on a stalling memory and with held pauses. The frames it sends must be
# the emulator's. bytewin reads and writes through the byte windows of
# sim/wb_mem.vhd (DEVICES.md §9), and runs again on a stalling memory.
# fpu, fpustack, fpudec, and fpufunc use the FPU, src/fpu.vhd, and fpu runs again
# on a stalling memory. fpu reads the time, which is memory in both.
# fpudec runs again with random pauses, with pauses held for up to 3000
# cycles, and one step at a time, so that pauses and steps come while
# the core waits for DIGITS and SCALE10 (DEVICES.md §11.5).
EXAMPLES = count replicate print wrap
PROBES = logic dest carry r15 cond rotate selfmod addr cputest \
  console screen iofetch reads reserved mpu mpu64 mpubits perf events input \
  r15modes r0dest r14mem skipconst carryin shiftc wrapmem smcown sd net eth bytewin \
  fpu fpustack fpudec fpufunc short shortfar
# The runs that read the cycle counter or the time: memory in both.
NOCYCLES_fpu        = yes
NOCYCLES_fpu_stall  = yes
# The console input of a run, a file, as the emulator's --input takes it.
INPUT_input = ../emulator/test/input.txt
# The runs with an SD card in slot 0: sd.img in the run's directory, the
# image of emulator/test/sd.nasm, for the core, and a copy of it for the
# emulator, which writes it. sim/sd_sim.vhd writes nothing back.
SD_sd = yes
SD_sd_stall = yes
SD_sd_hold = yes
# The runs with Ethernet frames: the frames of the file, and the frames
# sent, eth.out of the core and eth_emu.out of the emulator, compared.
ETH_eth = ../emulator/test/eth.in
ETH_eth_stall = $(ETH_eth)
ETH_eth_hold = $(ETH_eth)
SD_IMAGE = $(PYTHON) -c 'import sys; sys.stdout.buffer.write(bytes(o % 251 for o in range(1024)))'

# test/breaks.nasm stops at the breakpoints of BREAKS_breaks, in hex: in a
# loop, at an instruction with a data read, at a false condition, and at
# a jump target (doc/DEBUG.md §6). tb_core's
# G_BREAK_AT sets them, and its G_BREAK_LOG lists the stops. check_breaks
# compares that list with the emulator's, from test/break_stops.py. The
# run breaks_stall does the same on a stalling memory, and breaks_hold
# adds pauses held for a random time, which must not change the trace.
# A pause at a breakpoint is not a stop of the core's own, so that run's
# list is not compared.
BREAKS_breaks = 4 5 8 C
BREAKS_breaks_stall = $(BREAKS_breaks)
BREAK_GENERICS = "-gG_BREAK_AT=$(BREAKS_breaks)" -gG_BREAK_LOG=stops.out

# test/watches.nasm stops after the steps that hit the watchpoints of
# WATCH_watches: reads and writes in each addressing mode, two reads in
# one step, a skipped read, a read that must not pass a hit before it, an
# I/O store, and a jump through memory (doc/DEBUG.md §6). tb_core's
# G_WATCH_AT sets them, and check_breaks compares the stops, with the
# watchpoint and the address of each hit, with the emulator's. The run
# watches_stall does the same on a stalling memory.
WATCH_watches = 1Crw 1Dw FFFFFF20w 1Br
WATCH_watches_stall = $(WATCH_watches)
WATCH_GENERICS = "-gG_WATCH_AT=$(WATCH_watches)" -gG_BREAK_LOG=stops.out

# $(1) is the name of the run, and $(2) the program.
define check_breaks
	@$(PYTHON) test/break_stops.py --emu $(EMU) --watch "$(WATCH_$(1))" $(2) "$(BREAKS_$(1))" \
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
	@($(in_rundir) && $(call sim_run,tb_core,-gG_CORE=$(CORE) -gG_BIN_FILE=$(abspath $(2)) \
	  -gG_TRACE_FILE=core.out $(3)) > core.log 2>&1); echo "exit $$?" >> $(RUNDIR)/core.out
	@if cmp -s test/$(1).expected $(RUNDIR)/core.out; then echo "PASS $(CORE) $(1)"; \
	else echo "FAIL $(CORE) $(1)"; cat $(RUNDIR)/core.log; \
	  diff test/$(1).expected $(RUNDIR)/core.out | head -20; exit 1; fi

endef

# $(1) is the name of the run, $(2) the program, and $(3) any more generics.
define check_core
	@($(in_rundir) && $(if $(SD_$(1)),$(SD_IMAGE) > sd.img && cp sd.img sd_emu.img &&) \
	  $(call sim_run,tb_core,-gG_CORE=$(CORE) -gG_BIN_FILE=$(abspath $(2)) \
	  -gG_TRACE_FILE=core.out \
	  $(if $(INPUT_$(1)),-gG_INPUT_FILE=$(abspath $(INPUT_$(1)))) \
	  $(if $(NOCYCLES_$(1)),-gG_CYCLE_COUNTER=false) \
	  $(if $(SD_$(1)),-gG_SD0_FILE=sd.img) \
	  $(if $(ETH_$(1)),-gG_ETH_IN_FILE=$(abspath $(ETH_$(1))) -gG_ETH_OUT_FILE=eth.out) \
	  $(3)) > core.log 2>&1); echo "exit $$?" >> $(RUNDIR)/core.out
	@$(EMU) -t $(if $(INPUT_$(1)),--input $(INPUT_$(1))) \
	  $(if $(NOCYCLES_$(1)),--no-cycle-counter) \
	  $(if $(SD_$(1)),--sd0 $(RUNDIR)/sd_emu.img) \
	  $(if $(ETH_$(1)),--eth-in $(ETH_$(1)) --eth-out $(RUNDIR)/eth_emu.out) $(2) < /dev/null \
	  > $(RUNDIR)/core.expected; \
	  echo "exit $$?" >> $(RUNDIR)/core.expected
	$(if $(ETH_$(1)),@if cmp -s $(RUNDIR)/eth_emu.out $(RUNDIR)/eth.out; \
	then echo "PASS $(CORE) $(1) frames"; \
	else echo "FAIL $(CORE) $(1) frames"; diff $(RUNDIR)/eth_emu.out $(RUNDIR)/eth.out; exit 1; fi)
	@if cmp -s $(RUNDIR)/core.expected $(RUNDIR)/core.out; \
	then echo "PASS $(CORE) $(1)"; \
	else echo "FAIL $(CORE) $(1)"; cat $(RUNDIR)/core.log; \
	  diff $(RUNDIR)/core.expected $(RUNDIR)/core.out | head -20; exit 1; fi

endef

# The hazard programs of MICROARCH.md §9, step 4: test/hazard.nasm, the
# programs that test/sidefx_prog.py, test/pcfx_prog.py, and
# test/smc_prog.py write, and the HAZARD_PROGS below, each also on a
# memory that stalls. pcfx_prog.py's program has every pair of side
# effects on R15, and smc_prog.py's stores into its own code 1 to 40 words
# ahead. Both check themselves like hazard.nasm.
# hazard.nasm checks itself, so the emulator's run must end at its last HALT,
# with R12 = 0 and exit status 0, before the core's trace means anything.
define check_selfcheck
	@if grep -q '^R12 00000000' $(RUNDIR)/core.expected && \
	  tail -n 1 $(RUNDIR)/core.expected | grep -qx 'exit 0'; then echo "PASS emulator $(1)"; \
	else echo "FAIL emulator $(1): the program's own checks failed"; \
	  tail -n 6 $(RUNDIR)/core.expected; exit 1; fi

endef

# A program of HAZARD_PROGS does not check itself, and its run on a core
# is only compared with the emulator's. So the emulator's run must get to
# the program's end before the core's trace means anything: its exit
# status is 0, for a HALT, or the END_ of the program. jumpwords.nasm
# ends on a reserved word, with status 2. A program whose store into its
# own code goes wrong ends on a reserved word too, as smclate.nasm does at
# its bad. $(1) is the name of the run.
END_jumpwords = 2

define check_end
	@if tail -n 1 $(RUNDIR)/core.expected | grep -qx 'exit $(or $(END_$(1)),0)'; \
	then echo "PASS emulator $(1)"; \
	else echo "FAIL emulator $(1): the program did not run to its end"; \
	  tail -n 6 $(RUNDIR)/core.expected; exit 1; fi

endef

# In front of a recipe line, $(JOBSERVER) is the "+" that gives a script
# make's jobserver (test/core_runs.py). A "+" also runs its line under
# make -n, -q, and -t, where a run of the programs would take minutes. So
# under those it is nothing: make -n prints the line, and the script does
# not run.
JOBSERVER = $(if $(strip $(foreach o,n q t,$(findstring $(o),$(firstword -$(MAKEFLAGS))))),,+)

# The programs of the third repository review against the operand rules of
# the re-timed core (doc/review/third-repository-review.md §1.5): the shift
# counts WRITE reduces in a cycle of its own, the destinations adjusted by
# one, R14 and R15 in every field, R0, stores into fetched code from late
# instructions, the read counter and the instruction counter around them,
# jumps into constant words, and every shift into R15. Each runs on both
# cores, plain and on a stalling memory, compared with the emulator.
# test/samereg_prog.py writes one more, with one register in all three
# fields of a shift. smcskid came later: stores into an instruction in
# DECODE's skid register.
HAZARD_PROGS = latecount twocycle r15mix r14cond r0odd smclate readorder instret_late \
  jumpwords condlate shiftjump smcskid predict

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
	@($(in_rundir) && $(call sim_run,tb_core,-gG_CORE=$(CORE) -gG_BIN_FILE=$(abspath $(2)) \
	  -gG_TRACE_FILE=core.out -gG_TRACE=false $(3)) > core.log 2>&1); echo "exit $$?" >> $(RUNDIR)/core.out
	@if grep -q '^R12 00000000' $(RUNDIR)/core.out && \
	  tail -n 1 $(RUNDIR)/core.out | grep -qx 'exit 0'; then echo "PASS $(CORE) $(1)"; \
	else echo "FAIL $(CORE) $(1)"; cat $(RUNDIR)/core.log; tail -n 6 $(RUNDIR)/core.out; exit 1; fi

endef

# Random programs from test/random_prog.py, each run for RANDOM_STEPS steps
# on a memory that stalls in RANDOM_STALL
# percent of the cycles, and compared in the same way. A random program
# may read any address, so the cycle counter, which the core and the
# emulator count differently, is memory in both: G_CYCLE_COUNTER=false and
# --no-cycle-counter. The emulator's fonts, which the cores do not have,
# are memory too: --no-font, and so is the screen's mode word:
# --no-screen-mode. So is the FPU, in both, which leaves it to its
# own tests: G_FPU=false and --no-fpu. The fetch statistics read 0 and
# ignore writes in both: G_FETCH_STATS=false. random_prog.py writes the
# program. The seeds
# of PAUSE_SEEDS run again with random pauses, as random_pause_N, and with
# pauses held for a random time, as random_hold_N (G_PAUSE and
# G_PAUSE_HOLD of test/tb_core.vhd), which must not change the trace. In check_random, $(2)
# is any more generics, and $(3) the suffix of the name.
RANDOM_SEEDS = $(shell seq 1 30)
PAUSE_SEEDS = $(shell seq 1 8)
RANDOM_STEPS = 3000
RANDOM_STALL = 30

$(BUILD)/random_%.bin: test/random_prog.py
	@mkdir -p $(BUILD)
	@$(PYTHON) test/random_prog.py $* $@

define check_random
	@($(in_rundir) && $(call sim_run,tb_core,-gG_CORE=$(CORE) -gG_BIN_FILE=$(abspath $(BUILD)/random_$(1).bin) \
	  -gG_TRACE_FILE=core.out -gG_MAX_STEPS=$(RANDOM_STEPS) -gG_STALL=$(RANDOM_STALL) -gG_SEED=$(1) \
	  -gG_CYCLE_COUNTER=false -gG_FETCH_STATS=false -gG_FPU=false $(2)) > core.log 2>&1); \
	  echo "exit $$?" >> $(RUNDIR)/core.out
	@$(EMU) -t -n $(RANDOM_STEPS) --no-cycle-counter --no-font --no-screen-mode --no-fpu $(BUILD)/random_$(1).bin \
	  < /dev/null > $(RUNDIR)/core.expected; echo "exit $$?" >> $(RUNDIR)/core.expected
	@if cmp -s $(RUNDIR)/core.expected $(RUNDIR)/core.out; then echo "PASS $(CORE) random$(3) $(1)"; \
	else echo "FAIL $(CORE) random$(3) $(1)"; cat $(RUNDIR)/core.log; \
	  diff $(RUNDIR)/core.expected $(RUNDIR)/core.out | head -20; exit 1; fi

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

# The same for a random program, run/CORE/randomSUFFIX_SEED, which
# RANDOM_CORE lists too: $(1) is the core, $(2) the seed, $(3) any more
# generics, and $(4) the suffix.
define random_run
RUNS_$(1) += run/$(1)/random$(4)_$(2)
RANDOM_$(1) += run/$(1)/random$(4)_$(2)
.PHONY: run/$(1)/random$(4)_$(2)
run/$(1)/random$(4)_$(2): override CORE = $(1)
run/$(1)/random$(4)_$(2): $(BUILD)/random_$(2).bin
	$$(call check_random,$(2),$(3),$(4))

endef

# test/todbus.nasm sets and reads the clock of the time of day,
# src/tod.vhd, through the bus decoder of tb_core, and reads the word
# after it, which is src/perf.vhd's. It reads only what the emulator, on
# the host's clock, and the core, on its cycles, have in common, so the
# runs are compared as the others are. It runs again on a stalling memory.

# The runs of the core $(1).
define core_runs
$(foreach t,$(EXAMPLES),$(eval $(call core_run,$(1),$(t),../assembler/test/$(t).bin)))
$(foreach t,$(PROBES),$(eval $(call core_run,$(1),$(t),../emulator/test/$(t).bin)))
$(eval $(call core_run,$(1),shift,$(BUILD)/shift.bin))
$(eval $(call core_run,$(1),cputest_stall,../emulator/test/cputest.bin,-gG_STALL=30))
$(eval $(call core_run,$(1),reads_stall,../emulator/test/reads.bin,-gG_STALL=30 -gG_SEED=7))
$(eval $(call core_run,$(1),mpu_stall,../emulator/test/mpu.bin,-gG_STALL=30 -gG_SEED=3))
$(eval $(call core_run,$(1),mpu64_stall,../emulator/test/mpu64.bin,-gG_STALL=30 -gG_SEED=5))
$(eval $(call core_run,$(1),mpubits_stall,../emulator/test/mpubits.bin,-gG_STALL=30 -gG_SEED=39))
$(eval $(call core_run,$(1),fpu_stall,../emulator/test/fpu.bin,-gG_STALL=30 -gG_SEED=53))
$(eval $(call core_run,$(1),fpudec_pause,../emulator/test/fpudec.bin,-gG_PAUSE=40 -gG_SEED=65))
$(eval $(call core_run,$(1),fpudec_hold,../emulator/test/fpudec.bin,-gG_PAUSE=2 -gG_PAUSE_HOLD=3000 -gG_SEED=67))
$(eval $(call core_run,$(1),fpudec_step,../emulator/test/fpudec.bin,-gG_SINGLE_STEP=true))
$(eval $(call core_run,$(1),perf_stall,../emulator/test/perf.bin,-gG_STALL=30 -gG_SEED=9))
$(eval $(call core_run,$(1),events_stall,../emulator/test/events.bin,-gG_STALL=30 -gG_SEED=13))
$(eval $(call core_run,$(1),sd_stall,../emulator/test/sd.bin,-gG_STALL=30 -gG_SEED=41))
$(eval $(call core_run,$(1),sd_hold,../emulator/test/sd.bin,-gG_PAUSE=5 -gG_PAUSE_HOLD=40 -gG_SEED=43))
$(eval $(call core_run,$(1),bytewin_stall,../emulator/test/bytewin.bin,-gG_STALL=30 -gG_SEED=49))
$(eval $(call core_run,$(1),eth_stall,../emulator/test/eth.bin,-gG_STALL=30 -gG_SEED=45))
$(eval $(call core_run,$(1),eth_hold,../emulator/test/eth.bin,-gG_PAUSE=5 -gG_PAUSE_HOLD=40 -gG_SEED=47))
$(eval $(call core_run,$(1),cputest_pause,../emulator/test/cputest.bin,-gG_PAUSE=60 -gG_STALL=30 -gG_SEED=23))
$(eval $(call core_run,$(1),cputest_hold,../emulator/test/cputest.bin,-gG_PAUSE=5 -gG_PAUSE_HOLD=40 -gG_SEED=31))
$(eval $(call core_run,$(1),cputest_step,../emulator/test/cputest.bin,-gG_SINGLE_STEP=true))
$(eval $(call core_run,$(1),reads_step,../emulator/test/reads.bin,-gG_SINGLE_STEP=true -gG_STALL=30 -gG_SEED=25))
$(eval $(call core_run,$(1),pausepatch,$(BUILD)/pausepatch.bin,-gG_SINGLE_STEP=true -gG_PATCH_STEP=2 \
  -gG_PATCH_ADDR=5 -gG_PATCH_DATA=00010100,check_expected))
$(eval $(call core_run,$(1),breaks,$(BUILD)/breaks.bin,$(BREAK_GENERICS),check_core check_breaks))
$(eval $(call core_run,$(1),breaks_stall,$(BUILD)/breaks.bin,$(BREAK_GENERICS) -gG_STALL=30 -gG_SEED=35,check_core check_breaks))
$(eval $(call core_run,$(1),breaks_hold,$(BUILD)/breaks.bin,$(BREAK_GENERICS) -gG_PAUSE=5 -gG_PAUSE_HOLD=40 -gG_SEED=37))
$(eval $(call core_run,$(1),watches,$(BUILD)/watches.bin,$(WATCH_GENERICS),check_core check_breaks))
$(eval $(call core_run,$(1),watches_stall,$(BUILD)/watches.bin,$(WATCH_GENERICS) -gG_STALL=30 -gG_SEED=59,check_core check_breaks))
$(eval $(call core_run,$(1),instret,$(BUILD)/instret.bin))
$(eval $(call core_run,$(1),todbus,$(BUILD)/todbus.bin))
$(eval $(call core_run,$(1),todbus_stall,$(BUILD)/todbus.bin,-gG_STALL=30 -gG_SEED=57))
$(eval $(call core_run,$(1),instret_stall,$(BUILD)/instret.bin,-gG_STALL=30 -gG_SEED=17))
$(eval $(call core_run,$(1),addwave,$(BUILD)/addwave.bin))
$(eval $(call core_run,$(1),hazard,$(BUILD)/hazard.bin,,check_core check_selfcheck))
$(eval $(call core_run,$(1),hazard_stall,$(BUILD)/hazard.bin,-gG_STALL=30 -gG_SEED=13))
$(eval $(call core_run,$(1),sidefx,$(BUILD)/sidefx.bin))
$(eval $(call core_run,$(1),sidefx_stall,$(BUILD)/sidefx.bin,-gG_STALL=30 -gG_SEED=15))
$(eval $(call core_run,$(1),pcfx,$(BUILD)/pcfx.bin,,check_core check_selfcheck))
$(eval $(call core_run,$(1),pcfx_stall,$(BUILD)/pcfx.bin,-gG_STALL=30 -gG_SEED=29))
$(eval $(call core_run,$(1),smc,$(BUILD)/smc.bin,,check_core check_selfcheck))
$(eval $(call core_run,$(1),smc_stall,$(BUILD)/smc.bin,-gG_STALL=30 -gG_SEED=21))
$(foreach t,$(HAZARD_PROGS),$(eval $(call core_run,$(1),$(t),$(BUILD)/$(t).bin,,check_core check_end)))
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

test: emulator seqcheck analyze synth
	@$(MAKE) --no-print-directory $(PARALLEL) runs

# The ROM of the FPU's functions must be that of their programs,
# emulator/test/fpu_seq.py.
seqcheck:
	@$(PYTHON) ../emulator/test/fpu_seq.py --vhdl | cmp -s - src/fpu_seq_pkg.vhd \
	  || { echo "src/fpu_seq_pkg.vhd is stale: ../emulator/test/fpu_seq.py --vhdl > src/fpu_seq_pkg.vhd"; exit 1; }; \
	echo "PASS seqcheck"

# How test/programs.py divides the programs into shards.
run/split:
	@$(PYTHON) test/programs.py --test

# The check of test/core_runs.py's client of make's jobserver, with this
# make. THIS_MAKE is its name without the "$(MAKE)" in the recipe that
# would have make take the line for a recursive make. The script runs
# make jobserver-probe, with -j, -n, and -q, for what $(JOBSERVER) does.
THIS_MAKE := $(MAKE)
run/jobserver:
	@$(PYTHON) test/core_runs.py --make '$(THIS_MAKE)'

jobserver-probe:
	$(JOBSERVER)@$(PYTHON) test/core_runs.py --probe

# The check of the timing budget against made-up reports.
run/budget:
	@$(PYTHON) test/timing_budget.py --test

# The check of test/trace_reads.py's decoding against words decoded by hand.
run/reads:
	@$(PYTHON) test/trace_reads.py --test

# The check that the hazards random_stats.py shows are rows of the table of
# MICROARCH.md §5.6, which it reads their shares from.
run/shown:
	@$(PYTHON) test/random_stats.py --test

# The runs of make test: the unit tests, tb_link and tb_trace, and those of
# each core in CORES.
runs: run/split run/jobserver run/budget run/reads run/shown $(UNITS:%=run/unit/%) $(FPU_UNIT_RUNS:%=run/fpu_unit/%) $(FPU_RUNS) $(LINK_RUNS) $(TRACE_RUNS:%=run/trace/%) $(foreach c,$(CORES),$(RUNS_$(c)))

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

# The runtime's and the translator's test programs on the core (MICROARCH.md
# §9, step 7). runtime/Makefile with KEEP and translator/test/run.py with
# --keep run their tests and leave the programs in $(PROGRAMS), and
# test/programs.py runs each on the core and on the emulator, in parallel,
# and compares them. It takes minutes, so make test leaves it out. The
# programs that use floats use the FPU, as on the emulator.
PROGRAMS = $(BUILD)/programs
FUZZ_PROGRAMS = 10

# SHARD = I/N runs the Ith of N shares of the programs.
SHARD = 1/1

programs: emulator analyze
	@rm -rf $(PROGRAMS)
	@$(MAKE) --no-print-directory -C ../runtime test KEEP=$(abspath $(PROGRAMS)/runtime) \
	  > $(BUILD)/programs_runtime.log 2>&1 || { cat $(BUILD)/programs_runtime.log; exit 1; }
	@$(PYTHON) ../translator/test/run.py --keep $(PROGRAMS)/translator \
	  > $(BUILD)/programs_translator.log 2>&1 || { cat $(BUILD)/programs_translator.log; exit 1; }
	@for m in "" --no-mpu --unchecked --grow --windows --inline-fpu; do \
	  $(PYTHON) ../translator/test/fuzz.py $$m --keep $(PROGRAMS)/fuzz 1 $(FUZZ_PROGRAMS) \
	    || exit 1; done > $(BUILD)/programs_fuzz.log 2>&1 || { cat $(BUILD)/programs_fuzz.log; exit 1; }
	$(JOBSERVER)@$(PYTHON) test/programs.py --core $(CORE) $(SIM_ARGS) --build $(BUILD) --emu $(EMU) --shard $(SHARD) $(PROGRAMS)/runtime $(PROGRAMS)/translator $(PROGRAMS)/fuzz

# Analyzes the VHDL for SIM, and analyze-ghdl for GHDL's synthesis.
analyze: analyze-$(SIM)

analyze-ghdl:
	@mkdir -p $(BUILD)
	$(if $(PREBUILT),,cd $(BUILD) && $(GHDL) -a --std=08 $(addprefix ../,$(SOURCES) $(SIM_SOURCES) $(TEST_SOURCES)))

analyze-nvc:
	@mkdir -p $(BUILD)
	$(if $(PREBUILT),,$(NVC) $(NVCOPTS) -a $(SOURCES) $(SIM_SOURCES) $(TEST_SOURCES))

# Checks that GHDL can synthesize both cores, the math unit, the FPU and
# its arithmetic unit, the performance counters, the clock of the time of
# day, the fetch statistics, the data bus decoder, the debug link, the SD
# card controller, the network station, and the port for Ethernet frames,
# with the generics in SYNTH_GENERICS_unit.
SYNTH = multicycle pipeline mpu fpu_unit fpu perf tod fetch_stats wb_dmux debug_link sd_regs net_regs eth_regs
SYNTH_GENERICS_wb_dmux = -gG_SLAVES=4

define check_synth
	@cd $(BUILD) && $(GHDL) --synth --std=08 $(SYNTH_GENERICS_$(1)) $(1) > $(1)_synth.vhd 2> synth_$(1).log; \
	if [ $$? -eq 0 ]; then echo "PASS synth $(1)"; else echo "FAIL synth $(1)"; cat synth_$(1).log; exit 1; fi

endef

synth: analyze-ghdl
	$(foreach u,$(SYNTH),$(call check_synth,$(u)))

# The formal checks of formal/: each task of each .sby file must pass. Each
# is a target formal/FILE/TASK, and they run in parallel, as the runs of
# make test do. The work directories go in $(BUILD).
SBY ?= sby
FORMAL = nice_pkg multicycle tod wb_dmux pipe_fetch pipe_decode pipe_prepare pipe_dbus pipe_write pipeline perf fetch_stats mpu fpu debug_link sd_regs net_regs eth_regs
FORMAL_TASKS = prove cover
# The pipelined core is checked for a bounded number of cycles only.
FORMAL_TASKS_pipeline = bmc cover
# The FPU's bus is proven for every command, and its stack against a
# model for the commands of the stack.
FORMAL_TASKS_fpu = prove prove_stack cover
# The debug link is proven twice, with and without a ROM.
FORMAL_TASKS_debug_link = prove prove_held cover cover_side
FORMAL_TASKS_sd_regs = prove prove_nohold cover
FORMAL_TASKS_eth_regs = prove prove_nohold cover

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

# PREBUILT=1 says that the emulator is built and the VHDL analyzed, so that
# the runs of the top-level make slow, which go in parallel, do neither.
emulator:
	$(if $(PREBUILT),,$(MAKE) -C ../emulator build)

# The out-of-context timing of UNIT in Vivado, which timing.tcl
# describes: the pipelined core, pipeline, by default, or the FPU, fpu.
# For the part of BOARD (mega65 or nexys4ddr) with the directives of FLOW
# (default, or timing as NiceMonMEGA65 builds), a clock of PERIOD ns, and
# for the core BREAKS breakpoints and WATCHES watchpoints. The reports go
# to build/timing/BOARD-FLOW-BREAKS-WATCHES/ for the core, and to
# build/timing/fpu-BOARD-FLOW/ for the FPU: the worst
# register-to-register paths to timing.rpt, the worst from an input to
# timing_in.rpt, the worst to an output to timing_out.rpt, and the endpoints
# with less than 1 ns of slack, by group, to timing_groups.rpt. The worst of
# each is printed, and the groups. About 3 minutes with the default flow.
# Last it compares the slacks with the budget of the unit and board in
# test/timing_budget.py, writes budget.json, and prints "MISSED" on a miss,
# but still exits 0: a miss is to be seen, not to stop anything.
VIVADO ?= /opt/Xilinx/2025.1/Vivado/bin/vivado
UNIT   ?= pipeline
BOARD  ?= mega65
FLOW   ?= default
PERIOD ?= 10.0
BREAKS ?= 4
WATCHES ?= 4
PART_mega65    = xc7a200tfbg484-2
PART_nexys4ddr = xc7a100tcsg324-1
TIMING_DIR_pipeline = $(BUILD)/timing/$(BOARD)-$(FLOW)-$(BREAKS)-$(WATCHES)
TIMING_DIR_fpu      = $(BUILD)/timing/fpu-$(BOARD)-$(FLOW)
TIMING_DIR = $(TIMING_DIR_$(UNIT))

timing:
	@test -n "$(TIMING_DIR)" || { echo "unknown UNIT $(UNIT), not pipeline or fpu"; exit 1; }
	@test -n "$(PART_$(BOARD))" || { echo "unknown BOARD $(BOARD)"; exit 1; }
	@mkdir -p $(TIMING_DIR)
	@cd $(TIMING_DIR) && $(VIVADO) -mode batch -nolog -nojournal -source $(CURDIR)/timing.tcl \
	  -tclargs $(PART_$(BOARD)) $(FLOW) $(PERIOD) $(BREAKS) $(WATCHES) $(UNIT) > timing.log 2>&1 || \
	  { tail -20 timing.log; exit 1; }
	@for r in timing timing_in timing_out; do \
	  echo "$$r.rpt:"; grep -m1 -E "^Slack" $(TIMING_DIR)/$$r.rpt; \
	  grep -m2 -E "^  (Source|Destination):" $(TIMING_DIR)/$$r.rpt; done
	@cat $(TIMING_DIR)/timing_groups.rpt
	@$(PYTHON) test/timing_budget.py $(TIMING_DIR) $(BOARD) $(PERIOD) $(FLOW) $(UNIT)

# One run of make timing cannot show a change of a few tenths of a ns: a
# change elsewhere moves the placement, and the slacks with it (#151). This
# runs make timing for BOARD and FLOW with the seven counts of breakpoints
# and watchpoints of SPREAD_VARIANTS, all at once, and prints the least,
# median, and most of each slack. About 11 minutes with the default flow
# and 40 with the timing flow, on 20 CPUs. The FPU has no such variants.
SPREAD_VARIANTS = 4-0 4-1 4-2 4-3 4-4 2-0 2-4
SPREAD_DIRS = $(foreach v,$(SPREAD_VARIANTS),$(BUILD)/timing/$(BOARD)-$(FLOW)-$(v))

timing-spread:
	@test "$(UNIT)" = pipeline || { echo "make timing-spread is for UNIT=pipeline"; exit 1; }
	@$(MAKE) --no-print-directory -j $(words $(SPREAD_VARIANTS)) \
	  $(addprefix timing-spread/,$(SPREAD_VARIANTS))
	@$(PYTHON) test/timing_budget.py --spread $(SPREAD_DIRS)

timing-spread/%:
	@$(MAKE) --no-print-directory timing UNIT=pipeline BREAKS=$(word 1,$(subst -, ,$*)) \
	  WATCHES=$(word 2,$(subst -, ,$*)) > /dev/null

# Checks the style of every VHDL file against CODING_STYLE.md. Long lines are
# only warnings.
VSG ?= vsg

# Needs mypy (pip install mypy).
typecheck:
	cd test && MYPYPATH=../../emulator/test $(PYTHON) -m mypy --strict *.py

lint:
	$(VSG) -c vsg.yml -of syntastic -f $(SOURCES) $(SIM_SOURCES) $(TEST_SOURCES)

clean:
	rm -rf $(BUILD)

.PHONY: test seqcheck runs jobserver-probe programs random analyze analyze-ghdl analyze-nvc synth formal emulator timing timing-spread typecheck lint clean
