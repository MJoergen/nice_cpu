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
# A test of a start-up file for a program under a monitor is joined after
# PRE_X, test/monitor.nasm, the stand-in for the monitor, which sits at 0
# and calls the program at 0x8000, or test/monitor_console.nasm, the same
# with R1 = 0, which leaves the output on the console.
TESTS = start start_wasm start_mon start_wasm_mon start_wasm_trap_mon exit exit_mon console_mon \
  mul trap div div64 mul64 bits clz isqrt device edge trapvec trapreport trapreport_big \
  trapreport_nofpu
SOFT_TESTS = mul div mul64 div64 edge bits clz isqrt
START_start_wasm = start_wasm.nasm
START_start_mon  = start_mon.nasm
START_start_wasm_mon = start_wasm_mon.nasm
START_start_wasm_trap_mon = start_wasm_trap_mon.nasm
AFTER_start_wasm_trap_mon = trapmsg.nasm
START_exit_mon   = start_mon.nasm
START_console_mon = start_mon.nasm
PRE_start_mon    = test/monitor.nasm
PRE_start_wasm_mon = test/monitor.nasm
PRE_start_wasm_trap_mon = test/monitor.nasm
PRE_exit_mon     = test/monitor.nasm
PRE_console_mon  = test/monitor_console.nasm
START_trap       = start_wasm.nasm
START_trapreport = start_wasm_trap.nasm
AFTER_trapreport = trapmsg.nasm
START_trapreport_big = start_wasm_trap.nasm
AFTER_trapreport_big = trapmsg.nasm
START_trapreport_nofpu = start_wasm_trap.nasm
AFTER_trapreport_nofpu = trapmsg.nasm
OPTS_start      = -d 0xfffffeff:1
OPTS_start_wasm = -d 0x17:1 -d 0xfffffeff:1
OPTS_start_mon  = -d 0x800b:1 -d 0x8015:2 -d 0xfffffefe:2
OPTS_start_wasm_mon = -d 0x800e:1 -d 0x8023:2 -d 0xfffffefb:5
OPTS_start_wasm_trap_mon = -d 0x15:1 -d 0xfffffefe:2
OPTS_exit       = -d 0xfffffefc:4
OPTS_exit_mon   = -d 0xfffffefc:4
OPTS_console_mon = -d 0x15:1
OPTS_mul        = -d 0x2f:10
OPTS_div        = -d 0x3d:32
OPTS_div64      = -d 0x61:64
OPTS_mul64      = -d 0x43:16
OPTS_bits       = -d 0x40:54
OPTS_clz        = -d 0x1a:64
OPTS_isqrt      = -d 0x3c:12
OPTS_edge       = -d 0xb9:124
OPTS_trapvec    = -d 0x6:1 -d 0x1a:3
OPTS_device     = -s -d 0x4e:8 -d 0xffff0000:3 -d 0xffff0052:1 -d 0xffff08be:2
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
	@cat $(PRE_$(2)) $(or $(START_$(2)),start.nasm) test/$(2).nasm lib.nasm $(3) $(AFTER_$(2)) > test/$(1).out.nasm
	@$(ASM) -o test/$(1).out.bin test/$(1).out.nasm
	@$(EMU) $(OPTS_$(2)) $(if $(INPUT_$(2)),--input $(INPUT_$(2))) test/$(1).out.bin > test/$(1).out; \
	  echo "exit $$?" >> test/$(1).out
	$(call keep,test/$(1).out.bin,$(INPUT_$(2)),$(1))
	@if cmp -s test/$(1).out test/$(1).expected; then echo "PASS $(1)"; \
	else echo "FAIL $(1)"; diff test/$(1).expected test/$(1).out; exit 1; fi

endef

# The tests of nice.zig and nice.rs, test/X.zig and test/X.rs, as in
# libc/Makefile: each test/X.wasm is translated, joined with
# start_wasm.nasm, lib.nasm, and muldiv_mpu.nasm, and the float library,
# float_fpu.nasm, if it is in FLOAT_WASM_TESTS, and run with test/X.input,
# if there is one, as the console input. The console output, main's
# result in R1, and the exit status are compared with test/X.expected.
# The .wasm files are checked in, so make test needs no Zig or Rust; make
# wasm rebuilds them.
ZIG_TESTS = nicezig zigpoll zigheap zignoheap zigline zigfloat
RUST_TESTS = nicers rustpoll rustheap rustnoheap rustline rustfloat
FLOAT_WASM_TESTS = zigfloat rustfloat

