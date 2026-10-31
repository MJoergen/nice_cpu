# Eighth review of the repository, at commit 8d30320

Reviewed on 2026-10-31: the user documentation on `dev-V1.2` at commit 8d30320 ("doc: note the first window build fetches SDL"), before the release `V1.2`. The seventh review looked at the commits between `V1.0` and `V1.1`. This one asked three questions of each document a user reads: whether the essential features are presented, whether the text and the figures are organized so that a first-time reader can follow them, and whether a term is used before it is introduced. Correctness was checked only where a finding touched it.

**How it was checked.** I read README.md, doc/README.md, ISA.md, SYSTEM.md, TOOLCHAIN.md, CONTRIBUTING.md, REFERENCES.md, the source of the slides, and the `V1.2` section of RELEASE_NOTES.md myself. Three readers worked in parallel on the rest and changed nothing: one for hdl/README.md, DEBUG.md, MICROARCH.md, and the folder READMEs of `hdl/`; one for translator/README.md, WASM.md, runtime/README.md, and ABI.md; one for emulator/README.md, assembler/README.md, bench/README.md, release/README.md, and the release notes. Each spot-checked the options, targets, files, and addresses its documents name against the code and the `--help` outputs. I reproduced every finding below that names a line, and dropped the ones I could not (one named generics that the core does not have). `make -C doc test`, `make -C doc/intro pdfcheck`, and `make -C doc/intro test` pass on the unchanged tree.

## Summary

**Nothing in the documents blocks the tag.** Every option, target, file, and address the readers spot-checked exists and is described as the code has it, the links and section references check, and the slides match their PDF. The documents are accurate, and the short ones (ISA.md, TOOLCHAIN.md, doc/README.md, CONTRIBUTING.md, the folder READMEs of `hdl/`) read well. What the longer ones are less good at is being read for the first time, and the three questions found the same shape of problem in most of them:

- **Terms before their definition.** The README names MICROARCH.md before it says what it is (§2.1); ISA.md uses "the M bit" a section before it defines it (§3.1); SYSTEM.md's device tables say "a data read" without saying why (§3.5); TOOLCHAIN.md speaks of "a monitor in ROM" and `_mon` files that only ABI.md explains (§3.6); emulator/README.md's test narrative uses the link's registers before the link is introduced (§5.1); hdl/README.md uses the stage names, `wb_dmux`, `G_FORMAL`, and "the side port" long before their sections (§8.3); DEBUG.md uses "ISA §" and the version numbers before it declares them (§8.4).
- **Essential features missing or hard to find.** SYSTEM.md never states the screen's layout, 80 words per row (§3.3); the console's read rules read as a contradiction (§3.2); the slides have no slide for the window, though its example program is theirs (§4.3); translator/README.md has no quick start and no word on how a program prints, reads, and exits (§6.2); emulator/README.md has no recipe and no link to the README's worked examples (§5.2); hdl/README.md has no table of the core's ports and generics, and never names the clock (§8.2); DEBUG.md never says how to try the link (§8.4).
- **Organization.** Three READMEs put their tests before their usage (emulator, assembler, hdl: §5.1, §5.5, §8.1); translator/README.md is a user guide with a 455-line design note in the middle (§6.3); SYSTEM.md §1 holds seven topics under one heading (§3.4); DEBUG.md §7 holds three (§8.4); and one paragraph each in emulator/README.md, runtime/README.md, and bench/README.md tries to carry a whole table's worth of facts (§5.3, §6.4, §7.1).

**Two statements are wrong**, and should change before the tag: WASM.md says the translator accepts up to four results where it accepts one (§6.1), and runtime/README.md says NiceMonMEGA65's monitor exists where ABI.md and the board's README say it will (§6.5). **One release step is missing**: the table of board tags at the top of RELEASE_NOTES.md has no `V1.2` row, and no step of RELEASE.md adds one (§1.1).

**Twelve small fixes are worth making before the tag**, each a sentence or a few lines: §1.1, §2.1, §2.2, §3.1, §3.3, §3.5, §3.6, §4.1, §4.2, §5.3, §6.1, §6.5, and the two stale sentences of §8.3. The restructurings (§3.4, §5.1, §5.5, §6.2, §6.3, §6.4, §7.1, §8.1, §8.2, §8.4) are issues for after the tag, labeled `documentation`, unless the release waits for them. §9 lists what is good in each document, so that a restructuring keeps it.

