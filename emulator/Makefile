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
PROBES = logic dest carry r15 cond rotate selfmod addr cputest console screen screencolor screeninvert iofetch \
  reads reserved mpu mpu64 mpubits perf events input r15modes r0dest r14mem skipconst carryin shiftc \
  wrapmem smcown scrbound time trapsym sd font net eth bytewin skip clock clockhost stack \
  fpu fpustack fpudec fpufunc chunky
OPTS_dest    = -d 0x200:1 -d 0x211:1 -d 0x221:1
OPTS_selfmod = -d 4:1
OPTS_addr    = -d 0:1 -d 0x1fffff:1
OPTS_screen  = -s
OPTS_screencolor = --color
OPTS_screeninvert = --invert-fg
OPTS_iofetch = -d 0xffffff80:1 -d 0xffffffff:1
OPTS_reads   = -d 0xffffff01:1
OPTS_mpu     = -d 0x200:72 -d 0xffffff20:16
OPTS_mpu64   = -d 0x200:72 -d 0xffffff20:32
OPTS_mpubits = -d 0x200:64
OPTS_perf    = --step-time -d 0xffffff40:6
OPTS_events  = -d 0xffffff4a:10
OPTS_time    = --step-time -d 0xffffff44:2
OPTS_clock   = --step-time -d 0x100:17 -d 0xffffff46:4
# clock again, with its words ordinary memory: each read returns the last
# value written there, or 0.
OPTS_clock_mem = --step-time --no-cycle-counter -d 0x100:17 -d 0xffffff46:4
OPTS_skip     = --step-time -d 0x200:6 -d 0x210:2
# skip again: without --step-time, where the write is ignored; cut short
# by the step limit in its first skip; and with the counters' words
# memory, where TIME_SKIP stays a device.
OPTS_skip_off   = --max-steps 4 -d 0x200:3
OPTS_skip_limit = --step-time --max-steps 50 -d 0x200:3
OPTS_skip_mem   = --step-time --no-cycle-counter
OPTS_trapsym = --symbols test/trapsym.sym
OPTS_stack   = --stack
# The count example with --stack: it never changes R13, and its output is
# count.expected with the line that says so.
OPTS_stack_none = --stack
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
OPTS_net     = -d 0x200:17 -d 0xffffffb0:16
# The frames sent go to test/eth.frames.out, checked after the probes.
OPTS_eth     = --eth-in test/eth.in --eth-out test/eth.frames.out -d 0x200:33 -d 0xffffffc0:16
OPTS_font    = -d 0xfffe0820:32 -d 0xfffe0020:1 -d 0xfffe2826:1 -d 0xffffff86:1 \
               -d 0xfffe3000:32 -d 0xfffe32e0:32 -d 0xfffe3340:1
OPTS_chunky  = --color -d 0xffffff87:1
# chunky again, with --screen, which prints only the size of the mode.
OPTS_chunky_screen = -s
# And with -2004, whose screen keeps the 100 rows of pixels that cover
# its 25 rows of text.
OPTS_chunky_screen2004 = -2004 -s
OPTS_fpu     = --step-time -d 0x200:24 -d 0xffffff88:8
# fpu again, with the FPU's words ordinary memory: each read returns the
# last value written there, or 0.
OPTS_fpu_mem = --step-time --no-fpu -d 0x200:24 -d 0xffffff88:8
OPTS_fpustack = -d 0x200:18 -d 0xffffff88:8
OPTS_fpufunc = -d 0x200:22
OPTS_bytewin = -d 0x202:3 -d 0x03ffffff:1 -d 0x60000000:1 -d 0x20000809:1 -d 0x5000080e:1

define check
	@$(EMU) $(OPTS_$(1)) $(2) < /dev/null > test/$(1).out; echo "exit $$?" >> test/$(1).out
	@if cmp -s test/$(1).out test/$(or $(3),$(1)).expected; then echo "PASS $(1)"; \
	else echo "FAIL $(1)"; diff test/$(or $(3),$(1)).expected test/$(1).out; exit 1; fi

endef

# The unit tests run in Debug, for its safety checks; niceemu itself is
# built ReleaseSafe, which keeps the checks but runs much faster. The
# FPU's unit test replays the vectors of its model, test/fpu_vectors.py,
# which also checks their coverage, once for this machine's CPU and once
# for the baseline x86_64 CPU of make dist, which has no FMA instruction,
# so that the software floating point of Zig's library is tested too.
# Zig keeps the result of a run of the unit tests, and runs them again
# only when an input changed, so build.zig names the vectors as one.
# The last run checks that: the file gets a line that is wrong, a read
# of FPU_X_LO that gives 1 for the model's 0, and the unit test must fail.
test: build bincheck fmtcheck seqcheck
	@$(PYTHON) test/fpu_vectors.py -o test/fpu.vectors.out
	$(ZIG) build test -Dfpu-vectors=$(abspath test/fpu.vectors.out) --summary all
	$(ZIG) build test -Dcpu=baseline -Dfpu-vectors=$(abspath test/fpu.vectors.out) --summary all
	@echo "0 02 3FF0000000000000 0000000000000000 : R 0 00000001 : 0 02 3FF0000000000000 0000000000000000" \
	  >> test/fpu.vectors.out
	@if $(ZIG) build test -Dfpu-vectors=$(abspath test/fpu.vectors.out) > test/fpu.wrong.out 2>&1; \
	  then echo "FAIL the unit test passes with a wrong vector: it did not read the file"; exit 1; \
	  elif grep -Eq '(^| )1 of [0-9]+ vectors failed' test/fpu.wrong.out; \
	  then echo "PASS a wrong vector fails the unit test"; \
	  else echo "FAIL the unit test with a wrong vector:"; cat test/fpu.wrong.out; exit 1; fi
	@$(MAKE) --no-print-directory programs
	@NICEEMU=$(abspath $(EMU)) $(PYTHON) test/errors.py
	@$(PYTHON) test/fpu_model_test.py

