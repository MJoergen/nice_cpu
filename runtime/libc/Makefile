PYTHON ?= python3
CLANG ?= clang
AR = llvm-ar
NICEWASM = $(PYTHON) ../../translator/nicewasm.py
ASM = $(PYTHON) ../../assembler/niceasm.py
EMU = ../../emulator/zig-out/bin/niceemu

CFLAGS = --target=wasm32 -mbulk-memory -O2 -ffreestanding -nostdlibinc -isystem include \
  -Wall -Wextra
LDFLAGS = -nostdlib -Wl,--no-entry -Wl,--export=main -Wl,-z,stack-size=4096 \
  -Wl,--initial-memory=65536

SRCS = $(wildcard src/*.c)
OBJS = $(SRCS:src/%.c=build/%.o)

# The test programs, test/X.c. Their .wasm files are checked in, so make
# test needs no C compiler; make wasm rebuilds them.
TESTS = stdio string stdlib

libc.a: $(OBJS)
	rm -f $@
	$(AR) rcs $@ $(OBJS)

build/%.o: src/%.c $(wildcard include/*.h)
	@mkdir -p build
	$(CLANG) $(CFLAGS) -c -o $@ $<

wasm: libc.a
	@for t in $(TESTS); do \
	  $(CLANG) $(CFLAGS) $(LDFLAGS) -o test/$$t.wasm test/$$t.c libc.a || exit 1; \
	done

# Each test/X.wasm is translated and joined with the start-up code,
# lib.nasm, and muldiv_mpu.nasm. It is assembled and run, and the console
# output, main's result in R1, and the exit status are compared with
# test/X.expected. The step count and the other registers are left out, so
# that the expected files do not change with the compiler.
define check
	@$(NICEWASM) -o test/$(1).out.nasm test/$(1).wasm
	@cat ../start_wasm.nasm test/$(1).out.nasm ../lib.nasm ../muldiv_mpu.nasm > test/$(1).full.nasm
	@$(ASM) -o test/$(1).out.bin test/$(1).full.nasm
	@$(EMU) test/$(1).out.bin > test/$(1).raw; echo "exit $$?" > test/$(1).status
	@sed '/^\(Halted\|Stopped\)/,$$d' test/$(1).raw > test/$(1).out
	@grep -o ' R1  [0-9a-f]*' test/$(1).raw | cut -c2- >> test/$(1).out; cat test/$(1).status >> test/$(1).out
	@if cmp -s test/$(1).out test/$(1).expected; then echo "PASS libc/$(1)"; \
	else echo "FAIL libc/$(1)"; diff test/$(1).expected test/$(1).out; exit 1; fi

endef

test: emulator
	$(foreach t,$(TESTS),$(call check,$(t)))
	@rm -f test/*.out test/*.raw test/*.status test/*.out.nasm test/*.full.nasm test/*.out.bin

emulator:
	$(MAKE) -C ../../emulator build

clean:
	rm -rf build libc.a test/*.out test/*.raw test/*.status test/*.out.nasm test/*.full.nasm test/*.out.bin

.PHONY: wasm test emulator clean