## 1. The release

### 1.1 The table of board tags has no row for `V1.2`, and no step adds one

[RELEASE_NOTES.md](../../RELEASE_NOTES.md) opens with the table "Its tag that pins each is", which ends at `V1.1`, and the `V1.2` section sits below it. A reader at the tag cannot tell whether a `V1.2` board tag exists. RELEASE.md step 2.8 names the version table of DEBUG.md and the Zig version, but not this table, which the seventh review's §1.1 did not cover either. **Fix:** a `V1.2 | none yet` row when the section is finished, changed when NiceMonMEGA65 follows, and the row on the checklist in step 2.8 next to the DEBUG.md table. The date of the section is set at the tag, as the notes of `V1.1` were.

**Resolved**: RELEASE_NOTES.md has the row `V1.2 | none yet`. RELEASE.md's step 2.8 adds the row before `release.py check`, and step 8.4 fills it in when NiceMonMEGA65 follows.

### 1.2 The upgrade notes mix what a user must change with what is optional

The "Upgrade notes" of `V1.2` hold, in this order: `_exit` and the new labels (a hand-joined program must change), `nice_putc` and the rebuilt `.wasm` files (a C program must rebuild), the end of the input (a behavior change), the window (optional), the keys and the cursor (a specification), the link's side port (board authors), and "Zig 0.17.0, as in V1.1" (nothing to do). The opening paragraph does not say that a user who runs programs on the emulator with the runtime's start-up files needs to change nothing, and the pace of one step per microsecond, which changes how fast a program runs, is under "Emulator" only. **Fix:** order the list by who must act: what breaks, then what behaves differently (the input's end, R1–R6 and the flags, the trap report's R9, the pace with `--window`), then what is new and optional (the window, `--link ADDR:PORT`), then the board authors' items; and one sentence at the top for the user who needs to do nothing. The grouping by component below the notes is right.

**Resolved**: The upgrade notes open with the user who needs to do nothing, and run in the order of who must act: what breaks, what behaves differently, with the pace of `--window` among it, what is new and optional, and the two items for a board.

## 2. README.md

### 2.1 MICROARCH.md is named before it is introduced

Line 22: "the pipelined one of MICROARCH.md, which is the default". The reader meets the file name with no word on what it is, and learns it from the Contents table at line 241, "the design note for the pipelined core". **Fix:** "the pipelined one, whose design note is doc/MICROARCH.md, which is the default".

**Resolved**: The README says what MICROARCH.md is, with a link, at its first mention.

### 2.2 One sentence lists what the cores pass, and reads as a list of four things

Lines 23–27: "They both pass every comparison with the emulator, the test setup for them, and formal checks of their ports, of five stages of the pipeline, of the devices, and of the shifter and the ALU for every input." The aside "the test setup for them" reads as the second item of the list. **Fix:** two sentences: "Both are tested by comparing their traces with the emulator's, instruction by instruction, and both pass. Formal checks cover their ports, five stages of the pipeline, the devices, and the shifter and the ALU for every input."

**Resolved**: Two sentences: the comparison with the emulator, then the formal checks.

### 2.3 Where to start is a subsection of "The emulator"

The order is The emulator (its features, Building the emulator, Worked example, Worked example with the window), Toolchain, The specification, Contents, License. Read from the top, it works, and the two worked examples are the best part of the file. Scanned by its headings, how to begin is a subsection of a feature list, and the examples use the assembler (line 111) before Toolchain introduces it (207). The order is deliberate (9cda48d, "Quick start under The emulator"). **Fix:** a small one: head the three subsections "Getting started" and keep "The emulator" for the feature list, or leave the order and add "with the assembler, `niceasm`," at line 111. Not more.

**Resolved**: A heading "Getting started" holds Building the emulator and the two worked examples, and the first example names the assembler.

## 3. ISA.md, SYSTEM.md, and TOOLCHAIN.md

### 3.1 ISA.md: "the M bit" a section before its definition

[ISA.md](../ISA.md) §1.3, line 95: "Instructions with the M bit set update only X, C, Z, N, and V (§6)." The bit is defined in §2.1 and the term is fixed in §3 ("the M bit always means instruction bit 25"). **Fix:** "Instructions with the M bit (instruction bit 25, §2.1) set update only X, C, Z, N, and V (§6)." Nothing else: ISA.md is the best-organized document in the repository, with a contents list, a forward reference at nearly every term, and a worked example.

