PYTHON ?= python3
ZIG ?= zig
ASM = $(PYTHON) ../assembler/niceasm.py
EMU = ../emulator/zig-out/bin/niceemu

# Each test/X.nasm is joined with a start-up file, lib.nasm, and
# muldiv_mpu.nasm into one program, as ISA.md §9.3 describes. The program is
# assembled and run, and the output and exit status are compared with
# test/X.expected. The tests in SOFT_TESTS run a second time as X_soft,
# with muldiv_soft.nasm instead, and are compared with test/X_soft.expected.
TESTS = start start_wasm mul trap div div64 mul64 bits
SOFT_TESTS = mul div mul64 div64
START_start_wasm = start_wasm.nasm
START_trap       = start_wasm.nasm
OPTS_start      = -d 0xfffffeff:1
OPTS_start_wasm = -d 0x1b:1 -d 0xfffffeff:1
OPTS_mul        = -d 0x34:10
OPTS_div        = -d 0x4b:32
OPTS_div64      = -d 0x6f:64
OPTS_mul64      = -d 0x48:16
OPTS_bits       = -d 0x54:54

# $(1) is the name of the run, $(2) the test, and $(3) the muldiv file.
define check
	@cat $(or $(START_$(2)),start.nasm) test/$(2).nasm lib.nasm $(3) > test/$(1).out.nasm
	@$(ASM) -o test/$(1).out.bin test/$(1).out.nasm
	@$(EMU) $(OPTS_$(2)) test/$(1).out.bin > test/$(1).out; echo "exit $$?" >> test/$(1).out
	@if cmp -s test/$(1).out test/$(1).expected; then echo "PASS $(1)"; \
	else echo "FAIL $(1)"; diff test/$(1).expected test/$(1).out; exit 1; fi

endef

test: emulator
	$(foreach t,$(TESTS),$(call check,$(t),$(t),muldiv_mpu.nasm))
	$(foreach t,$(SOFT_TESTS),$(call check,$(t)_soft,$(t),muldiv_soft.nasm))
	@rm -f test/*.out test/*.out.nasm test/*.out.bin
	@$(MAKE) --no-print-directory -C libc test

# The float library, translated from float.wasm as the library module float
# (ISA.md §9.4). Only float.wasm is checked in.
float.nasm: float.wasm ../translator/nicewasm.py
	$(PYTHON) ../translator/nicewasm.py --library float -o float.nasm float.wasm

# Rebuilds float.wasm from float.zig and parts of Zig's compiler_rt. This
# needs Zig 0.15.
FLOAT_EXPORTS = __addsf3 __subsf3 __mulsf3 __divsf3 __adddf3 __subdf3 __muldf3 __divdf3 \
  __eqsf2 __nesf2 __ltsf2 __lesf2 __gtsf2 __gesf2 __eqdf2 __nedf2 __ltdf2 __ledf2 __gtdf2 __gedf2 \
  __floatsisf __floatunsisf __floatdisf __floatundisf __floatsidf __floatunsidf __floatdidf \
  __floatundidf __extendsfdf2 __truncdfsf2 __fixsfsi __fixunssfsi __fixsfdi __fixunssfdi \
  __fixdfsi __fixunsdfsi __fixdfdi __fixunsdfdi __ceilsf __floorsf __truncsf __nearestsf \
  __ceildf __floordf __truncdf __nearestdf __minsf __maxsf __mindf __maxdf __sqrtsf __sqrtdf

float:
	rm -rf build && mkdir build
	cp -r "$$($(ZIG) env | sed -n 's/.*\.lib_dir = "\(.*\)".*/\1/p')/compiler_rt" build/
	cp float.zig build/
	$(ZIG) build-exe -target wasm32-freestanding -fno-entry -fno-compiler-rt -O ReleaseSmall \
	  -fstrip --stack 1024 --initial-memory=65536 $(FLOAT_EXPORTS:%=--export=%) \
	  -femit-bin=float.wasm build/float.zig
	rm -rf build float.wasm.o

emulator:
	$(MAKE) -C ../emulator build

clean:
	rm -f test/*.out test/*.out.nasm test/*.out.bin float.nasm
	$(MAKE) -C libc clean

.PHONY: test emulator clean float
