PYTHON ?= python3
CLANG ?= clang
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

# float.c, the float benchmark (README.md, The float benchmark), translated
# from float.wasm and joined with the float library. make core runs it with
# CORE_PROGRAMS=float. The float library is ../runtime/float_fpu.nasm,
# which uses the FPU of SYSTEM.md §11, or with NO_FPU=1 float.nasm, in
# software.
FLOAT_LIB = ../runtime/$(if $(NO_FPU),float.nasm,float_fpu.nasm)

# make test runs float.c with float.nasm too, from SOFT_BUILD, built with
# NO_FPU=1 by a make of its own, as the files of the two builds have the
# same names.
SOFT_BUILD = $(BUILD)/nofpu

# Dhrystone 2.1, ported in dhrystone/ (README.md, Dhrystone), and its
# console input, the number of runs. The 1988 C of its sources is compiled
# as C89, as it stands, so without the warnings of CFLAGS, and with no
# inlining, which the ground rules of Dhrystone forbid.
DHRY = dhrystone
DHRY_CFLAGS = --target=wasm32 -mbulk-memory -O2 -ffreestanding -nostdlibinc -isystem $(LIBC)/include \
  -std=gnu89 -fno-inline -DNICE -Wno-deprecated-non-prototype -Wno-return-type
DHRY_RUNS = $(DHRY)/dhry.input

# CoreMark, ported in coremark/ (README.md, CoreMark). CM_CODEGEN are the
# flags that shape its code, which it prints as its compiler flags. The
# console gives it three seeds and the iterations: CM_perf or CM_valid,
# the performance or validation seeds, and CM_ITERATIONS on the emulator
# or CM_CORE_ITERATIONS on a core. CM_SEEDS picks the seeds of a core's
# run, perf or valid.
CM = coremark
CM_CODEGEN = --target=wasm32 -mbulk-memory -O2
CM_CFLAGS = $(CM_CODEGEN) -ffreestanding -nostdlibinc -isystem $(LIBC)/include -Wall -Wextra \
  -DFLAGS_STR='"$(CM_CODEGEN)"'
CM_SRCS = $(addprefix $(CM)/,core_list_join.c core_main.c core_matrix.c core_state.c core_util.c \
  core_portme.c)
CM_perf = 0 0 0x66
CM_valid = 0x3415 0x3415 0x66
CM_ITERATIONS = 10
CM_CORE_ITERATIONS = 1
CM_SEEDS = perf

# Runs both on the emulator and prints their tables. bench.wasm is checked
# in, so this needs no C compiler.
run: $(BUILD)/bench.bin $(BUILD)/hand.bin $(BUILD)/simple.bin $(BUILD)/float.bin emulator
	@echo "bench.c through nicewasm:"
	@$(EMU) $(BUILD)/bench.bin < /dev/null | sed '/^Halted/,$$d'
	@echo "hand.nasm:"
	@$(EMU) $(BUILD)/hand.bin < /dev/null | sed '/^Halted/,$$d'
	@echo "simple.nasm:"
	@$(EMU) $(BUILD)/simple.bin < /dev/null | sed '/^Halted/,$$d'
	@echo "float.c through nicewasm:"
	@$(EMU) $(BUILD)/float.bin < /dev/null | sed '/^Halted/,$$d'

# Runs Dhrystone on the emulator and prints its output.
dhry: $(BUILD)/dhry.bin emulator
	@$(EMU) --input $(DHRY_RUNS) $(BUILD)/dhry.bin < /dev/null | sed '/^Halted/,$$d'

# Runs CoreMark on the emulator with both sets of seeds and prints its output.
coremark: $(BUILD)/coremark.bin emulator
	@$(foreach s,perf valid,echo "$(CM_$(s)) $(CM_ITERATIONS)" | $(EMU) $(BUILD)/coremark.bin \
	  | sed '/^Halted/,$$d';)