**Resolved**: §1.3 says what the M bit is, with a pointer to §2.1, at its first use.

### 3.2 SYSTEM.md §1: the console's read rules contradict each other on first reading

[SYSTEM.md](../SYSTEM.md) §1, "Console", line 46, four sentences apart: "With no byte waiting, a read returns 0." and "The emulator and the simulation memory of the FPGA core never return 0: a read waits for the next byte or the end of the input." Both are true, as the emulator without a window has no state in which no byte waits, but the reader has to work that out, and the sentence that says what the console is for, "Programs use the console for input and output", is the paragraph's last. The console is the one device every program uses. **Fix:** lead with what it is for; then the write; then the read as three cases in a table: a byte waits (the byte in bits 7..0 with bit 8 set), none waits (0 from a UART or the window; stdin, a file, and the simulation memory wait instead), the input has ended (`0x200`); then where each system's input comes from.

**Resolved**: The paragraph leads with what the console is for, and a table gives what a read returns in the three cases, with where each system's input comes from after it.

### 3.3 SYSTEM.md §1: the screen's layout is not stated

"Screen", line 42, says where the screen is, the word's format, and the `-2004` option, but not that it is 25 rows of 80 words, row by row, 2000 words in all. The memory map says 80×25, and README.md says "80 words per row" in passing in the window example. A program that writes row 2 has to guess. The paragraph also opens with the 2004 history before saying what the screen is. **Fix:** first "The screen is 25 rows of 80 words at `0xFFFF0000`, row by row, so row r, column c is the word at `0xFFFF0000` + 80·r + c", then the word's format, then the 2004 option.

**Resolved**: The paragraph opens with the layout, 25 rows of 80 words, row by row, with the formula for a word's address, and the 2004 history follows.

### 3.4 SYSTEM.md §1 holds seven topics under one heading

§1 is "Console, screen, and read counter", and its paragraphs are Screen, Console, Window, Cursor, Keyboard, Pacing, and Read counter. The contents list shows none of the last five, and the table of the keys' bytes is what a program under the window needs most. **Fix:** sub-headings §1.1 to §1.7 in that order, and the contents list. The anchor of §1, which README.md and the release notes link, stays.

### 3.5 SYSTEM.md: "a data read" in every device table, with no word on why

The tables of §2 to §4 head a column "A data read returns". The term is ISA.md §8.2's, and the reason for it is ISA.md §8.3: an instruction fetch from the I/O range reads 0 and reaches no device. SYSTEM.md's introduction says that "ISA §8.2" refers to ISA.md, and nothing more; the first word on data reads is the Read counter paragraph at the end of §1. The memory map's lead, "The I/O range, and what the systems put in it", also heads a table whose first row, the screen, is outside the I/O range. **Fix:** one sentence in the introduction: "A data read is an operand read. An instruction fetch from this range reads 0 and reaches no device (ISA.md §8.3), so the tables say what a data read returns." And "The I/O range, the screen, and what the systems put in them."

**Resolved**: The introduction says what a data read is and why the tables say so, and the memory map's lead names the screen.

### 3.6 TOOLCHAIN.md: "a monitor in ROM" and `_mon` are not explained, and the `--monitor` example lacks `--monitor`

[TOOLCHAIN.md](../TOOLCHAIN.md), lines 28–31 of the build diagram: "or their `_mon` versions for a program that a monitor in ROM runs"; lines 52–54: "With `--monitor` it picks the `_mon` start-up file:" followed by `translator/nicebuild.py -o prog.bin prog.c`, without `--monitor`. Nothing in the file says what a monitor is; ABI.md's "Programs under a monitor" does, 150 lines into another file. The same gap is in translator/README.md (line 69) and emulator/README.md (line 205), which point at ABI.md. **Fix:** one sentence at the first use: "A monitor is a program in a ROM at address 0 that loads a program at `0x8000` and calls it, as NiceMonMEGA65's will; `--monitor` builds a program for one (ABI.md, Programs under a monitor)." And the example as it is, followed by "With `--monitor` it picks the `_mon` start-up file instead."

**Resolved**: TOOLCHAIN.md says what a monitor is, with the pointer to ABI.md, right after the `nicebuild.py` example, which stands without `--monitor`.

### 3.7 TOOLCHAIN.md: the labels of the runtime

