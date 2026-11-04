ZIG ?= zig
PYTHON ?= python3
EMU = zig-out/bin/niceemu
ASM = ../assembler/test

# Each program is run with its options, and its output and exit status are
# compared with test/X.expected, or with the file a third argument of check
# names. Stdin is /dev/null, so a program that reads
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
PROBES = logic dest carry r15 cond rotate vbase selfmod addr irq merge irqtimer after start cputest console screen screencolor screeninvert iofetch \
  reads reserved mpu mpu64 perf timer input r15modes r0dest r14mem skipconst carryin shiftc \
  wrapmem smcown scrbound time trapsym sd font
OPTS_dest    = -d 0x200:1 -d 0x211:1 -d 0x221:1
OPTS_selfmod = -d 4:1
OPTS_addr    = -d 0:1 -d 0x1fffff:1
OPTS_irq     = -t --nmi 2:1 --irq 2:2 --nmi 9:1 --irq 17:2 --nmi 17:1 --irq 100:2 -d 0x200:12
OPTS_merge   = --nmi 1:1 --nmi 1:2 --irq 1:3 --irq 4:4 --irq 7:5
OPTS_irqtimer = --irq 5:0x42
OPTS_after   = --nmi 3:1 --nmi 10:1 -d 0x200:6
OPTS_start   = -t --nmi 0:3
OPTS_screen  = -s
OPTS_screencolor = --color
OPTS_screeninvert = --invert-fg
OPTS_iofetch = -d 0xffffff80:1 -d 0xffffffff:1
OPTS_reads   = -d 0xffffff01:1
OPTS_mpu     = -d 0x200:72 -d 0xffffff20:16
OPTS_mpu64   = -d 0x200:72 -d 0xffffff20:32
OPTS_perf    = --step-time --nmi 3:0x41 -d 0xffffff40:6
OPTS_timer   = -d 0xffffff10:4
OPTS_time    = --step-time -d 0xffffff44:2
OPTS_trapsym = --symbols test/trapsym.sym
# timer again, with the timer's requests raised by --irq instead, before
# the steps after those that raise them in timer.nasm's table: 6, 16, 19,
# 22, 25, 28, 31, 34, 41, and 49, the last with vector 0x42. The output
# must equal timer.expected.
OPTS_timer_noirq = --no-timer-irq --irq 7:0x41 --irq 17:0x41 --irq 20:0x41 --irq 23:0x41 \
  --irq 26:0x41 --irq 29:0x41 --irq 32:0x41 --irq 35:0x41 --irq 42:0x41 --irq 50:0x42 \
  -d 0xffffff10:4
OPTS_input   = --input test/input.txt
OPTS_r15modes = -d 6:1 -d 0xa:1
OPTS_r0dest  = -d 0:2
OPTS_r14mem  = -d 0x01000010:2 -d 0x01ffffff:1
OPTS_carryin = -d 0x200:16
OPTS_shiftc  = -d 0x200:28
OPTS_wrapmem = -d 0xffffff01:1 -d 0xffffffff:1
OPTS_smcown  = -d 5:1
OPTS_scrbound = -s
# scrbound again, with the screen at 0x400.
OPTS_scrbound2004 = -2004 -s
# A fresh image for each run, as the probe writes it: byte o is o mod 251.
OPTS_sd      = --sd0 test/sd.img.out -d 0x200:32 -d 0xffffffa0:16
OPTS_font    = -d 0xfffe0820:32 -d 0xfffe0020:1 -d 0xfffe2826:1 -d 0xffffff86:1

define check
	@$(EMU) $(OPTS_$(1)) $(2) < /dev/null > test/$(1).out; echo "exit $$?" >> test/$(1).out
	@if cmp -s test/$(1).out test/$(or $(3),$(1)).expected; then echo "PASS $(1)"; \
	else echo "FAIL $(1)"; diff test/$(or $(3),$(1)).expected test/$(1).out; exit 1; fi

endef

# The unit tests run in Debug, for its safety checks; niceemu itself is
# built ReleaseSafe, which keeps the checks but runs much faster.
test: build bincheck
	$(ZIG) build test --summary all
	@$(MAKE) --no-print-directory programs
	@NICEEMU=$(abspath $(EMU)) $(PYTHON) test/errors.py