# The options for nicewasm.py of a test, if any. zignoheap and rustnoheap
# get a memory that ends before their heap starts, at the end of their
# static data: the 4096 bytes of the stack, for Zig the 24 of the heap's
# Allocator and of its table of four functions, and the 12 of the heap's
# three words. __heap_base is the next multiple of 16. With fewer bytes
# the data does not fit, or the heap's use of its words traps (code 2).
WASM_OPTS_rustheap = --memory-pages 2
WASM_OPTS_zigheap = --memory-pages 2
WASM_OPTS_rustnoheap = --memory-bytes 4108
WASM_OPTS_zignoheap = --memory-bytes 4132

# Translates test/$(1).wasm with the options $(3), joins it with the
# float library if the test needs it, assembles it, and runs it, as
# the run $(2): test/$(2).out gets the console output, R1, and the exit
# status. One shell command, for check_wasm and its keep.
define run_wasm
$(PYTHON) ../translator/nicewasm.py $(3) -o test/$(2).out.nasm test/$(1).wasm && \
	  cat start_wasm.nasm test/$(2).out.nasm lib.nasm muldiv_mpu.nasm \
	    $(if $(filter $(1),$(FLOAT_WASM_TESTS)),float_fpu.nasm) > test/$(2).full.nasm && \
	  $(ASM) -o test/$(2).out.bin test/$(2).full.nasm && \
	  { $(EMU) $(if $(wildcard test/$(1).input),--input test/$(1).input) test/$(2).out.bin < /dev/null > test/$(2).raw; \
	    echo "exit $$?" > test/$(2).status; } && \
	  sed '/^\(Halted\|Stopped\)/,$$d' test/$(2).raw > test/$(2).out && \
	  { grep -o ' R1  [0-9a-f]*' test/$(2).raw | cut -c2- >> test/$(2).out; cat test/$(2).status >> test/$(2).out; }
endef

# A kept program may reserve less of its memory, as in libc/Makefile:
# unless the test has options of its own, it is translated again with
# --memory-bytes, with each size of KEEP_BYTES in turn, and the first
# whose output is the expected one is kept.
KEEP_BYTES = 8192 16384 32768

# $(1) is the test, and $(2) the name of the run.
define check_wasm
	@$(call run_wasm,$(1),$(2),$(WASM_OPTS_$(1)))
	@if cmp -s test/$(2).out test/$(1).expected; then echo "PASS $(2)"; \
	else echo "FAIL $(2)"; diff test/$(1).expected test/$(2).out; exit 1; fi
	$(call keep,test/$(2).out.bin,$(wildcard test/$(1).input),$(2))
	$(if $(KEEP),$(if $(WASM_OPTS_$(1)),,@for n in $(KEEP_BYTES); do \
	  if { $(call run_wasm,$(1),$(2)_keep,--memory-bytes $$n); } 2>/dev/null && \
	    cmp -s test/$(2)_keep.out test/$(1).expected; then cp test/$(2)_keep.out.bin $(KEEP)/$(2).bin; break; fi; \
	done))

endef

test: emulator
	$(foreach t,$(TESTS),$(call check,$(t),$(t),muldiv_mpu.nasm))
	$(foreach t,$(SOFT_TESTS),$(call check,$(t)_soft,$(t),muldiv_soft.nasm))
	$(foreach t,$(ZIG_TESTS) $(RUST_TESTS),$(call check_wasm,$(t),$(t)))
	@$(PYTHON) test/float_fpu.py
	@$(PYTHON) test/colors.py
	@rm -f test/*.out test/*.out.nasm test/*.out.bin test/*.full.nasm test/*.raw test/*.status
	@$(MAKE) --no-print-directory -C libc test

# Rebuilds the .wasm files of the Zig and Rust tests. This needs Zig 0.17
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
	@chmod -x test/*.wasm
	@rm -f test/*.wasm.o

emulator:
	$(MAKE) -C ../emulator build

# Needs mypy (pip install mypy).
typecheck:
	cd libc/test && $(PYTHON) -m mypy --strict fuzz_printf.py fuzz_strtod.py fuzz_math.py
	cd test && MYPYPATH=../../translator:../../translator/test:../../assembler:../../emulator/test $(PYTHON) -m mypy --strict float_fpu.py colors.py

clean:
	rm -f test/*.out test/*.out.nasm test/*.out.bin test/*.full.nasm test/*.raw test/*.status
	$(MAKE) -C libc clean

.PHONY: test emulator typecheck clean wasm