"How the tools use each other" names `_main`, `___wasm_start`, `___wasm_trap_vector`, and `__mul` with no word on the underscores. ABI.md has the rule. **Fix:** one clause at `_main`: "(a C name `f` is the label `_f`, ABI.md)".

**Resolved**: The rule for the underscore is given at `_main`.

## 4. The slides

### 4.1 The `--irq` example says the vector but not the step

`nice_intro.tex` line 798: "`niceemu --irq 5:5 --irq 12:5 irq.bin` raises two IRQs with vector 5, and prints `**`." The reader cannot tell which number is the step, and the slides have not said what a step is. **Fix:** "raises an IRQ with vector 5 before steps 5 and 12 (`--irq STEP:VECTOR`; a step is one instruction), and prints `**`."

### 4.2 "Out of context" on the last slide

Line 914: "The pipelined core meets a 10 ns clock out of context." That is Vivado's term, and the first slide promises to assume "nothing more" than a register and a memory address. **Fix:** "runs at 100 MHz when synthesized on its own, and in the NiceMonMEGA65 system."

### 4.3 The window has no slide, though its example program is theirs

`doc/intro/examples/keys.nasm` lives in the slides' examples directory, `make -C doc/intro test` runs it, and README.md's second worked example is built on it, but no slide mentions the window, the screen, or the keys. The "Input/Output" slide (line 116) knows the console alone, and "Soft- and hardware" (803) lists the emulator without it. For a beginner, the window is the most visible feature of `V1.2`. **Fix:** one slide after "Watching a program run": `make -C emulator window`, `niceemu --window keys.bin`, the screen at `0xFFFF0000` with the character in bits 7..0 and the colors above, and that a console read returns 0 while no key waits. If the slides are to stay with the ISA, a line on "Soft- and hardware" and a pointer to the README's example.

### 4.4 Smaller

- "Some unusual operations" (line 282): "There is no multiply or divide. The runtime library has routines for that, such as `__mul`." The math unit of SYSTEM.md §2, which the emulator and both cores have, goes unmentioned. One clause.
- "Using the assembler and the emulator" (822) runs `emulator/zig-out/bin/niceemu` without saying that it must be built first (`make -C emulator build`, README.md).

## 5. The emulator and the assembler

### 5.1 emulator/README.md: the test narrative stands between the title and Usage

"Build and test" (lines 10–67) describes `make test` in detail before "Usage" (69). Lines 37–47 are one sentence of eleven lines on `test/link.py`, which uses "the debug link", "bit 5", "the stop register", and "the breakpoints" with DEBUG.md's section numbers alone, 250 lines before the Debug link section (302). "Probe" (29) and "cputest" (52) are used before they are explained (61). **Fix:** keep the three build lines at the top, move the test narrative to a "Tests" section at the end, and define "probe" at its first use.

### 5.2 emulator/README.md: Usage has no recipe and no link to the README's worked examples

Usage (69) opens with the synopsis, the meaning of a step, and a run of `count.bin`. Nothing shows assemble, run, give input, trace, and open the window in sequence, and the file never links README.md's two worked examples, which do exactly that. **Fix:** a four-line recipe before the option table, or one sentence that links the worked examples.

### 5.3 emulator/README.md: the exit statuses are one paragraph with three other remarks

Lines 124–132: the statuses 0, 2, 3, 4, 1, and 141 in one sentence, with the remarks on stderr, `--`, and the empty argument between them; the status after a signal with `--link`, 0, is at line 316. **Fix:** a table of the statuses, and the remarks after it.

**Resolved**: A table of the six statuses, the signal with `--link` among them, and the three remarks after it.

### 5.4 emulator/README.md: smaller

- The `--symbols` cell of the option table (98) is 115 words: the file's format, the trap handler, and the tie-break. One sentence in the cell, and the rest in a "Symbols file" paragraph under the table.
- The memory map's prose (223–291) is one dense paragraph per device. Sub-headings (Console, Math unit, Counters, Timer) would let a reader find the timer.
- "The pace" (150–156) is never defined. "The rate, in steps per second" at the first use.

**Resolved**: in part: the `--symbols` cell is one sentence and a "Symbols file" paragraph under the table has the format and the rules, and the Window section names the rate instead of "the pace". The sub-headings of the memory map's prose go with the restructuring of the file (§5.1).

### 5.5 assembler/README.md: the tests come first, and the details are unordered