# The FPU's vectors with a long random sequence, from the seed SEED,
# replayed by the unit test in ReleaseSafe. A failing run leaves the
# vectors in test/fpu.long.out.
SEED ?= 1
COUNT ?= 1000000
fpu-long:
	$(PYTHON) test/fpu_vectors.py --seed $(SEED) --count $(COUNT) -o test/fpu.long.out
	$(ZIG) build test -Doptimize=ReleaseSafe -Dfpu-vectors=$(abspath test/fpu.long.out) --summary all
	rm -f test/fpu.long.out

# The example and probe programs, and the debug link, on the niceemu of
# EMU. errors.py is apart, as it expects a build without the window.
programs:
	$(foreach t,$(EXAMPLES),$(call check,$(t),$(ASM)/$(t).bin))
	@$(PYTHON) -c 'import sys; sys.stdout.buffer.write(bytes(o % 251 for o in range(1024)))' > test/sd.img.out
	$(foreach t,$(PROBES),$(call check,$(t),test/$(t).bin))
	$(call check,scrbound2004,test/scrbound.bin)
	$(call check,clock_mem,test/clock.bin)
	$(call check,fpu_mem,test/fpu.bin)
	$(call check,skip_off,test/skip.bin)
	$(call check,skip_limit,test/skip.bin)
	$(call check,skip_mem,test/skip.bin)
	$(call check,stack_none,$(ASM)/count.bin)
	$(call check,chunky_screen,test/chunky.bin)
	$(call check,chunky_screen2004,test/chunky.bin)
	@if cmp -s test/eth.frames.out test/eth.frames.expected; then echo "PASS eth frames"; \
	else echo "FAIL eth frames"; diff test/eth.frames.expected test/eth.frames.out; exit 1; fi
	@rm -f test/*.out
	@NICEEMU=$(abspath $(EMU)) $(PYTHON) test/link.py
	@NICEEMU=$(abspath $(EMU)) $(PYTHON) test/udp.py
	@NICEEMU=$(abspath $(EMU)) $(PYTHON) test/tap.py

build:
	$(ZIG) build -Doptimize=ReleaseSafe

# Fail if a Zig source is not as zig fmt lays it out; zig fmt fixes it.
fmtcheck:
	$(ZIG) fmt --check build.zig src

# The same with the window of --window. The first build fetches SDL and
# compiles it from source; later ones take it from the Zig cache.
window:
	$(ZIG) build -Doptimize=ReleaseSafe -Dwindow

# The window's tests: the unit tests of window.zig, in ReleaseSafe, which
# shares the SDL of the window build, and test/window.py on SDL's dummy
# video driver, so with no display. The unit tests run with DISPLAY and
# WAYLAND_DISPLAY unset, so that one that needs a display fails here as
# it does in CI, where there is none.
window-test: window
	env -u DISPLAY -u WAYLAND_DISPLAY $(ZIG) build test -Doptimize=ReleaseSafe -Dwindow --summary all
	@$(PYTHON) test/window.py

# The release files of README.md, Download: niceemu for x86_64 Linux,
# without the window (static, musl) and with it (glibc 2.31 or later, as
# SDL loads X11 or Wayland at run time), each packed with the README, the
# license, and, with the window, the licenses of SDL. A named target
# builds for the baseline x86_64 CPU, not the CPU of this machine. The
# FPU's vectors are replayed on the target and the optimization of the
# first, and each build runs the programs of make test, and errors.py or,
# with the window, window.py. TAG is V and the first two numbers of the version
# in build.zig.zon.
VERSION := $(shell sed -n 's/^ *\.version = "\(.*\)",$$/\1/p' build.zig.zon)
TAG ?= V$(word 1,$(subst ., ,$(VERSION))).$(word 2,$(subst ., ,$(VERSION)))
DIST = dist
PLAIN = niceemu-$(TAG)-x86_64-linux
WINDOW = niceemu-window-$(TAG)-x86_64-linux

dist: bincheck
	rm -rf $(DIST)
	@$(PYTHON) test/fpu_vectors.py -o test/fpu.vectors.out
	$(ZIG) build test -Doptimize=ReleaseSafe -Dtarget=x86_64-linux-musl -Dfpu-vectors=$(abspath test/fpu.vectors.out) --summary all
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

# Fail if src/fpu_seq.zig is not what test/fpu_seq.py writes from the
# sequences of the FPU's functions.
seqcheck:
	@$(PYTHON) test/fpu_seq.py --zig | cmp -s - src/fpu_seq.zig \
	  || { echo "STALE src/fpu_seq.zig: run $(PYTHON) test/fpu_seq.py --zig > src/fpu_seq.zig"; exit 1; }; \
	echo "PASS seqcheck"

# Needs mypy (pip install mypy).
typecheck:
	$(PYTHON) -m mypy --strict test/errors.py test/link.py test/udp.py test/tap.py test/window.py test/fpu_model.py test/fpu_model_test.py test/fpu_vectors.py test/fpu_seq.py \
	  tools/nicetap.py font/gen_font.py

clean:
	rm -rf zig-out .zig-cache zig-pkg dist test/*.out

.PHONY: test fpu-long programs dist build window window-test bins bincheck seqcheck fmtcheck typecheck clean