# The same, and checks that every phase has its expected result, that main
# returns 0 in R1, and that the expected values in bench.c, hand.nasm, and
# simple.nasm are those of expected.py, and those in float.c are those of
# floatexpected.py. float.c runs with both float libraries, and as
# float_inline, with the FPU's accesses inline.
define check
	@$(EMU) $(BUILD)/$(1).bin < /dev/null > $(BUILD)/$(1).out; sed '/^Halted/,$$d' $(BUILD)/$(1).out
	@if grep -q ' R1  00000000 ' $(BUILD)/$(1).out && ! grep -q FAIL $(BUILD)/$(1).out; \
	then echo "PASS $(1)"; else echo "FAIL $(1)"; exit 1; fi

endef

test: $(BUILD)/bench.bin $(BUILD)/hand.bin $(BUILD)/simple.bin $(BUILD)/float.bin $(BUILD)/dhry.bin \
  $(BUILD)/coremark.bin $(BUILD)/float_inline.bin $(SOFT_BUILD)/float.bin emulator
	@$(PYTHON) expected.py --check bench.c hand.nasm simple.nasm
	@$(PYTHON) floatexpected.py --check float.c
	@$(PYTHON) hazards.py --test
	@NICEEMU=$(EMU) $(PYTHON) pipecycles.py --test
	@NICEEMU=$(EMU) $(PYTHON) cycprof.py --test
	@$(PYTHON) words.py --test
	$(foreach p,$(PROGRAMS) float float_inline,$(call check,$(p)))
	@$(EMU) $(SOFT_BUILD)/float.bin < /dev/null > $(SOFT_BUILD)/float.out
	@if grep -q ' R1  00000000 ' $(SOFT_BUILD)/float.out && ! grep -q FAIL $(SOFT_BUILD)/float.out; \
	then echo "PASS float with float.nasm"; else echo "FAIL float with float.nasm"; exit 1; fi
	@NICEEMU=$(EMU) $(PYTHON) pipecycles.py --phases 6 $(BUILD)/bench.bin $(BUILD)/hand.bin $(BUILD)/simple.bin \
	  > /dev/null \
	  && echo "PASS pipecycles.py --phases 6"
	@NICEEMU=$(EMU) $(PYTHON) pipecycles.py --phases 5 $(BUILD)/float.bin > /dev/null \
	  && echo "PASS pipecycles.py --phases 5"
	@$(PYTHON) dhrycheck.py --test
	@$(EMU) --input $(DHRY_RUNS) $(BUILD)/dhry.bin < /dev/null > $(BUILD)/dhry.out
	@$(PYTHON) dhrycheck.py --runs $$(cat $(DHRY_RUNS)) $(BUILD)/dhry.out
	@echo 0 | $(EMU) $(BUILD)/dhry.bin | grep -q 'must be at least 1' && echo "PASS dhrystone with 0 runs"
	@echo x | $(EMU) $(BUILD)/dhry.bin | grep -q 'must be at least 1' && echo "PASS dhrystone with no number"
	@$(PYTHON) coremarkcheck.py --test
	@$(foreach s,perf valid,echo "$(CM_$(s)) $(CM_ITERATIONS)" | $(EMU) $(BUILD)/coremark.bin \
	  > $(BUILD)/coremark_$(s).out && \
	  $(PYTHON) coremarkcheck.py --seeds $(s) --iterations $(CM_ITERATIONS) $(BUILD)/coremark_$(s).out &&) true
	@echo 0 0 0x66 | $(EMU) $(BUILD)/coremark.bin | grep -q 'ERROR! Give seeds' \
	  && echo "PASS coremark with three numbers"
	@echo 0 0 0x66 -1 | $(EMU) $(BUILD)/coremark.bin | grep -q 'ERROR! Give seeds' \
	  && echo "PASS coremark with -1 iterations"

# Runs both on a core in the simulator, SIM of ../hdl/sim.mk, so that the
# cycles are the core's: CORE,
# the generic G_CORE of hdl/test/tb_core.vhd, is pipeline for the
# pipelined core or multicycle for the multi-cycle one. On an idle machine
# the pipelined core takes about 22 minutes and the multi-cycle core about
# 38: the pipelined core runs fewer cycles, but more logic in each. The program is given relative to
# hdl/build, where the simulator runs, and the output is written there too,
# with the retire log that pipecycles.py --retires reads,
# $(1)_$(CORE).retires. The simulator runs in a directory of its own for
# each program and core, as the runs of hdl/ do, because GHDL's LLVM and GCC
# backends write an executable where they run; so the top-level make slow
# can run them all at once.
# The files stay in hdl/build. PREBUILT=1 skips the analysis, which make
# slow has done.
CORE ?= pipeline
HDL_BUILD = $(abspath ../hdl/build)
SIM_BUILD = $(HDL_BUILD)
include ../hdl/sim.mk
ANALYZE = $(if $(PREBUILT),,$(MAKE) -C ../hdl analyze SIM=$(SIM))