"Test" (line 9) is the first section, before Usage (24), and "Tests" (176) at the end is a second one. "Details beyond ISA.md" (135–174) is 17 bullets in no order, with the separators and the comments beside `.BLK 0xFFFFFFFF` and the byte order mark. The disassembler section's sentence at 113–117 ("is only a comment: on a line of its own at its address if a word is there, and in the comment of a constant, which stays a number") takes several readings. **Fix:** Usage first and one Tests section at the end; the details grouped into syntax, directives, and edge cases; the sentence split in two, with an example line of output.

## 6. The translator and the runtime

### 6.1 WASM.md states a rule the translator does not follow

[WASM.md](../../translator/WASM.md), line 58: "The translator rejects a function type whose results do not all fit in R1–R4." `nicewasm.py` rejects any function type with more than one result, at an import (line 604), a defined function (3034), and `call_indirect` (3883): "more than one result is not supported yet". translator/README.md says so under "Not supported yet" (334). A reader of the mapping expects up to four results to work. **Fix:** "The translator rejects a function type with more than one result; a block type may have several (translator README, Not supported yet)." This is the one finding in a specification document.

**Resolved**: WASM.md says that a function type with more than one result is rejected, and that a block type may have several, as the code and the translator README have it.

### 6.2 translator/README.md: no quick start, and the options come as prose

The file opens with the synopsis of `nicewasm.py` (lines 15–37) and then one paragraph of about forty lines on the options of `nicebuild.py` (43–86). The two-line recipe a newcomer wants, `nicebuild.py -o prog.bin prog.c` and then `niceemu prog.bin`, is in TOOLCHAIN.md and README.md and not here; how a program prints, reads, and exits is one sentence at line 123 and the runtime README. The manual clang, Zig, and Rust recipes (88–178) come next, and only line 49 says, obliquely, that `nicebuild.py` runs them ("The defaults are the options of the recipes below"). Nothing in this README or the runtime's says that C built this way has 8-bit `char` and wasm's byte memory, while ABI.md's one-word `char` is for assembly and a future native compiler; TOOLCHAIN.md says it in one clause. **Fix:** a "Quick start" after the introduction: build and run a C program with `printf`, the Zig and Rust variants, and what you get (the console for `printf` and `getchar`, exit by returning from `main` or calling `exit`, status 2 on a trap, 8-bit `char`); the options as a table; the recipes headed "What `nicebuild.py` runs", for reference.

### 6.3 translator/README.md is two documents

Usage, Target, Supported features, and Library modules (lines 1–366) are for users. "How functions are translated" and "Register allocation" (367–822, 455 lines) are for whoever changes `nicewasm.py`, and "Test" (823) comes after them. The "Supported features" list also carries design notes, such as how a multiplication by a constant is split (251–266) and the internal labels of the memory instructions (272–279). **Fix:** move the two internal sections to `translator/DESIGN.md`, or after Test under a heading that says whom they are for, with a contents list at the top; move the design notes out of the feature list.

### 6.4 runtime/README.md: the order, and two dense paragraphs

The sections are Files (7), Routines (46), Device routines (113), Floating point (158), C library (193), Zig and Rust (289), and Test (327). A C user's section is the fifth, and the Routines tables list `__mul64` and `__clz` before the reader knows who calls them. "The trap report" (111) is one paragraph of 1274 characters: what it prints, who installs it, the join order, the registers it uses, and the symbols options. The bullet on what the C library lacks (232) is 96 words. **Fix:** a "which section" paragraph at the top (C: C library; Zig or Rust: Zig and Rust; assembly: Files, Routines, Device routines); the trap report as three bullets, the first "`nicebuild.py` installs it unless given `--no-trap-report`"; the C library's limits as a list.

### 6.5 runtime/README.md and ABI.md disagree on whether NiceMonMEGA65's monitor exists

runtime/README.md, line 33: "a monitor in ROM, such as the one of NiceMonMEGA65, loads at `0x8000`". [ABI.md](../../runtime/ABI.md), line 146: "as the monitor of NiceMonMEGA65 will (MJoergen/NiceMonMEGA65#24)". The board's README says the monitor is not written yet. **Fix:** "will" in runtime/README.md too.

**Resolved**: runtime/README.md says "will have", as ABI.md does.

### 6.6 Smaller

