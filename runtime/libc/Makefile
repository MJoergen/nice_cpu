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

# Each test/X.wasm is translated and joined with the start-up code,
# lib.nasm, and muldiv_mpu.nasm. It is assembled and run, and the console
# output, main's result in R1, and the exit status are compared with
# test/X.expected. With KEEP=DIR, an absolute path, each test also leaves
# its program in DIR/libc_X.bin, and its console input in DIR/libc_X.input,
# for the tests of the FPGA core in hdl/. The step count and the other registers are left out, so
# that the expected files do not change with the compiler.
define check
	@$(NICEWASM) -o test/$(1).out.nasm test/$(1).wasm
	@cat ../start_wasm.nasm test/$(1).out.nasm ../lib.nasm ../muldiv_mpu.nasm > test/$(1).full.nasm
	@$(ASM) -o test/$(1).out.bin test/$(1).full.nasm
	@$(EMU) $(if $(wildcard test/$(1).input),--input test/$(1).input) test/$(1).out.bin < /dev/null > test/$(1).raw; echo "exit $$?" > test/$(1).status
	$(if $(KEEP),@mkdir -p $(KEEP) && cp test/$(1).out.bin $(KEEP)/libc_$(1).bin)
	$(if $(KEEP),$(if $(wildcard test/$(1).input),@cp test/$(1).input $(KEEP)/libc_$(1).input))
	@sed '/^\(Halted\|Stopped\)/,$$d' test/$(1).raw > test/$(1).out
	@grep -o ' R1  [0-9a-f]*' test/$(1).raw | cut -c2- >> test/$(1).out; cat test/$(1).status >> test/$(1).out
	@if cmp -s test/$(1).out test/$(1).expected; then echo "PASS libc/$(1)"; \
	else echo "FAIL libc/$(1)"; diff test/$(1).expected test/$(1).out; exit 1; fi

endef

test: emulator
	$(foreach t,$(TESTS),$(call check,$(t)))
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