# Runs tb_core on CORE in its own directory: $(1) is the name of the run,
# $(2) the program, and $(3) more generics.
define sim_core
mkdir -p $(HDL_BUILD)/bench_run/$(1)_$(CORE) && cd $(HDL_BUILD)/bench_run/$(1)_$(CORE) && \
	  $(call sim_run,tb_core,-gG_CORE=$(CORE) \
	  -gG_BIN_FILE=$(abspath $(2)) -gG_TRACE_FILE=$(HDL_BUILD)/$(1)_$(CORE).out -gG_TRACE=false $(3)) \
	  > $(HDL_BUILD)/$(1)_$(CORE).log 2>&1; status=$$?; sed '/^Halted/,$$d' $(HDL_BUILD)/$(1)_$(CORE).out
endef

define core_run
	@echo "$(1) on the $(CORE) core:"
	@$(call sim_core,$(1),$(BUILD)/$(1).bin,-gG_RETIRE_LOG=$(HDL_BUILD)/$(1)_$(CORE).retires); \
	  grep '^Read waits:' $(HDL_BUILD)/$(1)_$(CORE).log; \
	  if [ $$status -ne 0 ]; then cat $(HDL_BUILD)/$(1)_$(CORE).log; exit 1; fi

endef

$(SOFT_BUILD)/%.bin: FORCE
	@$(MAKE) --no-print-directory BUILD=$(SOFT_BUILD) NO_FPU=1 $@

FORCE:

core: $(CORE_PROGRAMS:%=$(BUILD)/%.bin)
	$(ANALYZE)
	$(foreach p,$(CORE_PROGRAMS),$(call core_run,$(p)))

# Dhrystone on a core in the simulator, CORE and SIM as above, with its output checked.
core-dhry: $(BUILD)/dhry.bin
	$(ANALYZE)
	@$(call sim_core,dhry,$(BUILD)/dhry.bin,-gG_INPUT_FILE=$(abspath $(DHRY_RUNS))); \
	  if [ $$status -ne 0 ]; then cat $(HDL_BUILD)/dhry_$(CORE).log; exit 1; fi
	@$(PYTHON) dhrycheck.py --runs $$(cat $(DHRY_RUNS)) ../hdl/build/dhry_$(CORE).out

# CoreMark on a core in the simulator, CORE and SIM as above, with
# CM_CORE_ITERATIONS and the seeds of CM_SEEDS, and its output checked.
core-coremark: $(BUILD)/coremark.bin
	$(ANALYZE)
	@mkdir -p $(HDL_BUILD)
	@echo "$(CM_$(CM_SEEDS)) $(CM_CORE_ITERATIONS)" > $(HDL_BUILD)/coremark_$(CORE).input
	@$(call sim_core,coremark,$(BUILD)/coremark.bin,-gG_INPUT_FILE=$(HDL_BUILD)/coremark_$(CORE).input); \
	  if [ $$status -ne 0 ]; then cat $(HDL_BUILD)/coremark_$(CORE).log; exit 1; fi
	@$(PYTHON) coremarkcheck.py --seeds $(CM_SEEDS) --iterations $(CM_CORE_ITERATIONS) \
	  ../hdl/build/coremark_$(CORE).out

$(BUILD)/bench.nasm: bench.wasm ../translator/nicewasm.py
	@mkdir -p $(BUILD)
	$(NICEWASM) -o $@ bench.wasm

$(BUILD)/bench.full.nasm: ../runtime/start_wasm.nasm $(BUILD)/bench.nasm ../runtime/lib.nasm \
  ../runtime/muldiv_mpu.nasm
	cat $^ > $@

$(BUILD)/dhry.nasm: $(DHRY)/dhry.wasm ../translator/nicewasm.py
	@mkdir -p $(BUILD)
	$(NICEWASM) -o $@ $(DHRY)/dhry.wasm

