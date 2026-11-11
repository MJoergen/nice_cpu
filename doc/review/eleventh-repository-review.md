# Eleventh review of the repository, at commit fdd337b

Reviewed on 2026-11-11: the 29 commits between `V2.0` and the head of `dev-V2.1`, commit fdd337b ("doc: V2.1 notes for #149 and #156"), before the release `V2.1`. They add the pseudo-instruction `JMPR` (#154), and close the loops of the runtime, the benchmarks, and the translator's output with it; make the labels of short loops anonymous in every `.nasm` file and in the translator's output; give the console a receive interrupt, `CONSOLE_IRQ` at `0xFFFFFF02`, in the emulator and in `hdl/src/console_irq.vhd`, with the rule of ISA.md §7.1 that requests merge per source, and `irq_merge.vhd` (#153); let a host raise an NMI over the debug link, which is version 8 (#131); add CoreMark (#143) and `make timing-spread` (#151); and bring SYSTEM.md §8 and §10 up to date with the board (#152, #155, #158). The tenth review looked at the code before `V1.9`. This one looks at the documents: what they leave out that the code or the board does, and what they and the comments of the code still say that is no longer true.

**How it was checked.** I read the whole diff since `V2.0`: the documents, the code, and the `.nasm` files. For each change I looked for the other places that state the same fact: every README, the documents of `doc/`, the header comments of the VHDL units, the docstrings and the usage texts of the tools, the slides, CLAUDE.md, and CONTRIBUTING.md. I checked every statement about NiceMonMEGA65 against its checkout, four commits after its `V2.0`, and the state of every issue that the documents cite, here and there. One script compared the tracked files of each directory with the README beside it. Another looked in every document and comment for the 110 labels that became anonymous. I checked link version 8 in DEBUG.md against the emulator, `debug_link.vhd`, the tests, and the debugger; the figures of CoreMark on the emulator; the "ten loops" of the notes; and the words of `make -C bench words`. On the unchanged tree I ran `make all`. Its tests print 1301 lines of `PASS`, and one test fails (§1.1), so I ran what the failure skipped by hand: `test/udp.py`, `tap.py`, and `errors.py` of the emulator, and `make typecheck lint pdfcheck`, which all pass. `make -C doc test` and `release.py figures` pass. CI passed every job on fdd337b but `formal`, which was still running when this was written.

## Summary

**One test fails on this machine, and `release.py check` cannot pass here until it is fixed** (§1.1). `test_nmi` of `emulator/test/link.py` closes its connection and connects again at once, and the emulator closes the new host when it sees both in one poll. The test failed in `make all` and in all 13 runs by hand here, and passes on CI. It is a race in the test, on a rule of the emulator that DEBUG.md §7 does not state.

**The documents of the new features are right.** ISA.md §7.1 and §10.1, SYSTEM.md §1.9 and §4, DEBUG.md §6 and §9, the READMEs of the assembler, the emulator, the debugger, the translator, and the benchmarks, and the `V2.1` notes say what the code does, in every case I checked (§4). No document or comment names a label that became anonymous.

**The stale statements are mostly about the board, and older than this release.** SYSTEM.md §8 still says that NiceMonMEGA65 plans four things it has had since its `V1.5`, `V1.7`, `V1.7.2`, and `V2.0` (§2.1). Three documents say that its monitor "will" load programs at `0x8000` (§2.2). The table of board tags in RELEASE_NOTES.md says "none yet" for eight releases, of which seven have a board tag (§1.3). HISTORY.md points at #131 for the button and the watchdog, which moved to #157 (§2.3). In `hdl/`, one bullet of the README was cut in two by another (§2.4), and the timer's text and comment still read as if a core's `ready` may go to any number of devices (§2.5).

**The gaps are small.** `hdl/test/README.md` leaves out three files (§3.1), the HDL README's list of the synthesis check leaves out the two new units (§3.2), and four places that list what a tool or a device has leave out what `V2.1` added (§3.3 to §3.6). Each fix is a sentence or a row.

**Three release steps are still to do** (§1.2 to §1.4): the version in `emulator/build.zig.zon`, the row for `V2.1` in the table, and the date of the notes.

Nothing is fixed yet, and no issue is filed. The numbers below are for the commits.

## 1. The release

### 1.1 `emulator/test/link.py` fails on this machine

    FAIL b of the new host: got b'', expected b'\xffb08#CA'
    FAIL none after b: got b'', expected b'\xffrFFFFFFD7000100000000#D2\xffrFFFFFFF0000100000018#D6'
    FAIL link (2 checks)

`test_nmi` (cdec4fb) ends with a new host, to check that a `b` leaves no NMI request. At line 1490 it calls `e.sock.close()` and then `e.connect()` with nothing between. `Link.service` (`emulator/src/link.zig:260`) calls `accept()` before it reads the old connection, and `accept()` closes the new one while `conn != null and !conn_eof`. So when one poll sees both the end of the old host and the new host, the new host is closed with nothing sent. That is the rule of DEBUG.md §7 for a second host, applied to a host that has already left.

It is a race of some 100 µs. In a loop of 20 on this machine, a host that connected right after the close got its `b` 6 times with the processor held, and once with it paused, as in the test. With 100 µs between the close and the connect it got it 20 times of 20. The test failed in `make all` and in all 13 runs by hand after it, 6 of them while the machine was loaded and 7 while it was quiet. It passed on CI for 0cb5422 and fdd337b. The other two full closes of the file sleep 0.3 s first (lines 1075 and 1322), and the rest half-close and wait.

**Fix:** `time.sleep(0.3)` before the connect at line 1491, as in the other two, so that `make test` and `release.py check` pass on any machine. The emulator's side is a question of its own, for an issue: `accept()` could look for the end of the old connection before it refuses the new one, so that a host that has left never keeps the next one out. Until then, one sentence in DEBUG.md §7 would say that a host which connects in the instant after another left may be closed, and connects again.

**Resolved**: The test sleeps 0.3 s before its new host, and passed in 5 runs of 5 here. DEBUG.md §7 says that a host which connects in the instant after another closed may be closed, and connects again. The emulator's side is #159.

### 1.2 `emulator/build.zig.zon` still says `2.0.0`

RELEASE.md step 2.9 asks for the new tag's version there before `release.py check`. **Fix:** `2.1.0`, and the line "The version is 2.1.0." under the emulator's heading of the notes, which every section since `V1.7` has.

### 1.3 The table of board tags in RELEASE_NOTES.md

Lines 17 to 24 say "none yet" for `V2.0` down to `V1.3`. NiceMonMEGA65 has tagged all of them but `V1.8`, and every tag is on its origin. The submodule of each tag gives:

| nice_cpu | NiceMonMEGA65 |
|---|---|
| `V2.1` | none yet |
| `V2.0` | `V2.0` |
| `V1.9` | `V1.9`, `V1.9.1` |
| `V1.8` | none |
| `V1.7` | `V1.7`, `V1.7.1`, `V1.7.2` |
| `V1.6` | `V1.6` |
| `V1.5` | `V1.5` |
| `V1.4` | `V1.4` |
| `V1.3` | `V1.3` |

The row for `V2.1` is the one that RELEASE.md step 2.8 asks for. RELEASE.md step 8.5 asks for the board's tag in its row after each board release, and that step was left out seven times. **Fix:** the rows above. `V1.8` gets "none", as the board went from `V1.7.2` to `V1.9`.

### 1.4 The `V2.1` section of the notes

- Its heading says 2026-11-10, and three of its commits are of 2026-11-11. The date is set at the tag.
- It has no line for #150. `release.py check` of `V2.0` recorded an error for the timing in its stamp though the run met, as `make timing` had moved its directory in fa8b2fa, which is in `V2.0`. b014356 fixes it. The sections of `RC06` to `V1.2` have a **Release** heading for such changes. **Fix:** that heading, with one line.

### 1.5 CoreMark on the cores is in no gate

`make -C bench core-coremark` checks the CRCs of one iteration on a core, in 97 seconds on the pipelined core in nvc. Nothing runs it: not `make slow`, which runs the benchmark, `hand`, Dhrystone, and the strides, not `release.py check`, and not CI. So the cycles that bench/README.md and the notes quote, 7898812 and 1065384, are from a run by hand on 5022cfe, and a change that breaks CoreMark on a core alone would not be found. This is not a fault of the documents, which say what runs where. **Fix, if wanted:** an issue for a `slow/%/coremark` beside `slow/%/dhry`, with RELEASE.md §5 naming it.

### 1.6 The rest of the checklist

- The milestone `V2.1` has 11 closed issues and none open.
- A row of DEBUG.md §9 for version 8 is there.
- No `make -C hdl sweep` is needed. a4da0a9 changes the contract of the IRQ port in comments and in the formal checks, with no line of RTL, as its message says, and I checked the diff of `hdl/src` for it. `console_irq.vhd` and `irq_merge.vhd` are new units outside the cores, and the link's NMI request is in `debug_link.vhd`. No file under `hdl/src/pipe_*` changes but for a comment, so no `make timing` before and after is owed either.
- CONTRIBUTING.md has the two rules that CLAUDE.md gained, the anonymous labels and `timing-spread`.
- CI's `formal` job on fdd337b was running when this was written. Cut no tag before it passes (RELEASE.md §6).

## 2. Stale statements

### 2.1 SYSTEM.md §8 says the board plans what it has

Four bullets of §8 describe NiceMonMEGA65 as it was. The commits of this release brought the bullets **Clock**, **Byte windows**, **NMI**, and **Receive interrupt** up to date, and these four were left:

- **Reserved words** (line 513): "NiceMonMEGA65 uses ... `0xFFFFFFE0`–`0xFFFFFFFF` for the debug registers of the link. The link's registers of version 7 start at `0xFFFFFFD0`." The board serves version 7 since its `V2.0`, with its registers at `0xFFFFFFD0`–`0xFFFFFFFF` (its `doc/DEBUG_LINK.md`). The **Debug link** bullet of the same section already says `0xFFFFFFD0`.
- **SD card slots** (line 519): "NiceMonMEGA65 plans to number them 0 and 1 (MJoergen/NiceMonMEGA65#55)." That issue closed on 2026-11-04. Slot 0 is the microSD slot at the back, and slot 1 the full-size slot underneath (its README).
- **Network station** (line 520): "NiceMonMEGA65 has its station at `0xFFFFFF98`–`0xFFFFFF9D` today, with the same registers in another order and no status word, until it follows §6." It follows §6 since its `V1.7`, at `0xFFFFFFB0` (MJoergen/NiceMonMEGA65#78).
- **Ethernet frames** (line 521): "NiceMonMEGA65 plans the port (#121), with the network stack in its ROM." It has the port at `0xFFFFFFC0`–`0xFFFFFFCF` since its `V1.7.2` (MJoergen/NiceMonMEGA65#82).

**Fix:** say what the board has in each, as the other bullets do. The **Reserved words** bullet should also say whether `0xFFFFFF90`–`0xFFFFFF9F` are still "its board's devices" now that the station has left `0xFFFFFF98`; the **Aliasing** bullet names the word at `0xFFFFFF9E`, which is there.

What §8 says the board does not have is still so: the link's NMI request (MJoergen/NiceMonMEGA65#106), the receive interrupt (#104), and the clock set from the RTC (#105) are open.

### 2.2 Three documents say what the board's monitor "will" do

- `doc/TOOLCHAIN.md:56`: "loads a program at `0x8000` and calls it, as NiceMonMEGA65's will."
- `runtime/README.md:61`: "a monitor in ROM, such as the one that NiceMonMEGA65 will have".
- `runtime/ABI.md:151`: "as the monitor of NiceMonMEGA65 will (MJoergen/NiceMonMEGA65#24)".

That issue closed on 2026-11-02, and the board's monitor loads programs at `0x8000`. **Fix:** "does", "has", and "does".

### 2.3 HISTORY.md says the button and the watchdog stay open in #131

`doc/HISTORY.md:719`: "The button and the watchdog stay open in #131." #131 closed on 2026-11-11, and the two moved to #157, which is open with no milestone. **Fix:** "are #157".

### 2.4 hdl/README.md: the bullet of `todbus` cuts the bullet of `instret` in two

Lines 1094 to 1103:

    - `test/instret.nasm`, also on a memory that stalls in 30% of the cycles.
    - `test/todbus.nasm` sets and reads the clock of the time of day through
      ...
      30% of the cycles.
      It reads the instruction counter right after a store to RAM, which the
      data bus decoder makes the read wait for, after a read of RAM, as the
      source of a store, and twice in one instruction.

The last sentence is `instret.nasm`'s (`hdl/test/README.md:28` says the same of it). e71acae put the new bullet between its two sentences, in `V2.0`. **Fix:** move the sentence back under `instret.nasm`.

### 2.5 The timer: "`ready` may go to more than one device"

- `hdl/src/timer.vhd:16`: "While no request is raised, irq_ready_i has no effect, so the core's ready may go to more than one device."
- `hdl/README.md:654`: "Its request goes to the core's IRQ port ... While no request is raised, `ready` has no effect, so `ready` may go to more than one device."

Both were written when every IRQ merged with any pending one. Now requests merge per source (ISA.md §7.1). A system that gave the core's `ready` to the timer and to `console_irq` would take both requests with one entry, and lose the console's. `tb_core` shares a `ready` only between the timer and `--irq`, which are one source, and gives the two sources theirs through `irq_merge`. The sentences are true of the timer alone, and read as leave to do what the next section of the README forbids. **Fix:** "so its `ready` may be shared with another device of its source, as `tb_core` shares it with `--irq`; two sources go through `irq_merge`", and "goes to the core's IRQ port, through `irq_merge` where the system has the console's too".

### 2.6 The lists of the devices in README.md and doc/README.md

- `doc/README.md:9` says of SYSTEM.md: "The devices that the emulator maps into the I/O range: console, math unit, performance counters, and timer." SYSTEM.md has had the SD card since `V1.5`, the network station and the Ethernet frames since `V1.7`, and the clock since `V2.0`.
- `README.md:50` lists the devices that niceemu implements, down to "the port for Ethernet frames", without the clock of SYSTEM.md §10.

**Fix:** the list of CLAUDE.md in the first, and "and the clock of the time of day" in the second.

### 2.7 hdl/README.md: "the reserved words of `0xFFFFFFD2`–`0xFFFFFFDF`"

Line 542: "The reserved words of `0xFFFFFFD2`–`0xFFFFFFDF` read 0 and take no write." The range now holds the registers of the watchpoints at `0xFFFFFFD4`–`0xFFFFFFD6` and `0xFFFFFFD8`–`0xFFFFFFDB`, and the NMI request at `0xFFFFFFD7`, which the next paragraph describes. The reserved words are `0xFFFFFFD2`, `0xFFFFFFD3`, and `0xFFFFFFDC`–`0xFFFFFFDF` (DEBUG.md §6). **Fix:** name those.

## 3. Gaps

### 3.1 hdl/test/README.md leaves out three files

`tb_tod.vhd`, `todbus.nasm` (both from `V2.0`), and `watches.nasm` have no row. Every other tracked file of `hdl/test`, `hdl/src`, `hdl/formal`, and `hdl/sim` is named in the README beside it. The row of `timing_budget.py` says that it compares the reports of `make timing`, and not that `--spread` gives the least, the median, and the most of several runs for `make timing-spread`. **Fix:** three rows and half a sentence.

### 3.2 The list of the synthesis check leaves out the two new units

`hdl/README.md:95` lists what `ghdl --synth` checks, from "both cores" to "the port for Ethernet frames". `SYNTH` in `hdl/Makefile:645` also has `console_irq` and `irq_merge`, as the message of 5022cfe says. The comment above `SYNTH` (line 641) leaves out those two and the fetch statistics. **Fix:** "the console's receive interrupt, the merge of the IRQ sources" in both, and "the fetch statistics" in the comment.

### 3.3 hdl/README.md does not say that `conirq` is compared exactly

The README says of `wait` that "its runs are compared exactly, and not by `irq_compare.py`", and why. `hdl/Makefile:186` sets `EXACT_conirq`, `EXACT_conirq_stall`, and `EXACT_conirq_hold` with the reason in a comment: the probe takes each request right after the instruction that sets E, which no core can take later. The README's section on the console's receive interrupt (line 675) names the three runs and not the comparison. It also does not say that the console's requests are not in the log of `G_INTR_LOG`, which the header of `tb_core.vhd` says. **Fix:** two sentences there.

### 3.4 niceemu's usage text has no `0xFFFFFF02`

`emulator/src/main.zig:19` describes the console at `0xFFFFFF00` and gives the range of each device. It names neither the receive interrupt at `0xFFFFFF02` nor the read counter at `0xFFFFFF01`. The table of emulator/README.md has both. **Fix, if wanted:** half a sentence, or leave the usage text to the options and point at SYSTEM.md.

### 3.5 The debugger's summaries leave out the NMI

`debugger/README.md:6` and the docstring of `nicedbg.py` (line 4) list what the debugger does: load, run, pause, step, breakpoints, watchpoints, registers, memory, and disassembly. The table of commands has `nmi VEC`, and `help` lists it. **Fix:** "raises an NMI" in both lists.

### 3.6 HISTORY.md has no entry for the merge per source

"Merged interrupt requests" (line 153) ends on 2026-10-22 with the rule that the first vector is kept. Until 73ba521 every IRQ merged with any pending one, and until a4da0a9 the cores asked for a stable IRQ vector. The notes say both under their upgrade notes, and "An NMI from the link" cites a4da0a9 in passing. HISTORY.md is where the other documents send what used to be true. **Fix:** three sentences at the end of that section.

### 3.7 The slides do not have `JMPR`, optional

The "Jumps" slide of `doc/intro/nice_intro.tex` (line 553) shows `MOVE PC, LOOP`, the relative `ADD PC, PC, 10`, and that the assembler accepts `JMP`. `JMPR` is the pseudo-instruction for its second line. The slides are right without it, and a beginner needs one jump. **Fix, if wanted:** "and `JMPR LOOP` for the relative jump" on that slide, and `make pdf`.

## 4. What was checked, and found right

These are recorded so that the next review need not repeat them.

- **Link version 8.** DEBUG.md §6 and §9, `emulator/src/link.zig`, `debug_link.vhd`, `tb_debug_link`, `tb_link`, `nicelink.py`, and `nicedbg.py` agree on the register at `0xFFFFFFD7`, bit 8, the read back until the request is taken, the write that raises nothing while the processor is held or halted, the drop by a hold, and bit 9 of the control register. The emulator README, the HDL README, and SYSTEM.md §8 say the same.
- **The console's receive interrupt.** SYSTEM.md §1.9 and §4, the emulator README's table and its section on the timer, `console_irq.vhd`, `irq_merge.vhd`, and MICROARCH.md §6 and §8 agree on the three edges, the order of the two sources, and that a request keeps its vector. `hdl/ASSUMPTIONS.md` has no rule of a stable IRQ vector left.
- **`JMPR`.** ISA.md §10.1, §9.2, and Appendix B, the assembler's README, `nicedis`, `nice.vim`, DESIGN.md, and `decisions.md` agree. The notes' "ten loops" are 3 in `lib.nasm`, 6 in `muldiv_soft.nasm`, and 1 in `trapmsg.nasm`.
- **Anonymous labels.** No document, comment, test script, or expected file names one of the 110 labels that went away. The `LOOP` of `debugger/README.md:89` is that of `test/break.nasm`, which keeps its name for the test. NiceMonMEGA65 uses none of the labels that `demo.nasm` and the runtime lost.
- **The figures.** CoreMark on the emulator gives 675095 cycles per iteration and 1.481 CoreMark/MHz, and 675422 and 1.480 with the validation seeds, as bench/README.md says. `make -C bench words` gives 11523, 5903, 30073, 6578, and 23392. `release.py figures` passes.
- **The references.** `make -C doc test` passes: every `FILE.md §n.m` and every link names what exists. `make -C doc/intro pdfcheck` passes.
- **The notes.** Each of #131, #143, #149, #151 to #156, and #158 has its lines, and the upgrade notes name the five things a user must know. What the notes say NiceMonMEGA65 has, the watchpoints and the RAM without the cascade, it has.
- **The board, where §8 is current.** The byte windows, the font, the clock, the size of the RAM with its word at `0xFFFFFF9E`, and the three things it does not have yet are as SYSTEM.md §8 says.
