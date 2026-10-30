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
TESTS = stdio stream string stdlib scanf nice printf strings numbers sscanf malloc abort exit limits assert time mchess
# The tests that also run as a program under a monitor, as X_mon: joined
# after ../test/monitor.nasm, the stand-in for a monitor at 0, with
# ../start_wasm_mon.nasm, and compared with test/X_mon.expected, which also
# shows R2, the number of bytes the stand-in's putc routine wrote.
MON_TESTS = exit

libc.a: $(OBJS)
	rm -f $@
	$(AR) rcs $@ $(OBJS)

build/%.o: src/%.c $(wildcard include/*.h)
	@mkdir -p build
	$(CLANG) $(CFLAGS) -c -o $@ $<

wasm: libc.a
	@for t in $(TESTS); do \
	  $(CLANG) $(CFLAGS) $(LDFLAGS) $$(if [ $$t = mchess ]; then echo $(BIGSTACK); fi) -o test/$$t.wasm test/$$t.c libc.a || exit 1; \
	done
	@chmod -x test/*.wasm

# Each test/X.wasm is translated and joined with the start-up code,
# lib.nasm, and muldiv_mpu.nasm. It is assembled and run, and the console
# output, main's result in R1, and the exit status are compared with
# test/X.expected. With KEEP=DIR, an absolute path, each test also leaves
# its program in DIR/libc_X.bin, and its console input in DIR/libc_X.input,
# for the tests of the FPGA core in hdl/. If test/X.core.input exists, that is
# the input it leaves. mchess.core.input has no "perft 3", which takes 11
# million steps and, in GHDL, hours. The step count and the other registers are left out, so
# that the expected files do not change with the compiler.
# $(1) is the name of the run, $(2) the test, $(3) the files before the
# program, and $(4) the registers to show.
define check
	@$(NICEWASM) -o test/$(1).out.nasm test/$(2).wasm
	@cat $(3) test/$(1).out.nasm ../lib.nasm ../muldiv_mpu.nasm > test/$(1).full.nasm
	@$(ASM) -o test/$(1).out.bin test/$(1).full.nasm
	@$(EMU) $(if $(wildcard test/$(2).input),--input test/$(2).input) test/$(1).out.bin < /dev/null > test/$(1).raw; echo "exit $$?" > test/$(1).status
	$(if $(KEEP),@mkdir -p $(KEEP) && cp test/$(1).out.bin $(KEEP)/libc_$(1).bin)
	$(if $(KEEP),$(if $(wildcard test/$(2).input),@cp $(or $(wildcard test/$(2).core.input),test/$(2).input) $(KEEP)/libc_$(1).input))
	@sed '/^\(Halted\|Stopped\)/,$$d' test/$(1).raw > test/$(1).out
	@grep -o ' $(4)' test/$(1).raw | cut -c2- >> test/$(1).out; cat test/$(1).status >> test/$(1).out
	@if cmp -s test/$(1).out test/$(1).expected; then echo "PASS libc/$(1)"; \
	else echo "FAIL libc/$(1)"; diff test/$(1).expected test/$(1).out; exit 1; fi

endef

test: emulator
	$(foreach t,$(TESTS),$(call check,$(t),$(t),../start_wasm.nasm,R1  [0-9a-f]*))
	$(foreach t,$(MON_TESTS),$(call check,$(t)_mon,$(t),../test/monitor.nasm ../start_wasm_mon.nasm,R1  [0-9a-f]* R2  [0-9a-f]*))
	@rm -f test/*.out test/*.raw test/*.status test/*.out.nasm test/*.full.nasm test/*.out.bin

# A random test of the printf family against a model of C's printf,
# test/fuzz_printf.py. It compiles a program with clang, so make test
# does not run it.
fuzz: libc.a emulator
	@$(PYTHON) test/fuzz_printf.py 1 300

emulator:
	$(MAKE) -C ../../emulator build

clean:
	rm -rf build libc.a test/*.out test/*.raw test/*.status test/*.out.nasm test/*.full.nasm test/*.out.bin

.PHONY: wasm test fuzz emulator clean