# Dhrystone reads its number of runs with scanf, whose float conversions
# use the float library, so it is joined with it.
$(BUILD)/dhry.full.nasm: ../runtime/start_wasm.nasm $(BUILD)/dhry.nasm ../runtime/lib.nasm \
  ../runtime/muldiv_mpu.nasm $(FLOAT_LIB)
	cat $^ > $@

$(BUILD)/coremark.nasm: $(CM)/coremark.wasm ../translator/nicewasm.py
	@mkdir -p $(BUILD)
	$(NICEWASM) -o $@ $(CM)/coremark.wasm

# CoreMark prints its seconds with %f, and reads its seeds with scanf,
# so it is joined with the float library too.
$(BUILD)/coremark.full.nasm: ../runtime/start_wasm.nasm $(BUILD)/coremark.nasm ../runtime/lib.nasm \
  ../runtime/muldiv_mpu.nasm $(FLOAT_LIB)
	cat $^ > $@

$(BUILD)/float.nasm: float.wasm ../translator/nicewasm.py
	@mkdir -p $(BUILD)
	$(NICEWASM) -o $@ float.wasm

$(BUILD)/float.full.nasm: ../runtime/start_wasm.nasm $(BUILD)/float.nasm ../runtime/lib.nasm \
  ../runtime/muldiv_mpu.nasm $(FLOAT_LIB)
	cat $^ > $@

# float.c with nicewasm's --inline-fpu, which needs float_fpu.nasm for the
# names of the FPU's words and the conversions of an i64 to f32.
$(BUILD)/float_inline.nasm: float.wasm ../translator/nicewasm.py
	@mkdir -p $(BUILD)
	$(NICEWASM) --inline-fpu -o $@ float.wasm

$(BUILD)/float_inline.full.nasm: ../runtime/start_wasm.nasm $(BUILD)/float_inline.nasm \
  ../runtime/lib.nasm ../runtime/muldiv_mpu.nasm ../runtime/float_fpu.nasm
	cat $^ > $@

# float.nasm is not checked in; the runtime translates it from float.wasm.
../runtime/float.nasm: ../runtime/float.wasm ../translator/nicewasm.py
	$(MAKE) -C ../runtime float.nasm

$(BUILD)/hand.full.nasm: ../runtime/start.nasm hand.nasm ../runtime/lib.nasm ../runtime/muldiv_mpu.nasm
	@mkdir -p $(BUILD)
	cat $^ > $@

$(BUILD)/simple.full.nasm: ../runtime/start.nasm simple.nasm ../runtime/lib.nasm ../runtime/muldiv_mpu.nasm
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
cycles: $(BUILD)/bench.bin $(BUILD)/hand.bin $(BUILD)/simple.bin $(BUILD)/float.bin \
  $(BUILD)/float_inline.bin emulator
	@NICEEMU=$(EMU) $(PYTHON) pipecycles.py $(BUILD)/bench.bin $(BUILD)/hand.bin $(BUILD)/simple.bin
	@NICEEMU=$(EMU) $(PYTHON) pipecycles.py $(BUILD)/float.bin $(BUILD)/float_inline.bin

# The model's cycles beside the pipelined core's, phase by phase, with the
# difference in percent, and by cause, from the output and the retire log
# of make core, which must have run first (README.md, The cycle estimate).
compare: $(BUILD)/bench.bin $(BUILD)/hand.bin emulator
	@NICEEMU=$(EMU) $(PYTHON) pipecycles.py --against ../hdl/build/bench_pipeline.out \
	  --causes ../hdl/build/bench_pipeline.retires $(BUILD)/bench.bin
	@NICEEMU=$(EMU) $(PYTHON) pipecycles.py --against ../hdl/build/hand_pipeline.out \
	  --causes ../hdl/build/hand_pipeline.retires $(BUILD)/hand.bin

