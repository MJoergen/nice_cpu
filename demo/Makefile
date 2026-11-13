# Builds the demo, demo.nasm, into build/demo.bin, a program under a
# monitor at 0x8000 (runtime/ABI.md, "Programs under a monitor"), which a
# board joins behind its monitor in its ROM, and build/emu.bin, the same
# behind the runtime's stand-in for a monitor at 0, which niceemu runs.
#
# make          builds build/demo.bin and build/emu.bin, with VERSION in the
#               demo's title bar, git describe of the tree by default, and
#               the text of TEXT, text.nasm by default
# make window   runs build/emu.bin in niceemu --window (make -C ../emulator
#               window first)
# make test     runs the demo in niceemu once for each of the inputs below
#               and compares the screens with test.expected
# make clean    removes build/
#
# The assembler has no include, so the text, TEXT, and build/version.nasm,
# which defines the label VERSION, are joined to demo.nasm. A board gives
# its own text with TEXT=, and its tag with VERSION=. The stand-in,
# ../runtime/test/monitor_console.nasm, sets SP, calls the demo at 0x8000,
# and halts when it returns, with its status in R1.

PYTHON  ?= python3
ASM      = $(PYTHON) ../assembler/niceasm.py
ASM_PY   = $(wildcard ../assembler/*.py)
EMU      = ../emulator/zig-out/bin/niceemu
STANDIN  = ../runtime/test/monitor_console.nasm
BUILD    = build
VERSION ?= $(shell git describe --tags --always --dirty 2>/dev/null || echo unknown)
TEXT    ?= text.nasm

.PHONY: all window test clean FORCE

all: $(BUILD)/demo.bin $(BUILD)/emu.bin

$(EMU):
	$(MAKE) -C ../emulator build

$(BUILD)/demo.bin: demo.nasm $(TEXT) $(BUILD)/version.nasm $(ASM_PY)
	@cat demo.nasm $(TEXT) $(BUILD)/version.nasm > $(BUILD)/demo_all.nasm
	$(ASM) -o $@ $(BUILD)/demo_all.nasm

# The stand-in, assembled once, at 0
$(BUILD)/standin.bin: $(STANDIN) $(ASM_PY) | $(BUILD)
	@$(ASM) -o $@ $(STANDIN)

# A program behind the stand-in, as a monitor's image and a program's
# concatenate
$(BUILD)/emu.bin: $(BUILD)/standin.bin $(BUILD)/demo.bin
	@cat $^ > $@

$(BUILD)/emu_%.bin: $(BUILD)/standin.bin $(BUILD)/demo_%.bin
	@cat $^ > $@

# Written only when the version changes, so that the demo is not
# assembled again, and a bitstream with it not built again, for nothing.
$(BUILD)/version.nasm: FORCE | $(BUILD)
	@echo "VERSION .ASCII_L '$(VERSION)'" | cmp -s - $@ || \
	  echo "VERSION .ASCII_L '$(VERSION)'" > $@

window: $(BUILD)/emu.bin
	$(EMU) --window $(BUILD)/emu.bin

# The test has a version of its own, so that its screen does not change
# with every commit, and the default text.
$(BUILD)/demo_test.bin: demo.nasm text.nasm $(ASM_PY) | $(BUILD)
	@(cat demo.nasm text.nasm; echo "VERSION .ASCII_L 'V9.9'") > $(BUILD)/demo_test_all.nasm
	@$(ASM) -o $@ $(BUILD)/demo_test_all.nasm

# The same with a wrong word in the script of the math unit's test, the
# high word of -7 * 6, which the self-test then shows as failed. cmp fails
# the build if sed changed nothing.
$(BUILD)/demo_fail.bin: $(BUILD)/demo_test.bin
	@sed 's/^\( *\.DAT *2, M_SMULH, \)-1$$/\1-2/' $(BUILD)/demo_test_all.nasm \
	  > $(BUILD)/demo_fail_all.nasm
	@! cmp -s $(BUILD)/demo_test_all.nasm $(BUILD)/demo_fail_all.nasm
	@$(ASM) -o $@ $(BUILD)/demo_fail_all.nasm

# The first input edits: a DEL, a TAB, a CR LF, the cursor keys, a
# line longer than 80 characters, an ESC without [, a sequence with
# parameters, a byte of 0x80 to 0x9F, which is dropped, and one of
# ISO 8859-1, which niceemu shows as a blank. The second clears what it
# typed, deletes at the first column, and scrolls by three rows, the last
# with a TAB past the last column. The third has the function keys: the
# VT220's F1 and xterm's F1 start the typewriter afresh, F2, F8, and
# SHIFT-F6, which have no demo, do nothing, ESC ESC [ A is the cursor up,
# ESC Q is Q, and a sequence that is no key does nothing. The fourth
# starts the key codes with the VT220's F3, ESC [ 13 ~, and types a
# letter, CR, a control code, DEL, a cursor key, F10, which has no demo, a
# cursor key with parameters, a byte of ISO 8859-1 and one of 0x80 to
# 0x9F, an ESC and an x, which are one key, as niceemu has the x at once,
# a sequence longer than the 12 bytes shown, and nine letters: 20 keys,
# which scroll by four rows. The fifth goes from the key codes back to the
# typewriter, which shows no bytes. The sixth starts the characters and
# colors, F5, where letters and F2 do nothing. niceemu shows neither the
# colors nor the characters from 0xA0 on, so the test also has the words
# of two of its rows: the red backgrounds, row 5, and the gray
# foregrounds, row 20, from column 44. The seventh starts the counters,
# F7, where a letter runs the sieve again. niceemu counts each step as a
# cycle and a microsecond, so all the numbers are the same in every run.
# The eighth plays the comet, F9, which takes a key at each tick, so . is
# a tick without a key. The comet waits for the right key, catches the
# star at row 4, column 67, and turns right, down, and left into its tail.
# A key starts a new game, in which the comet goes left, ignores the right
# key, which would turn it back, and hits the frame. The ninth runs the
# board, F11, twice, so that the second run starts with what the first
# left. The tenth types an IP address after F11: letters and a dot that do
# not belong are dropped, the number 256 is rejected, and the message
# stays. The eleventh writes the IP address 192.168.1.65, with a letter
# dropped, a number with leading zeros, 0001, and two DELs over the last
# digits, then a MAC address with one-digit bytes, and cancels a second
# MAC address with CTRL-C. The twelfth is rejected for a MAC address of a
# group, with an odd first byte, and the thirteenth for a byte of three
# hex digits, though its value, 0FF, is in range. The fourteenth runs the
# board in build/demo_fail.bin, whose math unit's test fails, so it shows
# FAIL, the address read, and the word read there. The fifteenth types in
# the typewriter with a backspace, 0x08, and moves with the cursor keys of
# ESC O A to ESC O D, and the VT220's F2 and F4, which have no demo, do
# nothing. The sixteenth leaves the demo with F12, which clears the
# screen and returns 0 to the stand-in, which halts; the test keeps R1
# for it. niceemu has no Ethernet, so the station's counts stay 0, and
# without --link its status is 0, no port and no host (doc/DEVICES.md §6).
# dash's printf, the shell of make on Ubuntu, has no \x.
TEST1 = Hello, world!\nabc\177\177X\tY\r\n$(shell printf '0123456789%.0s' 1 2 3 4 5 6 7 8)abcde\n\
\033[A\033[A\033[DQ\033[C\033[BR\n\033x\033[1;5Cy\200\351z\n
TEST3 = one\033[11~two\n\033OPthree\033OQ\033[19~\033[17;2~ F\n\033\033[Ax\033Q\033[99~
TEST4 = \033[13~a\r\003\177\033[A\033[21~\033[1;5C\351\200\033x\033[1;2;3;4;5;6;7;8~bcdefghij
TEST5 = \033ORab\033OPback
TEST6 = \033[15~abc\033OQ
DUMP6 = -d 0xFFFF01BC:36 -d 0xFFFF066C:36
TEST7 = \033[18~x
dots  = $(shell printf '.%.0s' $$(seq $(1)))
TEST8 = \033[20~.\033[C$(call dots,27)\033[A$(call dots,8)\033[C\033[B\033[D.\033[D..\033[C$(call dots,35)

TEST9  = \033[23~\033[23~
TEST10 = \033[23~iX10.0g.0.256\r
TEST11 = \033[23~i192.1x68.0001.66\177\17765\rm02:AB:c:D:e:F\rm02:\003
TEST12 = \033[23~m03:00:00:00:00:01\r
TEST13 = \033[23~m0FF:2:3:4:5:6\r
TEST14 = \033[23~
TEST15 = ab\010c\nwxyz\033OD\033OD\033OA1\033OC\033OB2\033[12~!\033[14~?
TEST16 = abc\033[24~more
TESTS  = 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16
# For the colors, which niceemu does not show, the ninth has the words of
# the menu, with F11 in black on white, of the four PASS in green, and of
# the line after them, and the fourteenth those of the FAIL in red, with
# its words in white, and of the line after it
DUMP9  = -d 0xFFFF0050:80 -d 0xFFFF01C2:4 -d 0xFFFF0212:4 -d 0xFFFF0262:4 \
	 -d 0xFFFF02B2:4 -d 0xFFFF0322:17
DUMP14 = -d 0xFFFF0212:22 -d 0xFFFF0322:14

test: $(BUILD)/emu_test.bin $(BUILD)/emu_fail.bin $(EMU)
	@printf '$(TEST1)' > $(BUILD)/test1.txt
	@{ printf 'junk\014\177'; for i in $$(seq 16); do printf 'line %d\n' $$i; done; \
	  printf 'first\tA\t\t\t\t\t\t\t\t\t\tB'; } > $(BUILD)/test2.txt
	@for t in 3 4 5 6 7 8 9 10 11 12 13 14 15 16; do \
	  case $$t in \
	    3) printf '$(TEST3)';; 4) printf '$(TEST4)';; 5) printf '$(TEST5)';; \
	    6) printf '$(TEST6)';; 7) printf '$(TEST7)';; 8) printf '$(TEST8)';; \
	    9) printf '$(TEST9)';; 10) printf '$(TEST10)';; 11) printf '$(TEST11)';; \
	    12) printf '$(TEST12)';; 13) printf '$(TEST13)';; 14) printf '$(TEST14)';; \
	    15) printf '$(TEST15)';; 16) printf '$(TEST16)';; \
	  esac > $(BUILD)/test$$t.txt; \
	done
	@for t in $(TESTS); do \
	  case $$t in 6) dump='$(DUMP6)';; 9) dump='$(DUMP9)';; \
	    14) dump='$(DUMP14)';; *) dump=;; esac; \
	  bin=emu_test; [ $$t = 14 ] && bin=emu_fail; \
	  $(EMU) -s --step-time -i $(BUILD)/test$$t.txt $$dump $(BUILD)/$$bin.bin > $(BUILD)/test$$t.out || \
	    { echo "FAIL demo: niceemu exits with $$? on input $$t"; exit 1; }; \
	  [ $$t = 16 ] && grep -o '^R0 .* R1  [0-9a-f]*' $(BUILD)/test$$t.out; \
	  sed -n -e '/^ffff/p' -e '/^Screen:/,$$p' $(BUILD)/test$$t.out; \
	done > $(BUILD)/test.screen; \
	if cmp -s test.expected $(BUILD)/test.screen; then echo "PASS demo"; \
	else echo "FAIL demo"; diff test.expected $(BUILD)/test.screen; exit 1; fi

$(BUILD):
	@mkdir -p $@

clean:
	rm -rf $(BUILD)