# The example and probe programs, and the debug link, on the niceemu of
# EMU. errors.py is apart, as it expects a build without the window.
programs:
	$(foreach t,$(EXAMPLES),$(call check,$(t),$(ASM)/$(t).bin))
	@$(PYTHON) -c 'import sys; sys.stdout.buffer.write(bytes(o % 251 for o in range(1024)))' > test/sd.img.out
	$(foreach t,$(PROBES),$(call check,$(t),test/$(t).bin))
	$(call check,timer_noirq,test/timer.bin,timer)
	$(call check,scrbound2004,test/scrbound.bin)
	@rm -f test/*.out
	@NICEEMU=$(abspath $(EMU)) $(PYTHON) test/link.py

build:
	$(ZIG) build -Doptimize=ReleaseSafe

# The same with the window of --window. The first build fetches SDL and
# compiles it from source; later ones take it from the Zig cache.
window:
	$(ZIG) build -Doptimize=ReleaseSafe -Dwindow

# The window's tests: the unit tests of window.zig, in ReleaseSafe, which
# shares the SDL of the window build, and test/window.py on SDL's dummy
# video driver, so with no display.
window-test: window
	$(ZIG) build test -Doptimize=ReleaseSafe -Dwindow --summary all
	@$(PYTHON) test/window.py

# The release files of README.md, Download: niceemu for x86_64 Linux,
# without the window (static, musl) and with it (glibc 2.31 or later, as
# SDL loads X11 or Wayland at run time), each packed with the README, the
# license, and, with the window, the licenses of SDL. A named target
# builds for the baseline x86_64 CPU, not the CPU of this machine. Each
# build runs the tests of make test, the window one those of window-test
# instead of errors.py. TAG is V and the first two numbers of the version
# in build.zig.zon.
VERSION := $(shell sed -n 's/^ *\.version = "\(.*\)",$$/\1/p' build.zig.zon)
TAG ?= V$(word 1,$(subst ., ,$(VERSION))).$(word 2,$(subst ., ,$(VERSION)))
DIST = dist
PLAIN = niceemu-$(TAG)-x86_64-linux
WINDOW = niceemu-window-$(TAG)-x86_64-linux

dist: bincheck
	rm -rf $(DIST)
	$(ZIG) build -Doptimize=ReleaseSafe -Dtarget=x86_64-linux-musl -p $(DIST)/$(PLAIN)
	$(ZIG) build -Doptimize=ReleaseSafe -Dtarget=x86_64-linux-gnu.2.31 -Dwindow -p $(DIST)/$(WINDOW)
	@$(MAKE) --no-print-directory programs EMU=$(DIST)/$(PLAIN)/bin/niceemu
	@NICEEMU=$(abspath $(DIST)/$(PLAIN)/bin/niceemu) $(PYTHON) test/errors.py
	@$(MAKE) --no-print-directory programs EMU=$(DIST)/$(WINDOW)/bin/niceemu
	@NICEEMU=$(abspath $(DIST)/$(WINDOW)/bin/niceemu) $(PYTHON) test/window.py
	for d in $(PLAIN) $(WINDOW); do \
	  mv $(DIST)/$$d/bin/niceemu $(DIST)/$$d/ && rmdir $(DIST)/$$d/bin && \
	  cp README.md ../LICENSE $(DIST)/$$d/ || exit 1; \
	done
	for p in zig-pkg/sdl-* zig-pkg/sdl_linux_deps-*; do \
	  n=$$(basename $$p | cut -d- -f1); mkdir -p $(DIST)/$(WINDOW)/licenses/$$n && \
	  cp -r $$p/LICENSE.txt $$p/LICENSES $$p/REUSE.toml $(DIST)/$(WINDOW)/licenses/$$n/ || exit 1; \
	done
	cd $(DIST) && for d in $(PLAIN) $(WINDOW); do \
	  tar --owner=0 --group=0 -czf $$d.tar.gz $$d || exit 1; done && \
	  sha256sum $(PLAIN).tar.gz $(WINDOW).tar.gz > SHA256SUMS
	@cat $(DIST)/SHA256SUMS

# Reassemble the probes with niceasm.
bins:
	@for t in $(PROBES); do $(PYTHON) ../assembler/niceasm.py test/$$t.nasm || exit 1; done

# Fail if a probe's .bin differs from what niceasm makes of its .nasm.
bincheck:
	@d=$$(mktemp -d); trap 'rm -rf $$d' EXIT; \
	for t in $(PROBES); do \
	  $(PYTHON) ../assembler/niceasm.py -o $$d/$$t.bin test/$$t.nasm || exit 1; \
	  cmp -s $$d/$$t.bin test/$$t.bin || { echo "STALE test/$$t.bin: run make bins"; exit 1; }; \
	done; echo "PASS bincheck"

# Needs mypy (pip install mypy).
typecheck:
	$(PYTHON) -m mypy --strict test/errors.py test/link.py test/window.py font/gen_font.py

clean:
	rm -rf zig-out .zig-cache zig-pkg dist test/*.out

.PHONY: test programs dist build window window-test bins bincheck typecheck clean
