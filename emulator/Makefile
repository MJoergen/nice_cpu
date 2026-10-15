ZIG ?= zig
PYTHON ?= python3
EMU = zig-out/bin/niceemu
ASM = ../assembler/test

# Each program is run with its options, and its output and exit status are
# compared with test/X.expected. Stdin is /dev/null, so a program that reads
# the console finds the input ended.
#
# The 2004 example programs, from the assembler's tests. Their .expected
# files were checked by hand, not just copied from the emulator: count
# takes 3 + 3*4096 + 1 = 12292 steps and leaves R1 = 4096*4097/2, and the
# dump of replicate equals program words 0-9. wrap checks that a word at
# 0xFFFFFFFF loads.
EXAMPLES = count replicate print wrap
OPTS_count     =
OPTS_replicate = -d 0x10:10
OPTS_print     = -2004 -s
OPTS_wrap      = -d 0xffffffff:1

# Probes of single rules of doc/ISA.md, in test/X.nasm. The expected values
# are in the comments of each program. Run make bins after changing one.
PROBES = logic dest carry r15 cond rotate vbase selfmod addr irq merge after start cputest console screen iofetch \
  reads reserved mpu mpu64 perf input
OPTS_dest    = -d 0x200:1 -d 0x211:1 -d 0x221:1
OPTS_selfmod = -d 4:1
OPTS_addr    = -d 0:1 -d 0x1fffff:1
OPTS_irq     = -t --nmi 2:1 --irq 2:2 --nmi 9:1 --irq 17:2 --nmi 17:1 --irq 100:2 -d 0x200:12
OPTS_merge   = --nmi 1:1 --nmi 1:2 --irq 1:3 --irq 4:4 --irq 7:5
OPTS_after   = --nmi 3:1 --nmi 10:1 -d 0x200:6
OPTS_start   = -t --nmi 0:3
OPTS_screen  = -s
OPTS_iofetch = -d 0xffffff80:1 -d 0xffffffff:1
OPTS_reads   = -d 0xffffff01:1
OPTS_mpu     = -d 0x200:72 -d 0xffffff20:16
OPTS_mpu64   = -d 0x200:72 -d 0xffffff20:32
OPTS_perf    = --nmi 3:0x41 -d 0xffffff10:5
OPTS_input   = --input test/input.txt

define check
	@$(EMU) $(OPTS_$(1)) $(2) < /dev/null > test/$(1).out; echo "exit $$?" >> test/$(1).out
	@if cmp -s test/$(1).out test/$(1).expected; then echo "PASS $(1)"; \
	else echo "FAIL $(1)"; diff test/$(1).expected test/$(1).out; exit 1; fi

endef

# The unit tests run in Debug, for its safety checks; niceemu itself is
# built ReleaseSafe, which keeps the checks but runs much faster.
test: build
	$(ZIG) build test --summary all
	$(foreach t,$(EXAMPLES),$(call check,$(t),$(ASM)/$(t).bin))
	$(foreach t,$(PROBES),$(call check,$(t),test/$(t).bin))
	@rm -f test/*.out
	@$(PYTHON) test/errors.py

build:
	$(ZIG) build -Doptimize=ReleaseSafe

# Reassemble the probes with niceasm.
bins:
	@for t in $(PROBES); do $(PYTHON) ../assembler/niceasm.py test/$$t.nasm || exit 1; done

clean:
	rm -rf zig-out .zig-cache test/*.out

.PHONY: test build bins clean
