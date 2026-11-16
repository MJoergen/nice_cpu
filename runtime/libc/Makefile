PYTHON ?= python3
CLANG ?= clang
AR ?= llvm-ar
NICEWASM = $(PYTHON) ../../translator/nicewasm.py
ASM = $(PYTHON) ../../assembler/niceasm.py
EMU = ../../emulator/zig-out/bin/niceemu

CFLAGS = --target=wasm32 -mbulk-memory -O2 -ffreestanding -nostdlibinc -isystem include \
  -Wall -Wextra
LDFLAGS = -nostdlib -Wl,--no-entry -Wl,--export=main -Wl,--stack-first -Wl,-z,stack-size=4096 \
  -Wl,--initial-memory=65536

SRCS = $(wildcard src/*.c)
OBJS = $(SRCS:src/%.c=build/%.o)

# The math functions of math.h that are C (README.md, Math functions):
# sin, cos, and tan, on the FPU's functions and musl's reduction of a
# huge argument, and musl's frexp, modf, fmin, and fmax, but for libm.h,
# features.h, and builtin.c (src/math/COPYRIGHT). They include their own
# headers with angle brackets, as in musl. -Os keeps clang from unrolling
# the loops of __rem_pio2_large, which saves 2200 words and no step on
# other arguments.
MATH_CFLAGS = $(filter-out -O2,$(CFLAGS)) -Os -I src/math
MATH_SRCS = $(wildcard src/math/*.c)
MATH_OBJS = $(MATH_SRCS:src/math/%.c=build/math/%.o)

# mchess keeps a move list of 2.5 KB on the stack in each level of its
# search: five levels, and then one per capture in the quiescence search,
# at most 30, since no king is taken. With main and the root, that is about
# 100 KB, so it is linked with a 128 KB stack in a memory of four pages.
# 64 KB overflows in the first search from the opening position, which
# takes 10^10 steps, so test/mchess.input has no "go". The later options
# win.
BIGSTACK = -Wl,-z,stack-size=131072 -Wl,--initial-memory=262144

# The test programs, test/X.c. Their .wasm files are checked in, so make
# test needs no C compiler; make wasm rebuilds them. A test/X.input file is
# the console input of test X.
TESTS = stdio stream lines string stdlib scanf iscanf nice printf iprintf strings numbers sscanf malloc noheap abort exit limits assert time math floatio \
  mchess
# The tests of the i families, which must name no label of the float
# library, so that a program that calls only them is joined without it.
NOFLOAT_TESTS = iprintf iscanf
# The tests that also run as a program under a monitor, as X_mon: joined
# after ../test/monitor.nasm, the stand-in for a monitor at 0, with
# ../start_wasm_mon.nasm, and compared with test/X_mon.expected, which also
# shows R2, the number of bytes the stand-in's putc routine wrote.
MON_TESTS = exit
# The tests that also run with only the start of their memory reserved, as
# X_small: translated with --memory-bytes 32768, half of the page, and
# compared with test/X_small.expected. malloc's heap then ends there, so
# fewer of its blocks fit before malloc fails, with the same output. A
# block past the end would trap (code 2).
SMALL_TESTS = malloc
# The tests that also run with a memory that ends before their heap
# starts, as X_cut: translated with --memory-bytes $(CUT_BYTES), and
# compared with test/X_cut.expected. malloc must take such a heap as
# empty. The bytes are the 4096 of the stack (LDFLAGS) and the 12 of
# malloc.c's three words, which are all the static data of such a test.
# They end 4 below __heap_base, which the linker puts at a multiple of 16.
# With fewer bytes, malloc's use of its words traps (code 2).
CUT_TESTS = noheap
CUT_BYTES = 4108

libc.a: $(OBJS) $(MATH_OBJS)
	rm -f $@
	$(AR) rcs $@ $(OBJS) $(MATH_OBJS)

build/%.o: src/%.c $(wildcard include/*.h)
	@mkdir -p build
	$(CLANG) $(CFLAGS) -c -o $@ $<

# floatscan.c is musl's, which compares c-'0' with 10U on purpose. -Os
# saves 6800 words and costs 3% of the steps of strtod.
build/floatscan.o: CFLAGS := $(filter-out -O2,$(CFLAGS)) -Os -Wno-sign-compare

build/math/%.o: src/math/%.c $(wildcard include/*.h src/math/*.h)
	@mkdir -p build/math
	$(CLANG) $(MATH_CFLAGS) -c -o $@ $<

wasm: libc.a
	@for t in $(TESTS); do \
	  $(CLANG) $(CFLAGS) $(LDFLAGS) $$(if [ $$t = mchess ]; then echo $(BIGSTACK); fi) -o test/$$t.wasm test/$$t.c libc.a || exit 1; \
	done
	@chmod -x test/*.wasm

# Each test/X.wasm is translated and joined with the start-up code,
# lib.nasm, and muldiv_mpu.nasm, and the float library, float_fpu.nasm, if
# the program names one of its labels, as nicebuild joins it: math, and
# every test that links scanf, whose float conversions use floats. It is
# assembled and run, and the console output, main's result in R1, and the
# exit status are compared with test/X.expected. With KEEP=DIR, an absolute path, each test also leaves
# its program in DIR/libc_X.bin, and its console input in DIR/libc_X.input,
# for the tests of the FPGA core in hdl/. If test/X.core.input exists, that is
# the input it leaves. mchess.core.input has no "perft 3", which takes 11
# million steps and, in GHDL, hours. The step count and the other registers are left out, so
# that the expected files do not change with the compiler.
#
# hdl/ compares the core with the emulator only, so a kept program may
# reserve less of its memory, which ___wasm_start then clears in fewer
# steps (WASM.md, Linear memory). Unless the run has nicewasm options of
# its own, the test is translated again with --memory-bytes, with each
# size of KEEP_BYTES in turn, and the first whose output is the expected
# one is kept. Otherwise the program is kept as it is: mchess, whose
# stack alone is 128 KB, and a test that its data or its heap does not
# let fit.
KEEP_BYTES = 8192 16384 32768

# Translates test/$(2).wasm with the options $(5), joins it after the
# files $(3), assembles it, and runs it, as the run $(1): test/$(1).out
# gets the console output, the registers $(4), and the exit status. One
# shell command, for check and keep.
define run
$(NICEWASM) $(5) -o test/$(1).out.nasm test/$(2).wasm && \
	  cat $(3) test/$(1).out.nasm ../lib.nasm ../muldiv_mpu.nasm > test/$(1).full.nasm && \
	  { if grep -qwFf build/float.labels test/$(1).out.nasm; then cat ../float_fpu.nasm >> test/$(1).full.nasm; fi; } && \
	  $(ASM) -o test/$(1).out.bin test/$(1).full.nasm && \
	  { $(EMU) $(if $(wildcard test/$(2).input),--input test/$(2).input) test/$(1).out.bin < /dev/null > test/$(1).raw; \
	    echo "exit $$?" > test/$(1).status; } && \
	  sed '/^\(Halted\|Stopped\)/,$$d' test/$(1).raw > test/$(1).out && \
	  { grep -o ' $(4)' test/$(1).raw | cut -c2- >> test/$(1).out; cat test/$(1).status >> test/$(1).out; }
endef

# $(1) is the name of the run, $(2) the test, $(3) the files before the
# program, $(4) the registers to show, and $(5) nicewasm's options.
define check
	@$(call run,$(1),$(2),$(3),$(4),$(5))
	$(if $(filter $(2),$(NOFLOAT_TESTS)),@if grep -qwFf build/float.labels test/$(1).out.nasm; then \
	  echo "FAIL libc/$(1): it names a label of the float library"; exit 1; fi)
	@if cmp -s test/$(1).out test/$(1).expected; then echo "PASS libc/$(1)"; \
	else echo "FAIL libc/$(1)"; diff test/$(1).expected test/$(1).out; exit 1; fi
	$(if $(KEEP),@mkdir -p $(KEEP) && cp test/$(1).out.bin $(KEEP)/libc_$(1).bin)
	$(if $(KEEP),$(if $(wildcard test/$(2).input),@cp $(or $(wildcard test/$(2).core.input),test/$(2).input) $(KEEP)/libc_$(1).input))
	$(if $(KEEP),$(if $(5),,@for n in $(KEEP_BYTES); do \
	  if { $(call run,$(1)_keep,$(2),$(3),$(4),--memory-bytes $$n); } 2>/dev/null && \
	    cmp -s test/$(1)_keep.out test/$(1).expected; then cp test/$(1)_keep.out.bin $(KEEP)/libc_$(1).bin; break; fi; \
	done))

endef

# build/float.labels holds the labels of the float library's routines:
# ___name for the float operations, and _name for the functions of math.h.
test: emulator
	@mkdir -p build && grep -oE '^_[A-Za-z0-9_]+$$' ../float_fpu.nasm > build/float.labels
	$(foreach t,$(TESTS),$(call check,$(t),$(t),../start_wasm.nasm,R1  [0-9a-f]*))
	$(foreach t,$(MON_TESTS),$(call check,$(t)_mon,$(t),../test/monitor.nasm ../start_wasm_mon.nasm,R1  [0-9a-f]* R2  [0-9a-f]*))
	$(foreach t,$(SMALL_TESTS),$(call check,$(t)_small,$(t),../start_wasm.nasm,R1  [0-9a-f]*,--memory-bytes 32768))
	$(foreach t,$(CUT_TESTS),$(call check,$(t)_cut,$(t),../start_wasm.nasm,R1  [0-9a-f]*,--memory-bytes $(CUT_BYTES)))
	@rm -f test/*.out test/*.raw test/*.status test/*.out.nasm test/*.full.nasm test/*.out.bin

# A random test of the printf family and the i family against a model of
# C's printf, test/fuzz_printf.py, one of strtod and strtof against exact arithmetic,
# test/fuzz_strtod.py, and one of the math functions against the host's
# libm and exact arithmetic, test/fuzz_math.py. They compile programs with clang, so make test does not run
# them, and the top-level make slow does.
fuzz: libc.a emulator
	@$(PYTHON) test/fuzz_printf.py 1 300
	@$(PYTHON) test/fuzz_printf.py --integer 1 300
	@$(PYTHON) test/fuzz_strtod.py 1 1000
	@$(PYTHON) test/fuzz_math.py 1 1000

emulator:
	$(MAKE) -C ../../emulator build

clean:
	rm -rf build libc.a test/*.out test/*.raw test/*.status test/*.out.nasm test/*.full.nasm test/*.out.bin

.PHONY: wasm test fuzz emulator clean