# The same, charged to the source lines of each program: the listings
# build/bench.cyc.txt, build/hand.cyc.txt, and build/float.cyc.txt.
profile: $(BUILD)/bench.bin $(BUILD)/hand.bin $(BUILD)/float.bin $(BUILD)/bench.full.nasm \
  $(BUILD)/hand.full.nasm $(BUILD)/float.full.nasm emulator
	@NICEEMU=$(EMU) $(PYTHON) cycprof.py $(BUILD)/bench.full.nasm $(BUILD)/bench.bin
	@NICEEMU=$(EMU) $(PYTHON) cycprof.py $(BUILD)/hand.full.nasm $(BUILD)/hand.bin
	@NICEEMU=$(EMU) $(PYTHON) cycprof.py $(BUILD)/float.full.nasm $(BUILD)/float.bin

# The size in words of the translated modules the READMEs quote: the
# benchmark's, translator/test/safe.zig's, CoreMark's, the float library's, and that
# of a module of all the math functions of the C library, in double and
# float, which needs clang.
MATH_FUNCS = acos asin atan atan2 ceil copysign cos exp fabs floor fmax fmin fmod frexp \
  ldexp log log10 log2 modf nearbyint pow rint round scalbn sin sqrt tan trunc
words:
	@$(PYTHON) words.py bench.wasm ../translator/test/safe.wasm $(CM)/coremark.wasm
	@$(PYTHON) words.py --library float ../runtime/float.wasm
	@$(MAKE) -s --no-print-directory -C $(LIBC) libc.a
	@mkdir -p $(BUILD)
	@$(CLANG) --target=wasm32 -mbulk-memory -nostdlib -Wl,--no-entry \
	  $(foreach f,$(MATH_FUNCS),-Wl,--export=$(f) -Wl,--export=$(f)f) \
	  -o $(BUILD)/math.wasm $(LIBC)/libc.a
	@$(PYTHON) words.py $(BUILD)/math.wasm

# Needs mypy (pip install mypy).
typecheck:
	MYPYPATH=../assembler $(PYTHON) -m mypy --strict expected.py floatexpected.py hazards.py pipecycles.py \
	  cycprof.py words.py dhrycheck.py coremarkcheck.py

# Rebuilds bench.wasm from bench.c, float.wasm from float.c,
# dhrystone/dhry.wasm from its sources, and coremark/coremark.wasm from
# its. Needs clang with the wasm32 target and wasm-ld, and builds the C
# library first.
wasm:
	$(MAKE) -C $(LIBC) libc.a
	$(CLANG) $(CFLAGS) $(LDFLAGS) -o bench.wasm bench.c $(LIBC)/libc.a
	$(CLANG) $(CFLAGS) $(LDFLAGS) -o float.wasm float.c $(LIBC)/libc.a
	$(CLANG) $(DHRY_CFLAGS) $(LDFLAGS) -o $(DHRY)/dhry.wasm $(DHRY)/dhry_1.c $(DHRY)/dhry_2.c \
	  $(LIBC)/libc.a
	$(CLANG) $(CM_CFLAGS) $(LDFLAGS) -o $(CM)/coremark.wasm $(CM_SRCS) $(LIBC)/libc.a
	@chmod -x bench.wasm float.wasm $(DHRY)/dhry.wasm $(CM)/coremark.wasm

# Builds and runs bench.c and float.c on the host, as a second check of
# their results. The counters read 0 there. Then CoreMark, with both sets
# of seeds and CM_ITERATIONS, its CRCs checked.
native:
	@mkdir -p $(BUILD)
	$(CLANG) -O2 -Wall -Wextra -o $(BUILD)/bench.native bench.c
	@./$(BUILD)/bench.native
	$(CLANG) -O2 -Wall -Wextra -o $(BUILD)/float.native float.c
	@./$(BUILD)/float.native
	$(CLANG) -O2 -Wall -Wextra -DFLAGS_STR='"-O2"' -o $(BUILD)/coremark.native $(CM_SRCS)
	@$(foreach s,perf valid,echo "$(CM_$(s)) $(CM_ITERATIONS)" | ./$(BUILD)/coremark.native \
	  > $(BUILD)/coremark_$(s).native.out && \
	  $(PYTHON) coremarkcheck.py --host --seeds $(s) --iterations $(CM_ITERATIONS) \
	  $(BUILD)/coremark_$(s).native.out &&) true

emulator:
	$(MAKE) -C ../emulator build

clean:
	rm -rf $(BUILD)

.PHONY: run dhry coremark test core core-dhry core-coremark hazards cycles compare profile words typecheck wasm native emulator clean