- ABI.md's register table (31–41) lists R14 twice, "the flags X, C, Z, N, and V: No" and "I, E, and VBASE: Yes". It is right, and reads as a typo. One row: "R14 | SR | The flags no; I, E, and VBASE yes".
- The order of the joined files is stated three ways: TOOLCHAIN.md's diagram, runtime/README.md (25–28), and ABI.md. They agree. One numbered list in runtime/README.md, and links to it from the other two.
- WASM.md is the contract for a translator, and says so only by its tone; a user who follows a README's link finds normative rules. One sentence at the top: "This is the mapping that `nicewasm` implements. To build programs, read the translator README."

**Resolved**: in part: ABI.md's table has one row for R14, and WASM.md says at the top what it is and where a user should read instead (§6.1). The join order stated once is part of the restructuring of the runtime README (§6.4).

## 7. The benchmark

### 7.1 bench/README.md: results pinned to three commits, and the model's rules in one sentence

The tables of [bench/README.md](../../bench/README.md) name commits 3064119 (line 136), 1a41b0c (149), and 98d2bed (160, 202, 232, 387, 475). A reader cannot tell which figures are current without the dates. "The cycle estimate" (267) states the model's rules in one sentence of about ten lines (275–285), which uses FETCH, DECODE, SEQUENCER, PREPARE, WRITE, "skid register", and "micro-operation" with MICROARCH.md linked only at line 21. `make compare` prints, by line 23, "the estimate beside the pipelined core's cycles" and, by line 372, "the percentages of the table's last column, not the cycles". **Fix:** one current table per program, with the commit named once and the older figures in HISTORY.md; the rules as a list, with a pointer to MICROARCH.md's stages at the first stage name; the same sentence on what `make compare` prints in both places.

### 7.2 Dhrystone: 1757 and the Arm figure

Line 457: "10⁶ / (1757 × cycles per run)" with no word that 1757 Dhrystones per second is the VAX 11/780, which defines 1 DMIPS; line 484: "Arm gives 0.87 DMIPS/MHz for the Cortex-M0" without a source. **Fix:** one clause each.

**Resolved**: The formula says what 1757 is, and the Arm figure names its source.

## 8. The cores and the debug link

### 8.1 hdl/README.md: 750 lines of tests and proofs before the cores

The order of [hdl/README.md](../../hdl/README.md) is Folder contents (30), Running the tests (44–422), The formal checks (423–797), The multi-cycle core (798), The pipelined core (982) with "Integrating the core" inside it (1089–1112), then the data bus decoder, the debug link, and the devices. An integrator reads about 750 lines on tests and proofs before the core and its interface. "Running the tests" mixes the quick start, `make lint`, `make timing` with its slack table (91–155), and a catalog of every testbench and test program (157–421), in which the `tb_debug_link` paragraph (189–218) is one sentence of about 25 clauses. "The formal checks" has no summary of its jobs. **Fix:** Folder contents; a short "Running the tests" with a table of the targets and their costs; Integrating the core, with the table of §8.2; the cores; the devices; the debug link; then "What the tests check" and "The formal checks", the latter with a table of the jobs (unit, what it proves, solver, time) before the paragraphs.

### 8.2 hdl/README.md: no table of the core's ports and generics, and the clock is not named

The ports are named piecemeal through the file (`dbus_ack_i`, `retire_o`, `stats_o`, `pause_i`, `paused_o`, `halted_o`, `brk_addr_i`, `nmi_valid_i`, and the rest); `clk_i` is not in the file, and `rst_i` appears only in the timing text (106) and the link (702). The generics `G_FORMAL` and `G_BREAKS` are named in passing, `G_FORMAL` at 478 before its explanation at 491, and `prove`, `cover`, and `bmc` before any word on what a task is. An integrator opens `src/pipeline.vhd` for the entity. **Fix:** under Integrating the core, a table of the ports (the clock and the synchronous reset, the two buses with their cyc, stb, stall, and ack, the interrupt handshake, pause and halt, the breakpoints, retire and stats) and the two generics, the same for both cores; and four lines at the top of the formal section (a job's tasks are `prove`, `cover`, and `bmc`; `G_FORMAL` turns on a unit's own assertions).

### 8.3 hdl/README.md: terms before their definition, and two stale sentences

