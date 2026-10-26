PYTHON ?= python3
ZIG ?= zig
RUSTC ?= rustc
ASM = $(PYTHON) ../assembler/niceasm.py
EMU = ../emulator/zig-out/bin/niceemu

# Each test/X.nasm is joined with a start-up file, lib.nasm, and
# muldiv_mpu.nasm into one program, as ABI.md describes. The program is
# assembled and run, and the output and exit status are compared with
# test/X.expected. The tests in SOFT_TESTS run a second time as X_soft,
# with muldiv_soft.nasm instead, and are compared with test/X_soft.expected.
TESTS = start start_wasm mul trap div div64 mul64 bits device edge trapvec trapreport trapreport_big
SOFT_TESTS = mul div mul64 div64 edge
START_start_wasm = start_wasm.nasm
START_trap       = start_wasm.nasm
START_trapreport = start_wasm_trap.nasm
AFTER_trapreport = trapmsg.nasm
START_trapreport_big = start_wasm_trap.nasm
AFTER_trapreport_big = trapmsg.nasm
OPTS_start      = -d 0xfffffeff:1
OPTS_start_wasm = -d 0x1b:1 -d 0xfffffeff:1
OPTS_mul        = -d 0x34:10
OPTS_div        = -d 0x4b:32
OPTS_div64      = -d 0x6f:64
OPTS_mul64      = -d 0x48:16
OPTS_bits       = -d 0x54:54
OPTS_edge       = -d 0xd8:124
OPTS_trapvec    = -d 0x1b:4
OPTS_device     = -s -d 0x7f:8 -d 0xffff0000:3 -d 0xffff0052:1 -d 0xffff07ce:2
INPUT_device    = test/device.input

# With KEEP=DIR, an absolute path, each test also leaves its program in
# DIR/X.bin, and its console input, if any, in DIR/X.input, for the tests
# of the FPGA core in hdl/. libc/Makefile does the same.
define keep
	$(if $(KEEP),@mkdir -p $(KEEP) && cp $(1) $(KEEP)/$(3).bin)
	$(if $(KEEP),$(if $(2),@cp $(2) $(KEEP)/$(3).input))
endef

# $(1) is the name of the run, $(2) the test, and $(3) the muldiv file.
define check
	@cat $(or $(START_$(2)),start.nasm) test/$(2).nasm lib.nasm $(3) $(AFTER_$(2)) > test/$(1).out.nasm
	@$(ASM) -o test/$(1).out.bin test/$(1).out.nasm
	@$(EMU) $(OPTS_$(2)) $(if $(INPUT_$(2)),--input $(INPUT_$(2))) test/$(1).out.bin > test/$(1).out; \
	  echo "exit $$?" >> test/$(1).out
	$(call keep,test/$(1).out.bin,$(INPUT_$(2)),$(1))
	@if cmp -s test/$(1).out test/$(1).expected; then echo "PASS $(1)"; \
	else echo "FAIL $(1)"; diff test/$(1).expected test/$(1).out; exit 1; fi

endef

# The tests of nice.zig and nice.rs, test/X.zig and test/X.rs, as in
# libc/Makefile: each test/X.wasm is translated, joined with
# start_wasm.nasm, lib.nasm, and muldiv_mpu.nasm, and run with test/X.input
# as the console input. The console output, main's result in R1, and the
# exit status are compared with test/X.expected. The .wasm files are
# checked in, so make test needs no Zig or Rust; make wasm rebuilds them.
ZIG_TESTS = nicezig zigpoll
RUST_TESTS = nicers rustpoll

define check_wasm
	@$(PYTHON) ../translator/nicewasm.py -o test/$(1).out.nasm test/$(1).wasm
	@cat start_wasm.nasm test/$(1).out.nasm lib.nasm muldiv_mpu.nasm > test/$(1).full.nasm
	@$(ASM) -o test/$(1).out.bin test/$(1).full.nasm
	@$(EMU) --input test/$(1).input test/$(1).out.bin < /dev/null > test/$(1).raw; echo "exit $$?" > test/$(1).status
	$(call keep,test/$(1).out.bin,test/$(1).input,$(1))
	@sed '/^\(Halted\|Stopped\)/,$$d' test/$(1).raw > test/$(1).out
	@grep -o ' R1  [0-9a-f]*' test/$(1).raw | cut -c2- >> test/$(1).out; cat test/$(1).status >> test/$(1).out
	@if cmp -s test/$(1).out test/$(1).expected; then echo "PASS $(1)"; \
	else echo "FAIL $(1)"; diff test/$(1).expected test/$(1).out; exit 1; fi

endef

test: emulator
	$(foreach t,$(TESTS),$(call check,$(t),$(t),muldiv_mpu.nasm))
	$(foreach t,$(SOFT_TESTS),$(call check,$(t)_soft,$(t),muldiv_soft.nasm))
	$(foreach t,$(ZIG_TESTS) $(RUST_TESTS),$(call check_wasm,$(t)))
	@rm -f test/*.out test/*.out.nasm test/*.out.bin test/*.full.nasm test/*.raw test/*.status
	@$(MAKE) --no-print-directory -C libc test

# The float library, translated from float.wasm as the library module float
# (WASM.md). Only float.wasm is checked in.
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

# Rebuilds the .wasm files of the Zig and Rust tests. This needs Zig 0.15
# and rustc with the wasm32-unknown-unknown target.
wasm:
	@for t in $(ZIG_TESTS); do \
	  $(ZIG) build-exe -target wasm32-freestanding -fno-entry -rdynamic -O ReleaseSmall -fstrip \
	    --stack 4096 --initial-memory=65536 --dep nice -Mroot=test/$$t.zig -Mnice=nice.zig \
	    -femit-bin=test/$$t.wasm || exit 1; \
	done
	@for t in $(RUST_TESTS); do \
	  $(RUSTC) --target wasm32-unknown-unknown --crate-type cdylib -C opt-level=s -C panic=abort \
	    -C strip=debuginfo -C link-arg=-zstack-size=4096 -C link-arg=--initial-memory=65536 \
	    -o test/$$t.wasm test/$$t.rs || exit 1; \
	done
	@rm -f test/*.wasm.o

emulator:
	$(MAKE) -C ../emulator build

# Needs mypy (pip install mypy).
typecheck:
	cd libc/test && $(PYTHON) -m mypy --strict fuzz_printf.py

clean:
	rm -f test/*.out test/*.out.nasm test/*.out.bin test/*.full.nasm test/*.raw test/*.status float.nasm
	$(MAKE) -C libc clean

.PHONY: test emulator typecheck clean float wasm