- The stage names DBUS, PREPARE, WRITE, and DECODE appear in the timing text (95–150) and the stage table is at 987; `wb_dmux` at 176 and its section at 1113; "side client" and "side port" from 212, defined at 1160; "the top-level `make slow`" (57, 385, 407) and "the stamp" (118) with only a link to RELEASE.md.
- Line 299: "`test/latecount.nasm` to `test/shiftjump.nasm` in the table above". The table is in `hdl/test/README.md`.
- Line 849: "Until 2026-10-24 the pipelined core's `halted_o` waited only for its last request, not for the ACKs (doc/HISTORY.md)". History in a document that says what is true now.
- Line 1005: a benchmark table "at commit 98d2bed" in the middle of the pipelined core's description, and dated results at 120, 382, and 399.
- `hdl/test/README.md` has no rows for `linkecho.nasm` and `link_init.bin`, which its `tb_link` row names.

**Fix:** the stage table, or a "Terms" paragraph, before the tests; "listed in test/README.md"; drop the history sentence and keep the pointer; the benchmark table in bench/README.md, or named by its release; the two rows.

**Resolved**: A "Terms" paragraph before the contents list names the stages, `wb_dmux`, the side port, `make slow`, and the stamp; the dangling "table above" points at test/README.md; the history sentence is a pointer to HISTORY.md; the benchmark table is a sentence and a pointer to bench/README.md; and test/README.md has the two rows.

### 8.4 DEBUG.md §7 holds three topics, and the file never says how to try the link

[DEBUG.md](../DEBUG.md) §7, "Transports" (410–549), has the UART and TCP transports, then the emulator's differences in about 18 bullets, then the rules for a board, from "A board that carries the link has to do more than follow this file" (513), with no heading of their own. A newcomer learns how to try the link only there, from `--link`; the introduction says "one host tool works with either" and names none. The R0 to R15 cell of the register table (228) is one line of about 150 words with five states. "ISA §" is used three times and declared nowhere (the notation sentence at 19–20 declares "SYSTEM.md §1" alone), and "a system of version 4" (294) comes before §9 explains the versions. **Fix:** §7 for the transports, §8 "The emulator", §9 "A board that carries the link", then the example and the versions, with `make -C doc test` for the references from hdl/README.md and the testbenches; three lines in the introduction on how to try it, with `niceemu --link` and the example; the R0 to R15 cell as a list below the table; "ISA §" in the notation sentence; the version asides left to §9.

## 9. What is correct

- **README.md.** The opening paragraph says what NICE is in four lines. The feature list of the emulator, the build instructions with the one Zig version, the two worked examples with their traces explained line by line, the Contents table, and the License paragraph are what a first-time reader needs, in that order.
- **ISA.md.** A contents list, a forward reference at nearly every term, the execution order of §5 that every later rule points at, the flags in one table, the worked example, and Appendix B. Nothing to reorganize.
- **SYSTEM.md.** The memory map first, then one section per device with a table of its words, the timer example, and §5 on what a board may do differently. The math unit's and the counters' rules are precise.
- **TOOLCHAIN.md.** The tool table and the build diagram are the best overview in the set. "How the tools use each other" and "Host tools" answer what a fresh machine needs.
- **The slides.** Short, one idea per slide, the encodings checked, the examples run by `make test`, the "Things to remember" slide. The order from registers through addressing modes to interrupts is right for a beginner.
- **emulator/README.md.** The option table, the memory map table with word counts, the trace format with an example, and the plain statements about the link (no authentication, SSH forwarding).
- **assembler/README.md.** The short Usage with its exit statuses, the disassembler's rules with a `.DAT` example, the column layout, and the editor hint.
- **translator/README.md and WASM.md.** The reasons given for each clang flag, the memory-size discussion, the Target section, and the error formats. WASM.md's tables of values and trap codes, and its worked example.
- **runtime/README.md and ABI.md.** The Files table, the Routines tables with the registers each changes, the C library's header table and `printf` and `scanf` lists, and ABI.md's argument rules and worked example.
- **bench/README.md.** The phase table with what each exercises, the instruction-ratio table with a reason per row, and "Checking the results".
- **hdl/README.md and the folder READMEs.** The Folder contents table, the device sections with their address ranges and bus widths, the stage table, the timing paragraph with its budget and slack table, and the four folder READMEs, each one accurate table.
- **DEBUG.md.** §2 and §3, the packet format and the request table; the hex-dump examples of §8; the error and notice tables; and §9's compatibility rules.
- **CONTRIBUTING.md and release/README.md.** The rules as short bold-headed paragraphs that agree with CLAUDE.md, and the command table that maps each command to a step of RELEASE.md.
